# Engineer Report

## Feature Slug

`feature/play-store-demo-login`

## Feature Title

Play Store Demo Login

## Goal

Add a hidden easter egg to the login screen: tapping the BandRoadie logo 7 times triggers a `signInWithPassword` demo login, providing Google Play reviewers with static credentials to access the app without disrupting the existing magic-link flow for real users.

## Architect Tasks Completed

- [x] Task 1 — Create `lib/app/constants/demo_credentials.dart`
- [x] Task 2 — Modify `lib/features/auth/login_screen.dart` (all sub-tasks: import, state vars, dispose, `_handleLogoTap`, `_triggerDemoLogin`, `_buildLogo` GestureDetector, hint text in `_buildContentCluster`)
- [x] Task 3 — Update `dart_defines.json` (add `DEMO_PASSWORD: ""` placeholder)
- [x] Task 4 — Update `.env.example` (document `DEMO_PASSWORD`)
- [x] Task 5 — Update `run.sh` (add `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"`)
- [x] Task 6 — Update `tools/build_android.sh`, `tools/build_ios.sh`, `tools/build_web.sh`

## Files Created

- `lib/app/constants/demo_credentials.dart`

## Files Modified

- `lib/features/auth/login_screen.dart`
- `dart_defines.json`
- `.env.example`
- `run.sh`
- `tools/build_android.sh`
- `tools/build_ios.sh`
- `tools/build_web.sh`

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings

## Test Results

Not run (no existing tests cover login_screen.dart; Architect plan did not require new tests)

## Verification

Manual steps performed:

- Confirmed `lib/app/constants/demo_credentials.dart` created with amended credentials (`bandroadie2026@gmail.com`) per user instruction
- Confirmed `dart:async` import added before `dart:io` in `login_screen.dart`
- Confirmed `../../app/constants/demo_credentials.dart` import added after `auth_gate.dart`
- Confirmed `_logoTapCount` and `_logoTapResetTimer` state variables added
- Confirmed `_logoTapResetTimer?.cancel()` added to `dispose()` before `super.dispose()`
- Confirmed `_handleLogoTap()` and `_triggerDemoLogin()` methods added after `_initHintController()`
- Confirmed `_buildLogo()` wrapped with `GestureDetector(behavior: HitTestBehavior.opaque, onTap: _handleLogoTap)`
- Confirmed logo `SizedBox` in `_buildContentCluster` replaced with `Stack` + conditional hint text
- Confirmed `dart format` reports 0 changes (already clean)
- Confirmed `flutter analyze` returns 0 issues

## Deviations From Architect Plan

**1. Working tree not clean at Phase 1**
The working tree had pre-existing unrelated modifications (ios/Runner.xcodeproj, lib/features/financials, lib/features/lyrics, lib/main.dart, pubspec.yaml, web/version.json). The user explicitly directed implementation to proceed; this deviation is noted only.

**2. Demo credentials amended per user instruction**
`kDemoEmail` is `'bandroadie2026@gmail.com'` (not `'demo@bandroadie.com'` as in the Architect plan). The comment header was also updated accordingly. All other credentials logic is identical.

**3. `tools/gen_dart_defines.sh` not modified (unlisted)**
`gen_dart_defines.sh` generates `dart_defines.json` for iOS builds from `.env` but does not include `DEMO_PASSWORD`. It is not in the Architect plan's file list and was not modified. Mitigation: `build_ios.sh` now passes `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"` explicitly on both `flutter build` commands, which takes precedence over `--dart-define-from-file`, ensuring the real value from `.env` is always used at build time. Tony should also update `gen_dart_defines.sh` in a follow-up to keep `dart_defines.json` in sync.

## Blockers Encountered

None

## Ready For QA

Yes — pending Tony completing the database seeding prerequisites listed in the Architect plan (demo account creation in Supabase Auth, user profile row, band membership for The Banana Stand) and setting `DEMO_PASSWORD` in `.env`.
