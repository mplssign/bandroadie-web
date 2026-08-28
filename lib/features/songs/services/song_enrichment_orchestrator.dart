import 'package:flutter/foundation.dart';

import '../../setlists/models/song.dart';
import '../../setlists/setlist_repository.dart';
import '../external_song_lookup_service.dart';
import '../song_enrichment_service.dart';

// ============================================================================
// SONG ENRICHMENT ORCHESTRATOR
// Coordinates the full enrichment flow: fetch songs, call service, update DB
// ============================================================================

/// Result of enrichment for a single field.
enum EnrichmentFieldResult {
  notRequested, // field not checked in drawer
  updated, // API returned value, RPC succeeded
  notFound, // API returned 'none' confidence or empty search results
  unchanged, // already had a value (skip due to non-overwrite)
  error, // RPC or network failure
}

/// Per-song enrichment outcome for results UI.
class SongEnrichmentDetail {
  final String songId;
  final String title;
  final String artist;
  final EnrichmentFieldResult bpmResult;
  final EnrichmentFieldResult durationResult;
  final EnrichmentFieldResult keyResult;
  final int? currentBpm;
  final String? currentKey;
  final int? currentDuration;
  final int? enrichedBpm;
  final String? enrichedKey;
  final int? enrichedDuration;

  const SongEnrichmentDetail({
    required this.songId,
    required this.title,
    required this.artist,
    required this.bpmResult,
    required this.durationResult,
    required this.keyResult,
    this.currentBpm,
    this.currentKey,
    this.currentDuration,
    this.enrichedBpm,
    this.enrichedKey,
    this.enrichedDuration,
  });
}

/// Summary of enrichment orchestration.
class EnrichmentOrchestrationResult {
  final int total;
  final int enriched; // successfully updated
  final int notFound; // API returned 'none' confidence or no search results
  final int unchanged; // already had values
  final int errors; // RPC or network failures
  final List<SongEnrichmentDetail> details; // per-song outcomes for results UI

  const EnrichmentOrchestrationResult({
    required this.total,
    required this.enriched,
    required this.notFound,
    required this.unchanged,
    required this.errors,
    required this.details,
  });
}

/// Orchestrates enrichment for one or more songs.
class SongEnrichmentOrchestrator {
  final SetlistRepository _repository;
  final SongEnrichmentService _enrichmentService;
  final ExternalSongLookupService _lookupService;

  SongEnrichmentOrchestrator({
    required SetlistRepository repository,
    required SongEnrichmentService enrichmentService,
    required ExternalSongLookupService lookupService,
  })  : _repository = repository,
        _enrichmentService = enrichmentService,
        _lookupService = lookupService;

