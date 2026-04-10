import 'package:flutter/material.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../../components/ui/brand_action_button.dart';

// ============================================================================
// VENUES EMPTY STATE
// Shown when no venues exist for the band.
// ============================================================================

class VenuesEmptyState extends StatelessWidget {
  final VoidCallback? onAddTap;

  const VenuesEmptyState({super.key, this.onAddTap});

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
                AppIcons.location,
                size: 40,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Venues Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              "No venues yet — where's the gig at? 🎸",
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
                label: '+ Add Venue',
                onPressed: onAddTap,
                icon: AppIcons.add,
              ),
          ],
        ),
      ),
    );
  }
}
