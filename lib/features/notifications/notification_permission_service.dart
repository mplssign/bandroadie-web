import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'web_notification_permission.dart';

// ============================================================================
// NOTIFICATION PERMISSION SERVICE
// Cross-platform notification permission flow (iOS, Android, Web)
// Respects user intent and platform-specific permission models
// ============================================================================

/// Keys for persistent local state
const String _kNotificationsEnabledInApp = 'notifications_enabled_in_app';

/// Cross-platform notification permission status
enum NotificationPermissionStatus {
  /// Permission not requested yet (iOS, Android 13+, Web)
  notDetermined,

  /// User granted permission
  granted,

  /// User denied permission (can request again)
  denied,

  /// Permission permanently denied (Android only - need Settings)
  permanentlyDenied,

  /// Not applicable (Android < 13 - no runtime permission needed

  /// Not applicable (non-iOS or web platform)
  notApplicable,
}

/// State for notification permissions
class NotificationPermissionState {
  /// Whether the user has dismissed the custom pre-prompt modal
  final bool promptDismissed;

  /// User's in-app toggle preference (represents their intent)
  final bool enabledInApp;

  /// iOS system permission status
  final NotificationPermissionStatus systemPermission;

  const NotificationPermissionState({
    required this.promptDismissed,
    required this.enabledInApp,
    required this.systemPermission,
  });

  NotificationPermissionState copyWith({
    bool? promptDismissed,
    bool? enabledInApp,
    NotificationPermissionStatus? systemPermission,
  }) {
    return NotificationPermissionState(
      promptDismissed: promptDismissed ?? this.promptDismissed,
      enabledInApp: enabledInApp ?? this.enabledInApp,
      systemPermission: systemPermission ?? this.systemPermission,
    );
  }

  /// Whether notifications should be delivered
  /// Must be true for both app intent AND system permission
  bool get shouldDeliverNotifications =>
      enabledInApp &&
      (systemPermission == NotificationPermissionStatus.granted ||
          systemPermission == NotificationPermissionStatus.notApplicable);
}

/// Provider for notification permission service
/// Access notifier methods via: ref.read(notificationPermissionProvider.notifier)
/// Watch state via: ref.watch(notificationPermissionProvider)
final notificationPermissionProvider =
    NotifierProvider<
      NotificationPermissionService,
      NotificationPermissionState
    >(NotificationPermissionService.new);

