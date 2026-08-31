# Engineer Report

## Feature Slug

bug/macos-printing-pod-broken

## Feature Title

iOS and macOS printing/permission_handler pods broken

## Goal

Validate iOS and macOS builds under Flutter Swift Package Manager plugin integration and then run Tier 2 manual smoke checks if both platform builds pass.

## Manager Clarification Applied

- Flutter Swift Package Manager plugin integration is enabled (`swift_package_manager_enabled: {ios: true, macos: true}` in `.flutter-plugins-dependencies`).
- `printing` and `permission_handler_apple` are expected to be resolved through Flutter-generated Swift packages.
- The 2-pod `Podfile.lock` result is expected in this mode and not treated as a plugin drop failure.

## Architect Tasks Completed

- [x] Task 1 — Confirmed current branch is `bug/macos-printing-pod-broken`.
- [x] Task 1 — Confirmed 10 modified files under `ios/` and `macos/` match the plan file list.
- [x] Task 2 — Captured baseline lockfile diff showing dropped `printing` and `permission_handler_apple` from `ios/Podfile.lock`, and dropped `printing` from `macos/Podfile.lock`.
- [x] Task 2 — Captured baseline deployment target diff (`IPHONEOS_DEPLOYMENT_TARGET 13.0 -> 15.0`, `MACOSX_DEPLOYMENT_TARGET 10.15 -> 12.0`).
- [x] Task 2 — Confirmed plugin inputs still include `printing` and `permission_handler_apple` in `pubspec.yaml`, `pubspec.lock`, and `.flutter-plugins-dependencies`.
- [x] Task 3 (partial) — Ran shared prep: `flutter clean`, `flutter pub get`.
- [x] Task 3 (partial) — Ran iOS: `pod deintegrate`, `pod install`.
- [x] Task 3 — Interpreted 2-pod iOS lockfile as expected with SPM plugin integration (manager clarification).
- [x] Task 4 (requested follow-up) — Ran `flutter build ios --no-codesign` (pass).
- [x] Task 4 (requested follow-up) — Ran `flutter build macos` (fail).
- [ ] Task 5 — Side-effect retention decision execution not performed (per user direction: do not revert deployment target/Firebase changes).
- [ ] Task 6 — Not started.
- [ ] Task 7 — Tier 2 manual smoke tests not run because both builds did not succeed.
- [ ] Task 8 — Not started (no revert decisions requested due blocker).
- [x] Task 9 — This report created.

## Files Created

- docs/features/macos-printing-pod-broken/ENGINEER_REPORT.md

## Files Modified

- ios/Podfile.lock
- ios/Runner.xcodeproj/project.pbxproj
- ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved
- macos/Podfile
- macos/Podfile.lock
- macos/Runner.xcodeproj/project.pbxproj
- macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
- macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved

## Analyzer Results

Command: `flutter analyze`
Result: Not run (execution stopped at escalation gate before implementation completion).

## Test Results

Build commands run:

- `flutter build ios --no-codesign`: Passed
- `flutter build macos`: Failed

Tier 2 manual smoke tests:

- Not run, because user requested these only if both builds succeed.

## Code Efficiency / Bloat Check

No Dart code changes were made in this run; native dependency command execution only.

## Verification

Manual steps performed:

- Verified branch and dirty-file scope:
  - `git branch --show-current` => `bug/macos-printing-pod-broken`
  - `git status --short` included the expected 10 modified files under `ios/` and `macos/`
- Baseline evidence captured:
  - `git diff -- ios/Podfile.lock macos/Podfile.lock`
  - `git diff -- ios/Runner.xcodeproj/project.pbxproj macos/Runner.xcodeproj/project.pbxproj | grep -A2 -B2 DEPLOYMENT_TARGET`
  - Dependency/plugin input checks in `pubspec*` and `.flutter-plugins-dependencies`
- iOS fix attempt executed:
  - `flutter clean`
  - `flutter pub get`
  - `cd ios && pod deintegrate && pod install`
- iOS post-install lock assertion:
  - `grep -n "printing\|permission_handler_apple" ios/Podfile.lock` returned no matches
- Manager clarification incorporated: with SPM plugin integration enabled, missing pod entries for `printing`/`permission_handler_apple` in `Podfile.lock` are expected when those plugins are resolved via Flutter-generated Swift package.
- Requested build validation commands executed:
  - `flutter build ios --no-codesign` => pass
  - `flutter build macos` => fail

### Exact build output summary

`flutter build ios --no-codesign`:

- Result: PASS
- Notable output:
  - "Warning: Building for device with codesigning disabled."
  - "Xcode is fetching Swift Package Manager dependencies."
  - "The following plugins do not support Swift Package Manager for ios: flutter_local_notifications"
  - "✓ Built build/ios/iphoneos/Runner.app (38.9MB)"

`flutter build macos`:

- Result: FAIL
- Notable output/errors:
  - "The following plugins do not support Swift Package Manager for macos: flutter_local_notifications"
  - linker warnings in `flutter_local_notifications` target regarding macOS deployment versions vs `FlutterMacOS.framework` built for 12.0
  - `Unexpected object (Class with illegal cid, full-aot): ... package:flutter/src/widgets/_window_macos.dart ... _Rect@429353218`
  - `Dart snapshot generator failed with exit code -6`
  - `Target compile_macos_framework failed: Exception: AOT snapshotter exited with code -6-6`
  - `Command PhaseScriptExecution failed with a nonzero exit code`
  - `** BUILD FAILED **`

### Exact CocoaPods output from failing iOS resolution attempt

