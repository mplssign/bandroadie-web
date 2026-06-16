# Auth Flow Audit — ARCHITECT PLAN

**Feature:** Complete audit of authentication flow for new user registration and existing user sign-in  
**Branch:** `feat/auth-flow-audit`  
**Created:** 2026-06-14  
**Architect:** AI Agent  
**Context:** Facebook ad campaign driving new users → marketing site → app download → signup/login. Flow must be bulletproof.

---

## Executive Summary

### Current State Assessment

**✅ What Works:**

- PKCE authentication flow is properly configured across all platforms (Web, iOS, Android, macOS)
- Magic link authentication with email OTP is functional
- Deep link handling via `DeepLinkService` covers cold start, background resume, and foreground scenarios
- Profile completion gate ensures users provide first_name/last_name before accessing app
- Session persistence via Supabase SDK with automatic token refresh
- Band loading and selection with SharedPreferences persistence
- Multiple safeguards for session state sync (auth state listener, lifecycle observer, periodic timer)
- Invite acceptance via edge function with RLS bypass

**⚠️ What's Fragile:**

- **Web auth confirmation** relies on JavaScript fragment capture + sessionStorage, creating multiple failure points
- **Session state synchronization** has three competing mechanisms that could race or conflict
- **Error messaging** is generic and doesn't guide users toward recovery
- **PKCE code verifier loss** on logout/restart leads to cryptic auth failures
- **Band member / setlist hydration** on fresh accounts has no explicit empty-state guards
- **Profile skip flow** allows null first_name/last_name despite database expecting non-null values

**❌ What's Broken:**

- **No explicit RLS validation** that new users can create their first band
- **Invite processing on fresh accounts** calls edge function even when no invites exist
- **Private browsing mode** silently fails to persist active band selection with no user feedback

---

## Authentication Flow Trace

### Happy Path: New User Registration

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 1. User taps Facebook ad → Marketing site (bandroadie.com)              │
│ 2. User downloads app from App Store / Google Play                       │
│ 3. User opens app → AuthGate checks session → null → LoginScreen        │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ LoginScreen (lib/features/auth/login_screen.dart)                        │
│   - User enters email                                                     │
│   - Tap "Send Magic Link"                                                 │
│   - signInWithOtp(email:, emailRedirectTo:) called                       │
│     • Web: https://app.bandroadie.com/auth/confirm                       │
│     • Android: https://app.bandroadie.com/auth/callback (App Link)       │
│     • iOS/macOS: bandroadie://login-callback/                            │
│   - Success message: "Check your email for the login link"               │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ Email received → User clicks magic link                                  │
│   PKCE Flow: Link contains ?code=... parameter                           │
│   code_verifier stored in requesting device's storage                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ Platform-specific routing:                                               │
│                                                                           │
│ Web:                                                                      │
│   → index.html JavaScript captures URL fragment (if present)             │
│   → Stores in sessionStorage['supabase.auth.fragment']                   │
│   → Routes to /auth/confirm?code=...                                     │
│   → AuthConfirmScreen mounted                                            │
│                                                                           │
│ Native (iOS/Android/macOS):                                              │
│   → Deep link opens app (cold start or resume)                           │
│   → DeepLinkService.initialize() or uriLinkStream receives link          │
│   → _handleDeepLink() extracts code parameter                            │
│   → exchangeCodeForSession(code) called                                  │
│   → Session established → authStateProvider updated                      │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ AuthConfirmScreen (lib/features/auth/auth_confirm_screen.dart)           │
│                                                                           │
│ Web Path:                                                                 │
│   1. Check for existing session → if found, navigate to /app             │
│   2. Try to retrieve fragment from sessionStorage                        │
│   3. Parse fragment for access_token + refresh_token                     │
│   4. Call setSession(refreshToken)                                       │
│   5. If successful → wait for authStateProvider to sync                  │
│   6. Navigate to /app                                                     │
│                                                                           │
│ Native Path (if not handled by DeepLinkService):                         │
│   1. Extract code from query parameters                                  │
│   2. Call exchangeCodeForSession(code)                                   │
│   3. Wait for authStateProvider to sync (max 5 seconds)                  │
│   4. Push AuthGate                                                        │
│                                                                           │
│ Error Handling:                                                           │
│   • expired_link → "Magic Link Expired" UI                               │
│   • browser_mismatch → "Login Link Opened in Wrong Browser" UI           │
│   • missing_token → "Invalid Link" UI                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ AuthGate (lib/features/auth/auth_gate.dart)                              │
│   - Watches authStateProvider for isAuthenticated                        │
│   - Session confirmed → initializeAuth()                                 │
│   - Calls _checkProfileComplete()                                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ Profile Completeness Check                                               │
│   Query: SELECT first_name, last_name FROM users WHERE id = auth.uid()   │
│   RLS Policy: Users can only read their own profile                      │
│                                                                           │
│   Case 1: first_name AND last_name non-null and non-empty                │
│     → Profile complete → proceed to invite check                         │
│                                                                           │
│   Case 2: Either field is null or empty                                  │
│     → Show ProfileGateScreen (MyProfileScreen with isGated=true)         │
│     → User must provide first_name + last_name                           │
│     → Can skip via onSkip callback                                       │
│     → After save or skip → proceed to invite check                       │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ Pending Invite Check (_checkAndProcessPendingInvite)                     │
│   - Only runs once per session (_hasCheckedPendingInvites guard)         │
│   - Calls supabase.functions.invoke('accept-invite', body: {})           │
│   - Edge function uses JWT for auth (service role with RLS bypass)       │
│   - Silently accepts any pending invitations for user's email            │
│   - No success message shown to user                                     │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ Band Loading (activeBandProvider.notifier.loadUserBands)                 │
│   Query:                                                                  │
│     SELECT bands(*) FROM band_members                                    │
│     WHERE user_id = auth.uid() AND status = 'active'                     │
│                                                                           │
│   Result handling:                                                        │
│     • Empty array → userBands = [], activeBand = null                    │
│       → AuthGate routes to NoBandShell (welcome screen)                  │
│                                                                           │
│     • Non-empty → Select persisted band ID from SharedPreferences        │
│       → If persisted ID found in bands → set as active                   │
│       → If not found → select first band, persist its ID                 │
│       → AuthGate routes to AppShell (main app)                           │
└─────────────────────────────────────────────────────────────────────────┘
                                    ↓
