# ARCHITECT_PLAN.md

## Feature Slug
`android-magic-link-deep-link-fallback`

## Branch
`bug/android-magic-link-deep-link-fallback`

---

## Problem Summary

On Android, tapping a magic link in the Gmail app opens the mobile browser to the web login page instead of launching the BandRoadie app in an authenticated state. The expected behavior (per MAGIC_LINK_FIX_VERIFICATION.md Tests 1, 6, 7, 8) is that the app opens directly to an authenticated state via the `bandroadie://login-callback/` deep link.

The regression was introduced by commit `3f2c0da` (March 10, 2026, "fix: migrate web app to app.bandroadie.com subdomain") which changed the Android `emailRedirectTo` from `https://bandroadie.com/auth/callback` to `https://app.bandroadie.com/auth/callback`. Both are Android App Links (HTTPS scheme) that depend on `android:autoVerify="true"` verification. The bug is specifically reproducible on local debug builds (`flutter run -d R5CNC05HJXT`).

---

## Root Cause

**Confidence: HIGH — confirmed in code via direct observation.**

### Primary cause (HIGH confidence)

`lib/features/auth/login_screen.dart` lines 408–415 select the `emailRedirectTo` URL by platform:

```dart
if (kIsWeb) {
  redirectUrl = 'https://app.bandroadie.com/auth/confirm';
} else if (!kIsWeb && Platform.isAndroid) {
  redirectUrl = 'https://app.bandroadie.com/auth/callback';  // ← Android App Links URL
} else {
  redirectUrl = 'bandroadie://login-callback/';
}
```

Android receives the HTTPS App Links URL `https://app.bandroadie.com/auth/callback`. For Android to open the app from an HTTPS URL, **Android App Links verification must have succeeded at install time**. This requires the app's signing certificate SHA-256 fingerprint to be listed in `https://app.bandroadie.com/.well-known/assetlinks.json`.

**The debug keystore fingerprint is NOT in `assetlinks.json`:**

| Certificate | SHA-256 | In assetlinks.json |
|---|---|---|
| Play Store (upload cert) | `04:7A:EE:2C:88:...` | ✅ yes |
| Release cert (2nd) | `AC:0D:A0:42:75:...` | ✅ yes |
| **Debug keystore** | **`84:6D:0B:D5:6F:9F:36:...`** | **❌ no** |

(Debug fingerprint extracted from `~/.android/debug.keystore` via `keytool`.)

Local dev builds (`flutter run`) are signed with the debug keystore. Android therefore cannot verify App Links for these builds. When verification fails, Android falls through to opening `https://app.bandroadie.com/auth/callback?code=...` in the default browser (or Gmail's in-app Chrome Custom Tab), which loads the Flutter web app. The web router has no `/auth/callback` route, so it falls through to `onUnknownRoute` → shows the web `AuthGate` (login page).

### Secondary factor (MEDIUM confidence)

Even on production/Play Store builds where the release certificate is verified, Gmail's in-app browser renders links in a Chrome Custom Tab (CCT). CCT handling of Android App Links for HTTPS-redirect URLs from third-party origins (Supabase's auth server) is documented to be unreliable: the CCT may not fire the system App Link intent for redirect targets, staying in the browser instead. Custom scheme intents (`bandroadie://`) are handled consistently by CCT because they are non-HTTP, causing CCT to delegate to the system intent resolver.

### DECISION-001 scope check (CONFIRMED — no impact)

The feature input asked to flag whether DECISION-001 (2026-04-14, web PKCE migration) touched native redirect handling. It did not. DECISION-001 was a single-line change in `lib/main.dart` switching `kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce` to `AuthFlowType.pkce` universally. Native platforms were already using PKCE. The `emailRedirectTo` values were not touched. The Android regression originates from `3f2c0da` (March 10, 2026), which predates DECISION-001.

---

## Reference Docs Consulted

| File | Purpose |
|---|---|
| `docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md` | Test scenarios (Tests 1, 6, 7, 8); platform behavior differences; Supabase redirect URL config |
| `docs/reference/general/AI_DECISIONS.md` | DECISION-001 scope verification; categories requiring a logged decision |
| `docs/agents/GUARDRAILS.md` | Platform constraints; dirty-tree rules |
| `docs/agents/OPERATING_MODEL.md` | Pipeline process |

---

## Existing System Analysis

### Full flow (current, broken for Android debug builds)

