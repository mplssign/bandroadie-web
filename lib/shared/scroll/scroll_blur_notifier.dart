import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
// SCROLL BLUR NOTIFIER
// Provides a 0..1 value representing how much blur/fade to apply based on
// scroll position. Used by the bottom nav to intensify glass effect as
// content scrolls underneath.
//
// TO ADD SCROLL TRACKING TO A NEW SCREEN:
// 1. Get the notifier: final scrollBlur = ref.read(scrollBlurProvider.notifier);
// 2. Wrap your scroll view with NotificationListener<ScrollNotification>:
//
//    NotificationListener<ScrollNotification>(
//      onNotification: (notification) {
//        if (notification.metrics.axis == Axis.vertical) {
//          scrollBlur.updateFromOffset(notification.metrics.pixels);
//        }
//        return false;
//      },
//      child: YourScrollView(...),
//    )
// ============================================================================

/// Scroll offset threshold for full blur effect (in pixels).
/// Content scrolled this far = blur at 100%.
const double kScrollBlurThreshold = 80.0;

/// A notifier that converts scroll offset to a 0..1 blur intensity value.
class ScrollBlurNotifier extends Notifier<double> {
  @override
  double build() => 0.0;

  /// Update blur value based on scroll offset.
  /// Offset of 0 = blur 0.0, offset >= threshold = blur 1.0.
  void updateFromOffset(double offset) {
    final t = (offset / kScrollBlurThreshold).clamp(0.0, 1.0);
    // Only update if value changed to avoid unnecessary rebuilds
    if ((state - t).abs() > 0.01) {
      state = t;
    }
  }

  /// Reset blur to 0 (e.g., when navigating away or scroll view isn't present).
  void reset() {
    if (state != 0.0) {
      state = 0.0;
    }
  }
}

/// Provider for scroll blur notifier.
/// Access with: ref.watch(scrollBlurProvider) for value
/// Or: ref.read(scrollBlurProvider.notifier) for the notifier
final scrollBlurProvider = NotifierProvider<ScrollBlurNotifier, double>(
  ScrollBlurNotifier.new,
);

/// Helper extension for linear interpolation used by glass effect widgets.
extension ScrollBlurLerp on double {
  /// Linear interpolate between [a] and [b] using this value as t (0..1).
  double lerpTo(double a, double b) => a + (b - a) * clamp(0.0, 1.0);
}