┌─────────────────────────────────────────────────────────────────────────┐
│ Final State: User in app                                                 │
│   • Session established and persisted                                    │
│   • Profile complete (or skipped)                                        │
│   • Invites accepted (if any existed)                                    │
│   • Bands loaded (or NoBandShell if none)                                │
│   • Active band selected (if bands exist)                                │
│   • Push token registered (iOS/Android/Web)                              │
└─────────────────────────────────────────────────────────────────────────┘
```

### Happy Path: Existing User Sign-In

```
Same flow as above, but:
  1. Profile is already complete → skip ProfileGateScreen
  2. Invite check still runs (once per session)
  3. Bands already exist → loads and selects persisted active band
  4. Routes directly to AppShell (dashboard)
```

---

## Failure Modes & Edge Cases

### P0 — Critical (Blocks User Progress)

#### 1. Web Fragment Auth Failure

**Failure Mode:**  
On web, magic link contains access_token in URL fragment (#access_token=...). JavaScript in `index.html` must capture this fragment before Flutter loads, store it in sessionStorage, then AuthConfirmScreen retrieves it. This chain has multiple failure points:

- JavaScript fails to execute (ad blockers, strict CSP policies)
- sessionStorage unavailable (incognito mode, browser restrictions)
- Fragment not captured before redirect
- Malformed fragment parsing

**Current Behavior:**  
AuthConfirmScreen falls back to checking query parameters (?code=...) and shows "Invalid Link" error if no auth data found.

**User Impact:**  
User clicks magic link → sees "Invalid Link" error → cannot log in → must request new link → same issue repeats.

**Root Cause Confidence:** HIGH — Direct observation of multi-step dependency chain.

**Proposed Fix:**

1. Migrate web flow to use PKCE code exchange exclusively (already supported by Supabase)
2. Remove fragment-based auth path from AuthConfirmScreen
3. Update emailRedirectTo to always use ?code= flow on web
4. Simplify error messaging since only one code path remains
5. Add retry mechanism for sessionStorage failures

**Files to Modify:**

- `lib/features/auth/login_screen.dart` — Remove fragment-based redirectTo
- `lib/features/auth/auth_confirm_screen.dart` — Remove fragment parsing logic
- `web/index.html` — Remove JavaScript fragment capture (no longer needed)

---

#### 2. PKCE Code Verifier Loss

**Failure Mode:**  
PKCE flow stores code_verifier in device storage (localStorage on web, platform storage on native). If user:

- Logs out after requesting magic link but before clicking it
- App is force-quit or crashes before clicking link
- Clears browser data / app cache

Then clicks magic link → code_verifier is gone → exchangeCodeForSession() fails with "invalid_grant" error.

**Current Behavior:**  
Shows generic "Authentication Error" with raw error message. User doesn't understand they need to request a new link.

**User Impact:**  
User clicks magic link → sees cryptic error → tries again → same error → thinks app is broken → abandons.

**Root Cause Confidence:** MEDIUM — Strongly implied by PKCE architecture and observed error handling.

**Proposed Fix:**

1. Detect "invalid_grant" and "code_verifier" errors specifically
2. Show user-friendly message: "This magic link has expired. Please request a new one from the login screen."
3. Add deep link to error UI that routes back to LoginScreen
4. Consider adding timestamp to magic link requests so UI can detect stale attempts

**Files to Modify:**

- `lib/features/auth/auth_confirm_screen.dart` — Enhanced error classification
- `lib/app/services/deep_link_service.dart` — Detect code verifier errors

---

#### 3. Session State Sync Race Conditions

**Failure Mode:**  
Three mechanisms try to keep session state in sync:

- Supabase SDK's `onAuthStateChange` stream (automatic)
- `WidgetsBindingObserver.didChangeAppLifecycleState` (manual refresh on app resume)
- Periodic timer in AuthGate (every 5 seconds, force checks)

These can race:

- Lifecycle observer fires before auth state change event propagates
- Periodic timer triggers mid-auth-flow, causing duplicate state updates
- Multiple components call `refreshSession()` simultaneously

**Current Behavior:**  
Usually works due to defensive checks, but logs show occasional "State mismatch" warnings. iPad multitasking exacerbates timing issues.

**User Impact:**  
Intermittent login loops, blank screens, or being shown LoginScreen despite having valid session.

**Root Cause Confidence:** HIGH — Observed in code: multiple `refreshSession()` call sites + periodic timer + lifecycle listener.

**Proposed Fix:**

1. **Primary:** Rely solely on Supabase SDK's `onAuthStateChange` stream
2. **Backup:** Single refresh on app lifecycle resume (debounced to prevent rapid-fire)
3. **Remove:** Periodic 5-second session sync timer (belt-and-suspenders approach no longer needed)
4. **Guard:** Add mutex/lock to prevent concurrent `refreshSession()` calls

**Files to Modify:**

- `lib/features/auth/auth_gate.dart` — Remove periodic timer, debounce lifecycle refresh
- `lib/features/auth/auth_state_provider.dart` — Add refresh guard

---

#### 4. Empty Band State Handling

**Failure Mode:**  
When `loadUserBands()` returns empty array (new user with no bands), AuthGate correctly routes to NoBandShell. However:

- No explicit validation that `userBands` array is iterable
- SharedPreferences fallback on persistedId lookup could throw if keys are malformed
- NoBandShell assumes certain state shape (could break if state is undefined/null)

**Current Behavior:**  
Works for legitimate empty state, but could crash on malformed data.

**User Impact:**  
Edge case: if SharedPreferences or state becomes corrupted, user sees crash instead of NoBandShell.

**Root Cause Confidence:** MEDIUM — No observed failures, but defensive guards are minimal.

**Proposed Fix:**

1. Add explicit null/empty guards in `loadUserBands()` before iterating
2. Wrap SharedPreferences access in try-catch with fallback to default state
3. Add logging for unexpected state shapes
4. Ensure NoBandShell can render with partially-initialized state

**Files to Modify:**

- `lib/features/bands/active_band_controller.dart` — Add defensive guards
- `lib/features/shell/no_band_shell.dart` — Validate state assumptions

---

### P1 — High Priority (Poor UX, Potential Errors)

#### 5. Email Scanner Link Consumption

**Failure Mode:**  
Corporate/Gmail security scanners follow magic links to scan for phishing. PKCE protects against session theft (scanner can't complete exchange without code_verifier), but link is marked as "already consumed" by Supabase.

User clicks link → sees "This link has already been used" error → doesn't understand why.

**Current Behavior:**  
AuthConfirmScreen shows "Magic Link Expired" UI with generic message.

**User Impact:**  
User confused, thinks they clicked wrong link or that link is broken.

**Root Cause Confidence:** HIGH — Known PKCE security feature, documented in Supabase.

**Proposed Fix:**

1. Detect "already been consumed" error specifically
2. Show explanation: "This link may have been scanned by email security software before you clicked it. Please request a new magic link."
3. Add note for Outlook/corporate email users
4. Consider rate-limiting magic link requests to prevent abuse

**Files to Modify:**

- `lib/features/auth/auth_confirm_screen.dart` — Add "scanner consumed" error UI

---

#### 6. Profile Completion Skip Flow Validation

**Failure Mode:**  
User can skip profile completion via `onSkip` callback. Code sets `_profileSkipped = true` and proceeds to load bands. However:

- Database expects `first_name` and `last_name` to be non-null (implied by query logic)
- If user skips, these fields remain null
- Downstream queries might fail or show "null" in UI

**Current Behavior:**  
Skip works, but profile remains incomplete. No visible error, but could cause UI issues or query failures.

**User Impact:**  
User sees "null" name in headers, sharing, or other UI. Potentially confusing or unprofessional.

**Root Cause Confidence:** MEDIUM — Skip callback exists, but no validation of null safety downstream.

**Proposed Fix:**

1. Remove skip option (force profile completion)
   OR
2. Add database migration to make first_name/last_name nullable + update UI to handle null gracefully
3. If keeping skip, add validation before calling any queries that assume non-null names

**Files to Modify:**

- `lib/features/auth/auth_gate.dart` — Remove onSkip or add validation
- `lib/features/profile/my_profile_screen.dart` — Disable skip button or add confirmation dialog

---

#### 7. Multiple Auth State Sources

**Failure Mode:**  
Auth state is read from three places:

- `authStateProvider` (reactive Riverpod state)
- `Supabase.instance.client.auth.currentSession` (direct SDK access)
- Periodic timer safeguard in AuthGate

These can temporarily disagree during rapid state changes (login, logout, token refresh).

**Current Behavior:**  
Code has defensive checks (`if provider says null but SDK says non-null, force refresh`), but this is reactive, not proactive.

**User Impact:**  
Brief flicker of LoginScreen when session exists, or vice versa.

**Root Cause Confidence:** HIGH — Observed in defensive checks throughout AuthGate.

**Proposed Fix:**

1. Designate `authStateProvider` as single source of truth
2. All components read from provider, never directly from SDK
3. Provider is the only code that reads from SDK
4. Remove periodic timer (covered by P0 issue #3)

**Files to Modify:**

- `lib/features/auth/auth_gate.dart` — Remove direct SDK checks
- `lib/features/bands/band_repository.dart` — Use provider instead of `supabase.auth.currentUser`
- All feature files — Audit for direct `supabase.auth` access

---

#### 8. Network Failure Error Messaging

**Failure Mode:**  
If network is unavailable during:

- `signInWithOtp()` call
- `exchangeCodeForSession()` call
- Profile completeness check
- Band loading

User sees generic "Error: ..." message with stack trace or Supabase error code.

**Current Behavior:**  
Errors are caught and displayed as-is. No retry mechanism, no clear recovery path.

**User Impact:**  
User doesn't know if problem is temporary (network) or permanent (account issue).

**Root Cause Confidence:** HIGH — Observed in catch blocks.

**Proposed Fix:**

1. Detect network errors specifically (`SocketException`, `TimeoutException`)
2. Show user-friendly message: "No internet connection. Please check your connection and try again."
3. Add "Retry" button that repeats the failed operation
4. Consider offline queue for auth requests

**Files to Modify:**

- `lib/features/auth/login_screen.dart` — Wrap signInWithOtp in network error handler
- `lib/features/auth/auth_confirm_screen.dart` — Add retry for session exchange
- `lib/features/auth/auth_gate.dart` — Add retry for profile/band loading

---

#### 9. Invite Processing on Fresh Accounts

**Failure Mode:**  
Every authenticated user triggers `_checkAndProcessPendingInvite()`, which calls the `accept-invite` edge function. For users with no pending invites, this:

- Fires edge function cold start (slow)
- Queries database for invites (none found)
- Returns success but did nothing

**Current Behavior:**  
Works correctly, but adds latency on every login for all users.

**User Impact:**  
Slight delay during login. Edge function cold start can take 1-2 seconds.

**Root Cause Confidence:** MEDIUM — Code always calls edge function, no pre-check.

**Proposed Fix:**

1. Query `band_invitations` table directly from client first
2. Only call edge function if pending invites exist
3. Or: Move invite acceptance to profile completion step (only for new users)

**Files to Modify:**

- `lib/features/auth/auth_gate.dart` — Add pre-check query before edge function call

---

### P2 — Medium Priority (Edge Cases, Polish)

#### 10. Deep Link Timing on iPad

**Observation:**  
iPad multitasking (Split View, Slide Over) causes app to enter `inactive` state instead of `paused`. Magic links may arrive while app is in this liminal state. Complex lifecycle handling tries to catch this, but timing is inherently racy.

**Current Mitigation:**  
Multiple safeguards (lifecycle observer, force refresh on resume, periodic timer). Usually works.

**Recommendation:**  
Keep current safeguards. Add telemetry to track iPad-specific auth failures.

---

#### 11. SharedPreferences Fallback in Private Browsing

**Observation:**  
When SharedPreferences is unavailable (private browsing, strict security mode), active band selection fails silently. User sees logs: "SharedPreferences unavailable (private browsing?)" but no UI feedback.

**Current Behavior:**  
Band selection still works in-memory, but doesn't persist across sessions.

**Recommendation:**  
Add banner notification when private browsing is detected: "You're in private browsing mode. Some features may not persist across sessions."

**Files to Modify:**

- `lib/features/bands/active_band_controller.dart` — Emit state flag for private browsing detection
- `lib/features/shell/app_shell.dart` — Show banner when flag is true

---

#### 12. Magic Link Expiry Clarity

**Observation:**  
No explicit UI indicating how long magic links are valid. Supabase default is typically 1 hour, but users don't know this.

**Recommendation:**  
Add tooltip or help text: "Magic links expire after 1 hour for security. Request a new one if yours has expired."

**Files to Modify:**

- `lib/features/auth/login_screen.dart` — Add help text after "Check your email" message

---

#### 13. RLS Policy Validation for New Users

**Observation:**  
No automated test or migration script validates that a newly created user can:

- Insert a row into `bands` table
- Insert a row into `band_members` table
- Read their own band_members rows

RLS policies are assumed correct, but schema changes could break this.

**Recommendation:**  
Add migration test script or E2E test that:

1. Creates test user via Supabase Auth
2. Attempts to create a band
3. Verifies band_member row is created
4. Cleans up test data

**Files to Create:**

- `sql/diagnostics/test_new_user_rls.sql` — SQL script to validate RLS policies
- `test/integration/auth_flow_test.dart` — Flutter integration test for full signup flow

---

#### 14. Token Refresh Visibility

**Observation:**  
No explicit token refresh logic visible in app code. Relies entirely on Supabase SDK's automatic refresh (happens in background when access_token expires).

**Recommendation:**  
Add logging when token refresh occurs (for debugging). Consider showing subtle UI indicator if refresh fails (rare, but possible on network issues).

**Files to Modify:**

- `lib/features/auth/auth_state_provider.dart` — Log `AuthChangeEvent.tokenRefreshed` events

---

## Database Impact Assessment

### Tables Involved in Auth Flow

| Table                      | Operation                    | RLS Policy                                                    | Impact                                     |
| -------------------------- | ---------------------------- | ------------------------------------------------------------- | ------------------------------------------ |
| `auth.users`               | SELECT                       | User can read own row                                         | ✅ Verified                                |
| `users` (public)           | SELECT first_name, last_name | User can read own row                                         | ✅ Verified                                |
| `band_invitations`         | SELECT                       | User can read invitations for their email                     | ⚠️ Not explicitly verified                 |
| `band_members`             | SELECT, INSERT               | User can read/insert own memberships                          | ⚠️ Not explicitly verified                 |
| `bands`                    | SELECT, INSERT               | User can read bands they're a member of; can insert new bands | ⚠️ Not explicitly verified                 |
| `device_tokens`            | INSERT, UPDATE               | User can manage own tokens                                    | ✅ Verified (from notifications migration) |
| `notification_preferences` | INSERT, SELECT               | User can manage own preferences                               | ✅ Verified (from notifications migration) |

### RLS Policy Gaps

**Critical Validation Needed:**

1. Verify new user can INSERT into `bands` table (first band creation)
2. Verify new user can INSERT into `band_members` table (self-membership on band creation)
3. Verify `band_invitations` RLS allows user to read invitations by email (before account exists)
4. Verify `accept-invite` edge function can UPDATE `band_invitations` and INSERT `band_members` with service role

**Recommended Actions:**

1. Review all RLS policies on auth-related tables
2. Create SQL diagnostic script: `sql/diagnostics/validate_auth_rls.sql`
3. Add to deployment checklist: "Run RLS validation script after schema changes"

---

## System Impact Map

| System                 | Impact        | Details                                                           |
| ---------------------- | ------------- | ----------------------------------------------------------------- |
| **Auth / Session**     | 🔴 Affected   | Core focus of this audit. Multiple fixes required.                |
| **Profile**            | 🟡 Affected   | Profile completion gate, skip flow validation.                    |
| **Bands**              | 🟡 Affected   | First band creation RLS, empty state handling, invite acceptance. |
| **Members / RBAC**     | 🟢 Unaffected | No changes to role assignment or permissions.                     |
| **Gigs / Rehearsals**  | 🟢 Unaffected | Only indirectly via auth gate.                                    |
| **Setlists / Catalog** | 🟢 Unaffected | Only indirectly via band loading.                                 |
| **Notifications**      | 🟡 Affected   | Push token registration on login, device token RLS.               |
| **Routing**            | 🟡 Affected   | AuthGate routing logic, deep link handling.                       |
| **Settings**           | 🟢 Unaffected | Settings screen accessed after auth succeeds.                     |

---

## Proposed Implementation Plan

### Phase 1: Critical Fixes (P0)

**Must complete before any other work. These block users.**

#### Task 1.1: Simplify Web Auth Flow

- **File:** `lib/features/auth/login_screen.dart`
- **Change:** Update `emailRedirectTo` for web to use code-based flow only (remove fragment path)
- **File:** `lib/features/auth/auth_confirm_screen.dart`
- **Change:** Remove sessionStorage + fragment parsing logic; rely only on `?code=` parameter
- **File:** `web/index.html`
- **Change:** Remove JavaScript fragment capture (no longer needed)
- **Test:** Web login with magic link, verify code exchange succeeds

#### Task 1.2: Enhanced PKCE Error Handling

- **File:** `lib/features/auth/auth_confirm_screen.dart`
- **Change:** Detect "invalid_grant" and "code_verifier" errors specifically
- **Change:** Show user-friendly error: "This magic link has expired or was opened incorrectly. Please request a new one."
- **Change:** Add button that routes back to LoginScreen
- **File:** `lib/app/services/deep_link_service.dart`
- **Change:** Detect code verifier errors in `exchangeCodeForSession` catch block
- **Test:** Logout → request magic link → login again → click old link → verify clear error message

#### Task 1.3: Session State Sync Refactor

- **File:** `lib/features/auth/auth_gate.dart`
- **Change:** Remove `_sessionSyncTimer` (periodic 5-second check)
- **Change:** Keep lifecycle observer, but debounce `refreshSession()` calls (max 1 per 2 seconds)
- **File:** `lib/features/auth/auth_state_provider.dart`
- **Change:** Add `_refreshInProgress` flag to prevent concurrent `refreshSession()` calls
- **Change:** Skip refresh if session hasn't changed (compare access tokens)
- **Test:** Open app → put in background → deep link arrives → resume → verify single refresh

#### Task 1.4: Band State Defensive Guards

- **File:** `lib/features/bands/active_band_controller.dart`
- **Change:** Wrap `SharedPreferences.getInstance()` in try-catch with fallback to in-memory state
- **Change:** Add null check before iterating `userBands` array
- **Change:** Add explicit empty-array check before `firstOrNull` access
- **File:** `lib/features/shell/no_band_shell.dart`
- **Change:** Add null safety checks for state shape (guard against undefined)
- **Test:** Fresh account signup → verify NoBandShell renders correctly

---

### Phase 2: High-Priority UX Fixes (P1)

**Improves user experience, prevents confusion.**

#### Task 2.1: Email Scanner Link Consumption Error

- **File:** `lib/features/auth/auth_confirm_screen.dart`
- **Change:** Detect "already been consumed" error message
- **Change:** Show dedicated error UI: "This link may have been scanned by email security software. Please request a new magic link."
- **Change:** Add note: "If you use Microsoft Outlook or a corporate email system, this is a known issue."
- **Test:** Simulate consumed link error → verify clear messaging

#### Task 2.2: Profile Completion Skip Decision

- **Decision Point:** Remove skip option OR make first_name/last_name nullable
- **Recommendation:** Remove skip option (force profile completion)
- **File:** `lib/features/auth/auth_gate.dart`
- **Change:** Remove `onSkip` callback, pass `onSkip: null` to ProfileGateScreen
- **File:** `lib/features/profile/my_profile_screen.dart`
- **Change:** Hide skip button when `onSkip == null`
- **Test:** New user signup → verify profile completion is required

#### Task 2.3: Single Source of Truth for Auth State

- **File:** `lib/features/bands/band_repository.dart`
- **Change:** Replace `supabase.auth.currentUser` with `ref.read(authStateProvider).session?.user`
- **File:** All feature files that access `supabase.auth.currentUser`
- **Change:** Audit and replace with provider access
- **File:** `lib/features/auth/auth_gate.dart`
- **Change:** Remove defensive checks that compare provider vs SDK session
- **Test:** Login → verify no "state mismatch" warnings in logs

#### Task 2.4: Network Failure Error Handling

- **File:** `lib/features/auth/login_screen.dart`
- **Change:** Wrap `signInWithOtp()` in try-catch that detects `SocketException` / `TimeoutException`
- **Change:** Show user-friendly error: "No internet connection. Please check your connection and try again."
- **Change:** Add "Retry" button that calls `_sendMagicLink()` again
- **File:** `lib/features/auth/auth_confirm_screen.dart`
- **Change:** Same network error handling for `exchangeCodeForSession()` and `verifyOTP()`
- **File:** `lib/features/auth/auth_gate.dart`
- **Change:** Add retry mechanism for profile check and band loading
- **Test:** Enable airplane mode → attempt login → verify clear error + retry button

#### Task 2.5: Optimize Invite Processing

- **File:** `lib/features/auth/auth_gate.dart`
- **Change:** Before calling `accept-invite` edge function, query `band_invitations` table:

  ```dart
  final pendingInvites = await supabase
    .from('band_invitations')
    .select('id')
    .eq('email', userEmail)
    .eq('status', 'pending')
    .limit(1);

  if (pendingInvites.isEmpty) {
    // Skip edge function call
    return;
  }
  ```

- **Change:** Only call edge function if invites exist
- **Test:** New user with no invites → verify edge function is not called
- **Test:** User with pending invite → verify edge function is called and invite is accepted

---

### Phase 3: Polish & Edge Cases (P2)

**Optional but recommended for production quality.**

#### Task 3.1: Private Browsing Mode Detection

- **File:** `lib/features/bands/active_band_controller.dart`
- **Change:** Add `isPrivateBrowsingMode` boolean to `ActiveBandState`
- **Change:** Set to `true` when SharedPreferences.getInstance() throws
- **File:** `lib/features/shell/app_shell.dart`
- **Change:** Watch `activeBandProvider.isPrivateBrowsingMode`
- **Change:** Show banner when `true`: "You're in private browsing mode. Band selection won't persist."
- **Test:** Open in incognito → verify banner shows

#### Task 3.2: Magic Link Expiry Help Text

- **File:** `lib/features/auth/login_screen.dart`
- **Change:** After "Check your email" message, add:
  ```dart
  Text(
    'Magic links expire after 1 hour for security.',
    style: TextStyle(fontSize: 12, color: Colors.grey),
  )
  ```
- **Test:** Request magic link → verify help text is visible

#### Task 3.3: RLS Validation Script

- **File:** `sql/diagnostics/validate_auth_rls.sql` (create new)
- **Content:** SQL script that:
  1. Creates test user with Supabase Auth
  2. Attempts to insert into `bands` table
  3. Verifies `band_members` row is created
  4. Cleans up test data
  5. Returns success/failure status
- **Documentation:** Add to `BAND_ROADIE_DOCUMENTATION.md` under "Database Maintenance"
- **Test:** Run script manually, verify it passes

#### Task 3.4: Token Refresh Logging

- **File:** `lib/features/auth/auth_state_provider.dart`
- **Change:** Add debug log when `AuthChangeEvent.tokenRefreshed` fires:
  ```dart
  case supabase.AuthChangeEvent.tokenRefreshed:
    debugPrint('🔄 Access token refreshed');
    debugPrint('   New expiry: ${data.session?.expiresAt}');
    state = AppAuthState(session: data.session);
    break;
  ```
- **Test:** Leave app running for >1 hour → verify token refresh is logged

---

## Test Scenarios for Engineer & QA

### Scenario 1: Happy Path — New User Registration

**Steps:**

1. Fresh device (no existing session)
2. Open app → LoginScreen visible
3. Enter email → tap "Send Magic Link"
4. Check email → click magic link
5. Fill out profile (first_name, last_name) → save
6. Verify user lands on NoBandShell (welcome screen)
7. Create a band → verify user lands on AppShell (dashboard)

**Expected Result:** No errors, smooth flow from login → profile → welcome → dashboard.

---

### Scenario 2: Happy Path — Existing User Login

**Steps:**

1. Device with previously logged-in user (session expired)
2. Open app → LoginScreen visible
3. Enter email → tap "Send Magic Link"
4. Check email → click magic link
5. Verify user lands directly on AppShell (dashboard) with their existing bands loaded

**Expected Result:** No errors, no profile gate (already complete), existing bands loaded.

---

### Scenario 3: Edge Case — Logout Before Clicking Link

**Steps:**

1. Open app → LoginScreen
2. Enter email → tap "Send Magic Link"
3. WITHOUT clicking link, tap logout button (if visible) or force-quit app
4. Reopen app → login with different email (or clear storage)
5. NOW click the first magic link

**Expected Result:**  
Clear error message: "This magic link has expired or was opened incorrectly. Please request a new one."  
Button to return to LoginScreen.

---

### Scenario 4: Edge Case — Network Failure During Login

**Steps:**

1. Open app → LoginScreen
2. Enable airplane mode
3. Enter email → tap "Send Magic Link"
4. Observe error message
5. Disable airplane mode
6. Tap "Retry" button

**Expected Result:**  
Step 4: "No internet connection. Please check your connection and try again." with Retry button.  
Step 6: Magic link request succeeds.

---

### Scenario 5: Edge Case — Email Scanner Consumes Link

**Steps:**

1. Request magic link using corporate email (Gmail, Outlook)
2. Wait for link to be scanned (30-60 seconds)
3. Click link after scanner has consumed it

**Expected Result:**  
Clear error message: "This link may have been scanned by email security software. Please request a new magic link."  
Explanation for Outlook/corporate email users.

---

### Scenario 6: Edge Case — Fresh Account with No Bands

**Steps:**

1. Complete registration + profile setup
2. Do NOT create a band
3. Verify NoBandShell renders correctly with "Create Band" and "Join Band" options

**Expected Result:**  
NoBandShell displays welcome message, no crashes or blank screens.

---

### Scenario 7: Edge Case — Private Browsing Mode

**Steps:**

1. Open app in incognito/private mode (web)
2. Login successfully
3. Create or join a band → select as active
4. Close tab
5. Reopen app in new incognito tab
6. Login again

**Expected Result:**  
Step 3: Banner shows "You're in private browsing mode. Band selection won't persist."  
Step 6: No persisted active band (user must select again).

---

### Scenario 8: Regression — iPad Magic Link (Deep Link)

**Steps:**

1. iPad device (iOS 17+)
2. Request magic link
3. Put app in Split View (split screen with another app)
4. Click magic link from Mail app in Split View
5. Verify app receives deep link and completes auth

**Expected Result:**  
App resumes from Split View, deep link is processed, user is logged in.

---

### Scenario 9: Regression — Second Device Login

**Steps:**

1. User is logged in on Device A (iPhone)
2. Request magic link on Device B (iPad)
3. Click link on Device B
4. Verify Device B is logged in
5. Verify Device A session remains valid (or is refreshed)

**Expected Result:**  
Both devices have valid sessions. Push notifications work on both devices.

---

### Scenario 10: Regression — Session Persistence Across App Restarts

**Steps:**

1. Login successfully
2. Force-quit app (swipe up in app switcher)
3. Reopen app
4. Verify user lands on AppShell (not LoginScreen)

**Expected Result:**  
Session persists, user is not asked to log in again.

---

## Supabase Configuration Review

### Current Auth Settings (from codebase)

```dart
// lib/main.dart
await Supabase.initialize(
  url: supabaseUrl,
  anonKey: supabaseAnonKey,
  authOptions: FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce,  // ✅ PKCE enabled
    detectSessionInUri: kIsWeb,        // ✅ Web only
  ),
);
```

### Required Supabase Dashboard Settings

**Authentication → URL Configuration:**

- ✅ Redirect URLs must include:
  - `https://app.bandroadie.com/auth/confirm` (web)
  - `https://app.bandroadie.com/auth/callback` (Android App Link)
  - `bandroadie://login-callback/` (iOS/macOS custom scheme)

