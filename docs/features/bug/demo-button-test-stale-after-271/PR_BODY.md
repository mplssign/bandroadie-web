## Summary

`test/features/auth/login_screen_demo_button_test.dart` Test A asserted the demo
button is always hidden (`findsNothing`), a contract from before PR #271 changed
`_kDemoBandVisible` from `false` to `!kIsWeb`. Since `flutter test` runs on the
non-web Dart VM, `_kDemoBandVisible` is `true` there, the button renders, and
Test A failed on every CI run.

This updates Test A to assert the behavior PR #271 actually intends for the
non-web target it runs under (`findsOneWidget`), with its description and an
inline comment updated to match. No shipping code changed — `_kDemoBandVisible`
stays `!kIsWeb` as PR #271 intended.

## Changes

- `test/features/auth/login_screen_demo_button_test.dart`: Test A description
  and assertion updated to reflect the non-web-visible contract. Test B
  (retired easter-egg guard), imports, and `setUpAll` untouched.

## Verification

- `flutter analyze` on the changed file: clean.
- `flutter test test/features/auth/login_screen_demo_button_test.dart`: 2/2 pass.
- Full `flutter test` suite: 275/275 pass, no regressions.
- QA independently re-ran all of the above and approved.

## Risk

LOW — test-only change, zero runtime/shipping behavior difference on any platform.
