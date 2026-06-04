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
  final bool canViewFinancials;

  const ContributorPermissions({
    this.canCreateGigs = true,
    this.canCreatePotentialGigsOnly = true,
    this.canViewSetlists = true,
    this.canViewCalendar = true,
    this.canViewMembers = true,
    this.canViewFinancials = false,
  });

  /// All permissions enabled (default state for new contributor rows in DB)
  static const ContributorPermissions allEnabled = ContributorPermissions(
    canViewFinancials: true,
  );

  /// All permissions disabled — fail-closed fallback when row can't be read
  static const ContributorPermissions allDisabled = ContributorPermissions(
    canCreateGigs: false,
    canCreatePotentialGigsOnly: false,
    canViewSetlists: false,
    canViewCalendar: false,
    canViewMembers: false,
    canViewFinancials: false,
  );

  factory ContributorPermissions.fromJson(Map<String, dynamic> json) {
    return ContributorPermissions(
      canCreateGigs: json['can_create_gigs'] as bool? ?? true,
      canCreatePotentialGigsOnly:
          json['can_create_potential_gigs_only'] as bool? ?? true,
      canViewSetlists: json['can_view_setlists'] as bool? ?? true,
      canViewCalendar: json['can_view_calendar'] as bool? ?? true,
      canViewMembers: json['can_view_members'] as bool? ?? true,
      canViewFinancials: json['can_view_financials'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'can_create_gigs': canCreateGigs,
      'can_create_potential_gigs_only': canCreatePotentialGigsOnly,
      'can_view_setlists': canViewSetlists,
      'can_view_calendar': canViewCalendar,
      'can_view_members': canViewMembers,
      'can_view_financials': canViewFinancials,
    };
  }

  ContributorPermissions copyWith({
    bool? canCreateGigs,
    bool? canCreatePotentialGigsOnly,
    bool? canViewSetlists,
    bool? canViewCalendar,
    bool? canViewMembers,
    bool? canViewFinancials,
  }) {
    return ContributorPermissions(
      canCreateGigs: canCreateGigs ?? this.canCreateGigs,
      canCreatePotentialGigsOnly:
          canCreatePotentialGigsOnly ?? this.canCreatePotentialGigsOnly,
      canViewSetlists: canViewSetlists ?? this.canViewSetlists,
      canViewCalendar: canViewCalendar ?? this.canViewCalendar,
      canViewMembers: canViewMembers ?? this.canViewMembers,
      canViewFinancials: canViewFinancials ?? this.canViewFinancials,
    );
  }

  @override
  String toString() =>
      'ContributorPermissions(gigs=$canCreateGigs, potentialOnly=$canCreatePotentialGigsOnly, setlists=$canViewSetlists, calendar=$canViewCalendar, members=$canViewMembers, financials=$canViewFinancials)';
}
