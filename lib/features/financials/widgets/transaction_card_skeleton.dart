import 'package:flutter/material.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';

// ============================================================================
// TRANSACTION CARD SKELETON
// Loading placeholder that matches the financials _TransactionCard layout.
// Uses shimmer effect for polished loading state.
// ============================================================================

class TransactionCardSkeleton extends StatefulWidget {
  const TransactionCardSkeleton({super.key});

  @override
  State<TransactionCardSkeleton> createState() =>
      _TransactionCardSkeletonState();
}

class _TransactionCardSkeletonState extends State<TransactionCardSkeleton>
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
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(Spacing.cardRadius),
            border: Border.all(color: context.colors.border),
          ),
          padding: const EdgeInsets.all(Spacing.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: title + amount
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildShimmerBox(width: 140, height: 16),
                  const Spacer(),
                  _buildShimmerBox(width: 70, height: 16),
                ],
              ),
              const SizedBox(height: Spacing.space4),
              // Row 2: category + chevron
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildShimmerBox(width: 100, height: 12),
                  const Spacer(),
                  _buildShimmerBox(width: 20, height: 20),
                ],
              ),
              const SizedBox(height: Spacing.space4),
              // Row 3: date + badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildShimmerBox(width: 90, height: 12),
                  const Spacer(),
                  _buildShimmerBox(width: 70, height: 18, radius: 4),
                ],
              ),
            ],
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
