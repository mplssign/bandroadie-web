# QA Report

## Feature Slug
`android-magic-link-deep-link-fallback`

## Feature Title
Android Magic Link Deep Link Fallback

## Final Verdict
**REQUIRES CHANGES** — pending Tier 2 on-device manual verification. All static checks pass. Implementation is correct. On-device tests T2-1 through T2-5 have not been executed and must be completed by Tony on physical Android device before this verdict can be upgraded to APPROVED.

---

## Validation Summary

Static verification was completed in full: diff reviewed against the Architect plan line-by-line, all off-limits files confirmed untouched, `flutter analyze` run independently and confirmed 0 issues, all Tier 1 checks confirmed in code. On-device runtime verification (Tier 2, tests T2-1 through T2-5) cannot be executed by the QA agent and remains outstanding; those tests must be run by Tony on the physical Android device (`R5CNC05HJXT`) using a debug build (`flutter run -d R5CNC05HJXT`) before a final APPROVED verdict can be issued.

---

## Architect Scope Review
- **Scope adherence:** compliant — implementation is minimal and matches the Architect plan exactly
- **Files modified:** as expected — only `lib/features/auth/login_screen.dart` modified; `ARCHITECT_PLAN.md` appears in `git diff main --name-only` because it was committed separately in the prior docs commit (`49a6835`), not as part of the code change
- **Files off-limits:** not touched — confirmed via `git diff main --name-only`; none of the six off-limits files appear

### Off-limits file confirmation

| File | Status |
|---|---|
| `lib/main.dart` | Not touched ✅ |
| `lib/features/auth/auth_confirm_screen.dart` | Not touched ✅ |
| `lib/app/services/deep_link_service.dart` | Not touched ✅ |
| `android/app/src/main/AndroidManifest.xml` | Not touched ✅ |
| `web/.well-known/assetlinks.json` | Not touched ✅ |
| `docs/reference/general/AI_DECISIONS.md` | Not touched ✅ |

---

## Completeness Check
- **All Architect tasks implemented:** yes
- **Missing tasks:** none

| # | Task | Status |
|---|---|---|
| 1 | Remove `Platform` from `dart:io` import | Complete — `import 'dart:io' show SocketException;` confirmed at line 28 |
| 2 | Remove `else if (!kIsWeb && Platform.isAndroid)` branch; update comment | Complete — branch removed; comment updated to "Native (Android, iOS, macOS): Use custom scheme (bandroadie://login-callback/)" |
| 3 | `flutter analyze` 0 errors/warnings | Complete — independently verified: "No issues found!" |

---

## Behavior Verification
- **Validation method:** code-path analysis (Tier 1 static verification)
- **Result:** matches expected

### Tier 1 checks (all confirmed in code)

| Check | Result |
|---|---|
| `Platform` does not appear anywhere in `login_screen.dart` | Confirmed — `grep` returned no output |
| `https://app.bandroadie.com/auth/callback` no longer in `login_screen.dart` | Confirmed — `grep` returned no output |
| `redirectUrl = 'bandroadie://login-callback/'` in `else` clause (line 411) | Confirmed |
| Web path (`kIsWeb` → `https://app.bandroadie.com/auth/confirm`) unchanged | Confirmed — line 409 |
| `auth_confirm_screen.dart` `maxAttempts = 10` wait loop intact | Confirmed — lines 296–307 |

### Root cause addressed

Android no longer receives `https://app.bandroadie.com/auth/callback` as `emailRedirectTo`. It now receives `bandroadie://login-callback/` — the same value iOS and macOS use. This eliminates the dependency on Android App Links certificate verification at install time, which was the root cause of the regression. The `bandroadie://` custom scheme intent-filter in `AndroidManifest.xml` (lines 49–56) does not require `autoVerify` and is already confirmed present. `DeepLinkService` already handles this URI correctly.

### Tier 2 — On-device verification (OUTSTANDING)

All five Tier 2 tests are outstanding. The QA agent cannot execute on-device tests.

**Tony must run these tests on physical Android device (serial `R5CNC05HJXT`) using `flutter run -d R5CNC05HJXT` before APPROVED can be issued.**

