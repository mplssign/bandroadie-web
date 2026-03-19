import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Centralized timezone conversion utility.
///
/// Converts stored event times (band timezone) to the viewer's local timezone
/// for display, and to UTC for accurate future/past filtering.
class TimezoneHelper {
  static bool _initialized = false;

  static const _defaultTimezone = 'America/Chicago';

  /// Initialize timezone database. Safe to call multiple times (idempotent).
  static void initialize() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  /// Resolve a timezone string to a [tz.Location], falling back to
  /// America/Chicago if the string is empty or invalid.
  static tz.Location _resolveLocation(String bandTimezone) {
    final tzName =
        bandTimezone.trim().isEmpty ? _defaultTimezone : bandTimezone;
    try {
      return tz.getLocation(tzName);
    } catch (e) {
      debugPrint(
        '[TimezoneHelper] Invalid timezone "$tzName", falling back to $_defaultTimezone',
      );
      return tz.getLocation(_defaultTimezone);
    }
  }

  /// Parse a 24h or 12h time string into hour (0-23) and minute components.
  ///
  /// Handles both "19:30" (24h) and "7:30 PM" (12h) formats.
  /// Database stores times in 12-hour format ("7:00 PM"), so AM/PM handling
  /// is critical.
  static (int hour, int minute) _parseTime(String timeStr) {
    final normalized = timeStr.trim();

    // Try 12-hour format first: "7:30 PM" or "7:30PM"
    final amPmMatch = RegExp(
      r'(\d{1,2}):(\d{2})\s*(AM|PM)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (amPmMatch != null) {
      int hour = int.parse(amPmMatch.group(1)!);
      final minute = int.parse(amPmMatch.group(2)!);
      final isPM = amPmMatch.group(3)!.toUpperCase() == 'PM';
      // Convert to 24-hour
      if (isPM && hour != 12) hour += 12;
      if (!isPM && hour == 12) hour = 0;
      return (hour, minute);
    }

    // Fall back to 24-hour format: "19:30"
    final parts = normalized.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
    return (hour, minute);
  }

  /// Convert a time string on a given date from the band's timezone to the
  /// device's local timezone. Returns a local [DateTime].
  static DateTime toLocal(
    DateTime eventDate,
    String timeStr24,
    String bandTimezone,
  ) {
    final location = _resolveLocation(bandTimezone);
    final (hour, minute) = _parseTime(timeStr24);

    final tzDateTime = tz.TZDateTime(
      location,
      eventDate.year,
      eventDate.month,
      eventDate.day,
      hour,
      minute,
    );

    // Use fromMillisecondsSinceEpoch instead of TZDateTime.toLocal() because
    // TZDateTime overrides DateTime in a way that can return UTC-tagged values.
    return DateTime.fromMillisecondsSinceEpoch(
      tzDateTime.millisecondsSinceEpoch,
    );
  }

  /// Build a timezone-aware UTC [DateTime] for accurate comparisons.
  /// Used by filtering logic (_isEndTimeInFuture).
  static DateTime toUtc(
    DateTime eventDate,
    String timeStr24,
    String bandTimezone,
  ) {
    final location = _resolveLocation(bandTimezone);
    final (hour, minute) = _parseTime(timeStr24);

    final tzDateTime = tz.TZDateTime(
      location,
      eventDate.year,
      eventDate.month,
      eventDate.day,
      hour,
      minute,
    );

    // Use fromMillisecondsSinceEpoch with isUtc:true for a clean UTC DateTime,
    // avoiding potential TZDateTime override quirks.
    return DateTime.fromMillisecondsSinceEpoch(
      tzDateTime.millisecondsSinceEpoch,
      isUtc: true,
    );
  }
}
