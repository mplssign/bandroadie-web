import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wrapper for [TextField] that respects app theme configuration.
///
/// Use this widget instead of [TextField] to ensure consistent
/// text field styling across the app. Delegates all props directly
/// to [TextField] while respecting theme's inputDecorationTheme.
///
/// When [decoration] is provided, it is used directly and overrides
/// [hintText], [labelText], [prefixIcon], and [suffixIcon].
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
    this.maxLines = 1,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.style,
    this.onChanged,
    this.enabled = true,
    this.inputFormatters,
    this.autocorrect = true,
    this.autofillHints,
    this.onSubmitted,
    this.autofocus = false,
  });

  /// Optional text editing controller
  final TextEditingController? controller;

  /// Optional focus node for managing focus
  final FocusNode? focusNode;

  /// Full input decoration. When provided, overrides [hintText], [labelText],
  /// [prefixIcon], and [suffixIcon].
  final InputDecoration? decoration;

  /// Optional hint text displayed when field is empty.
  /// Ignored if [decoration] is provided.
  final String? hintText;

  /// Optional label text displayed above field.
  /// Ignored if [decoration] is provided.
  final String? labelText;

  /// Optional prefix icon.
  /// Ignored if [decoration] is provided.
  final IconData? prefixIcon;

  /// Optional suffix widget (e.g., clear button, visibility toggle).
  /// Ignored if [decoration] is provided.
  final Widget? suffixIcon;

  /// Whether to obscure text (for passwords)
  final bool obscureText;

  /// Maximum number of lines (1 for single-line input)
  final int maxLines;

  /// Keyboard type for mobile platforms
  final TextInputType? keyboardType;

  /// Text capitalization behavior
  final TextCapitalization textCapitalization;

  /// Keyboard action button (e.g., next, done)
  final TextInputAction? textInputAction;

  /// Text style override
  final TextStyle? style;

  /// Callback when text changes
  final ValueChanged<String>? onChanged;

  /// Whether the field is enabled
  final bool enabled;

  /// Optional input formatters for restricting/formatting input
  final List<TextInputFormatter>? inputFormatters;

  /// Whether to enable autocorrect (defaults to true)
  final bool autocorrect;

  /// Optional autofill hints for password managers and form autofill
  final Iterable<String>? autofillHints;

  /// Callback when user submits the field (e.g., presses Enter)
  final ValueChanged<String>? onSubmitted;

  /// Whether to autofocus this field when widget is built (defaults to false)
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: decoration ??
          InputDecoration(
            hintText: hintText,
            labelText: labelText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: suffixIcon,
          ),
      obscureText: obscureText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      style: style,
      onChanged: onChanged,
      enabled: enabled,
      inputFormatters: inputFormatters,
      autocorrect: autocorrect,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
    );
  }
}
