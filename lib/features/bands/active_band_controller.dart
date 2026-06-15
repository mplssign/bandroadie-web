import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandroadie/app/models/band.dart';
import '../home/widgets/animated_bottom_nav_bar.dart' show NavTabIndex;
import '../members/permissions/band_permissions_provider.dart';
import '../setlists/setlist_detail_controller.dart'
    show selectedSetlistProvider;
import '../shell/tab_provider.dart';
import 'band_repository.dart';

// ============================================================================
// ACTIVE BAND CONTROLLER
// ============================================================================

/// Key for persisting active band ID
const _activeBandIdKey = 'active_band_id';

class DraftBandState {
  final Band? band;

  final File? localImageFile;

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
      localImageFile:
          clearLocalImage ? null : (localImageFile ?? this.localImageFile),
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
      timezone: state.band!.timezone,
      createdAt: state.band!.createdAt,
      updatedAt: state.band!.updatedAt,
    );
    state = state.copyWith(band: updated);
    if (kDebugMode) {
      debugPrint('[DraftBand] Name updated: $name');
    }
  }

  /// Update draft avatar color
  void updateAvatarColor(String avatarColor) {
    if (state.band == null) return;
    final updated = Band(
      id: state.band!.id,
      name: state.band!.name,
      imageUrl: null,
      createdBy: state.band!.createdBy,
      avatarColor: avatarColor,
      timezone: state.band!.timezone,
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
      timezone: state.band!.timezone,
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
  final List<Band> userBands;

  final Band? activeBand;

  final bool isLoading;

  final String? error;

  const ActiveBandState({
    this.userBands = const [],
    this.activeBand,
    this.isLoading = false,
    this.error,
  });

  /// Returns true if user has at least one band
  bool get hasBands => userBands.isNotEmpty;

  String? get activeBandId => activeBand?.id;

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
        activeBand?.name == other.activeBand?.name &&
        activeBand?.imageUrl == other.activeBand?.imageUrl &&
        activeBand?.avatarColor == other.activeBand?.avatarColor &&
        isLoading == other.isLoading &&
        error == other.error &&
        userBands.length == other.userBands.length &&
        (userBands.isEmpty || userBands.first.id == other.userBands.first.id);
  }

  @override
  int get hashCode => Object.hash(
        activeBand?.id,
        activeBand?.name,
        activeBand?.imageUrl,
        activeBand?.avatarColor,
        isLoading,
        error,
        userBands.length,
      );
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
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_activeBandIdKey);
    } catch (e) {
      debugPrint(
        '[ActiveBand] ⚠️ SharedPreferences unavailable (private browsing?): $e',
      );
      debugPrint('[ActiveBand] Falling back to in-memory state only');
      return null;
    }
  }

  /// Persist band ID to SharedPreferences
  Future<void> _persistBandId(String bandId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeBandIdKey, bandId);
    } catch (e) {
      debugPrint(
        '[ActiveBand] ⚠️ Failed to persist band ID (private browsing?): $e',
      );
      debugPrint('[ActiveBand] Band selection will not survive page reload');
    }
  }

  /// Clear persisted band ID
  Future<void> _clearPersistedBandId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeBandIdKey);
    } catch (e) {
      debugPrint('[ActiveBand] ⚠️ Failed to clear persisted band ID: $e');
    }
  }

  /// Fetch all bands for the current user and restore persisted selection
  Future<void> loadUserBands() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final results = await Future.wait([
        _bandRepository.fetchUserBands(),
        _loadPersistedBandId(),
      ]);

      final bandsResult = results[0];
      if (bandsResult == null) {
        debugPrint(
            '[ActiveBand] ⚠️ Band fetch returned null, defaulting to empty list');
        state = state.copyWith(
          userBands: const [],
          activeBand: null,
          clearActiveBand: true,
          isLoading: false,
        );
        return;
      }

      final bands = bandsResult as List<Band>;

      if (bands.isEmpty) {
        debugPrint('[ActiveBand] No bands found for user');
        state = state.copyWith(
          userBands: const [],
          activeBand: null,
          clearActiveBand: true,
          isLoading: false,
        );
        return;
      }

      final persistedId = results[1] as String?;
      Band? selected;

      if (persistedId != null && persistedId.isNotEmpty) {
        selected = bands.where((b) => b.id == persistedId).firstOrNull;
      }

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
      debugPrint('[ActiveBand] ❌ Failed to load bands: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load bands: $e',
      );
    }
  }

  /// Switch to a different band (persists selection)
  Future<void> selectBand(Band band) async {
    if (!state.userBands.any((b) => b.id == band.id)) {
      return;
    }

    await _persistBandId(band.id);
    state = state.copyWith(activeBand: band);
    ref.invalidate(displayBandProvider);

    ref.invalidate(currentUserPermissionsProvider);

    ref.read(selectedSetlistProvider.notifier).clear();

    ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);
  }

  /// Select band by ID (persists selection)
  Future<void> selectBandById(String bandId) async {
    final band = state.userBands.where((b) => b.id == bandId).firstOrNull;
    if (band != null) {
      await selectBand(band);
    }
  }

  /// Load bands and then select a specific band by ID.
  Future<void> loadAndSelectBand(String bandId) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final bands = await _bandRepository.fetchUserBands();

      // Add defensive null/empty guards
      if (bands.isEmpty) {
        debugPrint('[ActiveBand] ⚠️ loadAndSelectBand: No bands found');
        state = state.copyWith(
          userBands: const [],
          activeBand: null,
          clearActiveBand: true,
          isLoading: false,
        );
        return;
      }

      Band? selected = bands.where((b) => b.id == bandId).firstOrNull;
      selected ??= bands.firstOrNull;

      if (selected != null) {
        await _persistBandId(selected.id);
      }

      state = state.copyWith(
        userBands: bands,
        activeBand: selected,
        isLoading: false,
      );

      Future.microtask(() {
        ref.invalidate(currentUserPermissionsProvider);
        ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);
      });
    } catch (e) {
      debugPrint('[ActiveBand] ❌ loadAndSelectBand failed: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load bands: $e',
      );
    }
  }

  /// Refresh band list and update active band if it changed
  Future<void> refreshBands() async {
    final currentActiveId = state.activeBand?.id;

    try {
      final bands = await _bandRepository.fetchUserBands();

      // Add defensive null/empty guards
      if (bands.isEmpty) {
        debugPrint('[ActiveBand] ⚠️ refreshBands: No bands found');
        state = state.copyWith(
          userBands: const [],
          activeBand: null,
          clearActiveBand: true,
        );
        return;
      }

      Band? selected;
      if (currentActiveId != null && currentActiveId.isNotEmpty) {
        selected = bands.where((b) => b.id == currentActiveId).firstOrNull;
      }

      if (selected == null && bands.isNotEmpty) {
        selected = bands.first;
        await _persistBandId(selected.id);
      }

      state = state.copyWith(userBands: bands, activeBand: selected);
    } catch (e) {
      debugPrint('[ActiveBand] ⚠️ refreshBands failed: $e');
    }
  }

  /// Update the active band in state (e.g., after editing)
  void updateActiveBand(Band updatedBand) {
    final updatedList = state.userBands.map((b) {
      return b.id == updatedBand.id ? updatedBand : b;
    }).toList();

    state = state.copyWith(
      userBands: updatedList,
      activeBand: state.activeBand?.id == updatedBand.id
          ? updatedBand
          : state.activeBand,
    );
  }

  /// Handle band deletion cleanup
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

    await loadUserBands();

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

    ref.invalidate(currentUserPermissionsProvider);
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

final bandRepositoryProvider = Provider<BandRepository>((ref) {
  return BandRepository();
});

final activeBandProvider =
    NotifierProvider<ActiveBandNotifier, ActiveBandState>(() {
  return ActiveBandNotifier();
});

final draftBandProvider = NotifierProvider<DraftBandNotifier, DraftBandState>(
  () {
    return DraftBandNotifier();
  },
);

final displayBandProvider = Provider<Band?>((ref) {
  final draftState = ref.watch(draftBandProvider);
  final activeState = ref.watch(activeBandProvider);

  if (draftState.isEditing && draftState.band != null) {
    return draftState.band;
  }

  return activeState.activeBand;
});

final draftLocalImageProvider = Provider<File?>((ref) {
  final draftState = ref.watch(draftBandProvider);
  if (draftState.isEditing) {
    return draftState.localImageFile;
  }
  return null;
});

final activeBandIdProvider = Provider<String?>((ref) {
  return ref.watch(activeBandProvider).activeBandId;
});

/// Convenience provider for checking if user has any bands
final hasBandsProvider = Provider<bool>((ref) {
  return ref.watch(activeBandProvider).hasBands;
});
