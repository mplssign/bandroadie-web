# ARCHITECT PLAN — bug/app-subdomain-magic-link-404

> Branch: `bug/app-subdomain-magic-link-404`
> Type: Bug fix
> Date: 2026-03-10

---

## 1. Problem Summary

BandRoadie's Flutter web app currently loads at `https://bandroadie.com/app` while the marketing site loads at `https://bandroadie.com`. The desired final architecture is:

- `https://bandroadie.com` → marketing website
- `https://app.bandroadie.com` → Flutter web app

Two bugs exist:

1. **Subdomain routing:** `https://app.bandroadie.com` currently loads the marketing website instead of the Flutter web app. The `app` subdomain is either not configured in Vercel or is pointed at the marketing project instead of a separate Flutter web project.

2. **Magic link 404:** When a logged-out user requests a magic link, clicking the email link results in a 404 error. The `emailRedirectTo` in the Flutter code is hardcoded to `https://bandroadie.com/app`, and the magic link callback URL pattern (`/auth/confirm`) is resolved relative to `bandroadie.com`. If the user is expected to use `app.bandroadie.com`, but Supabase redirects to `bandroadie.com/auth/confirm`, the route hits the marketing site, which has no `/auth/confirm` handler → 404.

---

## 2. Existing System Analysis

### 2.1 Vercel Deployment

- **Build command (manual):** `flutter build web --release --base-href / && cd build/web && vercel --prod`
- **Build script (CI):** `tools/build_web.sh` — clones Flutter, builds with `--dart-define` env vars, copies `web/vercel.json` and `web/.well-known/` to `build/web/`
- **Vercel project linkage:** `build/web/.vercel/project.json` links to project `bandroadie-staging` (projectId: `prj_nPoARX3pVNg5zYG12jucXJK7Ole6`)
- **No root-level `vercel.json`** — only `web/vercel.json` (copied to `build/web/` during build)
- **No `.github/workflows/`** — no GitHub Actions CI/CD; deployments appear manual via `vercel --prod` from `build/web/`
- **No reference to `app.bandroadie.com`** exists anywhere in the codebase (zero matches)

### 2.2 Vercel Rewrite Configuration (web/vercel.json)

```json
{
  "headers": [
    { "source": "/.well-known/assetlinks.json", "headers": [...] }
  ],
  "rewrites": [
    { "source": "/api/calendar-feed", "destination": "https://nekwjxvgbveheooyorjo.supabase.co/functions/v1/calendar-feed" },
    { "source": "/((?!api/|.well-known/).*)", "destination": "/index.html" }
  ]
}
```

The SPA catch-all rewrite sends all non-API, non-`.well-known` paths to `/index.html`. This is correct for a Flutter SPA but only works if the project serving the domain actually contains the Flutter build output.

### 2.3 Web Entry Point (web/index.html)

- `<base href="/">` — Flutter routes resolve from domain root
- JavaScript fragment capture: Before Flutter loads, an inline script checks `window.location.hash` for `access_token=` and stores it in `sessionStorage` under key `supabase_auth_fragment`
- This is critical for the auth flow — it must be present in whatever `index.html` is served

### 2.4 Flutter Router (lib/main.dart)

Uses `onGenerateRoute` with `usePathUrlStrategy()`:

| Route           | Handler                              | Platform |
| --------------- | ------------------------------------ | -------- |
| `/`             | LandingPage (web), AuthGate (native) | Both     |
| `/app`          | AuthGate                             | Both     |
| `/auth/confirm` | AuthConfirmScreen                    | Both     |
| `/privacy`      | PrivacyPolicyScreen                  | Both     |
| `/invite`       | InviteScreen                         | Both     |
| Unknown routes  | LandingPage (web), AuthGate (native) | Both     |

**Key observation:** The `/` route on web shows the LandingPage (marketing). When the app moves to `app.bandroadie.com`, the root `/` must show AuthGate instead of LandingPage, since `app.bandroadie.com` IS the app.

### 2.5 Auth Redirect URLs (Hardcoded in Flutter)

