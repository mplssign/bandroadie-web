// ============================================================================
// REHEARSAL MODEL
// Represents a band rehearsal.
//
// IMPORTANT: Every rehearsal MUST have a bandId.
// Rehearsals are always fetched in the context of a specific band.
//
// Schema: public.rehearsals
// ============================================================================

import '../utils/time_formatter.dart';

class Rehearsal {
  final String id;
  final String bandId;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String location;
  final String? notes;
  final String? setlistId;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Recurrence fields
  final bool isRecurring;
  final String? recurrenceFrequency; // 'weekly', 'biweekly', 'monthly'
  final List<int>? recurrenceDays; // Day indices [0=Sun, 1=Mon, ..., 6=Sat]
  final DateTime? recurrenceUntil;
  final String? parentRehearsalId; // Links child instances to parent

  const Rehearsal({
    required this.id,
    required this.bandId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
    this.notes,
    this.setlistId,
    required this.createdAt,
    required this.updatedAt,
    this.isRecurring = false,
    this.recurrenceFrequency,
    this.recurrenceDays,
    this.recurrenceUntil,
    this.parentRehearsalId,
  });

  /// Create a Rehearsal from Supabase row data
  factory Rehearsal.fromJson(Map<String, dynamic> json) {
    return Rehearsal(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      location: json['location'] as String,
      notes: json['notes'] as String?,
      setlistId: json['setlist_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isRecurring: json['is_recurring'] as bool? ?? false,
      recurrenceFrequency: json['recurrence_frequency'] as String?,
      recurrenceDays: (json['recurrence_days'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
      recurrenceUntil: json['recurrence_until'] != null
          ? DateTime.parse(json['recurrence_until'] as String)
          : null,
      parentRehearsalId: json['parent_rehearsal_id'] as String?,
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'band_id': bandId,
      'date': date.toIso8601String().split('T')[0], // date only
      'start_time': startTime,
      'end_time': endTime,
      'location': location,
      'notes': notes,
      'setlist_id': setlistId,
      'is_recurring': isRecurring,
      'recurrence_frequency': recurrenceFrequency,
      'recurrence_days': recurrenceDays,
      'recurrence_until': recurrenceUntil?.toIso8601String().split('T')[0],
      'parent_rehearsal_id': parentRehearsalId,
    };
  }

  /// Whether this rehearsal is part of a recurring series (either parent or child)
  bool get isPartOfSeries => isRecurring || parentRehearsalId != null;

  /// Formatted time range (e.g., "6:00 PM - 9:00 PM")
  /// Uses TimeFormatter to ensure consistent 12-hour format display.
  String get timeRange => TimeFormatter.formatRange(startTime, endTime);

  @override
  String toString() => 'Rehearsal(id: $id, date: $date, location: $location)';
}
