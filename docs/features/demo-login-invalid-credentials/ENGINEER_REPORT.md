# Engineer Report

## Feature Slug

`bug/demo-login-invalid-credentials`

## Feature Title

Fix Demo Login Invalid Credentials on Web

## Goal

Add the missing `DEMO_PASSWORD` dart-define flag to the web deployment script so that demo login (7-tap gesture) works on `app.bandroadie.com`, enabling Play Store reviewers and testers to access the demo environment.

## Architect Tasks Completed

- [x] Task 1 — Add DEMO_PASSWORD to web build command
- [x] Task 2 — Add validation check for DEMO_PASSWORD

## Files Created

- none

## Files Modified

- `tools/deploy_web.sh`

## Analyzer Results

Command: `flutter analyze`  
Result: 0 errors / 4 info warnings (all pre-existing, unrelated to bash script changes)

Pre-existing warnings:

- `lib/features/setlists/new_setlist_screen.dart:984:13` — deprecated `onReorder`
- `lib/features/setlists/setlist_detail_screen.dart:1716:29` — deprecated `axisAlignment`
- `lib/features/setlists/setlist_detail_screen.dart:2295:23` — deprecated `onReorder`
- `lib/features/setlists/setlists_tab_content.dart:511:25` — deprecated `onReorder`

## Test Results

Not run — Architect plan does not require tests for build script changes, and no tests exist for `tools/deploy_web.sh`.

## Verification

Manual steps performed:

- Verified both changes applied correctly to `tools/deploy_web.sh`:
  - Line 81: Added DEMO_PASSWORD validation check
  - Line 251: Added `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD}"` flag to flutter build command
- Confirmed syntax follows existing pattern (trailing backslash, quote style, variable expansion)
- Confirmed no Dart code modified (only bash script)
- Ran `flutter analyze` to verify no new errors introduced

## Deviations From Architect Plan

None. Implemented both Task 1 (mandatory) and Task 2 (optional) exactly as specified.

## Blockers Encountered

None.

## Ready For QA

Yes.

**QA Instructions:**

1. Ensure `.env` contains valid `DEMO_PASSWORD` value matching the production Supabase demo account
2. Run preview deploy: `./tools/deploy_web.sh --preview`
3. Navigate to preview URL and tap logo 7 times
4. Verify demo login succeeds and loads demo band "The Banana Stand"
5. After preview verification, deploy to production: `./tools/deploy_web.sh`
6. Test demo login on `app.bandroadie.com`
7. Verify normal magic link auth still works (regression test)
