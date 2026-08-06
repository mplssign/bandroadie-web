import 'package:flutter/material.dart';

/// Wrapper for [DropdownButton] that respects app theme configuration.
///
/// Use this widget instead of [DropdownButton] to ensure consistent
/// dropdown styling across the app. Delegates all props directly
/// to [DropdownButton] while respecting theme's dropdownMenuTheme.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  /// Currently selected value
  final T? value;

  /// List of dropdown menu items
  final List<DropdownMenuItem<T>> items;

  /// Callback when selection changes (null disables dropdown)
  final ValueChanged<T?>? onChanged;

  /// Optional hint widget displayed when no value is selected
  final Widget? hint;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      hint: hint,
    );
  }
}
