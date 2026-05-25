// ============================================================================
// REHEARSAL DISPLAY HELPER
// Helper functions for grouping and paginating rehearsals for display.
//
// PURPOSE:
// - Groups rehearsals into series (standalone, finite recurring, open-ended recurring)
// - Applies pagination to open-ended recurring series
// - Provides flat list for display with "load more" markers
// ============================================================================

import '../../app/models/rehearsal.dart';

/// Represents a rehearsal series (can be single or recurring)
class RehearsalSeries {
  /// Unique identifier for this series (parent ID or single rehearsal ID)
  final String seriesId;

  /// All rehearsals in this series
  final List<Rehearsal> allOccurrences;

  /// Whether this is an open-ended recurring series (no recurrence_until)
  final bool isOpenEnded;

  /// Parent rehearsal (for metadata), or the single rehearsal if not recurring
  final Rehearsal parentOrSingle;

  const RehearsalSeries({
    required this.seriesId,
    required this.allOccurrences,
    required this.isOpenEnded,
    required this.parentOrSingle,
  });

  /// Get visible occurrences based on pagination limit
  List<Rehearsal> getVisibleOccurrences(int limit) {
    if (!isOpenEnded) {
      return allOccurrences; // Show all for finite series
    }
    return allOccurrences.take(limit).toList();
  }

  /// Whether there are more occurrences to load
  bool hasMore(int currentlyVisible) {
    return isOpenEnded && currentlyVisible < allOccurrences.length;
  }

  /// Total count of occurrences
  int get totalCount => allOccurrences.length;
}

/// Helper class for grouping and paginating rehearsals
class RehearsalDisplayHelper {
  /// Group rehearsals into series and identify open-ended ones
  static List<RehearsalSeries> groupIntoSeries(List<Rehearsal> rehearsals) {
    // Map to collect series: key = seriesId, value = list of rehearsals
    final Map<String, List<Rehearsal>> seriesMap = {};
    final Map<String, Rehearsal> parentMap = {}; // Track parent rehearsals

    // First pass: group by series and identify parents
    for (final rehearsal in rehearsals) {
      String seriesId;

      if (rehearsal.parentRehearsalId != null) {
        // This is a child occurrence
        seriesId = rehearsal.parentRehearsalId!;
      } else if (rehearsal.isRecurring) {
        // This is a parent rehearsal
        seriesId = rehearsal.id;
        parentMap[seriesId] = rehearsal;
      } else {
        // Standalone rehearsal (not part of a series)
        seriesId = rehearsal.id;
      }

      seriesMap.putIfAbsent(seriesId, () => []);
      seriesMap[seriesId]!.add(rehearsal);
    }

    // Second pass: create RehearsalSeries objects
    final List<RehearsalSeries> series = [];

    for (final entry in seriesMap.entries) {
      final seriesId = entry.key;
      final occurrences = entry.value;

      // Sort occurrences by date
      occurrences.sort((a, b) => a.date.compareTo(b.date));

      // Get parent or use first occurrence
      final parentOrSingle = parentMap[seriesId] ?? occurrences.first;

      // Check if this is open-ended (recurring with no end date)
      final isOpenEnded =
          parentOrSingle.isRecurring && parentOrSingle.recurrenceUntil == null;

      series.add(RehearsalSeries(
        seriesId: seriesId,
        allOccurrences: occurrences,
        isOpenEnded: isOpenEnded,
        parentOrSingle: parentOrSingle,
      ));
    }

    // Sort series by earliest date
    series.sort((a, b) {
      final aDate = a.allOccurrences.first.date;
      final bDate = b.allOccurrences.first.date;
      return aDate.compareTo(bDate);
    });

    return series;
  }

  /// Flatten series into a displayable list with pagination applied.
  /// Returns a list of items that can be rehearsals or "load more" markers.
  ///
  /// Rehearsal items are globally sorted by date after flattening so that
  /// occurrences from different series are interleaved in chronological order.
  /// Without this sort, all occurrences of Series A would appear before any
  /// occurrences of Series B, causing later dates from Series A to display
  /// ahead of earlier dates from Series B in the horizontal scroll.
  ///
  /// Note: the current caller (home_tab_content.dart) filters out load-more
  /// markers and uses the infinite-scroll listener instead; markers are
  /// retained here for forward compatibility.
  static List<DisplayItem> flattenForDisplay(
    List<RehearsalSeries> series,
    Map<String, int> visibleCountBySeriesId,
  ) {
    final List<DisplayItem> items = [];

    for (final s in series) {
      final visibleCount = visibleCountBySeriesId[s.seriesId] ?? 10;
      final visibleOccurrences = s.getVisibleOccurrences(visibleCount);

      // Add all visible rehearsals
      for (final rehearsal in visibleOccurrences) {
        items.add(DisplayItem.rehearsal(rehearsal));
      }

      // Add "load more" marker if there are more occurrences
      if (s.hasMore(visibleCount)) {
        items.add(DisplayItem.loadMore(
          seriesId: s.seriesId,
          currentCount: visibleCount,
          totalCount: s.totalCount,
        ));
      }
    }

    // Sort rehearsal items globally by date so that occurrences from different
    // series are shown in chronological order. Load-more markers are left in
    // place at the end of their series block (they are filtered out by the
    // current caller anyway).
    items.sort((a, b) {
      if (a.isRehearsal && b.isRehearsal) {
        return a.rehearsal!.date.compareTo(b.rehearsal!.date);
      }
      // Keep load-more markers after rehearsal items
      if (a.isLoadMore) return 1;
      if (b.isLoadMore) return -1;
      return 0;
    });

    return items;
  }
}

/// Represents an item in the display list (either a rehearsal or a "load more" marker)
class DisplayItem {
  final Rehearsal? rehearsal;
  final String? loadMoreSeriesId;
  final int? currentCount;
  final int? totalCount;

  const DisplayItem._({
    this.rehearsal,
    this.loadMoreSeriesId,
    this.currentCount,
    this.totalCount,
  });

  factory DisplayItem.rehearsal(Rehearsal rehearsal) {
    return DisplayItem._(rehearsal: rehearsal);
  }

  factory DisplayItem.loadMore({
    required String seriesId,
    required int currentCount,
    required int totalCount,
  }) {
    return DisplayItem._(
      loadMoreSeriesId: seriesId,
      currentCount: currentCount,
      totalCount: totalCount,
    );
  }

  bool get isRehearsal => rehearsal != null;
  bool get isLoadMore => loadMoreSeriesId != null;
}
