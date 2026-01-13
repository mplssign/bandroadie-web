// ============================================================================
// BAND MEMBER MODEL
// Represents a user's membership in a band.
// This is the join table between users and bands.
// ============================================================================

enum BandRole { member, admin, owner }

class BandMember {
  final String id;
  final String bandId;
  final String userId;
  final BandRole role;
  final DateTime joinedAt;

  const BandMember({
    required this.id,
    required this.bandId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  /// Create a BandMember from Supabase row data
  factory BandMember.fromJson(Map<String, dynamic> json) {
    return BandMember(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      userId: json['user_id'] as String,
      role: _parseRole(json['role'] as String?),
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  static BandRole _parseRole(String? role) {
    switch (role) {
      case 'owner':
        return BandRole.owner;
      case 'admin':
        return BandRole.admin;
      default:
        return BandRole.member;
    }
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'band_id': bandId,
      'user_id': userId,
      'role': role.name,
      'joined_at': joinedAt.toIso8601String(),
    };
  }

  @override
  String toString() =>
      'BandMember(userId: $userId, bandId: $bandId, role: $role)';
}
