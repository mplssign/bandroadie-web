import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/utils/timezone_helper.dart';
import '../bands/active_band_controller.dart';
import '../bands/band_full_state.dart';
import 'gig_repository.dart';

// ============================================================================
// GIG CONTROLLER
// Manages gig data for the active band.
//
// BAND ISOLATION: Gigs are ALWAYS fetched in context of activeBandId.
// When active band changes, gigs are automatically refetched.
// ============================================================================

/// State for gig data
class GigState {
  final List<Gig> allGigs;
  final List<Gig> upcomingGigs;
  final List<Gig> potentialGigs;
  final List<Gig> confirmedGigs;
  final bool isLoading;
  final String? error;

  /// The band ID this state was loaded for (null if never loaded)
  final String? loadedBandId;

  const GigState({
    this.allGigs = const [],
    this.upcomingGigs = const [],
    this.potentialGigs = const [],
    this.confirmedGigs = const [],
    this.isLoading = false,
    this.error,
    this.loadedBandId,
  });

  /// Returns true if there are any gigs at all
  bool get hasGigs => allGigs.isNotEmpty;

  /// Returns true if there are upcoming (confirmed) gigs
  bool get hasUpcomingGigs =>
      upcomingGigs.where((g) => g.isConfirmed).isNotEmpty;

  /// Returns true if there are potential gigs awaiting RSVP
  bool get hasPotentialGigs => potentialGigs.isNotEmpty;

  /// The next upcoming confirmed gig (or null)
  Gig? get nextConfirmedGig {
    final confirmed = upcomingGigs.where((g) => g.isConfirmed).toList();
    return confirmed.isNotEmpty ? confirmed.first : null;
  }

  /// The first potential gig needing attention (or null)
  Gig? get nextPotentialGig =>
      potentialGigs.isNotEmpty ? potentialGigs.first : null;

  GigState copyWith({
    List<Gig>? allGigs,
    List<Gig>? upcomingGigs,
    List<Gig>? potentialGigs,
    List<Gig>? confirmedGigs,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? loadedBandId,
  }) {
    return GigState(
      allGigs: allGigs ?? this.allGigs,
      upcomingGigs: upcomingGigs ?? this.upcomingGigs,
      potentialGigs: potentialGigs ?? this.potentialGigs,
      confirmedGigs: confirmedGigs ?? this.confirmedGigs,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      loadedBandId: loadedBandId ?? this.loadedBandId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GigState) return false;
    return isLoading == other.isLoading &&
        error == other.error &&
        loadedBandId == other.loadedBandId &&
        allGigs.length == other.allGigs.length &&
        potentialGigs.length == other.potentialGigs.length &&
        confirmedGigs.length == other.confirmedGigs.length;
  }

  @override
  int get hashCode => Object.hash(
        isLoading,
        error,
        loadedBandId,
        allGigs.length,
        potentialGigs.length,
        confirmedGigs.length,
      );
}

/// Notifier that manages gig state
class GigNotifier extends Notifier<GigState> {
  @override
  GigState build() {
    // Watch full band state — provides all data from a single RPC call
    final fullStateAsync = ref.watch(bandFullStateProvider);

    return fullStateAsync.when(
      data: (fullState) {
        if (fullState == null) {
          final activeBandId = ref.read(activeBandIdProvider);
          return GigState(loadedBandId: activeBandId);
        }
        final bandId = fullState.band.id;
        debugPrint(
          '[GigController] RPC data received for band $bandId -> ${fullState.gigs.length} gigs',
        );
        return _categorizeGigs(fullState.gigs, bandId, fullState.band.timezone);
      },
      loading: () {
        final activeBandId = ref.read(activeBandIdProvider);
        return GigState(isLoading: true, loadedBandId: activeBandId);
      },
      error: (e, stackTrace) {
        debugPrint(
            '═══════════════════════════════════════════════════════════');
        debugPrint('[GigController] Error from RPC:');
        debugPrint('  Error: $e');
        debugPrint('  Type: ${e.runtimeType}');
        debugPrint('  Stack: $stackTrace');
        debugPrint(
            '═══════════════════════════════════════════════════════════');
        final activeBandId = ref.read(activeBandIdProvider);
        return GigState(error: e.toString(), loadedBandId: activeBandId);
      },
    );
  }

  GigRepository get _repository => ref.read(gigRepositoryProvider);
  String? get _bandId => ref.read(activeBandIdProvider);

  /// Categorize a flat list of gigs into upcoming, potential, confirmed
  /// using the same client-side time filtering as the repository methods.
  GigState _categorizeGigs(
      List<Gig> allGigs, String bandId, String bandTimezone) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nowUtc = now.toUtc();