class NotificationPermissionService
    extends Notifier<NotificationPermissionState> {
  @override
  NotificationPermissionState build() {
    // Initialize state immediately (sync)
    // Async loading happens in _initialize()
    _initialize();

    return const NotificationPermissionState(
      promptDismissed: false, // No longer used, kept for state compatibility
      enabledInApp: true, // Default to true (user intent starts positive)
      systemPermission: NotificationPermissionStatus.notDetermined,
    );
  }

  /// Initialize by loading persisted state
  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // Load persisted local state
    final enabledInApp = prefs.getBool(_kNotificationsEnabledInApp) ?? true;

    // Check system permission (platform-specific)
    final systemPermission = await _getSystemPermissionStatus();

    state = NotificationPermissionState(
      promptDismissed: false, // No longer used
      enabledInApp: enabledInApp,
      systemPermission: systemPermission,
    );

    debugPrint(
      '[NotificationPermissionService] Initialized: '
      'enabledInApp=$enabledInApp, '
      'systemPermission=$systemPermission',
    );
  }

  /// Get the system permission status for the current platform
  /// iOS: Uses Firebase Messaging authorization status
  /// Android 13+: Uses POST_NOTIFICATIONS permission
  /// Android < 13: Returns notApplicable (no runtime permission)
  /// Web: Uses browser Notification API permission
  Future<NotificationPermissionStatus> _getSystemPermissionStatus() async {
    // WEB: Use browser Notification API
    if (kIsWeb) {
      return _getWebPermissionStatus();
    }

    // MOBILE: Platform-specific checks
    if (Platform.isIOS) {
      return _getIOSPermissionStatus();
    } else if (Platform.isAndroid) {
      return _getAndroidPermissionStatus();
    }

    // Other platforms (macOS, Linux, Windows) - not applicable
    return NotificationPermissionStatus.notApplicable;
  }

  /// Get iOS permission status using Firebase Messaging
  Future<NotificationPermissionStatus> _getIOSPermissionStatus() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();

      switch (settings.authorizationStatus) {
        case AuthorizationStatus.notDetermined:
          return NotificationPermissionStatus.notDetermined;
        case AuthorizationStatus.authorized:
        case AuthorizationStatus.provisional:
          return NotificationPermissionStatus.granted;
        case AuthorizationStatus.denied:
          return NotificationPermissionStatus.denied;
      }
    } catch (e) {
      // Firebase not initialized yet - this is normal on first launch
      // Return notApplicable so the app doesn't crash
      debugPrint(
        '[NotificationPermissionService] Error checking iOS permission: $e',
      );
      debugPrint(
        '[NotificationPermissionService] Note: Firebase may not be initialized yet',
      );
      return NotificationPermissionStatus.notApplicable;
    }
  }

  /// Get Android permission status
  /// Android 13+ (API 33+): Uses POST_NOTIFICATIONS runtime permission
  /// Android < 13: No runtime permission needed (returns notApplicable)
  Future<NotificationPermissionStatus> _getAndroidPermissionStatus() async {
    try {
      final status = await Permission.notification.status;

      // Check if runtime permission is even required (Android 13+)
      if (status.isLimited) {
        // Android < 13 - no runtime permission needed
        return NotificationPermissionStatus.notApplicable;
      }

      if (status.isGranted) {
        return NotificationPermissionStatus.granted;
      } else if (status.isPermanentlyDenied) {
        return NotificationPermissionStatus.permanentlyDenied;
      } else if (status.isDenied) {
        return NotificationPermissionStatus.denied;
      } else {
        // Not yet requested
        return NotificationPermissionStatus.notDetermined;
      }
    } catch (e) {
      debugPrint(
        '[NotificationPermissionService] Error checking Android permission: $e',
      );
      // If API not available, assume no runtime permission needed (older Android)
      return NotificationPermissionStatus.notApplicable;
    }
  }

  /// Get Web notification permission status using browser API
  Future<NotificationPermissionStatus> _getWebPermissionStatus() async {
    try {
      final permission = await checkWebNotificationPermission();

      switch (permission) {
        case 'granted':
          return NotificationPermissionStatus.granted;
        case 'denied':
          return NotificationPermissionStatus.denied;
        case 'default':
        default:
          return NotificationPermissionStatus.notDetermined;
      }
    } catch (e) {
      debugPrint(
        '[NotificationPermissionService] Error checking web permission: $e',
      );
      return NotificationPermissionStatus.notDetermined;
    }
  }

  /// Refresh system permission status (call after permission changes)
  Future<void> refreshSystemPermission() async {
    final systemPermission = await _getSystemPermissionStatus();
    state = state.copyWith(systemPermission: systemPermission);
  }

  // --------------------------------------------------------------------------
  // USER ACTIONS
  // --------------------------------------------------------------------------

  /// User toggled notifications OFF in settings
  /// Just update app state, DON'T trigger any permission requests
  Future<void> disableNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotificationsEnabledInApp, false);

    state = state.copyWith(enabledInApp: false);

    debugPrint(
      '[NotificationPermissionService] User disabled notifications in app',
    );
  }

  /// User toggled notifications ON in settings
  /// Handle based on system permission status (platform-specific)
  Future<NotificationToggleResult> enableNotifications() async {
    final systemPermission = await _getSystemPermissionStatus();

    // Case 1: System permission already granted
    if (systemPermission == NotificationPermissionStatus.granted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kNotificationsEnabledInApp, true);

      state = state.copyWith(enabledInApp: true);

      debugPrint(
        '[NotificationPermissionService] Enabled (permission already granted)',
      );
      return NotificationToggleResult.enabled;
    }

    // Case 2: System permission denied (user must go to Settings)
    if (systemPermission == NotificationPermissionStatus.denied) {
      debugPrint(
        '[NotificationPermissionService] Cannot enable: system permission denied',
      );
      return NotificationToggleResult.needsSystemSettings;
    }

    // Case 3: Android permanently denied (must go to Settings)
    if (systemPermission == NotificationPermissionStatus.permanentlyDenied) {
      debugPrint(
        '[NotificationPermissionService] Cannot enable: permission permanently denied',
      );
      return NotificationToggleResult.needsSystemSettings;
    }

    // Case 4: System permission not determined (show system dialog)
    if (systemPermission == NotificationPermissionStatus.notDetermined) {
      final granted = await _requestSystemPermission();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kNotificationsEnabledInApp, granted);

      final newSystemPermission = await _getSystemPermissionStatus();

      state = state.copyWith(
        enabledInApp: granted,
        systemPermission: newSystemPermission,
      );

      debugPrint(
        '[NotificationPermissionService] Permission requested from toggle: '
        'granted=$granted',
      );

      return granted
          ? NotificationToggleResult.enabled
          : NotificationToggleResult.denied;
    }

    // Case 5: No runtime permission needed (Android < 13, other platforms)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotificationsEnabledInApp, true);

    state = state.copyWith(enabledInApp: true);

    return NotificationToggleResult.enabled;
  }

  /// Request system notification permission (platform-specific)
  /// iOS: Firebase Messaging
  /// Android 13+: POST_NOTIFICATIONS permission
  /// Web: Browser Notification API
  Future<bool> _requestSystemPermission() async {
    if (kIsWeb) {
      return _requestWebPermission();
    }

    if (Platform.isIOS) {
      return _requestIOSPermission();
    } else if (Platform.isAndroid) {
      return _requestAndroidPermission();
    }

    return false;
  }

  /// Request iOS system notification permission via Firebase
  Future<bool> _requestIOSPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false, // Require explicit user approval
      );

      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      return granted;
    } catch (e) {
      debugPrint(
        '[NotificationPermissionService] Error requesting iOS permission: $e',
      );
      debugPrint(
        '[NotificationPermissionService] Note: Firebase may not be initialized yet',
      );
      debugPrint(
        '[NotificationPermissionService] To fix: Initialize Firebase in main.dart with Firebase.initializeApp()',
      );
      return false;
    }
  }

  /// Request Android notification permission (Android 13+ only)
  Future<bool> _requestAndroidPermission() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (e) {
      debugPrint(
        '[NotificationPermissionService] Error requesting Android permission: $e',
      );
      return false;
    }
  }

  /// Request Web notification permission via browser API
  Future<bool> _requestWebPermission() async {
    try {
      return await requestWebNotificationPermission();
    } catch (e) {
      debugPrint(
        '[NotificationPermissionService] Error requesting web permission: $e',
      );
      return false;
    }
  }
}

/// Result of attempting to enable notifications via toggle
enum NotificationToggleResult {
  /// Successfully enabled
  enabled,

  /// User denied permission in iOS dialog
  denied,

  /// System permission is denied, user must open iOS Settings
  needsSystemSettings,
}
