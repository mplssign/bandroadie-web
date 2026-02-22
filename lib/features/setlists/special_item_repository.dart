import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    List<String>? purposes,
    List<String>? customPurposes,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (durationMinutes != null) updates['duration_minutes'] = durationMinutes;
    if (durationSeconds != null) updates['duration_seconds'] = durationSeconds;
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

  /// Insert a special item at position 0, shifting all existing items down.
  Future<void> addToSetlist({
    required String setlistId,
    required String specialItemId,
    required SetlistItemType itemType,
  }) async {
    // 1. Shift all existing items down by 1
    // Use offset trick to avoid unique constraint violations on position
    final existing = await supabase
        .from('setlist_songs')
        .select('id, position')
        .eq('setlist_id', setlistId)
        .order('position', ascending: false);

    // Shift to high range first (avoids unique constraint)
    for (int i = 0; i < (existing as List).length; i++) {
      final row = existing[i];
      await supabase
          .from('setlist_songs')
          .update({'position': 1000 + (row['position'] as int)}).eq(
              'id', row['id'] as String);
    }

    // Then set final positions (+1 from original)
    for (int i = 0; i < existing.length; i++) {
      final row = existing[i];
      await supabase
          .from('setlist_songs')
          .update({'position': (row['position'] as int) + 1}).eq(
              'id', row['id'] as String);
    }

    // 2. Insert the special item at position 0
    await supabase.from('setlist_songs').insert({
      'setlist_id': setlistId,
      'song_id': null,
      'special_item_id': specialItemId,
      'item_type': itemType.dbValue,
      'position': 0,
    });

    debugPrint(
      '[SpecialItemRepo] Inserted ${itemType.displayName} at position 0, '
      'shifted ${existing.length} existing items',
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
            album_artwork, notes, youtube_links, lyrics
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

  /// Reorder all items in a setlist. Uses offset trick to avoid unique
  /// constraint violations on position.
  Future<void> reorderItems({
    required String setlistId,
    required List<String> itemIdsInOrder,
  }) async {
    // Phase 1: shift all to high range
    for (int i = 0; i < itemIdsInOrder.length; i++) {
      await supabase
          .from('setlist_songs')
          .update({'position': 1000 + i}).eq('id', itemIdsInOrder[i]);
    }

    // Phase 2: set final positions
    for (int i = 0; i < itemIdsInOrder.length; i++) {
      await supabase
          .from('setlist_songs')
          .update({'position': i}).eq('id', itemIdsInOrder[i]);
    }

    debugPrint(
      '[SpecialItemRepo] Reordered ${itemIdsInOrder.length} items in $setlistId',
    );
  }
}
