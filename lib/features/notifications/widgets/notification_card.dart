import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/app_notification.dart';
import '../models/notification_type.dart';
import '../notification_controller.dart';

// ============================================================================
// NOTIFICATION CARD
// Individual notification item in the activity feed
// ============================================================================

class NotificationCard extends ConsumerWidget {
  final AppNotification notification;
  final VoidCallback? onTap;

  const NotificationCard({super.key, required this.notification, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        // Mark as read on tap
        if (!notification.isRead) {
          ref
              .read(notificationListProvider.notifier)
              .markAsRead(notification.id);
        }
        onTap?.call();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: Spacing.space8),
        padding: const EdgeInsets.all(Spacing.space16),
        decoration: BoxDecoration(
          color: notification.isRead
              ? AppColors.cardBg
              : AppColors.cardBgElevated,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          border: notification.isRead
              ? null
              : Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  width: 1,
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getIconBackgroundColor().withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: Icon(
                _getIcon(),
                size: 20,
                color: _getIconBackgroundColor(),
              ),
            ),
            const SizedBox(width: Spacing.space12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Spacing.space4),
                  Text(
                    notification.body,
                    style: AppTextStyles.footnote.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Spacing.space8),
                  Text(
                    _formatTimestamp(notification.createdAt),
                    style: AppTextStyles.footnote.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Unread indicator
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (notification.type) {
      case NotificationType.gigCreated:
      case NotificationType.gigUpdated:
      case NotificationType.gigCancelled:
      case NotificationType.gigConfirmed:
      case NotificationType.potentialGigCreated:
        return Icons.music_note_rounded;
      case NotificationType.rehearsalCreated:
      case NotificationType.rehearsalUpdated:
      case NotificationType.rehearsalCancelled:
        return Icons.schedule_rounded;
      case NotificationType.blockoutCreated:
        return Icons.event_busy_rounded;
      case NotificationType.setlistUpdated:
        return Icons.queue_music_rounded;
      case NotificationType.availabilityRequest:
      case NotificationType.availabilityResponse:
        return Icons.how_to_reg_rounded;
      case NotificationType.memberJoined:
      case NotificationType.memberLeft:
      case NotificationType.roleChanged:
        return Icons.group_rounded;
      case NotificationType.bandInvitation:
        return Icons.mail_rounded;
    }
  }

  Color _getIconBackgroundColor() {
    switch (notification.type.category) {
      case NotificationCategory.gigs:
        return AppColors.accent;
      case NotificationCategory.rehearsals:
        return AppColors.blueAccent;
      case NotificationCategory.blockouts:
        return AppColors.warning;
      case NotificationCategory.setlists:
        return AppColors.success;
      case NotificationCategory.availability:
        return AppColors.warning;
      case NotificationCategory.members:
        return AppColors.textSecondary;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(timestamp);
    }
  }
}
