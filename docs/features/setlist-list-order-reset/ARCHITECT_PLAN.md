# Architect Plan: Fix Setlist List Order Reverting to Alphabetical

## Feature Slug
`bug/setlist-list-order-reset`

## Problem Summary
Users can drag-to-reorder their setlists on the Setlists tab. The drag correctly persists to the database via the `reorder_setlists` RPC, which updates the `position` column. However, the custom order does not stick — it silently reverts to alphabetical sorting on the next fetch (tab revisit, pull-to-refresh, app restart). This is a regression of a previously-working feature that is part of the standard post-deploy smoke test checklist.

## Root Cause
**Confidence: HIGH** — Confirmed by direct code observation.

In `lib/features/setlists/setlist_repository.dart`, method `_fetchSetlistsForBandInternal()`:

1. The query correctly orders by `.order('position', ascending: true)` (line 282) when the `position` column exists
2. A local boolean `hasPositionColumn` (declared line 269, initialized to `true`) tracks whether the position column is available
3. Multiple exception handlers (lines 287-340) correctly set `hasPositionColumn = false` when the position column is missing (pre-migration or degraded schema)
4. **BUT**: An unconditional final sort (lines 499-504) discards the position-based ordering on every call:

```dart
// Sort: Catalog first, then alphabetically
setlists.sort((a, b) {
  if (a.isCatalog && !b.isCatalog) return -1;
  if (!a.isCatalog && b.isCatalog) return 1;
  return a.name.compareTo(b.name);  // ← destroys position order
});
```

This is legacy sort logic that predates the position-based manual-reorder feature (added August 2026 via migration `20260804200000_reorder_setlists_rpc.sql`) and was never gated behind `hasPositionColumn` when that feature was added.

## Reference Docs Consulted
- `docs/agents/PROJECT_CONTEXT.md` — confirmed "setlist reorder" is part of post-deploy smoke test checklist (line 301)
- `docs/agents/GUARDRAILS.md` — reviewed file size constraints and change discipline
- `.github/copilot-instructions.md` — reviewed repository pattern and RPC usage

No domain-specific reference docs exist for setlist reordering.

## Existing System Analysis

**Current behavior — fetch path:**
1. `SetlistsNotifier.loadSetlists()` calls `SetlistRepository.fetchSetlistsForBand()`
2. Repository calls `_fetchSetlistsForBandInternal(bandId, depth: 0)`
3. Method queries Supabase with `.order('position', ascending: true)` when position column exists
4. Exception handlers set `hasPositionColumn = false` if position column is missing
5. **Unconditional alphabetical sort executes regardless of `hasPositionColumn` value** (lines 499-504)
6. Returns list to UI, which displays alphabetically-sorted setlists despite database containing correct position values

**Current behavior — reorder path (already correct):**
1. User drags setlist in `SetlistsTabContent` or `SetlistsScreen`
2. UI calls `SetlistsNotifier.reorderLocal(oldIndex, newIndex)` — updates local state
3. UI calls `SetlistsNotifier.persistReorder()` — calls `SetlistRepository.reorderSetlists()`
4. Repository invokes `reorder_setlists` RPC with array of setlist IDs in new order
5. RPC atomically updates `setlists.position` for all provided IDs (starting at position 1; position 0 is reserved for Catalog)
6. Returns success — UI remains in reordered state

**The disconnect:** The reorder path correctly writes position values to the database. The fetch path correctly reads them from the database. But the fetch path then throws away the position order with an unconditional alphabetical sort before returning to the UI.

## Proposed Solution

Make the final sort conditional on `hasPositionColumn`:

**When `hasPositionColumn == true`:**
- Trust the database ordering (which is already position-based via `.order('position', ascending: true)`)
- Do not re-sort client-side
- The Catalog already has position 0, so it naturally appears first

**When `hasPositionColumn == false`:**
- Fall back to the legacy Catalog-first-then-alphabetical sort
- This is the correct behavior when the position column doesn't exist (pre-migration or degraded schema)

**Implementation:**
Replace the unconditional sort block (lines 499-504) with:

```dart
// Sort: conditional based on position column availability
if (hasPositionColumn) {
  // Position column exists — trust database ordering
  // (already sorted by position via .order('position', ascending: true))
  // Catalog is at position 0, so it's already first
} else {
  // Position column missing — fall back to alphabetical sort
  setlists.sort((a, b) {
    if (a.isCatalog && !b.isCatalog) return -1;
    if (!a.isCatalog && b.isCatalog) return 1;
    return a.name.compareTo(b.name);
  });
}
```

