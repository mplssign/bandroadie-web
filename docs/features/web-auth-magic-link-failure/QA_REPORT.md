# QA Report

## Feature Slug

bug/web-auth-magic-link-failure

## Feature Title

Web magic link auth fails with "Unregistered API key" and "Invalid Link" for some users

## Final Verdict

**APPROVED**

## Validation Summary

All six active Architect tasks (7, 8, 9, 11, 12, 13) were implemented exactly as specified. The auth flow migration from implicit to PKCE is a single-line config change with supporting comment and documentation updates. The PKCE handling code already existed in `auth_confirm_screen.dart` and was not modified beyond the `missing_token` UX improvement. Validation was performed via code-path analysis and static analysis only — no runtime behavior was exercised.

## Architect Scope Review

- Scope adherence: compliant
- Files modified: as expected — `lib/main.dart`, `lib/features/auth/auth_confirm_screen.dart`, `web/vercel.json`, `docs/reference/general/RUNTIME_CONFIG.md`, `docs/reference/general/AI_DECISIONS.md`
- Files off-limits: not touched — verified `auth_state_provider.dart`, `login_screen.dart`, `auth_gate.dart`, `supabase_config.dart`, `tools/build_web.sh`, `tools/deploy_web.sh`, native platform directories, and `supabase/` directory were all unmodified
- Note: Working tree contains unrelated changes outside Architect scope (`bandroadie_fresh/` deletions, `docs/agents/MANAGER_AGENT.md` modification, `docs/agents/PROJECT_CONTEXT.md` untracked). These are not part of the feature diff and should be excluded from the commit.

## Completeness Check

- All Architect tasks implemented: yes
- Tasks 1–6 and Task 10: correctly marked N/A per Manager voiding
- Task 7: `authFlowType` changed from `kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce` to `AuthFlowType.pkce` — confirmed in `lib/main.dart` line 66
- Task 8: Comment block updated to describe PKCE for all platforms with localStorage/device storage details — confirmed in `lib/main.dart` lines 63–65
- Task 9: `missing_token` case updated with `Colors.orange` icon and scanner explanation message — confirmed in `auth_confirm_screen.dart` lines 431–438
- Task 11: `no-cache` headers for `/index.html` and `/flutter_service_worker.js` inserted after `/version.json` block — confirmed in `web/vercel.json`
- Task 12: Platform Differences table updated to show "PKCE (as of 2026-04-14 — was implicit)" — confirmed in `RUNTIME_CONFIG.md`
- Task 13: DECISION-001 added with complete context, decision, rationale, constraints, and rollback plan — confirmed in `AI_DECISIONS.md`
- Missing tasks: none

## Behavior Verification

- Validation method: code-path analysis only — no runtime behavior was exercised
- RC1 (scanner token consumption): `authFlowType` is now unconditionally `AuthFlowType.pkce`. PKCE flow requires `code_verifier` from browser localStorage to complete token exchange. Scanners operating in isolated environments cannot access the user's localStorage and therefore cannot consume the token. Confirmed in code.
- RC2 (stale CDN cache): `index.html` and `flutter_service_worker.js` now have `no-cache, no-store, must-revalidate` headers in `web/vercel.json`. Confirmed in code.
- UX improvement: `missing_token` error case displays orange icon with scanner explanation message. Confirmed in code — matches Architect plan exactly.
- Auth confirm screen PKCE handling: Pre-existing PKCE logic in `auth_confirm_screen.dart` was not modified. Only the `missing_token` case block was changed.
- Result: matches expected behavior per Architect plan

## Regression Check

- Risk level: MEDIUM
- Systems reviewed:
  - Auth/Session: `kIsWeb` import retained (line 4), 8 references remain in `main.dart`. `detectSessionInUri: kIsWeb` unchanged (line 68). Only the `authFlowType` ternary was removed.
  - Initialization order: Verified unchanged — WidgetsFlutterBinding → URL strategy → orientation → AppVersionService → validateSupabaseConfig → Supabase.initialize → Firebase → DeepLinkService → runApp.
  - Native auth (iOS/Android/macOS): Already used PKCE. Removing the ternary means they continue using `AuthFlowType.pkce`. No behavioral change.
  - Routing/AuthGate: Not touched.
  - Gigs, Rehearsals, Setlists/Catalog, Members/RBAC, Notifications: Not touched.
  - Platform — Web: Affected by auth flow change and cache headers. PKCE handling code already exists in `auth_confirm_screen.dart`.
  - Deployment/Vercel: Cache headers added. Valid JSON confirmed.
- Regressions found: none

## Database Safety

Not applicable

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found!"

## Test Results

Not run

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none
- Unrelated changes: Working tree contains modifications outside feature scope (`bandroadie_fresh/android/app/build.gradle` deleted, `bandroadie_fresh/android/app/src/main/AndroidManifest.xml` deleted, `docs/agents/MANAGER_AGENT.md` modified, `docs/agents/PROJECT_CONTEXT.md` untracked). These are not in the feature diff and should be excluded from the feature commit via selective staging (`git add` only the seven feature files).

## Issues Found

- **Informational:** Working tree contains unrelated unstaged changes. Recommend staging only the seven feature files when committing: `lib/main.dart`, `lib/features/auth/auth_confirm_screen.dart`, `web/vercel.json`, `docs/reference/general/RUNTIME_CONFIG.md`, `docs/reference/general/AI_DECISIONS.md`, `docs/features/web-auth-magic-link-failure/ENGINEER_REPORT.md`, `docs/features/web-auth-magic-link-failure/QA_REPORT.md`.
