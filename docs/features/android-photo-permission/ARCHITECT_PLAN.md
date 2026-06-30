# ARCHITECT PLAN

## Feature Slug

`bug/android-photo-permission`

---

## Problem Summary

Android users cannot grant BandRoadie permission to access photos. When the app attempts
to check or request photo/camera permissions, the permission dialog either fails to appear,
appears but silently fails, or the app treats the permission as denied even after the user
grants it. All features that read from the device photo library are broken on Android (band
photo upload, profile photo upload).

**iOS is unaffected.** No video permission issues are in scope.

### Prior Fix — Not Merged

An identical root cause was diagnosed and fixed in branch
`bug/android-dashboard-freeze-photo-permissions` (commit `4600007`,
dated 2026-06-23). That fix passed QA but was **never merged to main**. The current
`main` branch still has the unfixed manifest. This new plan supersedes that branch and
extends it to cover Android 14 partial access (`READ_MEDIA_VISUAL_USER_SELECTED`), which
was absent from the prior fix.

---

## Root Cause

### ROOT CAUSE — Missing Android Manifest Permissions (HIGH confidence — confirmed in code)

**File**: `android/app/src/main/AndroidManifest.xml`

The manifest declares only two permissions:
- `android.permission.POST_NOTIFICATIONS`
- `android.permission.INTERNET`

The following permissions required for photo and camera access are entirely absent:

| Permission | Required for | Android version |
|---|---|---|
| `CAMERA` | Camera image capture | All Android |
| `READ_MEDIA_IMAGES` | Photo library access | Android 13+ (API 33+) |
| `READ_MEDIA_VIDEO` | Video library access (future-proofing) | Android 13+ (API 33+) |
| `READ_MEDIA_VISUAL_USER_SELECTED` | Partial photo access ("Select photos") | Android 14+ (API 34+) |
| `READ_EXTERNAL_STORAGE` (`maxSdkVersion="32"`) | Photo library access | Android ≤ 12 (API ≤ 32) |
| `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion="32"`) | Storage write access | Android ≤ 12 (API ≤ 32) |

**Why this fails:** Android never registers an undeclared permission for an app. Calling
`Permission.photos.status` or `Permission.photos.request()` on a permission that is not
declared in the manifest yields unpredictable results — typically `denied` immediately with
no dialog shown. The permission toggle never appears in Android Settings → Apps →
BandRoadie → Permissions.

**Why the code cannot compensate:** The runtime permission check in
`_checkPhotoLibraryPermission()` and `_checkCameraPermission()` (both in
`lib/features/bands/band_form_screen.dart`) is correctly written. The failure is at the
Android platform layer — a missing manifest declaration — not in the Dart logic.

---

## Reference Docs Consulted

There is no `docs/reference/` directory for Android permissions or mobile platform
configuration. The following general reference docs were consulted:

- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`
- `docs/reference/general/RUNTIME_CONFIG.md`
- `docs/agents/GUARDRAILS.md`

No specific Android permissions reference exists. This plan serves as the authoritative
record of the diagnosis.

---

## Existing System Analysis

### SDK Versions (Flutter 3.41.2 — confirmed from `FlutterExtension.kt`)

| Setting | Value | Source |
|---|---|---|
| `compileSdkVersion` | 36 (Android 16) | `flutter.compileSdkVersion` → Flutter 3.41.2 default |
| `targetSdkVersion` | 36 (Android 16) | `flutter.targetSdkVersion` → Flutter 3.41.2 default |
| `minSdkVersion` | 24 (Android 7.0) | `flutter.minSdkVersion` → Flutter 3.41.2 default |

These are injected by Flutter's Gradle plugin via `flutter.compileSdkVersion` /
`flutter.targetSdkVersion` / `flutter.minSdkVersion` in `android/app/build.gradle.kts`.
No hardcoded SDK versions exist in the project.

Targeting API 36 means the app runs on Android 14+ devices where
`READ_MEDIA_VISUAL_USER_SELECTED` is the correct permission for partial photo access.

### Dependency Versions

| Package | Version | Relevant behavior |
|---|---|---|
| `permission_handler` | `^11.3.1` | Maps `Permission.photos` → `READ_MEDIA_IMAGES` on API 33, `READ_MEDIA_VISUAL_USER_SELECTED` on API 34+. Returns `PermissionStatus.limited` for partial access. Requires manifest declaration. |
| `image_picker` | `^1.2.1` | Uses Android Photo Picker (`ACTION_PICK_IMAGES`) on API 13+, which is permission-free. The pre-permission-check in `band_form_screen.dart` is therefore technically redundant on API 33+ but harmless. Fixing the manifest resolves the immediate bug without requiring code changes. |

### Permission Call Sites

There is **exactly one** location in the codebase that requests photo or camera permissions:

`lib/features/bands/band_form_screen.dart` — lines 1139–1222

Two methods:

**`_checkCameraPermission()` (lines 1139–1181)**
- Calls `Permission.camera.status`
- If `isDenied`: calls `Permission.camera.request()`
- If `isPermanentlyDenied` or `isRestricted`: shows "Open Settings" dialog
- Falls through to snack bar on post-request denial
- Guarded by `Platform.isIOS || Platform.isAndroid`

**`_checkPhotoLibraryPermission()` (lines 1185–1222)**
- Calls `Permission.photos.status`
- If `isGranted || isLimited`: returns `true` ✓ (Android 14 partial access already handled)
- If `isDenied`: calls `Permission.photos.request()`; returns `true` if `isGranted || isLimited`
- If `isPermanentlyDenied || isRestricted`: shows "Open Settings" dialog
- Falls through to snack bar on post-request denial
- Guarded by `Platform.isIOS || Platform.isAndroid`

Both methods are correct. No code changes required.

### Current Photo Access Flow (failing path)

```
User taps avatar → _pickImage() called
  → source == ImageSource.gallery
  → _checkPhotoLibraryPermission()
    → Permission.photos.status          ← permission not declared in manifest
    → Android returns `denied` immediately (no dialog)
    → status.isDenied == true
    → Permission.photos.request()       ← permission not declared in manifest
    → Android does not show dialog; returns `denied`
    → result.isGranted == false, result.isLimited == false
    → Shows snack bar: "Photo library permission is required"
    → returns false
  → hasPermission == false
  → _pickImage() returns early; image picker never opens
```

### Android 14 Partial Access (`READ_MEDIA_VISUAL_USER_SELECTED`)

When `READ_MEDIA_VISUAL_USER_SELECTED` is declared in the manifest:
- Android 14 shows three options in the permission dialog: "Allow all", "Select photos",
  "Don't allow"
- "Select photos" returns `PermissionStatus.limited`
- `permission_handler` 11.3.x maps this correctly
- `_checkPhotoLibraryPermission()` already handles `.isLimited` at lines 1189 and 1195

Without `READ_MEDIA_VISUAL_USER_SELECTED` in the manifest, Android 14 behaves like
Android 13 — full-access-or-nothing — which is not ideal but functional. Adding it
provides the expected Android 14 UX and is required for correct behavior on API 36 target.

---

## Proposed Solution

**Manifest-only change. No Dart code modifications required.**

Add the following 6 permission declarations to `android/app/src/main/AndroidManifest.xml`,
after the existing `INTERNET` permission and before the `<application>` block:

```xml
<!-- Camera and media permissions for band/profile photo upload -->

<!-- Camera: required for ImageSource.camera on all Android versions -->
<uses-permission android:name="android.permission.CAMERA"/>

<!-- Android 13+ (API 33+): granular media permissions replace READ_EXTERNAL_STORAGE -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>

<!-- Android 14+ (API 34+): partial photo access ("Select photos" option) -->
<!-- permission_handler 11.3.x maps Permission.photos → limited on API 34+ when declared -->
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>

<!-- Android 12 and below (API ≤ 32): legacy storage permissions -->
<!-- maxSdkVersion ensures these are ignored on API 33+ -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
```

**Why 6 permissions, not 5 (vs. prior plan):**
The prior branch (`bug/android-dashboard-freeze-photo-permissions`) declared 5 permissions
and was missing `READ_MEDIA_VISUAL_USER_SELECTED`. With `targetSdkVersion = 36` (API 36),
omitting this permission deprives Android 14+ users of the partial-access ("Select photos")
option. Since `permission_handler` 11.3.x and `_checkPhotoLibraryPermission()` already
handle `PermissionStatus.limited` correctly, this is a pure manifest addition with zero
code risk.

**What must NOT change:**
- `lib/features/bands/band_form_screen.dart` — permission logic is correct
- `pubspec.yaml` — no new dependencies
- `android/app/build.gradle.kts` — no SDK version overrides; Flutter defaults remain authoritative
- `ios/Runner/Info.plist` — iOS permissions are already correct and unaffected
- `lib/main.dart` — initialization order must not change (Guardrail #1)

---

## Database Impact

**Not applicable.**

No schema changes, migrations, RLS policies, RPC functions, or triggers are involved.
This is an Android platform configuration change only.

---

## Flutter Architecture Changes

**None.**

- No Riverpod providers modified
- No controllers modified
- No widgets modified
- No repositories modified
- No service classes modified

---

## Files to Create

**None.**

---

## Files to Modify

| File | What changes |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | Add 6 permission declarations: `CAMERA`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_VISUAL_USER_SELECTED`, `READ_EXTERNAL_STORAGE` (maxSdk=32), `WRITE_EXTERNAL_STORAGE` (maxSdk=32) |

