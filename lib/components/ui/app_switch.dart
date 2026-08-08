import 'package:flutter/material.dart';

/// Wrapper for [Switch] that respects app theme configuration.
///
/// Use this widget instead of [Switch] to ensure consistent
/// switch styling across the app. Delegates all props directly
/// to [Switch] while respecting theme's switchTheme unless
/// explicitly overridden.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeTrackColor,
    this.useAdaptiveSwitch = false,
  });

  /// Current switch state
  final bool value;

  /// Callback when switch state changes (null disables switch)
  final ValueChanged<bool>? onChanged;

  /// Optional active thumb color override
  /// If null, uses theme's switchTheme.thumbColor
  final Color? activeColor;

  /// Optional active track color override
  /// If null, uses theme's switchTheme.trackColor
  final Color? activeTrackColor;

  /// Whether to use Switch.adaptive (Cupertino on iOS/macOS, Material on Android/Web)
  /// Defaults to false (always use Material Switch)
  final bool useAdaptiveSwitch;

  @override
  Widget build(BuildContext context) {
    if (useAdaptiveSwitch) {
      return Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: activeColor,
        activeTrackColor: activeTrackColor,
      );
    }

    return Switch(
      value: value,
      onChanged: onChanged,
      thumbColor:
          activeColor != null ? WidgetStateProperty.all(activeColor) : null,
      trackColor: activeTrackColor != null
          ? WidgetStateProperty.all(activeTrackColor)
          : null,
    );
  }
}
