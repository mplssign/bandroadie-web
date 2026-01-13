import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';

// ============================================================================
// GLASS SURFACE
// iOS-style translucent glass effect with optional edge fade.
//
// USAGE:
//   GlassSurface(
//     blurSigma: 12.0,
//     tintOpacity: 0.15,
//     edge: GlassEdge.bottom, // or GlassEdge.top for header
//     edgeFadeStrength: 0.3,
//     child: YourContent(),
//   )
//
// SCROLL-DRIVEN BLUR:
// Both header and footer should read from scrollBlurProvider and use:
//   blurSigma: scrollBlur.lerpTo(8.0, 18.0)
//   tintOpacity: scrollBlur.lerpTo(0.10, 0.25)
//   edgeFadeStrength: scrollBlur.lerpTo(0.15, 0.55)
//
// PERFORMANCE:
// - BackdropFilter is clipped to widget bounds via ClipRRect/ClipRect
// - Blur sigma capped at 20.0 to avoid GPU strain
// - Only repaints when blurSigma/tintOpacity change, not on layout
// ============================================================================

/// Which edge to apply the scroll-shadow gradient fade.
enum GlassEdge {
  /// No edge fade
  none,

  /// Fade at top edge (for bottom nav - shadow cast by content above)
  top,

  /// Fade at bottom edge (for header - shadow cast by content below)
  bottom,
}

/// A widget that applies an iOS-style translucent glass effect.
///
/// Features:
/// - BackdropFilter blur for content behind the widget
/// - Configurable tint color and opacity
/// - Optional edge gradient fade (scroll shadow effect)
/// - Efficient clipping to prevent full-screen blur
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blurSigma = 10.0,
    this.tintColor,
    this.tintOpacity = 0.5,
    this.border,
    this.borderRadius,
    this.padding,
    this.height,
    this.width,
    this.edge = GlassEdge.none,
    this.edgeFadeStrength = 0.0,
    // Legacy parameters - deprecated, use edge/edgeFadeStrength instead
    @Deprecated('Use edge: GlassEdge.top instead') this.topEdgeFade = false,
    @Deprecated('Use edgeFadeStrength instead') this.topEdgeFadeStrength = 0.0,
  });

  /// The child widget displayed on top of the glass effect.
  final Widget child;

  /// Blur intensity (0..20). Higher = more blur.
  /// Capped at 20.0 for performance.
  final double blurSigma;

  /// The tint color applied over the blur.
  /// Defaults to AppColors.appBarBg.
  final Color? tintColor;

  /// Opacity of the tint color (0.0..1.0).
  /// Default 0.5 for subtle frosted appearance.
  final double tintOpacity;

  /// Optional border around the glass surface.
  final Border? border;

  /// Border radius for rounded corners.
  final BorderRadius? borderRadius;

  /// Internal padding.
  final EdgeInsetsGeometry? padding;

  /// Fixed height. If null, uses intrinsic height.
  final double? height;

  /// Fixed width. If null, expands to fill.
  final double? width;

  /// Which edge to apply the scroll-shadow gradient fade.
  /// - GlassEdge.top: For bottom nav (shadow at top)
  /// - GlassEdge.bottom: For header (shadow at bottom)
  /// - GlassEdge.none: No fade
  final GlassEdge edge;

  /// Intensity of the edge fade (0.0..1.0).
  /// 0.0 = invisible, 1.0 = fully visible.
  final double edgeFadeStrength;

  // Legacy parameters (deprecated)
  final bool topEdgeFade;
  final double topEdgeFadeStrength;

  @override
  Widget build(BuildContext context) {
    // Clamp blur sigma for performance
    final clampedBlur = blurSigma.clamp(0.0, 20.0);

    final bgColor = (tintColor ?? AppColors.appBarBg).withValues(
      alpha: tintOpacity,
    );

    // Determine effective edge and strength (support legacy API)
    final effectiveEdge = topEdgeFade ? GlassEdge.top : edge;
    final effectiveStrength = topEdgeFade
        ? topEdgeFadeStrength
        : edgeFadeStrength;

    // Main container with tint
    Widget content = Container(
      height: height,
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        border: border,
      ),
      child: child,
    );

    // Add edge fade if enabled
    if (effectiveEdge != GlassEdge.none && effectiveStrength > 0.0) {
      content = Stack(
        children: [
          content,
          // Edge gradient fade
          _buildEdgeFade(effectiveEdge, effectiveStrength),
        ],
      );
    }

    // Apply blur with proper clipping
    Widget blurred;
    if (borderRadius != null) {
      blurred = ClipRRect(
        borderRadius: borderRadius!,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: clampedBlur, sigmaY: clampedBlur),
          child: content,
        ),
      );
    } else {
      blurred = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: clampedBlur, sigmaY: clampedBlur),
          child: content,
        ),
      );
    }

    return blurred;
  }

  Widget _buildEdgeFade(GlassEdge fadeEdge, double strength) {
    final isTop = fadeEdge == GlassEdge.top;

    // Border radius for the fade gradient
    BorderRadius? fadeRadius;
    if (borderRadius != null) {
      fadeRadius = isTop
          ? BorderRadius.only(
              topLeft: borderRadius!.topLeft,
              topRight: borderRadius!.topRight,
            )
          : BorderRadius.only(
              bottomLeft: borderRadius!.bottomLeft,
              bottomRight: borderRadius!.bottomRight,
            );
    }

    return Positioned(
      left: 0,
      right: 0,
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      height: 16.0,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: fadeRadius,
            gradient: LinearGradient(
              begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35 * strength),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
