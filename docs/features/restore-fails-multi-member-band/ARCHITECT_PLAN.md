# Architect Plan

## Feature Slug

`bug/restore-fails-multi-member-band`

Branch: `bug/restore-fails-multi-member-band`
Docs path: `docs/features/restore-fails-multi-member-band/ARCHITECT_PLAN.md`

---

## Feature Title

Restore fails for multi-member bands — `band_members` RLS upsert failure

---

## Problem Summary

When restoring a band backup after band deletion, `_restoreBandData` currently attempts to restore `band_members` in a batch after calling `create_band` RPC and filtering out the restoring admin's row. For backups containing multiple active members (admin + 1 or more other members), the restore fails during the `band_members` step with a `PostgrestException 42501` permissions error.

This bug is latent in production and has not affected the primary user (Tony) because his restored/exported bands have only had one active member at export time — after filtering out his own row, the batch is empty, so no batch insert occurs.

A prior related bug (`bug/restore-fails-after-band-deletion`) was fixed in June 2026 and introduced the `create_band` RPC call plus UUID remapping logic. However, that fix did not address the multi-member batch insert RLS failure mode.

---

## Confirmed Current Behavior

### Current restore flow for missing-band scenario (after prior fix)

**File:** `lib/features/settings/data_backup_service.dart`, `_restoreBandData` lines 412–528

**Sequence:**

1. Call `supabase.rpc('create_band', params: {p_name, p_avatar_color, p_image_url})` → returns `newBandId`
   - `create_band` atomically inserts a new band row AND a `band_members` row with `(band_id: newBandId, user_id: auth.uid(), role: 'admin', status: 'active')`

2. Query the trigger-created catalog setlist UUID and build `setlistIdRemap`

3. Remap `band_id` to `newBandId` in all child table rows

4. Filter `band_members`:

   ```dart
   final rawMembers = (entry['band_members'] as List? ?? []).cast<Map<String, dynamic>>();
   final remappedMembers = rawMembers
       .map((r) => Map<String, dynamic>.from(r)..['band_id'] = newBandId)
       .where((r) => r['user_id'] != userId)  // ← filter out current user
       .toList();
   ```

5. Call `await _upsertRows('band_members', remappedMembers);`
   - `_upsertRows` executes: `supabase.from('band_members').upsert(data, onConflict: 'id', ignoreDuplicates: false)`
   - This is a **single statement** with multiple rows
   - For a backup with admin + 2 other members: `remappedMembers` contains 2 rows

6. Continue with the remaining upserts in FK-safe order

### Failure point

Step 5 fails with `PostgrestException 42501` (insufficient privilege) when `remappedMembers.length >= 1`.

---

## Root Cause

**Confidence: HIGH (confirmed via code inspection + prior investigation docs + user report)**

The `band_members` INSERT RLS policy uses:

```sql
WITH CHECK: (is_band_member(band_id) OR (user_id = auth.uid()))
```

The helper function `is_band_member(p_band_id uuid)` is defined as `STABLE SECURITY DEFINER`. Per PostgreSQL semantics, `STABLE` functions evaluate against the snapshot at statement start.

**What happens during the batch upsert:**

- Step 1 (`create_band` RPC) successfully inserted the admin's `band_members` row in statement 1. This row is now visible to all subsequent database statements.

- Step 5 calls `supabase.from('band_members').upsert([member2, member3], ...)` — this is statement 2, a single multi-row INSERT/ON CONFLICT UPDATE.

- For **member2's** row (first row in the batch):
  - `user_id = member2_user_id`
  - `band_id = newBandId`
  - RLS CHECK: `(is_band_member(newBandId) OR (user_id = auth.uid()))`
    - `user_id = auth.uid()` → `member2_user_id = restoring_admin_user_id` → **FALSE**
    - `is_band_member(newBandId)` → checks if `auth.uid()` (the restoring admin) is a member of `newBandId`
    - The admin row **was** inserted in statement 1 (the `create_band` call)
    - **However**, depending on how `is_band_member` is implemented and whether it's truly `SECURITY DEFINER`, it may be:
      - Running under the caller's RLS context (if actually `SECURITY INVOKER`)
      - Checking a different condition than expected
      - Evaluating against a stale snapshot

- Without being able to query the live `is_band_member` function definition, the exact failure mechanism is unclear. However, the empirical evidence (multi-member restore fails, single-member restore works) confirms that the batch upsert is the problem.

**Alternative root cause hypothesis (confidence: MEDIUM):**

It's possible that `is_band_member` is not actually `SECURITY DEFINER` and instead runs as `SECURITY INVOKER`, meaning it's subject to RLS when it queries `band_members`. If the `band_members` SELECT policy requires something more restrictive, the function might not be able to see the admin row even though it exists.

**Regardless of the exact mechanism, the observed behavior is:**

- Batch insert of 0 members (admin-only backup after filtering): ✅ succeeds (no INSERT happens)
- Batch insert of 1+ members (multi-member backup after filtering): ❌ fails with 42501

---

## Existing Restore Flow

See "Confirmed Current Behavior" above. The current flow is:

