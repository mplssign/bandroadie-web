import 'package:flutter/material.dart';

/// Wrapper for [Card] that respects app theme configuration.
///
/// Use this widget instead of [Card] to ensure consistent
/// card styling across the app. Delegates to [Card] while
/// respecting theme's cardTheme. Optionally wraps in [InkWell]
/// for tap interactions.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding});

  /// Card content
  final Widget child;

  /// Optional tap callback (adds InkWell ripple effect)
  final VoidCallback? onTap;

  /// Optional padding override
  /// If null, uses default spacing
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    if (onTap != null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      );
    }

    return Card(child: content);
  }
}
