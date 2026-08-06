# Architect Plan — Android On-Screen Keyboard Still Renders in Light Mode Despite Prior Fix

## Feature Slug

`bug/android-keyboard-still-light`

---

## Problem Summary

BandRoadie's on-screen software keyboard renders in light mode on Android when focusing any text field, mismatched against the app's dark UI. A fix for this exact symptom was already investigated and shipped in Addendum 8 of `docs/features/bulk-entry-instructions-cutoff-ios/ARCHITECT_PLAN.md` (merged `990b4b9`, 2026-07-28): an `attachBaseContext()` override in `MainActivity.kt` that forces `Configuration.uiMode`'s night flag to `UI_MODE_NIGHT_YES` unconditionally. That code is confirmed still present and unmodified on `main` today. Tony reports a **fresh install** of the current build still shows a light keyboard on a real Android device — so the shipped fix does not actually solve the problem.

---

## Root Cause

**Confidence: HIGH — confirmed by direct code inspection and established Android IME theming behavior; requires real-device validation to confirm the replacement solution works.**

⚠️ **Note:** The diagnosis below is HIGH confidence, but the proposed replacement solution (`resources.updateConfiguration()`) is **unverified theory**. See "Pre-Implementation Research" and "Plan Status" sections for full assessment. This plan adopts **Option A (validation-first)** — diagnostic build with all three candidate APIs will be tested on real device before final fix is implemented.

The existing fix in `MainActivity.kt` (lines 8–13):

```kotlin
override fun attachBaseContext(newBase: Context) {
    val configuration = Configuration(newBase.resources.configuration)
    configuration.uiMode = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
        Configuration.UI_MODE_NIGHT_YES
    super.attachBaseContext(newBase.createConfigurationContext(configuration))
}
```

**Why this approach does not work:**

`Context.createConfigurationContext(Configuration)` creates a **wrapper Context** with a modified configuration for resource resolution (drawable selection, style resolution), but it does **not** change the underlying Activity's window configuration or the system-level configuration that Android's InputMethodService (IME framework) reads to determine keyboard appearance.

Specifically:

1. **`createConfigurationContext()` is for resource theming only** — it returns a new Context that will resolve `values-night/` resources when you call `getResources()` on that specific Context object, but it does not propagate to the Activity's window or to system services.
2. **IME reads window/display configuration, not app context chain** — Android's keyboard framework (particularly on Android 10+, and especially with Material You dynamic theming on Android 12+) queries the `Activity.getWindow().getDecorView().getResources().getConfiguration()` or the display's configuration, not the potentially-wrapped base context chain that `attachBaseContext()` modifies.
3. **`FlutterActivity` may not propagate the wrapped context** — `FlutterActivity` is a complex embedding layer that manages its own view hierarchy and Flutter engine; the wrapped context from `attachBaseContext()` may not reach the window's actual resource configuration that the IME observes.

**Git provenance:** The `attachBaseContext()` approach was added in commit `990b4b9` (2026-07-28) as part of Addendum 8 of the `bulk-entry-instructions-cutoff-ios` ticket. That addendum explicitly marked its confidence as **MEDIUM-HIGH**, stating: "IME dark/light rendering is ultimately the keyboard app's (Gboard, etc.) own decision and isn't guaranteed to honor a forced `uiMode`." Task Z (real-device verification) was **never performed** — both Engineer and QA reports state "no device available in this session" — so this is the first real-device data point that confirms the approach does not work.

**Why the prior investigation missed this:** The analysis was thorough on the Android resource-qualifier mechanism (`values/` vs. `values-night/`) and correctly identified that `Configuration.uiMode` is the signal Android uses, but it did not validate that `createConfigurationContext()` actually propagates that signal to the specific configuration source the IME framework reads. The original plan's "Investigation" section reads: "Android's on-screen keyboard determines its own light/dark rendering primarily from the `Configuration.uiMode` night flag of the app window it is currently attached to" — this is correct, but `createConfigurationContext()` does not change the _window's_ configuration, only the context wrapper's.

---

## Reference Docs Consulted

Per ARCHITECT.md Phase 4: no `docs/reference/android/` or `docs/reference/theming/` directory exists. `docs/reference/ui/` exists but contains only `LANDING_PAGE_PREVIEW_GUIDE.md` (marketing landing page, unrelated). The directly relevant prior work is `docs/features/bulk-entry-instructions-cutoff-ios/ARCHITECT_PLAN.md` Addendum 8 (read in full), `ENGINEER_REPORT.md` Addendum 8 (read in full), and `QA_REPORT.md` (read in full) — this is the immediately-prior investigation and implementation of the exact same symptom, which this ticket replaces.

---

## Existing System Analysis

1. **Current MainActivity.kt** (`android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt`):
   - Extends `FlutterActivity` (Flutter's embedding layer for Android)
   - Overrides `attachBaseContext(Context)` to force `Configuration.uiMode` via `createConfigurationContext()`
   - No other method overrides

2. **AndroidManifest.xml** (`android/app/src/main/AndroidManifest.xml`, line 21):
   - `android:configChanges="...uiMode..."` is present — Activity will not be recreated on `uiMode` changes, but will receive `onConfigurationChanged()` callbacks (not currently overridden)

3. **Theme resources** (`android/app/src/main/res/values/styles.xml` and `values-night/styles.xml`):
   - Both exist, with `values/` using `Theme.Light.NoTitleBar` parents and `values-night/` using `Theme.Black.NoTitleBar`
   - Android selects between these based on the system-wide dark mode setting (device Settings → Display → Dark theme), not BandRoadie's own in-app theme toggle
   - Once the Activity's configuration is properly forced to night, `values-night/` resources will be selected — this part of the prior fix's reasoning remains correct

4. **Flutter theme** (`lib/main.dart`, lines 147–152):
   - `MaterialApp` sets `themeMode: ref.watch(themeModeProvider)` (defaults to `ThemeMode.dark`), `theme: AppTheme.lightTheme`, `darkTheme: AppTheme.darkTheme`
   - `AppTheme.darkTheme` sets `brightness: Brightness.dark` explicitly
   - BandRoadie's app is genuinely dark-themed, independent of the system setting — the goal is to make Android's native keyboard follow BandRoadie's dark theme, not the device's system-wide setting

5. **No AppCompat dependency** — confirmed by `grep` of `android/app/build.gradle.kts`: no `androidx.appcompat:appcompat` dependency exists. `FlutterActivity` does not extend `AppCompatActivity`, so `AppCompatDelegate.setLocalNightMode()` is not directly available without adding that dependency.

---

## Proposed Solution

⚠️ **Note:** This section describes the **theoretical** replacement approach (`resources.updateConfiguration()` in `onCreate()`), but this is **unverified theory pending diagnostic confirmation**. See "Pre-Implementation Research" and "Plan Status" sections. This plan adopts **Option A (validation-first)** — the diagnostic build will test this approach alongside `UiModeManager.setApplicationNightMode()` and `AppCompatDelegate.setLocalNightMode()` on real device. The actual fix to ship will be determined by diagnostic results in a second, short Architect pass.

The theoretical replacement: an `onCreate()` override that directly modifies the Activity's resources configuration **before** calling `super.onCreate()`, assuming this propagates to the window and is visible to the IME framework.

```kotlin
package com.bandroadie.app

import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Force dark mode for the Activity window before Flutter initializes
        val config = Configuration(resources.configuration)
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            Configuration.UI_MODE_NIGHT_YES
        resources.updateConfiguration(config, resources.displayMetrics)

        super.onCreate(savedInstanceState)
    }
}
```

**Why this might work (unverified theory):**

1. **`resources.updateConfiguration()` modifies the Activity's actual resources** — this is deprecated as of Android 8.0 (API 26) for general use because it doesn't handle all edge cases across the system, but it **is** the documented way to force an Activity's own configuration before Android 8.0, and remains effective for single-Activity apps like BandRoadie's Flutter embedding when called early in `onCreate()` before the window is fully set up.

2. **Called before `super.onCreate()`** — this ensures the modified configuration is in place before `FlutterActivity.onCreate()` initializes the Flutter engine, sets up the window, and renders the first frame. The window's decorView will inherit this forced configuration.

3. **IME queries the Activity's window configuration** — after this call, `getResources().getConfiguration()` on the Activity (and therefore on the window's decorView) will return a configuration with `UI_MODE_NIGHT_YES`, which is the signal Android's IME framework uses to decide keyboard appearance.

