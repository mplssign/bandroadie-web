// ============================================================================
// REHEARSAL PAGINATION CONTROLLER
// Manages pagination state for open-ended recurring rehearsals.
//
// PURPOSE:
// - Limits display of recurring rehearsals with no end date to 10 at a time
// - Tracks how many occurrences are shown per series
// - Provides "load more" functionality
//
// USAGE:
// - Watch this provider to get pagination limits for each series
// - Call loadMore(seriesId) to show next 10 occurrences
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for rehearsal pagination
class RehearsalPaginationState {
  /// Map of series ID (parent rehearsal ID or rehearsal ID if parent) to visible count
  final Map<String, int> visibleCountBySeriesId;

  const RehearsalPaginationState({
    this.visibleCountBySeriesId = const {},
  });

  RehearsalPaginationState copyWith({
    Map<String, int>? visibleCountBySeriesId,
  }) {
    return RehearsalPaginationState(
      visibleCountBySeriesId:
          visibleCountBySeriesId ?? this.visibleCountBySeriesId,
    );
  }

  /// Get visible count for a series (defaults to 10 if not set)
  int getVisibleCount(String seriesId) {
    return visibleCountBySeriesId[seriesId] ?? 10;
  }
}

/// Notifier for managing rehearsal pagination
class RehearsalPaginationNotifier extends Notifier<RehearsalPaginationState> {
  static const int pageSize = 10;

  @override
  RehearsalPaginationState build() {
    return const RehearsalPaginationState();
  }

  /// Load more occurrences for a series
  void loadMore(String seriesId) {
    final currentCount = state.getVisibleCount(seriesId);
    final newCounts = Map<String, int>.from(state.visibleCountBySeriesId);
    newCounts[seriesId] = currentCount + pageSize;

    state = state.copyWith(visibleCountBySeriesId: newCounts);
  }

  /// Reset pagination state (e.g., when band changes)
  void reset() {
    state = const RehearsalPaginationState();
  }

  /// Set initial visible count for a series
  void setInitialCount(String seriesId, int count) {
    if (!state.visibleCountBySeriesId.containsKey(seriesId)) {
      final newCounts = Map<String, int>.from(state.visibleCountBySeriesId);
      newCounts[seriesId] = count;
      state = state.copyWith(visibleCountBySeriesId: newCounts);
    }
  }
}

/// Provider for rehearsal pagination
final rehearsalPaginationProvider =
    NotifierProvider<RehearsalPaginationNotifier, RehearsalPaginationState>(
  RehearsalPaginationNotifier.new,
);
