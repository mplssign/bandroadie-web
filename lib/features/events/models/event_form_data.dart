// ============================================================================
// EVENT FORM DATA
// Models for the Add/Edit Event Bottom Sheet
// ============================================================================

import '../../calendar/models/calendar_event.dart';
import '../../../app/models/gig.dart';
import '../../../app/models/rehearsal.dart';
import '../../../app/utils/time_formatter.dart';

/// The type of event being created/edited
enum EventType {
  rehearsal,
  gig;

  String get displayName {
    switch (this) {
      case EventType.rehearsal:
        return 'Rehearsal';
      case EventType.gig:
        return 'Gig';
    }
  }
}

/// Frequency options for recurring events
enum RecurrenceFrequency {
  weekly,
  biweekly,
  monthly;

  String get displayName {
    switch (this) {
      case RecurrenceFrequency.weekly:
        return 'Weekly';
      case RecurrenceFrequency.biweekly:
        return 'Biweekly';
      case RecurrenceFrequency.monthly:
        return 'Monthly';
    }
  }

  /// Create from database string value
  static RecurrenceFrequency? fromString(String? value) {
    if (value == null) return null;
    return RecurrenceFrequency.values.firstWhere(
      (f) => f.name == value,
      orElse: () => RecurrenceFrequency.weekly,
    );
  }
}

/// Duration options (in minutes)
enum EventDuration {
  min30(30, '30m'),
  hour1(60, '1h'),
  hour1_30(90, '1h 30m'),
  hour2(120, '2h'),
  hour2_30(150, '2h 30m'),
  hour3(180, '3h'),
  hour3_30(210, '3h 30m'),
  hour4(240, '4h');

  final int minutes;
  final String label;

  const EventDuration(this.minutes, this.label);
}

/// Days of the week for recurring events
enum Weekday {
  sunday(0, 'S'),
  monday(1, 'M'),
  tuesday(2, 'T'),
  wednesday(3, 'W'),
  thursday(4, 'T'),
  friday(5, 'F'),
  saturday(6, 'S');

  final int dayIndex;
  final String shortLabel;

  const Weekday(this.dayIndex, this.shortLabel);

  /// Abbreviated day name (Sun, Mon, etc.)
  String get fullName {
    switch (this) {
      case Weekday.sunday:
        return 'Sun';
      case Weekday.monday:
        return 'Mon';
      case Weekday.tuesday:
        return 'Tue';
      case Weekday.wednesday:
        return 'Wed';
      case Weekday.thursday:
        return 'Thu';
      case Weekday.friday:
        return 'Fri';
      case Weekday.saturday:
        return 'Sat';
    }
  }

  /// Plural day name for recurrence summary (Sundays, Mondays, etc.)
  String get pluralName {
    switch (this) {
      case Weekday.sunday:
        return 'Sundays';
      case Weekday.monday:
        return 'Mondays';
      case Weekday.tuesday:
        return 'Tuesdays';
      case Weekday.wednesday:
        return 'Wednesdays';
      case Weekday.thursday:
        return 'Thursdays';
      case Weekday.friday:
        return 'Fridays';
      case Weekday.saturday:
        return 'Saturdays';
    }
  }
}

/// Recurrence configuration for recurring events
class RecurrenceConfig {
  final Set<Weekday> daysOfWeek;
  final RecurrenceFrequency frequency;
  final DateTime? untilDate;

  const RecurrenceConfig({
    required this.daysOfWeek,
    required this.frequency,
    this.untilDate,
  });

  /// Generate a human-readable summary of the recurrence
  String get summary {
    if (daysOfWeek.isEmpty) return '';

    // Sort days starting from Sunday
    final sortedDays = daysOfWeek.toList()
      ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
    final dayNames = sortedDays.map((d) => d.fullName).join(', ');

    final frequencyText = frequency.displayName;
    final untilText = untilDate != null
        ? ' until ${_formatDate(untilDate!)}'
        : '';

    return '$frequencyText on $dayNames$untilText';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Map<String, dynamic> toJson() {
    return {
      'days_of_week': daysOfWeek.map((d) => d.dayIndex).toList(),
      'frequency': frequency.name,
      'until_date': untilDate?.toIso8601String(),
    };
  }
}

/// Form data for creating/updating an event
class EventFormData {
  final EventType type;
  final DateTime date;
  final int hour; // 1-12
  final int minutes; // 0, 15, 30, 45
  final bool isPM;
  final EventDuration duration;
  final String location;
  final String? notes;
  final String? name; // For gigs (optional for rehearsals)
  final bool isRecurring;
  final RecurrenceConfig? recurrence;

