import 'dart:convert';

// ============================================================================
// LYRICS DATA MODEL
// Stores lyrics content with per-section formatting metadata.
//
// Designed for:
// - Simple block-level formatting (font size, weight, highlight color)
// - Future extensibility (chords, section labels, metronome sync)
// - JSON serialization for Supabase TEXT column storage
// ============================================================================

/// Highlight color presets for lyric sections.
/// Kept small and musician-friendly (verse, chorus, bridge, etc.)
///
/// [colorValue] is the background tint (20% opacity) used in the lyrics viewer.
/// [accentColorValue] is the vivid accent used for chip borders & icons.
enum LyricsHighlight {
  none('none', 'None', 0x00000000, 0xFF64748B),
  intro('intro', 'Intro', 0x3322C55E, 0xFF22C55E), // green
  verse('verse', 'Verse', 0x332563EB, 0xFF2563EB), // blue
  preChorus('pre_chorus', 'Pre-Chorus', 0x33EF4444, 0xFFEF4444), // red
  chorus('chorus', 'Chorus', 0x339333EA, 0xFF9333EA), // purple
  bridge('bridge', 'Bridge', 0x33F97316, 0xFFF97316), // orange
  outro('outro', 'Outro', 0x3322C55E, 0xFF22C55E); // green

  const LyricsHighlight(
    this.key,
    this.label,
    this.colorValue,
    this.accentColorValue,
  );

  final String key;
  final String label;
  final int colorValue;
  final int accentColorValue;

  /// Resolve from stored key string
  static LyricsHighlight fromKey(String? key) {
    if (key == null) return LyricsHighlight.none;
    return LyricsHighlight.values.firstWhere(
      (h) => h.key == key,
      orElse: () => LyricsHighlight.none,
    );
  }
}

/// A single block/section of lyrics with its formatting.
class LyricsBlock {
  final String text;
  final LyricsHighlight highlight;
  final double fontSize;
  final bool isBold;

  const LyricsBlock({
    required this.text,
    this.highlight = LyricsHighlight.none,
    this.fontSize = 16.0,
    this.isBold = false,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'highlight': highlight.key,
        'fontSize': fontSize,
        'isBold': isBold,
      };

  factory LyricsBlock.fromJson(Map<String, dynamic> json) {
    return LyricsBlock(
      text: json['text'] as String? ?? '',
      highlight: LyricsHighlight.fromKey(json['highlight'] as String?),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16.0,
      isBold: json['isBold'] as bool? ?? false,
    );
  }

  LyricsBlock copyWith({
    String? text,
    LyricsHighlight? highlight,
    double? fontSize,
    bool? isBold,
  }) {
    return LyricsBlock(
      text: text ?? this.text,
      highlight: highlight ?? this.highlight,
      fontSize: fontSize ?? this.fontSize,
      isBold: isBold ?? this.isBold,
    );
  }
}

/// Top-level lyrics data for a song.
/// Stores structured blocks + global defaults.
class LyricsData {
  final List<LyricsBlock> blocks;
  final double defaultFontSize;
  final bool defaultBold;

  const LyricsData({
    required this.blocks,
    this.defaultFontSize = 16.0,
    this.defaultBold = false,
  });

  /// Whether this lyrics data has any actual content
  bool get isEmpty =>
      blocks.isEmpty || blocks.every((b) => b.text.trim().isEmpty);

  bool get isNotEmpty => !isEmpty;

  /// Get all lyrics as plain text (blocks joined by double newline)
  String get plainText => blocks.map((b) => b.text).join('\n\n');

  /// Create from a single plain-text string (no formatting)
  factory LyricsData.fromPlainText(String text) {
    if (text.trim().isEmpty) {
      return const LyricsData(blocks: []);
    }
    // Split on double newlines to create blocks (sections)
    final sections = text.split(RegExp(r'\n\s*\n'));
    return LyricsData(
      blocks: sections.map((s) => LyricsBlock(text: s.trim())).toList(),
    );
  }

  /// Serialize to JSON string for database storage
  String toJsonString() {
    return json.encode({
      'blocks': blocks.map((b) => b.toJson()).toList(),
      'defaultFontSize': defaultFontSize,
      'defaultBold': defaultBold,
    });
  }

  /// Deserialize from JSON string
  factory LyricsData.fromJsonString(String? jsonString) {
    if (jsonString == null || jsonString.trim().isEmpty) {
      return const LyricsData(blocks: []);
    }

    try {
      final Map<String, dynamic> data =
          json.decode(jsonString) as Map<String, dynamic>;

      final blocksList = (data['blocks'] as List<dynamic>?)
              ?.map((b) => LyricsBlock.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [];

      return LyricsData(
        blocks: blocksList,
        defaultFontSize: (data['defaultFontSize'] as num?)?.toDouble() ?? 16.0,
        defaultBold: data['defaultBold'] as bool? ?? false,
      );
    } catch (_) {
      // Fallback: treat the entire string as plain text
      return LyricsData.fromPlainText(jsonString);
    }
  }

  LyricsData copyWith({
    List<LyricsBlock>? blocks,
    double? defaultFontSize,
    bool? defaultBold,
  }) {
    return LyricsData(
      blocks: blocks ?? this.blocks,
      defaultFontSize: defaultFontSize ?? this.defaultFontSize,
      defaultBold: defaultBold ?? this.defaultBold,
    );
  }
}
