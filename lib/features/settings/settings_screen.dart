import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/services/supabase_client.dart';
import '../../app/theme/brand_colors.dart';
import '../../app/theme/design_tokens.dart';
import '../../app/theme/theme_mode_controller.dart';
import '../../shared/utils/snackbar_helper.dart';
import '../notifications/notification_settings_screen.dart';
import '../calendar/one_calendar_settings_screen.dart';
import '../songs/enrichment_settings_screen.dart';
import '../bands/active_band_controller.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';
import 'package:bandroadie/components/ui/app_app_bar.dart';
import 'package:bandroadie/components/ui/app_icon_button.dart';
import 'package:bandroadie/components/ui/app_progress_indicator.dart';
import 'package:bandroadie/components/ui/app_switch.dart';
import 'package:bandroadie/components/ui/app_dialog.dart';
import 'package:bandroadie/components/ui/app_button.dart';

// ============================================================================
// SETTINGS SCREEN
// Displays app settings with Delete Account as the final item.
// Meets Apple App Store Guideline 5.1.1(v) for account deletion.
// ============================================================================

/// Settings item model for extensibility
class SettingsItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const SettingsItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isDeleting = false;

  /// Build the list of settings items.
  /// Delete Account is always last (enforced programmatically).
  List<SettingsItem> _buildSettingsItems() {
    // Regular settings items (add more here as needed)
    final regularItems = <SettingsItem>[
      SettingsItem(
        icon: AppIcons.bell,
        label: 'Notifications',
        subtitle: 'Manage push notifications',
        onTap: _openNotifications,
      ),
      SettingsItem(
        icon: AppIcons.music,
        label: 'Song Enrichment',
        subtitle:
            'Configure how songs are enriched with BPM, Duration, and Key',
        onTap: _openEnrichmentSettings,
      ),
      SettingsItem(
        icon: AppIcons.music,
        label: 'Song tempo & key data via GetSongBPM.com',
        onTap: _openGetSongBpmAttribution,
      ),
    ];

    // Conditionally add One Calendar (only if user has 2+ bands)
    final bandCount = ref.watch(activeBandProvider).userBands.length;
    if (bandCount >= 2) {
      regularItems.add(
        SettingsItem(
          icon: AppIcons.calendar,
          label: 'One Calendar',
          subtitle: 'Share block-out dates across bands',
          onTap: _openOneCalendar,
        ),
      );
    }

    // Delete Account - always last (enforced here)
    final deleteAccountItem = SettingsItem(
      icon: AppIcons.delete,
      label: 'Delete Account',
      subtitle: 'Permanently delete your account and all data',
      onTap: _showDeleteConfirmation,
      isDestructive: true,
    );

    return [...regularItems, deleteAccountItem];
  }

  /// Navigate to notification settings
  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NotificationSettingsScreen(),
      ),
    );
  }

  /// Navigate to enrichment settings
  void _openEnrichmentSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const EnrichmentSettingsScreen(),
      ),
    );
  }

  /// Navigate to One Calendar settings
  void _openOneCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const OneCalendarSettingsScreen(),
      ),
    );
  }

  /// Open the GetSongBPM attribution link (required by their API terms).
  Future<void> _openGetSongBpmAttribution() async {
    final uri = Uri.parse('https://getsongbpm.com');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Show confirmation dialog for account deletion
  Future<void> _showDeleteConfirmation() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              AppIcons.warning,
              color: AppColors.error,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete Account?',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: AppFontSizes.title2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This action is permanent and cannot be undone.',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Deleting your account will:',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: AppFontSizes.subhead,
              ),
            ),
            const SizedBox(height: 8),
            _buildBulletPoint('Remove your profile and personal data'),
            _buildBulletPoint('Remove you from all bands'),
            _buildBulletPoint(
              'Delete bands you created (if you\'re the only member)',
            ),
            _buildBulletPoint('Delete all your gig responses and notes'),
            const SizedBox(height: 16),
            Text(
              'This cannot be reversed. Are you sure?',
              style: TextStyle(
                color: AppColors.error,
                fontSize: AppFontSizes.subhead,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Delete Account',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _performAccountDeletion();
    }
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: AppFontSizes.subhead,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: AppFontSizes.subhead,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Perform the actual account deletion
  Future<void> _performAccountDeletion() async {
    setState(() => _isDeleting = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Not logged in');
      }

      // Call the Supabase RPC function to delete user data
      // This function handles cascading deletes safely
      await supabase.rpc(
        'delete_user_account',
        params: {'user_id_to_delete': userId},
      );

      // Sign out after successful deletion
      await supabase.auth.signOut();

      // Navigate to login screen
      if (mounted) {
        // Pop all routes and let auth gate handle redirect
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on PostgrestException catch (e) {
      setState(() => _isDeleting = false);
      if (mounted) {
        showErrorSnackBar(
          context,
          message: 'Failed to delete account: ${e.message}',
        );
      }
    } catch (e) {
      setState(() => _isDeleting = false);
      if (mounted) {
        showErrorSnackBar(
          context,
          message: 'Failed to delete account. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildSettingsItems();
    // Separate Delete Account from regular items
    final regularItems = items.where((item) => !item.isDestructive).toList();
    final deleteAccountItem = items.firstWhere((item) => item.isDestructive);

    return AppScaffold(
      backgroundColor: context.colors.background,
      appBar: AppAppBar(
        backgroundColor: context.colors.appBarBg,
        title: Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: AppFontSizes.title2,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: AppIconButton(
          icon: AppIcons.arrowLeft,
          color: AppColors.primary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isDeleting
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppProgressIndicator(
                    type: ProgressIndicatorType.circular,
                    color: AppColors.error,
                  ),
                  SizedBox(height: 24),
                  Text(
                    'Deleting your account...',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: AppFontSizes.body,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'This may take a moment',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: AppFontSizes.subhead,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Scrollable area for regular settings items
                if (regularItems.isNotEmpty)
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: regularItems.length,
                    itemBuilder: (context, index) {
                      return _SettingsListItem(item: regularItems[index]);
                    },
                  ),
                Divider(
                  color: context.colors.surfaceOverlay,
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                ),
                // Light mode toggle
                _LightModeToggle(),
                Divider(
                  color: context.colors.surfaceOverlay,
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                ),
                const Spacer(),

                // Bottom-anchored Delete Account section
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (regularItems.isNotEmpty) ...[
                      Divider(
                        color: context.colors.surfaceOverlay,
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      const SizedBox(height: 8),
                    ],
                    _SettingsListItem(item: deleteAccountItem),
                    // Bottom safe area padding
                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 16,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Light mode toggle widget
class _LightModeToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLight = ref.watch(themeModeProvider) == ThemeMode.light;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(Icons.light_mode, color: context.colors.textSecondary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Light mode',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Switch to light theme',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: AppFontSizes.caption,
                  ),
                ),
              ],
            ),
          ),
          AppSwitch(
            value: isLight,
            onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// Individual settings list item widget
class _SettingsListItem extends StatelessWidget {
  final SettingsItem item;

  const _SettingsListItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final textColor =
        item.isDestructive ? AppColors.error : context.colors.textPrimary;

    final iconColor =
        item.isDestructive ? AppColors.error : context.colors.textSecondary;

    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(item.icon, color: iconColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: AppFontSizes.body,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      style: TextStyle(
                        color: item.isDestructive
                            ? AppColors.error.withValues(alpha: 0.7)
                            : context.colors.textSecondary,
                        fontSize: AppFontSizes.caption,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              AppIcons.forward,
              color: item.isDestructive
                  ? AppColors.error.withValues(alpha: 0.5)
                  : context.colors.textSecondary.withValues(alpha: 0.5),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
