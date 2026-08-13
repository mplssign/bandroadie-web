import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for [FCheckbox] that provides consistent checkbox styling.
///
/// Use this widget instead of [Checkbox] to ensure consistent
/// checkbox styling across the app using Forui design system.
///
/// **Note for preview cycle:** The `activeColor` prop is currently ignored
/// (no style override applied). Checkbox uses theme default styling.
/// Tristate (indeterminate) is not supported - null values are treated as false.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  /// Current checkbox state (true/false/null for indeterminate)
  /// Note: null treated as false in Forui preview
  final bool? value;

  /// Callback when checkbox state changes (null disables checkbox)
  final ValueChanged<bool?>? onChanged;

  /// Optional active color override (ignored in Forui preview)
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return FCheckbox(
      value: value ?? false,
      onChange: onChanged != null ? (newValue) => onChanged!(newValue) : null,
      enabled: onChanged != null,
    );
  }
}
