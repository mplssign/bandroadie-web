import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Progress indicator type
enum ProgressIndicatorType {
  /// Circular progress indicator
  circular,

  /// Linear progress indicator
  linear,
}

/// Wrapper for Forui progress indicators that provides consistent styling.
///
/// Use this widget instead of [CircularProgressIndicator] or [LinearProgressIndicator]
/// to ensure consistent progress indicator styling across the app using Forui design system.
///
/// **Note for preview cycle:** The `color` and `strokeWidth` props are currently
/// ignored (no style override applied). Progress indicators use theme default styling.
/// Circular progress does not support determinate mode in Forui preview.
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

  /// Optional color override (ignored in Forui preview)
  final Color? color;

  /// Optional stroke width (ignored in Forui preview)
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case ProgressIndicatorType.circular:
        // Forui circular progress (indeterminate only)
        return const FCircularProgress();

      case ProgressIndicatorType.linear:
        // Use determinate if value provided, otherwise indeterminate
        if (value != null) {
          return FDeterminateProgress(value: value!);
        } else {
          return const FProgress();
        }
    }
  }
}
