import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// NOTIFICATION SETTINGS DEEP LINK MODAL
// Shown when user tries to enable notifications but system permission is denied
// Guides user to system Settings to re-enable permissions
// Works on iOS and Android
// ============================================================================

class NotificationSettingsModal extends StatelessWidget {
  const NotificationSettingsModal({super.key});

  /// Show the modal with system settings guidance
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const NotificationSettingsModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && Platform.isIOS;

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
                color: AppColors.textMuted.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_off_rounded,
                color: AppColors.textMuted,
                size: 32,
              ),
            ),

            const SizedBox(height: Spacing.space20),

            // Title
            Text(
              'Notifications Disabled',
              style: AppTextStyles.title3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: Spacing.space12),

            // Description
            Text(
              isIOS
                  ? 'Notifications are disabled for BandRoadie on this device. '
                        'To enable them, you\'ll need to update your system settings.'
                  : 'Notifications are disabled for BandRoadie. '
                        'To enable them, you\'ll need to update your app settings.',
              style: AppTextStyles.callout.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: Spacing.space8),

            // Instructions
            Container(
              padding: const EdgeInsets.all(Spacing.space12),
              decoration: BoxDecoration(
                color: AppColors.scaffoldBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isIOS
                    ? 'Settings → Notifications → BandRoadie'
                    : 'Settings → Apps → BandRoadie → Permissions',
                style: AppTextStyles.footnote.copyWith(
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: Spacing.space24),

            // Open Settings button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  // Close modal
                  Navigator.of(context).pop();

                  // Open system settings
                  await _openAppSettings();
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
                  'Open Settings',
                  style: AppTextStyles.calloutEmphasized.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: Spacing.space12),

            // Cancel button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    vertical: Spacing.space12,
                  ),
                ),
                child: Text(
                  'Cancel',
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

  /// Open system Settings app to app-specific notification settings
  /// iOS & Android: Uses permission_handler's openAppSettings
  /// Platform-safe (no-op on Web)
  static Future<void> _openAppSettings() async {
    if (kIsWeb) return;

    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('[NotificationSettingsModal] Error opening settings: $e');
    }
  }
}
