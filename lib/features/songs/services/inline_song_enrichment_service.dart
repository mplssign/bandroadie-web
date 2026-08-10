import 'package:flutter/foundation.dart';

import '../song_enrichment_service.dart';

/// Result of inline song enrichment for single-song auto mode
class InlineEnrichmentResult {
  final int? bpm;
  final int? durationSeconds;
  final String? musicalKey;

  const InlineEnrichmentResult({
    this.bpm,
    this.durationSeconds,
    this.musicalKey,
  });

  bool get hasAnyData =>
      bpm != null || durationSeconds != null || musicalKey != null;
}

/// Service for enriching individual songs inline (used by "auto" mode)
class InlineSongEnrichmentService {
  final SongEnrichmentService _enrichmentService;

  InlineSongEnrichmentService(this._enrichmentService);

  /// Enrich a single song with BPM and Musical Key
  ///
  /// Returns enriched metadata or null for fields not found.
  /// Does not throw — handles errors gracefully and returns partial results.
  /// Duration is passed through from the source (not enriched separately).
  Future<InlineEnrichmentResult> enrichSong({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    try {
      // Call enrichment service
      final result = await _enrichmentService.lookup(
        title: title,
        artist: artist,
        durationSeconds: durationSeconds,
      );

      // Log not-found cases for debugging
      if (result.bpm == null) {
        debugPrint('[InlineEnrichment] BPM not found for "$title" by $artist');
      }
      if (result.musicalKey == null) {
        debugPrint('[InlineEnrichment] Key not found for "$title" by $artist');
      }

      return InlineEnrichmentResult(
        bpm: result.bpm,
        durationSeconds: durationSeconds, // pass through from source
        musicalKey: result.musicalKey,
      );
    } catch (e) {
      debugPrint('[InlineEnrichment] Failed to enrich "$title": $e');
      // Return empty result on error (don't block song creation)
      return InlineEnrichmentResult(
        durationSeconds: durationSeconds, // preserve duration even on error
      );
    }
  }
}