| Context         | File                     | Line | Redirect URL                                 |
| --------------- | ------------------------ | ---- | -------------------------------------------- |
| Web login       | login_screen.dart        | 297  | `https://bandroadie.com/app`                 |
| Android login   | login_screen.dart        | 299  | `https://bandroadie.com/auth/callback`       |
| iOS/macOS login | login_screen.dart        | 301  | `bandroadie://login-callback/`               |
| Invite flow     | invite_screen.dart       | 191  | `https://bandroadie.com/invite?token=$token` |
| Post-auth nav   | auth_confirm_screen.dart | 52   | `Navigator.pushNamedAndRemoveUntil → '/app'` |

### 2.6 Deep Link Service (lib/app/services/deep_link_service.dart)

- Detects auth callbacks via `_isAuthCallback(Uri uri)`:
  - Custom scheme: `bandroadie://login-callback`
  - Android App Link: `https://bandroadie.com/auth/*`
  - Query/fragment params: `code` or `access_token`
- Hardcoded host check: `uri.host == 'bandroadie.com'`

### 2.7 Other Hardcoded Domain References

| File                                 | Usage                                      |
| ------------------------------------ | ------------------------------------------ |
| `calendar_subscription_service.dart` | `https://bandroadie.com/api/calendar-feed` |
| `screenshots_section.dart`           | `_launchUrl('https://bandroadie.com/app')` |
| `footer_section.dart`                | `https://bandroadie.com/privacy`           |
| `side_drawer.dart`                   | `https://bandroadie.com/privacy`           |
| `deep_link_service.dart`             | `uri.host == 'bandroadie.com'`             |
| `assetlinks.json`                    | Android App Links for `bandroadie.com`     |

### 2.8 Authentication System Analysis

**Email provider:** Magic link (OTP) via Supabase Auth  
**Flow type:** Web = implicit (`AuthFlowType.implicit`, `detectSessionInUri: true`); Native = PKCE  
**Supabase redirect URL allowlist (expected in dashboard):**

- `https://bandroadie.com/auth/confirm`
- `https://bandroadie.com/app`
- `bandroadie://login-callback/`
- `https://bandroadie.com/auth/callback`

**Magic link web flow:**

1. `login_screen.dart` calls `signInWithOtp(emailRedirectTo: 'https://bandroadie.com/app')`
2. Supabase sends email with link targeting `https://bandroadie.com/auth/confirm?token_hash=...`
3. User clicks link → browser loads `https://bandroadie.com/auth/confirm`
4. If SPA rewrite is working, this serves `index.html` → Flutter routes to `AuthConfirmScreen`
5. `AuthConfirmScreen` verifies token, navigates to `/app`

**Where the 404 occurs:** If the Flutter Web app is no longer served at `bandroadie.com` (only at `app.bandroadie.com`), then Step 3 hits the marketing site at `bandroadie.com`, which has no `/auth/confirm` route → 404. Alternatively, if the magic link redirect URL still points to `bandroadie.com/app` but the web app has moved, the redirect also 404s on the marketing site.

### 2.9 Migration Impact Analysis

No database migrations are relevant to this bug. All recent migrations (088 through 20260305100000) address song metadata, notifications, calendar subscriptions, band roles, and rehearsal RLS — none touch auth, URLs, or routing.

---

## 3. Root Cause

The root cause is a **multi-layer domain/routing misconfiguration** with three contributing factors:

### Primary: Vercel Domain Mapping (LIKELY — Deployment Configuration)

`app.bandroadie.com` is either:

- Not configured as a domain in any Vercel project, OR
- Assigned to the marketing site's Vercel project instead of the Flutter web app project

**Evidence:** The `build/web/.vercel/project.json` shows linkage to `bandroadie-staging`, not a production project specifically for `app.bandroadie.com`. There are zero references to `app.bandroadie.com` in the codebase. The manual deploy command `vercel --prod` from `build/web/` deploys to whatever project is linked — currently `bandroadie-staging`.

### Secondary: Hardcoded Redirect URLs (LIKELY — Flutter Code)

All `emailRedirectTo` values and post-auth navigation use `bandroadie.com/app` or `bandroadie.com/auth/confirm`. When the Flutter web app moves to `app.bandroadie.com`, these URLs must change to:

- `https://app.bandroadie.com/auth/confirm` (or just `https://app.bandroadie.com/` depending on flow)

**Evidence:** `login_screen.dart:297` hardcodes `https://bandroadie.com/app`. `invite_screen.dart:191` hardcodes `https://bandroadie.com/invite?token=$token`.

