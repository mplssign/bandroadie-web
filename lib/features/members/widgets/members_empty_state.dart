import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/app_button.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// MEMBERS EMPTY STATE
// Shown when no active members are in the band.
// Includes witty copy and invite CTA.
// ============================================================================

class MembersEmptyState extends StatelessWidget {
  final VoidCallback? onInviteTap;

  const MembersEmptyState({super.key, this.onInviteTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.users,
                size: 40,
                color: AppColors.primary,
              ),
            ),

            const SizedBox(height: 24),

            // Title (Title Case)
            Text(
              'No Members Yet',
              style: TextStyle(
                fontSize: AppFontSizes.sectionTitle,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // Subtitle with humor
            Text(
              "It's just you and your dreams.\nInvite someone before you become a solo act.",
              style: TextStyle(
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w400,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Invite button
            if (onInviteTap != null)
              AppButton(
                label: '+ Invite Member',
                onPressed: onInviteTap,
                icon: AppIcons.userAdd,
                variant: AppButtonVariant.primary,
              ),
          ],
        ),
      ),
    );
  }
}
