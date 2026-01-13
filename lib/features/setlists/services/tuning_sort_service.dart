import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// TUNING SORT SERVICE
// Persists per-setlist tuning sort preferences using SharedPreferences.
//
// KEY FORMAT: "tuning_sort_<bandId>_<setlistId>"
// VALUE: The tuning key string (e.g., "standard", "half_step", "drop_d")
//
// SORT ORDER (fixed priority):
// 1. standard
// 2. drop_d
// 3. half_step
// 4. full_step
// 5. any other tunings (alphabetical by label)
//
// When a sort mode is selected, songs with that tuning appear FIRST,
// then remaining songs follow in the fixed order above.
// ============================================================================

/// Fixed tuning order for consistent sorting.
/// Songs with the selected tuning appear first, then remaining songs
/// are sorted by this order, then by artist, then by title.
const List<String> kTuningSortOrder = [
  'standard',
  'drop_d',
  'half_step',
  'full_step',
];

/// Available tuning sort modes that the user can cycle through.
/// The toggle cycles: Standard → Half-Step → Full-Step → Drop D → Standard
const List<TuningSortMode> kTuningSortModes = [
  TuningSortMode.standard,
  TuningSortMode.halfStep,
  TuningSortMode.fullStep,
  TuningSortMode.dropD,
];

/// Tuning sort mode enum with display labels
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
    final currentIndex = kTuningSortModes.indexOf(this);
    final nextIndex = (currentIndex + 1) % kTuningSortModes.length;
    return kTuningSortModes[nextIndex];
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
    final prefs = await SharedPreferences.getInstance();
    final key = _buildKey(bandId, setlistId);
    final value = prefs.getString(key);
    return TuningSortMode.fromDbValue(value);
  }

  /// Persist the sort mode for a setlist.
  static Future<void> setSortMode({
    required String bandId,
    required String setlistId,
    required TuningSortMode mode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _buildKey(bandId, setlistId);
    await prefs.setString(key, mode.dbValue);
  }

  /// Clear the sort mode for a setlist (reverts to default).
  static Future<void> clearSortMode({
    required String bandId,
    required String setlistId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _buildKey(bandId, setlistId);
    await prefs.remove(key);
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
