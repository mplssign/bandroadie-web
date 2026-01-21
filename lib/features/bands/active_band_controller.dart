import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandroadie/app/models/band.dart';
import '../home/widgets/animated_bottom_nav_bar.dart' show NavTabIndex;
import '../shell/tab_provider.dart';
import 'band_repository.dart';

// ============================================================================
// ACTIVE BAND CONTROLLER
// Single source of truth for band state with persistence.
//
// ARCHITECTURE:
// - Band list is fetched from Supabase (userBands)
// - Active band ID is persisted to SharedPreferences
// - Active band is derived from userBands + persisted ID
// - Draft band state for real-time preview during editing
//
// ISOLATION RULES:
// - Only one band can be active at a time
// - Switching bands MUST reset all band-scoped state
// - All features that need band context should read from this controller
// ============================================================================

/// Key for persisting active band ID
const _activeBandIdKey = 'active_band_id';

// ============================================================================
// DRAFT BAND STATE - For real-time preview during editing
// ============================================================================

/// Draft band state for Edit Band screen
/// Contains temporary changes that haven't been saved yet
class DraftBandState {
  /// The band being edited (null if not editing)
  final Band? band;

  /// Local file path for picked image (before upload)
  final File? localImageFile;

  /// Whether editing is in progress
  final bool isEditing;

  const DraftBandState({
    this.band,
    this.localImageFile,
    this.isEditing = false,
  });

  DraftBandState copyWith({
    Band? band,
    File? localImageFile,
    bool clearLocalImage = false,
    bool? isEditing,
  }) {
    return DraftBandState(
      band: band ?? this.band,
      localImageFile: clearLocalImage
          ? null
          : (localImageFile ?? this.localImageFile),
      isEditing: isEditing ?? this.isEditing,
    );
  }
}

/// Notifier for draft band state
class DraftBandNotifier extends Notifier<DraftBandState> {
  @override
  DraftBandState build() {
    return const DraftBandState();
  }

  /// Start editing a band - initializes draft from saved band
  void startEditing(Band band) {
    if (kDebugMode) {
      debugPrint('[DraftBand] Started editing: ${band.name}');
    }
    state = DraftBandState(band: band, isEditing: true);
  }

  /// Update draft band name
  void updateName(String name) {
    if (state.band == null) return;
    final updated = Band(
      id: state.band!.id,
      name: name,
      imageUrl: state.band!.imageUrl,
      createdBy: state.band!.createdBy,
      avatarColor: state.band!.avatarColor,
      createdAt: state.band!.createdAt,
      updatedAt: state.band!.updatedAt,
    );
    state = state.copyWith(band: updated);
    if (kDebugMode) {
      debugPrint('[DraftBand] Name updated: $name');
    }
  }

  /// Update draft avatar color
  /// Note: This clears the imageUrl since selecting a color means using initials-based avatar
  void updateAvatarColor(String avatarColor) {
    if (state.band == null) return;
    final updated = Band(
      id: state.band!.id,
      name: state.band!.name,
      imageUrl: null, // Clear image to show color-based initials avatar
      createdBy: state.band!.createdBy,
      avatarColor: avatarColor,
      createdAt: state.band!.createdAt,
      updatedAt: state.band!.updatedAt,
    );
    state = state.copyWith(band: updated, clearLocalImage: true);
    if (kDebugMode) {
      debugPrint('[DraftBand] Avatar color updated: $avatarColor');
    }
  }

  /// Update draft image URL (after upload)
  void updateImageUrl(String? imageUrl) {
    if (state.band == null) return;
    final updated = Band(
      id: state.band!.id,
      name: state.band!.name,
      imageUrl: imageUrl,
      createdBy: state.band!.createdBy,
      avatarColor: state.band!.avatarColor,
      createdAt: state.band!.createdAt,
      updatedAt: state.band!.updatedAt,
    );
    state = state.copyWith(band: updated, clearLocalImage: true);
    if (kDebugMode) {
      debugPrint('[DraftBand] Image URL updated: $imageUrl');
    }
  }

  /// Set local image file (before upload - for instant preview)
  void setLocalImageFile(File? file) {
    state = state.copyWith(localImageFile: file, clearLocalImage: file == null);
    if (kDebugMode) {
      debugPrint('[DraftBand] Local image file set: ${file?.path}');
    }
  }

