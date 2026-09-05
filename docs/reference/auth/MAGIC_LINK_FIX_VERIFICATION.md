# Magic Link Authentication Fix - Verification Checklist

> **Note (April 2026):** Web auth was subsequently migrated from implicit flow to PKCE flow on all platforms (see `docs/reference/general/AI_DECISIONS.md` DECISION-001). The checklist below describes the January 2026 fix. The PKCE migration means web now uses `token_hash` not `code`, and the `code_verifier` is stored in `localStorage` to protect against email scanner pre-fetch. The redirect URL is `https://app.bandroadie.com/auth/confirm`.

---

## 🎯 Root Causes Identified & Fixed

### 1. **Race Condition: Auth State Not Synced**
**Problem:** When the magic link redirected to AuthGate, the auth state provider hadn't received the `signedIn` event yet, causing AuthGate to see no session and redirect to login.

**Fix:** AuthConfirmScreen now waits for the auth state provider to sync (up to 5 seconds, checking every 500ms) before navigating to AuthGate.

```dart
// Wait for the auth state provider to recognize the session
int attempts = 0;
const maxAttempts = 10; // 5 seconds max
while (attempts < maxAttempts) {
  final authState = ref.read(authStateProvider);
  if (authState.isAuthenticated) {
    break;
  }
  await Future.delayed(const Duration(milliseconds: 500));
  attempts++;
}
```

### 2. **Poor Error Classification**
**Problem:** All auth errors were treated the same, making it hard to distinguish expired links from browser mismatch.

**Fix:** Added specific error detection and user-friendly messaging:
- `expired_link` - Token expired or invalid
- `reused_link` - Link already consumed
- `browser_mismatch` - PKCE code verifier mismatch
- `missing_token` - No token in URL

### 3. **Insufficient Logging**
**Problem:** Hard to debug auth failures without visibility into the flow.

**Fix:** Added comprehensive emoji-based logging:
- 🔐 Auth state changes
- 🔔 Auth events (signedIn, tokenRefreshed, etc.)
- ✅ Success indicators
- ❌ Error markers
- ⏳ Timing information

### 4. **Navigation Stack Issues**
**Problem:** Using `pushReplacement` left routes in the stack that could cause back-button confusion.

**Fix:** Using `pushAndRemoveUntil` with `(route) => false` to completely clear the navigation stack.

---

## ✅ Production Verification Checklist

### **Test 1: Standard Magic Link (iOS Safari)**
1. ✓ Open Safari on iPhone
2. ✓ Go to https://bandroadie.com
3. ✓ Enter email and request magic link
4. ✓ Open Mail app, tap the magic link
5. ✓ **Expected:** App loads directly to main screen (no login screen flash)
6. ✓ **Check console:** Should see "🚀 Navigating to AuthGate" after auth state sync

### **Test 2: PKCE Flow (Desktop Chrome)**
1. ✓ Open Chrome on desktop
2. ✓ Go to https://bandroadie.com
3. ✓ Request magic link
4. ✓ Click link in webmail (Gmail, Outlook, etc.)
5. ✓ **Expected:** Immediate login, no errors
6. ✓ **Check console:** Should see "🔄 Using PKCE flow" and "✅ PKCE exchange successful"

### **Test 3: Expired Link**
1. ✓ Request magic link
2. ✓ Wait 10+ minutes (or use old link)
3. ✓ Click expired link
4. ✓ **Expected:** Error screen with timer icon and message "Magic Link Expired"
5. ✓ **Expected:** "Request New Magic Link" button visible
6. ✓ **Check console:** Should see "❌ AUTH EXCEPTION" with "Classification: Expired or reused link"

### **Test 4: Reused Link**
1. ✓ Request and click magic link successfully (log in)
2. ✓ Log out
3. ✓ Try to click the same magic link again
4. ✓ **Expected:** Error screen "This magic link has already been used"
5. ✓ **Check console:** Should see "Classification: Link already used"

### **Test 5: Browser Mismatch (PKCE)**
1. ✓ Request magic link in Safari
2. ✓ Copy the link URL
3. ✓ Paste and open in Chrome (different browser)
4. ✓ **Expected:** Orange warning icon and "Login Link Opened in Wrong Browser"
5. ✓ **Expected:** Help text about opening in the same browser
6. ✓ **Check console:** Should see "Classification: Browser mismatch (PKCE)"

### **Test 6: In-App Browser (Gmail App)**
1. ✓ Open Gmail app on iPhone
2. ✓ Request magic link
3. ✓ Tap link in Gmail app (opens in-app browser)
4. ✓ **Expected:** Should work OR show helpful error with "Open in Safari" guidance
5. ✓ **Note:** Some in-app browsers block cookies - check for specific error messaging

### **Test 7: Cold Start via Link**
1. ✓ Fully quit app (swipe up from app switcher)
2. ✓ Request magic link
3. ✓ Tap link to launch app
4. ✓ **Expected:** App opens directly to logged-in state
5. ✓ **Check native logs:** Should see deep link handling and auth state updates

### **Test 8: Background App Resume**
1. ✓ Have app open and backgrounded
2. ✓ Request magic link
3. ✓ Tap link while app is in background
4. ✓ **Expected:** App resumes and logs in without showing login screen
5. ✓ **Check logs:** Should see lifecycle events and auth state refresh

### **Test 9: Network Failure**
1. ✓ Enable airplane mode
2. ✓ Try to request magic link
3. ✓ **Expected:** Clear error message about network connectivity
4. ✓ Re-enable network and retry
5. ✓ **Expected:** Recovery and successful send

