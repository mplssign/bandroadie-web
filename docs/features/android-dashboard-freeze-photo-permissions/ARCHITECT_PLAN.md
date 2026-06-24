# ARCHITECT PLAN

## Feature Slug

`bug/android-dashboard-freeze-photo-permissions`

---

## Problem Summary

An Android user (Samsung Galaxy S23-series, Android 13+, app v1.2.22/182) reported two critical issues:

1. **Missing Photo Permissions**: The app never prompts for photo/media permissions, and no permission toggle appears in Android device Settings → Apps → BandRoadie → Permissions. This prevents users from uploading band photos or profile images.

2. **Dashboard Navigation Freeze**: The app hangs when navigating to the dashboard screen, requiring force-close.

Both issues were reported within 60 seconds, suggesting potential causal relationship.

---

## Root Cause

### ROOT CAUSE 1: Missing Android Manifest Permissions (CONFIRMED - HIGH Confidence)

**Location**: `android/app/src/main/AndroidManifest.xml`

**Diagnosis**: The AndroidManifest.xml declares only two permissions:

- `android.permission.POST_NOTIFICATIONS` (for push notifications)
- `android.permission.INTERNET` (for network access)

**Missing permissions required for photo functionality**:

**Android 13+ (API 33+)** — the user's OS version:

- `READ_MEDIA_IMAGES` — required to access photos from gallery
- `READ_MEDIA_VIDEO` — required if app will access videos (optional)
- `CAMERA` — required to take photos with camera

**Android 12 and below** (for backward compatibility):

- `READ_EXTERNAL_STORAGE` with `android:maxSdkVersion="32"` — legacy permission for pre-13 devices
- `WRITE_EXTERNAL_STORAGE` with `android:maxSdkVersion="32"` — legacy permission for pre-13 devices

**Impact**:

- When permissions are not declared in AndroidManifest.xml, Android never registers them for the app
- The permission toggle never appears in device Settings → Apps → BandRoadie → Permissions
- The `permission_handler` package's `Permission.photos.status` and `Permission.camera.status` fail silently or return incorrect status
- Users cannot grant permissions even if they want to
- Image picker fails when user tries to select band photos or profile images

**Evidence**:

- Code at `lib/features/bands/band_form_screen.dart:1186-1223` calls `Permission.photos.status` and `Permission.photos.request()`
- Code at `lib/features/bands/band_form_screen.dart:1139-1181` calls `Permission.camera.status` and `Permission.camera.request()`
- Both permission checks are properly implemented in the Flutter code, but fail because the manifest doesn't declare them
- User report confirms "the permission toggle is missing entirely from Android device Settings"

---

### ROOT CAUSE 2: Dashboard Freeze (UNCONFIRMED - LOW Confidence)

**Hypothesis**: Dashboard navigation hang is **likely unrelated** to the missing permissions.

**Reasoning**:

- Code review of `lib/features/home/home_screen.dart` shows no permission checks during dashboard initialization
- The `draftLocalImageProvider` watched by dashboard only reads state, does not trigger permission requests
- Permission checks in `band_form_screen.dart` are only called when user explicitly taps to pick an image
- No eager permission checking found in initialization path

**Alternative hypotheses (requires validation)**:

1. **Database query timeout**: One of the Riverpod providers (`activeBandProvider`, `gigProvider`, `rehearsalProvider`, `currentUserPermissionsProvider`) experiences a hanging Supabase query
2. **Race condition**: Multiple providers watching each other create a state deadlock
3. **Device-specific issue**: Samsung S23 on Android 13+ has Flutter rendering or state management quirks
4. **Network timeout**: Poor connectivity causes Supabase queries to hang without proper timeout handling
5. **Residual error state**: If user triggered photo permission failure before navigating to dashboard, app might be in corrupted state

**Recommendation**: Fix the confirmed permissions issue first. If dashboard freeze persists after permissions are added, conduct targeted investigation with device logs, Supabase query logs, and user reproduction steps.

---

## Reference Docs Consulted

- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — Platform configuration reference
- `docs/reference/architecture/architecture.md` — App architecture and initialization order
- `docs/agents/GUARDRAILS.md` — Platform safety constraints
- No specific Android permissions reference docs exist in `docs/reference/`

---