### Tertiary: Supabase Dashboard Configuration (LIKELY — Auth Configuration)

The Supabase Auth dashboard settings (Site URL, Redirect URL allowlist) almost certainly reference `bandroadie.com` paths. These need to include `app.bandroadie.com` variants.

**Evidence:** The MAGIC_LINK_FIX_VERIFICATION.md doc references `https://bandroadie.com/auth/confirm` as the expected magic link URL.

### Failure Surface Classification

| Surface                    | Classification | Evidence                                                                 |
| -------------------------- | -------------- | ------------------------------------------------------------------------ |
| Deployment configuration   | **LIKELY**     | No `app.bandroadie.com` reference in codebase; project linked to staging |
| Flutter auth redirect URLs | **LIKELY**     | Hardcoded to `bandroadie.com/app` and `bandroadie.com/auth/confirm`      |
| Supabase auth config       | **LIKELY**     | Dashboard redirect allowlist expected to reference old paths             |
| SPA rewrite behavior       | **POSSIBLE**   | Rewrites in vercel.json are correct IF served by the right project       |
| Flutter UI routing         | **POSSIBLE**   | `/` route shows LandingPage on web; needs to show AuthGate at subdomain  |
| Domain DNS                 | **POSSIBLE**   | CNAME for `app.bandroadie.com` may be missing or misconfigured           |
| Database / RLS             | **UNLIKELY**   | No auth/URL data in database schema                                      |
| Database triggers          | **UNLIKELY**   | No triggers related to auth URLs                                         |

**Primary failure surface:** Deployment configuration (Vercel domain/project mapping).

---

## 4. Proposed Solution

### Architecture Overview

The solution separates concerns across two Vercel projects and updates all hardcoded URL references:

```
bandroadie.com          → Vercel Project A (marketing site)
app.bandroadie.com      → Vercel Project B (Flutter web app from build/web)
```

### 4.1 Vercel Project/Domain Configuration (Manual — Dashboard)

1. **Create or identify the correct Vercel project** for the Flutter web app (or reuse an existing one). It must serve the contents of `build/web/`.
2. **Add `app.bandroadie.com`** as a production domain on that project.
3. **Verify DNS:** Ensure a CNAME record exists for `app` pointing to `cname.vercel-dns.com` (or the Vercel-assigned value).
4. **Remove `app.bandroadie.com`** from the marketing site project if it's currently there.
5. **Update the `.vercel/project.json`** linkage in `build/web/` to point to the correct production project (run `vercel link` from `build/web/` and select the correct project).

### 4.2 Vercel Rewrite/Redirect Configuration

**On the Flutter web app project (app.bandroadie.com):**

The existing `web/vercel.json` SPA rewrite is correct for Flutter at subdomain root. No change needed to the rewrite rules.

**On the marketing site project (bandroadie.com):**

Add redirects for legacy `/app` and `/auth/confirm` paths so existing bookmarks and in-flight magic links still work during transition:

```json
{
  "redirects": [
    {
      "source": "/app",
      "destination": "https://app.bandroadie.com/",
      "permanent": false
    },
    {
      "source": "/app/:path*",
      "destination": "https://app.bandroadie.com/:path*",
      "permanent": false
    },
    {
      "source": "/auth/:path*",
      "destination": "https://app.bandroadie.com/auth/:path*",
      "permanent": false
    },
    {
      "source": "/invite",
      "destination": "https://app.bandroadie.com/invite",
      "permanent": false
    }
  ]
}
```

Use `permanent: false` (302) initially so the redirects can be changed if needed. Upgrade to `permanent: true` (301) after the migration is verified stable.

### 4.3 Flutter Code Changes

**A. Update web redirect URL in login_screen.dart:**

Change `emailRedirectTo` from `https://bandroadie.com/app` to `https://app.bandroadie.com/auth/confirm`.

Rationale: After Supabase processes the magic link, it redirects the user to the auth confirmation page. This should now point to the subdomain where the Flutter SPA is served — the `/auth/confirm` route will be handled by Flutter's `onGenerateRoute`.

**B. Update web redirect URL in invite_screen.dart:**

Change `https://bandroadie.com/invite?token=$token` to `https://app.bandroadie.com/invite?token=$token`.