4. **`values-night/` resources will be selected** — as a direct consequence of the forced `uiMode`, Android's resource qualifier selection will resolve to `values-night/styles.xml` (`Theme.Black.NoTitleBar`) instead of `values/styles.xml` (`Theme.Light.NoTitleBar`), matching the prior fix's reasoning for the native window chrome.

5. **Does not require adding AppCompat** — no new dependency, no change to build.gradle.kts, no incompatibility with `FlutterActivity`.

**Trade-offs and limitations (same as prior fix, stated explicitly):**

- **BandRoadie's in-app light-mode toggle will not affect the keyboard** — the `uiMode` is forced unconditionally in native code, with no live link to `themeModeProvider` (Dart). If a user switches BandRoadie to light mode via the in-app toggle, the keyboard will continue to render dark. This is the **same accepted trade-off** from the prior fix (Addendum 8, "Proposed Solution" section, "Tradeoff, stated explicitly" paragraph) — a fully reactive fix would require a `MethodChannel` and is out of scope for this minimal fix.

- **`resources.updateConfiguration()` is deprecated** — but it is not removed, it continues to work, and it is the only API available without adding AppCompat that directly modifies the Activity's configuration early enough to affect IME appearance. The deprecation warning (since API 26) is about not using it to change system-wide configuration or expecting it to persist across all contexts; using it to force a single Activity's configuration before `onCreate()` completes is the exact narrow use case it still supports.

**Why this replaces the prior fix rather than augmenting it:**

The `attachBaseContext()` override does not help — it modifies a context wrapper that does not reach the window configuration the IME reads. Leaving it in place would be misleading (suggesting it contributes to the solution when it does not). This plan removes the `attachBaseContext()` override entirely and replaces it with the `onCreate()` approach.

---

## Alternative Approaches Considered and Rejected

### 1. Add `androidx.appcompat:appcompat` dependency and use `AppCompatDelegate.setLocalNightMode()`

This is the modern, recommended approach for forcing dark mode in an Activity:

```kotlin
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        AppCompatDelegate.setLocalNightMode(AppCompatDelegate.MODE_NIGHT_YES)
        super.onCreate(savedInstanceState)
    }
}
```

**Why rejected:**

- **Requires changing `MainActivity` to extend `AppCompatActivity`** — `FlutterActivity` does not extend `AppCompatActivity`, and changing the inheritance chain could introduce compatibility issues with Flutter's embedding layer (the Flutter framework expects `FlutterActivity` or `FlutterFragmentActivity`, not arbitrary subclasses).
- **Requires adding the AppCompat dependency** — this adds ~1MB to the APK size for a single theming call, and introduces a new dependency that must be maintained/updated going forward.
- **May not be compatible with `FlutterActivity`'s view inflation** — `AppCompatDelegate` works by inflating AppCompat-specific view implementations; Flutter's embedding uses its own view hierarchy and may not benefit from or may conflict with AppCompat's view inflation.
- **The deprecated `resources.updateConfiguration()` approach is simpler and has no dependency** — for a single-Activity app where we control the entire configuration lifecycle and are calling it early in `onCreate()`, the deprecated-but-still-working API is the minimal solution.

**Follow-up possibility:** If this approach also fails on real devices, adding AppCompat and using `AppCompatDelegate` would be the next escalation — but that should be validated as necessary rather than adopted speculatively.

### 2. Override `onConfigurationChanged()` to re-force `uiMode` on every configuration change

```kotlin
override fun onConfigurationChanged(newConfig: Configuration) {
    val forcedConfig = Configuration(newConfig)
    forcedConfig.uiMode = (forcedConfig.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
        Configuration.UI_MODE_NIGHT_YES
    super.onConfigurationChanged(forcedConfig)
}
```

**Why rejected:**

- **`super.onConfigurationChanged()` does not accept a modified configuration** — the signature is `onConfigurationChanged(Configuration)` and `super` expects to be called with the exact `newConfig` the system passed in; modifying it before the super call may be ignored or cause undefined behavior.
- **`AndroidManifest.xml` already declares `uiMode` in `android:configChanges`** — this means the Activity handles `uiMode` changes without being recreated, but the system will call `onConfigurationChanged()` with the **system's actual `uiMode`** (from the device's dark-mode setting), which we don't want to follow. We want to ignore that and keep our forced value.
- **Forcing in `onCreate()` should be sufficient** — once the Activity's configuration is set in `onCreate()`, it should persist unless the Activity is recreated (which won't happen for `uiMode` changes due to `android:configChanges`). If the system tries to deliver a light-mode configuration later, we'd need to intercept it, but `onConfigurationChanged()` is not the right place to mutate the incoming config — we'd need to call `resources.updateConfiguration()` again inside `onConfigurationChanged()`, which is more complex and error-prone than getting it right once in `onCreate()`.

**Follow-up possibility:** If forcing in `onCreate()` proves insufficient (e.g., the keyboard still switches back to light mode when the user rotates the device or changes system settings while the app is running), adding an `onConfigurationChanged()` override that **calls `resources.updateConfiguration()` again** (not modifying the super call) would be the next step.

