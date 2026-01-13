import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// MEMBER CARD SKELETON
// Loading placeholder that matches the MemberCard layout.
// Uses shimmer effect for polished loading state.
// ============================================================================

class MemberCardSkeleton extends StatefulWidget {
  const MemberCardSkeleton({super.key});

  @override
  State<MemberCardSkeleton> createState() => _MemberCardSkeletonState();
}

class _MemberCardSkeletonState extends State<MemberCardSkeleton>
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
            color: const Color(0xFF0B0F14),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.borderMuted.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name placeholder
                _buildShimmerBox(width: 200, height: 32),

                const SizedBox(height: 14),

                // Role pills row
                Row(
                  children: [
                    _buildShimmerPill(width: 70),
                    const SizedBox(width: 8),
                    _buildShimmerPill(width: 60),
                    const SizedBox(width: 8),
                    _buildShimmerPill(width: 85),
                  ],
                ),

                const SizedBox(height: 24),

                // Contact rows
                _buildContactRowSkeleton(),
                const SizedBox(height: 14),
                _buildContactRowSkeleton(width: 180),
                const SizedBox(height: 14),
                _buildContactRowSkeleton(width: 240),
                const SizedBox(height: 14),
                _buildContactRowSkeleton(width: 130),
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
      colors: const [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF1E293B)],
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

  Widget _buildShimmerPill({required double width}) {
    final gradient = LinearGradient(
      begin: Alignment(-1.0 + 2.0 * _shimmerController.value, 0),
      end: Alignment(1.0 + 2.0 * _shimmerController.value, 0),
      colors: const [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF1E293B)],
      stops: const [0.0, 0.5, 1.0],
    );

    return Container(
      width: width,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: gradient,
      ),
    );
  }

  Widget _buildContactRowSkeleton({double width = 220}) {
    final gradient = LinearGradient(
      begin: Alignment(-1.0 + 2.0 * _shimmerController.value, 0),
      end: Alignment(1.0 + 2.0 * _shimmerController.value, 0),
      colors: const [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF1E293B)],
      stops: const [0.0, 0.5, 1.0],
    );

    return Row(
      children: [
        // Icon placeholder
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: gradient,
          ),
        ),
        const SizedBox(width: 12),
        // Text placeholder
        Container(
          width: width,
          height: 18,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: gradient,
          ),
        ),
      ],
    );
  }
}
