import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/constants/app_constants.dart';
import '../bands/active_band_controller.dart';
import 'models/setlist_item.dart';
import 'models/setlist_item_type.dart';
import 'models/setlist_song.dart';
import 'models/special_item.dart';
import 'services/tuning_sort_service.dart';
import 'setlist_repository.dart';
import 'setlists_screen.dart';
import 'special_item_repository.dart';

// ============================================================================
// SONG UPDATE BROADCASTER
// Broadcasts global song updates to all listening setlist controllers.
// When a song's metadata changes (title, artist, BPM, duration, etc.),
// this notifies all open setlists to update their local copies.
// ============================================================================

/// Represents an update to a song's metadata
class SongUpdateEvent {
  final String songId;
  final String? title;
  final String? artist;
  final int? bpm;
  final int? durationSeconds;
  final String? notes;
  final String? tuning;
  final DateTime timestamp;

  /// Flags to indicate which fields should be cleared to null
  /// (needed because null means "no change" by default)
  final bool clearBpm;
  final bool clearNotes;

  SongUpdateEvent({
    required this.songId,
    this.title,
    this.artist,
    this.bpm,
    this.durationSeconds,
    this.notes,
    this.tuning,
    this.clearBpm = false,
    this.clearNotes = false,
  }) : timestamp = DateTime.now();
}

/// Notifier that broadcasts song updates to all listeners
class SongUpdateBroadcaster extends Notifier<SongUpdateEvent?> {
  @override
  SongUpdateEvent? build() => null;

  /// Broadcast a song update to all listeners
  void broadcast(SongUpdateEvent event) {
    state = event;
  }

  /// Clear bpm for a song (broadcasts with clearBpm flag)
  void broadcastBpmCleared(String songId) {
    state = SongUpdateEvent(songId: songId, clearBpm: true);
  }
}

/// Provider for song update broadcaster
final songUpdateBroadcasterProvider =
    NotifierProvider<SongUpdateBroadcaster, SongUpdateEvent?>(
      SongUpdateBroadcaster.new,
    );

// ============================================================================
// SETLIST DETAIL CONTROLLER
// Manages state for a single setlist detail view.
//
// FEATURES:
// - Fetch songs for a setlist
// - Delete song (with Catalog awareness)
// - Reorder songs (drag & drop)
//
// BAND ISOLATION: Uses activeBandId for Catalog cascade operations.
// ============================================================================

/// Selected setlist state
class SelectedSetlistState {
  final String? id;
  final String? name;

  const SelectedSetlistState({this.id, this.name});

  bool get isSelected => id != null && name != null;
}

/// Notifier for selected setlist
class SelectedSetlistNotifier extends Notifier<SelectedSetlistState> {
  @override
  SelectedSetlistState build() => const SelectedSetlistState();

  void select({required String id, required String name}) {
    state = SelectedSetlistState(id: id, name: name);
  }

  void clear() {
    state = const SelectedSetlistState();
  }
}

/// Provider to hold the currently selected setlist for detail view
final selectedSetlistProvider =
    NotifierProvider<SelectedSetlistNotifier, SelectedSetlistState>(
      SelectedSetlistNotifier.new,
    );

/// State for setlist detail
class SetlistDetailState {
  final String setlistId;
  final String setlistName;
  final List<SetlistSong> songs;
  final bool isLoading;
  final bool isDeleting;
  final bool isReordering;
  final String? error;

  /// Last successfully persisted song order (for rollback on failure).
  final List<SetlistSong>? lastKnownGoodSongs;

  /// Sort mode for Catalog setlist only.
  /// Preserved in-memory across navigation until explicitly changed by user.
  /// Defaults to title sort on app launch.
  final CatalogSortMode catalogSortMode;

  /// Mixed items list (songs + breaks + pauses) for non-Catalog setlists.
  /// Empty for Catalog setlists (which only have songs).
  final List<SetlistItem> items;

  /// Last successfully persisted item order (for rollback on failure).
  final List<SetlistItem>? lastKnownGoodItems;

  const SetlistDetailState({
    this.setlistId = '',
    this.setlistName = '',
    this.songs = const [],
    this.isLoading = false,
    this.isDeleting = false,
    this.isReordering = false,
    this.error,
    this.lastKnownGoodSongs,
    this.catalogSortMode = CatalogSortMode.title,
    this.items = const [],
    this.lastKnownGoodItems,
  });

  /// Total duration of all items (songs + breaks/pauses that contribute).
  /// For Catalog: uses songs list only.
  /// For non-Catalog: uses items list if available, otherwise songs.
  Duration get totalDuration {
    if (items.isNotEmpty) {
      return items.fold(Duration.zero, (sum, item) {
        if (item.contributesToRuntime) {
          return sum + Duration(seconds: item.durationSeconds);
        }
        return sum;
      });
    }
    return songs.fold(Duration.zero, (sum, song) => sum + song.duration);
  }

  /// Formatted total duration as "Xh XXm"
  String get formattedDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  /// Song count (only actual songs, not breaks/pauses)
  int get songCount {
    if (items.isNotEmpty) {
      return items.where((i) => i.isSong).length;
    }
    return songs.length;
  }

  /// Total item count (songs + breaks + pauses)
  int get itemCount => items.isNotEmpty ? items.length : songs.length;

  /// Count of special items (breaks + pauses)
  int get specialItemCount {
    return items.where((i) => i.isSpecial).length;
  }

  /// Formatted song count with pluralization
  String get formattedSongCount {
    return '$songCount ${songCount == 1 ? 'song' : 'songs'}';
  }

  /// Formatted item count including special items
  String get formattedItemCount {
    final sc = songCount;
    final sic = specialItemCount;
    final songStr = '$sc ${sc == 1 ? 'song' : 'songs'}';
    if (sic == 0) return songStr;
    return '$songStr, $sic ${sic == 1 ? 'break' : 'breaks'}';
  }

  /// Is this the Catalog setlist?
  /// Detection: Uses the shared constant kCatalogSetlistName from app_constants.
  bool get isCatalog => setlistName == kCatalogSetlistName;

