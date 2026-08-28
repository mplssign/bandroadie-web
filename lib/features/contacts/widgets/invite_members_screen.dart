import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/email_domain_shortcut_bar.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../../components/ui/app_scaffold.dart';
import '../../../components/ui/app_app_bar.dart';
import '../../../components/ui/app_icon_button.dart';
import '../../../components/ui/app_text_form_field.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/app_dialog.dart';

// ============================================================================
// INVITE MEMBERS SCREEN
// Standalone screen for inviting members to a band.
// Extracted from BandFormScreen edit-mode invite section.
// ============================================================================

class InviteMembersScreen extends ConsumerStatefulWidget {
  final Band band;

  const InviteMembersScreen({super.key, required this.band});

  @override
  ConsumerState<InviteMembersScreen> createState() =>
      _InviteMembersScreenState();
}

class _InviteMembersScreenState extends ConsumerState<InviteMembersScreen> {
  final _inviteEmailController = TextEditingController();
  List<Map<String, dynamic>> _pendingInvites = [];
  bool _isSendingInvite = false;
  String _selectedRole = 'member';

  @override
  void initState() {
    super.initState();
    _loadPendingInvites();
  }

  @override
  void dispose() {
    _inviteEmailController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    showErrorSnackBar(context, message: message);
  }

