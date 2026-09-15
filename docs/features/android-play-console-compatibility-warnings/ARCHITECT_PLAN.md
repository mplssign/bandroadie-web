# Architect Plan — bug/android-play-console-compatibility-warnings

## Feature Slug

`bug/android-play-console-compatibility-warnings`

## Feature Title

Resolve Google Play DEX optimization and edge-to-edge warnings

## Problem Summary

Google Play Console's Release dashboard for the current production Android bundle (version 26.9.14+26091401) reports three findings against the AAB. The product decision after the first architectural pass is to scope this bug to two of them and intentionally accept the third:

1. **"DEX code optimization is below our threshold"** — Play reports Obfuscation at 2% for the current release bundle. Play's threshold assumes an R8-minified release build; the AAB was shipped without minification, so Play measures effectively-zero obfuscation. **In scope.**
2. **"Edge-to-edge may not display for all users"** — recommendation triggered for apps targeting SDK 35 on Android 15 and later. The app does not opt into `SystemUiMode.edgeToEdge` nor render system bars transparently, so Android 15's enforced edge-to-edge composition can under-draw behind opaque bar backgrounds. **In scope.**
3. **"Remove resizability and orientation restrictions in your app to support large screen devices"** — Play detected `android:screenOrientation="portrait"` on `MainActivity`. **Out of scope, intentionally accepted.** BandRoadie is a portrait-only product on every form factor (phones, tablets, foldables, iPad). Both the manifest attribute on `.MainActivity` and the runtime `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` call in `lib/main.dart` must remain unchanged by this plan; the Play recommendation is treated as an accepted warning, not a defect.

The DEX finding and the edge-to-edge finding are both actionable code/config fixes on the release AAB. They ship together in the next production bundle after 26.9.14+26091401. The DEX finding also corroborates audit item 6.4 in [docs/reference/audits/CODEBASE_AUDIT.md](docs/reference/audits/CODEBASE_AUDIT.md).

## Root Cause

Two independent misconfigurations in the Android build and Flutter startup path:

- **DEX / Obfuscation at 2% — HIGH confidence.** [android/app/build.gradle.kts](android/app/build.gradle.kts) lines 52–57 declare `release { isMinifyEnabled = false; isShrinkResources = false }` and never call `proguardFiles(...)`. R8 is therefore disabled, and the existing [android/app/proguard-rules.pro](android/app/proguard-rules.pro) is not wired into any build type. Play's DEX scanner sees ~zero obfuscation, hence the 2% reading.
- **Edge-to-edge not opted in — HIGH confidence.** [lib/main.dart](lib/main.dart) never calls `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` and never sets `SystemChrome.setSystemUIOverlayStyle(...)` with transparent system bars. A repository-wide search across `lib/**/*.dart` for `setSystemUIMode`, `SystemUiOverlayStyle`, `edgeToEdge`, and `edge_to_edge` returns only one usage — a per-screen `SystemUiOverlayStyle.light` inside `lib/app/theme/event_editor_theme.dart` — and none in startup. The app already uses `SafeArea` extensively (~46 files) so insets are already handled at the widget layer; only the top-level opt-in and the transparent-bar overlay style are missing.

Confidence across both: **HIGH**. Both root causes are directly readable from the source; nothing requires a running instance to confirm.

The large-screen orientation finding also has a directly-readable root cause (`android:screenOrientation="portrait"` at [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) line 20; `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` at [lib/main.dart](lib/main.dart) line 45), but that root cause is preserved intentionally per the product decision and is not addressed by this plan.

## Existing System Analysis

**Flutter startup (fixed init order — [docs/reference/general/RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md)):**

```
1. WidgetsFlutterBinding.ensureInitialized()
2. URL strategy (web only)
3. Portrait orientation lock
4. AppVersionService.init()
5. validateSupabaseConfig()
5.5 Purge persisted anonymous demo session   ← native-only
6. Supabase.initialize()
7. Firebase.initializeApp()                  ← iOS/Android only
8. DeepLinkService setup
9. runApp()
```

