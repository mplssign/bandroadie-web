import 'package:flutter/material.dart';

import '../services/custom_tuning_service.dart';

// ============================================================================
// TUNING HELPERS
// Centralized tuning utilities for short labels and badge colors.
//
// USAGE:
// - tuningShortLabel(option) → badge-friendly label
// - tuningShortLabelAsync(option) → badge-friendly label with custom tuning lookup
// - tuningBadgeColor(tuningName) → Color for badge fill
// - tuningBadgeTextColor(Color, tuningKey: ...) → readable text color for badge
// ============================================================================

// =============================================================================
// CAPO ENCODING
// Capo is encoded inside the tuning string as "tuningId|capo:N" (N = 1-12).
// Existing values without "|capo:" are treated as no-capo and work exactly
// as before — full backwards compatibility.
// =============================================================================

/// Separator used to embed capo data inside the tuning string.
const String _capoSeparator = '|capo:';

/// Parse a stored tuning value into its base tuning ID and optional capo fret.
///
/// Examples:
///   'standard_e'         → ('standard_e', null)
///   'standard_e|capo:3'  → ('standard_e', 3)
///   'drop_d|capo:7'      → ('drop_d', 7)
///   null                 → (null, null)
({String? tuningId, int? capoFret}) parseCapoTuning(String? raw) {
  if (raw == null || raw.isEmpty) return (tuningId: null, capoFret: null);

  final idx = raw.indexOf(_capoSeparator);
  if (idx == -1) return (tuningId: raw, capoFret: null);

  final base = raw.substring(0, idx);
  final fretStr = raw.substring(idx + _capoSeparator.length);
  final fret = int.tryParse(fretStr);

  // Only accept valid fret numbers 1-12
  if (fret != null && fret >= 1 && fret <= 12) {
    return (tuningId: base, capoFret: fret);
  }
  // Malformed suffix → treat as no capo
  return (tuningId: base, capoFret: null);
}

/// Compose a stored tuning string from a tuning ID and optional capo fret.
///
/// If [capoFret] is null or 0, returns [tuningId] unchanged (no suffix).
String? composeCapoTuning(String? tuningId, int? capoFret) {
  if (tuningId == null || tuningId.isEmpty) return tuningId;
  if (capoFret == null || capoFret < 1 || capoFret > 12) return tuningId;
  return '$tuningId$_capoSeparator$capoFret';
}

// Cache for custom tuning names to avoid repeated async lookups
final Map<String, String> _customTuningNameCache = {};

/// Initialize/refresh the custom tuning name cache
/// Call this when the app starts or when custom tunings change
Future<void> refreshCustomTuningCache() async {
  final service = CustomTuningService();
  final tunings = await service.getCustomTunings();
  _customTuningNameCache.clear();
  for (final tuning in tunings) {
    _customTuningNameCache[tuning.id] = tuning.name;
  }
}

/// Get the cached custom tuning name, or null if not in cache
String? getCachedCustomTuningName(String id) {
  return _customTuningNameCache[id];
}

/// Update cache with a single tuning (call after creating a new custom tuning)
void cacheCustomTuningName(String id, String name) {
  _customTuningNameCache[id] = name;
}

/// Remove a tuning from cache (call after deleting a custom tuning)
void removeCachedCustomTuning(String id) {
  _customTuningNameCache.remove(id);
}

// =============================================================================
// SHORT LABEL MAPPING
// Maps full tuning names to short badge labels
// =============================================================================