**Authentication → Email Templates:**

- ✅ Confirm signup template must use `{{ .ConfirmationURL }}` (dynamic)
- ⚠️ Verify template does NOT hardcode domain (would break PKCE flow)

**Authentication → Email Rate Limits:**

- ⚠️ Check rate limit settings — too restrictive could block legitimate retries
- Recommended: 5 emails per hour per user

**Authentication → Session Settings:**

- ⚠️ Verify JWT expiry is reasonable (default 1 hour for access token, 30 days for refresh token)
- Verify auto-refresh is enabled (should be default)

### Email Template Audit Required

**Action Item:** Log into Supabase Dashboard → Authentication → Email Templates → Review all templates.

Verify:

1. "Confirm signup" template uses `{{ .ConfirmationURL }}`
2. No hardcoded domains like `https://bandroadie.com/...`
3. Email copy is user-friendly and mentions magic link expiry
4. Email subject line is clear: "Your BandRoadie Login Link"

---

## RLS Policy Review Checklist

### Tables Requiring Validation

#### `auth.users` (Supabase managed)

- ✅ Assumed correct — managed by Supabase Auth

#### `users` (public schema)

- **Policy:** User can SELECT own row
- **Test:** `SELECT * FROM users WHERE id = auth.uid()`
- **Expected:** Returns 1 row (current user)
- **Status:** ⚠️ Not explicitly validated in code

