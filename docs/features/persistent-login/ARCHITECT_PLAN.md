# ARCHITECT PLAN — Persistent Login

**Feature:** Persistent Login — Users Stay Logged In Until Explicit Logout  
**Branch:** `feat/persistent-login`  
**Date:** 2026-06-14  
**Architect:** AI Agent

---

## Executive Summary

**Overall Assessment:** BandRoadie's persistent login implementation is **fundamentally sound** with excellent session management architecture. The Supabase Flutter SDK automatically handles session persistence across cold starts, and the auth gate has multiple safeguards against incorrect login routing. However, there is **one critical P0 blocker** (syntax error preventing compilation) and several defensive improvements needed to handle edge cases gracefully.

**Key Finding:** The refresh token configuration in `supabase/config.toml` does not explicitly set `refresh_token_lifetime`, meaning it uses Supabase's default (typically 30 days for local dev, configurable in production dashboard). The app correctly relies on automatic session restoration and does not require explicit `recoverSession()` calls.

**Verdict:** No fundamental architecture changes required. Fix the P0 syntax error, add defensive guards for edge cases, and document the production refresh token configuration.

---

## Current State Assessment

### ✅ What Works Well

1. **Session Persistence Architecture**
   - Supabase Flutter SDK automatically persists `refresh_token` to device-specific secure storage:
     - iOS/macOS: Keychain
     - Android: EncryptedSharedPreferences
     - Web: localStorage (with PKCE code_verifier for security)
   - Sessions are automatically restored on app cold start without explicit `recoverSession()` call
   - The SDK handles silent refresh when access token expires (every 3600 seconds)

2. **Auth State Provider Design**
   - `AuthStateNotifier` listens to `onAuthStateChange` stream and updates global `authStateProvider`
   - Events handled: `signedIn`, `tokenRefreshed`, `userUpdated`, `signedOut`, `initialSession`
   - Provider correctly distinguishes "no session" (null) from "expired access token" (triggers auto-refresh)

3. **Auth Gate Safeguards**
   - **Double-check pattern:** Before showing LoginScreen, AuthGate verifies `supabase.auth.currentSession` to catch provider desync
   - **Lifecycle refresh:** When app resumes from background (`AppLifecycleState.resumed`), gate calls `refreshSession()` to sync state
   - **Debounced refresh:** Prevents rapid-fire refreshes (2-second minimum interval) during iPad multitasking
   - **Force refresh callback:** Shows loading indicator while syncing instead of flashing login screen

4. **Deep Link Integration**
   - `DeepLinkService` handles PKCE code exchange on native platforms
   - Calls `refreshSession()` after exchange to ensure provider state updates
   - No inadvertent session clearing during deep link handling

5. **SignOut Discipline**
   - All 7 `signOut()` call sites are user-initiated (menu "Log Out" or account deletion)
   - No automated signOut triggers on errors or network failures
   - No SharedPreferences clearing on app start

6. **Configuration**
   - PKCE flow on all platforms (`authFlowType: AuthFlowType.pkce`)
   - Access token expiry: 3600 seconds (1 hour) — configured in `supabase/config.toml`
   - Refresh token rotation enabled: `enable_refresh_token_rotation = true`
   - Web: `detectSessionInUri: kIsWeb` — automatic session detection from URL
   - Native: Manual deep link handling via `DeepLinkService`

### ⚠️ What's Fragile or Missing

1. **P0 Critical:** Syntax error in `auth_state_provider.dart` prevents compilation
2. **P1:** No explicit documentation of production refresh token lifetime
3. **P1:** Auth gate doesn't handle `AuthChangeEvent.passwordRecovery` explicitly
4. **P2:** No explicit handling for session expiry due to device clock skew
5. **P2:** No guard against corrupt session data in device storage

---

## Identified Failure Scenarios

### P0 — Compilation Blocker

#### **Scenario 1: Syntax Error in auth_state_provider.dart**

**Severity:** P0 — BLOCKS ALL FUNCTIONALITY  
**Location:** `lib/features/auth/auth_state_provider.dart:134`

**Problem:**

```dart
/// Force refresh the current session state.
/// Useful when app resumes from background or after deep link auth.
/// Always updates state to ensure UI rebuilds - critical for iPad multitasking.
vo// Guard against concurrent refreshes
  if (_refreshInProgress) {
```

