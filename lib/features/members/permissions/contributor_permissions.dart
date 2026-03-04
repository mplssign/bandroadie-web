// ============================================================================
// CONTRIBUTOR PERMISSIONS MODEL
// Sub-permissions for the 'contributor' role.
// Maps directly to the contributor_permissions table.
// ============================================================================

class ContributorPermissions {
  final bool canCreateGigs;
  final bool canCreatePotentialGigsOnly;
  final bool canViewSetlists;
  final bool canViewCalendar;
  final bool canViewMembers;

  const ContributorPermissions({
    this.canCreateGigs = true,
    this.canCreatePotentialGigsOnly = true,
    this.canViewSetlists = true,
    this.canViewCalendar = true,
    this.canViewMembers = true,
  });

  /// All permissions enabled (default state for new contributor rows in DB)
  static const ContributorPermissions allEnabled = ContributorPermissions();

  /// All permissions disabled — fail-closed fallback when row can't be read
  static const ContributorPermissions allDisabled = ContributorPermissions(
    canCreateGigs: false,
    canCreatePotentialGigsOnly: false,
    canViewSetlists: false,
    canViewCalendar: false,
    canViewMembers: false,
  );

  factory ContributorPermissions.fromJson(Map<String, dynamic> json) {
    return ContributorPermissions(
      canCreateGigs: json['can_create_gigs'] as bool? ?? true,
      canCreatePotentialGigsOnly:
          json['can_create_potential_gigs_only'] as bool? ?? true,
      canViewSetlists: json['can_view_setlists'] as bool? ?? true,
      canViewCalendar: json['can_view_calendar'] as bool? ?? true,
      canViewMembers: json['can_view_members'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'can_create_gigs': canCreateGigs,
      'can_create_potential_gigs_only': canCreatePotentialGigsOnly,
      'can_view_setlists': canViewSetlists,
      'can_view_calendar': canViewCalendar,
      'can_view_members': canViewMembers,
    };
  }

  ContributorPermissions copyWith({
    bool? canCreateGigs,
    bool? canCreatePotentialGigsOnly,
    bool? canViewSetlists,
    bool? canViewCalendar,
    bool? canViewMembers,
  }) {
    return ContributorPermissions(
      canCreateGigs: canCreateGigs ?? this.canCreateGigs,
      canCreatePotentialGigsOnly:
          canCreatePotentialGigsOnly ?? this.canCreatePotentialGigsOnly,
      canViewSetlists: canViewSetlists ?? this.canViewSetlists,
      canViewCalendar: canViewCalendar ?? this.canViewCalendar,
      canViewMembers: canViewMembers ?? this.canViewMembers,
    );
  }

  @override
  String toString() =>
      'ContributorPermissions(gigs=$canCreateGigs, potentialOnly=$canCreatePotentialGigsOnly, setlists=$canViewSetlists, calendar=$canViewCalendar, members=$canViewMembers)';
}
