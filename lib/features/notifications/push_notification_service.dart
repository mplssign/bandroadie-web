import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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

  // Callback for handling notification taps
  void Function(String? deepLink)? onNotificationTap;

  // Callback for silent data refresh
  void Function(Map<String, dynamic> data)? onSilentRefresh;

  PushNotificationService(this._repository);

  /// Initialize the push notification service
  /// Call this early in app startup (after Firebase.initializeApp)
  Future<void> initialize() async {
    // Set background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize local notifications for foreground display (mobile only)
    if (!kIsWeb) {
      await _initializeLocalNotifications();
    }

    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    // Check if app was opened from a notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationOpen(initialMessage);
    }

    debugPrint('[PushNotificationService] Initialized');
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
      final token = await _messaging.getToken();
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
        if (payload != null && onNotificationTap != null) {
          onNotificationTap!(payload);
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
          AndroidFlutterLocalNotificationsPlugin
        >()
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

    // Extract deep link from data
    final deepLink = message.data['deep_link'] as String?;

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
      payload: deepLink,
    );
  }

  void _handleNotificationOpen(RemoteMessage message) {
    debugPrint(
      '[PushNotificationService] Notification opened: ${message.messageId}',
    );

    final deepLink = message.data['deep_link'] as String?;
    onNotificationTap?.call(deepLink);
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
