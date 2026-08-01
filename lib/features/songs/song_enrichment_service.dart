import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// SONG ENRICHMENT SERVICE
// Fetches BPM + musical key for a new song via the getsongbpm_lookup Edge
// Function. Mirrors ExternalSongLookupService's shape — plain class wrapping
// supabase.functions.invoke, no state management dependency.
// ============================================================================

/// Result of a BPM/key enrichment lookup.
class SongEnrichmentResult {
  final int? bpm;
  final String? musicalKey; // normalized to the app's 24-key set, or null
  final String confidence; // 'medium' | 'none'

  const SongEnrichmentResult({
    this.bpm,
    this.musicalKey,
    required this.confidence,
  });

  factory SongEnrichmentResult.notFound() =>
      const SongEnrichmentResult(confidence: 'none');
}

/// Input for batch enrichment — one song's current state.
class EnrichmentSongInput {
  final String id;
  final String title;
  final String artist;
  final int? currentBpm;
  final int? currentDuration;
  final String? currentKey;

  const EnrichmentSongInput({
    required this.id,
    required this.title,
    required this.artist,
    this.currentBpm,
    this.currentDuration,
    this.currentKey,
  });
}

/// Result of batch enrichment for a single song.
class SongEnrichmentBatchResult {
  final String songId;
  final String title;
  final String artist;
  final SongEnrichmentResult result;

  const SongEnrichmentBatchResult({
    required this.songId,
    required this.title,
    required this.artist,
    required this.result,
  });
}

/// Service for fetching BPM/key enrichment via the getsongbpm_lookup Edge Function.
class SongEnrichmentService {
  final SupabaseClient _supabase;

  SongEnrichmentService(this._supabase);

  /// Look up BPM/key for a song by title+artist.
  ///
  /// Never throws — any failure (network, non-2xx, malformed response)
  /// returns [SongEnrichmentResult.notFound]. Callers should treat this as a
  /// best-effort convenience fetch, not a dependency for saving a song.
  Future<SongEnrichmentResult> lookup({
    required String title,
    required String artist,
    int? durationSeconds,
    String?
        isrc, // accepted for forward-compat; not populated by any caller today
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'getsongbpm_lookup',
        body: {
          'title': title,
          'artist': artist,
          if (durationSeconds != null) 'duration_seconds': durationSeconds,
          if (isrc != null) 'isrc': isrc,
        },
      );

      if (response.status != 200) {
        return SongEnrichmentResult.notFound();
      }

      final data = response.data;
      if (data == null || data['ok'] != true || data['data'] == null) {
        return SongEnrichmentResult.notFound();
      }

      final result = data['data'] as Map;
      return SongEnrichmentResult(
        bpm: result['bpm'] as int?,
        musicalKey: result['musicalKey'] as String?,
        confidence: result['confidence'] as String? ?? 'none',
      );
    } catch (e) {
      debugPrint('[SongEnrichmentService] Lookup failed (non-fatal): $e');
      return SongEnrichmentResult.notFound();
    }
  }

  /// Enrich multiple songs in batch for BPM and Key.
  ///
  /// For each song, calls GetSongBPM and returns results.
  /// Never throws — failed lookups return 'none' confidence.
  ///
  /// Progress callback is invoked after each song completes.
  /// NOTE: This handles BPM/Key only. Duration uses separate ExternalSongLookupService.
  ///
  /// Processing is sequential to avoid overwhelming the GetSongBPM API
  /// (3,000 requests/hour limit, sufficient for typical catalog sizes).
  Future<List<SongEnrichmentBatchResult>> enrichBatch({
    required List<EnrichmentSongInput> songs,
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <SongEnrichmentBatchResult>[];
    final total = songs.length;

    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      final result = await lookup(
        title: song.title,
        artist: song.artist,
        durationSeconds: song.currentDuration,
      );

      results.add(SongEnrichmentBatchResult(
        songId: song.id,
        title: song.title,
        artist: song.artist,
        result: result,
      ));

      // Report progress
      if (onProgress != null) {
        onProgress(i + 1, total);
      }
    }

    return results;
  }
}