  /// Cancel editing - clears draft state
  void cancelEditing() {
    if (kDebugMode) {
      debugPrint('[DraftBand] Editing cancelled');
    }
    state = const DraftBandState();
  }

  /// Finish editing - clears draft state (called after successful save)
  void finishEditing() {
    if (kDebugMode) {
      debugPrint('[DraftBand] Editing finished (saved)');
    }
    state = const DraftBandState();
  }
}

/// State for the active band controller
class ActiveBandState {
  /// All bands the user belongs to
  final List<Band> userBands;

  /// The currently selected band (null if none selected)
  final Band? activeBand;

  /// Loading state
  final bool isLoading;

  /// Error message if fetch failed
  final String? error;

  const ActiveBandState({
    this.userBands = const [],
    this.activeBand,
    this.isLoading = false,
    this.error,
  });

  /// Returns true if user has at least one band
  bool get hasBands => userBands.isNotEmpty;

  /// Returns the active band ID (or null)
  String? get activeBandId => activeBand?.id;

  /// Copy with new values
  ActiveBandState copyWith({
    List<Band>? userBands,
    Band? activeBand,
    bool clearActiveBand = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ActiveBandState(
      userBands: userBands ?? this.userBands,
      activeBand: clearActiveBand ? null : (activeBand ?? this.activeBand),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ActiveBandState) return false;
    return activeBand?.id == other.activeBand?.id &&
        isLoading == other.isLoading &&
        error == other.error &&
        userBands.length == other.userBands.length &&
        (userBands.isEmpty || userBands.first.id == other.userBands.first.id);
  }

  @override
  int get hashCode =>
      Object.hash(activeBand?.id, isLoading, error, userBands.length);
}

/// Notifier that manages the active band state with persistence
class ActiveBandNotifier extends Notifier<ActiveBandState> {
  @override
  ActiveBandState build() {
    return const ActiveBandState();
  }

  BandRepository get _bandRepository => ref.read(bandRepositoryProvider);

