import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/constants/app_constants.dart';
import '../bands/active_band_controller.dart';
import 'models/setlist_song.dart';
import 'services/tuning_sort_service.dart';
import 'setlist_repository.dart';
import 'setlists_screen.dart';

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

  /// Tuning sort mode for non-Catalog setlists.
  /// Persisted per-setlist via TuningSortService.
  final TuningSortMode tuningSortMode;

  const SetlistDetailState({
    this.setlistId = '',
    this.setlistName = '',
    this.songs = const [],
    this.isLoading = false,
    this.isDeleting = false,
    this.isReordering = false,
    this.error,
    this.lastKnownGoodSongs,
    this.tuningSortMode = TuningSortMode.standard,
  });

  /// Total duration of all songs
  Duration get totalDuration {
    return songs.fold(Duration.zero, (sum, song) => sum + song.duration);
  }

  /// Formatted total duration as "Xh XXm"
  String get formattedDuration {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  /// Song count
  int get songCount => songs.length;

  /// Formatted song count with pluralization
  String get formattedSongCount {
    return '$songCount ${songCount == 1 ? 'song' : 'songs'}';
  }

  /// Is this the Catalog setlist?
  /// Detection: Uses the shared constant kCatalogSetlistName from app_constants.
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
    TuningSortMode? tuningSortMode,
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
      tuningSortMode: tuningSortMode ?? this.tuningSortMode,
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

    final updatedSongs = List<SetlistSong>.from(state.songs);
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

    state = state.copyWith(songs: updatedSongs);
  }

  /// Override state setter to cache state for rebuild preservation
  @override
  set state(SetlistDetailState value) {
    _cachedState = value;
    super.state = value;
  }

  SetlistRepository get _repository => ref.read(setlistRepositoryProvider);
  String? get _bandId => ref.read(activeBandIdProvider);

  /// Load songs for this setlist with band scoping.
  ///
  /// SORTING BEHAVIOR:
  /// - Catalog: Always sorted alphabetically by artist, then title (display order only)
  /// - Non-Catalog: Sorted by persisted tuning mode preference
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
      var songs = await _repository.fetchSongsForSetlist(
        bandId: bandId,
        setlistId: state.setlistId,
      );

      // Load persisted tuning sort mode for non-Catalog setlists
      TuningSortMode sortMode = TuningSortMode.standard;
      if (!state.isCatalog) {
        sortMode = await TuningSortService.getSortMode(
          bandId: bandId,
          setlistId: state.setlistId,
        );
      }

      // Apply sorting
      songs = _applySorting(
        songs,
        isCatalog: state.isCatalog,
        sortMode: sortMode,
      );

      state = state.copyWith(
        songs: songs,
        isLoading: false,
        tuningSortMode: sortMode,
        clearLastKnownGood: true, // Loaded data is now the source of truth
      );

      if (kDebugMode) {
        debugPrint(
          '[SetlistDetail] Loaded ${songs.length} songs for ${state.setlistName}',
        );
        if (!state.isCatalog) {
          debugPrint('[SetlistDetail] Tuning sort mode: ${sortMode.label}');
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

  /// Apply sorting to a list of songs based on context.
  ///
  /// CATALOG: Alphabetical by artist (case-insensitive), then by title.
  /// NON-CATALOG: By tuning priority based on selected mode, then by artist, then by title.
  /// The selected tuning mode's songs appear first, followed by remaining tunings in rotation order.
  List<SetlistSong> _applySorting(
    List<SetlistSong> songs, {
    required bool isCatalog,
    required TuningSortMode sortMode,
  }) {
    final sorted = List<SetlistSong>.from(songs);

    if (isCatalog) {
      // Catalog: Always alphabetical by artist, then title
      sorted.sort((a, b) {
        final artistCompare = a.artist.toLowerCase().compareTo(
          b.artist.toLowerCase(),
        );
        if (artistCompare != 0) return artistCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    } else {
      // All tuning modes: Sort by tuning priority, then by artist, then by title
      // The selected mode's tuning appears first (e.g., Standard mode = Standard songs first)
      sorted.sort((a, b) {
        final aPriority = TuningSortService.getTuningPriority(
          a.tuning,
          sortMode,
        );
        final bPriority = TuningSortService.getTuningPriority(
          b.tuning,
          sortMode,
        );

        if (aPriority != bPriority) {
          return aPriority.compareTo(bPriority);
        }

        // Within same tuning priority, sort by artist then title
        final artistCompare = a.artist.toLowerCase().compareTo(
          b.artist.toLowerCase(),
        );
        if (artistCompare != 0) return artistCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }

    return sorted;
  }

  /// Cycle to the next tuning sort mode (non-Catalog only).
  /// Persists the new mode and re-sorts the songs.
  Future<void> cycleTuningSortMode() async {
    if (state.isCatalog) return; // No tuning sort for Catalog

    final bandId = _bandId;
    if (bandId == null) return;

    final newMode = state.tuningSortMode.next;

    // Persist the new mode
    await TuningSortService.setSortMode(
      bandId: bandId,
      setlistId: state.setlistId,
      mode: newMode,
    );

    // Re-sort songs with new mode
    final sortedSongs = _applySorting(
      state.songs,
      isCatalog: false,
      sortMode: newMode,
    );

    state = state.copyWith(tuningSortMode: newMode, songs: sortedSongs);

    if (kDebugMode) {
      debugPrint('[SetlistDetail] Changed tuning sort to: ${newMode.label}');
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

      // Update local state - remove the song
      final updatedSongs = state.songs.where((s) => s.id != songId).toList();

      // Re-index positions
      final reindexedSongs = updatedSongs.asMap().entries.map((entry) {
        return entry.value.copyWith(position: entry.key);
      }).toList();

      state = state.copyWith(songs: reindexedSongs, isDeleting: false);

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

    // Adjust newIndex if moving down
    final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    songs.insert(adjustedIndex, song);

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
}

/// Provider for setlist detail
final setlistDetailProvider =
    NotifierProvider<SetlistDetailNotifier, SetlistDetailState>(
      SetlistDetailNotifier.new,
    );
