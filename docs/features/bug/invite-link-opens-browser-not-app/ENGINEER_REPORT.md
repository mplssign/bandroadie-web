# Engineer Report

## Feature Slug

bug/invite-link-opens-browser-not-app

## Feature Title

Invite Link Opens Browser, Not App

## Goal

Enable native app handling for invite links on Android and iOS, keep the hosted app-link assets valid, and route invite URIs into the existing invite screen flow without disturbing auth callbacks.

## Architect Tasks Completed

- [x] Task 1 — Added `/invite` to the Android verified app-links intent filter.
- [x] Task 2 — Added Associated Domains entitlements to iOS debug and release configs.
- [x] Task 3 — Created `web/.well-known/apple-app-site-association` with valid JSON and invite/auth path coverage.
- [x] Task 4 — Updated `web/vercel.json` to serve the AASA file as JSON without rewriting it.
- [x] Task 5 — Extended `DeepLinkService` to recognize invite URIs, exchange auth params when present, and forward runtime invite links into the existing route table.
- [x] Task 6 — Verified init order was unchanged and no unrelated routing changes were introduced.

## Corrected Deviation

- Replaced the earlier non-functional `SystemChannels.navigation.invokeMethod('pushRoute', ...)` call with `WidgetsBinding.instance.handlePushRoute(route)`, the Flutter 3.44.6 framework hook that dispatches into the widget-tree route observers.
- Added a narrow analyzer suppression for the framework's protected/visible-for-testing annotations on that hook.

## QA Follow-up Corrections

- Fixed duplicate invite acceptance trigger in `InviteScreen._handleInvite()` by adding the same `!_hasTriedAccept` guard used by the auth-state listener before calling `_acceptInvite(token)`.
- Fixed duplicate `/invite` route stacking risk in `DeepLinkService._handleInviteLink()` by making auth-param handling and runtime route forwarding mutually exclusive:
  - If invite link has auth params (`code`, error, token fragment), process auth callback and return.
  - Only forward to `/invite` for runtime links that do not include auth params.

## Files Created

- [web/.well-known/apple-app-site-association](/Users/tonyholmes/apps/bandroadie/web/.well-known/apple-app-site-association)

## Files Modified

- [android/app/src/main/AndroidManifest.xml](/Users/tonyholmes/apps/bandroadie/android/app/src/main/AndroidManifest.xml)
- [ios/Runner/RunnerDebug.entitlements](/Users/tonyholmes/apps/bandroadie/ios/Runner/RunnerDebug.entitlements)
- [ios/Runner/RunnerRelease.entitlements](/Users/tonyholmes/apps/bandroadie/ios/Runner/RunnerRelease.entitlements)
- [web/vercel.json](/Users/tonyholmes/apps/bandroadie/web/vercel.json)
- [lib/app/services/deep_link_service.dart](/Users/tonyholmes/apps/bandroadie/lib/app/services/deep_link_service.dart)
- [lib/features/auth/invite_screen.dart](/Users/tonyholmes/apps/bandroadie/lib/features/auth/invite_screen.dart)

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 warnings

## Test Results

Not run

## Verification

Manual steps performed:

- Confirmed the current branch is `bug/invite-link-opens-browser-not-app`.
- Verified the Android verified link scope now includes `/invite` alongside `/auth`.
- Verified iOS entitlements now include `com.apple.developer.associated-domains` for `applinks:app.bandroadie.com`.
- Verified the hosted AASA file exists under `.well-known` with valid JSON content.
- Ran `flutter analyze` successfully after the edits.

## Deviations From Architect Plan

None
None beyond the corrected API mismatch noted above and the intentional analyzer suppression for the framework hook.

## Blockers Encountered

None

## Ready For QA

Yes
