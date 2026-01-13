// ============================================================================
// EVENT PERMISSION HELPER
// Centralized permission logic for editing/deleting events.
//
// PERMISSION RULES:
// -----------------
// 1. GIGS, POTENTIAL GIGS, REHEARSALS:
//    - Any band member can edit or delete any of these events.
//    - No ownership restriction — shared calendar collaboration model.
//
// 2. BLOCK OUT DATES (single or multi-day):
//    - Only the creator (user_id) can edit or delete their own block out.
//    - Other band members can VIEW block outs but cannot modify them.
//    - This protects personal availability from accidental changes.
//
// USAGE:
//   final helper = EventPermissionHelper(currentUserId: userId);
//
//   if (!helper.canEditEvent(calendarEvent)) {
//     showError(helper.editDeniedMessage(calendarEvent));
//   }
// ============================================================================

import '../../features/calendar/models/calendar_event.dart';

/// Result of a permission check with reason.
class PermissionResult {
  final bool allowed;
  final String? deniedReason;

  const PermissionResult.allowed() : allowed = true, deniedReason = null;

  const PermissionResult.denied(this.deniedReason) : allowed = false;
}

/// Centralized permission checker for calendar events.
class EventPermissionHelper {
  /// The current user's ID (from Supabase auth).
  final String? currentUserId;

  const EventPermissionHelper({required this.currentUserId});

  // ==========================================================================
  // PERMISSION CHECKS
  // ==========================================================================

  /// Check if the current user can edit this event.
  ///
  /// Returns true for gigs/rehearsals (any band member can edit).
  /// Returns true for block outs only if current user is the creator.
  bool canEditEvent(CalendarEvent event) {
    return checkEditPermission(event).allowed;
  }

  /// Check if the current user can delete this event.
  ///
  /// Same rules as editing — block outs are creator-only.
  bool canDeleteEvent(CalendarEvent event) {
    return checkDeletePermission(event).allowed;
  }

  /// Check edit permission with detailed result.
  PermissionResult checkEditPermission(CalendarEvent event) {
    // No user logged in — deny all
    if (currentUserId == null || currentUserId!.isEmpty) {
      return const PermissionResult.denied('Please log in to edit events.');
    }

    // Block out: only creator can edit
    if (event.isBlockOut) {
      final creatorId = event.blockOutSpan?.userId ?? event.blockOut?.userId;
      if (creatorId != currentUserId) {
        return const PermissionResult.denied(
          'Only the person who created this block out date can make changes.',
        );
      }
    }

    // Gigs and rehearsals: any band member can edit
    return const PermissionResult.allowed();
  }

  /// Check delete permission with detailed result.
  PermissionResult checkDeletePermission(CalendarEvent event) {
    // No user logged in — deny all
    if (currentUserId == null || currentUserId!.isEmpty) {
      return const PermissionResult.denied('Please log in to delete events.');
    }

    // Block out: only creator can delete
    if (event.isBlockOut) {
      final creatorId = event.blockOutSpan?.userId ?? event.blockOut?.userId;
      if (creatorId != currentUserId) {
        return const PermissionResult.denied(
          'Only the person who created this block out date can delete it.',
        );
      }
    }

    // Gigs and rehearsals: any band member can delete
    return const PermissionResult.allowed();
  }

  // ==========================================================================
  // USER-FRIENDLY ERROR MESSAGES
  // ==========================================================================

  /// Get user-friendly message when edit is denied.
  String editDeniedMessage(CalendarEvent event) {
    final result = checkEditPermission(event);
    return result.deniedReason ?? 'You cannot edit this event.';
  }

  /// Get user-friendly message when delete is denied.
  String deleteDeniedMessage(CalendarEvent event) {
    final result = checkDeletePermission(event);
    return result.deniedReason ?? 'You cannot delete this event.';
  }

  // ==========================================================================
  // BLOCK OUT SPECIFIC HELPERS
  // ==========================================================================

  /// Check if current user is the creator of a block out.
  bool isBlockOutCreator(CalendarEvent event) {
    if (!event.isBlockOut) return false;
    final creatorId = event.blockOutSpan?.userId ?? event.blockOut?.userId;
    return creatorId == currentUserId;
  }
}

// ============================================================================
// ERROR MAPPING UTILITIES
// ============================================================================

/// Classifies errors into permission vs network vs other categories.
enum EventErrorType {
  /// Permission/authorization error (RLS policy violation, ownership issue)
  permission,

  /// Network/connectivity error
  network,

  /// Validation error (invalid input)
  validation,

  /// Unknown/other error
  unknown,
}

/// Analyzes an error and returns its type.
EventErrorType classifyError(Object error) {
  final errorStr = error.toString().toLowerCase();

  // Permission/authorization errors
  if (errorStr.contains('permission') ||
      errorStr.contains('rls') ||
      errorStr.contains('policy') ||
      errorStr.contains('denied') ||
      errorStr.contains('unauthorized') ||
      errorStr.contains('forbidden') ||
      errorStr.contains('not allowed')) {
    return EventErrorType.permission;
  }

  // Network errors
  if (errorStr.contains('network') ||
      errorStr.contains('socket') ||
      errorStr.contains('connection') ||
      errorStr.contains('timeout') ||
      errorStr.contains('host')) {
    return EventErrorType.network;
  }

  // Validation errors
  if (errorStr.contains('validation') ||
      errorStr.contains('invalid') ||
      errorStr.contains('required')) {
    return EventErrorType.validation;
  }

  return EventErrorType.unknown;
}

/// Maps an error to a user-friendly message for event operations.
///
/// Use [context] to customize the message (e.g., "save", "delete", "edit").
String mapEventErrorToMessage(Object error, {String context = 'save'}) {
  final errorType = classifyError(error);

  switch (errorType) {
    case EventErrorType.permission:
      return "You don't have permission to $context this event.";
    case EventErrorType.network:
      return "Can't reach the server. Please check your connection and try again.";
    case EventErrorType.validation:
      return 'Please check your input and try again.';
    case EventErrorType.unknown:
      return 'Failed to $context event. Please try again.';
  }
}

/// Maps an error to a user-friendly message for block out operations.
///
/// Use [context] to customize the message (e.g., "save", "delete", "edit").
String mapBlockOutErrorToMessage(Object error, {String context = 'save'}) {
  final errorType = classifyError(error);

  switch (errorType) {
    case EventErrorType.permission:
      return 'Only the person who created this block out date can $context it.';
    case EventErrorType.network:
      return "Can't reach the server. Please check your connection and try again.";
    case EventErrorType.validation:
      return 'Please check your input and try again.';
    case EventErrorType.unknown:
      return 'Failed to $context block out. Please try again.';
  }
}