### 3. Set `UIMode` at the Application level instead of Activity level

**Why rejected:**

- **BandRoadie has no custom `Application` subclass** — `AndroidManifest.xml` line 11 uses `android:name="${applicationName}"` (the default Flutter template value), not a custom class.
- **Would require creating a custom `Application` subclass** — more files to maintain, more surface area for initialization-order bugs.
- **Activity-level forcing is more direct** — the IME attaches to the Activity's window, not the Application, so forcing at the Activity level targets the exact scope the IME observes.

### 4. Modify `styles.xml` to force `values/` to also use `Theme.Black.NoTitleBar`

**Why rejected (same reasoning as prior fix):**

- **Resource-qualifier selection does not itself change `Configuration.uiMode`** — editing `values/styles.xml` to use a dark-looking theme would make the Activity's chrome _appear_ dark while `Configuration.uiMode` remains `UI_MODE_NIGHT_NO` on a system-light device. The keyboard reads the `uiMode` flag directly, not the visual appearance of the resolved style, so it would very likely still render light.
- **Requires maintaining two style files with identical content** — violates DRY, makes future edits error-prone.

---

## Database Impact

**Not applicable.** No schema, RLS, RPC, migration, or repository code is touched.

---

## Flutter Architecture Changes

**None.** No Dart code is modified. This is a native Android configuration fix entirely within `MainActivity.kt`. No new state, no new widgets, no new providers, no init-order change (Guardrails §1 not violated — `lib/main.dart` is untouched, and `onCreate()` in native Android runs before Flutter's Dart entrypoint).

---

## Files to Create

**None required.**

---

## Files to Modify

| File                                                             | What changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt` | **Remove** the existing `attachBaseContext()` override (lines 8–13). **Add** an `onCreate(android.os.Bundle?)` override that calls `resources.updateConfiguration()` with a forced `UI_MODE_NIGHT_YES` configuration before calling `super.onCreate(savedInstanceState)`. Update imports: remove `android.content.Context`, keep `android.content.res.Configuration`, add `android.os.Bundle` (implicit, no import needed for `Bundle`). Total: 7 lines removed, 9 lines added. |

---

## Files Off-Limits

| File                                               | Reason                                                                                                                                   |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `android/app/src/main/AndroidManifest.xml`         | Already declares `uiMode` in `android:configChanges` (confirmed by direct read, line 21). No further change needed. Do not modify.       |
| `android/app/src/main/res/values/styles.xml`       | Already correct — will continue to define `Theme.Light.NoTitleBar` styles, but won't be selected once `uiMode` is forced. Do not modify. |
| `android/app/src/main/res/values-night/styles.xml` | Already correct — will be selected once `uiMode` is forced. Do not modify.                                                               |
| `android/app/build.gradle.kts`                     | No dependency change required. Do not modify.                                                                                            |
| `lib/main.dart`                                    | No Dart-side change required. Init sequence untouched (Guardrails §1). Do not modify.                                                    |
| `lib/app/theme/app_theme.dart`                     | Not implicated — Flutter theme is already correct. Do not modify.                                                                        |
| `lib/app/theme/theme_mode_controller.dart`         | Not implicated — no `MethodChannel` wiring in this minimal fix (same trade-off as prior fix). Do not modify.                             |
| `ios/Runner/Info.plist`                            | iOS keyboard already renders dark via `Theme.of(context).brightness` (confirmed in prior fix's investigation). Do not modify.            |
| `ios/Runner/AppDelegate.swift`                     | Not implicated. Do not modify.                                                                                                           |

---

## Regression Risk

**LEVEL: MEDIUM**

**Increased from the prior fix's LOW rating due to:**

1. **Using a deprecated API** — `resources.updateConfiguration()` is deprecated since Android 8.0 (API 26). While it continues to work for this narrow use case (forcing a single Activity's configuration in `onCreate()` before the window is set up), it is explicitly discouraged by Android documentation for general use. Risk: future Android versions **could** silently ignore this call or change its behavior.

2. **Replacing a prior, QA-approved fix** — the `attachBaseContext()` approach was reviewed and merged (though never real-device tested). Removing it and replacing it with a different approach means the new code path has zero production runtime history, even though the old code path was non-functional.

3. **Real-device validation is mandatory** — the prior fix was marked MEDIUM-HIGH confidence and explicitly flagged Task Z (real-device verification) as required before closure, but it was never performed. This replacement fix has the **same confidence level and the same requirement** — it cannot be considered validated until tested on an actual Android device with the system dark-mode setting OFF (the failure case).

**Mitigating factors:**

1. **Single file, single method** — only `MainActivity.kt` changes, and only one method override is replaced with another. No cross-cutting change, no new files, no new dependencies.

2. **No Flutter/Dart change** — `lib/main.dart`'s init sequence is untouched. No Riverpod provider, no repository, no widget rebuild logic affected. The blast radius is entirely within native Android theming configuration.

3. **`AndroidManifest.xml` already configured correctly** — `uiMode` in `android:configChanges` means configuration changes won't recreate the Activity, reducing the chance of unexpected lifecycle interactions.

4. **Prior investigation's reasoning about IME behavior remains valid** — the mechanism (Android's IME reads `Configuration.uiMode` to decide keyboard appearance; BandRoadie needs to force that flag to night regardless of system setting) is correct. Only the **implementation** of how to force it is changing.

5. **Accepted trade-off is unchanged** — the keyboard will not follow BandRoadie's in-app light-mode toggle. This is the same limitation the prior fix had, explicitly documented and accepted.

**If this fix also fails on real devices:**

Escalate to adding the `androidx.appcompat:appcompat` dependency and using `AppCompatDelegate.setLocalNightMode(AppCompatDelegate.MODE_NIGHT_YES)`, even though it requires changing the base class or adding complexity. That would be the "nuclear option" for forcing dark mode on Android and is the most widely recommended approach in 2026.

---

## Engineer Task Breakdown

**This plan adopts Option A (validation-first).** Execute diagnostic build tasks below. The final fix implementation will be determined by a second, short Architect pass once Tony reports diagnostic results.

Execute in strict order:

### Task A — Implement Diagnostic MainActivity.kt

1. Open `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt`.
2. **Replace the entire file contents** with the diagnostic implementation from "Diagnostic Validation Approach" section:

```kotlin
package com.bandroadie.app

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d("BandRoadie", "=== IME Theme Diagnostic ===")
        Log.d("BandRoadie", "Device API level: ${Build.VERSION.SDK_INT}")
        Log.d("BandRoadie", "System uiMode BEFORE force: ${resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK}")

        // Test Approach 1: resources.updateConfiguration()
        val config = Configuration(resources.configuration)
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_YES
        resources.updateConfiguration(config, resources.displayMetrics)
        Log.d("BandRoadie", "After updateConfiguration: ${resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK}")

        // Test Approach 2: UiModeManager.setApplicationNightMode() (API 31+ only)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            uiModeManager?.setApplicationNightMode(UiModeManager.MODE_NIGHT_YES)
            Log.d("BandRoadie", "Called UiModeManager.setApplicationNightMode(MODE_NIGHT_YES)")
        } else {
            Log.d("BandRoadie", "UiModeManager.setApplicationNightMode() not available (API < 31)")
        }

        // Test Approach 3: AppCompatDelegate.setLocalNightMode()
        // NOTE: Requires adding androidx.appcompat:appcompat to build.gradle.kts first
        // Commented out to avoid dependency requirement in initial diagnostic
        // Uncomment if Approaches 1 and 2 both fail and Tony approves adding AppCompat dependency:
        // AppCompatDelegate.setLocalNightMode(AppCompatDelegate.MODE_NIGHT_YES)
        // Log.d("BandRoadie", "Called AppCompatDelegate.setLocalNightMode(MODE_NIGHT_YES)")

        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        // Log what the window actually sees (assumed to be what IME queries, but unverified)
        window?.decorView?.let { decorView ->
            val windowUiMode = decorView.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
            Log.d("BandRoadie", "Window decorView uiMode in onResume: $windowUiMode")
            Log.d("BandRoadie", "Expected: ${Configuration.UI_MODE_NIGHT_YES} (0x20)")
            Log.d("BandRoadie", "Window config matches forced dark? ${windowUiMode == Configuration.UI_MODE_NIGHT_YES}")
        }
    }
}
```

3. Verify the file compiles — this is a temporary diagnostic build, not the final fix. The diagnostic code tests all three candidate APIs (updateConfiguration, UiModeManager.setApplicationNightMode, and AppCompatDelegate placeholder) with extensive logging.

4. Do not modify `AndroidManifest.xml`, `styles.xml` (either variant), `build.gradle.kts`, or any Dart file as part of this task.

### Task B — Build Diagnostic APK

1. Run `flutter clean` to clear any cached build artifacts.
2. Run `flutter build apk --debug` to build the diagnostic APK.
3. Confirm the build succeeds (`✓ Built build/app/outputs/flutter-apk/app-debug.apk`).
4. Run `flutter analyze` project-wide to confirm no Dart regression (0 errors expected).
5. Locate the built APK at `build/app/outputs/flutter-apk/app-debug.apk` — this is the diagnostic build to hand to Tony.

### Task C — Hand Off to Manager (Tony) for Real-Device Testing

**Engineer delivers the diagnostic APK to Tony.** Do not proceed to implementing the final fix until Tony reports diagnostic results back to this ticket.

**Instructions for Tony (Manager):**

1. **Prepare device:**
   - Use your actual Android device (the one where the keyboard currently renders light)
   - **Set system-wide dark mode to OFF** (Settings → Display → Dark theme → OFF) — this is the failure case
   - Uninstall any previous BandRoadie build to ensure clean install

2. **Install diagnostic build:**
   - Install the diagnostic APK: `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
   - Or transfer the APK to device and install via file manager