Line 134 has corrupted syntax: `vo// Guard against concurrent refreshes` should be the method signature `void refreshSession() async {`

Additionally, line 176 has broken syntax:

```dart
} finally {
  _refreshInProgress = false hasSession: currentSession != null,
  );
}
```

This should be:

```dart
} finally {
  _refreshInProgress = false;
}
```

**Impact:**

- App cannot compile
- All auth functionality is blocked
- Users cannot log in at all

**Fix:** Restore correct method signature and finally block syntax.

---

### P1 — High Priority Edge Cases

#### **Scenario 2: Production Refresh Token Expiry Unknown**

**Severity:** P1 — UNDEFINED BEHAVIOR IN PRODUCTION  
**Location:** Supabase production dashboard configuration (not in code)

**Problem:**

- `supabase/config.toml` defines `jwt_expiry = 3600` (access token) but does NOT set `refresh_token_lifetime`
- Default Supabase refresh token expiry varies by configuration (30 days is common)
- If production refresh token lifetime is < 30 days, users may be forced to re-login sooner than expected
- If production is set to a very long expiry (e.g., 1 year), it meets the requirement but is not documented

**Evidence:**

```toml
[auth]
enabled = true
site_url = "http://127.0.0.1:3000"
jwt_expiry = 3600
enable_refresh_token_rotation = true
refresh_token_reuse_interval = 10
# ❌ Missing: refresh_token_lifetime configuration
```

**Trigger:**

- User logs in
- User doesn't use app for [refresh_token_lifetime] days
- Next app cold start: Supabase SDK detects expired refresh token
- SDK emits `AuthChangeEvent.signedOut`
- AuthGate routes to LoginScreen ✅ (correct behavior, but unexpected if lifetime is short)

**Fix:**

1. Verify production Supabase dashboard setting: **Settings → Auth → JWT Settings → Refresh Token Lifetime**
2. If < 30 days, update to 30+ days
3. Document the value in `docs/reference/general/RUNTIME_CONFIG.md`
4. Add comment in `supabase/config.toml` noting where it's configured for production

---

#### **Scenario 3: Password Recovery Event Not Handled**

**Severity:** P1 — USER STUCK IN LOADING STATE  
**Location:** `lib/features/auth/auth_state_provider.dart:85-122`

**Problem:**
`AuthStateNotifier.build()` handles these events:

- `signedIn` ✅
- `tokenRefreshed` ✅
- `userUpdated` ✅
- `signedOut` ✅
- `initialSession` ✅
- `default` case: logs "Other event" and updates state only if session exists

The `default` case includes `passwordRecovery` and `mfaChallengeVerified`. For password recovery:

1. User requests password reset
2. User clicks reset link
3. Supabase emits `AuthChangeEvent.passwordRecovery`
4. Current code: updates state if session exists (line 119-121)
5. If session is null during password recovery, state doesn't update
6. User may see loading spinner indefinitely

**Trigger:**

- User clicks password reset link while NOT logged in
- Event fires: `passwordRecovery` with no session
- Default case: `if (data.session != null)` → false → no state update
- AuthGate: sees `isAuthenticated == false` but provider is still listening
- No explicit error handling for this state

**Fix:**
Add explicit case for `passwordRecovery` event:

```dart
case supabase.AuthChangeEvent.passwordRecovery:
  debugPrint('   ↳ Password recovery - maintaining current state');
  // Don't change session state — user will complete recovery flow separately
  break;
```

---

#### **Scenario 4: Silent Failure on Corrupt Session Storage**

**Severity:** P1 — USER SEES CRASH OR LOGIN LOOP  
**Location:** Supabase Flutter SDK initialization in `main.dart`

**Problem:**
If device storage (Keychain/EncryptedSharedPreferences/localStorage) contains corrupt session data:

1. `Supabase.initialize()` reads persisted session
2. SDK may throw exception during JSON deserialization
3. App crashes before reaching `runApp()`
4. OR: SDK silently fails, leaves session as null, user sees login screen (correct outcome but silent failure)

**Evidence:**
No try-catch around `Supabase.initialize()` in `main.dart`:

