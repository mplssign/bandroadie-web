import 'package:flutter/material.dart';

/// Wrapper for [IconButton] that respects app theme configuration.
///
/// Use this widget instead of [IconButton] to ensure consistent
/// icon button styling across the app. Delegates all props directly
/// to [IconButton] while respecting theme's iconTheme unless
/// explicitly overridden.
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

  /// Optional icon color override
  /// If null, uses theme's iconTheme.color
  final Color? color;

  /// Optional icon size override
  /// If null, uses theme's iconTheme.size
  final double? size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      color: color,
      iconSize: size,
    );
  }
}
