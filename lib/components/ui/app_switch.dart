import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for [FSwitch] that provides consistent switch styling.
///
/// Use this widget instead of [Switch] to ensure consistent
/// switch styling across the app using Forui design system.
///
/// **Note:** The `useAdaptiveSwitch` prop is not supported (Forui handles
/// platform adaptation automatically).
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
    // Build StyleDelta if any color overrides provided
    final styleDelta = (activeColor != null || activeTrackColor != null)
        ? FSwitchStyleDelta.delta(
            thumbColor: activeColor != null
                ? FVariantsValueDelta.delta([
                    FVariantValueDeltaOperation.all(activeColor!),
                  ])
                : null,
            trackColor: activeTrackColor != null
                ? FVariantsValueDelta.delta([
                    FVariantValueDeltaOperation.all(activeTrackColor!),
                  ])
                : null,
          )
        : null;

    return styleDelta != null
        ? FSwitch(
            value: value,
            onChange: onChanged,
            enabled: onChanged != null,
            style: styleDelta,
          )
        : FSwitch(
            value: value,
            onChange: onChanged,
            enabled: onChanged != null,
          );
  }
}
