import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_repository.dart';

// ============================================================================
// PUSH NOTIFICATION SERVICE
// Handles FCM integration, token management, and foreground notifications
// ============================================================================

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();
  debugPrint(
    '[PushNotificationService] Background message: ${message.messageId}',
  );

  // Silent notifications (data-only) trigger background refresh
  // The app will sync when opened via onMessageOpenedApp
}

/// Provider for PushNotificationService
final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  return PushNotificationService(
    NotificationRepository(Supabase.instance.client),
  );
});

class PushNotificationService {
  final NotificationRepository _repository;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Backing field for notification tap callback
  void Function(Map<String, dynamic>)? _onNotificationTap;

  // Buffered initial message (for terminated state tap before callback is set)
  Map<String, dynamic>? _pendingInitialMessage;

  // Setter that flushes pending message when callback is assigned
  set onNotificationTap(void Function(Map<String, dynamic>)? callback) {
    _onNotificationTap = callback;
    if (_pendingInitialMessage != null && callback != null) {
      callback(_pendingInitialMessage!);
      _pendingInitialMessage = null;
    }
  }

  // Callback for silent data refresh
  void Function(Map<String, dynamic> data)? onSilentRefresh;

  /// Guard against duplicate initialization.
  /// Without this, each call to initialize() adds a NEW listener to
  /// onMessage/onMessageOpenedApp, causing duplicate local notifications.
  bool _initialized = false;

  PushNotificationService(this._repository);

  /// Initialize the push notification service
  /// Call this early in app startup (after Firebase.initializeApp)
  Future<void> initialize() async {
    if (_initialized) {
      debugPrint('[PushNotificationService] Already initialized, skipping');
      // Still clear badge on re-entry (e.g. app resume)
      if (!kIsWeb) {
        await clearBadge();
      }
      return;
    }

    // Set background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize local notifications for foreground display (mobile only)
    if (!kIsWeb) {
      await _initializeLocalNotifications();
      // Clear badge when app opens
      await clearBadge();
    }

    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    // Check if app was opened from a notification (terminated state)
    // Buffer the message instead of immediately handling it, since the callback
    // is not yet assigned at this point in the lifecycle
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingInitialMessage = initialMessage.data;
    }

    _initialized = true;
    debugPrint('[PushNotificationService] Initialized');
  }

  static const _badgeChannel = MethodChannel('com.bandroadie/badge');

  /// Clear the app icon badge count
  Future<void> clearBadge() async {
    try {
      if (Platform.isIOS) {
        await _badgeChannel.invokeMethod('clearBadge');
        debugPrint('[PushNotificationService] Badge cleared to 0');
      }
      // Android doesn't have native badge support the same way
    } catch (e) {
      debugPrint('[PushNotificationService] Error clearing badge: $e');
    }
  }

  /// Request notification permission (with soft pre-prompt handled by caller)
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    debugPrint('[PushNotificationService] Permission granted: $granted');
    return granted;
  }

  /// Check if permission has been granted
  Future<bool> hasPermission() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Register device token with Supabase
  Future<void> registerToken() async {
    try {
      // Web requires a VAPID key to obtain an FCM token
      // iOS/Android derive the token from the native config files
      final token = kIsWeb
          ? await _messaging.getToken(
              vapidKey:
                  'BH-GpUNMkRmpMZ1IFpshMbGWnUDt0Gi0_s4M_4o2q6AWbVHFQK8oX3J2c8DEJbTWTvtbqCq8fS-UzHIV1qcg3Ks',
            )
          : await _messaging.getToken();
      if (token == null) {
        debugPrint('[PushNotificationService] No FCM token available');
        return;
      }

      final platform = _getPlatform();
      await _repository.upsertDeviceToken(
        fcmToken: token,
        platform: platform,
        deviceName: _getDeviceName(),
      );

      debugPrint('[PushNotificationService] Token registered for $platform');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        await _repository.upsertDeviceToken(
          fcmToken: newToken,
          platform: platform,
          deviceName: _getDeviceName(),
        );
        debugPrint('[PushNotificationService] Token refreshed');
      });
    } catch (e) {
      debugPrint('[PushNotificationService] Error registering token: $e');
    }
  }

  /// Unregister device token (call on logout)
  Future<void> unregisterToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _repository.removeDeviceToken(token);
        debugPrint('[PushNotificationService] Token unregistered');
      }
    } catch (e) {
      debugPrint('[PushNotificationService] Error unregistering token: $e');
    }
  }

  // --------------------------------------------------------------------------
  // PRIVATE METHODS
  // --------------------------------------------------------------------------

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const macosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && _onNotificationTap != null) {
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            _onNotificationTap!(data);
          } catch (e) {
            // Stale notification with non-JSON payload (pre-upgrade app versions)
            debugPrint('[PushNotificationService] Invalid notification payload: $e');
            return;
          }
        }
      },
    );

    // Create Android notification channel
    const androidChannel = AndroidNotificationChannel(
      'band_roadie_notifications',
      'Band Roadie Notifications',
      description: 'Notifications for gigs, rehearsals, and band updates',
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
      '[PushNotificationService] Foreground message: ${message.messageId}',
    );

    // Check if this is a silent/data-only notification
    if (message.notification == null) {
      // Silent notification - trigger background refresh
      onSilentRefresh?.call(message.data);
      return;
    }

    // Show local notification for foreground (mobile only)
    if (!kIsWeb) {
      _showLocalNotification(message);
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    // JSON-encode the full data map to pass as payload
    final dataJson = jsonEncode(message.data);

    const androidDetails = AndroidNotificationDetails(
      'band_roadie_notifications',
      'Band Roadie Notifications',
      channelDescription:
          'Notifications for gigs, rehearsals, and band updates',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      notificationDetails,
      payload: dataJson,
    );
  }

  void _handleNotificationOpen(RemoteMessage message) {
    debugPrint(
      '[PushNotificationService] Notification opened: ${message.messageId}',
    );

    final data = message.data;
    _onNotificationTap?.call(data);
  }

  String _getPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

  String? _getDeviceName() {
    // Could use device_info_plus for detailed device name
    // For now, return null and let the backend use defaults
    return null;
  }
}
