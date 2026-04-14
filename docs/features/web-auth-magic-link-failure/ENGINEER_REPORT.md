# Engineer Report

## Feature Slug
bug/web-auth-magic-link-failure

## Feature Title
Web magic link auth fails with "Unregistered API key" and "Invalid Link" for some users

## Goal
Migrate web auth from implicit flow to PKCE to prevent email security scanners from consuming magic link tokens before users click them, add defensive cache headers for index.html and flutter_service_worker.js to prevent stale build serving, and improve the missing_token error message to explain the scanner issue to affected users.

## Architect Tasks Completed
- [x] Task 7 — Changed `authFlowType` from `kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce` to `AuthFlowType.pkce`
- [x] Task 8 — Updated comment on lines 62-64 to reflect PKCE for all platforms with code_verifier explanation
- [x] Task 9 — Updated `missing_token` case: icon color changed from red to orange, message updated to explain email scanner issue
- [x] Task 11 — Added no-cache headers for `/index.html` and `/flutter_service_worker.js` in web/vercel.json
- [x] Task 12 — Updated Platform Differences table: web auth flow row changed from `Implicit (detectSessionInUri: true)` to `PKCE (as of 2026-04-14 — was implicit)`
- [x] Task 13 — Added DECISION-001 entry documenting the implicit → PKCE migration
- [N/A] Tasks 1–6 — voided: credentials come from local .env via tools/deploy_web.sh, Vercel env vars not applicable
- [N/A] Task 10 — voided: tools/build_web.sh is a dead script, not used in any build process

## Files Created
none

## Files Modified
- lib/main.dart
- lib/features/auth/auth_confirm_screen.dart
- web/vercel.json
- docs/reference/general/RUNTIME_CONFIG.md
- docs/reference/general/AI_DECISIONS.md

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors / 0 warnings — "No issues found!"

## Test Results
Not run

## Verification
Manual steps performed:
- Verified `kIsWeb` import is still used by other references in main.dart (detectSessionInUri, Firebase init, URL strategy, marketing host checks)
- Verified initialization order in main.dart is unchanged — only authFlowType value and comment were modified
- Verified auth_confirm_screen.dart missing_token case matches plan exactly (orange icon, scanner explanation message)
- Verified vercel.json is valid JSON structure with new headers inserted after /version.json block
- Verified RUNTIME_CONFIG.md Platform Differences table row updated correctly
- Verified AI_DECISIONS.md DECISION-001 entry matches plan content
- `dart format` confirmed both modified Dart files required no formatting changes

## Deviations From Architect Plan
- Tasks 1–6 and Task 10 voided per Manager correction (see prompt header)
- Tasks 14–16 (flutter clean, flutter pub get, local web build) not executed — these are validation/QA tasks requiring credentials; flutter analyze passed cleanly

## Blockers Encountered
- Branch `bug/web-auth-magic-link-failure` did not exist; created from `main` with user approval

## Ready For QA
Yes
