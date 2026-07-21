# Engineer Report

## Feature Slug
`bug/missing-location-usage-description`

## Feature Title
App Store Connect flags missing NSLocationWhenInUseUsageDescription in Info.plist

## Goal
Satisfy Apple's App Store Connect validation (error 90683) by adding an honest
`NSLocationWhenInUseUsageDescription` purpose string to `ios/Runner/Info.plist`, per
`ARCHITECT_PLAN.md` §6, after confirming with higher confidence which dependency actually
references location APIs in the compiled binary.

## Architect Tasks Completed
- [x] Task 1 (§14.1) — Diagnostic: ran a fresh `pod install`; the literal `grep -rl
      "CLLocationManager\|CoreLocation" Pods/` returned no matches (see Deviations — the plan's
      CocoaPods-only diagnostic missed the real source, which required going further; documented
      below with empirical proof).
- [x] Task 2 (§14.2) — Added `NSLocationWhenInUseUsageDescription` to `ios/Runner/Info.plist`
      with the exact string from §6, in the existing permissions block; retitled the block
      comment as explicitly permitted by the plan.
- [x] Task 3 (§14.3) — Rebuilt the release IPA via `./tools/build_ios.sh --ipa`; build succeeded.

## Files Created
- none

## Files Modified
- `ios/Runner/Info.plist` — added `NSLocationWhenInUseUsageDescription` key/string; retitled the
  adjacent comment from "Camera & Photo Library Permissions" to "Camera, Photo Library & Location
  Permissions" (comment-only). No other key touched — confirmed via `git diff` (see below).

## Diagnostic Result (Task 1) — Root Cause Upgraded to HIGH Confidence, Empirically Verified

The plan's literal instruction (`grep -rl "CLLocationManager\|CoreLocation" Pods/` after a fresh
`pod install`) came back empty — a fresh `pod install` still resolves only 4 CocoaPods pods
(`Flutter`, `flutter_local_notifications`, `permission_handler_apple`, `printing`). This is
expected, not a diagnostic failure: this project resolves `firebase_core`, `firebase_messaging`,
`image_picker`, `share_plus`, `file_picker`, `url_launcher`, `package_info_plus`, and `app_links`
via **Swift Package Manager**, not CocoaPods (confirmed by
`ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` and a
`XCLocalSwiftPackageReference "Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"`
entry in `ios/Runner.xcodeproj/project.pbxproj`). The Architect plan's MEDIUM-confidence Firebase
hypothesis was based on not having visibility into this SPM path.

To actually fulfill Task 1's intent ("identify which pod actually references location APIs"), I
extended the diagnostic beyond the plan's literal `Pods/` grep to the real dependency mechanism
in use, then verified empirically against the compiled binary — read-only investigation, no
additional files modified:

1. **Grepped the cached SPM checkouts** (`~/Library/Developer/Xcode/DerivedData/Runner-*/SourcePackages/checkouts/`)
   for `CLLocationManager`/`NSLocationWhenInUseUsageDescription`. Firebase's own packages
   (`firebase-ios-sdk`, `GoogleAppMeasurement`, `GoogleUtilities`, `GoogleDataTransport`,
   `nanopb`, `promises`, `app-check`, `google-ads-on-device-conversion-ios-sdk`) — **zero
   matches**. This rules out Firebase entirely, contrary to the plan's leading hypothesis.
   One package matched: **`DKCamera`**, at
   `DKCamera/DKCamera/DKCameraLocationManager.swift` — a real, unconditional
   `CLLocationManager` wrapper (`requestWhenInUseAuthorization()`, `startUpdatingLocation()`)
   used to embed GPS EXIF metadata into captured photos. It lives in the package's main library
   target (`DKCamera/DKCamera`, per its `Package.swift`), not a demo/test target — i.e. it ships.
   `DKCamera` is a transitive dependency of `DKImagePickerController`
   (`.package(url: "https://github.com/zhangao0086/DKCamera", .branch("master"))` in
   `DKImagePickerController/Package.swift`), which is a historical dependency of
   `image_picker_ios`'s multi-image-picker UI.
2. **Empirically confirmed against the actual compiled app binary**, first from a pre-existing
   build artifact (`build/ios/iphoneos/Runner.app/Runner`, predating this fix) and then re-checked
   against the fresh `Runner.xcarchive` produced by Task 3:
   - `otool -L Runner` lists `/System/Library/Frameworks/CoreLocation.framework/CoreLocation` as
     a linked framework.
   - `nm -u Runner | grep CLLocationManager` shows `_OBJC_CLASS_$_CLLocationManager` as an
     imported symbol.
   - `strings Runner | grep DKCameraLocationManager` matches, including the mangled Swift symbol
     `_TtC8DKCamera23DKCameraLocationManager` — directly tying the linked symbol back to the
     source file found in step 1.
   - `DKImagePickerController_DKImagePickerController.bundle` is present at the top level of the
     built `Runner.app`, confirming the package is actually linked into the shipped binary (not
     an orphaned `Package.resolved` pin).
   - `strings Runner.app/Info.plist | grep -i location` returned **nothing** before this fix —
     precisely matching Apple's complaint (location API present, no purpose string).
