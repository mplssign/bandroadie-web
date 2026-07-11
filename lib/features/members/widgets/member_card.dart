import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/utils/phone_formatter.dart';
import '../member_vm.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';

// ============================================================================
// MEMBER CARD
// Large polished card for displaying a band member.
// Figma-inspired dark theme with rose accent, gradient glow border.
// ============================================================================

/// Design tokens specific to member cards
class _MemberCardTokens {
  _MemberCardTokens._();

  // Colors
  static const Color borderRose = AppColors.primary; // rose-500
  static const Color iconRose = AppColors.primary;

  // Sizing
  static const double cardRadius = 24.0;
  static const double borderWidth = 2.0;
  static const double cardPadding = 24.0;
  static const double pillRadius = 16.0;
  static const double pillPaddingH = 12.0;
  static const double pillPaddingV = 6.0;
  static const double contactRowSpacing = 14.0;
  static const double iconSize = 20.0;
  static const double iconTextGap = 12.0;

  // Typography
  static const TextStyle nameStyle = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle pillStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: borderRose,
    height: 1.2,
  );

  static const TextStyle contactLabelStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle contactValueStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );
}

class MemberCard extends StatefulWidget {
  final MemberVM member;
  final VoidCallback? onTap;
  final VoidCallback? onManageRole;
  final bool showAdminActions;

  const MemberCard({
    super.key,
    required this.member,
    this.onTap,
    this.onManageRole,
    this.showAdminActions = false,
  });

  @override
  State<MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<MemberCard> {
  String get _normalizedBandRole => widget.member.bandRole.trim().toLowerCase();

  @override
  Widget build(BuildContext context) {
    // No card-level tap handler - contact rows handle their own taps (phone, email)
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(_MemberCardTokens.cardRadius),
        border: Border.all(
          color: _MemberCardTokens.borderRose,
          width: _MemberCardTokens.borderWidth,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          _MemberCardTokens.cardRadius - _MemberCardTokens.borderWidth,
        ),
        child: Stack(
          children: [
            // Subtle gradient wash overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _MemberCardTokens.borderRose.withValues(alpha: 0.05),
                      Colors.transparent,
                      _MemberCardTokens.borderRose.withValues(alpha: 0.03),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(_MemberCardTokens.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: Name + kebab menu
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_normalizedBandRole != 'member')
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 10),
                          child: _buildRoleIcon(),
                        ),
                      Expanded(
                        child: Text(
                          widget.member.name,
                          style: _MemberCardTokens.nameStyle.copyWith(
                            color: context.colors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.showAdminActions) _buildAdminButton(),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Role pills
                  _buildRolePills(),

                  const SizedBox(height: 20),

                  // Contact info rows
                  _buildContactRows(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRolePills() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // NOTE: "Invitation pending" is only shown in PendingInviteCard
        // for band_invitations rows. MemberCard only shows role pills.
        // Role pills
        ...widget.member.displayRoles.map((role) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _MemberCardTokens.pillPaddingH,
              vertical: _MemberCardTokens.pillPaddingV,
            ),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(_MemberCardTokens.pillRadius),
              border: Border.all(
                color: _MemberCardTokens.borderRose,
                width: 1.5,
              ),
            ),
            child: Text(role, style: _MemberCardTokens.pillStyle),
          );
        }),
      ],
    );
  }

  Widget _buildContactRows() {
    final member = widget.member;

    // Build list of available contact info
    // Don't show "Invitation pending" - that's handled in the separate invites section
    // Active members (status == 'active') NEVER show invitation pending
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Phone - only show if present, tappable to call
        if (member.phone != null && member.phone!.isNotEmpty)
          _buildContactRow(
            icon: AppIcons.phone,
            value: formatPhoneNumber(member.phone!),
            onTap: () => _launchPhone(member.phone!),
          ),

        // Email - only show if present, tappable to email
        if (member.email.isNotEmpty)
          _buildContactRow(
            icon: AppIcons.email,
            value: member.email,
            onTap: () => _launchEmail(member.email),
          ),

        // Address - only show if present (combine address, city, zip)
        if (_hasAddress(member))
          _buildContactRow(
            icon: AppIcons.location,
            value: _formatAddress(member),
          ),

        // Birthday - only show if present (format as Month Day)
        if (member.birthday != null)
          _buildContactRow(
            icon: Icons.cake_outlined,
            value: _formatBirthday(member.birthday!),
          ),
      ],
    );
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
    // Strip formatting to get raw digits for tel: URI
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

  Widget _buildContactRow({
    required IconData icon,
    String? label,
    required String value,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: _MemberCardTokens.contactRowSpacing,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: _MemberCardTokens.iconSize,
            color: _MemberCardTokens.iconRose,
          ),
          const SizedBox(width: _MemberCardTokens.iconTextGap),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: label != null
                  ? RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$label ',
                            style: _MemberCardTokens.contactLabelStyle.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                          TextSpan(
                            text: value,
                            style: _MemberCardTokens.contactValueStyle.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Text(
                      value,
                      style: _MemberCardTokens.contactValueStyle.copyWith(
                        color: context.colors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Role badge icon shown before the role pills.
  Widget _buildRoleIcon() {
    final IconData icon;
    switch (_normalizedBandRole) {
      case 'owner':
      case 'admin':
        icon = AppIcons.crown;
        break;
      case 'contributor':
        icon = Icons.visibility_outlined;
        break;
      default:
        return const SizedBox.shrink();
    }
    return Icon(
      icon,
      size: 18,
      color: _MemberCardTokens.iconRose,
    );
  }

  /// Direct admin action button — single tap opens RoleManagementSheet
  Widget _buildAdminButton() {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        color: context.colors.textSecondary,
        size: 20,
      ),
      onPressed: () => widget.onManageRole?.call(),
      splashRadius: 20,
      constraints: const BoxConstraints(
        minWidth: 40,
        minHeight: 40,
      ),
    );
  }
}