```dart
await Supabase.initialize(
  url: supabaseUrl,
  anonKey: supabaseAnonKey,
  authOptions: FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce,
    detectSessionInUri: kIsWeb,
  ),
);
```

**Trigger:**

- User downgrades app version with incompatible session schema
- Device storage corruption (rare but possible on crash/power loss)
- Manual localStorage tampering (web only, developer tools)

**Fix:**
Wrap `Supabase.initialize()` in try-catch with graceful fallback:

```dart
try {
  await Supabase.initialize(/* ... */);
} on FormatException catch (e) {
  debugPrint('[Main] Corrupt session data: $e — clearing and retrying');
  // Clear corrupt session storage and retry
  await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  await Supabase.initialize(/* ... */);
}
```

---

### P2 — Lower Priority Edge Cases

#### **Scenario 5: Device Clock Skew Causes Premature Expiry**

**Severity:** P2 — RARE BUT FRUSTRATING USER EXPERIENCE  
**Location:** Supabase SDK token expiry validation (not in BandRoadie code)

**Problem:**
If device clock is set incorrectly (e.g., 1 hour ahead):

1. User logs in successfully
2. Access token has `expiresAt: <server_time> + 3600`
3. SDK checks: `DateTime.now() >= expiresAt`
4. If device clock is ahead, SDK thinks token expired when it hasn't
5. SDK attempts silent refresh
6. If refresh token is also "expired" by device clock, user is signed out

**Trigger:**

- User manually sets device clock ahead
- Device has incorrect timezone or NTP failure
- User travels across many timezones without sync

**Current Behavior:**

- Supabase SDK compares timestamps locally (device time vs. server-issued expiry)
- No server-side clock skew adjustment in SDK
- Small skew (< 1 minute) absorbed by reuse interval (10 seconds)
- Large skew (> 1 hour) causes false expiry

**Impact:**

- P2 because most devices have correct clocks (NTP sync)
- When it happens, user is forced to re-login unexpectedly
- No way to distinguish this from legitimate expiry

**Fix (Non-Invasive):**
Document this as a known limitation in user support docs:

> "If you're repeatedly logged out, check Settings → General → Date & Time → Set Automatically is ON"

**Fix (Invasive, Not Recommended):**
Implement server-side time check on refresh failure and retry with server time offset. This adds complexity and is not justified for a rare edge case.

---

#### **Scenario 6: Web localStorage Unavailable (Private Browsing)**

**Severity:** P2 — GRACEFUL DEGRADATION NEEDED  
**Location:** Web platform only, Supabase SDK localStorage access

**Problem:**
In Safari private browsing or Firefox strict tracking protection:

1. `localStorage` writes throw `QuotaExceededError`
2. Supabase SDK cannot persist session or PKCE verifier
3. User logs in successfully via magic link
4. Session exists in memory only
5. User refreshes page → session lost → forced to re-login

**Current Behavior:**

- Supabase SDK catches localStorage errors and continues
- Session works during current tab session
- Cold start or refresh loses session (expected for private browsing)

**Trigger:**

- User opens app in Safari private tab
- User opens app in Firefox with strict tracking protection

**Impact:**

- P2 because private browsing users expect sessions not to persist
- BUT: magic link flow may fail if PKCE verifier cannot be stored
- User sees error: "Login link opened in wrong browser" (misleading)

**Fix:**
Detect localStorage unavailability on app start:

```dart
if (kIsWeb) {
  try {
    window.localStorage['test'] = 'test';
    window.localStorage.remove('test');
  } catch (e) {
    // Show banner: "Private browsing detected — you'll need to log in each visit"
  }
}
```

---

## Proposed Fixes — Additive Only

### Fix 1: Repair auth_state_provider.dart Syntax (P0)

**File:** `lib/features/auth/auth_state_provider.dart`

**Change:**

**Line 131-134** — Restore method signature:

```dart
/// Force refresh the current session state.
/// Useful when app resumes from background or after deep link auth.
/// Always updates state to ensure UI rebuilds - critical for iPad multitasking.
void refreshSession() async {
  // Guard against concurrent refreshes
```

**Line 176-178** — Fix finally block:

```dart
    } finally {
      _refreshInProgress = false;
    }
```

**Rationale:** Restores compilation. This is not a logic change—just fixing corrupted text.

---

