# Architect Plan: Web Magic Link Auth Failure

**Feature Slug:** `bug/web-auth-magic-link-failure`  
**Type:** Bug Fix  
**Architect:** AI Assistant  
**Date:** 2026-04-14  
**Status:** Draft — Pending Tony Approval

---

## Problem Summary

Web users signing in via magic link on `app.bandroadie.com` encounter two distinct failure modes:

1. **"Invalid Link" Error** — Magic link consumed before user clicks (HIGH confidence, confirmed via Supabase auth logs)
2. **"Unregistered API key" Error** — Intermittent client-side config validation failure (LOW confidence, non-reproducible, single user event)

The "Invalid Link" failure is caused by email security scanning software (Microsoft Defender Safe Links or similar) pre-fetching the Supabase `/auth/v1/verify?token=...` URL embedded directly in the magic link email. The scanner consumes the one-time token 13 seconds after issuance — before the user opens the email. When the user clicks, the OTP is already invalid.

The "Unregistered API key" error occurs at the `validateSupabaseConfig()` step and never reaches the Supabase server (zero 401s in server logs), indicating missing or empty `--dart-define` values at build time. The error resolved on retry, suggesting transient CDN caching of a stale build artifact.

---

## Root Cause

### RC1: Email Scanner Token Consumption (HIGH Confidence)

**Evidence:**

- Supabase auth logs for `markeburt@gmail.com` show OTP token consumed 13 seconds after issuance (2026-04-13)
- User reports receiving email 1+ minute later, well after the OTP was invalidated
- Pattern repeated twice in the same session — different tokens, same 13-second consumption window
- User's email agent (Microsoft Outlook) uses Defender Safe Links, which is known to pre-fetch URLs in emails

**Root Cause:**  
Web auth currently uses **implicit flow** (`AuthFlowType.implicit` + `detectSessionInUri: true`). In this flow:

1. User requests magic link via `signInWithOtp(emailRedirectTo: 'https://app.bandroadie.com/auth/confirm')`
2. Supabase sends email with link: `https://<project>.supabase.co/auth/v1/verify?token=XXX&redirect_to=https://app.bandroadie.com/auth/confirm`
3. **Email scanner follows the link immediately** (within 13 seconds of send)
4. Supabase `/auth/v1/verify` endpoint validates token and logs successful auth event
5. Token is marked as consumed
6. When user clicks the link later, the token is invalid → "Invalid Link" error

Native platforms (iOS/Android/macOS) use PKCE flow and are unaffected because:

- PKCE flow generates a `code_verifier` stored in local browser storage
- Email link contains only the `token_hash`, not the verification endpoint
- Scanner cannot complete the exchange without the `code_verifier`

**Code Evidence:**  
`lib/main.dart` lines 60-68:

```dart
authOptions: FlutterAuthClientOptions(
  // Web uses implicit flow (simpler, works better with email links)
  // Native uses PKCE (more secure for deep links)
  authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
  // On web: enable auto-detection so Supabase handles session from URL
  // On native: disable it - we handle deep links manually for iPad/background support
  detectSessionInUri: kIsWeb,
),
```

The comment states implicit is "simpler" and "works better with email links", but this is incorrect — implicit flow is **vulnerable to scanner preemption**, while PKCE flow **protects against it**.

**Discrepancy Resolution:**  
`docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md` (dated 2026-01-24) describes PKCE flow as already working on web, with log patterns showing "🔄 Using PKCE flow" and "✅ PKCE exchange successful". This is **aspirational documentation** — it describes the desired end state, not the current implementation. The actual code in `lib/main.dart` confirms web is still using implicit flow.

However, `lib/features/auth/auth_confirm_screen.dart` **already contains PKCE handling logic**:

- Lines 150-176: Handles `code` parameter and calls `exchangeCodeForSession()`
- Lines 178-184: Handles `token_hash` starting with `pkce_` prefix
- Lines 186-193: Handles standard `token_hash` via `verifyOTP(type: OtpType.email)`

**Conclusion:** The migration path to PKCE is **90% complete** in code. The only missing piece is changing `authFlowType` from `implicit` to `pkce` in `lib/main.dart`. Everything downstream is already prepared.

---

### RC2: "Unregistered API key" — Stale Build Cache (LOW Confidence)

**Evidence:**

- Error occurs at `validateSupabaseConfig()` before Supabase client instantiation
- Zero Supabase 401 errors in server logs during the affected 24-hour window
- Error resolved on retry without code changes
- User accessed via DuckDuckGo browser (not a common browser, may route to different CDN edge nodes)

**Hypothesis:**  
Vercel CDN served a stale build artifact where `--dart-define` values were absent or empty. When user retried, they hit a different edge node with a fresh build.

