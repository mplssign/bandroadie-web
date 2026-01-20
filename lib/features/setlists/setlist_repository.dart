import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/constants/app_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import '../../shared/utils/title_case_formatter.dart';
import 'models/bulk_song_row.dart';
import 'models/setlist.dart';
import 'models/setlist_song.dart';
import 'models/song.dart';
import 'tuning/tuning_helpers.dart';

// ============================================================================
// ERROR TYPES FOR DETAILED DIAGNOSTICS
// ============================================================================

/// Detailed error information from setlist operations
class SetlistQueryError {
  final String code;
  final String message;
  final String? details;
  final String? hint;
  final String? reason;

  const SetlistQueryError({
    required this.code,
    required this.message,
    this.details,
    this.hint,
    this.reason,
  });

  /// User-friendly message based on error analysis
  String get userMessage {
    // RLS-related errors
    if (code == '42501' || message.contains('permission denied')) {
      return 'Access denied. You may not have permission to view this setlist.';
    }
    // No rows returned (could be RLS or deleted data)
    if (code == 'PGRST116' || reason == 'no_rows') {
      return 'Setlist not found or has been deleted.';
    }
    // Schema/FK issues (column doesn't exist)
    if (code == '42703' || reason == 'schema_mismatch') {
      return 'Database schema update needed. Please update the app or contact support.';
    }
    // Parse error (malformed data)
    if (reason == 'parse_error') {
      return 'One or more setlists have invalid data format.';
    }
    // Foreign key constraint
    if (code == '23503') {
      return 'Referenced data not found.';
    }
    // Network/connection issues
    if (message.contains('network') || message.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    // Default
    return 'Failed to load setlists. Please try again.';
  }

  @override
  String toString() =>
      'SetlistQueryError(code: $code, message: $message, details: $details, hint: $hint, reason: $reason)';
}

// ============================================================================
// BULK ADD RESULT
// ============================================================================

/// Result of a bulk add operation with undo support
class BulkAddResult {
  /// Number of songs successfully added
  final int addedCount;

  /// IDs of setlist_songs entries added to the target setlist (for undo)
  /// Note: Does NOT include Catalog entries - we only undo target setlist
  final List<String> setlistSongIds;

  const BulkAddResult({required this.addedCount, required this.setlistSongIds});

  /// Whether any songs were added
  bool get hasAddedSongs => addedCount > 0;
}

// ============================================================================
// ADD SONG RESULT
// ============================================================================

/// Result of adding a song to a setlist
/// Includes whether the song already existed in Catalog
class AddSongResult {
  final String? setlistSongId;
  final bool wasAlreadyInCatalog;
  final bool wasAlreadyInSetlist;
  final bool wasEnriched; // True if existing song was updated with new data
  final String songTitle;
  final String songArtist;

  const AddSongResult({
    this.setlistSongId,
    this.wasAlreadyInCatalog = false,
    this.wasAlreadyInSetlist = false,
    this.wasEnriched = false,
    this.songTitle = '',
    this.songArtist = '',
  });

  bool get success => setlistSongId != null;

  /// Get a friendly message about what happened.
  /// Uses humorous "roadie" copy per the BandRoadie brand voice.
  String get friendlyMessage {
    if (wasAlreadyInSetlist) {
      return '🎸 "$songTitle" is already in this setlist — great minds rehearse alike!';
    }
    if (wasAlreadyInCatalog) {
      // Humorous message for Catalog duplicates - "the Catalog remembers"
      if (wasEnriched) {
        return '🎸 "$songTitle" already exists in the Catalog — updated with new info!';
      }
      return '🎸 "$songTitle" already exists in the Catalog. (The Catalog remembers everything… like a drummer.)';
    }
    return 'Added "$songTitle" to setlist';
  }

  /// Message specifically for when adding to Catalog directly
  String get catalogAddMessage {
    if (wasAlreadyInCatalog) {
      if (wasEnriched) {
        return '🎸 "$songTitle" already exists in the Catalog — updated with new info!';
      }
      return '🎸 "$songTitle" already exists in the Catalog. (The Catalog remembers everything… like a drummer.)';
    }
    return 'Added "$songTitle" to Catalog';
  }
}

// ============================================================================
// SETLIST REPOSITORY
// Handles all setlist-related Supabase operations.
//
// ISOLATION RULES (NON-NEGOTIABLE):
// - Every query REQUIRES a non-null bandId
// - Catalog logic is enforced at this layer
// - Supabase RLS provides additional protection
// ============================================================================

/// Exception thrown when attempting operations without band context
class NoBandSelectedError extends Error {
  final String message;
  NoBandSelectedError([
    this.message =
        'No band selected. Cannot perform setlist operations without band context.',
  ]);

  @override
  String toString() => 'NoBandSelectedError: $message';
}

/// Provider for the setlist repository
final setlistRepositoryProvider = Provider<SetlistRepository>((ref) {
  return SetlistRepository();
});

class SetlistRepository {
  // ==========================================================================
  // FETCH SETLISTS FOR A BAND
  // ==========================================================================

  /// Fetches all setlists for a band with song counts.
  /// Orders by: Catalog first, then by name.
  ///
  /// [bandId] - Required for band isolation
  ///
  /// Returns list of Setlist objects with song counts.
  /// Resilient to schema changes - will fallback if is_catalog column doesn't exist.
  /// Automatically deduplicates Catalogs and ensures exactly one exists.
  Future<List<Setlist>> fetchSetlistsForBand(String bandId) async {
    return _fetchSetlistsForBandInternal(bandId, 0);
  }

  /// Internal method with recursion guard for deduplication re-fetches.
  Future<List<Setlist>> _fetchSetlistsForBandInternal(
    String bandId,
    int depth,
  ) async {
    // Prevent infinite recursion
    if (depth > 2) {
      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Max recursion depth reached for deduplication',
        );
      }
      // Fall through and return whatever we have
    }

    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    final userId = supabase.auth.currentUser?.id;

    if (kDebugMode) {
      debugPrint('[SetlistRepository] fetchSetlistsForBand');
      debugPrint('  bandId: $bandId');
      debugPrint('  userId: $userId');
    }

    // ==== STEP 1: ENSURE CATALOG EXISTS VIA RPC ====
    // Call the server-side RPC first - this handles:
    // - Creating Catalog if none exists
    // - Deduplicating if multiple exist
    // - Renaming "All Songs" to "Catalog"
    if (depth == 0) {
      try {
        await ensureCatalogSetlist(bandId);
      } catch (e) {
        // RPC may not exist in older deployments - continue with client-side fallback
        if (kDebugMode) {
          debugPrint(
            '[SetlistRepository] ensure_catalog_setlist RPC not available, using client-side fallback: $e',
          );
        }
      }
    }

    try {
      // Try query with is_catalog column first
      // If it fails with 42703 (column doesn't exist), fallback to basic query
      List<dynamic> response;
      bool hasIsCatalogColumn = true;

      try {
        response = await supabase
            .from('setlists')
            .select('''
              id,
              name,
              band_id,
              total_duration,
              is_catalog,
              created_at,
              updated_at,
              setlist_songs(count)
            ''')
            .eq('band_id', bandId)
            .order('name', ascending: true);
      } on PostgrestException catch (e) {
        // If is_catalog column doesn't exist, fallback to basic query
        if (e.code == '42703' && e.message.contains('is_catalog')) {
          if (kDebugMode) {
            debugPrint(
              '[SetlistRepository] is_catalog column not found, using fallback query',
            );
          }
          hasIsCatalogColumn = false;
          response = await supabase
              .from('setlists')
              .select('''
                id,
                name,
                band_id,
                total_duration,
                created_at,
                updated_at,
                setlist_songs(count)
              ''')
              .eq('band_id', bandId)
              .order('name', ascending: true);
        } else {
          rethrow;
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Query returned ${response.length} setlists (is_catalog column: $hasIsCatalogColumn)',
        );
      }

      // Parse results and compute song counts
      // Resilient parsing - skip bad rows instead of failing
      final setlists = <Setlist>[];
      int skippedRows = 0;

      for (int i = 0; i < response.length; i++) {
        final json = response[i];
        try {
          // Extract song count from nested aggregate
          int songCount = 0;
          if (json['setlist_songs'] != null) {
            final countData = json['setlist_songs'];
            if (countData is List &&
                countData.isNotEmpty &&
                countData[0] is Map) {
              final count = (countData[0] as Map)['count'];
              songCount = (count is int)
                  ? count
                  : (count is num ? count.toInt() : 0);
            }
          }

          // Create modified json with flattened song_count
          final flatJson = Map<String, dynamic>.from(json as Map);
          flatJson['song_count'] = songCount;

          setlists.add(Setlist.fromSupabase(flatJson));
        } catch (parseError, stackTrace) {
          skippedRows++;
          if (kDebugMode) {
            debugPrint(
              '════════════════════════════════════════════════════════════',
            );
            debugPrint('[SetlistRepository] Failed to parse setlist row $i');
            debugPrint('Exception: ${parseError.runtimeType} - $parseError');
            debugPrint('Row data: $json');
            debugPrint('Stack: $stackTrace');
            debugPrint(
              '════════════════════════════════════════════════════════════',
            );
          }
        }
      }

      if (skippedRows > 0 && kDebugMode) {
        debugPrint('[SetlistRepository] Skipped $skippedRows malformed rows');
      }

      // ==== CATALOG DEDUPLICATION ====
      // Only run deduplication if we haven't exceeded recursion depth
      if (depth <= 2) {
        // Check if there are multiple Catalogs and clean up if needed
        final catalogs = setlists
            .where((s) => s.isCatalog || isCatalogName(s.name))
            .toList();
        if (catalogs.length > 1) {
          if (kDebugMode) {
            debugPrint(
              '[SetlistRepository] ALERT: Found ${catalogs.length} Catalogs - running deduplication',
            );
          }
          // Run deduplication (wrapped in try-catch to prevent fetch failure)
          try {
            await deduplicateCatalogs(bandId);
            // Re-fetch to get clean data
            return _fetchSetlistsForBandInternal(bandId, depth + 1);
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                '[SetlistRepository] Deduplication failed, continuing with existing data: $e',
              );
            }
            // Continue with multiple catalogs rather than crashing
          }
        }

        // Check if no Catalog exists - create one
        if (catalogs.isEmpty) {
          if (kDebugMode) {
            debugPrint('[SetlistRepository] No Catalog found - creating one');
          }
          try {
            await ensureCatalogSetlist(bandId);
            // Re-fetch to include the new Catalog
            return _fetchSetlistsForBandInternal(bandId, depth + 1);
          } catch (e) {
            // Log but don't fail - continue with existing setlists
            if (kDebugMode) {
              debugPrint(
                '[SetlistRepository] Failed to create Catalog, continuing with existing setlists: $e',
              );
            }
            // Continue - return whatever setlists we have without Catalog
          }
        }