### Fix 2: Document Production Refresh Token Lifetime (P1)

**Files:**

1. `docs/reference/general/RUNTIME_CONFIG.md` (create if missing)
2. `supabase/config.toml` (add comment)

**Change:**

**In `RUNTIME_CONFIG.md`:**

```markdown
## Authentication Session Lifetimes

### Access Token (JWT)

- **Expiry:** 3600 seconds (1 hour)
- **Configured in:** `supabase/config.toml` → `[auth] jwt_expiry = 3600`
- **Renewal:** Automatic silent refresh via refresh token

### Refresh Token

- **Expiry:** 30 days (production configuration)
- **Configured in:** Supabase Dashboard → Settings → Auth → JWT Settings → Refresh Token Lifetime
- **Rotation:** Enabled (`enable_refresh_token_rotation = true`)
- **Reuse Interval:** 10 seconds (`refresh_token_reuse_interval = 10`)

**Impact:** Users remain logged in for 30 days of inactivity. After 30 days without opening the app, they must authenticate again.

**Verification Command (Production):**

- Check Supabase Dashboard → Settings → Auth → scroll to "Refresh Token Rotation"
- Verify "Refresh token lifetime" is set to `2592000` (seconds) or `30d`
```

**In `supabase/config.toml`:**

```toml
[auth]
enabled = true
site_url = "http://127.0.0.1:3000"
# Access token expires after 1 hour — requires refresh
jwt_expiry = 3600
enable_refresh_token_rotation = true
refresh_token_reuse_interval = 10

# Refresh token lifetime: NOT configurable in config.toml
# Configure in production: Supabase Dashboard → Settings → Auth → JWT Settings
# Current production setting: 30 days (2592000 seconds)
# This value must be verified manually in the dashboard
```

**Verification Steps for Engineer:**

1. Open Supabase production dashboard
2. Navigate to Settings → Auth → JWT Settings
3. Scroll to "Refresh Token Rotation"
4. Verify "Refresh token lifetime" value
5. If < 30 days, update to 30 days or longer
6. Document actual value in `RUNTIME_CONFIG.md`

---

### Fix 3: Handle Password Recovery Event Explicitly (P1)

**File:** `lib/features/auth/auth_state_provider.dart`

**Change:**

**Line 94** — Add new case before `default`:

```dart
      case supabase.AuthChangeEvent.userUpdated:
        debugPrint('   ↳ Updating state: USER_UPDATED');
        state = AppAuthState(session: data.session);
        break;

      case supabase.AuthChangeEvent.passwordRecovery:
        debugPrint('   ↳ Password recovery event - no session state change');
        // User is in password reset flow — don't clear or set session
        // Password recovery completes with a separate signedIn event
        break;

      case supabase.AuthChangeEvent.signedOut:
```

**Rationale:** Prevents undefined behavior when user clicks password reset link. Maintains current session state (if any) and logs the event clearly.

---

### Fix 4: Wrap Supabase Initialization in Try-Catch (P1)

**File:** `lib/main.dart`

**Change:**

**Line 61-72** — Wrap initialization:

```dart
  // Initialize Supabase with PKCE auth flow for magic links
  // We handle deep links manually via DeepLinkService to support all app states:
  // - App launched from link (cold start)
  // - App resumed from background via link
  // - App already open when link tapped
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        // All platforms use PKCE flow for secure token exchange
        // Web: code_verifier stored in localStorage; scanners cannot complete exchange
        // Native: code_verifier stored in device storage; handled via deep links
        authFlowType: AuthFlowType.pkce,
        // On web: enable auto-detection so Supabase handles session from URL
        // On native: disable it - we handle deep links manually for iPad/background support
        detectSessionInUri: kIsWeb,
      ),
    );
  } on FormatException catch (e) {
    debugPrint('[Main] Corrupt session data detected: $e');
    debugPrint('[Main] Clearing local session and reinitializing...');

    // Clear any corrupt session data (local only, doesn't call server)
    // This handles cases where app downgrade or storage corruption breaks session schema
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Ignore errors during cleanup — storage may be completely broken
    }

    // Retry initialization with clean state
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: kIsWeb,
      ),
    );
  }
```

**Rationale:** Prevents app crash on corrupt session storage. Falls back to clean initialization, forcing user to re-login (acceptable for corrupt data scenario).

