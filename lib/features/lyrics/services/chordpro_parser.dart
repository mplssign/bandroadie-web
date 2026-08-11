/// ChordPro parser for extracting chord annotations from lyrics text.
///
/// ChordPro format uses [ChordName] syntax to annotate chords inline with lyrics.
/// Example: "[G]Hello [C]world" → Chord "G" at position 0, "C" at position 6

/// Parsed chord annotation with position metadata
class ChordAnnotation {
  /// Chord name (e.g., "Am", "C", "G7")
  final String chord;

  /// Character offset in line where chord applies (before bracket removal)
  final int position;

  const ChordAnnotation({
    required this.chord,
    required this.position,
  });

  @override
  String toString() => 'ChordAnnotation(chord: $chord, position: $position)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordAnnotation &&
          runtimeType == other.runtimeType &&
          chord == other.chord &&
          position == other.position;

  @override
  int get hashCode => chord.hashCode ^ position.hashCode;
}

/// Parsed line with chords extracted
class ParsedLyricsLine {
  /// Lyrics text with [Chord] removed
  final String text;

  /// Chords in order of appearance
  final List<ChordAnnotation> chords;

  const ParsedLyricsLine({
    required this.text,
    required this.chords,
  });

  /// True if line has no text and no chords (blank line)
  bool get isEmpty => text.trim().isEmpty && chords.isEmpty;

  /// True if line has chord annotations
  bool get hasChords => chords.isNotEmpty;

  @override
  String toString() =>
      'ParsedLyricsLine(text: "$text", chords: [${chords.join(", ")}])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedLyricsLine &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          _listEquals(chords, other.chords);

  @override
  int get hashCode => text.hashCode ^ chords.hashCode;

  bool _listEquals(List<ChordAnnotation> a, List<ChordAnnotation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Parse ChordPro plain text into structured lines
class ChordProParser {
  ChordProParser._();

  /// Regex to match chord annotations: [ChordName]
  static final _chordRegex = RegExp(r'\[([^\]]+)\]');

  /// Parse full lyrics text into lines with chord annotations
  ///
  /// Returns list of [ParsedLyricsLine], one per line in input text.
  /// Chord positions are tracked before bracket removal for alignment.
  ///
  /// Edge cases handled:
  /// - Empty lines → return empty [ParsedLyricsLine]
  /// - No chords → return line with empty chords list
  /// - Malformed brackets (e.g., "[Am" without closing) → treated as literal text
  static List<ParsedLyricsLine> parse(String lyricsText) {
    if (lyricsText.trim().isEmpty) {
      return [];
    }

    final lines = lyricsText.split('\n');
    final result = <ParsedLyricsLine>[];

    for (final line in lines) {
      result.add(_parseLine(line));
    }

    return result;
  }

  /// Parse a single line, extracting chords and their positions
  static ParsedLyricsLine _parseLine(String line) {
    final chords = <ChordAnnotation>[];
    final matches = _chordRegex.allMatches(line);

    if (matches.isEmpty) {
      // No chords in line, return as-is
      return ParsedLyricsLine(text: line, chords: chords);
    }

    // Track position offset as we remove brackets
    var textWithoutChords = line;
    var offsetAccumulator = 0;

    for (final match in matches) {
      final chordName = match.group(1)!;
      final originalPosition = match.start - offsetAccumulator;

      chords.add(ChordAnnotation(
        chord: chordName,
        position: originalPosition,
      ));

      // Update offset for next iteration
      offsetAccumulator += match.group(0)!.length;
    }

    // Remove all chord annotations from text
    textWithoutChords = line.replaceAll(_chordRegex, '');

    return ParsedLyricsLine(
      text: textWithoutChords,
      chords: chords,
    );
  }

  /// Extract section directives (e.g., {start_of_chorus})
  ///
  /// Returns list of (directive, lineIndex) pairs.
  /// Phase 2.4: Not used in UI, but parse for future extensibility.
  ///
  /// Example directives:
  /// - {start_of_chorus}
  /// - {end_of_chorus}
  /// - {start_of_verse}
  /// - {comment: This is a note}
  static List<(String directive, int lineIndex)> extractDirectives(
      String lyricsText) {
    final directiveRegex = RegExp(r'\{([^}]+)\}');
    final lines = lyricsText.split('\n');
    final directives = <(String, int)>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final matches = directiveRegex.allMatches(line);

      for (final match in matches) {
        final directive = match.group(1)!;
        directives.add((directive, i));
      }
    }

    return directives;
  }
}
