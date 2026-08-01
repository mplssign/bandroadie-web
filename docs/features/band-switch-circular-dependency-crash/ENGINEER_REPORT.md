# Engineer Report

## Feature Slug

bug/band-switch-circular-dependency-crash

## Feature Title

Band switch circular dependency crash

## Goal

Remove the redundant derived-provider invalidation that causes Riverpod's `CircularDependencyError` during band switching, while preserving the rest of the existing band switch flow.

## Architect Tasks Completed

- [x] Task 1 - Removed `ref.invalidate(displayBandProvider);` from `ActiveBandNotifier.selectBand()`.
- [x] Task 2 - Kept active band update, permissions refresh, selected setlist clear, dashboard tab navigation, and persistence behavior intact.
- [x] Task 3 - Confirmed no other manual invalidation of `displayBandProvider` exists in current `lib` sources.
- [ ] Task 4 - Analyzer validation completed; local manual band-switch reproduction was not executed in this session.

## Files Created

- docs/features/band-switch-circular-dependency-crash/ENGINEER_REPORT.md

## Files Modified

- lib/features/bands/active_band_controller.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 1 info (`use_build_context_synchronously` at `lib/features/setlists/setlist_detail_screen.dart:1449:32`), unrelated to this change.

## Test Results

Not run (not required by Architect plan)

## Verification

Manual steps performed:

- Verified branch is `bug/band-switch-circular-dependency-crash`.
- Verified non-clean tree was only expected untracked docs/sql test artifacts.
- Confirmed the only functional code edit in scope was removal of the `displayBandProvider` invalidation line.
- Ran `flutter analyze` and confirmed 0 analyzer errors.

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes
