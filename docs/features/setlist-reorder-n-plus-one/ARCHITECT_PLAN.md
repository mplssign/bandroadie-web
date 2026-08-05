# ARCHITECT_PLAN.md

## Bug Fix: Setlist Reorder N+1 Query

---

## 1. Feature Slug

`bug/setlist-reorder-n-plus-one`

---

## 2. Problem Summary

`SetlistRepository.reorderSetlists()` issues one sequential `UPDATE` query per setlist inside a `for` loop (lines 1004–1010 of `setlist_repository.dart`). For a band with N setlists, reordering requires N sequential network round trips, causing user-facing latency that scales linearly with setlist count (30 setlists = 30 sequential round trips).

This violates §6 Data Integrity of `GUARDRAILS.md`, which requires ordering logic to live in Supabase RPC for atomic server-side execution, not client-side sequential writes.

**Impact:**

- User-facing latency scales linearly with setlist count
- No atomicity guarantee (partial reorder possible if network fails mid-loop)
- Violates established architectural standard (RPC-based ordering)

**Caller:**
`lib/features/setlists/setlists_screen.dart:272` → `_repository.reorderSetlists(...)`

---

## 3. Root Cause

**Confidence Level:** `HIGH` (confirmed via direct code inspection)

**Primary Failure Layer:** Repository pattern implementation

**Why It Fails:**
The `reorderSetlists()` method in `SetlistRepository` (lines 1001–1023) iterates over the ordered list of setlist IDs and issues one `await supabase.from('setlists').update({'position': i + 1}).eq('id', ...).eq('band_id', ...)` call per setlist. Each `await` forces sequential execution, blocking on network round trips.

```dart
// Current implementation (lines 1004-1010)
for (int i = 0; i < setlistIdsInOrder.length; i++) {
  await supabase
      .from('setlists')
      .update({'position': i + 1})
      .eq('id', setlistIdsInOrder[i])
      .eq('band_id', bandId);
}
```

This pattern was flagged in the May 2026 code review and remains unfixed as of 2026-08-04.

**Contrast with Working Solution:**
`reorderSongs()` (lines 1035+) correctly delegates to RPC `reorder_setlist_songs`, which the Dart code expects to handle all updates atomically. When the RPC is unavailable, it falls back to `_reorderSongsFallback()` (lines 1126+), which uses a two-phase approach to avoid unique constraint violations on `setlist_songs(setlist_id, position)`.

---

## 4. Reference Docs Consulted

**Notification Domain:** Not applicable (this is a setlist ordering bug)