#### `band_invitations`

- **Policy:** User can SELECT invitations where email = their email
- **Test:** `SELECT * FROM band_invitations WHERE email = (SELECT email FROM auth.users WHERE id = auth.uid())`
- **Expected:** Returns pending invitations (or empty if none)
- **Status:** ⚠️ Not explicitly validated

#### `band_members`

- **Policy:** User can SELECT own memberships
- **Test:** `SELECT * FROM band_members WHERE user_id = auth.uid()`
- **Expected:** Returns user's band memberships
- **Status:** ✅ Verified in `BandRepository.fetchUserBands()`
- **Policy:** User can INSERT own memberships (when creating band)
- **Test:** New user creates band → verify band_member row is created
- **Status:** ⚠️ Not explicitly validated

#### `bands`

- **Policy:** User can SELECT bands they're a member of (via band_members join)
- **Test:** `SELECT * FROM bands WHERE id IN (SELECT band_id FROM band_members WHERE user_id = auth.uid())`
- **Expected:** Returns user's bands
- **Status:** ✅ Verified in `BandRepository.fetchUserBands()`
- **Policy:** User can INSERT new bands
- **Test:** New user creates band → verify band row is created
- **Status:** ⚠️ Not explicitly validated

#### `device_tokens`

- **Policy:** User can SELECT/INSERT/UPDATE own tokens
- **Status:** ✅ Verified in `20260109_notifications.sql` migration