## Existing System Analysis

### Current Behavior

**Photo Access Flow**:

1. User navigates to Create/Edit Band screen
2. User taps band avatar to change photo
3. Bottom sheet appears with "Take Photo" or "Photo Library" options
4. User selects option → `_pickImage()` is called
5. Code checks permission via `_checkCameraPermission()` or `_checkPhotoLibraryPermission()`
6. `permission_handler` package queries Android for permission status
7. **FAILURE**: Because permissions are not declared in manifest, Android returns unexpected status
8. Permission dialog never appears, or permission check fails
9. Image picker never launches
10. User sees error or nothing happens

**Dashboard Navigation Flow**:

1. User taps bottom nav to navigate to dashboard
2. `HomeScreen` widget builds
3. `initState()` calls `ref.read(activeBandProvider.notifier).loadUserBands()`
4. `initState()` calls `_loadUserProfile()` to fetch user name from Supabase
5. `build()` method watches multiple providers: `activeBandProvider`, `gigProvider`, `rehearsalProvider`, `setlistsProvider`, `currentUserPermissionsProvider`, `displayBandProvider`, `draftLocalImageProvider`
6. Each provider fetches data from Supabase asynchronously
7. **SUSPECTED FAILURE POINT**: One of these async operations hangs, preventing dashboard from rendering
8. User sees frozen UI, app becomes unresponsive

**Key Code Locations**:

- Permissions: `lib/features/bands/band_form_screen.dart:1139-1223`
- Dashboard: `lib/features/home/home_screen.dart:54-450`
- Active Band Controller: `lib/features/bands/active_band_controller.dart`
- Permissions Provider: `lib/features/members/permissions/band_permissions_provider.dart`

---

## Proposed Solution

### Phase 1: Fix Missing Permissions (Immediate - HIGH Priority)

**File**: `android/app/src/main/AndroidManifest.xml`

**Add permission declarations after existing permissions**:

```xml
<!-- Required for push notifications on Android 13+ (API 33+) -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<!-- Required for Firebase Cloud Messaging -->
<uses-permission android:name="android.permission.INTERNET"/>

<!-- NEW: Camera and Media Permissions for Band/Profile Photos -->
<!-- Android 13+ (API 33+) uses granular media permissions -->
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>

<!-- Android 12 and below use legacy storage permissions -->
<!-- maxSdkVersion ensures these are ignored on Android 13+ -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
```

**Rationale**:

- Android 13+ (API 33) replaced `READ_EXTERNAL_STORAGE` with granular permissions (`READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`)
- Using `maxSdkVersion="32"` ensures legacy permissions only apply to pre-13 devices
- Including both legacy and modern permissions ensures all Android versions are covered
- `CAMERA` permission required for `ImageSource.camera` in image picker
- These are standard permissions for photo-enabled apps, low user friction

### Phase 2: Add Dashboard Diagnostic Logging (Conditional - LOW Priority)

**Only implement if dashboard freeze persists after Phase 1**

**File**: `lib/features/home/home_screen.dart`

**Add debug logging in `initState()` and provider watch callbacks**:

- Log when `activeBandProvider.loadUserBands()` starts/completes
- Log when `_loadUserProfile()` starts/completes
- Add timeout wrappers around Supabase queries (10-second timeout)
- Log provider state transitions (loading → data/error)

**Rationale**: Provides observable data for diagnosing hang location if issue persists

---

## Database Impact

**Database: NOT APPLICABLE**

No database schema, RLS policies, RPC functions, or triggers are modified. This is purely a client-side Android platform configuration change.

---

## Flutter Architecture Changes

**State Management**: No changes to Riverpod providers or controllers.

**Widgets**: No changes to UI components.

**Repositories**: No changes to data access layer.

**Services**: No changes to permission handling logic in `band_form_screen.dart` — the existing `_checkCameraPermission()` and `_checkPhotoLibraryPermission()` methods will work correctly once manifest permissions are added.

**Platform**: Android manifest configuration only.

---

## Files to Create

**None** — this fix modifies an existing platform configuration file only.

---

## Files to Modify

