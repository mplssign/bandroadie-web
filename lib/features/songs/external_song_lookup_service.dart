import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================================
// EXTERNAL SONG LOOKUP SERVICE
// Searches iTunes and MusicBrainz for songs not in the Catalog.
// iTunes Search API is free and requires no authentication.
// MusicBrainz Edge Function is the fallback.
// ============================================================================

/// Result source for display purposes
enum SongSource { catalog, itunes, spotify, musicbrainz }

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
  final int? popularity; // 0-100, from Spotify or MusicBrainz score

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
    this.popularity,
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
      case SongSource.itunes:
      case SongSource.spotify:
      case SongSource.musicbrainz:
        return 'Online';
    }
  }
}

/// Grouped search results split by match type
class GroupedSongResults {
  final List<SongLookupResult> songs;
  final List<SongLookupResult> artists;
  final List<SongLookupResult> _otherRanked;

  const GroupedSongResults({
    required this.songs,
    required this.artists,
    required List<SongLookupResult> otherRanked,
  }) : _otherRanked = otherRanked;

  SongLookupResult? get bestMatch => songs.isNotEmpty
      ? songs.first
      : artists.isNotEmpty
          ? artists.first
          : _otherRanked.isNotEmpty
              ? _otherRanked.first
              : null;
}

/// Cache entry for external search results
class _CacheEntry {
  final GroupedSongResults results;
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
  final Map<String, Future<GroupedSongResults>> _inFlightRequests = {};

  ExternalSongLookupService(this._supabase);

