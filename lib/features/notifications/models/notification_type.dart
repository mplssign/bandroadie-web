// ============================================================================
// NOTIFICATION TYPE ENUM
// All supported notification types in the system
// ============================================================================

/// Types of notifications supported by the app
enum NotificationType {
  gigCreated('gig_created'),
  gigUpdated('gig_updated'),
  gigCancelled('gig_cancelled'),
  gigConfirmed('gig_confirmed'),
  rehearsalCreated('rehearsal_created'),
  rehearsalUpdated('rehearsal_updated'),
  rehearsalCancelled('rehearsal_cancelled'),
  setlistUpdated('setlist_updated'),
  availabilityRequest('availability_request'),
  availabilityResponse('availability_response'),
  memberJoined('member_joined'),
  memberLeft('member_left'),
  roleChanged('role_changed'),
  bandInvitation('band_invitation');

  const NotificationType(this.value);
  final String value;

  static NotificationType fromString(String value) {
    return NotificationType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => NotificationType.gigUpdated, // Fallback
    );
  }

  /// Category for preference matching
  NotificationCategory get category {
    switch (this) {
      case NotificationType.gigCreated:
      case NotificationType.gigUpdated:
      case NotificationType.gigCancelled:
      case NotificationType.gigConfirmed:
        return NotificationCategory.gigs;
      case NotificationType.rehearsalCreated:
      case NotificationType.rehearsalUpdated:
      case NotificationType.rehearsalCancelled:
        return NotificationCategory.rehearsals;
      case NotificationType.setlistUpdated:
        return NotificationCategory.setlists;
      case NotificationType.availabilityRequest:
      case NotificationType.availabilityResponse:
        return NotificationCategory.availability;
      case NotificationType.memberJoined:
      case NotificationType.memberLeft:
      case NotificationType.roleChanged:
      case NotificationType.bandInvitation:
        return NotificationCategory.members;
    }
  }
}

/// Notification categories for preferences
enum NotificationCategory { gigs, rehearsals, setlists, availability, members }
