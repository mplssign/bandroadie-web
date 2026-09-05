import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'adaptive_text_selection_toolbar.dart';

/// Wrapper for [FTextField] that provides consistent text field styling.
///
/// Use this widget instead of [TextField] to ensure consistent
/// text field styling across the app using Forui design system.
///
/// **Note:** The `decoration`, `prefixIcon`, and `suffixIcon` props are not
/// fully supported in the current implementation (builder pattern required).
/// The `style` prop is not supported (use Forui theme instead).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.maxLines,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.textAlign = TextAlign.start,
    this.style,
    this.onChanged,
    this.enabled = true,
    this.inputFormatters,
    this.autocorrect = true,
    this.autofillHints,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTap,
    this.autofocus = false,
    this.readOnly = false,
  });

  /// Optional text editing controller
  final TextEditingController? controller;

  /// Optional focus node for managing focus
  final FocusNode? focusNode;

  /// Full input decoration (not supported in Forui preview)
  final InputDecoration? decoration;

  /// Optional hint text displayed when field is empty
  final String? hintText;

  /// Optional label text displayed above field
  final String? labelText;

  /// Optional prefix icon
  final Widget? prefixIcon;

  /// Optional suffix widget
  final Widget? suffixIcon;

  /// Whether to obscure text (for passwords)
  final bool obscureText;

  /// Maximum number of lines (null for unlimited, 1 for single-line input)
  final int? maxLines;

  /// Minimum number of lines (not supported in Forui preview)
  final int? minLines;

  /// Maximum number of characters allowed (not supported in Forui preview)
  final int? maxLength;

  /// Keyboard type for mobile platforms
  final TextInputType? keyboardType;

  /// Text capitalization behavior (not supported in Forui preview)
  final TextCapitalization textCapitalization;

  /// Keyboard action button (not supported in Forui preview)
  final TextInputAction? textInputAction;

  /// Text alignment (not supported in Forui preview)
  final TextAlign textAlign;

  /// Text style override (not supported in Forui preview)
  final TextStyle? style;

  /// Callback when text changes
  final ValueChanged<String>? onChanged;

  /// Whether the field is enabled
  final bool enabled;

  /// Optional input formatters (not supported in Forui preview)
  final List<TextInputFormatter>? inputFormatters;

  /// Whether to enable autocorrect
  final bool autocorrect;

  /// Optional autofill hints (not supported in Forui preview)
  final Iterable<String>? autofillHints;

  /// Callback when user submits (not supported in Forui preview)
  final ValueChanged<String>? onSubmitted;

  /// Callback when editing is complete (not supported in Forui preview)
  final VoidCallback? onEditingComplete;

  /// Callback when the field is tapped (not supported in Forui preview)
  final VoidCallback? onTap;

  /// Whether to autofocus (not supported in Forui preview)
  final bool autofocus;

  /// Whether the field is read-only (not supported in Forui preview)
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    // Wrap controller in FTextFieldManagedControl if provided
    final control = controller != null
        ? FTextFieldManagedControl(
            controller: controller,
            onChange:
                onChanged != null ? (value) => onChanged!(value.text) : null,
          )
        : FTextFieldManagedControl(
            onChange:
                onChanged != null ? (value) => onChanged!(value.text) : null,
          );

    return FTextField(
      control: control,
      focusNode: focusNode,
      label: labelText != null ? Text(labelText!) : null,
      hint: hintText,
      enabled: enabled,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autocorrect: autocorrect,
      textAlign: textAlign,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      onSubmit: onSubmitted,
      onEditingComplete: onEditingComplete,
      onTap: onTap,
      autofocus: autofocus,
      readOnly: readOnly,
      contextMenuBuilder: buildLocalizedAdaptiveTextSelectionToolbar,
      prefixBuilder:
          prefixIcon != null ? (context, style, variants) => prefixIcon! : null,
      suffixBuilder:
          suffixIcon != null ? (context, style, variants) => suffixIcon! : null,
    );
  }
}