    // Upcoming: date >= today AND end time in the future
    final upcomingGigs = allGigs.where((gig) {
      if (gig.date.isBefore(today)) return false;
      return _isEndTimeInFuture(gig, nowUtc, bandTimezone);
    }).toList();

    // Potential: upcoming AND is_potential
    final potentialGigs = upcomingGigs.where((gig) => gig.isPotential).toList();

    // Confirmed: upcoming AND NOT is_potential
    final confirmedGigs =
        upcomingGigs.where((gig) => !gig.isPotential).toList();

    return GigState(
      allGigs: allGigs,
      upcomingGigs: upcomingGigs,
      potentialGigs: potentialGigs,
      confirmedGigs: confirmedGigs,
      isLoading: false,
      loadedBandId: bandId,
    );
  }

  /// Check if a gig's end time is still in the future
  bool _isEndTimeInFuture(Gig gig, DateTime nowUtc, String bandTimezone) {
    try {
      final endDateTime = TimezoneHelper.toUtc(
        gig.date,
        gig.endTime,
        bandTimezone,
      );
      return endDateTime.isAfter(nowUtc);
    } catch (e) {
      // If parsing fails, include the gig to be safe
      return true;
    }
  }

  /// Targeted refresh: fetches gigs individually (for after mutations).
  /// Does NOT use the RPC — only fetches gigs for speed.
  Future<void> loadGigs() async {
    final bandId = _bandId;
    if (bandId == null) {
      state = const GigState();
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      loadedBandId: bandId,
    );

    try {
      final allGigs = await _repository.fetchGigsForBand(bandId);
      final bandTimezone = ref.read(activeBandProvider).activeBand?.timezone ??
          'America/Chicago';
      state = _categorizeGigs(allGigs, bandId, bandTimezone);

      debugPrint(
        '[GigController] refresh for band $bandId -> ${allGigs.length} gigs, error=null',
      );
    } on NoBandSelectedError {
      // This is expected when no band is selected - not an error state
      debugPrint('[GigController] No band selected, returning empty state');
      state = const GigState();
    } catch (e, stackTrace) {
      // Log detailed error for debugging
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('[GigController] Error loading gigs:');
      debugPrint('  Error: $e');
      debugPrint('  Type: ${e.runtimeType}');
      debugPrint('  Stack: $stackTrace');
      debugPrint('═══════════════════════════════════════════════════════════');

      state = state.copyWith(isLoading: false, error: e.toString());
      debugPrint(
        '[GigController] refresh for band $bandId -> 0 gigs, error=${e.toString()}',
      );
    }
  }

  /// Reset state for band change — clears error and lists, sets loading
  void resetForBandChange() {
    debugPrint('[GigController] resetForBandChange');
    state = const GigState(isLoading: true);
  }

  /// Refresh gigs (for pull-to-refresh or retry)
  Future<void> refresh() => loadGigs();

  /// Submit RSVP "Yes" for a gig
  Future<void> rsvpYes(String gigId) async {
    final bandId = _bandId;
    final userId = supabase.auth.currentUser?.id;
    if (bandId == null || userId == null) return;

    try {
      await _repository.submitRsvp(
        gigId: gigId,
        bandId: bandId,
        userId: userId,
        response: 'yes',
      );
      // Refresh gigs to update UI
      await loadGigs();
    } catch (e) {
      state = state.copyWith(error: 'Failed to submit RSVP: $e');
    }
  }

  /// Submit RSVP "No" for a gig
  Future<void> rsvpNo(String gigId) async {
    final bandId = _bandId;
    final userId = supabase.auth.currentUser?.id;
    if (bandId == null || userId == null) return;

    try {
      await _repository.submitRsvp(
        gigId: gigId,
        bandId: bandId,
        userId: userId,
        response: 'no',
      );
      // Refresh gigs to update UI
      await loadGigs();
    } catch (e) {
      state = state.copyWith(error: 'Failed to submit RSVP: $e');
    }
  }

  /// Clear all gig state (e.g., on logout)
  void reset() {
    state = const GigState();
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

/// Provider for the gig repository
final gigRepositoryProvider = Provider<GigRepository>((ref) {
  return GigRepository();
});

/// Provider for gig state — automatically refetches when active band changes
final gigProvider = NotifierProvider<GigNotifier, GigState>(() {
  return GigNotifier();
});

/// Convenience: does the active band have any gigs?
final hasGigsProvider = Provider<bool>((ref) {
  return ref.watch(gigProvider).hasGigs;
});

/// Convenience: are there potential gigs needing RSVP?
final hasPotentialGigsProvider = Provider<bool>((ref) {
  return ref.watch(gigProvider).hasPotentialGigs;
});