#### `notification_preferences`

- **Policy:** User can SELECT/INSERT/UPDATE own preferences
- **Status:** ✅ Verified in `20260109_notifications.sql` migration

### Recommended Actions

1. **Create RLS validation script:** `sql/diagnostics/validate_auth_rls.sql`
2. **Run script in test environment** before deploying Phase 1 fixes
3. **Add to deployment checklist:** "Verify RLS policies allow new user band creation"

---

## File Change Summary

### Files to Modify

| File                                             | Change Type  | Phase      |
| ------------------------------------------------ | ------------ | ---------- |
| `lib/features/auth/login_screen.dart`            | Code change  | P0, P1     |
| `lib/features/auth/auth_confirm_screen.dart`     | Code change  | P0, P1     |
| `lib/features/auth/auth_gate.dart`               | Code change  | P0, P1, P2 |
| `lib/features/auth/auth_state_provider.dart`     | Code change  | P0, P2     |
| `lib/app/services/deep_link_service.dart`        | Code change  | P0         |
| `lib/features/bands/active_band_controller.dart` | Code change  | P0, P2     |
| `lib/features/bands/band_repository.dart`        | Code change  | P1         |
| `lib/features/shell/no_band_shell.dart`          | Code change  | P0         |
| `lib/features/shell/app_shell.dart`              | Code change  | P2         |
| `lib/features/profile/my_profile_screen.dart`    | Code change  | P1         |
| `web/index.html`                                 | Code removal | P0         |