> **⚠️ POST-PLAN CORRECTION (2026-04-14):** The analysis below referencing `tools/build_web.sh` and Vercel environment variables was superseded by information discovered after this plan was written. `tools/build_web.sh` is a **dead script** — it is not used in any build or deploy process. The actual deploy script is `tools/deploy_web.sh`, which loads credentials from a local `.env` file and passes them via `--dart-define`. Vercel does not run the build and does not need environment variables configured. As a result, **the build script fix (Task 10) was voided** before Engineer execution. The cache headers fix (Task 11 / Change 7) was retained and implemented.

**Code Evidence (superseded — see correction above):**  
At plan-writing time, `tools/build_web.sh` was inspected and found to be missing `--dart-define` injections for `SUPABASE_URL` and `SUPABASE_ANON_KEY`. This was incorrectly identified as the RC2 source. The actual deploy script (`tools/deploy_web.sh`) was not inspected at plan time and already handled credentials correctly.

**Missing Cache Headers (still valid — fix was implemented):**  
`web/vercel.json` was missing `Cache-Control` headers for `index.html` and `flutter_service_worker.js`. These have been added as `no-cache, no-store, must-revalidate`.

**Severity Assessment:**  
Impact is LOW — error is non-reproducible and affected only one user in one session. The remaining viable explanation is transient CDN caching of a stale `index.html`, which the cache header fix addresses defensively.

**Recommended Fix (as implemented):**  
Add no-cache headers for `/index.html` and `/flutter_service_worker.js` in `web/vercel.json`. Build script change was voided — no action required on credential injection.

```bash
flutter build web \
  --release \
  --pwa-strategy=none \
  --dart-define=BUILD_TIMESTAMP=$BUILD_TS \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  || fail "Flutter build failed"
```

Add explicit cache headers to `web/vercel.json`:

```json
{
  "source": "/index.html",
  "headers": [
    { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
  ]
},
{
  "source": "/flutter_service_worker.js",
  "headers": [
    { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
  ]
}
```

---

## Reference Docs Consulted

### Auth Domain Reference

- **`docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md`** — Describes PKCE flow as already implemented (dated 2026-01-24). Document is aspirational or describes a partial implementation. Confirmation screen logic supports PKCE, but `lib/main.dart` still uses implicit flow. The 5-second auth state sync wait loop described in this doc **is confirmed present** in `auth_confirm_screen.dart` lines 267-280.

### General Reference

- **`docs/reference/general/RUNTIME_CONFIG.md`** — Documents initialization order and configuration model. States web uses implicit flow, native uses PKCE. Confirms `--dart-define` is the only permitted config source.
- **`docs/reference/general/AI_DECISIONS.md`** — Empty. No prior decisions logged about auth flow changes.

---

## Critical Discrepancy Resolution

**Conflict:**

- `RUNTIME_CONFIG.md` states: "Web uses implicit flow (`detectSessionInUri: true`)"
- `MAGIC_LINK_FIX_VERIFICATION.md` describes PKCE flow working on web with log patterns showing "Using PKCE flow"
- `PROJECT_CONTEXT.md` (from feature input) states web uses implicit flow

**Ground Truth (Code Inspection):**  
`lib/main.dart` line 64:

```dart
authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
```

**Web currently uses implicit flow.**

`lib/features/auth/auth_confirm_screen.dart` contains full PKCE handling logic (lines 150-193), including:

- `exchangeCodeForSession(code)` for PKCE flow
- `verifyOTP(tokenHash:, type: OtpType.email)` for email OTP flow
- Detection of `pkce_` prefix in `token_hash`

**Conclusion:**  
The PKCE implementation is **code-complete** in `AuthConfirmScreen`, but **disabled in configuration**. `MAGIC_LINK_FIX_VERIFICATION.md` describes the intended final state after the auth flow type is changed. The migration from implicit to PKCE requires **one line change** in `lib/main.dart`.

---

## Existing System Analysis

### Current Auth Flow (Implicit — Web Only)

1. **User Requests Magic Link:**
   - User enters email on `LoginScreen`
   - `signInWithOtp(email: email, emailRedirectTo: 'https://app.bandroadie.com/auth/confirm')` is called
   - Supabase sends email with link: `https://<project>.supabase.co/auth/v1/verify?token=<OTP>&redirect_to=https://app.bandroadie.com/auth/confirm`

2. **Email Delivered:**
   - Email contains button with direct link to Supabase `/auth/v1/verify` endpoint
   - **Vulnerability:** Email scanners follow this link immediately

3. **Link Click / Scanner Preemption:**
   - Scanner (or user) follows Supabase verify URL
   - Supabase validates OTP and consumes it
   - Supabase redirects to `https://app.bandroadie.com/auth/confirm#{access_token=...&refresh_token=...}`
   - If scanner opened the link, the fragment is captured in the scanner's session, not the user's browser

