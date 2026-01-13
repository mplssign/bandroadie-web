import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// ANIMATED GRADIENT BORDER
// A reusable widget that wraps a child with an animated gradient border.
// The gradient rotates/shifts over time to create a "living" effect.
//
// DETERMINISTIC SPEED:
// Each instance can have a unique animation speed derived from a seed (e.g., UUID).
// This ensures the same speed across rebuilds and app relaunches.
// ============================================================================

/// Derives a deterministic animation duration from a setlist ID.
///
/// Uses the ID's hash as a seed to ensure the same speed is generated
/// for the same setlist across rebuilds and app restarts.
///
/// Returns duration in milliseconds within [SetlistCardBorder.minDurationMs, maxDurationMs].
/// Also determines direction (clockwise vs counter-clockwise).
class GradientAnimationConfig {
  final int durationMs;
  final bool clockwise;

  const GradientAnimationConfig({
    required this.durationMs,
    required this.clockwise,
  });

  /// Create a deterministic config from a setlist ID (UUID string).
  factory GradientAnimationConfig.fromId(String id) {
    // Use hashCode as seed for deterministic randomness
    final seed = id.hashCode;
    final random = Random(seed);

    // Generate duration in range [min, max]
    final range =
        SetlistCardBorder.maxDurationMs - SetlistCardBorder.minDurationMs;
    final durationMs = SetlistCardBorder.minDurationMs + random.nextInt(range);

    // Randomly choose direction
    final clockwise = random.nextBool();

    return GradientAnimationConfig(
      durationMs: durationMs,
      clockwise: clockwise,
    );
  }
}

/// An animated gradient border that wraps a child widget.
///
/// The gradient rotates around the border to create a dynamic, alive effect.
/// Animation speed and direction are controlled by [config].
class AnimatedGradientBorder extends StatefulWidget {
  /// The child widget to wrap with the gradient border.
  final Widget child;

  /// Animation configuration (duration and direction).
  /// Use [GradientAnimationConfig.fromId] for deterministic speeds per setlist.
  final GradientAnimationConfig config;

  /// Border thickness. Defaults to [SetlistCardBorder.width].
  final double borderWidth;

  /// Border radius. Defaults to [SetlistCardBorder.radius].
  final double borderRadius;

  /// Gradient colors. Defaults to [AppColors.setlistGradientColors].
  final List<Color>? gradientColors;

  /// Background color for the inner area. Defaults to [AppColors.scaffoldBg].
  final Color? backgroundColor;

  const AnimatedGradientBorder({
    super.key,
    required this.child,
    required this.config,
    this.borderWidth = SetlistCardBorder.width,
    this.borderRadius = SetlistCardBorder.radius,
    this.gradientColors,
    this.backgroundColor,
  });

  @override
  State<AnimatedGradientBorder> createState() => _AnimatedGradientBorderState();
}

class _AnimatedGradientBorderState extends State<AnimatedGradientBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: widget.config.durationMs),
      vsync: this,
    )..repeat();
  }

  @override
  void didUpdateWidget(AnimatedGradientBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update duration if config changes
    if (oldWidget.config.durationMs != widget.config.durationMs) {
      _controller.duration = Duration(milliseconds: widget.config.durationMs);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.gradientColors ?? AppColors.setlistGradientColors;
    final bgColor = widget.backgroundColor ?? AppColors.scaffoldBg;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Calculate rotation angle based on animation value and direction
        final angle = widget.config.clockwise
            ? _controller.value * 2 * pi
            : -_controller.value * 2 * pi;

        return CustomPaint(
          painter: _GradientBorderPainter(
            colors: colors,
            borderWidth: widget.borderWidth,
            borderRadius: widget.borderRadius,
            rotationAngle: angle,
          ),
          child: Container(
            margin: EdgeInsets.all(widget.borderWidth),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(
                widget.borderRadius - widget.borderWidth,
              ),
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Custom painter for the animated gradient border.
///
/// Paints a rounded rectangle with a sweep gradient that rotates.
class _GradientBorderPainter extends CustomPainter {
  final List<Color> colors;
  final double borderWidth;
  final double borderRadius;
  final double rotationAngle;

  _GradientBorderPainter({
    required this.colors,
    required this.borderWidth,
    required this.borderRadius,
    required this.rotationAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Create a sweep gradient centered on the widget
    final gradient = SweepGradient(
      center: Alignment.center,
      colors: colors,
      transform: GradientRotation(rotationAngle),
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    // Draw rounded rectangle border
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        borderWidth / 2,
        borderWidth / 2,
        size.width - borderWidth,
        size.height - borderWidth,
      ),
      Radius.circular(borderRadius - borderWidth / 2),
    );

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GradientBorderPainter oldDelegate) {
    return oldDelegate.rotationAngle != rotationAngle ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.colors != colors;
  }
}
