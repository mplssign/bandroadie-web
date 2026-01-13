// ============================================================================
// BULK SONG PARSER
// Pure parsing logic for bulk-pasted song data from spreadsheets or manual entry.
//
// Features:
// - Tab-delimited parsing (spreadsheet paste)
// - Comma-delimited parsing (manual entry)
// - 2+ space fallback for legacy formats
// - BPM validation (1-300 or empty)
// - Tuning normalization to match app's tuning IDs
// - De-duplication within pasted batch
// - Validation error reporting per row
// ============================================================================

import 'package:flutter/foundation.dart';

import '../models/bulk_song_row.dart';

/// Result of parsing bulk song input
class BulkSongParseResult {
  /// All parsed rows (including invalid ones)
  final List<BulkSongRow> allRows;

  /// Only valid rows ready for submission
  final List<BulkSongRow> validRows;

  /// Only invalid rows (for error display)
  final List<BulkSongRow> invalidRows;

  /// Number of duplicates that were removed
  final int duplicatesRemoved;

  const BulkSongParseResult({
    required this.allRows,
    required this.validRows,
    required this.invalidRows,
    required this.duplicatesRemoved,
  });

  /// Whether there are any valid rows to submit
  bool get hasValidRows => validRows.isNotEmpty;

  /// Total row count (for display)
  int get totalRows => allRows.length;
}

/// Parser for bulk song input
class BulkSongParser {
  /// Singleton instance
  static const BulkSongParser instance = BulkSongParser._();

  const BulkSongParser._();

  /// Parse raw input text into BulkSongRow objects.
  ///
  /// Supports two input formats:
  /// 1. Spreadsheet paste: ARTIST\tSONG\tBPM\tTUNING (tab-delimited or 2+ spaces)
  /// 2. Manual entry: ARTIST, SONG, BPM, TUNING (comma-delimited)
  ///
  /// - BPM and TUNING are optional
  /// - Blank lines are ignored
  /// - [maxRows] limits the number of rows processed (default: no limit)
  BulkSongParseResult parse(String input, {int? maxRows}) {
    if (input.trim().isEmpty) {
      return const BulkSongParseResult(
        allRows: [],
        validRows: [],
        invalidRows: [],
        duplicatesRemoved: 0,
      );
    }

    final lines = input.split('\n');
    final allRows = <BulkSongRow>[];
    final seenKeys = <String>{};
    var duplicatesRemoved = 0;
    var processedCount = 0;

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      // Check row limit
      if (maxRows != null && processedCount >= maxRows) break;
      processedCount++;

      // Parse the line into columns
      final columns = _parseColumns(trimmedLine);

      // Need at least 2 columns (artist and song)
      if (columns.length < 2) {
        allRows.add(
          BulkSongRow.invalid(
            artist: columns.isNotEmpty ? columns[0] : '',
            title: '',
            error: BulkSongValidationError.missingTitle,
            errorMessage: 'Missing song title',
          ),
        );
        continue;
      }

      final artist = columns[0].trim();
      final title = columns[1].trim();
      final rawBpm = columns.length > 2 ? columns[2].trim() : '';
      final rawTuning = columns.length > 3 ? columns[3].trim() : '';

      // Validate title is not empty
      if (title.isEmpty) {
        allRows.add(
          BulkSongRow.invalid(
            artist: artist,
            title: title,
            error: BulkSongValidationError.missingTitle,
            errorMessage: 'Missing song title',
          ),
        );
        continue;
      }

      // Parse and validate BPM
      int? bpm;
      BulkSongValidationError? bpmWarning;
      String? bpmWarningMessage;
      if (rawBpm.isNotEmpty) {
        bpm = int.tryParse(rawBpm);
        if (bpm == null || bpm < 1 || bpm > 300) {
          // Invalid BPM is a warning, not an error - row is still valid
          bpmWarning = BulkSongValidationError.invalidBpm;
          bpmWarningMessage = 'Invalid BPM ignored';
          bpm = null; // Clear invalid BPM
        }
      }

      // Normalize and validate tuning
      String? tuningId;
      String? tuningLabel;
      BulkSongValidationError? tuningWarning;
      String? tuningWarningMessage;
      if (rawTuning.isNotEmpty) {
        final normalized = _normalizeTuning(rawTuning);
        if (normalized == null) {
          // Unknown tuning is a warning, not an error - row is still valid
          tuningWarning = BulkSongValidationError.unknownTuning;
          tuningWarningMessage = 'Unknown tuning ignored';
          // Leave tuning as null
        } else {
          tuningId = normalized.id;
          tuningLabel = normalized.label;
        }
      }

      // Determine overall warning (prioritize BPM warning over tuning)
      final warning = bpmWarning ?? tuningWarning;
      final warningMessage = bpmWarningMessage ?? tuningWarningMessage;

      // Create valid row (with possible warning)
      final row = BulkSongRow.valid(
        artist: artist,
        title: title,
        bpm: bpm,
        tuning: tuningId,
        tuningLabel: tuningLabel,
        warning: warning,
        warningMessage: warningMessage,
      );

      // De-duplicate within batch
      if (seenKeys.contains(row.dedupeKey)) {
        duplicatesRemoved++;
        continue;
      }
      seenKeys.add(row.dedupeKey);

      allRows.add(row);
    }

