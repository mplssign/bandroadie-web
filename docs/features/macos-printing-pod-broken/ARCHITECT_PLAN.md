# ARCHITECT_PLAN.md — iOS/macOS native project sync verification

## 1. Feature Slug

`bug/macos-printing-pod-broken`

**Note:** Branch name retained to avoid churn; the true scope encompasses **both iOS and macOS**, as documented below.

---

## 2. Problem Summary

Original report observations on this branch were:

- iOS diffs showed missing printing and permission_handler_apple entries in ios/Podfile.lock, plus iOS deployment-target and Package.resolved changes.
- macOS diffs showed missing printing entry in macos/Podfile.lock, plus macOS deployment-target and Package.resolved changes.

Investigation determined no active defect exists in pod resolution for either platform. See Section 3 for the corrected diagnosis and evidence interpretation.

## Additional Context

- Follow-up issue tracked separately: `bug/macos-release-build-aot-crash`.
- The macOS release build failure is a pre-existing Flutter AOT snapshotter crash reproduced on clean `main`, unrelated to `printing`/`permission_handler_apple` pod resolution and out of scope for this feature.

---

## 3. Root Cause

**Diagnosed Cause:** No defect exists in `printing`/`permission_handler_apple` pod resolution on either iOS or macOS.

- **iOS:** Missing `printing` and `permission_handler_apple` entries in `ios/Podfile.lock` are expected when Flutter Swift Package Manager plugin routing is enabled (`swift_package_manager_enabled: {ios: true, macos: true}` in `.flutter-plugins-dependencies`). Plugins are correctly resolved through `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift` with existing Xcode project wiring.
- **macOS:** `Podfile`, `project.pbxproj`, and deployment-target-to-12.0 diffs are expected automatic Flutter 3.47.1 project migration output, not branch-specific defects.
- **macOS build failure context:** The observed `flutter build macos` failure is a separate, pre-existing Flutter framework AOT snapshotter crash reproduced on clean `main` and is out of scope here.

**Confidence Level:** `HIGH`

The original bug report premise (that plugin pod resolution is broken) does not hold on either platform based on verified external evidence.

---

## 4. Reference Docs Consulted

From `docs/reference/`:

- `docs/reference/general/` — checked for cross-platform conventions and configuration guardrails
- Domain folder `docs/reference/deployment/` (if present) — would document native toolchain constraints

No domain-specific reference docs for CocoaPods/SPM lifecycle found in workspace. This Architect plan supplements with empirical observations from git diffs and pubspec/podspec state.

---

## 5. Existing System Analysis

### Observed Current State — iOS

- `ios/Podfile.lock` removed `permission_handler_apple (9.3.0)` entirely:
  - pod entry
  - dependency line
  - external source block
  - spec checksum
- `ios/Podfile.lock` removed `printing (1.0.0)` entirely:
  - pod entry
  - dependency line
  - external source block
  - spec checksum
- `ios/Runner.xcodeproj/project.pbxproj` raised `IPHONEOS_DEPLOYMENT_TARGET` from `13.0` to `15.0` in all 3 build configs (Release, Debug, Profile).
- `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` bumped Firebase iOS SDK: `12.15.0` → `12.18.0` (revision hash `42e81d2...` → `346daa9...`).
- `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` also bumped Firebase identically.

### Observed Current State — macOS

- `macos/Podfile.lock` removed `printing (1.0.0)` entirely:
  - pod entry
  - dependency line
  - external source block
  - spec checksum
- `macos/Podfile` modified (target raised).
- `macos/Runner.xcodeproj/project.pbxproj` raised `MACOSX_DEPLOYMENT_TARGET` from `10.15` to `12.0` in all 3 build configs.
- `macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` bumped Firebase iOS SDK identically: `12.15.0` → `12.18.0`.
- `macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved` also bumped Firebase identically.

### Cross-Checks Against Active Dependency Graph

#### Printing (both platforms)

- `pubspec.yaml` declares `printing: ^5.13.4` ✓
- `pubspec.lock` includes `printing` package ✓
- iOS `GeneratedPluginRegistrant.swift` imports and registers `PrintingPlugin` ✓
- macOS `GeneratedPluginRegistrant.swift` imports and registers `PrintingPlugin` ✓
- `.flutter-plugins-dependencies` lists `printing` with iOS and macOS support ✓
- `ios/Flutter/ephemeral/.symlinks/plugins/printing/` exists and points to `printing-5.15.0` ✓
- `macos/Flutter/ephemeral/.symlinks/plugins/printing/` exists ✓
- `printing` iOS podspec exists (`s.ios.deployment_target = '8.0'`) — compatible with iOS 15.0 ✓
- `printing` macOS podspec exists (`s.osx.deployment_target = '10.11'`) — compatible with macOS 12.0 ✓