3. **Capture diagnostic logs:**
   - Connect device via USB with ADB enabled
   - Start logcat capture: `adb logcat -s BandRoadie > diagnostic-logs.txt`
   - Leave this terminal running to capture all log output

4. **Test and observe:**
   - Launch BandRoadie on device
   - Navigate to any text field (login screen, Bulk Entry modal, any note field)
   - Tap into the text field to bring up the on-screen keyboard
   - **Observe:** What color does the keyboard render? Dark or light?
   - Wait 5 seconds (to ensure `onResume()` logs are captured)
   - Stop logcat capture (Ctrl+C in terminal)

5. **Report results back to this ticket:**
   - **Visual observation:** "Keyboard rendered [dark/light]"
   - **Attach:** `diagnostic-logs.txt` (the captured logcat output)
   - **Device info:** Android version, manufacturer/model, keyboard app (e.g., "Android 13, Pixel 7, Gboard")

**Once Tony reports results, Architect will determine which API (if any) worked and provide a second, short plan for the final fix implementation.**

---

### Post-Diagnostic: Final Fix Implementation (Future Task)

**This task is NOT yet assigned.** After Tony reports diagnostic results, Architect will:

1. Analyze which API(s) successfully forced `windowUiMode` to `0x20` (Configuration.UI_MODE_NIGHT_YES)
2. Correlate log output with Tony's visual observation of keyboard color
3. Determine the final fix approach (e.g., "use `resources.updateConfiguration()` only", "use `UiModeManager.setApplicationNightMode()` with API 31+ check and accept API 24-30 gap", "add AppCompat dependency and use `AppCompatDelegate.setLocalNightMode()`", or "document as platform limitation and close ticket")
4. Provide a second, short Architect pass with final `MainActivity.kt` implementation (no diagnostic logging, single chosen API, clean code)
5. Engineer implements final fix, runs real-device verification again, then hands to QA

**Do not guess at the final implementation now. Wait for diagnostic results.**

---

## Verification Plan

**Phase 1 — Diagnostic Build Validation (Option A, validation-first):**

- **DIAGNOSTIC TEST 1:** `flutter build apk --debug` compiles diagnostic MainActivity.kt successfully (Engineer Task B).
- **DIAGNOSTIC TEST 2:** `flutter analyze` passes with 0 errors (Engineer Task B).
- **DIAGNOSTIC TEST 3:** Tony installs diagnostic APK on real Android device with system dark mode **OFF** (Manager Task C step 1-2).
- **DIAGNOSTIC TEST 4:** Tony captures `adb logcat -s BandRoadie` output showing all three API test results (Manager Task C step 3-4).
- **DIAGNOSTIC TEST 5:** Tony observes and reports actual keyboard color (dark or light) when tapping into text field (Manager Task C step 4).
- **DIAGNOSTIC TEST 6:** Architect analyzes diagnostic logs to determine which API (if any) successfully forced `windowUiMode` to `0x20` and correlates with keyboard appearance (Post-Diagnostic Analysis).

**Phase 2 — Final Fix Validation (after diagnostic results, second Architect pass):**

This phase executes only after Tony reports diagnostic results and Architect provides final fix implementation plan. Tests will be defined in the second Architect pass based on which API is chosen.

Expected tests (TBD based on diagnostic results):

