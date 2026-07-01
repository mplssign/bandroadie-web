import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/features/calendar/auto_conflict_blocking_service.dart';
import 'models/event_form_data.dart';

// ============================================================================
// EVENTS REPOSITORY
// Unified repository for creating/updating rehearsals and gigs.
// Implements lightweight caching with 5-minute TTL, keyed by bandId + month.
//
// BAND ISOLATION: Every operation REQUIRES a non-null bandId.
// ============================================================================

/// Exception thrown when attempting operations without a band context.
class NoBandSelectedError extends Error {
  final String message;
  NoBandSelectedError([
    this.message = 'No band selected. Cannot perform this operation.',
  ]);

  @override
  String toString() => 'NoBandSelectedError: $message';
}

/// Cache entry with timestamp
class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;

  _CacheEntry(this.data) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp).inMinutes >= 5; // 5-minute TTL
}

class EventsRepository {
  final AutoConflictBlockingService _autoConflictBlockingService;

  EventsRepository(this._autoConflictBlockingService);

  // Cache: key = "$bandId:$yearMonth" for events lists
  final Map<String, _CacheEntry<List<Rehearsal>>> _rehearsalCache = {};
  final Map<String, _CacheEntry<List<Gig>>> _gigCache = {};

  // ============================================================================
  // CACHE MANAGEMENT
  // ============================================================================

  /// Get cache key for a band and month
  String _cacheKey(String bandId, DateTime date) {
    final yearMonth = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    return '$bandId:$yearMonth';
  }

  /// Invalidate all cache entries for a band (call after create/update)
  void invalidateCache(String bandId) {
    debugPrint('[EventsRepository] Invalidating cache for band: $bandId');
    _rehearsalCache.removeWhere((key, _) => key.startsWith(bandId));
    _gigCache.removeWhere((key, _) => key.startsWith(bandId));
  }

  /// Clear all cache (e.g., on logout)
  void clearAllCache() {
    _rehearsalCache.clear();
    _gigCache.clear();
  }

  // ============================================================================
  // REHEARSAL OPERATIONS
  // ============================================================================