```
1. User enters email → LoginScreen._sendMagicLink()
2. emailRedirectTo = 'https://app.bandroadie.com/auth/callback'  (Android)
3. supabase.auth.signInWithOtp(email, emailRedirectTo: redirectUrl)
   → Supabase stores code_verifier (PKCE), sends magic link email
   → Email link: https://{project}.supabase.co/auth/v1/verify?token=...
                 &redirect_to=https://app.bandroadie.com/auth/callback
4. User opens Gmail app → taps link
5. Gmail opens link in Chrome Custom Tab (CCT)
6. CCT navigates to Supabase verify URL
7. Supabase verifies token → redirects CCT to:
   https://app.bandroadie.com/auth/callback?code=<pkce_code>
8. Android attempts App Links resolution for app.bandroadie.com/auth/callback
   → App Links verification FAILED (debug cert not in assetlinks.json)
   → Falls back to browser
9. Chrome/CCT loads https://app.bandroadie.com/auth/callback?code=...
10. Flutter web router receives path /auth/callback → no matching route
    → onUnknownRoute → AuthGate → LoginScreen (web)
11. User sees web login page
```

### Expected flow (after fix, matching iOS/macOS)

```
1. User enters email → LoginScreen._sendMagicLink()
2. emailRedirectTo = 'bandroadie://login-callback/'  (all native platforms)
3. supabase.auth.signInWithOtp(email, emailRedirectTo: redirectUrl)
   → Supabase stores code_verifier (PKCE), sends magic link email
4. User opens Gmail app → taps link
5. Gmail opens link in Chrome Custom Tab (CCT)
6. CCT navigates to Supabase verify URL
7. Supabase verifies token → redirects to:
   bandroadie://login-callback/?code=<pkce_code>
8. CCT encounters non-HTTP scheme → fires Android intent for bandroadie://
9. Android intent system matches bandroadie://login-callback intent-filter
   → app opens (cold start or foreground)
10. DeepLinkService.getInitialLink() or uriLinkStream receives URI
11. _isAuthCallback() → true (scheme=bandroadie, host=login-callback)
12. code extracted → exchangeCodeForSession(code)
    → code_verifier retrieved from device storage → PKCE exchange succeeds
13. Session established → _notifyAuthStateChanged()
14. AuthGate sees authenticated state → app opens to home screen
```

### Why the custom scheme works from Gmail CCT

Android Chrome Custom Tabs handle non-HTTP/HTTPS scheme redirects by passing them to the Android intent system. The `bandroadie://` scheme has a matching intent-filter in `AndroidManifest.xml` (lines 49–56, no `autoVerify`). No certificate verification is required. This is the same mechanism iOS uses with Universal Links / custom scheme fallback, and it is the mechanism iOS already successfully uses.

### Why the HTTPS App Links approach fails for debug builds

`android:autoVerify="true"` causes Android to contact `https://app.bandroadie.com/.well-known/assetlinks.json` at install time. The file content (`web/.well-known/assetlinks.json`) lists only the two release certificate fingerprints. The debug keystore certificate (`84:6D:0B:D5:...`) is absent. Android marks the domain as unverified for this install, and all HTTPS links to `app.bandroadie.com` fall through to the browser for the lifetime of that install.

---

## Proposed Solution

**Change Android's `emailRedirectTo` to match iOS/macOS: `bandroadie://login-callback/`.**

This is a minimal change to a single file. It eliminates the dependency on App Links certificate verification for the auth flow and removes the CCT/App Links interaction as a failure mode.

The `bandroadie://login-callback/` intent-filter already exists in `AndroidManifest.xml` and does not require `autoVerify`. The `DeepLinkService` already handles `bandroadie://login-callback/?code=...` URIs correctly (PKCE flow: extracts `code`, calls `exchangeCodeForSession(code)`). The custom scheme URL is already present in Supabase's redirect URL allowlist.

**The Android-specific `else if` branch is eliminated entirely** since Android's redirect URL becomes identical to iOS/macOS. The `Platform` import in `login_screen.dart` becomes unused and must be removed from the `dart:io` show list to satisfy the analyzer.

### Required changes in `lib/features/auth/login_screen.dart`

**Change 1 — Import (line 28):**

Before:
```dart
import 'dart:io' show Platform, SocketException;
```

After:
```dart
import 'dart:io' show SocketException;
```

**Change 2 — Redirect URL logic (~lines 404–415):**

Before:
```dart
// Web: Redirect to /auth/confirm on the app subdomain
// Android: Use verified App Link (https://app.bandroadie.com/auth/callback)
// iOS/macOS: Use custom scheme (bandroadie://login-callback/)
final String redirectUrl;
if (kIsWeb) {
  redirectUrl = 'https://app.bandroadie.com/auth/confirm';
} else if (!kIsWeb && Platform.isAndroid) {
  redirectUrl = 'https://app.bandroadie.com/auth/callback';
} else {
  redirectUrl = 'bandroadie://login-callback/';
}
```