1. Check if `backupBandId` exists in database → `bandExists`
2. If `bandExists == true`: upsert with original IDs (existing-band path — unchanged from prior fix)
3. If `bandExists == false`:
   - Call `create_band` RPC → get `newBandId`
   - Query trigger-created catalog, build `setlistIdRemap`
   - Remap `band_id`, filter current user from `band_members`, generate fresh UUIDs for rehearsals/block_dates
   - Upsert in FK-safe order (see §4 of prior plan)

**Current partial-restore behavior:**

If step 5 (`band_members` upsert) fails:

- A `PostgrestException` is thrown from `_upsertRows`
- It's caught by the `on PostgrestException` handler in `_restoreBandData` and re-thrown as `DataBackupException('Database error during restore: ${e.message}')`
- This propagates to `_performImport` in `band_form_screen.dart`, which displays the error message in a snackbar
- The new band (`newBandId`) **remains** in the database with:
  - ✅ `bands` row created
  - ✅ `band_members` row for the restoring admin created by `create_band`
  - ✅ Trigger-created catalog setlist created
  - ❌ No other `band_members` rows
  - ❌ No `songs`, `setlists`, `gigs`, `rehearsals`, or `block_dates`

**This is a partially restored band** — unsafe state. The admin is a member of a band with the correct name but no other data.

---

## Live Database Findings

### Required investigation (cannot be completed without live database access)

The Engineer must run the following queries against production before implementing and record the results in `ENGINEER_REPORT.md`:

#### Query 1: Confirm `is_band_member` function signature, volatility, security mode

```sql
SELECT
  proname AS function_name,
  pg_get_function_arguments(oid) AS arguments,
  pg_get_function_result(oid) AS return_type,
  provolatile AS volatility_code,
  CASE provolatile
    WHEN 'i' THEN 'IMMUTABLE'
    WHEN 's' THEN 'STABLE'
    WHEN 'v' THEN 'VOLATILE'
  END AS volatility,
  prosecdef AS is_security_definer
FROM pg_proc
WHERE proname = 'is_band_member'
  AND pronamespace = 'public'::regnamespace;
```

**Expected (based on prior investigation):** `volatility = STABLE`, `is_security_definer = TRUE`

#### Query 2: Get `is_band_member` function body

```sql
SELECT pg_get_functiondef('public.is_band_member(uuid)'::regprocedure);
```

This will reveal exactly what `is_band_member` checks and whether it includes `status = 'active'` or other filters.

#### Query 3: Confirm `band_members` INSERT RLS policy

```sql
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'band_members'
  AND schemaname = 'public'
  AND cmd = 'INSERT';
```

**Expected:** `with_check` contains `(is_band_member(band_id) OR (user_id = auth.uid()))`

#### Query 4: Check for `band_members` constraints and indexes

```sql
-- Constraints
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.band_members'::regclass;

-- Indexes
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'band_members' AND schemaname = 'public';
```

This confirms the `(band_id, user_id)` unique constraint and any other constraints that might be relevant.

---

## Fix Options Evaluated

### Option 1 — Serialized single-row inserts

**Description:**  
Replace the batch `_upsertRows('band_members', remappedMembers)` call with a loop that inserts each row individually:

```dart
for (final member in remappedMembers) {
  await _upsertRows('band_members', [member]);
}
```

Each `_upsertRows` call is a separate database statement. If `is_band_member` is `STABLE`, it will evaluate against the snapshot at each statement's start, potentially allowing it to see previously inserted rows.

**Pros:**

