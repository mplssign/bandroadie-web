import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// CATALOG SORT SERVICE
// Manages catalog sorting preferences and provides sorting logic.
//
// SORT MODES:
// - Title: Alphabetical by song title
// - Artist: Alphabetical by artist/band name
// - BPM: Ascending or descending by beats per minute
// - Duration: Ascending or descending by song length
// - Tuning: Grouped by tuning type (Standard, Drop D, etc.)
//
// Catalog sort mode is preserved in-memory and persists across navigation
// until explicitly changed by the user or app restart.
// Custom setlists always use position order from database.
// ============================================================================

/// Available sort modes for the Catalog
enum CatalogSortMode {
  title('Song Title (A–Z)', 'title'),
  artist('Artist / Band (A–Z)', 'artist'),
  bpm('BPM (Low → High)', 'bpm'),
  bpmDesc('BPM (High → Low)', 'bpm_desc'),
  duration('Duration (Short → Long)', 'duration'),
  durationDesc('Duration (Long → Short)', 'duration_desc'),
  tuning('Guitar Tuning', 'tuning');

  final String label;
  final String key;

  const CatalogSortMode(this.label, this.key);

  /// Get mode from key
  static CatalogSortMode fromKey(String key) {
    return CatalogSortMode.values.firstWhere(
      (mode) => mode.key == key,
      orElse: () => CatalogSortMode.title,
    );
  }
}

/// Fixed tuning order for consistent sorting.
/// When sorting by tuning, songs are grouped in this order.
const List<String> kTuningSortOrder = [
  'standard',
  'drop_d',
  'half_step',
  'full_step',
];

/// Legacy tuning sort mode enum (kept for backwards compatibility)
/// This is now mapped to CatalogSortMode.tuning
enum TuningSortMode {
  standard('Standard', 'standard'),
  halfStep('Half-Step', 'half_step'),
  fullStep('Full-Step', 'full_step'),
  dropD('Drop D', 'drop_d');

  final String label;
  final String dbValue;

  const TuningSortMode(this.label, this.dbValue);

  /// Get the next mode in the cycle
  TuningSortMode get next {
    final currentIndex = TuningSortMode.values.indexOf(this);
    final nextIndex = (currentIndex + 1) % TuningSortMode.values.length;
    return TuningSortMode.values[nextIndex];
  }

  /// Parse from database value string
  static TuningSortMode fromDbValue(String? value) {
    if (value == null || value.isEmpty) return TuningSortMode.standard;

    for (final mode in TuningSortMode.values) {
      if (mode.dbValue == value) return mode;
    }
    return TuningSortMode.standard;
  }
}

/// Service for persisting and retrieving tuning sort preferences per setlist.
class TuningSortService {
  static const _keyPrefix = 'tuning_sort';

  /// Build the storage key for a band/setlist combination
  static String _buildKey(String bandId, String setlistId) {
    return '${_keyPrefix}_${bandId}_$setlistId';
  }

  /// Get the persisted sort mode for a setlist.
  /// Returns [TuningSortMode.standard] if not set.
  static Future<TuningSortMode> getSortMode({
    required String bandId,
    required String setlistId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _buildKey(bandId, setlistId);
      final value = prefs.getString(key);
      return TuningSortMode.fromDbValue(value);
    } catch (e) {
      debugPrint('[TuningSortService] ⚠️ Failed to load sort mode: $e');
      return TuningSortMode.standard; // Default fallback
    }
  }

  /// Persist the sort mode for a setlist.
  static Future<void> setSortMode({
    required String bandId,
    required String setlistId,
    required TuningSortMode mode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _buildKey(bandId, setlistId);
      await prefs.setString(key, mode.dbValue);
    } catch (e) {
      debugPrint('[TuningSortService] ⚠️ Failed to persist sort mode: $e');
      // Sort preference not persisting is non-critical
    }
  }

  /// Clear the sort mode for a setlist (reverts to default).
  static Future<void> clearSortMode({
    required String bandId,
    required String setlistId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _buildKey(bandId, setlistId);
      await prefs.remove(key);
    } catch (e) {
      debugPrint('[TuningSortService] ⚠️ Failed to clear sort mode: $e');
      // Silent failure acceptable for cleanup
    }
  }

  /// Get the sort priority for a tuning value using rotation logic.
  ///
  /// The base order is: standard, drop_d, half_step, full_step
  ///
  /// When a different mode is selected, the order rotates so that
  /// the selected mode comes first, followed by the remaining modes
  /// in their original sequence (wrapping around):
  ///
  /// - Standard first:  standard → drop_d → half_step → full_step
  /// - Drop D first:    drop_d → half_step → full_step → standard
  /// - Half-Step first: half_step → full_step → standard → drop_d
  /// - Full-Step first: full_step → standard → drop_d → half_step
  ///
  /// Returns priority 0-3 for known tunings (lower = higher priority).
  /// Unknown tunings get 100+ for alphabetical fallback.
  static int getTuningPriority(String? tuning, TuningSortMode selectedMode) {
    if (tuning == null) return 999; // No tuning sorts last

    // Normalize the tuning value for comparison
    final normalized = _normalizeTuning(tuning);

    // Build the rotated order based on selected mode
    final rotatedOrder = getRotatedOrder(selectedMode);

    // Find position in the rotated order
    final index = rotatedOrder.indexOf(normalized);
    if (index >= 0) {
      return index;
    }

    // Unknown tunings sort after the known ones (alphabetically)
    return 100 + normalized.codeUnitAt(0);
  }

  /// Get the rotated tuning order based on the selected mode.
  ///
  /// The order rotates so the selected mode's dbValue is first,
  /// followed by the remaining tunings in their original sequence.
  static List<String> getRotatedOrder(TuningSortMode selectedMode) {
    final startIndex = kTuningSortOrder.indexOf(selectedMode.dbValue);
    if (startIndex < 0) return kTuningSortOrder; // Fallback to default

    // Rotate the list so selectedMode.dbValue is first
    final rotated = <String>[
      ...kTuningSortOrder.sublist(startIndex),
      ...kTuningSortOrder.sublist(0, startIndex),
    ];

    return rotated;
  }

  /// Normalize tuning value to database format.
  /// Handles both display labels and database values.
  static String _normalizeTuning(String tuning) {
    final lower = tuning.toLowerCase().trim();

    // Map common variations to database values
    const mapping = <String, String>{
      'standard': 'standard',
      'standard (e)': 'standard',
      'standard_e': 'standard',
      'half-step': 'half_step',
      'half step': 'half_step',
      'half_step': 'half_step',
      'half step down': 'half_step',
      'half_step_down': 'half_step',
      'eb standard': 'half_step',
      'full-step': 'full_step',
      'full step': 'full_step',
      'full_step': 'full_step',
      'full step down': 'full_step',
      'whole step down': 'full_step',
      'whole_step_down': 'full_step',
      'd standard': 'full_step',
      'd_standard': 'full_step',
      'drop d': 'drop_d',
      'drop_d': 'drop_d',
    };

    return mapping[lower] ?? lower;
  }
}
