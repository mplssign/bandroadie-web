import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Wrapper for [FCard] that provides consistent card styling.
///
/// Use this widget instead of [Card] to ensure consistent
/// card styling across the app using Forui design system.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.height,
    this.borderRadius,
    this.border,
    this.boxShadow,
  });

  /// Card content
  final Widget child;

  /// Optional tap callback
  final VoidCallback? onTap;

  /// Optional padding override (ignored in Forui preview)
  final EdgeInsets? padding;

  /// Optional fixed height (e.g., 121 for song cards)
  final double? height;

  /// Optional border radius override (e.g., BorderRadius.circular(8))
  final BorderRadius? borderRadius;

  /// Optional border (e.g., Border.all(color: AppColors.primary, width: 1.5))
  final BoxBorder? border;

  /// Optional box shadow (e.g., [BoxShadow(color: ..., blurRadius: 24)])
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    // Read Forui's theme border color
    final themeBorderColor = context.theme.colors.border;

    // Default to Forui's theme border for consistent contrast across all cards
    // (translucent white in dark mode, opaque gray in light mode). Call sites
    // can override with explicit border: param for brand accents (e.g. rose).
    final effectiveBorder =
        border ?? Border.all(color: themeBorderColor, width: 1);

    // Build StyleDelta with border (always present), plus optional padding and borderRadius
    final styleDelta = FCardStyleDelta.delta(
      padding: padding != null ? EdgeInsetsGeometryDelta.value(padding!) : null,
      decoration: DecorationDelta.boxDelta(
        borderRadius: borderRadius,
        border: effectiveBorder,
        boxShadow: boxShadow,
      ),
    );

    final card = FCard(
      style: styleDelta,
      child: child,
    );

    // Wrap in SizedBox if height provided
    final cardWithHeight =
        height != null ? SizedBox(height: height, child: card) : card;

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: cardWithHeight);
    }

    return cardWithHeight;
  }
}