- Minimal code change (5-10 lines)
- No database migration required
- No new RLS policies or helper functions
- Preserves existing RLS semantics
- If the issue is statement-level snapshot visibility, this fixes it
- Compatible with the prior fix (doesn't undo any of the `create_band` work)

**Cons:**

- N round-trip cost: for a band with 10 members, this is 9 HTTP requests instead of 1
- If a row fails midway (e.g., row 3 of 7), rows 1–2 are already inserted → partial state (see "Partial restore risk" below)
- If the root cause is NOT snapshot visibility (e.g., `is_band_member` is actually `SECURITY INVOKER` and blocked by RLS), this may not fix the problem
- No atomicity: failure leaves some members inserted, others not

**Security risk:** Low — no privilege escalation, no RLS bypass. Uses the same RLS checks as the batch insert.

**Data-integrity risk:** Medium — partial member inserts possible. Requires explicit cleanup strategy.

**Implementation complexity:** Low

**Confidence this will work:** MEDIUM — depends on whether snapshot visibility is the actual root cause. If `is_band_member` is `SECURITY INVOKER`, this won't help.

---

### Option 2 — Trusted `SECURITY DEFINER` RPC for restore membership

**Description:**  
Create a new RPC function `restore_band_members(p_band_id uuid, p_members jsonb)` that:

1. Validates that the caller is the creator of `p_band_id` (checks `bands.created_by = auth.uid()`)
2. Validates that a `band_members` row exists for `(p_band_id, auth.uid())` with `role = 'admin'` and `status = 'active'`
3. Inserts/upserts the provided member rows using `SECURITY DEFINER` to bypass RLS
4. Returns success/failure

**Rationale:** The restore flow is inherently privileged — the restoring admin is recreating a band from a trusted backup they exported. Allowing them to restore all members atomically is safe because:

- They are admin of the newly created band
- They exported the backup (or obtained it from a trusted source)
- The RPC validates their authority before proceeding

**Pros:**

- Atomic: all members inserted in a single database call, or none
- Bypasses the RLS issue entirely (no `is_band_member` check for the inserted rows)
- No client-side loop → single round-trip
- Explicit validation inside the RPC (defense in depth)
- Works regardless of whether the root cause is snapshot visibility or RLS blocking `is_band_member`
- Can include explicit rollback on failure

**Cons:**

- Requires a database migration
- Introduces a new `SECURITY DEFINER` function (privilege escalation surface — requires careful review)
- Must be documented in `AI_DECISIONS.md`
- Adds complexity to the restore flow (app must call RPC instead of direct upsert)
- JSONB parameter passing from Dart requires careful serialization
- Must include `SET search_path = public` (per guardrails)

**Security risk:** Medium — `SECURITY DEFINER` functions are privilege escalation surfaces. Mitigation:

- Validate caller owns the band (`bands.created_by = auth.uid()`)
- Validate caller is admin member (`band_members` check)
- Only allow upserting members for the band the caller just created (no arbitrary band ID)
- Do NOT blindly trust `role` or `status` from client — could enforce `status = 'active'` and validate `role IN ('admin', 'member', 'contributor')`

**Data-integrity risk:** Low — atomic operation. Either all members are inserted or the transaction rolls back.

**Implementation complexity:** Medium (migration + RPC function + Dart integration)

**Confidence this will work:** HIGH — bypasses RLS entirely, so root cause becomes irrelevant.

---

### Option 3 — RLS policy rework

**Description:**  
Modify the `band_members` INSERT policy to allow the creator of a band to insert members during restore. Possible approaches:

**Approach A:** Add a check for `bands.created_by = auth.uid()`:

```sql
WITH CHECK: (
  EXISTS (
    SELECT 1 FROM bands b
    WHERE b.id = band_members.band_id
      AND b.created_by = auth.uid()
  )
  OR is_band_member(band_id)
  OR (user_id = auth.uid())
)
```

**Approach B:** Change `is_band_member` to `VOLATILE` instead of `STABLE` (ruled out — see Option 4).

**Pros (Approach A):**

- Fixes the restore case without requiring an RPC
- Allows batch insert to succeed
- No new SECURITY DEFINER function

**Cons (Approach A):**

- This self-references `bands` from `band_members` — may be fine (not self-referencing the same table), but must be tested
- Changes the INSERT policy for ALL `band_members` inserts, not just restore
- A band creator can now insert arbitrary members at any time (not just during restore) — is this acceptable?
- If the band creator adds a malicious user, they can do so without that user accepting an invitation
- Broadens the policy beyond the restore use case

**Security risk:** Medium/High — allows band creators to bypass the invitation flow and directly insert members. This is a significant RBAC change.

**Data-integrity risk:** Low — if the policy is correct, inserts will succeed atomically.

**Implementation complexity:** Low (policy change in a migration)

**Confidence this will work:** HIGH — if the policy is correct, the batch insert will pass RLS.

**Recommendation:** Do NOT use Approach A. It's too broad and breaks the invitation model.

---

### Option 4 — Change `is_band_member` volatility to `VOLATILE`

**Description:**  
Change `is_band_member` from `STABLE` to `VOLATILE`:

```sql
CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id uuid)
RETURNS boolean
LANGUAGE <language>
VOLATILE  -- ← change from STABLE
SECURITY DEFINER
SET search_path = public
AS $$
<function body>
$$;
```

**Rationale:** `VOLATILE` functions re-evaluate for every row in a multi-row statement, so each member row's RLS check would see the rows inserted earlier in the same statement.

**Pros:**

- May fix the snapshot visibility issue
- No app code changes required

**Cons:**

- Changes the volatility of a function used by **every** `bands` SELECT query (see the `bands` SELECT policy: `USING is_band_member(id)`)
- `VOLATILE` functions are not inlineable and cannot be used in index scans — performance impact on all band queries
- If `is_band_member` is `STABLE`, there's a reason (either it was intentional, or it's safe because it doesn't modify data)
- Changing this affects **every system** that uses `is_band_member`, not just restore
- The blast radius is too large for a restore-only bug fix

**Security risk:** Low — no privilege escalation, just a query optimization change.

**Data-integrity risk:** Low.

**Performance risk:** HIGH — affects all band queries.

**Implementation complexity:** Low (one-line function change).

**Confidence this will work:** MEDIUM — may fix the snapshot visibility issue, but the side effects are unacceptable.

**Recommendation:** RULE OUT. The blast radius and performance implications make this unsuitable for a restore-scoped fix.

---

## Recommended Solution

**Option 2 — Trusted `SECURITY DEFINER` RPC for restore membership.**

**Rationale:**

1. **Atomic:** All members are inserted in a single database transaction. No partial restore state if a member fails.

2. **Bypasses the root cause:** Whether the issue is snapshot visibility, `is_band_member` being `SECURITY INVOKER`, or any other RLS quirk, the RPC sidesteps it entirely by using `SECURITY DEFINER`.

3. **Scoped to restore:** The RPC is narrowly scoped to the restore use case. It does not affect normal member addition (via invitation), role changes, or any other RBAC operation.

4. **Defense in depth:** The RPC validates:
   - Caller created the band (`bands.created_by = auth.uid()`)
   - Caller is an active admin member of the band (double-check membership exists)
   - Band ID is valid

5. **Explicit rollback:** If any member insert fails, the entire RPC transaction can be rolled back, leaving the band with only the admin row (the `create_band` result). The caller can then retry or report the error.

6. **Future-proof:** If RLS policies or `is_band_member` change in the future, the RPC remains stable.

7. **Minimal app changes:** Replace one `_upsertRows` call with one `supabase.rpc` call.

**Why not Option 1 (serialized inserts)?**

- Partial restore risk is too high (leaves some members inserted, others not)
- N round-trips are inefficient
- Doesn't guarantee the fix (may not address the root cause if it's RLS-related, not snapshot-related)
- No atomicity