### **Test 10: Redirect URL Validation**
1. ✓ Check browser console during login
2. ✓ **Expected:** Magic link URL contains `https://app.bandroadie.com/auth/confirm`
3. ✓ **Expected:** URL has `?token_hash=` parameter (PKCE flow — as of April 2026)
4. ✓ **Verify:** Redirect URL matches Supabase dashboard configuration

---

## 🔍 Debugging Commands

### **View Auth Flow in Real-Time (Safari Web Inspector)**
1. Connect iPhone to Mac via cable
2. iPhone: Settings → Safari → Advanced → Enable "Web Inspector"
3. Mac: Safari → Develop → [Your iPhone] → bandroadie.com
4. Watch Console tab during magic link flow

### **Key Log Patterns to Look For**

#### ✅ **Successful Flow:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔐 AUTH CONFIRM: Starting magic link verification
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📧 Token hash: abc123...
🔄 Using PKCE flow - exchanging code for session...
✅ PKCE exchange successful
   User: user@example.com
   Session expires: 2026-01-25...
✅ Session verified successfully
   User ID: 550e8400-...
   Email: user@example.com
⏳ Waiting for auth state provider to sync...
   Attempt 1/10...
✅ Auth state provider synced (attempt 2)
🚀 Navigating to AuthGate
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

#### ❌ **Failed Flow (Expired Link):**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔐 AUTH CONFIRM: Starting magic link verification
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ AUTH EXCEPTION: Invalid grant: expired token
   Status code: 400
   Classification: Expired or reused link
```

#### 🔔 **Auth State Provider Events:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔔 AUTH EVENT: signedIn
   Session: ✅ Present
   User: user@example.com
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ↳ Updating state: SIGNED_IN
```

---

## 🚨 Common Issues & Solutions

### **Issue: Login screen flashes briefly then shows main app**
**Cause:** AuthGate renders before auth state updates
**Solution:** Already fixed - we wait for auth state sync
**Verify:** Check logs show "Auth state provider synced" before navigation

### **Issue: "Browser mismatch" on same browser**
**Cause:** Cookies cleared between request and click
**Solution:** User education - don't clear cookies mid-auth
**Verify:** Check if browser settings or extensions block cookies

### **Issue: Link works on desktop but not mobile**
**Cause:** Mobile browser restrictions (private mode, content blockers)
**Solution:** Detect and show guidance
**Verify:** Test in regular Safari vs. Private browsing

### **Issue: Link opens app but shows login screen**
**Cause:** Deep link not properly handled or session not persisting
**Solution:** Check DeepLinkService initialization and PKCE flow
**Verify:** Native logs should show deep link captured and processed

---

## 📊 Success Metrics

After deploying, monitor these metrics for 7 days:

- **Login Success Rate:** Should be >95% (was likely <80% before)
- **"Request New Link" Clicks:** Should decrease significantly
- **Session Duration:** Should increase (users staying logged in)
- **Error Type Distribution:**
  - `expired_link`: <5% (unavoidable, users taking too long)
  - `browser_mismatch`: <2% (edge case)
  - `reused_link`: <1% (users clicking old links)
  - Other errors: <1% (should be near zero)

---

## BandRoadie-Specific Notes

### **Platform Behavior Differences**

#### **Web (Flutter Web)**
- Uses `detectSessionInUri: true` - Supabase auto-detects `?code=` or `?token_hash=`
- PKCE flow preferred for security
- Session stored in `localStorage`
- Works in: Safari, Chrome, Firefox, Edge

#### **Native (iOS/Android)**
- Uses `detectSessionInUri: false` - manual deep link handling
- Deep links: `bandroadie://login-callback/`
- Session stored in secure device storage
- Handles background/foreground transitions

### **Supabase Dashboard Configuration**

Verify these settings match:

1. **Authentication → URL Configuration**
   - Redirect URLs: `https://app.bandroadie.com/auth/confirm` (web — matches `emailRedirectTo` in code)
   - Redirect URLs: `bandroadie://login-callback/` (native apps)

2. **Authentication → Email Templates**
   - Magic Link: Should use `{{ .ConfirmationURL }}`
   - Redirect parameter: Should append correctly

3. **Authentication → Auth Providers**
   - Email: Enabled
   - Email OTP: Enabled
   - PKCE: Enabled (default)

---

## ✨ Final Checklist

Before marking as COMPLETE:

- [ ] All 10 test scenarios pass
- [ ] Console logging shows correct flow (no errors in happy path)
- [ ] Error messages are user-friendly (no technical jargon)
- [ ] "Open in Safari" guidance visible for in-app browsers
- [ ] Navigation stack clears properly (no back button issues)
- [ ] Session persists across app restarts
- [ ] Production deployed and smoke tested
- [ ] Monitoring set up for success metrics

---

## 🎯 What Changed

### Files Modified:
1. **`lib/features/auth/auth_confirm_screen.dart`**
   - Added Riverpod ConsumerWidget for auth state access
   - Added wait loop for auth state provider sync (fixes race condition)
   - Enhanced error classification (expired, reused, browser mismatch)
   - Added comprehensive emoji-based logging
   - Improved error UI with specific guidance per error type

2. **`lib/features/auth/auth_state_provider.dart`**
   - Enhanced logging with visual separators (━━━)
   - Added detailed event logging for all auth state changes
   - Added timestamp and user email to session logs

### Key Behavioral Changes:
- ✅ No more login loops
- ✅ Wait for auth state before navigation
- ✅ Clear error messages for common failures
- ✅ Guidance for browser mismatch scenarios
- ✅ Better visibility into auth flow via logging

---

**Last Updated:** January 24, 2026
**Fix Version:** v1.0.0
**Status:** Ready for Production Verification