    // Split into valid and invalid
    final validRows = allRows.where((r) => r.isValid).toList();
    final invalidRows = allRows.where((r) => !r.isValid).toList();

    return BulkSongParseResult(
      allRows: allRows,
      validRows: validRows,
      invalidRows: invalidRows,
      duplicatesRemoved: duplicatesRemoved,
    );
  }

  /// Parse a single line into columns.
  ///
  /// Priority order:
  /// 1. TAB-delimited (spreadsheet paste)
  /// 2. Comma-delimited (manual entry)
  /// 3. 2+ spaces fallback (legacy support)
  List<String> _parseColumns(String line) {
    // Try TAB-delimited first (spreadsheet paste)
    if (line.contains('\t')) {
      return line.split('\t').map((c) => c.trim()).toList();
    }

    // Try comma-delimited (manual entry)
    if (line.contains(',')) {
      return line.split(',').map((c) => c.trim()).toList();
    }

    // Fall back to 2+ spaces (legacy support)
    return line.split(RegExp(r'\s{2,}')).map((c) => c.trim()).toList();
  }

  /// Normalize tuning input to our internal ID and label.
  /// Returns null if tuning is not recognized.
  ///
  /// Handles patterns like:
  /// - "Standard (E A D G B e)" → Standard
  /// - "Drop D tuning" → Drop D
  /// - "open g" → Open G
  _NormalizedTuning? _normalizeTuning(String input) {
    // Clean input: trim, lowercase, remove extra info in parentheses
    var normalized = input.trim().toLowerCase();

    // Remove parenthetical info like "(E A D G B e)"
    normalized = normalized.replaceAll(RegExp(r'\s*\([^)]*\)'), '');

    // Remove trailing "tuning" word
    normalized = normalized.replaceAll(RegExp(r'\s+tuning$'), '');

    // Trim again after cleanup
    normalized = normalized.trim();

    // Mapping from various input forms to our tuning IDs
    // Tuning IDs match those in tuning_picker_bottom_sheet.dart
    const tuningMap = <String, _NormalizedTuning>{
      // Standard / E Standard
      'standard': _NormalizedTuning('standard_e', 'Standard'),
      'e standard': _NormalizedTuning('standard_e', 'Standard'),
      'e': _NormalizedTuning('standard_e', 'Standard'),
      'standard (e)': _NormalizedTuning('standard_e', 'Standard'),
      'standard_e': _NormalizedTuning('standard_e', 'Standard'),

      // Half-Step Down / Eb Standard
      'half-step': _NormalizedTuning('half_step_down', 'Half-Step'),
      'half step': _NormalizedTuning('half_step_down', 'Half-Step'),
      'half step down': _NormalizedTuning('half_step_down', 'Half-Step'),
      'half-step down': _NormalizedTuning('half_step_down', 'Half-Step'),
      'half step down (eb)': _NormalizedTuning('half_step_down', 'Half-Step'),
      'eb standard': _NormalizedTuning('half_step_down', 'Half-Step'),
      'eb': _NormalizedTuning('half_step_down', 'Half-Step'),
      'e♭': _NormalizedTuning('half_step_down', 'Half-Step'),
      'e flat': _NormalizedTuning('half_step_down', 'Half-Step'),
      'half_step_down': _NormalizedTuning('half_step_down', 'Half-Step'),

      // Whole Step Down / D Standard
      'full-step': _NormalizedTuning('whole_step_down', 'Full-Step'),
      'full step': _NormalizedTuning('whole_step_down', 'Full-Step'),
      'full step down': _NormalizedTuning('whole_step_down', 'Full-Step'),
      'full-step down': _NormalizedTuning('whole_step_down', 'Full-Step'),
      'whole step down': _NormalizedTuning('whole_step_down', 'Full-Step'),
      'whole step down (d)': _NormalizedTuning('whole_step_down', 'Full-Step'),
      'whole_step_down': _NormalizedTuning('whole_step_down', 'Full-Step'),
      'd standard': _NormalizedTuning('d_standard', 'D Standard'),
      'd_standard': _NormalizedTuning('d_standard', 'D Standard'),

      // Drop tunings
      'drop d': _NormalizedTuning('drop_d', 'Drop D'),
      'drop_d': _NormalizedTuning('drop_d', 'Drop D'),
      'drop c': _NormalizedTuning('drop_c', 'Drop C'),
      'drop_c': _NormalizedTuning('drop_c', 'Drop C'),
      'drop db': _NormalizedTuning('drop_db', 'Drop Db'),
      'drop d♭': _NormalizedTuning('drop_db', 'Drop Db'),
      'drop c#': _NormalizedTuning('drop_db', 'Drop Db'),
      'drop c♯': _NormalizedTuning('drop_db', 'Drop Db'),
      'drop_db': _NormalizedTuning('drop_db', 'Drop Db'),
      'drop db (c#)': _NormalizedTuning('drop_db', 'Drop Db'),
      'drop b': _NormalizedTuning('drop_b', 'Drop B'),
      'drop_b': _NormalizedTuning('drop_b', 'Drop B'),
      'drop a': _NormalizedTuning('drop_a', 'Drop A'),
      'drop_a': _NormalizedTuning('drop_a', 'Drop A'),

      // Other standard tunings
      'c standard': _NormalizedTuning('c_standard', 'C Standard'),
      'c_standard': _NormalizedTuning('c_standard', 'C Standard'),
      'b standard': _NormalizedTuning('b_standard', 'B Standard'),
      'b_standard': _NormalizedTuning('b_standard', 'B Standard'),
      'b standard (baritone)': _NormalizedTuning('b_standard', 'B Standard'),

      // Open tunings
      'open g': _NormalizedTuning('open_g', 'Open G'),
      'open_g': _NormalizedTuning('open_g', 'Open G'),
      'open d': _NormalizedTuning('open_d', 'Open D'),
      'open_d': _NormalizedTuning('open_d', 'Open D'),
      'open e': _NormalizedTuning('open_e', 'Open E'),
      'open_e': _NormalizedTuning('open_e', 'Open E'),
      'open a': _NormalizedTuning('open_a', 'Open A'),
      'open_a': _NormalizedTuning('open_a', 'Open A'),
      'open c': _NormalizedTuning('open_c', 'Open C'),
      'open_c': _NormalizedTuning('open_c', 'Open C'),
    };

    final result = tuningMap[normalized];
    if (result == null && kDebugMode) {
      debugPrint(
        '[BulkSongParser] Unknown tuning: "$input" -> normalized="$normalized"',
      );
    }
    return result;
  }
}

/// Internal class for normalized tuning data
class _NormalizedTuning {
  final String id;
  final String label;

  const _NormalizedTuning(this.id, this.label);
}
