# ARCHITECT_PLAN.md

## Feature Slug

`bug/demo-login-invalid-credentials`

---

## Problem Summary

The 7-tap-on-logo gesture on the web sign-in page (`app.bandroadie.com`) correctly triggers demo login, but the authentication attempt fails with "Invalid login credentials" from Supabase Auth. The demo account cannot be accessed on web, despite the feature being fully implemented in the UI.

**Why it matters**: This blocks Play Store reviewers and testers from accessing the demo environment on web, which is needed for app review and evaluation.

---

## Root Cause

The web deployment script `tools/deploy_web.sh` does not pass `DEMO_PASSWORD` via `--dart-define` to the `flutter build web` command. As a result, the compiled web app uses the default empty string value for `kDemoPassword`, causing Supabase Auth to reject the login with "Invalid login credentials".

**Evidence:**

- `lib/app/constants/demo_credentials.dart` defines `kDemoPassword = String.fromEnvironment('DEMO_PASSWORD', defaultValue: '')`
- `tools/deploy_web.sh` line 240 builds web with 10 `--dart-define` flags, but DEMO_PASSWORD is absent
- `tools/build_ios.sh`, `tools/build_android.sh`, and `tools/build_mobile_release.sh` all correctly include `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD}"`
- `.env.example` documents `DEMO_PASSWORD` as required for demo account access
- `docs/reference/deployment/deployment.md` confirms `deploy_web.sh` is the canonical web deployment script (`build_web.sh` is not used)

**Root cause confidence**: **HIGH** (directly confirmed in source code)

---

## Reference Docs Consulted

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md` (reviewed but not directly relevant — covers magic link auth, not demo login)
- `docs/reference/deployment/deployment.md` (confirmed `deploy_web.sh` is the canonical script)

---

## Existing System Analysis

### Current Demo Login Flow

1. **Trigger**: User taps BandRoadie logo 7 times on `LoginScreen`
2. **Handler**: `_handleLogoTap()` increments `_logoTapCount`, resets after 3 seconds of inactivity
3. **Activation**: After 7th tap, `_triggerDemoLogin()` is called
4. **Authentication**: Calls `supabase.auth.signInWithPassword(email: kDemoEmail, password: kDemoPassword)`
5. **Constants**:
   - `kDemoEmail = 'hello@bandroadie.com'` (hardcoded in `demo_credentials.dart`)
   - `kDemoPassword = String.fromEnvironment('DEMO_PASSWORD', defaultValue: '')`
6. **Build-time injection**: `DEMO_PASSWORD` must be passed via `--dart-define` at compile time
7. **Web build**: `tools/deploy_web.sh` loads `.env` but does NOT pass DEMO_PASSWORD to Flutter build
8. **Result**: Web app compiled with `kDemoPassword = ''` → authentication fails

### Why Native Platforms Work

iOS, Android, and macOS build scripts correctly include:

```bash
--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"
```

### Why Web Fails

`tools/deploy_web.sh` lines 240–251 contain:

```bash
flutter build web \
  --release \
  --dart-define=BUILD_TIMESTAMP=$BUILD_TS \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=FIREBASE_API_KEY="${FIREBASE_API_KEY}" \
  --dart-define=FIREBASE_AUTH_DOMAIN="${FIREBASE_AUTH_DOMAIN}" \
  --dart-define=FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID}" \
  --dart-define=FIREBASE_STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_APP_ID="${FIREBASE_APP_ID}" \
  --dart-define=FIREBASE_MEASUREMENT_ID="${FIREBASE_MEASUREMENT_ID}" \
  || fail "Flutter build failed"
```

Missing: `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD}"`

---

## Proposed Solution

Add `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD}"` to the `flutter build web` command in `tools/deploy_web.sh`, immediately after the existing `--dart-define` flags.

**Optional enhancement** (recommended): Add validation check to ensure `DEMO_PASSWORD` is set in `.env` before build proceeds, matching the pattern used for `SUPABASE_URL` and `SUPABASE_ANON_KEY`.

**Why this is minimal and safe:**

- Single-line addition to build script
- Matches existing pattern in iOS/Android/macOS builds
- No runtime code changes
- No database changes
- No new dependencies
- Failure mode is safe: if password is wrong, demo login fails but normal auth is unaffected

---

