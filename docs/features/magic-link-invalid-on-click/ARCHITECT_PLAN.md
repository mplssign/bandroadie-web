# ARCHITECT PLAN

## 1. Feature Slug

`bug/magic-link-invalid-on-click`

## 2. Problem Summary

When a user requests a magic link on the web app (app.bandroadie.com) and clicks the link from their email, they are routed to `/auth/confirm` but the screen displays "Invalid Link — The magic link appears to be incomplete or corrupted. Please request a new one." The authentication does not complete. This maps to the `missing_token` error state in `AuthConfirmScreen._handleConfirm()`.

## 3. Root Cause

**Confidence: MEDIUM-HIGH (multi-factor)**

The failure has **two contributing causes** — one server-side and one client-side:

### Primary cause: SDK `detectSessionInUri` silently fails (client-side)

The Supabase SDK's `detectSessionInUri: true` path is the primary mechanism for establishing sessions from magic link redirects on web. During `Supabase.initialize()`, the SDK reads the initial URL via `app_links_web` (`window.location.href`) and processes it through `getSessionFromUrl()`. If this path succeeds, `AuthConfirmScreen` finds an existing session at line 72 and navigates home.

When this SDK path **fails** (due to network error, expired token in the redirect, or the Supabase server changing its redirect format), the error is **silently swallowed** in `SupabaseAuth._handleDeeplink()`:

```dart
// supabase_flutter-2.12.0/lib/src/supabase_auth.dart:222-228
try {
    await Supabase.instance.client.auth.getSessionFromUrl(uri);
} on AuthException catch (error, stackTrace) {
    Supabase.instance.client.auth.notifyException(error, stackTrace);
} catch (error, stackTrace) {
    _log.warning('Error while getSessionFromUrl', error, stackTrace);
}
```

No session is established, no error is surfaced to the app code. The `AuthConfirmScreen` then falls through all its branches.

### Secondary cause: `_handleConfirm()` lacks `onAuthStateChange` listener

The fallback logic in `_handleConfirm()` relies on:

1. Checking `currentSession` (one-shot, may miss async session establishment)
2. Reading sessionStorage (works only if fragment was captured)
3. Polling `currentSession` 10 times over 2.5 seconds

However, the SDK's `detectSessionInUri` establishes the session asynchronously via `notifyAllSubscribers(AuthChangeEvent.signedIn)`. The proper way to detect this is by listening to `onAuthStateChange`, not by polling `currentSession`. The 2.5-second polling window may also be too short for slow networks.

### Triggering scenario

The redirect from Supabase's `/auth/v1/verify` endpoint arrives at the browser. If either:

- (a) The redirect URL's fragment (`#access_token=...`) is stripped during the redirect chain (e.g., by email client link protection like Gmail's proxy, Outlook SafeLinks, or a server-side redirect format change), OR
- (b) The Supabase production server has been updated to use PKCE-style redirects (`?code=...`) while the client expects implicit flow (`#access_token=...`)

Then the app receives a bare `/auth/confirm` URL. The SDK's `_isAuthCallbackDeeplink()` returns false (no fragment, no code), no session is established, and `AuthConfirmScreen` shows `missing_token`.

**ESCALATION REQUIRED**: Tony must verify in the Supabase dashboard:

1. **Auth > URL Configuration**: Check if `https://app.bandroadie.com/auth/confirm` (or `https://app.bandroadie.com/**`) is in the Redirect URLs list
2. **Auth > Providers > Email**: Check if PKCE is forced as the default flow type
3. **Auth > Email Templates > Magic Link**: Verify the template uses `{{ .ConfirmationURL }}` (not `{{ .TokenHash }}`)
4. Open browser DevTools Network tab, click a magic link, and inspect the exact 302/303 redirect response from Supabase's `/auth/v1/verify` endpoint — specifically the `Location` header

## 4. Reference Docs Consulted

