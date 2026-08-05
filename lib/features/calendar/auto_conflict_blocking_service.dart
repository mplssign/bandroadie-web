import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/features/calendar/one_calendar_preferences_repository.dart';
import 'package:bandroadie/features/calendar/block_out_repository.dart';

// ============================================================================
// AUTO CONFLICT BLOCKING SERVICE
// Automatically creates block-out dates on other bands when a user confirms
// a gig or rehearsal in one band (if One Calendar auto-blocking is enabled).
// ============================================================================

class AutoConflictBlockingService {
  final OneCalendarPreferencesRepository _prefsRepository;
  final BlockOutRepository _blockOutRepository;

  AutoConflictBlockingService(
    this._prefsRepository,
    this._blockOutRepository,
  );

  /// Automatically block dates on other bands when an event is created
  ///
  /// [userId] - The user who is confirming the event
  /// [eventBandId] - The band where the event is being created
  /// [eventDate] - The date of the event (for gigs)
  /// [eventStartTime] - The start time of the event (for rehearsals)
  /// [eventEndTime] - The end time of the event (for rehearsals, optional)
  /// [eventName] - The name of the event (for display in block-out reason)
  /// [bandName] - The name of the band (for display in block-out reason)
  Future<void> autoBlockConflictingDate({
    required String userId,
    required String eventBandId,
    required DateTime eventDate,
    DateTime? eventStartTime,
    DateTime? eventEndTime,
    required String eventName,
    required String bandName,
  }) async {
    debugPrint(
      '[AutoConflictBlockingService] Checking auto-block for user: $userId, event: $eventName',
    );

    try {
      // Check if user has auto-conflict blocking enabled
      final prefs = await _prefsRepository.getPreferences();

      if (!prefs.oneCalendarEnabled || !prefs.autoBlockConflictsEnabled) {
        debugPrint(
          '[AutoConflictBlockingService] Auto-block disabled, skipping',
        );
        return;
      }

      // Fetch user's bands from database
      final bandsResponse = await supabase
          .from('band_members')
          .select('band_id')
          .eq('user_id', userId);

      final userBandIds = (bandsResponse as List)
          .map((row) => row['band_id'] as String)
          .toList();

      // Get band IDs where block-out should be propagated
      final bandIds = await _prefsRepository.getBandIdsToApplyBlockOut(
        userBandIds,
      );

      // Remove the event band (user is already busy in that band)
      final otherBandIds = bandIds.where((id) => id != eventBandId).toList();

      if (otherBandIds.isEmpty) {
        debugPrint(
          '[AutoConflictBlockingService] No other bands to block, skipping',
        );
        return;
      }

      // Generate block-out reason
      final reason = 'Unavailable (scheduled with $bandName)';

      // Create block-out dates for other bands
      // Use only the date (not time) for block-out
      final blockOutDate = DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
      );

      for (final bandId in otherBandIds) {
        try {
          await _blockOutRepository.createBlockOut(
            bandId: bandId,
            userId: userId,
            startDate: blockOutDate,
            untilDate: null, // Single day
            reason: reason,
          );
          debugPrint(
            '[AutoConflictBlockingService] Auto-blocked date for band: $bandId',
          );
        } catch (e) {
          // Skip duplicates or errors for individual bands
          // (user may have already manually blocked the date)
          debugPrint(
            '[AutoConflictBlockingService] Failed to auto-block for band $bandId: $e',
          );
        }
      }

      debugPrint(
        '[AutoConflictBlockingService] Auto-block complete: ${otherBandIds.length} bands',
      );
    } catch (e) {
      // Do not fail the primary operation if auto-blocking fails
      debugPrint('[AutoConflictBlockingService] Auto-block error: $e');
    }
  }

  /// Automatically block multiple dates on other bands when recurring events are created
  ///
  /// [userId] - The user who is confirming the event
  /// [eventBandId] - The band where the event is being created
  /// [eventDates] - List of event dates to block
  /// [eventStartTime] - The start time of the event (for rehearsals)
  /// [eventEndTime] - The end time of the event (for rehearsals, optional)
  /// [eventName] - The name of the event (for display in block-out reason)
  /// [bandName] - The name of the band (for display in block-out reason)
  /// [sourceGigId] - If blocking for a gig, pass the gig ID (applies to all dates)
  /// [sourceRehearsalIdsByDate] - If blocking for rehearsal(s), pass list of rehearsal IDs (parallel to eventDates)
  Future<void> autoBlockConflictingDates({
    required String userId,
    required String eventBandId,
    required List<DateTime> eventDates,
    DateTime? eventStartTime,
    DateTime? eventEndTime,
    required String eventName,
    required String bandName,
    String? sourceGigId,
    List<String>? sourceRehearsalIdsByDate,
  }) async {
    debugPrint(
      '[AutoConflictBlockingService] Auto-blocking ${eventDates.length} date(s) for user: $userId, event: $eventName',
    );

    // Validate sourceRehearsalIdsByDate length matches eventDates if provided
    if (sourceRehearsalIdsByDate != null) {
      assert(
        sourceRehearsalIdsByDate.length == eventDates.length,
        'sourceRehearsalIdsByDate length must match eventDates length',
      );
    }

    try {
      // Check if user has auto-conflict blocking enabled
      final prefs = await _prefsRepository.getPreferences();

      if (!prefs.oneCalendarEnabled || !prefs.autoBlockConflictsEnabled) {
        debugPrint(
          '[AutoConflictBlockingService] Auto-block disabled, skipping',
        );
        return;
      }

      // Fetch user's bands from database
      final bandsResponse = await supabase
          .from('band_members')
          .select('band_id')
          .eq('user_id', userId);

      final userBandIds = (bandsResponse as List)
          .map((row) => row['band_id'] as String)
          .toList();

      // Get band IDs where block-out should be propagated
      final bandIds = await _prefsRepository.getBandIdsToApplyBlockOut(
        userBandIds,
      );

      // Remove the event band (user is already busy in that band)
      final otherBandIds = bandIds.where((id) => id != eventBandId).toList();

      if (otherBandIds.isEmpty) {
        debugPrint(
          '[AutoConflictBlockingService] No other bands to block, skipping',
        );
        return;
      }

      // Generate block-out reason
      final reason = 'Unavailable (scheduled with $bandName)';

      // Loop through all dates (indexed to match sourceRehearsalIdsByDate)
      for (var i = 0; i < eventDates.length; i++) {
        final eventDate = eventDates[i];
        final sourceRehearsalId = sourceRehearsalIdsByDate?[i];

        // Use only the date (not time) for block-out
        final blockOutDate = DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
        );

        // Loop through all other bands
        for (final bandId in otherBandIds) {
          try {
            await _blockOutRepository.createBlockOut(
              bandId: bandId,
              userId: userId,
              startDate: blockOutDate,
              untilDate: null, // Single day
              reason: reason,
              sourceGigId: sourceGigId,
              sourceRehearsalId: sourceRehearsalId,
            );
            debugPrint(
              '[AutoConflictBlockingService] Auto-blocked date $blockOutDate for band: $bandId',
            );
          } catch (e) {
            // Skip duplicates or errors for individual bands
            // (user may have already manually blocked the date)
            debugPrint(
              '[AutoConflictBlockingService] Failed to auto-block for band $bandId date $blockOutDate: $e',
            );
          }
        }
      }

      debugPrint(
        '[AutoConflictBlockingService] Auto-block complete: ${eventDates.length} date(s) × ${otherBandIds.length} bands',
      );
    } catch (e) {
      // Do not fail the primary operation if auto-blocking fails
      debugPrint('[AutoConflictBlockingService] Auto-block error: $e');
    }
  }

  /// Clear all auto-created block-outs for a specific source event
  /// Used when updating or deleting gigs/rehearsals.
  Future<void> clearAutoBlocksForSource({
    String? sourceGigId,
    String? sourceRehearsalId,
  }) {
    return _blockOutRepository.deleteBlockOutsForSource(
      sourceGigId: sourceGigId,
      sourceRehearsalId: sourceRehearsalId,
    );
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

final autoConflictBlockingServiceProvider =
    Provider<AutoConflictBlockingService>((ref) {
  final prefsRepo = ref.read(oneCalendarPreferencesRepositoryProvider);
  final blockOutRepo = ref.read(blockOutRepositoryProvider);
  return AutoConflictBlockingService(prefsRepo, blockOutRepo);
});
