import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/brand_action_button.dart';

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
                color: AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                size: 40,
                color: AppColors.accent,
              ),
            ),

            const SizedBox(height: 24),

            // Title (Title Case)
            const Text(
              'No Members Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // Subtitle with humor
            const Text(
              "It's just you and your dreams.\nInvite someone before you become a solo act.",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Invite button
            if (onInviteTap != null)
              BrandActionButton(
                label: '+ Invite Member',
                onPressed: onInviteTap,
                icon: Icons.person_add_outlined,
              ),
          ],
        ),
      ),
    );
  }
}
