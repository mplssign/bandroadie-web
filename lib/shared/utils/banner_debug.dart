// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Debug utilities for testing the native app banner on different platforms.
///
/// Usage in Chrome DevTools Console:
/// 1. Check user agent: console.log(navigator.userAgent)
/// 2. Check display mode: console.log(matchMedia('(display-mode: standalone)').matches)
/// 3. Check localStorage: console.log(localStorage.getItem('hideAppBanner'))
class BannerDebugInfo {
  static Map<String, dynamic> get info {
    if (!kIsWeb) {
      return {
        'platform': 'non-web',
        'error': 'This debug info only works on web',
      };
    }

    final userAgent = html.window.navigator.userAgent;
    final isStandalone = html.window
        .matchMedia('(display-mode: standalone)')
        .matches;
    final dismissed = html.window.localStorage['hideAppBanner'];
    final dismissedAt = html.window.localStorage['bannerDismissedAt'];

    final isIOS = userAgent.contains('iPhone') || userAgent.contains('iPad');
    final isAndroid = userAgent.contains('Android');
    final isMacOS = userAgent.contains('Macintosh');
    final isWindows = userAgent.contains('Windows');

    return {
      'userAgent': userAgent,
      'detectedPlatforms': {
        'iOS': isIOS,
        'Android': isAndroid,
        'macOS': isMacOS,
        'Windows': isWindows,
      },
      'isStandalone': isStandalone,
      'isMobileWeb': !isStandalone && (isIOS || isAndroid),
      'dismissal': {
        'dismissed': dismissed == 'true',
        'dismissedAt': dismissedAt,
      },
      'shouldShowBanner':
          !isStandalone && (isIOS || isAndroid) && dismissed != 'true',
    };
  }

  /// Print debug info to console
  static void printDebugInfo() {
    if (!kIsWeb) {
      debugPrint('Banner debug info only available on web');
      return;
    }

    debugPrint('=== Native App Banner Debug Info ===');
    final data = info;
    data.forEach((key, value) {
      debugPrint('$key: $value');
    });
    debugPrint('====================================');
  }

  /// Reset banner dismissal for testing
  static void resetDismissal() {
    if (!kIsWeb) return;
    html.window.localStorage.remove('hideAppBanner');
    html.window.localStorage.remove('bannerDismissedAt');
    debugPrint('✅ Banner dismissal reset. Reload page to see banner.');
  }

  /// Force dismiss banner (for testing)
  static void forceDismiss() {
    if (!kIsWeb) return;
    html.window.localStorage['hideAppBanner'] = 'true';
    html.window.localStorage['bannerDismissedAt'] = DateTime.now()
        .toIso8601String();
    debugPrint('✅ Banner dismissed. Call resetDismissal() to undo.');
  }
}
