// ============================================================================
// PENDING INVITE VIEW MODEL
// Represents a pending band invitation for display in the Members screen.
// Data comes from public.band_invitations table.
// ============================================================================

/// View model for a pending band invitation
class PendingInviteVM {
  /// The invitation ID (from band_invitations.id)
  final String id;

  /// The invited email address
  final String email;

  /// Invitation status (should always be 'pending' for this VM)
  final String status;

  /// When the invitation was created
  final DateTime createdAt;

  /// When the invitation expires (optional)
  final DateTime? expiresAt;

  const PendingInviteVM({
    required this.id,
    required this.email,
    required this.status,
    required this.createdAt,
    this.expiresAt,
  });

  /// Create from band_invitations row
  factory PendingInviteVM.fromJson(Map<String, dynamic> json) {
    DateTime? expiresAt;
    final expiresAtStr = json['expires_at'] as String?;
    if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
      try {
        expiresAt = DateTime.parse(expiresAtStr);
      } catch (_) {
        // Invalid date format, ignore
      }
    }

    return PendingInviteVM(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: expiresAt,
    );
  }

  /// Display name derived from email
  String get displayName {
    if (email.isEmpty) return 'Unknown';
    final localPart = email.split('@').first;
    if (localPart.isEmpty) return email;
    return localPart[0].toUpperCase() + localPart.substring(1);
  }

  /// Whether the invitation has expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  @override
  String toString() => 'PendingInviteVM(email: $email, status: $status)';
}
