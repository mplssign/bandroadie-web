import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../../shared/utils/snackbar_helper.dart';
import 'notification_permission_service.dart';
import 'notification_preferences_controller.dart';
import 'widgets/notification_settings_modal.dart';

// ============================================================================
// NOTIFICATION SETTINGS SCREEN
// Apple-compliant notification permission flow with master toggle
// Respects user intent and iOS permission reality at all times
// ============================================================================

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final permissionState = ref.watch(notificationPermissionProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: prefsAsync.when(
        data: (prefs) => _buildContent(context, ref, prefs, permissionState),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Failed to load preferences',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    dynamic prefs,
    NotificationPermissionState permissionState,
  ) {
    // App toggle represents USER INTENT
    // Toggle can only be ON if system permission is granted
    final appToggleEnabled =
        permissionState.enabledInApp &&
        (permissionState.systemPermission ==
                NotificationPermissionStatus.granted ||
            permissionState.systemPermission ==
                NotificationPermissionStatus.notApplicable);

    // Show warning banner if system permission is denied or permanently denied
    final showPermissionDeniedBanner =
        permissionState.systemPermission ==
            NotificationPermissionStatus.denied ||
        permissionState.systemPermission ==
            NotificationPermissionStatus.permanentlyDenied;

    return ListView(
      padding: const EdgeInsets.all(Spacing.pagePadding),
      children: [
        // Warning banner (system permission denied)
        if (showPermissionDeniedBanner) ...[
          _buildPermissionDeniedBanner(context),
          const SizedBox(height: Spacing.space16),
        ],

        // Master toggle (represents user intent + system reality)
        _MasterToggleCard(
          enabled: appToggleEnabled,
          onChanged: (value) async {
            if (value) {
              // User wants to ENABLE notifications
              final service = ref.read(notificationPermissionProvider.notifier);
              final result = await service.enableNotifications();

              if (context.mounted) {
                switch (result) {
                  case NotificationToggleResult.enabled:
                    // Success - refresh state
                    await service.refreshSystemPermission();
                    break;

                  case NotificationToggleResult.denied:
                    // User denied in iOS dialog - show feedback
                    showErrorSnackBar(
                      context,
                      message: 'Notifications permission was denied',
                    );
                    break;

                  case NotificationToggleResult.needsSystemSettings:
                    // System permission denied - show "Open Settings" modal
                    await NotificationSettingsModal.show(context);
                    // Refresh state in case user enabled in Settings
                    await service.refreshSystemPermission();
                    break;
                }
              }
            } else {
              // User wants to DISABLE notifications (simple)
              final service = ref.read(notificationPermissionProvider.notifier);
              await service.disableNotifications();
            }
          },
        ),

        const SizedBox(height: Spacing.space16),

        // Subcategory section (only shown when app toggle is
        // Subcategory section (only shown when app toggle is enabled)
        if (appToggleEnabled) ...[
          Text(
            'Notify me when:',
            style: AppTextStyles.footnote.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: Spacing.space12),

          _CategoryCheckbox(
            label: 'Gigs',
            description: 'Someone schedules a confirmed gig',
            value: prefs.gigsEnabled as bool,
            onChanged: appToggleEnabled
                ? (value) async {
                    try {
                      await ref
                          .read(notificationPreferencesProvider.notifier)
                          .updateGigsEnabled(value ?? false);
                    } catch (e) {
                      if (context.mounted) {
                        showErrorSnackBar(context, message: 'Update failed');
                      }
                    }
                  }
                : null,
          ),

          const SizedBox(height: Spacing.space8),

          _CategoryCheckbox(
            label: 'Potential Gigs',
            description: 'Someone creates a potential gig',
            value: prefs.potentialGigsEnabled as bool,
            onChanged: appToggleEnabled
                ? (value) async {
                    try {
                      await ref
                          .read(notificationPreferencesProvider.notifier)
                          .updatePotentialGigsEnabled(value ?? false);
                    } catch (e) {
                      if (context.mounted) {
                        showErrorSnackBar(context, message: 'Update failed');
                      }
                    }
                  }
                : null,
          ),

          const SizedBox(height: Spacing.space8),

          _CategoryCheckbox(
            label: 'Rehearsals',
            description: 'Someone schedules a rehearsal',
            value: prefs.rehearsalsEnabled as bool,
            onChanged: appToggleEnabled
                ? (value) async {
                    try {
                      await ref
                          .read(notificationPreferencesProvider.notifier)
                          .updateRehearsalsEnabled(value ?? false);
                    } catch (e) {
                      if (context.mounted) {
                        showErrorSnackBar(context, message: 'Update failed');
                      }
                    }
                  }
                : null,
          ),

          const SizedBox(height: Spacing.space8),

          _CategoryCheckbox(
            label: 'Block-out Dates',
            description: 'Someone marks themselves unavailable',
            value: prefs.blockoutsEnabled as bool,
            onChanged: appToggleEnabled
                ? (value) async {
                    try {
                      await ref
                          .read(notificationPreferencesProvider.notifier)
                          .updateBlockoutsEnabled(value ?? false);
                    } catch (e) {
                      if (context.mounted) {
                        showErrorSnackBar(context, message: 'Update failed');
                      }
                    }
                  }
                : null,
          ),
        ],
      ],
    );
  }

  /// Warning banner when system permission is denied
  Widget _buildPermissionDeniedBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.accent, size: 24),
          const SizedBox(width: Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications Disabled',
                  style: AppTextStyles.calloutEmphasized.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'BandRoadie doesn\'t have permission to send notifications. '
                  'Enable the toggle below to fix this.',
                  style: AppTextStyles.footnote.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MASTER TOGGLE CARD
// ============================================================================

class _MasterToggleCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _MasterToggleCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.borderMuted),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_outlined,
            color: enabled ? AppColors.accent : AppColors.textMuted,
            size: 28,
          ),
          const SizedBox(width: Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notifications', style: AppTextStyles.calloutEmphasized),
                const SizedBox(height: 4),
                Text(
                  enabled ? 'You\'ll receive updates' : 'All notifications off',
                  style: AppTextStyles.footnote.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onChanged,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CATEGORY CHECKBOX
// ============================================================================

class _CategoryCheckbox extends StatelessWidget {
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool?>? onChanged;

  const _CategoryCheckbox({
    required this.label,
    required this.description,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onChanged != null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space12,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.borderMuted),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accent,
            side: BorderSide(
              color: isEnabled ? AppColors.borderMuted : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: Spacing.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.callout.copyWith(
                    color: isEnabled
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: AppTextStyles.footnote.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
