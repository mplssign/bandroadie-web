import 'package:flutter/foundation.dart';

// ============================================================================
// INITIALS UTILITY
// Single source of truth for generating initials from names.
// Used by BandAvatar in both header and band switcher to ensure consistency.
// ============================================================================

/// Generates initials from a name string.
///
/// Rules:
/// - Trim whitespace, collapse multiple spaces
/// - Split by spaces and hyphens
/// - If multiple words: take first letter of each word
/// - If 1 word: take all characters (up to maxLetters if specified)
/// - Result is uppercased
///
/// [name] The name to generate initials from
/// [maxLetters] Maximum number of letters to return (default: 99 = no practical limit)
/// [fallback] Fallback initials if name is null or empty (default: 'BR')
String bandInitials(
  String? name, {
  int maxLetters = 99,
  String fallback = 'BR',
}) {
  if (name == null || name.trim().isEmpty) {
    if (kDebugMode) {
      debugPrint(
        '[initials] Name is null/empty, returning fallback: $fallback',
      );
    }
    return fallback;
  }

  // Trim and collapse multiple spaces
  final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');

  // Split by spaces and hyphens
  final words = trimmed.split(RegExp(r'[\s\-]+'));

  if (words.isEmpty || (words.length == 1 && words[0].isEmpty)) {
    if (kDebugMode) {
      debugPrint('[initials] No words found, returning fallback: $fallback');
    }
    return fallback;
  }

  String result;

  if (words.length >= 2) {
    // Multiple words: take first letter of each word (up to maxLetters)
    result = words.map((w) => w.isNotEmpty ? w[0] : '').join();
    // Apply maxLetters limit if set
    if (result.length > maxLetters) {
      result = result.substring(0, maxLetters);
    }
  } else {
    // 1 word: take first [maxLetters] chars
    final word = words[0];
    final charCount = word.length.clamp(0, maxLetters);
    result = word.substring(0, charCount);
  }

  final uppercased = result.toUpperCase();

  // Debug print disabled - was causing log spam on every rebuild
  // if (kDebugMode) {
  //   debugPrint('[initials] "$name" -> "$uppercased" (maxLetters=$maxLetters)');
  // }

  return uppercased;
}
