import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/models/gig.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/utils/time_formatter.dart';

// ============================================================================
// CONFIRMED GIG CARD
// Figma: 271x126px, radius 8
// Animated rotating gradient border from blue (#2563EB) to rose (#F43F5E)
// Layout: Title 20px, Location gray-400 16px, Date 17px bold, Time gray-400
// ============================================================================

class ConfirmedGigCard extends StatefulWidget {
  final Gig gig;
  final VoidCallback? onTap;
  final int index; // Used to create unique random speed per card

  const ConfirmedGigCard({
    super.key,
    required this.gig,
    this.onTap,
    this.index = 0,
  });

  @override
  State<ConfirmedGigCard> createState() => _ConfirmedGigCardState();
}

class _ConfirmedGigCardState extends State<ConfirmedGigCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    // Create slightly different speed for each card (3-6 seconds based on index)
    final random = math.Random(widget.index);
    final durationSeconds = 3 + random.nextInt(4); // 3-6 seconds
    _rotationController = AnimationController(
      duration: Duration(seconds: durationSeconds),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with AnimatedScale for subtle press feedback on tap
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap ?? () {},
      child: AnimatedScale(
        scale: _isPressed ? AnimScales.cardPressed : 1.0,
        duration: AppDurations.fast,
        curve: AppCurves.ease,
        child: AnimatedBuilder(
          animation: _rotationController,
          builder: (context, child) {
            return CustomPaint(
              painter: _GradientBorderPainter(
                rotation: _rotationController.value * 2 * math.pi,
                borderWidth: 3,
                borderRadius: Spacing.buttonRadius,
              ),
              child: child,
            );
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
            height: Spacing.gigCardHeight, // 126px
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.space20,
              vertical: Spacing.space16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title - 20px Title3/Emphasized
                Text(
                  widget.gig.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 2),

                // Location - 16px Callout/Regular, gray-400
                Text(
                  widget.gig.location,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF94A3B8), // gray-400
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const Spacer(),

                // Date - 17px Headline bold
                Text(
                  _formatFullDate(widget.gig.date),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 2),

                // Time - 16px Callout/Regular, gray-400
                Text(
                  TimeFormatter.formatRange(
                    widget.gig.startTime,
                    widget.gig.endTime,
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF94A3B8), // gray-400
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatFullDate(DateTime date) {
    final days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Custom painter for rotating gradient border
class _GradientBorderPainter extends CustomPainter {
  final double rotation;
  final double borderWidth;
  final double borderRadius;

  _GradientBorderPainter({
    required this.rotation,
    required this.borderWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(borderWidth / 2),
      Radius.circular(borderRadius),
    );

    // Seamless rotating gradient with smooth color transitions
    final gradient = SweepGradient(
      center: Alignment.center,
      colors: const [
        Color(0xFF2563EB), // blue-600
        Color(0xFF7C3AED), // violet (midpoint blend)
        Color(0xFFF43F5E), // rose-500
        Color(0xFF7C3AED), // violet (midpoint blend)
        Color(0xFF2563EB), // blue-600 (seamless)
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(rotation),
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GradientBorderPainter oldDelegate) {
    return oldDelegate.rotation != rotation;
  }
}
