# Architect Plan

## 1. Feature Slug

`bug/missing-location-usage-description`

## 2. Problem Summary

App Store Connect (via Transporter, during upload validation of build 1.3.36 (224)) returned
error 90683: the compiled app binary references APIs that access sensitive location data (or
holds an entitlement permitting such access), but `ios/Runner/Info.plist` has no
`NSLocationWhenInUseUsageDescription` purpose string. BandRoadie has no maps/GPS feature that
uses the device's live location. The question this plan resolves is *why* the compiled binary
references location APIs at all, and whether the correct fix is to strip an unused capability
or add an honest purpose string.

## 3. Root Cause

**Confidence: MEDIUM** (confirmed by elimination via direct inspection of every candidate named
in the Feature Input, plus full git history; the one remaining candidate — Firebase's native
iOS SDK — could not be directly inspected because doing so requires running `pod install`, a
state-changing/build command outside Architect's read-only mandate, and the locally installed
`ios/Pods` / `ios/Podfile.lock` are stale — see Discrepancy note below).

### Ruled out, with evidence

1. **`permission_handler` Podfile macro (the hypothesis stated in the Feature Input) — RULED OUT.**
   Full history of `ios/Podfile` (`git log --follow -p -- ios/Podfile`) shows exactly two
   commits: the initial commit and a later `platform :ios` bump. In both, and in the current
   working tree, the `post_install` block has only ever defined:
   ```ruby
   config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
     '$(inherited)',
     # Camera permission
     'PERMISSION_CAMERA=1',
     # Photo library permission
     'PERMISSION_PHOTOS=1',
   ]
   ```
   `PERMISSION_LOCATION` (or `_WHENINUSE`/`_ALWAYS`) has never been present. This is not a
   regression or something that was recently removed — it was never enabled.

2. **`permission_handler_apple` compiled code — RULED OUT as a contributor under current config.**
   Read `.../permission_handler_apple-9.4.7/ios/Classes/strategies/LocationPermissionStrategy.m`:
   ```objc
   #import "LocationPermissionStrategy.h"

   #if PERMISSION_LOCATION || PERMISSION_LOCATION_WHENINUSE || PERMISSION_LOCATION_ALWAYS
   ...
   @implementation LocationPermissionStrategy {
       CLLocationManager *_locationManager;
   ```
   And `PermissionHandlerEnums.h`:
   ```objc
   #ifndef PERMISSION_LOCATION
       #define PERMISSION_LOCATION 0
   ```
   And `PermissionManager.m` line 103 gates the `case PermissionGroupLocation:` dispatch itself
   behind the same `#if`. With `PERMISSION_LOCATION` undefined (defaults to 0), the entire
   `LocationPermissionStrategy` implementation — including every `CLLocationManager` reference —
   is preprocessed out of the compiled object file. No location symbols reach the binary from
   this pod under the current Podfile.

3. **`image_picker` / `image_picker_ios` (2.2.0) — RULED OUT.**
   `grep -rl "CLLocationManager\|CoreLocation\|NSLocationWhenInUse" .../image_picker_ios-0.8.13+6/ios`
   returned no matches.

