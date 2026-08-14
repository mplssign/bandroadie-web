import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for `FSelect` that provides consistent dropdown styling.
///
/// Use this widget instead of `DropdownButton` to ensure consistent
/// dropdown styling across the app using Forui design system.
///
/// Supports both flat dropdowns (via `items`) and grouped dropdowns with
/// section headers (via `children`). Exactly one of `items` or `children`
/// must be provided.
///
/// For Form integration, use `validator`, `onSaved`, and `autovalidateMode`
/// parameters. `FSelect` natively implements `FormField` via `FFormFieldProperties<T>`.
///
/// **Hint limitation:** The `hint` prop is accepted for backward compatibility
/// but not rendered in Forui. Use an explicit null-value `DropdownMenuItem` as
/// the first item instead.
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    super.key,
    required this.value,
    this.items,
    this.children,
    required this.onChanged,
    this.hint,
    this.format,
    this.labelBuilder,
    this.enabled = true,
    this.validator,
    this.onSaved,
    this.autovalidateMode,
  }) : assert(
          (items != null && children == null) ||
              (items == null && children != null),
          'AppDropdown: Must provide exactly one of items or children, not both.',
        );

  /// Currently selected value
  final T? value;

  /// List of dropdown menu items (for flat dropdowns).
  /// Mutually exclusive with [children].
  final List<DropdownMenuItem<T>>? items;

  /// List of grouped/sectioned items (for grouped dropdowns with headers).
  /// Use [FSelectSection] to create groups. Mutually exclusive with [items].
  final List<FSelectItemMixin>? children;

  /// Callback when selection changes
  final ValueChanged<T?> onChanged;

  /// Optional hint widget (accepted for backward compatibility but not rendered).
  /// Use an explicit null-value DropdownMenuItem as first item instead.
  final Widget? hint;

  /// Optional custom format function for displaying selected value.
  /// Defaults to [toString()] if both [format] and [labelBuilder] are null.
  final String Function(T value)? format;

  /// Alias for [format] (semantic clarity for custom label rendering).
  final String Function(T value)? labelBuilder;

  /// Whether the dropdown is enabled. Defaults to true.
  final bool enabled;

  /// Form validator function (for Form integration).
  final FormFieldValidator<T>? validator;

  /// Form save callback (for Form integration).
  final FormFieldSetter<T>? onSaved;

  /// Form autovalidation mode (for Form integration).
  final AutovalidateMode? autovalidateMode;

  @override
  Widget build(BuildContext context) {
    // Convert items to FSelectItem list if provided, otherwise use children
    final selectChildren = children ??
        items!.map((item) {
          return FSelectItem<T>.item(
            title: item.child,
            value: item.value as T,
          );
        }).toList();

    final formatFunction =
        format ?? labelBuilder ?? (value) => value.toString();

    // FSelect.rich already draws its own field chrome (border, background, rounded corners)
    // via FTextField.defaultBuilder, so no Container wrapper is needed.
    return validator != null
        ? FSelect<T>.rich(
            control: FSelectControl<T>.lifted(
              value: value,
              onChange: onChanged,
            ),
            format: formatFunction,
            enabled: enabled,
            validator: validator!,
            onSaved: onSaved,
            autovalidateMode: autovalidateMode ?? AutovalidateMode.disabled,
            children: selectChildren,
          )
        : FSelect<T>.rich(
            control: FSelectControl<T>.lifted(
              value: value,
              onChange: onChanged,
            ),
            format: formatFunction,
            enabled: enabled,
            onSaved: onSaved,
            autovalidateMode: autovalidateMode ?? AutovalidateMode.disabled,
            children: selectChildren,
          );
  }
}
