import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/rehearsal.dart';
import '../bands/active_band_controller.dart';
import '../gigs/gig_repository.dart';
import 'rehearsal_repository.dart';

// ============================================================================
// REHEARSAL CONTROLLER
// Manages rehearsal data for the active band.
//
// BAND ISOLATION: Rehearsals are ALWAYS fetched in context of activeBandId.
// When active band changes, rehearsals are automatically refetched.
// ============================================================================

/// State for rehearsal data
class RehearsalState {
  final List<Rehearsal> allRehearsals;
  final List<Rehearsal> upcomingRehearsals;
  final Rehearsal? nextRehearsal;
  final bool isLoading;
  final String? error;

  /// The band ID this state was loaded for (null if never loaded)
  final String? loadedBandId;

  const RehearsalState({
    this.allRehearsals = const [],
    this.upcomingRehearsals = const [],
    this.nextRehearsal,
    this.isLoading = false,
    this.error,
    this.loadedBandId,
  });

  /// Returns true if there are any rehearsals
  bool get hasRehearsals => allRehearsals.isNotEmpty;

  /// Returns true if there's an upcoming rehearsal
  bool get hasUpcomingRehearsal => nextRehearsal != null;

  RehearsalState copyWith({
    List<Rehearsal>? allRehearsals,
    List<Rehearsal>? upcomingRehearsals,
    Rehearsal? nextRehearsal,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearNextRehearsal = false,
    String? loadedBandId,
  }) {
    return RehearsalState(
      allRehearsals: allRehearsals ?? this.allRehearsals,
      upcomingRehearsals: upcomingRehearsals ?? this.upcomingRehearsals,
      nextRehearsal: clearNextRehearsal
          ? null
          : (nextRehearsal ?? this.nextRehearsal),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      loadedBandId: loadedBandId ?? this.loadedBandId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RehearsalState) return false;
    return isLoading == other.isLoading &&
        error == other.error &&
        loadedBandId == other.loadedBandId &&
        allRehearsals.length == other.allRehearsals.length &&
        nextRehearsal?.id == other.nextRehearsal?.id;
  }

  @override
  int get hashCode => Object.hash(
    isLoading,
    error,
    loadedBandId,
    allRehearsals.length,
    nextRehearsal?.id,
  );
}

/// Notifier that manages rehearsal state
class RehearsalNotifier extends Notifier<RehearsalState> {
  /// Track the last band ID we loaded for to prevent duplicate loads
  String? _lastLoadedBandId;

  @override
  RehearsalState build() {
    // Watch the active band — when it changes, reset and refetch
    final bandId = ref.watch(activeBandIdProvider);

    // If no band selected, return empty state
    if (bandId == null) {
      _lastLoadedBandId = null;
      return const RehearsalState();
    }

    // Only trigger load if band actually changed
    if (bandId != _lastLoadedBandId) {
      _lastLoadedBandId = bandId;
      // Trigger async load (can't await in build, so use Future.microtask)
      Future.microtask(() => loadRehearsals());
    }

    return const RehearsalState(isLoading: true);
  }

  RehearsalRepository get _repository => ref.read(rehearsalRepositoryProvider);
  String? get _bandId => ref.read(activeBandIdProvider);

  /// Load all rehearsal data for the active band
  Future<void> loadRehearsals() async {
    final bandId = _bandId;
    if (bandId == null) {
      state = const RehearsalState();
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      loadedBandId: bandId,
    );

    try {
      // Fetch rehearsals in parallel
      final results = await Future.wait([
        _repository.fetchRehearsalsForBand(bandId),
        _repository.fetchUpcomingRehearsals(bandId),
        _repository.fetchNextRehearsal(bandId),
      ]);

      state = state.copyWith(
        allRehearsals: results[0] as List<Rehearsal>,
        upcomingRehearsals: results[1] as List<Rehearsal>,
        nextRehearsal: results[2] as Rehearsal?,
        isLoading: false,
        clearError: true,
        loadedBandId: bandId,
      );

      debugPrint(
        '[RehearsalController] load for band $bandId -> ${(results[0] as List).length} rehearsals, error=null',
      );
    } on NoBandSelectedError {
      // This is expected when no band is selected - not an error state
      debugPrint(
        '[RehearsalController] No band selected, returning empty state',
      );
      state = const RehearsalState();
    } catch (e, stackTrace) {
      // Log detailed error for debugging
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('[RehearsalController] Error loading rehearsals:');
      debugPrint('  Error: $e');
      debugPrint('  Type: ${e.runtimeType}');
      debugPrint('  Stack: $stackTrace');
      debugPrint('═══════════════════════════════════════════════════════════');

      state = state.copyWith(isLoading: false, error: e.toString());
      debugPrint(
        '[RehearsalController] load for band $bandId -> 0 rehearsals, error=${e.toString()}',
      );
    }
  }

  /// Reset state for band change — clears error and lists, sets loading
  void resetForBandChange() {
    debugPrint('[RehearsalController] resetForBandChange');
    state = const RehearsalState(isLoading: true);
  }

  /// Refresh rehearsals (for pull-to-refresh or retry)
  Future<void> refresh() => loadRehearsals();

  /// Clear all rehearsal state (e.g., on logout)
  void reset() {
    state = const RehearsalState();
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Provider for the rehearsal repository
final rehearsalRepositoryProvider = Provider<RehearsalRepository>((ref) {
  return RehearsalRepository();
});

/// Provider for rehearsal state — automatically refetches when active band changes
final rehearsalProvider = NotifierProvider<RehearsalNotifier, RehearsalState>(
  () {
    return RehearsalNotifier();
  },
);

/// Convenience: does the active band have any rehearsals?
final hasRehearsalsProvider = Provider<bool>((ref) {
  return ref.watch(rehearsalProvider).hasRehearsals;
});

/// Convenience: is there an upcoming rehearsal?
final hasUpcomingRehearsalProvider = Provider<bool>((ref) {
  return ref.watch(rehearsalProvider).hasUpcomingRehearsal;
});

/// Convenience: get the next upcoming rehearsal
final nextRehearsalProvider = Provider<Rehearsal?>((ref) {
  return ref.watch(rehearsalProvider).nextRehearsal;
});
