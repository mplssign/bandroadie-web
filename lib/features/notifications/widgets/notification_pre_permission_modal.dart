import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../notification_permission_service.dart';

// ============================================================================
// NOTIFICATION PRE-PERMISSION MODAL
// Custom modal shown BEFORE requesting system permission
// Respects Apple, Android, and Web guidelines
// Explains value before triggering native permission prompt
// ============================================================================

class NotificationPrePermissionModal extends ConsumerWidget {
  const NotificationPrePermissionModal({super.key});

  /// Show the modal if appropriate (checks state internally)
  static Future<void> showIfNeeded(BuildContext context, WidgetRef ref) async {
    final permissionState = ref.read(notificationPermissionProvider);

    // Only show if we should (not dismissed + system permission not determined)
    if (!permissionState.shouldShowPrePrompt) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false, // User must choose an action
      builder: (context) => const NotificationPrePermissionModal(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: AppColors.accent,
                size: 32,
              ),
            ),

            const SizedBox(height: Spacing.space20),

            // Title
            Text(
              'Stay in the Loop',
              style: AppTextStyles.title3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: Spacing.space12),

            // Description
            Text(
              'Get notified when your band schedules gigs, rehearsals, or marks block-out dates. '
              'Stay coordinated and never miss an update.',
              style: AppTextStyles.callout.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: Spacing.space24),

            // Enable button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  // Request system permission
                  final service = ref.read(
                    notificationPermissionProvider.notifier,
                  );
                  await service.requestPermissionFromPrePrompt();

                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: Spacing.space16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Enable Notifications',
                  style: AppTextStyles.calloutEmphasized.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: Spacing.space12),

            // Not now button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  // Mark as dismissed (never show again)
                  final service = ref.read(
                    notificationPermissionProvider.notifier,
                  );
                  await service.dismissPrePrompt();

                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    vertical: Spacing.space12,
                  ),
                ),
                child: Text(
                  'Not Now',
                  style: AppTextStyles.callout.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