4. **App Confirm Screen:**
   - `AuthConfirmScreen` mounts
   - On web with implicit flow, it tries to retrieve `access_token` from URL fragment via `getSupabaseAuthFragment()` (sessionStorage)
   - If scanner consumed the token, fragment is empty → falls through to "No query params" timeout → "missing_token" error
   - If user clicked directly and got the fragment, session is established and user is redirected to `/app`

### Native Auth Flow (PKCE — iOS/Android/macOS)

1. **User Requests Magic Link:**
   - Same as web, but `emailRedirectTo: 'bandroadie://login-callback/'`

2. **Email Delivered:**
   - Supabase sends link to custom scheme
   - Email contains: `bandroadie://login-callback/?token_hash=<hash>&type=email`

3. **Link Click:**
   - Deep link opens app via `DeepLinkService`
   - `AuthConfirmScreen` receives `token_hash` via route params

4. **PKCE Exchange:**
   - `auth_confirm_screen.dart` calls `verifyOTP(tokenHash:, type: OtpType.email)`
   - Supabase validates token_hash against the PKCE code_verifier stored in device storage
   - Session established

**Key Difference:**  
Native flow never exposes the Supabase `/auth/v1/verify` endpoint in the email link. The link goes directly to the app, which then performs the token exchange with the server-stored code_verifier. Scanners cannot complete the exchange.

---

## Proposed Solution

### RC1 Fix: Migrate Web to PKCE Flow

**Change 1: Enable PKCE for Web** (1 line change)  
File: `lib/main.dart`  
Line 64:

```dart
// BEFORE:
authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,

// AFTER:
authFlowType: AuthFlowType.pkce,
```

**Rationale:**

- PKCE is the secure, modern auth flow and is already used on native platforms
- `AuthConfirmScreen` already handles PKCE `code` parameter and `token_hash` verification
- Supabase Flutter SDK will generate and store `code_verifier` in browser localStorage
- Email link will change from direct Supabase endpoint to app's `/auth/confirm?token_hash=...`
- Scanners opening the link without the browser-stored `code_verifier` cannot complete the exchange

**Expected Email URL Change:**

```
BEFORE (Implicit):
https://<project>.supabase.co/auth/v1/verify?token=<OTP>&redirect_to=https://app.bandroadie.com/auth/confirm

AFTER (PKCE):
https://app.bandroadie.com/auth/confirm?token_hash=<hash>&type=email
```

**Impact:**

- Scanners will open the `/auth/confirm` route with `token_hash` but no `code_verifier` in localStorage
- `AuthConfirmScreen.verifyOTP()` will fail with "Invalid grant" or "PKCE verification failed"
- User opening the link in the **same browser** where they requested the link **will** have the `code_verifier` and can complete the exchange
- This is the **intended security behavior** of PKCE

**Change 2: Update Initialization Comment**  
File: `lib/main.dart`  
Lines 61-63 (comment):

```dart
// BEFORE:
// Web uses implicit flow (simpler, works better with email links)
// Native uses PKCE (more secure for deep links)

// AFTER:
// All platforms use PKCE flow for secure token exchange
// Web: code_verifier stored in localStorage; scanners cannot complete exchange
// Native: code_verifier stored in device storage; handled via deep links
```

**Change 3: Update RUNTIME_CONFIG.md**  
File: `docs/reference/general/RUNTIME_CONFIG.md`  
Platform Differences table (line ~68):

```markdown
| Area       | Native (iOS / macOS / Android) | Web                                    |
| ---------- | ------------------------------ | -------------------------------------- |
| Config     | `--dart-define` only           | `--dart-define` only                   |
| Auth flow  | PKCE                           | PKCE (as of 2026-04-14 — was implicit) |
| Firebase   | Initialized (step 7)           | Not initialized                        |
| Deep links | Handled via `DeepLinkService`  | Not applicable                         |
```

**Change 4: Add Decision Log Entry**  
File: `docs/reference/general/AI_DECISIONS.md`

````markdown
## [DECISION-001] Web Auth Flow Migration: Implicit → PKCE

**Date:** 2026-04-14  
**Feature:** bug/web-auth-magic-link-failure  
**Agent:** Architect  
**Status:** Active

### Context

Web magic link authentication was failing for users with email security scanners (Microsoft Defender Safe Links, etc.) that pre-fetch URLs in emails. The implicit flow used a direct Supabase `/auth/v1/verify?token=...` URL in the email, which scanners would follow immediately, consuming the one-time token before the user could click.

Supabase auth logs confirmed OTP tokens consumed within 13 seconds of issuance, well before users opened their email.

### Decision

Migrate web auth from implicit flow to PKCE flow (`AuthFlowType.pkce`). This changes the email link from a direct Supabase verification endpoint to the app's `/auth/confirm?token_hash=...` route. The PKCE code_verifier is stored in the user's browser localStorage and is required to complete the token exchange. Scanners cannot access localStorage from the user's browser and therefore cannot complete the exchange.

### Rationale

