import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for [FCard] that provides consistent card styling.
///
/// Use this widget instead of [Card] to ensure consistent
/// card styling across the app using Forui design system.
///
/// **Note for preview cycle:** The `padding` prop is currently ignored
/// (no style override applied). Card uses theme default padding.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding});

  /// Card content
  final Widget child;

  /// Optional tap callback
  final VoidCallback? onTap;

  /// Optional padding override (ignored in Forui preview)
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final card = FCard(child: child);

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }

    return card;
  }
}