4. **`firebase_core` / `firebase_messaging` Flutter plugin wrapper code — RULED OUT.**
   Same grep against `.../firebase_core-4.12.1/ios` and `.../firebase_messaging-16.4.3/ios`
   returned no matches. (Note: this only covers the Dart-facing Flutter plugin glue code, not
   Firebase's underlying native CocoaPods SDK — see Discrepancy note below.)

5. **Every other native-iOS Flutter plugin in `pubspec.yaml`** (`share_plus` 10.1.4,
   `file_picker` 8.3.7, `url_launcher_ios` 6.3.6, `package_info_plus` 9.0.0, `app_links` 6.4.1,
   `flutter_local_notifications` 18.0.1, `printing` 5.14.2) — **RULED OUT.** Same grep pattern
   against each package's `ios/` directory returned no matches.

6. **`ios/Runner/RunnerRelease.entitlements` and `RunnerDebug.entitlements` — RULED OUT.**
   Both files contain only `com.apple.developer.associated-domains` and `aps-environment`. No
   location entitlement (e.g. `com.apple.developer.location.push`) is present.

7. **`ios/GoogleService-Info.plist` — RULED OUT.** `grep -i location` returns no matches.

8. **First-party Dart code (`lib/`) — RULED OUT.** `grep -rn "Permission\.location\|geolocator\|CLLocationManager\|requestLocation" lib/` returns no matches. Every hit for the
   bare word "location" in `lib/` (e.g. `lib/app/models/gig.dart:28`) is a venue-address
   `String` field, unrelated to device GPS. This is corroborated by the existing plan at
   `docs/features/gig-navigate-maps-launch-fail/ARCHITECT_PLAN.md`, which documents the gig
   "Navigate" feature as an address-string-based external URL launch
   (`https://maps.google.com/?q=<address>` via `url_launcher`), not a device-location API call.
   This also explains the `LSApplicationQueriesSchemes` entries (`maps`, `comgooglemaps`,
   `waze`) in `Info.plist` — they exist to open external map apps by address, not to request the
   device's current location.

### Remaining candidate (not directly verifiable — root of the MEDIUM rating)

By elimination, the only unexamined surface is **Firebase's native iOS SDK** — the actual
CocoaPods libraries (`FirebaseCore`, `FirebaseMessaging`, `FirebaseInstallations`,
`GoogleUtilities`, `GoogleDataTransport`, `nanopb`, `PromisesObjC`/`PromisesSwift`) that
`firebase_core`/`firebase_messaging` pull in transitively via CocoaPods. These are not present
in `~/.pub-cache` (they are native SDKs resolved by CocoaPods, not Dart packages), and inspecting
them requires a real `pod install`, which is a state-changing/network-dependent build step
outside Architect's read-only mandate.

**Discrepancy found and documented (not caused by this bug, flagged for transparency):** the
locally installed `ios/Pods` and the git-tracked `ios/Podfile.lock` are both stale — they list
only 4 pods (`Flutter`, `flutter_local_notifications`, `permission_handler_apple`, `printing`)
and predate the addition of `firebase_core`, `firebase_messaging`, `image_picker`, `share_plus`,
`file_picker`, `url_launcher`, `package_info_plus`, and `app_links` to `pubspec.yaml`. This does
**not** affect the diagnosis of the shipped build: `tools/build_ios.sh` unconditionally deletes
`ios/Pods` and `ios/Podfile.lock` and runs a fresh `pod install` before every release/IPA build
(lines 80–84), so the actual TestFlight binary that produced the warning was built against the
full, current dependency set regardless of what's committed locally. The stale lockfile is a
pre-existing local/repo hygiene gap, out of scope for this fix (see §18).

This is a well-documented, widely-reported pattern in the Flutter/Firebase ecosystem: Firebase's
iOS SDK dependency graph (via `GoogleUtilities`/`GoogleDataTransport`) has historically shipped
compiled references to `CoreLocation` APIs in some versions, which Apple's static binary scan
(error 90683) flags regardless of whether the app ever calls them at runtime. Given every
BandRoadie-controlled surface (own code, own Podfile config, own plugin choices, entitlements)
has been ruled out with direct evidence, and Firebase Messaging is a real, load-bearing
dependency (push notifications) that cannot be removed, this is the most probable remaining
explanation.

**Required pre-implementation validation (Engineer Task 1):** run a real `pod install` and grep
the resulting `ios/Pods` tree for `CLLocationManager`/`CoreLocation` to identify the exact pod,
and record it in `ENGINEER_REPORT.md`. This does not change the prescribed fix (see §6) — it
exists to close the confidence gap and leave a verifiable record, not to gate the decision
between "remove capability" and "add purpose string" (see next section for why that decision is
already determined).

### Why the fix is "add a purpose string," not "remove a capability"

The Feature Input's own decision framework: *if genuinely unused, remove the enabling flag; if
something does need it, add a real purpose string.* Given the evidence above:
- There is no `PERMISSION_LOCATION` flag to remove — it was never set (see point 1).
- The location-referencing code, if it exists at all, lives inside Firebase's compiled native
  SDK, not in anything BandRoadie's Podfile, pubspec, or source controls. There is no flag or
  macro available to strip it — Firebase does not expose a "disable CoreLocation linkage" build
  setting, and removing `firebase_messaging` is not viable (push notifications are core
  functionality).
- Therefore the correct minimal fix is an honest `NSLocationWhenInUseUsageDescription` string
  that reflects reality: BandRoadie does not use the device's location for any feature.

## 4. Reference Docs Consulted

Per explicit instruction for this session, `docs/agents/ARCHITECT.md` Phase 4 (notification
domain reference) is **N/A** — this is an iOS Info.plist/permissions bug, not a notification
delivery bug. Confirmed no dedicated reference domain exists for this area either: listed
`docs/reference/` and found `ui/`, `audits/`, `auth/`, `general/`, `bpm/`, `banners/`,
`architecture/`, `deployment/`, `notifications/` — no `ios/`, `permissions/`, or `build/`
subdirectory. No reference docs were consulted for this diagnosis.

## 5. Existing System Analysis

Current data/build flow relevant to this bug:

1. `tools/build_ios.sh --ipa` runs `flutter pub get`, `flutter build ios --config-only`, then
   deletes and reinstalls `ios/Pods`/`ios/Podfile.lock` from scratch, then
   `flutter build ipa --release`.
2. `ios/Podfile`'s `post_install` hook sets `GCC_PREPROCESSOR_DEFINITIONS` to enable only
   `PERMISSION_CAMERA=1` and `PERMISSION_PHOTOS=1` for `permission_handler_apple` — no location
   macro is or has ever been set.
3. `ios/Runner/Info.plist` declares purpose strings for camera and photo library only
   (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
   `NSPhotoLibraryAddUsageDescription`). No location purpose string exists.
4. The compiled Runner.app binary — per Apple's validator — contains a reference to a
   location-sensitive API without a corresponding Info.plist purpose string, triggering error
   90683 on upload. Root-cause elimination (§3) points to Firebase's native SDK as the source,
   with MEDIUM confidence pending the Engineer's confirmatory `pod install` grep.
5. This does not block internal TestFlight delivery today, only flags a warning; per Apple's
   review policy, unresolved purpose-string gaps of this kind can block public App Store review.

## 6. Proposed Solution

Add a single, honest `NSLocationWhenInUseUsageDescription` key to `ios/Runner/Info.plist`,
stating that BandRoadie does not use the device's location. This satisfies Apple's static binary
scan without misrepresenting app behavior, requires no Podfile/dependency changes (there is
nothing to remove — see §3), and does not touch any other platform or entitlement.

Exact string (Engineer to use verbatim, placed alongside the existing `NS*UsageDescription`
keys, in the "Camera & Photo Library Permissions" block — rename block comment to reflect the
addition):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>BandRoadie does not use your location. This permission is not requested by any app feature.</string>
```

## 7. Database Impact

Not applicable. No Supabase schema, RLS, RPC, or trigger involved.

## 8. Flutter Architecture Changes

None. No Dart state, widget, provider, or repository is touched. This is a native
iOS-configuration-only change (`Info.plist`).

## 9. Files to Create

None.

## 10. Files to Modify

| File | What changes |
|------|-------------|
| `ios/Runner/Info.plist` | Add `NSLocationWhenInUseUsageDescription` key with the honest purpose string from §6, in the existing permissions block. |

## 11. Files Off-Limits

| File | Reason |
|------|--------|
| `ios/Podfile` | No `PERMISSION_LOCATION` flag exists to remove (confirmed absent in full history); nothing in this file causes or fixes the warning. |
| `ios/Runner/RunnerRelease.entitlements`, `ios/Runner/RunnerDebug.entitlements` | Confirmed to contain no location entitlement; not implicated. |
| `ios/GoogleService-Info.plist` | Confirmed no location keys; Firebase project config, not an app capability declaration. |
| `pubspec.yaml` | No dependency change required; removing `firebase_messaging` is not viable (push notifications). |
| `ios/Podfile.lock`, `ios/Pods/` | Build artifacts regenerated fresh by `tools/build_ios.sh` on every release build; the diagnostic `pod install` in Engineer Task 1 (§14) is read-only-in-intent — do not hand-edit, and do not treat any resulting lockfile diff as part of this fix's scope (see §18). |
| Any file under `lib/` | No first-party Dart code references device location (confirmed); this is a native-config-only fix. |
| `ios/Runner/Info.plist` keys other than `NSLocationWhenInUseUsageDescription` | No other key is implicated; do not touch `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `LSApplicationQueriesSchemes`, or any other existing key. |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not allowed (none proposed)
**New files:** none

## 12. System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected (Firebase Messaging remains unchanged; only Info.plist gains a declarative key) |
| Platform (iOS / Android / Web / macOS) | iOS: affected (Info.plist change, App Store Connect validation outcome). Android / Web / macOS: unaffected — this Info.plist key has no effect on non-iOS platforms and no Android/web/macOS file is touched. |

## 13. Regression Risk

**LOW.**

Rationale:
- Exactly one file changes, adding one declarative Info.plist string key.
- No init order, auth, session, routing, or database mutation is touched.
- No other notification type or code path shares this file's runtime behavior — adding an
  unused purpose string has no functional effect; iOS only surfaces it if the corresponding API
  is actually invoked, which BandRoadie never does.
- The change cannot regress camera/photo permission behavior — those keys are untouched.

## 14. Engineer Task Breakdown

1. **Diagnostic (does not gate the fix, confirms root cause for the record):** From
   `ios/`, run `pod install` (mirroring `tools/build_ios.sh` lines 80–84: delete `Pods` and
   `Podfile.lock` first for a clean resolve against current `pubspec.yaml`), then run
   `grep -rl "CLLocationManager\|CoreLocation" Pods/` against the resulting tree. Record which
   pod(s) matched in `ENGINEER_REPORT.md`. Do not commit the regenerated `Podfile.lock` as part
   of this fix unless the Manager separately authorizes refreshing that pre-existing staleness
   (see §18) — if in doubt, ask before including it in the diff.
2. Edit `ios/Runner/Info.plist`: add the `NSLocationWhenInUseUsageDescription` key with the
   exact string from §6, placed in the existing "Camera & Photo Library Permissions" comment
   block (Engineer may retitle the comment to reflect the addition, e.g. "Camera, Photo Library
   & Location Permissions" — comment-only, no functional change).
3. Rebuild the release IPA via `./tools/build_ios.sh --ipa` to confirm the build still succeeds
   with the new key present.

## 15. Verification Plan

This bug has no database or backend component; the two-tier SQL-specific structure in
`ARCHITECT.md` §Phase 12 item 15 does not apply as written. Adapted to this iOS build/validation
change:

**Tier 1 — Pre-upload (must pass before building the IPA for delivery):**
- PRE-DEPLOY TEST 1: `plutil -lint ios/Runner/Info.plist` succeeds (valid plist syntax).
- PRE-DEPLOY TEST 2: Manual read of `ios/Runner/Info.plist` confirms
  `NSLocationWhenInUseUsageDescription` is present with non-empty string content, and that no
  other existing key was modified or removed (diff review against §10/§11).
- PRE-DEPLOY TEST 3: `./tools/build_ios.sh --ipa` completes successfully (build does not
  regress).

**Tier 2 — Post-upload (run after uploading the new IPA via Transporter):**
- POST-DEPLOY TEST 1: Transporter delivery for the new build shows 0 issues (no 90683 warning),
  confirming the purpose string satisfied Apple's validator.
- POST-DEPLOY TEST 2: Confirm camera and photo library permission prompts still show their
  original, correct purpose strings on a real device/simulator (regression check that the edit
  didn't disturb adjacent keys).

## 16. QA Regression Areas

- Confirm `NSLocationWhenInUseUsageDescription` string is present and matches §6 exactly.
- Confirm `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
  `NSPhotoLibraryAddUsageDescription` are unchanged (byte-for-byte, aside from surrounding
  comment text).
- Confirm no location permission prompt is ever triggered anywhere in the app (there is no
  code path that would call `CLLocationManager`/`Permission.location` — if QA finds one, that
  contradicts this plan's root-cause analysis and must be escalated, not silently accepted).
- Confirm Android, Web, and macOS builds are unaffected (this file is iOS-only).
- Confirm the app still builds and archives cleanly via `./tools/build_ios.sh --ipa`.

## 17. Rollout / Migration Strategy

No phased rollout needed. Ship in the next TestFlight/App Store build. No data migration, no
feature flag, no backend deploy. Recommend re-uploading via Transporter once to positively
confirm the 90683 warning clears before relying on this as closed.

## 18. Out of Scope

- Refreshing/committing the stale `ios/Podfile.lock` (currently missing `firebase_core`,
  `firebase_messaging`, `image_picker`, `share_plus`, `file_picker`, `url_launcher`,
  `package_info_plus`, `app_links` entries) is a pre-existing repo-hygiene discrepancy, not
  caused by and not required to fix this bug. Flagged for Manager/Tony awareness, not actioned
  here.
- Identifying the exact upstream Firebase pod/version responsible for the CoreLocation reference
  beyond Engineer's Task 1 diagnostic grep (e.g., filing an upstream issue against
  firebase-ios-sdk or GoogleUtilities) is out of scope.
- Any change to Android or web permission handling — this bug and fix are iOS-only.
- Any change to the gig "Navigate" maps-launch feature (`view_gig_drawer.dart`) — confirmed
  unrelated, already covered by its own separate plan at
  `docs/features/gig-navigate-maps-launch-fail/`.
