// ============================================================================
// TIME FORMATTER
// Centralized time parsing and formatting utilities.
// Used by: Dashboard cards, Calendar event cards, Edit drawer.
//
// IMPORTANT: All time strings in the database are stored in 12-hour format
// (e.g., "7:30 PM"). This utility normalizes parsing and formatting.
// ============================================================================

import 'package:flutter/foundation.dart';

/// Parsed time components in 12-hour format.
class ParsedTime {
  final int hour; // 1-12
  final int minutes; // 0-59
  final bool isPM;

  const ParsedTime({
    required this.hour,
    required this.minutes,
    required this.isPM,
  });

  /// Convert to 24-hour format (0-23)
  int get hour24 {
    if (isPM && hour != 12) return hour + 12;
    if (!isPM && hour == 12) return 0;
    return hour;
  }

  /// Total minutes from midnight
  int get totalMinutes => hour24 * 60 + minutes;

  /// Format as 12-hour display string (e.g., "7:30 PM")
  String format() {
    final minStr = minutes.toString().padLeft(2, '0');
    final amPm = isPM ? 'PM' : 'AM';
    return '$hour:$minStr $amPm';
  }

  @override
  String toString() => format();
}

/// Time formatting utilities for consistent display across the app.
class TimeFormatter {
  TimeFormatter._();

  /// Parse a time string into components.
  ///
  /// Supports:
  /// - 12-hour format: "7:30 PM", "12:00 AM"
  /// - 24-hour format: "19:30", "00:00"
  ///
  /// Returns default (7:00 PM) if parsing fails.
  static ParsedTime parse(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) {
      return const ParsedTime(hour: 7, minutes: 0, isPM: true);
    }

    final normalized = timeStr.trim();

    // Try 12-hour format first: "7:30 PM" or "7:30PM"
    final amPmMatch = RegExp(
      r'(\d{1,2}):(\d{2})\s*(AM|PM)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (amPmMatch != null) {
      int hour = int.parse(amPmMatch.group(1)!);
      final minutes = int.parse(amPmMatch.group(2)!);
      final isPM = amPmMatch.group(3)!.toUpperCase() == 'PM';

      if (kDebugMode) {
        debugPrint(
          '[TimeFormatter] Parsed 12h "$timeStr" -> $hour:$minutes ${isPM ? "PM" : "AM"}',
        );
      }

      return ParsedTime(hour: hour, minutes: minutes, isPM: isPM);
    }

    // Try 24-hour format: "19:30"
    final h24Match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(normalized);
    if (h24Match != null) {
      int hour24 = int.parse(h24Match.group(1)!);
      final minutes = int.parse(h24Match.group(2)!);
      final isPM = hour24 >= 12;
      int hour12 = hour24 % 12;
      if (hour12 == 0) hour12 = 12;

      if (kDebugMode) {
        debugPrint(
          '[TimeFormatter] Parsed 24h "$timeStr" -> $hour12:$minutes ${isPM ? "PM" : "AM"}',
        );
      }

      return ParsedTime(hour: hour12, minutes: minutes, isPM: isPM);
    }

    // Fallback
    if (kDebugMode) {
      debugPrint(
        '[TimeFormatter] Failed to parse "$timeStr", using default 7:00 PM',
      );
    }
    return const ParsedTime(hour: 7, minutes: 0, isPM: true);
  }

  /// Format a time range from two time strings.
  ///
  /// Example: formatRange("7:30 PM", "10:00 PM") -> "7:30 PM - 10:00 PM"
  static String formatRange(String? startTime, String? endTime) {
    final start = parse(startTime);
    final end = parse(endTime);
    return '${start.format()} - ${end.format()}';
  }

  /// Calculate duration in minutes between two time strings.
  ///
  /// Handles overnight events (end before start).
  static int durationMinutes(String? startTime, String? endTime) {
    final start = parse(startTime);
    final end = parse(endTime);

    int endTotalMinutes = end.totalMinutes;
    // Handle overnight events
    if (endTotalMinutes < start.totalMinutes) {
      endTotalMinutes += 24 * 60;
    }

    return endTotalMinutes - start.totalMinutes;
  }
}
