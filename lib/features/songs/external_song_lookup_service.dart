import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// EXTERNAL SONG LOOKUP SERVICE
// Searches Spotify and MusicBrainz for songs not in the Catalog.
// Uses Supabase Edge Functions to protect API secrets.
// ============================================================================

/// Result source for display purposes
enum SongSource { catalog, spotify, musicbrainz }

/// Unified search result from any source
class SongLookupResult {
  final String? id; // Only set for Catalog results
  final String title;
  final String artist;
  final int? bpm;
  final int? durationSeconds;
  final String? albumArtwork;
  final String? spotifyId;
  final String? musicbrainzId;
  final SongSource source;

  const SongLookupResult({
    this.id,
    required this.title,
    required this.artist,
    this.bpm,
    this.durationSeconds,
    this.albumArtwork,
    this.spotifyId,
    this.musicbrainzId,
    required this.source,
  });

  /// Duration as Dart Duration object
  Duration get duration => Duration(seconds: durationSeconds ?? 0);

  /// Format duration as "m:ss" (e.g., "3:14", "4:11")
  String get formattedDuration {
    if (durationSeconds == null || durationSeconds! <= 0) return '—';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format BPM for display (e.g., "120 BPM" or "—")
  String get formattedBpm {
    if (bpm == null || bpm! <= 0) return '—';
    return '$bpm BPM';
  }

  /// Whether this result is from the local Catalog
  bool get isFromCatalog => source == SongSource.catalog;

  /// Whether this result is from an external source (not catalog)
  bool get isExternal => source != SongSource.catalog;

  /// Display name for the source (generic - no service branding)
  String get sourceLabel {
    switch (source) {
      case SongSource.catalog:
        return 'In Catalog';
      case SongSource.spotify:
      case SongSource.musicbrainz:
        return 'Online';
    }
  }
}

/// Cache entry for external search results
class _CacheEntry {
  final List<SongLookupResult> results;
  final DateTime timestamp;

  _CacheEntry(this.results) : timestamp = DateTime.now();

  bool get isExpired => DateTime.now().difference(timestamp).inMinutes >= 5;
}

/// Service for external song lookups via Edge Functions
class ExternalSongLookupService {
  final SupabaseClient _supabase;

  // In-memory cache for search results (5 minute TTL)
  final Map<String, _CacheEntry> _cache = {};

  // Debounce timer
  Timer? _debounceTimer;

  // Track in-flight requests to avoid duplicates
  final Map<String, Future<List<SongLookupResult>>> _inFlightRequests = {};

  ExternalSongLookupService(this._supabase);

  /// Normalize query for cache key and comparison
  String _normalizeQuery(String query) {
    return query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Search external sources (Spotify, then MusicBrainz fallback)
  /// Returns cached results if available and not expired.
  ///
  /// Implements debouncing internally - call from onChanged without delay.
  Future<List<SongLookupResult>> searchExternalSongs(
    String query, {
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final normalizedQuery = _normalizeQuery(query);

    // Minimum query length
    if (normalizedQuery.length < 2) {
      return [];
    }

    // Check cache first
    if (!forceRefresh && _cache.containsKey(normalizedQuery)) {
      final entry = _cache[normalizedQuery]!;
      if (!entry.isExpired) {
        if (kDebugMode) {
          debugPrint('[ExternalSongLookup] Cache hit for "$normalizedQuery"');
        }
        return entry.results;
      }
      _cache.remove(normalizedQuery);
    }

    // Return in-flight request if exists
    if (_inFlightRequests.containsKey(normalizedQuery)) {
      if (kDebugMode) {
        debugPrint(
          '[ExternalSongLookup] Returning in-flight request for "$normalizedQuery"',
        );
      }
      return _inFlightRequests[normalizedQuery]!;
    }

    // Create the request
    final request = _performExternalSearch(normalizedQuery, limit);
    _inFlightRequests[normalizedQuery] = request;

    try {
      final results = await request;
      _cache[normalizedQuery] = _CacheEntry(results);
      return results;
    } finally {
      _inFlightRequests.remove(normalizedQuery);
    }
  }

  /// Perform the actual external search
  Future<List<SongLookupResult>> _performExternalSearch(
    String query,
    int limit,
  ) async {
    if (kDebugMode) {
      debugPrint('[ExternalSongLookup] Searching Spotify for "$query"');
    }

    try {
      // First try Spotify
      final spotifyResults = await _searchSpotify(query, limit);

      if (spotifyResults.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[ExternalSongLookup] Found ${spotifyResults.length} Spotify results',
          );
        }
        return spotifyResults;
      }

      // Fallback to MusicBrainz if Spotify returns nothing
      if (kDebugMode) {
        debugPrint('[ExternalSongLookup] Spotify empty, trying MusicBrainz');
      }
      return await _searchMusicBrainz(query, limit);
    } catch (e) {
      debugPrint('[ExternalSongLookup] Error: $e');

      // Try MusicBrainz as fallback on Spotify error
      try {
        return await _searchMusicBrainz(query, limit);
      } catch (e2) {
        debugPrint(
          '[ExternalSongLookup] MusicBrainz fallback also failed: $e2',
        );
        return [];
      }
    }
  }

