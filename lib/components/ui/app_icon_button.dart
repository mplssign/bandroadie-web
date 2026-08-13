import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for [FButton.icon] that provides consistent icon button styling.
///
/// Use this widget instead of [IconButton] to ensure consistent
/// icon button styling across the app using Forui design system.
///
/// **Note for preview cycle:** The `color` and `size` props are currently
/// ignored (no style override applied). Icon buttons use theme default styling.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.size,
  });

  /// Icon to display
  final IconData icon;

  /// Callback when button is pressed (null disables button)
  final VoidCallback? onPressed;

  /// Optional icon color override (ignored in Forui preview)
  final Color? color;

  /// Optional icon size override (ignored in Forui preview)
  final double? size;

  @override
  Widget build(BuildContext context) {
    return FButton.icon(
      onPress: onPressed,
      child: Icon(icon),
    );
  }
}
