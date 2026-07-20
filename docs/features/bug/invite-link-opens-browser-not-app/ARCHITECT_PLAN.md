# ARCHITECT PLAN

## 1. Feature Slug

`bug/invite-link-opens-browser-not-app`

## 2. Problem Summary

Invite emails use an HTTPS URL (`https://app.bandroadie.com/invite?token=...`). On mobile devices with the native app installed, tapping the link opens the browser instead of opening BandRoadie.

Expected behavior: invite link opens the installed native app directly to invite handling.

Observed behavior: link opens web.

## 3. Root Cause

Native-app deep-linking for invite URLs was not fully implemented end-to-end.

Confirmed findings:

- Invite links are generated as HTTPS app-domain URLs in `supabase/functions/send-band-invite/index.ts`.
- Android App Links intent filters in `android/app/src/main/AndroidManifest.xml` are scoped to `/auth` only, not `/invite`.
- iOS app entitlements in `ios/Runner/RunnerDebug.entitlements` and `ios/Runner/RunnerRelease.entitlements` do not include Associated Domains (`applinks:...`).
- No `apple-app-site-association` file exists in hosted web roots.
- Flutter deep-link handling in `lib/app/services/deep_link_service.dart` only processes auth callbacks (`/auth` and `bandroadie://login-callback`) and ignores invite URLs.

Failure mode classification:

- Primary: platform config gap (Universal Links/App Links scope does not cover invite flow on iOS and partially on Android).
- Secondary: app routing gap for invite links at runtime (DeepLinkService does not route invite URIs).

Confidence: HIGH (direct code/config observation).

Open question resolution:

- This is a missing-feature gap, not a true regression of previously working invite native deep-link behavior. Evidence shows auth deep linking exists, but invite deep linking was never implemented end-to-end.

## 4. Reference Docs Consulted

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/agents/PROJECT_CONTEXT.md`
- `docs/features/invite-link-404/ARCHITECT_PLAN.md`
- `docs/features/invite-link-404/ENGINEER_REPORT.md`
- `docs/features/invite-link-404/QA_REPORT.md`

## 5. Existing System Analysis

Current invite flow on `main`:

1. `send-band-invite` sends `https://app.bandroadie.com/invite?token=...`.
2. If opened in browser/web, Flutter route `/invite` in `lib/main.dart` renders `InviteScreen`.
3. Native auth deep links are handled by `DeepLinkService`, but only auth callbacks are accepted.

Current platform behavior:

- Android: verified links are configured, but only for `/auth` path prefixes.
- iOS: no Associated Domains entitlement and no hosted AASA file, so Universal Links for app domain cannot work.

Result:

- Browser-open behavior is expected with current configuration for invite links.

## 6. Proposed Solution

Implement invite deep-linking as explicit native capability, minimal diff:

1. Expand Android App Links scope to include invite path.
2. Enable iOS Universal Links for app domain via entitlements.
3. Host `apple-app-site-association` for app domain (`/.well-known/apple-app-site-association`) with invite/auth paths.
4. Update deep-link runtime handling to process invite URLs and navigate to `/invite?token=...` when app is launched/resumed from such links.

What must not change:

- Invite token semantics.
- Existing auth callback behavior.
- Initialization order in `lib/main.dart`.

## 7. Database Impact

Database: not applicable.

- Migrations: unaffected
- RLS: unaffected
- RPC signatures: unaffected
- Triggers: unaffected

## 8. Flutter Architecture Changes

- `DeepLinkService` gains invite-link branch alongside auth branch; no new provider/repository architecture.
- Routing stays in existing `onGenerateRoute` in `lib/main.dart`.
- No state-model or repository redesign.

## 9. Files to Create

- `web/.well-known/apple-app-site-association`
  - Required for iOS Universal Links trust handshake.

## 10. Files to Modify

- `android/app/src/main/AndroidManifest.xml`
  - Extend autoVerify HTTPS intent filter to include `/invite` path (and keep existing `/auth`).
- `ios/Runner/RunnerDebug.entitlements`
  - Add `com.apple.developer.associated-domains` with `applinks:app.bandroadie.com`.
- `ios/Runner/RunnerRelease.entitlements`
  - Add `com.apple.developer.associated-domains` with `applinks:app.bandroadie.com`.
- `web/vercel.json`
  - Add explicit header rule for AASA content type and preserve `.well-known` routing behavior.
