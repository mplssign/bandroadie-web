// Application-wide constants
//
// This file contains constants that are used across the app.
// Import this file to access shared constants.

// =============================================================================
// SUPPORT & CONTACT CONSTANTS
// =============================================================================

/// The official support email address for bug reports, feature requests,
/// and general inquiries. Used by:
///   - Bug report screen (client-side clipboard fallback)
///   - Edge function send-bug-report (must be kept in sync)
///   - Privacy policy contact section
const String kSupportEmail = 'hello@bandroadie.com';

// =============================================================================
// SETLIST CONSTANTS
// =============================================================================

/// The canonical name for the default Catalog setlist.
/// Every band has exactly one Catalog setlist that contains all songs.
/// This constant should be used everywhere instead of hardcoded strings.
const String kCatalogSetlistName = 'Catalog';

/// Legacy name that may exist in old data. Used for detection only.
const String _kLegacyCatalogName = 'All Songs';

/// Checks if a setlist name indicates it's the Catalog (or legacy "All Songs").
/// Use this for detection/matching, not for display.
bool isCatalogName(String name) {
  final lower = name.toLowerCase().trim();
  return lower == kCatalogSetlistName.toLowerCase() ||
      lower == _kLegacyCatalogName.toLowerCase();
}