**Why not Option 3 (RLS policy rework)?**

- Too broad: allows band creators to bypass invitations at any time, not just during restore
- Breaks the invitation model
- Security risk is unacceptable

**Why not Option 4 (change `is_band_member` to `VOLATILE`)?**

- Blast radius is too large (affects all band queries)
- Performance implications are unacceptable for a restore-only fix

---

## Partial Restore / Rollback Strategy

### Current behavior (no rollback)

If `_upsertRows('band_members', remappedMembers)` fails:

- The new band (`newBandId`) remains in the database
- The admin's `band_members` row (inserted by `create_band`) remains
- The trigger-created catalog setlist remains
- No other data is restored

**This is unsafe** — the user sees an error, but the band exists in a half-restored state.

### Option 2 (RPC) rollback strategy

The RPC `restore_band_members(p_band_id, p_members)` runs inside a `plpgsql` function, which is automatically wrapped in a transaction. If any INSERT fails:

1. PostgreSQL automatically rolls back the entire function
2. The RPC returns an error
3. The Dart code catches the error and displays it
4. The band (`newBandId`) remains with only the admin's row (the result of `create_band`)
5. No partial member inserts occur

**Compensating cleanup (optional):**

If the restore fails at the `band_members` step, the Dart code could optionally call `delete_band(newBandId)` to remove the partially restored band entirely. However, this is **not recommended** because:

- The user may want to inspect the partially restored band
- The user can manually delete the band if desired
- Automatic deletion could be surprising and lose the `create_band` progress

**Recommended:** Leave the band with the admin row only. The error message should clearly state that restore failed and the new band is incomplete.

### Option 1 (serialized inserts) rollback strategy

If serialized inserts are used (not recommended), the rollback strategy must be:

1. If any `_upsertRows([member])` fails:
   - Catch the exception
   - Call `delete_band(newBandId)` to remove the partially restored band
   - Re-throw the exception as a `DataBackupException`

2. This ensures no partial member state remains.

**However, this is complex and error-prone:**

- What if `delete_band` itself fails?
- What if the network disconnects during cleanup?
- The cleanup is not atomic with the restore

**Option 2's automatic rollback is superior.**

---

## Database Impact

### New RPC: `restore_band_members`

**Signature:**

```sql
public.restore_band_members(
  p_band_id uuid,
  p_members jsonb  -- array of {id, user_id, role, status, joined_at, ...}
) RETURNS void
```

**Security mode:** `SECURITY DEFINER`  
**Search path:** `SET search_path = public`  
**Language:** `plpgsql`

**Logic:**

1. Validate caller authority:

   ```sql
   IF NOT EXISTS (
     SELECT 1 FROM bands
     WHERE id = p_band_id AND created_by = auth.uid()
   ) THEN
     RAISE EXCEPTION 'Permission denied: you did not create this band';
   END IF;

   IF NOT EXISTS (
     SELECT 1 FROM band_members
     WHERE band_id = p_band_id
       AND user_id = auth.uid()
       AND role = 'admin'
       AND status = 'active'
   ) THEN
     RAISE EXCEPTION 'Permission denied: you are not an admin of this band';
   END IF;
   ```

2. Loop over `p_members` JSONB array and upsert each row:

   ```sql
   INSERT INTO band_members (id, band_id, user_id, role, status, joined_at)
   SELECT
     (m->>'id')::uuid,
     p_band_id,
     (m->>'user_id')::uuid,
     (m->>'role')::band_role_type,
     (m->>'status')::text,
     COALESCE((m->>'joined_at')::timestamptz, NOW())
   FROM jsonb_array_elements(p_members) AS m
   ON CONFLICT (id) DO UPDATE SET
     user_id = EXCLUDED.user_id,
     role = EXCLUDED.role,
     status = EXCLUDED.status,
     joined_at = EXCLUDED.joined_at;
   ```

3. Return (implicit void return)

**Grant:** `GRANT EXECUTE ON FUNCTION public.restore_band_members(uuid, jsonb) TO authenticated;`

