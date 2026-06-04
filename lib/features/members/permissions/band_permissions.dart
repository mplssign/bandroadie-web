// ============================================================================
// BAND PERMISSIONS
// Pure Dart permission abstraction layer.
// Takes a role + optional sub-permissions and returns boolean checks.
//
// This is a CLIENT-SIDE CONVENIENCE — backend RLS is the final authority.
// All permission checks in the UI must flow through this class.
// Do NOT check role strings directly in UI code.
// ============================================================================

import 'contributor_permissions.dart';

class BandPermissions {
  final String role;
  final ContributorPermissions? subPermissions;

  const BandPermissions._({
    required this.role,
    this.subPermissions,
  });

  /// Create permissions from a role string and optional sub-permissions.
  /// [role] should be 'admin', 'member', or 'contributor'.
  /// [subPerms] is only relevant for contributor role.
  factory BandPermissions.fromRole(
    String role, {
    ContributorPermissions? subPerms,
  }) {
    return BandPermissions._(
      role: role,
      subPermissions: role == 'contributor' ? subPerms : null,
    );
  }

  /// Default permissions (admin) — used as fallback
  static const BandPermissions admin = BandPermissions._(role: 'admin');

  // ──────────────────────────────────────────────────────
  // Role checks
  // ──────────────────────────────────────────────────────

  bool get isAdmin => role == 'admin';
  bool get isMember => role == 'member';
  bool get isContributor => role == 'contributor';

  // ──────────────────────────────────────────────────────
  // Admin-only actions
  // ──────────────────────────────────────────────────────

  /// Edit band name, avatar, settings
  bool get canEditBandSettings => isAdmin;

  /// Invite new members to the band
  bool get canInviteMembers => isAdmin;

  /// Remove members from the band
  bool get canRemoveMembers => isAdmin;

  /// Change another member's role
  bool get canChangeRoles => isAdmin;

  /// Delete the band entirely
  bool get canDeleteBand => isAdmin;

  /// Whether this user can export / backup band data.
  /// Admin & member: yes. Contributor: no.
  bool get canExportBandData => isAdmin || isMember;

  // ──────────────────────────────────────────────────────
  // Gig actions
  // ──────────────────────────────────────────────────────

  /// Whether this user can create gigs
  /// Admin & member: always. Contributor: if canCreateGigs OR
  /// canCreatePotentialGigsOnly is enabled (potential-only still requires
  /// access to the gig creation flow).
  bool get canCreateGigs {
    if (isAdmin || isMember) return true;
    if (isContributor) {
      final canFull = subPermissions?.canCreateGigs ?? false;
      final canPotential = subPermissions?.canCreatePotentialGigsOnly ?? false;
      return canFull || canPotential;
    }
    return false;
  }

  /// Whether contributor can ONLY create potential gigs (not confirmed)
  bool get canCreatePotentialGigsOnly {
    if (isAdmin || isMember) return false;
    if (isContributor) {
      return subPermissions?.canCreatePotentialGigsOnly ?? false;
    }
    return false;
  }

  /// Whether this user can edit gigs (admin & member only)
  bool get canEditGigs => isAdmin || isMember;

  /// Whether this user can edit potential gigs.
  /// Admin & member: always. Contributor: if they can create gigs or
  /// potential gigs (they should be able to edit what they created).
  bool get canEditPotentialGigs {
    if (isAdmin || isMember) return true;
    if (isContributor) {
      final canFull = subPermissions?.canCreateGigs ?? false;
      final canPotential = subPermissions?.canCreatePotentialGigsOnly ?? false;
      return canFull || canPotential;
    }
    return false;
  }

  /// Whether this user can delete gigs (admin & member only)
  bool get canDeleteGigs => isAdmin || isMember;

  // ──────────────────────────────────────────────────────
  // Setlist actions
  // ──────────────────────────────────────────────────────

  /// Whether this user can create/edit/delete setlists
  bool get canCreateSetlists => isAdmin || isMember;
  bool get canEditSetlists => isAdmin || isMember;

  /// Whether this user can view setlists
  /// Admin & member: always. Contributor: depends on sub-permissions.
  bool get canViewSetlists {
    if (isAdmin || isMember) return true;
    if (isContributor) {
      return subPermissions?.canViewSetlists ?? false;
    }
    return false;
  }

  // ──────────────────────────────────────────────────────
  // Calendar / members visibility
  // ──────────────────────────────────────────────────────

  /// Whether this user can view the calendar
  bool get canViewCalendar {
    if (isAdmin || isMember) return true;
    if (isContributor) {
      return subPermissions?.canViewCalendar ?? false;
    }
    return false;
  }

  /// Whether this user can view the members list
  bool get canViewMembers {
    if (isAdmin || isMember) return true;
    if (isContributor) {
      return subPermissions?.canViewMembers ?? false;
    }
    return false;
  }

  /// Whether this user can view the financials screen.
  /// Admin & member: always. Contributor: only if canViewFinancials sub-permission is set.
  bool get canViewFinancials {
    if (isAdmin || isMember) return true;
    if (isContributor) {
      return subPermissions?.canViewFinancials ?? false;
    }
    return false;
  }

  @override
  String toString() =>
      'BandPermissions(role=$role, isAdmin=$isAdmin, canCreateGigs=$canCreateGigs)';
}