| File                                       | What changes                                                                                                                                                |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `android/app/src/main/AndroidManifest.xml` | Add 5 permission declarations: `CAMERA`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_EXTERNAL_STORAGE` (maxSdk=32), `WRITE_EXTERNAL_STORAGE` (maxSdk=32) |

---

## Files Off-Limits

| File                                       | Reason                                                                                   |
| ------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `lib/main.dart`                            | Initialization order must not change (Guardrail #1)                                      |
| `lib/features/bands/band_form_screen.dart` | Permission handling logic is already correct; only manifest needs fixing                 |
| `lib/features/home/home_screen.dart`       | Dashboard code is not the root cause; do not modify unless freeze persists after Phase 1 |
| `pubspec.yaml`                             | No dependency changes required; `permission_handler: ^11.3.1` already present            |
| `ios/Runner/Info.plist`                    | iOS permissions already configured (not affected by this bug)                            |
| `android/app/build.gradle.kts`             | No build configuration changes required                                                  |

---

## System Impact Map

| System             | Impact                                                                            |
| ------------------ | --------------------------------------------------------------------------------- |
| Gigs               | **unaffected** — gig features do not use photo permissions                        |
| Rehearsals         | **unaffected** — rehearsal features do not use photo permissions                  |
| Setlists / Catalog | **unaffected** — setlist features do not use photo permissions                    |
| Members / RBAC     | **unaffected** — member features do not use photo permissions                     |
| Auth / Session     | **unaffected** — no auth flow changes                                             |
| Routing            | **unaffected** — no navigation changes                                            |
| Notifications      | **unaffected** — notification permissions already declared correctly              |
| Platform (iOS)     | **unaffected** — iOS Info.plist already has required photo permissions            |
| Platform (Android) | **affected** — manifest permissions added, enables photo access on Android        |
| Platform (Web)     | **unaffected** — web uses browser file picker, no manifest permissions            |
| Platform (macOS)   | **unaffected** — macOS has separate entitlements file                             |
| Band Management    | **affected** — users can now upload band photos on Android                        |
| Profile Management | **affected** — users can now upload profile photos on Android (if feature exists) |

---

## Regression Risk

**LEVEL: LOW**

**Rationale**:

- **Single file change**: Only modifying `AndroidManifest.xml`
- **Additive change**: Adding permissions does not modify existing functionality
- **No code changes**: Zero Dart/Flutter code modifications
- **No state management changes**: Riverpod providers untouched
- **No database changes**: No migrations, RLS, or RPCs
- **Platform-isolated**: Only affects Android; iOS, web, macOS unaffected
- **Standard permissions**: Camera and media permissions are common, low-friction for users
- **Existing code validated**: Flutter permission-handling code in `band_form_screen.dart` is already correct

**Risk areas**:

- **User permission prompts**: Users will see permission dialogs when first attempting to access camera or photos (expected behavior, not a regression)
- **App size**: Minimal increase from additional manifest entries (negligible)
- **Review process**: Google Play may flag new permissions (standard process, not a blocker)

---

## Engineer Task Breakdown

### Task 1: Add Camera Permission to AndroidManifest.xml

- Open `android/app/src/main/AndroidManifest.xml`
- After line 4 (`<uses-permission android:name="android.permission.INTERNET"/>`), add blank line
- Insert comment: `<!-- NEW: Camera and Media Permissions for Band/Profile Photos -->`
- Insert: `<uses-permission android:name="android.permission.CAMERA"/>`

### Task 2: Add Android 13+ Media Permissions

- Below `CAMERA` permission, add comment: `<!-- Android 13+ (API 33+) uses granular media permissions -->`
- Insert: `<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>`
- Insert: `<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>`

### Task 3: Add Legacy Storage Permissions for Android 12 and Below

- Add blank line
- Insert comment: `<!-- Android 12 and below use legacy storage permissions -->`
- Insert comment: `<!-- maxSdkVersion ensures these are ignored on Android 13+ -->`
- Insert: `<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>`
- Insert: `<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>`

### Task 4: Verify XML Formatting

- Ensure proper indentation (4 spaces per level)
- Verify no syntax errors (XML well-formed)
- Confirm closing tags match

### Task 5: Test on Android Emulator (API 33+)

- Run `flutter run -d android` with Android 13+ emulator
- Navigate to Create/Edit Band screen
- Tap avatar to change photo
- Tap "Photo Library" → verify permission dialog appears
- Grant permission → verify image picker opens
- Select photo → verify photo uploads successfully
- Tap "Take Photo" → verify camera permission dialog appears
- Grant permission → verify camera opens

### Task 6: Test on Android Emulator (API 32 and below)

- Run with Android 12 emulator
- Verify legacy storage permissions are used
- Verify image picker works correctly

### Task 7: Verify Android Settings Integration

- Open Android Settings → Apps → BandRoadie → Permissions
- Verify "Camera" permission toggle is present
- Verify "Photos and videos" or "Files and media" permission toggle is present
- Toggle permissions off/on → verify app respects settings

### Task 8: Smoke Test Dashboard Navigation

- After permissions fix is deployed
- Navigate between tabs multiple times
- Navigate to dashboard from other screens
- Verify no freeze or hang occurs
- If freeze persists, escalate to Architect for Phase 2 investigation

---

## Verification Plan

### Tier 1 — Pre-deployment (Manual Testing)

This is a client-side Android platform configuration change with no backend dependencies. All verification is manual device/emulator testing.

**Test 1: Verify permissions appear in Android Settings**

```
Device: Android 13+ emulator (API 33)
Steps:
1. Install app with new manifest
2. Open Android Settings → Apps → BandRoadie → Permissions
3. Verify "Camera" permission entry exists
4. Verify "Photos and videos" or "Files and media" permission entry exists
5. Verify toggles can be enabled/disabled
Expected: All permission toggles present and functional
```

**Test 2: Verify photo library permission request**

```
Device: Android 13+ emulator (API 33), fresh install (no prior permissions)
Steps:
1. Launch app, navigate to Create Band screen
2. Tap avatar placeholder
3. Select "Photo Library" from bottom sheet
4. Observe: Android permission dialog appears requesting "Photos and videos" access
5. Tap "Allow" or "Only this time"
6. Observe: System photo picker opens
7. Select any image
8. Observe: Image uploads successfully, avatar displays selected image
Expected: Permission dialog → photo picker → successful upload
```

**Test 3: Verify camera permission request**

```
Device: Android 13+ emulator (API 33), fresh install
Steps:
1. Launch app, navigate to Create Band screen
2. Tap avatar placeholder
3. Select "Take Photo" from bottom sheet
4. Observe: Android permission dialog appears requesting "Camera" access
5. Tap "Allow"
6. Observe: Camera view opens
7. Take photo, confirm
8. Observe: Image uploads successfully, avatar displays captured image
Expected: Permission dialog → camera → successful upload
```

**Test 4: Verify permission denial handling**

```
Device: Android 13+ emulator
Steps:
1. Clear app data to reset permissions
2. Launch app, navigate to Create Band screen
3. Tap avatar → select "Photo Library"
4. When permission dialog appears, tap "Don't allow"
5. Observe: Permission denied dialog appears with "Open Settings" button
6. Tap "Open Settings" → verify Android Settings opens to BandRoadie permissions
Expected: Graceful permission denial handling with Settings redirect
```

**Test 5: Verify backward compatibility (Android 12 and below)**

```
Device: Android 12 emulator (API 32)
Steps:
1. Install app
2. Navigate to Create Band screen
3. Tap avatar → select "Photo Library"
4. Observe: Permission dialog requests "Storage" or "Files and media" access
5. Grant permission → verify photo picker works
Expected: Legacy permissions work on pre-13 devices
```

**Test 6: Verify no regression on other platforms**

```
Devices: iOS simulator, web browser, macOS app
Steps:
1. Run app on each platform
2. Navigate to Create Band screen
3. Tap avatar → select photo
4. Verify photo picker works as before
Expected: No regressions on non-Android platforms
```

---

### Tier 2 — Post-deployment (User Validation)

**Test 1: Verify fix with original reporter**

```
Contact: Ben Seay (band: Squish)
Device: Samsung Galaxy S23-series, Android build BP4A.251205.006.S931USQUACZF1
Steps:
1. Confirm app version 1.2.23+ (next build) is installed
2. Open Android Settings → Apps → BandRoadie → Permissions
3. Verify "Camera" and "Photos and videos" permissions now appear
4. Navigate to dashboard
5. Verify no freeze occurs
6. Navigate to Edit Band screen
7. Attempt to change band photo
8. Verify permission prompt appears and photo upload works
Expected: Both issues resolved for original reporter
```

**Test 2: Monitor Sentry/Firebase for new permission errors**

```
Timeline: 7 days post-deployment
Action:
- Monitor crash reports for permission-related exceptions
- Monitor ANR (Application Not Responding) reports for dashboard navigation
- Query Supabase logs for hanging queries from affected users
Expected: No new permission failures, dashboard navigation stable
```

---

## QA Regression Areas

### Primary Validation (Required)

1. **Android Photo Permissions** (affected system):
   - Permission dialogs appear when accessing camera/photos on Android 13+
   - Permission dialogs appear when accessing camera/photos on Android 12 and below (legacy storage permissions)
   - Permissions appear in Android Settings → Apps → BandRoadie → Permissions
   - Denying permission shows appropriate error dialog with "Open Settings" button
   - Granting permission allows image picker to open
   - Selected/captured photos upload successfully
   - Band avatar updates with new photo

2. **Dashboard Navigation** (suspected issue):
   - Navigate to dashboard from login screen
   - Navigate to dashboard from other tabs (setlists, calendar, members, contacts)
   - Switch between bands and navigate to dashboard
   - Test on Samsung S23 or similar device if available
   - Test with poor network connectivity (airplane mode → wifi)
   - Verify no freezes, hangs, or ANR errors

3. **Band Management** (directly affected):
   - Create new band with photo on Android
   - Edit existing band photo on Android
   - Delete band photo on Android
   - Verify avatar generates correctly when no photo is set

### Regression Testing (Ensure No Breaks)

4. **iOS Photo Permissions** (platform isolation check):
   - Verify iOS Info.plist permissions unchanged
   - Verify photo picker works on iOS
   - Verify no new permission prompts or errors

5. **Web Photo Picker** (platform isolation check):
   - Verify web file picker works (no manifest permissions)
   - Verify photo upload works on web

6. **Notification Permissions** (adjacent permission check):
   - Verify notification permission dialog still appears on first launch (Android 13+)
   - Verify notifications can be enabled/disabled in Settings screen
   - Verify push notifications still deliver correctly

7. **Cross-Platform Parity** (general smoke test):
   - Create band with photo on iOS → verify visible on Android
   - Create band with photo on Android → verify visible on iOS
   - Create band with photo on web → verify visible on all platforms

---

## Rollout / Migration Strategy

**Deployment Type**: Client-side app update (Google Play Store release)

**Rollback Plan**: Not applicable — permission declarations are additive and cannot break existing functionality. If issues arise, users can manually deny permissions in Settings.

**Staged Rollout Recommendation**:

1. **Alpha**: Internal team testing on multiple Android devices (API 30-34)
2. **Beta**: Small user group (50-100 users) for 3-5 days
3. **Production**: Full release to Google Play Store

**User Communication**: Optional release notes:

> "🎸 Android users can now upload band photos and profile images! The app will request camera and photo permissions when you try to change your band avatar."

---

## Out of Scope

### Explicitly NOT Included in This Fix

1. **Dashboard freeze investigation** — Will only be addressed if issue persists after permissions fix
2. **Permission UI/UX improvements** — Current permission dialog flow is standard Android behavior
3. **Profile photo feature** — This fix enables infrastructure, but profile photo UI may not exist yet
4. **Video upload support** — `READ_MEDIA_VIDEO` permission added for future-proofing, but video upload not implemented
5. **iOS permission improvements** — iOS permissions already working correctly
6. **Web file picker enhancements** — Web works differently (browser file picker), no manifest changes
7. **Permission analytics** — Tracking permission grant/deny rates not in scope
8. **Bulk image uploads** — Single image selection only; batch upload not addressed
9. **Image compression optimization** — Current `maxWidth: 512, maxHeight: 512, imageQuality: 85` unchanged
10. **Storage permission for other features** — This fix only addresses band/profile photo upload; other potential storage use cases (e.g., setlist export to file) not evaluated

---

**ARCHITECT SIGN-OFF**: This plan addresses the confirmed root cause (missing Android permissions) with minimal risk and surgical precision. The dashboard freeze issue requires user validation post-fix to determine if further investigation is needed.
