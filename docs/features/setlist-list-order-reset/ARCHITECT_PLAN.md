# Architect Plan: Fix Setlist List Order Reverting to Alphabetical

## Feature Slug

`bug/setlist-list-order-reset`

## Problem Summary

Users can drag-to-reorder their setlists on the Setlists tab. The drag correctly persists to the database via the `reorder_setlists` RPC, which updates the `position` column. However, the custom order does not stick — it silently reverts to alphabetical sorting on the next fetch (tab revisit, pull-to-refresh, app restart). This is a regression of a previously-working feature that is part of the standard post-deploy smoke test checklist.

## Root Cause

**Confidence: HIGH** — Confirmed by direct code observation and production database inspection.

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

## Additional Findings — Production Database Evidence

**Critical constraint violation discovered via direct Supabase inspection (project `nekwjxvgbveheooyorjo`):**

The `setlists.position` column has no `NOT NULL` constraint, no uniqueness constraint, and defaults to `0`. This creates a widespread tie condition that makes naive position-based ordering unreliable:

- **799 of 898 setlists (89%)** in production are at `position = 0` (the default)
- Any band that hasn't manually reordered setlists will have all setlists tied at position 0
- When positions are tied, PostgreSQL returns results in an unstable, insertion-order-dependent sequence

**Why the Catalog's position is never reliably set:**

1. **The `ensure_catalog_setlist` RPC** (called during fetch to create/maintain the Catalog) never writes the `position` column — it only ensures the row exists with `is_catalog = true` and `name = 'Catalog'`

2. **The `reorderSetlists` function** in `setlists_screen.dart` (line 273) explicitly filters out the Catalog before calling the `reorder_setlists` RPC:
   ```dart
   final nonCatalog = state.setlists.where((s) => !s.isCatalog).toList();
   final ids = nonCatalog.map((s) => s.id).toList();
   await _repository.reorderSetlists(bandId: bandId, setlistIdsInOrder: ids);
   ```

3. **The `reorder_setlists` RPC** (migration `20260804200000_reorder_setlists_rpc.sql`, line 62) comments that "position 0 is reserved for Catalog" but never enforces this — it only updates the positions of the setlist IDs passed to it (which exclude the Catalog)

**Verified example:** Band `c4a975df-9736-434b-b1d0-e2522742632b` has 7 setlists (including Catalog), all at `position = 0`. A query with `ORDER BY position ASC` returns the Catalog in slot 2 of 7, not slot 1.

**Consequence:** Simply removing client-side sorting when `hasPositionColumn == true` (as the original plan proposed) would cause the Catalog to appear in an arbitrary position for 89% of bands, breaking the fundamental invariant that the Catalog always appears first.

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

Make the final sort conditional on `hasPositionColumn`, with explicit Catalog-first enforcement and deterministic tiebreaking:

**When `hasPositionColumn == true`:**

- Always place Catalog first, regardless of its actual position value
- Sort remaining setlists by position ascending
- When positions are tied (common: 89% of production setlists are at position 0), fall back to alphabetical order for deterministic, stable results

**When `hasPositionColumn == false`:**

- Fall back to the legacy Catalog-first-then-alphabetical sort (unchanged)
- This is the correct behavior when the position column doesn't exist (pre-migration or degraded schema)

**Implementation:**
Replace the unconditional sort block (lines 499-504) with:

```dart
// Sort: conditional based on position column availability
if (hasPositionColumn) {
  // Position column exists — use three-tier sort:
  // 1. Catalog always first (regardless of its position value)
  // 2. Then by position ascending (respects manual reorder)
  // 3. Then alphabetically (deterministic tiebreak for default position = 0)
  setlists.sort((a, b) {
    // Catalog always first
    if (a.isCatalog != b.isCatalog) return a.isCatalog ? -1 : 1;
    // Then by position
    final posCompare = a.position.compareTo(b.position);
    if (posCompare != 0) return posCompare;
    // Then alphabetically (tiebreak when positions are equal/default)
    return a.name.compareTo(b.name);
  });
} else {
  // Position column missing — fall back to alphabetical sort
  setlists.sort((a, b) {
    if (a.isCatalog && !b.isCatalog) return -1;
    if (!a.isCatalog && b.isCatalog) return 1;
    return a.name.compareTo(b.name);
  });
}
```

**Why this works:**

1. **Catalog-first guarantee:** Explicitly checks `a.isCatalog != b.isCatalog` before position comparison, so Catalog always appears first even though it's stuck at position 0
2. **Respects manual reorder:** For bands that have used drag-to-reorder, their non-Catalog setlists have unique sequential positions (1, 2, 3...) from the RPC, so position comparison returns the correct order
3. **Stable for default-position bands:** For bands that have never reordered (89% of current data), all non-Catalog setlists are at position 0, so the tiebreak falls through to alphabetical order — which exactly reproduces the pre-fix visual behavior, preventing user-visible churn
4. **No database backfill required:** The three-tier sort logic naturally handles both reordered and non-reordered bands without needing to migrate legacy data

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

