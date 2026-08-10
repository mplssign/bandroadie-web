/// Song model for search results (not tied to a setlist).
/// Maps to public.songs table.
///
/// This is the single source of truth for all song metadata.
/// All setlists reference the same Song entity by ID.
class Song {
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
  final String bandId;
  final String? spotifyId;
  final String? musicbrainzId;
  final String? notes;
  final String? youtubeLinks; // JSON string of YouTube links
  final String? lyrics; // JSON string of LyricsData

  /// Get the effective BPM to display (performance if set, else source)
  int? get effectiveBpm => performanceBpm ?? sourceBpm;

  /// Get the effective key to display (performance if set, else source)
  String? get effectiveMusicalKey => performanceMusicalKey ?? sourceMusicalKey;

  /// Get the effective tuning to display (performance if set, else source)
  String? get effectiveTuning => performanceTuning ?? sourceTuning;

  const Song({
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
    required this.bandId,
    this.spotifyId,
    this.musicbrainzId,
    this.notes,
    this.youtubeLinks,
    this.lyrics,
  });

  /// Duration as Dart Duration object
  Duration get duration => Duration(seconds: durationSeconds);

  /// Format duration as "m:ss" (e.g., "3:14", "4:11")
  String get formattedDuration {
    if (durationSeconds <= 0) return '—';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format BPM for display (e.g., "120 BPM" or "—")
  /// Uses effective BPM (performance if set, else source)
  String get formattedBpm {
    final bpmValue = effectiveBpm;
    if (bpmValue == null || bpmValue <= 0) return '—';
    return '$bpmValue BPM';
  }

  /// Create from Supabase songs table row
  factory Song.fromSupabase(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      // Old fields (kept for rollout, deprecated)
      bpm: json['bpm'] as int?,
      musicalKey: json['musical_key'] as String?,
      tuning: json['tuning'] as String?,
      // New dual-value fields
      sourceBpm: json['source_bpm'] as int?,
      performanceBpm: json['performance_bpm'] as int?,
      sourceMusicalKey: json['source_musical_key'] as String?,
      performanceMusicalKey: json['performance_musical_key'] as String?,
      sourceTuning: json['source_tuning'] as String?,
      performanceTuning: json['performance_tuning'] as String?,
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      albumArtwork: json['album_artwork'] as String?,
      bandId: json['band_id'] as String,
      spotifyId: json['spotify_id'] as String?,
      musicbrainzId: json['musicbrainz_id'] as String?,
      notes: json['notes'] as String?,
      youtubeLinks: json['youtube_links'] as String?,
      lyrics: json['lyrics'] as String?,
    );
  }
}
