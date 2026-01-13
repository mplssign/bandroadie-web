import 'package:flutter/foundation.dart';

// ============================================================================
// MEMBER VIEW MODEL
// Represents a band member for display in the Members screen.
// Combines data from band_members + users + user_band_roles tables.
//
// DATA HANDLING (three-table merge):
// - band_members: id, user_id, role (permission: owner/admin/member), status, joined_at
// - users: id, email, first_name, last_name, phone, address, city, zip, birthday, roles (musical), profile_completed
// - user_band_roles: user_id, band_id, roles[] (band-specific musical roles)
// - Display name priority:
//   1. "first_name last_name" (if both exist)
//   2. first_name or last_name (if one exists)
//   3. email (if exists)
//   4. "Member {userId.substring(0, 8)}"
//
// ROLE TYPES:
// - bandRole: Permission level (owner/admin/member) from band_members.role
// - musicalRoles: Instruments/positions (Guitar, Drums, etc.)
//   - First checks user_band_roles for band-specific roles
//   - Falls back to users.roles (global roles) if no band-specific roles exist
// - displayRoles getter returns musicalRoles for pill display
//
// BAND-SPECIFIC ROLES:
// - Users in multiple bands can have different musical roles per band
// - Stored in user_band_roles table with (user_id, band_id) unique constraint
// - If no band-specific roles, falls back to global roles from users.roles
//
// INVITATION PENDING RULE (STRICT):
// - "Invitation pending" ONLY shows for band_invitations rows (PendingInviteCard)
// - MemberCard displays band_members rows WITHOUT any invitation badge
// - Missing user row does NOT mean "Invitation pending"
// ============================================================================

/// View model for a band member
class MemberVM {
  /// The user's ID (from band_members.user_id) - internal use only
  final String userId;

  /// The band_members row ID
  final String memberId;

  /// Full display name (from user row or fallback)
  final String name;

  /// First name (from users.first_name) - used for short display labels
  final String? firstName;

  /// Last name (from users.last_name) - used for disambiguation
  final String? lastName;

  /// Email address (from users.email)
  final String email;

  /// Phone number (from users.phone)
  final String? phone;

  /// Street address (from users.address)
  final String? address;

  /// City (from users.city)
  final String? city;

  /// ZIP code (from users.zip)
  final String? zip;

  /// Birthday (from users.birthday) - only month/day are relevant
  final DateTime? birthday;

  /// Musical roles (from users.roles) - e.g. ["Guitar", "Lead Vocals"]
  final List<String> musicalRoles;

  /// Band permission role (owner/admin/member)
  final String bandRole;

  /// Membership status (active/invited/inactive/removed)
  final String status;

  /// When the member joined the band
  final DateTime joinedAt;

  /// Whether this member has a user row in public.users
  final bool hasUserRow;

  /// Whether this user has completed their profile (from users.profile_completed)
  final bool profileCompleted;

  const MemberVM({
    required this.userId,
    required this.memberId,
    required this.name,
    this.firstName,
    this.lastName,
    required this.email,
    this.phone,
    this.address,
    this.city,
    this.zip,
    this.birthday,
    this.musicalRoles = const [],
    required this.bandRole,
    required this.status,
    required this.joinedAt,
    required this.hasUserRow,
    required this.profileCompleted,
  });

