import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import 'package:bandroadie/features/calendar/models/one_calendar_preferences.dart';

// ============================================================================
// ONE CALENDAR PREFERENCES REPOSITORY
// Repository for managing user calendar preferences (One Calendar feature).
// Allows users to share block-out dates across multiple bands.
//
// Table: public.user_calendar_preferences
// ============================================================================

class OneCalendarPreferencesRepository {
  /// Get user's calendar preferences (creates default if missing)
  Future<OneCalendarPreferences> getPreferences() async {
    debugPrint(
      '[OneCalendarPreferencesRepository] Fetching preferences for current user',
    );
    debugPrint(
      '[OneCalendarPreferencesRepository] About to call RPC: get_or_create_calendar_preferences',
    );

    try {
      final response = await supabase.rpc(
        'get_or_create_calendar_preferences',
      );

      debugPrint(
        '[OneCalendarPreferencesRepository] RPC call completed, response: $response',
      );

      final prefs = OneCalendarPreferences.fromJson(
        response as Map<String, dynamic>,
      );

      debugPrint(
        '[OneCalendarPreferencesRepository] Loaded preferences: oneCalendarEnabled=${prefs.oneCalendarEnabled}',
      );

      return prefs;
    } catch (e, stackTrace) {
      debugPrint(
        '[OneCalendarPreferencesRepository] Failed to load preferences: $e',
      );
      debugPrint(
        '[OneCalendarPreferencesRepository] Stack trace: $stackTrace',
      );
      rethrow;
    }
  }

  /// Update user's calendar preferences
  Future<OneCalendarPreferences> updatePreferences(
    OneCalendarPreferences prefs,
  ) async {
    debugPrint(
      '[OneCalendarPreferencesRepository] Updating preferences for current user',
    );

    try {
      final response = await supabase.rpc(
        'update_calendar_preferences',
        params: {
          'p_one_calendar_enabled': prefs.oneCalendarEnabled,
          'p_apply_to_mode': prefs.applyToMode.value,
          'p_selected_band_ids': prefs.selectedBandIds,
          'p_auto_block_conflicts_enabled': prefs.autoBlockConflictsEnabled,
        },
      );

      final updated = OneCalendarPreferences.fromJson(
        response as Map<String, dynamic>,
      );

      debugPrint('[OneCalendarPreferencesRepository] Preferences updated');

      return updated;
    } catch (e) {
      debugPrint(
        '[OneCalendarPreferencesRepository] Failed to update preferences: $e',
      );
      rethrow;
    }
  }

  /// Get list of band IDs where block-out dates should be created
  /// based on user's One Calendar preferences.
  ///
  /// Returns:
  /// - Empty list if One Calendar is disabled
  /// - All user band IDs if apply_to_mode is 'all_bands'
  /// - Selected band IDs if apply_to_mode is 'selected_bands'
  Future<List<String>> getBandIdsToApplyBlockOut(
    List<String> userBandIds,
  ) async {
    debugPrint(
      '[OneCalendarPreferencesRepository] Resolving band IDs for current user',
    );

    try {
      final prefs = await getPreferences();

      // One Calendar disabled: return empty list
      if (!prefs.oneCalendarEnabled) {
        debugPrint(
          '[OneCalendarPreferencesRepository] One Calendar disabled, returning empty list',
        );
        return [];
      }

      // Apply to all bands
      if (prefs.applyToMode == ApplyToMode.allBands) {
        debugPrint(
          '[OneCalendarPreferencesRepository] Apply to all bands: ${userBandIds.length} bands',
        );
        return userBandIds;
      }

      // Apply to selected bands only
      final selectedIds = prefs.selectedBandIds
          .where((id) => userBandIds.contains(id))
          .toList();

      debugPrint(
        '[OneCalendarPreferencesRepository] Apply to selected bands: ${selectedIds.length} bands',
      );

      return selectedIds;
    } catch (e) {
      debugPrint(
        '[OneCalendarPreferencesRepository] Failed to resolve band IDs: $e',
      );
      // On error, return empty list (fail safe: do not propagate)
      return [];
    }
  }
}

// ============================================================================
// PROVIDER
// ============================================================================

final oneCalendarPreferencesRepositoryProvider =
    Provider<OneCalendarPreferencesRepository>((ref) {
  return OneCalendarPreferencesRepository();
});
