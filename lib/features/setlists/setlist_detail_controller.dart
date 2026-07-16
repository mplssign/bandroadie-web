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
  final String? youtubeLinks;
  final String? lyrics;
  final String? musicalKey;
  final DateTime timestamp;

  /// Flags to indicate which fields should be cleared to null
  /// (needed because null means "no change" by default)
  final bool clearBpm;
  final bool clearNotes;
  final bool clearYoutubeLinks;
  final bool clearLyrics;
  final bool clearMusicalKey;

  SongUpdateEvent({
    required this.songId,
    this.title,
    this.artist,
    this.bpm,
    this.durationSeconds,
    this.notes,
    this.tuning,
    this.youtubeLinks,
    this.lyrics,
    this.musicalKey,
    this.clearBpm = false,
    this.clearNotes = false,
    this.clearYoutubeLinks = false,
    this.clearLyrics = false,
    this.clearMusicalKey = false,
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
  final CatalogSortMode catalogSortMode;

  /// Starting tuning for tuning-group sort (non-Catalog setlists only).
  /// null = original position order.
  final String? startingTuningId;

  /// Mixed items list (songs + set breaks + pauses) for non-Catalog setlists.
  final List<SetlistItem> items;

  /// Last known good items order (for reorder rollback).
  final List<SetlistItem>? lastKnownGoodItems;

  /// ID of the most recently inserted item (for entry animation).
  final String? newlyInsertedItemId;

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
    this.startingTuningId,
    this.items = const [],
    this.lastKnownGoodItems,
    this.newlyInsertedItemId,
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

  /// Formatted song count with pluralization
  String get formattedSongCount {
    return '$songCount ${songCount == 1 ? 'song' : 'songs'}';
  }

  /// Pause count
  int get pauseCount {
    if (items.isNotEmpty) {
      return items.where((i) => i.isPause).length;
    }
    return 0;
  }

  /// Set break count
  int get setBreakCount {
    if (items.isNotEmpty) {
      return items.where((i) => i.isSetBreak).length;
    }
    return 0;
  }

  /// Format metadata with counts: "24 songs, 6 pauses, 1 set break"
  /// Omits pauses/set breaks when zero.
  String get formattedMetadata {
    final parts = <String>[
      '$songCount ${songCount == 1 ? 'song' : 'songs'}',
    ];
    if (pauseCount > 0) {
      parts.add('$pauseCount ${pauseCount == 1 ? 'pause' : 'pauses'}');
    }
    if (setBreakCount > 0) {
      parts.add(
          '$setBreakCount ${setBreakCount == 1 ? 'set break' : 'set breaks'}');
    }
    return parts.join(', ');
  }

  /// Total item count (songs + breaks + pauses)
  int get itemCount => items.isNotEmpty ? items.length : songs.length;

  /// Is this the Catalog setlist?
  bool get isCatalog => setlistName == kCatalogSetlistName;

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
    String? startingTuningId,
    bool clearStartingTuningId = false,
    List<SetlistItem>? items,
    List<SetlistItem>? lastKnownGoodItems,
    bool clearLastKnownGoodItems = false,
    String? newlyInsertedItemId,
    bool clearNewlyInsertedItemId = false,
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
      startingTuningId: clearStartingTuningId
          ? null
          : (startingTuningId ?? this.startingTuningId),
      items: items ?? this.items,
      lastKnownGoodItems: clearLastKnownGoodItems
          ? null
          : (lastKnownGoodItems ?? this.lastKnownGoodItems),
      newlyInsertedItemId: clearNewlyInsertedItemId
          ? null
          : (newlyInsertedItemId ?? this.newlyInsertedItemId),
    );
  }
}

/// Notifier for setlist detail - watches selectedSetlistProvider
class SetlistDetailNotifier extends Notifier<SetlistDetailState> {
  String? _setlistId;
  String? _setlistName;
  String? _loadedForBandId;
  SetlistDetailState? _cachedState;

  /// Guard against concurrent item reorder persists.
  /// When true, a reorder HTTP call is in-flight.
  bool _isItemReorderInFlight = false;

