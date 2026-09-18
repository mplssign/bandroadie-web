import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/app_card.dart';

// ============================================================================
// REHEARSAL CARD SKELETON
// Loading placeholder that matches the confirmed RehearsalCard layout.
// Uses shimmer effect for polished loading state.
// ============================================================================

class RehearsalCardSkeleton extends StatefulWidget {
  const RehearsalCardSkeleton({super.key});

  @override
  State<RehearsalCardSkeleton> createState() => _RehearsalCardSkeletonState();
}

class _RehearsalCardSkeletonState extends State<RehearsalCardSkeleton>
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
        return SizedBox(
          width: Spacing.rehearsalCardWidth,
          height: Spacing.rehearsalCardHeight,
          child: AppCard(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.space16,
                Spacing.space16,
                Spacing.space16,
                Spacing.space8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chip pill placeholder
                  _buildShimmerBox(width: 50, height: 20, radius: 10),

                  const SizedBox(height: 14),

                  // Title placeholder
                  _buildShimmerBox(width: 180, height: 20),

                  const SizedBox(height: 8),

                  // Info line 1 placeholder
                  _buildShimmerBox(width: 140, height: 14),

                  const SizedBox(height: 8),

                  // Info line 2 placeholder
                  _buildShimmerBox(width: 110, height: 14),

                  const Spacer(),

                  // Trailing element placeholder
                  _buildShimmerBox(width: 60, height: 24, radius: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    double radius = 8,
  }) {
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
        borderRadius: BorderRadius.circular(radius),
        gradient: gradient,
      ),
    );
  }
}
