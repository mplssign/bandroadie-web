import 'package:flutter/material.dart';

// ============================================================================
// TUNING HELPERS
// Centralized tuning utilities for short labels and badge colors.
//
// USAGE:
// - tuningShortLabel(option) → badge-friendly label
// - tuningBadgeColor(tuningName) → Color for badge fill
// - tuningBadgeTextColor(Color) → readable text color for badge
// ============================================================================

// =============================================================================
// SHORT LABEL MAPPING
// Maps full tuning names to short badge labels
// =============================================================================

/// Get a short label for display on badges (3-12 chars ideal)
/// Falls back to input if no mapping found
String tuningShortLabel(String? tuningName) {
  if (tuningName == null || tuningName.isEmpty) return 'Standard';

  // Normalize for lookup: trim whitespace
  final normalized = tuningName.trim();

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

  return shortLabels[normalized] ?? normalized;
}

// =============================================================================
// BADGE COLOR MAPPING
// Hex fills from user specs
// =============================================================================

/// Get the badge background color for a tuning
/// Normalizes input and provides sensible default
Color tuningBadgeColor(String? tuningKey) {
  if (tuningKey == null || tuningKey.isEmpty) {
    return const Color(0xFF2563EB); // Default to Standard blue
  }

  // Normalize: trim, lowercase for comparison
  final normalized = tuningKey.trim().toLowerCase();

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
Color tuningBadgeTextColor(Color backgroundColor) {
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

  // Map NEW app IDs → LEGACY enum values (for pre-migration databases)
  // This is the REVERSE of what the old code did
  const newToLegacy = <String, String>{
    // New app IDs → Old enum values
    'standard_e': 'standard',
    'half_step_down': 'half_step',
    'whole_step_down': 'full_step',
    // 'drop_d' stays as 'drop_d' - no change needed
  };

  // If input matches a new ID, return the legacy enum value
  if (newToLegacy.containsKey(tuningId)) {
    return newToLegacy[tuningId];
  }

  // Already a legacy value or unsupported by legacy enum
  // Return as-is and let the database reject if it's incompatible
  return tuningId;
}

/// Check if a tuning ID is supported by the legacy enum.
/// This helps diagnose issues when the database hasn't been migrated.
bool isLegacyEnumSupported(String? tuningId) {
  if (tuningId == null || tuningId.isEmpty) return true;
  const legacyEnumValues = {'standard', 'drop_d', 'half_step', 'full_step'};
  const newIdsWithLegacyMapping = {
    'standard_e',
    'half_step_down',
    'whole_step_down',
  };
  return legacyEnumValues.contains(tuningId) ||
      newIdsWithLegacyMapping.contains(tuningId);
}

/// Get a user-friendly message if a tuning can't be saved due to legacy enum.
String? getLegacyEnumWarning(String? tuningId) {
  if (tuningId == null || isLegacyEnumSupported(tuningId)) return null;
  return 'This tuning requires a database update. '
      'Please contact support or run migration 052.';
}
