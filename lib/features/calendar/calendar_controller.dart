import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/block_out.dart';
import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/app/utils/time_formatter.dart';
import '../bands/active_band_controller.dart';
import '../gigs/gig_repository.dart';
import '../rehearsals/rehearsal_repository.dart';
import 'block_out_repository.dart';
import 'calendar_markers.dart';
import 'models/calendar_event.dart';

// ============================================================================
// CALENDAR CONTROLLER
// Manages calendar state: selected month, all events for the month.
//
// Combines data from gigs and rehearsals tables.
// Events are filtered by the currently active band.
// Uses in-memory cache keyed by "$bandId-$year-$month" to avoid re-fetching.
// ============================================================================

/// Cached month data
class MonthData {
  final List<CalendarEvent> events;
  final DateTime fetchedAt;

  const MonthData({required this.events, required this.fetchedAt});

  /// Cache is considered stale after 5 minutes
  bool get isStale => DateTime.now().difference(fetchedAt).inMinutes > 5;
}

/// State for the calendar feature
class CalendarState {
  /// Currently viewed month (year + month, day is ignored)
  final DateTime selectedMonth;

  /// All events (gigs + rehearsals) for the active band
  final List<CalendarEvent> allEvents;

  /// Pre-computed markers map for efficient grid rendering
  final Map<DayKey, CalendarDayMarkers> markers;

  /// Loading indicator
  final bool isLoading;

  /// Error message if data fetch failed
  final String? error;

  const CalendarState({
    required this.selectedMonth,
    this.allEvents = const [],
    this.markers = const {},
    this.isLoading = false,
    this.error,
  });

  /// Events for the selected month only, sorted by date then start time
  List<CalendarEvent> get eventsForMonth {
    return allEvents.where((event) {
      return event.date.year == selectedMonth.year &&
          event.date.month == selectedMonth.month;
    }).toList()..sort(_compareByDateAndTime);
  }

  /// Compare two events by date, then by start time
  static int _compareByDateAndTime(CalendarEvent a, CalendarEvent b) {
    // First compare by date
    final dateComparison = a.date.compareTo(b.date);
    if (dateComparison != 0) return dateComparison;

    // If same date, compare by start time
    // Block outs (empty start time) should come last
    if (a.startTime.isEmpty && b.startTime.isEmpty) return 0;
    if (a.startTime.isEmpty) return 1;
    if (b.startTime.isEmpty) return -1;

    // Parse start times and compare
    final aTime = TimeFormatter.parse(a.startTime);
    final bTime = TimeFormatter.parse(b.startTime);
    return aTime.totalMinutes.compareTo(bTime.totalMinutes);
  }

  /// Events grouped by date for calendar indicators
  Map<DateTime, List<CalendarEvent>> get eventsByDate {
    final map = <DateTime, List<CalendarEvent>>{};
    for (final event in allEvents) {
      final dateKey = DateTime(
        event.date.year,
        event.date.month,
        event.date.day,
      );
      map.putIfAbsent(dateKey, () => []).add(event);
    }
    return map;
  }

  /// Get events for a specific date
  List<CalendarEvent> eventsForDate(DateTime date) {
    final dateKey = DateTime(date.year, date.month, date.day);
    return eventsByDate[dateKey] ?? [];
  }

  /// Check if a date has events
  bool hasEvents(DateTime date) {
    return eventsForDate(date).isNotEmpty;
  }

  /// Check if a date has a gig (uses markers if available, fallback to events)
  bool hasGig(DateTime date) {
    final key = dayKey(date);
    if (markers.containsKey(key)) {
      return markers[key]!.gig;
    }
    return eventsForDate(date).any((e) => e.isGig);
  }

  /// Check if a date has a rehearsal (uses markers if available, fallback to events)
  bool hasRehearsal(DateTime date) {
    final key = dayKey(date);
    if (markers.containsKey(key)) {
      return markers[key]!.rehearsal;
    }
    return eventsForDate(date).any((e) => e.isRehearsal);
  }

  /// Check if a date has a block out
  bool hasBlockOut(DateTime date) {
    final key = dayKey(date);
    return markers[key]?.blockOut ?? false;
  }

  /// Get markers for a specific date
  CalendarDayMarkers getMarkers(DateTime date) {
    return getMarkersForDate(markers, date);
  }

