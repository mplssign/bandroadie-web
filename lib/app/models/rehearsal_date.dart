// ============================================================================
// REHEARSAL DATE MODEL
// Represents an additional date for a multi-date potential rehearsal.
//
// This is used alongside the primary date stored in rehearsals.date.
// Only potential rehearsals can have multiple dates.
//
// Schema: public.rehearsal_dates
// ============================================================================

class RehearsalDate {
  final String id;
  final String rehearsalId;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RehearsalDate({
    required this.id,
    required this.rehearsalId,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a RehearsalDate from Supabase row data
  factory RehearsalDate.fromJson(Map<String, dynamic> json) {
    return RehearsalDate(
      id: json['id'] as String,
      rehearsalId: json['rehearsal_id'] as String,
      date: DateTime.parse(json['date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert
  Map<String, dynamic> toJson() {
    return {
      'rehearsal_id': rehearsalId,
      'date': date.toIso8601String().split('T')[0], // date only
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RehearsalDate && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RehearsalDate(id: $id, date: $date)';
}
