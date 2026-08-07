import 'package:flutter/material.dart';

/// Wrapper for [Checkbox] that respects app theme configuration.
///
/// Use this widget instead of [Checkbox] to ensure consistent
/// checkbox styling across the app. Delegates all props directly
/// to [Checkbox] while respecting theme's checkboxTheme unless
/// explicitly overridden.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  /// Current checkbox state (true/false/null for indeterminate)
  final bool? value;

  /// Callback when checkbox state changes (null disables checkbox)
  final ValueChanged<bool?>? onChanged;

  /// Optional active color override
  /// If null, uses theme's checkboxTheme.fillColor
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: value,
      onChanged: onChanged,
      activeColor: activeColor,
      tristate: true, // Allow indeterminate state (null value)
    );
  }
}
