import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for [FSwitch] that provides consistent switch styling.
///
/// Use this widget instead of [Switch] to ensure consistent
/// switch styling across the app using Forui design system.
///
/// **Note for preview cycle:** The `activeColor`, `activeTrackColor`, and
/// `useAdaptiveSwitch` props are currently ignored (no style override applied).
/// Switch uses theme default styling.
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

  /// Optional active thumb color override (ignored in Forui preview)
  final Color? activeColor;

  /// Optional active track color override (ignored in Forui preview)
  final Color? activeTrackColor;

  /// Whether to use adaptive switch (ignored in Forui preview)
  final bool useAdaptiveSwitch;

  @override
  Widget build(BuildContext context) {
    return FSwitch(
      value: value,
      onChange: onChanged,
      enabled: onChanged != null,
    );
  }
}