  // Load-in time fields (gigs only, optional)
  final int? loadInHour; // 1-12
  final int? loadInMinutes; // 0, 15, 30, 45
  final bool? loadInIsPM;

  // Potential gig fields (gigs only)
  final bool isPotentialGig;
  final Set<String> selectedMemberIds; // User IDs of members to notify

  // Multi-date potential gig fields
  /// Additional dates for multi-date potential gigs.
  /// The primary date is `date`; these are extra options.
  final List<DateTime> additionalDates;

  /// IDs of existing GigDate records (for edit mode).
  /// Maps DateTime -> GigDate.id for additional dates that already exist in DB.
  final Map<DateTime, String> existingGigDateIds;

  // Setlist fields (optional for both gigs and rehearsals)
  final String? setlistId;
  final String? setlistName; // For gigs - stores the name for display

  // Gig pay field (gigs only, optional)
  /// Payment amount for this gig in cents (stored as integer for precision).
  /// Null means no pay specified. 0 means explicitly unpaid.
  final int? gigPayCents;

  // Recurring rehearsal series tracking (rehearsals only)
  /// Parent rehearsal ID if this is a child in a recurring series.
  /// Null for non-recurring or parent rehearsals.
  final String? parentRehearsalId;

  const EventFormData({
    required this.type,
    required this.date,
    required this.hour,
    required this.minutes,
    required this.isPM,
    required this.duration,
    required this.location,
    this.notes,
    this.name,
    this.isRecurring = false,
    this.recurrence,
    this.loadInHour,
    this.loadInMinutes,
    this.loadInIsPM,
    this.isPotentialGig = false,
    this.selectedMemberIds = const {},
    this.additionalDates = const [],
    this.existingGigDateIds = const {},
    this.setlistId,
    this.setlistName,
    this.gigPayCents,
    this.parentRehearsalId,
  });

  /// Whether this is a multi-date potential gig
  bool get isMultiDate => isPotentialGig && additionalDates.isNotEmpty;

  /// All dates for this event (primary + additional), sorted chronologically
  List<DateTime> get allDates {
    final dates = [date, ...additionalDates];
    dates.sort();
    return dates;
  }

