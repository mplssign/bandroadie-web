// ============================================================================
// NOTIFICATION PREFERENCES MODEL
// User preferences for notification types and delivery methods
// ============================================================================

class NotificationPreferences {
  final String id;
  final String userId;

  // Master toggle
  final bool notificationsEnabled;

  // Category toggles (only visible when notificationsEnabled = true)
  final bool gigsEnabled;
  final bool potentialGigsEnabled;
  final bool rehearsalsEnabled;
  final bool blockoutsEnabled;

  // Legacy fields (kept for backwards compatibility)
  final bool setlistUpdates;
  final bool availabilityRequests;
  final bool memberUpdates;
  final bool pushEnabled;
  final bool inAppEnabled;

  final DateTime createdAt;
  final DateTime updatedAt;

  const NotificationPreferences({
    required this.id,
    required this.userId,
    this.notificationsEnabled = true,
    this.gigsEnabled = true,
    this.potentialGigsEnabled = true,
    this.rehearsalsEnabled = true,
    this.blockoutsEnabled = true,
    this.setlistUpdates = true,
    this.availabilityRequests = true,
    this.memberUpdates = true,
    this.pushEnabled = true,
    this.inAppEnabled = true,
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
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      gigsEnabled: json['gigs_enabled'] as bool? ?? true,
      potentialGigsEnabled: json['potential_gigs_enabled'] as bool? ?? true,
      rehearsalsEnabled: json['rehearsals_enabled'] as bool? ?? true,
      blockoutsEnabled: json['blockouts_enabled'] as bool? ?? true,
      setlistUpdates: json['setlist_updates'] as bool? ?? true,
      availabilityRequests: json['availability_requests'] as bool? ?? true,
      memberUpdates: json['member_updates'] as bool? ?? true,
      pushEnabled: json['push_enabled'] as bool? ?? true,
      inAppEnabled: json['in_app_enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'notifications_enabled': notificationsEnabled,
      'gigs_enabled': gigsEnabled,
      'potential_gigs_enabled': potentialGigsEnabled,
      'rehearsals_enabled': rehearsalsEnabled,
      'blockouts_enabled': blockoutsEnabled,
      'setlist_updates': setlistUpdates,
      'availability_requests': availabilityRequests,
      'member_updates': memberUpdates,
      'push_enabled': pushEnabled,
      'in_app_enabled': inAppEnabled,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  NotificationPreferences copyWith({
    String? id,
    String? userId,
    bool? notificationsEnabled,
    bool? gigsEnabled,
    bool? potentialGigsEnabled,
    bool? rehearsalsEnabled,
    bool? blockoutsEnabled,
    bool? setlistUpdates,
    bool? availabilityRequests,
    bool? memberUpdates,
    bool? pushEnabled,
    bool? inAppEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NotificationPreferences(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      gigsEnabled: gigsEnabled ?? this.gigsEnabled,
      potentialGigsEnabled: potentialGigsEnabled ?? this.potentialGigsEnabled,
      rehearsalsEnabled: rehearsalsEnabled ?? this.rehearsalsEnabled,
      blockoutsEnabled: blockoutsEnabled ?? this.blockoutsEnabled,
      setlistUpdates: setlistUpdates ?? this.setlistUpdates,
      availabilityRequests: availabilityRequests ?? this.availabilityRequests,
      memberUpdates: memberUpdates ?? this.memberUpdates,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      inAppEnabled: inAppEnabled ?? this.inAppEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
