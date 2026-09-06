import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/app_scaffold.dart';
import '../../../components/ui/app_app_bar.dart';
import '../../../components/ui/app_icon_button.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/app_dialog.dart';
import '../../../components/ui/app_switch.dart';
import '../../../components/ui/sheet_footer.dart';
import '../../../app/services/supabase_client.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../bands/active_band_controller.dart';
import '../member_vm.dart';
import '../members_controller.dart';
import '../members_repository.dart';
import '../permissions/contributor_permissions.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// ROLE MANAGEMENT SHEET
// Full-screen modal for changing a band member's role.
// Admin only. Includes:
//   - Member name heading
//   - Current role display
//   - Role toggle buttons (Admin / Band Member / Contributor)
//   - Sub-permission toggles for contributor
//   - Remove from band button (admin only)
//   - Save / Cancel buttons
// ============================================================================

class RoleManagementSheet extends ConsumerStatefulWidget {
  final MemberVM member;
  final int adminCount;

  const RoleManagementSheet({
    super.key,
    required this.member,
    required this.adminCount,
  });

  @override
  ConsumerState<RoleManagementSheet> createState() =>
      _RoleManagementSheetState();
}

class _RoleManagementSheetState extends ConsumerState<RoleManagementSheet> {
  late String _selectedRole;
  late String _initialRole;
  late ContributorPermissions _subPermissions;
  late ContributorPermissions _initialSubPermissions;
  bool _isSaving = false;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    // Map 'owner' to 'admin' for backward safety
    final currentRole = widget.member.bandRole;
    _selectedRole = (currentRole == 'owner') ? 'admin' : currentRole;
    _initialRole = _selectedRole;
    _subPermissions = ContributorPermissions.allEnabled;
    _initialSubPermissions = ContributorPermissions.allEnabled;

