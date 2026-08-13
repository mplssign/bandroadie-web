import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for [FSelect] that provides consistent dropdown styling.
///
/// Use this widget instead of [DropdownButton] to ensure consistent
/// dropdown styling across the app using Forui design system.
///
/// **Note for preview cycle:** This wrapper has zero call sites in the current
/// codebase. Implementation is provided for future-proofing but will not be
/// visible in Tony's preview. The `hint` prop is not supported in Forui preview.
/// The format function uses toString() on the value, which may not be ideal for
/// all use cases.
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

  /// Optional hint widget (not supported in Forui preview)
  final Widget? hint;

  @override
  Widget build(BuildContext context) {
    // Convert DropdownMenuItem items to FSelect children
    final children = items.map((item) {
      return FSelectItem.item(
        title: item.child,
        value: item.value as T,
      );
    }).toList();

    return FSelect<T>.rich(
      format: (value) => value.toString(),
      children: children,
    );
  }
}