/// Get a short label for display on badges (3-12 chars ideal)
/// Falls back to input if no mapping found
///
/// For custom tunings, pass the custom name via [customName] parameter,
/// or it will look up from cache. Falls back to 'Custom' if not found.
///
/// If the tuning contains capo data (e.g. "standard_e|capo:3") the label
/// is formatted as "Standard • C3".  Songs without capo show just "Standard".
String tuningShortLabel(String? tuningName, {String? customName}) {
  if (tuningName == null || tuningName.isEmpty) return 'Standard';

  // Parse capo suffix before any other processing
  final parsed = parseCapoTuning(tuningName);
  final baseTuning = parsed.tuningId ?? tuningName;
  final capo = parsed.capoFret;

  // Normalize for lookup: trim whitespace
  final normalized = baseTuning.trim();

  // Check if it's a custom tuning ID (format: custom_<timestamp>)
  if (normalized.startsWith('custom_')) {
    // Use provided custom name, or look up from cache
    String base;
    if (customName != null && customName.isNotEmpty) {
      base = customName;
    } else {
      final cachedName = _customTuningNameCache[normalized];
      base = cachedName ?? 'Custom';
    }
    return capo != null ? '$base • C$capo' : base;
  }

  // Short label mapping
  const shortLabels = <String, String>{
    // Standard tunings (match id or name)
    'Standard (E)': 'Standard',
    'standard_e': 'Standard',
    'Standard': 'Standard',
    'standard': 'Standard', // Old enum value
    // Half-step down
    'Half Step Down (Eb)': 'Half-Step',
    'half_step_down': 'Half-Step',
    'half_step': 'Half-Step',
    'Eb Standard': 'Half-Step',
    'Half-Step Down': 'Half-Step',
    'Half-Step': 'Half-Step',

    // Full/Whole step down
    'Whole Step Down (D)': 'Full-Step',
    'whole_step_down': 'Full-Step',
    'full_step': 'Full-Step',
    'Full-Step Down': 'Full-Step',
    'Full-Step': 'Full-Step',

    // Drop tunings
    'Drop D': 'Drop D',
    'drop_d': 'Drop D',
    'Drop C': 'Drop C',
    'drop_c': 'Drop C',
    'Drop Db (C#)': 'Drop Db',
    'drop_db': 'Drop Db',
    'Drop B': 'Drop B',
    'drop_b': 'Drop B',
    'Drop A': 'Drop A',
    'drop_a': 'Drop A',

    // Standard variants
    'D Standard': 'D Standard',
    'd_standard': 'D Standard',
    'C Standard': 'C Standard',
    'c_standard': 'C Standard',
    'B Standard (Baritone)': 'B Standard',
    'B Standard': 'B Standard',
    'b_standard': 'B Standard',
    'A Standard': 'A Standard',
    'a_standard': 'A Standard',

    // Open tunings
    'Open G': 'Open G',
    'open_g': 'Open G',
    'Open D': 'Open D',
    'open_d': 'Open D',
    'Open E': 'Open E',
    'open_e': 'Open E',
    'Open A': 'Open A',
    'open_a': 'Open A',
    'Open C': 'Open C',
    'open_c': 'Open C',

    // Special tunings
    'DADGAD': 'DADGAD',
    'dadgad': 'DADGAD',
    'Nashville': 'Nashville',
    'nashville': 'Nashville',
    'Custom': 'Custom',
    'custom': 'Custom',
  };

  final baseLabel = shortLabels[normalized] ?? normalized;
  return capo != null ? '$baseLabel • C$capo' : baseLabel;
}

// =============================================================================
// BADGE COLOR MAPPING
// Hex fills from user specs
// =============================================================================

/// Get the badge background color for a tuning
/// Normalizes input and provides sensible default.
/// Capo suffix ("|capo:N") is stripped before lookup — colour is based
/// on the base tuning only.
Color tuningBadgeColor(String? tuningKey) {
  if (tuningKey == null || tuningKey.isEmpty) {
    return const Color(0xFF2563EB); // Default to Standard blue
  }

  // Strip capo suffix first so colour is always based on the base tuning
  final baseTuning = parseCapoTuning(tuningKey).tuningId ?? tuningKey;

  // Normalize: trim, lowercase for comparison
  final normalized = baseTuning.trim().toLowerCase();

  // Custom tunings get slate color
  if (normalized.startsWith('custom_')) {
    return const Color(0xFF64748B); // Slate for custom tunings
  }

  // Color mapping (case-insensitive keys)
  final colorMap = <String, Color>{
    // Standard
    'standard': const Color(0xFF2563EB),
    'standard (e)': const Color(0xFF2563EB),
    'standard_e': const Color(0xFF2563EB),

    // Half-Step
    'half-step': const Color(0xFFC026D3),
    'half step down (eb)': const Color(0xFFC026D3),
    'half_step_down': const Color(0xFFC026D3),
    'half_step': const Color(0xFFC026D3),
    'eb standard': const Color(0xFFC026D3),
    'half-step down': const Color(0xFFC026D3),

    // Drop D
    'drop d': const Color(0xFF65A30D),
    'drop_d': const Color(0xFF65A30D),

    // Full-Step
    'full-step': const Color(0xFFEA580C),
    'whole step down (d)': const Color(0xFFEA580C),
    'whole_step_down': const Color(0xFFEA580C),
    'full_step': const Color(0xFFEA580C),
    'full-step down': const Color(0xFFEA580C),

    // Drop C
    'drop c': const Color(0xFF06B6D4),
    'drop_c': const Color(0xFF06B6D4),

    // Drop Db
    'drop db': const Color(0xFF581C87),
    'drop db (c#)': const Color(0xFF581C87),
    'drop_db': const Color(0xFF581C87),

    // D Standard
    'd standard': const Color(0xFF1E40AF),
    'd_standard': const Color(0xFF1E40AF),

    // Drop B
    'drop b': const Color(0xFF14532D),
    'drop_b': const Color(0xFF14532D),

    // B Standard
    'b standard': const Color(0xFF312E81),
    'b standard (baritone)': const Color(0xFF312E81),
    'b_standard': const Color(0xFF312E81),

    // Drop A
    'drop a': const Color(0xFF065F46),
    'drop_a': const Color(0xFF065F46),

    // Open G
    'open g': const Color(0xFFF43F5E),
    'open_g': const Color(0xFFF43F5E),

    // Open D
    'open d': const Color(0xFFE11D48),
    'open_d': const Color(0xFFE11D48),

    // Open E
    'open e': const Color(0xFFBE123C),
    'open_e': const Color(0xFFBE123C),

    // Open A
    'open a': const Color(0xFF9F1239),
    'open_a': const Color(0xFF9F1239),

    // Open C
    'open c': const Color(0xFF881337),
    'open_c': const Color(0xFF881337),

    // C Standard
    'c standard': const Color(0xFF0891B2),
    'c_standard': const Color(0xFF0891B2),

    // A Standard
    'a standard': const Color(0xFF0D9488),
    'a_standard': const Color(0xFF0D9488),

    // Special tunings
    'dadgad': const Color(0xFFDB2777),
    'nashville': const Color(0xFFF59E0B),
    'custom': const Color(0xFF64748B),
  };

  return colorMap[normalized] ?? const Color(0xFF64748B); // Default slate
}