  /// Set to true when a local reorder happens while a persist is in-flight,
  /// signaling that we need to persist again after the current call completes.
  bool _itemReorderPendingAfterFlight = false;

  /// Original item order before any tuning-group sort is applied.
  /// Restored when starting tuning is cleared.
  List<SetlistItem>? _originalItems;

  @override
  SetlistDetailState build() {
    // Listen for song updates from other setlists (unchanged)
    // IMPORTANT: Must be registered unconditionally on every build() call,
    // before any early returns, or Riverpod will tear it down
    ref.listen<SongUpdateEvent?>(songUpdateBroadcasterProvider, (prev, next) {
      if (next != null && prev?.timestamp != next.timestamp) {
        _applySongUpdate(next);
      }
    });

    // SAFEGUARD: Watch active band ID - clear state if band changes while screen is mounted
    // This replaces the protection that watching selectedSetlistProvider used to provide
    final currentBandId = ref.watch(activeBandIdProvider);

    if (_loadedForBandId != null && _loadedForBandId != currentBandId) {
      if (kDebugMode) {
        debugPrint(
          '[SetlistDetail] Band changed from $_loadedForBandId to $currentBandId, '
          'clearing stale setlist state',
        );
      }
      _setlistId = null;
      _setlistName = null;
      _loadedForBandId = null;
      _cachedState = null;
      return const SetlistDetailState(); // Return empty state
    }

    // FIX: No longer watch selectedSetlistProvider.
    // Screen calls loadSetlist() directly with route args.
    // Return cached state (or empty if not yet initialized). Must NOT read
    // the `state` getter here — on the first build there is no state yet,
    // which throws "Bad state: Tried to read the state of an uninitialized
    // provider."
    return _cachedState ?? const SetlistDetailState();
  }

