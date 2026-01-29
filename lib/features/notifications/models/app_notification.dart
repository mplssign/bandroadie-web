import 'notification_type.dart';

// ============================================================================
// APP NOTIFICATION MODEL
// Represents a notification in the activity feed
// ============================================================================

class AppNotification {
  final String id;
  final String? bandId;
  final String recipientUserId;
  final NotificationType type;
  final String title;
  final String body;
  final Map<String, dynamic> metadata;
  final DateTime? readAt;
  final DateTime createdAt;
  final String? actorUserId;

  const AppNotification({
    required this.id,
    this.bandId,
    required this.recipientUserId,
    required this.type,
    required this.title,
    required this.body,
    this.metadata = const {},
    this.readAt,
    required this.createdAt,
    this.actorUserId,
  });

  bool get isRead => readAt != null;

  /// Deep link target based on notification type and metadata
  String? get deepLink {
    final gigId = metadata['gig_id'] as String?;
    final rehearsalId = metadata['rehearsal_id'] as String?;
    final setlistId = metadata['setlist_id'] as String?;
    final bandId = this.bandId ?? metadata['band_id'] as String?;

    switch (type) {
      case NotificationType.gigCreated:
      case NotificationType.gigUpdated:
      case NotificationType.gigCancelled:
      case NotificationType.gigConfirmed:
      case NotificationType.potentialGigCreated:
      case NotificationType.availabilityRequest:
      case NotificationType.availabilityResponse:
        return gigId != null ? '/gig/$gigId' : null;
      case NotificationType.rehearsalCreated:
      case NotificationType.rehearsalUpdated:
      case NotificationType.rehearsalCancelled:
        return rehearsalId != null ? '/rehearsal/$rehearsalId' : null;
      case NotificationType.blockoutCreated:
        return '/calendar';
      case NotificationType.setlistUpdated:
        return setlistId != null ? '/setlist/$setlistId' : null;
      case NotificationType.memberJoined:
      case NotificationType.memberLeft:
      case NotificationType.roleChanged:
        return bandId != null ? '/band/$bandId/members' : null;
      case NotificationType.bandInvitation:
        return '/invitations';
    }
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      bandId: json['band_id'] as String?,
      recipientUserId: json['recipient_user_id'] as String,
      type: NotificationType.fromString(json['type'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      actorUserId: json['actor_user_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'band_id': bandId,
      'recipient_user_id': recipientUserId,
      'type': type.value,
      'title': title,
      'body': body,
      'metadata': metadata,
      'read_at': readAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'actor_user_id': actorUserId,
    };
  }

  AppNotification copyWith({
    String? id,
    String? bandId,
    String? recipientUserId,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? metadata,
    DateTime? readAt,
    DateTime? createdAt,
    String? actorUserId,
  }) {
    return AppNotification(
      id: id ?? this.id,
      bandId: bandId ?? this.bandId,
      recipientUserId: recipientUserId ?? this.recipientUserId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      metadata: metadata ?? this.metadata,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
      actorUserId: actorUserId ?? this.actorUserId,
    );
  }
}