**C. Update routing in main.dart:**

When the Flutter web app is served at `app.bandroadie.com`, the `/` route should no longer show the `LandingPage` — it should show `AuthGate` (the actual app). The `LandingPage` is only relevant on `bandroadie.com` (marketing site), which is a separate deployment.

Approach: Remove the web-specific LandingPage routing from the Flutter app entirely, since the marketing site is now a completely separate project. The `/` route on all platforms should route to `AuthGate`.

Alternatively, if the marketing landing page must remain accessible in the Flutter build (e.g., for the marketing site), keep the LandingPage at `/` but add logic to detect the hostname:

- If `window.location.host == 'app.bandroadie.com'` → show AuthGate at `/`
- If `window.location.host == 'bandroadie.com'` → show LandingPage at `/`

This approach is more complex. **The recommended approach is to remove LandingPage routing from the Flutter build** and treat the marketing site as a separate codebase/deployment, since mixing marketing and app in one Flutter build creates exactly this kind of routing problem.

However, if the marketing site at `bandroadie.com` is also served from this same Flutter build (i.e., both domains serve the same `build/web`), then hostname detection is required. The Engineer must verify this during implementation.

**D. Update post-auth navigation in auth_confirm_screen.dart:**

Change `Navigator.pushNamedAndRemoveUntil(context, '/app', ...)` to `Navigator.pushNamedAndRemoveUntil(context, '/', ...)` — since at `app.bandroadie.com`, the root `/` IS the app.

**E. Update deep_link_service.dart host check:**

Add `app.bandroadie.com` as a recognized host:

```
uri.host == 'bandroadie.com' || uri.host == 'app.bandroadie.com'
```

**F. Update landing page link in screenshots_section.dart:**

Change `https://bandroadie.com/app` to `https://app.bandroadie.com/`.

**G. Update calendar feed URL in calendar_subscription_service.dart:**

Change `https://bandroadie.com/api/calendar-feed` to `https://app.bandroadie.com/api/calendar-feed` — since the Vercel rewrite for `/api/calendar-feed` must exist in the Flutter web project.

**H. Update Android App Link host (if Android should also use subdomain):**

If Android deep links should target `app.bandroadie.com` (recommended for consistency), update:

- `android/app/src/main/AndroidManifest.xml`: Add `app.bandroadie.com` host to intent filter
- `web/.well-known/assetlinks.json`: Must also be served at `app.bandroadie.com/.well-known/assetlinks.json`
- `deep_link_service.dart`: Already addressed in (E)
- `login_screen.dart` Android redirect: Change to `https://app.bandroadie.com/auth/callback`

### 4.4 Supabase Dashboard Configuration (Manual)

1. **Site URL:** Update from `https://bandroadie.com` to `https://app.bandroadie.com`
2. **Redirect URLs allowlist — Add:**
   - `https://app.bandroadie.com/auth/confirm`
   - `https://app.bandroadie.com/`
   - `https://app.bandroadie.com/invite`
   - `https://app.bandroadie.com/auth/callback`
3. **Redirect URLs allowlist — Keep (transition period):**
   - `https://bandroadie.com/app`
   - `https://bandroadie.com/auth/confirm`
   - `https://bandroadie.com/auth/callback`
   - `https://bandroadie.com/invite`
   - `bandroadie://login-callback/`
4. **After transition is verified:** Remove old `bandroadie.com/app` and `bandroadie.com/auth/*` entries from allowlist

### 4.5 Rollback Considerations

- All redirects on the marketing site use `permanent: false` so they can be reversed
- Supabase keeps old redirect URLs in the allowlist during transition
- Native apps (iOS/macOS) continue using `bandroadie://login-callback/` — unaffected
- Android App Links can keep `bandroadie.com/auth/*` as a secondary intent filter during transition
- If rollback is needed: revert the Flutter code changes, remove `app.bandroadie.com` from Vercel, and re-deploy to `bandroadie.com/app`

---

## 5. Database Impact

**None.** This bug is entirely in the deployment/configuration/routing layer. No database schema, data, or query changes are required.

---

## 6. RLS / RPC Changes

**None.** No RLS policies or RPC functions are affected by this bug.

---

## 7. Flutter Architecture Changes

