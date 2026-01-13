import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/services/supabase_client.dart';
import '../../app/theme/design_tokens.dart';
import '../../shared/utils/snackbar_helper.dart';

// ============================================================================
// SETTINGS SCREEN
// Displays app settings with Delete Account as the final item.
// Meets Apple App Store Guideline 5.1.1(v) for account deletion.
// ============================================================================

/// Design tokens for settings screen
class _SettingsTokens {
  _SettingsTokens._();

  static const Color background = Color(0xFF0F172A); // slate-900
  static const Color cardBackground = Color(0xFF1E293B); // slate-800
  static const Color divider = Color(0xFF334155); // slate-700
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8); // slate-400
  static const Color destructive = Color(0xFFEF4444); // red-500
  static const Color destructiveBg = Color(0xFF7F1D1D); // red-900
}

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
      // Future items can be added here:
      // SettingsItem(
      //   icon: Icons.notifications_outlined,
      //   label: 'Notifications',
      //   subtitle: 'Manage push notifications',
      //   onTap: () => _openNotifications(),
      // ),
      // SettingsItem(
      //   icon: Icons.palette_outlined,
      //   label: 'Appearance',
      //   subtitle: 'Theme and display options',
      //   onTap: () => _openAppearance(),
      // ),
      // SettingsItem(
      //   icon: Icons.info_outline,
      //   label: 'About',
      //   subtitle: 'App info and licenses',
      //   onTap: () => _openAbout(),
      // ),
    ];

    // Delete Account - always last (enforced here)
    final deleteAccountItem = SettingsItem(
      icon: Icons.delete_forever_outlined,
      label: 'Delete Account',
      subtitle: 'Permanently delete your account and all data',
      onTap: _showDeleteConfirmation,
      isDestructive: true,
    );

    return [...regularItems, deleteAccountItem];
  }

  /// Show confirmation dialog for account deletion
  Future<void> _showDeleteConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (context) => AlertDialog(
        backgroundColor: _SettingsTokens.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: _SettingsTokens.destructive,
              size: 28,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delete Account?',
                style: TextStyle(
                  color: _SettingsTokens.textPrimary,
                  fontSize: 20,
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
            const Text(
              'This action is permanent and cannot be undone.',
              style: TextStyle(
                color: _SettingsTokens.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Deleting your account will:',
              style: TextStyle(
                color: _SettingsTokens.textSecondary,
                fontSize: 14,
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
            const Text(
              'This cannot be reversed. Are you sure?',
              style: TextStyle(
                color: _SettingsTokens.destructive,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: _SettingsTokens.textSecondary,
                fontSize: 16,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              backgroundColor: _SettingsTokens.destructive,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Delete Account',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
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
          const Text(
            '• ',
            style: TextStyle(
              color: _SettingsTokens.textSecondary,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _SettingsTokens.textSecondary,
                fontSize: 14,
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
    final hasRegularItems = items.length > 1;

    return Scaffold(
      backgroundColor: _SettingsTokens.background,
      appBar: AppBar(
        backgroundColor: AppColors.appBarBg,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: _SettingsTokens.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isDeleting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: _SettingsTokens.destructive),
                  SizedBox(height: 24),
                  Text(
                    'Deleting your account...',
                    style: TextStyle(
                      color: _SettingsTokens.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'This may take a moment',
                    style: TextStyle(
                      color: _SettingsTokens.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount:
                  items.length + (hasRegularItems ? 1 : 0), // +1 for divider
              itemBuilder: (context, index) {
                // If we have regular items, add a divider before Delete Account
                if (hasRegularItems && index == items.length - 1) {
                  // Divider before destructive section
                  return Column(
                    children: [
                      const SizedBox(height: 24),
                      const Divider(
                        color: _SettingsTokens.divider,
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      const SizedBox(height: 24),
                      _SettingsListItem(item: items.last),
                    ],
                  );
                }

                // Adjust index if we added the divider
                final itemIndex = hasRegularItems && index >= items.length - 1
                    ? items.length - 1
                    : index;

                // Skip if we already rendered the last item with divider
                if (hasRegularItems && index == items.length) {
                  return const SizedBox.shrink();
                }

                return _SettingsListItem(item: items[itemIndex]);
              },
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
    final textColor = item.isDestructive
        ? _SettingsTokens.destructive
        : _SettingsTokens.textPrimary;

    final iconColor = item.isDestructive
        ? _SettingsTokens.destructive
        : _SettingsTokens.textSecondary;

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
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      style: TextStyle(
                        color: item.isDestructive
                            ? _SettingsTokens.destructive.withValues(alpha: 0.7)
                            : _SettingsTokens.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: item.isDestructive
                  ? _SettingsTokens.destructive.withValues(alpha: 0.5)
                  : _SettingsTokens.textSecondary.withValues(alpha: 0.5),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
