# Cross-Platform Notification Permission Flow

## Overview

This implementation provides a platform-aware notification permission flow for BandRoadie that:
- Respects user intent at all times
- Never spams or re-prompts automatically
- Keeps in-app notification toggle in sync with OS permission reality
- Works correctly on iOS, Android (API 33+), and Web platforms
- Gracefully handles Android <33 (no runtime permission required)

## Architecture

### Components

1. **NotificationPermissionService** (`notification_permission_service.dart`)
   - Manages persistent local state using SharedPreferences
   - Tracks platform-specific system permission status (iOS, Android, Web)
   - Provides methods for permission requests and state management
   - Platform-specific logic properly guarded with kIsWeb and Platform checks

2. **NotificationPrePermissionModal** (`widgets/notification_pre_permission_modal.dart`)
   - Custom modal shown BEFORE requesting system permission
   - Explains value of notifications to the user
   - Only shown once (respects dismissal)
   - Works on iOS, Android API 33+, and Web

3. **NotificationSettingsModal** (`widgets/notification_settings_modal.dart`)
   - Shown when user tries to enable notifications but system permission is denied
   - Provides "Open Settings" deep link to system Settings (iOS/Android)
   - Platform-safe (no-op on Web)

4. **WebNotificationPermission** (conditional exports)
   - `web_notification_permission_web.dart`: Uses dart:html Notification API
   - `web_notification_permission_stub.dart`: No-op for non-web platforms
   - Handles browser permission checks and requests

4. **NotificationSettingsScreen** (updated `notification_settings_screen.dart`)
   - Master toggle reflects both user intent AND system permission reality
   - Shows appropriate modals based on permission state
   - Never allows toggle to be ON when system permission is denied

## State Management

### Persisted State (SharedPreferences)

```dart
notifications_prompt_dismissed: boolean  // Default: false
notifications_enabled_in_app: boolean    // Default: true
```

### Runtime State

```dart
class NotificationPermissionState {
  final bool promptDismissed;              // Custom modal dismissed
  final bool enabledInApp;                 // User's in-app intent
  final NotificationPermissionStatus systemPermission;  // Platform-specific state
}

enum NotificationPermissionStatus {
  notDetermined,     // Permission not requested yet (iOS, Android 33+, Web)
  granted,           // User granted permission
  denied,            // User denied permission (can change in Settings)
  permanentlyDenied, // User permanently denied (Android only - denied twice)
  notApplicable,     // No runtime permission needed (Android <33, desktop)
}
```

## User Flow

### First App Launch

1. User opens app for first time
2. After authentication, `AppShell` shows custom pre-permission modal
3. Modal explains why notifications are useful
4. User choices:
   - **"Enable notifications"** → Triggers platform-specific permission dialog
     - **iOS**: Firebase authorization dialog
     - **Android 33+**: POST_NOTIFICATIONS system dialog
     - **Web**: Browser Notification.requestPermission()
     - If **granted**: `enabledInApp = true`, `promptDismissed = true`
     - If **denied**: `enabledInApp = false`, `promptDismissed = true`
   - **"Not now"** → `enabledInApp = false`, `promptDismissed = true`
   - Modal never shows again automatically

### Settings Toggle Behavior

#### User Turns Toggle OFF:
- Sets `enabledInApp = false`
- No system dialogs or prompts shown
- Simple state update

#### User Turns Toggle ON:
```dart
if (systemPermission == granted) {
  // Just enable
  enabledInApp = true
}

if (systemPermission == denied || systemPermission == permanentlyDenied) {
  // Show "Open Settings" modal (iOS/Android only)
  // Keep enabledInApp = false
  // User must go to system Settings to fix
}

if (systemPermission == notDetermined) {
  // Trigger platform-specific permission dialog
  // Update enabledInApp based on result
}

if (systemPermission == notApplicable) {
  // Android <33: Just use app-level toggle, no system permission needed
}
```

## Important Rules

### ✅ DO:
- Show custom pre-prompt ONCE before requesting system permission
- Respect user's dismissal of custom modal (never re-show automatically)
- Keep app toggle in sync with system permission reality
- Provide "Open Settings" guidance when permission is denied
- Check both `enabledInApp` AND `systemPermission` before delivering notifications

### ❌ DON'T:
- Never automatically open iOS Settings without explicit user action
- Never re-trigger iOS permission dialog after denial
- Never auto-show prompts on app launch once dismissed
- Never show app toggle as ON when system permission is denied
- Never spam the user with permission requests

## Platform Safety

All platform-specific code is properly guarded:

```dart
// iOS
if (kIsWeb || !Platform.isIOS) {
  return NotificationPermissionStatus.notApplicable;
}

// Android
if (kIsWeb || !Platform.isAndroid) {
  return NotificationPermissionStatus.notApplicable;
}

// Web
if (!kIsWeb) {
  return NotificationPermissionStatus.notApplicable;
}
```

Each platform has appropriate fallbacks for unsupported operations.

## Platform-Specific Implementations

### iOS
- **Permission Check**: Uses `firebase_messaging` package
- **API**: `FirebaseMessaging.instance.getNotificationSettings()`
- **Request**: `FirebaseMessaging.instance.requestPermission()`
- **Status Mapping**:
  - `AuthorizationStatus.authorized` → `granted`
  - `AuthorizationStatus.denied` → `denied`
  - `AuthorizationStatus.notDetermined` → `notDetermined`
