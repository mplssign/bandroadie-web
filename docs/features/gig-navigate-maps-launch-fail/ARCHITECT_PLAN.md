# Architect Plan

## 1. Feature Slug

`bug/gig-navigate-maps-launch-fail`

## 2. Problem Summary

The gig detail Navigate action does not meet product expectations on iOS.

Observed from code on `main`:

- The Navigate button always attempts one hardcoded URL (`https://maps.google.com/?q=...`) via `launchUrl(..., mode: LaunchMode.externalApplication)`.
- If that launch returns `false`, the user sees `Could not open maps`.
- There is no code path that attempts a platform-default navigation app first.
- There is no in-app fallback picker implementation in the current `main` branch.

Expected behavior for this bug:

- Attempt direct launch into the platform-default navigation handler first.
- Only if that fails, show a fallback app-picker path that actually works.

## 3. Root Cause

1. **Primary root cause (HIGH confidence):** gig navigation is implemented as a single hardcoded Google Maps web URL path in `ViewGigDrawer`, with no default-app-first attempt and no robust fallback chain.
2. **Secondary root cause (MEDIUM confidence):** the current failure handling is binary (`launchUrl` false => snackbar), so any iOS resolver failure immediately produces `Could not open maps` with no recovery.
3. **Platform config gap (HIGH confidence):** `ios/Runner/Info.plist` has no `LSApplicationQueriesSchemes` entries for `maps`, `comgooglemaps`, or `waze`. This will break `canLaunchUrl` checks for custom scheme fallback paths if/when those are used.

Code evidence:

- `lib/features/gigs/widgets/view_gig_drawer.dart` uses only `https://maps.google.com/?q=$query` and emits `Could not open maps` on launch failure.
- `ios/Runner/Info.plist` currently contains no `LSApplicationQueriesSchemes` key.

Important discrepancy documented:

- The reported in-app picker (Apple Maps / Google Maps / Waze) is not present in `main` code. The current implementation has no such drawer. This implies either runtime behavior from external app/browser chooser UI or a build/runtime mismatch outside this branch.

## 4. Reference Docs Consulted

No maps/navigation domain reference folder exists under `docs/reference/`.

Checked reference structure:

- `docs/reference/architecture/`
- `docs/reference/auth/`
- `docs/reference/banners/`
- `docs/reference/bpm/`
- `docs/reference/deployment/`
- `docs/reference/general/`
- `docs/reference/notifications/`
- `docs/reference/ui/`

No dedicated docs for maps-launch behavior were found.

## 5. Existing System Analysis

Current data/behavior flow for gig navigation:

1. User taps Navigate icon in `ViewGigDrawer`.
2. `_openNavigation()` builds a query from `gig.address + gig.location` fallback `gig.name + gig.location`.
3. It constructs `Uri.parse('https://maps.google.com/?q=$query')`.
4. Calls `launchUrl(uri, mode: LaunchMode.externalApplication)`.
5. On false result, shows app snackbar: `Could not open maps`.

There is no shared map-launch utility currently used by gigs/rehearsals/venues. Gig navigation appears feature-local to `ViewGigDrawer`.

## 6. Proposed Solution

Implement a minimal two-stage launch strategy in the gig drawer flow:

1. **Default-first attempt (no picker):**
   - iOS + Android: attempt a generic platform-resolved URI first, designed to route through OS intent resolution:
     - iOS: `maps://?q=<encoded>` (closest practical approximation to default maps handling, without public API to query chosen default nav app).
     - Android: `geo:0,0?q=<encoded>` (uses Android intent resolution and can honor user default/chooser behavior).
2. **Fallback picker (only if default-first fails):**
   - Present in-app bottom sheet with explicit providers:
     - Apple Maps
     - Google Maps
     - Waze
   - Each option uses provider-specific URI/scheme.
   - Attempt launch with provider URI; show failure snackbar only if selected provider fails.
3. **Platform config updates for fallback viability:**
   - iOS `LSApplicationQueriesSchemes`: add `maps`, `comgooglemaps`, `waze`.
   - Android package visibility queries (if `canLaunchUrl` is used for non-http schemes): add intent queries needed for custom URI checks to avoid false negatives on Android 11+.
4. **Keep existing query composition behavior** (address-first fallback to name+location) unchanged.

iOS feasibility note:

- iOS does not provide a public API to read the user’s default navigation app selection. A guaranteed “open user default nav app” contract is therefore not fully determinable from Flutter.
- Closest correct approximation: launch a generic maps URI first, then explicit app fallback picker.

Android feasibility note:

- Android supports intent-based resolution for `geo:` URIs, so true default/chooser behavior is achievable via OS intent routing.

## 7. Database Impact

`not applicable`

- Migrations: unaffected
- RLS: unaffected
- RPCs: unaffected
- Triggers: unaffected

## 8. Flutter Architecture Changes

No new provider/repository/controller architecture.

Localized behavior changes only:

- Update gig drawer navigation handler to a two-stage launcher flow.
- Add internal picker UI in gig feature widget.
- Optionally add a small shared helper only if needed to keep URI-building readable; otherwise keep logic in-place.

