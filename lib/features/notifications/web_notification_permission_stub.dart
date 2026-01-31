// ============================================================================
// WEB NOTIFICATION PERMISSION (STUB)
// Stub implementation for non-web platforms
// ============================================================================

/// Check web notification permission status
/// Returns 'default', 'granted', or 'denied'
Future<String> checkWebNotificationPermission() async {
  return 'default'; // Not applicable on non-web platforms
}

/// Request web notification permission
/// Returns true if granted
Future<bool> requestWebNotificationPermission() async {
  return false; // Not applicable on non-web platforms
}
