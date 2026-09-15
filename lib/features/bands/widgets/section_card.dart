import 'package:flutter/material.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.space20),
      decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        border: Border.all(
          color: context.colors.border.withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.sectionHeader.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.space20),
          child,
        ],
      ),
    );
  }
}
