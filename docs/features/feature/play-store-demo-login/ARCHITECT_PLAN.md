# ARCHITECT_PLAN — Play Store Demo Login

**Feature slug:** `feature/play-store-demo-login`  
**Branch:** `feature/play-store-demo-login`  
**Priority:** High — app is currently rejected from Google Play  
**Architect:** AI Architect Agent  
**Date:** 2026-06-03

---

## Problem Statement

The BandRoadie Android app was rejected from Google Play because Google's reviewers cannot log in to review the app. BandRoadie uses magic-link (passwordless) email auth exclusively. Google's App Access declaration requires working static credentials (email + password). No such credentials exist in the app today.

---

## Solution

Add a hidden easter egg on the login screen: tapping the BandRoadie logo exactly 7 times in rapid succession triggers a demo login that calls `supabase.auth.signInWithPassword` with hardcoded demo credentials. This is a well-established pattern (identical in concept to Android's Developer Options unlock). After successful sign-in, the existing `authStateProvider` stream fires a `signedIn` event and `AuthGate` routes the user to the home screen as normal — no routing changes required.

---

## Code Investigation Findings

### 1. Logo location

**File:** `lib/features/auth/login_screen.dart`  
**Method:** `_buildLogo({required double logoWidth})` (approx. line 441)

The logo is `Image.asset('assets/images/bandroadie_logo_stacked.png')` nested inside three animation wrappers:

```
FadeTransition (opacity: _titleOpacity)
  └─ ScaleTransition (scale: _titleScale)
       └─ AnimatedBuilder (controller: _logoShrinkScale)
            └─ Transform.scale
                 └─ Image.asset
```

The logo is rendered inside `_buildContentCluster()`:

```dart
SizedBox(
  height: availableHeight / 2,
  child: Center(child: _buildLogo(logoWidth: logoWidth)),
),
```

**Current state:** No tap handler exists. No `GestureDetector`. The outermost widget of `_buildLogo()` is `FadeTransition`.

### 2. Supabase password auth availability

`supabase.auth.signInWithPassword(email:, password:)` is a first-class method of the `supabase_flutter` SDK already in `pubspec.yaml`. It requires **Email auth to be enabled** in the Supabase project — which it is (confirmed: `signInWithOtp` works, which requires the same Email auth provider). No Supabase dashboard changes needed beyond verifying Email auth is enabled.

**Current usage of password auth:** None. Only `signInWithOtp` is used. No code in `lib/**` references `signInWithPassword`.

### 3. Post-login routing

After `signInWithPassword` succeeds:

1. `authStateProvider`'s `onAuthStateChange` stream fires `AuthChangeEvent.signedIn`
2. `AuthGate._initializeAuth()` detects the auth state change via `ref.listenManual`
3. `_checkProfileComplete()` is called — verifies the demo user has `first_name` + `last_name` in `users` table
4. `loadUserBands()` is called — fetches bands for the demo user
5. The demo user belongs only to **The Banana Stand** — it becomes `bands.first` and is auto-selected
6. `AuthGate` renders `AppShell`

**No changes to `main.dart` or routing are required.**

### 4. Band auto-selection after demo login

`ActiveBandNotifier.loadUserBands()` (line ~307 in `active_band_controller.dart`):

- Checks `SharedPreferences` for a persisted `active_band_id`
- Falls back to `bands.first` if no persisted ID or persisted ID not in results
- Persists the selection for future sessions

If the demo user is a member of only The Banana Stand, `bands.first` will always be The Banana Stand. **No special band-selection handling is needed.**

### 5. Demo credentials storage

The project's config philosophy (`lib/app/supabase_config.dart`, `GUARDRAILS.md §2`) mandates `--dart-define` as the only config source. All existing credentials use `String.fromEnvironment(...)` and are injected from `.env` at build time.

The demo email (`demo@bandroadie.com`) is public — it will appear in the Play Store App Access declaration. It is safe as a source-code constant.  
The demo password is a user credential (not a service credential), but following project convention, it must be injected via `--dart-define=DEMO_PASSWORD`. It must NOT be hardcoded as a string literal in source.

### 6. Visual feedback — what fits the existing UI

The existing login UX uses controlled animations (single `AnimationController`) and a `Stack`/`Column` layout for content. The cleanest non-intrusive approach:

- **Tap 1–2:** No feedback (standard Flutter tap; any accidental tap does nothing visible)
- **Tap 3–6:** A small hint text `"${7 - _logoTapCount} more..."` appears at the bottom edge of the logo's `SizedBox` container (inside the existing `availableHeight / 2` slot), using `AppColors.primary` at low opacity
- **Tap 7:** `_isLoading = true` is set immediately (existing login button spinner activates); demo login proceeds

This means the hint widget only renders inside the `SizedBox(height: availableHeight / 2)` — no layout disruption for normal users since the `SizedBox` height never changes.

- **Auto-reset:** A 3-second inactivity `Timer` resets `_logoTapCount` to 0 with no feedback. Prevents accidental partial sequences from persisting.

### 7. `dart:async` import

`lib/features/auth/login_screen.dart` does not currently import `dart:async`. The `Timer` class requires it. This import must be added.

---

## Files to Create

| File                                      | Action     | Reason                                                       |
| ----------------------------------------- | ---------- | ------------------------------------------------------------ |
| `lib/app/constants/demo_credentials.dart` | **CREATE** | Centralised compile-time credentials per feature requirement |

## Files to Modify

| File                                  | Change summary                                                                                              |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `lib/features/auth/login_screen.dart` | Add tap counter, reset timer, `_handleLogoTap`, `_triggerDemoLogin`, visual hint, `GestureDetector` on logo |
| `dart_defines.json`                   | Add `"DEMO_PASSWORD": ""` placeholder key (engineer fills value after Tony sets it in Supabase)             |
| `.env.example`                        | Document `DEMO_PASSWORD` variable                                                                           |
| `run.sh`                              | Add `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD}"`                                                        |
| `tools/build_android.sh`              | Add `DEMO_PASSWORD` to `REQUIRED_VARS` and `--dart-define` list                                             |
| `tools/build_ios.sh`                  | Add `DEMO_PASSWORD` to `REQUIRED_VARS` and `--dart-define` list                                             |
| `tools/build_web.sh`                  | Add `DEMO_PASSWORD` to `REQUIRED_VARS` and `--dart-define` list                                             |

> **Note:** `DEMO_PASSWORD` must NOT be committed with a real value. `dart_defines.json` gets an empty placeholder only. Tony must add the actual value to his `.env` file (gitignored) after setting the password in Supabase.

---

## Implementation Tasks

Implement in this exact order.

---

### Task 1 — Create `lib/app/constants/demo_credentials.dart`

Create a new file with these contents exactly:

```dart
// ============================================================================
// DEMO CREDENTIALS
// Compile-time constants for Play Store review access.
//
// The email is public — it appears in the Play Store App Access declaration.
// The password is injected at build time via --dart-define=DEMO_PASSWORD.
// It must NOT be a string literal in source code.
//
// Demo band: The Banana Stand (band_id: 9187f897-1731-4337-bbd3-4f80afbe88ec)
// ============================================================================

/// Email address for the Play Store demo account.
const String kDemoEmail = 'demo@bandroadie.com';

/// Password for the Play Store demo account.
/// Injected at compile time via --dart-define=DEMO_PASSWORD.
/// An empty defaultValue causes demo login to fail safely if the define is absent.
const String kDemoPassword = String.fromEnvironment(
  'DEMO_PASSWORD',
  defaultValue: '',
);
```

---

### Task 2 — Modify `lib/features/auth/login_screen.dart`

#### 2a. Add `dart:async` import

At the top of the file, after the existing `dart:io` import:

```dart
import 'dart:async';
import 'dart:io' show Platform;
```

#### 2b. Add demo credentials import

After the existing `auth_gate.dart` import at the bottom of the import block:

```dart
import '../../app/constants/demo_credentials.dart';
```

#### 2c. Add state variables to `_LoginScreenState`

After the existing `bool _reduceMotion = false;` field declaration:

```dart
// === DEMO LOGIN (Play Store easter egg) ===
/// Number of times the logo has been tapped in the current sequence.
int _logoTapCount = 0;

/// Auto-reset timer — clears tap count after 3 seconds of inactivity.
Timer? _logoTapResetTimer;
```

#### 2d. Add `dispose` cleanup

In the existing `dispose()` method, before `super.dispose()`:

```dart
_logoTapResetTimer?.cancel();
```

The final `dispose()` must include:

```dart
@override
void dispose() {
  _emailController.removeListener(_onEmailTextChange);
  _focusNode.removeListener(_onEmailFocusChange);
  _emailController.dispose();
  _focusNode.dispose();
  _emailHintController.dispose();
  _animController.dispose();
  _logoShrinkController.dispose();
  _logoTapResetTimer?.cancel();  // ADD THIS LINE
  super.dispose();
}
```

#### 2e. Add `_handleLogoTap()` method

Add this method after `_initHintController()`:

```dart
/// Easter egg: 7 taps on the logo triggers Play Store demo login.
/// Shows a subtle "X more..." hint from tap 3 onwards.
/// Auto-resets after 3 seconds of inactivity.
void _handleLogoTap() {
  // Cancel any pending reset
  _logoTapResetTimer?.cancel();

  setState(() {
    _logoTapCount++;
  });

  if (_logoTapCount >= 7) {
    setState(() {
      _logoTapCount = 0;
    });
    _triggerDemoLogin();
    return;
  }

  // Schedule reset after 3 seconds of inactivity
  _logoTapResetTimer = Timer(const Duration(seconds: 3), () {
    if (mounted) {
      setState(() {
        _logoTapCount = 0;
      });
    }
  });
}
```

#### 2f. Add `_triggerDemoLogin()` method

Add this method after `_handleLogoTap()`:

```dart
/// Performs email+password sign-in with the Play Store demo account.
/// Called after 7 logo taps. AuthGate handles routing on success.
Future<void> _triggerDemoLogin() async {
  if (_isLoading) return;

  setState(() {
    _isLoading = true;
    _message = null;
  });

  try {
    await supabase.auth.signInWithPassword(
      email: kDemoEmail,
      password: kDemoPassword,
    );
    // On success, authStateProvider fires signedIn and AuthGate routes
    // to AppShell. No further action needed here.
  } on AuthException catch (e) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _message = 'Demo login failed: ${e.message}';
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _message = 'Demo login failed. Please try again.';
      });
    }
  }
}
```

#### 2g. Modify `_buildLogo()` to add `GestureDetector`

Wrap the existing return value of `_buildLogo()` in a `GestureDetector`:

**Current code:**

```dart
Widget _buildLogo({required double logoWidth}) {
  return FadeTransition(
    opacity: _titleOpacity,
    child: ScaleTransition(
      ...
    ),
  );
}
```

**Replace the entire `_buildLogo` method body** with:

```dart
Widget _buildLogo({required double logoWidth}) {
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _handleLogoTap,
    child: FadeTransition(
      opacity: _titleOpacity,
      child: ScaleTransition(
        scale: _titleScale,
        child: AnimatedBuilder(
          animation: _logoShrinkScale,
          builder: (context, child) =>
              Transform.scale(scale: _logoShrinkScale.value, child: child),
          child: Image.asset(
            'assets/images/bandroadie_logo_stacked.png',
            width: logoWidth,
            fit: BoxFit.contain,
          ),
        ),
      ),
    ),
  );
}
```

> **Note:** `behavior: HitTestBehavior.opaque` ensures taps on the transparent areas of the PNG register correctly. Without it, taps on transparent pixels are ignored.

#### 2h. Modify `_buildContentCluster()` logo section to add hint text

In `_buildContentCluster()`, find the logo `SizedBox`:

**Current code:**

```dart
SizedBox(
  height: availableHeight / 2,
  child: Center(child: _buildLogo(logoWidth: logoWidth)),
),
```

**Replace with:**

```dart
SizedBox(
  height: availableHeight / 2,
  child: Stack(
    alignment: Alignment.center,
    children: [
      Center(child: _buildLogo(logoWidth: logoWidth)),
      if (_logoTapCount >= 3 && _logoTapCount < 7)
        Align(
          alignment: Alignment.bottomCenter,
          child: Text(
            '${7 - _logoTapCount} more...',
            style: TextStyle(
              color: AppColors.primary.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
    ],
  ),
),
```

The hint appears at the bottom edge of the `availableHeight / 2` slot — just above the email field's natural position. It is fully contained within the existing layout bounds so normal users see zero layout change.

---

### Task 3 — Update `dart_defines.json`

Add the `DEMO_PASSWORD` placeholder key. The value must remain empty in the committed file. Tony adds the real value to his `.env` file only.

**Current last entry:**

```json
"FIREBASE_MEASUREMENT_ID": "G-QFC8JXHKDC"
```

**After change:**

```json
"FIREBASE_MEASUREMENT_ID": "G-QFC8JXHKDC",
"DEMO_PASSWORD": ""
```

---

### Task 4 — Update `.env.example`

After the `FIREBASE_MEASUREMENT_ID` line:

```
# ── Demo Account (Play Store App Access) ─────────────────────
# Set this after creating demo@bandroadie.com in Supabase Auth.
DEMO_PASSWORD=your-demo-account-password
```

---

### Task 5 — Update `run.sh`

After the `--dart-define=FIREBASE_MEASUREMENT_ID` line:

```bash
  --dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"
```

Use `${DEMO_PASSWORD:-}` (empty fallback) so local dev without `DEMO_PASSWORD` set in `.env` does not fail the script's `set -u` check.

---

### Task 6 — Update build scripts

Apply the same pattern to:

- `tools/build_android.sh`
- `tools/build_ios.sh`
- `tools/build_web.sh`

In each:

1. Add `DEMO_PASSWORD` to the `REQUIRED_VARS` array — **NO.** Do NOT add to `REQUIRED_VARS` (the demo password is optional for CI; builds without it simply disable the easter egg). Instead, handle as an optional variable.
2. Add the `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"` flag to the `flutter build` command, matching the spacing and indentation of existing `--dart-define` flags.

> **Important:** Do NOT add `DEMO_PASSWORD` to `REQUIRED_VARS`. It is optional. A build without it compiles fine — `kDemoPassword` will be an empty string and demo login will fail gracefully with an `AuthException` rather than breaking the build.

---

## Database Seeding Requirement (Tony action — not implemented by Engineer)

The following must be confirmed or seeded manually in Supabase before testing:

1. **Demo Supabase Auth user exists:**
   - Email: `demo@bandroadie.com`
   - Auth method: Email + Password (must be a Password-type account, not just OTP)
   - Must have a confirmed email address

2. **Demo user profile row exists:**

   ```sql
   SELECT * FROM users WHERE id = (
     SELECT id FROM auth.users WHERE email = 'demo@bandroadie.com'
   );
   ```

   Must have non-null `first_name` and `last_name` — otherwise AuthGate shows the profile completion screen.

3. **Demo user is a member of The Banana Stand:**

   ```sql
   SELECT * FROM band_members
   WHERE band_id = '9187f897-1731-4337-bbd3-4f80afbe88ec'
   AND user_id = (SELECT id FROM auth.users WHERE email = 'demo@bandroadie.com');
   ```

4. **The Banana Stand band exists:**

   ```sql
   SELECT * FROM bands WHERE id = '9187f897-1731-4337-bbd3-4f80afbe88ec';
   ```

5. **Tony sets a strong password on the `demo@bandroadie.com` account** via Supabase Auth dashboard, then adds it to `.env` as `DEMO_PASSWORD=<value>`.

---

## System Impact

| System             | Impact             | Notes                                                                                            |
| ------------------ | ------------------ | ------------------------------------------------------------------------------------------------ |
| Auth / Session     | **Affected**       | New sign-in method added (`signInWithPassword`). No changes to existing magic-link flow.         |
| Routing            | **Unaffected**     | AuthGate handles post-login routing identically for all sign-in methods.                         |
| Gigs               | **Unaffected**     | No changes.                                                                                      |
| Rehearsals         | **Unaffected**     | No changes.                                                                                      |
| Setlists / Catalog | **Unaffected**     | No changes.                                                                                      |
| Members / RBAC     | **Unaffected**     | Demo user uses existing RLS + band_members RLS.                                                  |
| Push Notifications | **Unaffected**     | Token registration is handled in AuthGate on sign-in, same path for all auth methods.            |
| Database           | **Not applicable** | No migrations. Seeding is a manual step.                                                         |
| Build / CI         | **Affected**       | New `DEMO_PASSWORD` `--dart-define` added to all build scripts (optional, graceful degradation). |

---

## Acceptance Criteria Verification Map

| AC                                                       | Verification approach                                                                                   |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| 1. 7 logo taps triggers demo login                       | Manual test on all platforms. Count taps, confirm 7th triggers spinner and auto-login.                  |
| 2. Visual feedback during tap sequence                   | Manual: tap 3+ times, confirm small hint text appears below logo.                                       |
| 3. Signs in with real Supabase demo account              | Auth logs show `AuthChangeEvent.signedIn` for `demo@bandroadie.com`.                                    |
| 4. Lands on home screen associated with The Banana Stand | After login, home screen shows The Banana Stand as active band.                                         |
| 5. Works on all platforms                                | Test on iOS, Android, macOS, and Chrome.                                                                |
| 6. No visible change to normal login UX                  | Tap 0–2: no visible change. Layout identical.                                                           |
| 7. Credentials are compile-time constants                | Confirm `kDemoEmail` + `kDemoPassword` are in `demo_credentials.dart` only, no literals in login logic. |

---

## Guardrails Compliance

| Rule                                    | Status                                                                            |
| --------------------------------------- | --------------------------------------------------------------------------------- |
| No secrets in source code               | ✅ Password is `String.fromEnvironment`, never a string literal                   |
| No service_role keys in client code     | ✅ Uses anon key only via existing `supabase` client                              |
| No initialization order changes         | ✅ Not applicable                                                                 |
| No new config loading paths             | ✅ Uses existing `--dart-define` pattern                                          |
| No new RLS-breaking policies            | ✅ No database changes                                                            |
| No async setState without mounted guard | ✅ `_triggerDemoLogin()` checks `mounted` before every `setState` in catch blocks |
| No controller/FocusNode leaks           | ✅ `_logoTapResetTimer?.cancel()` added to `dispose()`                            |
| No modification to `main.dart` routing  | ✅ Not required — AuthGate handles routing from `signedIn` event identically      |
| Modify only files in Architect plan     | ✅ All modified files are listed above                                            |

---

## Flagged Items for Tony

1. **Password not set yet.** The demo account password in the Play Store listing is `[TO BE SET]`. Tony must:  
   a. Create `demo@bandroadie.com` in Supabase Auth with email + password  
   b. Set a strong, memorable password (it will be public in the Play Store declaration)  
   c. Add `DEMO_PASSWORD=<value>` to local `.env`  
   d. Add the same value to CI/CD secrets if applicable

2. **Demo user profile and band membership must be seeded manually** (see Database Seeding section). This is a pre-test prerequisite, not a migration.

3. **Google Play App Access declaration text** (to add after implementation):

   > "Tap the BandRoadie logo 7 times on the login screen to reveal demo login. Use email: `demo@bandroadie.com`, password: `[your chosen password]`."

4. **`dart_defines.json` note:** This file is tracked in git and currently contains the Supabase anon key and Firebase keys. The `DEMO_PASSWORD` placeholder value is empty (`""`). The actual password must live ONLY in the gitignored `.env` file. Do not commit the real password to `dart_defines.json`.

---

## What the Engineer Must NOT Do

- Do not modify `main.dart`
- Do not add new Riverpod providers or notifiers
- Do not modify `auth_gate.dart`, `auth_state_provider.dart`, or `active_band_controller.dart`
- Do not add `DEMO_PASSWORD` to `REQUIRED_VARS` in build scripts (it is optional)
- Do not hardcode the password as a string literal anywhere
- Do not add a new route for demo login — the existing auth flow handles it
