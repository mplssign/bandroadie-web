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

class MonthData {
  final List<CalendarEvent> events;
  final DateTime fetchedAt;

  const MonthData({
    required this.events,
    required this.fetchedAt,
  });

  bool get isStale => DateTime.now().difference(fetchedAt).inMinutes > 5;
}

class CalendarState {
  final DateTime selectedMonth;
  final List<CalendarEvent> allEvents;
  final Map<DayKey, CalendarDayMarkers> markers;
  final bool isLoading;
  final String? error;

  const CalendarState({
    required this.selectedMonth,
    this.allEvents = const [],
    this.markers = const {},
    this.isLoading = false,
    this.error,
  });

  List<CalendarEvent> get eventsForMonth {
    final year = selectedMonth.year;
    final month = selectedMonth.month;

    return allEvents.where((event) {
      if (event.date.year == year && event.date.month == month) {
        return true;
      }

      final endDate = event.endDate;
      if (endDate != null) {
        final monthStart = DateTime(year, month, 1);
        final monthEnd = DateTime(year, month + 1, 0);
        return !event.date.isAfter(monthEnd) && !endDate.isBefore(monthStart);
      }

      return false;
    }).toList()
      ..sort(_compareByDateAndTime);
  }

  static int _compareByDateAndTime(CalendarEvent a, CalendarEvent b) {
    final dateComparison = a.date.compareTo(b.date);

    if (dateComparison != 0) {
      return dateComparison;
    }

    if (a.startTime.isEmpty && b.startTime.isEmpty) return 0;
    if (a.startTime.isEmpty) return 1;
    if (b.startTime.isEmpty) return -1;

    final aTime = TimeFormatter.parse(a.startTime);
    final bTime = TimeFormatter.parse(b.startTime);

    return aTime.totalMinutes.compareTo(bTime.totalMinutes);
  }

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

  List<CalendarEvent> eventsForDate(DateTime date) {
    final dateKey = DateTime(date.year, date.month, date.day);
    final exact = eventsByDate[dateKey] ?? [];

    final spanning = allEvents.where((event) {
      final endDate = event.endDate;
      if (endDate == null) return false;

      if (event.date.year == dateKey.year &&
          event.date.month == dateKey.month &&
          event.date.day == dateKey.day) {
        return false;
      }

      return !event.date.isAfter(dateKey) && !endDate.isBefore(dateKey);
    });

    final result = spanning.isEmpty ? List.of(exact) : [...exact, ...spanning];
    result.sort(_compareByDateAndTime);

    return result;
  }

  bool hasEvents(DateTime date) {
    return eventsForDate(date).isNotEmpty;
  }

  bool hasGig(DateTime date) {
    final key = dayKey(date);

    if (markers.containsKey(key)) {
      return markers[key]!.gig;
    }

    return eventsForDate(date).any((e) => e.isGig);
  }

  bool hasRehearsal(DateTime date) {
    final key = dayKey(date);

    if (markers.containsKey(key)) {
      return markers[key]!.rehearsal;
    }

    return eventsForDate(date).any((e) => e.isRehearsal);
  }

  bool hasBlockOut(DateTime date) {
    final key = dayKey(date);
    return markers[key]?.blockOut ?? false;
  }

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

class CalendarNotifier extends Notifier<CalendarState> {
  static final Map<String, MonthData> _cache = {};
  String? _lastLoadedBandId;

  @override
  CalendarState build() {
    final bandId = ref.watch(activeBandIdProvider);

    if (bandId == null || bandId.isEmpty) {
      _lastLoadedBandId = null;

      return CalendarState(
        selectedMonth: DateTime.now(),
        error: 'No band selected',
      );
    }

    if (bandId != _lastLoadedBandId) {
      _lastLoadedBandId = bandId;
      Future.microtask(loadEvents);
    }

    return CalendarState(
      selectedMonth: DateTime.now(),
      isLoading: true,
    );
  }

  GigRepository get _gigRepository => GigRepository();
  RehearsalRepository get _rehearsalRepository => RehearsalRepository();
  BlockOutRepository get _blockOutRepository => BlockOutRepository();

  String? get _bandId => ref.read(activeBandIdProvider);

  String _cacheKey(String bandId, int year, int month) =>
      '$bandId-$year-$month';

