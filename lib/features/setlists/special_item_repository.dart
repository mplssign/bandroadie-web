import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/services/supabase_client.dart';
import '../bands/active_band_controller.dart';
import 'models/setlist_item.dart';
import 'models/setlist_item_type.dart';
import 'models/special_item.dart';

/// Repository for managing setlist special items (set breaks and pauses).
///
/// Handles CRUD for the `setlist_special_items` table (reusable templates)
/// and adding/removing special items to/from setlists via `setlist_songs`.
class SpecialItemRepository {
  final SupabaseClient _client;

  SpecialItemRepository(this._client);

  // ==========================================================================
  // TEMPLATE CRUD (setlist_special_items table)
  // ==========================================================================

  /// Fetch all saved templates for a band, ordered by most recently created first.
  Future<List<SpecialItem>> fetchTemplates({
    required String bandId,
    SetlistItemType? typeFilter,
  }) async {
    if (bandId.isEmpty) {
      throw ArgumentError('bandId cannot be empty');
    }

    var query = _client
        .from('setlist_special_items')
        .select()
        .eq('band_id', bandId)
        .eq('is_saved_template', true);

    if (typeFilter != null) {
      query = query.eq('type', typeFilter.toDbString());
    }

    final response = await query.order('created_at', ascending: false);

    return (response as List)
        .map((json) => SpecialItem.fromSupabase(json as Map<String, dynamic>))
        .toList();
  }

  /// Create a new special item template and optionally add it to a setlist.
  ///
  /// Returns the created [SpecialItem].
  Future<SpecialItem> createTemplate({
    required String bandId,
    required SetlistItemType type,
    int? durationMinutes,
    int? durationSeconds,
    List<String>? purposes,
    List<String>? customPurposes,
    bool isSavedTemplate = true,
  }) async {
    if (bandId.isEmpty) {
      throw ArgumentError('bandId cannot be empty');
    }

    final item = SpecialItem(
      id: '', // Will be set by DB
      bandId: bandId,
      type: type,
      durationMinutes: durationMinutes,
      durationSeconds: durationSeconds,
      purposes: purposes ?? [],
      customPurposes: customPurposes ?? [],
      isSavedTemplate: isSavedTemplate,
    );

    final response = await _client
        .from('setlist_special_items')
        .insert(item.toSupabase())
        .select()
        .single();

    final created = SpecialItem.fromSupabase(response);

    if (kDebugMode) {
      debugPrint(
        '[SpecialItemRepo] Created ${type.displayName} template: ${created.id}',
      );
    }

    return created;
  }

