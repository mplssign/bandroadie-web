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

/// Full musical proximity order for setlist tuning grouping.
///
/// Ordered by closeness to Standard tuning — fewest string changes first,
/// then progressive downtuning, then open/special tunings last.
///
/// Uses normalized tuning IDs (output of [TuningSortService.normalizeTuning]).
const List<String> kMusicalTuningOrder = [
  'standard',    // Standard (E)
  'drop_d',      // Drop D — only 1 string changes from Standard
  'half_step',   // Half-Step Down (Eb)
  'drop_db',     // Drop Db — Drop D on half-step-down guitar
  'full_step',   // Full-Step Down / D Standard
  'drop_c',      // Drop C — Drop D on full-step-down guitar
  'c_standard',  // C Standard
  'drop_b',      // Drop B
  'b_standard',  // B Standard (Baritone)
  'drop_a',      // Drop A
  'a_standard',  // A Standard
  'open_e',      // Open E
  'open_g',      // Open G
  'open_d',      // Open D
  'open_a',      // Open A
  'open_c',      // Open C
  'dadgad',      // DADGAD
  'nashville',   // Nashville
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

  /// Normalize tuning value to a canonical ID used in [kMusicalTuningOrder].
  /// Handles app IDs, legacy DB values, and display labels.
  static String normalizeTuning(String tuning) {
    final lower = tuning.toLowerCase().trim();

    const mapping = <String, String>{
      // Standard
      'standard': 'standard',
      'standard (e)': 'standard',
      'standard_e': 'standard',

      // Drop D
      'drop d': 'drop_d',
      'drop_d': 'drop_d',

      // Half-Step Down
      'half-step': 'half_step',
      'half step': 'half_step',
      'half_step': 'half_step',
      'half step down': 'half_step',
      'half_step_down': 'half_step',
      'half-step down': 'half_step',
      'eb standard': 'half_step',

      // Drop Db
      'drop db': 'drop_db',
      'drop_db': 'drop_db',
      'drop db (c#)': 'drop_db',

      // Full-Step / D Standard
      'full-step': 'full_step',
      'full step': 'full_step',
      'full_step': 'full_step',
      'full step down': 'full_step',
      'whole step down': 'full_step',
      'whole_step_down': 'full_step',
      'full-step down': 'full_step',
      'd standard': 'full_step',
      'd_standard': 'full_step',
      'whole step down (d)': 'full_step',

      // Drop C
      'drop c': 'drop_c',
      'drop_c': 'drop_c',

      // C Standard
      'c standard': 'c_standard',
      'c_standard': 'c_standard',

      // Drop B
      'drop b': 'drop_b',
      'drop_b': 'drop_b',

      // B Standard
      'b standard': 'b_standard',
      'b_standard': 'b_standard',
      'b standard (baritone)': 'b_standard',

      // Drop A
      'drop a': 'drop_a',
      'drop_a': 'drop_a',

      // A Standard
      'a standard': 'a_standard',
      'a_standard': 'a_standard',

      // Open tunings
      'open e': 'open_e',
      'open_e': 'open_e',
      'open g': 'open_g',
      'open_g': 'open_g',
      'open d': 'open_d',
      'open_d': 'open_d',
      'open a': 'open_a',
      'open_a': 'open_a',
      'open c': 'open_c',
      'open_c': 'open_c',

      // Special
      'dadgad': 'dadgad',
      'nashville': 'nashville',
    };

    return mapping[lower] ?? lower;
  }

  // Private alias for internal use
  static String _normalizeTuning(String tuning) => normalizeTuning(tuning);

  // ── String-based starting tuning persistence (for non-Catalog setlists) ───

  static const _startingTuningKeyPrefix = 'starting_tuning';

  static String _startingTuningKey(String bandId, String setlistId) =>
      '${_startingTuningKeyPrefix}_${bandId}_$setlistId';

  /// Get the persisted starting tuning ID for a setlist.
  /// Returns null if not set (original order).
  static Future<String?> getStartingTuningId({
    required String bandId,
    required String setlistId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_startingTuningKey(bandId, setlistId));
    } catch (e) {
      debugPrint('[TuningSortService] ⚠️ Failed to load starting tuning: $e');
      return null;
    }
  }

  /// Persist the starting tuning ID for a setlist.
  /// Pass null to clear (restore original order).
  static Future<void> setStartingTuningId({
    required String bandId,
    required String setlistId,
    required String? tuningId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _startingTuningKey(bandId, setlistId);
      if (tuningId == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, tuningId);
      }
    } catch (e) {
      debugPrint('[TuningSortService] ⚠️ Failed to persist starting tuning: $e');
    }
  }

  /// Return the unique tuning IDs present in [tunings], sorted by
  /// [kMusicalTuningOrder]. Unknown tunings are appended alphabetically.
  static List<String> sortedUniqueTunings(Iterable<String?> tunings) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final t in tunings) {
      if (t == null || t.isEmpty) continue;
      final n = normalizeTuning(t);
      if (seen.add(n)) normalized.add(n);
    }

    normalized.sort((a, b) {
      final ai = kMusicalTuningOrder.indexOf(a);
      final bi = kMusicalTuningOrder.indexOf(b);
      if (ai != -1 && bi != -1) return ai.compareTo(bi);
      if (ai != -1) return -1;
      if (bi != -1) return 1;
      return a.compareTo(b);
    });

    return normalized;
  }

  /// Given the current [startingTuningId] and the list of tunings present
  /// in the setlist, return the next tuning in the cycle.
  /// Cycles through all available tunings in musical order, then returns null
  /// (deselected / original order) after the last tuning.
  static String? nextStartingTuning(
    String? currentStartingTuningId,
    List<String> availableTunings,
  ) {
    if (availableTunings.isEmpty) return null;
    if (currentStartingTuningId == null) return availableTunings.first;
    final idx = availableTunings.indexOf(currentStartingTuningId);
    if (idx == -1 || idx == availableTunings.length - 1) {
      return null; // Wrap back to deselected (original order)
    }
    return availableTunings[idx + 1];
  }

  /// Standard and Drop D are always placed adjacent to each other,
  /// regardless of which one is the starting tuning.
  ///
  /// - Standard first → Standard, Drop D, Half-Step, ...
  /// - Drop D first   → Drop D, Standard, Half-Step, ...
  static const Map<String, String> _tuningNeighbors = {
    'standard': 'drop_d',
    'drop_d': 'standard',
  };

  /// Sort priority for a tuning given a starting tuning.
  ///
  /// Order:
  ///   0 → starting tuning
  ///   1 → its neighbor (Standard ↔ Drop D special case)
  ///   2+ → remaining tunings in [kMusicalTuningOrder] order, skipping
  ///         the starting tuning and neighbor, continuing from the position
  ///         after the neighbor in the master list.
  ///   9999 → no tuning
  ///   1000+ → unknown tuning (alphabetical fallback)
  static int getTuningGroupPriority(
    String? tuning,
    String startingTuningId,
  ) {
    if (tuning == null || tuning.isEmpty) return 9999;
    final normalized = normalizeTuning(tuning);
    if (normalized == startingTuningId) return 0;

    final neighbor = _tuningNeighbors[startingTuningId];
    if (neighbor != null && normalized == neighbor) return 1;

    // Remaining: musical order starting from after the neighbor (or starting
    // tuning if no neighbor), wrapping around, skipping already-placed entries.
    final skipSet = {startingTuningId, if (neighbor != null) neighbor};
    final anchorId = neighbor ?? startingTuningId;
    final anchorIdx = kMusicalTuningOrder.indexOf(anchorId);

    int rank = 2;
    for (int i = 1; i < kMusicalTuningOrder.length; i++) {
      final t = kMusicalTuningOrder[(anchorIdx + i) % kMusicalTuningOrder.length];
      if (skipSet.contains(t)) continue;
      if (t == normalized) return rank;
      rank++;
    }

    // Unknown tuning
    return 1000 + normalized.codeUnitAt(0);
  }
}