### Files to Create

| File                                    | Purpose                               | Phase |
| --------------------------------------- | ------------------------------------- | ----- |
| `sql/diagnostics/validate_auth_rls.sql` | RLS policy validation script          | P2    |
| `test/integration/auth_flow_test.dart`  | End-to-end auth flow integration test | P2    |

---

## Risk Assessment

### High Risk Changes

1. **Removing web fragment auth path** — Could break existing users mid-flow
   - **Mitigation:** Deploy during low-traffic window, monitor error logs
   - **Rollback:** Revert commit, redeploy previous version

2. **Removing periodic session sync timer** — Could cause missed session updates
   - **Mitigation:** Extensive testing on iPad, add telemetry for session drift
   - **Rollback:** Re-add timer as temporary fix, investigate root cause

### Medium Risk Changes

1. **Profile skip removal** — Could frustrate users who want to skip
   - **Mitigation:** Add clear messaging: "Profile required for full access"
   - **Alternative:** Keep skip but add validation + banner warning

2. **Changing auth state source** — Large refactor touching many files
   - **Mitigation:** Audit all direct `supabase.auth` access before modifying
   - **Rollback:** Git revert is straightforward

### Low Risk Changes

1. **Error message improvements** — UI copy only
2. **Network error retry buttons** — Additive feature
3. **RLS validation script** — Diagnostic tool, no code changes

