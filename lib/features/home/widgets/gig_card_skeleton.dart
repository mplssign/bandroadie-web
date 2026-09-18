import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/app_card.dart';

// ============================================================================
// GIG CARD SKELETON
// Loading placeholder that matches the ConfirmedGigCard layout.
// Uses shimmer effect for polished loading state.
// ============================================================================

class GigCardSkeleton extends StatefulWidget {
  const GigCardSkeleton({super.key});

  @override
  State<GigCardSkeleton> createState() => _GigCardSkeletonState();
}

class _GigCardSkeletonState extends State<GigCardSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(
            color: const Color(0x3322C55E), // green-500 @ 20% alpha
            width: 1.5,
          ),
          color: const Color(0x1F22C55E), // green-500 @ ~12% alpha
          child: Container(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 400),
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.space20,
              vertical: Spacing.space16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title placeholder
                _buildShimmerBox(width: 160, height: 20),

                const SizedBox(height: 6),

                // Location placeholder
                _buildShimmerBox(width: 120, height: 14),

                const SizedBox(height: 8),

                // Date placeholder
                _buildShimmerBox(width: 90, height: 17),

                const SizedBox(height: 4),

                // Time placeholder
                _buildShimmerBox(width: 80, height: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerBox({required double width, required double height}) {
    final gradient = LinearGradient(
      begin: Alignment(-1.0 + 2.0 * _shimmerController.value, 0),
      end: Alignment(1.0 + 2.0 * _shimmerController.value, 0),
      colors: [
        context.colors.surface,
        context.colors.surfaceOverlay,
        context.colors.surface
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: gradient,
      ),
    );
  }
}