3. **Checked whether BandRoadie's own code could trigger this path**:
   `grep -rn "ImagePicker\|pickMultiImage\|pickImage" lib/` shows the app only ever calls
   `ImagePicker().pickImage(...)` (`lib/features/bands/band_form_screen.dart:1404`) — the
   single-image API, never `pickMultiImage()`. `pickMultiImage()` is what actually invokes
   `DKImagePickerController`'s UI at runtime. This confirms `DKCamera`'s location code is present
   in the binary due to how `image_picker_ios` statically links the whole
   `DKImagePickerController` product regardless of which method is called at the Dart level — it
   is never reachable from BandRoadie's actual usage. This is exactly the scenario the plan's §6
   purpose string is designed for: real symbol presence, zero actual runtime use.

**Net effect on the plan:** the *fix* prescribed in §6 (add an honest purpose string) is
unchanged and remains correct — if anything, this finding makes it a stronger fit, since
`DKCamera`'s location code is verifiably unreachable from BandRoadie's own call sites. Root cause
confidence is upgraded from the plan's MEDIUM to **HIGH**, now backed by direct symbol-level
evidence from the actual shipped binary, not elimination alone.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors / 0 warnings ("No issues found!") — expected, no Dart code was touched.

## Test Results
Not run — plan requires tests only if they clearly cover changed code; this change is a native
iOS Info.plist key with no Dart-testable surface.

## Verification
Manual steps performed (per plan §15 Tier 1):
- `plutil -lint ios/Runner/Info.plist` → `OK`.
- `git diff -- ios/Runner/Info.plist` reviewed line-by-line: confirms only the block comment
  retitle and the new `NSLocationWhenInUseUsageDescription` key/string were added; every other
  existing key (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
  `NSPhotoLibraryAddUsageDescription`, `LSApplicationQueriesSchemes`, etc.) is byte-for-byte
  unchanged.
- `./tools/build_ios.sh --ipa` completed successfully end-to-end (`flutter pub get` → config-only
  build → clean `pod install` → `flutter build ipa --release`), producing
  `build/ios/archive/Runner.xcarchive` and `build/ios/ipa/BandRoadie.ipa` (38.5MB) with no build
  errors.
- Confirmed the new key made it into the actual shipped artifacts (not just source): checked
  `build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Info.plist` and the
  extracted `Payload/Runner.app/Info.plist` from `build/ios/ipa/BandRoadie.ipa` — both contain
  `NSLocationWhenInUseUsageDescription` = "BandRoadie does not use your location. This permission
  is not requested by any app feature."
- Re-ran the `otool -L` / `nm -u` / `strings` checks (see Diagnostic Result above) against the
  fresh archive binary to confirm the underlying `CLLocationManager` linkage is unchanged (as
  expected — no dependency was modified) and now sits alongside the new purpose string.
- `git status --short` after the full build shows only `M ios/Runner/Info.plist`; `ios/Pods/` is
  gitignored (untouched by git regardless of the diagnostic `pod install`), and `git diff --stat
  -- ios/Podfile.lock` shows no diff — the diagnostic/build-script pod installs resolved to
  byte-identical lockfile content, so no unintended lockfile change is in the diff.
- Tier 2 (Transporter re-upload to confirm error 90683 clears) was not performed — that requires
  uploading to App Store Connect, which is outside Engineer's scope (build-only) and is called
  out in the plan as a post-upload verification step for Tony/Manager.

## Deviations From Architect Plan
1. **Task 1 diagnostic extended beyond the literal `Pods/` grep.** The plan's exact command
   (`grep -rl "CLLocationManager\|CoreLocation" Pods/`) returned no matches because this project's
   relevant native dependencies resolve via Swift Package Manager, not CocoaPods — a fact the
   Architect plan couldn't see (Architect is read-only and cannot run `pod install`). I ran the
   literal command as instructed (recorded above: empty result), then extended the same
   read-only diagnostic intent to the actual SPM checkouts and the real compiled binary to avoid
   filing a false "not found" result. No file outside the plan's scope was modified — this was
   investigation only. Justification: the plan itself frames Task 1's purpose as "identify which
   pod actually references location APIs... close the confidence gap," and explicitly says this
   "does not change the prescribed fix" — which held true. Flagging this as a deviation for
   transparency per Engineer protocol, not because it changed any file.
2. No other deviations. The Info.plist edit matches §6/§10 exactly; no off-limits file (§11) was
   touched; no new dependency was added.

## Blockers Encountered
None.

## Ready For QA
Yes.