- `lib/app/services/deep_link_service.dart`
  - Handle invite URI (`https://app.bandroadie.com/invite?token=...`) and navigate into invite screen path.

## 11. Files Off-Limits

- `lib/main.dart`
  - Initialization order and router ownership must remain unchanged.
- `supabase/functions/send-band-invite/index.ts`
  - Invite URL already points to app domain; not part of this bug fix.
- `marketing/vercel.json`
  - Existing redirect behavior is separate and already in place.

## 12. System Impact Map

| System                                 | Impact                                                                                  |
| -------------------------------------- | --------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                              |
| Rehearsals                             | unaffected                                                                              |
| Setlists / Catalog                     | unaffected                                                                              |
| Members / RBAC                         | unaffected                                                                              |
| Auth / Session                         | affected (shared deep-link handler path)                                                |
| Routing                                | affected                                                                                |
| Notifications                          | unaffected                                                                              |
| Platform (iOS / Android / Web / macOS) | iOS affected, Android affected, Web minimally affected (AASA hosting), macOS unaffected |

## 13. Regression Risk

MEDIUM.

Rationale:

- Touches platform entry/link behavior (iOS entitlements + Android manifest + shared deep-link service).
- No database changes.
- Shared auth deep-link code path must remain stable.

## 14. Engineer Task Breakdown

1. Add invite path support to Android verified app-links intent filter.
2. Add iOS Associated Domains entitlement in both debug and release entitlements.
3. Add and validate AASA file under `web/.well-known/` with correct JSON structure and allowed paths.
4. Update `web/vercel.json` headers so AASA is served with correct content type and not rewritten.
5. Extend `DeepLinkService` to recognize invite URIs and forward to app routing for `InviteScreen` without breaking auth callbacks.
6. Verify no init-order or unrelated routing changes were introduced.

## 15. Verification Plan

### Tier 1 - Pre-deployment (must pass before any deploy)

- PRE-DEPLOY TEST 1: Static config validation
  - Confirm Android manifest includes HTTPS app-link for `app.bandroadie.com` + `/invite`.
- PRE-DEPLOY TEST 2: Static config validation
  - Confirm iOS debug and release entitlements include `com.apple.developer.associated-domains` with `applinks:app.bandroadie.com`.
- PRE-DEPLOY TEST 3: Static config validation
  - Confirm `web/.well-known/apple-app-site-association` exists and contains valid JSON with app identifier and `/invite` path allowance.
- PRE-DEPLOY TEST 4: Unit/path validation
  - Confirm deep-link parser routes invite URIs and still routes auth URIs unchanged.

### Tier 2 - Post-deployment (after web + app release)

- POST-DEPLOY TEST 1: Hosted well-known verification
  - `https://app.bandroadie.com/.well-known/apple-app-site-association` returns HTTP 200 with expected JSON body.
- POST-DEPLOY TEST 2: Android end-to-end
  - On installed Android release build, tap invite email link and verify direct app open to invite handling.
- POST-DEPLOY TEST 3: iOS end-to-end
  - On installed iOS release/TestFlight build, tap invite email link and verify direct app open to invite handling.
- POST-DEPLOY TEST 4: Auth regression
  - Validate magic-link login callbacks still complete on both iOS and Android.
- POST-DEPLOY TEST 5: Browser fallback
  - On device without app installed, invite URL still opens web invite route successfully.

## 16. QA Regression Areas

- Invite email tap behavior on iOS with app installed.
- Invite email tap behavior on Android with app installed.
- Invite handling when app is cold-started, backgrounded, and foregrounded.
- Magic-link auth flow (custom scheme + HTTPS auth callback) to ensure no auth regressions.
- Invite link behavior when app is not installed (web fallback remains intact).

## 17. Rollout / Migration Strategy

No database migration.

Deployment sequence required:

1. Deploy web assets (AASA + `web/vercel.json`) to `app.bandroadie.com`.
2. Ship new mobile builds (iOS + Android) containing entitlement/manifest/runtime changes.
3. Validate end-to-end from real invite email links on physical devices.

Important operational note:

- This fix is not purely Flutter code. It requires coordinated app binary release plus hosted well-known-file deployment.

## 18. Out of Scope

- Reworking invite token/business logic.
- Refactoring global routing architecture.
- Changing Supabase edge-function invite generation.
- Broad universal-link coverage beyond invite/auth paths.