This plan inserts exactly one new step — an edge-to-edge display mode + transparent system UI overlay style — between step 2 (URL strategy) and step 3 (Portrait orientation lock). Step 3 itself and every step after it stay literally unchanged. The insertion is a logged decision in [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md) and reflected in both [docs/reference/general/RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md) and [docs/reference/architecture/architecture.md](docs/reference/architecture/architecture.md) (which carry the same init-order listing).

**Android release build ([android/app/build.gradle.kts](android/app/build.gradle.kts)):** Signing config, Java 17 compileOptions, core library desugaring, and `compileSdk`/`targetSdk` inherited from Flutter's Gradle plugin. Release buildType currently opts out of both R8 and resource shrinking and never wires the `proguard-rules.pro` file. Debug buildType is unspecified (Gradle defaults apply).

**Existing ProGuard rules ([android/app/proguard-rules.pro](android/app/proguard-rules.pro)):** Keeps `io.flutter.**`, `io.flutter.plugins.**`, `com.google.**`, Flutter's deferred-components / Play Store split classes, and dontwarn entries for `org.conscrypt.**`, `org.bouncycastle.**`, `org.openjsse.**`, and `com.google.android.play.core.**`. No `-keepattributes SourceFile,LineNumberTable`, so once R8 is enabled crash traces will not include line numbers unless we add them.

**AndroidManifest.xml:** `.MainActivity` declares `android:screenOrientation="portrait"` (line 20) and `android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"` (line 21) — Flutter's standard set. Both attributes are preserved by this plan. The `configChanges` attribute tells Android to hand config changes to the activity rather than recreate it; it is independent of `screenOrientation` and remains correct as-is.

**Widget layer:** `SafeArea` and `MediaQuery.viewPadding` are already used across auth, home, calendar, setlist, band, drawer, and bottom-sheet surfaces — including the app bars in [home_app_bar.dart](lib/features/home/widgets/home_app_bar.dart), [calendar_app_bar.dart](lib/features/calendar/widgets/calendar_app_bar.dart), [setlists_app_bar.dart](lib/features/setlists/widgets/setlists_app_bar.dart), the bottom nav in [animated_bottom_nav_bar.dart](lib/features/home/widgets/animated_bottom_nav_bar.dart), and every bottom-sheet call site. This means turning edge-to-edge on will not push content under system bars; the SafeAreas already reserve space. **No widget-layer changes are required for edge-to-edge to render correctly.**

**iOS Info.plist:** `UISupportedInterfaceOrientations` (iPhone) allows portrait only. `UISupportedInterfaceOrientations~ipad` (iPad) declares all four orientations, but the runtime `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` call in `main.dart` overrides that on iPad — an accepted consequence of the product decision to remain portrait-only on all form factors. No plist change is proposed or wanted; iPad continues to run portrait-only under the runtime lock exactly as today.

## Proposed Solution

Two minimal, direct fixes shipping in the same release bundle.

**1. Enable R8 with existing rules and preserved line numbers.** In [android/app/build.gradle.kts](android/app/build.gradle.kts), set the release buildType to `isMinifyEnabled = true`, `isShrinkResources = true`, and add `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")`. In [android/app/proguard-rules.pro](android/app/proguard-rules.pro), add `-keepattributes SourceFile,LineNumberTable` and `-renamesourcefileattribute SourceFile` so Play Console crash traces stay readable. Do not add new keep rules speculatively — Flutter plugins in this app's dependency graph (Firebase, `flutter_local_notifications`, `share_plus`, `file_picker`, `path_provider`, `permission_handler`, `printing`, `image_picker`, `url_launcher`, `app_links`) ship consumer ProGuard rules via their AARs. The existing keep rules for `io.flutter.**`, `io.flutter.plugins.**`, `com.google.**`, and Play Core deferred-components already cover the additional Flutter-side reflection surface. If the first minified build surfaces a specific plugin needing a keep rule, add exactly that rule then — a speculative sweep is out of scope.

