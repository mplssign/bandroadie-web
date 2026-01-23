// localStorage utilities for Flutter Web
// Uses conditional imports to safely include dart:html only on web
import 'web_storage_stub.dart' if (dart.library.html) 'web_storage_web.dart';

/// Check if the app banner has been dismissed
bool get dismissedAppBanner => getDismissedAppBannerImpl();

/// Mark the app banner as dismissed
void dismissAppBanner() => dismissAppBannerImpl();

/// Clear the dismissal (for testing or if you want to re-show after X days)
void clearAppBannerDismissal() => clearAppBannerDismissalImpl();

/// Get when the banner was dismissed (null if never dismissed)
DateTime? getBannerDismissedAt() => getBannerDismissedAtImpl();
