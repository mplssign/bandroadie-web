# Engineer Report

## Feature Slug

bug/band-switch-stale-avatar

## Feature Title

Band Switch Stale Avatar

## Goal

Ensure the header avatar color updates immediately when switching bands by forcing display-band provider re-evaluation in the active band selection flow.

## Architect Tasks Completed

- [x] Task 1 - Added provider invalidation in selectBand() after active band state update.
- [x] Task 2 - Ran flutter analyze and confirmed 0 errors.
- [x] Task 3 - Wrote this ENGINEER_REPORT.md and verified it exists on disk.

## Files Created

- docs/features/bug/band-switch-stale-avatar/ENGINEER_REPORT.md

## Files Modified

- lib/features/bands/active_band_controller.dart

## Code Change Details

Exact line changed:

- lib/features/bands/active_band_controller.dart:337
- Added line: ref.invalidate(displayBandProvider);

Full modified method body:

```dart
Future<void> selectBand(Band band) async {
  if (!state.userBands.any((b) => b.id == band.id)) {
    // Safety check: can't select a band user doesn't belong to
    return;
  }

  await _persistBandId(band.id);
  state = state.copyWith(activeBand: band);
  ref.invalidate(displayBandProvider);

  // Force permissions to re-fetch for the new band context
  ref.invalidate(currentUserPermissionsProvider);

  // Clear stale setlist selection so SetlistDetailNotifier doesn't attempt
  // to load a previous band's setlist under the new band context
  ref.read(selectedSetlistProvider.notifier).clear();

  // Navigate to Dashboard when switching bands
  ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);
}
```

## Analyzer Results

Command: flutter analyze

Output:

```text
Analyzing bandroadie...
No issues found! (ran in 3.9s)
```

Result: 0 errors, 0 warnings.

## Import / Scope Verification

Confirmed: displayBandProvider is defined in the same file as ActiveBandNotifier at lib/features/bands/active_band_controller.dart, so no import was required.

## Test Results

Not run (not required by Architect plan).

## Verification

Manual/code verification performed:

- Confirmed inserted invalidation line appears immediately after state = state.copyWith(activeBand: band);
- Confirmed selectBand() ordering remains unchanged otherwise.
- Confirmed analysis passes with no issues.

## Deviations From Architect Plan

- Proceeded despite pre-existing untracked paths in the working tree, based on explicit user authorization in this session to continue without staging or committing those paths.

## Blockers Encountered

None.

## Ready For QA

Yes.