  /// Convert hour/minutes/isPM to 24-hour start time string (HH:MM)
  String get startTime24 {
    int hour24 = hour;
    if (isPM && hour != 12) {
      hour24 = hour + 12;
    } else if (!isPM && hour == 12) {
      hour24 = 0;
    }
    return '${hour24.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  /// Convert to 12-hour display string (e.g., "7:30 PM")
  String get startTimeDisplay {
    final minStr = minutes.toString().padLeft(2, '0');
    final amPm = isPM ? 'PM' : 'AM';
    return '$hour:$minStr $amPm';
  }

  /// Convert load-in time to 12-hour display string (e.g., "6:00 PM")
  /// Returns null if no load-in time is set
  String? get loadInTimeDisplay {
    if (loadInHour == null || loadInMinutes == null || loadInIsPM == null) {
      return null;
    }
    final minStr = loadInMinutes!.toString().padLeft(2, '0');
    final amPm = loadInIsPM! ? 'PM' : 'AM';
    return '$loadInHour:$minStr $amPm';
  }

  /// Calculate end time based on duration
  String get endTime24 {
    int hour24 = hour;
    if (isPM && hour != 12) {
      hour24 = hour + 12;
    } else if (!isPM && hour == 12) {
      hour24 = 0;
    }

    final totalMinutes = hour24 * 60 + minutes + duration.minutes;
    final endHour = (totalMinutes ~/ 60) % 24;
    final endMinutes = totalMinutes % 60;

    return '${endHour.toString().padLeft(2, '0')}:${endMinutes.toString().padLeft(2, '0')}';
  }

  /// Calculate end time in 12-hour display format
  String get endTimeDisplay {
    int hour24 = hour;
    if (isPM && hour != 12) {
      hour24 = hour + 12;
    } else if (!isPM && hour == 12) {
      hour24 = 0;
    }

    final totalMinutes = hour24 * 60 + minutes + duration.minutes;
    int endHour = (totalMinutes ~/ 60) % 24;
    final endMinutes = totalMinutes % 60;

    final endPM = endHour >= 12;
    if (endHour > 12) endHour -= 12;
    if (endHour == 0) endHour = 12;

    final minStr = endMinutes.toString().padLeft(2, '0');
    final amPm = endPM ? 'PM' : 'AM';
    return '$endHour:$minStr $amPm';
  }

  /// Get the event name (with default for rehearsals)
  String get displayName {
    if (type == EventType.gig) {
      return name ?? '';
    }
    return name ?? 'Band Rehearsal';
  }

  /// Validate the form data
  List<String> validate() {
    final errors = <String>[];

    if (type == EventType.gig && (name == null || name!.trim().isEmpty)) {
      errors.add('Gig name is required');
    }

    // For gigs, location (city) is required
    if (type == EventType.gig && location.trim().isEmpty) {
      errors.add('City is required');
    }

    // Potential gig validation: require at least one member
    if (type == EventType.gig && isPotentialGig && selectedMemberIds.isEmpty) {
      errors.add('Select at least one member for potential gig');
    }

    if (isRecurring && recurrence != null) {
      if (recurrence!.daysOfWeek.isEmpty) {
        errors.add('Select at least one day for recurring events');
      }
      if (recurrence!.untilDate != null &&
          recurrence!.untilDate!.isBefore(date)) {
        errors.add('End date must be after event date');
      }
    }

    return errors;
  }

  EventFormData copyWith({
    EventType? type,
    DateTime? date,
    int? hour,
    int? minutes,
    bool? isPM,
    EventDuration? duration,
    String? location,
    String? notes,
    String? name,
    bool? isRecurring,
    RecurrenceConfig? recurrence,
    bool? isPotentialGig,
    Set<String>? selectedMemberIds,
    List<DateTime>? additionalDates,
    Map<DateTime, String>? existingGigDateIds,
    String? setlistId,
    String? setlistName,
    int? gigPayCents,
    String? parentRehearsalId,
    bool clearSetlist = false,
    bool clearGigPay = false,
  }) {
    return EventFormData(
      type: type ?? this.type,
      date: date ?? this.date,
      hour: hour ?? this.hour,
      minutes: minutes ?? this.minutes,
      isPM: isPM ?? this.isPM,
      duration: duration ?? this.duration,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      name: name ?? this.name,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrence: recurrence ?? this.recurrence,
      isPotentialGig: isPotentialGig ?? this.isPotentialGig,
      selectedMemberIds: selectedMemberIds ?? this.selectedMemberIds,
      additionalDates: additionalDates ?? this.additionalDates,
      existingGigDateIds: existingGigDateIds ?? this.existingGigDateIds,
      setlistId: clearSetlist ? null : (setlistId ?? this.setlistId),
      setlistName: clearSetlist ? null : (setlistName ?? this.setlistName),
      gigPayCents: clearGigPay ? null : (gigPayCents ?? this.gigPayCents),
      parentRehearsalId: parentRehearsalId ?? this.parentRehearsalId,
    );
  }

  // ===========================================================================
  // FACTORY CONSTRUCTORS FROM MODELS
  // ===========================================================================

  /// Parse a time string using the shared TimeFormatter utility.
  /// Returns a record with hour (1-12), minutes, and isPM.
  static ({int hour, int minutes, bool isPM}) _parseTime(String timeStr) {
    final parsed = TimeFormatter.parse(timeStr);
    return (hour: parsed.hour, minutes: parsed.minutes, isPM: parsed.isPM);
  }

  /// Infer duration from start and end times using TimeFormatter
  static EventDuration _inferDuration(String startTime, String endTime) {
    final durationMinutes = TimeFormatter.durationMinutes(startTime, endTime);

    // Map to closest EventDuration
    if (durationMinutes <= 45) return EventDuration.min30;
    if (durationMinutes <= 75) return EventDuration.hour1;
    if (durationMinutes <= 105) return EventDuration.hour1_30;
    if (durationMinutes <= 135) return EventDuration.hour2;
    if (durationMinutes <= 165) return EventDuration.hour2_30;
    if (durationMinutes <= 195) return EventDuration.hour3;
    if (durationMinutes <= 225) return EventDuration.hour3_30;
    return EventDuration.hour4;
  }

  /// Create EventFormData from a Gig model
  factory EventFormData.fromGig(Gig gig) {
    final parsed = _parseTime(gig.startTime);
    final duration = _inferDuration(gig.startTime, gig.endTime);

    // Parse load-in time if present
    int? loadInHour;
    int? loadInMinutes;
    bool? loadInIsPM;
    if (gig.loadInTime != null) {
      final loadInParsed = _parseTime(gig.loadInTime!);
      loadInHour = loadInParsed.hour;
      loadInMinutes = loadInParsed.minutes;
      loadInIsPM = loadInParsed.isPM;
    }

    return EventFormData(
      type: EventType.gig,
      date: gig.date,
      hour: parsed.hour,
      minutes: parsed.minutes,
      isPM: parsed.isPM,
      duration: duration,
      location: gig.location,
      notes: gig.notes,
      name: gig.name,
      isRecurring: false,
      recurrence: null,
      loadInHour: loadInHour,
      loadInMinutes: loadInMinutes,
      loadInIsPM: loadInIsPM,
      isPotentialGig: gig.isPotential,
      selectedMemberIds: gig.requiredMemberIds,
      additionalDates: gig.additionalDates.map((d) => d.date).toList(),
      existingGigDateIds: gig.additionalDateIds,
      setlistId: gig.setlistId,
      setlistName: gig.setlistName,
      gigPayCents: gig.gigPayCents,
    );
  }

  /// Create EventFormData from a Rehearsal model
  factory EventFormData.fromRehearsal(Rehearsal rehearsal) {
    final parsed = _parseTime(rehearsal.startTime);
    final duration = _inferDuration(rehearsal.startTime, rehearsal.endTime);

    // Build recurrence config if this is a recurring rehearsal
    RecurrenceConfig? recurrence;
    if (rehearsal.isRecurring && rehearsal.recurrenceDays != null) {
      final days = rehearsal.recurrenceDays!
          .map((index) => Weekday.values.firstWhere((w) => w.dayIndex == index))
          .toSet();
      final frequency =
          RecurrenceFrequency.fromString(rehearsal.recurrenceFrequency) ??
          RecurrenceFrequency.weekly;
      recurrence = RecurrenceConfig(
        daysOfWeek: days,
        frequency: frequency,
        untilDate: rehearsal.recurrenceUntil,
      );
    }

    return EventFormData(
      type: EventType.rehearsal,
      date: rehearsal.date,
      hour: parsed.hour,
      minutes: parsed.minutes,
      isPM: parsed.isPM,
      duration: duration,
      location: rehearsal.location,
      notes: rehearsal.notes,
      name: null,
      isRecurring: rehearsal.isRecurring,
      recurrence: recurrence,
      isPotentialGig: false,
      selectedMemberIds: const {},
      setlistId: rehearsal.setlistId,
      setlistName: null, // Rehearsals don't store setlist name
      parentRehearsalId: rehearsal.parentRehearsalId,
    );
  }

  /// Create EventFormData from a CalendarEvent
  factory EventFormData.fromCalendarEvent(CalendarEvent event) {
    if (event.gig != null) {
      return EventFormData.fromGig(event.gig!);
    } else if (event.rehearsal != null) {
      return EventFormData.fromRehearsal(event.rehearsal!);
    }

    // Fallback (shouldn't happen in practice)
    final parsed = _parseTime(event.startTime);
    return EventFormData(
      type: event.isGig ? EventType.gig : EventType.rehearsal,
      date: event.date,
      hour: parsed.hour,
      minutes: parsed.minutes,
      isPM: parsed.isPM,
      duration: EventDuration.hour2,
      location: event.location,
      notes: event.notes,
      name: event.title,
      isRecurring: false,
      recurrence: null,
      isPotentialGig: false,
      selectedMemberIds: const {},
      setlistId: null,
      setlistName: null,
    );
  }
}