## Database Impact

**Not applicable** — this is a build configuration change only. No migrations, RLS policies, RPC functions, or triggers are affected.

---

## Flutter Architecture Changes

None. The demo login feature is fully implemented and correct. Only the build-time injection of credentials is broken.

**Files analyzed (no changes required):**

- `lib/app/constants/demo_credentials.dart` — correctly uses `String.fromEnvironment`
- `lib/features/auth/login_screen.dart` — 7-tap gesture and demo login logic work correctly

---

## Files to Create

None.

---

## Files to Modify

| File                  | What changes                                                                                                                                                                                          |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --- | --- |
| `tools/deploy_web.sh` | Add `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD}" \` to the `flutter build web` command (locate at lines 240–251, after the last `--dart-define=FIREBASE_MEASUREMENT_ID` line, before the closing ` |     | `). |

**Optional enhancement:**
| File | What changes |
|------|-------------|
| `tools/deploy_web.sh` | Add validation check after loading `.env` (around line 73): `[[ -z "${DEMO_PASSWORD:-}" ]] && fail "DEMO_PASSWORD not set in .env"` |

---

## Files Off-Limits

| File                                      | Reason                                                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `lib/app/constants/demo_credentials.dart` | No change needed — correctly implements `String.fromEnvironment` pattern                          |
| `lib/features/auth/login_screen.dart`     | Demo login logic is correct — only build config is missing the credential                         |
| `tools/build_web.sh`                      | Not used in production deploys (per `docs/reference/deployment/deployment.md`) — do not reference |
| `tools/build_ios.sh`                      | Already correct                                                                                   |
| `tools/build_android.sh`                  | Already correct                                                                                   |
| `tools/build_mobile_release.sh`           | Already correct                                                                                   |
| All files in `lib/`, `test/`, `supabase/` | Not relevant to this build configuration fix                                                      |

---

## System Impact Map

| System                                 | Impact                                                         |
| -------------------------------------- | -------------------------------------------------------------- |
| Gigs                                   | unaffected                                                     |
| Rehearsals                             | unaffected                                                     |
| Setlists / Catalog                     | unaffected                                                     |
| Members / RBAC                         | unaffected                                                     |
| Auth / Session                         | affected (demo login only) — normal magic link auth unaffected |
| Routing                                | unaffected                                                     |
| Notifications                          | unaffected                                                     |
| Platform (iOS / Android / Web / macOS) | Web only — native platforms already work correctly             |

---

## Regression Risk

**Level**: **LOW**

**Rationale:**

- Single-line change to build script, not runtime code
- Does not modify app logic, database, routing, or core auth flows
- Only enables an existing feature that was already implemented but broken on web
- Native platforms unaffected (already include DEMO_PASSWORD correctly)
- Failure mode is safe: if DEMO_PASSWORD is wrong or missing, demo login fails gracefully with error message; normal auth is unaffected
- No changes to initialization order, state management, or shared providers

---

## Engineer Task Breakdown

### Task 1: Add DEMO_PASSWORD to web build command

**File**: `tools/deploy_web.sh`  
**Action**: Locate the `flutter build web \` command block (currently at lines 240–251, but search for the `flutter build web \` marker rather than relying on line numbers). Add a new line immediately after the last `--dart-define=FIREBASE_MEASUREMENT_ID` line:

```bash
--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD}" \
```

Ensure the backslash is present for line continuation.

### Task 2 (Optional): Add validation check for DEMO_PASSWORD