**Reviewed Files:**

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md` (§6 Data Integrity)
- `docs/agents/OPERATING_MODEL.md`
- `.github/copilot-instructions.md` (Repository Pattern, Band Isolation)

---

## 5. Existing System Analysis

### Current Data Flow: Setlist Reordering

1. **User Action:** Drag-and-drop reorder in `SetlistsScreen` (UI layer)
2. **State Update:** `SetlistsNotifier.reorderSetlists()` updates local state optimistically
3. **Persistence:** `SetlistsNotifier.persistReorder()` calls `SetlistRepository.reorderSetlists()`
4. **Database Write:** For each setlist ID, issue sequential `UPDATE setlists SET position = ? WHERE id = ? AND band_id = ?`
5. **Revert on Failure:** If any update fails, revert to pre-reorder snapshot

**Observed Behavior:**

- Latency: `O(N)` where N = number of setlists (each awaited sequentially)
- Network round trips: N individual queries
- Atomicity: None (network failure mid-loop leaves partial reorder persisted)
- RLS enforcement: Per-row via client queries (correct but inefficient)

### Existing Song Reorder Pattern (Working Precedent)

`SetlistRepository.reorderSongs()` (lines 1035+):

1. Calls RPC `reorder_setlist_songs(p_setlist_id, p_song_ids)`
2. If RPC unavailable (error codes `PGRST202` or `42883`), falls back to `_reorderSongsFallback()`
3. Fallback uses two-phase update:
   - Phase 1: Move all to temporary high positions (100000+)
   - Phase 2: Set final positions (0-indexed)
   - **Rationale:** Avoids unique constraint violation on `setlist_songs(setlist_id, position)` per migration `20260724143942_fix_setlist_positions_trigger_collision.sql`

**Key Difference:**

- `setlist_songs` table has `UNIQUE(setlist_id, position) DEFERRABLE INITIALLY DEFERRED`
- `setlists` table has **no unique constraint on `(band_id, position)`** (verified against production project `nekwjxvgbveheooyorjo`)
- Therefore, setlist reordering does **not** require the two-phase trick

### Verified Schema Facts (Production)

**`setlists` table constraints (prod project `nekwjxvgbveheooyorjo`):**

- Primary key: `id`
- Foreign key: `band_id → bands(id)`
- Check constraint: `setlist_type = ANY (ARRAY['regular', 'catalog'])`
- **No unique constraint on `(band_id, position)`**

**Implication:**
A direct single-statement `UPDATE ... FROM unnest(...) WITH ORDINALITY` is safe and sufficient.

---

## 6. Proposed Solution

### Minimal Fix (Two Components)

**Component 1: New Supabase RPC (Migration)**
Create `reorder_setlists(p_band_id UUID, p_setlist_ids UUID[])` RPC that:

1. Verifies `auth.uid()` is an active member of `p_band_id`
2. Verifies all `p_setlist_ids` belong to `p_band_id` (prevent cross-band tampering)
3. Updates all positions atomically using `UPDATE ... FROM unnest(...) WITH ORDINALITY`
4. Returns JSON: `{'success': true/false, 'reordered_count': N, 'error': '...'}`

**Pattern to follow:**

- Use `SECURITY DEFINER` + `SET search_path = public` (per Guardrails §4)
- Use `json_build_object()` for return value (matches `move_song_between_setlists`)
- Use `EXCEPTION WHEN OTHERS` block to catch errors (matches existing RPCs)

**Component 2: Update Dart Call Site**
Modify `SetlistRepository.reorderSetlists()` (lines 1001–1023):

1. Replace `for` loop with single `supabase.rpc('reorder_setlists', params: {...})`
2. Parse JSON response (check `success`, `reordered_count`, `error`)
3. **No fallback required** — this RPC is simpler than song reordering (no unique constraint)

**Why No Fallback:**

- Fallback only needed when migration hasn't deployed yet (e.g., dev environment, fresh local DB)
- Song reordering has fallback because RPC was added mid-project (v1.4.x)
- This fix is isolated to one feature branch → migration deploys before merge
- If RPC missing, fail loudly (don't silently degrade to N+1 pattern)

---

## 7. Database Impact

**Migration Required:** `YES`

**New Migration File:**
`supabase/migrations/20260804200000_reorder_setlists_rpc.sql`

**Changes:**

- **New RPC:** `reorder_setlists(p_band_id UUID, p_setlist_ids UUID[])`
  - `SECURITY DEFINER` (bypasses RLS for validation queries)
  - `SET search_path = public` (per Guardrails §4)
  - Returns `JSON` (matches existing RPC pattern)

**RLS Impact:** `NOT AFFECTED`

- RPC uses `SECURITY DEFINER` to validate band membership and ownership
- Actual `UPDATE` executes under service role context, bypassing RLS
- This matches pattern from `move_song_between_setlists`, `bulk_add_songs_to_setlist`, etc.

**Trigger Impact:** `NOT AFFECTED`

- No triggers exist on `setlists` table position changes
- Triggers only exist on `setlist_songs` (song-level reordering)

**Index Impact:** `NOT AFFECTED`

- No new columns added
- Existing indexes on `setlists(band_id)` sufficient for WHERE clause performance

**Rollback Safety:**

- Migration can be rolled back by `DROP FUNCTION reorder_setlists(UUID, UUID[]);`
- No schema changes to tables, constraints, or columns

---

## 8. Flutter Architecture Changes

### State Management

**Affected:** `lib/features/setlists/setlists_controller.dart`

- No changes required — controller already calls `_repository.reorderSetlists()` via `persistReorder()`
- Revert-on-failure logic remains unchanged

### Repository Layer

**Affected:** `lib/features/setlists/setlist_repository.dart`

- **Lines 1001–1023:** Replace sequential `for` loop with single `supabase.rpc()` call
- Preserve existing error handling structure (try/catch, debug prints, rethrow)
- Parse JSON response: `{'success': bool, 'reordered_count': int, 'error': string?}`

**No new dependencies required** — uses existing `supabase` client

### Widget Layer

**Not affected:** `lib/features/setlists/setlists_screen.dart`

- Caller at line 272 remains unchanged — it already calls `_repository.reorderSetlists()`

---

## 9. Files to Create

| File                                                          | Justification                                                                                                                                                                                         |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260804200000_reorder_setlists_rpc.sql` | New migration defining `reorder_setlists()` RPC. Required to implement atomic server-side ordering per Guardrails §6. Timestamp `20260804200000` follows existing naming convention (YYYYMMDDHHMMSS). |
| `docs/features/setlist-reorder-n-plus-one/ENGINEER_REPORT.md` | Standard Engineer deliverable per Operating Model. To be created by Engineer after implementation.                                                                                                    |
| `docs/features/setlist-reorder-n-plus-one/QA_REPORT.md`       | Standard QA deliverable per Operating Model. To be created by QA after validation.                                                                                                                    |

