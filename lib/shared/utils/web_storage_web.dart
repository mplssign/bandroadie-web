// Web implementation using dart:html localStorage
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

const String _kHideAppBannerKey = 'hideAppBanner';
const String _kBannerDismissedAtKey = 'bannerDismissedAt';

bool getDismissedAppBannerImpl() {
  try {
    final value = html.window.localStorage[_kHideAppBannerKey];
    debugPrint('getDismissedAppBannerImpl: value=$value');

    // Check if dismissed
    if (value != 'true') return false;

    // Optional: Check if 30 days have passed since dismissal
    final dismissedAt = getBannerDismissedAtImpl();
    if (dismissedAt != null) {
      final daysSinceDismissal = DateTime.now().difference(dismissedAt).inDays;
      debugPrint(
        'getDismissedAppBannerImpl: daysSinceDismissal=$daysSinceDismissal',
      );
      if (daysSinceDismissal >= 30) {
        // Clear dismissal after 30 days
        debugPrint('getDismissedAppBannerImpl: Clearing after 30 days');
        clearAppBannerDismissalImpl();
        return false;
      }
    }

    return true;
  } catch (e) {
    debugPrint('getDismissedAppBannerImpl: Error accessing localStorage: $e');
    return false;
  }
}

void dismissAppBannerImpl() {
  html.window.localStorage[_kHideAppBannerKey] = 'true';
  html.window.localStorage[_kBannerDismissedAtKey] = DateTime.now()
      .toIso8601String();
}

void clearAppBannerDismissalImpl() {
  html.window.localStorage.remove(_kHideAppBannerKey);
  html.window.localStorage.remove(_kBannerDismissedAtKey);
}

DateTime? getBannerDismissedAtImpl() {
  final value = html.window.localStorage[_kBannerDismissedAtKey];
  if (value == null) return null;
  try {
    return DateTime.parse(value);
  } catch (e) {
    return null;
  }
}