## 9. Files to Create

`none`

## 10. Files to Modify

| File                                             | What changes                                                                                                                                             |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/gigs/widgets/view_gig_drawer.dart` | Replace single hardcoded Google web launch with default-first launch + fallback provider picker + provider-specific launch handling and error messaging. |
| `ios/Runner/Info.plist`                          | Add `LSApplicationQueriesSchemes` entries: `maps`, `comgooglemaps`, `waze` for reliable custom scheme checks.                                            |
| `android/app/src/main/AndroidManifest.xml`       | Add `<queries>` entries for map intents/schemes if `canLaunchUrl` checks are used for fallback providers on Android 11+.                                 |

## 11. Files Off-Limits

| File                                    | Reason                                                                     |
| --------------------------------------- | -------------------------------------------------------------------------- |
| `lib/main.dart`                         | App initialization order is guardrail-protected and unrelated to this bug. |
| `lib/features/gigs/gig_repository.dart` | Data layer is not part of launch failure; no persistence changes required. |
| `supabase/**`                           | No backend/database behavior involved in maps launch flow.                 |
| `pubspec.yaml`                          | No dependency changes required for this fix.                               |

## 12. System Impact Map

| System                                 | Impact                                                                           |
| -------------------------------------- | -------------------------------------------------------------------------------- |
| Gigs                                   | affected                                                                         |
| Rehearsals                             | unaffected (no shared maps launcher path currently)                              |
| Setlists / Catalog                     | unaffected                                                                       |
| Members / RBAC                         | unaffected                                                                       |
| Auth / Session                         | unaffected                                                                       |
| Routing                                | unaffected                                                                       |
| Notifications                          | unaffected                                                                       |
| Platform (iOS / Android / Web / macOS) | iOS affected, Android potentially affected by parity logic, Web/macOS unaffected |

## 13. Regression Risk

`MEDIUM`

Rationale:

- User-facing launch behavior changes on mobile platforms.
- Touches platform-specific URL behavior and manifest/plist configuration.
- Scope is still localized to one feature widget + platform config files.

## 14. Engineer Task Breakdown

1. Update `ViewGigDrawer` navigation action to attempt a platform-resolved default launch URI first.
2. Implement in-app fallback picker with Apple Maps, Google Maps, and Waze options (shown only after default-first attempt fails).
3. Implement provider-specific URI builders and launch handlers with robust per-option failure messaging.
4. Add iOS `LSApplicationQueriesSchemes` entries (`maps`, `comgooglemaps`, `waze`).
5. Add Android `<queries>` support if the implementation uses `canLaunchUrl` for custom schemes.
6. Validate analyzer passes and verify no unrelated UX/state changes in gig drawer.

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

No database deployment is required for this feature. Tier structure retained for process compliance.

- `-- PRE-DEPLOY TEST 1:` Static review confirms default-first attempt executes before any picker UI is shown.
- `-- PRE-DEPLOY TEST 2:` Static review confirms fallback picker is only presented when default-first launch fails.
- `-- PRE-DEPLOY TEST 3:` Static review confirms iOS plist contains `maps`, `comgooglemaps`, `waze` under `LSApplicationQueriesSchemes`.
- `-- PRE-DEPLOY TEST 4:` Static review confirms Android manifest includes required package-visibility queries when non-http `canLaunchUrl` checks are used.
- `-- PRE-DEPLOY TEST 5:` `flutter analyze` returns 0 errors.

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

No Supabase deployment is required; execute as post-implementation runtime verification.

- `-- POST-DEPLOY TEST 1:` iOS physical device with Apple Maps default: tap Navigate from gig detail and verify direct app launch occurs without picker.
- `-- POST-DEPLOY TEST 2:` iOS: force default-first failure path (e.g., provider unavailable scenario) and verify in-app fallback picker appears with 3 options.
- `-- POST-DEPLOY TEST 3:` iOS: tap each fallback option (Apple Maps / Google Maps / Waze) and verify success for installed apps, graceful error for unavailable app.
- `-- POST-DEPLOY TEST 4:` Android physical device: tap Navigate and verify `geo:` intent resolves through default app / chooser and launches.
- `-- POST-DEPLOY TEST 5:` Regression check: gig drawer still closes/behaves normally; no impact to edit/save/detail rendering.

## 16. QA Regression Areas

- Gig detail Navigate primary flow: direct launch with no picker when default resolution succeeds.
- Fallback picker behavior: appears only on failure of default-first attempt.
- Fallback provider options: Apple Maps, Google Maps, Waze each validated independently.
- iOS end-to-end behavior on physical device (not simulator-only).
- Android parity behavior via `geo:` intent and chooser/default handling.
- Address vs name fallback query composition remains correct.

## 17. Rollout / Migration Strategy

- No DB migration.
- Standard client release path only.
- Validate on iOS first (primary affected platform), then Android parity check before full release.

## 18. Out of Scope

- Reworking navigation behavior in non-gig features.
- Introducing a cross-feature maps-launch architecture abstraction.
- Changing venue/address data modeling.
- Any backend/Supabase changes.
