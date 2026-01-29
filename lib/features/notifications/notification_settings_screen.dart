import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../../shared/utils/snackbar_helper.dart';
import 'notification_preferences_controller.dart';

// ============================================================================
// NOTIFICATION SETTINGS SCREEN
// Master toggle + 4 subcategory checkboxes for notification preferences
// ============================================================================

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

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
        data: (prefs) => _buildContent(context, ref, prefs),
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

  Widget _buildContent(BuildContext context, WidgetRef ref, dynamic prefs) {
    final notificationsEnabled = prefs.notificationsEnabled as bool;

    return ListView(
      padding: const EdgeInsets.all(Spacing.pagePadding),
      children: [
        // Master toggle
        _MasterToggleCard(
          enabled: notificationsEnabled,
          onChanged: (value) async {
            try {
              await ref
                  .read(notificationPreferencesProvider.notifier)
                  .updateNotificationsEnabled(value);
            } catch (e) {
              if (context.mounted) {
                showErrorSnackBar(
                  context,
                  message: 'Failed to update notification settings',
                );
              }
            }
          },
        ),

        const SizedBox(height: Spacing.space16),

        // Subcategory section (only shown when notifications are enabled)
        if (notificationsEnabled) ...[
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
            onChanged: notificationsEnabled
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
            onChanged: notificationsEnabled
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
            onChanged: notificationsEnabled
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
            onChanged: notificationsEnabled
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
            activeColor: AppColors.accent,
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