- `supabase_flutter` v2.12.0 source (`lib/src/supabase_auth.dart`, `lib/src/supabase.dart`)
- `gotrue` v2.18.0 source (`lib/src/gotrue_client.dart` — `getSessionFromUrl()`, `setSession()`)
- `app_links_web` v1.0.4 source (`lib/app_links_web.dart`)
- Flutter `PathUrlStrategy` source (`flutter_web_plugins/lib/src/navigation/url_strategy.dart`)
- Supabase docs: [Passwordless Login](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- Supabase docs: [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- BandRoadie `BAND_ROADIE_DOCUMENTATION.md` (copilot-instructions.md)

## 5. Existing System Analysis

### Full Web Magic Link Flow

```
User enters email → _sendMagicLink()
    ↓
signInWithOtp(email, emailRedirectTo: 'https://app.bandroadie.com/auth/confirm')
    ↓
Supabase sends email with {{ .ConfirmationURL }} link pointing to:
  https://<project>.supabase.co/auth/v1/verify?token=<hash>&type=magiclink&redirect_to=https://app.bandroadie.com/auth/confirm
    ↓
User clicks link in email
    ↓
Supabase server verifies token, creates session, redirects (303) to:
  https://app.bandroadie.com/auth/confirm#access_token=<jwt>&refresh_token=<token>&expires_in=3600&token_type=bearer&type=magiclink
    ↓
Browser navigates to app.bandroadie.com/auth/confirm#...
    ↓
Vercel SPA rewrite serves index.html
    ↓
[STEP A] index.html JS (synchronous, first script):
  - Checks window.location.hash for 'access_token='
  - If found: stores cleanFragment in sessionStorage['supabase_auth_fragment']
    ↓
[STEP B] Service Worker update script:
  - If waiting SW exists AND not already reloaded: calls window.location.reload()
  - Sets sessionStorage['br_sw_reloaded'] = 'true'
  - After reload: fragment persists in URL, JS capture runs again, SW script exits early
    ↓
[STEP C] flutter_bootstrap.js loads Flutter engine
  - Plugin registration: AppLinksPluginWeb captures window.location.href (with fragment)
  - AppLinksPlatform.instance set to AppLinksPluginWeb
    ↓
[STEP D] main() executes:
  - usePathUrlStrategy() — sets routing strategy (does NOT modify window.location)
  - Supabase.initialize() [AWAITED]:
    - SupabaseAuth.initialize():
      - Restore persisted session from localStorage
      - detectSessionInUri = true → _startDeeplinkObserver()
      - _handleInitialUri():
        - _appLinks.getInitialLink() → Uri.parse(window.location.href) [captured at Step C]
        - _isAuthCallbackDeeplink(uri):
          - uri.fragment.contains('access_token') → TRUE (if fragment present)
          - _authFlowType == AuthFlowType.implicit → TRUE
          - Returns TRUE
        - _handleDeeplink(uri):
          - getSessionFromUrl(uri) — replaces # with ?, extracts tokens, calls getUser(accessToken)
          - On success: saves session, notifies AuthChangeEvent.signedIn
          - On error: SILENTLY CAUGHT, no session established ← PROBLEM
  - DeepLinkService.instance.initialize() — skips on web
  - runApp()
    ↓
[STEP E] Flutter routing:
  - PathUrlStrategy.getPath() returns '/auth/confirm' (fragment stripped, includeHash=false)
  - onGenerateRoute parses uri.queryParameters — tokenHash: null, code: null, type: null
  - Creates AuthConfirmScreen(tokenHash: null, code: null, type: null)
    ↓
[STEP F] AuthConfirmScreen._handleConfirm():
  1. Check currentSession — if SDK succeeded at Step D, session exists → navigate home ✅
  2. If null: read sessionStorage fragment → parse tokens → setSession(refreshToken)
  3. If no fragment or setSession fails: check tokenHash/code params (both null on web implicit)
  4. Poll currentSession 10× over 2.5s
  5. All failed → _error = 'missing_token' → "Invalid Link" displayed ← BUG MANIFESTS
```

### Failure path analysis

When the Supabase server redirect does NOT deliver tokens (fragment stripped or format changed):

- Step A: JS finds NO fragment → sessionStorage empty
- Step C: AppLinksPluginWeb captures URL with NO fragment
- Step D: `_isAuthCallbackDeeplink` returns FALSE → no deeplink processing
- Step F: currentSession is null, sessionStorage is null, no params → `missing_token`

## 6. Proposed Solution

### Fix 1: Replace polling with `onAuthStateChange` listener (auth_confirm_screen.dart)

**Rationale**: The 2.5-second polling loop is fragile. The Supabase SDK uses `onAuthStateChange` to notify about session changes. This is the correct, event-driven way to detect session establishment by `detectSessionInUri`.

**Change**: In `_handleConfirm()`, after all immediate checks fail, instead of (or in addition to) the polling loop:

1. Subscribe to `Supabase.instance.client.auth.onAuthStateChange`
2. Wait for `AuthChangeEvent.signedIn` or `AuthChangeEvent.initialSession` events
3. Use a longer timeout (5-8 seconds) to account for slow networks
4. If the event arrives with a valid session, navigate home
5. If timeout expires, THEN show `missing_token`

### Fix 2: Improve sessionStorage fragment path error handling (auth_confirm_screen.dart)

**Rationale**: When `setSession(refreshToken)` returns a null session (line 112-113), the code falls through silently to the `missing_token` path with no diagnostic information. This masks whether the fragment path was actually attempted and what went wrong.

**Change**: When `setSession` returns null session or throws, set a specific error state (e.g., `'session_creation_failed'`) with a user message like "Session could not be established. Please try requesting a new magic link." instead of falling through to the generic `missing_token`.

### Fix 3: Add onAuthStateChange listener early in initState (auth_confirm_screen.dart)

**Rationale**: There's a race between the SDK async session establishment and the synchronous `currentSession` check. If the SDK's deep link handling fires asynchronously (after `Supabase.initialize()` resolves but before the session is fully saved), the session might not be reflected in `currentSession` when checked.

**Change**: Set up an `onAuthStateChange` listener in `initState()` BEFORE calling `_handleConfirm()`. If a `signedIn` event fires at any point while the screen is mounted, navigate home immediately. This acts as a safety net for any timing issues.

### Ordering

Fix 3 should be implemented first (safety net listener), then Fix 1 (replace polling with event-driven wait), then Fix 2 (better error differentiation). Fix 3 subsumes part of Fix 1's purpose but both should be present for clarity.

## 7. Database Impact

- **RLS**: Not applicable. This is a client-side auth flow bug.
- **Migrations**: Not applicable. No database schema changes needed.
- **RPCs**: Not applicable. No RPC functions involved.

## 8. Flutter Architecture Changes

None. The fix stays within the existing auth flow architecture. No new providers, no new services, no new patterns. The change is confined to improving the resilience of `AuthConfirmScreen._handleConfirm()`.

## 9. Files to Create

None.

## 10. Files to Modify

| File                                         | Change                                                                                                                                                                                        | Scope                                                                          |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `lib/features/auth/auth_confirm_screen.dart` | Add `onAuthStateChange` listener in `initState()` as safety net; replace polling loop with event-driven wait using `onAuthStateChange`; improve error handling for null `setSession` response | `_handleConfirm()` method and `initState()`/`dispose()` for listener lifecycle |

## 11. Files Off-Limits

| File                                      | Reason                                                      |
| ----------------------------------------- | ----------------------------------------------------------- |
| `lib/main.dart`                           | Init order, Supabase config, and routing must not change    |
| `lib/app/services/deep_link_service.dart` | Native only — not involved in web auth                      |
| `lib/features/auth/login_screen.dart`     | `signInWithOtp` config and `emailRedirectTo` are correct    |
| `web/index.html`                          | JS fragment capture logic is correct and not the root cause |
| `lib/app/utils/web_storage.dart`          | Storage key matches between JS and Dart — no change needed  |
| `lib/app/utils/web_storage_web.dart`      | Implementation is correct                                   |
| Any migration or edge function            | No database involvement                                     |
| `supabase/config.toml`                    | Local config; production settings are in dashboard          |

## 12. System Impact Map

| System                            | Impact                                                   |
| --------------------------------- | -------------------------------------------------------- |
| Auth / Session                    | **Affected** — fixing session detection resilience       |
| Routing (onGenerateRoute)         | Unaffected — no changes to route parsing                 |
| Service Worker update logic       | Unaffected — not the root cause                          |
| Web index.html JS                 | Unaffected — fragment capture is correct                 |
| Native (iOS / Android / macOS)    | **Unaffected** — web-only code path, guarded by `kIsWeb` |
| Setlists, Songs, Gigs, Rehearsals | Unaffected                                               |
| Riverpod state management         | Unaffected — no provider changes                         |

## 13. Regression Risk

**Rating: LOW**

Rationale:

- Changes are scoped to a single method (`_handleConfirm()`) in a single file
- The web-only code path is guarded by `kIsWeb` — native platforms are untouched
- Adding an `onAuthStateChange` listener is an additive change; it doesn't remove existing functionality
- The listener pattern is already used elsewhere in the codebase (`AuthGate`)
- The fix improves resilience without changing the happy path — if the SDK establishes the session before the widget mounts, the `currentSession` check at line 72 still works as before

## 14. Engineer Task Breakdown

### Task 1: Add `onAuthStateChange` safety net listener

**File**: `lib/features/auth/auth_confirm_screen.dart`

1. Add a `StreamSubscription<AuthState>? _authSubscription;` field to `_AuthConfirmScreenState`
2. In `initState()`, BEFORE calling `_handleConfirm()`, subscribe to `Supabase.instance.client.auth.onAuthStateChange`
3. In the listener callback, check for `AuthChangeEvent.signedIn` with a non-null session
4. If detected and `_loading` is still true (haven't errored yet), call `_navigateToHome()`
5. Cancel the subscription in `dispose()`

### Task 2: Replace polling with event-driven session wait

**File**: `lib/features/auth/auth_confirm_screen.dart`

1. In the `_handleConfirm()` web fallback path (currently lines 144-156), replace the 10×250ms polling loop
2. Use a `Completer<void>` that completes when either:
   - `onAuthStateChange` fires with a `signedIn` event (from the Task 1 listener), OR
   - A timeout of 6 seconds elapses
3. After the completer resolves, check `currentSession` one final time
4. If still null, proceed to `missing_token` error
5. Remove the `for (int i = 0; i < 10; ...)` polling loop

### Task 3: Improve error differentiation for failed sessionStorage path

**File**: `lib/features/auth/auth_confirm_screen.dart`

1. After `setSession(refreshToken)` returns null session (line 112-113), instead of silently continuing, log a clear diagnostic message
2. Try calling `setSession` with the access token as a secondary attempt (the access token was already validated by the SDK if it was valid)
3. If both fail, set `_error` to a new distinct error type `'session_failed'` with message: "We found your login tokens but couldn't establish a session. Please try again."
4. Add a corresponding error display case in the `build()` method for `'session_failed'`

### Task 4: Cancel auth subscription on navigation

**File**: `lib/features/auth/auth_confirm_screen.dart`

1. In `_navigateToHome()`, cancel `_authSubscription` before navigation to prevent double-navigation
2. Add a `_navigating` flag to prevent the `onAuthStateChange` listener from triggering navigation if `_handleConfirm()` is already navigating

## 15. Verification Plan

### Tier 1: Pre-deploy (local/staging)

1. **Unit logic check**: Verify that `_handleConfirm()` subscribes to `onAuthStateChange` before any async work
2. **Happy path simulation**: With DevTools, navigate to `/auth/confirm` with a valid Supabase session already established — should navigate home immediately
3. **Missing fragment simulation**: Navigate to `/auth/confirm` with no query params, no fragment, and no existing session. Verify:
   - The `onAuthStateChange` listener is active
   - The timeout fires after 6 seconds (not 2.5)
   - The error displayed is `missing_token` (or the new `session_failed` if the fragment path was attempted)
4. **Auth event detection**: Manually trigger a session establishment (via browser console calling `supabase.auth.setSession(...)`) while on `/auth/confirm` with no params — verify the `onAuthStateChange` listener catches it and navigates home
5. **Dispose safety**: Navigate away from `/auth/confirm` before timeout completes — verify no errors or state updates after dispose

### Tier 2: Post-deploy (production)

1. **End-to-end magic link flow**: Request a magic link on `app.bandroadie.com`, click it from email, verify authentication completes and user lands inside the app
2. **Multiple email clients**: Test magic link clicks from Gmail (web), Apple Mail, and Outlook — verify all work
3. **Slow network**: Throttle network in DevTools to 3G, click magic link — verify the extended timeout (6s) is sufficient
4. **Rapid re-click**: Click same magic link twice rapidly — verify graceful handling (no crash, shows appropriate error)
5. **Console inspection**: Open DevTools Console before clicking magic link, verify debug logs show the auth flow path taken (SDK `detectSessionInUri`, or sessionStorage fallback, or `onAuthStateChange` listener)

## 16. QA Regression Areas

- **Web magic link happy path (primary)**: Request magic link → click → authenticated → lands in app
- **Web magic link with expired token**: Click a link that has expired (>1 hour old) — should show "expired_link" error, NOT "missing_token"
- **Web magic link with reused token**: Click an already-used link — should show "reused_link" error, NOT "missing_token"
- **Native magic link flows must be unaffected**: iOS/Android/macOS deep link auth continues to work via `DeepLinkService`
- **Web login with session restore**: Refresh the web app while already logged in — session should persist
- **Web login from marketing site**: Navigating to `bandroadie.com` (marketing) should NOT trigger auth flow

## 17. Out of Scope

- Changing `AuthFlowType` from implicit to PKCE on web
- Changing `detectSessionInUri` setting
- Modifying `main.dart` initialization order
- Modifying the Supabase email template (this is a dashboard change, not a code change)
- Restructuring the overall auth architecture
- Adding native platform deep link changes
- Fixing email client link mangling behavior (external to our control)
- Service worker update logic changes (not the root cause)
- Upgrading `supabase_flutter` SDK version (could be a future follow-up if server-side issues are confirmed)
