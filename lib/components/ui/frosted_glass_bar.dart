import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// FROSTED GLASS BAR
// A reusable widget that provides an iOS-style frosted glass blur effect.
// Used for app bars, bottom navigation, and other floating UI elements.
//
// USAGE:
//   FrostedGlassBar(
//     height: Spacing.appBarHeight,
//     child: Row(...),
//   )
//
// PERFORMANCE NOTES:
// - Uses ClipRect to constrain blur to the widget bounds
// - BackdropFilter only affects pixels within the clip region
// - Avoid nesting multiple FrostedGlassBar widgets
// ============================================================================

/// Default blur intensity for frosted glass effect
const double kFrostedGlassBlurSigma = 10.0;

/// Default background opacity for frosted glass effect
const double kFrostedGlassOpacity = 0.5;

/// A widget that applies a frosted glass blur effect to its background.
///
/// The blur effect is applied to content behind the widget, creating an
/// elegant translucent appearance similar to iOS navigation bars.
class FrostedGlassBar extends StatelessWidget {
  /// The child widget to display on top of the frosted background.
  final Widget child;

  /// The height of the bar. If null, uses intrinsic height.
  final double? height;

  /// The width of the bar. If null, expands to fill available width.
  final double? width;

  /// The blur intensity. Higher values = more blur.
  /// Default is 10.0 for a subtle, elegant effect.
  final double blurSigma;

  /// The background color applied over the blur.
  /// Default is AppColors.appBarBg with 50% opacity.
  final Color? backgroundColor;

  /// The opacity of the background color (0.0 to 1.0).
  /// Default is 0.5 for a subtle frosted appearance.
  final double backgroundOpacity;

  /// Padding inside the bar.
  final EdgeInsetsGeometry? padding;

  /// Border radius for rounded corners. Null for no rounding.
  final BorderRadius? borderRadius;

  /// Optional decoration for additional styling (borders, shadows, etc.)
  /// Note: If provided, backgroundColor will be ignored - use decoration's color.
  final BoxDecoration? decoration;

  const FrostedGlassBar({
    super.key,
    required this.child,
    this.height,
    this.width,
    this.blurSigma = kFrostedGlassBlurSigma,
    this.backgroundColor,
    this.backgroundOpacity = kFrostedGlassOpacity,
    this.padding,
    this.borderRadius,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor =
        backgroundColor ??
        AppColors.appBarBg.withValues(alpha: backgroundOpacity);

    Widget container = Container(
      height: height,
      width: width,
      padding: padding,
      decoration:
          decoration ??
          BoxDecoration(color: bgColor, borderRadius: borderRadius),
      child: child,
    );

    // Apply border radius clip if specified
    Widget clipped;
    if (borderRadius != null) {
      clipped = ClipRRect(
        borderRadius: borderRadius!,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: container,
        ),
      );
    } else {
      clipped = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: container,
        ),
      );
    }

    return clipped;
  }
}

/// A frosted glass container for floating UI elements.
///
/// Similar to FrostedGlassBar but optimized for cards, modals, and overlays.
class FrostedGlassContainer extends StatelessWidget {
  final Widget child;
  final double blurSigma;
  final Color? backgroundColor;
  final double backgroundOpacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;

  const FrostedGlassContainer({
    super.key,
    required this.child,
    this.blurSigma = kFrostedGlassBlurSigma,
    this.backgroundColor,
    this.backgroundOpacity = 0.6,
    this.padding,
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.border,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor =
        backgroundColor ??
        AppColors.cardBg.withValues(alpha: backgroundOpacity);

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: borderRadius,
              border: border,
              boxShadow: boxShadow,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