- **Settings**: Opens via `openAppSettings()` to Settings → Notifications → BandRoadie

### Android
**API 33+ (Android 13+)**:
- **Permission Check**: Uses `permission_handler` package
- **Required Permission**: `POST_NOTIFICATIONS`
- **API**: `Permission.notification.status`
- **Request**: `Permission.notification.request()`
- **Status Mapping**:
  - `PermissionStatus.granted` → `granted`
  - `PermissionStatus.denied` → `denied`
  - `PermissionStatus.permanentlyDenied` → `permanentlyDenied`
  - `PermissionStatus.restricted` → `notDetermined`
- **Settings**: Opens via `openAppSettings()` to Settings → Apps → BandRoadie → Permissions

**API < 33 (Android 12 and below)**:
- **No Runtime Permission**: POST_NOTIFICATIONS doesn't exist
- **Status**: Always returns `notApplicable`
- **Behavior**: App-level toggle directly controls notification delivery

### Web
- **Permission Check**: Browser Notification API
- **API**: `Notification.permission` (returns: `granted`, `denied`, `default`)
- **Request**: `Notification.requestPermission()`
- **Conditional Import**: Uses `dart:html` only when targeting web
- **Status Mapping**:
  - `'granted'` → `granted`
  - `'denied'` → `denied`
  - `'default'` (or null) → `notDetermined`
- **Settings**: No deep link (browser controls permission state)

## Integration Points

### App Startup (`app_shell.dart`)
```dart
class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationPrePermissionModal.showIfNeeded(context, ref);
    });
  }
}
```

### Settings Screen
```dart
final permissionState = ref.watch(notificationPermissionStateProvider);
// Toggle reflects: enabledInApp && systemPermission == granted
```

### Notification Delivery Logic
```dart
// Server-side or client-side check
if (permissionState.shouldDeliverNotifications) {
  // Both app intent AND system permission are enabled
  sendNotification();
}
```

## Testing Checklist

- [ ] Custom pre-prompt shows on first app launch
- [ ] Pre-prompt never re-appears after dismissal
- [ ] "Enable" button triggers iOS system dialog
- [ ] "Not now" button dismisses permanently
- [ ] Settings toggle turns OFF without prompts
- [ ] Settings toggle turns ON (granted) → enables successfully
- [ ] Settings toggle turns ON (denied) → shows "Open Settings" modal
- [ ] Settings toggle turns ON (notDetermined) → shows iOS dialog
- [ ] "Open Settings" button opens iOS app settings
- [ ] Toggle always shows correct state (never ON when permission denied)
- [ ] Notification delivery respects both toggles
- [ ] Non-iOS platforms safely degrade

## Files Modified/Created

### New Files:
- `lib/features/notifications/notification_permission_service.dart`
- `lib/features/notifications/widgets/notification_pre_permission_modal.dart`
- `lib/features/notifications/widgets/notification_settings_modal.dart`

### Modified Files:
- `lib/features/notifications/notification_settings_screen.dart`
- `lib/features/shell/app_shell.dart`

## Dependencies

Uses existing packages:
- `shared_preferences` - For persistent state (all platforms)
- `firebase_messaging` - For iOS permission checks
- `permission_handler` - For Android permission checks and Settings deep link
- `dart:html` (conditional) - For Web browser Notification API

## Brand Voice

User-facing messages use friendly "roadie" humor:
- Pre-prompt: "Stay in the Loop" 
- Body: "Get notified when your band schedules gigs, rehearsals, or marks block-out dates. Stay coordinated and never miss an update."

## Testing Checklist

### iOS
- [ ] Fresh install shows custom pre-prompt after login
- [ ] "Enable notifications" triggers Firebase authorization dialog
- [ ] "Not now" dismisses modal and never shows again
- [ ] Denied permission shows "Open Settings" modal on toggle attempt
- [ ] `openAppSettings()` opens Settings → Notifications → BandRoadie
- [ ] Toggle stays OFF when system permission is denied

### Android API 33+
- [ ] Fresh install shows custom pre-prompt after login
- [ ] "Enable notifications" triggers POST_NOTIFICATIONS dialog
- [ ] Permanently denied (denied twice) shows "Open Settings" modal
- [ ] `openAppSettings()` opens Settings → Apps → BandRoadie → Permissions
- [ ] Toggle correctly reflects permission status

### Android API < 33
- [ ] No system permission dialog appears
- [ ] Toggle directly controls app-level preference
- [ ] Status returns `notApplicable`

### Web
- [ ] Fresh install shows custom pre-prompt after login
- [ ] "Enable notifications" triggers browser permission request
- [ ] Denied permission prevents toggle from turning ON
- [ ] No "Open Settings" option (browser manages permission)
- [ ] Works in Chrome, Firefox, Safari

## Notes

- This implementation prioritizes user respect over conversion rates
- Following platform guidelines prevents rejections (iOS App Store, Google Play)
- State is kept locally to avoid backend complexity
- The flow works consistently across iOS, Android, and Web
