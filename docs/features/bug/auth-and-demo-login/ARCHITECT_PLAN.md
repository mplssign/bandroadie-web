# ARCHITECT_PLAN — Auth and Demo Login Fixes

**Feature slug:** `bug/auth-and-demo-login`  
**Type:** Bug fix (3 issues)

---

## Problem Summary

Three independent authentication-related bugs affecting production:

1. **Android magic link loop** — Tapping magic link email opens browser instead of deep-linking back to app, causing login loop
2. **iOS crash after auth** — App crashes with `EXC_BAD_ACCESS (code=50)` immediately after auth state confirms (at "AUTH STEP 4/4")
3. **Demo login failure** — "Demo login" easter egg returns "invalid login credentials" due to missing password configuration

All three issues are production-critical:
- Issue 1 blocks all Android users from logging in via magic link
- Issue 2 blocks all iOS users from completing authentication
- Issue 3 blocks Play Store reviewers from accessing demo account

---

## Root Cause

### Issue 1 — Android Magic Link Loop

**Confidence: HIGH (confirmed in code)**

**Primary cause:** Redirect URL mismatch between code and `supabase/config.toml`. The code requests the correct URL, but the config file lists a stale custom scheme that is not configured in AndroidManifest.

**Evidence from code inspection:**
- `lib/features/auth/login_screen.dart` lines 407-417: Platform-specific redirect URL selection
  - Web: `https://app.bandroadie.com/auth/confirm`
  - **Android: `https://app.bandroadie.com/auth/callback`** (intentional use of verified App Link)
  - iOS/macOS: `bandroadie://login-callback/` (custom scheme)
- `android/app/src/main/AndroidManifest.xml` lines 45-56: Verified Android App Links intent filter
  - `android:autoVerify="true"`
  - `android:scheme="https"`
  - `android:host="app.bandroadie.com"` AND `android:host="bandroadie.com"`
  - `android:pathPrefix="/auth"` — matches `/auth/callback` ✅