  /// Enrich songs for BPM, Duration, and/or Key.
  ///
  /// [songIds]: List of song IDs to enrich. Empty = all catalog songs.
  /// [enrichBpm]: Whether to enrich BPM (checked in drawer).
  /// [enrichDuration]: Whether to enrich Duration (checked in drawer).
  /// [enrichKey]: Whether to enrich Key (checked in drawer).
  /// [overwriteExisting]: Whether to overwrite existing values (default false).
  /// [onProgress]: Callback invoked after each song completes.
  ///
  /// Returns summary with per-song details for results overlay.
  Future<EnrichmentOrchestrationResult> enrichSongs({
    required String bandId,
    required List<String> songIds, // empty = all catalog songs
    required bool enrichBpm,
    required bool enrichDuration,
    required bool enrichKey,
    bool overwriteExisting = false,
    void Function(int completed, int total)? onProgress,
  }) async {
    // 1. Fetch song records
    final List<Song> allSongs = await _repository.fetchSongsForBand(bandId);
    final List<Song> songsToEnrich = songIds.isEmpty
        ? allSongs
        : allSongs.where((s) => songIds.contains(s.id)).toList();

    if (songsToEnrich.isEmpty) {
      return const EnrichmentOrchestrationResult(
        total: 0,
        enriched: 0,
        notFound: 0,
        unchanged: 0,
        errors: 0,
        details: [],
      );
    }

    // 2. Filter: skip songs where all requested fields are already filled
    final songsNeedingEnrichment = songsToEnrich.where((song) {
      final needsBpm = enrichBpm && (overwriteExisting || song.bpm == null);
      final needsDuration =
          enrichDuration && (overwriteExisting || song.durationSeconds == 0);
      final needsKey =
          enrichKey && (overwriteExisting || song.musicalKey == null);
      return needsBpm || needsDuration || needsKey;
    }).toList();

    debugPrint(
      '[SongEnrichmentOrchestrator] Enriching ${songsNeedingEnrichment.length} of ${songsToEnrich.length} songs',
    );

    // 3. Process each song
    final details = <SongEnrichmentDetail>[];
    int enrichedCount = 0;
    int notFoundCount = 0;
    int unchangedCount = 0;
    int errorCount = 0;

    for (var i = 0; i < songsToEnrich.length; i++) {
      final song = songsToEnrich[i];

      // Check if this song needs enrichment
      final needsBpm = enrichBpm && (overwriteExisting || song.bpm == null);
      final needsDuration =
          enrichDuration && (overwriteExisting || song.durationSeconds == 0);
      final needsKey =
          enrichKey && (overwriteExisting || song.musicalKey == null);

      if (!needsBpm && !needsDuration && !needsKey) {
        // All requested fields already filled
        details.add(SongEnrichmentDetail(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          bpmResult: enrichBpm
              ? EnrichmentFieldResult.unchanged
              : EnrichmentFieldResult.notRequested,
          durationResult: enrichDuration
              ? EnrichmentFieldResult.unchanged
              : EnrichmentFieldResult.notRequested,
          keyResult: enrichKey
              ? EnrichmentFieldResult.unchanged
              : EnrichmentFieldResult.notRequested,
        ));
        unchangedCount++;
        if (onProgress != null) onProgress(i + 1, songsToEnrich.length);
        continue;
      }

      // Fetch enrichment data
      int? fetchedBpm;
      int? fetchedDuration;
      String? fetchedKey;
      bool bpmNotFound = false;
      bool durationNotFound = false;
      bool keyNotFound = false;
      bool bpmLookupError = false;
      bool keyLookupError = false;
      bool durationLookupError = false;

      // a. If BPM or Key requested: Call SongEnrichmentService
      if (needsBpm || needsKey) {
        try {
          final enrichmentResult = await _enrichmentService.lookup(
            title: song.title,
            artist: song.artist,
            durationSeconds:
                song.durationSeconds > 0 ? song.durationSeconds : null,
          );

          if (enrichmentResult.confidence == 'none') {
            if (needsBpm) bpmNotFound = true;
            if (needsKey) keyNotFound = true;
          } else {
            if (needsBpm) fetchedBpm = enrichmentResult.bpm;
            if (needsKey) fetchedKey = enrichmentResult.musicalKey;
          }
        } catch (e) {
          debugPrint(
            '[SongEnrichmentOrchestrator] BPM/Key lookup error for "${song.title}": $e',
          );
          if (needsBpm) bpmLookupError = true;
          if (needsKey) keyLookupError = true;
        }
      }

      // b. If Duration requested: Call ExternalSongLookupService
      if (needsDuration) {
        try {
          final query = '${song.title} ${song.artist}';
          final groupedResults =
              await _lookupService.searchExternalSongs(query);
          final bestResult = groupedResults.bestMatch;

          if (bestResult == null || bestResult.durationSeconds == null) {
            durationNotFound = true;
          } else {
            fetchedDuration = bestResult.durationSeconds;
          }
        } catch (e) {
          debugPrint(
            '[SongEnrichmentOrchestrator] Duration lookup error for "${song.title}": $e',
          );
          durationLookupError = true;
        }
      }

      // c. Merge results and update song via RPC for whichever fields resolved.
      final updateMap = <String, dynamic>{};
      if (fetchedBpm != null) updateMap['bpm'] = fetchedBpm;
      if (fetchedDuration != null) {
        updateMap['durationSeconds'] = fetchedDuration;
      }
      if (fetchedKey != null) updateMap['musicalKey'] = fetchedKey;

      // Call RPC if we have any update
      bool rpcSuccess = false;
      bool rpcFailed = false;
      if (updateMap.isNotEmpty) {
        try {
          final result = await _repository.enrichSongs(
            bandId: bandId,
            updates: {song.id: updateMap},
          );
          rpcSuccess = result[song.id] ?? false;
          rpcFailed = !rpcSuccess;
        } catch (e) {
          debugPrint(
            '[SongEnrichmentOrchestrator] RPC error for "${song.title}": $e',
          );
          rpcFailed = true;
        }
      }

      // Determine per-field results
      final bpmResult = !enrichBpm
          ? EnrichmentFieldResult.notRequested
          : !needsBpm
              ? EnrichmentFieldResult.unchanged
              : bpmLookupError
                  ? EnrichmentFieldResult.error
                  : bpmNotFound || fetchedBpm == null
                      ? EnrichmentFieldResult.notFound
                      : rpcFailed
                          ? EnrichmentFieldResult.error
                          : EnrichmentFieldResult.updated;

      final durationResult = !enrichDuration
          ? EnrichmentFieldResult.notRequested
          : !needsDuration
              ? EnrichmentFieldResult.unchanged
              : durationLookupError
                  ? EnrichmentFieldResult.error
                  : durationNotFound || fetchedDuration == null
                      ? EnrichmentFieldResult.notFound
                      : rpcFailed
                          ? EnrichmentFieldResult.error
                          : EnrichmentFieldResult.updated;

      final keyResult = !enrichKey
          ? EnrichmentFieldResult.notRequested
          : !needsKey
              ? EnrichmentFieldResult.unchanged
              : keyLookupError
                  ? EnrichmentFieldResult.error
                  : keyNotFound || fetchedKey == null
                      ? EnrichmentFieldResult.notFound
                      : rpcFailed
                          ? EnrichmentFieldResult.error
                          : EnrichmentFieldResult.updated;

      details.add(SongEnrichmentDetail(
        songId: song.id,
        title: song.title,
        artist: song.artist,
        bpmResult: bpmResult,
        durationResult: durationResult,
        keyResult: keyResult,
      ));

      // Update counts, allowing partial success + partial failures in one song.
      final hasUpdated = bpmResult == EnrichmentFieldResult.updated ||
          durationResult == EnrichmentFieldResult.updated ||
          keyResult == EnrichmentFieldResult.updated;
      final hasNotFound = bpmResult == EnrichmentFieldResult.notFound ||
          durationResult == EnrichmentFieldResult.notFound ||
          keyResult == EnrichmentFieldResult.notFound;
      final hasError = bpmResult == EnrichmentFieldResult.error ||
          durationResult == EnrichmentFieldResult.error ||
          keyResult == EnrichmentFieldResult.error;

      if (hasUpdated) {
        enrichedCount++;
      }
      if (hasError) {
        errorCount++;
      }
      if (!hasUpdated && !hasError && hasNotFound) {
        notFoundCount++;
      }
      if (!hasUpdated && !hasError && !hasNotFound) {
        unchangedCount++;
      }

      // Report progress
      if (onProgress != null) {
        onProgress(i + 1, songsToEnrich.length);
      }
    }

    return EnrichmentOrchestrationResult(
      total: songsToEnrich.length,
      enriched: enrichedCount,
      notFound: notFoundCount,
      unchanged: unchangedCount,
      errors: errorCount,
      details: details,
    );
  }
}
