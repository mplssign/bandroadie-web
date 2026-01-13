import 'dart:ui';

import '../../../app/theme/design_tokens.dart';
import '../tuning/tuning_helpers.dart';

/// Song model for display within a setlist.
/// Maps to public.songs joined with public.setlist_songs.
///
/// DATA MAPPING:
/// - songs.id -> id
/// - songs.title -> title
/// - songs.artist -> artist
/// - songs.bpm (or setlist_songs.bpm override) -> bpm
/// - songs.duration_seconds (or setlist_songs.duration_seconds override) -> durationSeconds
/// - songs.tuning (or setlist_songs.tuning override) -> tuning
/// - songs.album_artwork -> albumArtwork
/// - songs.notes -> notes
/// - setlist_songs.position -> position
class SetlistSong {
  final String id;
  final String title;
  final String artist;
  final int? bpm;
  final int durationSeconds;
  final String? tuning;
  final String? albumArtwork;
  final String? notes;
  final int position;

  /// Track whether values are overrides (for visual indicator)
  final bool hasBpmOverride;
  final bool hasDurationOverride;
  final bool hasTuningOverride;

  const SetlistSong({
    required this.id,
    required this.title,
    required this.artist,
    this.bpm,
    required this.durationSeconds,
    this.tuning,
    this.albumArtwork,
    this.notes,
    required this.position,
    this.hasBpmOverride = false,
    this.hasDurationOverride = false,
    this.hasTuningOverride = false,
  });

  /// Whether any override exists for this song in this setlist
  bool get hasAnyOverride =>
      hasBpmOverride || hasDurationOverride || hasTuningOverride;

  /// Duration as Dart Duration object
  Duration get duration => Duration(seconds: durationSeconds);

  /// Format duration as "m:ss" (e.g., "3:14", "4:11")
  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format BPM as "XXX BPM" or "- BPM" if null/invalid
  /// Uses shared formatBpm helper for consistency
  String get formattedBpm => formatBpm(bpm);

  /// Whether BPM is a placeholder (null or 0/invalid)
  bool get isBpmPlaceholder => bpm == null || bpm! <= 0;

  /// Create from Supabase join result
  /// Expected structure from query:
  /// {
  ///   song_id: string,
  ///   position: int,
  ///   bpm: int? (override),
  ///   tuning: string? (override),
  ///   duration_seconds: int? (override),
  ///   songs: {
  ///     id: string,
  ///     title: string,
  ///     artist: string,
  ///     bpm: int?,
  ///     duration_seconds: int,
  ///     tuning: string?,
  ///     album_artwork: string?,
  ///     notes: string?,
  ///   }
  /// }
  factory SetlistSong.fromSupabase(Map<String, dynamic> json) {
    final songData = json['songs'] as Map<String, dynamic>;

    // BPM, duration, and tuning are GLOBAL (stored on songs table)
    // Position is per-setlist (stored on setlist_songs table)
    return SetlistSong(
      id: songData['id'] as String,
      title: songData['title'] as String? ?? 'Untitled',
      artist: songData['artist'] as String? ?? 'Unknown Artist',
      bpm: songData['bpm'] as int?,
      durationSeconds: songData['duration_seconds'] as int? ?? 0,
      tuning: songData['tuning'] as String?,
      albumArtwork: songData['album_artwork'] as String?,
      notes: songData['notes'] as String?,
      position: json['position'] as int? ?? 0,
      // No more per-setlist overrides - values are global
      hasBpmOverride: false,
      hasDurationOverride: false,
      hasTuningOverride: false,
    );
  }

  /// Create a copy with updated fields
  /// To explicitly clear an optional field, pass the clear* parameter as true.
  SetlistSong copyWith({
    String? title,
    String? artist,
    int? position,
    int? bpm,
    bool clearBpm = false,
    int? durationSeconds,
    String? tuning,
    String? notes,
    bool clearNotes = false,
    bool? hasBpmOverride,
    bool? hasDurationOverride,
    bool? hasTuningOverride,
  }) {
    return SetlistSong(
      id: id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      bpm: clearBpm ? null : (bpm ?? this.bpm),
      durationSeconds: durationSeconds ?? this.durationSeconds,
      tuning: tuning ?? this.tuning,
      albumArtwork: albumArtwork,
      notes: clearNotes ? null : (notes ?? this.notes),
      position: position ?? this.position,
      hasBpmOverride: hasBpmOverride ?? this.hasBpmOverride,
      hasDurationOverride: hasDurationOverride ?? this.hasDurationOverride,
      hasTuningOverride: hasTuningOverride ?? this.hasTuningOverride,
    );
  }
}

/// Tuning type constants matching Figma design
/// Ordered from most common rock tunings to less common
class TuningType {
  // Standard tunings
  static const String standard = 'Standard';
  static const String dropD = 'Drop D';
  static const String dStandard = 'D Standard';
  static const String dropC = 'Drop C';
  static const String cStandard = 'C Standard';
  static const String dropB = 'Drop B';
  static const String bStandard = 'B Standard';
  static const String dropA = 'Drop A';
  static const String aStandard = 'A Standard';

  // Alternative tunings
  static const String halfStep = 'Eb Standard';

  // Open tunings
  static const String openG = 'Open G';
  static const String openD = 'Open D';
  static const String openE = 'Open E';
  static const String openA = 'Open A';

  // Special tunings
  static const String dadgad = 'DADGAD';
  static const String nashville = 'Nashville';
  static const String custom = 'Custom';

  /// Ordered list of all tunings for display
  static const List<String> orderedList = [
    standard,
    dropD,
    dStandard,
    dropC,
    cStandard,
    dropB,
    bStandard,
    dropA,
    aStandard,
    halfStep,
    openG,
    openD,
    openE,
    openA,
    dadgad,
    nashville,
    custom,
  ];

  /// Get color for a tuning type
  /// Delegates to shared tuningBadgeColor helper
  static Color getColor(String? tuning) => tuningBadgeColor(tuning);
}