- `supabase/config.toml` line 50: `additional_redirect_urls` lists:
  - `https://app.bandroadie.com` (missing path, won't match `/auth/callback`)
  - `https://bandroadie.com` (missing path)
  - `com.bandroadie.app://callback` (stale custom scheme — AndroidManifest has NO intent filter for this scheme)

**Data flow:**
1. User requests magic link → code passes `emailRedirectTo: 'https://app.bandroadie.com/auth/callback'`
2. Supabase validates the redirect URL against its allowed list
3. If `https://app.bandroadie.com/auth/callback` is not in the allowed list, Supabase rejects or modifies the URL
4. User taps link in email → Android can't intercept the URL → opens in browser → login loop

**Failure layer:** Configuration mismatch between code (requests `https://app.bandroadie.com/auth/callback`) and `supabase/config.toml` (lists stale `com.bandroadie.app://callback`).

**Why the code is correct:**
- Android App Links require `https://` scheme with `android:autoVerify="true"`
- The AndroidManifest is correctly configured to intercept `https://app.bandroadie.com/auth/*`
- The code's selection logic is intentional and correct
- The config file has stale entries

### Issue 2 — iOS Crash After Auth

**Confidence: HIGH (confirmed in code)**

**Primary cause:** Missing `mounted` guard in `ref.listenManual` callback before calling `setState()` and async methods that access widget state. When auth state changes and the callback fires on a disposed widget, accessing `setState()` causes `EXC_BAD_ACCESS`.

**Evidence from code inspection:**
- `lib/features/auth/auth_gate.dart` lines 146-166: `ref.listenManual(authStateProvider, ...)` callback
  - **Line 148:** `setState(...)` called with NO `mounted` guard before it ❌
  - Line 157: `_checkProfileComplete()` called without `mounted` guard
  - Line 159: `_registerPushToken()` called without `mounted` guard
  - Line 162: Another `setState(...)` called without `mounted` guard
- Crash timing: "AUTH STEP 4/4" indicates `onAuthStateChange` fired with `authenticated: true`
- Crash signature: `EXC_BAD_ACCESS (code=50)` on DartWorker thread — memory access violation, typically from calling `setState()` on a disposed `StatefulWidget`

**Exact failure sequence:**
1. User taps magic link → deep link handler calls `supabase.auth.exchangeCodeForSession(code)`
2. Session exchange succeeds → `authStateProvider` fires state change via `onAuthStateChange`
3. `ref.listenManual` callback (lines 146-166) is invoked
4. If the `AuthGate` widget was disposed or not yet fully mounted (e.g., during rapid navigation or app resume edge cases), the callback still fires
5. Line 148 calls `setState()` on the disposed widget → `EXC_BAD_ACCESS`

**Why other methods contribute to crash risk:**
- `_checkProfileComplete()` and `_registerPushToken()` both perform async operations (Supabase queries, SharedPreferences, FCM initialization)
- If called without checking `mounted` first, any `setState()` or `ref.read()` after an async gap can crash if the widget was disposed

**Failure layer:** Missing lifecycle guard in `AuthGate._initializeAuth()` listener callback.

### Issue 3 — Demo Login Failure

**Confidence: HIGH (confirmed in code)**

**Primary cause:** `DEMO_PASSWORD` is not included in `dart_defines.json` generated by `tools/gen_dart_defines.sh`. When production builds rely solely on `dart_defines.json`, the password is an empty string, causing authentication to fail.

**Evidence from code inspection:**
- `lib/app/constants/demo_credentials.dart` lines 13-21:
  - `kDemoEmail = 'bandroadie2026@gmail.com'` (hardcoded)
  - `kDemoPassword = String.fromEnvironment('DEMO_PASSWORD', defaultValue: '')` (compile-time injection, defaults to empty string if not provided)
- `.env` file line 11: `DEMO_PASSWORD=BandRoadie-Demo-2026!`
- `tools/gen_dart_defines.sh` lines 28-37: Generates JSON with Firebase and Supabase credentials **but does NOT include DEMO_PASSWORD**
- `tools/build_android.sh` line 81: Passes `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"` ✅
- `tools/build_ios.sh` lines 95, 103: Pass `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"` ✅
- **BUT** `tools/build_ios.sh` lines 92, 100 also use `--dart-define-from-file=dart_defines.json`

**Why this causes failure:**
- When both `--dart-define` and `--dart-define-from-file` are used, Flutter merges them with `--dart-define` taking precedence
- However, if a production build process uses ONLY `--dart-define-from-file=dart_defines.json` (e.g., in CI/CD or a different build command), `DEMO_PASSWORD` is missing
- `kDemoPassword` defaults to `""`, causing `signInWithPassword` to fail with "invalid login credentials"

**Safest fix:** Add `DEMO_PASSWORD` to `gen_dart_defines.sh` so it's always present in `dart_defines.json`, removing any ambiguity or dependency on separate `--dart-define` flags.

**Note:** `.env` has `DEMO_EMAIL=hello@bandroadie.com` but code hardcodes `bandroadie2026@gmail.com` — the `.env` value is stale and not used.

**Failure layer:** Build configuration — `gen_dart_defines.sh` does not emit DEMO_PASSWORD.

---

## Reference Docs Consulted

- `docs/agents/ARCHITECT.md` — Architect role definition and execution phases
- `docs/agents/GUARDRAILS.md` — Technical constraints (config rules, initialization order, async safety)
- `docs/agents/OPERATING_MODEL.md` — Four-role pipeline, gates, parallelization policy

**Code files inspected (read in full):**
- `lib/features/auth/login_screen.dart` — Platform-specific redirect URL selection (lines 407-417)
- `lib/features/auth/auth_gate.dart` — Auth state listener and post-auth initialization (lines 146-243)
- `lib/features/bands/active_band_controller.dart` — Band loading and persistence (lines 258-290)
- `android/app/src/main/AndroidManifest.xml` — Verified App Links intent filter configuration
- `supabase/config.toml` — Local development redirect URL configuration
- `tools/gen_dart_defines.sh` — Compile-time config generation
- `tools/build_android.sh` — Android build with --dart-define flags
- `tools/build_ios.sh` — iOS build with --dart-define and --dart-define-from-file
- `lib/app/constants/demo_credentials.dart` — Demo account credentials and compile-time injection
- `web/.well-known/assetlinks.json` — Android App Links verification file

---

## Existing System Analysis

### Auth Flow — Native Platforms (iOS/Android)

1. **Login request:** User enters email in `LoginScreen`, taps "Send Magic Link"
2. **Redirect URL selection** (`login_screen.dart` lines 407-417):
   - **Web:** `https://app.bandroadie.com/auth/confirm`
   - **Android:** `https://app.bandroadie.com/auth/callback` (verified App Link)
   - **iOS/macOS:** `bandroadie://login-callback/` (custom scheme)
3. **Supabase sends email** with magic link containing PKCE `code` parameter
4. **User taps link:**
   - **iOS:** Custom scheme `bandroadie://` triggers app via CFBundleURLSchemes in `Info.plist`
   - **Android:** Verified app link `https://app.bandroadie.com/auth/callback` is intercepted by Android App Links if `assetlinks.json` is deployed and verified
5. **Deep link handling:** `DeepLinkService` captures URI via `app_links` package
6. **Session exchange:** `DeepLinkService._handleDeepLink()` calls `supabase.auth.exchangeCodeForSession(code)`
7. **Auth state update:** `authStateProvider` fires state change via `onAuthStateChange`
8. **AuthGate reacts** (`auth_gate.dart` lines 146-166):
   - `ref.listenManual` callback fires when `isAuthenticated` changes to `true`
   - **Line 148:** `setState()` resets profile state (NO `mounted` guard) ❌
   - **Line 157:** `_checkProfileComplete()` queries `users` table, then calls `loadUserBands()` on success
   - **Line 159:** `_registerPushToken()` initializes `PushNotificationService`, requests permissions, registers FCM token
9. **Routing:** AuthGate renders `ProfileGateScreen` (if profile incomplete) or `AppShell` / `NoBandShell` (if complete)

**Current failure points:**
- **Android (Issue 1):** Step 4 fails — Supabase rejects/modifies redirect URL because `https://app.bandroadie.com/auth/callback` is not in the allowed list, causing link to open in browser
- **iOS (Issue 2):** Step 8 crashes — `setState()` called on disposed widget in listener callback (line 148), causing `EXC_BAD_ACCESS`

### Demo Login Flow

1. User taps BandRoadie logo 7 times in rapid succession (`login_screen.dart` lines 165-185)
2. `LoginScreen._triggerDemoLogin()` calls `supabase.auth.signInWithPassword(email: kDemoEmail, password: kDemoPassword)`
3. On success, `authStateProvider` fires state change and AuthGate routes to `AppShell`
4. Demo user belongs to "The Banana Stand" band (band_id: `9187f897-1731-4337-bbd3-4f80afbe88ec`)

**Current failure:** Step 2 fails with "invalid login credentials" because `kDemoPassword` is empty string in production builds that rely solely on `dart_defines.json`.

---

## Proposed Solution

### Fix 1 — Android Magic Link Loop

**Change:** Update `supabase/config.toml` to list the exact redirect URLs that the code requests, replacing stale entries.

**Implementation:**
1. Update `supabase/config.toml` line 50 `additional_redirect_urls` array to:
   ```toml
   additional_redirect_urls = [
     "https://app.bandroadie.com/auth/confirm",
     "https://app.bandroadie.com/auth/callback",
     "bandroadie://login-callback/"
   ]
   ```
2. **Critical:** Engineer must verify production Supabase dashboard (Authentication → URL Configuration → Redirect URLs) includes the same three URLs:
   - `https://app.bandroadie.com/auth/confirm` (web)
   - `https://app.bandroadie.com/auth/callback` (Android verified App Link)
   - `bandroadie://login-callback/` (iOS/macOS custom scheme)
3. Remove stale URLs from production dashboard:
   - `https://app.bandroadie.com` (missing path)
   - `https://bandroadie.com` (missing path)
   - `com.bandroadie.app://callback` (stale custom scheme not in AndroidManifest)

**Why this fixes it:**
- The code requests `https://app.bandroadie.com/auth/callback` for Android (line 414 of `login_screen.dart`)
- AndroidManifest has a verified App Links intent filter for `https://app.bandroadie.com` with `android:pathPrefix="/auth"` and `android:autoVerify="true"`
- When Supabase's allowed redirect URLs list includes `https://app.bandroadie.com/auth/callback`, the magic link email contains this URL
- When the user taps the link, Android OS recognizes the URL as belonging to the app (via App Links verification) and opens the app directly
- The app never opens in the browser

**Verification:**
- Android App Links verification can be tested via:
  ```bash
  adb shell pm get-app-links com.bandroadie.app
  ```
  This should show `app.bandroadie.com` with state `verified`.
- Manual test: Request magic link on Android device, tap link in Gmail, confirm app opens directly (no browser shown)
- Verify `assetlinks.json` is deployed at both:
  - `https://app.bandroadie.com/.well-known/assetlinks.json`
  - `https://bandroadie.com/.well-known/assetlinks.json` (if `bandroadie.com` is also listed in intent filter)

**Note:** The file `web/.well-known/assetlinks.json` exists with correct SHA-256 fingerprints. Ensure this file is deployed at the production URLs above.

### Fix 2 — iOS Crash After Auth

**Change:** Add `mounted` guard in `AuthGate._initializeAuth()` listener callback before any `setState()` or method calls that access widget state.

**Root cause confirmed:** `ref.listenManual` callback (lines 146-166 of `auth_gate.dart`) calls `setState()` and async methods without checking if the widget is still mounted. When auth state changes and the widget is disposed, accessing `setState()` causes `EXC_BAD_ACCESS`.

**Implementation:**

1. In `lib/features/auth/auth_gate.dart` line 147, immediately after the `debugPrint` and before any `setState()` or method calls, add:
   ```dart
   ref.listenManual(authStateProvider, (previous, next) {
     debugPrint(
       '[AuthGate] Auth state changed: ${previous?.isAuthenticated} -> ${next.isAuthenticated}',
     );

     // SAFEGUARD: If widget is disposed, do not attempt state changes
     if (!mounted) return;

     // Session state changed
     if (previous?.isAuthenticated != next.isAuthenticated) {
       // ... existing code
   ```

2. No other changes required. The existing `mounted` guards in `_checkProfileComplete()` (lines 223, 238) and error handling are sufficient once the listener callback itself is guarded.

**Why this fixes it:**
- The crash occurs at "AUTH STEP 4/4" when `authStateProvider` fires a state change
- The `ref.listenManual` callback is invoked even if the widget is disposed
- Without a `mounted` guard, line 148 calls `setState()` on a disposed StatefulWidget → `EXC_BAD_ACCESS`
- Adding `if (!mounted) return;` prevents any state mutations on a disposed widget

**Why NOT to use `WidgetsBinding.instance.addPostFrameCallback`:**
- Post-frame callbacks defer async work unnecessarily, introducing timing complexity
- The issue is not "widget tree not ready" — it's "widget disposed before callback runs"
- A simple `mounted` guard is the correct Flutter pattern for listener callbacks

**Verification:**
- Test on physical iPhone: Request magic link, tap link in Mail app, confirm app opens without crash
- Monitor Xcode console: Should see "AUTH STEP 4/4" followed by profile check and band load logs (no crash)
- Test both cold start (app killed) and warm resume (app backgrounded) scenarios
- If crash persists, check Xcode crash logs for exact line number and stack trace

### Fix 3 — Demo Login Failure

**Change:** Add `DEMO_PASSWORD` to `tools/gen_dart_defines.sh` JSON output so it's always available in `dart_defines.json`.

**Implementation:**
1. Update `tools/gen_dart_defines.sh` line 37 (end of JSON block) to add `DEMO_PASSWORD`:
   ```bash
   cat > "$OUTPUT_FILE" <<EOF
   {
     "SUPABASE_URL": "${SUPABASE_URL}",
     "SUPABASE_ANON_KEY": "${SUPABASE_ANON_KEY}",
     "FIREBASE_API_KEY": "${FIREBASE_API_KEY:-}",
     "FIREBASE_AUTH_DOMAIN": "${FIREBASE_AUTH_DOMAIN:-}",
     "FIREBASE_PROJECT_ID": "${FIREBASE_PROJECT_ID:-}",
     "FIREBASE_STORAGE_BUCKET": "${FIREBASE_STORAGE_BUCKET:-}",
     "FIREBASE_MESSAGING_SENDER_ID": "${FIREBASE_MESSAGING_SENDER_ID:-}",
     "FIREBASE_APP_ID": "${FIREBASE_APP_ID:-}",
     "FIREBASE_MEASUREMENT_ID": "${FIREBASE_MEASUREMENT_ID:-}",
     "DEMO_PASSWORD": "${DEMO_PASSWORD:-}"
   }
   EOF
   ```

2. **Critical:** Engineer must verify the demo user exists in Supabase production:
   - Log into Supabase dashboard: https://supabase.com/dashboard/project/nekwjxvgbveheooyorjo
   - Navigate to: Authentication → Users
   - Confirm user `bandroadie2026@gmail.com` exists and can authenticate with password `BandRoadie-Demo-2026!`
   - If user does not exist or password is incorrect, demo login will still fail even after this fix

3. Optional: Update `.env` comment at line 10 to clarify:
   ```bash
   # DEMO_EMAIL is not used in code — email is hardcoded as bandroadie2026@gmail.com
   DEMO_EMAIL=hello@bandroadie.com
   DEMO_PASSWORD=BandRoadie-Demo-2026!
   ```

**Why this fixes it:**
- `kDemoPassword` is injected via `String.fromEnvironment('DEMO_PASSWORD', defaultValue: '')`
- If `DEMO_PASSWORD` is not in `dart_defines.json` and not passed via `--dart-define`, it defaults to empty string `""`
- Adding it to `gen_dart_defines.sh` ensures all builds (including those using only `--dart-define-from-file`) have the password
- Removes dependency on separate `--dart-define=DEMO_PASSWORD` flags in build scripts

**Compliance with GUARDRAILS:**
- ✅ No runtime `.env` loading — password is compile-time injected only
- ✅ No hardcoded secrets in source — password is in `.env` (gitignored) and injected at build time
- ✅ No `flutter_dotenv` or equivalent introduced
- ✅ Uses existing compile-time injection pattern (`String.fromEnvironment`)

**Verification:**
- Local test: Run `./tools/gen_dart_defines.sh` and confirm `dart_defines.json` contains `"DEMO_PASSWORD": "BandRoadie-Demo-2026!"`
- Build test: Build Android/iOS release (`./tools/build_android.sh --apk` or `./tools/build_ios.sh`), install on device, tap logo 7 times, confirm demo login succeeds
- Production test: On TestFlight or Play Store internal test track, confirm demo login works and user is logged into "The Banana Stand" band

**Security note:** `DEMO_PASSWORD` is visible in `dart_defines.json` (which is gitignored). The password is not a production user password — it's specifically for Play Store reviewers. The demo account should have read-only or limited access to a demo band.

---

## Database Impact

**Not applicable** — all three issues are client-side configuration or code bugs. No database schema, RLS policies, RPCs, or triggers are affected.

**Supabase dashboard impact (manual verification required):**
- Issue 1: Engineer must verify production Supabase dashboard includes correct redirect URLs in Authentication → URL Configuration
- Issue 3: Engineer must verify demo user `bandroadie2026@gmail.com` exists in Authentication → Users with correct password

---

## Flutter Architecture Changes

### State Management

**Issue 2 fix affects:**
- `lib/features/auth/auth_gate.dart` — Add `mounted` guard in `_initializeAuth()` listener callback before any state mutations

**No new controllers or providers required.**

### Widgets

**No widget changes required** — Issue 2 fix adds a single defensive guard only.

### Repositories

**No repository changes required.**

---

## Files to Create

**None** — all fixes are modifications to existing files.

---

## Files to Modify

| File | What changes | Lines affected |
|------|-------------|----------------|
| `supabase/config.toml` | Update `additional_redirect_urls` array to list exact URLs requested by code: `["https://app.bandroadie.com/auth/confirm", "https://app.bandroadie.com/auth/callback", "bandroadie://login-callback/"]` | Line 50 |
| `tools/gen_dart_defines.sh` | Add `"DEMO_PASSWORD": "${DEMO_PASSWORD:-}"` to JSON output (before closing brace) | Line 37 |
| `lib/features/auth/auth_gate.dart` | Add `if (!mounted) return;` guard immediately after the `debugPrint` in `ref.listenManual` callback, before any `setState()` or method calls | Line 147 (after existing debugPrint, before line 149) |
| `.env` (optional) | Add comment above `DEMO_EMAIL` line: `# DEMO_EMAIL is not used — email is hardcoded as bandroadie2026@gmail.com` | Line 10 |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/main.dart` | Initialization order must not change (GUARDRAILS §1) |
| `lib/app/services/deep_link_service.dart` | Deep link handling logic is correct — issue is redirect URL config in Supabase, not deep link parsing logic |
| `android/app/src/main/AndroidManifest.xml` | Intent filters are correctly configured for verified App Links — issue is Supabase redirect URL allowlist, not Android config |
| `ios/Runner/Info.plist` | CFBundleURLSchemes is correctly configured for iOS custom scheme |
| `lib/app/constants/demo_credentials.dart` | Email and password injection pattern is correct — issue is missing value in `dart_defines.json`, not the code that reads it |
| `lib/features/auth/login_screen.dart` | Platform-specific redirect URL selection logic is correct and intentional |
| `lib/features/bands/active_band_controller.dart` | No null guard needed — `_bandRepository` is a getter that reads from a provider, always returns a value. Issue is in the caller (auth_gate), not here |
| `lib/features/auth/auth_gate.dart` except line 147 | Other methods (`_checkProfileComplete()`, `_registerPushToken()`) have sufficient guards once the listener callback itself is guarded |

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | **affected** — Issue 1 fixes Android magic link deep linking; Issue 2 fixes iOS post-auth crash; Issue 3 fixes demo login |
| Routing | **affected (minor)** — Issue 2 fix prevents crash before AuthGate routing completes |
| Notifications | unaffected — Issue 2 fix does not change push notification registration logic, only guards the caller |
| Platform (iOS) | **affected** — Issue 2 fix prevents iOS crash after auth |
| Platform (Android) | **affected** — Issue 1 fix enables Android deep linking for magic links |
| Platform (Web) | unaffected |
| Platform (macOS) | unaffected |

---

## Regression Risk

**Level:** MEDIUM

**Rationale:**
- Issue 1 fix changes only `supabase/config.toml` (configuration, not code) — low risk, but requires manual Supabase dashboard verification
- Issue 2 fix adds defensive guards to AuthGate initialization — medium risk, as this is a critical code path that runs for every authenticated user on every platform
- Issue 3 fix changes only `gen_dart_defines.sh` (build configuration, not runtime logic) — low risk

**Critical risk:** Issue 2 fix touches the auth initialization flow, which is the entry point for all authenticated users. If the `mounted` guards or post-frame callbacks are incorrect, users could be stuck on a loading screen or see a different crash.

**Mitigation:**
- Test Issue 2 fix on physical iPhone and iPad (not just simulator)
- Test both cold start (app killed, tap magic link) and warm start (app backgrounded, tap magic link)
- Test demo login on physical Android device (not just emulator)
- Verify Android deep link interception with `adb shell am start -a android.intent.action.VIEW -d "https://app.bandroadie.com/auth/callback?code=test"`

---

## Engineer Task Breakdown

### Task 1 — Fix Android Magic Link Deep Linking (Issue 1)

**Subtasks:**
1. Update `supabase/config.toml` line 50 `additional_redirect_urls` array:
   - **Remove:** `"com.bandroadie.app://callback"` (stale custom scheme)
   - **Replace with:**
     ```toml
     additional_redirect_urls = [
       "https://app.bandroadie.com/auth/confirm",
       "https://app.bandroadie.com/auth/callback",
       "bandroadie://login-callback/"
     ]
     ```
2. Commit change with message: `fix(auth): Update redirect URLs to match platform-specific code paths`
3. **CRITICAL MANUAL STEP:** Verify production Supabase dashboard configuration:
   - Log into: https://supabase.com/dashboard/project/nekwjxvgbveheooyorjo
   - Navigate to: Authentication → URL Configuration → Redirect URLs
   - Confirm the following URLs are present:
     - `https://app.bandroadie.com/auth/confirm` (web)
     - `https://app.bandroadie.com/auth/callback` (Android)
     - `bandroadie://login-callback/` (iOS/macOS)
   - Remove any stale URLs:
     - `https://app.bandroadie.com` (no path)
     - `https://bandroadie.com` (no path)
     - `com.bandroadie.app://callback` (old custom scheme)
   - Save changes
4. Document in ENGINEER_REPORT.md:
   - "Updated `supabase/config.toml` with correct redirect URLs"
   - "Verified production Supabase dashboard redirect URLs list (screenshot attached if possible)"
   - "Verified `assetlinks.json` is deployed at `https://app.bandroadie.com/.well-known/assetlinks.json`"

**Verification:**
```bash
# 1. Verify Android App Links status (connect Android device via USB)
adb shell pm get-app-links com.bandroadie.app
# Expected: app.bandroadie.com with state "verified"

# 2. Verify assetlinks.json is deployed
curl https://app.bandroadie.com/.well-known/assetlinks.json
# Expected: JSON with package_name "com.bandroadie.app" and SHA-256 fingerprints

# 3. Test manual deep link trigger
adb shell am start -a android.intent.action.VIEW \
  -d "https://app.bandroadie.com/auth/callback?code=test"
# Expected: App opens (may show error about invalid code, but app should open, not browser)

# 4. End-to-end test
# - Run app on Android device: flutter run -d <device-id>
# - Request magic link from LoginScreen
# - Check email on device, tap link
# - Expected: App opens directly (no browser), login succeeds
```

### Task 2 — Fix iOS Post-Auth Crash (Issue 2)

**Subtasks:**
1. Open `lib/features/auth/auth_gate.dart`
2. Locate `_initializeAuth()` method, specifically the `ref.listenManual(authStateProvider, ...)` callback starting at line 146
3. After the `debugPrint` statement (line 147) and before the `if (previous?.isAuthenticated != next.isAuthenticated)` check (line 149), add a mounted guard:
   ```dart
   ref.listenManual(authStateProvider, (previous, next) {
     debugPrint(
       '[AuthGate] Auth state changed: ${previous?.isAuthenticated} -> ${next.isAuthenticated}',
     );

     // SAFEGUARD: If widget is disposed, do not attempt state changes
     if (!mounted) return;

     // Session state changed
     if (previous?.isAuthenticated != next.isAuthenticated) {
       // ... existing code unchanged
   ```
4. No other changes required to `auth_gate.dart`
5. Commit with message: `fix(auth): Add mounted guard to prevent iOS post-auth crash`

**Verification:**
```bash
# 1. Build iOS release
./tools/build_ios.sh

# 2. Install on physical iPhone via Xcode
open ios/Runner.xcworkspace
# Select iPhone device, press Cmd+R to build and install

# 3. Cold start test (app killed)
# - Kill app completely (swipe up from app switcher)
# - Request magic link from LoginScreen
# - Tap link in Mail app
# - Expected: App launches, no crash, user lands in AppShell or ProfileGateScreen

# 4. Warm resume test (app backgrounded)
# - Minimize app to home screen (do not kill)
# - Request magic link from LoginScreen
# - Tap link in Mail app
# - Expected: App resumes from background, no crash, login succeeds

# 5. Monitor Xcode console for expected log sequence:
# - "AUTH STEP 4/4 — AUTH STATE UPDATED (authenticated: true, ...)"
# - "[AuthGate] Auth state changed: false -> true"
# - "[AuthGate] Initial session: present" (or similar profile check logs)
# - NO crash, NO "EXC_BAD_ACCESS"
```

### Task 3 — Fix Demo Login (Issue 3)

**Subtasks:**
1. Open `tools/gen_dart_defines.sh`
2. Locate the `cat > "$OUTPUT_FILE" <<EOF` block (lines 28-37)
3. Add `DEMO_PASSWORD` to the JSON output before the closing brace:
   ```bash
   cat > "$OUTPUT_FILE" <<EOF
   {
     "SUPABASE_URL": "${SUPABASE_URL}",
     "SUPABASE_ANON_KEY": "${SUPABASE_ANON_KEY}",
     "FIREBASE_API_KEY": "${FIREBASE_API_KEY:-}",
     "FIREBASE_AUTH_DOMAIN": "${FIREBASE_AUTH_DOMAIN:-}",
     "FIREBASE_PROJECT_ID": "${FIREBASE_PROJECT_ID:-}",
     "FIREBASE_STORAGE_BUCKET": "${FIREBASE_STORAGE_BUCKET:-}",
     "FIREBASE_MESSAGING_SENDER_ID": "${FIREBASE_MESSAGING_SENDER_ID:-}",
     "FIREBASE_APP_ID": "${FIREBASE_APP_ID:-}",
     "FIREBASE_MEASUREMENT_ID": "${FIREBASE_MEASUREMENT_ID:-}",
     "DEMO_PASSWORD": "${DEMO_PASSWORD:-}"
   }
   EOF
   ```
4. Run `./tools/gen_dart_defines.sh` to regenerate `dart_defines.json`
5. Verify `dart_defines.json` contains `"DEMO_PASSWORD": "BandRoadie-Demo-2026!"`
6. Optional: Add comment to `.env` at line 10:
   ```bash
   # DEMO_EMAIL is not used in code — email is hardcoded as bandroadie2026@gmail.com
   DEMO_EMAIL=hello@bandroadie.com
   DEMO_PASSWORD=BandRoadie-Demo-2026!
   ```
7. **CRITICAL MANUAL STEP:** Verify demo user exists in Supabase production:
   - Log into: https://supabase.com/dashboard/project/nekwjxvgbveheooyorjo
   - Navigate to: Authentication → Users
   - Search for: `bandroadie2026@gmail.com`
   - Confirm user exists and is enabled
   - Test authentication (if possible via Supabase dashboard or SQL Editor):
     ```sql
     -- This query verifies the user exists
     SELECT id, email, created_at FROM auth.users WHERE email = 'bandroadie2026@gmail.com';
     ```
   - If user does not exist or password is incorrect, create/update user before proceeding
8. Commit with message: `fix(auth): Include DEMO_PASSWORD in dart_defines.json for production builds`
9. Document in ENGINEER_REPORT.md:
   - "Updated `gen_dart_defines.sh` to include DEMO_PASSWORD"
   - "Verified demo user `bandroadie2026@gmail.com` exists in production Supabase"
   - "Regenerated `dart_defines.json` and confirmed DEMO_PASSWORD is present"

**Verification:**
```bash
# 1. Verify dart_defines.json contains DEMO_PASSWORD
./tools/gen_dart_defines.sh
grep "DEMO_PASSWORD" dart_defines.json
# Expected: "DEMO_PASSWORD": "BandRoadie-Demo-2026!"

# 2. Build Android release and test
./tools/build_android.sh --apk
# Install APK on device
adb install -r build/app/outputs/flutter-apk/app-release.apk
# Open app, navigate to LoginScreen
# Tap BandRoadie logo 7 times rapidly
# Expected: Demo login succeeds, user is logged into "The Banana Stand" band

# 3. Build iOS release and test
./tools/build_ios.sh
# Install on iPhone via Xcode
# Open app, tap logo 7 times rapidly
# Expected: Demo login succeeds

# 4. Production test (after deployment to TestFlight/Play Store)
# - Install from TestFlight or Play Store internal test track
# - Tap logo 7 times on LoginScreen
# - Expected: Demo login succeeds, lands in AppShell with demo band selected
```

---

## Verification Plan

### Pre-Deployment (Tier 1)

**No Tier 1 database tests required** — all three issues are client-side configuration or code bugs with no database schema impact.

**Manual verification required:**
1. Engineer must verify production Supabase dashboard redirect URLs (Issue 1)
2. Engineer must verify demo user exists in production Supabase (Issue 3)

### Post-Deployment (Tier 2)

**Test 1 — Android Magic Link Deep Linking**
```bash
# Prerequisites:
# - Physical Android device (not emulator) connected via USB
# - Gmail or other email client installed and signed in

# Step 1: Verify App Links verification status
adb shell pm get-app-links com.bandroadie.app
# Expected: app.bandroadie.com with state "verified"
# If state is "none" or "legacy_failure", run:
adb shell pm verify-app-links --re-verify com.bandroadie.app

# Step 2: Verify assetlinks.json deployment
curl https://app.bandroadie.com/.well-known/assetlinks.json
# Expected: JSON response with "package_name": "com.bandroadie.app"

# Step 3: Test manual deep link interception
adb shell am start -a android.intent.action.VIEW \
  -d "https://app.bandroadie.com/auth/callback?code=test123"
# Expected: App opens (may show error about invalid code, but app MUST open, not browser)

# Step 4: End-to-end magic link flow
# - Open BandRoadie on Android device
# - Navigate to LoginScreen, enter email, tap "Send Magic Link"
# - Wait for email to arrive
# - Tap magic link in email client
# - Expected: App opens directly (no browser shown), login succeeds, user lands in AppShell
```

**Test 2 — iOS Post-Auth Stability**
```bash
# Prerequisites:
# - Physical iPhone (not simulator)
# - Xcode installed with iOS device configured

# Step 1: Build and install
./tools/build_ios.sh
open ios/Runner.xcworkspace
# Select iPhone device, press Cmd+R to build and run

# Step 2: Cold start test (app killed)
# - Kill app completely (swipe up from app switcher)
# - Request magic link from LoginScreen
# - Tap link in Mail app
# - Expected: App launches, no crash, user lands in AppShell or ProfileGateScreen
# - Monitor Xcode console: Should see "AUTH STEP 4/4" followed by profile check logs

# Step 3: Warm resume test (app backgrounded)
# - Minimize app to home screen (do not kill)
# - Request magic link from LoginScreen
# - Tap link in Mail app
# - Expected: App resumes from background, no crash, login succeeds

# Step 4: Check Xcode console for expected log sequence
# Expected logs:
# - "AUTH STEP 4/4 — AUTH STATE UPDATED (authenticated: true, ...)"
# - "[AuthGate] Auth state changed: false -> true"
# - "[AuthGate] Initial session: present" or profile check logs
# - NO "EXC_BAD_ACCESS" or crash logs
```

**Test 3 — Demo Login Functionality**
```bash
# Prerequisites:
# - Android device or emulator
# - iOS device (physical or simulator)

# Step 1: Verify dart_defines.json
cat dart_defines.json | grep DEMO_PASSWORD
# Expected: "DEMO_PASSWORD": "BandRoadie-Demo-2026!"

# Step 2: Test on Android
./tools/build_android.sh --apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
# - Open app, navigate to LoginScreen
# - Tap BandRoadie logo 7 times rapidly (within 3 seconds)
# - Expected: Success message, automatic login, lands in AppShell with "The Banana Stand" band selected

# Step 3: Test on iOS
./tools/build_ios.sh
# Install via Xcode
# - Open app, tap logo 7 times rapidly
# - Expected: Demo login succeeds, lands in AppShell with demo band

# Step 4: Verify demo band access
# After demo login, confirm:
# - Active band name is "The Banana Stand"
# - Can view setlists, songs, members
# - Can navigate between tabs
```

**Test 4 — Production Supabase Dashboard Verification (Critical)**

**Redirect URLs (Issue 1):**
1. Log into: https://supabase.com/dashboard/project/nekwjxvgbveheooyorjo
2. Navigate to: Authentication → URL Configuration → Redirect URLs
3. Confirm the following URLs are present:
   - `https://app.bandroadie.com/auth/confirm` (web)
   - `https://app.bandroadie.com/auth/callback` (Android)
   - `bandroadie://login-callback/` (iOS/macOS)
4. Remove any stale URLs:
   - `https://app.bandroadie.com` (missing path)
   - `https://bandroadie.com` (missing path)
   - `com.bandroadie.app://callback` (old custom scheme)
5. Save changes
6. Screenshot for ENGINEER_REPORT.md

**Demo User (Issue 3):**
1. Navigate to: Authentication → Users
2. Search for: `bandroadie2026@gmail.com`
3. Confirm user exists and is enabled
4. Optional: Test login via Supabase SQL Editor:
   ```sql
   SELECT id, email, created_at, confirmed_at 
   FROM auth.users 
   WHERE email = 'bandroadie2026@gmail.com';
   ```
5. Confirm user has `confirmed_at` timestamp (email confirmed)
6. Confirm user is member of demo band "The Banana Stand":
   ```sql
   SELECT bm.id, bm.role, b.name 
   FROM band_members bm
   JOIN bands b ON b.id = bm.band_id
   WHERE bm.user_id = (SELECT id FROM auth.users WHERE email = 'bandroadie2026@gmail.com');
   ```
7. Expected result: One row with band name "The Banana Stand"

**Test 5 — Android App Links Verification (Detailed)**

```bash
# Connect Android device
adb devices

# Check current verification state
adb shell pm get-app-links com.bandroadie.app
# Expected output format:
#   com.bandroadie.app:
#     ID: <uuid>
#     Signatures: <sha256>
#     Domain verification state:
#       app.bandroadie.com: verified
#       bandroadie.com: verified  (if both domains are in intent filter)

# If state is "none" or "legacy_failure", re-verify
adb shell pm verify-app-links --re-verify com.bandroadie.app

# Verify assetlinks.json for both domains
curl https://app.bandroadie.com/.well-known/assetlinks.json
curl https://bandroadie.com/.well-known/assetlinks.json
# Expected: Both should return JSON with package_name "com.bandroadie.app" and matching SHA-256 fingerprints
# If either 404s, deploy web/.well-known/assetlinks.json to that domain

# Test deep link manually
adb shell am start -a android.intent.action.VIEW \
  -d "https://app.bandroadie.com/auth/callback?code=test"
# Expected: App opens (may show error about invalid code, but APP OPENS, not browser)
```

---

## QA Regression Areas

### Primary Testing (must pass before release)

**1. Android magic link end-to-end**
- **Platform:** Physical Android device (not emulator — App Links verification requires physical device)
- **Prerequisites:** Device connected to internet, Gmail or email client installed
- **Flow:**
  1. Open BandRoadie, navigate to LoginScreen
  2. Enter email address, tap "Send Magic Link"
  3. Observe success message: "Check your email for the login link"
  4. Open email client (Gmail, Outlook, etc.)
  5. Tap magic link in email
- **Success criteria:**
  - No browser is shown at any point
  - App opens directly when link is tapped
  - Login completes successfully
  - User lands in AppShell (if they have bands) or NoBandShell (if they don't)
  - No error messages or crashes

**2. iOS magic link end-to-end**
- **Platform:** Physical iPhone (not simulator — push notifications and lifecycle behavior differ)
- **Flow:**
  1. Open BandRoadie, navigate to LoginScreen
  2. Request magic link
  3. Tap link in Mail app
- **Success criteria:**
  - App opens without crash
  - User lands in AppShell or ProfileGateScreen (if profile incomplete)
  - Xcode console shows "AUTH STEP 4/4" followed by profile check logs
  - NO `EXC_BAD_ACCESS` or crash logs
- **Test both scenarios:**
  - Cold start: Kill app, tap link, app launches
  - Warm resume: Minimize app, tap link, app resumes from background

**3. Demo login (both platforms)**
- **Platform:** Android and iOS
- **Flow:**
  1. On LoginScreen, tap BandRoadie logo 7 times rapidly (within 3 seconds)
  2. Observe demo login triggered
- **Success criteria:**
  - User logs in as demo user
  - Active band is "The Banana Stand"
  - Can navigate to Setlists, Gigs, Members tabs
  - No errors or crashes
- **Test on both:**
  - Android release build (via `./tools/build_android.sh --apk`)
  - iOS release build (via `./tools/build_ios.sh`)

### Secondary Testing (regression checks)

**4. Web magic link (no regression)**
- **Platform:** Chrome on desktop, Safari on macOS
- **Flow:** Request magic link → click link in webmail → confirm login succeeds
- **Success criteria:** No change in behavior (web flow unchanged by these fixes)
- **Note:** Web uses different redirect URL (`/auth/confirm` instead of `/auth/callback`)

**5. Magic link cold start (iOS/Android)**
- **Platform:** Physical device for each platform
- **Flow:**
  1. Kill app completely (swipe up from app switcher on iOS, force stop on Android)
  2. Request magic link (via web or another device)
  3. Tap link in email
- **Success criteria:**
  - App launches from killed state
  - Deep link is handled correctly
  - Login succeeds
  - User lands in correct screen (AppShell or ProfileGateScreen)

**6. Magic link warm resume (iOS/Android)**
- **Platform:** Physical device for each platform
- **Flow:**
  1. Minimize app to home screen (do not kill)
  2. Request magic link
  3. Tap link in email
- **Success criteria:**
  - App resumes from background
  - Login succeeds
  - No crash or state loss

**7. Profile completion after auth (iOS)**
- **Platform:** Physical iPhone
- **Prerequisites:** New user account with no profile data (first_name/last_name are NULL)
- **Flow:**
  1. New user taps magic link
  2. App opens after auth
  3. Confirm ProfileGateScreen renders (not crash)
  4. User enters first name and last name
  5. Tap "Save"
- **Success criteria:**
  - ProfileGateScreen renders without crash
  - User can save profile
  - After save, user lands in AppShell or NoBandShell
  - No `EXC_BAD_ACCESS` at any point

**8. Push notification registration (iOS)**
- **Platform:** Physical iPhone with push permissions granted
- **Flow:**
  1. Ensure notification permissions are granted (Settings → BandRoadie → Notifications)
  2. Tap magic link, log in
  3. Monitor Xcode console
- **Success criteria:**
  - Console shows push token registration logs
  - No crash during push service initialization
  - No `EXC_BAD_ACCESS` in `_registerPushToken()`

**9. Band loading after auth (iOS/Android)**
- **Platform:** Both platforms
- **Prerequisites:** User is member of at least one band
- **Flow:**
  1. Tap magic link, log in
  2. Observe band loading
- **Success criteria:**
  - User's bands are loaded from Supabase
  - Previously selected band is restored from SharedPreferences
  - If no persisted selection, first band is selected
  - Active band is displayed in AppShell
  - No crash in `activeBandProvider.loadUserBands()`

**10. Demo login cooldown (both platforms)**
- **Platform:** Android and iOS
- **Flow:**
  1. Tap logo 7 times → demo login succeeds
  2. Log out
  3. Immediately tap logo 7 times again
- **Success criteria:**
  - Second demo login also succeeds
  - No rate limiting or cooldown for demo login (different from magic link cooldown)

**11. Magic link cooldown (both platforms)**
- **Platform:** Android and iOS
- **Flow:**
  1. Request magic link → observe success message
  2. Immediately request another magic link
- **Success criteria:**
  - Second request shows cooldown message: "Please wait X seconds before requesting another link"
  - Button is disabled during cooldown
  - After 60 seconds, can request again
- **Note:** Cooldown is per-session, not per-email (client-side timer)

**12. Android App Links verification state persistence**
- **Platform:** Android device
- **Flow:**
  1. Install app, verify App Links state shows "verified"
  2. Uninstall app
  3. Reinstall app
  4. Check App Links state again
- **Success criteria:**
  - App Links state is "verified" after reinstall (not "none" or "legacy_failure")
  - First magic link tap after reinstall opens app directly

**13. iOS custom scheme fallback (if App Links fail)**
- **Platform:** iPhone
- **Scenario:** If iOS ever falls back to custom scheme (unlikely, but possible)
- **Flow:** Request magic link with iOS fallback URL (`bandroadie://login-callback/`)
- **Success criteria:**
  - App opens via custom scheme
  - Login succeeds
- **Note:** This is a backup test; primary iOS flow should use custom scheme by default (not App Links)

---

## Regression Risk

**Level:** MEDIUM

**Rationale:**
- **Issue 1 fix:** Changes only `supabase/config.toml` (configuration, not code) — **LOW risk**, but requires manual Supabase dashboard verification
- **Issue 2 fix:** Adds a single `mounted` guard to AuthGate listener callback — **MEDIUM risk**, as this is a critical code path that runs for every authenticated user on every platform. If the guard logic is incorrect, users could be stuck on a loading screen.
- **Issue 3 fix:** Changes only `gen_dart_defines.sh` (build configuration, not runtime logic) — **LOW risk**, but requires verification that demo user exists in Supabase production.

**Critical risk:** Issue 2 fix touches the auth initialization flow, which is the entry point for all authenticated users. If the `mounted` guard prevents legitimate auth state updates, users will not be able to log in.

**Mitigation:**
- Test Issue 2 fix on physical iPhone and iPad (not just simulator) — lifecycle behavior differs
- Test both cold start (app killed, tap magic link) and warm start (app backgrounded, tap magic link)
- Test profile completion flow for new users (ensures `_checkProfileComplete()` still runs correctly)
- Test demo login on physical Android device (not just emulator) to confirm compile-time injection works in release builds
- Verify Android deep link interception with manual `adb` commands before end-to-end testing

---

## Rollout / Migration Strategy

### Phase 1 — Local Verification (Before Commit)

1. **Engineer completes all three tasks** (Android redirect URL, iOS mounted guard, demo password in dart_defines.json)
2. **Run local tests:**
   ```bash
   # Verify dart_defines.json contains DEMO_PASSWORD
   ./tools/gen_dart_defines.sh
   grep DEMO_PASSWORD dart_defines.json

   # Run flutter analyze (must be 0 errors)
   flutter analyze

   # Test on local iOS device (if available)
   flutter run -d <ios-device-id>
   # Request magic link, tap link, verify no crash

   # Test on local Android device (if available)
   flutter run -d <android-device-id>
   # Request magic link, tap link, verify app opens directly
   ```
3. **Generate git diff** and include in ENGINEER_REPORT.md
4. **Document verification steps completed** in ENGINEER_REPORT.md
5. **Pass to QA** for full regression testing

### Phase 2 — QA Testing (Before Production Deploy)

1. **QA tests all Primary Testing scenarios** (see QA Regression Areas above)
2. **QA tests at least 5 Secondary Testing scenarios** (regression checks)
3. **QA produces QA_REPORT.md** with verdict: APPROVED or REQUIRES CHANGES
4. If REQUIRES CHANGES: Engineer addresses issues, returns to Phase 1
5. If APPROVED: Proceed to Phase 3

### Phase 3 — Production Supabase Config Update (Critical Manual Step)

**Before deploying code, Engineer must verify Supabase dashboard:**

1. Log into: https://supabase.com/dashboard/project/nekwjxvgbveheooyorjo
2. Navigate to: Authentication → URL Configuration → Redirect URLs
3. Update redirect URLs list to:
   - `https://app.bandroadie.com/auth/confirm` (web)
   - `https://app.bandroadie.com/auth/callback` (Android)
   - `bandroadie://login-callback/` (iOS/macOS)
4. Remove stale URLs (if present):
   - `https://app.bandroadie.com` (no path)
   - `https://bandroadie.com` (no path)
   - `com.bandroadie.app://callback` (old custom scheme)
5. **Screenshot updated list** and include in ENGINEER_REPORT.md
6. Save changes

**Before deploying code, Engineer must verify demo user exists:**

1. Navigate to: Authentication → Users
2. Search for: `bandroadie2026@gmail.com`
3. Confirm user exists and is enabled
4. Confirm user is member of demo band:
   ```sql
   SELECT b.name, bm.role 
   FROM band_members bm
   JOIN bands b ON b.id = bm.band_id
   WHERE bm.user_id = (SELECT id FROM auth.users WHERE email = 'bandroadie2026@gmail.com');
   ```
5. Expected result: `name = "The Banana Stand"`, `role = "member"` or `"admin"`
6. If user or band membership does not exist, **STOP and escalate to Manager**

### Phase 4 — Code Deploy

1. **Merge PR to main** (after QA APPROVED)
2. **Build and deploy web** (no web code changes, but ensures latest version is live):
   ```bash
   ./tools/deploy_web.sh
   ```
3. **Build and upload iOS to TestFlight**:
   ```bash
   ./tools/build_ios.sh --ipa
   # Upload via Transporter or Xcode Organizer
   ```
4. **Build and upload Android to Play Store internal test track**:
   ```bash
   ./tools/build_android.sh
   # Upload .aab to Play Console
   ```
5. **Test on TestFlight and Play Store internal track** before promoting to production

### Phase 5 — Production Smoke Test (Before Public Release)

1. **Install from TestFlight** (iOS) and Play Store internal track (Android)
2. **Test magic link flow** on each platform:
   - Request magic link
   - Tap link in email
   - Confirm app opens and login succeeds
3. **Test demo login** on each platform:
   - Tap logo 7 times
   - Confirm demo login succeeds
4. **Monitor Supabase logs** for auth errors
5. **If any test fails, STOP and rollback** (see Phase 6)

### Phase 6 — Production Rollout

1. **Promote TestFlight build to App Store** (submit for review)
2. **Promote Play Store internal track to production**
3. **Monitor crash logs** for 24-48 hours after release:
   - Xcode Organizer (iOS crashes)
   - Play Console (Android crashes)
   - Supabase logs (auth errors)
4. **If no new auth-related crashes or errors, mark as complete**

### Phase 7 — Rollback Plan (If Issues Detected)

**If iOS crash persists after deploy:**
1. Revert commit that added `mounted` guard to `auth_gate.dart`
2. Rebuild iOS: `./tools/build_ios.sh --ipa`
3. Upload hotfix to TestFlight
4. Promote to production after testing

**If Android deep linking fails:**
1. Verify Supabase dashboard redirect URLs are correct
2. If incorrect, update dashboard and retest (no code changes needed)
3. If assetlinks.json is missing, deploy `web/.well-known/assetlinks.json` to production domains
4. If issue persists, revert `supabase/config.toml` changes and redeploy

**If demo login fails:**
1. Verify demo user exists in Supabase production
2. If user does not exist, create user with email `bandroadie2026@gmail.com` and password `BandRoadie-Demo-2026!`
3. Add user to "The Banana Stand" band via `band_members` table
4. Retest demo login
5. If issue persists, revert `gen_dart_defines.sh` changes, regenerate `dart_defines.json`, and rebuild

---

## Out of Scope

- **Universal Links (associated domains) for iOS** — Not required; iOS uses custom scheme `bandroadie://login-callback/` which is correctly configured in `Info.plist`
- **Android App Links auto-verification debugging** — Assumes `.well-known/assetlinks.json` is correctly deployed at production URLs. If verification fails, Engineer must deploy assetlinks.json to both `app.bandroadie.com` and `bandroadie.com` (if both are in intent filter)
- **Demo band data cleanup** — Assumes demo band "The Banana Stand" exists with correct data in production database
- **Demo user creation or password reset** — Assumes `bandroadie2026@gmail.com` exists in Supabase with password `BandRoadie-Demo-2026!`. If user does not exist, Engineer must create it before marking Issue 3 resolved
- **Auth state provider refactor** — Existing architecture is correct; issue is defensive guards only
- **Deep link service refactor** — Existing logic is correct; issue is redirect URL config in Supabase, not deep link parsing
- **Magic link expiration handling** — Existing error handling is sufficient
- **Multi-account demo login** — Demo login is single-user only (7 taps = one specific demo account)
- **PKCE flow changes** — Existing PKCE implementation is correct and compliant with Supabase best practices
- **Redirect URL dynamic selection based on environment** — Current platform-specific URLs are hardcoded correctly; no need for environment-based selection
- **Alternative deep link schemes** — Current configuration (HTTPS App Links for Android, custom scheme for iOS) is the correct pattern
- **Push notification permission prompts after auth** — Existing flow handles permissions correctly; Issue 2 fix does not change permission logic
- **Band loading retry logic** — Existing error handling in `activeBandProvider` is sufficient
- **SharedPreferences fallback for private browsing** — Existing code handles SharedPreferences errors gracefully
- **Session sync timer improvements** — Existing 5-second sync timer is sufficient for iPad review reliability

---

**Plan Status:** COMPLETE — Ready for Architecture Gate Approval  
**Author:** Architect Agent  
**Date:** 2026-06-24  
**Revision:** 2 (Architecture Gate review corrections applied)