```
Deintegrating `Runner.xcodeproj`
Deleted 1 'Check Pods Manifest.lock' build phases.
Deleted 1 'Embed Pods Frameworks' build phases.
- Pods_Runner.framework
Deleted 1 'Check Pods Manifest.lock' build phases.
- Pods_RunnerTests.framework
- Pods-RunnerTests.debug.xcconfig
- Pods-RunnerTests.release.xcconfig
- Pods-RunnerTests.profile.xcconfig
Deleting Pod file references from project
- Pods-Runner.debug.xcconfig
- Pods-Runner.release.xcconfig
- Pods-Runner.profile.xcconfig
Deleted 1 empty `Frameworks` groups from project.
Removing `Pods` directory.

Project has been deintegrated. No traces of CocoaPods left in project.
Note: The workspace referencing the Pods project still remains.
Analyzing dependencies
Downloading dependencies
Installing Flutter (1.0.0)
Installing flutter_local_notifications (0.0.1)
Generating Pods project
Integrating client project
Pod installation complete! There are 2 dependencies from the Podfile and 2 total pods installed.

[!] CocoaPods did not set the base configuration of your project because your project already has a custom config set. In order for CocoaPods integration to work at all, please either set the base configurations of the target `Runner` to `Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig` or include the `Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig` in your build configuration (`Flutter/Release.xcconfig`).
```

### Required escalation diagnostics output (`pod repo update && pod deintegrate && pod install --verbose`)

```
Updating spec repo `trunk`
Deintegrating `Runner.xcodeproj`
Deleted 1 'Check Pods Manifest.lock' build phases.
Deleted 1 'Embed Pods Frameworks' build phases.
- Pods_Runner.framework
Deleted 1 'Check Pods Manifest.lock' build phases.
- Pods_RunnerTests.framework
- Pods-RunnerTests.debug.xcconfig
- Pods-RunnerTests.release.xcconfig
- Pods-RunnerTests.profile.xcconfig
Deleting Pod file references from project
- Pods-Runner.debug.xcconfig
- Pods-Runner.release.xcconfig
- Pods-Runner.profile.xcconfig
Deleted 1 empty `Frameworks` groups from project.
Removing `Pods` directory.

Project has been deintegrated. No traces of CocoaPods left in project.
Note: The workspace referencing the Pods project still remains.
  Preparing

Analyzing dependencies

Inspecting targets to integrate
  Using `ARCHS` setting to build architectures of target `Pods-Runner`: (``)
  Using `ARCHS` setting to build architectures of target `Pods-RunnerTests`: (``)

Finding Podfile changes
  - Flutter
  - flutter_local_notifications

Fetching external sources
-> Fetching podspec for `Flutter` from `Flutter`
-> Fetching podspec for `flutter_local_notifications` from `.symlinks/plugins/flutter_local_notifications/ios`

Resolving dependencies of `Podfile`
  CDN: trunk Relative path: CocoaPods-version.yml exists! Returning local because checking is only performed in repo update

Comparing resolved specification to the sandbox manifest
  A Flutter
  A flutter_local_notifications

Downloading dependencies

-> Installing Flutter (1.0.0)

-> Installing flutter_local_notifications (0.0.1)
  - Running pre install hooks
  - Running pre integrate hooks

Generating Pods project
  - Creating Pods project
  - Installing files into Pods project
    - Adding source files
    - Adding frameworks
    - Adding libraries
    - Adding resources
    - Adding development pod helper files
    - Linking headers
  - Installing Pod Targets
    - Installing target `Flutter` iOS 15.0
    - Installing target `flutter_local_notifications` iOS 11.0
  - Installing Aggregate Targets
    - Installing target `Pods-Runner` iOS 15.0
    - Installing target `Pods-RunnerTests` iOS 15.0
  - Generating deterministic UUIDs
  - Stabilizing target UUIDs
  - Running post install hooks
    - Podfile
  - Writing Xcode project file to `Pods/Pods.xcodeproj`
  Cleaning up sandbox directory

Integrating client project

Integrating target `Pods-Runner` (`Runner.xcodeproj` project)
  Adding Build Phase '[CP] Embed Pods Frameworks' to project.
  Adding Build Phase '[CP] Check Pods Manifest.lock' to project.

Integrating target `Pods-RunnerTests` (`Runner.xcodeproj` project)
  Adding Build Phase '[CP] Check Pods Manifest.lock' to project.
  - Running post integrate hooks
  - Writing Lockfile in `Podfile.lock`
  - Writing Manifest in `Pods/Manifest.lock`
  CDN: trunk Relative path: CocoaPods-version.yml exists! Returning local because checking is only performed in repo update

-> Pod installation complete! There are 2 dependencies from the Podfile and 2 total pods installed.

[!] CocoaPods did not set the base configuration of your project because your project already has a custom config set. In order for CocoaPods integration to work at all, please either set the base configurations of the target `Runner` to `Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig` or include the `Target Support Files/Pods-Runner/Pods-Runner.profile.xcconfig` in your build configuration (`Flutter/Release.xcconfig`).
```

### iOS Podfile.lock state after pod install

```
PODS:
  - Flutter (1.0.0)
  - flutter_local_notifications (0.0.1):
    - Flutter

DEPENDENCIES:
  - Flutter (from `Flutter`)
  - flutter_local_notifications (from `.symlinks/plugins/flutter_local_notifications/ios`)
```

## Deviations From Architect Plan

Manager-directed interpretation update superseded the earlier escalation assumption: 2-pod lockfile under SPM is expected behavior, not plugin loss.

## Blockers Encountered

- `flutter build macos` failed with Dart AOT snapshotter error (`exit code -6`) and build failure, so post-build manual smoke testing could not proceed under the user's "if both succeed" condition.

## Ready For QA

No. iOS build passed, but macOS build failed; Tier 2 manual smoke tests were therefore not executed.
