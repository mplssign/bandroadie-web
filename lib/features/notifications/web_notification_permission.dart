// ============================================================================
// WEB NOTIFICATION PERMISSION (CONDITIONAL IMPORT)
// Platform-specific implementation dispatcher
// ============================================================================

// Conditional imports based on platform
export 'web_notification_permission_stub.dart'
    if (dart.library.html) 'web_notification_permission_web.dart';
