import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/components/ui/app_dialog.dart';
import 'package:bandroadie/components/ui/app_button.dart';

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
    await showAppDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const NotificationSettingsModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && Platform.isIOS;

    return Dialog(
      backgroundColor: context.colors.surface,
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
                color: context.colors.textMuted.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                AppIcons.bellOff,
                color: context.colors.textMuted,
                size: 32,
              ),
            ),

            const SizedBox(height: Spacing.space20),

            // Title
            Text(
              'Notifications Disabled',
              style: AppTextStyles.title3.copyWith(
                color: context.colors.textPrimary,
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
                color: context.colors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: Spacing.space8),

            // Instructions
            Container(
              padding: const EdgeInsets.all(Spacing.space12),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isIOS
                    ? 'Settings → Notifications → BandRoadie'
                    : 'Settings → Apps → BandRoadie → Permissions',
                style: AppTextStyles.footnote.copyWith(
                  color: context.colors.textSecondary,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: Spacing.space24),

            // Open Settings button
            AppButton(
              label: 'Open Settings',
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                Navigator.of(context).pop();
                await _openAppSettings();
              },
              fullWidth: true,
            ),

            const SizedBox(height: Spacing.space12),

            // Cancel button
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.text,
              onPressed: () {
                Navigator.of(context).pop();
              },
              fullWidth: true,
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