This is the minimal change that fixes the root cause without introducing new abstractions or refactoring the 4,027-line repository file.

## Database Impact
**Not applicable** — no migrations, RLS policies, RPCs, or triggers are modified.

The `position` column already exists in the `setlists` table (added in migration `20260804200000_reorder_setlists_rpc.sql`). The `reorder_setlists` RPC already works correctly. This fix only changes the client-side fetch path to respect the database ordering.

## Flutter Architecture Changes

**State:**
- No changes — `SetlistsNotifier` and `SetlistsState` are unaffected

**Widgets:**
- No changes — `SetlistsTabContent`, `SetlistsScreen`, and all setlist UI components are unaffected

**Repositories:**
- `SetlistRepository._fetchSetlistsForBandInternal()` — modify final sort logic to respect `hasPositionColumn` flag

## Files to Create
**None**

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/setlists/setlist_repository.dart` | Replace unconditional alphabetical sort (lines 499-504) with conditional sort that respects `hasPositionColumn`. When `true`, trust database ordering. When `false`, apply legacy Catalog-first-then-alphabetical sort. |

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/main.dart` | Initialization order must not change (Guardrails §1) |
| `lib/features/setlists/setlists_screen.dart` | Already confirmed correct — reorder logic works, not part of this bug |
| `lib/features/setlists/setlists_tab_content.dart` | Already confirmed correct — reorder logic works, not part of this bug |
| `lib/features/setlists/new_setlist_screen.dart` | Already confirmed correct — reorder logic works, not part of this bug |
| `lib/features/setlists/setlist_detail_screen.dart` | Already confirmed correct — reorder logic works, not part of this bug |
| `lib/features/setlists/setlist_detail_controller.dart` | Already confirmed correct — reorder logic works, not part of this bug |
| `supabase/migrations/*.sql` | No database changes required |
| Any RPC function | `reorder_setlists` already works correctly |

## System Impact Map

| System | Impact |
|--------|--------|
| Setlists / Catalog | **affected** — fetch path now respects position column |
| Gigs | unaffected — gigs reference setlists by ID, not order |
| Rehearsals | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Platform (iOS / Android / Web / macOS) | unaffected — all platforms use same fetch path |

## Regression Risk
**MEDIUM**

**Rationale:**
- This is a single-method, single-block change in the fetch path
- The change is behind a conditional that explicitly handles both cases (position column present vs. absent)
- No state management, routing, or auth logic is touched
- Risk is elevated because:
  1. `setlist_repository.dart` is 4,027 lines — large surface area for regressions
  2. This is a regression of a previously-working feature that is part of the post-deploy smoke test
  3. The fetch path is shared across all setlist UI contexts (tab, detail screen, new setlist modal)
  4. Multiple recursive calls (`depth + 1`) go through the same method — must verify the fix is idempotent across all call depths

**Mitigation:**
- Explicit verification that `hasPositionColumn` is correctly set in all exception handler branches
- Explicit testing of recursive call scenarios (Catalog deduplication, missing Catalog, metadata update)
- Pre-deployment validation on all platforms (iOS, Android, macOS, Web)
- Post-deployment smoke test must explicitly verify setlist reorder persists across app restart

## Engineer Task Breakdown

Execute in strict order:

1. **Verify current state**
   - Confirm `_fetchSetlistsForBandInternal()` method starts at line 220
   - Confirm `hasPositionColumn` declaration at line 269
   - Confirm unconditional sort block at lines 499-504
   - Confirm all exception handlers that set `hasPositionColumn = false` (lines 287-340)

2. **Implement conditional sort**
   - Replace lines 499-504 with conditional sort logic
   - When `hasPositionColumn == true`: do not sort (trust database order)
   - When `hasPositionColumn == false`: apply legacy Catalog-first-then-alphabetical sort
   - Preserve existing comment structure and debug logging context

