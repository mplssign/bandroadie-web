// ============================================================================
// BLOCK OUT MODEL
// Represents a single blocked-out date for a band member.
//
// Schema: public.block_dates
// Columns: id (uuid), user_id (uuid), band_id (uuid), date (date),
//          reason (text NOT NULL), created_at, updated_at
// Unique constraint: (user_id, band_id, date)
// ============================================================================

class BlockOut {
  final String id;
  final String bandId;
  final String userId;
  final DateTime date;
  final String reason; // NOT NULL in DB, use empty string if none
  final DateTime createdAt;
  final DateTime updatedAt;

  const BlockOut({
    required this.id,
    required this.bandId,
    required this.userId,
    required this.date,
    required this.reason,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a BlockOut from Supabase row data
  factory BlockOut.fromJson(Map<String, dynamic> json) {
    // Parse date-only column as local midnight
    DateTime parseDate(String dateStr) {
      // Handle both 'YYYY-MM-DD' and ISO timestamp formats
      if (dateStr.contains('T')) {
        return DateTime.parse(dateStr).toLocal();
      }
      // Date-only: parse as local date
      final parts = dateStr.split('-');
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }

    return BlockOut(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      userId: json['user_id'] as String,
      date: parseDate(json['date'] as String),
      reason: json['reason'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      'band_id': bandId,
      'user_id': userId,
      'date': _formatDateOnly(date),
      'reason': reason, // Always include, empty string if none
    };
  }

  /// Format DateTime as YYYY-MM-DD for DB date column
  static String _formatDateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Get display text for the date
  String get dateDisplay => _formatDisplayDate(date);

  static String _formatDisplayDate(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}';
  }

  @override
  String toString() => 'BlockOut(id: $id, date: $date, reason: $reason)';
}