  Future<void> loadEvents({bool forceRefresh = false}) async {
    final bandId = _bandId;

    if (bandId == null || bandId.isEmpty) {
      debugPrint('[CalendarController] loadEvents skipped - no bandId');
      return;
    }

    state = state.copyWith(
      isLoading: true,
      clearError: true,
    );

    try {
      final results = await Future.wait([
        _gigRepository.fetchGigsForBand(bandId),
        _rehearsalRepository.fetchRehearsalsForBand(bandId),
        _blockOutRepository.fetchBlockOutsForBand(bandId),
      ]);

      final gigs = results[0] as List<Gig>;
      final rehearsals = results[1] as List<Rehearsal>;
      final blockOuts = results[2] as List<BlockOut>;

      final userNames = await _fetchUserNames(blockOuts);

      final blockOutSpans = _groupBlockOutsIntoSpans(
        blockOuts,
        userNames,
      );

      final events = <CalendarEvent>[
        ...gigs.map(CalendarEvent.fromGig),
        ...rehearsals.map(CalendarEvent.fromRehearsal),
        ...blockOutSpans.map(CalendarEvent.fromBlockOutSpan),
      ];

      events.sort((a, b) => a.date.compareTo(b.date));

      final blockOutRanges = blockOuts
          .map(
            (bo) => BlockOutRange(
              startDate: bo.date,
              untilDate: null,
            ),
          )
          .toList();

      final markers = buildCalendarMarkers(
        gigs: gigs,
        rehearsals: rehearsals,
        blockOuts: blockOutRanges,
      );

      _updateCache(bandId, events);

      state = state.copyWith(
        allEvents: events,
        markers: markers,
        isLoading: false,
      );

      if (kDebugMode) {
        debugPrint(
          '[CalendarController] ${events.length} events loaded',
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

  Future<Map<String, String>> _fetchUserNames(List<BlockOut> blockOuts) async {
    if (blockOuts.isEmpty) return {};

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

  List<BlockOutSpan> _groupBlockOutsIntoSpans(
    List<BlockOut> blockOuts,
    Map<String, String> userNames,
  ) {
    if (blockOuts.isEmpty) return [];

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
        spanStart = bo;
        spanEnd = bo;
      } else if (spanEnd != null &&
          bo.userId == spanStart.userId &&
          bo.reason == spanStart.reason &&
          _isNextDay(spanEnd.date, bo.date)) {
        spanEnd = bo;
      } else {
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

  bool _isNextDay(DateTime a, DateTime b) {
    final aDate = DateTime(a.year, a.month, a.day);
    final bDate = DateTime(b.year, b.month, b.day);
    return bDate.difference(aDate).inDays == 1;
  }

  void _updateCache(String bandId, List<CalendarEvent> events) {
    final byMonth = <String, List<CalendarEvent>>{};

    for (final event in events) {
      final key = _cacheKey(bandId, event.date.year, event.date.month);
      byMonth.putIfAbsent(key, () => []).add(event);
    }

    for (final entry in byMonth.entries) {
      _cache[entry.key] = MonthData(
        events: entry.value,
        fetchedAt: DateTime.now(),
      );
    }
  }

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

  void clearCache() {
    _cache.clear();
  }

  Future<void> invalidateAndRefresh({required String bandId}) async {
    final keysToRemove =
        _cache.keys.where((key) => key.startsWith('$bandId-')).toList();

    for (final key in keysToRemove) {
      _cache.remove(key);
    }

    await loadEvents(forceRefresh: true);
  }

  void previousMonth() {
    final current = state.selectedMonth;

    state = state.copyWith(
      selectedMonth: DateTime(current.year, current.month - 1, 1),
    );
  }

  void nextMonth() {
    final current = state.selectedMonth;

    state = state.copyWith(
      selectedMonth: DateTime(current.year, current.month + 1, 1),
    );
  }

  void goToToday() {
    state = state.copyWith(
      selectedMonth: DateTime.now(),
    );
  }

  void reset() {
    clearCache();
    state = CalendarState(
      selectedMonth: DateTime.now(),
    );
  }
}

final calendarProvider = NotifierProvider<CalendarNotifier, CalendarState>(
  CalendarNotifier.new,
);
