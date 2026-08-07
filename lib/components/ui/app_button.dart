import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';

/// Button style variants
enum AppButtonVariant {
  /// Filled button with primary color background (FilledButton)
  primary,

  /// Elevated button with shadow (ElevatedButton)
  secondary,

  /// Text-only button with no background (TextButton)
  text,

  /// Outlined button with border (OutlinedButton)
  outlined,

  /// Error-colored filled button for dangerous actions (FilledButton with error background)
  destructive,
}

/// Wrapper for Material button widgets that respects app theme configuration.
///
/// Use this widget instead of [FilledButton], [ElevatedButton], [TextButton],
/// or [OutlinedButton] to ensure consistent button styling across the app.
/// Delegates to the appropriate Material button based on [variant] while
/// respecting theme configuration.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.fullWidth = false,
  });

  /// Button label text
  final String label;

  /// Callback when button is pressed (null disables button)
  final VoidCallback? onPressed;

  /// Optional leading icon
  final IconData? icon;

  /// Button style variant
  final AppButtonVariant variant;

  /// Shows loading spinner instead of content when true
  final bool isLoading;

  /// If true, button expands to fill available width
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    // Disable button when loading or onPressed is null
    final effectiveOnPressed = isLoading ? null : onPressed;

    // Build button content
    final content = isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Text(label),
                ],
              )
            : Text(label);

    // Build the button based on variant
    Widget button;
    switch (variant) {
      case AppButtonVariant.primary:
        button = FilledButton(onPressed: effectiveOnPressed, child: content);
      case AppButtonVariant.secondary:
        button = ElevatedButton(onPressed: effectiveOnPressed, child: content);
      case AppButtonVariant.text:
        button = TextButton(onPressed: effectiveOnPressed, child: content);
      case AppButtonVariant.outlined:
        button = OutlinedButton(onPressed: effectiveOnPressed, child: content);
      case AppButtonVariant.destructive:
        button = FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: content,
        );
    }

    // Wrap in full-width container if needed
    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }
}
