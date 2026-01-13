// ============================================================================
// NOTIFICATION PREFERENCES MODEL
// User preferences for notification types and delivery methods
// ============================================================================

class NotificationPreferences {
  final String id;
  final String userId;

  // Category toggles
  final bool gigUpdates;
  final bool rehearsalUpdates;
  final bool setlistUpdates;
  final bool availabilityRequests;
  final bool memberUpdates;

  // Delivery method toggles
  final bool pushEnabled;
  final bool inAppEnabled;

  // Quiet hours
  final String? quietHoursStart; // '22:00'
  final String? quietHoursEnd; // '08:00'
  final String timezone;

  final DateTime createdAt;
  final DateTime updatedAt;

  const NotificationPreferences({
    required this.id,
    required this.userId,
    this.gigUpdates = true,
    this.rehearsalUpdates = true,
    this.setlistUpdates = true,
    this.availabilityRequests = true,
    this.memberUpdates = true,
    this.pushEnabled = true,
    this.inAppEnabled = true,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.timezone = 'America/New_York',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Default preferences for a new user
  factory NotificationPreferences.defaults(String userId) {
    final now = DateTime.now();
    return NotificationPreferences(
      id: '',
      userId: userId,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      gigUpdates: json['gig_updates'] as bool? ?? true,
      rehearsalUpdates: json['rehearsal_updates'] as bool? ?? true,
      setlistUpdates: json['setlist_updates'] as bool? ?? true,
      availabilityRequests: json['availability_requests'] as bool? ?? true,
      memberUpdates: json['member_updates'] as bool? ?? true,
      pushEnabled: json['push_enabled'] as bool? ?? true,
      inAppEnabled: json['in_app_enabled'] as bool? ?? true,
      quietHoursStart: json['quiet_hours_start'] as String?,
      quietHoursEnd: json['quiet_hours_end'] as String?,
      timezone: json['timezone'] as String? ?? 'America/New_York',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'gig_updates': gigUpdates,
      'rehearsal_updates': rehearsalUpdates,
      'setlist_updates': setlistUpdates,
      'availability_requests': availabilityRequests,
      'member_updates': memberUpdates,
      'push_enabled': pushEnabled,
      'in_app_enabled': inAppEnabled,
      'quiet_hours_start': quietHoursStart,
      'quiet_hours_end': quietHoursEnd,
      'timezone': timezone,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  NotificationPreferences copyWith({
    String? id,
    String? userId,
    bool? gigUpdates,
    bool? rehearsalUpdates,
    bool? setlistUpdates,
    bool? availabilityRequests,
    bool? memberUpdates,
    bool? pushEnabled,
    bool? inAppEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
    String? timezone,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NotificationPreferences(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      gigUpdates: gigUpdates ?? this.gigUpdates,
      rehearsalUpdates: rehearsalUpdates ?? this.rehearsalUpdates,
      setlistUpdates: setlistUpdates ?? this.setlistUpdates,
      availabilityRequests: availabilityRequests ?? this.availabilityRequests,
      memberUpdates: memberUpdates ?? this.memberUpdates,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      inAppEnabled: inAppEnabled ?? this.inAppEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      timezone: timezone ?? this.timezone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
