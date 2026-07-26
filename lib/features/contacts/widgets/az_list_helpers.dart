// ============================================================================
// A-Z LIST HELPERS
// Pure grouping/flat-index/nearest-letter logic shared by Venues, Band
// Members, and Contacts A-Z listings.
// ============================================================================

/// Groups [items] by the first character of the string returned by [nameOf],
/// bucketing non-A-Z characters (and empty names) into '#'. Result is
/// ordered A-Z first, then '#' last.
Map<String, List<T>> groupByLetter<T>(
  List<T> items,
  String Function(T) nameOf,
) {
  final Map<String, List<T>> grouped = {};
  for (final item in items) {
    final name = nameOf(item);
    final firstChar = name.isEmpty ? '#' : name[0].toUpperCase();
    final letter = RegExp(r'^[A-Z]$').hasMatch(firstChar) ? firstChar : '#';
    grouped.putIfAbsent(letter, () => []).add(item);
  }
  return Map.fromEntries(
    grouped.entries.toList()
      ..sort((a, b) {
        if (a.key == '#' && b.key != '#') return 1;
        if (a.key != '#' && b.key == '#') return -1;
        return a.key.compareTo(b.key);
      }),
  );
}

/// Returns the flat item index of [targetLetter]'s section header within
/// [grouped], walking the ordered map and summing `1 (header) + items.length`
/// per prior section.
int flatIndexForSection(String targetLetter, Map<String, List> grouped) {
  int currentIndex = 0;

  for (final key in grouped.keys) {
    if (key == targetLetter) {
      return currentIndex;
    }
    currentIndex += 1 + grouped[key]!.length;
  }

  return 0;
}

/// Resolves [letter] to the nearest populated section in [grouped]: itself
/// if populated, else the first key `>= letter` (or '#'), else the last key.
String resolveTargetLetter(String letter, Map<String, List> grouped) {
  if (grouped.containsKey(letter)) {
    return letter;
  }

  String? nearestLetter;
  for (final key in grouped.keys) {
    if (key.compareTo(letter) >= 0 || key == '#') {
      nearestLetter = key;
      break;
    }
  }
  nearestLetter ??= grouped.keys.last;
  return nearestLetter;
}