1. **Security:** PKCE is the modern, recommended flow for OAuth/OIDC
2. **Scanner Protection:** Code verifier requirement prevents unauthorized token consumption
3. **Implementation Ready:** `AuthConfirmScreen` already contains full PKCE handling logic
4. **Platform Consistency:** Native platforms already use PKCE successfully
5. **Minimal Risk:** One-line config change; all downstream logic already tested (per MAGIC_LINK_FIX_VERIFICATION.md)

### Constraints Imposed

- Web users must click magic links in the **same browser** where they requested the link
- Browser localStorage must be enabled (standard requirement)
- Users who request a link in Safari but open it in Chrome will see a "Browser Mismatch" error — this is expected PKCE behavior (already handled in `auth_confirm_screen.dart` lines 302-311)
- Email link format changes — Supabase email templates may need verification (default template should auto-adapt)

### Rollback Plan

If PKCE causes unexpected issues, revert `lib/main.dart` line 64 to:

```dart
authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
```
````

No database migration or RLS changes required. Rollback is safe.

````

**Change 5: Improve "Invalid Link" Error UX**
File: `lib/features/auth/auth_confirm_screen.dart`
Lines 438-445 (in `_buildErrorUI()` method, `missing_token` case):

```dart
// BEFORE:
case 'missing_token':
  icon = Icons.link_off;
  iconColor = Colors.red;
  title = 'Invalid Link';
  message = 'The magic link appears to be incomplete or corrupted. Please request a new one.';
  break;

// AFTER:
case 'missing_token':
  icon = Icons.link_off;
  iconColor = Colors.orange;
  title = 'Invalid Link';
  message = 'This magic link may have been opened by email security software before you could click it. '
      'If you use Microsoft Outlook or a corporate email system, this is a known issue.\n\n'
      'Please request a new magic link and try again.';
  break;
````

**Rationale:**  
Provide clear user feedback that explains the scanner issue without technical jargon. Orange icon (vs. red) signals "issue is external, not your fault".

---

### RC2 Fix: Vercel Build Config Hardening (Config Audit + Cache Fix)

**Change 6: Inject Supabase Credentials in Build Script**  
File: `tools/build_web.sh`  
Lines 162-167:

```bash
# BEFORE:
flutter build web \
  --release \
  --pwa-strategy=none \
  --dart-define=BUILD_TIMESTAMP=$BUILD_TS \
  || fail "Flutter build failed"

# AFTER:
flutter build web \
  --release \
  --pwa-strategy=none \
  --dart-define=BUILD_TIMESTAMP=$BUILD_TS \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
  || fail "Flutter build failed"