### Routing Changes

The `onGenerateRoute` in `main.dart` needs adjustment:

**Before:** `/` on web → `LandingPage`; `/app` → `AuthGate`

**After:** `/` on web → `AuthGate` (at `app.bandroadie.com` the root IS the app); `/app` → `AuthGate` (kept for backward compatibility during transition)

The `LandingPage` route can be removed from the Flutter web build if the marketing site is served separately. If both share the same build, hostname detection is needed (see Section 4.3C).

### Auth Flow Changes

No changes to auth flow logic. Only the redirect URLs change:

- `emailRedirectTo` for web: `bandroadie.com/app` → `app.bandroadie.com/auth/confirm`
- `emailRedirectTo` for invite: `bandroadie.com/invite` → `app.bandroadie.com/invite`
- Post-auth navigation: `/app` → `/`

### State Management Changes

**None.** No provider changes, no controller changes, no state model changes.

---

## 8. Exact Files to Create

**No new Dart files are required.**

One new configuration file may be needed:

| File                                              | Purpose                                                                    |
| ------------------------------------------------- | -------------------------------------------------------------------------- |
| Marketing site's `vercel.json` (NOT in this repo) | Redirect rules from old `/app` and `/auth/*` paths to `app.bandroadie.com` |

If the marketing site is a separate repo, the redirects must be added there. If it shares this repo, the redirect rules apply to the marketing Vercel project's configuration.

---

## 9. Exact Files to Modify

| #   | File                                                       | Change                                                                                                                     |
| --- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| 1   | `lib/features/auth/login_screen.dart`                      | Update web `emailRedirectTo` from `https://bandroadie.com/app` to `https://app.bandroadie.com/auth/confirm`                |
| 2   | `lib/features/auth/invite_screen.dart`                     | Update `redirectUrl` from `https://bandroadie.com/invite?token=$token` to `https://app.bandroadie.com/invite?token=$token` |
| 3   | `lib/features/auth/auth_confirm_screen.dart`               | Update post-auth navigation from `/app` to `/`                                                                             |
| 4   | `lib/main.dart`                                            | Update `/` web route from `LandingPage` to `AuthGate`; keep `/app` route as alias                                          |
| 5   | `lib/app/services/deep_link_service.dart`                  | Add `app.bandroadie.com` to recognized auth callback hosts                                                                 |
| 6   | `lib/features/landing/widgets/screenshots_section.dart`    | Update link from `https://bandroadie.com/app` to `https://app.bandroadie.com/`                                             |
| 7   | `lib/features/calendar/calendar_subscription_service.dart` | Update feed URL from `https://bandroadie.com/api/calendar-feed` to `https://app.bandroadie.com/api/calendar-feed`          |
| 8   | `android/app/src/main/AndroidManifest.xml`                 | Add `app.bandroadie.com` host to App Link intent filter                                                                    |
| 9   | `lib/features/auth/login_screen.dart`                      | Update Android `emailRedirectTo` from `https://bandroadie.com/auth/callback` to `https://app.bandroadie.com/auth/callback` |

---

## 10. Risks / Edge Cases

### HIGH RISK

1. **In-flight magic links:** Users who requested a magic link before the migration will have links pointing to `bandroadie.com/auth/confirm`. The marketing site must have 302 redirects in place BEFORE the Flutter code changes deploy. Otherwise, these links 404.

2. **Supabase dashboard timing:** If Supabase redirect URLs are updated before the code deploys (or vice versa), there will be a window where magic links fail. **Order matters:** update Supabase allowlist first (add new URLs), then deploy code, then clean up old URLs later.

3. **Vercel project linkage:** If `vercel --prod` from `build/web/` deploys to the wrong project, the Flutter app could overwrite the marketing site or deploy to staging. The Engineer must run `vercel link` to explicitly link `build/web/` to the correct production project for `app.bandroadie.com`.

### MEDIUM RISK

4. **Android App Links verification:** If `assetlinks.json` is not served at `app.bandroadie.com/.well-known/assetlinks.json`, Android verified deep links to the new subdomain will fail. The `web/.well-known/assetlinks.json` must be in the `build/web` output (already handled by `tools/build_web.sh`).