    // Load actual sub-permissions for existing contributors
    if (widget.member.isContributor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadExistingPermissions();
      });
    }
  }

  /// Loads the member's saved contributor permissions from the database.
  /// Sets both current and initial state so dirty-detection works correctly.
  Future<void> _loadExistingPermissions() async {
    final repo = ref.read(membersRepositoryProvider);
    try {
      final existing = await repo.fetchContributorPermissions(
        bandMemberId: widget.member.memberId,
      );
      if (mounted && existing != null) {
        setState(() {
          _subPermissions = existing;
          _initialSubPermissions = existing;
        });
      }
    } catch (e) {
      debugPrint('[RoleManagement] Failed to load contributor permissions: $e');
      // Permissions fail silently — sheet still opens with defaults
    }
  }

  bool get _isSelfAndLastAdmin {
    // Check if viewing self AND they're the last admin
    final currentUserId = supabase.auth.currentUser?.id;
    return widget.member.userId == currentUserId &&
        widget.member.isAdmin &&
        widget.adminCount <= 1;
  }

  bool get _isLastAdmin {
    return widget.member.isAdmin && widget.adminCount <= 1;
  }

  bool get _hasChanges {
    // Check if role changed
    if (_selectedRole != _initialRole) return true;
    // If role is contributor, check sub-permission changes
    if (_selectedRole == 'contributor') {
      return !_permissionsEqual(_subPermissions, _initialSubPermissions);
    }
    return false;
  }

  /// Stable field-by-field comparison of contributor permissions.
  bool _permissionsEqual(
    ContributorPermissions a,
    ContributorPermissions b,
  ) {
    return a.canCreateGigs == b.canCreateGigs &&
        a.canCreatePotentialGigsOnly == b.canCreatePotentialGigsOnly &&
        a.canViewSetlists == b.canViewSetlists &&
        a.canViewCalendar == b.canViewCalendar &&
        a.canViewMembers == b.canViewMembers &&
        a.canViewFinancials == b.canViewFinancials &&
        a.canViewGear == b.canViewGear;
  }

  Future<void> _saveRole() async {
    if (!_hasChanges || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      final bandId = ref.read(activeBandProvider).activeBandId;
      if (bandId == null) return;

      await ref.read(membersProvider.notifier).updateRole(
            memberId: widget.member.memberId,
            bandId: bandId,
            newRole: _selectedRole,
            subPermissions:
                _selectedRole == 'contributor' ? _subPermissions : null,
          );

      if (mounted) {
        showSuccessSnackBar(context, message: 'Role updated');
        Navigator.of(context).pop();
      }
    } on PostgrestException catch (e) {
      debugPrint(
          '[RoleManagement] PostgrestException: ${e.message} (code: ${e.code})');
      if (mounted) {
        String message = 'Failed to update role';
        if (e.message.contains('at least one admin must remain')) {
          message = 'Cannot demote: at least one admin must remain';
        } else if (e.message.contains('Permission denied')) {
          message = 'Only admins can change roles';
        } else if (e.message.contains('Member not found')) {
          message = 'Member not found in this band';
        } else if (e.message.contains('Could not find the function')) {
          message = 'Server update needed — please try again in a moment';
        }
        showErrorSnackBar(context, message: message);
      }
    } catch (e) {
      debugPrint('[RoleManagement] Unexpected error: $e (${e.runtimeType})');
      if (mounted) {
        showErrorSnackBar(context, message: 'Failed to update role: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeMember() async {
    if (_isRemoving) return;

    // Show confirmation dialog
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: 'Remove ${widget.member.name}?',
      message:
          'Are you sure you want to remove this member from the band? This cannot be undone.',
      actions: [
        DialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DialogAction(
          label: 'Remove',
          onPressed: () => Navigator.of(context).pop(true),
          isDestructive: true,
        ),
      ],
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRemoving = true);

    try {
      final bandId = ref.read(activeBandProvider).activeBandId;
      if (bandId == null) return;

      final success = await ref
          .read(membersProvider.notifier)
          .removeMember(widget.member.memberId, bandId);

      if (mounted) {
        if (success) {
          showSuccessSnackBar(context, message: 'Member removed');
          Navigator.of(context).pop();
        } else {
          showErrorSnackBar(context, message: 'Failed to remove member');
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, message: 'Failed to remove member');
      }
    } finally {
      if (mounted) setState(() => _isRemoving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      backgroundColor: context.colors.background,
      appBar: AppAppBar(
        backgroundColor: Colors.transparent,
        leading: AppIconButton(
          icon: AppIcons.close,
          color: context.colors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Manage Role',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: AppFontSizes.title,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── Member name heading ───
                    Text(
                      widget.member.name,
                      style: TextStyle(
                        fontSize: AppFontSizes.pageTitle,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _roleDisplayName(widget.member.bandRole),
                      style: TextStyle(
                        fontSize: AppFontSizes.subhead,
                        color: context.colors.textSecondary,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ─── Change role section ───
                    Text(
                      'Change role',
                      style: TextStyle(
                        fontSize: AppFontSizes.body,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Role toggle buttons
                    _buildRoleButton(
                      role: 'admin',
                      label: 'Admin',
                      description: 'Full access to everything',
                      enabled: !(_isLastAdmin && _selectedRole == 'admin'),
                    ),
                    const SizedBox(height: 8),
                    _buildRoleButton(
                      role: 'member',
                      label: 'Band Member',
                      description: 'Can manage gigs and setlists',
                      enabled: !_isSelfAndLastAdmin,
                    ),
                    const SizedBox(height: 8),
                    _buildRoleButton(
                      role: 'contributor',
                      label: 'Contributor',
                      description: 'Limited access with custom permissions',
                      enabled: !_isSelfAndLastAdmin,
                    ),

                    // ─── Contributor sub-permissions ───
                    if (_selectedRole == 'contributor') ...[
                      const SizedBox(height: 24),
                      Text(
                        'Contributor permissions',
                        style: TextStyle(
                          fontSize: AppFontSizes.body,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildPermissionToggle(
                        label: 'Can create gigs',
                        value: _subPermissions.canCreateGigs,
                        onChanged: (v) => setState(() {
                          _subPermissions =
                              _subPermissions.copyWith(canCreateGigs: v);
                        }),
                      ),
                      _buildPermissionToggle(
                        label: 'Potential gigs only',
                        value: _subPermissions.canCreatePotentialGigsOnly,
                        onChanged: (v) => setState(() {
                          _subPermissions = _subPermissions.copyWith(
                              canCreatePotentialGigsOnly: v);
                        }),
                      ),
                      _buildPermissionToggle(
                        label: 'Can view setlists',
                        value: _subPermissions.canViewSetlists,
                        onChanged: (v) => setState(() {
                          _subPermissions =
                              _subPermissions.copyWith(canViewSetlists: v);
                        }),
                      ),
                      _buildPermissionToggle(
                        label: 'Can view calendar',
                        value: _subPermissions.canViewCalendar,
                        onChanged: (v) => setState(() {
                          _subPermissions =
                              _subPermissions.copyWith(canViewCalendar: v);
                        }),
                      ),
                      _buildPermissionToggle(
                        label: 'Can view members',
                        value: _subPermissions.canViewMembers,
                        onChanged: (v) => setState(() {
                          _subPermissions =
                              _subPermissions.copyWith(canViewMembers: v);
                        }),
                      ),
                      _buildPermissionToggle(
                        label: 'Can view financials',
                        value: _subPermissions.canViewFinancials,
                        onChanged: (v) => setState(() {
                          _subPermissions =
                              _subPermissions.copyWith(canViewFinancials: v);
                        }),
                      ),
                      _buildPermissionToggle(
                        label: 'Can view gear',
                        value: _subPermissions.canViewGear,
                        onChanged: (v) => setState(() {
                          _subPermissions =
                              _subPermissions.copyWith(canViewGear: v);
                        }),
                      ),
                    ],

                    // ─── Last admin warning ───
                    if (_isSelfAndLastAdmin) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.colors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                context.colors.warning.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(AppIcons.warning,
                                color: context.colors.warning, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You are the only admin. You cannot change your own role.',
                                style: TextStyle(
                                  fontSize: AppFontSizes.caption,
                                  color: context.colors.warning,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ─── Remove from band button ───
                    if (!_isLastAdmin) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: AppButton(
                          label: 'Remove from band',
                          icon: AppIcons.userRemove,
                          variant: AppButtonVariant.destructive,
                          onPressed: _isRemoving ? null : _removeMember,
                          isLoading: _isRemoving,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _buildFixedBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedBottomActions() {
    return SheetFooter(
      primaryLabel: 'Save',
      onPrimary: (_hasChanges && !_isSaving) ? _saveRole : null,
      primaryIsLoading: _isSaving,
      onCancel: () => Navigator.of(context).pop(),
    );
  }

  Widget _buildRoleButton({
    required String role,
    required String label,
    required String description,
    bool enabled = true,
  }) {
    final isSelected = _selectedRole == role;

    return GestureDetector(
      onTap: enabled ? () => setState(() => _selectedRole = role) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : enabled
                    ? context.colors.border
                    : context.colors.border.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : enabled
                          ? context.colors.textSecondary
                          : context.colors.textDisabled,
                  width: 2,
                ),
                color: isSelected ? AppColors.primary : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(AppIcons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            // Label + description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppFontSizes.subhead,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? context.colors.textPrimary
                          : context.colors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: AppFontSizes.caption,
                      color: enabled
                          ? context.colors.textSecondary
                          : context.colors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionToggle({
    required String label,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AppSwitch(
        value: value,
        onChanged: onChanged,
        leadingLabel: true,
        label: Text(
          label,
          style: TextStyle(
            fontSize: AppFontSizes.subhead,
            color: onChanged != null
                ? context.colors.textPrimary
                : context.colors.textDisabled,
          ),
        ),
      ),
    );
  }

  String _roleDisplayName(String role) {
    switch (role) {
      case 'admin':
      case 'owner':
        return 'Admin';
      case 'member':
        return 'Band Member';
      case 'contributor':
        return 'Contributor';
      default:
        return 'Band Member';
    }
  }
}