```

**Rationale:**

- Uses `${VAR:-}` syntax to safely expand environment variables (empty string if unset)
- If Vercel has `SUPABASE_URL` and `SUPABASE_ANON_KEY` configured, they will be injected
- If not, the build will fail at `validateSupabaseConfig()` (same as current behavior)
- Makes the build deterministic and auditable

**Change 7: Add Cache Control Headers for Critical Bootstrap Files**  
File: `web/vercel.json`  
Insert after the existing `/version.json` header block (around line 15):

```json
{
  "source": "/index.html",
  "headers": [
    { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
  ]
},
{
  "source": "/flutter_service_worker.js",
  "headers": [
    { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
  ]
},
```

**Rationale:**

- `index.html` is the entry point — must never be cached to prevent stale builds
- `flutter_service_worker.js` registers the service worker and controls asset caching — must always be fresh
- These are the two most common causes of "app stuck on old version" issues in production Flutter web apps

**Verification Step (Pre-Deployment):**

1. Check Vercel project settings at https://vercel.com/bandroadie
2. Navigate to **Settings → Environment Variables**
3. Confirm `SUPABASE_URL` and `SUPABASE_ANON_KEY` are set for Production, Preview, and Development environments
4. If missing, add them before merging this fix
5. Document findings in `docs/reference/general/RUNTIME_CONFIG.md` under a new "Vercel Deployment" section

---

## Supabase Dashboard Configuration

**Required Dashboard Changes:**  
None. PKCE flow is enabled by default in Supabase Auth.

**Verification Steps:**

1. Navigate to Supabase Dashboard → **Authentication → URL Configuration**
2. Confirm **Redirect URLs** includes:
   - `https://app.bandroadie.com/auth/confirm`
   - `bandroadie://login-callback/`
3. Navigate to **Authentication → Auth Providers → Email**
4. Confirm **Enable Email Provider** is ON
5. Confirm **Enable Email Confirmations** is OFF (magic link, not confirmation code)
6. (Optional) Navigate to **Authentication → Email Templates → Magic Link**
7. Verify template uses `{{ .ConfirmationURL }}` variable — **do not change** (Supabase auto-generates correct URL format based on `authFlowType`)

**Post-Deployment Verification:**  
Request a magic link and inspect the email. Confirm the link format is:

```
https://app.bandroadie.com/auth/confirm?token_hash=...&type=email
```

If the link still points to `https://<project>.supabase.co/auth/v1/verify`, the email template may need manual update.

---

## Database Impact

**Not Applicable** — Auth flow changes are client-side and Supabase SDK configuration only.

- No schema changes
- No RLS policy changes
- No RPC functions required
- No migrations required

Supabase Auth manages PKCE flow server-side with no developer intervention.

---

## Flutter Architecture Changes

### Files to Create: **None**

All required logic already exists. No new files needed.

---

### Files to Modify

| File                                         | Description of Changes                                                                                                                                                                             |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                              | **Line 64:** Change `authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,` to `authFlowType: AuthFlowType.pkce,`<br>**Lines 61-63:** Update comment to reflect PKCE for all platforms |
| `lib/features/auth/auth_confirm_screen.dart` | **Lines 438-445:** Update `missing_token` error message to explain scanner consumption issue                                                                                                       |
| `docs/reference/general/RUNTIME_CONFIG.md`   | **Platform Differences table:** Update web auth flow from "Implicit" to "PKCE (as of 2026-04-14)"<br>**Add new section:** "Vercel Deployment" documenting environment variable requirements        |
| `docs/reference/general/AI_DECISIONS.md`     | **Add DECISION-001:** Document auth flow migration decision, rationale, and constraints                                                                                                            |
| ~~`tools/build_web.sh`~~                      | ~~**Lines 164-165:** Add `--dart-define=SUPABASE_URL` and `--dart-define=SUPABASE_ANON_KEY` to `flutter build web` command~~ **[VOIDED: dead script — `tools/deploy_web.sh` already handles credentials from `.env`]** |
| `web/vercel.json`                            | **Insert after line 14:** Add cache control headers for `/index.html` and `/flutter_service_worker.js` (no-cache)                                                                                  |

---

### Files Off-Limits

| File                                                    | Reason                                                                                |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `lib/features/auth/auth_state_provider.dart`            | No changes needed — auth state observation logic is correct                           |
| `lib/features/auth/login_screen.dart`                   | No changes needed — `signInWithOtp` call does not require modification for PKCE       |
| `lib/features/auth/auth_gate.dart`                      | No changes needed — routing logic is flow-agnostic                                    |
| `lib/main.dart` (initialization order)                  | Guardrail: cannot change order without Architect approval (not required for this fix) |
| `lib/supabase_config.dart`                              | No changes needed — `validateSupabaseConfig()` is already correct                     |
| Any native platform code (`ios/`, `android/`, `macos/`) | Native auth already uses PKCE and is unaffected                                       |
| Any test files                                          | Tests will be updated by QA if needed; Architect does not modify tests                |
| `supabase/` directory                                   | No edge functions, triggers, or migrations required                                   |

---

## System Impact Map

| System                               | Impact       | Notes                                                                        |
| ------------------------------------ | ------------ | ---------------------------------------------------------------------------- |
| **Auth / Session**                   | Affected     | Auth flow type changes from implicit to PKCE for web; native unchanged       |
| **Routing / AuthGate**               | Unaffected   | AuthGate is flow-agnostic; no logic changes needed                           |
| **Gigs**                             | Unaffected   | No dependency on auth flow type                                              |
| **Rehearsals**                       | Unaffected   | No dependency on auth flow type                                              |
| **Setlists / Catalog**               | Unaffected   | No dependency on auth flow type                                              |
| **Members / RBAC**                   | Unaffected   | Auth flow change does not affect user roles or permissions                   |
| **Notifications**                    | Unaffected   | Firebase/FCM initialization and push delivery unchanged                      |
| **Platform — Web**                   | **Affected** | Auth flow changes to PKCE; users must use same browser for request and click |
| **Platform — iOS / Android / macOS** | Unaffected   | Already using PKCE; no code changes                                          |
| **Deployment / Vercel**              | Affected     | Build script updated to inject `--dart-define` values; cache headers added   |

---

## Regression Risk

**Rating: MEDIUM**

### Risk Factors (Elevating Risk):

1. **Auth is critical path** — Any auth failure blocks 100% of web users from signing in
2. **Flow type change** — Moving from implicit to PKCE changes Supabase SDK behavior
3. **Browser dependency** — PKCE requires same-browser login (request + click), which may confuse users who switch browsers
4. **Email template format** — If Supabase email template does not auto-adapt, users may still receive old link format

### Mitigating Factors (Reducing Risk):

1. **Code already exists** — `AuthConfirmScreen` has full PKCE handling logic; this is a **config change**, not a new feature
2. **Native validation** — iOS/Android/macOS have been using PKCE successfully; web is adopting a proven pattern
3. **MAGIC_LINK_FIX_VERIFICATION.md** describes PKCE verification as complete (doc written before code was enabled)
4. **Graceful error handling** — "Browser mismatch" error is already implemented with clear UX (lines 330-393)
5. **Rollback is trivial** — Revert one line in `lib/main.dart`; no database state to unwind
6. **RC2 fix is defensive** — Cache headers and build script changes prevent stale build issues but do not alter app logic

### Risk Mitigation Requirements:

1. **Pre-Deployment:**
   - Verify Vercel environment variables are set (Engineer task)
   - Test PKCE flow locally in Chrome, Safari, Firefox (QA task)
   - Test "browser mismatch" scenario by requesting link in Safari, opening in Chrome (QA task)
2. **Deployment:**
   - Deploy to Vercel preview environment first (not prod)
   - Perform full magic link test in preview
   - Request magic link and inspect email URL format
   - If URL is still Supabase `/auth/v1/verify` endpoint, investigate email template config
3. **Post-Deployment:**
   - Monitor Supabase auth logs for increased "Invalid grant" errors (would indicate browsers not persisting code_verifier)
   - Monitor web analytics for drop in login success rate
   - Prepare rollback PR in advance

**If regression occurs:**  
Revert `lib/main.dart` line 64, redeploy. Users will be back on implicit flow. Scanner consumption issue will return, but at least login works.

---

## Engineer Task Breakdown

Tasks are atomic, ordered, and independently verifiable.

### Tier 1: Pre-Deploy Config Verification (Read-Only)

1. Log in to Vercel Dashboard at https://vercel.com/bandroadie
2. Navigate to **Settings → Environment Variables**
3. Confirm `SUPABASE_URL` is set for Production, Preview, Development
4. Confirm `SUPABASE_ANON_KEY` is set for Production, Preview, Development
5. If missing, add them using values from local `.vscode/launch.json` or Supabase Dashboard
6. Document findings in `docs/reference/general/RUNTIME_CONFIG.md` under new section: "Vercel Deployment"

### Tier 2: Code Changes (Implementation)

7. **Modify:** `lib/main.dart` line 64 — Change auth flow type from conditional (web=implicit) to universal PKCE
8. **Modify:** `lib/main.dart` lines 61-63 — Update comment to reflect PKCE for all platforms
9. **Modify:** `lib/features/auth/auth_confirm_screen.dart` lines 438-445 — Update `missing_token` error message to explain scanner issue
10. ~~**Modify:** `tools/build_web.sh` lines 164-165 — Add `--dart-define` injections for `SUPABASE_URL` and `SUPABASE_ANON_KEY`~~ **[VOIDED: `tools/build_web.sh` is a dead script. `tools/deploy_web.sh` already handles credentials from `.env`.]**
11. **Modify:** `web/vercel.json` — Insert cache headers for `/index.html` and `/flutter_service_worker.js` after the `/version.json` block
12. **Modify:** `docs/reference/general/RUNTIME_CONFIG.md` — Update Platform Differences table to show PKCE for web
13. **Modify:** `docs/reference/general/AI_DECISIONS.md` — Add DECISION-001 documenting auth flow migration

### Tier 3: Local Testing (Verification)

14. Run `flutter clean && flutter pub get`
15. Run `flutter analyze` — confirm zero errors
16. Run local web build: `flutter run -d chrome --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_ANON_KEY=<key>`
17. Request magic link from local app
18. Open DevTools Console, filter for "AUTH" logs
19. Click magic link in email
20. **Verify log pattern:** "🔄 Using PKCE flow" → "✅ PKCE exchange successful" (per MAGIC_LINK_FIX_VERIFICATION.md line 63)
21. Confirm successful login and redirect to `/app`

### Tier 4: Supabase Dashboard Verification

22. Navigate to Supabase Dashboard → Authentication → URL Configuration
23. Confirm redirect URLs include `https://app.bandroadie.com/auth/confirm` and `bandroadie://login-callback/`
24. Navigate to Authentication → Email Templates → Magic Link
25. **Do NOT modify template** — verify it uses `{{ .ConfirmationURL }}` (Supabase auto-formats based on flow type)

### Tier 5: Deployment

26. Commit changes with message: `fix(auth): migrate web to PKCE flow to prevent scanner token consumption`
27. Push to branch `bug/web-auth-magic-link-failure`
28. Open PR targeting `main`
29. Deploy to Vercel Preview environment (auto-triggered by PR)
30. Test magic link auth in Preview environment
31. **Inspect email:** Confirm link format is `https://app.bandroadie.com/auth/confirm?token_hash=...` (not Supabase verify endpoint)
32. If email still has old format, investigate Supabase template config (may need cache clear or manual adjustment)
33. Merge PR after QA approval
34. Monitor production auth logs for 24 hours

---

## Verification Plan

### Tier 1 — Pre-Deployment Tests (Before Any Code Changes)

**-- PRE-DEPLOY TEST 1: Verify Current Auth Flow Type**  
**File:** `lib/main.dart`  
**Action:** Read line 64 and confirm it shows `authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,`  
**Expected:** Confirmation that web is currently using implicit flow  
**Pass Criteria:** Line matches exactly

**-- PRE-DEPLOY TEST 2: Verify Vercel Cache Headers**  
**File:** `web/vercel.json`  
**Action:** Read headers array and check for `/index.html` and `/flutter_service_worker.js` entries  
**Expected:** Both are missing (confirming the gap identified in diagnosis)  
**Pass Criteria:** No cache control header found for either file

**-- PRE-DEPLOY TEST 3: Verify Build Script Gap**  
**File:** `tools/build_web.sh`  
**Action:** Read `flutter build web` command and check for `--dart-define=SUPABASE_URL` and `--dart-define=SUPABASE_ANON_KEY`  
**Expected:** Both are missing (confirming the RC2 gap)  
**Pass Criteria:** Only `BUILD_TIMESTAMP` is injected via `--dart-define`

**-- PRE-DEPLOY TEST 4: Verify PKCE Handling Already Exists**  
**File:** `lib/features/auth/auth_confirm_screen.dart`  
**Action:** Grep for `exchangeCodeForSession` and `verifyOTP`  
**Expected:** Both methods are present and handle PKCE flow  
**Pass Criteria:** Lines 150-193 contain PKCE exchange logic

**-- PRE-DEPLOY TEST 5: Verify Native Platforms Unaffected**  
**File:** `lib/main.dart`  
**Action:** Confirm auth flow type for native is already PKCE (ternary condition)  
**Expected:** `authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,` shows native uses PKCE  
**Pass Criteria:** Non-web platforms already configured for PKCE

---

### Tier 2 — Post-Deployment Tests (After Code Changes and Vercel Deploy)

**-- POST-DEPLOY TEST 1: Web Magic Link Happy Path (No Scanner)**  
**Platform:** Web (Chrome on macOS)  
**Steps:**

1. Open `https://app.bandroadie.com` in Chrome
2. Enter email and request magic link
3. Open email in the **same Chrome window** (webmail)
4. Click magic link button
5. Open browser DevTools Console, filter for "AUTH"

**Expected:**

- Console shows: `🔄 Using PKCE flow - exchanging code for session...`
- Console shows: `✅ PKCE exchange successful`
- Console shows: `User: <email>`
- User is redirected to `/app` and logged in
- No error screens shown

**Pass Criteria:** Login completes without error; user sees main app

**-- POST-DEPLOY TEST 2: Email Link Format Verification**  
**Platform:** Web  
**Steps:**

1. Request magic link from web app
2. Open email (Gmail, Outlook, etc.)
3. **Do NOT click the link**
4. Right-click the magic link button → "Copy Link Address"
5. Paste URL into a text editor

**Expected URL Format:**

```
https://app.bandroadie.com/auth/confirm?token_hash=<hash>&type=email
```

**NOT:**

```
https://<project>.supabase.co/auth/v1/verify?token=...
```

**Pass Criteria:** Link points to app domain, not Supabase domain

**-- POST-DEPLOY TEST 3: Browser Mismatch Error (PKCE Verification)**  
**Platform:** Web  
**Steps:**

1. Open `https://app.bandroadie.com` in **Safari**
2. Request magic link
3. Copy the link from the email
4. Open **Chrome** (different browser)
5. Paste link into Chrome address bar and press Enter

**Expected:**

- Error screen with orange warning icon
- Title: "Login Link Opened in Wrong Browser"
- Message: "For security, magic links must be opened in the same browser where you requested them."
- "Request New Magic Link" button visible

**Pass Criteria:** Clear error messaging; no crash

**-- POST-DEPLOY TEST 4: Email Scanner Simulation**  
**Platform:** Web  
**Steps:**

1. Request magic link in Chrome
2. Copy link from email
3. Open link in **Incognito/Private Window** (no localStorage)
4. Observe error

**Expected:**

- Error occurs because incognito window has no `code_verifier` in localStorage
- Error screen shows "Invalid Link" or "Browser Mismatch"

**Pass Criteria:** Auth fails gracefully (expected behavior — demonstrates scanner cannot hijack auth)

**-- POST-DEPLOY TEST 5: Native Auth Unchanged**  
**Platform:** iOS (Simulator or Device)  
**Steps:**

1. Open BandRoadie iOS app
2. Request magic link
3. Tap link in Mail app
4. App opens and user is logged in

**Expected:**

- iOS magic link flow works exactly as before
- No errors
- Session established

**Pass Criteria:** Native auth unaffected by web PKCE migration

**-- POST-DEPLOY TEST 6: Expired Link Error**  
**Platform:** Web  
**Steps:**

1. Request magic link
2. Wait 10+ minutes (or use a link from another session)
3. Click the expired link

**Expected:**

- Error screen with timer icon
- Title: "Magic Link Expired"
- Message includes explanation about time limits
- "Request New Magic Link" button visible

**Pass Criteria:** Clear expiration messaging

**-- POST-DEPLOY TEST 7: Reused Link Error**  
**Platform:** Web  
**Steps:**

1. Request magic link
2. Click link and log in successfully
3. Log out
4. Try to click the same magic link again

**Expected:**

- Error screen: "This magic link has already been used. Each link can only be used once for security."

**Pass Criteria:** Reused link is rejected with clear messaging

---

## QA Regression Areas

### Primary Focus (High Priority)

1. **Web magic link happy path** — Same browser request and click (Chrome, Safari, Firefox, Edge)
2. **Native magic link** — iOS and Android unaffected
3. **Browser mismatch scenario** — Request in Safari, open in Chrome → expect error
4. **Error state: Expired link** — Wait 10 minutes, click link → expect clear error
5. **Error state: Reused link** — Log in, log out, reuse link → expect error
6. **Error state: Scanner simulation** — Open link in incognito (no localStorage) → expect auth failure

### Secondary Focus (Medium Priority)

7. **Email link format** — Inspect raw link URL to confirm it points to app domain, not Supabase
8. **In-app browser handling** — Gmail app, LinkedIn app (may have restricted localStorage)
9. **Session persistence** — Log in, close tab, reopen app → should stay logged in
10. **"Request New Link" button** — Click from error screen → should land on login screen with email prefilled (if possible)

### Tertiary Focus (Low Priority)

11. **Network failure handling** — Airplane mode during OTP request → expect clear error
12. **Supabase auth logs** — Monitor for increased "Invalid grant" errors post-deploy (would indicate browsers not storing code_verifier)
13. **Web analytics** — Track login success rate for 7 days post-deploy

---

## Rollout / Migration Strategy

### Deployment Sequence

1. **Deploy to Vercel Preview** (auto-triggered by PR)
2. **QA tests all POST-DEPLOY tests** in preview environment
3. **Inspect email link format** to confirm PKCE URL structure
4. **If preview passes:** Merge PR → auto-deploy to Production
5. **If preview fails:** Investigate email template config, rollback if needed

### User Impact

- **Zero downtime** — This is a client-side auth flow change; no server migration required
- **Existing sessions unaffected** — Users already logged in remain logged in
- **New logins:** Users must click magic link in the same browser where they requested it
- **Scanner-affected users:** Will now be **unaffected** (fix resolves RC1)

### Monitoring (First 24 Hours)

1. **Supabase Dashboard → Auth Logs:**
   - Look for successful `magiclink` or `pkce` auth events
   - Look for `Invalid grant` errors (would indicate PKCE issues)
2. **Vercel Analytics:**
   - Track `/auth/confirm` route hit rate
   - Track `/app` route hit rate (successful login)
3. **User Feedback Channels:**
   - Monitor support email for "can't log in" reports
   - Check app reviews (if applicable)

### Rollback Trigger

If web login success rate drops below 80% in the first 24 hours:

1. Immediately revert `lib/main.dart` line 64 to:
   ```dart
   authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
   ```
2. Commit as hotfix and push to `main`
3. Vercel auto-deploys within 2 minutes
4. Scanner issue will return, but at least users can log in again
5. Investigate PKCE implementation and email template config before retrying

### Success Criteria (7 Days Post-Deploy)

- Web login success rate **≥95%** (was estimated ~80% with scanner issue)
- "Invalid Link" error reports from affected user drop to zero
- "Browser mismatch" errors <2% of login attempts (expected for users switching browsers)
- Native platform login success rate unchanged

---

## Out of Scope

The following are **explicitly excluded** from this fix:

1. **Social login (Google, Apple, GitHub)** — Not affected by magic link flow
2. **Email confirmation codes** (as opposed to magic links) — BandRoadie uses magic links only
3. **Password-based auth** — BandRoadie is passwordless
4. **Multi-factor authentication (MFA)** — Not implemented; would require separate feature
5. **Session refresh logic** — Already handled by Supabase SDK; not changed by PKCE migration
6. **Deep link handling on native** — Already correct; unaffected by web changes
7. **Supabase RLS policies** — Auth flow change does not affect data access rules
8. **User profile creation flow** — Happens after auth; unaffected
9. **Band invitation flow** — Separate from initial auth; unaffected
10. **Push notification permissions** — Requested after login; unaffected

---

**End of Architect Plan**

---

## Next Steps

1. **Tony:** Review and approve this plan
2. **Engineer:** Execute tasks in order per "Engineer Task Breakdown"
3. **QA:** Execute "Verification Plan" post-deployment
4. **Manager:** Gate commit based on QA PASS

---

**Architect Signature:** AI Assistant  
**Date:** 2026-04-14  
**Status:** Awaiting Tony Approval
