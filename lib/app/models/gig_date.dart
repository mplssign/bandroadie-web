// ============================================================================
// GIG DATE MODEL
// Represents an additional date for a multi-date potential gig.
//
// This is used alongside the primary date stored in gigs.date.
// Only potential gigs can have multiple dates.
//
// Schema: public.gig_dates
// ============================================================================

class GigDate {
  final String id;
  final String gigId;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GigDate({
    required this.id,
    required this.gigId,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a GigDate from Supabase row data
  factory GigDate.fromJson(Map<String, dynamic> json) {
    return GigDate(
      id: json['id'] as String,
      gigId: json['gig_id'] as String,
      date: DateTime.parse(json['date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert
  Map<String, dynamic> toJson() {
    return {
      'gig_id': gigId,
      'date': date.toIso8601String().split('T')[0], // date only
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GigDate && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GigDate(id: $id, date: $date)';
}
