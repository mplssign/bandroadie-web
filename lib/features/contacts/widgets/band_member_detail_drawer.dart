import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/phone_formatter.dart';
import '../../../components/ui/collapsing_sheet_scaffold.dart';
import '../../../components/ui/sheet_footer.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../../members/member_vm.dart';

// ============================================================================
// BAND MEMBER DETAIL DRAWER
// Read-only bottom drawer showing a band member's full details.
// Mirrors ViewGigDrawer's mechanics (slide-up, rounded top corners, drag
// handle, scrollable body of conditional detail rows, fixed Done/Edit
// footer).
// ============================================================================

class BandMemberDetailDrawer extends StatelessWidget {
  final MemberVM member;
  final bool isAdmin;
  final VoidCallback onManageRole;

  const BandMemberDetailDrawer({
    super.key,
    required this.member,
    required this.isAdmin,
    required this.onManageRole,
  });

  static Future<void> show(
    BuildContext context, {
    required MemberVM member,
    required bool isAdmin,
    required VoidCallback onManageRole,
  }) {
    return showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      mainAxisMaxRatio: 0.95,
      useSafeArea: true,
      builder: (_) => BandMemberDetailDrawer(
        member: member,
        isAdmin: isAdmin,
        onManageRole: onManageRole,
      ),
    );
  }

  void _handleEdit(BuildContext context) {
    Navigator.of(context).pop();
    onManageRole();
  }

  String _roleLabel(MemberVM member) {
    if (member.isAdmin) return 'Admin';
    if (member.isContributor) return 'Contributor';
    return 'Band Member';
  }

  bool _hasAddress(MemberVM member) {
    return (member.address != null && member.address!.isNotEmpty) ||
        (member.city != null && member.city!.isNotEmpty) ||
        (member.zip != null && member.zip!.isNotEmpty);
  }

  String _formatAddress(MemberVM member) {
    final parts = <String>[];
    if (member.address != null && member.address!.isNotEmpty) {
      parts.add(member.address!);
    }
    if (member.city != null && member.city!.isNotEmpty) {
      parts.add(member.city!);
    }
    if (member.zip != null && member.zip!.isNotEmpty) {
      parts.add(member.zip!);
    }
    return parts.join(', ');
  }

  String _formatBirthday(DateTime birthday) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[birthday.month - 1]} ${birthday.day}';
  }

  /// Launch phone dialer with the given phone number.
  /// Fails silently if the device cannot handle the action.
  Future<void> _launchPhone(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return;

    final uri = Uri(scheme: 'tel', path: digits);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {
      // Fail silently
    }
  }

  /// Launch email client with the given email address.
  /// Fails silently if the device cannot handle the action.
  Future<void> _launchEmail(String email) async {
    if (email.isEmpty) return;

    final uri = Uri(scheme: 'mailto', path: email);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {
      // Fail silently
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.95,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: CollapsingSheetScaffold(
        dragHandle: Center(
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
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: Spacing.space16),

              // Header block: role-badge icon (crown-only) + name
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pagePadding,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (member.isAdmin)
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: Icon(
                          AppIcons.crown,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        member.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: context.colors.textPrimary,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: Spacing.space16),
              const Divider(height: 1),

              // Detail rows
              if (member.musicalRoles.isNotEmpty)
                _DetailRow(
                  label: 'Band role',
                  value: member.musicalRoles.join(', '),
                ),

              if (member.phone != null && member.phone!.isNotEmpty)
                _DetailRow(
                  label: 'Phone',
                  value: formatPhoneNumber(member.phone!),
                  onTap: () => _launchPhone(member.phone!),
                ),

              if (member.email.isNotEmpty)
                _DetailRow(
                  label: 'Email',
                  value: member.email,
                  onTap: () => _launchEmail(member.email),
                ),

              if (_hasAddress(member))
                _DetailRow(
                  label: 'Address',
                  value: _formatAddress(member),
                ),

              if (member.birthday != null)
                _DetailRow(
                  label: 'Birthday',
                  value: _formatBirthday(member.birthday!),
                ),

              _DetailRow(
                label: 'Access',
                value: _roleLabel(member),
              ),

              const SizedBox(height: Spacing.space24),
            ],
          ),
        ),
        footer: SheetFooter(
          primaryLabel: 'Done',
          onPrimary: () => Navigator.of(context).pop(),
          cancelLabel: 'Edit',
          onCancel: isAdmin ? () => _handleEdit(context) : null,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.pagePadding,
        vertical: Spacing.space12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: Spacing.space8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.start,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        onTap != null ? InkWell(onTap: onTap, child: row) : row,
        Divider(height: 1, color: context.colors.border),
      ],
    );
  }
}
