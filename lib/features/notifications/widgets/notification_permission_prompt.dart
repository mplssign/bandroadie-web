import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../push_notification_service.dart';

// ============================================================================
// NOTIFICATION PERMISSION PROMPT
// In-app prompt shown BEFORE requesting system notification permission
// Users must explicitly opt-in before we show the OS permission dialog
// ============================================================================

/// Notifier to track if permission prompt has been dismissed
class PermissionPromptDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final permissionPromptDismissedProvider =
    NotifierProvider<PermissionPromptDismissedNotifier, bool>(
      PermissionPromptDismissedNotifier.new,
    );

class NotificationPermissionPrompt extends ConsumerWidget {
  const NotificationPermissionPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(permissionPromptDismissedProvider);

    if (dismissed) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(Spacing.pagePadding),
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                color: AppColors.accent,
                size: 24,
              ),
              const SizedBox(width: Spacing.space12),
              Expanded(
                child: Text(
                  'Stay in the Loop',
                  style: AppTextStyles.headline.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: AppColors.textSecondary,
                onPressed: () {
                  ref
                      .read(permissionPromptDismissedProvider.notifier)
                      .dismiss();
                },
              ),
            ],
          ),
          const SizedBox(height: Spacing.space8),
          Text(
            'Get notified when your band schedules gigs, rehearsals, or marks block-out dates.',
            style: AppTextStyles.callout.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.space16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    ref.read(permissionPromptDismissedProvider.notifier).state =
                        true;
                  },
                  child: Text(
                    'Not Now',
                    style: AppTextStyles.callout.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.space12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () async {
                    // Dismiss the in-app prompt
                    ref
                        .read(permissionPromptDismissedProvider.notifier)
                        .dismiss();

                    // Now request OS permission
                    final service = ref.read(pushNotificationServiceProvider);
                    final granted = await service.requestPermission();

                    if (granted) {
                      // Register device token
                      await service.registerToken();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🎸 Notifications enabled!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.textPrimary,
                  ),
                  child: Text(
                    'Enable Notifications',
                    style: AppTextStyles.callout.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// NOTIFICATION SETTINGS BUTTON
// Button in settings to enable notifications after initial dismissal
// ============================================================================

class EnableNotificationsButton extends ConsumerStatefulWidget {
  const EnableNotificationsButton({super.key});

  @override
  ConsumerState<EnableNotificationsButton> createState() =>
      _EnableNotificationsButtonState();
}

class _EnableNotificationsButtonState
    extends ConsumerState<EnableNotificationsButton> {
  bool _isChecking = true;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final service = ref.read(pushNotificationServiceProvider);
    final granted = await service.hasPermission();
    if (mounted) {
      setState(() {
        _hasPermission = granted;
        _isChecking = false;
      });
    }
  }

  Future<void> _enableNotifications() async {
    final service = ref.read(pushNotificationServiceProvider);
    final granted = await service.requestPermission();

    if (granted) {
      await service.registerToken();
      if (mounted) {
        setState(() => _hasPermission = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎸 Notifications enabled!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const SizedBox.shrink();
    }

    if (_hasPermission) {
      return ListTile(
        leading: Icon(Icons.check_circle, color: AppColors.accent),
        title: const Text('Push Notifications'),
        subtitle: const Text('Enabled'),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: AppColors.textSecondary,
        ),
        onTap: () {
          // Could navigate to detailed settings
        },
      );
    }

    return ListTile(
      leading: Icon(
        Icons.notifications_off_outlined,
        color: AppColors.textSecondary,
      ),
      title: const Text('Enable Push Notifications'),
      subtitle: const Text('Get notified about band activity'),
      trailing: ElevatedButton(
        onPressed: _enableNotifications,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space16,
            vertical: Spacing.space8,
          ),
        ),
        child: const Text('Enable'),
      ),
    );
  }
}
