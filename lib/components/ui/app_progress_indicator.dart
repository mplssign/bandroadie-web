import 'package:flutter/material.dart';

/// Progress indicator type
enum ProgressIndicatorType {
  /// Circular progress indicator
  circular,

  /// Linear progress indicator
  linear,
}

/// Wrapper for Material progress indicators that respects app theme configuration.
///
/// Use this widget instead of [CircularProgressIndicator] or [LinearProgressIndicator]
/// to ensure consistent progress indicator styling across the app. Delegates to
/// the appropriate Material widget based on [type] while respecting theme configuration.
class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator({
    super.key,
    this.type = ProgressIndicatorType.circular,
    this.value,
    this.color,
    this.strokeWidth,
  });

  /// Progress indicator type (circular or linear)
  final ProgressIndicatorType type;

  /// Optional progress value (0.0 to 1.0) for determinate progress
  /// If null, shows indeterminate progress
  final double? value;

  /// Optional color override
  /// If null, uses theme's progressIndicatorTheme.color
  final Color? color;

  /// Optional stroke width for circular progress indicator
  /// If null, uses Material default (4.0)
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case ProgressIndicatorType.circular:
        return CircularProgressIndicator(
          value: value,
          color: color,
          strokeWidth: strokeWidth ?? 4.0,
        );

      case ProgressIndicatorType.linear:
        return LinearProgressIndicator(value: value, color: color);
    }
  }
}
