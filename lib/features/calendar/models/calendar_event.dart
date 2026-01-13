// ============================================================================
// CALENDAR EVENT MODEL
// Unified event type for displaying gigs, rehearsals, and block outs on the calendar.
// ============================================================================

import '../../../app/models/block_out.dart';
import '../../../app/models/gig.dart';
import '../../../app/models/rehearsal.dart';
import '../../../app/utils/time_formatter.dart';

/// Event types that can appear on the calendar.
enum CalendarEventType {
  /// A gig (confirmed or potential) - shown with green indicator
  gig,

  /// A rehearsal - shown with blue indicator
  rehearsal,

  /// A block out - shown with rose indicator
  blockOut,
}

/// Represents a spanning block out (grouped consecutive dates)
class BlockOutSpan {
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String userId;
  final String userName; // "FirstName" for display

  const BlockOutSpan({
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.userId,
    required this.userName,
  });

  /// Whether this span covers multiple days
  bool get isMultiDay => !_isSameDay(startDate, endDate);

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// Unified calendar event model that wraps either a Gig, Rehearsal, or BlockOut.
class CalendarEvent {
  final String id;
  final CalendarEventType type;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String location;
  final String? title;
  final String? notes;

  /// Original gig object (if type is gig)
  final Gig? gig;

  /// Original rehearsal object (if type is rehearsal)
  final Rehearsal? rehearsal;

  /// Original block out object (if type is blockOut)
  final BlockOut? blockOut;

  /// Block out span info (for grouped consecutive dates)
  final BlockOutSpan? blockOutSpan;

  const CalendarEvent({
    required this.id,
    required this.type,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
    this.title,
    this.notes,
    this.gig,
    this.rehearsal,
    this.blockOut,
    this.blockOutSpan,
  });

  /// Create a CalendarEvent from a Gig
  factory CalendarEvent.fromGig(Gig gig) {
    return CalendarEvent(
      id: gig.id,
      type: CalendarEventType.gig,
      date: gig.date,
      startTime: gig.startTime,
      endTime: gig.endTime,
      location: gig.location,
      title: gig.name,
      notes: gig.notes,
      gig: gig,
    );
  }

  /// Create a CalendarEvent from a Rehearsal
  factory CalendarEvent.fromRehearsal(Rehearsal rehearsal) {
    return CalendarEvent(
      id: rehearsal.id,
      type: CalendarEventType.rehearsal,
      date: rehearsal.date,
      startTime: rehearsal.startTime,
      endTime: rehearsal.endTime,
      location: rehearsal.location,
      title: 'Rehearsal',
      notes: rehearsal.notes,
      rehearsal: rehearsal,
    );
  }

  /// Create a CalendarEvent from a BlockOutSpan (grouped consecutive dates)
  /// The userName should be the first name of the user who created the block out.
  factory CalendarEvent.fromBlockOutSpan(BlockOutSpan span) {
    return CalendarEvent(
      id: '${span.userId}_${span.startDate.toIso8601String()}',
      type: CalendarEventType.blockOut,
      date: span.startDate,
      startTime: '', // Block outs are all-day
      endTime: '',
      location: '', // No location for block outs
      title: '${span.userName} Out',
      notes: span.reason.isNotEmpty ? span.reason : null,
      blockOutSpan: span,
    );
  }

  /// Formatted time range (e.g., "6:00 PM - 9:00 PM")
  /// Uses TimeFormatter to ensure consistent 12-hour format display.
  String get timeRange => TimeFormatter.formatRange(startTime, endTime);

  /// Display title - gig name, "Rehearsal", or "FirstName Out"
  String get displayTitle => title ?? 'Event';

  /// Whether this is a gig event
  bool get isGig => type == CalendarEventType.gig;

  /// Whether this is a rehearsal event
  bool get isRehearsal => type == CalendarEventType.rehearsal;

  /// Whether this is a block out event
  bool get isBlockOut => type == CalendarEventType.blockOut;

  /// End date for multi-day block outs (null if single day or not a block out)
  DateTime? get endDate {
    if (isBlockOut && blockOutSpan != null && blockOutSpan!.isMultiDay) {
      return blockOutSpan!.endDate;
    }
    return null;
  }

  /// Whether this is a potential (unconfirmed) gig
  bool get isPotentialGig => isGig && (gig?.isPotential ?? false);

  /// Whether this is a confirmed gig
  bool get isConfirmedGig => isGig && (gig?.isConfirmed ?? false);

  @override
  String toString() =>
      'CalendarEvent(type: $type, date: $date, title: $displayTitle)';
}
