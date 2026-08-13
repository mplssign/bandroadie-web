import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Button style variants
enum AppButtonVariant {
  /// Filled button with primary color background
  primary,

  /// Elevated button with shadow
  secondary,

  /// Text-only button with no background (maps to Forui .ghost)
  text,

  /// Outlined button with border
  outlined,

  /// Error-colored filled button for dangerous actions
  destructive,
}

/// Wrapper for [FButton] that provides consistent button styling.
///
/// Use this widget instead of [FilledButton], [ElevatedButton], [TextButton],
/// or [OutlinedButton] to ensure consistent button styling across the app
/// using Forui design system.
///
/// **Note:** The `elevation`, `disabledBackgroundColor`, and
/// `disabledForegroundColor` props are not fully supported (use variant styling).
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.fullWidth = false,
    this.backgroundColor,
    this.borderRadius,
    this.elevation,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.padding,
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

  /// Optional custom background color (ignored in Forui preview)
  final Color? backgroundColor;

  /// Optional custom border radius (ignored in Forui preview)
  final BorderRadius? borderRadius;

  /// Optional custom elevation (ignored in Forui preview)
  final double? elevation;

  /// Optional custom disabled background color (ignored in Forui preview)
  final Color? disabledBackgroundColor;

  /// Optional custom disabled foreground color (ignored in Forui preview)
  final Color? disabledForegroundColor;

  /// Optional custom padding (ignored in Forui preview)
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    // Disable button when loading or onPressed is null
    final effectiveOnPress = isLoading ? null : onPressed;

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

    // Map AppButtonVariant to FButtonVariant
    final FButtonVariant foruiVariant;
    switch (variant) {
      case AppButtonVariant.primary:
        foruiVariant = FButtonVariant.primary;
      case AppButtonVariant.secondary:
        foruiVariant = FButtonVariant.secondary;
      case AppButtonVariant.text:
        foruiVariant = FButtonVariant.ghost;
      case AppButtonVariant.outlined:
        foruiVariant = FButtonVariant.outline;
      case AppButtonVariant.destructive:
        foruiVariant = FButtonVariant.destructive;
    }

    // Build StyleDelta if any visual overrides provided
    final styleDelta =
        (backgroundColor != null || borderRadius != null || padding != null)
            ? FButtonStyleDelta.delta(
                decoration: (backgroundColor != null || borderRadius != null)
                    ? FVariantsDelta.delta([
                        FVariantOperation.all(
                          DecorationDelta.boxDelta(
                            color: backgroundColor,
                            borderRadius: borderRadius,
                          ),
                        ),
                      ])
                    : null,
                contentStyle: padding != null
                    ? FButtonContentStyleDelta.delta(
                        padding: EdgeInsetsGeometryDelta.value(padding!),
                      )
                    : null,
              )
            : null;

    // Build the button
    final button = styleDelta != null
        ? FButton(
            onPress: effectiveOnPress,
            variant: foruiVariant,
            style: styleDelta,
            child: content,
          )
        : FButton(
            onPress: effectiveOnPress,
            variant: foruiVariant,
            child: content,
          );

    // Wrap in full-width container if needed
    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }
}
