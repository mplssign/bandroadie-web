# Engineer Report

## Feature Slug

`android-keyboard-still-light`

## Feature Title

Android On-Screen Keyboard Still Renders in Light Mode Despite Prior Fix

## Goal

Close ticket as confirmed platform limitation after diagnostic testing proved Android keyboards read their own internal theme settings, not the hosting app's `Configuration.uiMode`. Revert MainActivity.kt to plain FlutterActivity, removing both the original ineffective fix and diagnostic code.

## Architect Tasks Completed

- [x] Task A — Implement diagnostic MainActivity.kt (completed 2026-08-06, prior session)
- [x] Task B — Build diagnostic APK (completed 2026-08-06, prior session)
- [x] Task C — Manager (Tony) real-device testing (completed 2026-08-06, confirmed platform limitation)
- [x] Task D — Revert MainActivity.kt to plain FlutterActivity (completed this session)
- [x] Task E — Build and validate revert (completed this session)
- [x] Task F — Update ENGINEER_REPORT.md (this document)

## Files Created

None

## Files Modified

- `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt`
  - **Reverted to plain FlutterActivity with no overrides**
  - Removed all diagnostic logging (`Log.d()` calls)
  - Removed `onCreate()` override with `resources.updateConfiguration()` and `UiModeManager.setApplicationNightMode()` calls
  - Removed `onResume()` override with window decorView configuration checks
  - Removed all unused imports (`android.app.UiModeManager`, `android.content.Context`, `android.content.res.Configuration`, `android.os.Build`, `android.os.Bundle`, `android.util.Log`)
  - **Final state:** 4 lines total (package, import, class declaration)

## Analyzer Results

```
Command: flutter analyze
Result: No issues found! (ran in 3.2s)
```

✅ 0 errors, 0 warnings

## Test Results

Not run — Kotlin-only change, no Dart test coverage affected.

## Build Results

```
Command: flutter clean && flutter build apk --debug
Result: ✓ Built build/app/outputs/flutter-apk/app-debug.apk (32.6s)
```

✅ APK built successfully

**Note:** Kotlin deprecation warning ("Some input files use or override a deprecated API") still present — this is unrelated to MainActivity.kt (which now has zero deprecated API usage). The warning is from other Android dependencies in the project.

## Verification

Manual steps performed by Engineer:

- Confirmed MainActivity.kt reverted to minimal FlutterActivity (4 lines, no overrides)
- Confirmed `flutter clean` cleared diagnostic build artifacts
- Confirmed `flutter build apk --debug` succeeded with reverted code
- Confirmed `flutter analyze` passed with 0 errors
- Confirmed no other files were modified (per Architect plan's off-limits list)

## Diagnostic Results Summary (Task C — Manager/Tony)

Tony tested the diagnostic build on **Samsung Galaxy S21 (Android 12, API 31)**:

1. **Logcat confirmed:** `Configuration.uiMode` was forced to `UI_MODE_NIGHT_YES` (32) at all checkpoints — before forcing, after `resources.updateConfiguration()`, and in window decorView check.
2. **Keyboard appearance:** Still rendered **light** despite configuration being confirmably dark.
3. **Root cause:** Samsung Keyboard had internal "Theme: Light" setting, independent of app configuration.
4. **Generalization:** Confirmed via research that Gboard and all major Android keyboards have their own internal theme settings. Keyboards read their own preferences or device system setting, never the hosting app's `Configuration.uiMode`.

**Conclusion:** No Android API allows apps to override keyboard theme settings. This is a confirmed platform limitation, not a BandRoadie bug.

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Code Impact

This is a **net code removal** with **no functional behavior change**:

- Removed code never affected keyboard appearance (confirmed by diagnostic testing)
- Original `attachBaseContext()` fix (shipped 2026-07-28) — ineffective, removed
- Diagnostic code (added 2026-08-06) — validation complete, removed
- Final state: minimal FlutterActivity, smallest correct implementation

## Ready For QA

**N/A — Ticket closing as platform limitation, not proceeding to QA.**

No code fix is possible. The reported symptom (keyboard renders light when BandRoadie UI is dark) is expected Android behavior when the user's keyboard app theme is set to "Light" or follows device system mode (which may be OFF while BandRoadie's in-app theme is dark).

## User Guidance for Future Reports

If this symptom is reported again, provide this guidance (not a BandRoadie bug):

1. **Check keyboard app's own theme setting:**
   - Samsung Keyboard: Settings → General management → Keyboard list and default → Samsung Keyboard → Theme → select "Dark"
   - Gboard: Open Gboard settings → Theme → select "Dark" or "Follow system" (and ensure device dark mode is ON)
   - Other keyboards: Check app settings for theme/appearance options

2. **If keyboard is set to "Follow system":** Ensure device's system-wide dark mode is enabled (Settings → Display → Dark theme → ON)

**Do not re-open this ticket as a BandRoadie bug.** Reference ARCHITECT_PLAN.md Closing Addendum for full technical explanation.

---

## Engineer Session Complete

Tasks D, E, and F executed successfully. MainActivity.kt reverted to plain FlutterActivity. Ticket closed as confirmed platform limitation.