---

## Files Off-Limits

| File | Reason |
|---|---|
| `lib/main.dart` | Initialization order must not change (Guardrail #1) |
| `lib/features/bands/band_form_screen.dart` | Permission-handling logic is correct; no changes needed |
| `pubspec.yaml` | No new dependencies; `permission_handler ^11.3.1` and `image_picker ^1.2.1` are already sufficient |
| `ios/Runner/Info.plist` | iOS is unaffected; touching this file is out of scope |
| `android/app/build.gradle.kts` | SDK targets are Flutter-managed; do not override with hardcoded values |
| All other `lib/` Dart files | No other files request photo or camera permissions |

---

## System Impact Map

| System | Impact |
|---|---|
| Gigs | unaffected — gig features do not use photo permissions |
| Rehearsals | unaffected — rehearsal features do not use photo permissions |
| Setlists / Catalog | unaffected — setlist features do not use photo permissions |
| Members / RBAC | unaffected — member features do not use photo permissions |
| Auth / Session | unaffected — no auth flow changes |
| Routing | unaffected — no navigation changes |
| Notifications | unaffected — `POST_NOTIFICATIONS` already declared correctly; not touched |
| Platform (iOS / macOS / Web) | unaffected — change is Android manifest only |
| Platform (Android) | **affected** — 6 permissions added; enables photo and camera access |
| Band Management | **affected** — band photo upload will work on Android after this fix |

---

## Regression Risk

**LEVEL: LOW**

- Single file modified (`AndroidManifest.xml`)
- Additive-only change; no existing declarations removed or altered
- Zero Dart/Flutter code changes
- Zero state management changes
- Zero database changes
- Platform-isolated to Android; iOS, web, macOS unaffected
- `permission_handler` and `image_picker` require no version changes
- Existing runtime permission code handles all new permission states already

**Expected behavior change (not a regression):**
Android users will see system permission dialogs when first accessing camera or photo
library. On Android 14+, they will see a three-option dialog (Allow all / Select photos /
Don't allow). This is the intended behavior the bug fix restores.

---

## Engineer Task Breakdown

### Task 1 — Add Camera Permission

In `android/app/src/main/AndroidManifest.xml`, after line 5
(`<uses-permission android:name="android.permission.INTERNET"/>`), add a blank line then:

```xml
<!-- Camera and media permissions for band/profile photo upload -->

<uses-permission android:name="android.permission.CAMERA"/>
```

### Task 2 — Add Android 13+ Media Permissions

Immediately after the `CAMERA` line, add:

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
```

### Task 3 — Add Android 14+ Partial Access Permission

Immediately after `READ_MEDIA_VIDEO`, add:

```xml
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>
```

### Task 4 — Add Legacy Storage Permissions for Android 12 and Below

After `READ_MEDIA_VISUAL_USER_SELECTED`, add a blank line then:

```xml
<!-- Android 12 and below (API ≤ 32): legacy storage permissions -->
<!-- maxSdkVersion ensures these are ignored on API 33+ -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
```

### Task 5 — Verify XML Formatting

- Confirm the file is well-formed XML (no unclosed tags, no duplicate attributes)
- Confirm indentation is consistent with the existing manifest style (4 spaces)
- Confirm the new permissions appear before the `<application>` element

**Final manifest permissions block should be:**

```xml
<!-- Required for push notifications on Android 13+ (API 33+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<!-- Required for Firebase Cloud Messaging -->
<uses-permission android:name="android.permission.INTERNET"/>

<!-- Camera and media permissions for band/profile photo upload -->

<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>

<!-- Android 12 and below (API ≤ 32): legacy storage permissions -->
<!-- maxSdkVersion ensures these are ignored on API 33+ -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
```

---

## Verification Plan

This is a client-side Android platform configuration change with no backend dependencies.
All verification is manual device or emulator testing. The tier structure maps to the
deploy gate: Tier 1 validates pre-commit; Tier 2 validates post-build.

### Tier 1 — Pre-deployment (must pass before commit)

These tests require only the modified `AndroidManifest.xml` — no build or deploy step:

**PRE-DEPLOY TEST 1: Manifest XML validity**
```
Tool: xmllint or Android Studio manifest inspector
Steps:
1. Open android/app/src/main/AndroidManifest.xml
2. Verify file is well-formed XML (no parse errors)
3. Confirm all 8 uses-permission elements are present:
   - POST_NOTIFICATIONS
   - INTERNET
   - CAMERA
   - READ_MEDIA_IMAGES
   - READ_MEDIA_VIDEO
   - READ_MEDIA_VISUAL_USER_SELECTED
   - READ_EXTERNAL_STORAGE (maxSdkVersion="32")
   - WRITE_EXTERNAL_STORAGE (maxSdkVersion="32")
4. Confirm READ_EXTERNAL_STORAGE has android:maxSdkVersion="32" attribute
5. Confirm READ_MEDIA_VISUAL_USER_SELECTED has no maxSdkVersion (applies to all API 34+)
Expected: All permissions present, attributes correct
```

**PRE-DEPLOY TEST 2: flutter analyze passes**
```
Command: flutter analyze
Expected: No issues found
```

### Tier 2 — Post-deployment (run after app is built and installed)

**POST-DEPLOY TEST 1: Permissions appear in Android Settings (API 33+)**
```
Device: Android 13 emulator (API 33) or physical device, fresh install
Steps:
1. Build and install the app: flutter run -d <android-device>
2. Open Android Settings → Apps → BandRoadie → Permissions
3. Verify "Camera" permission entry is present
4. Verify "Photos and videos" permission entry is present
Expected: Both toggles visible and toggleable
```

**POST-DEPLOY TEST 2: Photo library permission dialog — full access (API 33)**
```
Device: Android 13 emulator (API 33), fresh install (no prior permissions granted)
Steps:
1. Launch app, navigate to Create/Edit Band screen
2. Tap avatar placeholder
3. Select "Photo Library" from the bottom sheet
4. Observe: Android system permission dialog appears
5. Tap "Allow"
6. Observe: System photo picker opens
7. Select any image
8. Observe: Image displayed in avatar, upload proceeds
Expected: Permission dialog → photo picker → successful upload
```

**POST-DEPLOY TEST 3: Camera permission dialog (API 33)**
```
Device: Android 13 emulator (API 33), fresh install
Steps:
1. Launch app, navigate to Create/Edit Band screen
2. Tap avatar placeholder
3. Select "Take Photo" from the bottom sheet
4. Observe: Android camera permission dialog appears
5. Tap "Allow"
6. Observe: Camera view opens
7. Capture photo and confirm
Expected: Permission dialog → camera view → photo captured
```

**POST-DEPLOY TEST 4: Android 14 partial access ("Select photos") dialog (API 34+)**
```
Device: Android 14+ emulator (API 34+) or physical device, fresh install
Steps:
1. Launch app, navigate to Create/Edit Band screen
2. Tap avatar placeholder → "Photo Library"
3. Observe: Permission dialog shows three options:
   "Allow all", "Select photos", "Don't allow"
4. Tap "Select photos"
5. System photo picker opens; select 1 image
6. Observe: Selected image is uploaded and displayed in avatar
Expected: Three-option dialog present; partial access granted; image upload succeeds
```

**POST-DEPLOY TEST 5: Permission denial handling — snack bar path**
```
Device: Android 13 emulator (API 33)
Steps:
1. Clear app data to reset permissions
2. Launch app → Create/Edit Band → tap avatar → "Photo Library"
3. When permission dialog appears, tap "Don't allow"
4. Observe: App shows snack bar: "Photo library permission is required"
5. Avatar does not change
Expected: Graceful denial with informative snack bar; no crash
```

**POST-DEPLOY TEST 6: Permission denial handling — permanent denial / Open Settings**
```
Device: Android 13 emulator (API 33)
Steps:
1. Deny photo permission twice (to trigger isPermanentlyDenied)
2. Tap avatar → "Photo Library" again
3. Observe: Dialog appears with title "Photo Library Access Required"
   and "Open Settings" button
4. Tap "Open Settings"
5. Observe: Android Settings → BandRoadie Permissions opens
Expected: Settings dialog appears; Settings opens correctly
```

**POST-DEPLOY TEST 7: Android 12 backward compatibility (API 32)**
```
Device: Android 12 emulator (API 32)
Steps:
1. Build and install app
2. Navigate to Create/Edit Band screen
3. Tap avatar → "Photo Library"
4. Observe: Storage permission dialog appears (not READ_MEDIA_IMAGES)
5. Grant permission → photo picker opens
6. Select image → upload succeeds
Expected: Legacy READ_EXTERNAL_STORAGE permission works; photo picker functional
```

**POST-DEPLOY TEST 8: iOS and web — no regression**
```
Devices: iOS simulator, web browser
Steps:
1. Build and run on iOS simulator
2. Navigate to Create/Edit Band → tap avatar → "Photo Library"
3. Verify iOS photo picker works as before
4. Repeat on web (browser file picker)
Expected: No regressions; platforms behave identically to before fix
```

---

## QA Regression Areas

### Primary Validation (Required)

1. **Android Photo Permissions** (directly fixed):
   - Permission dialogs appear on Android 13+ (API 33)
   - Three-option dialog (including "Select photos") appears on Android 14+ (API 34+)
   - Legacy storage permissions work on Android 12 and below (API ≤ 32)
   - Permissions toggles visible in Android Settings → Apps → BandRoadie → Permissions
   - Denial handled gracefully (snack bar, then "Open Settings" after permanent denial)
   - Photo upload succeeds end-to-end after permission grant

2. **Band Management** (directly affected):
   - Create band with photo on Android
   - Edit existing band photo on Android
   - Avatar displays selected image after upload

### Regression Areas (Ensure No Breaks)

3. **Camera access on Android**:
   - "Take Photo" flow opens camera after permission grant
   - Camera permission denial handled with snack bar / Open Settings dialog

4. **iOS Photo Permissions** (platform isolation):
   - Photo picker works on iOS (unchanged)
   - No new permission prompts or errors introduced

5. **Web File Picker** (platform isolation):
   - Web file picker works in browser (unchanged)
   - No manifest permission errors on web

6. **Notification Permissions** (adjacent permission — must not be disturbed):
   - `POST_NOTIFICATIONS` still declared and functional
   - Push notification permission flow unaffected

---

## Rollout / Migration Strategy

**Deployment type:** Client-side app update (Google Play Store).

**Rollback:** Not applicable — adding permissions is additive and cannot break existing
functionality. If any issue arises, users can deny the new permissions in Android Settings
without affecting other app features.

**Staged rollout (recommended):**
1. **Internal testing:** Build and test on API 32, 33, 34 emulators
2. **Alpha/Beta:** Deploy to 10–20 Android testers across different API levels
3. **Production:** Full Google Play Store release

**Note on the prior unmerged branch:** Do not merge or cherry-pick from
`bug/android-dashboard-freeze-photo-permissions`. That branch is missing
`READ_MEDIA_VISUAL_USER_SELECTED`. The Engineer must implement this plan fresh from `main`.

---

## Out of Scope

1. **iOS permissions** — `ios/Runner/Info.plist` already has correct photo permissions; iOS is unaffected
2. **Dashboard navigation freeze** — Investigated in prior plan; unrelated to permissions
3. **Permission pre-check redundancy on API 33+** — `image_picker` 1.2.x uses the system photo picker (permission-free) on Android 13+, making the `Permission.photos.request()` pre-check redundant. Removing it is a UX/architecture decision that is separate from this bug fix and must not be done here
4. **Video upload** — `READ_MEDIA_VIDEO` is added for manifest completeness; no video upload UI exists
5. **Profile photo feature** — Not currently implemented; these permissions enable it when built
6. **Bulk image upload** — Not in scope; single image selection only
7. **Image compression settings** — `maxWidth: 512, maxHeight: 512, imageQuality: 85` unchanged
8. **`file_picker` permissions** — `data_backup_service.dart` uses `file_picker` for backup export; that package manages its own storage access and is not affected
9. **macOS permissions** — macOS uses a separate entitlements file; not affected

---

**ARCHITECT SIGN-OFF:** Root cause confirmed at HIGH confidence. The fix is a single-file,
additive-only Android manifest change. The existing Dart permission-handling code is correct
and requires no modification. The prior fix branch had 5 of the 6 required permissions and
was never merged; this plan adds the missing `READ_MEDIA_VISUAL_USER_SELECTED` for Android
14+ and supersedes that branch.