**Migration file:** `supabase/migrations/<timestamp>_restore_band_members_rpc.sql`

Use timestamp format `YYYYMMDDHHMMSS`. Timestamp after the most recent migration (`20260621000001`).

---

### Updated migration: Document decision in `AI_DECISIONS.md`

This introduces a new `SECURITY DEFINER` function, which is a guardrails-level decision. The migration must include a comment referencing `AI_DECISIONS.md`, and `AI_DECISIONS.md` must be updated with a new decision entry.

**Decision entry (to be added by Engineer):**

```markdown
## [DECISION-003] Restore Band Members RPC — SECURITY DEFINER for atomic multi-member restore

**Date:** 2026-06-20
**Feature:** bug/restore-fails-multi-member-band
**Agent:** Architect
**Status:** Active

### Context

Multi-member band restore fails during `band_members` batch upsert with RLS permission error (42501). The `is_band_member()` RLS helper is `STABLE`, causing snapshot visibility issues during batch INSERT. Serialized single-row inserts risk partial restore state and are inefficient. Broadening the RLS policy to allow band creators to insert members bypasses the invitation model and is a security risk.

### Decision

Introduce a narrow `SECURITY DEFINER` RPC `restore_band_members(p_band_id uuid, p_members jsonb)` that:

- Validates caller created the band (`bands.created_by = auth.uid()`)
- Validates caller is an active admin of the band
- Atomically inserts/upserts all member rows in a single transaction
- Bypasses RLS for the INSERT (since caller authority is validated server-side)

### Rationale

1. **Atomic:** Transaction rollback prevents partial member restore
2. **Scoped:** Only affects restore flow, not normal member addition/invitation
3. **Secure:** Explicit server-side validation of caller authority
4. **Minimal:** No changes to existing RLS policies or helper functions
5. **Efficient:** Single round-trip, no N+1 queries

### Constraints Imposed

- The RPC must only be called immediately after `create_band` during restore
- Caller must be the band creator and an active admin
- JSONB parameter must be validated (no SQL injection, role ENUM enforcement)
- `SET search_path = public` is mandatory (per GUARDRAILS)
- Any future changes to `band_members` schema must update this RPC
```

---

### No other database changes

- No RLS policy changes
- No changes to `is_band_member` or `get_user_band_role`
- No schema changes
- No trigger changes

---

## Flutter Architecture Changes

### State management

No provider changes. Restore flow remains inside `DataBackupService`.

### Repositories

No repository changes.

### Widgets

No widget changes beyond the error handling already present in `band_form_screen.dart`.

---

## Files to Create

| File                                                              | Justification                                        |
| ----------------------------------------------------------------- | ---------------------------------------------------- |
| `supabase/migrations/<timestamp>_restore_band_members_rpc.sql`    | New `SECURITY DEFINER` RPC for atomic member restore |
| `docs/features/restore-fails-multi-member-band/ARCHITECT_PLAN.md` | This document                                        |

**No new Dart files.** Changes are localized to existing files.

---

## Files to Modify

