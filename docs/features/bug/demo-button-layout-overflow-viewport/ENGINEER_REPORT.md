# ENGINEER_REPORT — bug/demo-button-layout-overflow-viewport

## Feature Slug

`bug/demo-button-layout-overflow-viewport`

## Feature Title

`_buildContentCluster`'s half-height `SizedBox` intermittently overflows by 173px in tests when the demo button is visible

## Cycle Number

1

## Goal

Fix the deterministic layout overflow in `LoginScreen._buildContentCluster()` where the logo's unconstrained intrinsic height plus the demo button and spacers can exceed the `availableHeight / 2` budget at compact viewports, and add a regression test that reproduces the worst case deterministically.

## Architect Tasks Completed

1. Wrapped `_buildLogo(logoWidth: logoWidth)` in `Flexible(child: ...)` inside the inner `Column` under `SizedBox(height: availableHeight / 2)` in `_buildContentCluster()`. No other lines in that Column changed.
2. Updated the `_buildContentCluster` docstring's "Layout contract" bullets to reflect that the logo + demo button now share the top-half budget and that the logo shrinks via `BoxFit.contain` under pressure.
3. Appended `'Test C: content cluster fits within 800×600 without RenderFlex overflow (button visible)'` to `test/features/auth/login_screen_demo_button_test.dart`, following the plan's exact recipe: `tester.view.physicalSize`/`devicePixelRatio` set with matching `addTearDown` resets, same widget tree as Tests A/B, `precacheImage` inside `tester.runAsync`, `pumpAndSettle()`, then `expect(tester.takeException(), isNull)`. Tests A and B left unmodified.
4. Ran `flutter analyze` on both changed files — no issues.
5. Ran `flutter test test/features/auth/login_screen_demo_button_test.dart` — all 3 tests pass. Ran 20-iteration stability loops against `--plain-name "Test C"` and `--plain-name "Test B"` — 20/20 pass in both loops.

## Files Created

None.

## Files Modified

- `lib/features/auth/login_screen.dart`
- `test/features/auth/login_screen_demo_button_test.dart`

## Analyzer Results

`flutter analyze lib/features/auth/login_screen.dart test/features/auth/login_screen_demo_button_test.dart` → "No issues found!"

## Test Results

- `flutter test test/features/auth/login_screen_demo_button_test.dart` → `+3` all tests passed (Test A, Test B, Test C).
- 20-iteration loop, `--plain-name "Test C"` → 20/20 passed, 0 failures logged.
- 20-iteration loop, `--plain-name "Test B"` → 20/20 passed, 0 failures logged.

## Code Efficiency/Bloat Check

- No new helper, extension, util, or private widget class was introduced; the fix is a single `Flexible` wrap around an existing call, using a built-in Flutter widget.
- No existing-helper search was needed since no new abstraction was created.
- No `_buildX()` methods added or touched beyond the required docstring/line edit.
- File size: `login_screen.dart` and the test file remain within their prior line-count territory (net deltas below); no target exceeded.

## Verification (manual steps performed)

- Read the diff hunks in full after edit to confirm only the intended `Column` child and docstring lines changed, and that `mainAxisAlignment`, the demo-button block, and trailing spacer were untouched.
- Confirmed via `git diff --numstat` that the diff touches only the two files the plan lists.
- Confirmed via `dart format` (files-scoped) that formatting is unchanged (0 files reformatted).
- Did not run the app on any platform — Tier 1 (QA gate) is mechanical only per the plan; Tier 2 owner-run steps (macOS/iOS/Chrome resize checks) are explicitly Tony's punch list, not Engineer's.

## Deviations From Plan

- Change-budget line delta for `login_screen.dart` came out net **0** (4 added / 4 removed) rather than the plan's expected +2 to +4. This is because the `Flexible(child: ...)` wrap replaced the existing single-line `_buildLogo(...)` call in place (no new line added) and the docstring edit was a 3-line-for-3-line rewrite. No extra lines were needed to implement the minimal fix exactly as specified in Task 1; this is a tighter diff than estimated, not a scope deviation.
- Change-budget line delta for the test file came out net **+36** (36 added / 0 removed), slightly below the plan's +40 to +60 estimate. The appended `testWidgets` block implements every step in the plan's recipe (a)–(e) with no omissions; it is simply more compact than estimated. Per the plan's own Tier 1 check #6, an out-of-bounds line delta is a "warn," not a "fail" — flagging for QA awareness, not requesting an exception.

## Blockers Encountered

None.

## Ready For QA

Yes.