  /// Create a MemberVM from merged band_members + users data
  ///
  /// [bandMember] - Row from band_members table
  /// [userRow] - Row from users table (may be null if user not found or RLS blocks)
  /// [bandRolesOverride] - Band-specific roles from user_band_roles (overrides users.roles if present)
  /// [bandId] - Optional band ID for debug logging
  factory MemberVM.fromMergedData({
    required Map<String, dynamic> bandMember,
    Map<String, dynamic>? userRow,
    List<String>? bandRolesOverride,
    String? bandId,
  }) {
    final userId = bandMember['user_id'] as String;
    final hasUserRow = userRow != null;

    // Extract fields from public.users table
    final firstName = userRow?['first_name'] as String?;
    final lastName = userRow?['last_name'] as String?;
    final userEmail = userRow?['email'] as String?;
    final userPhone = userRow?['phone'] as String?;
    final userAddress = userRow?['address'] as String?;
    final userCity = userRow?['city'] as String?;
    final userZip = userRow?['zip'] as String?;
    final birthdayStr = userRow?['birthday'] as String?;
    final userBirthday = birthdayStr != null
        ? DateTime.tryParse(birthdayStr)
        : null;
    final profileCompleted = userRow?['profile_completed'] as bool? ?? false;

    // Extract musical roles:
    // 1. Use band-specific roles if provided (from user_band_roles table)
    // 2. Fall back to global roles from users.roles
    final List<String> userMusicalRoles;
    final String rolesSource;
    if (bandRolesOverride != null && bandRolesOverride.isNotEmpty) {
      // Use band-specific roles
      userMusicalRoles = bandRolesOverride;
      rolesSource = 'perBand';
    } else {
      // Fall back to global roles from users.roles
      final rolesRaw = userRow?['roles'];
      if (rolesRaw is List) {
        userMusicalRoles = rolesRaw.cast<String>();
      } else {
        userMusicalRoles = [];
      }
      rolesSource = 'users';
    }

    // Debug log per requirements
    if (kDebugMode) {
      debugPrint(
        '[MemberVM] Member roles resolved: user=${userId.substring(0, 8)}... band=$bandId rolesSource=$rolesSource roles=$userMusicalRoles',
      );
    }

    // Build display name with priority fallbacks:
    // 1. "first_name last_name" (if both exist)
    // 2. first_name or last_name (if one exists)
    // 3. email (if exists)
    // 4. "Member {userId.substring(0, 8)}"
    String name;
    final hasFirstName = firstName != null && firstName.isNotEmpty;
    final hasLastName = lastName != null && lastName.isNotEmpty;

    if (hasFirstName && hasLastName) {
      name = '$firstName $lastName';
    } else if (hasFirstName) {
      name = firstName;
    } else if (hasLastName) {
      name = lastName;
    } else if (userEmail != null && userEmail.isNotEmpty) {
      name = userEmail;
    } else {
      // Final fallback: show truncated userId
      name = 'Member ${userId.substring(0, 8)}';
    }

    // Status from band_members
    final status = bandMember['status'] as String? ?? 'active';

    return MemberVM(
      userId: userId,
      memberId: bandMember['id'] as String,
      name: name,
      firstName: firstName,
      lastName: lastName,
      email: userEmail ?? '',
      phone: userPhone,
      address: userAddress,
      city: userCity,
      zip: userZip,
      birthday: userBirthday,
      musicalRoles: userMusicalRoles,
      bandRole: bandMember['role'] as String? ?? 'member',
      status: status,
      joinedAt: DateTime.parse(bandMember['joined_at'] as String),
      hasUserRow: hasUserRow,
      profileCompleted: profileCompleted,
    );
  }

  /// Display-friendly roles list - shows musical roles (e.g. Guitar, Drums)
  List<String> get displayRoles {
    // Return musical roles from user profile
    // If no musical roles, return empty list (no pills shown)
    return musicalRoles;
  }

  /// Whether this member is in "invited" status (band_members.status)
  /// NOTE: This does NOT trigger "Invitation pending" display on MemberCard.
  /// "Invitation pending" is ONLY shown for band_invitations rows.
  bool get isInvited => status == 'invited';

  /// Whether this member is active
  bool get isActive => status == 'active';

  /// Whether this member has admin/owner privileges
  bool get isAdmin => bandRole == 'admin' || bandRole == 'owner';

  /// Whether this member is the band owner
  bool get isOwner => bandRole == 'owner';

  @override
  String toString() =>
      'MemberVM(name: $name, bandRole: $bandRole, status: $status, hasUserRow: $hasUserRow, profileCompleted: $profileCompleted)';
}
