import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../shared/widgets/toggle_tile.dart';
import 'notification_controller.dart';
import 'push_notification_service.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// NOTIFICATION PREFERENCES SCREEN
// Settings for notification types and delivery methods
// ============================================================================

class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  bool _hasSystemPermission = false;

  @override
  void initState() {
    super.initState();
    _checkSystemPermission();
  }

  Future<void> _checkSystemPermission() async {
    final service = ref.read(pushNotificationServiceProvider);
    final granted = await service.hasPermission();
    if (mounted) {
      setState(() => _hasSystemPermission = granted);
    }
  }

  Future<void> _requestPermission() async {
    final service = ref.read(pushNotificationServiceProvider);
    final granted = await service.requestPermission();
    if (mounted) {
      setState(() => _hasSystemPermission = granted);
      if (granted) {
        await service.registerToken();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: Text(
          'Notifications',
          style: AppTextStyles.title3.copyWith(color: context.colors.textPrimary),
        ),
        leading: IconButton(
          icon: Icon(AppIcons.back, color: context.colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: prefsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, _) => Center(
          child: Text(
            'Error loading preferences',
            style: AppTextStyles.body.copyWith(color: context.colors.textSecondary),
          ),
        ),
        data: (prefs) => ListView(
          padding: const EdgeInsets.all(Spacing.pagePadding),
          children: [
            // System permission banner (if not granted)
            if (!_hasSystemPermission) ...[
              _buildPermissionBanner(),
              const SizedBox(height: Spacing.space24),
            ],

            // Push notifications master toggle
            _buildSectionHeader('Push Notifications'),
            const SizedBox(height: Spacing.space12),
            AppToggleTile(
              title: 'Enable Push Notifications',
              subtitle: 'Receive notifications when the app is closed',
              value: prefs.pushEnabled && _hasSystemPermission,
              enabled: _hasSystemPermission,
              onChanged: (value) {
                ref
                    .read(notificationPreferencesProvider.notifier)
                    .togglePushEnabled(value);
              },
            ),

            const SizedBox(height: Spacing.space24),

            // Notification categories
            _buildSectionHeader('Notification Types'),
            const SizedBox(height: Spacing.space12),

            AppToggleTile(
              title: 'Gig Updates',
              subtitle: 'New gigs, changes, and confirmations',
              value: prefs.gigsEnabled,
              onChanged: (value) {
                ref
                    .read(notificationPreferencesProvider.notifier)
                    .toggleGigUpdates(value);
              },
            ),
            const SizedBox(height: Spacing.space8),

            AppToggleTile(
              title: 'Rehearsal Updates',
              subtitle: 'Rehearsal schedules and changes',
              value: prefs.rehearsalsEnabled,
              onChanged: (value) {
                ref
                    .read(notificationPreferencesProvider.notifier)
                    .toggleRehearsalUpdates(value);
              },
            ),
            const SizedBox(height: Spacing.space8),

            AppToggleTile(
              title: 'Setlist Updates',
              subtitle: 'Changes to setlists and song order',
              value: prefs.setlistUpdates,
              onChanged: (value) {
                ref
                    .read(notificationPreferencesProvider.notifier)
                    .toggleSetlistUpdates(value);
              },
            ),
            const SizedBox(height: Spacing.space8),

            AppToggleTile(
              title: 'Availability Requests',
              subtitle: 'When someone asks for your availability',
              value: prefs.availabilityRequests,
              onChanged: (value) {
                ref
                    .read(notificationPreferencesProvider.notifier)
                    .toggleAvailabilityRequests(value);
              },
            ),
            const SizedBox(height: Spacing.space8),

            AppToggleTile(
              title: 'Member Updates',
              subtitle: 'When members join, leave, or change roles',
              value: prefs.memberUpdates,
              onChanged: (value) {
                ref
                    .read(notificationPreferencesProvider.notifier)
                    .toggleMemberUpdates(value);
              },
            ),

            const SizedBox(height: Spacing.space32),

            // Info text
            Text(
              'In-app notifications are always enabled. These settings control push notifications only.',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                AppIcons.bellOff,
                color: AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: Spacing.space12),
              Expanded(
                child: Text(
                  'Notifications are disabled',
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.space8),
          Text(
            'Enable notifications to stay updated on gigs, rehearsals, and band activity.',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: Spacing.space12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _requestPermission,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                ),
              ),
              child: const Text('Enable Notifications'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTextStyles.headline.copyWith(color: context.colors.textPrimary),
    );
  }

}