**2. Opt into edge-to-edge with transparent system bars.** In [lib/main.dart](lib/main.dart), immediately after `WidgetsFlutterBinding.ensureInitialized()`, after `TimezoneHelper.initialize()`, and after the web-only `if (kIsWeb) { usePathUrlStrategy(); }` block, but **before** the existing `await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);` call, add:

```dart
await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarIconBrightness: Brightness.light,
));
```

Both calls are cross-platform-safe: `setEnabledSystemUIMode` and the navigation-bar fields of `SystemUiOverlayStyle` are Android-only in effect and no-op on iOS/macOS/web; the status-bar brightness field applies to iOS as well and matches the app's dark-mode-only design already documented in [.github/copilot-instructions.md](.github/copilot-instructions.md). Combined with the existing wall-to-wall `SafeArea` usage, this satisfies Android 15's edge-to-edge expectations without any widget-layer changes.

**Not changed by this plan.** The following code and config remain byte-for-byte identical to the current production release:

- The `android:screenOrientation="portrait"` attribute on `.MainActivity` in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml).
- The `await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);` call in [lib/main.dart](lib/main.dart).
- Every other attribute, intent-filter, meta-data element, and `<queries>` block in the manifest.
- Every other statement in `main()`.

The Google Play large-screen recommendation for the portrait manifest attribute is intentionally accepted and remains present on the next release. This is not a regression; it is the product decision recorded in this plan.

## Database Impact

n/a

## Flutter Architecture Changes

No new providers, controllers, repositories, or dependencies. Init order gains exactly one new step (edge-to-edge display mode + transparent system UI overlay) inserted between the existing URL-strategy step and the existing portrait-orientation-lock step — logged as a decision per the plan below. Riverpod graph unchanged. Deep-link handling unchanged. Auth (PKCE) flow unchanged.

## Files to Create

None.

## Files to Modify

| File | Change |
| --- | --- |
| [android/app/build.gradle.kts](android/app/build.gradle.kts) | In `buildTypes.release` (currently lines 53–57), change `isMinifyEnabled = false` → `isMinifyEnabled = true`, change `isShrinkResources = false` → `isShrinkResources = true`, and add exactly one new line inside the block: `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")`. Do not add or reorder any other block, plugin, dependency, or signingConfig. |
| [android/app/proguard-rules.pro](android/app/proguard-rules.pro) | Append two lines at the end of the file: `-keepattributes SourceFile,LineNumberTable` and `-renamesourcefileattribute SourceFile`. Do not modify or remove any existing rule. |
| [lib/main.dart](lib/main.dart) | Exactly one edit, inside `Future<void> main()`. After `WidgetsFlutterBinding.ensureInitialized();`, after `TimezoneHelper.initialize();`, and after the `if (kIsWeb) { usePathUrlStrategy(); }` block, and **immediately before** the existing `await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);` line, insert one `await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);` call followed by one `SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent, systemNavigationBarDividerColor: Colors.transparent, statusBarIconBrightness: Brightness.light, systemNavigationBarIconBrightness: Brightness.light,));` call. `Colors.transparent` is from `package:flutter/material.dart`, already imported; `SystemUiMode` / `SystemUiOverlayStyle` / `Brightness` are from `package:flutter/services.dart`, already imported. Do not add any other logic anywhere in `main.dart`. Do not touch the existing `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` call — it remains verbatim as init step 4 after the insertion. Do not touch any other function, class, or the existing Firebase/Supabase/DeepLinkService/DemoSessionService blocks. |
| [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md) | Append one new decision entry after the last existing decision, following the file's own template. Title: "Android edge-to-edge display mode on startup". Feature: `bug/android-play-console-compatibility-warnings`. Status: Active. Context section: cites the two in-scope Play Console findings (DEX code optimization; edge-to-edge on Android 15+) and explicitly notes the large-screen orientation recommendation is an accepted warning, not part of the fix. Decision section: inserts `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` + transparent `SystemUiOverlayStyle` as new init step 3 (between URL strategy and the existing portrait orientation lock, which becomes step 4). Rationale section: Play Console recommendation for SDK 35 / Android 15+; existing `SafeArea` coverage makes edge-to-edge safe with no widget-layer changes; dark-mode-only design already matches `Brightness.light` bar icons. Constraints Imposed: any future addition of a non-edge-to-edge system UI mode must supersede this decision; the existing portrait orientation lock is unaffected by this decision and remains in force on all form factors. Rollback Plan: revert the two `SystemChrome` calls added to `main.dart` and remove the new step 3 entries from `RUNTIME_CONFIG.md` and `architecture.md`. |
| [docs/reference/general/RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md) | Update the "App Initialization Order" numbered list (currently lines 12–22) by inserting one new step between the current step 2 and step 3 and renumbering the rest. New listing (with the existing `5.5` sub-step preserved and renumbered to `6.5`): `1. WidgetsFlutterBinding.ensureInitialized()` / `2. URL strategy (web only)` / `3. Edge-to-edge display mode + transparent system UI overlay` / `4. Portrait orientation lock` / `5. AppVersionService.init()` / `6. validateSupabaseConfig()` / `6.5 Purge persisted anonymous demo session` / `7. Supabase.initialize()` / `8. Firebase.initializeApp()` / `9. DeepLinkService setup` / `10. runApp()`. Do not change any other content in the file. |
| [docs/reference/architecture/architecture.md](docs/reference/architecture/architecture.md) | Update the "App Initialization Order" numbered list (currently lines 51–59) with the same insertion and renumbering — this file has no `5.5` sub-step, so the resulting listing is: `1. WidgetsFlutterBinding.ensureInitialized()` / `2. URL strategy (web only)` / `3. Edge-to-edge display mode + transparent system UI overlay` / `4. Portrait orientation lock` / `5. AppVersionService.init()` / `6. validateSupabaseConfig()` / `7. Supabase.initialize()` / `8. Firebase.initializeApp()` / `9. DeepLinkService setup` / `10. runApp()`. Do not change any other content in the file. |

