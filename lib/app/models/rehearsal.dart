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
    };
  }

  /// Formatted time range (e.g., "6:00 PM - 9:00 PM")
  /// Uses TimeFormatter to ensure consistent 12-hour format display.
  String get timeRange => TimeFormatter.formatRange(startTime, endTime);

  @override
  String toString() => 'Rehearsal(id: $id, date: $date, location: $location)';
}