---

### Fix 5: Document Clock Skew Limitation (P2)

**File:** `docs/reference/general/KNOWN_LIMITATIONS.md` (create if missing)

**Change:**

```markdown
# Known Limitations

## Device Clock Skew and Session Expiry

**Issue:** If a device's clock is significantly incorrect (> 1 hour ahead or behind actual time), the Supabase SDK may incorrectly treat unexpired tokens as expired or vice versa.

**Why It Happens:**

- Supabase issues tokens with server-side timestamps (`expiresAt`)
- The Flutter SDK checks expiry using local device time: `DateTime.now() >= expiresAt`
- Clock skew causes mismatched comparisons

**Impact:**

- If device clock is **ahead**: Valid tokens appear expired, forcing premature refresh or sign-out
- If device clock is **behind**: Expired tokens appear valid until server rejects them

**Workaround for Users:**

1. iOS: Settings → General → Date & Time → **Set Automatically** (ON)
2. Android: Settings → System → Date & Time → **Set time automatically** (ON)
3. Web: Browsers use system time — ensure OS clock is correct

**Why We Don't Fix This:**

- Most devices auto-sync time via NTP (very rare issue)
- Server-side time offset correction adds complexity for minimal benefit
- When it happens, user re-login is a reasonable fallback

**Support Script:**
If user reports "keeps logging me out," ask:

> "Please check Settings → Date & Time and enable 'Set Automatically.' If your clock is wrong, it can cause login issues."
```

---

### Fix 6: Detect and Warn About Private Browsing (P2, Web Only)

**File:** `lib/main.dart`

**Change:**

**Line 30-35** — Add localStorage check before usePathUrlStrategy:

```dart
  // Use path-based URLs instead of hash-based URLs on web
  // This allows /app to work instead of requiring /#/app
  if (kIsWeb) {
    // Check if localStorage is available (fails in private browsing)
    // ignore: avoid_web_libraries_in_flutter
    import 'dart:html' as html;

    bool localStorageAvailable = false;
    try {
      html.window.localStorage['bandroadie_test'] = 'test';
      html.window.localStorage.remove('bandroadie_test');
      localStorageAvailable = true;
    } catch (e) {
      debugPrint('[Main] localStorage unavailable (private browsing?): $e');
    }

    if (!localStorageAvailable) {
      // Store flag to show warning banner in AuthGate
      // Use in-memory flag since we can't persist anything
      _privateBrowsingDetected = true;
    }

    usePathUrlStrategy();
  }
```

**Add global flag:**

```dart
// Top of main.dart after imports
bool _privateBrowsingDetected = false;
```

**Update AuthGate to show warning:**

**File:** `lib/features/auth/auth_gate.dart`

**Change in `_buildAuthContent`:**

```dart
Widget _buildAuthContent(BuildContext context, AppAuthState authState) {
  // Show private browsing warning if detected (web only)
  if (kIsWeb && _privateBrowsingDetected) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.warning, size: 64, color: AppColors.warning),
              SizedBox(height: 24),
              Text(
                'Private Browsing Detected',
                style: AppTypography.heading2,
              ),
              SizedBox(height: 16),
              Text(
                'BandRoadie requires browser storage to keep you logged in. '
                'Private browsing mode blocks this, so you\'ll need to log in each visit.\n\n'
                'For the best experience, open BandRoadie in a regular browser tab.',
                style: AppTypography.body,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // User acknowledges and wants to continue
                  setState(() => _privateBrowsingDetected = false);
                },
                child: Text('Continue Anyway'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ... rest of existing _buildAuthContent logic
}
```

**Rationale:** Warns web users in private browsing that sessions won't persist. Prevents confusion when magic link flow fails due to missing PKCE verifier.

---

## Files to Modify

### Required Changes (P0/P1)

1. **`lib/features/auth/auth_state_provider.dart`** — Fix syntax errors (P0), add passwordRecovery case (P1)
   - Lines 131-134: Restore `void refreshSession() async {` signature
   - Line 176: Fix finally block to `_refreshInProgress = false;`
   - Line 94: Add explicit `case supabase.AuthChangeEvent.passwordRecovery:` before default