5. **Calendar feed proxy:** The Vercel rewrite for `/api/calendar-feed` → Supabase must exist in the `app.bandroadie.com` project's `vercel.json`. It currently does. But if the marketing site also had this rewrite, removing it could break existing calendar subscriptions that use `bandroadie.com/api/calendar-feed`. Marketing site should also redirect `/api/calendar-feed` to `app.bandroadie.com/api/calendar-feed`.

6. **Privacy policy links:** `footer_section.dart` and `side_drawer.dart` link to `https://bandroadie.com/privacy`. If the privacy page is on the marketing site, these links remain correct and need no change. If the `/privacy` route is expected to work within the Flutter app (it does — `PrivacyPolicyScreen` handles it), these links should stay as-is since `bandroadie.com/privacy` is a marketing concern.

### LOW RISK

7. **Support email references:** `hello@bandroadie.com` — no change needed.
8. **Capacitor config:** `capacitor.config.json` references `build/web` — unaffected by domain changes.
9. **Firebase service worker:** Only relevant on the web domain where Flutter is served — moves with the build output.

---

## 11. Verification Plan

### Pre-deployment verification

1. `flutter analyze` — no new issues
2. `flutter build web --release --base-href /` — builds successfully
3. Verify `build/web/` contains `vercel.json` with correct SPA rewrites
4. Verify `build/web/.well-known/assetlinks.json` is present

### Deployment verification (ordered)

1. **Verify Supabase dashboard:**
   - Site URL is `https://app.bandroadie.com`
   - Redirect allowlist includes all new AND old URLs (transition period)

2. **Verify Vercel DNS:**
   - `app.bandroadie.com` CNAME resolves to Vercel
   - SSL certificate is provisioned

3. **Verify Vercel project:**
   - `app.bandroadie.com` is assigned to the Flutter web project
   - `bandroadie.com` remains on the marketing project

4. **Deploy Flutter web app** to `app.bandroadie.com` project

5. **Verify marketing site redirects:**
   - `https://bandroadie.com/app` → 302 to `https://app.bandroadie.com/`
   - `https://bandroadie.com/auth/confirm?test=1` → 302 to `https://app.bandroadie.com/auth/confirm?test=1`

6. **Functional verification:**
   - `https://bandroadie.com` loads marketing site
   - `https://app.bandroadie.com` loads Flutter web app (AuthGate/login)
   - `https://app.bandroadie.com/auth/confirm` loads AuthConfirmScreen (shows missing token message — expected without params)
   - `https://app.bandroadie.com/privacy` loads PrivacyPolicyScreen
   - `https://app.bandroadie.com/invite` loads InviteScreen

7. **Magic link full flow test:**
   - Open `https://app.bandroadie.com` in browser
   - Enter email, request magic link
   - Verify email contains link to `https://app.bandroadie.com/auth/confirm?token_hash=...`
   - Click link
   - Verify successful auth and navigation to app home

8. **Native app verification:**
   - iOS magic link via `bandroadie://login-callback/` still works
   - Android magic link via `https://app.bandroadie.com/auth/callback` works (if updated) or `https://bandroadie.com/auth/callback` still works (via redirect)

---

## 12. Engineer Task Breakdown

### Task 0: Vercel Infrastructure Setup (Manual — Dashboard)

- [ ] Identify or create the Vercel project for the Flutter web app
- [ ] Add `app.bandroadie.com` as a production domain on that project
- [ ] Verify DNS CNAME for `app.bandroadie.com` points to Vercel
- [ ] Wait for SSL certificate provisioning
- [ ] Link `build/web/` to the correct Vercel project (`vercel link`)
- [ ] Add redirects on the marketing site Vercel project (see Section 4.2)

### Task 1: Update Supabase Auth Configuration (Manual — Dashboard)

- [ ] Add `https://app.bandroadie.com/auth/confirm` to redirect allowlist
- [ ] Add `https://app.bandroadie.com/` to redirect allowlist
- [ ] Add `https://app.bandroadie.com/invite` to redirect allowlist
- [ ] Add `https://app.bandroadie.com/auth/callback` to redirect allowlist
- [ ] Update Site URL to `https://app.bandroadie.com`
- [ ] Keep all existing `bandroadie.com` redirect URLs during transition

### Task 2: Update Flutter Auth Redirect URLs