  /// Load persisted band ID from SharedPreferences
  Future<String?> _loadPersistedBandId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeBandIdKey);
  }

  /// Persist band ID to SharedPreferences
  Future<void> _persistBandId(String bandId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeBandIdKey, bandId);
  }

  /// Clear persisted band ID
  Future<void> _clearPersistedBandId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeBandIdKey);
  }

  /// Fetch all bands for the current user and restore persisted selection
  Future<void> loadUserBands() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final bands = await _bandRepository.fetchUserBands();

      // Try to restore persisted band ID
      final persistedId = await _loadPersistedBandId();
      Band? selected;

      if (persistedId != null) {
        selected = bands.where((b) => b.id == persistedId).firstOrNull;
      }

      // If persisted band not found (or no persisted ID), use first band
      if (selected == null && bands.isNotEmpty) {
        selected = bands.first;
        await _persistBandId(selected.id);
      }

      state = state.copyWith(
        userBands: bands,
        activeBand: selected,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load bands: $e',
      );
    }
  }

  /// Switch to a different band (persists selection)
  ///
  /// IMPORTANT: When switching bands, all band-scoped data should be reset.
  /// Features listening to activeBandId will automatically refetch.
  /// Also navigates to Dashboard to avoid stale data on other screens.
  Future<void> selectBand(Band band) async {
    if (!state.userBands.any((b) => b.id == band.id)) {
      // Safety check: can't select a band user doesn't belong to
      return;
    }

    await _persistBandId(band.id);
    state = state.copyWith(activeBand: band);

    // Navigate to Dashboard when switching bands
    ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);
  }

  /// Select band by ID (persists selection)
  Future<void> selectBandById(String bandId) async {
    final band = state.userBands.where((b) => b.id == bandId).firstOrNull;
    if (band != null) {
      await selectBand(band);
    }
  }

  /// Load bands and then select a specific band by ID
  /// Used after creating a new band to ensure it becomes active
  Future<void> loadAndSelectBand(String bandId) async {
    await loadUserBands();
    await selectBandById(bandId);
  }

  /// Refresh band list and update active band if it changed
  /// Call this after updating a band to reflect changes in the header
  Future<void> refreshBands() async {
    final currentActiveId = state.activeBand?.id;

    try {
      final bands = await _bandRepository.fetchUserBands();

      // Find the current active band in the refreshed list
      Band? selected;
      if (currentActiveId != null) {
        selected = bands.where((b) => b.id == currentActiveId).firstOrNull;
      }

      // If not found, use first band
      if (selected == null && bands.isNotEmpty) {
        selected = bands.first;
        await _persistBandId(selected.id);
      }

      state = state.copyWith(userBands: bands, activeBand: selected);
    } catch (e) {
      // Silently fail - keep current state
    }
  }

  /// Update the active band in state (e.g., after editing)
  ///
  /// This updates both the active band and the band in the userBands list,
  /// ensuring the UI reflects changes immediately without a full reload.
  void updateActiveBand(Band updatedBand) {
    // Update the band in the userBands list
    final updatedList = state.userBands.map((b) {
      return b.id == updatedBand.id ? updatedBand : b;
    }).toList();

    // Update state with the new list and active band
    state = state.copyWith(
      userBands: updatedList,
      activeBand: state.activeBand?.id == updatedBand.id
          ? updatedBand
          : state.activeBand,
    );
  }

  /// Handle band deletion cleanup
  ///
  /// This method ensures proper state cleanup after a band is deleted:
  /// 1. Clears the persisted band ID if the deleted band was active
  /// 2. Reloads the band list from the database
  /// 3. Selects a new active band (first available) or null if no bands remain
  /// 4. Navigates to Dashboard to ensure fresh data
  ///
  /// Call this after successfully deleting a band via the RPC.
  Future<void> handleBandDeletion(String deletedBandId) async {
    if (kDebugMode) {
      debugPrint('[ActiveBand] Handling deletion of band: $deletedBandId');
    }

    // Clear persisted ID if the deleted band was the active one
    if (state.activeBand?.id == deletedBandId) {
      await _clearPersistedBandId();
      if (kDebugMode) {
        debugPrint('[ActiveBand] Cleared persisted ID for deleted band');
      }
    }

    // Reload bands and auto-select a new one
    await loadUserBands();

    // Always navigate to Dashboard after deletion to ensure fresh UI
    // - If bands remain, shows the new active band's dashboard
    // - If no bands remain, shows NoBandState (create/join prompt)
    ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);

    if (kDebugMode) {
      debugPrint(
        '[ActiveBand] Deletion cleanup complete. New active band: ${state.activeBand?.name ?? "none"}',
      );
    }
  }

  /// Clear active band (e.g., on logout)
  Future<void> clearActiveBand() async {
    await _clearPersistedBandId();
    state = state.copyWith(clearActiveBand: true);
  }

  /// Reset all state (e.g., on logout)
  Future<void> reset() async {
    await _clearPersistedBandId();
    state = const ActiveBandState();
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Provider for the band repository
final bandRepositoryProvider = Provider<BandRepository>((ref) {
  return BandRepository();
});

/// Provider for the active band state
final activeBandProvider =
    NotifierProvider<ActiveBandNotifier, ActiveBandState>(() {
      return ActiveBandNotifier();
    });

/// Provider for draft band state (used during editing)
final draftBandProvider = NotifierProvider<DraftBandNotifier, DraftBandState>(
  () {
    return DraftBandNotifier();
  },
);

/// Provider that returns the band to display in the header
/// Returns draft band if editing, otherwise returns active band
final displayBandProvider = Provider<Band?>((ref) {
  final draftState = ref.watch(draftBandProvider);
  final activeState = ref.watch(activeBandProvider);

  // If editing, return the draft band for real-time preview
  if (draftState.isEditing && draftState.band != null) {
    return draftState.band;
  }

  // Otherwise return the saved active band
  return activeState.activeBand;
});

/// Provider for the local image file being previewed (before upload)
final draftLocalImageProvider = Provider<File?>((ref) {
  final draftState = ref.watch(draftBandProvider);
  if (draftState.isEditing) {
    return draftState.localImageFile;
  }
  return null;
});

/// Convenience provider for just the active band ID
/// Use this when you only need the ID for queries
final activeBandIdProvider = Provider<String?>((ref) {
  return ref.watch(activeBandProvider).activeBandId;
});

/// Convenience provider for checking if user has any bands
final hasBandsProvider = Provider<bool>((ref) {
  return ref.watch(activeBandProvider).hasBands;
});
