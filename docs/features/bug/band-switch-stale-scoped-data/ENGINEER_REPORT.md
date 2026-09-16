# ENGINEER_REPORT — bug/band-switch-stale-scoped-data

## Feature Slug

`bug/band-switch-stale-scoped-data`

## Feature Title

Band switching throws an unhandled `CircularDependencyError` on every single
switch (from `ActiveBandNotifier.selectBand()`)

## Cycle Number

2 (retry — Cycle 1's `ENGINEER_REPORT.md` claimed the production edit was
applied and tests passed, but Manager verified the file on disk still had
both `ref.invalidate(currentUserPermissionsProvider);` lines unchanged. This
cycle re-applies the edit and explicitly re-reads the file from disk after
editing, before writing this report.)

## Goal

Delete the two synchronous `ref.invalidate(currentUserPermissionsProvider)`
calls in `selectBand()` and `reset()` that trip Riverpod's
`CircularDependencyError` guard. The regression test from Cycle 1 already
exists on disk; verify it still matches the plan's spec.

## Architect Tasks Completed

1. Deleted `ref.invalidate(currentUserPermissionsProvider);` from
   `selectBand()` (was line 338).
2. Deleted `ref.invalidate(currentUserPermissionsProvider);` from
   `reset()` (was line 485), along with the blank line left orphaned above
   the closing brace.
3. Left the `import '../members/permissions/band_permissions_provider.dart';`
   line untouched — still required by the remaining invalidate call inside
   `loadAndSelectBand()`'s `Future.microtask` block (now at line 387).
4. Re-read
   [test/features/bands/active_band_controller_circular_dependency_test.dart](../../../test/features/bands/active_band_controller_circular_dependency_test.dart)
   (already present on disk from Cycle 1) against the plan's Case A / Case B
   spec — it matches exactly (same `_SeededActiveBandNotifier`, same
   `currentUserPermissionsProvider` override watching `activeBandIdProvider`,
   same `fireImmediately: true` forced listen, same assertions on both
   `selectBand` and `reset`). No changes made to it.
5. Ran `flutter analyze` and the Tier 1 Verification Plan test commands, and
   **re-read the edited file from disk** (plus a whole-file `grep` for the
   literal invalidate string) to positively confirm the edit landed before
   writing this report.

## Files Created

None this cycle — the regression test file already existed on disk from
Cycle 1 and required no changes.

## Files Modified

- [lib/features/bands/active_band_controller.dart](../../../lib/features/bands/active_band_controller.dart)
  — 2 line deletions plus the now-blank line left orphaned in `reset()`
  (net **−3** lines per `git diff`). No other lines touched.

## Disk Verification (post-edit re-read)

After applying the edit, re-read both edited regions directly from disk and
ran:

```
grep -n "ref.invalidate(currentUserPermissionsProvider)" lib/features/bands/active_band_controller.dart
```

Output:

```
387:        ref.invalidate(currentUserPermissionsProvider);
```

Only one match remains — the `loadAndSelectBand()` microtask call the plan
explicitly says to leave untouched. Both target lines (previously ~338 and
~485) are confirmed gone from the file on disk, and the surrounding bodies
of `selectBand()` and `reset()` match the plan's expected post-edit snippets
verbatim.

## Analyzer Results

`flutter analyze lib/features/bands/active_band_controller.dart
test/features/bands/active_band_controller_circular_dependency_test.dart`
→ **No issues found.**

## Test Results

- `flutter test test/features/bands/active_band_controller_circular_dependency_test.dart
  test/features/bands/active_band_controller_invalidation_test.dart` →
  **All 5 tests passed** (T1-B and T1-C).
- `flutter test test/features/` (T1-D) → **150 tests, 146 passed, 4 failed.**
  All 4 failures are in
  [test/features/bands/band_currency_picker_test.dart](../../../test/features/bands/band_currency_picker_test.dart),
  a file this change did not touch (confirmed via `git diff --name-only`
  showing only `active_band_controller.dart` modified). These failures are
  data-cardinality assertions about currency picker groupings, unrelated to
  `ActiveBandNotifier`/`CircularDependencyError`, and pre-exist this change.
  `invite_screen_test.dart` and `auth_gate_anonymous_recovery_test.dart`
  (called out in the plan as also exercising the notifier) both passed.

## Code Efficiency/Bloat Check

- No new helpers, extensions, or private widget classes added this cycle —
  only line deletions in production code, and no changes to the existing
  test file.
- Re-verified (did not need to search for a new pattern): the existing
  regression test reuses the `_SeededActiveBandNotifier` / band-fixture
  shape from the sibling
  [active_band_controller_invalidation_test.dart](../../../test/features/bands/active_band_controller_invalidation_test.dart)
  per the plan — no separate helper exists, none was added.
- Bug fix is a pure deletion (3 lines removed, 0 added in production code) —
  root cause was two lines of dead-on-arrival code, not a missing check, so
  a pure-deletion fix is correct here.

## Verification (manual steps performed)

- Read the exact `selectBand()` and `reset()` regions before editing to
  confirm the two target lines matched the plan's description precisely.
- Applied the deletions, then **re-read both regions from disk** and ran a
  whole-file `grep` for the literal invalidate string, confirming the edit
  actually persisted (see Disk Verification above) — this is the specific
  check the Cycle 1 retry notice called out as missing.
- Ran `flutter analyze` scoped to touched files → no issues.
- Ran the regression test in isolation and alongside the sibling
  invalidation test → all 5 passed.
- Ran the full `test/features/` suite → 146/150 passed; the 4 failures are
  pre-existing and unrelated (see Test Results).
- Ran `dart format lib/features/bands/active_band_controller.dart` →
  `Formatted 1 file (0 changed)`.
- Ran `git diff --stat` → `lib/features/bands/active_band_controller.dart |
  3 ---` (1 file changed, 3 deletions(-), 0 insertions).
- Ran `git status --porcelain` →
  `M lib/features/bands/active_band_controller.dart`,
  `?? docs/features/bug/band-switch-stale-scoped-data/`,
  `?? test/features/bands/active_band_controller_circular_dependency_test.dart`
  (the latter two are the expected pre-existing untracked items; no other
  files touched).
- Owner-run device checks (CRASH-1 through CRASH-5, FIN-1) were not
  performed — per the plan these require a physical device and are Tony's
  responsibility, not Engineer's or QA's.

## Deviations From Plan

None.

## Blockers Encountered

None.

## Ready For QA

Yes.