After:
```dart
// Web: Redirect to /auth/confirm on the app subdomain
// Native (Android, iOS, macOS): Use custom scheme (bandroadie://login-callback/)
final String redirectUrl;
if (kIsWeb) {
  redirectUrl = 'https://app.bandroadie.com/auth/confirm';
} else {
  redirectUrl = 'bandroadie://login-callback/';
}
```

---

## Database Impact

**Not applicable.** This change does not touch Supabase schema, RLS policies, migrations, or RPCs.

---

## Flutter Architecture Changes

| Area | Change |
|---|---|
| `login_screen.dart` — `_sendMagicLink()` | Android-specific redirect URL branch removed; Android now uses `bandroadie://login-callback/` |
| `login_screen.dart` — `dart:io` import | `Platform` removed from show list (no longer referenced) |
| `DeepLinkService` | No change — already handles `bandroadie://login-callback/?code=...` correctly |
| `AndroidManifest.xml` | No change — `bandroadie://login-callback` intent-filter already present at lines 49–56 |
| `main.dart` | No change — init order and PKCE config unchanged |
| `auth_confirm_screen.dart` | No change — race-condition wait logic must not be removed (MAGIC_LINK_FIX_VERIFICATION.md) |

---

## Files to Create

None.

---

## Files to Modify

| File | What changes |
|---|---|
| `lib/features/auth/login_screen.dart` | (1) Remove `Platform` from `dart:io` import. (2) Remove Android-specific `else if` branch. (3) Update comment. |

---

## Files Off-Limits

| File | Reason |
|---|---|
| `lib/main.dart` | Initialization order and PKCE auth flow config must not change (GUARDRAILS §1; DECISION-001 active) |
| `lib/features/auth/auth_confirm_screen.dart` | Race-condition wait logic (`maxAttempts = 10`, 500ms polling) must not be removed (MAGIC_LINK_FIX_VERIFICATION.md §Root Causes Identified & Fixed) |
| `lib/app/services/deep_link_service.dart` | Already correct; HTTPS App Links handling can remain for future use (removing it is scope creep) |
| `android/app/src/main/AndroidManifest.xml` | Both intent-filters are correct and can remain; no change needed |
| `web/.well-known/assetlinks.json` | Adding debug cert is not required and is a separate concern (security teams may not want debug certs in production assetlinks) |
| `docs/reference/general/AI_DECISIONS.md` | No new decision required (see AI_DECISIONS.md assessment below) |
| All other files | Not required for this fix |

---

## AI_DECISIONS.md Assessment

**No new entry required.**

The "Categories Requiring a Logged Decision" in AI_DECISIONS.md are:
- Changes to app initialization order — **not applicable**
- New state management pattern or provider type — **not applicable**
- New config loading mechanism — **not applicable**
- Changes to Supabase auth flow type (PKCE vs. implicit) — **not applicable** (PKCE unchanged)
- New SECURITY DEFINER functions — **not applicable**
- Approved exception to a GUARDRAILS.md rule — **not applicable**
- New external services or dependencies — **not applicable**
- Changes to RLS policy architecture — **not applicable**

This fix reverts a platform-specific redirect URL to an already-used custom scheme pattern. It introduces no new architecture. No entry is required.

---

## System Impact Map

| System | Impact |
|---|---|
| Auth / Session | **affected** — bug fixed; Android PKCE auth now completes correctly |
| Platform — Android | **affected** — custom scheme replaces HTTPS App Links for magic link redirect |
| Platform — iOS | **unaffected** — already uses `bandroadie://login-callback/`; no change |
| Platform — macOS | **unaffected** — already uses `bandroadie://login-callback/`; no change |
| Platform — Web | **unaffected** — web path unchanged |
| Gigs | **unaffected** |
| Rehearsals | **unaffected** |
| Setlists / Catalog | **unaffected** |
| Members / RBAC | **unaffected** |
| Routing | **unaffected** |
| Notifications | **unaffected** |

---

## Regression Risk

**LOW.**

- One file changed; two edits (import + redirect logic)
- Android falls to the same code path iOS/macOS already use and have verified working
- PKCE auth flow type unchanged; `DeepLinkService` already handles the target URI
- No database, no RLS, no initialization order, no dependencies touched
- Removing an unused `Platform` import cannot regress anything

---

## Engineer Task Breakdown

Execute in order:

| # | Task | File | Description |
|---|---|---|---|
| 1 | Update `dart:io` import | `lib/features/auth/login_screen.dart` | Remove `Platform` from the show list; retain `SocketException` |
| 2 | Remove Android-specific redirect branch | `lib/features/auth/login_screen.dart` | Delete the `else if (!kIsWeb && Platform.isAndroid)` block; update the comment |
| 3 | Verify 0 analyzer errors | (command) | `flutter analyze lib/features/auth/login_screen.dart` — must report 0 errors, 0 warnings |

No migration, no edge function deploy, no new dependencies.

---

## Verification Plan

### Tier 1 — Static verification (before device testing)

**Must pass before any on-device test:**

1. `flutter analyze lib/features/auth/login_screen.dart` reports **0 errors, 0 warnings**.
2. Confirm `Platform` does not appear anywhere in `login_screen.dart` (no residual reference).
3. Confirm `redirectUrl = 'bandroadie://login-callback/'` is the value produced for all `!kIsWeb` branches (inspect the `else` clause).
4. Confirm `'https://app.bandroadie.com/auth/callback'` no longer appears anywhere in `login_screen.dart`.
5. Confirm `auth_confirm_screen.dart` is unchanged — specifically that the `maxAttempts = 10` wait loop (lines 295–305) is intact.

### Tier 2 — On-device manual verification (physical Android, debug build)

**Test device:** physical Android, serial `R5CNC05HJXT` (or equivalent).
**Build command:** `flutter run -d R5CNC05HJXT` (or `./run.sh android`).

These tests map directly to `docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md`:

| Test | Ref | Steps | Expected |
|---|---|---|---|
| **T2-1: Cold start from Gmail (primary bug)** | Test 7 + Test 6 | (1) Fully quit app. (2) Request magic link. (3) Open Gmail app on same device. (4) Tap the link. | BandRoadie app opens directly to home screen. No browser. Logs: `[DeepLinkService] Initial link: bandroadie://login-callback/?code=...`, `[DeepLinkService] PKCE exchange successful`. |
| **T2-2: Background resume from Gmail** | Test 8 | (1) App open and backgrounded. (2) Request magic link. (3) Tap link in Gmail. | App resumes and transitions to home screen. Logs: `[DeepLinkService] Received link while running: bandroadie://login-callback/...`. |
| **T2-3: Standard cold start (system browser)** | Test 7 | (1) Fully quit app. (2) Request magic link. (3) Open link from default email/browser. | App opens to home screen. |
| **T2-4: In-app browser explicitly** | Test 6 | Open link from inside Gmail as in T2-1. | App opens (not browser). This is the regression test for the reported bug. |
| **T2-5: iOS regression (no change expected)** | Test 1 | Request magic link → tap in iOS Mail app. | App opens to home screen (unchanged). This confirms iOS was not regressed. |

**Failure criteria for Tier 2:**
- Any scenario where a browser opens instead of the app → QA FAIL
- Any scenario where the app shows a login screen after tapping the link → QA FAIL
- Any `[DeepLinkService]` log showing an HTTPS URL for the initial link → QA FAIL

---

## QA Regression Areas

1. **Android magic link (primary):** Tests T2-1 through T2-4 above.
2. **iOS magic link:** Test T2-5; confirm iOS continues using `bandroadie://login-callback/` (should show no change in behavior).
3. **Web magic link:** Confirm web still uses `https://app.bandroadie.com/auth/confirm` (DECISION-001 path); log should show `🔄 Using PKCE flow` and `✅ PKCE exchange successful`.
4. **LoginScreen UI:** Verify no visual regression — login screen renders correctly, domain pills work, cooldown timer works. The removed `Platform` import has no UI impact.
5. **Analyzer:** `flutter analyze` must pass with 0 errors.

---

## Rollout / Migration Strategy

Not applicable. This is a client-side fix with no server-side deployment required. A standard `flutter run` debug build on the physical device is sufficient for verification.

---

## Out of Scope

- **Web PKCE flow** — already working; DECISION-001 is active; do not touch
- **iOS behavior** — not reported as broken; no change planned
- **`assetlinks.json` debug cert** — adding the debug keystore fingerprint to `assetlinks.json` is a separate concern outside this fix and may conflict with production security policy
- **Removing HTTPS App Links from `AndroidManifest.xml`** — the intent-filter is harmless and may be useful for other HTTPS link handling; scope creep to remove it
- **Supabase dashboard** — `bandroadie://login-callback/` is already in the redirect URL allowlist per MAGIC_LINK_FIX_VERIFICATION.md; no dashboard change required
- **`https://app.bandroadie.com/auth/callback` Supabase allowlist cleanup** — safe to leave in place; removing it is a separate chore
