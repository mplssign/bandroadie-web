/// Song model for search results (not tied to a setlist).
/// Maps to public.songs table.
class Song {
  final String id;
  final String title;
  final String artist;
  final int? bpm;
  final int durationSeconds;
  final String? tuning;
  final String? albumArtwork;
  final String bandId;
  final String? spotifyId;
  final String? musicbrainzId;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.bpm,
    required this.durationSeconds,
    this.tuning,
    this.albumArtwork,
    required this.bandId,
    this.spotifyId,
    this.musicbrainzId,
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
  String get formattedBpm {
    if (bpm == null || bpm! <= 0) return '—';
    return '$bpm BPM';
  }

  /// Create from Supabase songs table row
  factory Song.fromSupabase(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      bpm: json['bpm'] as int?,
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      tuning: json['tuning'] as String?,
      albumArtwork: json['album_artwork'] as String?,
      bandId: json['band_id'] as String,
      spotifyId: json['spotify_id'] as String?,
      musicbrainzId: json['musicbrainz_id'] as String?,
    );
  }
}