  /// Update an existing template.
  Future<SpecialItem> updateTemplate({
    required String itemId,
    int? durationMinutes,
    int? durationSeconds,
    List<String>? purposes,
    List<String>? customPurposes,
    bool? isSavedTemplate,
    bool clearDurationMinutes = false,
    bool clearDurationSeconds = false,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (durationMinutes != null || clearDurationMinutes) {
      updates['duration_minutes'] = clearDurationMinutes
          ? null
          : durationMinutes;
    }
    if (durationSeconds != null || clearDurationSeconds) {
      updates['duration_seconds'] = clearDurationSeconds
          ? null
          : durationSeconds;
    }
    if (purposes != null) {
      updates['purposes'] = purposes.isEmpty ? null : purposes;
    }
    if (customPurposes != null) {
      updates['custom_purposes'] = customPurposes.isEmpty
          ? null
          : customPurposes;
    }
    if (isSavedTemplate != null) {
      updates['is_saved_template'] = isSavedTemplate;
    }

    final response = await _client
        .from('setlist_special_items')
        .update(updates)
        .eq('id', itemId)
        .select()
        .single();

    final updated = SpecialItem.fromSupabase(response);

    if (kDebugMode) {
      debugPrint('[SpecialItemRepo] Updated template: $itemId');
    }

    return updated;
  }

  /// Remove a template from the library (sets is_saved_template = false).
  /// Does NOT delete existing setlist entries that reference this template.
  Future<void> removeFromLibrary({required String itemId}) async {
    await _client
        .from('setlist_special_items')
        .update({
          'is_saved_template': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', itemId);

    if (kDebugMode) {
      debugPrint('[SpecialItemRepo] Removed template from library: $itemId');
    }
  }

  /// Permanently delete a template. Only deletes if no setlist entries reference it.
  Future<bool> deleteTemplate({required String itemId}) async {
    try {
      // Check if any setlist entries reference this template
      final refs = await _client
          .from('setlist_songs')
          .select('id')
          .eq('special_item_id', itemId)
          .limit(1);

      if ((refs as List).isNotEmpty) {
        // Has references - just remove from library instead
        await removeFromLibrary(itemId: itemId);
        return false;
      }

      // No references - safe to delete
      await _client.from('setlist_special_items').delete().eq('id', itemId);

      if (kDebugMode) {
        debugPrint('[SpecialItemRepo] Deleted template: $itemId');
      }
      return true;
    } catch (e) {
      debugPrint('[SpecialItemRepo] Error deleting template: $e');
      return false;
    }
  }

  // ==========================================================================
  // SETLIST INTEGRATION (setlist_songs table)
  // ==========================================================================

  /// Add a special item to a setlist.
  ///
  /// When [insertAtTop] is true the item is placed at position 0 and all
  /// existing items are shifted down. Otherwise it is appended to the end.
  ///
  /// Returns the setlist_songs row ID.
  Future<String> addToSetlist({
    required String setlistId,
    required String specialItemId,
    required SetlistItemType itemType,
    bool insertAtTop = false,
  }) async {
    if (setlistId.isEmpty || specialItemId.isEmpty) {
      throw ArgumentError('setlistId and specialItemId cannot be empty');
    }

    int targetPosition;

    if (insertAtTop) {
      // Insert at (current minimum position − 1) so the new item sorts first
      // when ordered by position ASC.  No RPC / position-shift required.
      final minResult = await _client
          .from('setlist_songs')
          .select('position')
          .eq('setlist_id', setlistId)
          .order('position', ascending: true)
          .limit(1);

      if ((minResult as List).isNotEmpty) {
        targetPosition = (minResult[0]['position'] as int? ?? 0) - 1;
      } else {
        targetPosition = 0; // empty setlist
      }
    } else {
      // Append to the end.
      final positionResult = await _client
          .from('setlist_songs')
          .select('position')
          .eq('setlist_id', setlistId)
          .order('position', ascending: false)
          .limit(1);

      targetPosition = 0;
      if ((positionResult as List).isNotEmpty) {
        targetPosition = (positionResult[0]['position'] as int? ?? 0) + 1;
      }
    }

    debugPrint(
      '[SpecialItemRepo] Inserting into setlist_songs: '
      'setlist=$setlistId, special_item=$specialItemId, '
      'type=${itemType.toDbString()}, position=$targetPosition',
    );

    final result = await _client
        .from('setlist_songs')
        .insert({
          'setlist_id': setlistId,
          'song_id': null,
          'special_item_id': specialItemId,
          'item_type': itemType.toDbString(),
          'position': targetPosition,
          'bpm': null,
          'tuning': null,
          'duration_seconds': null,
        })
        .select('id')
        .single();

    final insertedId = result['id'] as String;

    debugPrint(
      '[SpecialItemRepo] Added ${itemType.displayName} to setlist '
      '$setlistId at position $targetPosition -> $insertedId',
    );

    return insertedId;
  }

  /// Remove a special item entry from a setlist.
  /// This removes the setlist_songs row, NOT the template.
  Future<void> removeFromSetlist({required String setlistSongId}) async {
    await _client.from('setlist_songs').delete().eq('id', setlistSongId);

    if (kDebugMode) {
      debugPrint('[SpecialItemRepo] Removed setlist entry: $setlistSongId');
    }
  }

  /// Fetch all items for a setlist (songs + special items), ordered by position.
  ///
  /// Returns a unified list of [SetlistItem] objects.
  Future<List<SetlistItem>> fetchSetlistItems({
    required String bandId,
    required String setlistId,
  }) async {
    if (bandId.isEmpty || setlistId.isEmpty) {
      throw ArgumentError('bandId and setlistId cannot be empty');
    }

    // Verify setlist belongs to band
    final setlistCheck = await _client
        .from('setlists')
        .select('id, band_id')
        .eq('id', setlistId)
        .eq('band_id', bandId)
        .maybeSingle();

    if (setlistCheck == null) {
      throw Exception('Setlist not found or wrong band');
    }

    // Fetch all items with left joins to both songs and special items
    final response = await _client
        .from('setlist_songs')
        .select('''
          id,
          item_type,
          position,
          song_id,
          special_item_id,
          bpm,
          tuning,
          duration_seconds,
          songs (
            id,
            title,
            artist,
            bpm,
            duration_seconds,
            tuning,
            album_artwork,
            notes,
            youtube_links,
            lyrics
          ),
          setlist_special_items (
            id,
            band_id,
            type,
            duration_minutes,
            duration_seconds,
            purposes,
            custom_purposes,
            is_saved_template,
            created_at,
            updated_at
          )
        ''')
        .eq('setlist_id', setlistId)
        .order('position', ascending: true);

    final items = <SetlistItem>[];
    for (final json in response as List) {
      try {
        items.add(SetlistItem.fromSupabase(json as Map<String, dynamic>));
      } catch (e) {
        debugPrint('[SpecialItemRepo] Error parsing setlist item: $e');
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
}

/// Riverpod provider for the special items repository
final specialItemRepositoryProvider = Provider<SpecialItemRepository>((ref) {
  return SpecialItemRepository(supabase);
});

/// Provider to fetch templates for the active band
final specialItemTemplatesProvider =
    FutureProvider.family<List<SpecialItem>, SetlistItemType?>((
      ref,
      typeFilter,
    ) async {
      final bandState = ref.watch(activeBandProvider);
      final bandId = bandState.activeBandId;
      if (bandId == null) return [];

      final repo = ref.read(specialItemRepositoryProvider);
      return repo.fetchTemplates(bandId: bandId, typeFilter: typeFilter);
    });