---

## Additional Context

### Known Constraints

1. **Supabase PKCE implementation** — Cannot be customized, must work within Supabase's flow
2. **Platform differences** — Web uses localStorage, native uses platform storage (different failure modes)
3. **Email provider delays** — Magic links can take 1-5 minutes to arrive (out of our control)
4. **Firebase push notification dependency** — Auth flow registers FCM token, depends on Firebase being initialized

### Future Considerations

1. **OAuth providers** — Plan mentions OAuth (Google, Apple) but not currently implemented
   - If added, auth flow complexity increases significantly
   - Recommend separate audit for OAuth implementation

2. **Password reset flow** — Not mentioned in current plan, but users may expect it
   - Magic link is passwordless, so no password to reset
   - Could add "Forgot Email?" flow for users who forget which email they used

3. **Multi-factor authentication (MFA)** — Not currently supported
   - Supabase supports MFA, but requires additional UI flows
   - Recommend separate feature request if security requirements change

4. **Session timeout customization** — Currently uses Supabase defaults
   - Users may want "Remember Me" option for longer sessions
   - Or: "This is a public device" option for shorter sessions

---

## Success Criteria

### Definition of Done

✅ **P0 Fixes Complete:**

- Web auth no longer depends on JavaScript fragment capture
- PKCE errors show clear, actionable messages
- Session sync uses single mechanism (no races)
- Empty band state renders NoBandShell without crashes

