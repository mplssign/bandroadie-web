import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../../components/ui/brand_action_button.dart';

// ============================================================================
// CONTACTS EMPTY STATE
// Shown when no standalone contacts exist for the band.
// ============================================================================

class ContactsEmptyState extends StatelessWidget {
  final VoidCallback? onAddTap;

  const ContactsEmptyState({super.key, this.onAddTap});

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
                color: AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.users,
                size: 40,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Contacts Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              "No contacts yet — who's your booking agent? 🎸",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (onAddTap != null)
              BrandActionButton(
                label: 'Add Contact',
                onPressed: onAddTap,
                icon: AppIcons.userAdd,
              ),
          ],
        ),
      ),
    );
  }
}
