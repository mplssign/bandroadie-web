# ARCHITECT PLAN

## Feature

- Type: bug
- Slug: invite-link-404
- Branch: feature/invite-link-404
- Date: 2026-06-10

## 1. Problem Summary

A band invite email link is sending invitees to a URL that resolves on the marketing site domain, not the app domain. On iOS, tapping the email link opens web first; the marketing site does not serve an invite acceptance route, so invitees hit a 404 before any app or Supabase invite-acceptance logic runs.

## 2. Confirmed Findings

### 2.1 Invite email template URL generation

Source of truth is the edge function:

- File: supabase/functions/send-band-invite/index.ts
- Current behavior: uses `APP_URL = "https://bandroadie.com"`
- Generated link: `${APP_URL}/invite?token=${invitation.token}`

This produces `https://bandroadie.com/invite?token=...`.

### 2.2 Invite acceptance route in app code

There is no Next.js app routing layer in this repo for invites (`BandRoadie/` does not contain `app/` or `pages/` invite routes).

The active web app is Flutter SPA routing:

- File: lib/main.dart
- Route exists: `/invite` -> `InviteScreen(token: token)`

So route handling exists in Flutter, not in Next.js.

### 2.3 Deployed domain behavior (runtime verification)

Observed directly via HTTP checks:

- `https://app.bandroadie.com/invite?token=test123` -> `200` and returns Flutter `index.html` (SPA shell)
- `https://bandroadie.com/invite?token=test123` -> `307` to `https://www.bandroadie.com/invite?...` -> final `404` Webflow marketing page

This confirms the 404 occurs at marketing web routing, before app invite logic.

### 2.4 Vercel alias/deployment state

Vercel aliases show:

- `bandroadie.com` and `www.bandroadie.com` -> marketing deployment
- `app.bandroadie.com` -> app deployment (`web` project)

So the domain split is correct, but invite email generation points to the wrong domain.

### 2.5 Invite token storage and inclusion

Token usage is present in the send flow:

- Invite insert selects `id, token` in client invite creation flows
- `send-band-invite` loads invitation row including `token`
- Link explicitly appends `?token=${invitation.token}`

Given user-provided context, `band_invitations` records exist and queries are successful; this is not a missing-row/data-integrity issue.

### 2.6 Vercel runtime logs

Attempted Vercel CLI log queries for 404 invite paths on both `marketing` and `web` projects returned no matching entries in this environment. This does not invalidate the diagnosis because direct HTTP probing reproduces the domain-specific 404 deterministically.

## 3. Root Cause

Primary root cause: invite email links are generated on the marketing domain (`bandroadie.com`) instead of the app domain (`app.bandroadie.com`).

Failure chain:

1. Admin sends invite.
2. Email link is generated as `https://bandroadie.com/invite?token=...`.
3. iOS opens web URL.
4. `bandroadie.com` routes to marketing site.
5. Marketing site has no invite route handling and serves 404.
6. Invite acceptance flow is never reached.

Root cause confidence: HIGH (directly confirmed in code and live URL behavior).

## 4. Proposed Minimal Fix

### 4.1 Change invite email base domain to app subdomain

Update `send-band-invite` to generate:

- `https://app.bandroadie.com/invite?token=...`

This is the smallest direct fix for current production architecture.

### 4.2 Add defensive redirect on marketing domain

Add a marketing redirect rule:

- `/invite` (and token query) -> `https://app.bandroadie.com/invite`

Reason: protects existing/stale invite links that may still use `bandroadie.com` and improves resilience if any future URL regression occurs.

### 4.3 Keep invite acceptance logic unchanged

Do not alter:

- Supabase invite acceptance logic
- AuthGate pending-invite auto-accept flow
- Invite token semantics

Those are functioning and out of scope for this routing bug.

## 5. Implementation Boundaries

### Files to modify

- `supabase/functions/send-band-invite/index.ts`
  - Replace hardcoded invite base URL from `https://bandroadie.com` to `https://app.bandroadie.com`.
  - Optional hardening: read from env/config with default to app domain, but do not introduce new architecture.

- `marketing/vercel.json`
  - Add redirect for `/invite` (and optionally `/invite/(.*)`) to app domain.

### Files explicitly off-limits

- `lib/main.dart` (invite route already exists)
- `lib/features/auth/invite_screen.dart` (invite acceptance UI already wired)
- `supabase/functions/accept-invite/index.ts` (not implicated in this failure)
- Any migrations/RLS policies (not a database bug)

### Migration policy

- Required: no

### Edge function deploy

- Required: yes (`send-band-invite`)

### New dependencies

- none

### New files

- none

## 6. Database Impact Assessment

- Migrations: unaffected
- RLS: unaffected
- RPC signatures: unaffected
- Triggers: unaffected
- Data model (`band_invitations.token`): unaffected

Database status for this bug: unaffected (routing/domain issue only).

## 7. System Impact Map

- Gigs: unaffected
- Rehearsals: unaffected
- Setlists / Catalog: unaffected
- Members / RBAC: unaffected
- Auth / Session: unaffected
- Routing: affected
- Notifications: unaffected
- Platform iOS: affected (web fallback path)
- Platform Android: potentially affected for email web-open paths
- Platform Web: affected
- Platform macOS: potentially affected for web-open paths

## 8. Regression Risk

Overall regression risk: LOW

Rationale:

- Small, localized changes
- No auth flow contract changes
- No database changes
- No Flutter route changes
- Domain alignment with existing production architecture

## 9. Verification Plan

### Pre-deploy checks

1. Trigger invite send from admin account.
2. Inspect generated email link host; it must be `app.bandroadie.com`.

### Post-deploy checks

1. Open `https://app.bandroadie.com/invite?token=test` -> should return app shell (HTTP 200), not 404.
2. Open `https://bandroadie.com/invite?token=test` -> should redirect to app domain (if redirect rule added).
3. Full iOS flow: tap invite email link -> Invite screen loads -> auth/acceptance flow continues.
4. Confirm Supabase API traffic appears only after app route loads (expected order).

## 10. Rollout Sequence

1. Deploy updated `send-band-invite` edge function.
2. Deploy marketing redirect update.
3. Send fresh test invite and validate iOS tap flow end-to-end.
4. Monitor for residual 404s on `/invite` paths.

## 11. Open Questions

- None required to proceed with fix implementation.
- Optional improvement (separate task): centralize app base URL configuration for all outbound links to avoid future hardcoded-domain drift.