  /// Whether this setlist has mixed items (non-Catalog with items loaded)
  bool get hasMixedItems => items.isNotEmpty && !isCatalog;

  SetlistDetailState copyWith({
    String? setlistId,
    String? setlistName,
    List<SetlistSong>? songs,
    bool? isLoading,
    bool? isDeleting,
    bool? isReordering,
    String? error,
    bool clearError = false,
    List<SetlistSong>? lastKnownGoodSongs,
    bool clearLastKnownGood = false,
    CatalogSortMode? catalogSortMode,
    List<SetlistItem>? items,
    List<SetlistItem>? lastKnownGoodItems,
    bool clearLastKnownGoodItems = false,
  }) {
    return SetlistDetailState(
      setlistId: setlistId ?? this.setlistId,
      setlistName: setlistName ?? this.setlistName,
      songs: songs ?? this.songs,
      isLoading: isLoading ?? this.isLoading,
      isDeleting: isDeleting ?? this.isDeleting,
      isReordering: isReordering ?? this.isReordering,
      error: clearError ? null : (error ?? this.error),
      lastKnownGoodSongs: clearLastKnownGood
          ? null
          : (lastKnownGoodSongs ?? this.lastKnownGoodSongs),
      catalogSortMode: catalogSortMode ?? this.catalogSortMode,
      items: items ?? this.items,
      lastKnownGoodItems: clearLastKnownGoodItems
          ? null
          : (lastKnownGoodItems ?? this.lastKnownGoodItems),
    );
  }
}

/// Notifier for setlist detail - watches selectedSetlistProvider
class SetlistDetailNotifier extends Notifier<SetlistDetailState> {
  String? _lastLoadedSetlistId;
  SetlistDetailState? _cachedState;

  @override
  SetlistDetailState build() {
    // Watch the selected setlist - when it changes, reset and refetch
    final selected = ref.watch(selectedSetlistProvider);

    // Listen for song updates from other setlists
    ref.listen<SongUpdateEvent?>(songUpdateBroadcasterProvider, (prev, next) {
      if (next != null && prev?.timestamp != next.timestamp) {
        _applySongUpdate(next);
      }
    });

    // If no setlist selected, return empty state
    if (!selected.isSelected) {
      _lastLoadedSetlistId = null;
      _cachedState = null;
      return const SetlistDetailState();
    }

    // Only reload if the setlist ID actually changed
    // This prevents losing optimistic updates when provider rebuilds
    if (_lastLoadedSetlistId != selected.id) {
      _lastLoadedSetlistId = selected.id;
      _cachedState = null;
      // Trigger async load
      Future.microtask(() => loadSongs());

      return SetlistDetailState(
        setlistId: selected.id!,
        setlistName: selected.name!,
        isLoading: true,
      );
    }

    // Setlist didn't change - return cached state (or create one if missing)
    // This preserves optimistic updates like BPM changes
    if (_cachedState != null) {
      return _cachedState!.copyWith(setlistName: selected.name);
    }

    // Fallback: shouldn't happen, but return loading state
    return SetlistDetailState(
      setlistId: selected.id!,
      setlistName: selected.name!,
      isLoading: true,
    );
  }

  /// Apply a song update from the broadcaster to our local state
  void _applySongUpdate(SongUpdateEvent event) {
    // Check if this setlist contains the updated song
    final songIndex = state.songs.indexWhere((s) => s.id == event.songId);
    if (songIndex == -1) return; // Song not in this setlist

    debugPrint(
      '[SetlistDetail] Applying song update for ${event.songId} in ${state.setlistName}',
    );

    var updatedSongs = List<SetlistSong>.from(state.songs);
    final song = updatedSongs[songIndex];

    // Apply the updates using explicit clear flags
    updatedSongs[songIndex] = song.copyWith(
      title: event.title ?? song.title,
      artist: event.artist ?? song.artist,
      bpm: event.bpm ?? song.bpm,
      durationSeconds: event.durationSeconds ?? song.durationSeconds,
      notes: event.notes ?? song.notes,
      tuning: event.tuning ?? song.tuning,
      clearBpm: event.clearBpm,
      clearNotes: event.clearNotes,
    );

    // RACE CONDITION FIX: Re-sort Catalog to maintain consistent ordering
    // after song metadata changes that affect sort order (artist, BPM, etc.)
    if (state.isCatalog) {
      updatedSongs = _applySorting(
        updatedSongs,
        sortMode: state.catalogSortMode,
      );
      if (kDebugMode) {
        debugPrint('[SetlistDetail] Re-sorted Catalog after song update');
      }
    }

    // Also update the items list if we have mixed items
    List<SetlistItem>? updatedItems;
    if (state.hasMixedItems) {
      updatedItems = state.items.map((item) {
        if (item.isSong && item.song?.id == event.songId) {
          final updatedSong = item.song!.copyWith(
            title: event.title ?? item.song!.title,
            artist: event.artist ?? item.song!.artist,
            bpm: event.bpm ?? item.song!.bpm,
            durationSeconds:
                event.durationSeconds ?? item.song!.durationSeconds,
            notes: event.notes ?? item.song!.notes,
            tuning: event.tuning ?? item.song!.tuning,
            clearBpm: event.clearBpm,
            clearNotes: event.clearNotes,
          );
          return item.copyWith(song: updatedSong);
        }
        return item;
      }).toList();
    }

    state = state.copyWith(songs: updatedSongs, items: updatedItems);
  }

  /// Override state setter to cache state for rebuild preservation
  @override
  set state(SetlistDetailState value) {
    _cachedState = value;
    super.state = value;
  }

  SetlistRepository get _repository => ref.read(setlistRepositoryProvider);
  SpecialItemRepository get _specialItemRepo =>
      ref.read(specialItemRepositoryProvider);
  String? get _bandId => ref.read(activeBandIdProvider);

