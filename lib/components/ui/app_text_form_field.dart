import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import 'adaptive_text_selection_toolbar.dart';

/// Wrapper for [FTextFormField] that provides consistent text form field styling.
///
/// Use this widget instead of [TextFormField] to ensure consistent
/// text form field styling across the app using Forui design system.
///
/// **Note:** The `decoration`, `prefixIcon`, and `suffixIcon` props are not
/// fully supported in the current implementation (builder pattern required).
/// The `style` prop is not supported (use Forui theme instead).
class AppTextFormField extends StatelessWidget {
  const AppTextFormField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.style,
    this.onChanged,
    this.enabled = true,
    this.validator,
    this.onSaved,
    this.inputFormatters,
    this.autocorrect = true,
    this.autofillHints,
    this.onSubmitted,
    this.autofocus = false,
    this.contextMenuBuilder,
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

  /// Maximum number of lines (1 for single-line input)
  final int maxLines;

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

  /// Text style override (not supported in Forui preview)
  final TextStyle? style;

  /// Callback when text changes
  final ValueChanged<String>? onChanged;

  /// Whether the field is enabled
  final bool enabled;

  /// Validation function for form field
  final FormFieldValidator<String>? validator;

  /// Callback when form is saved
  final FormFieldSetter<String>? onSaved;

  /// Optional input formatters (not supported in Forui preview)
  final List<TextInputFormatter>? inputFormatters;

  /// Whether to enable autocorrect
  final bool autocorrect;

  /// Optional autofill hints (not supported in Forui preview)
  final Iterable<String>? autofillHints;

  /// Callback when user submits (not supported in Forui preview)
  final ValueChanged<String>? onSubmitted;

  /// Whether to autofocus (not supported in Forui preview)
  final bool autofocus;

  /// Builder for the text selection context menu.
  final EditableTextContextMenuBuilder? contextMenuBuilder;

  @override
  Widget build(BuildContext context) {
    final isMultiline = maxLines > 1;
    final effectiveTextInputAction = textInputAction ??
        (isMultiline ? TextInputAction.newline : TextInputAction.next);

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

    return FTextFormField(
      control: control,
      focusNode: focusNode,
      label: labelText != null ? Text(labelText!) : null,
      hint: hintText,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autocorrect: autocorrect,
      validator: validator,
      onSaved: onSaved,
      textCapitalization: textCapitalization,
      textInputAction: effectiveTextInputAction,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      onSubmit: onSubmitted ??
          (effectiveTextInputAction == TextInputAction.next
              ? (_) => FocusScope.of(context).nextFocus()
              : null),
      autofocus: autofocus,
      contextMenuBuilder:
          contextMenuBuilder ?? buildLocalizedAdaptiveTextSelectionToolbar,
      prefixBuilder:
          prefixIcon != null ? (context, style, variants) => prefixIcon! : null,
      suffixBuilder:
          suffixIcon != null ? (context, style, variants) => suffixIcon! : null,
    );
  }
}