**File**: `tools/deploy_web.sh`  
**Action**: After the existing validation checks for `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `FIREBASE_API_KEY`, and `FIREBASE_APP_ID` (around line 73), add:

```bash
[[ -z "${DEMO_PASSWORD:-}" ]] && fail "DEMO_PASSWORD not set in .env"
```

### Task 3: Test build locally

**Action**: Run `tools/deploy_web.sh --preview` to verify:

1. Build completes successfully with the new flag
2. No errors or warnings about DEMO_PASSWORD
3. (Optional) Check build logs confirm `--dart-define=DEMO_PASSWORD` was passed

### Task 4: Verify deployed preview

**Action**: After preview deploy, navigate to the preview URL, tap logo 7 times, verify demo login succeeds.

### Task 5: Production deploy

**Action**: After preview verification passes, run `tools/deploy_web.sh` (production) and verify demo login on `app.bandroadie.com`.

---

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable** — this is a build configuration change, not a database migration or RPC function change. No pre-deployment tests are required.

### Tier 2 — Post-deployment

**POST-DEPLOY TEST 1: Verify DEMO_PASSWORD is compiled into web artifact**

- **Action**: Check the build logs from `flutter build web` to confirm the flag was passed
- **Expected**: Logs show `--dart-define=DEMO_PASSWORD=...` (value will be redacted in output)
- **Alternative**: Verify no "DEMO_PASSWORD not set in .env" error occurred during build

**POST-DEPLOY TEST 2: Functional test — demo login on preview deployment**

- **Action**:
  1. Navigate to preview deployment URL (from `deploy_web.sh --preview`)
  2. Tap BandRoadie logo 7 times on the sign-in page
  3. Observe authentication result
- **Expected**: Demo login succeeds, user is authenticated and routed to AppShell with demo band "The Banana Stand" loaded
- **Failure indicator**: Still seeing "Demo login failed: Invalid login credentials"

**POST-DEPLOY TEST 3: Functional test — demo login on production**

- **Action**:
  1. Open incognito/private window
  2. Navigate to `https://app.bandroadie.com`
  3. Tap logo 7 times
  4. Observe authentication result
- **Expected**: Demo login succeeds, user enters demo mode
- **Failure indicator**: "Invalid login credentials" error

**POST-DEPLOY TEST 4: Verify demo account exists in production Supabase**

- **Action**: Log into Supabase dashboard for project `nekwjxvgbveheooyorjo`, navigate to Authentication → Users, search for `hello@bandroadie.com`
- **Expected**: User exists with email confirmed
- **If missing**: Tony must create the demo account manually using the Supabase dashboard or CLI with the password stored in `.env`

**POST-DEPLOY TEST 5: Verify normal auth is unaffected**

- **Action**:
  1. On `app.bandroadie.com`, request a magic link for a real user account (not demo)
  2. Complete magic link auth flow
  3. Verify successful login
- **Expected**: Magic link auth works normally
- **Rationale**: Confirms demo login fix did not regress normal authentication

---

## QA Regression Areas

### Primary Verification

1. **Demo login on web**: 7-tap gesture on `app.bandroadie.com` → successful authentication to demo band
2. **Build process**: `deploy_web.sh` completes without errors when DEMO_PASSWORD is set in `.env`

### Regression Testing (Confirm No Impact)

1. **Magic link auth on web**: Normal email login still works
2. **iOS/Android/macOS demo login**: Native platforms still support demo login (should already work)
3. **Web sign-in page**: No UI or layout regressions from code changes (none expected — no UI code modified)
4. **AuthGate routing**: Demo login correctly triggers session state update and routes to AppShell

### Boundary Conditions to Test

1. **Missing DEMO_PASSWORD in .env**: If optional validation is implemented, build should fail with clear error message
2. **Wrong DEMO_PASSWORD**: Demo login should fail gracefully with error message, not crash
3. **Demo account doesn't exist in Supabase**: Login should fail with "Invalid login credentials" (same as before fix if account is missing)

---

## Rollout / Migration Strategy

**Not applicable** — this is a build-time fix with no runtime migration requirements.

**Post-deploy action required**: Tony must verify the demo account (`hello@bandroadie.com`) exists in the production Supabase project (`nekwjxvgbveheooyorjo`) with the password matching `.env`. If missing, create it via Supabase dashboard before deploying to production.

---

## Out of Scope

The following are explicitly NOT part of this fix:

1. Creating or rotating the demo account in Supabase (manual Tony task if needed)
2. Changing the demo email address or moving it to a different account
3. Adding demo login to native platforms (already works)
4. Implementing demo mode features or sample data (already exists)
5. Adding UI feedback for tap count progress (feature works, just shows "X more..." from tap 3 onwards)
6. Changing the tap count threshold from 7 to another number
7. Fixing `tools/build_web.sh` (not used in production deploys — leave as-is per deployment docs)
8. Updating `.env.example` (already correctly documents DEMO_PASSWORD)
9. Adding DEMO_PASSWORD to Makefile targets (Makefile is for local dev only, not production builds)
10. Any changes to the magic link auth flow or AuthGate routing logic