## Files Off-Limits

| File | Why off-limits |
| --- | --- |
| [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) | Portrait-only behavior is an intentional product decision. The `android:screenOrientation="portrait"` attribute on `.MainActivity` remains verbatim, and the corresponding Play Console large-screen recommendation is an accepted warning. Every other attribute, intent-filter, meta-data element, and `<queries>` block in this file is also unchanged. Any diff against this file fails the plan. |
| [ios/Runner/Info.plist](ios/Runner/Info.plist) | iPhone portrait-only (`UISupportedInterfaceOrientations`) and iPad's four-orientation declaration (`UISupportedInterfaceOrientations~ipad`) are both preserved. The runtime portrait lock in `main.dart` continues to constrain iPad to portrait — an accepted consequence of the portrait-only product decision. |
| `macos/Runner/*`, `web/*`, `vercel.json` | Not affected. Edge-to-edge is an Android/iOS concern; `SystemChrome` calls are no-ops on macOS and web. |
| [android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt](android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt) | Empty `FlutterActivity` subclass. Edge-to-edge is set from Dart via `SystemChrome`. No native code needed. |
| [android/app/src/main/res/values/styles.xml](android/app/src/main/res/values/styles.xml), [android/app/src/main/res/values-night/styles.xml](android/app/src/main/res/values-night/styles.xml) | LaunchTheme/NormalTheme drive only the splash-screen background. System bar transparency is controlled by `SystemUiOverlayStyle` from Dart. Adding `windowLightStatusBar` / `windowTranslucentStatus` here would fight the SystemChrome call and is unnecessary. |
| [android/build.gradle.kts](android/build.gradle.kts), [android/settings.gradle.kts](android/settings.gradle.kts), [android/gradle.properties](android/gradle.properties), [android/gradle/wrapper/*](android/gradle/wrapper) | Top-level Gradle config, plugin versions, and wrapper are not the source of either in-scope finding. R8 is enabled per-buildType inside `android/app/build.gradle.kts`. |
| Every Dart file in `lib/` other than [lib/main.dart](lib/main.dart) | The existing `SafeArea` / `MediaQuery.viewPadding` usage across ~46 files already handles system-bar insets correctly for edge-to-edge. No widget-layer changes are required. In particular, the existing per-screen `SystemUiOverlayStyle.light` inside [lib/app/theme/event_editor_theme.dart](lib/app/theme/event_editor_theme.dart) is left alone. |
| [supabase/**](supabase), [database/**](database), any RPC/migration/Edge Function | No DB, RLS, RPC, or edge-function change. |
| [pubspec.yaml](pubspec.yaml), [pubspec.lock](pubspec.lock) | No new or upgraded dependencies. |
| [android/key.properties](android/key.properties), signing configs | Signing is unrelated to either in-scope finding. |
| [bandroadie_fresh/**](bandroadie_fresh), [BandRoadie/**](BandRoadie), [build/**](build) | Not part of the production Flutter app. |

## Change Budget

| Metric | Expected |
| --- | --- |
| Files created | 0 |
| Files modified | 6 |
| Net line delta — [android/app/build.gradle.kts](android/app/build.gradle.kts) | +1 (add one `proguardFiles(...)` line; two existing lines flip `false`→`true`) |
| Net line delta — [android/app/proguard-rules.pro](android/app/proguard-rules.pro) | +2 |
| Net line delta — [lib/main.dart](lib/main.dart) | approximately +8 (one `await SystemChrome.setEnabledSystemUIMode(...);` statement + one `SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(...));` block spanning 7 lines; the existing portrait orientation lock line is untouched) |
| Net line delta — [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md) | approximately +35 (one new decision entry following the file's template) |
| Net line delta — [docs/reference/general/RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md) | +1 (insert one new numbered step; renumber trailing steps in-place) |
| Net line delta — [docs/reference/architecture/architecture.md](docs/reference/architecture/architecture.md) | +1 (same insertion and renumbering) |
| Net line delta — [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) | 0 (file is off-limits) |
| New public classes / methods | 0 |
| New dependencies | 0 |
| New migrations / edge functions | 0 |
| New Riverpod providers / notifiers | 0 |

## System Impact Map

| System | Impact |
| --- | --- |
| Gigs | Unaffected — no repository, controller, model, screen, or widget in `lib/features/gigs/` is touched. |
| Rehearsals | Unaffected — same. |
| Setlists | Unaffected — no change to setlist repository, controller, screens, or the drag-reorder / inline-edit surfaces. |
| Members | Unaffected. |
| Auth | Unaffected. PKCE flow, magic-link Supabase config, `DemoSessionService` purge, and `DeepLinkService` initialization all run at unchanged positions in the init order (they simply now run after the new display-mode step). No auth token, no session, no OTP flow touched. |
| Routing | Unaffected — no changes to `AuthGate`, `BandRoadieApp`, `LandingPage`, `AuthConfirmScreen`, or `InviteScreen`. |
| Notifications | Unaffected — no change to Firebase Messaging init, notification channels, or FCM token flow. |
| Deep links | Unaffected — `DeepLinkService.initialize()` and both the `bandroadie://login-callback` custom-scheme intent-filter and the `bandroadie.com` / `app.bandroadie.com` App Links intent-filter in the manifest are preserved verbatim. The manifest is not edited at all by this plan. |
| Init order | **Changed intentionally by exactly one insertion.** New step 3 is "Edge-to-edge display mode + transparent system UI overlay"; the previous step 3 ("Portrait orientation lock") becomes step 4; every subsequent step shifts by +1. Logged as a new decision in AI_DECISIONS.md and reflected in RUNTIME_CONFIG.md and architecture.md. |
| Android platform | Both in-scope fixes apply. Release AAB gains R8 minification + resource shrinking; edge-to-edge composition is opt-in with transparent system bars. Portrait-only orientation behavior is unchanged. |
| iOS iPhone platform | Unaffected in practice. `setSystemUIOverlayStyle` `statusBarIconBrightness: Brightness.light` matches the existing dark-only theme. `SystemUiMode.edgeToEdge` is a no-op on iOS. iPhone stays portrait via Info.plist. |
| iOS iPad platform | Unaffected. Portrait-only runtime lock in `main.dart` remains in place; iPad continues to run portrait-only exactly as today. |
| macOS platform | Unaffected — `SystemChrome` calls are no-ops on macOS. |
| Web platform | Unaffected — `SystemChrome` calls are no-ops on web; `usePathUrlStrategy()` (step 2, web-only) runs before the new display-mode step. |
| Google Play Console (post-release) | DEX code optimization finding and edge-to-edge finding are expected to clear on the next AAB. The large-screen orientation recommendation is expected to remain — an intentionally accepted warning, not a regression. |

## Regression Risk

**MEDIUM**, driven entirely by the R8 change; edge-to-edge is LOW.

- Enabling R8 minification + resource shrinking on a codebase that has never been minified before can strip classes reflected at runtime (Firebase, Kotlin metadata, JSON serialization). The existing `proguard-rules.pro` covers Flutter, Play Core deferred-components, and Google/Supabase package roots. Every remaining Android plugin in `pubspec.yaml` (`firebase_core`, `firebase_messaging`, `flutter_local_notifications`, `share_plus`, `file_picker`, `path_provider`, `package_info_plus`, `url_launcher`, `image_picker`, `permission_handler`, `printing`, `app_links`) ships consumer ProGuard rules via its AAR, which R8 picks up automatically. QA cannot exercise the built AAB on a running device, so this risk lands on the owner-run punch list — the same posture [docs/reference/audits/CODEBASE_AUDIT.md](docs/reference/audits/CODEBASE_AUDIT.md) item 6.4 has recorded since it was written.
- Edge-to-edge opt-in is LOW risk because `SafeArea` and `MediaQuery.viewPadding` are already used at every top-level scaffold, app bar, bottom nav, and bottom sheet in the app.

Auth, session, routing, DB, RLS, deep links, portrait orientation behavior, and every non-Android platform are untouched. No new dependency, no new RPC, no new migration.

## Engineer Task Breakdown

1. In [android/app/build.gradle.kts](android/app/build.gradle.kts), inside `buildTypes.release`: flip `isMinifyEnabled = false` → `isMinifyEnabled = true`, flip `isShrinkResources = false` → `isShrinkResources = true`, and add one new line `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")` inside the same block.
2. Append two lines to the end of [android/app/proguard-rules.pro](android/app/proguard-rules.pro): `-keepattributes SourceFile,LineNumberTable` and `-renamesourcefileattribute SourceFile`.
3. In [lib/main.dart](lib/main.dart) inside `Future<void> main()`, immediately before the existing `await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);` line, insert one `await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);` call followed by a single `SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent, systemNavigationBarDividerColor: Colors.transparent, statusBarIconBrightness: Brightness.light, systemNavigationBarIconBrightness: Brightness.light,));` call. Use `Colors.transparent` from `package:flutter/material.dart` (already imported) and `SystemUiMode` / `SystemUiOverlayStyle` / `Brightness` from `package:flutter/services.dart` (already imported). Do not add any other logic. **Do not remove, replace, or reorder the existing `await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);` line — it stays verbatim, immediately after the new insertion.**
4. Add a new decision entry to [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md) following the file's template, with the content specified in the Files to Modify table row for that file. Preserve the file's existing header and every prior decision verbatim.
5. Update the "App Initialization Order" numbered list in [docs/reference/general/RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md) by inserting new step 3 ("Edge-to-edge display mode + transparent system UI overlay") and renumbering the trailing steps as specified in the Files to Modify table row. Change only that list.
6. Update the identical "App Initialization Order" numbered list in [docs/reference/architecture/architecture.md](docs/reference/architecture/architecture.md) with the same insertion and renumbering. Change only that list.

Tasks 1 and 2 are independent of task 3 and can be done in either order. Tasks 4–6 depend on tasks 1–3 being decided but not on them being written — they can be authored in parallel.

## Verification Plan

**Tier 1 — pre-deploy, mechanically executable by QA (no running app):**

1. `flutter analyze` on the feature branch — no new warnings, no new errors introduced. Existing warnings/errors are unchanged in count and location.
2. `flutter test` — headless test suite passes with the same green count as `main`. No new test file is added or required for this change; the fix is Gradle-config, ProGuard-rules, startup-sequence, and documentation work with no new pure-function or widget-logic surface to unit-test.
3. Static review of [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml): confirm the file is byte-for-byte identical to `main`. Command: `GIT_OPTIONAL_LOCKS=0 git diff main -- android/app/src/main/AndroidManifest.xml` returns empty. Additionally, `grep -n 'screenOrientation' android/app/src/main/AndroidManifest.xml` must still return the single existing `android:screenOrientation="portrait"` line — its continued presence is an intentional product decision and its removal would fail the plan.
4. Static review of [android/app/build.gradle.kts](android/app/build.gradle.kts): confirm the `buildTypes.release` block contains all three of `isMinifyEnabled = true`, `isShrinkResources = true`, and a `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")` call. Command: `grep -nE 'isMinifyEnabled|isShrinkResources|proguardFiles' android/app/build.gradle.kts` returns exactly those three lines with the expected values.
5. Static review of [android/app/proguard-rules.pro](android/app/proguard-rules.pro): confirm the file ends with the two new lines `-keepattributes SourceFile,LineNumberTable` and `-renamesourcefileattribute SourceFile`, and every prior rule remains unchanged.
6. Static review of [lib/main.dart](lib/main.dart): confirm exactly one `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` call, exactly one `SystemChrome.setSystemUIOverlayStyle` call at startup with all bar-color fields set to `Colors.transparent` and both icon-brightness fields set to `Brightness.light`, and that the existing `await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);` line is present, unchanged, immediately after the new insertion. Confirm no other `SystemChrome.setPreferredOrientations` call exists anywhere in `lib/` (there was exactly one before this change; there must still be exactly one).
7. Static review of [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md): confirm a new decision entry exists with feature slug `bug/android-play-console-compatibility-warnings`, status `Active`, covering the edge-to-edge init-order insertion and explicitly noting that the portrait orientation lock is unaffected.
8. Static review of [docs/reference/general/RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md) and [docs/reference/architecture/architecture.md](docs/reference/architecture/architecture.md): confirm both init-order lists include the new "Edge-to-edge display mode + transparent system UI overlay" step as step 3, the existing "Portrait orientation lock" step is renumbered to step 4, and the trailing steps are renumbered correctly in both files (see the exact orderings in the Files to Modify table rows).

Any Tier 1 check failing blocks approval.

**Tier 2 — post-deploy, mechanically executable by QA:** n/a. No RPC, migration, or edge function is added; there is nothing post-deploy for QA to verify without a running app.

**Owner-run punch list (Tony, at PR-test or release time — not a QA gate):**

1. From the feature branch, build a release AAB: `flutter build appbundle --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`. Expected: build succeeds; R8 runs (visible in Gradle log as `:app:minifyReleaseWithR8` and `:app:shrinkReleaseRes`); no `Missing class` R8 errors.
2. Install the built AAB on a physical Android phone running Android 15 (API 35) if available, otherwise the newest Android device on hand. Launch the app cold. Expected: login screen renders; status bar and gesture-bar background are transparent over the app background; no content is clipped by system bars.
3. On the same phone, rotate the device to landscape. Expected: the app remains in portrait — portrait-only behavior is intentional and preserved on this release.
4. Upload the AAB to the Play Console **Internal testing** track under the same package name. Open the Release dashboard for the new bundle. Expected: the DEX code optimization finding and the edge-to-edge finding from version 26.9.14+26091401 are both absent from the new bundle's dashboard. The large-screen orientation recommendation may still appear — this is expected and intentionally accepted, not a regression.
5. Launch on iPhone simulator (any recent model). Expected: portrait-only, no behavior change vs current production.
6. Launch on iPad simulator (any recent model). Expected: portrait-only, no behavior change vs current production (the runtime portrait lock continues to constrain iPad).

## QA Regression Areas

- Auth surfaces ([login_screen.dart](lib/features/auth/login_screen.dart), [auth_confirm_screen.dart](lib/features/auth/auth_confirm_screen.dart), [invite_screen.dart](lib/features/auth/invite_screen.dart)) — verify no imports or logic changes leaked in via the `main.dart` edit.
- App shell top-level app bars ([home_app_bar.dart](lib/features/home/widgets/home_app_bar.dart), [calendar_app_bar.dart](lib/features/calendar/widgets/calendar_app_bar.dart), [setlists_app_bar.dart](lib/features/setlists/widgets/setlists_app_bar.dart), [back_only_app_bar.dart](lib/features/setlists/widgets/back_only_app_bar.dart)) — no code change expected in this feature; verify the diff does not touch them.
- Bottom sheet / drawer surfaces — no code change expected; verify diff.
- Deep-link handling ([DeepLinkService](lib/app/services/deep_link_service.dart), custom scheme + App Links intent-filters in the manifest) — verify [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml) has an empty diff against `main`. Every intent-filter, `<data>` child, meta-data element, `<queries>` block, and the `android:screenOrientation="portrait"` attribute on `.MainActivity` must be byte-for-byte unchanged.
- Existing per-screen system UI overlay in [lib/app/theme/event_editor_theme.dart](lib/app/theme/event_editor_theme.dart) — no code change expected; verify diff.

## Rollout Strategy

Single Android release. Ship both in-scope fixes together in the next production AAB after 26.9.14+26091401.

- No feature flag needed — the changes are startup-time and Gradle-config only.
- No Supabase migration, no RLS change, no edge-function deployment, no client-side sync required.
- Portrait-only behavior is unchanged on every platform, so there is no orientation-related user-visible behavior change on this release.
- Post-release monitoring: watch Play Console vitals (ANRs, crashes, install failures) and Sentry / Firebase Crashlytics **if configured** (per audit item 7.1 it is not yet — post-release monitoring is best-effort via Play Console only until then).
- If a post-release regression is traced to R8, revert **only** the Gradle change (flip `isMinifyEnabled` and `isShrinkResources` back to `false`, remove the `proguardFiles(...)` line) and ship a hotfix bundle; leave the edge-to-edge fix in place — it is independent.
- If a post-release regression is traced to edge-to-edge (content under a system bar somewhere), the fix is a per-screen `SafeArea` addition rather than reverting the startup change. Full rollback of edge-to-edge is per the AI_DECISIONS entry's Rollback Plan.

## Out of Scope

- **Removing the AndroidManifest `android:screenOrientation="portrait"` attribute on `.MainActivity`.** Explicitly reversed from the first architectural pass. Portrait-only is a product decision.
- **Making the runtime `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` call adaptive to screen size or device class.** Same reversal. The unconditional portrait lock remains in force on all form factors.
- **Any change to iOS Info.plist orientation declarations.** iPhone stays portrait; iPad's four-orientation plist entry is retained but continues to be overridden by the runtime portrait lock, matching the portrait-only product decision.
- Any landscape-specific UI polish or dedicated tablet layouts.
- Adding crash reporting (Sentry / Crashlytics Android). Audit item 7.1 tracks this separately; enabling R8 with `-keepattributes SourceFile,LineNumberTable` prepares crash traces for whichever tool lands later, but wiring the tool itself is separate work.
- Broadening ProGuard keep rules speculatively. Only rules proven necessary by an actual R8 build failure should be added, and that would be a follow-up bug rather than part of this plan.
- Any change to Supabase config, RLS policies, RPC functions, or edge functions.
- Any change to Firebase Messaging channel setup, APNS, or notification payload handling.
- Any change to `pubspec.yaml` dependencies or `pubspec.lock`.
- Any refactor of `main.dart` beyond the single insertion specified. The current structure (long linear `main()`) is preserved intentionally.
- Any change to the marketing-vs-app host detection, `vercel.json`, or the web build pipeline.
- Any change to iOS or macOS build config, entitlements, or code signing.