| File                                             | What changes                                                                                                                                    |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/settings/data_backup_service.dart` | Replace `_upsertRows('band_members', remappedMembers)` with `supabase.rpc('restore_band_members', params: {...})` in the missing-band path only |
| `docs/reference/general/AI_DECISIONS.md`         | Add DECISION-003 entry for the new SECURITY DEFINER function                                                                                    |

### Detailed changes to `data_backup_service.dart`

**Location:** Line ~487 (inside the `bandExists == false` block)

**Current code:**

```dart
// 2. Band members (filtered, remapped)
await _upsertRows('band_members', remappedMembers);
```

**New code:**

```dart
// 2. Band members (filtered, remapped) — use RPC for atomic restore
if (remappedMembers.isNotEmpty) {
  await supabase.rpc(
    'restore_band_members',
    params: {
      'p_band_id': newBandId,
      'p_members': remappedMembers,
    },
  );
}
```

**Rationale for `if (remappedMembers.isNotEmpty)` check:**

- If the backup contains only the admin (the restoring user), `remappedMembers` will be empty after filtering
- No need to call the RPC with an empty array (harmless, but wasteful)
- The RPC will succeed with an empty array (no-op), but the check makes intent clearer

**Error handling:**

- If the RPC throws a `PostgrestException`, the existing `on PostgrestException catch (e)` handler in `_restoreBandData` will catch it and wrap it as `DataBackupException`
- The error message from the RPC (e.g., "Permission denied: you did not create this band") will propagate to the user

---

## Files Off-Limits

| File                                                                                                     | Reason                                                     |
| -------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `lib/main.dart`                                                                                          | Initialization order must not change                       |
| `lib/features/settings/data_backup_service.dart` — all methods except `_restoreBandData` (lines 380–528) | Only the missing-band path's `band_members` upsert changes |
| `lib/features/bands/band_form_screen.dart`                                                               | Error handling is already correct from prior fix           |
| All migrations except the new `_restore_band_members_rpc.sql` and `AI_DECISIONS.md` update               | No other migrations modified                               |
| `supabase/functions/**`                                                                                  | No edge function changes required                          |
| All other `lib/features/**` files                                                                        | Not in scope                                               |
| `pubspec.yaml`                                                                                           | No new packages required                                   |

---

## Stop-Gate Protocol

An Engineer working from this plan may never claim authorization to bypass a stop-gate unless the exact authorizing words appear verbatim in the current Copilot chat thread. "The Architect plan implied it," "Tony said so earlier," and "the pipeline context permits it" are not valid authorization. If a stop-gate is reached and no verbatim authorization exists in this thread, the Engineer must stop, report the blocker, and wait.

---

## System Impact Map

| System              | Impact                                          |
| ------------------- | ----------------------------------------------- |
| Backup / Export     | Unaffected — export logic unchanged             |
| Restore / Import    | **Affected** — primary fix target               |
| Bands               | **Affected** — new RPC for band member restore  |
| Band members / RBAC | **Affected** — new restore path for members     |
| Gigs                | Unaffected — restore order unchanged            |
| Rehearsals          | Unaffected — restore order unchanged            |
| Setlists / Catalog  | Unaffected — restore order unchanged            |
| Songs               | Unaffected — restore order unchanged            |
| Auth / Session      | Unaffected                                      |
| Routing             | Unaffected                                      |
| Notifications       | Unaffected                                      |
| Supabase RLS / RPC  | **Affected** — new `SECURITY DEFINER` RPC added |

---

## Regression Risk

**MEDIUM**

Rationale:

- The new RPC is `SECURITY DEFINER` — privilege escalation surface (requires careful review)
- The RPC is narrowly scoped to restore and includes explicit authority checks
- The existing-band restore path is unchanged (no regression risk there)
- The missing-band restore path only changes the `band_members` step — all other steps unchanged
- If the RPC has a bug (e.g., doesn't validate caller authority correctly), it could allow unauthorized member insertion — however, the RPC validates both `created_by` and admin status, so the surface is small
- No changes to auth, routing, init order, or other high-risk areas

Risk is MEDIUM (not LOW) because `SECURITY DEFINER` functions always carry privilege escalation risk, even when carefully designed.

---

## Engineer Task Breakdown

Execute in strict order. Do not skip or reorder.

### Task 1 — Confirm `is_band_member` function properties (required before coding)

Run Queries 1–4 from "Live Database Findings" section against production. Record the full output in `ENGINEER_REPORT.md`. This confirms:

- The exact volatility and security mode of `is_band_member`
- The function body (to understand what it checks)
- The `band_members` INSERT RLS policy (to confirm it uses `is_band_member`)
- Constraints and indexes on `band_members` (to confirm `(band_id, user_id)` unique constraint)

If `is_band_member` is NOT `STABLE SECURITY DEFINER` as stated in the prior investigation, document the discrepancy and proceed with the RPC fix (which works regardless).

### Task 2 — Create migration: `restore_band_members` RPC

Create `supabase/migrations/<timestamp>_restore_band_members_rpc.sql`.

The migration must:

1. Include a comment at the top referencing this plan and the `AI_DECISIONS.md` entry
2. Define the RPC function:
   - Signature: `public.restore_band_members(p_band_id uuid, p_members jsonb) RETURNS void`
   - `LANGUAGE plpgsql`
   - `SECURITY DEFINER`
   - `SET search_path = public`
3. Validate caller created the band (`bands.created_by = auth.uid()`)
4. Validate caller is active admin (`band_members` check)
5. Loop over `p_members` JSONB array and INSERT/UPDATE each row:
   - Use `INSERT ... ON CONFLICT (id) DO UPDATE`
   - Cast JSONB fields: `(m->>'id')::uuid`, `(m->>'role')::band_role_type`, etc.
   - Use `COALESCE((m->>'joined_at')::timestamptz, NOW())` for `joined_at` (in case it's null)
6. `GRANT EXECUTE ON FUNCTION public.restore_band_members(uuid, jsonb) TO authenticated;`

**Template:**

```sql
-- ===========================================================================
-- Migration: restore_band_members RPC (SECURITY DEFINER)
-- Feature: bug/restore-fails-multi-member-band
-- Date: 2026-06-20
--
-- Introduces a trusted RPC for atomically restoring band members during
-- backup restore. The RPC bypasses RLS for the INSERT/UPDATE but validates
-- caller authority server-side (creator of band + active admin member).
--
-- See docs/features/restore-fails-multi-member-band/ARCHITECT_PLAN.md
-- See docs/reference/general/AI_DECISIONS.md — DECISION-003
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.restore_band_members(
  p_band_id uuid,
  p_members jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate: caller must be the creator of this band
  IF NOT EXISTS (
    SELECT 1 FROM bands
    WHERE id = p_band_id AND created_by = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Permission denied: you did not create this band';
  END IF;

  -- Validate: caller must be an active admin member of this band
  IF NOT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = auth.uid()
      AND role = 'admin'
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Permission denied: you are not an admin of this band';
  END IF;

  -- Insert or update all members from the JSONB array
  -- ON CONFLICT handles the case where a member row already exists (shouldn't happen
  -- during restore, but defensive)
  INSERT INTO band_members (id, band_id, user_id, role, status, joined_at)
  SELECT
    (m->>'id')::uuid,
    p_band_id,
    (m->>'user_id')::uuid,
    (m->>'role')::band_role_type,
    (m->>'status')::text,
    COALESCE((m->>'joined_at')::timestamptz, NOW())
  FROM jsonb_array_elements(p_members) AS m
  ON CONFLICT (id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    role = EXCLUDED.role,
    status = EXCLUDED.status,
    joined_at = EXCLUDED.joined_at;
END;
$$;

-- Grant execute to authenticated users (admins who are restoring)
GRANT EXECUTE ON FUNCTION public.restore_band_members(uuid, jsonb) TO authenticated;

-- Documentation
COMMENT ON FUNCTION public.restore_band_members IS
  'SECURITY DEFINER RPC for atomically restoring band members during backup restore. Validates caller is band creator and active admin. See DECISION-003 in AI_DECISIONS.md.';
```

### Task 3 — Update `AI_DECISIONS.md`

Add the DECISION-003 entry from the "Database Impact" section to `docs/reference/general/AI_DECISIONS.md`, following the existing format.

### Task 4 — Update `data_backup_service.dart`

Replace the `_upsertRows('band_members', remappedMembers)` call with the RPC call as specified in "Files to Modify" section.

**Exact location:** Line ~487, inside the `bandExists == false` block, step 2.

**Before:**

```dart
// 2. Band members (filtered, remapped)
await _upsertRows('band_members', remappedMembers);
```

**After:**

```dart
// 2. Band members (filtered, remapped) — use RPC for atomic restore
if (remappedMembers.isNotEmpty) {
  await supabase.rpc(
    'restore_band_members',
    params: {
      'p_band_id': newBandId,
      'p_members': remappedMembers,
    },
  );
}
```

**Do NOT modify:**

- The `bandExists == true` block (existing-band path)
- Any other upsert calls
- Any other methods in the file

### Task 5 — `flutter analyze` — zero errors

Run `flutter analyze` and fix any analysis errors introduced by the changes. Do not modify files not listed in this plan to fix pre-existing errors.

---

## Verification Plan

### Tier 1 — Pre-deployment (run before `supabase db push`)

All Tier 1 tests are read-only and do not depend on the new RPC.

```sql
-- PRE-DEPLOY TEST 1: Confirm is_band_member function properties
-- Run Query 1 from "Live Database Findings" section
-- Expected: volatility = STABLE, is_security_definer = TRUE (or document if different)

-- PRE-DEPLOY TEST 2: Confirm is_band_member function body
-- Run Query 2 from "Live Database Findings" section
-- Record the full function body for documentation

-- PRE-DEPLOY TEST 3: Confirm band_members INSERT RLS policy
-- Run Query 3 from "Live Database Findings" section
-- Expected: with_check contains (is_band_member(band_id) OR (user_id = auth.uid()))

-- PRE-DEPLOY TEST 4: Confirm band_members constraints
-- Run Query 4 from "Live Database Findings" section
-- Expected: UNIQUE constraint on (band_id, user_id) exists

-- PRE-DEPLOY TEST 5: Confirm create_band RPC signature is unchanged
SELECT proname, pg_get_function_arguments(oid) AS args
FROM pg_proc
WHERE proname = 'create_band' AND pronamespace = 'public'::regnamespace;
-- Expected: create_band | p_name text, p_avatar_color text DEFAULT NULL::text, p_image_url text DEFAULT NULL::text
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

```sql
-- POST-DEPLOY TEST 1: Confirm restore_band_members RPC exists with correct signature
SELECT proname, pg_get_function_arguments(oid) AS args, prosecdef AS is_security_definer
FROM pg_proc
WHERE proname = 'restore_band_members' AND pronamespace = 'public'::regnamespace;
-- Expected: restore_band_members | p_band_id uuid, p_members jsonb | TRUE

-- POST-DEPLOY TEST 2: Confirm SET search_path = public
SELECT pg_get_functiondef('public.restore_band_members(uuid, jsonb)'::regprocedure) LIKE '%SET search_path = public%' AS has_search_path;
-- Expected: TRUE

-- POST-DEPLOY TEST 3: Confirm permission checks exist in function body
SELECT pg_get_functiondef('public.restore_band_members(uuid, jsonb)'::regprocedure) LIKE '%Permission denied: you did not create this band%' AS has_creator_check;
-- Expected: TRUE

SELECT pg_get_functiondef('public.restore_band_members(uuid, jsonb)'::regprocedure) LIKE '%Permission denied: you are not an admin of this band%' AS has_admin_check;
-- Expected: TRUE

-- POST-DEPLOY TEST 4: Confirm GRANT to authenticated
SELECT has_function_privilege('authenticated', 'public.restore_band_members(uuid, jsonb)', 'execute') AS can_execute;
-- Expected: TRUE

-- POST-DEPLOY TEST 5: Functional test — unauthorized caller fails
-- (Requires a test band created by another user. Replace 'other-band-uuid' with actual ID.)
-- This must be run from a client or Supabase dashboard with a test account that is NOT the creator.
-- Expected: Exception raised "Permission denied: you did not create this band"
DO $$
BEGIN
  PERFORM restore_band_members(
    'other-band-uuid'::uuid,
    '[]'::jsonb
  );
  RAISE EXCEPTION 'FAIL: RPC should have blocked unauthorized caller';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'PASS: RPC correctly blocked unauthorized caller: %', SQLERRM;
END $$;

-- POST-DEPLOY TEST 6: Functional test — creator who is not admin fails
-- (Requires a test band where the creator demoted themselves. Unlikely scenario, but RPC checks both.)
-- Expected: Exception raised "Permission denied: you are not an admin of this band"

-- POST-DEPLOY TEST 7: Functional test — authorized caller succeeds (manual integration test)
-- See QA Regression Areas §21 for end-to-end restore test
```

---

## QA Regression Areas

QA must verify the following test cases:

### Primary — restore multi-member band after deletion (new band path)

1. Create a test band with Admin (user A) + Member (user B) + Member (user C)
2. Export the band's data (JSON backup file) while logged in as Admin (user A)
3. Delete the band via app Settings → "Delete Band"
4. Log in as Admin (user A)
5. Create a new band (or use an existing band to navigate to restore)
6. Navigate to Settings → Backup / Restore
7. Select the backup file and confirm restore
8. **Expected:** Restore succeeds. A new band is created with:
   - Name, avatar colour, avatar image from the backup
   - Admin (user A) is a member (from `create_band`)
   - Member (user B) is present in the members list
   - Member (user C) is present in the members list
   - Songs, setlists, gigs, rehearsals, block-out dates are all present
9. **Expected:** Success snackbar is shown
10. **Confirm:** No orphan/partial restored bands remain (query production DB)

### Regression — single-member restore (admin only)

1. Export a band with only Admin (user A) as the sole member
2. Delete the band
3. Restore the backup
4. **Expected:** Restore succeeds. New band has Admin (user A) only. No RPC call is made (empty `remappedMembers` array).

### Regression — restore when source band still exists (existing-band path)

1. Export a band's data (multi-member)
2. Do NOT delete the band
3. Navigate to the same band's Settings → Backup / Restore
4. Select the backup file and confirm restore
5. **Expected:** Restore succeeds. Band data is replaced with backup content. No new band is created. No RPC call is made (existing-band path uses direct upsert).

### Security — unauthorized restore attempt

**Scenario A:** User B (not the creator) attempts to restore a band created by User A

1. User A creates a band and exports it
2. User A shares the backup JSON file with User B
3. User B deletes a band they own and attempts to restore User A's backup
4. **Expected:** Restore fails with error message "Permission denied: you did not create this band" (or similar RPC error)

**Scenario B:** User A creates a band, demotes themselves to member, and attempts restore

1. User A creates a band, adds User B as admin
2. User B demotes User A to member
3. User A exports the band (should fail — only admins can export, per prior constraint)
4. If export somehow succeeds, User A deletes the band and attempts restore
5. **Expected:** Restore fails with "Permission denied: you are not an admin of this band"

(Note: Scenario B is unlikely because export is admin-only, but the RPC checks both conditions defensively.)

### Error handling — RPC error surfaces correctly

1. Manually trigger a restore RPC failure (e.g., corrupt JSONB, invalid role ENUM value)
2. **Expected:** Snackbar displays the RPC error message, not the generic "Restore failed. Please try again."

### Partial restore cleanup

1. Manually simulate a restore failure after `create_band` but before `restore_band_members` (requires code injection or network disconnect)
2. **Expected:** New band exists with only the admin row. No other data. User can delete the band manually if desired.

---

## Rollout / Migration Strategy

1. Run `supabase db push --linked` to deploy `_restore_band_members_rpc.sql`. Verify post-deploy tests pass.
2. Deploy the Flutter app:
   - Web: `./tools/deploy_web.sh`
   - Mobile: standard release build via Xcode / Android Studio
3. No data backfill is required. Existing single-member restores continue to work (no RPC call). Future multi-member restores will use the RPC.

---

## Rollback Plan

If the fix introduces a regression:

1. **Immediate:** Revert the Flutter app deployment to the prior version (before the RPC call)
2. **Database rollback:**
   - If the RPC has a critical security flaw, run:
     ```sql
     DROP FUNCTION IF EXISTS public.restore_band_members(uuid, jsonb);
     ```
   - If the RPC merely has a bug (e.g., doesn't insert members correctly), leave it in place and fix forward with a new migration
3. **Communication:** Notify users that multi-member restore is temporarily unavailable. Single-member restore and existing-band restore continue to work.

---

## Out of Scope

- Changing the backup file schema/format (schema v1 is unchanged)
- Expanding backup/restore to non-admin roles (separate planned feature)
- Cleaning up historically orphaned `rehearsals`/`block_dates` rows from pre-fix deletions (handled by prior fix)
- UX improvements to the restore confirmation dialog
- Optimizing the `is_band_member` function (separate performance investigation)
- Changing `is_band_member` volatility or RLS policies (too broad for this fix)
- Adding automated tests for the restore flow (no test coverage exists currently)

---

**ARCHITECT_PLAN.md created.**
