# Engineer Report

## Feature Slug
bug/band-switch-avatar-stale

## Feature Title
Band switch nav bar avatar intermittently shows stale (previous band's) image

## Goal
Reorder `selectBand()` in `ActiveBandNotifier` so the UI-visible state mutation (and `displayBandProvider` invalidation) happens synchronously before the `_persistBandId` disk write, closing the async gap that let the header render the previous band's avatar for one or more frames after a switch.

## Architect Tasks Completed
- [x] Task 1 — Moved `await _persistBandId(band.id);` from the first line of `selectBand()` to the last statement in the method, after `ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);`. No other line reordered or modified.
- [x] Task 2 — Ran `flutter analyze`: 0 errors, 0 warnings.
- [x] Task 3 — No other file touched; §11 off-limits list respected.

## Files Created
- none

## Files Modified
- `lib/features/bands/active_band_controller.dart`

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings

## Test Results
Not run (Architect plan did not require it; no existing test covers `selectBand()` ordering).

## Verification
Manual steps performed:
- Read the exact `selectBand()` body before editing and confirmed it matched the Architect plan's §3.2 code excerpt verbatim.
- Applied the single statement move via `Edit`, then re-read the resulting `git diff` and confirmed it contains exactly one line removed (`await _persistBandId(band.id);` in its original position) and one line added (the same statement, now last), with no other line touched.
- Ran `dart format lib/features/bands/active_band_controller.dart` — 0 files changed, confirming no incidental formatting drift.
- Confirmed `await` keyword and `async` signature on `selectBand()` are unchanged.
- Did not perform Tier 2 (live-build/manual UI) verification — that is QA's responsibility per the plan's rollout strategy (§17).

## Deviations From Architect Plan
None.

## Blockers Encountered
None.

## Ready For QA
Yes