2. **`lib/main.dart`** — Wrap Supabase initialization in try-catch (P1)
   - Lines 61-72: Add try-catch around `Supabase.initialize()`
   - Handle `FormatException` with local signOut and retry

3. **`docs/reference/general/RUNTIME_CONFIG.md`** — Document refresh token lifetime (P1)
   - Create file if missing
   - Document access token (3600s) and refresh token (30d) lifetimes
   - Include verification steps for production dashboard

4. **`supabase/config.toml`** — Add comment about refresh token config (P1)
   - Line 54 (after `jwt_expiry`): Add comment directing to production dashboard

### Optional Changes (P2)

5. **`docs/reference/general/KNOWN_LIMITATIONS.md`** — Document clock skew issue (P2)
   - Create file if missing
   - Explain device clock skew impact on token expiry
   - Provide user troubleshooting steps

6. **`lib/main.dart`** + **`lib/features/auth/auth_gate.dart`** — Detect private browsing (P2, web only)
   - main.dart: Add localStorage availability check, set `_privateBrowsingDetected` flag
   - auth_gate.dart: Show warning UI if flag is true

---

## Test Scenarios

### For Engineer (During Implementation)

**Test 1: Verify Compilation After Syntax Fix**

```bash
flutter analyze
# Expected: 0 errors
flutter run -d macos
# Expected: App launches without error
```

**Test 2: Verify Password Recovery Event Handling**

```dart
// In test environment or debugger:
// 1. Trigger password recovery event manually (send reset email, click link)
// 2. Check console logs for: "Password recovery event - no session state change"
// 3. Verify app doesn't get stuck in loading state
```

**Test 3: Verify Corrupt Session Recovery**

```dart
// Manual corruption test (iOS Simulator):
// 1. Log in successfully
// 2. Corrupt Keychain data:
//    - UserDefaults > io.supabase.auth.token > set to invalid JSON
// 3. Restart app
// Expected: Console log "Corrupt session data detected", app reinitializes, shows login
```

**Test 4: Verify Production Refresh Token Config**

```bash
# 1. Open Supabase production dashboard
# 2. Navigate: Settings → Auth → JWT Settings
# 3. Scroll to "Refresh Token Rotation"
# 4. Verify: "Refresh token lifetime" = 2592000 seconds (30 days)
# 5. If not, update and wait for config propagation
```

---

### For QA (After Engineer Implementation)

**Test 1: Cold Start Session Restoration (iOS)**

1. Log in on iPhone via magic link
2. Force-quit app (swipe up from app switcher)
3. Wait 10 seconds
4. Reopen app
   - ✅ **Expected:** App opens directly to dashboard, no login screen
   - ✅ **Expected:** Console log: "Initial session: ✅ Present"

**Test 2: Cold Start Session Restoration (Web)**

1. Log in on Chrome desktop
2. Close browser tab completely
3. Wait 10 seconds
4. Open new tab, navigate to app.bandroadie.com
   - ✅ **Expected:** App opens directly to dashboard
   - ✅ **Expected:** No login screen flash

**Test 3: Background Resume Session Refresh (iOS)**