- [ ] `login_screen.dart:297` — web redirect → `https://app.bandroadie.com/auth/confirm`
- [ ] `login_screen.dart:299` — Android redirect → `https://app.bandroadie.com/auth/callback`
- [ ] `invite_screen.dart:191` — invite redirect → `https://app.bandroadie.com/invite?token=$token`

### Task 3: Update Flutter Routing

- [ ] `main.dart` — change `/` web route from `LandingPage` to `AuthGate`
- [ ] `main.dart` — keep `/app` route pointing to `AuthGate` (backward compat)
- [ ] `auth_confirm_screen.dart:52` — change post-auth nav from `/app` to `/`

### Task 4: Update Deep Link & Host References

- [ ] `deep_link_service.dart` — add `app.bandroadie.com` to host check
- [ ] `screenshots_section.dart` — update link to `https://app.bandroadie.com/`
- [ ] `calendar_subscription_service.dart` — update feed URL to `https://app.bandroadie.com/api/calendar-feed`

### Task 5: Update Android Deep Link Config

- [ ] `AndroidManifest.xml` — add `app.bandroadie.com` intent filter host

### Task 6: Build, Deploy, and Verify

- [ ] `flutter analyze` — clean
- [ ] `flutter build web --release --base-href /`
- [ ] Deploy to `app.bandroadie.com` Vercel project
- [ ] Run verification plan (Section 11)

---

## 13. Rollout / Migration Strategy

### Phase A: Prepare (No User Impact)

1. Add `app.bandroadie.com` to Supabase redirect allowlist (keep old URLs)
2. Configure Vercel project and DNS for `app.bandroadie.com`
3. Add 302 redirects on marketing site for `/app`, `/auth/*`, `/invite`
4. Verify redirects work

### Phase B: Deploy (Brief Transition Window)

5. Deploy updated Flutter web build to `app.bandroadie.com`
6. Verify `app.bandroadie.com` loads Flutter app
7. Verify magic link flow works end-to-end
8. Verify marketing site still works at `bandroadie.com`

### Phase C: Harden (Post-Verification)

9. Update Supabase Site URL to `https://app.bandroadie.com` (if not done in Phase A)
10. Monitor for auth failures in logs
11. After 2 weeks stable: upgrade marketing site redirects from 302 to 301
12. After 4 weeks stable: remove old `bandroadie.com/app` and `bandroadie.com/auth/*` URLs from Supabase allowlist

### Rollback Procedure

If issues arise after Phase B:

1. Revert Flutter code (redirect URLs back to `bandroadie.com` paths)
2. Re-deploy to the original project
3. Remove `app.bandroadie.com` Vercel domain config
4. Revert Supabase Site URL to `https://bandroadie.com`
5. Keep Supabase allowlist with both old and new URLs (no harm)

---

## 14. Out of Scope

- Marketing site redesign or separate repo creation
- Removing the `LandingPage` widget from the Flutter codebase (it may still be used for the marketing site deployment)
- Native app store release process
- Custom domain email configuration
- Firebase/push notification changes
- Database schema changes
- RLS policy changes
- Performance optimization
- UI redesign of auth screens
- Migrating the build script (`tools/build_web.sh`) to GitHub Actions
- Removing Capacitor dependencies

---

## 15. Widget Contracts (Public API)

**No new widgets are required.** All changes are to existing configuration, redirect URLs, and routing logic.

---

## 16. Data Flow Architecture

### Auth Flow After Fix (Web — app.bandroadie.com)

```
User opens https://app.bandroadie.com
    │
    ▼
Vercel serves build/web/index.html (SPA rewrite)
    │
    ▼
Flutter loads at / → onGenerateRoute → AuthGate
    │
    ▼
AuthGate checks session → no session → shows LoginScreen
    │
    ▼
User enters email → signInWithOtp(emailRedirectTo: 'https://app.bandroadie.com/auth/confirm')
    │
    ▼
Supabase sends magic link email with URL:
    https://app.bandroadie.com/auth/confirm?token_hash=xxx&type=email
    │
    ▼
User clicks link → browser navigates to https://app.bandroadie.com/auth/confirm
    │
    ▼
Vercel SPA rewrite → serves index.html
    │
    ▼
index.html JS captures any #access_token fragment → sessionStorage
    │
    ▼
Flutter loads → onGenerateRoute('/auth/confirm') → AuthConfirmScreen(tokenHash, code, type)
    │
    ▼
AuthConfirmScreen calls verifyOTP(tokenHash) or exchangeCodeForSession(code)
    │
    ▼
Session established → waits for authStateProvider sync (up to 5s)
    │
    ▼
Navigator.pushNamedAndRemoveUntil('/')  →  AuthGate  →  App Home
```

