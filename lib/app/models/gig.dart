// ============================================================================
// GIG MODEL
// Represents a gig (potential or confirmed) for a band.
//
// IMPORTANT: Every gig MUST have a bandId.
// Gigs are always fetched in the context of a specific band.
//
// Multi-date potential gigs:
// - The primary date is stored in `date`
// - Additional dates are stored in `additionalDates` (from gig_dates table)
// - Only potential gigs can have multiple dates
// - `allDates` returns all dates sorted chronologically
//
// Schema: public.gigs, public.gig_dates
// ============================================================================

import '../utils/time_formatter.dart';
import 'gig_date.dart';

class Gig {
  final String id;
  final String bandId;
  final String name;
  final DateTime date;
  final String startTime;
  final String endTime;
  final String location;
  final String? setlistId;
  final String? setlistName;
  final String? notes;

  /// Payment amount for this gig in cents (stored as integer for precision).
  /// Null means no pay specified. 0 means explicitly unpaid.
  /// Example: 15000 = $150.00
  final int? gigPayCents;

  /// If true, this gig requires band member approval before it's confirmed.
  /// Potential gigs show RSVP UI. Confirmed gigs show as scheduled.
  final bool isPotential;

  /// List of user IDs for band members required for this potential gig.
  /// Empty set means all members are required (default behavior).
  final Set<String> requiredMemberIds;

  /// Additional dates for multi-date potential gigs.
  /// Empty list for single-date gigs or confirmed gigs.
  final List<GigDate> additionalDates;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Gig({
    required this.id,
    required this.bandId,
    required this.name,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
    this.setlistId,
    this.setlistName,
    this.notes,
    this.gigPayCents,
    required this.isPotential,
    this.requiredMemberIds = const {},
    this.additionalDates = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a Gig from Supabase row data
  factory Gig.fromJson(Map<String, dynamic> json) {
    return Gig(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      name: json['name'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      location: json['location'] as String,
      setlistId: json['setlist_id'] as String?,
      setlistName: json['setlist_name'] as String?,
      notes: json['notes'] as String?,
      gigPayCents: _parseGigPay(json['gig_pay']),
      isPotential: json['is_potential'] as bool? ?? false,
      requiredMemberIds: _parseRequiredMemberIds(json['required_member_ids']),
      additionalDates: _parseAdditionalDates(json['gig_dates']),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'band_id': bandId,
      'name': name,
      'date': date.toIso8601String().split('T')[0], // date only
      'start_time': startTime,
      'end_time': endTime,
      'location': location,
      'setlist_id': setlistId,
      'setlist_name': setlistName,
      'notes': notes,
      'gig_pay': gigPayCents != null ? gigPayCents! / 100.0 : null,
      'is_potential': isPotential,
      'required_member_ids': requiredMemberIds.toList(),
    };
  }

  /// Parse gig_pay from database (stored as numeric, convert to cents)
  static int? _parseGigPay(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      return (value * 100).round();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return (parsed * 100).round();
      }
    }
    return null;
  }

  /// Parse required_member_ids from database (can be null, List, or array)
  static Set<String> _parseRequiredMemberIds(dynamic value) {
    if (value == null) return {};
    if (value is List) {
      return value.map((e) => e.toString()).toSet();
    }
    return {};
  }

  /// Parse additional dates from gig_dates join (can be null or List)
  static List<GigDate> _parseAdditionalDates(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value
          .map((e) => GigDate.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Returns true if this is a confirmed (not potential) gig
  bool get isConfirmed => !isPotential;

  /// Returns true if this potential gig has multiple dates
  bool get isMultiDate => isPotential && additionalDates.isNotEmpty;

  /// Returns all dates for this gig (primary + additional), sorted chronologically.
  /// For single-date gigs, returns a list with just the primary date.
  List<DateTime> get allDates {
    final dates = [date, ...additionalDates.map((d) => d.date)];
    dates.sort();
    return dates;
  }

  /// Returns a map of date -> GigDate.id for additional dates.
  /// The primary date is not included (it has no GigDate.id).
  Map<DateTime, String> get additionalDateIds {
    final map = <DateTime, String>{};
    for (final gigDate in additionalDates) {
      map[gigDate.date] = gigDate.id;
    }
    return map;
  }

  /// Formatted time range (e.g., "7:30 PM - 10:30 PM")
  /// Uses TimeFormatter to ensure consistent 12-hour format display.
  String get timeRange => TimeFormatter.formatRange(startTime, endTime);

  /// Returns true if this gig has a pay amount specified
  bool get hasPay => gigPayCents != null && gigPayCents! > 0;

  /// Formatted gig pay (e.g., "$150.00")
  /// Returns null if no pay is specified.
  String? get formattedPay {
    if (gigPayCents == null) return null;
    final dollars = gigPayCents! ~/ 100;
    final cents = gigPayCents! % 100;
    return '\$$dollars.${cents.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => 'Gig(id: $id, name: $name, isPotential: $isPotential)';
}
