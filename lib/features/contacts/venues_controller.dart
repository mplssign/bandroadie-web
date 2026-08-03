import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/venue.dart';
import 'venues_repository.dart';

// ============================================================================
// VENUES CONTROLLER
// Riverpod state management for the Venues view.
// ============================================================================

class VenuesState {
  final List<Venue> venues;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final List<Venue> filteredVenues;

  const VenuesState({
    this.venues = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.filteredVenues = const [],
  });

  bool get hasVenues => venues.isNotEmpty;

  VenuesState copyWith({
    List<Venue>? venues,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? searchQuery,
    List<Venue>? filteredVenues,
  }) {
    return VenuesState(
      venues: venues ?? this.venues,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      filteredVenues: filteredVenues ?? this.filteredVenues,
    );
  }
}

class VenuesNotifier extends Notifier<VenuesState> {
  final VenuesRepository _repository = VenuesRepository();

  @override
  VenuesState build() => const VenuesState();

  Future<void> load(String? bandId) async {
    if (bandId == null || bandId.isEmpty) {
      state = state.copyWith(
        venues: [],
        isLoading: false,
        error: 'No band selected',
        filteredVenues: [],
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final venues = await _repository.fetchVenues(bandId: bandId);
      state = state.copyWith(
        venues: venues,
        isLoading: false,
        filteredVenues: _filterVenues(venues, state.searchQuery),
      );

      if (kDebugMode) {
        debugPrint('[VenuesController] Loaded ${venues.length} venues');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      if (kDebugMode) {
        debugPrint('[VenuesController] Error loading venues: $e');
      }
    }
  }

  Future<void> refresh(String? bandId) async {
    if (bandId == null || bandId.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final venues =
          await _repository.fetchVenues(bandId: bandId, forceRefresh: true);
      state = state.copyWith(
        venues: venues,
        isLoading: false,
        filteredVenues: _filterVenues(venues, state.searchQuery),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<Venue?> create({
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final venue = await _repository.createVenue(bandId: bandId, data: data);
      await load(bandId);
      return venue;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VenuesController] Error creating venue: $e');
      }
      return null;
    }
  }

  Future<Venue> createForGigSave({
    required String bandId,
    required String name,
    String? city,
    String? address,
    String? state,
    required bool isPotential,
  }) async {
    try {
      final venue = await _repository.createVenueForGigSave(
        bandId: bandId,
        name: name,
        city: city,
        address: address,
        state: state,
        isPotential: isPotential,
      );
      await load(bandId);
      return venue;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VenuesController] Error creating venue for gig save: $e');
      }
      rethrow;
    }
  }

  Future<Venue?> update({
    required String id,
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final venue = await _repository.updateVenue(id: id, data: data);
      await load(bandId);
      return venue;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VenuesController] Error updating venue: $e');
      }
      return null;
    }
  }

  Future<bool> delete({
    required String id,
    required String bandId,
  }) async {
    try {
      await _repository.deleteVenue(id: id, bandId: bandId);
      await load(bandId);
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[VenuesController] Error deleting venue: $e');
      }
      return false;
    }
  }

  void reset() {
    _repository.clearCache();
    state = const VenuesState();
  }

  void setSearchQuery(String query) {
    state = state.copyWith(
      searchQuery: query,
      filteredVenues: _filterVenues(state.venues, query),
    );
  }

  List<Venue> _filterVenues(List<Venue> venues, String query) {
    if (query.isEmpty) return venues;
    final lower = query.toLowerCase();
    return venues.where((v) {
      if (v.name.toLowerCase().contains(lower)) return true;
      if (v.city != null && v.city!.toLowerCase().contains(lower)) {
        return true;
      }
      return v.contacts.any((c) => c.name.toLowerCase().contains(lower));
    }).toList();
  }
}

final venuesProvider = NotifierProvider<VenuesNotifier, VenuesState>(
  VenuesNotifier.new,
);