  /// Create a new rehearsal (or multiple for recurring)
  /// Returns the first created rehearsal
  Future<Rehearsal> createRehearsal({
    required String bandId,
    required EventFormData formData,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    debugPrint('[EventsRepository] Creating rehearsal for band: $bandId');

    // Generate all dates for recurring events
    final dates = _generateRecurringDates(formData);
    debugPrint(
      '[EventsRepository] Creating ${dates.length} rehearsal(s) '
      '(recurring: ${formData.isRecurring})',
    );

    Rehearsal? firstRehearsal;
    String? parentId;

    try {
      for (var i = 0; i < dates.length; i++) {
        final date = dates[i];
        final isFirst = i == 0;

        final data = {
          'band_id': bandId,
          'date': date.toIso8601String().split('T')[0],
          'start_time': formData.startTimeDisplay,
          'end_time': formData.endTimeDisplay,
          'location': formData.location,
          'notes': formData.notes,
          'setlist_id': formData.setlistId,
          'is_potential': formData.isPotentialGig,
          // Recurrence fields - store on all instances for consistency
          'is_recurring': formData.isRecurring,
          'recurrence_frequency':
              formData.isRecurring ? formData.recurrence?.frequency.name : null,
          'recurrence_days': formData.isRecurring
              ? formData.recurrence?.daysOfWeek.map((d) => d.dayIndex).toList()
              : null,
          'recurrence_until': formData.isRecurring
              ? formData.recurrence?.untilDate?.toIso8601String().split('T')[0]
              : null,
          // Link child instances to parent (first rehearsal)
          'parent_rehearsal_id': isFirst ? null : parentId,
        };

        debugPrint('[EventsRepository] Inserting rehearsal with data: $data');

        final response =
            await supabase.from('rehearsals').insert(data).select().single();

        debugPrint('[EventsRepository] Successfully created rehearsal');

        if (isFirst) {
          firstRehearsal = Rehearsal.fromJson(response);
          parentId = firstRehearsal.id;

          // Create additional dates for multi-date potential rehearsals
          // (only on the first/primary rehearsal instance)
          if (formData.isPotentialGig && formData.additionalDates.isNotEmpty) {
            await _createRehearsalDates(
                firstRehearsal.id, formData.additionalDates);
          }
        }
      }

      invalidateCache(bandId);

      // Trigger automatic conflict blocking (if enabled)
      if (firstRehearsal != null) {
        try {
          final userId = supabase.auth.currentUser?.id;
          if (userId != null) {
            // Fetch band name for auto-conflict blocking reason
            final bandResponse = await supabase
                .from('bands')
                .select('name')
                .eq('id', bandId)
                .single();
            final bandName = bandResponse['name'] as String;

            await _autoConflictBlockingService.autoBlockConflictingDate(
              userId: userId,
              eventBandId: bandId,
              eventDate: firstRehearsal.date,
              eventStartTime: null,
              eventEndTime: null,
              eventName: 'Rehearsal',
              bandName: bandName,
            );
          }
        } catch (e) {
          // Do not fail rehearsal creation if auto-blocking fails
          debugPrint(
            '[EventsRepository] Auto-conflict blocking failed: $e',
          );
        }
      }

      return firstRehearsal!;
    } catch (e, st) {
      debugPrint('[EventsRepository] ERROR creating rehearsal:');
      debugPrint('  Error: $e');
      debugPrint('  Type: ${e.runtimeType}');
      debugPrint('  Stack: $st');
      rethrow;
    }
  }

  /// Generate all dates for a recurring event based on recurrence config
  List<DateTime> _generateRecurringDates(EventFormData formData) {
    if (!formData.isRecurring || formData.recurrence == null) {
      return [formData.date];
    }

    final rawRecurrence = formData.recurrence!;

    // Safety net: if daysOfWeek is empty, default to the weekday of formData.date.
    // Prevents zero-instance generation when the UI deselects all day chips.
    final recurrence = rawRecurrence.daysOfWeek.isEmpty
        ? RecurrenceConfig(
            daysOfWeek: {Weekday.values[formData.date.weekday % 7]},
            frequency: rawRecurrence.frequency,
            untilDate: rawRecurrence.untilDate,
          )
        : rawRecurrence;

    final dates = <DateTime>[];

    // Default end date: 1 year from start if not specified (indefinite recurrence)
    final untilDate =
        recurrence.untilDate ?? formData.date.add(const Duration(days: 365));

    // --- Monthly: true calendar-month intervals (Nth weekday of month) ---
    if (recurrence.frequency == RecurrenceFrequency.monthly) {
      final n = _weekdayOccurrenceInMonth(formData.date);

      var year = formData.date.year;
      var month = formData.date.month;
      const maxMonths = 24;
      var monthCount = 0;

      while (monthCount < maxMonths) {
        final monthStart = DateTime(year, month, 1);
        if (monthStart.isAfter(untilDate)) break;

        for (final day in recurrence.daysOfWeek) {
          final candidate = _nthWeekdayOfMonth(year, month, day.dayIndex, n);
          if (candidate != null &&
              !candidate.isBefore(formData.date) &&
              !candidate.isAfter(untilDate)) {
            dates.add(candidate);
          }
        }

        // Advance to next month
        month++;
        if (month > 12) {
          month = 1;
          year++;
        }
        monthCount++;
      }

      dates.sort();
      return dates.isEmpty ? [formData.date] : dates;
    }

    // --- Weekly / Biweekly: unchanged ---
    // Calculate interval based on frequency
    final weekInterval = switch (recurrence.frequency) {
      RecurrenceFrequency.weekly => 1,
      RecurrenceFrequency.biweekly => 2,
      RecurrenceFrequency.monthly => 4, // unreachable; handled above
    };

    // Start from the event date
    var currentWeekStart = _startOfWeek(formData.date);

    // Safety limit to prevent infinite loops
    const maxIterations = 52; // Max 1 year of weekly events
    var iterations = 0;

    while (currentWeekStart.isBefore(untilDate) && iterations < maxIterations) {
      // Check each selected day of the week
      for (final day in recurrence.daysOfWeek) {
        final dateForDay = DateTime(
          currentWeekStart.year,
          currentWeekStart.month,
          currentWeekStart.day + day.dayIndex,
          12,
        );

        // Only include dates from the start date onwards and before until date
        if (!dateForDay.isBefore(formData.date) &&
            !dateForDay.isAfter(untilDate)) {
          dates.add(dateForDay);
        }
      }

      // Move to next interval
      currentWeekStart = DateTime(
        currentWeekStart.year,
        currentWeekStart.month,
        currentWeekStart.day + (7 * weekInterval),
        12,
      );
      iterations++;
    }

    // Sort dates and return
    dates.sort();
    return dates.isEmpty ? [formData.date] : dates;
  }

  /// Returns the 1-based occurrence of [date]'s weekday within its month.
  /// Example: April 20, 2026 (3rd Monday) → 3
  int _weekdayOccurrenceInMonth(DateTime date) {
    return ((date.day - 1) ~/ 7) + 1;
  }

  /// Returns the [occurrence]-th (1-based) instance of the weekday identified
  /// by [weekdayDayIndex] (0=Sun..6=Sat) in the given [year]/[month].
  /// Returns null if that occurrence does not exist in the month
  /// (e.g., a 5th Monday in a month that only has 4).
  ///
  /// Example: _nthWeekdayOfMonth(2026, 5, 1, 3) → May 18, 2026 (3rd Monday)
  DateTime? _nthWeekdayOfMonth(
    int year,
    int month,
    int weekdayDayIndex,
    int occurrence,
  ) {
    // Convert Weekday dayIndex (0=Sun..6=Sat) to Dart weekday (1=Mon..7=Sun)
    final targetDartWeekday = weekdayDayIndex == 0 ? 7 : weekdayDayIndex;

    // Find the first occurrence of this weekday in the month
    final firstDayOfMonth = DateTime(year, month, 1, 12);
    final daysUntilTarget =
        (targetDartWeekday - firstDayOfMonth.weekday + 7) % 7;
    final dayOfMonth = 1 + daysUntilTarget + (7 * (occurrence - 1));

    // Calculate the nth occurrence using calendar-day construction to avoid DST drift.
    final result = DateTime(year, month, dayOfMonth, 12);

    // Return null if the result falls outside the target month
    if (result.month != month || result.year != year) return null;

    return result;
  }

  /// Get start of week (Sunday) for a given date
  DateTime _startOfWeek(DateTime date) {
    final daysSinceSunday = date.weekday % 7;
    return DateTime(date.year, date.month, date.day - daysSinceSunday);
  }

  /// Update an existing rehearsal.
  ///
  /// If [wasRecurring] is provided and the rehearsal is transitioning from
  /// non-recurring to recurring, future events will be generated automatically.
  /// If transitioning from recurring to non-recurring, all child rehearsals
  /// in the series will be deleted.
  Future<Rehearsal> updateRehearsal({
    required String rehearsalId,
    required String bandId,
    required EventFormData formData,
    bool? wasRecurring,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    debugPrint(
      '[EventsRepository] Updating rehearsal $rehearsalId for band: $bandId',
    );

    // Check if we're transitioning from non-recurring to recurring
    final isBecomingRecurring = wasRecurring == false && formData.isRecurring;
    // Check if we're transitioning from recurring to non-recurring
    final isStoppingRecurring = wasRecurring == true && !formData.isRecurring;

    if (isBecomingRecurring) {
      // Generate future events for the new recurring series
      debugPrint(
        '[EventsRepository] Rehearsal is becoming recurring - generating future events',
      );
      return _updateAndGenerateRecurringSeries(
        rehearsalId: rehearsalId,
        bandId: bandId,
        formData: formData,
      );
    }

    if (isStoppingRecurring) {
      // Delete all child rehearsals in the series
      debugPrint(
        '[EventsRepository] Rehearsal is stopping recurrence - deleting child rehearsals',
      );
      await _deleteChildRehearsals(rehearsalId: rehearsalId, bandId: bandId);
    }

    // Standard update (no recurrence generation needed)
    final data = {
      'date': formData.date.toIso8601String().split('T')[0],
      'start_time': formData.startTimeDisplay,
      'end_time': formData.endTimeDisplay,
      'location': formData.location,
      'notes': formData.notes,
      'setlist_id': formData.setlistId,
      'is_potential': formData.isPotentialGig,
      // Update recurrence fields
      'is_recurring': formData.isRecurring,
      'recurrence_frequency':
          formData.isRecurring ? formData.recurrence?.frequency.name : null,
      'recurrence_days': formData.isRecurring
          ? formData.recurrence?.daysOfWeek.map((d) => d.dayIndex).toList()
          : null,
      'recurrence_until': formData.isRecurring
          ? formData.recurrence?.untilDate?.toIso8601String().split('T')[0]
          : null,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final response = await supabase
        .from('rehearsals')
        .update(data)
        .eq('id', rehearsalId)
        .eq('band_id', bandId)
        .select()
        .single();

    // Sync additional dates for multi-date potential rehearsals
    await _syncRehearsalDates(rehearsalId, formData);

    invalidateCache(bandId);
    return Rehearsal.fromJson(response);
  }

  /// Delete all child rehearsals that belong to a recurring series.
  Future<void> _deleteChildRehearsals({
    required String rehearsalId,
    required String bandId,
  }) async {
    await supabase
        .from('rehearsals')
        .delete()
        .eq('parent_rehearsal_id', rehearsalId)
        .eq('band_id', bandId);

    debugPrint(
      '[EventsRepository] Deleted child rehearsals for parent $rehearsalId',
    );
  }

  /// Update a rehearsal and generate future recurring events.
  /// The original rehearsal becomes the parent of the series.
  Future<Rehearsal> _updateAndGenerateRecurringSeries({
    required String rehearsalId,
    required String bandId,
    required EventFormData formData,
  }) async {
    // Generate all dates for the recurring series
    final dates = _generateRecurringDates(formData);
    debugPrint(
      '[EventsRepository] Generating ${dates.length} rehearsal(s) for recurring series',
    );

    // Update the original rehearsal (becomes the parent)
    final parentData = {
      'date': formData.date.toIso8601String().split('T')[0],
      'start_time': formData.startTimeDisplay,
      'end_time': formData.endTimeDisplay,
      'location': formData.location,
      'notes': formData.notes,
      'setlist_id': formData.setlistId,
      'is_potential': formData.isPotentialGig,
      'is_recurring': true,
      'recurrence_frequency': formData.recurrence?.frequency.name,
      'recurrence_days':
          formData.recurrence?.daysOfWeek.map((d) => d.dayIndex).toList(),
      'recurrence_until':
          formData.recurrence?.untilDate?.toIso8601String().split('T')[0],
      'parent_rehearsal_id': null, // Parent has no parent
      'updated_at': DateTime.now().toIso8601String(),
    };

    final response = await supabase
        .from('rehearsals')
        .update(parentData)
        .eq('id', rehearsalId)
        .eq('band_id', bandId)
        .select()
        .single();

    final parentRehearsal = Rehearsal.fromJson(response);

    // Create child rehearsals for remaining dates (skip the first date which is the parent)
    for (var i = 1; i < dates.length; i++) {
      final date = dates[i];

      // Skip if this date is the same as the parent's date
      if (_isSameDay(date, formData.date)) {
        continue;
      }

      final childData = {
        'band_id': bandId,
        'date': date.toIso8601String().split('T')[0],
        'start_time': formData.startTimeDisplay,
        'end_time': formData.endTimeDisplay,
        'location': formData.location,
        'notes': formData.notes,
        'setlist_id': formData.setlistId,
        'is_potential': formData.isPotentialGig,
        'is_recurring': true,
        'recurrence_frequency': formData.recurrence?.frequency.name,
        'recurrence_days':
            formData.recurrence?.daysOfWeek.map((d) => d.dayIndex).toList(),
        'recurrence_until':
            formData.recurrence?.untilDate?.toIso8601String().split('T')[0],
        'parent_rehearsal_id': rehearsalId, // Link to parent
      };

      await supabase.from('rehearsals').insert(childData);
    }

    debugPrint(
      '[EventsRepository] Created ${dates.length - 1} additional rehearsal(s) in series',
    );

    invalidateCache(bandId);
    return parentRehearsal;
  }

  /// Check if two dates are the same day
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Fetch rehearsals for a month (with caching)
  Future<List<Rehearsal>> fetchRehearsalsForMonth({
    required String bandId,
    required DateTime month,
    bool forceRefresh = false,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    final key = _cacheKey(bandId, month);

    // Check cache
    if (!forceRefresh) {
      final cached = _rehearsalCache[key];
      if (cached != null && !cached.isExpired) {
        debugPrint('[EventsRepository] Cache hit for rehearsals: $key');
        return cached.data;
      }
    }

    debugPrint('[EventsRepository] Fetching rehearsals for month: $key');

    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0);

    final response = await supabase
        .from('rehearsals')
        .select(
            '*, rehearsal_dates(id, rehearsal_id, date, start_time, created_at, updated_at)')
        .eq('band_id', bandId)
        .gte('date', startOfMonth.toIso8601String().split('T')[0])
        .lte('date', endOfMonth.toIso8601String().split('T')[0])
        .order('date', ascending: true);

    final rehearsals =
        response.map<Rehearsal>((json) => Rehearsal.fromJson(json)).toList();

    // Update cache
    _rehearsalCache[key] = _CacheEntry(rehearsals);

    return rehearsals;
  }

  // ============================================================================
  // GIG OPERATIONS
  // ============================================================================

  /// Create a new gig
  Future<Gig> createGig({
    required String bandId,
    required EventFormData formData,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    // Recurrence not yet supported
    if (formData.isRecurring) {
      throw Exception('Recurring events are not yet supported.');
    }

    final name = formData.name ?? formData.displayName;
    if (name.isEmpty) {
      throw Exception('Gig name is required.');
    }

    debugPrint('[EventsRepository] Creating gig for band: $bandId');

    final data = {
      'band_id': bandId,
      'name': name,
      'date': formData.date.toIso8601String().split('T')[0],
      'start_time': formData.startTimeDisplay,
      'end_time': formData.endTimeDisplay,
      'load_in_time': formData.loadInTimeDisplay,
      'location': formData.location,
      'address': formData.address,
      'notes': formData.notes,
      'is_potential': formData.isPotentialGig,
      'setlist_id': formData.setlistId,
      'setlist_name': formData.setlistName,
      'required_member_ids': formData.selectedMemberIds.toList(),
      'gig_pay':
          formData.gigPayCents != null ? formData.gigPayCents! / 100.0 : null,
      if (formData.venueId != null) 'venue_id': formData.venueId,
    };

    debugPrint('[EventsRepository] Inserting gig with data: $data');

    final Map<String, dynamic> response;
    try {
      response = await supabase.from('gigs').insert(data).select().single();
    } catch (e, st) {
      debugPrint('[EventsRepository] ERROR creating gig:');
      debugPrint('  Error: $e');
      debugPrint('  Type: ${e.runtimeType}');
      debugPrint('  Stack: $st');
      rethrow;
    }
    final gigId = response['id'] as String;

    // Create additional dates for multi-date potential gigs
    if (formData.isPotentialGig && formData.additionalDates.isNotEmpty) {
      debugPrint(
        '[EventsRepository] Creating ${formData.additionalDates.length} additional dates',
      );
      await _createGigDates(gigId, formData.additionalDates);
    }

    invalidateCache(bandId);

    // Trigger automatic conflict blocking (if enabled)
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        // Fetch band name for auto-conflict blocking reason
        final bandResponse = await supabase
            .from('bands')
            .select('name')
            .eq('id', bandId)
            .single();
        final bandName = bandResponse['name'] as String;

        await _autoConflictBlockingService.autoBlockConflictingDate(
          userId: userId,
          eventBandId: bandId,
          eventDate: formData.date,
          eventStartTime: null,
          eventEndTime: null,
          eventName: formData.name ?? formData.displayName,
          bandName: bandName,
        );
      }
    } catch (e) {
      // Do not fail gig creation if auto-blocking fails
      debugPrint('[EventsRepository] Auto-conflict blocking failed: $e');
    }

    // Fetch the gig with its dates to return complete data
    final gigWithDates = await supabase
        .from('gigs')
        .select(
            '*, gig_dates(id, gig_id, date, start_time, created_at, updated_at)')
        .eq('id', gigId)
        .single();

    return Gig.fromJson(gigWithDates);
  }

  /// Update an existing gig
  Future<Gig> updateGig({
    required String gigId,
    required String bandId,
    required EventFormData formData,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    final name = formData.name ?? formData.displayName;
    if (name.isEmpty) {
      throw Exception('Gig name is required.');
    }

    debugPrint('[EventsRepository] Updating gig $gigId for band: $bandId');

    final data = {
      'name': name,
      'date': formData.date.toIso8601String().split('T')[0],
      'start_time': formData.startTimeDisplay,
      'end_time': formData.endTimeDisplay,
      'load_in_time': formData.loadInTimeDisplay,
      'location': formData.location,
      'address': formData.address,
      'notes': formData.notes,
      'is_potential': formData.isPotentialGig,
      'setlist_id': formData.setlistId,
      'setlist_name': formData.setlistName,
      'required_member_ids': formData.selectedMemberIds.toList(),
      'gig_pay':
          formData.gigPayCents != null ? formData.gigPayCents! / 100.0 : null,
      if (formData.venueId != null) 'venue_id': formData.venueId,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await supabase
        .from('gigs')
        .update(data)
        .eq('id', gigId)
        .eq('band_id', bandId);

    // Sync additional dates for multi-date potential gigs
    await _syncGigDates(gigId, formData);

    invalidateCache(bandId);

    // Fetch the gig with its dates to return complete data
    final gigWithDates = await supabase
        .from('gigs')
        .select(
            '*, gig_dates(id, gig_id, date, start_time, created_at, updated_at)')
        .eq('id', gigId)
        .single();

    return Gig.fromJson(gigWithDates);
  }

  /// Create additional dates for a gig (with per-date start times)
  Future<void> _createGigDates(
      String gigId, List<AdditionalDateEntry> entries) async {
    if (entries.isEmpty) return;

    final rows = entries
        .map((e) => {
              'gig_id': gigId,
              'date': e.date.toIso8601String().split('T')[0],
              'start_time': e.startTimeDisplay,
            })
        .toList();

    await supabase.from('gig_dates').insert(rows);
  }

  /// Sync gig dates — add new ones, remove deleted ones, update start_time on
  /// existing rows whose time changed.
  Future<void> _syncGigDates(String gigId, EventFormData formData) async {
    // If not a potential gig, remove all additional dates
    if (!formData.isPotentialGig) {
      await supabase.from('gig_dates').delete().eq('gig_id', gigId);
      return;
    }

    final newEntries = {for (final e in formData.additionalDates) e.date: e};
    final existingDateIds = formData.existingGigDateIds;

    // Dates to add: in newEntries but have no existing ID
    final entriesToAdd = <AdditionalDateEntry>[];
    for (final entry in newEntries.entries) {
      if (!existingDateIds.containsKey(entry.key)) {
        entriesToAdd.add(entry.value);
      }
    }

    // IDs to remove: in existingDateIds but not in newEntries
    final idsToRemove = <String>[];
    for (final entry in existingDateIds.entries) {
      if (!newEntries.containsKey(entry.key)) {
        idsToRemove.add(entry.value);
      }
    }

    // Existing rows to update (start_time may have changed)
    for (final entry in newEntries.entries) {
      final existingId = existingDateIds[entry.key];
      if (existingId != null) {
        await supabase.from('gig_dates').update({
          'start_time': entry.value.startTimeDisplay,
        }).eq('id', existingId);
      }
    }

    if (entriesToAdd.isNotEmpty) {
      debugPrint(
          '[EventsRepository] Adding ${entriesToAdd.length} new gig dates');
      await _createGigDates(gigId, entriesToAdd);
    }

    if (idsToRemove.isNotEmpty) {
      debugPrint('[EventsRepository] Removing ${idsToRemove.length} gig dates');
      await supabase.from('gig_dates').delete().inFilter('id', idsToRemove);
    }
  }

  // ---------------------------------------------------------------------------
  // Rehearsal date helpers
  // ---------------------------------------------------------------------------

  /// Create additional dates for a rehearsal (with per-date start times)
  Future<void> _createRehearsalDates(
      String rehearsalId, List<AdditionalDateEntry> entries) async {
    if (entries.isEmpty) return;

    final rows = entries
        .map((e) => {
              'rehearsal_id': rehearsalId,
              'date': e.date.toIso8601String().split('T')[0],
              'start_time': e.startTimeDisplay,
            })
        .toList();

    await supabase.from('rehearsal_dates').insert(rows);
  }

  /// Sync rehearsal dates — mirrors _syncGigDates logic.
  Future<void> _syncRehearsalDates(
      String rehearsalId, EventFormData formData) async {
    if (!formData.isPotentialGig) {
      await supabase
          .from('rehearsal_dates')
          .delete()
          .eq('rehearsal_id', rehearsalId);
      return;
    }

    final newEntries = {for (final e in formData.additionalDates) e.date: e};
    final existingDateIds = formData.existingGigDateIds;

    final entriesToAdd = <AdditionalDateEntry>[];
    for (final entry in newEntries.entries) {
      if (!existingDateIds.containsKey(entry.key)) {
        entriesToAdd.add(entry.value);
      }
    }

    final idsToRemove = <String>[];
    for (final entry in existingDateIds.entries) {
      if (!newEntries.containsKey(entry.key)) {
        idsToRemove.add(entry.value);
      }
    }

    for (final entry in newEntries.entries) {
      final existingId = existingDateIds[entry.key];
      if (existingId != null) {
        await supabase.from('rehearsal_dates').update({
          'start_time': entry.value.startTimeDisplay,
        }).eq('id', existingId);
      }
    }

    if (entriesToAdd.isNotEmpty) {
      await _createRehearsalDates(rehearsalId, entriesToAdd);
    }

    if (idsToRemove.isNotEmpty) {
      await supabase
          .from('rehearsal_dates')
          .delete()
          .inFilter('id', idsToRemove);
    }
  }

  /// Fetch gigs for a month (with caching)
  Future<List<Gig>> fetchGigsForMonth({
    required String bandId,
    required DateTime month,
    bool forceRefresh = false,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    final key = _cacheKey(bandId, month);

    // Check cache
    if (!forceRefresh) {
      final cached = _gigCache[key];
      if (cached != null && !cached.isExpired) {
        debugPrint('[EventsRepository] Cache hit for gigs: $key');
        return cached.data;
      }
    }

    debugPrint('[EventsRepository] Fetching gigs for month: $key');

    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0);

    final response = await supabase
        .from('gigs')
        .select()
        .eq('band_id', bandId)
        .gte('date', startOfMonth.toIso8601String().split('T')[0])
        .lte('date', endOfMonth.toIso8601String().split('T')[0])
        .order('date', ascending: true);

    final gigs = response.map<Gig>((json) => Gig.fromJson(json)).toList();

    // Update cache
    _gigCache[key] = _CacheEntry(gigs);

    return gigs;
  }

  // ============================================================================
  // DELETE OPERATIONS
  // ============================================================================

  /// Delete a rehearsal by ID.
  /// This only deletes the single rehearsal, not the entire series.
  Future<void> deleteRehearsal({
    required String rehearsalId,
    required String bandId,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    debugPrint(
      '[EventsRepository] Deleting rehearsal $rehearsalId for band: $bandId',
    );

    await supabase
        .from('rehearsals')
        .delete()
        .eq('id', rehearsalId)
        .eq('band_id', bandId);

    invalidateCache(bandId);
  }

  /// Delete an entire recurring series.
  /// Strategy:
  /// 1. First try parent-child links (for properly linked series)
  /// 2. Fall back to pattern matching (same time, location, recurring flag)
  ///    for legacy data without parent_rehearsal_id
  Future<void> deleteRehearsalSeries({
    required String rehearsalId,
    required String bandId,
    String? parentRehearsalId,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    debugPrint(
      '[EventsRepository] deleteRehearsalSeries called:\n'
      '  rehearsalId: $rehearsalId\n'
      '  parentRehearsalId param: $parentRehearsalId',
    );

    // First, fetch the rehearsal we're deleting to get its properties
    final rehearsalResult = await supabase
        .from('rehearsals')
        .select()
        .eq('id', rehearsalId)
        .eq('band_id', bandId)
        .maybeSingle();

    if (rehearsalResult == null) {
      debugPrint('[EventsRepository] Rehearsal not found, nothing to delete');
      return;
    }

    final startTime = rehearsalResult['start_time'] as String;
    final endTime = rehearsalResult['end_time'] as String;
    final location = rehearsalResult['location'] as String;
    final rehearsalDate = DateTime.parse(rehearsalResult['date'] as String);

    debugPrint(
      '[EventsRepository] Rehearsal details:\n'
      '  startTime: $startTime\n'
      '  endTime: $endTime\n'
      '  location: $location\n'
      '  date: $rehearsalDate',
    );

    // Strategy 1: Try parent-child links
    String? seriesParentId = parentRehearsalId;

    if (seriesParentId == null) {
      // Check if this rehearsal has children
      final childrenResult = await supabase
          .from('rehearsals')
          .select('id')
          .eq('parent_rehearsal_id', rehearsalId)
          .eq('band_id', bandId);

      if (childrenResult.isNotEmpty) {
        seriesParentId = rehearsalId;
        debugPrint(
          '[EventsRepository] Found ${childrenResult.length} children via parent_rehearsal_id',
        );
      }
    }

    if (seriesParentId != null) {
      // Delete using parent-child relationship
      debugPrint('[EventsRepository] Deleting series via parent-child link');

      await supabase
          .from('rehearsals')
          .delete()
          .eq('parent_rehearsal_id', seriesParentId)
          .eq('band_id', bandId);

      await supabase
          .from('rehearsals')
          .delete()
          .eq('id', seriesParentId)
          .eq('band_id', bandId);

      if (rehearsalId != seriesParentId) {
        await supabase
            .from('rehearsals')
            .delete()
            .eq('id', rehearsalId)
            .eq('band_id', bandId);
      }

      invalidateCache(bandId);
      return;
    }

    // Strategy 2: Pattern matching for legacy data
    // Find all recurring rehearsals with same time, location, and day of week
    debugPrint(
      '[EventsRepository] No parent-child link found, using pattern matching',
    );

    // Get all recurring rehearsals for this band with same time/location
    final matchingRehearsals = await supabase
        .from('rehearsals')
        .select('id, date')
        .eq('band_id', bandId)
        .eq('is_recurring', true)
        .eq('start_time', startTime)
        .eq('end_time', endTime)
        .eq('location', location)
        .gte('date', DateTime.now().toIso8601String().split('T')[0]);

    debugPrint(
      '[EventsRepository] Found ${matchingRehearsals.length} matching recurring rehearsals',
    );

    // Filter to same day of week as the clicked rehearsal
    final clickedDayOfWeek = rehearsalDate.weekday; // 1=Mon, 7=Sun
    final idsToDelete = <String>[];

    for (final r in matchingRehearsals) {
      final rDate = DateTime.parse(r['date'] as String);
      if (rDate.weekday == clickedDayOfWeek) {
        idsToDelete.add(r['id'] as String);
      }
    }

    // Always include the clicked rehearsal (even if it's in the past)
    if (!idsToDelete.contains(rehearsalId)) {
      idsToDelete.add(rehearsalId);
    }

    debugPrint(
      '[EventsRepository] Deleting ${idsToDelete.length} rehearsals matching pattern',
    );

    // Delete all matching rehearsals
    if (idsToDelete.isNotEmpty) {
      await supabase
          .from('rehearsals')
          .delete()
          .inFilter('id', idsToDelete)
          .eq('band_id', bandId);
    }

    invalidateCache(bandId);
  }

  /// Delete a gig by ID
  Future<void> deleteGig({
    required String gigId,
    required String bandId,
  }) async {
    if (bandId.isEmpty) {
      throw NoBandSelectedError();
    }

    debugPrint('[EventsRepository] Deleting gig $gigId for band: $bandId');

    await supabase.from('gigs').delete().eq('id', gigId).eq('band_id', bandId);

    invalidateCache(bandId);
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  final autoConflictService = ref.read(autoConflictBlockingServiceProvider);
  return EventsRepository(autoConflictService);
});
