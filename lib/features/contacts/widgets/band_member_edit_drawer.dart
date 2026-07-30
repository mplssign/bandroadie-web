import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/services/supabase_client.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../bands/active_band_controller.dart';
import '../../members/member_vm.dart';
import '../../members/members_controller.dart';
import '../../members/members_repository.dart';
import '../../members/permissions/contributor_permissions.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// BAND MEMBER EDIT DRAWER
// Bottom-drawer port of RoleManagementSheet's role-management functionality
// (Amendment 2, Decision 1 revised). Full, faithful port of
// _RoleManagementSheetState's state and behavior — role selection, sub-
// permission toggles, last-admin guard, save/error handling, remove member —
// wrapped in the same drawer chrome as BandMemberDetailDrawer/ViewGigDrawer.
// role_management_sheet.dart itself is not modified or called by this file.
// ============================================================================

class BandMemberEditDrawer extends ConsumerStatefulWidget {
  final MemberVM member;
  final int adminCount;
  final int activeMemberCount;

  const BandMemberEditDrawer({
    super.key,
    required this.member,
    required this.adminCount,
    required this.activeMemberCount,
  });

  static Future<void> show(
    BuildContext context, {
    required MemberVM member,
    required int adminCount,
    required int activeMemberCount,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BandMemberEditDrawer(
        member: member,
        adminCount: adminCount,
        activeMemberCount: activeMemberCount,
      ),
    );
  }

  @override
  ConsumerState<BandMemberEditDrawer> createState() =>
      _BandMemberEditDrawerState();
}

class _BandMemberEditDrawerState extends ConsumerState<BandMemberEditDrawer> {
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

  bool get _isSoleActiveMember {
    final currentUserId = supabase.auth.currentUser?.id;
    return widget.member.userId == currentUserId &&
        widget.activeMemberCount <= 1;
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
        a.canViewFinancials == b.canViewFinancials;
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove ${widget.member.name}?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to remove this member from the band? This cannot be undone.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
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
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header: 'Edit' label + member name + current role
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.pagePadding,
              Spacing.space16,
              Spacing.pagePadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit',
                  style: TextStyle(
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
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
              ],
            ),
          ),
          const SizedBox(height: Spacing.space16),
          const Divider(height: 1),

          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                          color: context.colors.warning.withValues(alpha: 0.3),
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

                  // ─── Remove from band button / sole-member notice ───
                  if (_isSoleActiveMember) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.colors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: context.colors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(AppIcons.warning,
                              color: context.colors.warning, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Since you are the only member in this band, you cannot leave the band, instead you must delete the band (Tap band avatar top right → Edit band → Delete)',
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
                  ] else if (!_isLastAdmin) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: TextButton.icon(
                        onPressed: _isRemoving ? null : _removeMember,
                        icon: _isRemoving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      AppColors.error),
                                ),
                              )
                            : const Icon(AppIcons.userRemove,
                                color: AppColors.error, size: 20),
                        label: Text(
                          _isRemoving ? 'Removing...' : 'Remove from band',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: AppFontSizes.subhead,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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
    );
  }

  Widget _buildFixedBottomActions() {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(
            color: context.colors.border.withValues(alpha: 0.5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: Spacing.space16,
        right: Spacing.space16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + Spacing.space16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (_hasChanges && !_isSaving) ? _saveRole : null,
              style: FilledButton.styleFrom(
                backgroundColor: (_hasChanges && !_isSaving)
                    ? AppColors.primary
                    : context.colors.border.withValues(alpha: 0.3),
                disabledBackgroundColor:
                    context.colors.border.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Save',
                      style: AppTextStyles.body.copyWith(
                        color: (_hasChanges && !_isSaving)
                            ? Colors.white
                            : context.colors.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: AppFontSizes.body,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
            ),
            child: Text(
              'Cancel',
              style: AppTextStyles.body.copyWith(
                color: context.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
      child: SwitchListTile(
        title: Text(
          label,
          style: TextStyle(
            fontSize: AppFontSizes.subhead,
            color: onChanged != null
                ? context.colors.textPrimary
                : context.colors.textDisabled,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeTrackColor: AppColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        dense: true,
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