  /// Load songs for this setlist with band scoping.
  ///
  /// SORTING BEHAVIOR:
  /// - Catalog: Sorted according to active catalogSortMode (title, artist, BPM, etc.)
  /// - Non-Catalog: Respects custom position order from database (no sorting applied)
  Future<void> loadSongs() async {
    if (state.setlistId.isEmpty) return;

    final bandId = _bandId;
    if (bandId == null || bandId.isEmpty) {
      debugPrint('[SetlistDetail] Cannot load songs: No band selected');
      state = state.copyWith(
        isLoading: false,
        error: 'No band selected. Please select a band first.',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    if (kDebugMode) {
      debugPrint('[SetlistDetail] Loading songs...');
      debugPrint('  bandId: $bandId');
      debugPrint('  setlistId: ${state.setlistId}');
      debugPrint('  setlistName: ${state.setlistName}');
    }

    try {
      if (state.isCatalog) {
        // Catalog: only songs, no special items
        var songs = await _repository.fetchSongsForSetlist(
          bandId: bandId,
          setlistId: state.setlistId,
        );

        // ASYNC SAFETY: Verify bandId hasn't changed during the await
        final currentBandId = _bandId;
        if (currentBandId != bandId) {
          if (kDebugMode) {
            debugPrint(
              '[SetlistDetail] Discarding stale load result: '
              'bandId changed from $bandId to $currentBandId',
            );
          }
          return;
        }

        songs = _applySorting(songs, sortMode: state.catalogSortMode);

        state = state.copyWith(
          songs: songs,
          items: const [],
          isLoading: false,
          clearLastKnownGood: true,
          clearLastKnownGoodItems: true,
        );

        if (kDebugMode) {
          debugPrint(
            '[SetlistDetail] Loaded ${songs.length} songs for Catalog',
          );
          debugPrint(
            '[SetlistDetail] Catalog sort mode: ${state.catalogSortMode.label}',
          );
        }

        // Persist computed total duration so setlist cards stay in sync
        await _repository.updateTotalDuration(
          setlistId: state.setlistId,
          totalSeconds: state.totalDuration.inSeconds,
        );
      } else {
        // Non-Catalog: fetch mixed items (songs + special items)
        final mixedItems = await _specialItemRepo.fetchSetlistItems(
          bandId: bandId,
          setlistId: state.setlistId,
        );

        // ASYNC SAFETY: Verify bandId hasn't changed during the await
        final currentBandId = _bandId;
        if (currentBandId != bandId) {
          if (kDebugMode) {
            debugPrint(
              '[SetlistDetail] Discarding stale load result: '
              'bandId changed from $bandId to $currentBandId',
            );
          }
          return;
        }

        // Extract songs for backward compatibility with existing methods
        final songs = mixedItems
            .where((i) => i.isSong && i.song != null)
            .map((i) => i.song!)
            .toList();

        state = state.copyWith(
          songs: songs,
          items: mixedItems,
          isLoading: false,
          clearLastKnownGood: true,
          clearLastKnownGoodItems: true,
        );

        if (kDebugMode) {
          final breakCount = mixedItems.where((i) => i.isSetBreak).length;
          final pauseCount = mixedItems.where((i) => i.isPause).length;
          debugPrint(
            '[SetlistDetail] Loaded ${mixedItems.length} items: '
            '${songs.length} songs, $breakCount breaks, $pauseCount pauses '
            'for ${state.setlistName}',
          );
        }

        // Persist computed total duration so setlist cards stay in sync
        await _repository.updateTotalDuration(
          setlistId: state.setlistId,
          totalSeconds: state.totalDuration.inSeconds,
        );
      }
    } on SetlistQueryError catch (e) {
      debugPrint('[SetlistDetail] SetlistQueryError: $e');
      state = state.copyWith(isLoading: false, error: e.userMessage);
    } on NoBandSelectedError catch (e) {
      debugPrint('[SetlistDetail] NoBandSelectedError: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'No band selected. Please select a band first.',
      );
    } catch (e) {
      debugPrint('[SetlistDetail] Unexpected error loading songs: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load songs. Please try again.',
      );
    }
  }

  /// Apply sorting to Catalog songs based on selected sort mode.
  /// Handles null/empty values gracefully by pushing them to the bottom.
  List<SetlistSong> _applySorting(
    List<SetlistSong> songs, {
    required CatalogSortMode sortMode,
  }) {
    final sorted = List<SetlistSong>.from(songs);

    switch (sortMode) {
      case CatalogSortMode.title:
        sorted.sort((a, b) {
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;

      case CatalogSortMode.artist:
        sorted.sort((a, b) {
          final aArtist = a.artist.isEmpty ? 'zzz' : a.artist.toLowerCase();
          final bArtist = b.artist.isEmpty ? 'zzz' : b.artist.toLowerCase();
          final artistCompare = aArtist.compareTo(bArtist);
          if (artistCompare != 0) return artistCompare;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;

      case CatalogSortMode.bpm:
        sorted.sort((a, b) {
          // Null/0 BPM goes to bottom
          if (a.bpm == null || a.bpm == 0) return 1;
          if (b.bpm == null || b.bpm == 0) return -1;
          final bpmCompare = a.bpm!.compareTo(b.bpm!);
          if (bpmCompare != 0) return bpmCompare;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;

      case CatalogSortMode.bpmDesc:
        sorted.sort((a, b) {
          // Null/0 BPM goes to bottom
          if (a.bpm == null || a.bpm == 0) return 1;
          if (b.bpm == null || b.bpm == 0) return -1;
          final bpmCompare = b.bpm!.compareTo(
            a.bpm!,
          ); // Reversed for descending
          if (bpmCompare != 0) return bpmCompare;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;

      case CatalogSortMode.duration:
        sorted.sort((a, b) {
          final aDuration = a.durationSeconds;
          final bDuration = b.durationSeconds;
          // 0 duration goes to bottom
          if (aDuration == 0) return 1;
          if (bDuration == 0) return -1;
          final durationCompare = aDuration.compareTo(bDuration);
          if (durationCompare != 0) return durationCompare;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;

      case CatalogSortMode.durationDesc:
        sorted.sort((a, b) {
          final aDuration = a.durationSeconds;
          final bDuration = b.durationSeconds;
          // 0 duration goes to bottom
          if (aDuration == 0) return 1;
          if (bDuration == 0) return -1;
          final durationCompare = bDuration.compareTo(
            aDuration,
          ); // Reversed for descending
          if (durationCompare != 0) return durationCompare;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;

      case CatalogSortMode.tuning:
        sorted.sort((a, b) {
          final aTuning = a.tuning ?? '';
          final bTuning = b.tuning ?? '';
          // Empty tuning goes to bottom
          if (aTuning.isEmpty) return 1;
          if (bTuning.isEmpty) return -1;

          // Use predefined musical order from kTuningSortOrder
          final aTuningLower = aTuning.toLowerCase();
          final bTuningLower = bTuning.toLowerCase();
          final aIndex = kTuningSortOrder.indexOf(aTuningLower);
          final bIndex = kTuningSortOrder.indexOf(bTuningLower);

          // Both tunings are in the predefined order
          if (aIndex != -1 && bIndex != -1) {
            final orderCompare = aIndex.compareTo(bIndex);
            if (orderCompare != 0) return orderCompare;
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          }

          // Only a is known - it comes first
          if (aIndex != -1) return -1;

          // Only b is known - it comes first
          if (bIndex != -1) return 1;

          // Neither is known - fallback to alphabetical
          final tuningCompare = aTuningLower.compareTo(bTuningLower);
          if (tuningCompare != 0) return tuningCompare;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
    }

    return sorted;
  }

  /// Set the sort mode for Catalog.
  /// Immediately re-sorts the song list and persists selection in-memory
  /// until changed by user or app restart.
  void setSortMode(CatalogSortMode newMode) {
    if (!state.isCatalog) return; // Only for Catalog

    // Re-sort songs with new mode
    final sortedSongs = _applySorting(state.songs, sortMode: newMode);

    state = state.copyWith(catalogSortMode: newMode, songs: sortedSongs);

    if (kDebugMode) {
      debugPrint('[SetlistDetail] Changed catalog sort to: ${newMode.label}');
    }
  }

  /// Debug: Run smoke test for songs query
  /// Returns diagnostic information for troubleshooting
  Future<Map<String, dynamic>> debugSmokeTest() async {
    final bandId = _bandId;
    if (bandId == null || state.setlistId.isEmpty) {
      return {'error': 'Missing bandId or setlistId'};
    }
    return _repository.debugFetchSongsRaw(
      bandId: bandId,
      setlistId: state.setlistId,
    );
  }

  /// Delete a song from this setlist
  ///
  /// If this is the Catalog, cascades to all setlists in the band.
  /// Otherwise, only removes from this setlist.
  Future<bool> deleteSong(String songId) async {
    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    state = state.copyWith(isDeleting: true, clearError: true);

    try {
      if (state.isCatalog) {
        // Catalog deletion - remove from all setlists + delete song
        await _repository.deleteSongFromCatalog(bandId: bandId, songId: songId);
      } else {
        // Regular setlist - only remove from this setlist
        await _repository.deleteSongFromSetlist(
          setlistId: state.setlistId,
          songId: songId,
        );
      }

      // ASYNC SAFETY: Verify bandId hasn't changed during the await
      final currentBandId = _bandId;
      if (currentBandId != bandId) {
        if (kDebugMode) {
          debugPrint(
            '[SetlistDetail] Discarding delete result: '
            'bandId changed from $bandId to $currentBandId',
          );
        }
        state = state.copyWith(isDeleting: false);
        return false;
      }

      // Update local state - remove the song
      final updatedSongs = state.songs.where((s) => s.id != songId).toList();

      // Re-index positions
      final reindexedSongs = updatedSongs.asMap().entries.map((entry) {
        return entry.value.copyWith(position: entry.key);
      }).toList();

      // Also update items if we have mixed items
      List<SetlistItem>? updatedItems;
      if (state.hasMixedItems) {
        final filtered = state.items
            .where((i) => !(i.isSong && i.song?.id == songId))
            .toList();
        updatedItems = filtered.asMap().entries.map((entry) {
          return entry.value.copyWith(position: entry.key);
        }).toList();
      }

      state = state.copyWith(
        songs: reindexedSongs,
        items: updatedItems,
        isDeleting: false,
      );

      // Refresh setlists list to update song count and duration stats
      ref.read(setlistsProvider.notifier).refresh();

      debugPrint('[SetlistDetail] Deleted song $songId');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error deleting song: $e');
      state = state.copyWith(
        isDeleting: false,
        error: 'Failed to delete song. Please try again.',
      );
      return false;
    }
  }

  /// Reorder items locally (optimistic update).
  ///
  /// For non-Catalog: reorders the items list (mixed songs + breaks/pauses).
  /// For Catalog: reorders the songs list (songs only).
  ///
  /// Saves the current order as "last known good" before applying changes,
  /// so we can revert if persistence fails.
  void reorderLocal(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;

    if (state.hasMixedItems) {
      // Non-Catalog: reorder items list
      final lastGood =
          state.lastKnownGoodItems ?? List<SetlistItem>.from(state.items);

      final items = List<SetlistItem>.from(state.items);
      final item = items.removeAt(oldIndex);

      final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
      items.insert(adjustedIndex, item);

      final reindexedItems = items.asMap().entries.map((entry) {
        return entry.value.copyWith(position: entry.key);
      }).toList();

      // Also keep songs in sync
      final songs = reindexedItems
          .where((i) => i.isSong && i.song != null)
          .map((i) => i.song!)
          .toList();

      debugPrint(
        '[SetlistDetail] reorderLocal (items): $oldIndex -> $newIndex',
      );

      state = state.copyWith(
        items: reindexedItems,
        songs: songs,
        lastKnownGoodItems: lastGood,
      );
    } else {
      // Catalog or legacy: reorder songs list
      final lastGood =
          state.lastKnownGoodSongs ?? List<SetlistSong>.from(state.songs);

      final songs = List<SetlistSong>.from(state.songs);
      final song = songs.removeAt(oldIndex);

      final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
      songs.insert(adjustedIndex, song);

      final reindexedSongs = songs.asMap().entries.map((entry) {
        return entry.value.copyWith(position: entry.key);
      }).toList();

      debugPrint(
        '[SetlistDetail] reorderLocal (songs): $oldIndex -> $newIndex',
      );

      state = state.copyWith(
        songs: reindexedSongs,
        lastKnownGoodSongs: lastGood,
      );
    }
  }

  /// Persist reorder to database.
  ///
  /// For non-Catalog: uses setlist_songs row IDs (supports mixed items).
  /// For Catalog: uses song IDs (backward compatible).
  ///
  /// On success: clears the lastKnownGood (current order becomes "known good").
  /// On failure: reverts to lastKnownGood and shows error.
  Future<bool> persistReorder() async {
    state = state.copyWith(isReordering: true, clearError: true);

    final bandId = _bandId;

    try {
      if (state.hasMixedItems) {
        // Non-Catalog: reorder using setlist_songs row IDs
        final rowIds = state.items.map((i) => i.setlistSongId).toList();

        debugPrint('[SetlistDetail] persistReorder (items):');
        debugPrint('  setlistId: ${state.setlistId}');
        debugPrint('  itemCount: ${rowIds.length}');

        await _repository.reorderSetlistItems(
          setlistId: state.setlistId,
          rowIdsInOrder: rowIds,
        );
      } else {
        // Catalog or legacy: reorder using song IDs
        final songIds = state.songs.map((s) => s.id).toList();

        debugPrint('[SetlistDetail] persistReorder (songs):');
        debugPrint('  setlistId: ${state.setlistId}');
        debugPrint('  bandId: $bandId');
        debugPrint('  songCount: ${songIds.length}');

        await _repository.reorderSongs(
          setlistId: state.setlistId,
          songIdsInOrder: songIds,
          bandId: bandId,
        );
      }

      // ASYNC SAFETY: Verify bandId hasn't changed during the await
      final currentBandId = _bandId;
      if (currentBandId != bandId) {
        if (kDebugMode) {
          debugPrint(
            '[SetlistDetail] Discarding reorder result: '
            'bandId changed from $bandId to $currentBandId',
          );
        }
        state = state.copyWith(isReordering: false);
        return false;
      }

      // Success: clear the backup (current order is now the "known good")
      state = state.copyWith(
        isReordering: false,
        clearLastKnownGood: true,
        clearLastKnownGoodItems: true,
      );
      debugPrint('[SetlistDetail] ✓ Persisted reorder successfully');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] ✗ Error persisting reorder: $e');

      if (state.hasMixedItems) {
        // Revert items to last known good order
        final lastGood = state.lastKnownGoodItems;
        if (lastGood != null && lastGood.isNotEmpty) {
          debugPrint(
            '[SetlistDetail] Reverting items to last known good order',
          );
          final songs = lastGood
              .where((i) => i.isSong && i.song != null)
              .map((i) => i.song!)
              .toList();
          state = state.copyWith(
            items: lastGood,
            songs: songs,
            isReordering: false,
            error: 'Failed to save order. Changes reverted.',
            clearLastKnownGoodItems: true,
          );
        } else {
          debugPrint('[SetlistDetail] No backup available, triggering refetch');
          state = state.copyWith(
            isReordering: false,
            error: 'Failed to save order. Reloading...',
          );
          Future.microtask(() => loadSongs());
        }
      } else {
        // Revert songs to last known good order
        final lastGood = state.lastKnownGoodSongs;
        if (lastGood != null && lastGood.isNotEmpty) {
          debugPrint('[SetlistDetail] Reverting to last known good order');
          state = state.copyWith(
            songs: lastGood,
            isReordering: false,
            error: 'Failed to save order. Changes reverted.',
            clearLastKnownGood: true,
          );
        } else {
          debugPrint('[SetlistDetail] No backup available, triggering refetch');
          state = state.copyWith(
            isReordering: false,
            error: 'Failed to save order. Reloading...',
          );
          Future.microtask(() => loadSongs());
        }
      }
      return false;
    }
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Update BPM for a song (global - syncs across all setlists)
  ///
  /// Returns true if successful, false if validation fails or save fails.
  Future<bool> updateSongBpm(String songId, int bpm) async {
    // Validate range
    if (bpm < 20 || bpm > 300) {
      state = state.copyWith(error: 'BPM must be between 20 and 300');
      return false;
    }

    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    // Optimistic update
    final originalSongs = List<SetlistSong>.from(state.songs);
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(bpm: bpm);
      }
      return song;
    }).toList();
    state = state.copyWith(songs: updatedSongs);

    try {
      debugPrint(
        '[SetlistDetail] Calling updateSongBpmOverride with bandId=$bandId, songId=$songId, bpm=$bpm',
      );
      await _repository.updateSongBpmOverride(
        bandId: bandId,
        setlistId: state.setlistId,
        songId: songId,
        bpm: bpm,
      );
      debugPrint('[SetlistDetail] Updated BPM to $bpm for song $songId');

      // Broadcast the update to other setlists
      ref
          .read(songUpdateBroadcasterProvider.notifier)
          .broadcast(SongUpdateEvent(songId: songId, bpm: bpm));

      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error updating BPM: $e');
      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        error: 'Failed to save BPM. Please try again.',
      );
      return false;
    }
  }

  /// Clear BPM for a song (global - syncs across all setlists)
  ///
  /// Sets the BPM to null (shows "- BPM").
  Future<bool> clearSongBpm(String songId) async {
    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    // Optimistic update - clear the BPM
    final originalSongs = List<SetlistSong>.from(state.songs);
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(clearBpm: true);
      }
      return song;
    }).toList();
    state = state.copyWith(songs: updatedSongs);

    try {
      await _repository.clearSongBpmOverride(
        bandId: bandId,
        setlistId: state.setlistId,
        songId: songId,
      );
      debugPrint('[SetlistDetail] Cleared BPM for song $songId');

      // Broadcast the update to other setlists
      ref
          .read(songUpdateBroadcasterProvider.notifier)
          .broadcastBpmCleared(songId);

      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error clearing BPM: $e');
      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        error: 'Failed to clear BPM. Please try again.',
      );
      return false;
    }
  }

  /// Update duration for a song (global - syncs across all setlists)
  ///
  /// Duration is in seconds. Must be between 0 and 1200 (20 minutes).
  Future<bool> updateSongDuration(String songId, int durationSeconds) async {
    // Validate range
    if (durationSeconds < 0 || durationSeconds > 1200) {
      state = state.copyWith(
        error: 'Duration must be between 0 and 20 minutes',
      );
      return false;
    }

    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    // Optimistic update
    final originalSongs = List<SetlistSong>.from(state.songs);
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(durationSeconds: durationSeconds);
      }
      return song;
    }).toList();
    state = state.copyWith(songs: updatedSongs);

    try {
      await _repository.updateSongDurationOverride(
        bandId: bandId,
        setlistId: state.setlistId,
        songId: songId,
        durationSeconds: durationSeconds,
      );
      debugPrint(
        '[SetlistDetail] Updated duration to $durationSeconds for song $songId',
      );

      // Broadcast the update to other setlists
      ref
          .read(songUpdateBroadcasterProvider.notifier)
          .broadcast(
            SongUpdateEvent(songId: songId, durationSeconds: durationSeconds),
          );

      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error updating duration: $e');
      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        error: 'Failed to save duration. Please try again.',
      );
      return false;
    }
  }

  /// Update tuning for a song (global - syncs across all setlists)
  ///
  /// Uses optimistic update pattern:
  /// 1. Store original state
  /// 2. Apply change immediately (UI feels instant)
  /// 3. Persist to database
  /// 4. On failure: revert to original and show error
  Future<bool> updateSongTuning(String songId, String tuning) async {
    if (tuning.isEmpty) {
      state = state.copyWith(error: 'Tuning cannot be empty');
      return false;
    }

    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    debugPrint(
      '[SetlistDetail] updateSongTuning: songId=$songId, tuning=$tuning, setlistId=${state.setlistId}',
    );

    // Store original state for rollback
    final originalSongs = List<SetlistSong>.from(state.songs);

    // Optimistic update - apply immediately so UI feels instant
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(tuning: tuning);
      }
      return song;
    }).toList();
    state = state.copyWith(songs: updatedSongs, clearError: true);

    try {
      await _repository.updateSongTuningOverride(
        bandId: bandId,
        setlistId: state.setlistId,
        songId: songId,
        tuning: tuning,
      );
      debugPrint(
        '[SetlistDetail] Successfully updated tuning to $tuning for song $songId',
      );

      // Broadcast the update to other setlists
      ref
          .read(songUpdateBroadcasterProvider.notifier)
          .broadcast(SongUpdateEvent(songId: songId, tuning: tuning));

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error updating tuning: $e');
      debugPrint('[SetlistDetail] Stack trace: $stack');

      // Extract user-friendly error message
      String errorMessage = 'Couldn\'t save tuning. Try again.';
      final errorString = e.toString();
      if (errorString.contains('not yet available')) {
        // Legacy enum limitation - tuning not supported
        errorMessage =
            'This tuning isn\'t available yet. Try Standard, Drop D, Half-Step, or Full-Step.';
      } else if (errorString.contains('access denied')) {
        errorMessage = 'You don\'t have permission to update this song.';
      }

      // Revert optimistic update
      state = state.copyWith(songs: originalSongs, error: errorMessage);
      return false;
    }
  }

  /// Update notes for a song (global - syncs across all setlists)
  ///
  /// Uses optimistic update pattern:
  /// 1. Store original state
  /// 2. Apply change immediately (UI feels instant)
  /// 3. Persist to database
  /// 4. On failure: revert to original and show error
  Future<bool> updateSongNotes(String songId, String? notes) async {
    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    debugPrint(
      '[SetlistDetail] updateSongNotes: songId=$songId, notes=${notes != null ? notes.substring(0, notes.length > 30 ? 30 : notes.length) : 'null'}...',
    );

    // Store original state for rollback
    final originalSongs = List<SetlistSong>.from(state.songs);

    // Optimistic update - apply immediately so UI feels instant
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(
          notes: notes,
          clearNotes: notes == null || notes.isEmpty,
        );
      }
      return song;
    }).toList();
    state = state.copyWith(songs: updatedSongs, clearError: true);

    try {
      await _repository.updateSongNotes(
        bandId: bandId,
        songId: songId,
        notes: notes,
      );
      debugPrint('[SetlistDetail] Successfully updated notes for song $songId');

      // Broadcast the update to other setlists
      ref
          .read(songUpdateBroadcasterProvider.notifier)
          .broadcast(SongUpdateEvent(songId: songId, notes: notes ?? ''));

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error updating notes: $e');
      debugPrint('[SetlistDetail] Stack trace: $stack');

      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        error: 'Couldn\'t save notes. Try again.',
      );
      return false;
    }
  }

  /// Updates a song's YouTube links globally.
  ///
  /// Uses optimistic update pattern:
  /// 1. Store original state
  /// 2. Apply change immediately (UI feels instant)
  /// 3. Persist to database
  /// 4. On failure: revert to original and show error
  Future<bool> updateSongYoutubeLinks(
    String songId,
    String? youtubeLinksJson,
  ) async {
    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    debugPrint(
      '[SetlistDetail] updateSongYoutubeLinks: songId=$songId, links=${youtubeLinksJson != null ? youtubeLinksJson.substring(0, youtubeLinksJson.length > 30 ? 30 : youtubeLinksJson.length) : 'null'}...',
    );

    // Store original state for rollback
    final originalSongs = List<SetlistSong>.from(state.songs);

    // Optimistic update - apply immediately so UI feels instant
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(
          youtubeLinks: youtubeLinksJson,
          clearYoutubeLinks:
              youtubeLinksJson == null || youtubeLinksJson.isEmpty,
        );
      }
      return song;
    }).toList();
    state = state.copyWith(songs: updatedSongs, clearError: true);

    try {
      await _repository.updateSongYoutubeLinks(
        bandId: bandId,
        songId: songId,
        youtubeLinks: youtubeLinksJson,
      );
      debugPrint(
        '[SetlistDetail] Successfully updated YouTube links for song $songId',
      );

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error updating YouTube links: $e');
      debugPrint('[SetlistDetail] Stack trace: $stack');

      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        error: 'Couldn\'t save YouTube links. Try again.',
      );
      return false;
    }
  }

  /// Updates a song's lyrics globally.
  ///
  /// Uses optimistic update pattern:
  /// 1. Store original state
  /// 2. Apply change immediately (UI feels instant)
  /// 3. Persist to database
  /// 4. On failure: revert to original and show error
  Future<bool> updateSongLyrics(String songId, String? lyricsJson) async {
    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    debugPrint(
      '[SetlistDetail] updateSongLyrics: songId=$songId, lyrics=${lyricsJson != null ? lyricsJson.substring(0, lyricsJson.length > 30 ? 30 : lyricsJson.length) : 'null'}...',
    );

    // Store original state for rollback
    final originalSongs = List<SetlistSong>.from(state.songs);

    // Optimistic update - apply immediately so UI feels instant
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(
          lyrics: lyricsJson,
          clearLyrics: lyricsJson == null || lyricsJson.isEmpty,
        );
      }
      return song;
    }).toList();
    state = state.copyWith(songs: updatedSongs, clearError: true);

    try {
      await _repository.updateSongLyrics(
        bandId: bandId,
        songId: songId,
        lyrics: lyricsJson,
      );
      debugPrint(
        '[SetlistDetail] Successfully updated lyrics for song $songId',
      );

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error updating lyrics: $e');
      debugPrint('[SetlistDetail] Stack trace: $stack');

      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        error: 'Couldn\'t save lyrics. Try again.',
      );
      return false;
    }
  }

  /// Updates a song's title and/or artist globally.
  ///
  /// Uses optimistic update pattern.
  Future<bool> updateSongTitleArtist(
    String songId, {
    String? title,
    String? artist,
  }) async {
    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    if (title == null && artist == null) {
      return true; // Nothing to update
    }

    debugPrint(
      '[SetlistDetail] updateSongTitleArtist: songId=$songId, title=$title, artist=$artist',
    );

    // Store original state for rollback
    final originalSongs = List<SetlistSong>.from(state.songs);

    // Optimistic update - apply immediately so UI feels instant
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(
          title: title ?? song.title,
          artist: artist ?? song.artist,
        );
      }
      return song;
    }).toList();
    state = state.copyWith(songs: updatedSongs, clearError: true);

    try {
      await _repository.updateSongTitleArtist(
        bandId: bandId,
        songId: songId,
        title: title,
        artist: artist,
      );
      debugPrint(
        '[SetlistDetail] Successfully updated title/artist for song $songId',
      );

      // Broadcast the update to other setlists
      ref
          .read(songUpdateBroadcasterProvider.notifier)
          .broadcast(
            SongUpdateEvent(songId: songId, title: title, artist: artist),
          );

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error updating title/artist: $e');
      debugPrint('[SetlistDetail] Stack trace: $stack');

      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        error: 'Couldn\'t save changes. Try again.',
      );
      return false;
    }
  }

  /// Add a song to this setlist
  ///
  /// Ensures the song is also in the Catalog (Catalog-first guarantee).
  /// Returns an AddSongResult with friendly messaging for UI display.
  Future<AddSongResult> addSong(
    String songId,
    String songTitle,
    String artist,
  ) async {
    final bandId = _bandId;
    if (bandId == null) {
      debugPrint('[SetlistDetail] Cannot add song: no band selected');
      return AddSongResult(
        setlistSongId: null,
        songTitle: songTitle,
        songArtist: artist,
      );
    }

    final result = await _repository.addSongToSetlistEnsureCatalog(
      bandId: bandId,
      setlistId: state.setlistId,
      songId: songId,
      songTitle: songTitle,
      songArtist: artist,
    );

    // ASYNC SAFETY: Verify bandId hasn't changed during the await
    final currentBandId = _bandId;
    if (currentBandId != bandId) {
      if (kDebugMode) {
        debugPrint(
          '[SetlistDetail] Discarding addSong result: '
          'bandId changed from $bandId to $currentBandId',
        );
      }
      return AddSongResult(
        setlistSongId: null,
        songTitle: songTitle,
        songArtist: artist,
      );
    }

    if (result.success) {
      // Reload to get the updated list with the new song
      await loadSongs();

      // Refresh setlists list to update song count and duration stats
      ref.read(setlistsProvider.notifier).refresh();

      debugPrint('[SetlistDetail] ${result.friendlyMessage}');
    }

    return result;
  }

  /// Rename the current setlist
  ///
  /// Returns true if successful, false otherwise.
  /// Cannot rename the Catalog setlist.
  Future<bool> renameSetlist(String newName) async {
    if (state.isCatalog) {
      debugPrint('[SetlistDetail] Cannot rename Catalog setlist');
      return false;
    }

    final bandId = _bandId;
    if (bandId == null || state.setlistId.isEmpty) {
      debugPrint('[SetlistDetail] Cannot rename: missing bandId or setlistId');
      return false;
    }

    try {
      await _repository.renameSetlist(
        bandId: bandId,
        setlistId: state.setlistId,
        newName: newName,
      );

      // ASYNC SAFETY: Verify bandId hasn't changed during the await
      final currentBandId = _bandId;
      if (currentBandId != bandId) {
        if (kDebugMode) {
          debugPrint(
            '[SetlistDetail] Discarding rename result: '
            'bandId changed from $bandId to $currentBandId',
          );
        }
        return false;
      }

      state = state.copyWith(setlistName: newName);
      debugPrint('[SetlistDetail] Renamed setlist to "$newName"');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error renaming setlist: $e');
      state = state.copyWith(
        error: 'Failed to rename setlist. Please try again.',
      );
      return false;
    }
  }

  /// Delete the current setlist
  ///
  /// Returns true if successful, false otherwise.
  /// Cannot delete the Catalog setlist.
  Future<bool> deleteSetlist() async {
    if (state.isCatalog) {
      debugPrint('[SetlistDetail] Cannot delete Catalog setlist');
      state = state.copyWith(
        error: 'Cannot delete the Catalog. It\'s where all your songs live!',
      );
      return false;
    }

    final bandId = _bandId;
    if (bandId == null || state.setlistId.isEmpty) {
      debugPrint('[SetlistDetail] Cannot delete: missing bandId or setlistId');
      return false;
    }

    state = state.copyWith(isDeleting: true, clearError: true);

    try {
      await _repository.deleteSetlist(
        bandId: bandId,
        setlistId: state.setlistId,
      );
      debugPrint('[SetlistDetail] Deleted setlist "${state.setlistName}"');

      // Refresh setlists list
      ref.read(setlistsProvider.notifier).refresh();

      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error deleting setlist: $e');
      state = state.copyWith(
        isDeleting: false,
        error: 'Failed to delete setlist. Please try again.',
      );
      return false;
    }
  }

  // ==========================================================================
  // SPECIAL ITEMS (Set Breaks & Pauses)
  // ==========================================================================

  /// Add a special item (set break or pause) to this setlist.
  ///
  /// Creates the template in the database, then adds it to the setlist,
  /// then reloads the item list.
  ///
  /// Cannot add special items to the Catalog.
  Future<bool> addSpecialItem({
    required SetlistItemType type,
    int? durationMinutes,
    int? durationSeconds,
    List<String>? purposes,
    List<String>? customPurposes,
    bool saveAsTemplate = true,
  }) async {
    if (state.isCatalog) {
      debugPrint('[SetlistDetail] Cannot add breaks to Catalog');
      state = state.copyWith(
        error: 'Breaks and pauses can only be added to setlists.',
      );
      return false;
    }

    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    try {
      // 1. Create the template
      debugPrint(
        '[SetlistDetail] Step 1: Creating template for ${type.displayName}...',
      );
      late final SpecialItem template;
      try {
        template = await _specialItemRepo.createTemplate(
          bandId: bandId,
          type: type,
          durationMinutes: durationMinutes,
          durationSeconds: durationSeconds,
          purposes: purposes,
          customPurposes: customPurposes,
          isSavedTemplate: saveAsTemplate,
        );
        debugPrint('[SetlistDetail] Step 1 OK: template ${template.id}');
      } catch (e, stack) {
        debugPrint('[SetlistDetail] Step 1 FAILED (createTemplate): $e');
        debugPrint('[SetlistDetail] Stack: $stack');
        rethrow;
      }

      // 2. Add to setlist at the top so it's immediately visible
      debugPrint(
        '[SetlistDetail] Step 2: Adding to setlist ${state.setlistId}...',
      );
      try {
        await _specialItemRepo.addToSetlist(
          setlistId: state.setlistId,
          specialItemId: template.id,
          itemType: type,
          insertAtTop: true,
        );
        debugPrint('[SetlistDetail] Step 2 OK: added to setlist');
      } catch (e, stack) {
        debugPrint('[SetlistDetail] Step 2 FAILED (addToSetlist): $e');
        debugPrint('[SetlistDetail] Stack: $stack');
        rethrow;
      }

      debugPrint('[SetlistDetail] Added ${type.displayName} to setlist');

      // 3. Reload list and refresh in the background so the overlay
      //    closes instantly while the UI catches up.
      loadSongs();
      ref.read(setlistsProvider.notifier).refresh();

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error adding special item: $e');
      debugPrint('[SetlistDetail] Stack: $stack');
      state = state.copyWith(
        error: 'Failed to add ${type.displayName}. Please try again.',
      );
      return false;
    }
  }

  /// Add an existing template to this setlist.
  ///
  /// Reuses an existing special item template (by ID) and adds it to the setlist.
  Future<bool> addExistingTemplate(SpecialItem template) async {
    if (state.isCatalog) {
      state = state.copyWith(
        error: 'Breaks and pauses can only be added to setlists.',
      );
      return false;
    }

    try {
      await _specialItemRepo.addToSetlist(
        setlistId: state.setlistId,
        specialItemId: template.id,
        itemType: template.type,
        insertAtTop: true,
      );

      debugPrint(
        '[SetlistDetail] Added existing template ${template.id} to setlist',
      );

      // Reload list and refresh in the background so the overlay
      // closes instantly while the UI catches up.
      loadSongs();
      ref.read(setlistsProvider.notifier).refresh();

      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error adding template: $e');
      state = state.copyWith(error: 'Failed to add item. Please try again.');
      return false;
    }
  }

  /// Delete a special item from this setlist (by setlist_songs row ID).
  ///
  /// This removes the setlist_songs row, NOT the template.
  Future<bool> deleteItem(String setlistSongId) async {
    state = state.copyWith(isDeleting: true, clearError: true);

    try {
      await _specialItemRepo.removeFromSetlist(setlistSongId: setlistSongId);

      // Update local state - remove the item from items list
      if (state.hasMixedItems) {
        final updatedItems = state.items
            .where((i) => i.setlistSongId != setlistSongId)
            .toList();
        final reindexedItems = updatedItems.asMap().entries.map((entry) {
          return entry.value.copyWith(position: entry.key);
        }).toList();

        final songs = reindexedItems
            .where((i) => i.isSong && i.song != null)
            .map((i) => i.song!)
            .toList();

        state = state.copyWith(
          items: reindexedItems,
          songs: songs,
          isDeleting: false,
        );
      } else {
        state = state.copyWith(isDeleting: false);
      }

      ref.read(setlistsProvider.notifier).refresh();

      debugPrint('[SetlistDetail] Deleted item $setlistSongId');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error deleting item: $e');
      state = state.copyWith(
        isDeleting: false,
        error: 'Failed to delete item. Please try again.',
      );
      return false;
    }
  }
}

/// Provider for setlist detail
final setlistDetailProvider =
    NotifierProvider<SetlistDetailNotifier, SetlistDetailState>(
      SetlistDetailNotifier.new,
    );
