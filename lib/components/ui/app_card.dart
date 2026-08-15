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

  @override
  Widget build(BuildContext context) {
    // Build StyleDelta if padding, borderRadius, or border override provided
    final styleDelta =
        (padding != null || borderRadius != null || border != null)
            ? FCardStyleDelta.delta(
                padding: padding != null
                    ? EdgeInsetsGeometryDelta.value(padding!)
                    : null,
                decoration: (borderRadius != null || border != null)
                    ? DecorationDelta.boxDelta(
                        borderRadius: borderRadius,
                        border: border,
                      )
                    : null,
              )
            : null;

    final card = styleDelta != null
        ? FCard(
            style: styleDelta,
            child: child,
          )
        : FCard(child: child);

    // Wrap in SizedBox if height provided
    final cardWithHeight =
        height != null ? SizedBox(height: height, child: card) : card;

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: cardWithHeight);
    }

    return cardWithHeight;
  }
}
