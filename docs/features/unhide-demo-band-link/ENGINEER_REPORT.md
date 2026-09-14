# Engineer Report

## Feature Slug

`unhide-demo-band-link`

## Feature Title

Unhide the "Check out the demo band" link on the login screen

## Cycle Number

1

## Goal

Make the existing login-screen demo entry point visible on every Flutter target
without changing its interaction, layout, lifecycle, or backend behavior.

## Architect Tasks Completed

1. Replaced the stale visibility warning with the current bounded-capacity note.
2. Changed `_kDemoBandVisible` from `!kIsWeb` to `true` while preserving the const and call-site gate.
3. Updated only Test A's description to state the all-platform contract.
4. Updated only Test A's inline comment; its `findsOneWidget` assertion is unchanged.
5. Added DECISION-007 covering all-platform visibility, the native-only pre-init purge, capacity controls, rate-limiting tradeoff, and feature slug.

## Files Created

- `docs/features/unhide-demo-band-link/ENGINEER_REPORT.md`

## Files Modified

- `lib/features/auth/login_screen.dart`
- `test/features/auth/login_screen_demo_button_test.dart`
- `docs/reference/general/AI_DECISIONS.md`

## Analyzer Results

- `flutter analyze lib/features/auth/login_screen.dart test/features/auth/login_screen_demo_button_test.dart`: clean, no issues.
- `flutter analyze`: clean, no issues.
- Final post-format changed-file analysis: clean, no issues.
- `dart fix --dry-run`: nothing to fix.

## Test Results

- `flutter test test/features/auth/login_screen_demo_button_test.dart`: 5 passed, 0 failed.
- `flutter test`: 322 passed, 0 failed.
- Final post-format focused run: 5 passed, 0 failed.

## Code Efficiency/Bloat Check

The change adds no helpers, extensions, utilities, widgets, providers, dependencies,
or dead code; an existing-helper search was therefore not applicable. The touched
`login_screen.dart` already exceeds the 500-line target, but this scoped change
reduces it by two net lines and the plan forbids structural changes elsewhere in
the file.

## Verification (manual steps performed)

- Reviewed the full scoped diff and confirmed only the plan-listed implementation files changed.
- Confirmed `const bool _kDemoBandVisible = true;` and the unchanged `if (_kDemoBandVisible)` call-site gate.
- Confirmed the unrelated `_sendMagicLink` `kIsWeb` branch remains present and untouched.
- Confirmed Test A has no stale `!kIsWeb` wording and its assertion is unchanged.
- Confirmed DECISION-007 contains all four required decision points.
- Ran `dart format` only on the two changed Dart files; both were already formatted.
- Tier 2 runtime smoke checks were not performed because the plan assigns them to Tony.

## Deviations From Plan

None.

## Blockers Encountered

None.

## Ready For QA

Ready For QA: Yes