  Future<void> _loadPendingInvites() async {
    try {
      final bandId = widget.band.id;

      // Load pending invitations (both 'pending' and 'sent' statuses)
      final invitesResponse = await supabase
          .from('band_invitations')
          .select('id, email, status, created_at')
          .eq('band_id', bandId)
          .inFilter('status', ['pending', 'sent']).order('created_at',
              ascending: false);

      final invitesList = List<Map<String, dynamic>>.from(invitesResponse);

      // Dedupe invites by email (keep newest created_at)
      final Map<String, Map<String, dynamic>> dedupedByEmail = {};
      for (final invite in invitesList) {
        final email = (invite['email'] as String?)?.toLowerCase().trim() ?? '';
        if (!dedupedByEmail.containsKey(email)) {
          dedupedByEmail[email] = invite;
        }
        // Already sorted by created_at desc, so first one is newest
      }
      final dedupedInvites = dedupedByEmail.values.toList();

      if (mounted) {
        setState(() {
          _pendingInvites = dedupedInvites;
        });
      }
    } on PostgrestException catch (e) {
      debugPrint(
        '[LoadPendingInvites] PostgrestException: ${e.code} - ${e.message}',
      );
      if (mounted) {
        _showErrorSnackBar('Failed to load invitations');
      }
    } catch (e) {
      debugPrint('[LoadPendingInvites] Error: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to load invitations');
      }
    }
  }

  Future<void> _sendInvite() async {
    final email = _inviteEmailController.text.trim().toLowerCase();
    if (email.isEmpty) return;

    final emailRegex = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
    );
    if (!emailRegex.hasMatch(email)) {
      _showErrorSnackBar('Please enter a valid email address');
      return;
    }

    // Check if inviting yourself
    final user = supabase.auth.currentUser;
    if (user?.email?.toLowerCase() == email) {
      _showErrorSnackBar('You cannot invite yourself');
      return;
    }

    final bandId = widget.band.id;

    // Check if email belongs to an existing active band member
    try {
      final userLookup = await supabase
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (userLookup != null) {
        final userId = userLookup['id'] as String;
        final memberLookup = await supabase
            .from('band_members')
            .select('id')
            .eq('band_id', bandId)
            .eq('user_id', userId)
            .eq('status', 'active')
            .maybeSingle();

        if (memberLookup != null) {
          _showErrorSnackBar('This person is already a band member');
          return;
        }
      }
    } catch (e) {
      debugPrint('[Invite] Failed to check active membership: $e');
    }

    // Check for existing pending invite in the database (not just local state)
    try {
      final existingInvites = await supabase
          .from('band_invitations')
          .select('id')
          .eq('band_id', bandId)
          .eq('email', email)
          .inFilter('status', ['pending', 'sent']);

      if (existingInvites.isNotEmpty) {
        _showErrorSnackBar('User already invited');
        return;
      }
    } catch (e) {
      debugPrint('[Invite] Failed to check existing invites: $e');
    }

    if (mounted) setState(() => _isSendingInvite = true);

    try {
      final userId = supabase.auth.currentUser?.id;

      // Insert invitation and get the returned row
      final insertResponse = await supabase
          .from('band_invitations')
          .insert({
            'band_id': bandId,
            'email': email,
            'invited_by': userId,
            'status': 'pending',
            'intended_role': _selectedRole,
          })
          .select('id, token')
          .single();

      final inviteId = insertResponse['id'] as String;
      debugPrint('[Invite] inserted invitation id=$inviteId email=$email');

      _inviteEmailController.clear();
      if (mounted) setState(() => _selectedRole = 'member');

      // Call edge function to send email via Resend
      debugPrint('[Invite] invoking send-band-invite id=$inviteId');

      try {
        final functionResponse = await supabase.functions.invoke(
          'send-band-invite',
          body: {'bandInvitationId': inviteId},
        );

        if (functionResponse.status == 200) {
          debugPrint('[Invite] send success id=$inviteId');
          if (mounted) {
            showSuccessSnackBar(context, message: 'Invite sent to $email');
          }
        } else {
          final errorData = functionResponse.data;
          debugPrint('[Invite] send failed id=$inviteId error=$errorData');
          if (mounted) {
            showAppSnackBar(
              context,
              message: 'Invite saved but email failed to send',
              backgroundColor: context.colors.warning,
            );
          }
        }
      } catch (functionError) {
        debugPrint('[Invite] send failed id=$inviteId error=$functionError');
        if (mounted) {
          showAppSnackBar(
            context,
            message: 'Invite saved but email failed to send',
            backgroundColor: context.colors.warning,
          );
        }
      }

      await _loadPendingInvites();
    } on PostgrestException catch (e) {
      debugPrint('[SendInvite] PostgrestException: ${e.code} - ${e.message}');
      if (e.code == '23505') {
        _showErrorSnackBar('User already invited');
      } else if (e.code == '42501') {
        // RLS policy violation - user is not a band admin
        _showErrorSnackBar('Only band admins can invite members');
      } else {
        _showErrorSnackBar('Failed to send invitation');
      }
    } catch (e) {
      debugPrint('[SendInvite] Error: $e');
      _showErrorSnackBar('Failed to send invitation');
    } finally {
      if (mounted) {
        setState(() => _isSendingInvite = false);
      }
    }
  }

  Future<void> _cancelInvite(Map<String, dynamic> invite) async {
    final email = invite['email'] ?? '';

    // Show confirmation dialog
    final confirmed = await showAppDialog<bool>(
      context: context,
      title: 'Cancel Invite?',
      message: 'Cancel invite for $email?',
      actions: [
        DialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DialogAction(
          label: 'Cancel Invite',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirmed != true) return;

    try {
      final bandId = widget.band.id;

      // Hard delete the invitation row (cancellations are usually typos)
      await supabase
          .from('band_invitations')
          .delete()
          .eq('id', invite['id'])
          .eq('band_id', bandId);

      debugPrint('[CancelInvite] deleted invite ${invite['id']} for $email');

      await _loadPendingInvites();

      if (mounted) {
        showSuccessSnackBar(context, message: 'Invitation to $email removed');
      }
    } on PostgrestException catch (e) {
      debugPrint('[CancelInvite] PostgrestException: ${e.code} - ${e.message}');
      if (mounted) {
        _showErrorSnackBar('Failed to cancel invite');
      }
    } catch (e) {
      debugPrint('[CancelInvite] Error: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to cancel invite');
      }
    }
  }

  Widget _buildInviteEmailInput() {
    return Row(
      children: [
        Expanded(
          child: AppTextFormField(
            controller: _inviteEmailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            hintText: 'name@example.com',
            onSubmitted: (_) => _sendInvite(),
          ),
        ),
        const SizedBox(width: Spacing.space12),
        SizedBox(
          width: 80,
          child: AppButton(
            label: 'Invite',
            variant: AppButtonVariant.primary,
            onPressed: _isSendingInvite ? null : _sendInvite,
            isLoading: _isSendingInvite,
          ),
        ),
      ],
    );
  }

  Widget _buildPendingInvitesList() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _pendingInvites.map((invite) {
        return _InvitePill(
          email: invite['email'] ?? '',
          onCancel: () => _cancelInvite(invite),
        );
      }).toList(),
    );
  }

  Widget _buildRoleSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select role',
          style: TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _buildRoleButton(
          role: 'admin',
          label: 'Admin',
          description: 'Full access to everything',
        ),
        const SizedBox(height: 8),
        _buildRoleButton(
          role: 'member',
          label: 'Band Member',
          description: 'Can manage gigs and setlists',
        ),
        const SizedBox(height: 8),
        _buildRoleButton(
          role: 'contributor',
          label: 'Contributor',
          description: 'Limited access with custom permissions',
        ),
      ],
    );
  }

  Widget _buildRoleButton({
    required String role,
    required String label,
    required String description,
  }) {
    final isSelected = _selectedRole == role;

    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : context.colors.border,
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
                      : context.colors.textSecondary,
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
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: AppFontSizes.caption,
                      color: context.colors.textSecondary,
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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      backgroundColor: context.colors.background,
      appBar: AppAppBar(
        backgroundColor: context.colors.background,
        leading: AppIconButton(
          icon: AppIcons.back,
          color: context.colors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Invite Members',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: AppFontSizes.title,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.band.name,
              style: TextStyle(
                fontSize: AppFontSizes.title2,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.space8),
            Text(
              'Send an invitation to join your band',
              style: TextStyle(
                fontSize: AppFontSizes.body,
                fontWeight: FontWeight.w400,
                height: 1.4,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: Spacing.space24),
            _buildRoleSelector(),
            const SizedBox(height: Spacing.space24),
            _buildInviteEmailInput(),
            const SizedBox(height: 8),
            EmailDomainShortcutBar(controller: _inviteEmailController),
            if (_pendingInvites.isNotEmpty) ...[
              const SizedBox(height: Spacing.space24),
              Text(
                'Invited',
                style: TextStyle(
                  fontSize: AppFontSizes.title,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: Spacing.space12),
              _buildPendingInvitesList(),
            ],
          ],
        ),
      ),
    );
  }
}

class _InvitePill extends StatelessWidget {
  final String email;
  final VoidCallback onCancel;

  const _InvitePill({required this.email, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space12,
          vertical: Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: context.colors.surfaceOverlay,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: context.colors.warning.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.clock,
              size: 14,
              color: context.colors.warning,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                email.trim(),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppFontSizes.subhead,
                  fontWeight: FontWeight.w400,
                  height: 1.33,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCancel,
              child: Icon(
                AppIcons.close,
                size: 16,
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