| File                                            | What changes                                                                                                                                                                                                            |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_repository.dart` | Replace unconditional alphabetical sort (lines 499-504) with conditional sort that respects `hasPositionColumn`. When `true`, trust database ordering. When `false`, apply legacy Catalog-first-then-alphabetical sort. |

## Files Off-Limits

| File                                                   | Reason                                                                |
| ------------------------------------------------------ | --------------------------------------------------------------------- |
| `lib/main.dart`                                        | Initialization order must not change (Guardrails §1)                  |
| `lib/features/setlists/setlists_screen.dart`           | Already confirmed correct — reorder logic works, not part of this bug |
| `lib/features/setlists/setlists_tab_content.dart`      | Already confirmed correct — reorder logic works, not part of this bug |
| `lib/features/setlists/new_setlist_screen.dart`        | Already confirmed correct — reorder logic works, not part of this bug |
| `lib/features/setlists/setlist_detail_screen.dart`     | Already confirmed correct — reorder logic works, not part of this bug |
| `lib/features/setlists/setlist_detail_controller.dart` | Already confirmed correct — reorder logic works, not part of this bug |
| `supabase/migrations/*.sql`                            | No database changes required                                          |
| Any RPC function                                       | `reorder_setlists` already works correctly                            |

## System Impact Map

| System                                 | Impact                                                 |
| -------------------------------------- | ------------------------------------------------------ |
| Setlists / Catalog                     | **affected** — fetch path now respects position column |
| Gigs                                   | unaffected — gigs reference setlists by ID, not order  |
| Rehearsals                             | unaffected                                             |
| Members / RBAC                         | unaffected                                             |
| Auth / Session                         | unaffected                                             |
| Routing                                | unaffected                                             |
| Platform (iOS / Android / Web / macOS) | unaffected — all platforms use same fetch path         |

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
  5. **The corrected fix affects 89% of bands in production** — any band that hasn't manually reordered setlists relies on the three-tier sort to keep Catalog first and results stable

**Why MEDIUM is appropriate (not HIGH):**

- The three-tier sort logic is explicit and deterministic — no edge cases or complex branching
- The alphabetical tiebreak reproduces the exact pre-fix visual behavior for the 89% of bands with default positions, so there's no user-visible churn for existing data
- For bands that have used manual reorder, their unique sequential positions (1, 2, 3...) ensure the position comparison returns the correct order without falling through to the tiebreak
- The fix is self-contained — no cross-feature dependencies or provider state changes

**Mitigation:**

- Explicit verification that `hasPositionColumn` is correctly set in all exception handler branches
- Explicit testing of both manually-reordered bands (unique positions) and never-reordered bands (all positions = 0)
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

2. **Verify Setlist model**
   - Confirm `Setlist.position` is a non-null `int` field (lib/features/setlists/models/setlist.dart)
   - Confirm it supports `.compareTo()` for numeric comparison
   - If position is nullable in the model, implement defensive null handling in the sort logic

3. **Implement three-tier conditional sort**
   - Replace lines 499-504 with the three-tier sort logic:
     - When `hasPositionColumn == true`: sort by (1) Catalog first, (2) position ascending, (3) name alphabetically
     - When `hasPositionColumn == false`: apply legacy Catalog-first-then-alphabetical sort (unchanged)
   - Preserve existing comment structure and debug logging context
   - Ensure the sort is stable and deterministic for all tie conditions

4. **Verify exception handler consistency**
   - Trace all branches that catch `PostgrestException` with code `'42703'` (column doesn't exist)
   - Confirm each branch that catches missing `position` column sets `hasPositionColumn = false`
   - Confirm the conditional sort will execute correctly in all branches

5. **Run static analysis**
   - Execute `flutter analyze` and confirm 0 errors
   - Verify no new lint warnings in modified file

6. **Generate implementation report**
   - Document all modified lines with before/after diffs
   - Confirm no other files were touched
   - Record any deviations from this plan (there should be none)

## Verification Plan

### Tier 1 — Pre-deployment (Client-side only)

**Test 1: Fetch with position column (modern schema) — manually reordered band**

```dart
// Manual verification in debug mode:
// 1. Open Setlists tab for a band that has used drag-to-reorder (positions are 0, 1, 2, 3...)
// 2. Verify debug log shows: "Query returned X setlists (is_catalog: true, position: true)"
// 3. Verify setlists display in user-defined order (not alphabetical)
// 4. Verify Catalog appears first
```

**Test 2: Fetch with position column (modern schema) — band with default positions**

```dart
// Manual verification in debug mode:
// 1. Create a new band or use a band that has never reordered setlists (all positions = 0)
// 2. Add multiple non-Catalog setlists with names that would sort differently than alphabetically (e.g., "Zebra Set", "Alpha Set", "Beta Set")
// 3. Open Setlists tab
// 4. Verify debug log shows: "Query returned X setlists (is_catalog: true, position: true)"
// 5. Verify Catalog appears first
// 6. Verify remaining setlists appear in alphabetical order ("Alpha Set", "Beta Set", "Zebra Set")
// 7. Close and reopen app, pull-to-refresh multiple times
// 8. Verify order remains stable (same alphabetical order every time — no Postgres tie-order churn)
```

**Test 3: Fetch without position column (fallback schema)**

```dart
// Manual verification requires temporary schema rollback (not safe for production):
// This test must be performed in a development environment only.
// Skip in production verification.
```

**Test 4: Recursive call idempotence**

```dart
// Manual verification in debug mode:
// 1. Delete all Catalogs for a test band (forces Catalog creation flow)
// 2. Open Setlists tab
// 3. Verify debug log shows recursive call: "No Catalog found - creating one"
// 4. Verify final list respects position order after recursive fetch
// 5. Verify Catalog appears first
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
