import 'package:flutter/material.dart';

/// Wrapper for [TextField] that respects app theme configuration.
///
/// Use this widget instead of [TextField] to ensure consistent
/// text field styling across the app. Delegates all props directly
/// to [TextField] while respecting theme's inputDecorationTheme.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.enabled = true,
  });

  /// Optional text editing controller
  final TextEditingController? controller;

  /// Optional hint text displayed when field is empty
  final String? hintText;

  /// Optional label text displayed above field
  final String? labelText;

  /// Optional prefix icon
  final IconData? prefixIcon;

  /// Optional suffix widget (e.g., clear button, visibility toggle)
  final Widget? suffixIcon;

  /// Whether to obscure text (for passwords)
  final bool obscureText;

  /// Maximum number of lines (1 for single-line input)
  final int maxLines;

  /// Keyboard type for mobile platforms
  final TextInputType? keyboardType;

  /// Callback when text changes
  final ValueChanged<String>? onChanged;

  /// Whether the field is enabled
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        suffixIcon: suffixIcon,
      ),
      obscureText: obscureText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      enabled: enabled,
    );
  }
}