✅ **P1 Fixes Complete:**

- Email scanner link consumption shows helpful explanation
- Profile completion is required (or skip is validated)
- All components read from authStateProvider (single source of truth)
- Network errors show friendly messages with retry buttons
- Invite processing only calls edge function when invites exist

✅ **All Test Scenarios Pass:**

- 10 test scenarios documented above all pass without errors

✅ **Documentation Updated:**

- BAND_ROADIE_DOCUMENTATION.md reflects new auth flow
- RLS validation script is documented
- Deployment checklist includes RLS verification step

✅ **Zero Regressions:**

- Existing users can still log in
- iPad deep links still work
- Second device login still works
- Push notifications still register

---

## Deployment Plan

### Pre-Deployment Checklist

- [ ] Run RLS validation script in test environment
- [ ] Verify Supabase Dashboard email templates are correct
- [ ] Test all 10 scenarios in staging environment
- [ ] Review error logs for existing auth failures (baseline)
- [ ] Ensure rollback plan is ready (previous git commit SHA documented)

### Deployment Steps

1. **Deploy P0 fixes first** — Critical path must be stable
2. **Monitor error logs for 24 hours** — Watch for new auth failures
3. **Deploy P1 fixes** — UX improvements can follow
4. **Monitor user feedback** — Check support channels for confusion
5. **Deploy P2 fixes** — Polish and edge cases last

### Post-Deployment Monitoring

- [ ] Auth error rate (should decrease)
- [ ] Average time from magic link request to successful login (should decrease)
- [ ] Number of "Invalid Link" errors (should decrease)
- [ ] Number of "Browser Mismatch" errors (should stay low, but be visible)
- [ ] Support tickets mentioning "can't log in" (should decrease)

---

## Open Questions for Tony

1. **Profile Skip Flow:** Should we remove the skip option entirely, or keep it with validation? Removing is cleaner, but some users may want to defer profile completion.

2. **OAuth Priority:** Feature input mentions "OAuth (if applicable)". Is Google/Apple sign-in on the roadmap? If so, should we design auth flow to accommodate it now?

3. **Magic Link Expiry:** Supabase default is 1 hour. Is this acceptable, or should we request customization via Supabase support?

4. **Private Browsing Support:** Should we block private browsing entirely, or just show warnings? Current approach allows it with limitations.

5. **Email Rate Limiting:** Should we add client-side rate limiting (e.g., max 3 magic links per 10 minutes) to prevent abuse?

6. **Session Duration:** Should we add "Remember Me" / "This is a public device" options, or keep current behavior (Supabase defaults)?

---

**End of ARCHITECT_PLAN.md**