### State Ownership

- **AuthGate** — owns auth state observation, delegates to `authStateProvider`
- **LoginScreen** — owns email input state, calls Supabase auth
- **AuthConfirmScreen** — owns token verification state, navigates on success
- **authStateProvider** — shared Riverpod provider, single source of auth truth
- **DeepLinkService** — singleton, catches native deep links, notifies provider

### Provider Invalidation

No provider invalidation changes. The `authStateProvider` continues to react to Supabase auth events. The URL changes are transparent to the state layer.

### Session Restoration Flow

Unchanged. `Supabase.initialize()` with `detectSessionInUri: true` on web auto-restores sessions from localStorage. The domain change does not affect localStorage (same-origin policy: `app.bandroadie.com` is a new origin, so users will need to re-authenticate once after the migration).

**Important note for users:** Existing web sessions at `bandroadie.com/app` will NOT carry over to `app.bandroadie.com` because they are different origins. Users will need to log in again at the new URL. This is expected and unavoidable with a domain change.

---

## 17. Exact Change Locations

### lib/features/auth/login_screen.dart

- **Line 297** — `redirectUrl = 'https://bandroadie.com/app'`
  - Change to: `redirectUrl = 'https://app.bandroadie.com/auth/confirm'`
- **Line 299** — `redirectUrl = 'https://bandroadie.com/auth/callback'`
  - Change to: `redirectUrl = 'https://app.bandroadie.com/auth/callback'`

### lib/features/auth/invite_screen.dart

- **Line 191** — `final redirectUrl = 'https://bandroadie.com/invite?token=$token'`
  - Change to: `final redirectUrl = 'https://app.bandroadie.com/invite?token=$token'`

### lib/features/auth/auth_confirm_screen.dart

- **Line 52** — `Navigator.pushNamedAndRemoveUntil(context, '/app', (route) => false)`
  - Change to: `Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false)`

### lib/main.dart

- **~Line 128** — `if (uri.path == '/' && kIsWeb)` → returns `LandingPage`
  - Change to: Return `AuthGate` at `/` on web (same as native behavior)
- **~Line 133** — `if (uri.path == '/app' ...)` → returns `AuthGate`
  - Keep this route for backward compatibility
- **~Line 169** — `onUnknownRoute` returns `LandingPage` on web
  - Change to: Return `AuthGate` on web (unknown routes should show app, not marketing)

### lib/app/services/deep_link_service.dart

- **Line 236-238** — `_isAuthCallback` method, host check
  - `uri.host == 'bandroadie.com'`
  - Change to: `(uri.host == 'bandroadie.com' || uri.host == 'app.bandroadie.com')`

### lib/features/landing/widgets/screenshots_section.dart

- **Line 124** — `onTap: () => _launchUrl('https://bandroadie.com/app')`
  - Change to: `onTap: () => _launchUrl('https://app.bandroadie.com/')`

### lib/features/calendar/calendar_subscription_service.dart

- **Line 34** — `static const String _feedBaseUrl = 'https://bandroadie.com/api/calendar-feed'`
  - Change to: `static const String _feedBaseUrl = 'https://app.bandroadie.com/api/calendar-feed'`

### android/app/src/main/AndroidManifest.xml

- **App Link intent filter** — existing `android:host="bandroadie.com"`
  - Add a second `<data>` element: `android:host="app.bandroadie.com"` with same `android:pathPrefix="/auth"`

### Vercel dashboard changes (not in code)

- Marketing site project: Add redirect rules (Section 4.2)
- Flutter web project: Add `app.bandroadie.com` domain
- DNS: Verify CNAME for `app.bandroadie.com`

### Supabase dashboard changes (not in code)

- Auth → URL Configuration → Site URL: `https://app.bandroadie.com`
- Auth → URL Configuration → Redirect URLs: Add new subdomain URLs (Section 4.4)
