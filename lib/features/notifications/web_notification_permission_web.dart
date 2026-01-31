// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

// ============================================================================
// WEB NOTIFICATION PERMISSION (WEB IMPLEMENTATION)
// Uses browser's Notification API
// ============================================================================

/// Check web notification permission status
/// Returns 'default', 'granted', or 'denied'
Future<String> checkWebNotificationPermission() async {
  if (html.Notification.supported) {
    return html.Notification.permission ?? 'default';
  }
  return 'denied'; // Notifications not supported in this browser
}

/// Request web notification permission
/// Returns true if granted
Future<bool> requestWebNotificationPermission() async {
  if (!html.Notification.supported) {
    return false; // Notifications not supported
  }

  try {
    final permission = await html.Notification.requestPermission();
    return permission == 'granted';
  } catch (e) {
    print('[WebNotifications] Error requesting permission: $e');
    return false;
  }
}
