import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/app_button.dart';

class GearEmptyState extends StatelessWidget {
  final bool canManageGear;
  final VoidCallback? onAddTap;

  const GearEmptyState({
    super.key,
    required this.canManageGear,
    this.onAddTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.library,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: Spacing.space24),
            Text(
              'No Gear Yet',
              style: TextStyle(
                fontSize: AppFontSizes.sectionTitle,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.space12),
            Text(
              'Your rig vault is empty. Add your first item and keep the band battle-ready.',
              style: TextStyle(
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w400,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.space32),
            if (canManageGear && onAddTap != null)
              AppButton(
                label: 'Add Your First Item',
                icon: AppIcons.add,
                onPressed: onAddTap,
              ),
          ],
        ),
      ),
    );
  }
}
