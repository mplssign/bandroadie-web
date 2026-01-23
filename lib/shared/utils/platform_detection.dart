// Platform detection utilities for Flutter Web
// Uses conditional imports to safely include dart:html only on web
import 'platform_detection_stub.dart'
    if (dart.library.html) 'platform_detection_web.dart';

/// Check if running on iOS Safari (web)
bool get isIOS => isIOSImpl();

/// Check if running on Android Chrome (web)
bool get isAndroid => isAndroidImpl();

/// Check if running as PWA/standalone mode
bool get isStandalone => isStandaloneImpl();

/// Check if running on mobile web (iOS or Android browser, not standalone)
bool get isMobileWeb => isMobileWebImpl();
