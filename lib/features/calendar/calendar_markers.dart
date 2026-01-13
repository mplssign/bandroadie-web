// ============================================================================
// CALENDAR MARKERS
// Single source of truth for computing calendar day markers.
//
// Computes which days have gigs, rehearsals, and block outs for
// efficient rendering in the calendar grid.
// ============================================================================

import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';

/// Color constants for calendar markers (matching Figma design)
class MarkerColors {
  MarkerColors._();

  /// Green indicator for gigs (#65A30D)
  static const int gigColor = 0xFF65A30D;

  /// Blue indicator for rehearsals (#2563EB)
  static const int rehearsalColor = 0xFF2563EB;

  /// Rose indicator for block outs (#F43F5E)
  static const int blockOutColor = 0xFFF43F5E;
}

/// Markers for a single calendar day
class CalendarDayMarkers {
  bool gig;
  bool rehearsal;
  bool blockOut;

  /// Number of band members with block outs on this day
  int blockOutCount;

  CalendarDayMarkers({
    this.gig = false,
    this.rehearsal = false,
    this.blockOut = false,
    this.blockOutCount = 0,
  });

  /// Returns true if any marker is set
  bool get hasAny => gig || rehearsal || blockOut;

  /// Returns the count of active markers
  int get count => (gig ? 1 : 0) + (rehearsal ? 1 : 0) + (blockOut ? 1 : 0);

  @override
  String toString() =>
      'CalendarDayMarkers(gig: $gig, rehearsal: $rehearsal, blockOut: $blockOut, blockOutCount: $blockOutCount)';
}

/// Type alias for day key in format yyyy-mm-dd
typedef DayKey = String;

/// Generate a normalized day key from a DateTime (local date only)
DayKey dayKey(DateTime dt) {
  final year = dt.year.toString();
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Parse a day key back to DateTime (noon local time)
DateTime parseDayKey(DayKey key) {
  final parts = key.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
    12, // noon to avoid timezone edge cases
  );
}

/// Simple block out representation for marker computation.
/// This can be replaced with a proper BlockOut model when available.
class BlockOutRange {
  final DateTime startDate;
  final DateTime? untilDate;

  const BlockOutRange({required this.startDate, this.untilDate});

  /// Expand this range into individual day keys
  List<DayKey> expandToDayKeys() {
    final keys = <DayKey>[];

    if (untilDate == null) {
      // Single day block out
      keys.add(dayKey(startDate));
    } else {
      // Multi-day block out: iterate from start to until (inclusive)
      var current = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(untilDate!.year, untilDate!.month, untilDate!.day);

      while (!current.isAfter(end)) {
        keys.add(dayKey(current));
        current = current.add(const Duration(days: 1));
      }
    }

    return keys;
  }
}

/// Build a map of day keys to calendar markers.
///
/// This is the single source of truth for determining which markers
/// should display on each calendar day.
Map<DayKey, CalendarDayMarkers> buildCalendarMarkers({
  required List<Gig> gigs,
  required List<Rehearsal> rehearsals,
  List<BlockOutRange> blockOuts = const [],
}) {
  final markers = <DayKey, CalendarDayMarkers>{};

  // Helper to get or create markers for a day
  CalendarDayMarkers markersFor(DayKey key) {
    return markers.putIfAbsent(key, () => CalendarDayMarkers());
  }

  // Add gig markers
  for (final gig in gigs) {
    final key = dayKey(gig.date);
    markersFor(key).gig = true;
  }

  // Add rehearsal markers
  for (final rehearsal in rehearsals) {
    final key = dayKey(rehearsal.date);
    markersFor(key).rehearsal = true;
  }

  // Add block out markers (expanding ranges) and count per day
  for (final blockOut in blockOuts) {
    final keys = blockOut.expandToDayKeys();
    for (final key in keys) {
      final marker = markersFor(key);
      marker.blockOut = true;
      marker.blockOutCount += 1;
    }
  }

  return markers;
}

/// Get markers for a specific date from a pre-computed markers map.
/// Returns empty markers if the date is not in the map.
CalendarDayMarkers getMarkersForDate(
  Map<DayKey, CalendarDayMarkers> markers,
  DateTime date,
) {
  final key = dayKey(date);
  return markers[key] ?? CalendarDayMarkers();
}

/// Check if markers map has any markers for a specific date.
bool hasMarkersForDate(Map<DayKey, CalendarDayMarkers> markers, DateTime date) {
  final key = dayKey(date);
  return markers[key]?.hasAny ?? false;
}