#### Permission Handler (iOS only)

- `pubspec.yaml` declares `permission_handler: ^11.3.1` ✓
- `pubspec.lock` includes `permission_handler` package ✓
- iOS `GeneratedPluginRegistrant.swift` imports and registers `PermissionHandlerPlugin` ✓
- `.flutter-plugins-dependencies` lists `permission_handler` with iOS support ✓
- `ios/Flutter/ephemeral/.symlinks/plugins/permission_handler_apple/` exists ✓
- `permission_handler_apple` iOS podspec exists (`s.ios.deployment_target = '12.0'`) — compatible with iOS 15.0 ✓
- Actively used: `lib/features/notifications/notification_permission_service.dart`, `lib/features/notifications/widgets/notification_settings_modal.dart`, `lib/features/bands/band_form_screen.dart`

### Practical Resolution Flow

Current native build chain for each plugin path:

1. Flutter dependency declarations (`pubspec*`) include plugin.
2. Flutter plugin tooling generates registrant + plugin symlinks per platform.
3. CocoaPods resolves plugin podspecs from symlink paths in platform's `Podfile`.
4. `Podfile.lock` should include each resolved plugin pod with valid spec checksum.

This flow describes normal expected resolution behavior, and no failure in this path was confirmed for this feature (see Section 3).

---

## 6. Proposed Solution

No code fix is required for this feature.

The generated native file diffs (`Podfile`, `Podfile.lock`, `project.pbxproj`, and `Package.resolved` on iOS/macOS) reflect routine Flutter 3.47.1 version-sync and deployment-target migration behavior. They can be handled in either of two acceptable ways:

1. Commit once as a housekeeping baseline sync.
2. Discard locally.

Either choice is operationally valid; the same generated changes will reappear on subsequent builds.

---

## 7. Database Impact

`not applicable`

- No migrations
- No RLS changes
- No RPC changes
- No trigger changes

---

## 8. Flutter Architecture Changes

No Dart architecture changes expected.

- State management: unaffected
- Widgets/UI logic: unaffected
- Repositories/services: unaffected

Potential generated-file refresh only if tooling regenerates plugin registrant artifacts (platform-specific, automatic).

---

## 9. Files to Create

- `docs/features/macos-printing-pod-broken/ARCHITECT_PLAN.md` (this document, overwrites previous macOS-only plan)

---

## 10. Files to Modify

Optional housekeeping sync file set. **All files in this table are uncommitted in working tree as of plan write:**

### iOS

| File                                                                             | What changes                                                       | Retention Decision                                                                                  |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| `ios/Podfile.lock`                                                               | Generated lockfile state from Flutter native project sync behavior | Retain if committing housekeeping sync; otherwise no action needed                                  |
| `ios/Runner.xcodeproj/project.pbxproj`                                           | Deployment target bump (13.0 → 15.0) in all build configs          | **Decide with Tony**: retain as part of optional housekeeping sync or discard                       |
| `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Firebase SDK bump (12.15.0 → 12.18.0) and other deps               | **Decide with Tony**: keep if it is part of intended toolchain upgrade; otherwise revert to 12.15.0 |
| `ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`                   | Firebase SDK bump (12.15.0 → 12.18.0) and other deps               | **Decide with Tony**: keep if it is part of intended toolchain upgrade; otherwise revert            |

### macOS

| File                                                                               | What changes                                                       | Retention Decision                                                                                  |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| `macos/Podfile.lock`                                                               | Generated lockfile state from Flutter native project sync behavior | Retain if committing housekeeping sync; otherwise no action needed                                  |
| `macos/Podfile`                                                                    | Deployment target and/or other platform settings                   | **Decide with Tony**: retain as part of optional housekeeping sync or discard                       |
| `macos/Runner.xcodeproj/project.pbxproj`                                           | Deployment target bump (10.15 → 12.0) in all build configs         | **Decide with Tony**: retain as part of optional housekeeping sync or discard                       |
| `macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Firebase SDK bump (12.15.0 → 12.18.0) and other deps               | **Decide with Tony**: keep if it is part of intended toolchain upgrade; otherwise revert to 12.15.0 |
| `macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved`                   | Firebase SDK bump (12.15.0 → 12.18.0) and other deps               | **Decide with Tony**: keep if it is part of intended toolchain upgrade; otherwise revert            |

