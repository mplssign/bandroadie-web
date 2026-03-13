# QA Report — Firebase Web Push Notifications

**Feature slug:** firebase-web-push
**Date:** 2026-03-13
**Verdict:** ✅ APPROVED

---

## Changes Reviewed

### 1. `web/firebase-messaging-sw.js`
- Replaced all placeholder values with real Firebase web app config
- `apiKey`, `authDomain`, `projectId`, `storageBucket`, `messagingSenderId`, `appId`, `measurementId` all set correctly
- Background message handler and notification click handler intact — no regressions

### 2. `android/app/src/main/assets/public/firebase-messaging-sw.js`
- Same replacement applied — kept in sync with `web/firebase-messaging-sw.js`
- Required for WebView-based Android web builds

### 3. `lib/main.dart`
- Firebase `if (!kIsWeb)` guard replaced with explicit `if (kIsWeb) / else if (Platform.isIOS || Platform.isAndroid)` branching
- Web branch passes `FirebaseOptions` with all required fields
- iOS/Android branch unchanged — still uses `Firebase.initializeApp()` (reads from native config files)
- macOS still excluded (no FCM on macOS) ✓
- Try/catch wrapper preserved — Firebase init failures are logged, not fatal ✓

### 4. `lib/features/notifications/push_notification_service.dart`
- `registerToken()` now calls `getToken(vapidKey: '...')` on web, `getToken()` on native
- VAPID key matches the key pair generated in Firebase Console → Cloud Messaging → Web Push certificates
- No other logic changed

### 5. `lib/features/auth/auth_gate.dart`
- Both `_registerPushToken()` call sites updated: `if (!kIsWeb && ...)` → `if (kIsWeb || Platform.isIOS || Platform.isAndroid)`
- Web will now go through the full permission request → token registration flow after sign-in ✓
- `clearBadge()` on app resume remains mobile-only (correct — badges don't apply to web) ✓

---

## Risk Assessment

| Area | Risk | Notes |
|------|------|-------|
| iOS/Android push | None | No changes to native init path |
| Web push service worker | Low | Real config replaces placeholders — service worker must be re-served after deploy |
| Firebase web init | Low | `FirebaseOptions` matches registered web app — mismatch would throw at runtime |
| VAPID key | Low | Generated from Firebase Console, tied to this project's web app |
| macOS | None | Still excluded from FCM init |

---

## Deployment Notes

1. Vercel redeploy required — service worker is a static asset, CDN cache must be purged
2. Users must grant browser notification permission — the `requestPermission()` flow is already implemented
3. Background notifications on web require the service worker to be registered — Flutter Web registers it automatically from `web/` directory
4. HTTPS required for service workers (Vercel handles this) ✓
