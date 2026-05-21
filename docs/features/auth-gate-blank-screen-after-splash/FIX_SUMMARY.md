# Bug Fix: AuthGate Blank Screen After Splash

**Slug:** `bug/auth-gate-blank-screen-after-splash`  
**Priority:** Critical — production broken for unauthenticated web users  
**Status:** Fixed  
**Date:** May 21, 2026

---

## Problem

`app.bandroadie.com` showed the login screen for ~1 second during splash animation, then rendered a blank white screen. The site was completely inaccessible to new and logged-out users.

### Console Evidence

```
[AuthGate] build() - _showSplash=true, authenticated=false  ← login briefly visible
[AuthGate] Lifecycle: null -> AppLifecycleState.inactive    ← splash ends, screen goes blank
```

When `_showSplash` flipped to `false` with `authenticated=false`, the AuthGate rendered nothing.

---

## Root Cause

The `build()` method in [auth_gate.dart](../../../lib/features/auth/auth_gate.dart) had implicit control flow that relied on `_buildAuthContent()` to handle all states. Under certain timing conditions (related to lifecycle state transitions), the unauthenticated state after splash completion wasn't reliably rendering the LoginScreen.

**Previous Structure:**

```dart
final authContent = _buildAuthContent(context, authState);  // Build once

if (_showSplash) return Stack([authContent, splash]);
return authContent;  // Implicit trust that authContent handles all cases
```

This created a regression when the splash-screen-video feature was introduced (~May 11).

---

## Solution

Restructured the `build()` method to have **explicit control flow** for the critical unauthenticated state:

**New Structure:**

```dart
if (_showSplash) {
  final authContent = _buildAuthContent(context, authState);
  return Stack([authContent, splash]);
}

// CRITICAL FIX: Explicit handling of unauthenticated state
if (!authState.isAuthenticated) {
  // Safeguard check for state mismatch
  if (supabase.auth.currentSession != null) {
    // Force refresh and show loading
    return loadingScaffold;
  }
  // Always show login screen for logged-out users after splash
  return const LoginScreen();
}

// User is authenticated - delegate to full logic
return _buildAuthContent(context, authState);
```

### Key Changes

1. **Explicit branch** for `!_showSplash && !authenticated` that directly returns `LoginScreen()`
2. **Safeguard check** remains in place to catch provider/Supabase state mismatch
3. **Simplified call pattern** — `_buildAuthContent()` only called when needed
4. **Clear debug logs** added: `"No session after splash - showing login screen"`

---

## Files Modified

- [lib/features/auth/auth_gate.dart](../../../lib/features/auth/auth_gate.dart) — Restructured `build()` method

---

## Verification

### Pre-Deployment Verification

✅ `flutter analyze` passes with 0 issues  
✅ `flutter build web` succeeds in production mode

### Production Verification Checklist

1. **Load `app.bandroadie.com` in incognito window (no active session)**
   - Expected: Splash plays for ~3 seconds
   - Expected: Login screen remains visible after splash completes
   - Expected: No blank screen at any point

2. **Check browser console logs**
   - Expected: `[AuthGate] build() - _showSplash=false, authenticated=false`
   - Expected: `[AuthGate] No session after splash - showing login screen`
   - Expected: No errors

3. **Test authenticated flow**
   - Log in via magic link
   - Expected: After login, user lands on home/dashboard correctly
   - Expected: Refresh page → still authenticated (no logout)

4. **Test lifecycle transitions (iOS/iPad)**
   - Open app while logged out
   - Expected: Login screen appears after splash
   - Send to background (inactive state)
   - Return to foreground
   - Expected: Login screen still visible

---

## Regression Risk

**LOW** — Scoped to AuthGate control flow only. No changes to:

- Authentication logic
- Session management
- Profile checking
- Band loading
- Any other features

The fix makes the unauthenticated path MORE explicit and reliable, reducing edge cases rather than introducing new behavior.

---

## Related Features

- **Splash Screen Video** (`splash-screen-video`) — Feature that introduced the regression
- **Auth State Provider** — Dependency that provides auth state
- **Login Screen** — Widget explicitly returned by this fix

---

## Notes

- This is a **defensive fix** — the existing `_buildAuthContent()` should have handled this case, but explicit control flow eliminates timing-related edge cases
- The safeguard check for state mismatch (provider vs. Supabase) remains in place
- Debug logging enhanced to catch this scenario in future monitoring