  CalendarState copyWith({
    DateTime? selectedMonth,
    List<CalendarEvent>? allEvents,
    Map<DayKey, CalendarDayMarkers>? markers,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return CalendarState(
      selectedMonth: selectedMonth ?? this.selectedMonth,
      allEvents: allEvents ?? this.allEvents,
      markers: markers ?? this.markers,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Notifier for calendar state
class CalendarNotifier extends Notifier<CalendarState> {
  /// In-memory cache keyed by "$bandId-$year-$month"
  static final Map<String, MonthData> _cache = {};

  /// Track the last band ID we loaded for to prevent duplicate loads
  String? _lastLoadedBandId;

  @override
  CalendarState build() {
    // Watch the active band - when it changes, refetch events
    final bandId = ref.watch(activeBandIdProvider);

    if (bandId == null || bandId.isEmpty) {
      _lastLoadedBandId = null;
      return CalendarState(
        selectedMonth: DateTime.now(),
        error: 'No band selected',
      );
    }

    // Only trigger load if band actually changed
    if (bandId != _lastLoadedBandId) {
      _lastLoadedBandId = bandId;
      // Trigger async load
      Future.microtask(() => loadEvents());
    }

    return CalendarState(selectedMonth: DateTime.now(), isLoading: true);
  }

  GigRepository get _gigRepository => GigRepository();
  RehearsalRepository get _rehearsalRepository => RehearsalRepository();
  BlockOutRepository get _blockOutRepository => BlockOutRepository();
  String? get _bandId => ref.read(activeBandIdProvider);

  /// Generate cache key for current month and band
  String _cacheKey(String bandId, int year, int month) =>
      '$bandId-$year-$month';

  /// Load all events (gigs + rehearsals + block outs) for the active band
  Future<void> loadEvents({bool forceRefresh = false}) async {
    final bandId = _bandId;
    if (bandId == null || bandId.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Fetch gigs, rehearsals, and block outs in parallel
      final results = await Future.wait([
        _gigRepository.fetchGigsForBand(bandId),
        _rehearsalRepository.fetchRehearsalsForBand(bandId),
        _blockOutRepository.fetchBlockOutsForBand(bandId),
      ]);

      final gigs = results[0] as List<Gig>;
      final rehearsals = results[1] as List<Rehearsal>;
      final blockOuts = results[2] as List<BlockOut>;

      // Fetch user names for block outs
      final userNames = await _fetchUserNames(blockOuts);

      // Group consecutive block outs into spans
      final blockOutSpans = _groupBlockOutsIntoSpans(blockOuts, userNames);

      // Combine into CalendarEvents
      final events = <CalendarEvent>[
        ...gigs.map((g) => CalendarEvent.fromGig(g)),
        ...rehearsals.map((r) => CalendarEvent.fromRehearsal(r)),
        ...blockOutSpans.map((s) => CalendarEvent.fromBlockOutSpan(s)),
      ];

      // Sort by date
      events.sort((a, b) => a.date.compareTo(b.date));

      // Convert BlockOut models to BlockOutRange for marker computation
      // Each BlockOut is now a single date (the new block_dates schema)
      final blockOutRanges = blockOuts
          .map(
            (bo) => BlockOutRange(
              startDate: bo.date,
              untilDate: null, // Single date, no range
            ),
          )
          .toList();

      // Build markers map (single source of truth for grid indicators)
      final markers = buildCalendarMarkers(
        gigs: gigs,
        rehearsals: rehearsals,
        blockOuts: blockOutRanges,
      );

      // Update cache for each month that has events
      _updateCache(bandId, events);

      state = state.copyWith(
        allEvents: events,
        markers: markers,
        isLoading: false,
      );

      if (kDebugMode) {
        debugPrint(
          '[CalendarController] Loaded ${gigs.length} gigs, ${rehearsals.length} rehearsals, ${blockOuts.length} block outs (${blockOutSpans.length} spans)',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load events: $e',
      );
      if (kDebugMode) {
        debugPrint('[CalendarController] Error loading events: $e');
      }
    }
  }

  /// Fetch user first names for block outs
  Future<Map<String, String>> _fetchUserNames(List<BlockOut> blockOuts) async {
    if (blockOuts.isEmpty) return {};

    // Get unique user IDs
    final userIds = blockOuts.map((bo) => bo.userId).toSet().toList();

    try {
      final response = await supabase
          .from('users')
          .select('id, first_name, last_name')
          .inFilter('id', userIds);

      final userNames = <String, String>{};
      for (final row in response) {
        final id = row['id'] as String;
        final firstName = row['first_name'] as String?;
        final lastName = row['last_name'] as String?;
        // Use first name, fallback to last name, fallback to "Member"
        userNames[id] = firstName?.isNotEmpty == true
            ? firstName!
            : (lastName?.isNotEmpty == true ? lastName! : 'Member');
      }
      return userNames;
    } catch (e) {
      debugPrint('[CalendarController] Failed to fetch user names: $e');
      return {};
    }
  }

  /// Group consecutive block outs by user+reason into spans
  List<BlockOutSpan> _groupBlockOutsIntoSpans(
    List<BlockOut> blockOuts,
    Map<String, String> userNames,
  ) {
    if (blockOuts.isEmpty) return [];

    // Sort by user, then by date
    final sorted = List<BlockOut>.from(blockOuts)
      ..sort((a, b) {
        final userCmp = a.userId.compareTo(b.userId);
        if (userCmp != 0) return userCmp;
        return a.date.compareTo(b.date);
      });

    final spans = <BlockOutSpan>[];
    BlockOut? spanStart;
    BlockOut? spanEnd;

    for (final bo in sorted) {
      if (spanStart == null) {
        // Start a new span
        spanStart = bo;
        spanEnd = bo;
      } else if (bo.userId == spanStart.userId &&
          bo.reason == spanStart.reason &&
          _isNextDay(spanEnd!.date, bo.date)) {
        // Extend the current span
        spanEnd = bo;
      } else {
        // Close the current span and start a new one
        spans.add(
          BlockOutSpan(
            startDate: spanStart.date,
            endDate: spanEnd!.date,
            reason: spanStart.reason,
            userId: spanStart.userId,
            userName: userNames[spanStart.userId] ?? 'Member',
          ),
        );
        spanStart = bo;
        spanEnd = bo;
      }
    }

    // Don't forget the last span
    if (spanStart != null) {
      spans.add(
        BlockOutSpan(
          startDate: spanStart.date,
          endDate: spanEnd!.date,
          reason: spanStart.reason,
          userId: spanStart.userId,
          userName: userNames[spanStart.userId] ?? 'Member',
        ),
      );
    }

    return spans;
  }

  /// Check if date b is the day after date a
  bool _isNextDay(DateTime a, DateTime b) {
    final aDate = DateTime(a.year, a.month, a.day);
    final bDate = DateTime(b.year, b.month, b.day);
    return bDate.difference(aDate).inDays == 1;
  }

  /// Update cache with events grouped by month
  void _updateCache(String bandId, List<CalendarEvent> events) {
    // Group events by year-month
    final byMonth = <String, List<CalendarEvent>>{};
    for (final event in events) {
      final key = _cacheKey(bandId, event.date.year, event.date.month);
      byMonth.putIfAbsent(key, () => []).add(event);
    }

    // Update cache for each month
    for (final entry in byMonth.entries) {
      _cache[entry.key] = MonthData(
        events: entry.value,
        fetchedAt: DateTime.now(),
      );
    }
  }

  /// Get cached events for a specific month (returns null if not cached or stale)
  MonthData? getCachedMonth(int year, int month) {
    final bandId = _bandId;
    if (bandId == null) return null;

    final key = _cacheKey(bandId, year, month);
    final cached = _cache[key];
    if (cached != null && !cached.isStale) {
      return cached;
    }
    return null;
  }

  /// Clear all cached data (useful when band changes or data is modified)
  void clearCache() {
    _cache.clear();
  }

  /// Invalidate cache for a specific band and force reload.
  /// Call this after deleting/modifying events from Dashboard or other screens.
  void invalidateAndRefresh({required String bandId}) {
    // Clear cache entries for this band only
    final keysToRemove = _cache.keys
        .where((key) => key.startsWith('$bandId-'))
        .toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
    }

    debugPrint(
      '[Calendar] invalidateAndRefresh for band $bandId, cleared ${keysToRemove.length} cached months',
    );

    // Force reload events
    loadEvents(forceRefresh: true);
  }

  /// Navigate to the previous month
  void previousMonth() {
    final current = state.selectedMonth;
    state = state.copyWith(
      selectedMonth: DateTime(current.year, current.month - 1, 1),
    );
  }

  /// Navigate to the next month
  void nextMonth() {
    final current = state.selectedMonth;
    state = state.copyWith(
      selectedMonth: DateTime(current.year, current.month + 1, 1),
    );
  }

  /// Go to today's month
  void goToToday() {
    state = state.copyWith(selectedMonth: DateTime.now());
  }

  /// Reset the controller state and clear cache
  void reset() {
    clearCache();
    state = CalendarState(selectedMonth: DateTime.now());
  }
}

/// Provider for calendar state
final calendarProvider = NotifierProvider<CalendarNotifier, CalendarState>(
  CalendarNotifier.new,
);
