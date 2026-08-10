import 'dart:ui';

import '../../../app/theme/design_tokens.dart';
import '../tuning/tuning_helpers.dart';

/// Song model for display within a setlist.
/// Maps to public.songs joined with public.setlist_songs.
///
/// All metadata is stored globally on the songs table (single source of truth).
/// The setlist_songs table only stores the song reference and position.
/// Edits to any field propagate to every setlist containing this song.
///
/// DATA MAPPING (all from songs table):
/// - songs.id -> id
/// - songs.title -> title
/// - songs.artist -> artist
/// - songs.bpm -> bpm (deprecated)
/// - songs.source_bpm -> sourceBpm (Phase 2.2)
/// - songs.performance_bpm -> performanceBpm (Phase 2.2)
/// - songs.duration_seconds -> durationSeconds
/// - songs.tuning -> tuning (deprecated)
/// - songs.source_tuning -> sourceTuning (Phase 2.2)
/// - songs.performance_tuning -> performanceTuning (Phase 2.2)
/// - songs.album_artwork -> albumArtwork
/// - songs.notes -> notes
/// - songs.youtube_links -> youtubeLinks
/// - songs.lyrics -> lyrics
/// - songs.musical_key -> musicalKey (deprecated)
/// - songs.source_musical_key -> sourceMusicalKey (Phase 2.2)
/// - songs.performance_musical_key -> performanceMusicalKey (Phase 2.2)
///
/// DATA MAPPING (from setlist_songs table):
/// - setlist_songs.position -> position
class SetlistSong {
  final String id;
  final String title;
  final String artist;

  // OLD single-value fields (deprecated in Phase 2.2, kept for backward compat during rollout)
  @Deprecated('Use sourceBpm/performanceBpm instead')
  final int? bpm;
  @Deprecated('Use sourceMusicalKey/performanceMusicalKey instead')
  final String? musicalKey;
  @Deprecated('Use sourceTuning/performanceTuning instead')
  final String? tuning;

  // NEW dual-value fields (Phase 2.2)
  final int? sourceBpm;
  final int? performanceBpm;
  final String? sourceMusicalKey;
  final String? performanceMusicalKey;
  final String? sourceTuning;
  final String? performanceTuning;

  final int durationSeconds;
  final String? albumArtwork;
  final String? notes;
  final String? youtubeLinks; // JSON string of YouTube links
  final String? lyrics; // JSON string of LyricsData
  final int position;

  /// Get the effective BPM to display (performance if set, else source)
  int? get effectiveBpm => performanceBpm ?? sourceBpm;

  /// Get the effective key to display (performance if set, else source)
  String? get effectiveMusicalKey => performanceMusicalKey ?? sourceMusicalKey;

  /// Get the effective tuning to display (performance if set, else source)
  String? get effectiveTuning => performanceTuning ?? sourceTuning;

  const SetlistSong({
    required this.id,
    required this.title,
    required this.artist,
    this.bpm,
    this.musicalKey,
    this.tuning,
    this.sourceBpm,
    this.performanceBpm,
    this.sourceMusicalKey,
    this.performanceMusicalKey,
    this.sourceTuning,
    this.performanceTuning,
    required this.durationSeconds,
    this.albumArtwork,
    this.notes,
    this.youtubeLinks,
    this.lyrics,
    required this.position,
  });

  /// Duration as Dart Duration object
  Duration get duration => Duration(seconds: durationSeconds);

  /// Format duration as "m:ss" (e.g., "3:14", "4:11")
  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format BPM as "XXX BPM" or "- BPM" if null/invalid
  /// Uses shared formatBpm helper for consistency (uses effective BPM)
  String get formattedBpm => formatBpm(effectiveBpm);

  /// Whether BPM is a placeholder (null or 0/invalid)
  bool get isBpmPlaceholder => effectiveBpm == null || effectiveBpm! <= 0;

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

    // All metadata is GLOBAL (stored on songs table)
    // Only position is per-setlist (stored on setlist_songs table)
    return SetlistSong(
      id: songData['id'] as String,
      title: songData['title'] as String? ?? 'Untitled',
      artist: songData['artist'] as String? ?? 'Unknown Artist',
      // Old fields (kept for rollout, deprecated)
      bpm: songData['bpm'] as int?,
      musicalKey: songData['musical_key'] as String?,
      tuning: songData['tuning'] as String?,
      // New dual-value fields
      sourceBpm: songData['source_bpm'] as int?,
      performanceBpm: songData['performance_bpm'] as int?,
      sourceMusicalKey: songData['source_musical_key'] as String?,
      performanceMusicalKey: songData['performance_musical_key'] as String?,
      sourceTuning: songData['source_tuning'] as String?,
      performanceTuning: songData['performance_tuning'] as String?,
      durationSeconds: songData['duration_seconds'] as int? ?? 0,
      albumArtwork: songData['album_artwork'] as String?,
      notes: songData['notes'] as String?,
      youtubeLinks: songData['youtube_links'] as String?,
      lyrics: songData['lyrics'] as String?,
      position: json['position'] as int? ?? 0,
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
    String? youtubeLinks,
    bool clearYoutubeLinks = false,
    String? lyrics,
    bool clearLyrics = false,
    String? musicalKey,
    bool clearMusicalKey = false,
    // Phase 2.2: Dual-value parameters
    int? sourceBpm,
    bool clearSourceBpm = false,
    int? performanceBpm,
    bool clearPerformanceBpm = false,
    String? sourceMusicalKey,
    bool clearSourceMusicalKey = false,
    String? performanceMusicalKey,
    bool clearPerformanceMusicalKey = false,
    String? sourceTuning,
    bool clearSourceTuning = false,
    String? performanceTuning,
    bool clearPerformanceTuning = false,
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
      youtubeLinks:
          clearYoutubeLinks ? null : (youtubeLinks ?? this.youtubeLinks),
      lyrics: clearLyrics ? null : (lyrics ?? this.lyrics),
      musicalKey: clearMusicalKey ? null : (musicalKey ?? this.musicalKey),
      // Phase 2.2: Dual-value fields with clear flag support
      sourceBpm: clearSourceBpm ? null : (sourceBpm ?? this.sourceBpm),
      performanceBpm:
          clearPerformanceBpm ? null : (performanceBpm ?? this.performanceBpm),
      sourceMusicalKey: clearSourceMusicalKey
          ? null
          : (sourceMusicalKey ?? this.sourceMusicalKey),
      performanceMusicalKey: clearPerformanceMusicalKey
          ? null
          : (performanceMusicalKey ?? this.performanceMusicalKey),
      sourceTuning:
          clearSourceTuning ? null : (sourceTuning ?? this.sourceTuning),
      performanceTuning: clearPerformanceTuning
          ? null
          : (performanceTuning ?? this.performanceTuning),
      position: position ?? this.position,
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