| Test | Ref | Steps | Expected | Status |
|---|---|---|---|---|
| **T2-1: Cold start from Gmail (primary bug)** | Test 7+6 | Fully quit app → request magic link → open Gmail → tap link | App opens to home screen; no browser; logs show `bandroadie://login-callback/?code=...` | ⏳ Outstanding |
| **T2-2: Background resume from Gmail** | Test 8 | App backgrounded → request magic link → tap in Gmail | App resumes to home screen; logs show `Received link while running: bandroadie://login-callback/...` | ⏳ Outstanding |
| **T2-3: Cold start from default browser/mail** | Test 7 | Fully quit app → request magic link → open from default browser | App opens to home screen | ⏳ Outstanding |
| **T2-4: Gmail app tap (exact bug repro)** | Test 6 | Repeat T2-1 steps exactly | App opens (not browser) — confirms original bug is resolved | ⏳ Outstanding |
| **T2-5: iOS sanity check** | Test 1 | Request magic link → tap in iOS Mail app | App opens to home screen (no regression) | ⏳ Outstanding |

**Failure criteria for any Tier 2 test:**
- Browser opens instead of app → QA FAIL
- App shows login screen after tapping link → QA FAIL
- `[DeepLinkService]` log shows HTTPS URL for initial link → QA FAIL

---

## Regression Check
- **Risk level:** LOW
- **Systems reviewed:** Auth/Session, Platform (Android, iOS, macOS, Web), Gigs, Rehearsals, Setlists/Catalog, Members/RBAC, Routing, Notifications
- **Regressions found:** none (code-path analysis)

### Notes

- **Android auth:** Root cause fixed. PKCE flow type (`AuthFlowType.pkce`) unchanged — confirmed `lib/main.dart` not touched.
- **iOS/macOS auth:** Behavior unchanged. These platforms already used `bandroadie://login-callback/` via the `else` branch; the branch still exists and is unchanged.
- **Web auth:** `kIsWeb` branch unchanged — still produces `https://app.bandroadie.com/auth/confirm` (DECISION-001 path).
- **`auth_confirm_screen.dart`:** Race-condition wait loop (`maxAttempts = 10`, 500ms polling) at lines 296–307 confirmed intact.
- **All other systems:** Not affected. No database, RLS, routing, or feature code touched.

---

## Database Safety
Not applicable — this change does not touch Supabase schema, RLS policies, migrations, or RPCs.

---

## Analyzer Results
Command: `flutter analyze`
Result: **0 errors, 0 warnings** — "No issues found! (ran in 7.5s)"

Command: `flutter analyze lib/features/auth/login_screen.dart` (per Engineer report)
Result: 0 errors, 0 warnings

---

## Test Results
Not run — Architect plan does not require automated tests; verification is manual per Tier 1 (static, complete) and Tier 2 (on-device, outstanding).

---

## Diff Safety Review
- **Secrets:** none found
- **Debug artifacts:** none found — no print statements, TODO hacks, or temporary flags introduced
- **Unrelated changes:** none found — diff is limited to the two specified edits in `login_screen.dart`

### Full diff reviewed

```diff
--- a/lib/features/auth/login_screen.dart
+++ b/lib/features/auth/login_screen.dart
@@ -25,7 +25,7 @@
-import 'dart:io' show Platform, SocketException;
+import 'dart:io' show SocketException;

@@ -403,13 +403,10 @@
-      // Android: Use verified App Link (https://app.bandroadie.com/auth/callback)
-      // iOS/macOS: Use custom scheme (bandroadie://login-callback/)
+      // Native (Android, iOS, macOS): Use custom scheme (bandroadie://login-callback/)
       if (kIsWeb) {
         redirectUrl = 'https://app.bandroadie.com/auth/confirm';
-      } else if (!kIsWeb && Platform.isAndroid) {
-        redirectUrl = 'https://app.bandroadie.com/auth/callback';
       } else {
         redirectUrl = 'bandroadie://login-callback/';
       }
```

Diff is exactly as specified in the Architect plan. No extraneous changes.

---

## Issues Found

### Critical (must resolve before APPROVED)

1. **Tier 2 on-device tests outstanding (T2-1 through T2-5)** — Static verification is complete and correct, but the ARCHITECT_PLAN.md Tier 2 verification plan requires physical Android device testing. All five tests are unrun. Tony must execute them on device `R5CNC05HJXT` (or equivalent) using `flutter run -d R5CNC05HJXT` and report results. Only after T2-1 through T2-4 pass (and T2-5 confirms iOS is unaffected) can this verdict be changed to APPROVED.

### Warnings
None.

### Suggestions
None.
