// ============================================================================
// BULK SONG ROW MODEL
// Represents a single parsed row from bulk paste input.
// Includes validation state for UI preview.
// ============================================================================

/// Validation error types for bulk paste rows
enum BulkSongValidationError { missingTitle, invalidBpm, unknownTuning }

/// Represents a single parsed row from the bulk paste input.
///
/// This model holds both the parsed data and any validation errors
/// to enable displaying preview rows with inline error badges.
class BulkSongRow {
  /// Original artist text (Column 1)
  final String artist;

  /// Original song title (Column 2) - REQUIRED
  final String title;

  /// Parsed BPM value (Column 3) - null if not provided
  final int? bpm;

  /// Normalized tuning ID (Column 4) - null if not provided
  /// Maps to the tuning IDs defined in tuning_picker_bottom_sheet.dart
  final String? tuning;

  /// Display-friendly tuning label (for preview)
  final String? tuningLabel;

  /// Validation error if the row is invalid (missing required fields)
  final BulkSongValidationError? error;

  /// Human-readable error message for display
  final String? errorMessage;

  /// Non-fatal warning (row is still valid but has issues)
  final BulkSongValidationError? warning;

  /// Human-readable warning message for display
  final String? warningMessage;

  const BulkSongRow({
    required this.artist,
    required this.title,
    this.bpm,
    this.tuning,
    this.tuningLabel,
    this.error,
    this.errorMessage,
    this.warning,
    this.warningMessage,
  });

  /// Whether this row is valid and can be submitted
  bool get isValid => error == null && title.isNotEmpty;

  /// Whether this row has a warning (but is still valid)
  bool get hasWarning => warning != null;

  /// Create an invalid row with an error
  factory BulkSongRow.invalid({
    required String artist,
    required String title,
    int? bpm,
    String? tuning,
    required BulkSongValidationError error,
    required String errorMessage,
  }) {
    return BulkSongRow(
      artist: artist,
      title: title,
      bpm: bpm,
      tuning: tuning,
      error: error,
      errorMessage: errorMessage,
    );
  }

  /// Create a valid row (with optional warning)
  factory BulkSongRow.valid({
    required String artist,
    required String title,
    int? bpm,
    String? tuning,
    String? tuningLabel,
    BulkSongValidationError? warning,
    String? warningMessage,
  }) {
    return BulkSongRow(
      artist: artist,
      title: title,
      bpm: bpm,
      tuning: tuning,
      tuningLabel: tuningLabel,
      warning: warning,
      warningMessage: warningMessage,
    );
  }

  /// Formatted BPM for display (e.g., "120 BPM" or "- BPM" if missing)
  String get formattedBpm => bpm != null ? '$bpm BPM' : '- BPM';

  /// Formatted tuning for display
  String get formattedTuning => tuningLabel ?? tuning ?? 'Standard';

  /// Unique key for de-duplication: lowercase artist + title
  String get dedupeKey =>
      '${artist.toLowerCase().trim()}|${title.toLowerCase().trim()}';

  @override
  String toString() {
    return 'BulkSongRow(artist: $artist, title: $title, bpm: $bpm, tuning: $tuning, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BulkSongRow &&
        other.artist == artist &&
        other.title == title &&
        other.bpm == bpm &&
        other.tuning == tuning;
  }

  @override
  int get hashCode => Object.hash(artist, title, bpm, tuning);
}
