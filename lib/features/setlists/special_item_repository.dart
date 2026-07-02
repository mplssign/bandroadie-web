import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import 'models/setlist_item.dart';
import 'models/setlist_item_type.dart';
import 'models/setlist_song.dart';
import 'models/special_item.dart';

// ============================================================================
// SPECIAL ITEM REPOSITORY
// Handles CRUD for setlist_special_items (templates) and the mixed-item
// queries needed to fetch a setlist's ordered items (songs + specials).
// ============================================================================

final specialItemRepositoryProvider = Provider<SpecialItemRepository>((ref) {
  return SpecialItemRepository();
});

class SpecialItemRepository {
  // ==========================================================================
  // TEMPLATE CRUD
  // ==========================================================================

  /// Create a new special item template.
  Future<SpecialItem> createTemplate({
    required String bandId,
    required SetlistItemType type,
    int? durationMinutes,
    int? durationSeconds,
    List<String>? purposes,
    List<String>? customPurposes,
    bool isSavedTemplate = true,
  }) async {
    final row = await supabase
        .from('setlist_special_items')
        .insert({
          'band_id': bandId,
          'type': type.dbValue,
          'duration_minutes': durationMinutes,
          'duration_seconds': durationSeconds,
          'purposes': purposes,
          'custom_purposes': customPurposes,
          'is_saved_template': isSavedTemplate,
        })
        .select()
        .single();

    return SpecialItem.fromSupabase(row);
  }

  /// Fetch saved templates for the "Previously Used" list.
  Future<List<SpecialItem>> fetchTemplates({
    required String bandId,
    SetlistItemType? type,
  }) async {
    var query = supabase
        .from('setlist_special_items')
        .select()
        .eq('band_id', bandId)
        .eq('is_saved_template', true);

    if (type != null) {
      query = query.eq('type', type.dbValue);
    }

    final rows = await query.order('created_at', ascending: false);
    return (rows as List).map((r) => SpecialItem.fromSupabase(r)).toList();
  }

  /// Delete a template. Does NOT delete existing setlist entries.
  Future<void> deleteTemplate(String templateId) async {
    await supabase.from('setlist_special_items').delete().eq('id', templateId);
  }

  /// Update a template (e.g. duration, purposes).
  Future<SpecialItem> updateTemplate({
    required String templateId,
    int? durationMinutes,
    int? durationSeconds,
    bool clearDurationSeconds = false,
    List<String>? purposes,
    List<String>? customPurposes,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (durationMinutes != null) updates['duration_minutes'] = durationMinutes;
    if (durationSeconds != null) {
      updates['duration_seconds'] = durationSeconds;
    } else if (clearDurationSeconds) {
      updates['duration_seconds'] = null;
    }
    if (purposes != null) updates['purposes'] = purposes;
    if (customPurposes != null) updates['custom_purposes'] = customPurposes;

    final row = await supabase
        .from('setlist_special_items')
        .update(updates)
        .eq('id', templateId)
        .select()
        .single();

    return SpecialItem.fromSupabase(row);
  }

  // ==========================================================================
  // ADD SPECIAL ITEM TO SETLIST
  // ==========================================================================

  /// Append a special item at the end of the setlist.
  ///
  /// Uses the `add_special_item_to_setlist` RPC for an atomic,
  /// single-transaction insert. Falls back to sequential client-side
  /// logic if the RPC is not yet deployed.
  Future<void> addToSetlist({
    required String setlistId,
    required String specialItemId,
    required SetlistItemType itemType,
  }) async {
    try {
      final response = await supabase.rpc(
        'add_special_item_to_setlist',
        params: {
          'p_setlist_id': setlistId,
          'p_special_item_id': specialItemId,
          'p_item_type': itemType.dbValue,
        },
      );

      if (response is Map && response['success'] == true) {
        debugPrint(
          '[SpecialItemRepo] ✓ Added ${itemType.displayName} at position '
          '${response['new_position']} via RPC',
        );
        return;
      }

      if (response is Map && response['success'] == false) {
        final error = response['error'] ?? 'Unknown RPC error';
        debugPrint('[SpecialItemRepo] add RPC error: $error');
        throw Exception('Add special item failed: $error');
      }

      debugPrint('[SpecialItemRepo] Unexpected add RPC response: $response');
      throw Exception(
          'Unexpected response from add_special_item_to_setlist RPC');
    } on PostgrestException catch (e) {
      // RPC not found — fall back to sequential client-side updates.
      if (e.code == 'PGRST202' || e.code == '42883') {
        debugPrint(
          '[SpecialItemRepo] add_special_item_to_setlist RPC not found, using fallback',
        );
        await _addToSetlistFallback(
          setlistId: setlistId,
          specialItemId: specialItemId,
          itemType: itemType,
        );
        return;
      }
      rethrow;
    }
  }

  /// Fallback: append at end when the RPC is not deployed.
  Future<void> _addToSetlistFallback({
    required String setlistId,
    required String specialItemId,
    required SetlistItemType itemType,
  }) async {
    // Find the current max position
    final existing = await supabase
        .from('setlist_songs')
        .select('position')
        .eq('setlist_id', setlistId)
        .order('position', ascending: false)
        .limit(1);

    final rows = existing as List;
    final maxPosition = rows.isNotEmpty ? (rows.first['position'] as int) : -1;
    final newPosition = maxPosition + 1;

    // Insert the special item at the end
    await supabase.from('setlist_songs').insert({
      'setlist_id': setlistId,
      'song_id': null,
      'special_item_id': specialItemId,
      'item_type': itemType.dbValue,
      'position': newPosition,
    });

    debugPrint(
      '[SpecialItemRepo] Fallback: inserted ${itemType.displayName} at position $newPosition',
    );
  }

  /// Remove a special item from a setlist (by setlist_songs row ID).
  Future<void> removeFromSetlist(String setlistSongId) async {
    await supabase.from('setlist_songs').delete().eq('id', setlistSongId);
  }

  // ==========================================================================
  // FETCH MIXED ITEMS (SONGS + SPECIALS)
  // ==========================================================================

  /// Fetch all items for a setlist, ordered by position.
  /// Returns a unified list of [SetlistItem] containing both songs and specials.
  Future<List<SetlistItem>> fetchSetlistItems({
    required String bandId,
    required String setlistId,
  }) async {
    // Query setlist_songs with nested joins to both songs and special_items
    final response = await supabase.from('setlist_songs').select('''
          id,
          song_id,
          special_item_id,
          item_type,
          position,
          songs(
            id, title, artist, bpm, duration_seconds, tuning,
            album_artwork, notes, youtube_links, lyrics, musical_key
          ),
          setlist_special_items(
            id, band_id, type, duration_minutes, duration_seconds,
            purposes, custom_purposes, is_saved_template,
            created_at, updated_at
          )
        ''').eq('setlist_id', setlistId).order('position', ascending: true);

    final items = <SetlistItem>[];

    for (final row in (response as List)) {
      try {
        final itemType = SetlistItemType.fromDb(row['item_type'] as String?);
        final rowId = row['id'] as String;
        final position = row['position'] as int? ?? 0;

        if (itemType == SetlistItemType.song) {
          // Song item — parse via SetlistSong
          final songData = row['songs'];
          if (songData == null) continue; // orphaned row

          final song = SetlistSong.fromSupabase(row);
          items.add(SetlistItem(
            id: rowId,
            type: SetlistItemType.song,
            position: position,
            song: song,
          ));
        } else {
          // Special item (set break or pause)
          final specialData = row['setlist_special_items'];
          if (specialData == null) continue;

          final special = SpecialItem.fromSupabase(
            specialData is Map<String, dynamic>
                ? specialData
                : (specialData as Map).cast<String, dynamic>(),
          );
          items.add(SetlistItem(
            id: rowId,
            type: itemType,
            position: position,
            specialItem: special,
          ));
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SpecialItemRepo] Parse error for row: $row');
          debugPrint('  Error: $e');
        }
      }
    }

    if (kDebugMode) {
      final songCount = items.where((i) => i.isSong).length;
      final breakCount = items.where((i) => i.isSetBreak).length;
      final pauseCount = items.where((i) => i.isPause).length;
      debugPrint(
        '[SpecialItemRepo] Fetched ${items.length} items: '
        '$songCount songs, $breakCount breaks, $pauseCount pauses',
      );
    }

    return items;
  }