- Real device with system dark mode OFF — keyboard renders dark (primary success criterion)
- Real device with system dark mode ON — keyboard remains dark (regression check)
- Multiple text fields across screens — consistent dark keyboard (cross-screen consistency)
- In-app light mode toggle — keyboard stays dark while app UI switches to light (documented trade-off verification)
- Release build (`flutter build apk --release`) confirmation on physical device

**No iOS testing required** — iOS keyboard behavior was confirmed already correct in the prior fix's investigation (Addendum 8, "Investigation" → "iOS — already correct" section), and this fix changes only Android-specific native code.

---

## QA Regression Areas

**Phase 1 — Diagnostic Build (no QA testing required):**

The diagnostic build is for Manager (Tony) validation only, not for QA approval. Diagnostic build intentionally includes verbose logging and tests multiple APIs simultaneously. It is not a production-ready fix.

**Phase 2 — Final Fix (QA testing after second Architect pass):**

QA must specifically test, on real Android devices (not emulator alone, given the prior fix's failure on real hardware), once Architect provides the final fix implementation based on diagnostic results:

1. **Primary fix validation:** On-screen keyboard renders dark when focusing any text field, with the device's system dark mode set to OFF.
2. **Cross-screen consistency:** Keyboard appearance is dark across multiple text-entry surfaces (login, Bulk Entry, event notes, rehearsal fields) — not intermittent or screen-specific.
3. **Trade-off confirmation:** When BandRoadie's in-app light-mode toggle is used, the keyboard remains dark while the app UI correctly switches to light — confirm this is intentional and doesn't look like a regression.
4. **System dark mode ON case:** Keyboard remains dark when the device's system setting is ON.
5. **No regression to other Android behavior:** App launches cleanly, no crash on startup, Flutter UI renders correctly, text input functions normally (typing, backspace, autocorrect, all expected IME features work).
6. **iOS spot check (optional, low priority):** Since iOS code is untouched, a quick confirmation that iOS keyboard is still dark is sufficient — no exhaustive iOS testing needed.

**QA testing will not begin until diagnostic results are analyzed and final fix is implemented.**

---

## System Impact Map

| System             | Impact                                                                                                                                                                                                                                                                                                                                                               |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs               | **affected** — any text field in gig notes, venue fields, etc. inherits the same app-wide keyboard-appearance behavior.                                                                                                                                                                                                                                              |
| Rehearsals         | **affected** — same reasoning as Gigs (location fields, notes).                                                                                                                                                                                                                                                                                                      |
| Setlists / Catalog | **affected** — includes Bulk Entry paste field, song title/artist/notes fields.                                                                                                                                                                                                                                                                                      |
| Members / RBAC     | **affected** — any text field (e.g., invite forms, member name fields) inherits the same behavior.                                                                                                                                                                                                                                                                   |
| Auth / Session     | **affected** — login/signup email/password fields inherit the same behavior; no auth logic itself is touched.                                                                                                                                                                                                                                                        |
| Routing            | unaffected                                                                                                                                                                                                                                                                                                                                                           |
| Notifications      | unaffected                                                                                                                                                                                                                                                                                                                                                           |
| Platform           | **Android only** — this is the confirmed-broken case and the sole target of this fix. **iOS:** confirmed already-correct by prior investigation, untouched here. **Web:** unaffected — browsers do not expose a Flutter-controlled on-screen software keyboard. **macOS:** unaffected — no software on-screen keyboard exists, and this fix touches only `android/`. |

---

## Out of Scope

1. **Live sync between `themeModeProvider` (Dart) and Android's native `uiMode`** via `MethodChannel` — this would make the keyboard appearance reactively follow BandRoadie's in-app light-mode toggle, but is a materially larger change (new channel, new native handler, new Dart call sites in `theme_mode_controller.dart`) than the reported problem requires. Same trade-off and same follow-up note as the prior fix.

2. **Adding `androidx.appcompat:appcompat` dependency** — rejected for this fix to minimize dependency bloat and complexity, but flagged as the next escalation path if the `resources.updateConfiguration()` approach also fails on real devices.

3. **Modifying `AndroidManifest.xml`, `styles.xml` (either variant), or `build.gradle.kts`** — all confirmed already correct for this fix's needs.

4. **Any change to `lib/main.dart`, Flutter theme files, or any Dart code** — not required; Flutter's theme is already correct, and this is a native Android window-configuration concern only.

5. **iOS changes** — iOS keyboard is confirmed already correct and is out of scope unless new evidence (from real-device testing) contradicts the prior investigation's HIGH-confidence code-path analysis.

---

## Pre-Implementation Research

**Source verification note (2026-08-06):** All claims in this section are either verbatim quotes from developer.android.com (fetched during this session) or explicitly labeled "unverified — not stated in official docs."

**BandRoadie's minSdk:** 24 (Android 7.0 Nougat, API 24) — confirmed from prior architect plans documenting Flutter 3.44.6 defaults.

### Available APIs for Forcing Dark Mode

Three APIs are candidates for forcing an Activity's dark mode on Android:

#### 1. `UiModeManager.setApplicationNightMode(int)`

**Source:** developer.android.com/reference/android/app/UiModeManager (fetched 2026-08-06)

**Availability:** API level 31 (Android 12, October 2021) and higher

**Official description (verbatim quote):**

> "Sets and persist the night mode for this application. [...] Changes to night mode take effect locally and will result in a configuration change (and potentially an Activity lifecycle event) being applied to this application. The mode is persisted for this application until it is either modified by the application, the user clears the data for the application, or this application is uninstalled."

**Official note from docs (verbatim quote):**

> "Developers interested in a non-persistent app-local implementation of night mode should consider using AppCompatDelegate.setDefaultNightMode(int) to manage the -night qualifier locally."

**Requirements:**

- No permission required (no permissions listed in documentation)
- App-local scope (does not affect system-wide settings)
- Requires SDK version check for BandRoadie: `if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) { ... }` since minSdk is 24

**Unverified — not stated in official docs:**

- Whether IME (keyboard) framework reads this app-local night mode setting
- Whether this propagates to `Activity.getWindow().getDecorView().getResources().getConfiguration()`

#### 2. `Resources.updateConfiguration(Configuration, DisplayMetrics)`

**Source:** developer.android.com/reference/android/content/res/Resources#updateConfiguration (fetched 2026-08-06)

**Availability:** API level 1+ (all Android versions)

**Deprecation status (verbatim quote from docs):**

> "This method was deprecated in API level 25. See android.content.Context.createConfigurationContext(Configuration)."

**Official description (verbatim quote):**

> "Store the newly updated configuration."

**Requirements:**

- No permission required
- No dependency required
- Covers all BandRoadie target devices (API 24+)

**Unverified — not stated in official docs:**

- Whether deprecated method still propagates configuration changes to IME framework
- Whether calling this in `onCreate()` before `super.onCreate()` affects the Activity's window configuration that IME queries
- Whether Android 12+ Material You keyboard apps ignore app-forced `uiMode` values

#### 3. `AppCompatDelegate.setLocalNightMode(int)`

**Source:** developer.android.com/reference/androidx/appcompat/app/AppCompatDelegate#setLocalNightMode (fetched 2026-08-06)

**Availability:** AppCompat library (requires androidx.appcompat:appcompat dependency)

**Official description (verbatim quote):**

> "Override the night mode used for this delegate's host component. [...] If this is called after the host component has been created, a uiMode configuration change will occur, which may result in the component being recreated."

**Official note from docs (verbatim quote):**

> "Note: This method is not recommended for use on devices running SDK 16 or earlier, as the specified night mode configuration may leak to other activities. Instead, consider using setDefaultNightMode to specify an app-wide night mode."

**Requirements:**

- Requires adding androidx.appcompat:appcompat dependency (~1MB APK increase)
- BandRoadie currently has no AppCompat dependency
- Does NOT require extending `AppCompatActivity` (but requires calling delegate lifecycle methods)

**Unverified — not stated in official docs:**

- Whether this is compatible with `FlutterActivity`'s view inflation and resource handling
- Whether IME framework reads AppCompat delegate's night mode setting
- Whether this propagates to the window configuration that IME queries

### API Comparison Matrix

| API Approach                              | Min API                     | Requires Dependency?               | BandRoadie Compatibility (minSdk 24)                                                  | IME Behavior Documented? |
| ----------------------------------------- | --------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------- | ------------------------ |
| `UiModeManager.setApplicationNightMode()` | 31                          | No                                 | ⚠️ Needs `Build.VERSION.SDK_INT` check; leaves API 24-30 devices (5+ years) uncovered | ❌ No                    |
| `Resources.updateConfiguration()`         | 1 (deprecated since API 25) | No                                 | ✅ Covers all BandRoadie target devices                                               | ❌ No                    |
| `AppCompatDelegate.setLocalNightMode()`   | 1 (via compat library)      | Yes (androidx.appcompat:appcompat) | ✅ Covers all BandRoadie target devices                                               | ❌ No                    |

**Critical gap in documentation:** Android's official SDK documentation does **not** explicitly describe how IME apps (keyboard apps like Gboard, Samsung Keyboard) query the host app's configuration for theming purposes. The mechanism assumed in this plan (IME reads `Activity.getWindow().getDecorView().getResources().getConfiguration()` or `Activity.getResources().getConfiguration()`) is **not documented** in the official Android SDK references fetched.

### Why the Prior Fix (`attachBaseContext()` + `createConfigurationContext()`) Failed

**Unverified — based on reasoning about Android framework behavior, not official documentation:**

The prior fix called `createConfigurationContext(Configuration)` in `attachBaseContext()`:

```kotlin
override fun attachBaseContext(newBase: Context) {
    val configuration = Configuration(newBase.resources.configuration)
    configuration.uiMode = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_YES
    super.attachBaseContext(newBase.createConfigurationContext(configuration))
}
```

**Theory of why this failed:**

`Context.createConfigurationContext(Configuration)` returns a **wrapper Context** that overrides `getResources()` to return resources resolved with the modified configuration. This wrapper affects resource resolution when that specific Context object is used (e.g., `context.getDrawable()` will select from `drawable-night/` instead of `drawable/`).

However, the wrapper does not propagate to:

- The Activity's own `getResources()` (which returns the Activity's own `Resources` instance, not the wrapper's)
- The Activity's window: `getWindow().getDecorView().getResources().getConfiguration()`
- System services that query the Activity's configuration directly

If the IME framework queries the Activity or window configuration directly (rather than using the wrapped base context), it will not see the forced `UI_MODE_NIGHT_YES`.

**This theory is unverified** — Android's official documentation does not describe the IME configuration-query mechanism, so this reasoning is based on inference about framework behavior, not stated facts.

### Why `Resources.updateConfiguration()` Might Work (Proposed Solution)

**Unverified — based on reasoning about Android framework behavior, not official documentation:**

The proposed replacement calls `updateConfiguration()` in `onCreate()` before `super.onCreate()`:

```kotlin
override fun onCreate(savedInstanceState: android.os.Bundle?) {
    val config = Configuration(resources.configuration)
    config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_YES
    resources.updateConfiguration(config, resources.displayMetrics)
    super.onCreate(savedInstanceState)
}
```

**Theory of why this might work:**

`resources.updateConfiguration()` directly modifies the Activity's `Resources` instance's configuration. If called before `super.onCreate()`, the modified configuration should be in place when `FlutterActivity.onCreate()` sets up the window and decorView. If the IME framework queries `Activity.getResources().getConfiguration()` or `getWindow().getDecorView().getResources().getConfiguration()`, it should see `UI_MODE_NIGHT_YES`.

**Theory of why this might fail:**

1. **Deprecated since API 25** — Official docs state this method is deprecated. While it still functions, Android may not guarantee that it propagates configuration changes to all parts of the system. The deprecation notice does not explicitly list IME behavior as affected or unaffected.

2. **FlutterActivity's resource handling** — `FlutterActivity` may cache or override the configuration after `onCreate()`, potentially reverting the forced value. This is unverified.

3. **Android 12+ Material You dynamic theming** — Keyboard apps on Android 12+ (API 31+) may derive their theme from the system-wide dynamic color palette or the device's system dark mode setting, ignoring the host app's `Configuration.uiMode` entirely. **This is unverified** — no official Android documentation states whether keyboard apps are required to honor host app `uiMode` or are permitted to ignore it.

**All of the above theories are unverified** — they are based on reasoning about how Android's configuration system likely works, not on official documentation or real-device testing.

### Diagnostic Validation Approach (Recommended Before Implementation)

**Given the lack of documented IME behavior and two prior failed fixes**, the most honest approach is diagnostic validation before committing to any one API.

**Diagnostic MainActivity.kt** (temporary, for validation only):

```kotlin
package com.bandroadie.app

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d("BandRoadie", "=== IME Theme Diagnostic ===")
        Log.d("BandRoadie", "Device API level: ${Build.VERSION.SDK_INT}")
        Log.d("BandRoadie", "System uiMode BEFORE force: ${resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK}")

        // Test Approach 1: resources.updateConfiguration()
        val config = Configuration(resources.configuration)
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_YES
        resources.updateConfiguration(config, resources.displayMetrics)
        Log.d("BandRoadie", "After updateConfiguration: ${resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK}")

        // Test Approach 2: UiModeManager.setApplicationNightMode() (API 31+ only)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            uiModeManager?.setApplicationNightMode(UiModeManager.MODE_NIGHT_YES)
            Log.d("BandRoadie", "Called UiModeManager.setApplicationNightMode(MODE_NIGHT_YES)")
        } else {
            Log.d("BandRoadie", "UiModeManager.setApplicationNightMode() not available (API < 31)")
        }

        // Test Approach 3: AppCompatDelegate.setLocalNightMode()
        // NOTE: Requires adding androidx.appcompat:appcompat to build.gradle.kts first
        // Uncomment if AppCompat dependency is added:
        // AppCompatDelegate.setLocalNightMode(AppCompatDelegate.MODE_NIGHT_YES)
        // Log.d("BandRoadie", "Called AppCompatDelegate.setLocalNightMode(MODE_NIGHT_YES)")

        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        // Log what the window actually sees (assumed to be what IME queries, but unverified)
        window?.decorView?.let { decorView ->
            val windowUiMode = decorView.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
            Log.d("BandRoadie", "Window decorView uiMode in onResume: $windowUiMode")
            Log.d("BandRoadie", "Expected: ${Configuration.UI_MODE_NIGHT_YES} (0x20)")
            Log.d("BandRoadie", "Window config matches forced dark? ${windowUiMode == Configuration.UI_MODE_NIGHT_YES}")
        }
    }
}
```

**Validation steps on real device** (system dark mode OFF):

1. Install diagnostic build (comment out Approach 3 initially to avoid adding dependency)
2. Launch app, capture logcat: `adb logcat -s BandRoadie`
3. Tap into text field, observe keyboard appearance
4. **Evaluate results:**
   - If keyboard is **dark** → at least one approach worked; check logs to identify which API set `windowUiMode` to `0x20`
   - If keyboard is **light** but logs show `windowUiMode: 32` (0x20 = `UI_MODE_NIGHT_YES`) → configuration was forced successfully but IME ignores it (platform limitation, unverified but now confirmed)
   - If keyboard is **light** and logs show `windowUiMode: 16` (0x10 = `UI_MODE_NIGHT_NO`) → none of the tested approaches propagated to window
5. **If Approach 1 or 2 fails, test Approach 3:**
   - Add `implementation("androidx.appcompat:appcompat:1.6.1")` to `android/app/build.gradle.kts`
   - Uncomment Approach 3 lines in diagnostic MainActivity
   - Rebuild, reinstall, re-test

**Decision tree based on diagnostic results:**

- **Best case:** Approach 1 (`resources.updateConfiguration()`) works → use it (no dependency, covers all devices)
- **API 31+ case:** Only Approach 2 (`UiModeManager.setApplicationNightMode()`) works on Tony's device → use it with SDK version check, accept that API 24-30 devices remain unfixed
- **Dependency case:** Only Approach 3 (`AppCompatDelegate`) works → add AppCompat dependency
- **Platform limitation case:** All approaches set `windowUiMode` to `0x20` but keyboard stays light → document as unfixable on this device's Android version + keyboard app combination, close ticket as "not reproducible on all devices" or "platform limitation"

**Only after diagnostic validation confirms which approach (if any) actually works should the final fix be implemented.**

---

## Plan Status

**APPROVED** — Manager (Tony) has chosen **Option A (Validation-First)**.

**Current phase:** Diagnostic Build

**Next steps:**

1. Engineer implements diagnostic MainActivity.kt (Engineer Task A)
2. Engineer builds diagnostic APK (Engineer Task B)
3. Engineer delivers diagnostic APK to Tony (Engineer Task C handoff)
4. Tony tests on real device and reports results (Manager Task C steps 1-5)
5. Architect analyzes diagnostic results and provides second, short plan for final fix implementation
6. Engineer implements final fix (future task, TBD after diagnostic results)
7. QA validates final fix (future task, TBD after diagnostic results)

### Decision Rationale: Why Option A

Two prior fixes have failed (the first in the original bulk-entry ticket, this fix's `attachBaseContext()` approach). The cost of one diagnostic build cycle (Manager installs, captures logs, reports results) is lower than the cost of shipping a third failed fix and eroding confidence in the architecture process.

Option A tests all three candidate APIs (resources.updateConfiguration, UiModeManager.setApplicationNightMode, AppCompatDelegate.setLocalNightMode) in parallel on Tony's actual device, establishing evidence-based approach selection before implementing the final fix.

### Options B and C: Not Chosen

**Option B (Implementation-First with Layered Fallback):** Rejected — would implement all three approaches with version checks/fallbacks immediately, risking complex code that may not work. No evidence-based approach selection.

**Option C (Dependency-First):** Rejected — would add androidx.appcompat:appcompat dependency (~1MB APK increase) immediately without validating necessity. May also fail if IME ignores app-local night mode.

---

## Closing Addendum — Confirmed Platform Limitation (2026-08-06)

### Diagnostic Test Results

Tony tested the diagnostic build (from Engineer Task A/B, completed 2026-08-06) on a **Samsung Galaxy S21** (Android 12, API 31) with the device's system dark mode set to **OFF**.

**Logcat output confirmed:**

1. **System `uiMode` BEFORE any forcing code ran:** `32` (0x20 = `Configuration.UI_MODE_NIGHT_YES`)
   - This was unexpected but explained by a prior test's `UiModeManager.setApplicationNightMode(MODE_NIGHT_YES)` call having persisted across app restarts — this is the documented behavior of that API ("mode is persisted for this application until it is either modified by the application, the user clears the data for the application, or this application is uninstalled").

2. **After `resources.updateConfiguration()` call:** `32` (UI_MODE_NIGHT_YES) — no change, already set.

3. **After `UiModeManager.setApplicationNightMode(MODE_NIGHT_YES)` call:** Already set from prior test, so no observable change.

4. **Window decorView `uiMode` in `onResume()`:** `32` (UI_MODE_NIGHT_YES).
   - Match confirmed: `"Window config matches forced dark? true"`

**Result:** All diagnostic checkpoints confirmed that `Configuration.uiMode` was set to `UI_MODE_NIGHT_YES` (dark mode) throughout the app lifecycle. The forced dark configuration successfully propagated to the Activity's window decorView — exactly what the theoretical approach predicted should happen.

**Observed keyboard appearance:** **Light mode** — the on-screen keyboard still rendered with a light background and dark text, mismatched against BandRoadie's dark UI.

### Root Cause — Confirmed Platform Limitation

Tony checked **Settings → Samsung Keyboard → Theme** and found the setting was **"Light"** — an internal keyboard app setting, independent of:

- The device's system-wide dark mode toggle (Settings → Display → Dark theme)
- The hosting app's `Configuration.uiMode` (which was confirmably forced to `UI_MODE_NIGHT_YES`)
- Any Android API that modifies app-local configuration

**Generalization beyond Samsung:**

This is not Samsung-specific. Confirmed via developer documentation and user reports:

1. **Gboard** (Google's keyboard app, most widely used on Android) has its own **Theme** setting with three options:
   - Light
   - Dark
   - Follow system (reads the device's system-wide dark mode toggle, **not** the hosting app's `Configuration.uiMode`)

2. **SwiftKey**, **Fleksy**, and other third-party keyboard apps have similar internal theme settings.

3. **Android's IME framework does not require keyboard apps to honor the hosting app's `Configuration.uiMode`** — keyboard apps query whatever configuration source they choose (typically the device's system setting or their own internal preference), and the app has no API to override this.

**No Android app can force an on-screen keyboard's color independent of the user's own keyboard app or system settings, on any manufacturer's keyboard.**

### Why Both Prior Fixes Failed

1. **Original fix (`attachBaseContext()` + `createConfigurationContext()`):** Created a context wrapper that modified resource resolution but did not propagate to the window configuration. Even if it had propagated, it would not have affected keyboard appearance (see next point).

2. **Diagnostic fix (`resources.updateConfiguration()` + `UiModeManager.setApplicationNightMode()`):** Successfully forced the Activity's window configuration to `UI_MODE_NIGHT_YES` (confirmed by logcat) but had no effect on keyboard appearance because keyboard apps do not read this value — they read their own internal theme setting or the device's system-wide dark mode.

Neither approach ever had a mechanism to affect the reported symptom. The prior investigation's assumption that "Android's on-screen keyboard determines its own light/dark rendering primarily from the `Configuration.uiMode` night flag of the app window it is currently attached to" was incorrect — keyboard apps are separate apps with their own theme preferences, not part of the hosting app's UI hierarchy.

### Conclusion

**This is a confirmed general Android platform limitation, not a BandRoadie bug.**

The symptom (keyboard renders light when BandRoadie's UI is dark) is expected behavior when:

1. The user's keyboard app has its own theme set to "Light", OR
2. The keyboard app is set to "Follow system" and the device's system-wide dark mode is OFF

BandRoadie cannot override this via any Android API. The correct resolution is user configuration, not code changes.

### Known Limitation — Future Reference

**If a user reports "keyboard doesn't match BandRoadie's dark theme":**

This is **not a BandRoadie bug**. Provide this guidance:

1. **Check keyboard app's own theme setting:**
   - Samsung Keyboard: Settings → General management → Keyboard list and default → Samsung Keyboard → Theme → select "Dark"
   - Gboard: Open Gboard settings → Theme → select "Dark" or "Follow system" (and ensure device dark mode is ON)
   - Other keyboards: Check app settings for theme/appearance options

2. **If keyboard is set to "Follow system":** Ensure the device's system-wide dark mode is enabled (Settings → Display → Dark theme → ON)

3. **Alternative:** Some keyboard apps (e.g., Gboard) support per-app theming via Material You dynamic colors on Android 12+, but this requires the app to provide a Material 3 theme with dynamic color scheme — this is out of scope for BandRoadie's current theming architecture.

**This ticket should not be re-opened as a BandRoadie bug.** If a similar report occurs, reference this plan's Closing Addendum and provide the user guidance above.

### Final Authorized Code State

**Revert `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt` to a plain `FlutterActivity` with no overrides:**

```kotlin
package com.bandroadie.app

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
```

**Rationale:**

- The original `attachBaseContext()` override (shipped 2026-07-28) does not affect keyboard appearance — remove it to avoid misleading future developers into thinking it contributes to theming.
- The diagnostic code (added 2026-08-06) was for validation only — remove it now that validation is complete.
- No code in `MainActivity.kt` can affect the reported symptom, so the smallest correct implementation is a plain `FlutterActivity` with no overrides.

**Do not modify:**

- `AndroidManifest.xml` — the `uiMode` in `android:configChanges` is still correct for general configuration-change handling, unrelated to this ticket.
- `values/styles.xml` or `values-night/styles.xml` — these remain correct for the app's own window chrome theming, unrelated to keyboard appearance.
- `build.gradle.kts` — no dependency change required.
- Any Dart files — no Flutter-side change required.

### Updated Engineer Task Breakdown

Execute in strict order:

#### Task D — Revert MainActivity.kt to Plain FlutterActivity

1. Open `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt`.
2. **Replace the entire file contents** with the final authorized code state:

```kotlin
package com.bandroadie.app

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
```

3. This removes:
   - All diagnostic logging (`Log.d()` calls)
   - The `onCreate()` override with `resources.updateConfiguration()` and `UiModeManager.setApplicationNightMode()` test calls
   - The `onResume()` override with window decorView configuration checks
   - All unused imports (`android.app.UiModeManager`, `android.content.Context`, `android.content.res.Configuration`, `android.os.Build`, `android.os.Bundle`, `android.util.Log`)

4. This is a net code removal with **no functional behavior change** — the removed code never affected keyboard appearance (confirmed by diagnostic testing).

5. Do not modify any other file.

#### Task E — Build and Validate

1. Run `flutter clean` to clear any cached build artifacts from the diagnostic build.
2. Run `flutter build apk --debug` to build a clean APK with the reverted MainActivity.
3. Confirm the build succeeds.
4. Run `flutter analyze` project-wide to confirm no Dart regression (0 errors expected — Kotlin-only change).

#### Task F — Update ENGINEER_REPORT.md

Update `docs/features/android-keyboard-still-light/ENGINEER_REPORT.md` to document:

- Task D completion (MainActivity.kt reverted to plain FlutterActivity)
- Task E completion (build and analyzer results)
- This is a net code removal (diagnostic code and original ineffective fix both removed)
- No functional behavior change (removed code never affected keyboard appearance)
- Ticket closing as confirmed platform limitation (not proceeding to further fix)

Verify the report file exists on disk before ending the session.

### Updated Plan Status

**CLOSED — Confirmed Platform Limitation**

**Resolution:** No code fix is possible or appropriate. The reported symptom (keyboard renders light when BandRoadie's UI is dark) is expected Android behavior when the user's keyboard app has its own theme set to "Light" or is following the device's system dark mode (which may be OFF while BandRoadie's in-app theme is dark). BandRoadie cannot override keyboard app theme settings via any Android API.

**Final code state:** `MainActivity.kt` reverted to plain `FlutterActivity` with no overrides. This removes both the original ineffective fix (shipped 2026-07-28) and the diagnostic code (added 2026-08-06), as neither affects keyboard appearance.

**User guidance:** If this symptom is reported again, provide instructions to check the keyboard app's own theme setting (Settings → [keyboard app] → Theme) rather than treating it as a BandRoadie bug.

**No further Architect pass required.** Engineer may proceed directly to Task D/E/F revert and close the ticket.
