import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../pending_invite_vm.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// PENDING INVITE CARD
// Simpler card for displaying a pending band invitation.
// Shows email + "Invitation pending" status badge.
// ============================================================================

class PendingInviteCard extends StatefulWidget {
  final PendingInviteVM invite;
  final VoidCallback? onResend;
  final VoidCallback? onCancel;
  final bool showActions;

  const PendingInviteCard({
    super.key,
    required this.invite,
    this.onResend,
    this.onCancel,
    this.showActions = false,
  });

  @override
  State<PendingInviteCard> createState() => _PendingInviteCardState();
}

class _PendingInviteCardState extends State<PendingInviteCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _scaleController.forward();
    HapticFeedback.selectionClick();
  }

  void _onTapUp(TapUpDetails details) {
    _scaleController.reverse();
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.colors.border, // gray-700
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar placeholder
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: context.colors.surface, // gray-800
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    AppIcons.email,
                    color: context.colors.textSecondary, // gray-400
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Email or display name
                      Text(
                        widget.invite.email.isNotEmpty
                            ? widget.invite.email
                            : 'Unknown',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF422006), // amber-950
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          widget.invite.isExpired
                              ? 'Expired'
                              : 'Invitation pending',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: widget.invite.isExpired
                                ? AppColors.error // red-500
                                : const Color(0xFFFBBF24), // amber-400
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Actions menu (if admin)
                if (widget.showActions)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: context.colors.textSecondary,
                      size: 20,
                    ),
                    color: context.colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) {
                      if (value == 'resend') {
                        widget.onResend?.call();
                      } else if (value == 'cancel') {
                        widget.onCancel?.call();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'resend',
                        child: Row(
                          children: [
                            Icon(AppIcons.refresh, color: AppColors.primary),
                            SizedBox(width: 12),
                            Text('Resend invite'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Row(
                          children: [
                            Icon(AppIcons.close, color: AppColors.error),
                            SizedBox(width: 12),
                            Text(
                              'Cancel invite',
                              style: TextStyle(color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