  /// Normalize query for cache key and comparison
  String _normalizeQuery(String query) {
    return query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Search external sources (Spotify, then MusicBrainz fallback)
  /// Returns cached results if available and not expired.
  ///
  /// Implements debouncing internally - call from onChanged without delay.
  Future<GroupedSongResults> searchExternalSongs(
    String query, {
    int songsLimit = 6,
    int artistsLimit = 6,
    bool forceRefresh = false,
  }) async {
    final normalizedQuery = _normalizeQuery(query);
    final cacheKey = '$normalizedQuery-$songsLimit-$artistsLimit';

    // Minimum query length
    if (normalizedQuery.length < 2) {
      return const GroupedSongResults(
        songs: [],
        artists: [],
        otherRanked: [],
      );
    }

    // Check cache first
    if (!forceRefresh && _cache.containsKey(cacheKey)) {
      final entry = _cache[cacheKey]!;
      if (!entry.isExpired) {
        if (kDebugMode) {
          debugPrint('[ExternalSongLookup] Cache hit for "$cacheKey"');
        }
        return entry.results;
      }
      _cache.remove(cacheKey);
    }

    // Return in-flight request if exists
    if (_inFlightRequests.containsKey(cacheKey)) {
      if (kDebugMode) {
        debugPrint(
          '[ExternalSongLookup] Returning in-flight request for "$cacheKey"',
        );
      }
      return _inFlightRequests[cacheKey]!;
    }

    // Create the request - CRITICAL: Pass normalizedQuery (the search text), not cacheKey
    final request = _performExternalSearch(
      normalizedQuery,
      songsLimit: songsLimit,
      artistsLimit: artistsLimit,
    );
    _inFlightRequests[cacheKey] = request;

    try {
      final results = await request;
      _cache[cacheKey] = _CacheEntry(results);
      return results;
    } finally {
      _inFlightRequests.remove(cacheKey);
    }
  }

  /// Perform the actual external search.
  /// Fetches extra results from the API so ranking has a larger pool,
  /// then returns only the top [limit] after scoring.
  Future<GroupedSongResults> _performExternalSearch(
    String query, {
    required int songsLimit,
    required int artistsLimit,
  }) async {
    // Fetch more than needed so ranking can surface the best results
    final fetchLimit = ((songsLimit + artistsLimit) * 3).clamp(10, 50);

    if (kDebugMode) {
      debugPrint(
          '[ExternalSongLookup] Searching iTunes for "$query" (fetch $fetchLimit, return $songsLimit+$artistsLimit)');
    }

    try {
      // First try iTunes Search (free, no auth, pre-sorted by popularity)
      final itunesResults = await _searchItunes(query, fetchLimit);

      if (itunesResults.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[ExternalSongLookup] Found ${itunesResults.length} iTunes results',
          );
        }
        final ranked = _rankResults(query, itunesResults);
        return _groupResults(query, ranked,
            songsLimit: songsLimit, artistsLimit: artistsLimit);
      }

      // Fallback to MusicBrainz if iTunes returns nothing
      if (kDebugMode) {
        debugPrint('[ExternalSongLookup] iTunes empty, trying MusicBrainz');
      }
      final mbResults = await _searchMusicBrainz(query, fetchLimit);
      final ranked = _rankResults(query, mbResults);
      return _groupResults(query, ranked,
          songsLimit: songsLimit, artistsLimit: artistsLimit);
    } catch (e) {
      debugPrint('[ExternalSongLookup] Error: $e');

      // Try MusicBrainz as fallback on iTunes error
      try {
        final mbResults = await _searchMusicBrainz(query, fetchLimit);
        final ranked = _rankResults(query, mbResults);
        return _groupResults(query, ranked,
            songsLimit: songsLimit, artistsLimit: artistsLimit);
      } catch (e2) {
        debugPrint(
          '[ExternalSongLookup] MusicBrainz fallback also failed: $e2',
        );
        rethrow;
      }
    }
  }

  /// Search iTunes via Edge Function (avoids CORS on Web).
  /// Results are pre-sorted by Apple's internal popularity ranking.
  Future<List<SongLookupResult>> _searchItunes(String query, int limit) async {
    final response = await _supabase.functions.invoke(
      'itunes_search',
      body: {'query': query, 'limit': limit},
    );

    if (response.status != 200) {
      throw Exception('iTunes search failed: ${response.status}');
    }

    final data = response.data;
    if (data == null || data['ok'] != true) {
      throw Exception(data?['error'] ?? 'Unknown iTunes error');
    }

    final results = (data['data'] as List?) ?? [];

    if (kDebugMode) {
      debugPrint('[ExternalSongLookup] Raw iTunes results: ${results.length}');
      for (var i = 0; i < results.length && i < 5; i++) {
        final t = results[i];
        debugPrint(
          '[ExternalSongLookup] RAW #$i: "${t['title']}" by ${t['artist']}',
        );
      }
    }

    return results.map<SongLookupResult>((track) {
      // iTunes results are returned in popularity order by Apple,
      // so we use the API position as the implicit popularity signal.
      // We assign a synthetic popularity: position 0 = 100, decays linearly.
      final idx = results.indexOf(track);
      final syntheticPopularity =
          (100 - (idx * (100 / limit)).round()).clamp(0, 100);

      return SongLookupResult(
        title: track['title'] as String? ?? 'Unknown',
        artist: track['artist'] as String? ?? 'Unknown Artist',
        durationSeconds: track['duration_seconds'] as int?,
        albumArtwork: track['album_artwork'] as String?,
        bpm: null,
        popularity: syntheticPopularity,
        source: SongSource.itunes,
      );
    }).toList();
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
      // MusicBrainz doesn't have popularity. Use release_count as a proxy:
      // more releases = more popular (originals appear on reissues, compilations, etc.)
      // Scale: 50+ releases → 100, logarithmic curve so 10 releases ≈ 65
      final releaseCount = recording['release_count'] as int? ?? 0;
      final popularity = releaseCount > 0
          ? ((100 * (1 - 1 / (1 + releaseCount / 10))).round().clamp(0, 100))
          : 0;

      return SongLookupResult(
        title: recording['title'] as String? ?? 'Unknown',
        artist: recording['artist'] as String? ?? 'Unknown Artist',
        musicbrainzId: recording['musicbrainz_id'] as String?,
        durationSeconds: recording['duration_seconds'] as int?,
        albumArtwork: null, // MusicBrainz doesn't provide artwork
        bpm: null, // MusicBrainz doesn't provide BPM
        popularity: popularity,
        source: SongSource.musicbrainz,
      );
    }).toList();
  }

  /// Rank results by relevance to the search query.
  ///
  /// Scoring layers:
  /// 1. Title match:        +100 exact, +75 startsWith, +50 contains
  /// 2. Artist-only match:  +25
  /// 3. Fuzzy/no match:     -20
  /// 4. Canonical boost:    +80 if exact title + popularity > 70
  ///                        +30 additional if popularity > 85
  /// 5. Popularity:         up to +60 (scaled from 0-100)
  /// 6. Spotify position:   +25 / +15 / +10 for first three results
  /// 7. Cover penalty:      -40
  List<SongLookupResult> _rankResults(
    String query,
    List<SongLookupResult> results,
  ) {
    if (results.isEmpty) return results;

    final lowerQuery = query.toLowerCase().trim();

    // Cover/tribute indicators in title or artist name
    final coverPattern = RegExp(
      r'(\bcover\b|\btribute\b|\bkaraoke\b|\bmade famous\b'
      r'|\boriginally performed\b|\bin the style of\b'
      r'|\bvarious artists\b)',
      caseSensitive: false,
    );

    double scoreResult(SongLookupResult r, int apiPosition) {
      final lowerTitle = r.title.toLowerCase();
      final lowerArtist = r.artist.toLowerCase();
      final pop = r.popularity ?? 0;
      double score = 0;

      // --- 1. Title relevance (primary signal) ---
      final exactTitle = lowerTitle == lowerQuery;
      if (exactTitle) {
        score += 100;
      } else if (lowerTitle.startsWith(lowerQuery)) {
        score += 75;
      } else if (lowerTitle.contains(lowerQuery)) {
        score += 50;
      } else if (lowerArtist.contains(lowerQuery)) {
        score += 25;
      } else {
        score -= 20;
      }

      // --- 2. Canonical artist boost ---
      // When the title is an exact match and the artist is highly popular,
      // this is very likely the original/canonical version.
      if (exactTitle && pop > 70) {
        score += 80;
        if (pop > 85) {
          score += 30; // Elite popularity — almost certainly the original
        }
      }

      // --- 3. Popularity boost (0-100 → 0-60) ---
      if (pop > 0) {
        score += (pop / 100) * 60;
      }

      // --- 4. API position boost ---
      // iTunes/API ordering is a strong relevance signal.
      if (apiPosition == 0) {
        score += 25;
      } else if (apiPosition == 1) {
        score += 15;
      } else if (apiPosition == 2) {
        score += 10;
      }

      // --- 5. Cover / tribute penalty ---
      if (coverPattern.hasMatch(lowerTitle) ||
          coverPattern.hasMatch(lowerArtist)) {
        score -= 40;
      }

      return score;
    }

    final indexed = List.generate(results.length, (i) => i);
    indexed.sort(
      (a, b) =>
          scoreResult(results[b], b).compareTo(scoreResult(results[a], a)),
    );

    final ranked = indexed.map((i) => results[i]).toList();

    if (kDebugMode) {
      for (var i = 0; i < ranked.length && i < 10; i++) {
        final r = ranked[i];
        final idx = indexed[i];
        debugPrint(
          '[ExternalSongLookup] #${i + 1}: "${r.title}" by ${r.artist}'
          ' | pop=${r.popularity} | apiPos=$idx'
          ' | score=${scoreResult(r, idx).toStringAsFixed(1)}',
        );
      }
    }

    return ranked;
  }

  /// Group results into songs, artists, and other buckets based on query match
  GroupedSongResults _groupResults(
    String query,
    List<SongLookupResult> results, {
    int songsLimit = 6,
    int artistsLimit = 6,
  }) {
    final lowerQuery = query.toLowerCase().trim();

    final songMatches = <SongLookupResult>[];
    final artistMatches = <SongLookupResult>[];
    final otherMatches = <SongLookupResult>[];

    for (final result in results) {
      final lowerTitle = result.title.toLowerCase();
      final lowerArtist = result.artist.toLowerCase();

      final isTitleMatch = lowerTitle == lowerQuery ||
          lowerTitle.startsWith(lowerQuery) ||
          lowerTitle.contains(lowerQuery);

      if (isTitleMatch) {
        songMatches.add(result);
      } else if (lowerArtist.contains(lowerQuery)) {
        artistMatches.add(result);
      } else {
        otherMatches.add(result);
      }
    }

    final rankedSongs = _rankResults(query, songMatches);
    final rankedArtists = _rankResults(query, artistMatches);
    final rankedOthers = _rankResults(query, otherMatches);

    return GroupedSongResults(
      songs: rankedSongs.take(songsLimit).toList(),
      artists: rankedArtists.take(artistsLimit).toList(),
      otherRanked: rankedOthers.take(6).toList(),
    );
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