/// Get readable text color for a badge background
/// Returns white for dark backgrounds, dark for light backgrounds
/// Nashville is a special case: always use the app's dark background tone for
/// its label text.
Color tuningBadgeTextColor(Color backgroundColor, {String? tuningKey}) {
  if (tuningKey != null && tuningKey.isNotEmpty) {
    final baseTuning = parseCapoTuning(tuningKey).tuningId ?? tuningKey;
    if (baseTuning.trim().toLowerCase() == 'nashville') {
      return const Color(0xFF09090B);
    }
  }

  // Calculate relative luminance
  final luminance = backgroundColor.computeLuminance();
  // Use white text for dark backgrounds (luminance < 0.5)
  return luminance < 0.5 ? const Color(0xFFF5F5F5) : const Color(0xFF1F1F1F);
}

// =============================================================================
// DATABASE TUNING NORMALIZATION
// Maps app tuning IDs to database values.
//
// The database may use either:
// 1. OLD ENUM: tuning_type with values: 'standard', 'drop_d', 'half_step', 'full_step'
// 2. NEW TEXT: After migration 052, tuning is TEXT supporting all values
//
// This function maps app IDs to whichever format the database uses.
// =============================================================================

/// Maps new app tuning IDs to legacy enum values.
/// Returns the legacy enum value if one exists, otherwise returns the input.
///
/// Handles compound capo strings (e.g. "standard_e|capo:3"):
/// 1. Strips the capo suffix
/// 2. Maps the base tuning to the legacy enum
/// 3. Reattaches the capo suffix
///
/// IMPORTANT: The production database may still use the legacy enum:
///   - standard (not standard_e)
///   - half_step (not half_step_down)
///   - full_step (not whole_step_down)
///   - drop_d (unchanged)
///
/// Tunings not supported by the legacy enum (drop_c, open_g, etc.) will
/// cause database errors if migration 052 hasn't been applied.
String? tuningToDbEnum(String? tuningId) {
  if (tuningId == null || tuningId.isEmpty) return null;

  // Parse capo first so the mapping only sees the base tuning
  final parsed = parseCapoTuning(tuningId);
  final baseTuning = parsed.tuningId ?? tuningId;
  final capo = parsed.capoFret;

  // Map NEW app IDs → LEGACY enum values (for pre-migration databases)
  // This is the REVERSE of what the old code did
  const newToLegacy = <String, String>{
    // New app IDs → Old enum values
    'standard_e': 'standard',
    'half_step_down': 'half_step',
    'whole_step_down': 'full_step',
    // 'drop_d' stays as 'drop_d' - no change needed
  };

  // Map the base tuning, keeping as-is if no mapping exists
  final mappedBase = newToLegacy[baseTuning] ?? baseTuning;

  // Recompose with capo suffix if present
  return composeCapoTuning(mappedBase, capo);
}

/// Check if a tuning ID is supported by the legacy enum.
/// This helps diagnose issues when the database hasn't been migrated.
/// Handles compound capo strings by checking the base tuning only.
bool isLegacyEnumSupported(String? tuningId) {
  if (tuningId == null || tuningId.isEmpty) return true;
  final baseTuning = parseCapoTuning(tuningId).tuningId ?? tuningId;
  const legacyEnumValues = {'standard', 'drop_d', 'half_step', 'full_step'};
  const newIdsWithLegacyMapping = {
    'standard_e',
    'half_step_down',
    'whole_step_down',
  };
  return legacyEnumValues.contains(baseTuning) ||
      newIdsWithLegacyMapping.contains(baseTuning);
}

/// Get a user-friendly message if a tuning can't be saved due to legacy enum.
String? getLegacyEnumWarning(String? tuningId) {
  if (tuningId == null || isLegacyEnumSupported(tuningId)) return null;
  return 'This tuning requires a database update. '
      'Please contact support or run migration 052.';
}