3. **Verify exception handler consistency**
   - Trace all branches that catch `PostgrestException` with code `'42703'` (column doesn't exist)
   - Confirm each branch that catches missing `position` column sets `hasPositionColumn = false`
   - Confirm the conditional sort will execute correctly in all branches

4. **Run static analysis**
   - Execute `flutter analyze` and confirm 0 errors
   - Verify no new lint warnings in modified file

5. **Generate implementation report**
   - Document all modified lines with before/after diffs
   - Confirm no other files were touched
   - Record any deviations from this plan (there should be none)

## Verification Plan

### Tier 1 — Pre-deployment (Client-side only)

**Test 1: Fetch with position column (modern schema)**
```dart
// Manual verification in debug mode:
// 1. Open Setlists tab
// 2. Verify debug log shows: "Query returned X setlists (is_catalog: true, position: true)"
// 3. Verify debug log does NOT show alphabetical sort being applied
// 4. Verify setlists display in user-defined order (not alphabetical)
```

**Test 2: Fetch without position column (fallback schema)**
```dart
// Manual verification requires temporary schema rollback (not safe for production):
// This test must be performed in a development environment only.
// Skip in production verification.
```

**Test 3: Recursive call idempotence**
```dart
// Manual verification in debug mode:
// 1. Delete all Catalogs for a test band (forces Catalog creation flow)
// 2. Open Setlists tab
// 3. Verify debug log shows recursive call: "No Catalog found - creating one"
// 4. Verify final list respects position order after recursive fetch
```

### Tier 2 — Post-deployment (Production validation)

**Test 1: Position persistence across app lifecycle**
```sql
-- Verify position column values are preserved in database
SELECT id, name, position, is_catalog
FROM setlists
WHERE band_id = '<test-band-uuid>'
ORDER BY position ASC NULLS LAST;

-- Expected: Catalog has position 0, other setlists have sequential positions
```

**Test 2: End-to-end reorder + fetch cycle**
```
Manual UI flow:
1. Open Setlists tab
2. Drag setlist from position 2 to position 5
3. Observe immediate UI update
4. Pull-to-refresh
5. Verify order persists (setlist remains at position 5)
6. Close app completely
7. Reopen app and navigate to Setlists tab
8. Verify order still persists (setlist remains at position 5)
```

**Test 3: Cross-platform consistency**
```
Repeat Test 2 on:
- iOS (physical device or simulator)
- Android (physical device or emulator)
- macOS (desktop app)
- Web (Chrome, incognito mode)

Expected: Order persists across all platforms
```

**Test 4: Multi-catalog deduplication path**
```
This test requires creating duplicate Catalogs (not safe for production).
Skip unless in controlled test environment.
```

## QA Regression Areas

QA must explicitly test:

1. **Primary fix validation:**
   - Drag-reorder setlists on Setlists tab
   - Verify order persists after pull-to-refresh
   - Verify order persists after app restart
   - Verify order persists when switching between bands

2. **Catalog positioning:**
   - Verify Catalog always appears first in list
   - Verify Catalog cannot be dragged/reordered (if this constraint exists)

3. **Alphabetical fallback (if testable):**
   - If a development environment with no position column is available, verify setlists sort alphabetically (Catalog first)

4. **Cross-platform consistency:**
   - Test reorder persistence on iOS, Android, macOS, and Web

5. **Multi-setlist operations:**
   - Create new setlist — verify it appears in correct position (last, after existing setlists)
   - Delete a setlist — verify remaining setlists maintain order
   - Rename a setlist — verify alphabetical name change does not reorder list

6. **Recursive fetch scenarios:**
   - If possible in test environment: trigger Catalog deduplication by creating duplicate Catalogs, verify order persists after cleanup

## Rollout / Migration Strategy
Not applicable — no database migration required. This is a client-side fix only.

**Deployment:**
1. Merge PR to `main`
2. Run `./tools/deploy_web.sh` to deploy web app
3. Web users get fix immediately on next page load
4. Native app users (iOS/Android/macOS) get fix in next app release

**Rollback:**
If the fix causes regressions, revert the commit and redeploy. No database state needs to be restored.

## Out of Scope

Explicitly not included in this fix:

- Refactoring `setlist_repository.dart` (4,027 lines) — per PROJECT_CONTEXT.md, avoid adding to this file
- Adding position column to database — already exists
- Modifying `reorder_setlists` RPC — already works correctly
- Adding unit tests for `SetlistRepository` — test infrastructure exists but coverage is minimal, not required for this fix
- Optimizing setlist fetch performance — not part of this bug
- Changing Catalog positioning logic (position 0) — already correct
- UI/UX changes to drag handle or reorder animation — already correct
- Adding position indicators to setlist cards — not requested
