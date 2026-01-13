// ============================================================================
// USER PROFILE MODEL
// Represents a user's profile in the system.
//
// Schema: public.users (not public.profiles — profiles is for avatar/bio)
// ============================================================================

class UserProfile {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? address;
  final String? city;
  final String? zip;
  final DateTime? birthday;
  final List<String> roles;
  final bool profileCompleted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.phone,
    this.address,
    this.city,
    this.zip,
    this.birthday,
    this.roles = const [],
    this.profileCompleted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a UserProfile from Supabase row data
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      zip: json['zip'] as String?,
      birthday: json['birthday'] != null
          ? DateTime.parse(json['birthday'] as String)
          : null,
      roles: (json['roles'] as List<dynamic>?)?.cast<String>() ?? [],
      profileCompleted: json['profile_completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'address': address,
      'city': city,
      'zip': zip,
      'birthday': birthday?.toIso8601String().split('T')[0],
      'roles': roles,
      'profile_completed': profileCompleted,
    };
  }

  /// Full name (first + last) with fallback to email
  String get fullName {
    final first = firstName?.trim() ?? '';
    final last = lastName?.trim() ?? '';
    final combined = [first, last].where((s) => s.isNotEmpty).join(' ');
    return combined.isNotEmpty ? combined : email.split('@').first;
  }

  /// Display name (first name, email prefix, or "Member" as fallback)
  String get displayName {
    final first = firstName?.trim() ?? '';
    if (first.isNotEmpty) return first;
    return email.split('@').first;
  }

  @override
  String toString() => 'UserProfile(id: $id, email: $email, name: $fullName)';
}