  /// Search Spotify via Edge Function
  Future<List<SongLookupResult>> _searchSpotify(String query, int limit) async {
    final response = await _supabase.functions.invoke(
      'spotify_search',
      body: {'query': query, 'limit': limit},
    );

    if (response.status != 200) {
      throw Exception('Spotify search failed: ${response.status}');
    }

    final data = response.data;
    if (data == null || data['ok'] != true) {
      throw Exception(data?['error'] ?? 'Unknown Spotify error');
    }

    final tracks = (data['data'] as List?) ?? [];

    // Fetch BPM for each track in parallel (with concurrency limit)
    final results = <SongLookupResult>[];

    for (final track in tracks) {
      final spotifyId = track['spotify_id'] as String?;
      int? bpm;

      // Fetch BPM if we have a Spotify ID
      if (spotifyId != null) {
        bpm = await _fetchSpotifyBpm(spotifyId);
      }

      results.add(
        SongLookupResult(
          title: track['title'] as String? ?? 'Unknown',
          artist: track['artist'] as String? ?? 'Unknown Artist',
          spotifyId: spotifyId,
          durationSeconds: track['duration_seconds'] as int?,
          albumArtwork: track['album_artwork'] as String?,
          bpm: bpm,
          source: SongSource.spotify,
        ),
      );
    }

    return results;
  }

  /// Fetch BPM for a Spotify track
  Future<int?> _fetchSpotifyBpm(String spotifyId) async {
    try {
      final response = await _supabase.functions.invoke(
        'spotify_audio_features',
        body: {'spotify_id': spotifyId},
      );

      if (response.status != 200) {
        return null;
      }

      final data = response.data;
      if (data == null || data['ok'] != true) {
        return null;
      }

      return data['data']?['bpm'] as int?;
    } catch (e) {
      debugPrint('[ExternalSongLookup] BPM fetch failed for $spotifyId: $e');
      return null;
    }
  }

  /// Search MusicBrainz via Edge Function (fallback)
  Future<List<SongLookupResult>> _searchMusicBrainz(
    String query,
    int limit,
  ) async {
    final response = await _supabase.functions.invoke(
      'musicbrainz_search',
      body: {'query': query, 'limit': limit},
    );

    if (response.status != 200) {
      throw Exception('MusicBrainz search failed: ${response.status}');
    }

    final data = response.data;
    if (data == null || data['ok'] != true) {
      throw Exception(data?['error'] ?? 'Unknown MusicBrainz error');
    }

    final recordings = (data['data'] as List?) ?? [];

    return recordings.map<SongLookupResult>((recording) {
      return SongLookupResult(
        title: recording['title'] as String? ?? 'Unknown',
        artist: recording['artist'] as String? ?? 'Unknown Artist',
        musicbrainzId: recording['musicbrainz_id'] as String?,
        durationSeconds: recording['duration_seconds'] as int?,
        albumArtwork: null, // MusicBrainz doesn't provide artwork
        bpm: null, // MusicBrainz doesn't provide BPM
        source: SongSource.musicbrainz,
      );
    }).toList();
  }

  /// Cancel any pending debounced search
  void cancelPendingSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Clear the cache (e.g., on logout or band switch)
  void clearCache() {
    _cache.clear();
  }

  /// Dispose resources
  void dispose() {
    cancelPendingSearch();
  }
}
