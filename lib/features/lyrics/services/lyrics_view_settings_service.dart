import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// LYRICS VIEW SETTINGS
// Per-song, per-user view preferences (auto-scroll speed, font size).
// Stored locally in SharedPreferences.
//
// Key format: "lyrics_view_<songId>"
// ============================================================================

class LyricsViewSettings {
  final double fontSize;
  final double scrollSpeed; // pixels per second
  final bool autoScrollEnabled;

  const LyricsViewSettings({
    this.fontSize = 18.0,
    this.scrollSpeed = 30.0,
    this.autoScrollEnabled = false,
  });

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'scrollSpeed': scrollSpeed,
        'autoScrollEnabled': autoScrollEnabled,
      };

  factory LyricsViewSettings.fromJson(Map<String, dynamic> json) {
    return LyricsViewSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
      scrollSpeed: (json['scrollSpeed'] as num?)?.toDouble() ?? 30.0,
      autoScrollEnabled: json['autoScrollEnabled'] as bool? ?? false,
    );
  }

  LyricsViewSettings copyWith({
    double? fontSize,
    double? scrollSpeed,
    bool? autoScrollEnabled,
  }) {
    return LyricsViewSettings(
      fontSize: fontSize ?? this.fontSize,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
      autoScrollEnabled: autoScrollEnabled ?? this.autoScrollEnabled,
    );
  }
}

// ============================================================================
// LYRICS VIEW SETTINGS SERVICE
// Manages per-song view preferences persistence.
// ============================================================================

class LyricsViewSettingsService {
  static const String _keyPrefix = 'lyrics_view_';
  static const String _chordsVisibleKey = 'lyrics_view_chords_visible_global';

  /// Load saved view settings for a song
  static Future<LyricsViewSettings> load(String songId) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('$_keyPrefix$songId');
    if (jsonString == null) return const LyricsViewSettings();

    try {
      final data = json.decode(jsonString) as Map<String, dynamic>;
      return LyricsViewSettings.fromJson(data);
    } catch (_) {
      return const LyricsViewSettings();
    }
  }

  /// Save view settings for a song
  static Future<void> save(String songId, LyricsViewSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyPrefix$songId', json.encode(settings.toJson()));
  }

  /// Load global chords-visible preference (default: true)
  static Future<bool> loadChordsVisible() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chordsVisibleKey) ?? true;
  }

  /// Save global chords-visible preference
  static Future<void> saveChordsVisible(bool visible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chordsVisibleKey, visible);
  }
}
