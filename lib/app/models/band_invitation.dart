// ============================================================================
// BAND INVITATION MODEL
// Represents a pending invitation to join a band.
//
// Schema: public.band_invitations
// ============================================================================

enum InvitationStatus { pending, accepted, declined, expired }

class BandInvitation {
  final String id;
  final String bandId;
  final String email;
  final String? invitedBy;
  final InvitationStatus status;
  final String token;
  final DateTime createdAt;
  final DateTime expiresAt;

  const BandInvitation({
    required this.id,
    required this.bandId,
    required this.email,
    this.invitedBy,
    required this.status,
    required this.token,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Create a BandInvitation from Supabase row data
  factory BandInvitation.fromJson(Map<String, dynamic> json) {
    return BandInvitation(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      email: json['email'] as String,
      invitedBy: json['invited_by'] as String?,
      status: _parseStatus(json['status'] as String?),
      token: json['token'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  static InvitationStatus _parseStatus(String? status) {
    switch (status) {
      case 'accepted':
        return InvitationStatus.accepted;
      case 'declined':
        return InvitationStatus.declined;
      case 'expired':
        return InvitationStatus.expired;
      default:
        return InvitationStatus.pending;
    }
  }

  /// Convert to JSON for Supabase insert
  Map<String, dynamic> toJson() {
    return {
      'band_id': bandId,
      'email': email,
      'invited_by': invitedBy,
      'status': status.name,
    };
  }

  bool get isPending => status == InvitationStatus.pending;
  bool get isExpired =>
      status == InvitationStatus.expired || DateTime.now().isAfter(expiresAt);

  @override
  String toString() =>
      'BandInvitation(email: $email, bandId: $bandId, status: ${status.name})';
}