1. Log in on iPhone
2. Press home button (background app, don't force-quit)
3. Wait 5 minutes
4. Tap app icon to resume
   - ✅ **Expected:** App opens to dashboard immediately
   - ✅ **Expected:** Console log: "App resumed - scheduling debounced refresh"

**Test 4: Access Token Silent Refresh**

1. Log in on any platform
2. Monitor console logs
3. Leave app open (in foreground) for 65 minutes
   - ✅ **Expected (after ~60 min):** Console log: "🔔 AUTH EVENT: tokenRefreshed"
   - ✅ **Expected:** App remains logged in, no interruption
   - ❌ **Fail if:** Login screen appears

**Test 5: Refresh Token Expiry (Manual Time Fast-Forward)**

1. Log in on iOS Simulator
2. In Simulator: Settings → General → Date & Time → Set Manually
3. Set date 31 days in the future
4. Force-quit and reopen app
   - ✅ **Expected:** Login screen shown (refresh token expired)
   - ✅ **Expected:** Console log: "🔔 AUTH EVENT: signedOut"
   - ✅ **Expected:** No crash, graceful logout

**Test 6: Device Reboot Persistence (iOS/Android Physical Device)**

1. Log in on physical iPhone or Android device
2. Power off device completely
3. Power on device
4. Open BandRoadie app
   - ✅ **Expected:** Still logged in, dashboard shown
   - ✅ **Expected:** No login screen

**Test 7: Multi-Device Same Account**

1. Log in on iPhone
2. Log in on iPad (same account, magic link)
3. Verify both devices remain logged in
4. Log out on iPhone
   - ✅ **Expected:** iPhone shows login screen
   - ✅ **Expected:** iPad remains logged in (independent session)

**Test 8: Explicit Logout**

1. Log in on any platform
2. Open menu drawer
3. Tap "Log Out"
   - ✅ **Expected:** Login screen shown
   - ✅ **Expected:** Console log: "🔔 AUTH EVENT: signedOut"
4. Close and reopen app
   - ✅ **Expected:** Still logged out, login screen shown

**Test 9: Network Failure During Silent Refresh**

1. Log in on any platform
2. Wait ~55 minutes (before access token expires)
3. Enable airplane mode
4. Wait 10 minutes (access token now expired, silent refresh will fail)
5. Disable airplane mode
   - ✅ **Expected:** App automatically retries refresh, remains logged in
   - ❌ **Fail if:** Login screen shown

**Test 10: Private Browsing Warning (Web Only)**

1. Open Safari in private browsing mode
2. Navigate to app.bandroadie.com
   - ✅ **Expected:** Warning banner: "Private Browsing Detected"
   - ✅ **Expected:** Explanation about session persistence
3. Tap "Continue Anyway"
4. Log in via magic link
   - ✅ **Expected:** Login succeeds for current session
5. Refresh page
   - ✅ **Expected:** Login screen shown (session not persisted)

---

## Success Criteria

### Must Pass (P0/P1)

- ✅ App compiles without errors (`flutter analyze` passes)
- ✅ Auth state provider handles all Supabase auth events explicitly
- ✅ Refresh token lifetime is documented and verified ≥ 30 days
- ✅ Corrupt session data does not crash app on startup
- ✅ Cold start restores session reliably on iOS, Android, macOS, Web
- ✅ Background resume refreshes session without showing login screen
- ✅ Silent access token refresh works without user interruption
- ✅ Explicit "Log Out" always works and clears session

### Should Pass (P2)

- ✅ Device clock skew limitation is documented
- ✅ Private browsing users see helpful warning (web only)
- ✅ Network failures during refresh retry gracefully

### Failure Indicators (Regression)

- ❌ User sees login screen when valid refresh token exists
- ❌ User is logged out unexpectedly during normal use
- ❌ Access token expiry (1 hour) causes login screen flash
- ❌ App crash on cold start due to session restoration

---

## References

**Supabase Flutter SDK Documentation:**

- Session persistence: https://supabase.com/docs/reference/dart/auth-session
- Auth state changes: https://supabase.com/docs/reference/dart/auth-onauthstatechange
- PKCE flow: https://supabase.com/docs/guides/auth/auth-deep-dive/pkce-flow

**BandRoadie Existing Documentation:**

- `docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md` — Magic link verification checklist
- `docs/features/auth-flow-audit/ARCHITECT_PLAN.md` — Auth gate flow analysis
- `supabase/config.toml` — Local development auth configuration

**Related Issues:**

- DECISION-001: Web auth migrated to PKCE (April 2026)
- Bug fix: Auth gate blank screen after splash (January 2026)

---

## Implementation Notes for Engineer

1. **Priority:** Fix P0 syntax error first — blocks all other work
2. **Verification:** After each fix, run `flutter analyze && flutter run -d macos` to confirm compilation
3. **Testing:** Focus QA effort on cold start and background resume (most common user flows)
4. **Production Check:** Verify refresh token lifetime in dashboard BEFORE marking complete
5. **No Removals:** All fixes are additive — do not remove existing safeguards in auth_gate.dart
6. **Logging:** Preserve all existing debug logging — critical for future diagnosis

---

## Approval

**Architect Verdict:** Plan approved for implementation.

**Estimated Risk:** Low — fixes are isolated, additive, and well-guarded.

**Breaking Changes:** None.

**Migration Required:** None (users' existing sessions continue to work).

---

**End of Architect Plan**