  /// Public method called by screen to initialize the setlist.
  /// Replaces the previous pattern of watching selectedSetlistProvider.
  void loadSetlist(String id, String name) {
    // If already loaded this setlist, don't reload
    if (_setlistId == id) {
      if (kDebugMode) {
        debugPrint(
            '[SetlistDetail] Setlist $id already loaded, skipping reload');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('[SetlistDetail] Loading setlist: $name (ID: $id)');
    }

    _setlistId = id;
    _setlistName = name;
    _loadedForBandId = ref.read(activeBandIdProvider);
    _cachedState = null;

    state = SetlistDetailState(
      setlistId: id,
      setlistName: name,
      isLoading: true,
    );

    Future.microtask(() => loadSongs());
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
      youtubeLinks: event.youtubeLinks ?? song.youtubeLinks,
      lyrics: event.lyrics ?? song.lyrics,
      musicalKey: event.musicalKey ?? song.musicalKey,
      clearBpm: event.clearBpm,
      clearNotes: event.clearNotes,
      clearYoutubeLinks: event.clearYoutubeLinks,
      clearLyrics: event.clearLyrics,
      clearMusicalKey: event.clearMusicalKey,
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

    _syncSongStateWith(updatedSongs);
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

  /// Sync updated songs into both [state.songs] and [state.items].
  ///
  /// Non-Catalog setlists always populate items (even without set breaks),
  /// so the UI reads song data from items — not songs. Whenever a song's
  /// metadata changes, we must update both lists to keep the UI in sync.
  void _syncSongStateWith(
    List<SetlistSong> updatedSongs, {
    bool clearError = false,
  }) {
    if (state.items.isNotEmpty) {
      final songMap = {for (final s in updatedSongs) s.id: s};
      final updatedItems = state.items.map((item) {
        if (item.isSong && item.song != null) {
          final updated = songMap[item.song!.id];
          return updated != null ? item.copyWith(song: updated) : item;
        }
        return item;
      }).toList();
      state = state.copyWith(
        songs: updatedSongs,
        items: updatedItems,
        clearError: clearError,
      );
    } else {
      state = state.copyWith(
        songs: updatedSongs,
        clearError: clearError,
      );
    }
  }

  /// Load songs for this setlist with band scoping.
  ///
  /// SORTING BEHAVIOR:
  /// - Catalog: Songs only, sorted by active catalogSortMode
  /// - Non-Catalog: Mixed items (songs + specials), position order from DB
  Future<void> loadSongs() async {
    // FIX: Read from instance variables instead of selectedSetlistProvider
    if (_setlistId == null || _setlistName == null) {
      if (kDebugMode) {
        debugPrint(
            '[SetlistDetail] loadSongs called but setlist not initialized');
      }
      return;
    }

    final setlistId = _setlistId!;
    final setlistName = _setlistName!;

    if (setlistId.isEmpty) return;

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
      debugPrint('  setlistId: $setlistId');
      debugPrint('  setlistName: $setlistName');
    }

    try {
      if (state.isCatalog) {
        // Catalog: only songs, no special items
        var songs = await _repository.fetchSongsForSetlist(
          bandId: bandId,
          setlistId: setlistId,
        );

        final currentBandId = _bandId;
        if (currentBandId != bandId) {
          if (kDebugMode) {
            debugPrint(
              '[SetlistDetail] Discarding stale load result: '
              'bandId changed from $bandId to $currentBandId',
            );
          }
          state = state.copyWith(isLoading: false);
          return;
        }

        songs = _applySorting(songs, sortMode: state.catalogSortMode);

        state = state.copyWith(
          setlistId: setlistId,
          setlistName: setlistName,
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
        }
      } else {
        // Non-Catalog: fetch mixed items (songs + special items)
        final mixedItems = await _specialItemRepo.fetchSetlistItems(
          bandId: bandId,
          setlistId: setlistId,
        );

        final currentBandId = _bandId;
        if (currentBandId != bandId) {
          if (kDebugMode) {
            debugPrint(
              '[SetlistDetail] Discarding stale load result: '
              'bandId changed from $bandId to $currentBandId',
            );
          }
          state = state.copyWith(isLoading: false);
          return;
        }

        // Extract songs for backward compatibility
        final songs = mixedItems
            .where((i) => i.isSong && i.song != null)
            .map((i) => i.song!)
            .toList();

        // Reset original-order snapshot so stale data isn't used after reload
        _originalItems = null;

        // Re-apply tuning sort if one was active
        final activeTuning = state.startingTuningId;
        final displayItems = activeTuning != null
            ? _applyTuningGroupSort(
                List<SetlistItem>.from(mixedItems),
                activeTuning,
              )
            : mixedItems;
        if (activeTuning != null) {
          _originalItems = List<SetlistItem>.from(mixedItems);
        }

        state = state.copyWith(
          setlistId: setlistId,
          setlistName: setlistName,
          songs: songs,
          items: displayItems,
          isLoading: false,
          clearLastKnownGood: true,
          clearLastKnownGoodItems: true,
        );

        if (kDebugMode) {
          final breakCount = mixedItems.where((i) => i.isSetBreak).length;
          final pauseCount = mixedItems.where((i) => i.isPause).length;
          debugPrint(
            '[SetlistDetail] Loaded ${mixedItems.length} items: '
            '${songs.length} songs, $breakCount breaks, $pauseCount pauses',
          );
        }
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

  // ── Tuning-group sort (non-Catalog setlists) ─────────────────────────────

  /// Returns the unique tuning IDs present in the current setlist's songs,
  /// sorted in musical proximity order.
  List<String> get availableTunings {
    final songItems = state.items.where((i) => i.isSong && i.song != null);
    final rawTunings = songItems.map((i) => i.song!.tuning);
    return TuningSortService.sortedUniqueTunings(rawTunings);
  }

  /// Cycle to the next starting tuning (or clear if wrapping past last).
  /// Persists the selection via SharedPreferences.
  void cycleStartingTuning() {
    if (state.isCatalog) return;
    final available = availableTunings;
    if (available.length < 2) return; // Nothing to cycle through

    final next = TuningSortService.nextStartingTuning(
      state.startingTuningId,
      available,
    );
    _applyStartingTuning(next);

    // Persist
    final bandId = _bandId;
    if (bandId != null) {
      TuningSortService.setStartingTuningId(
        bandId: bandId,
        setlistId: state.setlistId,
        tuningId: next,
      );
    }
  }

  /// Apply tuning-group sort with [tuningId] as the leading group.
  /// Passing null restores the original position order.
  void _applyStartingTuning(String? tuningId) {
    if (tuningId == null) {
      // Restore original order
      final original = _originalItems;
      _originalItems = null;
      state = state.copyWith(
        clearStartingTuningId: true,
        items: original ?? state.items,
      );
      return;
    }

    // Snapshot original order on first sort
    _originalItems ??= List<SetlistItem>.from(state.items);

    final sorted = _applyTuningGroupSort(
      List<SetlistItem>.from(_originalItems!),
      tuningId,
    );
    state = state.copyWith(startingTuningId: tuningId, items: sorted);
  }

  /// Sort [items] so songs are grouped by tuning (starting with [startingTuningId]),
  /// preserving relative order within each tuning group.
  /// Non-song items (set breaks, pauses) are pushed to the end.
  List<SetlistItem> _applyTuningGroupSort(
    List<SetlistItem> items,
    String startingTuningId,
  ) {
    final songItems = items.where((i) => i.isSong).toList();
    final nonSongItems = items.where((i) => !i.isSong).toList();

    songItems.sort((a, b) {
      final aTuning = a.song?.tuning;
      final bTuning = b.song?.tuning;
      final aPriority = TuningSortService.getTuningGroupPriority(
        aTuning,
        startingTuningId,
      );
      final bPriority = TuningSortService.getTuningGroupPriority(
        bTuning,
        startingTuningId,
      );
      return aPriority.compareTo(bPriority);
    });

    return [...songItems, ...nonSongItems];
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

      // Update local state - remove the song from songs list
      final updatedSongs = state.songs.where((s) => s.id != songId).toList();

      // Re-index positions
      final reindexedSongs = updatedSongs.asMap().entries.map((entry) {
        return entry.value.copyWith(position: entry.key);
      }).toList();

      // Also update items list if it's populated (mixed items mode)
      if (state.items.isNotEmpty) {
        final updatedItems = state.items
            .where((i) => !(i.isSong && i.song?.id == songId))
            .toList()
            .asMap()
            .entries
            .map((e) => e.value.copyWith(position: e.key))
            .toList();

        state = state.copyWith(
          songs: reindexedSongs,
          items: updatedItems,
          isDeleting: false,
        );
      } else {
        state = state.copyWith(songs: reindexedSongs, isDeleting: false);
      }

      // Refresh setlists list to update song count and duration stats
      ref.read(setlistsProvider.notifier).refresh();

      debugPrint('[SetlistDetail] Deleted song $songId');
      return true;
    } catch (e, stackTrace) {
      debugPrint('[SetlistDetail] Error deleting song: $e');
      debugPrint('[SetlistDetail] Stack trace: $stackTrace');
      state = state.copyWith(
        isDeleting: false,
        error: 'Failed to delete song. Please try again.',
      );
      return false;
    }
  }

  /// Copy a song to another setlist.
  /// The song remains in the current setlist.
  ///
  /// Returns true if successful, false on error.
  Future<bool> copySongToSetlist({
    required String songId,
    required String targetSetlistId,
  }) async {
    try {
      final result = await _repository.addSongToSetlist(
        setlistId: targetSetlistId,
        songId: songId,
      );

      if (result == null) return false;

      // Refresh setlists list to update song count and duration stats
      await ref.read(setlistsProvider.notifier).refresh();

      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Copy failed: $e');
      return false;
    }
  }

  /// Move a song to another setlist atomically.
  /// The song is removed from the current setlist and added to the target setlist
  /// via an atomic RPC transaction.
  ///
  /// Returns true if successful, false on error.
  Future<bool> moveSongToSetlist({
    required String songId,
    required String targetSetlistId,
    required String sourceSetlistId,
  }) async {
    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    try {
      final success = await _repository.moveSongBetweenSetlists(
        sourceSetlistId: sourceSetlistId,
        targetSetlistId: targetSetlistId,
        songId: songId,
        bandId: bandId,
      );

      if (!success) return false;

      // ASYNC SAFETY: Verify bandId hasn't changed during the await
      final currentBandId = _bandId;
      if (currentBandId != bandId) {
        if (kDebugMode) {
          debugPrint(
            '[SetlistDetail] Discarding move result: '
            'bandId changed from $bandId to $currentBandId',
          );
        }
        return false;
      }

      // Update local state - remove song from current setlist
      final updatedSongs = state.songs.where((s) => s.id != songId).toList();

      // Re-index positions
      final reindexedSongs = updatedSongs.asMap().entries.map((entry) {
        return entry.value.copyWith(position: entry.key);
      }).toList();

      // Also update items list if it's populated (mixed items mode)
      if (state.items.isNotEmpty) {
        final updatedItems = state.items
            .where((i) => !(i.isSong && i.song?.id == songId))
            .toList()
            .asMap()
            .entries
            .map((e) => e.value.copyWith(position: e.key))
            .toList();

        state = state.copyWith(
          songs: reindexedSongs,
          items: updatedItems,
        );
      } else {
        state = state.copyWith(songs: reindexedSongs);
      }

      // Refresh setlists list to update song count and duration stats
      await ref.read(setlistsProvider.notifier).refresh();

      debugPrint(
          '[SetlistDetail] Moved song $songId to setlist $targetSetlistId');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Move failed: $e');
      return false;
    }
  }

  /// Reorder songs locally (optimistic update).
  ///
  /// Saves the current order as "last known good" before applying changes,
  /// so we can revert if persistence fails.
  void reorderLocal(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;

    // Save current order as last known good (only if not already saved)
    final lastGood =
        state.lastKnownGoodSongs ?? List<SetlistSong>.from(state.songs);

    final songs = List<SetlistSong>.from(state.songs);
    final song = songs.removeAt(oldIndex);
    songs.insert(newIndex, song);

    // Update positions
    final reindexedSongs = songs.asMap().entries.map((entry) {
      return entry.value.copyWith(position: entry.key);
    }).toList();

    debugPrint('[SetlistDetail] reorderLocal: $oldIndex -> $newIndex');

    state = state.copyWith(songs: reindexedSongs, lastKnownGoodSongs: lastGood);
  }

  /// Persist reorder to database.
  ///
  /// On success: clears the lastKnownGoodSongs (current order becomes "known good").
  /// On failure: reverts to lastKnownGoodSongs and shows error.
  Future<bool> persistReorder() async {
    state = state.copyWith(isReordering: true, clearError: true);

    final songIds = state.songs.map((s) => s.id).toList();
    final bandId = _bandId;

    debugPrint('[SetlistDetail] persistReorder:');
    debugPrint('  setlistId: ${state.setlistId}');
    debugPrint('  bandId: $bandId');
    debugPrint('  songCount: ${songIds.length}');

    try {
      await _repository.reorderSongs(
        setlistId: state.setlistId,
        songIdsInOrder: songIds,
        bandId: bandId,
      );

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
      state = state.copyWith(isReordering: false, clearLastKnownGood: true);
      debugPrint('[SetlistDetail] ✓ Persisted reorder successfully');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] ✗ Error persisting reorder: $e');

      // Revert to last known good order
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
        // No backup available - trigger a refetch
        debugPrint('[SetlistDetail] No backup available, triggering refetch');
        state = state.copyWith(
          isReordering: false,
          error: 'Failed to save order. Reloading...',
        );
        // Refetch from server to get the actual persisted order
        Future.microtask(() => loadSongs());
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
    final originalItems = List<SetlistItem>.from(state.items);
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(bpm: bpm);
      }
      return song;
    }).toList();
    _syncSongStateWith(updatedSongs);

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
        items: originalItems,
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
    final originalItems = List<SetlistItem>.from(state.items);
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(clearBpm: true);
      }
      return song;
    }).toList();
    _syncSongStateWith(updatedSongs);

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
        items: originalItems,
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
    final originalItems = List<SetlistItem>.from(state.items);
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(durationSeconds: durationSeconds);
      }
      return song;
    }).toList();
    _syncSongStateWith(updatedSongs);

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
      ref.read(songUpdateBroadcasterProvider.notifier).broadcast(
            SongUpdateEvent(songId: songId, durationSeconds: durationSeconds),
          );

      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error updating duration: $e');
      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        items: originalItems,
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
    final originalItems = List<SetlistItem>.from(state.items);

    // Optimistic update - apply immediately so UI feels instant
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(tuning: tuning);
      }
      return song;
    }).toList();
    _syncSongStateWith(updatedSongs, clearError: true);

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
      state = state.copyWith(
          songs: originalSongs, items: originalItems, error: errorMessage);
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
    final originalItems = List<SetlistItem>.from(state.items);

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
    _syncSongStateWith(updatedSongs, clearError: true);

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
        items: originalItems,
        error: 'Couldn\'t save notes. Try again.',
      );
      return false;
    }
  }

  /// Updates a song's musical key globally.
  ///
  /// Uses optimistic update pattern:
  /// 1. Store original state
  /// 2. Apply change immediately (UI feels instant)
  /// 3. Persist to database
  /// 4. On failure: revert to original and show error
  Future<bool> updateSongMusicalKey(String songId, String? musicalKey) async {
    final bandId = _bandId;
    if (bandId == null) {
      state = state.copyWith(error: 'No band selected');
      return false;
    }

    debugPrint(
      '[SetlistDetail] updateSongMusicalKey: songId=$songId, musicalKey=$musicalKey',
    );

    // Store original state for rollback
    final originalSongs = List<SetlistSong>.from(state.songs);
    final originalItems = List<SetlistItem>.from(state.items);

    // Optimistic update - apply immediately so UI feels instant
    final updatedSongs = state.songs.map((song) {
      if (song.id == songId) {
        return song.copyWith(
          musicalKey: musicalKey,
          clearMusicalKey: musicalKey == null || musicalKey.isEmpty,
        );
      }
      return song;
    }).toList();
    _syncSongStateWith(updatedSongs, clearError: true);

    try {
      await _repository.updateSongMusicalKey(
        bandId: bandId,
        songId: songId,
        musicalKey: musicalKey,
      );
      debugPrint(
        '[SetlistDetail] Successfully updated musical key for song $songId',
      );

      // Broadcast the update to other setlists
      ref
          .read(songUpdateBroadcasterProvider.notifier)
          .broadcast(SongUpdateEvent(songId: songId, musicalKey: musicalKey));

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error updating musical key: $e');
      debugPrint('[SetlistDetail] Stack trace: $stack');

      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        items: originalItems,
        error: 'Couldn\'t save musical key. Try again.',
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
    final originalItems = List<SetlistItem>.from(state.items);

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
    _syncSongStateWith(updatedSongs, clearError: true);

    try {
      await _repository.updateSongYoutubeLinks(
        bandId: bandId,
        songId: songId,
        youtubeLinks: youtubeLinksJson,
      );
      debugPrint(
        '[SetlistDetail] Successfully updated YouTube links for song $songId',
      );

      // Broadcast the update to other setlists
      ref.read(songUpdateBroadcasterProvider.notifier).broadcast(
            SongUpdateEvent(
              songId: songId,
              youtubeLinks: youtubeLinksJson ?? '',
              clearYoutubeLinks:
                  youtubeLinksJson == null || youtubeLinksJson.isEmpty,
            ),
          );

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error updating YouTube links: $e');
      debugPrint('[SetlistDetail] Stack trace: $stack');

      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        items: originalItems,
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
    final originalItems = List<SetlistItem>.from(state.items);

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
    _syncSongStateWith(updatedSongs, clearError: true);

    try {
      await _repository.updateSongLyrics(
        bandId: bandId,
        songId: songId,
        lyrics: lyricsJson,
      );
      debugPrint(
        '[SetlistDetail] Successfully updated lyrics for song $songId',
      );

      // Broadcast the update to other setlists
      ref.read(songUpdateBroadcasterProvider.notifier).broadcast(
            SongUpdateEvent(
              songId: songId,
              lyrics: lyricsJson ?? '',
              clearLyrics: lyricsJson == null || lyricsJson.isEmpty,
            ),
          );

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error updating lyrics: $e');
      debugPrint('[SetlistDetail] Stack trace: $stack');

      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        items: originalItems,
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
    final originalItems = List<SetlistItem>.from(state.items);

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
    _syncSongStateWith(updatedSongs, clearError: true);

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
      ref.read(songUpdateBroadcasterProvider.notifier).broadcast(
            SongUpdateEvent(songId: songId, title: title, artist: artist),
          );

      return true;
    } catch (e, stack) {
      debugPrint('[SetlistDetail] Error updating title/artist: $e');
      debugPrint('[SetlistDetail] Stack trace: $stack');

      // Revert optimistic update
      state = state.copyWith(
        songs: originalSongs,
        items: originalItems,
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
  // SPECIAL ITEMS (SET BREAKS & PAUSES)
  // ==========================================================================

  /// Add a special item (set break or pause) to this setlist.
  ///
  /// Creates a template, appends at the end of the list, reloads, and
  /// sets [newlyInsertedItemId] so the UI can animate the entry.
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
      final template = await _specialItemRepo.createTemplate(
        bandId: bandId,
        type: type,
        durationMinutes: durationMinutes,
        durationSeconds: durationSeconds,
        purposes: purposes,
        customPurposes: customPurposes,
        isSavedTemplate: saveAsTemplate,
      );

      // 2. Add to setlist at the end
      await _specialItemRepo.addToSetlist(
        setlistId: state.setlistId,
        specialItemId: template.id,
        itemType: type,
      );

      // 3. Reload to get the updated list
      await loadSongs();

      // 4. Set the newly-inserted item ID for animation
      // The new item is at the end → last in the items list
      if (state.items.isNotEmpty) {
        state = state.copyWith(
          newlyInsertedItemId: state.items.last.id,
        );
      }

      // 5. Refresh setlists list
      ref.read(setlistsProvider.notifier).refresh();

      debugPrint('[SetlistDetail] Added ${type.displayName} to setlist');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error adding special item: $e');
      state = state.copyWith(
        error: 'Failed to add ${type.displayName}. Please try again.',
      );
      return false;
    }
  }

  /// Update an existing special item's metadata (duration, purposes, etc.).
  /// Reloads the setlist items after updating.
  Future<bool> updateSpecialItem({
    required String specialItemId,
    int? durationMinutes,
    int? durationSeconds,
    bool clearDurationSeconds = false,
    List<String>? purposes,
    List<String>? customPurposes,
  }) async {
    try {
      await _specialItemRepo.updateTemplate(
        templateId: specialItemId,
        durationMinutes: durationMinutes,
        durationSeconds: durationSeconds,
        clearDurationSeconds: clearDurationSeconds,
        purposes: purposes,
        customPurposes: customPurposes,
      );

      await loadSongs();

      ref.read(setlistsProvider.notifier).refresh();
      debugPrint('[SetlistDetail] Updated special item $specialItemId');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error updating special item: $e');
      state = state.copyWith(
        error: 'Failed to update. Please try again.',
      );
      return false;
    }
  }

  /// Add an existing template to this setlist.
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
      );

      await loadSongs();

      if (state.items.isNotEmpty) {
        state = state.copyWith(
          newlyInsertedItemId: state.items.last.id,
        );
      }

      ref.read(setlistsProvider.notifier).refresh();
      debugPrint('[SetlistDetail] Added template ${template.id}');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error adding template: $e');
      state = state.copyWith(
        error: 'Failed to add item. Please try again.',
      );
      return false;
    }
  }

  /// Remove a special item from this setlist (by setlist_songs row ID).
  Future<bool> deleteSpecialItem(String setlistSongId) async {
    try {
      await _specialItemRepo.removeFromSetlist(setlistSongId);

      // Remove from local state
      final updatedItems = state.items
          .where((i) => i.id != setlistSongId)
          .toList()
          .asMap()
          .entries
          .map((e) => e.value.copyWith(position: e.key))
          .toList();

      final updatedSongs = updatedItems
          .where((i) => i.isSong && i.song != null)
          .map((i) => i.song!)
          .toList();

      state = state.copyWith(
        items: updatedItems,
        songs: updatedSongs,
      );

      ref.read(setlistsProvider.notifier).refresh();
      debugPrint('[SetlistDetail] Removed special item $setlistSongId');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error removing special item: $e');
      state = state.copyWith(
        error: 'Failed to remove item. Please try again.',
      );
      return false;
    }
  }

  /// Clear the newly-inserted item ID (after animation completes).
  void clearNewlyInsertedItemId() {
    state = state.copyWith(clearNewlyInsertedItemId: true);
  }

  /// Reorder mixed items locally (optimistic update).
  void reorderItemsLocal(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;

    final lastGood =
        state.lastKnownGoodItems ?? List<SetlistItem>.from(state.items);

    final items = List<SetlistItem>.from(state.items);
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    // Re-index positions
    final reindexed = items.asMap().entries.map((entry) {
      return entry.value.copyWith(position: entry.key);
    }).toList();

    // Also update songs list for backward compatibility
    final songs = reindexed
        .where((i) => i.isSong && i.song != null)
        .map((i) => i.song!)
        .toList();

    state = state.copyWith(
      items: reindexed,
      songs: songs,
      lastKnownGoodItems: lastGood,
    );
  }

  /// Persist mixed-item reorder to database.
  ///
  /// Guarded against concurrent calls: if a persist is already in-flight,
  /// marks a pending flag so the current call will re-persist with the
  /// latest state after completion. This prevents UNIQUE constraint
  /// violations from overlapping multi-step position updates.
  Future<bool> persistItemReorder() async {
    // If a persist is already in-flight, mark pending and return.
    // The in-flight call will re-persist with latest state when done.
    if (_isItemReorderInFlight) {
      _itemReorderPendingAfterFlight = true;
      debugPrint('[SetlistDetail] Item reorder already in-flight, queued');
      return true; // Optimistic: will be persisted when current call finishes
    }

    _isItemReorderInFlight = true;
    _itemReorderPendingAfterFlight = false;
    state = state.copyWith(isReordering: true, clearError: true);

    final itemIds = state.items.map((i) => i.id).toList();

    try {
      await _specialItemRepo.reorderItems(
        setlistId: state.setlistId,
        itemIdsInOrder: itemIds,
      );

      _isItemReorderInFlight = false;

      // If another reorder happened while we were persisting,
      // persist again with the latest state.
      if (_itemReorderPendingAfterFlight) {
        _itemReorderPendingAfterFlight = false;
        debugPrint('[SetlistDetail] Re-persisting queued item reorder');
        return persistItemReorder();
      }

      state = state.copyWith(
        isReordering: false,
        clearLastKnownGoodItems: true,
      );
      debugPrint('[SetlistDetail] Persisted item reorder');
      return true;
    } catch (e) {
      debugPrint('[SetlistDetail] Error persisting item reorder: $e');
      _isItemReorderInFlight = false;
      _itemReorderPendingAfterFlight = false;

      final lastGood = state.lastKnownGoodItems;
      if (lastGood != null && lastGood.isNotEmpty) {
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
        state = state.copyWith(
          isReordering: false,
          error: 'Failed to save order. Reloading...',
        );
        Future.microtask(() => loadSongs());
      }
      return false;
    }
  }
}

/// Provider for setlist detail
final setlistDetailProvider =
    NotifierProvider<SetlistDetailNotifier, SetlistDetailState>(
  SetlistDetailNotifier.new,
);
