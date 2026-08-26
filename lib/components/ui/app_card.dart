import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';

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
    this.color,
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

  /// Optional background color (e.g., Color(0x140EA5E9) for subtle tint)
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Default to a stronger brand border so card outlines are easier to see.
    // Call sites can still override via explicit border: for special cases.
    final effectiveBorder =
        border ?? Border.all(color: context.colors.borderStrong, width: 1);

    // Keep cards opaque by default so overlapping drag states do not show
    // content through neighboring cards.
    final effectiveColor = color ?? context.colors.background;

    // Build StyleDelta with border (always present), plus optional padding and borderRadius
    final styleDelta = FCardStyleDelta.delta(
      padding: padding != null ? EdgeInsetsGeometryDelta.value(padding!) : null,
      decoration: DecorationDelta.boxDelta(
        color: effectiveColor,
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