        // Single Catalog - ensure it has correct metadata (name="Catalog", is_catalog=true)
        if (catalogs.isNotEmpty) {
          final catalog = catalogs.first;
          if (catalog.name.toLowerCase() != 'catalog') {
            try {
              await _ensureCatalogMetadata(catalog.id, catalog.name);
              // Re-fetch to get updated name
              return _fetchSetlistsForBandInternal(bandId, depth + 1);
            } catch (e) {
              if (kDebugMode) {
                debugPrint(
                  '[SetlistRepository] Failed to update Catalog metadata: $e',
                );
              }
              // Continue with existing data
            }
          }
        }
      }

      // Sort: Catalog first, then alphabetically
      setlists.sort((a, b) {
        if (a.isCatalog && !b.isCatalog) return -1;
        if (!a.isCatalog && b.isCatalog) return 1;
        return a.name.compareTo(b.name);
      });

      // ==== VERIFICATION LOGGING ====
      if (kDebugMode) {
        final catalogCount = setlists
            .where((s) => s.isCatalog || isCatalogName(s.name))
            .length;
        debugPrint(
          '════════════════════════════════════════════════════════════',
        );
        debugPrint('[SetlistRepository] SETLIST VERIFICATION');
        debugPrint('  Band: $bandId');
        debugPrint('  Total setlists: ${setlists.length}');
        debugPrint('  Catalog count: $catalogCount');
        if (catalogCount != 1) {
          debugPrint(
            '  ⚠️  WARNING: Expected exactly 1 Catalog, found $catalogCount',
          );
        } else {
          debugPrint('  ✓ Catalog uniqueness verified');
        }
        debugPrint(
          '════════════════════════════════════════════════════════════',
        );
        for (final s in setlists) {
          debugPrint(
            '  - ${s.name}: ${s.songCount} songs, isCatalog: ${s.isCatalog}',
          );
        }
      }

      return setlists;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '════════════════════════════════════════════════════════════',
        );
        debugPrint('[SetlistRepository] PostgrestException fetching setlists');
        debugPrint('  code: ${e.code}');
        debugPrint('  message: ${e.message}');
        debugPrint('  details: ${e.details}');
        debugPrint('  hint: ${e.hint}');
        debugPrint(
          '════════════════════════════════════════════════════════════',
        );
      }

      String reason = 'unknown';
      if (e.code == '42501') reason = 'rls_denied';
      if (e.code == '42703') reason = 'schema_mismatch';

      throw SetlistQueryError(
        code: e.code ?? 'UNKNOWN',
        message: e.message,
        details: e.details?.toString(),
        hint: e.hint,
        reason: reason,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '════════════════════════════════════════════════════════════',
        );
        debugPrint('[SetlistRepository] Unexpected error fetching setlists');
        debugPrint('Exception: ${e.runtimeType} - $e');
        debugPrint('Stack: $stackTrace');
        debugPrint(
          '════════════════════════════════════════════════════════════',
        );
      }
      throw SetlistQueryError(
        code: 'UNEXPECTED',
        message: e.toString(),
        reason: 'unexpected',
      );
    }
  }

  // ==========================================================================
  // FETCH SONGS FOR A SETLIST (WITH BAND SCOPING)
  // ==========================================================================

  /// Fetches all songs for a setlist, ordered by position.
  /// Joins setlist_songs with songs table.
  ///
  /// [bandId] - Required for band isolation verification
  /// [setlistId] - The setlist to fetch songs for
  ///
  /// Returns songs with override values applied (bpm, tuning, duration_seconds).
  /// Throws [SetlistQueryError] with detailed diagnostics on failure.
  Future<List<SetlistSong>> fetchSongsForSetlist({
    required String bandId,
    required String setlistId,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }
    if (setlistId.isEmpty) {
      throw ArgumentError('setlistId cannot be empty');
    }

    final userId = supabase.auth.currentUser?.id;

    if (kDebugMode) {
      debugPrint('[SetlistRepository] fetchSongsForSetlist');
      debugPrint('  bandId: $bandId');
      debugPrint('  setlistId: $setlistId');
      debugPrint('  userId: $userId');
    }

    try {
      // Step 1: Verify setlist belongs to this band (prevents ID guessing attacks)
      final setlistCheck = await supabase
          .from('setlists')
          .select('id, band_id')
          .eq('id', setlistId)
          .eq('band_id', bandId)
          .maybeSingle();

      if (setlistCheck == null) {
        if (kDebugMode) {
          debugPrint('[SetlistRepository] Setlist not found or wrong band');
          debugPrint('  Requested setlistId: $setlistId');
          debugPrint('  Expected bandId: $bandId');
        }
        throw SetlistQueryError(
          code: 'BAND_MISMATCH',
          message: 'Setlist does not belong to active band',
          reason: 'band_mismatch',
          hint: 'Setlist may have been deleted or belongs to another band',
        );
      }

      // Step 2: Fetch songs with nested join
      final response = await supabase
          .from('setlist_songs')
          .select('''
            song_id,
            position,
            bpm,
            tuning,
            duration_seconds,
            songs!inner (
              id,
              title,
              artist,
              bpm,
              duration_seconds,
              tuning,
              album_artwork,
              notes
            )
          ''')
          .eq('setlist_id', setlistId)
          .order('position', ascending: true);

      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Query returned ${response.length} rows',
        );
      }

      // Step 3: Parse results, handling potential null songs
      final songs = <SetlistSong>[];
      for (final json in response) {
        try {
          final songData = json['songs'];
          if (songData == null) {
            if (kDebugMode) {
              debugPrint(
                '[SetlistRepository] Warning: Null songs data for song_id ${json['song_id']}',
              );
            }
            continue; // Skip orphaned setlist_songs entries
          }
          final song = SetlistSong.fromSupabase(json);
          // Debug: log BPM values for songs with overrides
          if (kDebugMode && json['bpm'] != null) {
            debugPrint(
              '[SetlistRepository] Song "${song.title}" has BPM override: ${json['bpm']}',
            );
          }
          // Debug: log duration for all songs to trace sync issues
          if (kDebugMode) {
            final songData = json['songs'] as Map<String, dynamic>;
            debugPrint(
              '[SetlistRepository] Song "${song.title}" (${song.id}): duration=${songData['duration_seconds']}',
            );
          }
          songs.add(song);
        } catch (parseError) {
          if (kDebugMode) {
            debugPrint('[SetlistRepository] Parse error for row: $json');
            debugPrint('  Error: $parseError');
          }
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Successfully parsed ${songs.length} songs',
        );
      }

      return songs;
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint('[SetlistRepository] PostgrestException:');
        debugPrint('  code: ${e.code}');
        debugPrint('  message: ${e.message}');
        debugPrint('  details: ${e.details}');
        debugPrint('  hint: ${e.hint}');
      }

      String reason = 'unknown';
      if (e.code == '42501') reason = 'rls_denied';
      if (e.code == '42703') reason = 'schema_mismatch';
      if (e.code == '23503') reason = 'fk_violation';
      if (e.code == 'PGRST116') reason = 'no_rows';

      throw SetlistQueryError(
        code: e.code ?? 'UNKNOWN',
        message: e.message,
        details: e.details?.toString(),
        hint: e.hint,
        reason: reason,
      );
    } on SetlistQueryError {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SetlistRepository] Unexpected error: $e');
        debugPrint('  Type: ${e.runtimeType}');
      }
      throw SetlistQueryError(
        code: 'UNEXPECTED',
        message: e.toString(),
        reason: 'unexpected',
      );
    }
  }

  // ==========================================================================
  // DEBUG: SMOKE TEST QUERY
  // ==========================================================================

  /// Debug-only method to test the songs query with full console output.
  /// Returns raw response data for inspection.
  Future<Map<String, dynamic>> debugFetchSongsRaw({
    required String bandId,
    required String setlistId,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    debugPrint('=== DEBUG SMOKE TEST ===');
    debugPrint('bandId: $bandId');
    debugPrint('setlistId: $setlistId');
    debugPrint('userId: $userId');

    final result = <String, dynamic>{
      'bandId': bandId,
      'setlistId': setlistId,
      'userId': userId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // Test 1: Can we see the setlist?
      final setlistResult = await supabase
          .from('setlists')
          .select('id, name, band_id')
          .eq('id', setlistId)
          .maybeSingle();
      result['setlist'] = setlistResult;
      debugPrint('Setlist: $setlistResult');

      // Test 2: Can we see setlist_songs?
      final setlistSongsResult = await supabase
          .from('setlist_songs')
          .select('id, song_id, position')
          .eq('setlist_id', setlistId)
          .order('position');
      result['setlist_songs_count'] = setlistSongsResult.length;
      result['setlist_songs'] = setlistSongsResult;
      debugPrint('Setlist songs: ${setlistSongsResult.length} rows');

      // Test 3: Can we see songs?
      if (setlistSongsResult.isNotEmpty) {
        final songIds = setlistSongsResult.map((s) => s['song_id']).toList();
        final songsResult = await supabase
            .from('songs')
            .select('id, title, artist, band_id')
            .inFilter('id', songIds);
        result['songs'] = songsResult;
        debugPrint('Songs: ${songsResult.length} rows');
      }

      result['success'] = true;
    } on PostgrestException catch (e) {
      result['error'] = {
        'code': e.code,
        'message': e.message,
        'details': e.details?.toString(),
        'hint': e.hint,
      };
      debugPrint('PostgrestException: ${e.code} - ${e.message}');
    } catch (e) {
      result['error'] = {'message': e.toString()};
      debugPrint('Unexpected error: $e');
    }

    debugPrint('=== END DEBUG ===');
    return result;
  }

  // ==========================================================================
  // DELETE SONG FROM SETLIST
  // ==========================================================================

  /// Deletes a song from a specific setlist (not Catalog behavior).
  /// Only removes the setlist_songs row for this setlist_id + song_id.
  ///
  /// Use [deleteSongFromCatalog] for Catalog deletion which cascades.
  Future<void> deleteSongFromSetlist({
    required String setlistId,
    required String songId,
  }) async {
    if (setlistId.isEmpty || songId.isEmpty) {
      throw ArgumentError('setlistId and songId cannot be empty');
    }

    try {
      // Try RPC first (handles RLS issues)
      final response = await supabase.rpc(
        'delete_song_from_setlist',
        params: {'p_setlist_id': setlistId, 'p_song_id': songId},
      );

      final result = response as Map<String, dynamic>?;
      if (result == null || result['success'] != true) {
        final error = result?['error'] ?? 'Unknown error';
        throw Exception(error);
      }

      debugPrint(
        '[SetlistRepository] Removed song $songId from setlist $setlistId via RPC',
      );
    } on PostgrestException catch (e) {
      // Fallback if RPC doesn't exist yet
      if (e.code == 'PGRST202') {
        debugPrint(
          '[SetlistRepository] delete_song_from_setlist RPC not found, using direct delete',
        );
        await supabase
            .from('setlist_songs')
            .delete()
            .eq('setlist_id', setlistId)
            .eq('song_id', songId);

        debugPrint(
          '[SetlistRepository] Removed song $songId from setlist $setlistId (fallback)',
        );
        return;
      }
      debugPrint('[SetlistRepository] Error deleting song from setlist: $e');
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] Error deleting song from setlist: $e');
      rethrow;
    }
  }

  /// Deletes a song from Catalog, which cascades to ALL setlists in the band.
  ///
  /// STEPS:
  /// 1. Get all setlist IDs for this band
  /// 2. Delete all setlist_songs rows for this song in those setlists
  /// 3. Delete the song record itself
  ///
  /// This is the nuclear option - song is completely removed from the band.
  Future<void> deleteSongFromCatalog({
    required String bandId,
    required String songId,
  }) async {
    if (bandId.isEmpty || songId.isEmpty) {
      throw ArgumentError('bandId and songId cannot be empty');
    }

    try {
      // Try RPC first (handles RLS issues with songs table)
      final response = await supabase.rpc(
        'delete_song_from_catalog',
        params: {'p_band_id': bandId, 'p_song_id': songId},
      );

      final result = response as Map<String, dynamic>?;
      if (result == null || result['success'] != true) {
        final error = result?['error'] ?? 'Unknown error';
        throw Exception(error);
      }

      debugPrint(
        '[SetlistRepository] Deleted song $songId from band $bandId via RPC',
      );
    } on PostgrestException catch (e) {
      // Fallback if RPC doesn't exist yet
      if (e.code == 'PGRST202') {
        debugPrint(
          '[SetlistRepository] delete_song_from_catalog RPC not found, using fallback',
        );
        await _deleteSongFromCatalogFallback(bandId: bandId, songId: songId);
        return;
      }
      debugPrint('[SetlistRepository] Error deleting song from Catalog: $e');
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] Error deleting song from Catalog: $e');
      rethrow;
    }
  }

  /// Fallback deletion method when RPC is not available
  Future<void> _deleteSongFromCatalogFallback({
    required String bandId,
    required String songId,
  }) async {
    // Step 1: Get all setlist IDs for this band
    final setlistsResponse = await supabase
        .from('setlists')
        .select('id')
        .eq('band_id', bandId);

    final setlistIds = setlistsResponse
        .map<String>((s) => s['id'] as String)
        .toList();

    if (setlistIds.isNotEmpty) {
      // Step 2: Delete from all setlist_songs in this band
      await supabase
          .from('setlist_songs')
          .delete()
          .eq('song_id', songId)
          .inFilter('setlist_id', setlistIds);

      debugPrint(
        '[SetlistRepository] Removed song $songId from ${setlistIds.length} setlists (fallback)',
      );
    }

    // Step 3: Delete the song record
    await supabase
        .from('songs')
        .delete()
        .eq('id', songId)
        .eq('band_id', bandId);

    debugPrint(
      '[SetlistRepository] Deleted song $songId from band $bandId (fallback)',
    );
  }

  // ==========================================================================
  // REORDER SONGS IN SETLIST
  // ==========================================================================

  /// Updates positions for all songs in a setlist after reorder.
  ///
  /// Takes a list of song IDs in their new order and updates positions.
  /// Uses the `reorder_setlist_songs` RPC for atomic, constraint-safe updates.
  ///
  /// Falls back to client-side upsert if RPC is not available.
  Future<void> reorderSongs({
    required String setlistId,
    required List<String> songIdsInOrder,
    String? bandId,
  }) async {
    if (setlistId.isEmpty) {
      throw ArgumentError('setlistId cannot be empty');
    }

    if (songIdsInOrder.isEmpty) {
      return; // Nothing to reorder
    }

    debugPrint('[SetlistRepository] reorderSongs:');
    debugPrint('  setlistId: $setlistId');
    debugPrint('  bandId: $bandId');
    debugPrint('  songCount: ${songIdsInOrder.length}');

    try {
      // Try the atomic RPC first (avoids unique constraint violations)
      final response = await supabase.rpc(
        'reorder_setlist_songs',
        params: {'p_setlist_id': setlistId, 'p_song_ids': songIdsInOrder},
      );

      // Check RPC response
      if (response is Map && response['success'] == true) {
        debugPrint(
          '[SetlistRepository] ✓ Reordered ${response['reordered_count']} songs via RPC',
        );

        // Verify positions actually persisted
        final verify = await supabase
            .from('setlist_songs')
            .select('song_id, position')
            .eq('setlist_id', setlistId)
            .order('position', ascending: true);

        debugPrint('[SetlistRepository] Verifying persisted positions:');
        for (int i = 0; i < verify.length && i < 5; i++) {
          final v = verify[i];
          final expectedSongId = i < songIdsInOrder.length
              ? songIdsInOrder[i]
              : '?';
          final match = v['song_id'] == expectedSongId ? '✓' : '✗';
          debugPrint(
            '  [$i] $match pos=${v['position']} song=${(v['song_id'] as String).substring(0, 8)}... expected=${expectedSongId.substring(0, 8)}...',
          );
        }
        if (verify.length > 5) {
          debugPrint('  ... and ${verify.length - 5} more');
        }

        return;
      }

      // RPC returned an error
      if (response is Map && response['success'] == false) {
        final error = response['error'] ?? 'Unknown RPC error';
        debugPrint('[SetlistRepository] RPC error: $error');
        throw Exception('Reorder failed: $error');
      }

      debugPrint('[SetlistRepository] Unexpected RPC response: $response');
      throw Exception('Unexpected response from reorder RPC');
    } on PostgrestException catch (e) {
      // RPC not found - fall back to client-side approach
      if (e.code == 'PGRST202' || e.code == '42883') {
        debugPrint(
          '[SetlistRepository] reorder_setlist_songs RPC not found, using fallback',
        );
        await _reorderSongsFallback(
          setlistId: setlistId,
          songIdsInOrder: songIdsInOrder,
        );
        return;
      }

      debugPrint('[SetlistRepository] Error reordering songs: $e');
      debugPrint('  code: ${e.code}');
      debugPrint('  message: ${e.message}');
      debugPrint('  details: ${e.details}');
      debugPrint('  hint: ${e.hint}');
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] Error reordering songs: $e');
      rethrow;
    }
  }

  /// Fallback reorder method using client-side upsert.
  /// This may fail with unique constraint violations if positions overlap.
  Future<void> _reorderSongsFallback({
    required String setlistId,
    required List<String> songIdsInOrder,
  }) async {
    debugPrint(
      '[SetlistRepository] Using fallback reorder (client-side upsert)',
    );

    // Build batch update payload
    final updates = songIdsInOrder.asMap().entries.map((entry) {
      return {
        'setlist_id': setlistId,
        'song_id': entry.value,
        'position': entry.key,
      };
    }).toList();

    // Upsert all positions in one call
    await supabase
        .from('setlist_songs')
        .upsert(updates, onConflict: 'setlist_id,song_id');

    debugPrint(
      '[SetlistRepository] Fallback reordered ${updates.length} songs in setlist $setlistId',
    );
  }

  // ==========================================================================
  // CATALOG HELPERS
  // ==========================================================================

  /// Checks if a setlist is the Catalog by name.
  /// Uses the shared isCatalogName function from app_constants.
  bool isCatalog(String setlistName) {
    return setlistName == kCatalogSetlistName;
  }

  /// Gets the Catalog setlist ID for a band.
  /// Returns null if no Catalog exists (shouldn't happen in normal use).
  Future<String?> getCatalogId(String bandId) async {
    if (bandId.isEmpty) return null;

    try {
      // Try by is_catalog flag first
      var response = await supabase
          .from('setlists')
          .select('id')
          .eq('band_id', bandId)
          .eq('is_catalog', true)
          .maybeSingle();

      if (response != null) {
        return response['id'] as String?;
      }

      // Fallback to name match
      response = await supabase
          .from('setlists')
          .select('id')
          .eq('band_id', bandId)
          .eq('name', kCatalogSetlistName)
          .maybeSingle();

      return response?['id'] as String?;
    } catch (e) {
      debugPrint('[SetlistRepository] Error getting Catalog ID: $e');
      return null;
    }
  }

  // ==========================================================================
  // CATALOG DEDUPLICATION (CLIENT-SIDE CLEANUP)
  // ==========================================================================

  /// Detects and cleans up duplicate Catalog/"All Songs" setlists for a band.
  ///
  /// This method:
  /// 1. Finds all setlists that are Catalogs (by name or is_catalog flag)
  /// 2. Keeps the canonical one (oldest, or with most songs if tied)
  /// 3. Merges songs from duplicates into the canonical
  /// 4. Renames legacy "All Songs" to "Catalog"
  /// 5. Deletes duplicate setlists
  ///
  /// Safe to call multiple times (idempotent).
  /// Works even if is_catalog column doesn't exist (uses name matching).
  ///
  /// Returns the canonical Catalog's ID, or null if no Catalog exists.
  Future<String?> deduplicateCatalogs(String bandId) async {
    if (bandId.isEmpty) return null;

    try {
      // Try query with is_catalog column first
      List<dynamic> response;
      bool hasIsCatalogColumn = true;

      try {
        response = await supabase
            .from('setlists')
            .select('id, name, is_catalog, created_at, setlist_songs(count)')
            .eq('band_id', bandId);
      } on PostgrestException catch (e) {
        if (e.code == '42703') {
          // is_catalog column doesn't exist, use fallback
          hasIsCatalogColumn = false;
          response = await supabase
              .from('setlists')
              .select('id, name, created_at, setlist_songs(count)')
              .eq('band_id', bandId);
        } else {
          rethrow;
        }
      }

      // Filter to only Catalog candidates (by name matching)
      final catalogCandidates = <Map<String, dynamic>>[];

      for (final row in response) {
        final name = row['name'] as String? ?? '';
        final isCatalogFlag = hasIsCatalogColumn
            ? (row['is_catalog'] as bool? ?? false)
            : false;

        // Include if is_catalog=true OR name matches Catalog/All Songs
        if (isCatalogFlag || isCatalogName(name)) {
          // Extract song count
          int songCount = 0;
          if (row['setlist_songs'] != null) {
            final countData = row['setlist_songs'];
            if (countData is List &&
                countData.isNotEmpty &&
                countData[0] is Map) {
              songCount = (countData[0] as Map)['count'] as int? ?? 0;
            }
          }

          catalogCandidates.add({
            'id': row['id'],
            'name': name,
            'is_catalog': isCatalogFlag,
            'created_at': row['created_at'],
            'song_count': songCount,
          });
        }
      }

      if (catalogCandidates.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[SetlistRepository] No Catalog found for band $bandId - will create',
          );
        }
        return null;
      }

      if (catalogCandidates.length == 1) {
        final only = catalogCandidates.first;
        // Ensure it's named "Catalog" and has is_catalog=true
        await _ensureCatalogMetadata(
          only['id'] as String,
          only['name'] as String,
        );
        return only['id'] as String;
      }

      // Multiple Catalogs found - need to deduplicate
      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Found ${catalogCandidates.length} Catalog candidates - deduplicating',
        );
        for (final c in catalogCandidates) {
          debugPrint('  - ${c['name']} (${c['id']}): ${c['song_count']} songs');
        }
      }

      // Sort by: most songs first, then oldest created_at
      catalogCandidates.sort((a, b) {
        final songCompare = (b['song_count'] as int).compareTo(
          a['song_count'] as int,
        );
        if (songCompare != 0) return songCompare;

        final aDate = DateTime.tryParse(a['created_at'] as String? ?? '');
        final bDate = DateTime.tryParse(b['created_at'] as String? ?? '');
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });

      final canonical = catalogCandidates.first;
      final canonicalId = canonical['id'] as String;
      final duplicates = catalogCandidates.skip(1).toList();

      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Canonical Catalog: ${canonical['name']} ($canonicalId)',
        );
      }

      // Merge songs from duplicates into canonical
      for (final duplicate in duplicates) {
        final duplicateId = duplicate['id'] as String;
        await _mergeSongsIntoSetlist(
          sourceSetlistId: duplicateId,
          targetSetlistId: canonicalId,
        );
      }

      // Delete duplicate setlists
      for (final duplicate in duplicates) {
        final duplicateId = duplicate['id'] as String;
        try {
          // Delete songs first (in case of FK constraints)
          await supabase
              .from('setlist_songs')
              .delete()
              .eq('setlist_id', duplicateId);

          // Then delete the setlist
          await supabase.from('setlists').delete().eq('id', duplicateId);

          if (kDebugMode) {
            debugPrint(
              '[SetlistRepository] Deleted duplicate Catalog: ${duplicate['name']} ($duplicateId)',
            );
          }
        } catch (e) {
          debugPrint(
            '[SetlistRepository] Error deleting duplicate $duplicateId: $e',
          );
          // Continue with other duplicates
        }
      }

      // Ensure canonical has correct name and is_catalog flag
      await _ensureCatalogMetadata(canonicalId, canonical['name'] as String);

      return canonicalId;
    } catch (e) {
      debugPrint('[SetlistRepository] Error deduplicating Catalogs: $e');
      return null;
    }
  }

  /// Ensures a setlist has is_catalog=true and name='Catalog'
  /// Handles case where is_catalog column may not exist.
  Future<void> _ensureCatalogMetadata(
    String setlistId,
    String currentName,
  ) async {
    try {
      // Try with is_catalog first
      final updates = <String, dynamic>{'is_catalog': true};
      if (currentName.toLowerCase() != 'catalog') {
        updates['name'] = kCatalogSetlistName;
      }

      try {
        await supabase.from('setlists').update(updates).eq('id', setlistId);
      } on PostgrestException catch (e) {
        if (e.code == '42703') {
          // is_catalog column doesn't exist, just update name
          if (currentName.toLowerCase() != 'catalog') {
            await supabase
                .from('setlists')
                .update({'name': kCatalogSetlistName})
                .eq('id', setlistId);
          }
        } else {
          rethrow;
        }
      }

      if (kDebugMode && updates.containsKey('name')) {
        debugPrint(
          '[SetlistRepository] Renamed "$currentName" to "$kCatalogSetlistName"',
        );
      }
    } catch (e) {
      debugPrint('[SetlistRepository] Error updating Catalog metadata: $e');
    }
  }

  /// Merges songs from source setlist into target setlist (skipping duplicates)
  Future<void> _mergeSongsIntoSetlist({
    required String sourceSetlistId,
    required String targetSetlistId,
  }) async {
    try {
      // Get songs from source that don't exist in target
      final sourceSongs = await supabase
          .from('setlist_songs')
          .select('song_id, bpm, tuning, duration_seconds')
          .eq('setlist_id', sourceSetlistId);

      if ((sourceSongs as List).isEmpty) return;

      // Get existing song IDs in target
      final targetSongs = await supabase
          .from('setlist_songs')
          .select('song_id')
          .eq('setlist_id', targetSetlistId);

      final existingIds = (targetSongs as List)
          .map((r) => r['song_id'] as String)
          .toSet();

      // Get max position in target
      final posResult = await supabase
          .from('setlist_songs')
          .select('position')
          .eq('setlist_id', targetSetlistId)
          .order('position', ascending: false)
          .limit(1);

      int nextPosition = 0;
      if ((posResult as List).isNotEmpty) {
        nextPosition = (posResult[0]['position'] as int? ?? 0) + 1;
      }

      // Insert songs that don't exist in target
      int mergedCount = 0;
      for (final song in sourceSongs) {
        final songId = song['song_id'] as String;
        if (existingIds.contains(songId)) continue;

        try {
          await supabase.from('setlist_songs').insert({
            'setlist_id': targetSetlistId,
            'song_id': songId,
            'position': nextPosition,
            'bpm': song['bpm'],
            'tuning': song['tuning'],
            'duration_seconds': song['duration_seconds'],
          });
          nextPosition++;
          mergedCount++;
        } catch (e) {
          // Skip duplicates silently
        }
      }

      if (kDebugMode && mergedCount > 0) {
        debugPrint(
          '[SetlistRepository] Merged $mergedCount songs from $sourceSetlistId into $targetSetlistId',
        );
      }
    } catch (e) {
      debugPrint('[SetlistRepository] Error merging songs: $e');
    }
  }

  // ==========================================================================
  // UPDATE SONG OVERRIDES (Global - syncs across all setlists)
  // ==========================================================================

  /// Updates the BPM for a song globally (syncs across all setlists).
  ///
  /// This updates the songs.bpm value directly. Changes apply to all setlists
  /// containing this song. Uses RPC with SECURITY DEFINER to bypass RLS.
  Future<void> updateSongBpmOverride({
    required String bandId,
    required String setlistId,
    required String songId,
    required int bpm,
  }) async {
    if (songId.isEmpty) {
      throw ArgumentError('songId cannot be empty');
    }
    if (bpm < 20 || bpm > 300) {
      throw ArgumentError('BPM must be between 20 and 300');
    }
    if (bandId.isEmpty) {
      throw ArgumentError('bandId is required for security');
    }

    debugPrint(
      '[SetlistRepository] updateSongBpmOverride: songId=$songId, bpm=$bpm, bandId=$bandId',
    );

    try {
      // Use RPC with SECURITY DEFINER to bypass RLS for songs with NULL band_id
      // Pass ALL parameters to avoid function overload ambiguity (PGRST203)
      final result = await supabase.rpc(
        'update_song_metadata',
        params: {
          'p_song_id': songId,
          'p_band_id': bandId,
          'p_bpm': bpm,
          'p_duration_seconds': null,
          'p_tuning': null,
          'p_notes': null,
          'p_title': null,
          'p_artist': null,
        },
      );

      // Check RPC result - handle both Map and dynamic response types
      debugPrint(
        '[SetlistRepository] RPC result type: ${result.runtimeType}, value: $result',
      );

      if (result is Map) {
        if (result['success'] == false) {
          final error = result['error'] ?? 'Unknown error';
          debugPrint('[SetlistRepository] RPC returned error: $error');
          throw Exception(error);
        }
      }

      debugPrint(
        '[SetlistRepository] ✓ Updated BPM to $bpm for song $songId (global via RPC)',
      );
    } on PostgrestException catch (e) {
      // Handle specific PostgrestException codes
      debugPrint(
        '[SetlistRepository] PostgrestException: code=${e.code}, message=${e.message}',
      );

      // PGRST203 = ambiguous function call (multiple overloads)
      if (e.code == 'PGRST203') {
        debugPrint(
          '[SetlistRepository] PGRST203: Multiple function overloads exist. Run migration 081_fix_update_song_metadata_rpc.sql',
        );
        throw Exception('Server configuration error. Please contact support.');
      }

      // RPC may not exist - fall back to direct update
      if (e.code == 'PGRST202' || e.code == '42883') {
        debugPrint(
          '[SetlistRepository] update_song_metadata RPC not found, falling back to direct update',
        );
        await supabase.from('songs').update({'bpm': bpm}).eq('id', songId);
        debugPrint(
          '[SetlistRepository] ✓ Updated BPM to $bpm for song $songId (direct)',
        );
        return;
      }
      debugPrint('[SetlistRepository] Error updating song BPM: $e');
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] Error updating song BPM: $e');
      rethrow;
    }
  }

  /// Clears the BPM for a song globally (syncs across all setlists).
  /// Uses RPC with SECURITY DEFINER to bypass RLS for legacy songs.
  Future<void> clearSongBpmOverride({
    required String bandId,
    required String setlistId,
    required String songId,
  }) async {
    if (songId.isEmpty) {
      throw ArgumentError('songId cannot be empty');
    }
    if (bandId.isEmpty) {
      throw ArgumentError('bandId is required for security');
    }

    debugPrint(
      '[SetlistRepository] clearSongBpmOverride: songId=$songId, bandId=$bandId',
    );

    try {
      // Use clear_song_metadata RPC with SECURITY DEFINER to bypass RLS
      final result = await supabase.rpc(
        'clear_song_metadata',
        params: {'p_song_id': songId, 'p_band_id': bandId, 'p_clear_bpm': true},
      );

      // Check RPC result - handle both Map and dynamic response types
      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] RPC result type: ${result.runtimeType}, value: $result',
        );
      }

      if (result is Map) {
        if (result['success'] == false) {
          final error = result['error'] ?? 'Unknown error';
          debugPrint('[SetlistRepository] RPC returned error: $error');
          throw Exception(error);
        }
      }

      debugPrint(
        '[SetlistRepository] ✓ Cleared BPM for song $songId (global via RPC)',
      );
    } on PostgrestException catch (e) {
      debugPrint(
        '[SetlistRepository] PostgrestException: code=${e.code}, message=${e.message}',
      );

      // PGRST203 = ambiguous function call (multiple overloads)
      if (e.code == 'PGRST203') {
        debugPrint(
          '[SetlistRepository] PGRST203: Multiple function overloads exist. Run migration 081_fix_update_song_metadata_rpc.sql',
        );
        throw Exception('Server configuration error. Please contact support.');
      }

      // RPC may not exist - fall back to direct update
      if (e.code == 'PGRST202' || e.code == '42883') {
        debugPrint(
          '[SetlistRepository] clear_song_metadata RPC not found, falling back to direct update',
        );
        await supabase.from('songs').update({'bpm': null}).eq('id', songId);
        debugPrint(
          '[SetlistRepository] ✓ Cleared BPM for song $songId (direct fallback)',
        );
        return;
      }
      debugPrint('[SetlistRepository] Error clearing song BPM: $e');
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] Error clearing song BPM: $e');
      rethrow;
    }
  }

  /// Updates the duration for a song globally (syncs across all setlists).
  /// Duration is in seconds. Uses RPC with SECURITY DEFINER to bypass RLS.
  Future<void> updateSongDurationOverride({
    required String bandId,
    required String setlistId,
    required String songId,
    required int durationSeconds,
  }) async {
    if (songId.isEmpty) {
      throw ArgumentError('songId cannot be empty');
    }
    if (durationSeconds < 0 || durationSeconds > 1200) {
      throw ArgumentError('Duration must be between 0 and 20 minutes');
    }
    if (bandId.isEmpty) {
      throw ArgumentError('bandId is required for security');
    }

    debugPrint(
      '[SetlistRepository] updateSongDurationOverride: songId=$songId, duration=$durationSeconds, bandId=$bandId',
    );

    try {
      // Use RPC with SECURITY DEFINER to bypass RLS for songs with NULL band_id
      // Pass ALL parameters to avoid function overload ambiguity (PGRST203)
      final result = await supabase.rpc(
        'update_song_metadata',
        params: {
          'p_song_id': songId,
          'p_band_id': bandId,
          'p_bpm': null,
          'p_duration_seconds': durationSeconds,
          'p_tuning': null,
          'p_notes': null,
          'p_title': null,
          'p_artist': null,
        },
      );

      // Check RPC result - handle both Map and dynamic response types
      debugPrint(
        '[SetlistRepository] RPC result type: ${result.runtimeType}, value: $result',
      );

      if (result is Map) {
        if (result['success'] == false) {
          final error = result['error'] ?? 'Unknown error';
          debugPrint('[SetlistRepository] RPC returned error: $error');
          throw Exception(error);
        }
      }

      debugPrint(
        '[SetlistRepository] ✓ Updated duration to $durationSeconds for song $songId (global via RPC)',
      );
    } on PostgrestException catch (e) {
      // Handle specific PostgrestException codes
      debugPrint(
        '[SetlistRepository] PostgrestException: code=${e.code}, message=${e.message}',
      );

      // PGRST203 = ambiguous function call (multiple overloads)
      if (e.code == 'PGRST203') {
        debugPrint(
          '[SetlistRepository] PGRST203: Multiple function overloads exist. Run migration 081_fix_update_song_metadata_rpc.sql',
        );
        throw Exception('Server configuration error. Please contact support.');
      }

      // RPC may not exist - fall back to direct update
      if (e.code == 'PGRST202' || e.code == '42883') {
        debugPrint(
          '[SetlistRepository] update_song_metadata RPC not found, falling back to direct update',
        );
        await supabase
            .from('songs')
            .update({'duration_seconds': durationSeconds})
            .eq('id', songId);
        debugPrint(
          '[SetlistRepository] ✓ Updated duration to $durationSeconds for song $songId (direct)',
        );
        return;
      }
      debugPrint('[SetlistRepository] Error updating song duration: $e');
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] Error updating song duration: $e');
      rethrow;
    }
  }

  /// Updates the tuning for a song globally (syncs across all setlists).
  /// Uses RPC with SECURITY DEFINER to bypass RLS.
  ///
  /// The tuning value should be a valid tuning ID (e.g., 'half_step_down', 'drop_d').
  Future<void> updateSongTuningOverride({
    required String bandId,
    required String setlistId,
    required String songId,
    required String tuning,
  }) async {
    if (songId.isEmpty) {
      throw ArgumentError('songId cannot be empty');
    }
    if (tuning.isEmpty) {
      throw ArgumentError('Tuning cannot be empty');
    }
    if (bandId.isEmpty) {
      throw ArgumentError('bandId is required for security');
    }

    // Normalize tuning value for database compatibility (handles legacy enum)
    final dbTuning = tuningToDbEnum(tuning) ?? tuning;
    final isLegacySupported = isLegacyEnumSupported(tuning);

    if (kDebugMode) {
      debugPrint(
        '[SetlistRepository] updateSongTuning: songId=$songId, tuning=$tuning → $dbTuning, bandId=$bandId',
      );
    }

    try {
      // Use RPC with SECURITY DEFINER to bypass RLS for songs with NULL band_id
      // Pass ALL parameters to avoid function overload ambiguity (PGRST203)
      final result = await supabase.rpc(
        'update_song_metadata',
        params: {
          'p_song_id': songId,
          'p_band_id': bandId,
          'p_bpm': null,
          'p_duration_seconds': null,
          'p_tuning': dbTuning,
          'p_notes': null,
          'p_title': null,
          'p_artist': null,
        },
      );

      // Check RPC result - handle both Map and dynamic response types
      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] RPC result type: ${result.runtimeType}, value: $result',
        );
      }

      if (result is Map) {
        if (result['success'] == false) {
          final error = result['error'] ?? 'Unknown error';
          debugPrint('[SetlistRepository] RPC returned error: $error');
          throw Exception(error);
        }
      }

      debugPrint(
        '[SetlistRepository] ✓ Updated tuning to $dbTuning for song $songId (global via RPC)',
      );
    } on PostgrestException catch (e) {
      debugPrint(
        '[SetlistRepository] PostgrestException: code=${e.code}, message=${e.message}',
      );

      // PGRST203 = ambiguous function call (multiple overloads)
      if (e.code == 'PGRST203') {
        debugPrint(
          '[SetlistRepository] PGRST203: Multiple function overloads exist. Run migration 081_fix_update_song_metadata_rpc.sql',
        );
        throw Exception('Server configuration error. Please contact support.');
      }

      // RPC may not exist - fall back to direct update
      if (e.code == 'PGRST202' || e.code == '42883') {
        debugPrint(
          '[SetlistRepository] update_song_metadata RPC not found, falling back to direct update',
        );
        await supabase
            .from('songs')
            .update({'tuning': dbTuning})
            .eq('id', songId);
        debugPrint(
          '[SetlistRepository] ✓ Updated tuning to $dbTuning for song $songId (direct)',
        );
        return;
      }

      // Check for enum cast error (invalid tuning value)
      // PostgreSQL returns 22P02 for invalid_text_representation
      // PostgREST may wrap this as various codes
      final isEnumError =
          e.message.contains('invalid input value for enum') ||
          e.message.contains('tuning_type') ||
          e.code == '22P02' ||
          e.code == '400';

      if (isEnumError && !isLegacySupported) {
        throw Exception(
          'This tuning is not yet available. Please try Standard, Drop D, Half-Step, or Full-Step.',
        );
      }
      debugPrint('[SetlistRepository] ❌ PostgrestException: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] ❌ Error updating tuning: $e');
      rethrow;
    }
  }

  // ==========================================================================
  // UPDATE SONG NOTES
  // ==========================================================================

  /// Updates a song's notes (stored on the songs table - global, not per-setlist).
  ///
  /// Uses RPC with SECURITY DEFINER to bypass RLS.
  Future<void> updateSongNotes({
    required String bandId,
    required String songId,
    required String? notes,
  }) async {
    if (songId.isEmpty) {
      throw ArgumentError('songId cannot be empty');
    }
    if (bandId.isEmpty) {
      throw ArgumentError('bandId is required for security');
    }

    if (kDebugMode) {
      debugPrint(
        '[SetlistRepository] updateSongNotes: songId=$songId, notes=${notes != null ? notes.substring(0, notes.length > 50 ? 50 : notes.length) : 'null'}...',
      );
    }

    try {
      // Use RPC with SECURITY DEFINER to bypass RLS for songs with NULL band_id
      // Must pass ALL 8 parameters to avoid PGRST203 function overload ambiguity
      final result = await supabase.rpc(
        'update_song_metadata',
        params: {
          'p_song_id': songId,
          'p_band_id': bandId,
          'p_bpm': null,
          'p_duration_seconds': null,
          'p_tuning': null,
          'p_notes': notes,
          'p_title': null,
          'p_artist': null,
        },
      );

      // Check RPC result - handle both Map and dynamic response types
      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] RPC result type: ${result.runtimeType}, value: $result',
        );
      }

      if (result is Map) {
        if (result['success'] == false) {
          final error = result['error'] ?? 'Unknown error';
          debugPrint('[SetlistRepository] RPC returned error: $error');
          throw Exception(error);
        }
      }

      debugPrint(
        '[SetlistRepository] ✓ Updated notes for song $songId (via RPC)',
      );
    } on PostgrestException catch (e) {
      debugPrint(
        '[SetlistRepository] PostgrestException: code=${e.code}, message=${e.message}',
      );

      // PGRST203 = ambiguous function call (multiple overloads)
      if (e.code == 'PGRST203') {
        debugPrint(
          '[SetlistRepository] PGRST203: Multiple function overloads exist. Run migration 081_fix_update_song_metadata_rpc.sql',
        );
        throw Exception('Server configuration error. Please contact support.');
      }

      // RPC may not exist - fall back to direct update
      if (e.code == 'PGRST202' || e.code == '42883') {
        debugPrint(
          '[SetlistRepository] update_song_metadata RPC not found, falling back to direct update',
        );
        await supabase.from('songs').update({'notes': notes}).eq('id', songId);
        debugPrint(
          '[SetlistRepository] ✓ Updated notes for song $songId (direct)',
        );
        return;
      }
      debugPrint('[SetlistRepository] ❌ PostgrestException: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] ❌ Error updating notes: $e');
      rethrow;
    }
  }

  /// Updates a song's title and/or artist (stored on the songs table - global).
  ///
  /// Uses RPC with SECURITY DEFINER to bypass RLS.
  Future<void> updateSongTitleArtist({
    required String bandId,
    required String songId,
    String? title,
    String? artist,
  }) async {
    if (songId.isEmpty) {
      throw ArgumentError('songId cannot be empty');
    }
    if (title == null && artist == null) {
      return; // Nothing to update
    }
    if (bandId.isEmpty) {
      throw ArgumentError('bandId is required for security');
    }

    if (kDebugMode) {
      debugPrint(
        '[SetlistRepository] updateSongTitleArtist: songId=$songId, title=$title, artist=$artist',
      );
    }

    try {
      // Use RPC with SECURITY DEFINER to bypass RLS for songs with NULL band_id
      // Must pass ALL 8 parameters to avoid PGRST203 function overload ambiguity
      final result = await supabase.rpc(
        'update_song_metadata',
        params: {
          'p_song_id': songId,
          'p_band_id': bandId,
          'p_bpm': null,
          'p_duration_seconds': null,
          'p_tuning': null,
          'p_notes': null,
          'p_title': title,
          'p_artist': artist,
        },
      );

      // Check RPC result
      if (result is Map && result['success'] == false) {
        final error = result['error'] ?? 'Unknown error';
        debugPrint('[SetlistRepository] RPC returned error: $error');
        throw Exception(error);
      }

      debugPrint(
        '[SetlistRepository] ✓ Updated title/artist for song $songId (via RPC)',
      );
    } on PostgrestException catch (e) {
      // RPC may not exist - fall back to direct update
      if (e.code == 'PGRST202' || e.code == '42883') {
        debugPrint(
          '[SetlistRepository] update_song_metadata RPC not found, falling back to direct update',
        );
        final updates = <String, dynamic>{};
        if (title != null) updates['title'] = title;
        if (artist != null) updates['artist'] = artist;
        await supabase.from('songs').update(updates).eq('id', songId);
        debugPrint(
          '[SetlistRepository] ✓ Updated title/artist for song $songId (direct)',
        );
        return;
      }
      debugPrint('[SetlistRepository] ❌ PostgrestException: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] ❌ Error updating title/artist: $e');
      rethrow;
    }
  }

  // ==========================================================================
  // DELETE SETLIST
  // ==========================================================================

  /// Deletes a setlist and all associated setlist_songs.
  ///
  /// [bandId] - Required for band isolation verification
  /// [setlistId] - The setlist to delete
  ///
  /// IMPORTANT: Cannot delete the Catalog setlist.
  /// The cascade delete of setlist_songs happens automatically via FK constraint.
  /// Deletes a setlist using server-side RPC for bulletproof deletion.
  ///
  /// The RPC handles:
  /// - Permission checks (must be admin or creator)
  /// - Catalog protection (cannot delete Catalog or "All Songs")
  /// - Dependent row cleanup (setlist_songs, rehearsals, gigs references)
  ///
  /// Falls back to direct delete if RPC is not available.
  Future<void> deleteSetlist({
    required String bandId,
    required String setlistId,
  }) async {
    debugPrint(
      '[SetlistRepository] deleteSetlist called: bandId=$bandId, setlistId=$setlistId',
    );

    if (bandId.isEmpty) {
      debugPrint('[SetlistRepository] deleteSetlist failed: bandId is empty');
      throw NoBandSelectedError();
    }
    if (setlistId.isEmpty) {
      debugPrint(
        '[SetlistRepository] deleteSetlist failed: setlistId is empty',
      );
      throw ArgumentError('setlistId cannot be empty');
    }

    try {
      // Try server-side RPC first (handles permissions, FK cleanup, Catalog protection)
      debugPrint('[SetlistRepository] trying delete_setlist RPC...');
      await supabase.rpc(
        'delete_setlist',
        params: {'p_band_id': bandId, 'p_setlist_id': setlistId},
      );

      debugPrint('[SetlistRepository] Deleted setlist $setlistId via RPC');
    } on PostgrestException catch (e) {
      debugPrint(
        '[SetlistRepository] deleteSetlist PostgrestException: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}',
      );

      // Parse error messages from the RPC
      final message = e.message.toLowerCase();

      if (message.contains('catalog')) {
        throw SetlistQueryError(
          code: 'CATALOG_PROTECTED',
          message: 'Cannot delete the Catalog setlist',
          reason: 'catalog_protected',
        );
      }

      if (message.contains('not found') ||
          message.contains('does not belong')) {
        throw SetlistQueryError(
          code: 'NOT_FOUND',
          message: 'Setlist not found or does not belong to this band',
          reason: 'not_found',
        );
      }

      if (message.contains('permission') || message.contains('access denied')) {
        throw SetlistQueryError(
          code: 'PERMISSION_DENIED',
          message: 'You do not have permission to delete this setlist',
          reason: 'permission_denied',
        );
      }

      // RPC doesn't exist yet - fall back to direct delete
      if (e.code == '42883' ||
          e.code == 'PGRST202' ||
          message.contains('does not exist')) {
        debugPrint(
          '[SetlistRepository] delete_setlist RPC not found (code=${e.code}), falling back to direct delete',
        );
        await _deleteSetlistDirectly(bandId: bandId, setlistId: setlistId);
        return;
      }

      throw SetlistQueryError(
        code: e.code ?? 'UNKNOWN',
        message: e.message,
        details: e.details?.toString(),
        hint: e.hint,
      );
    } catch (e) {
      debugPrint('[SetlistRepository] deleteSetlist error: $e');
      if (e is SetlistQueryError) rethrow;
      throw SetlistQueryError(
        code: 'UNEXPECTED',
        message: e.toString(),
        reason: 'unexpected',
      );
    }
  }

  /// Fallback direct delete method when RPC is not available.
  Future<void> _deleteSetlistDirectly({
    required String bandId,
    required String setlistId,
  }) async {
    debugPrint(
      '[SetlistRepository] _deleteSetlistDirectly: bandId=$bandId, setlistId=$setlistId',
    );

    try {
      // Verify setlist exists and belongs to this band
      // Don't select is_catalog as it may not exist in all environments
      final setlistCheck = await supabase
          .from('setlists')
          .select('id, name, band_id')
          .eq('id', setlistId)
          .eq('band_id', bandId)
          .maybeSingle();

      if (setlistCheck == null) {
        debugPrint(
          '[SetlistRepository] delete failed: setlist not found or wrong band',
        );
        throw SetlistQueryError(
          code: 'NOT_FOUND',
          message: 'Setlist not found or does not belong to this band',
          reason: 'not_found',
        );
      }

      // Prevent deletion of Catalog (check by name since is_catalog column may not exist)
      final name = setlistCheck['name'] as String? ?? '';
      if (isCatalogName(name)) {
        debugPrint('[SetlistRepository] delete failed: cannot delete Catalog');
        throw SetlistQueryError(
          code: 'CATALOG_PROTECTED',
          message: 'Cannot delete the Catalog setlist',
          reason: 'catalog_protected',
        );
      }

      // Delete setlist_songs first (FK constraint)
      await supabase.from('setlist_songs').delete().eq('setlist_id', setlistId);
      debugPrint('[SetlistRepository] deleted setlist_songs for $setlistId');

      // Delete the setlist
      await supabase
          .from('setlists')
          .delete()
          .eq('id', setlistId)
          .eq('band_id', bandId);

      debugPrint('[SetlistRepository] Deleted setlist $setlistId directly');
    } on PostgrestException catch (e) {
      debugPrint(
        '[SetlistRepository] _deleteSetlistDirectly PostgrestException: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}',
      );
      rethrow;
    } catch (e) {
      debugPrint('[SetlistRepository] _deleteSetlistDirectly error: $e');
      rethrow;
    }
  }

  // ==========================================================================
  // DUPLICATE SETLIST
  // ==========================================================================

  /// Duplicates a setlist with all its songs and overrides.
  ///
  /// [bandId] - Required for band isolation verification
  /// [setlistId] - The setlist to duplicate
  ///
  /// NAMING CONVENTION:
  /// - First copy: "Original Name (Copy)"
  /// - Subsequent copies: "Original Name (Copy 2)", "(Copy 3)", etc.
  ///
  /// Returns the new setlist's ID.
  ///
  /// NOTE: Catalog can be duplicated to create new setlists from it.
  Future<String> duplicateSetlist({
    required String bandId,
    required String setlistId,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }
    if (setlistId.isEmpty) {
      throw ArgumentError('setlistId cannot be empty');
    }

    try {
      // Step 1: Fetch the source setlist
      final sourceSetlist = await supabase
          .from('setlists')
          .select('id, name, band_id, total_duration')
          .eq('id', setlistId)
          .eq('band_id', bandId)
          .maybeSingle();

      if (sourceSetlist == null) {
        throw SetlistQueryError(
          code: 'NOT_FOUND',
          message: 'Setlist not found or does not belong to this band',
          reason: 'not_found',
        );
      }

      // Get the source name for generating copy name
      final sourceName = sourceSetlist['name'] as String;

      // Step 3: Generate unique name for the copy
      final newName = await _generateCopyName(
        bandId: bandId,
        originalName: sourceName,
      );

      // Step 4: Create the new setlist (must include created_by for RLS)
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw SetlistQueryError(
          code: 'AUTH_REQUIRED',
          message: 'You must be logged in to duplicate a setlist',
          reason: 'no_auth',
        );
      }

      final newSetlistResponse = await supabase
          .from('setlists')
          .insert({
            'name': newName,
            'band_id': bandId,
            'created_by': userId,
            'total_duration': sourceSetlist['total_duration'] ?? 0,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();

      final newSetlistId = newSetlistResponse['id'] as String;

      // Step 5: Copy all setlist_songs with their overrides
      final sourceSongs = await supabase
          .from('setlist_songs')
          .select('song_id, position, bpm, tuning, duration_seconds')
          .eq('setlist_id', setlistId)
          .order('position', ascending: true);

      if (sourceSongs.isNotEmpty) {
        final newSongs = sourceSongs.map((song) {
          return {
            'setlist_id': newSetlistId,
            'song_id': song['song_id'],
            'position': song['position'],
            'bpm': song['bpm'],
            'tuning': song['tuning'],
            'duration_seconds': song['duration_seconds'],
          };
        }).toList();

        await supabase.from('setlist_songs').insert(newSongs);
      }

      debugPrint(
        '[SetlistRepository] Duplicated setlist $setlistId to $newSetlistId as "$newName"',
      );
      return newSetlistId;
    } on SetlistQueryError {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint(
        '[SetlistRepository] PostgrestException duplicating setlist: $e',
      );
      throw SetlistQueryError(
        code: e.code ?? 'UNKNOWN',
        message: e.message,
        details: e.details?.toString(),
        hint: e.hint,
      );
    } catch (e) {
      debugPrint('[SetlistRepository] Error duplicating setlist: $e');
      throw SetlistQueryError(
        code: 'UNEXPECTED',
        message: e.toString(),
        reason: 'unexpected',
      );
    }
  }

  // ==========================================================================
  // CREATE NEW SETLIST
  // ==========================================================================

  /// Creates a new empty setlist with the given name.
  ///
  /// [bandId] - Required for band isolation
  /// [name] - The name for the new setlist
  ///
  /// Returns the created [Setlist] object.
  /// Throws [SetlistQueryError] on failure.
  Future<Setlist> createSetlist({
    required String bandId,
    required String name,
  }) async {
    // Validate inputs
    if (bandId.isEmpty) {
      debugPrint('[SetlistRepository] createSetlist failed: bandId is empty');
      throw NoBandSelectedError();
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      debugPrint('[SetlistRepository] createSetlist failed: name is empty');
      throw ArgumentError('Setlist name cannot be empty');
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint(
        '[SetlistRepository] createSetlist failed: no authenticated user',
      );
      throw SetlistQueryError(
        code: 'AUTH_REQUIRED',
        message: 'You must be logged in to create a setlist',
        reason: 'no_auth',
      );
    }

    // Build the insert payload matching the database schema
    final payload = {
      'name': trimmedName,
      'band_id': bandId,
      'created_by': userId,
      'total_duration': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    debugPrint(
      '[SetlistRepository] createSetlist tapped: bandId=$bandId, userId=$userId',
    );
    debugPrint('[SetlistRepository] insert payload: $payload');

    try {
      final response = await supabase
          .from('setlists')
          .insert(payload)
          .select('id, name, band_id, total_duration')
          .single();

      debugPrint(
        '[SetlistRepository] insert ok: id=${response['id']}, name=${response['name']}, bandId=${response['band_id']}',
      );

      final totalSeconds = response['total_duration'] as int? ?? 0;

      return Setlist(
        id: response['id'] as String,
        name: response['name'] as String,
        bandId: response['band_id'] as String,
        songCount: 0,
        totalDuration: Duration(seconds: totalSeconds),
        isCatalog: false,
      );
    } on PostgrestException catch (e) {
      debugPrint(
        '[SetlistRepository] insert failed: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}',
      );
      throw SetlistQueryError(
        code: e.code ?? 'UNKNOWN',
        message: e.message,
        details: e.details?.toString(),
        hint: e.hint,
      );
    } catch (e) {
      debugPrint('[SetlistRepository] insert failed (unexpected): $e');
      throw SetlistQueryError(
        code: 'UNEXPECTED',
        message: e.toString(),
        reason: 'unexpected',
      );
    }
  }

  // ==========================================================================
  // RENAME SETLIST
  // ==========================================================================

  /// Renames an existing setlist.
  ///
  /// [bandId] - Required for band isolation verification
  /// [setlistId] - The setlist to rename
  /// [newName] - The new name for the setlist
  ///
  /// Returns the updated [Setlist] object.
  /// Throws [SetlistQueryError] on failure.
  Future<Setlist> renameSetlist({
    required String bandId,
    required String setlistId,
    required String newName,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }
    if (setlistId.isEmpty) {
      throw ArgumentError('setlistId cannot be empty');
    }
    if (newName.trim().isEmpty) {
      throw ArgumentError('New name cannot be empty');
    }

    try {
      // First verify the setlist belongs to this band and is not a Catalog
      final existingSetlist = await supabase
          .from('setlists')
          .select('id, name')
          .eq('id', setlistId)
          .eq('band_id', bandId)
          .maybeSingle();

      if (existingSetlist == null) {
        throw SetlistQueryError(
          code: 'NOT_FOUND',
          message: 'Setlist not found or does not belong to this band',
          reason: 'not_found',
        );
      }

      // Check if this is the Catalog by name
      final existingName = existingSetlist['name'] as String? ?? '';
      if (existingName.toLowerCase() == 'catalog') {
        throw SetlistQueryError(
          code: 'CATALOG_PROTECTED',
          message: 'Cannot rename the Catalog setlist',
          reason: 'catalog_protected',
        );
      }

      // Perform the update
      final response = await supabase
          .from('setlists')
          .update({'name': newName.trim()})
          .eq('id', setlistId)
          .eq('band_id', bandId)
          .select('id, name, band_id, total_duration')
          .single();

      debugPrint(
        '[SetlistRepository] Renamed setlist $setlistId to "${response['name']}"',
      );

      final totalSeconds = response['total_duration'] as int? ?? 0;

      return Setlist(
        id: response['id'] as String,
        name: response['name'] as String,
        bandId: response['band_id'] as String,
        songCount:
            0, // We don't have song count here, but it's not critical for rename
        totalDuration: Duration(seconds: totalSeconds),
        isCatalog: false,
      );
    } on SetlistQueryError {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('[SetlistRepository] PostgrestException renaming setlist: $e');
      throw SetlistQueryError(
        code: e.code ?? 'UNKNOWN',
        message: e.message,
        details: e.details?.toString(),
        hint: e.hint,
      );
    } catch (e) {
      debugPrint('[SetlistRepository] Error renaming setlist: $e');
      throw SetlistQueryError(
        code: 'UNEXPECTED',
        message: e.toString(),
        reason: 'unexpected',
      );
    }
  }

  /// Generates a unique copy name following the pattern:
  /// "Name (Copy)", "Name (Copy 2)", "Name (Copy 3)", etc.
  Future<String> _generateCopyName({
    required String bandId,
    required String originalName,
  }) async {
    // Get all existing setlist names in this band
    final existingSetlists = await supabase
        .from('setlists')
        .select('name')
        .eq('band_id', bandId);

    final existingNames = existingSetlists
        .map<String>((s) => s['name'] as String)
        .toSet();

    // Try "Name (Copy)" first
    final baseCopyName = '$originalName (Copy)';
    if (!existingNames.contains(baseCopyName)) {
      return baseCopyName;
    }

    // Try "Name (Copy 2)", "Name (Copy 3)", etc.
    int copyNumber = 2;
    while (true) {
      final candidateName = '$originalName (Copy $copyNumber)';
      if (!existingNames.contains(candidateName)) {
        return candidateName;
      }
      copyNumber++;
      // Safety limit to prevent infinite loops
      if (copyNumber > 100) {
        return '$originalName (Copy ${DateTime.now().millisecondsSinceEpoch})';
      }
    }
  }

  // ==========================================================================
  // ENSURE CATALOG SETLIST EXISTS
  // ==========================================================================

  /// Ensures a band has exactly one Catalog setlist.
  /// Creates one if it doesn't exist, returns existing if it does.
  /// Also handles deduplication if multiple exist.
  ///
  /// [bandId] - Required for band isolation
  ///
  /// Returns the Catalog setlist's ID.
  ///
  /// Uses the database RPC function for atomic creation.
  /// Falls back to client-side logic if RPC doesn't exist.
  Future<String> ensureCatalogSetlist(String bandId) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    try {
      // Call the database function which handles:
      // - Creating Catalog if none exists
      // - Deduplicating if multiple exist
      // - Renaming "All Songs" to "Catalog"
      final result = await supabase.rpc(
        'ensure_catalog_setlist',
        params: {'p_band_id': bandId},
      );

      final catalogId = result as String?;
      if (catalogId == null || catalogId.isEmpty) {
        throw SetlistQueryError(
          code: 'NO_CATALOG',
          message: 'Failed to create or find Catalog setlist',
          reason: 'no_catalog_returned',
        );
      }

      if (kDebugMode) {
        debugPrint('[SetlistRepository] Catalog ensured via RPC: $catalogId');
      }
      return catalogId;
    } on PostgrestException catch (e) {
      // Check if it's a "function doesn't exist" error
      // PGRST202: Function not found in schema cache
      // 42883: Function does not exist (PostgreSQL error)
      final isFunctionNotFound =
          e.code == 'PGRST202' ||
          e.code == '42883' ||
          e.message.contains('does not exist') ||
          e.message.contains('could not find');
      if (isFunctionNotFound) {
        if (kDebugMode) {
          debugPrint(
            '[SetlistRepository] ensure_catalog_setlist RPC not found (${e.code}), using client-side fallback',
          );
        }
        // Fall back to client-side deduplication
        return await _ensureCatalogClientSide(bandId);
      }
      debugPrint('[SetlistRepository] PostgrestException ensuring Catalog: $e');
      throw SetlistQueryError(
        code: e.code ?? 'UNKNOWN',
        message: e.message,
        details: e.details?.toString(),
        hint: e.hint,
      );
    } catch (e) {
      debugPrint('[SetlistRepository] Error ensuring Catalog: $e');
      throw SetlistQueryError(
        code: 'UNEXPECTED',
        message: e.toString(),
        reason: 'unexpected',
      );
    }
  }

  /// Client-side fallback for ensuring Catalog exists when RPC is unavailable.
  Future<String> _ensureCatalogClientSide(String bandId) async {
    // Try to find existing Catalog by setlist_type first (this exists in the schema)
    try {
      final byType = await supabase
          .from('setlists')
          .select('id, name')
          .eq('band_id', bandId)
          .eq('setlist_type', 'catalog')
          .limit(1);

      if ((byType as List).isNotEmpty) {
        return byType[0]['id'] as String;
      }
    } catch (e) {
      // setlist_type column may not exist in all environments
    }

    // Try to find existing Catalog by is_catalog flag
    try {
      final existing = await supabase
          .from('setlists')
          .select('id, name')
          .eq('band_id', bandId)
          .eq('is_catalog', true)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        return existing[0]['id'] as String;
      }
    } catch (e) {
      // is_catalog column may not exist
    }

    // Try to find by name
    try {
      final byName = await supabase
          .from('setlists')
          .select('id, name')
          .eq('band_id', bandId)
          .or('name.ilike.Catalog,name.ilike.All Songs')
          .order('created_at', ascending: true)
          .limit(1);

      if ((byName as List).isNotEmpty) {
        final id = byName[0]['id'] as String;
        final name = byName[0]['name'] as String;
        // Rename to Catalog if needed
        if (name.toLowerCase() != 'catalog') {
          await _ensureCatalogMetadata(id, name);
        }
        return id;
      }
    } catch (e) {
      // Query failed
    }

    // Create new Catalog (try multiple column combinations)
    try {
      // Try with setlist_type first (preferred schema)
      try {
        final newCatalog = await supabase
            .from('setlists')
            .insert({
              'band_id': bandId,
              'name': kCatalogSetlistName,
              'setlist_type': 'catalog',
              'is_catalog': true,
              'total_duration': 0,
            })
            .select('id')
            .single();

        if (kDebugMode) {
          debugPrint(
            '[SetlistRepository] Created Catalog via client-side: ${newCatalog['id']}',
          );
        }
        return newCatalog['id'] as String;
      } on PostgrestException catch (e) {
        if (e.code == '42703') {
          // Column doesn't exist, try with just setlist_type
          try {
            final newCatalog = await supabase
                .from('setlists')
                .insert({
                  'band_id': bandId,
                  'name': kCatalogSetlistName,
                  'setlist_type': 'catalog',
                  'total_duration': 0,
                })
                .select('id')
                .single();

            if (kDebugMode) {
              debugPrint(
                '[SetlistRepository] Created Catalog via client-side (setlist_type only): ${newCatalog['id']}',
              );
            }
            return newCatalog['id'] as String;
          } on PostgrestException {
            // Try with just is_catalog
            final newCatalog = await supabase
                .from('setlists')
                .insert({
                  'band_id': bandId,
                  'name': kCatalogSetlistName,
                  'is_catalog': true,
                  'total_duration': 0,
                })
                .select('id')
                .single();

            if (kDebugMode) {
              debugPrint(
                '[SetlistRepository] Created Catalog via client-side (is_catalog only): ${newCatalog['id']}',
              );
            }
            return newCatalog['id'] as String;
          }
        }
        rethrow;
      }
    } catch (e) {
      // Last resort: create with just name
      try {
        final newCatalog = await supabase
            .from('setlists')
            .insert({
              'band_id': bandId,
              'name': kCatalogSetlistName,
              'total_duration': 0,
            })
            .select('id')
            .single();

        if (kDebugMode) {
          debugPrint(
            '[SetlistRepository] Created Catalog via client-side (name only): ${newCatalog['id']}',
          );
        }
        return newCatalog['id'] as String;
      } catch (finalError) {
        debugPrint(
          '[SetlistRepository] Error creating Catalog client-side: $finalError',
        );
        throw SetlistQueryError(
          code: 'CREATE_FAILED',
          message: 'Failed to create Catalog setlist',
          reason: 'client_side_create_failed',
        );
      }
    }
  }

  /// Gets the Catalog setlist for a band, or null if not found.
  ///
  /// [bandId] - Required for band isolation
  ///
  /// Returns the Catalog setlist if found, null otherwise.
  Future<Setlist?> getCatalogSetlist(String bandId) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    try {
      // Try with setlist_type first (preferred schema)
      Map<String, dynamic>? response;
      try {
        response = await supabase
            .from('setlists')
            .select('''
              id,
              name,
              band_id,
              total_duration,
              is_catalog,
              setlist_type,
              created_at,
              updated_at,
              setlist_songs(count)
            ''')
            .eq('band_id', bandId)
            .eq('setlist_type', 'catalog')
            .maybeSingle();
      } on PostgrestException {
        // setlist_type column may not exist, try is_catalog
        response = await supabase
            .from('setlists')
            .select('''
              id,
              name,
              band_id,
              total_duration,
              is_catalog,
              created_at,
              updated_at,
              setlist_songs(count)
            ''')
            .eq('band_id', bandId)
            .eq('is_catalog', true)
            .maybeSingle();
      }

      response ??= await supabase
          .from('setlists')
          .select('''
              id,
              name,
              band_id,
              total_duration,
              created_at,
              updated_at,
              setlist_songs(count)
            ''')
          .eq('band_id', bandId)
          .or('name.ilike.Catalog,name.ilike.All Songs')
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      // Extract song count
      int songCount = 0;
      if (response['setlist_songs'] != null) {
        final countData = response['setlist_songs'] as List;
        if (countData.isNotEmpty && countData[0] is Map) {
          songCount = (countData[0] as Map)['count'] as int? ?? 0;
        }
      }

      final flatJson = Map<String, dynamic>.from(response);
      flatJson['song_count'] = songCount;

      return Setlist.fromSupabase(flatJson);
    } on PostgrestException catch (e) {
      debugPrint('[SetlistRepository] PostgrestException getting Catalog: $e');
      throw SetlistQueryError(
        code: e.code ?? 'UNKNOWN',
        message: e.message,
        details: e.details?.toString(),
        hint: e.hint,
      );
    } catch (e) {
      debugPrint('[SetlistRepository] Error getting Catalog: $e');
      throw SetlistQueryError(
        code: 'UNEXPECTED',
        message: e.toString(),
        reason: 'unexpected',
      );
    }
  }

  // ==========================================================================
  // SONG SEARCH
  // ==========================================================================

  /// Fetches all songs for a band (for local filtering).
  /// This is more efficient than repeated server queries when user types.
  ///
  /// [bandId] - Required for band isolation
  ///
  /// Returns list of Song objects.
  Future<List<Song>> fetchSongsForBand(String bandId) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    try {
      final response = await supabase
          .from('songs')
          .select('''
            id,
            title,
            artist,
            bpm,
            duration_seconds,
            tuning,
            album_artwork,
            band_id
          ''')
          .eq('band_id', bandId)
          .order('title', ascending: true);

      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Fetched ${response.length} songs for band $bandId',
        );
      }

      return (response as List).map((json) => Song.fromSupabase(json)).toList();
    } on PostgrestException catch (e) {
      debugPrint('[SetlistRepository] Error fetching songs: $e');
      rethrow;
    }
  }

  // ==========================================================================
  // UPSERT EXTERNAL SONG
  // ==========================================================================

  /// Upserts an external song (from Spotify/MusicBrainz) into the songs table.
  ///
  /// Uses the unique constraint (band_id, title, artist) for conflict resolution.
  /// On conflict:
  /// - Updates missing fields (bpm, spotify_id, musicbrainz_id, album_artwork, duration_seconds)
  /// - Does NOT overwrite user-edited tuning unless it is null
  ///
  /// [bandId] - Required for band isolation
  /// [title] - Song title (required)
  /// [artist] - Artist name (required)
  /// [bpm] - BPM (optional)
  /// [durationSeconds] - Duration in seconds (optional)
  /// [albumArtwork] - Album artwork URL (optional)
  /// [spotifyId] - Spotify track ID (optional)
  /// [musicbrainzId] - MusicBrainz recording ID (optional)
  ///
  /// Returns the song ID (existing or newly created).
  Future<String?> upsertExternalSong({
    required String bandId,
    required String title,
    required String artist,
    int? bpm,
    int? durationSeconds,
    String? albumArtwork,
    String? spotifyId,
    String? musicbrainzId,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    if (title.trim().isEmpty || artist.trim().isEmpty) {
      debugPrint(
        '[SetlistRepository] upsertExternalSong: title and artist are required',
      );
      return null;
    }

    // Apply title case to normalize song title and artist
    final normalizedTitle = toTitleCase(title.trim());
    final normalizedArtist = toTitleCase(artist.trim());

    debugPrint(
      '[SetlistRepository] upsertExternalSong: "$normalizedTitle" by $normalizedArtist',
    );

    try {
      // First check if song already exists
      final existing = await supabase
          .from('songs')
          .select(
            'id, tuning, bpm, spotify_id, musicbrainz_id, album_artwork, duration_seconds',
          )
          .eq('band_id', bandId)
          .ilike('title', normalizedTitle)
          .ilike('artist', normalizedArtist)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        final existingRow = existing[0];
        final existingId = existingRow['id'] as String;

        // Update missing fields only
        final updates = <String, dynamic>{};

        if (bpm != null && existingRow['bpm'] == null) {
          updates['bpm'] = bpm;
        }
        if (spotifyId != null && existingRow['spotify_id'] == null) {
          updates['spotify_id'] = spotifyId;
        }
        if (musicbrainzId != null && existingRow['musicbrainz_id'] == null) {
          updates['musicbrainz_id'] = musicbrainzId;
        }
        if (albumArtwork != null && existingRow['album_artwork'] == null) {
          updates['album_artwork'] = albumArtwork;
        }
        if (durationSeconds != null &&
            existingRow['duration_seconds'] == null) {
          updates['duration_seconds'] = durationSeconds;
        }

        if (updates.isNotEmpty) {
          updates['updated_at'] = DateTime.now().toIso8601String();
          await supabase.from('songs').update(updates).eq('id', existingId);
          if (kDebugMode) {
            debugPrint(
              '[SetlistRepository] Updated existing song $existingId with: ${updates.keys.join(', ')}',
            );
          }
        } else if (kDebugMode) {
          debugPrint(
            '[SetlistRepository] Song already exists, no updates needed: $existingId',
          );
        }

        return existingId;
      }

      // Create new song
      final insertData = <String, dynamic>{
        'band_id': bandId,
        'title': normalizedTitle,
        'artist': normalizedArtist,
        'tuning': 'standard', // Default tuning
      };

      if (bpm != null) {
        insertData['bpm'] = bpm;
      }
      if (durationSeconds != null) {
        insertData['duration_seconds'] = durationSeconds;
      }
      if (albumArtwork != null) {
        insertData['album_artwork'] = albumArtwork;
      }
      if (spotifyId != null) {
        insertData['spotify_id'] = spotifyId;
      }
      if (musicbrainzId != null) {
        insertData['musicbrainz_id'] = musicbrainzId;
      }

      final result = await supabase
          .from('songs')
          .insert(insertData)
          .select('id')
          .single();

      final newId = result['id'] as String;
      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Created external song: "$normalizedTitle" by $normalizedArtist -> $newId',
        );
      }
      return newId;
    } on PostgrestException catch (e) {
      // Handle unique constraint violation (race condition)
      if (e.code == '23505') {
        final existing = await supabase
            .from('songs')
            .select('id')
            .eq('band_id', bandId)
            .ilike('title', normalizedTitle)
            .ilike('artist', normalizedArtist)
            .limit(1);

        if ((existing as List).isNotEmpty) {
          return existing[0]['id'] as String;
        }
      }
      // RLS violation
      if (e.code == '42501') {
        debugPrint('[SetlistRepository] RLS ERROR upserting external song: $e');
        debugPrint('[SetlistRepository]   bandId: $bandId');
        debugPrint(
          '[SetlistRepository]   userId: ${supabase.auth.currentUser?.id}',
        );
      } else {
        debugPrint('[SetlistRepository] Error upserting external song: $e');
      }
      return null;
    } catch (e) {
      debugPrint(
        '[SetlistRepository] Unexpected error upserting external song: $e',
      );
      return null;
    }
  }

  // ==========================================================================
  // ADD SONG TO SETLIST (WITH CATALOG GUARANTEE)
  // ==========================================================================

  /// Adds a song to a setlist, ensuring it's also in the Catalog.
  ///
  /// This is the primary method for adding songs to any setlist.
  /// Guarantees:
  /// 1. Song is always added to Catalog first
  /// 2. No duplicates are created
  /// 3. Returns friendly status about what happened
  ///
  /// [bandId] - Required for Catalog lookup
  /// [setlistId] - The target setlist
  /// [songId] - The song to add
  /// [songTitle] - For friendly messaging
  /// [songArtist] - For friendly messaging
  Future<AddSongResult> addSongToSetlistEnsureCatalog({
    required String bandId,
    required String setlistId,
    required String songId,
    required String songTitle,
    required String songArtist,
  }) async {
    if (bandId.isEmpty || setlistId.isEmpty || songId.isEmpty) {
      throw ArgumentError('bandId, setlistId, and songId cannot be empty');
    }

    try {
      // Step 1: Ensure Catalog exists and get its ID
      final catalogId = await ensureCatalogSetlist(bandId);
      final targetIsCatalog = setlistId == catalogId;

      // Step 2: Check if song is already in Catalog
      final existingCatalog = await supabase
          .from('setlist_songs')
          .select('id')
          .eq('setlist_id', catalogId)
          .eq('song_id', songId)
          .limit(1);

      final wasAlreadyInCatalog = (existingCatalog as List).isNotEmpty;

      // Step 3: Add to Catalog if not already there
      if (!wasAlreadyInCatalog) {
        await addSongToSetlist(setlistId: catalogId, songId: songId);
        if (kDebugMode) {
          debugPrint('[SetlistRepository] Added song $songId to Catalog');
        }
      }

      // Step 4: If target is Catalog, we're done
      if (targetIsCatalog) {
        final catalogSongId = wasAlreadyInCatalog
            ? (existingCatalog as List)[0]['id'] as String
            : (await supabase
                          .from('setlist_songs')
                          .select('id')
                          .eq('setlist_id', catalogId)
                          .eq('song_id', songId)
                          .limit(1)
                      as List)[0]['id']
                  as String;

        return AddSongResult(
          setlistSongId: catalogSongId,
          wasAlreadyInCatalog: wasAlreadyInCatalog,
          wasAlreadyInSetlist: wasAlreadyInCatalog,
          songTitle: songTitle,
          songArtist: songArtist,
        );
      }

      // Step 5: Check if song is already in target setlist
      final existingTarget = await supabase
          .from('setlist_songs')
          .select('id')
          .eq('setlist_id', setlistId)
          .eq('song_id', songId)
          .limit(1);

      if ((existingTarget as List).isNotEmpty) {
        return AddSongResult(
          setlistSongId: existingTarget[0]['id'] as String,
          wasAlreadyInCatalog: wasAlreadyInCatalog,
          wasAlreadyInSetlist: true,
          songTitle: songTitle,
          songArtist: songArtist,
        );
      }

      // Step 6: Add to target setlist
      final setlistSongId = await addSongToSetlist(
        setlistId: setlistId,
        songId: songId,
      );

      return AddSongResult(
        setlistSongId: setlistSongId,
        wasAlreadyInCatalog: wasAlreadyInCatalog,
        wasAlreadyInSetlist: false,
        songTitle: songTitle,
        songArtist: songArtist,
      );
    } catch (e) {
      debugPrint(
        '[SetlistRepository] Error in addSongToSetlistEnsureCatalog: $e',
      );
      return AddSongResult(
        setlistSongId: null,
        songTitle: songTitle,
        songArtist: songArtist,
      );
    }
  }

  // ==========================================================================
  // ADD SONG TO SETLIST (LOW-LEVEL)
  // ==========================================================================

  /// Adds a song to a setlist at the end position.
  ///
  /// If the song is already in the setlist, this is a no-op (returns true).
  /// The Catalog auto-add trigger handles ensuring song is also in Catalog.
  ///
  /// [setlistId] - The setlist to add to
  /// [songId] - The song to add
  ///
  /// Returns the setlist_songs ID if successful (or existing ID if already exists),
  /// null on error.
  Future<String?> addSongToSetlist({
    required String setlistId,
    required String songId,
  }) async {
    if (setlistId.isEmpty || songId.isEmpty) {
      throw ArgumentError('setlistId and songId cannot be empty');
    }

    try {
      // First check if already exists
      final existing = await supabase
          .from('setlist_songs')
          .select('id')
          .eq('setlist_id', setlistId)
          .eq('song_id', songId)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        final existingId = existing[0]['id'] as String;
        if (kDebugMode) {
          debugPrint(
            '[SetlistRepository] Song $songId already in setlist $setlistId',
          );
        }
        return existingId;
      }

      // Get the current max position
      final positionResult = await supabase
          .from('setlist_songs')
          .select('position')
          .eq('setlist_id', setlistId)
          .order('position', ascending: false)
          .limit(1);

      int nextPosition = 0;
      if ((positionResult as List).isNotEmpty) {
        nextPosition = (positionResult[0]['position'] as int? ?? 0) + 1;
      }

      // Insert the song at the end and get the ID
      // IMPORTANT: Explicitly set override fields to null to prevent DB defaults
      // from applying (e.g., tuning DEFAULT 'standard' would override song's actual tuning)
      final result = await supabase
          .from('setlist_songs')
          .insert({
            'setlist_id': setlistId,
            'song_id': songId,
            'position': nextPosition,
            // Override fields - null means "use song's value"
            'bpm': null,
            'tuning': null,
            'duration_seconds': null,
          })
          .select('id')
          .single();

      final insertedId = result['id'] as String;

      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Added song $songId to setlist $setlistId at position $nextPosition -> $insertedId',
        );
      }

      return insertedId;
    } on PostgrestException catch (e) {
      // Handle duplicate key error (song already in setlist)
      if (e.code == '23505') {
        // Try to get the existing ID
        final existing = await supabase
            .from('setlist_songs')
            .select('id')
            .eq('setlist_id', setlistId)
            .eq('song_id', songId)
            .limit(1);

        if ((existing as List).isNotEmpty) {
          return existing[0]['id'] as String;
        }
        return null;
      }
      debugPrint('[SetlistRepository] Error adding song to setlist: $e');
      return null;
    } catch (e) {
      debugPrint('[SetlistRepository] Unexpected error adding song: $e');
      return null;
    }
  }

  // ==========================================================================
  // BULK ADD SONGS
  // ==========================================================================

  /// Result of bulk add operation
  static const _bulkAddBatchSize = 50;

  /// Bulk add songs from parsed rows.
  ///
  /// This method:
  /// 1. Ensures Catalog setlist exists
  /// 2. Creates/upserts songs in public.songs
  /// 3. Adds songs to both Catalog and the target setlist
  ///
  /// [bandId] - Required for band scoping
  /// [setlistId] - Target setlist to add songs to
  /// [rows] - Parsed and validated BulkSongRow objects
  ///
  /// Returns [BulkAddResult] with count and IDs for undo support.
  /// Throws [SetlistQueryError] on failure.
  Future<BulkAddResult> bulkAddSongs({
    required String bandId,
    required String setlistId,
    required List<BulkSongRow> rows,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }
    if (setlistId.isEmpty) {
      throw ArgumentError('setlistId cannot be empty');
    }
    if (rows.isEmpty) {
      return const BulkAddResult(addedCount: 0, setlistSongIds: []);
    }

    // Filter to only valid rows
    final validRows = rows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) {
      return const BulkAddResult(addedCount: 0, setlistSongIds: []);
    }

    try {
      // Step 0: Verify user is a band member (diagnostic)
      final userId = supabase.auth.currentUser?.id;
      if (kDebugMode) {
        debugPrint('[SetlistRepository] Checking band membership...');
        debugPrint('[SetlistRepository]   userId: $userId');
        debugPrint('[SetlistRepository]   bandId: $bandId');

        final memberCheck = await supabase
            .from('band_members')
            .select('status')
            .eq('band_id', bandId)
            .eq('user_id', userId!)
            .maybeSingle();

        debugPrint('[SetlistRepository]   memberCheck result: $memberCheck');
        if (memberCheck == null) {
          debugPrint(
            '[SetlistRepository]   ⚠️ User is NOT in band_members table for this band!',
          );
        } else if (memberCheck['status'] != 'active') {
          debugPrint(
            '[SetlistRepository]   ⚠️ User membership status is: ${memberCheck['status']} (not active)',
          );
        } else {
          debugPrint('[SetlistRepository]   ✓ User is an active band member');
        }
      }

      // Step 1: Ensure Catalog exists
      final catalogId = await ensureCatalogSetlist(bandId);
      final isCatalog = setlistId == catalogId;

      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Bulk adding ${validRows.length} songs to band $bandId',
        );
        debugPrint('[SetlistRepository] Catalog ID: $catalogId');
        debugPrint('[SetlistRepository] Target setlist is Catalog: $isCatalog');
      }

      var addedCount = 0;
      final addedSetlistSongIds = <String>[];

      // Process in batches to avoid timeout
      for (var i = 0; i < validRows.length; i += _bulkAddBatchSize) {
        final batch = validRows.skip(i).take(_bulkAddBatchSize).toList();

        for (final row in batch) {
          try {
            // Step 2: Create or find the song
            final songId = await _createOrFindSong(
              bandId: bandId,
              title: row.title,
              artist: row.artist,
              bpm: row.bpm,
              tuning: row.tuning,
            );

            if (songId == null) {
              if (kDebugMode) {
                debugPrint(
                  '[SetlistRepository] Failed to create/find song: ${row.title}',
                );
              }
              continue;
            }

            // Step 3: Add to Catalog (always)
            await addSongToSetlist(setlistId: catalogId, songId: songId);

            // Step 4: Add to target setlist (if not Catalog)
            if (!isCatalog) {
              final setlistSongId = await addSongToSetlist(
                setlistId: setlistId,
                songId: songId,
              );
              if (setlistSongId != null) {
                addedSetlistSongIds.add(setlistSongId);
              }
            }

            addedCount++;
          } catch (e) {
            if (kDebugMode) {
              debugPrint(
                '[SetlistRepository] Error adding song "${row.title}": $e',
              );
            }
            // Continue with next song
          }
        }
      }

      if (kDebugMode) {
        debugPrint('[SetlistRepository] Bulk add complete: $addedCount songs');
        debugPrint(
          '[SetlistRepository] Setlist song IDs for undo: ${addedSetlistSongIds.length}',
        );
      }

      return BulkAddResult(
        addedCount: addedCount,
        setlistSongIds: addedSetlistSongIds,
      );
    } on SetlistQueryError {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint('[SetlistRepository] PostgrestException in bulk add: $e');
      throw SetlistQueryError(
        code: e.code ?? 'UNKNOWN',
        message: e.message,
        details: e.details?.toString(),
        hint: e.hint,
      );
    } catch (e) {
      debugPrint('[SetlistRepository] Error in bulk add: $e');
      throw SetlistQueryError(
        code: 'UNEXPECTED',
        message: e.toString(),
        reason: 'unexpected',
      );
    }
  }

  /// Undo a bulk add operation by removing songs from a setlist.
  ///
  /// This only removes the setlist_songs entries - it does NOT delete
  /// the songs themselves from the songs table (they stay in Catalog).
  ///
  /// [setlistSongIds] - The setlist_songs IDs returned from bulkAddSongs
  ///
  /// Returns the number of songs successfully removed.
  Future<int> undoBulkAdd({required List<String> setlistSongIds}) async {
    if (setlistSongIds.isEmpty) {
      return 0;
    }

    try {
      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Undoing bulk add: ${setlistSongIds.length} songs',
        );
      }

      // Delete the setlist_songs entries
      await supabase
          .from('setlist_songs')
          .delete()
          .inFilter('id', setlistSongIds);

      if (kDebugMode) {
        debugPrint('[SetlistRepository] Undo complete');
      }

      return setlistSongIds.length;
    } on PostgrestException catch (e) {
      debugPrint('[SetlistRepository] Error undoing bulk add: $e');
      return 0;
    } catch (e) {
      debugPrint('[SetlistRepository] Unexpected error undoing bulk add: $e');
      return 0;
    }
  }

  /// Create a new song or find existing one by (band_id, title, artist).
  ///
  /// If an existing song is found, enriches it with any missing data
  /// (bpm, tuning, durationSeconds, albumArtwork) - never overwrites non-null values.
  ///
  /// Returns the song ID, or null if creation failed.
  Future<String?> _createOrFindSong({
    required String bandId,
    required String title,
    required String artist,
    int? bpm,
    String? tuning,
    int? durationSeconds,
    String? albumArtwork,
  }) async {
    // Apply title case to normalize song title and artist
    final normalizedTitle = toTitleCase(title.trim());
    final normalizedArtist = toTitleCase(artist.trim());

    debugPrint(
      '[SetlistRepository] _createOrFindSong: title=$normalizedTitle, artist=$normalizedArtist, bpm=$bpm, tuning=$tuning',
    );
    try {
      // First, try to find existing song
      final existing = await supabase
          .from('songs')
          .select('id, bpm, tuning, duration_seconds, album_artwork')
          .eq('band_id', bandId)
          .ilike('title', normalizedTitle)
          .ilike('artist', normalizedArtist)
          .limit(1);

      if ((existing as List).isNotEmpty) {
        final existingId = existing[0]['id'] as String;
        final existingBpm = existing[0]['bpm'] as int?;

        if (kDebugMode) {
          debugPrint(
            '[SetlistRepository] Found existing song: $normalizedTitle by $normalizedArtist -> $existingId',
          );
        }

        // Enrich existing song with any missing data (never overwrite non-null)
        final updates = <String, dynamic>{};

        if (bpm != null && existingBpm == null) {
          updates['bpm'] = bpm;
        }
        if (tuning != null && existing[0]['tuning'] == null) {
          final dbTuning = tuningToDbEnum(tuning);
          if (dbTuning != null) {
            updates['tuning'] = dbTuning;
          }
        }
        if (durationSeconds != null &&
            existing[0]['duration_seconds'] == null) {
          updates['duration_seconds'] = durationSeconds;
        }
        if (albumArtwork != null && existing[0]['album_artwork'] == null) {
          updates['album_artwork'] = albumArtwork;
        }

        if (updates.isNotEmpty) {
          await supabase.from('songs').update(updates).eq('id', existingId);
          if (kDebugMode) {
            debugPrint(
              '[SetlistRepository] Enriched song with missing data: $updates',
            );
          }
        }

        // If song still has no BPM (and we didn't just add one), try Spotify enrichment
        if (existingBpm == null && !updates.containsKey('bpm')) {
          // Fire and forget - don't await, let it run in background
          enrichSongBpmFromSpotify(
            songId: existingId,
            bandId: bandId,
            title: normalizedTitle,
            artist: normalizedArtist,
          ).then((enrichedBpm) {
            if (enrichedBpm != null && kDebugMode) {
              debugPrint(
                '[SetlistRepository] Background BPM enrichment got: $enrichedBpm for existing song',
              );
            }
          });
        }

        return existingId;
      }

      // Create new song with title-cased values
      final insertData = <String, dynamic>{
        'band_id': bandId,
        'title': normalizedTitle,
        'artist': normalizedArtist,
      };

      if (bpm != null) {
        insertData['bpm'] = bpm;
      }

      if (durationSeconds != null) {
        insertData['duration_seconds'] = durationSeconds;
      }

      if (albumArtwork != null) {
        insertData['album_artwork'] = albumArtwork;
      }

      // Convert app tuning ID to database enum value
      // The database uses enum: 'standard', 'drop_d', 'half_step', 'full_step'
      final dbTuning = tuningToDbEnum(tuning);
      if (dbTuning != null) {
        insertData['tuning'] = dbTuning;
        if (kDebugMode) {
          debugPrint('[SetlistRepository] Mapped tuning: $tuning -> $dbTuning');
        }
      } else if (tuning != null && kDebugMode) {
        debugPrint('[SetlistRepository] Unsupported tuning skipped: $tuning');
      }

      final result = await supabase
          .from('songs')
          .insert(insertData)
          .select('id')
          .single();

      final newId = result['id'] as String;
      if (kDebugMode) {
        debugPrint(
          '[SetlistRepository] Created new song: $normalizedTitle by $normalizedArtist -> $newId',
        );
      }

      // If no BPM was provided, trigger background enrichment from Spotify
      if (bpm == null) {
        // Fire and forget - don't await, let it run in background
        enrichSongBpmFromSpotify(
          songId: newId,
          bandId: bandId,
          title: normalizedTitle,
          artist: normalizedArtist,
        ).then((enrichedBpm) {
          if (enrichedBpm != null && kDebugMode) {
            debugPrint(
              '[SetlistRepository] Background BPM enrichment got: $enrichedBpm for $normalizedTitle',
            );
          }
        });
      }

      return newId;
    } on PostgrestException catch (e) {
      // Handle unique constraint violation (race condition)
      if (e.code == '23505') {
        // Try to find the existing song
        final existing = await supabase
            .from('songs')
            .select('id')
            .eq('band_id', bandId)
            .ilike('title', title.trim())
            .ilike('artist', artist.trim())
            .limit(1);

        if ((existing as List).isNotEmpty) {
          return existing[0]['id'] as String;
        }
      }
      // RLS violation - user is not a member of the band
      if (e.code == '42501') {
        debugPrint('[SetlistRepository] RLS ERROR creating song: $e');
        debugPrint('[SetlistRepository]   bandId: $bandId');
        debugPrint(
          '[SetlistRepository]   userId: ${supabase.auth.currentUser?.id}',
        );
        debugPrint(
          '[SetlistRepository]   This usually means the user is not a member of the band,',
        );
        debugPrint(
          '[SetlistRepository]   or the is_band_member() function is not deployed.',
        );
      } else {
        debugPrint('[SetlistRepository] Error creating song: $e');
      }
      return null;
    } catch (e) {
      debugPrint('[SetlistRepository] Unexpected error creating song: $e');
      return null;
    }
  }

  // ==========================================================================
  // BPM ENRICHMENT FROM SPOTIFY
  // ==========================================================================

  /// Enriches a song with BPM from Spotify if the song doesn't have BPM set.
  ///
  /// This method:
  /// 1. Searches Spotify for the song by title + artist
  /// 2. Fetches audio features (BPM) for the best match
  /// 3. Updates the song in the database with the BPM
  ///
  /// Returns the BPM if found and saved, null otherwise.
  /// This is a fire-and-forget operation - failures are logged but not thrown.
  Future<int?> enrichSongBpmFromSpotify({
    required String songId,
    required String bandId,
    required String title,
    required String artist,
  }) async {
    if (songId.isEmpty || title.isEmpty || artist.isEmpty) {
      return null;
    }

    try {
      debugPrint('[SetlistRepository] Enriching BPM for "$title" by $artist');

      // Search Spotify for the song
      final searchResponse = await supabase.functions.invoke(
        'spotify_search',
        body: {'query': '$title $artist', 'limit': 1},
      );

      if (searchResponse.status != 200) {
        debugPrint('[SetlistRepository] Spotify search failed');
        return null;
      }

      final searchData = searchResponse.data;
      if (searchData == null || searchData['ok'] != true) {
        debugPrint('[SetlistRepository] Spotify search returned no results');
        return null;
      }

      final tracks = (searchData['data'] as List?) ?? [];
      if (tracks.isEmpty) {
        debugPrint('[SetlistRepository] No Spotify tracks found');
        return null;
      }

      final spotifyId = tracks[0]['spotify_id'] as String?;
      if (spotifyId == null) {
        debugPrint('[SetlistRepository] No Spotify ID in result');
        return null;
      }

      // Fetch audio features (BPM)
      final bpmResponse = await supabase.functions.invoke(
        'spotify_audio_features',
        body: {'spotify_id': spotifyId},
      );

      if (bpmResponse.status != 200) {
        debugPrint('[SetlistRepository] Spotify audio features failed');
        return null;
      }

      final bpmData = bpmResponse.data;
      if (bpmData == null || bpmData['ok'] != true) {
        debugPrint('[SetlistRepository] No BPM data returned');
        return null;
      }

      final bpm = bpmData['data']?['bpm'] as int?;
      if (bpm == null || bpm <= 0) {
        debugPrint('[SetlistRepository] Invalid BPM value');
        return null;
      }

      // Update the song with the BPM
      // Must pass ALL 8 parameters to avoid PGRST203 function overload ambiguity
      await supabase.rpc(
        'update_song_metadata',
        params: {
          'p_song_id': songId,
          'p_band_id': bandId,
          'p_bpm': bpm,
          'p_duration_seconds': null,
          'p_tuning': null,
          'p_notes': null,
          'p_title': null,
          'p_artist': null,
        },
      );

      debugPrint('[SetlistRepository] Enriched "$title" with BPM: $bpm');
      return bpm;
    } catch (e) {
      debugPrint('[SetlistRepository] BPM enrichment failed: $e');
      return null;
    }
  }

  /// Enriches multiple songs with missing BPM in the background.
  ///
  /// This is useful for batch enrichment after bulk add operations.
  /// Runs in parallel with a concurrency limit to avoid rate limiting.
  Future<void> enrichSongsBpmInBackground({
    required String bandId,
    required List<({String songId, String title, String artist})> songs,
  }) async {
    if (songs.isEmpty) return;

    debugPrint(
      '[SetlistRepository] Starting background BPM enrichment for ${songs.length} songs',
    );

    // Process in batches of 3 to avoid rate limiting
    const batchSize = 3;
    for (var i = 0; i < songs.length; i += batchSize) {
      final batch = songs.skip(i).take(batchSize);
      await Future.wait(
        batch.map(
          (song) => enrichSongBpmFromSpotify(
            songId: song.songId,
            bandId: bandId,
            title: song.title,
            artist: song.artist,
          ),
        ),
      );
      // Small delay between batches to avoid rate limiting
      if (i + batchSize < songs.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    debugPrint('[SetlistRepository] Background BPM enrichment complete');
  }
}