---

## 10. Files to Modify

| File                                            | What Changes                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/setlist_repository.dart` | **Lines 1001–1023:** Replace `reorderSetlists()` method body. Remove `for` loop (lines 1004–1010). Add single `supabase.rpc('reorder_setlists', params: {'p_band_id': bandId, 'p_setlist_ids': setlistIdsInOrder})` call. Parse JSON response and handle errors. Preserve debug prints, argument validation, and empty-list early return. **No other methods modified.** |

---

## 11. Files Off-Limits

| File                                             | Reason                                                          |
| ------------------------------------------------ | --------------------------------------------------------------- |
| `lib/main.dart`                                  | Initialization order must not change (Guardrails §1)            |
| `lib/app/theme/design_tokens.dart`               | No UI changes in this fix                                       |
| `lib/features/setlists/setlists_screen.dart`     | Caller already correct — no widget changes needed               |
| `lib/features/setlists/setlists_controller.dart` | Controller already correct — no state management changes needed |
| `lib/features/setlists/models/*.dart`            | No model changes required                                       |
| `supabase/migrations/*` (existing files)         | Never modify existing migrations — only create new              |
| All other `setlist_repository.dart` methods      | Fix is localized to `reorderSetlists()` only (lines 1001–1023)  |

---

## 12. System Impact Map

| System                                 | Impact                   | Explanation                                                               |
| -------------------------------------- | ------------------------ | ------------------------------------------------------------------------- |
| Gigs                                   | **unaffected**           | Gigs reference setlists via `setlist_id` FK, not position                 |
| Rehearsals                             | **unaffected**           | Rehearsals do not interact with setlist ordering                          |
| Setlists / Catalog                     | **affected**             | Direct change to setlist ordering persistence layer                       |
| Songs                                  | **unaffected**           | Song ordering within setlists uses separate RPC (`reorder_setlist_songs`) |
| Members / RBAC                         | **unaffected**           | RPC validates band membership but does not change RBAC logic              |
| Auth / Session                         | **unaffected**           | No auth flow changes                                                      |
| Routing                                | **unaffected**           | No navigation changes                                                     |
| Notifications                          | **unaffected**           | No notification triggers on setlist position changes                      |
| Platform (iOS / Android / Web / macOS) | **all affected equally** | Shared Dart repository — behavior identical across all platforms          |

---

## 13. Regression Risk

**Level:** `LOW`

**Rationale:**

**Isolated Change:**

- Single method in one repository file (`reorderSetlists()` lines 1001–1023)
- No state management changes (controller already correct)
- No widget changes (UI already correct)
- No changes to song reordering (separate code path)

**Atomic Improvement:**

- Current: N sequential writes (can leave partial reorder on network failure)
- Proposed: 1 atomic transaction (all-or-nothing guarantee)
- Regression would manifest as "reorder fails completely" (visible immediately in manual testing), not silent corruption

**Well-Established Pattern:**

- RPC signature matches `move_song_between_setlists`, `bulk_add_songs_to_setlist`
- JSON response format matches existing RPCs
- SECURITY DEFINER + band membership validation is standard practice (5+ existing RPCs use this pattern)

**No Constraint Conflicts:**

- `setlists` table has **no unique constraint on `(band_id, position)`** (verified production schema)
- No two-phase trick needed (unlike `setlist_songs` which has `UNIQUE(setlist_id, position)`)
- Direct `UPDATE ... FROM unnest(...)` is safe

**Test Coverage:**

- No existing tests for `reorderSetlists()` (confirmed by feature input)
- QA will validate manually via drag-and-drop in UI (existing user workflow)

**Deployment Safety:**

- Migration deploys first via `supabase db push` (local) or CI/CD (prod)
- If migration fails, Dart code never calls new RPC (deployment atomicity)
- No backward compatibility required (feature branch merge is atomic)

---

## 14. Engineer Task Breakdown

Execute tasks **in strict order**. Do not skip. Do not reorder.

### Task 1: Create Migration File

**File:** `supabase/migrations/20260804200000_reorder_setlists_rpc.sql`

**Requirements:**

1. Create migration file with standard header comment:

   ```sql
   -- Migration: Atomic setlist reordering RPC
   -- Feature: bug/setlist-reorder-n-plus-one
   -- Purpose: Replace client-side N+1 sequential updates with single atomic server-side transaction
   ```

2. Define RPC signature:

   ```sql
   CREATE OR REPLACE FUNCTION reorder_setlists(
     p_band_id UUID,
     p_setlist_ids UUID[]
   )
   RETURNS JSON
   LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public
   ```

3. Function body must:
   - Validate `auth.uid()` is active member of `p_band_id` (query `band_members` table)
   - Verify all UUIDs in `p_setlist_ids` belong to `p_band_id` (prevent cross-band tampering)
   - Count verified setlists — if count doesn't match array length, return error JSON
   - Execute atomic UPDATE using `unnest(p_setlist_ids) WITH ORDINALITY`:
     ```sql
     UPDATE setlists
     SET position = subquery.new_position
     FROM unnest(p_setlist_ids) WITH ORDINALITY AS subquery(id, new_position)
     WHERE setlists.id = subquery.id
       AND setlists.band_id = p_band_id;
     ```
   - Return success JSON: `json_build_object('success', true, 'reordered_count', array_length(p_setlist_ids, 1))`
   - Catch exceptions: `EXCEPTION WHEN OTHERS THEN RETURN json_build_object('success', false, 'error', SQLERRM);`

4. **Critical:** Position starts at 1 (not 0) because position 0 is reserved for Catalog per `copilot-instructions.md` comment in current code

**Reference Pattern:** `supabase/migrations/20260712000000_move_song_between_setlists_rpc.sql`

**Success Criteria:**

- File created at correct path with correct timestamp
- RPC compiles without syntax errors
- Follows SECURITY DEFINER + search_path pattern per Guardrails §4

---

### Task 2: Update Repository Method

**File:** `lib/features/setlists/setlist_repository.dart` (lines 1001–1023)

**Requirements:**

1. Preserve method signature (do not change):

   ```dart
   Future<void> reorderSetlists({
     required String bandId,
     required List<String> setlistIdsInOrder,
   }) async
   ```

2. Preserve argument validation and early returns:
   - `if (bandId.isEmpty) throw ArgumentError('bandId cannot be empty');`
   - `if (setlistIdsInOrder.isEmpty) return;`

3. Preserve debug prints (update text to reflect RPC call):

   ```dart
   if (kDebugMode) {
     debugPrint('[SetlistRepository] reorderSetlists (via RPC):');
     debugPrint('  bandId: $bandId');
     debugPrint('  setlistCount: ${setlistIdsInOrder.length}');
   }
   ```

4. **Replace lines 1004–1010** (the `for` loop) with single RPC call:

   ```dart
   try {
     final response = await supabase.rpc(
       'reorder_setlists',
       params: {
         'p_band_id': bandId,
         'p_setlist_ids': setlistIdsInOrder,
       },
     );

     // Parse JSON response
     if (response is Map && response['success'] == true) {
       if (kDebugMode) {
         debugPrint(
           '[SetlistRepository] ✓ Reordered ${response['reordered_count']} setlists via RPC',
         );
       }
       return;
     }

     // RPC returned error
     if (response is Map && response['success'] == false) {
       final error = response['error'] ?? 'Unknown RPC error';
       if (kDebugMode) {
         debugPrint('[SetlistRepository] RPC error: $error');
       }
       throw Exception('Reorder setlists failed: $error');
     }

     // Unexpected response format
     if (kDebugMode) {
       debugPrint('[SetlistRepository] Unexpected RPC response: $response');
     }
     throw Exception('Unexpected response from reorder_setlists RPC');
   } catch (e) {
     if (kDebugMode) {
       debugPrint('[SetlistRepository] Error reordering setlists: $e');
     }
     rethrow;
   }
   ```

5. **Do NOT add fallback logic** — if RPC missing, fail loudly (see §6 rationale)

**Success Criteria:**

- Lines 1001–1023 contain new implementation
- No changes outside this method
- `flutter analyze` passes with 0 errors
- Debug output distinguishes RPC call from old sequential approach

---

### Task 3: Verify Migration Syntax

**Command:** `supabase db reset --local` (destroys local DB and replays all migrations)

**Requirements:**

1. Run in project root directory
2. Confirm all migrations apply successfully (including new `20260804200000_reorder_setlists_rpc.sql`)
3. If migration fails, fix syntax errors and re-run

**Success Criteria:**

- `supabase db reset --local` completes without errors
- New RPC visible in Supabase Studio Functions tab

---

### Task 4: Static Analysis

**Command:** `flutter analyze`

**Requirements:**

- Must pass with **0 errors**
- Warnings are acceptable if they existed before (do not introduce new warnings)

**Success Criteria:**

- Exit code 0
- No new analyzer complaints about `setlist_repository.dart` lines 1001–1023

---

### Task 5: Generate Git Diff

**Command:** `git diff`

**Requirements:**

1. Capture complete diff showing:
   - New migration file (`supabase/migrations/20260804200000_reorder_setlists_rpc.sql`)
   - Modified `lib/features/setlists/setlist_repository.dart` (lines 1001–1023 only)

2. Confirm no unintended changes (e.g., accidental formatting, unrelated files)

**Success Criteria:**

- Diff includes exactly 2 files (1 new migration, 1 modified repository)
- No changes to files listed in §11 (Files Off-Limits)

---

### Task 6: Create ENGINEER_REPORT.md

**File:** `docs/features/setlist-reorder-n-plus-one/ENGINEER_REPORT.md`

**Requirements:**

1. Document all completed tasks (1–5)
2. Include `flutter analyze` output (confirm 0 errors)
3. Include `supabase db reset --local` output (confirm migration applied)
4. Paste complete `git diff` output
5. Note any deviations from Architect plan (should be none)
6. Explicitly state: "Ready for QA validation"

**Success Criteria:**

- Report complete and factual
- No speculation or interpretation (just facts)
- Clear handoff to QA

---

## 15. Verification Plan

### Tier 1 — Pre-Deployment (Before `supabase db push`)

**Context:**
Tier 1 tests run **before** the new migration is applied to production. The new `reorder_setlists` RPC does not exist yet in prod DB. Tests in this tier must not call the new RPC — they verify supporting logic or inspect the migration file itself.

**Test 1: Migration File Syntax**

```sql
-- PRE-DEPLOY TEST 1: Verify migration file compiles without syntax errors
-- Run: supabase db reset --local (in dev environment)
-- Expected: All migrations (including 20260804200000_reorder_setlists_rpc.sql) apply successfully
-- No direct SQL to paste here — this is a process verification
```

**Test 2: Verify No Breaking Changes to Existing Setlists**

```sql
-- PRE-DEPLOY TEST 2: Confirm existing setlist queries still work (RLS unchanged)
-- Run this in production Supabase SQL Editor (as authenticated user, not service role)
SELECT id, band_id, name, position, setlist_type
FROM setlists
WHERE band_id = 'YOUR_BAND_ID'  -- Replace with test band UUID
ORDER BY position ASC
LIMIT 5;

-- Expected: Query succeeds, returns setlists in position order
-- This confirms RLS policies are unaffected by upcoming RPC addition
```

**Test 3: Verify Band Membership Query Pattern**

```sql
-- PRE-DEPLOY TEST 3: Confirm band membership validation query (used by RPC) works
-- Run this in production Supabase SQL Editor (as authenticated user)
SELECT EXISTS (
  SELECT 1 FROM band_members
  WHERE band_id = 'YOUR_BAND_ID'  -- Replace with test band UUID
    AND user_id = auth.uid()
) AS is_member;

-- Expected: Returns {is_member: true} if you're a member, {is_member: false} otherwise
-- This validates the RPC's membership check will function correctly
```

**Test 4: Flutter Code Compiles**

```bash
# PRE-DEPLOY TEST 4: Verify Dart code compiles and analyzes cleanly
flutter analyze

# Expected: 0 errors (warnings acceptable if pre-existing)
# This confirms the modified repository method has no syntax/type errors
```

---

### Tier 2 — Post-Deployment (After `supabase db push` and Flutter Deploy)

**Context:**
Tier 2 tests run **after** the migration has been applied to production and the Flutter app has been deployed. The new `reorder_setlists` RPC now exists in the prod DB.

**Test 5: Verify RPC Exists in Production**

```sql
-- POST-DEPLOY TEST 5: Confirm RPC function exists in prod DB
SELECT pg_get_functiondef(oid) AS function_definition
FROM pg_proc
WHERE proname = 'reorder_setlists'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

-- Expected: Returns the full function definition containing "SECURITY DEFINER"
-- If empty result, RPC did not deploy — rollback required
```

**Test 6: RPC Input Validation (Invalid Band)**

```sql
-- POST-DEPLOY TEST 6: Verify RPC rejects calls for bands where user is not a member
-- Run as authenticated user (not service role)
SELECT reorder_setlists(
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,  -- Fake band ID
  ARRAY['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid]  -- Fake setlist ID
);

-- Expected: Returns JSON with "success": false, "error": "User is not a member of this band"
-- If success=true, security validation failed — critical bug
```

**Test 7: RPC Cross-Band Tampering Protection**

```sql
-- POST-DEPLOY TEST 7: Verify RPC rejects setlist IDs that don't belong to target band
-- Prerequisites:
--   - User is member of BAND_A
--   - SETLIST_X belongs to BAND_A
--   - SETLIST_Y belongs to BAND_B (different band)
-- Run as authenticated user:

SELECT reorder_setlists(
  'BAND_A_UUID'::uuid,  -- Replace with real band A UUID
  ARRAY['SETLIST_X_UUID'::uuid, 'SETLIST_Y_UUID'::uuid]  -- Mix of bands
);

-- Expected: Returns JSON with "success": false, "error" containing "do not belong to this band"
-- If success=true, cross-band security check failed — critical bug
```

**Test 8: RPC Success Case (Atomic Reorder)**

```sql
-- POST-DEPLOY TEST 8: Verify RPC successfully reorders setlists atomically
-- Prerequisites: User is active member of test band, band has 3+ non-Catalog setlists
-- Run as authenticated user:

-- Step 1: Record current order
SELECT id, name, position FROM setlists
WHERE band_id = 'YOUR_BAND_ID'::uuid  -- Replace with test band
  AND setlist_type != 'catalog'
ORDER BY position ASC;

-- Step 2: Call RPC with reversed order (example UUIDs — replace with actual from Step 1)
SELECT reorder_setlists(
  'YOUR_BAND_ID'::uuid,
  ARRAY['SETLIST_3_ID'::uuid, 'SETLIST_2_ID'::uuid, 'SETLIST_1_ID'::uuid]
);

-- Expected: Returns JSON with "success": true, "reordered_count": 3

-- Step 3: Verify new order persisted
SELECT id, name, position FROM setlists
WHERE band_id = 'YOUR_BAND_ID'::uuid
  AND setlist_type != 'catalog'
ORDER BY position ASC;

-- Expected: Positions now match reversed array order (setlist_3 at position 1, etc.)
-- If order unchanged, UPDATE statement in RPC failed — critical bug
```

**Test 9: UI Workflow (Manual Drag-and-Drop)**

```
Manual Test — POST-DEPLOY TEST 9: Verify UI reorder completes successfully

Prerequisites:
- Band with 5+ setlists (exclude Catalog)
- Logged in on any platform (Web recommended for fastest iteration)

Steps:
1. Navigate to Setlists screen
2. Drag setlist at position 2 to position 4 (or any non-trivial reorder)
3. Observe: No error snackbar appears
4. Pull to refresh the setlist list
5. Verify: Setlist order persisted correctly (matches post-drag state)
6. Open browser DevTools Network tab (Web) or Charles Proxy (mobile)
7. Repeat drag-and-drop
8. Verify: Only ONE network request to `supabase.co/rest/v1/rpc/reorder_setlists` (not N individual updates)

Expected Behavior:
- Reorder completes in <500ms regardless of setlist count
- No error messages
- Order persists across app restarts
- Network tab shows single RPC call (not multiple UPDATE queries)

If any step fails:
- Check browser console for JavaScript errors
- Check Supabase Logs for RPC errors
- Verify migration applied successfully (see Test 5)
```

**Test 10: Performance Baseline (N=20 Setlists)**

```
Manual Test — POST-DEPLOY TEST 10: Measure reorder latency improvement

Prerequisites:
- Band with exactly 20 non-Catalog setlists (create test band if needed)
- Browser DevTools Network tab open (Web platform)

Steps:
1. Navigate to Setlists screen
2. Drag last setlist to first position (maximum reorder distance)
3. Measure time from drag release to success (no error)
4. Record network request duration in DevTools (look for `reorder_setlists` RPC call)

Expected Performance:
- Old implementation (N sequential queries): ~2–5 seconds (estimated, cannot test post-fix)
- New implementation (1 RPC call): <500ms total, <200ms for RPC itself

Pass Criteria:
- Reorder completes in <1 second
- Only 1 RPC call visible in network tab
- No timeout errors
- User perceives reorder as "instant" (no visible loading state beyond optimistic UI)

If latency >1 second:
- Check network conditions (not a code issue if slow network)
- Check Supabase dashboard for query performance metrics
- Verify RPC uses indexed columns (band_id has index)
```

---

### QA Handoff Checklist

Before QA begins Tier 2 tests, Engineer must confirm:

- [ ] All Engineer tasks (§14 Tasks 1–6) completed
- [ ] `ENGINEER_REPORT.md` created and contains full `git diff`
- [ ] `flutter analyze` passes with 0 errors
- [ ] `supabase db reset --local` succeeds (migration applies cleanly)
- [ ] Tier 1 tests completed successfully (pre-deploy validation)
- [ ] Migration deployed to production via `supabase db push` (or CI/CD pipeline)
- [ ] Flutter app deployed to production (Web: `./tools/deploy_web.sh`, Mobile: standard release process)
- [ ] Test band exists in production with 5+ setlists for manual testing

QA will execute Tier 2 tests (Tests 5–10) and produce `QA_REPORT.md` with verdict: **APPROVED** or **REQUIRES CHANGES**.

---

## Notes for Manager

**Pipeline Gate Status:**

- ✅ Gate 1 (Input Gate): Feature input is complete, slug is valid
- ✅ Gate 2 (Architecture Gate): This plan is the gate deliverable
- ⏳ Gate 3 (Implementation Gate): Pending Engineer execution
- ⏳ Gate 4 (Release Gate): Pending QA approval

**Blockers:** None identified

**Escalation Points:**

- If `supabase db reset --local` fails on new migration, Engineer must fix syntax before proceeding to Task 4
- If Tier 2 Test 8 or Test 9 fails (RPC exists but reorder doesn't work), escalate to Architect for diagnosis (likely logic error in RPC UPDATE statement)

**Deployment Sequence (Critical):**

1. Merge feature branch to `main` (after QA APPROVED)
2. Deploy migration: `supabase db push --project-ref nekwjxvgbveheooyorjo` (production project)
3. Confirm migration applied (check Supabase Studio Functions tab for `reorder_setlists`)
4. Deploy Flutter: `./tools/deploy_web.sh` (Web first, mobile follows standard release)
5. Run Tier 2 Test 9 (UI workflow) in production to confirm end-to-end success

**Rollback Plan (If Post-Deploy Failure):**

1. Revert Flutter deployment (rollback to previous Git tag)
2. Drop function: `DROP FUNCTION reorder_setlists(UUID, UUID[]);` via Supabase SQL Editor
3. Dart code will fail when calling RPC — this is intentional (fail loudly, don't silently degrade to N+1)
4. Architect must diagnose RPC logic error before redeployment

---

**END OF ARCHITECT_PLAN.md**