  // ==========================================================================
  // REORDER MIXED ITEMS
  // ==========================================================================

  /// Reorder all items in a setlist.
  ///
  /// Uses the `reorder_setlist_items` RPC for an atomic, single-transaction
  /// update that avoids UNIQUE constraint violations and trigger-induced
  /// lock contention from parallel HTTP calls.
  ///
  /// Falls back to sequential client-side updates if the RPC is not deployed.
  Future<void> reorderItems({
    required String setlistId,
    required List<String> itemIdsInOrder,
  }) async {
    if (itemIdsInOrder.isEmpty) return;

    try {
      final response = await supabase.rpc(
        'reorder_setlist_items',
        params: {
          'p_setlist_id': setlistId,
          'p_row_ids': itemIdsInOrder,
        },
      );

      if (response is Map && response['success'] == true) {
        debugPrint(
          '[SpecialItemRepo] ✓ Reordered ${response['reordered_count']} items via RPC',
        );
        return;
      }

      if (response is Map && response['success'] == false) {
        final error = response['error'] ?? 'Unknown RPC error';
        debugPrint('[SpecialItemRepo] RPC error: $error');
        throw Exception('Reorder items failed: $error');
      }

      debugPrint('[SpecialItemRepo] Unexpected RPC response: $response');
      throw Exception('Unexpected response from reorder_setlist_items RPC');
    } on PostgrestException catch (e) {
      // RPC not found — fall back to sequential client-side updates.
      if (e.code == 'PGRST202' || e.code == '42883') {
        debugPrint(
          '[SpecialItemRepo] reorder_setlist_items RPC not found, using fallback',
        );
        await _reorderItemsFallback(
          setlistId: setlistId,
          itemIdsInOrder: itemIdsInOrder,
        );
        return;
      }
      rethrow;
    }
  }

  /// Fallback: sequential two-phase position update.
  /// Each phase runs one row at a time to avoid trigger lock contention.
  Future<void> _reorderItemsFallback({
    required String setlistId,
    required List<String> itemIdsInOrder,
  }) async {
    // Phase 1: shift all to high range (sequential to avoid lock contention)
    for (int i = 0; i < itemIdsInOrder.length; i++) {
      await supabase
          .from('setlist_songs')
          .update({'position': 100000 + i}).eq('id', itemIdsInOrder[i]);
    }

    // Phase 2: set final positions
    for (int i = 0; i < itemIdsInOrder.length; i++) {
      await supabase
          .from('setlist_songs')
          .update({'position': i}).eq('id', itemIdsInOrder[i]);
    }

    debugPrint(
      '[SpecialItemRepo] Fallback reordered ${itemIdsInOrder.length} items in $setlistId',
    );
  }
}