---

## 11. Files Off-Limits

| File                       | Reason                                                                                                                |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `lib/**`                   | Issue scope is native-only; no Dart behavior changes intended (plugin registrants regenerate automatically if needed) |
| `android/**`               | Android does not use CocoaPods/SwiftPM; unaffected by this bug                                                        |
| `web/**`                   | Web does not use CocoaPods/SwiftPM; unaffected by this bug                                                            |
| `supabase/**`              | No backend/database involvement                                                                                       |
| `pubspec.yaml`             | `printing` and `permission_handler` dependencies are already present and should not be removed                        |
| `pubspec.lock`             | App dependency graph is already consistent with expected plugin presence                                              |
| `docs/agents/ARCHITECT.md` | Unrelated pre-existing change from a separate housekeeping fix; must not be touched or committed by this feature      |

---

## 12. System Impact Map

| System                                 | Impact     | Notes                                                            |
| -------------------------------------- | ---------- | ---------------------------------------------------------------- |
| Gigs                                   | unaffected | No gig logic depends on `printing` or `permission_handler`       |
| Rehearsals                             | unaffected | No rehearsal logic depends on `printing` or `permission_handler` |
| Setlists / Catalog                     | unaffected | No actual pod loss occurred; see Section 3                       |
| Financials                             | unaffected | No actual pod loss occurred; see Section 3                       |
| Members / RBAC                         | unaffected | No role/permission logic depends on native pods                  |
| Auth / Session                         | unaffected | Auth flow independent of CocoaPods                               |
| Notifications                          | unaffected | No actual pod loss occurred; see Section 3                       |
| Platform (iOS / Android / Web / macOS) | unaffected | No actual pod loss occurred on any platform; see Section 3       |

---

## 13. Regression Risk

`LOW`

Rationale:

- No functional code fix is required.
- No Dart application code changes are part of this feature.
- Remaining action is purely a repository hygiene decision: optionally commit already-generated Flutter native project sync files or discard them.
- The known macOS AOT build crash is tracked separately and does not increase risk for this feature scope.

---

## 14. Engineer Task Breakdown

1. Confirm with Tony whether to commit the current generated-file diffs as a single housekeeping commit (`chore: sync macOS/iOS project files to Flutter 3.47.1`) or discard them.
2. If committing, stage exactly the files already listed in the plan's Files to Modify section and nothing else.
3. No further remediation is required for this feature.

---

## 15. Verification Plan

### iOS

- `flutter build ios --no-codesign` is the relevant verification command.
- Status: already verified passing.

### macOS

- macOS build currently fails due to a known, separate Flutter framework AOT snapshotter crash.
- This failure reproduces on clean `main` and is independent of this feature.
- Do not gate completion of this feature on a macOS build pass.
- Track and resolve that build failure under `bug/macos-release-build-aot-crash`.

---

## 16. QA Regression Areas

Minimal QA scope:

1. Confirm flutter build ios --no-codesign still passes (already verified).
2. Confirm no app code changed in this feature scope.
3. No additional functional QA regression sweep is required for this feature because no functional code fix was made.

---

## 17. Rollout / Migration Strategy

- No backend rollout required.
- No functional rollout is required.
- If Tony chooses to keep the generated Flutter native project sync diffs, land them as a single housekeeping commit.
- If Tony chooses not to keep them, discard locally; they will regenerate identically on future builds.

---

## 18. Out of Scope

- Any Dart feature logic changes.
- Android native toolchain changes (Android does not use CocoaPods).
- Web native toolchain changes (Web does not use CocoaPods/SwiftPM).
- Notification system Dart or backend logic changes.
- Supabase schema/function/policy changes.
- Opportunistic dependency upgrades unrelated to the optional Flutter native housekeeping sync decision.
- Changes to `permission_handler` Android or Web support (this feature only verifies iOS/macOS native project sync behavior).

---

## Summary

Investigation found no defect in printing or permission_handler_apple pod resolution on either iOS or macOS. The observed iOS and macOS native diffs are routine Flutter 3.47.1 version-sync and project-migration artifacts, not feature breakage. A separate pre-existing macOS release build issue (Flutter AOT snapshotter crash) has been split out to bug/macos-release-build-aot-crash and is out of scope here. No code fix is required for this feature.
