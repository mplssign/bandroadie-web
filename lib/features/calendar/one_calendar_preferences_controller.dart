import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/features/calendar/models/one_calendar_preferences.dart';
import 'package:bandroadie/features/calendar/one_calendar_preferences_repository.dart';

// ============================================================================
// ONE CALENDAR PREFERENCES CONTROLLER
// Manages One Calendar preferences state with Riverpod
// ============================================================================

final oneCalendarPreferencesProvider = AsyncNotifierProvider<
    OneCalendarPreferencesController, OneCalendarPreferences>(() {
  return OneCalendarPreferencesController();
});

class OneCalendarPreferencesController
    extends AsyncNotifier<OneCalendarPreferences> {
  @override
  Future<OneCalendarPreferences> build() async {
    final repository = ref.read(oneCalendarPreferencesRepositoryProvider);

    debugPrint('[OneCalendarPreferencesController] build() called');
    debugPrint(
        '[OneCalendarPreferencesController] Calling repository.getPreferences()...');

    try {
      final prefs = await repository.getPreferences();
      debugPrint(
          '[OneCalendarPreferencesController] Successfully loaded preferences');
      return prefs;
    } catch (e, stackTrace) {
      debugPrint(
          '[OneCalendarPreferencesController] Failed to load preferences: $e');
      debugPrint('[OneCalendarPreferencesController] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Toggle One Calendar feature on/off
  Future<void> toggleOneCalendar(bool enabled) async {
    if (!state.hasValue) return;
    final current = state.value!;

    final updated = current.copyWith(oneCalendarEnabled: enabled);
    state = AsyncValue.data(updated);

    try {
      final repository = ref.read(oneCalendarPreferencesRepositoryProvider);
      final persisted = await repository.updatePreferences(updated);
      state = AsyncValue.data(persisted);
    } catch (e) {
      // Rollback on error
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  /// Set apply-to mode (all bands or selected bands)
  Future<void> setApplyToMode(ApplyToMode mode) async {
    if (!state.hasValue) return;
    final current = state.value!;

    final updated = current.copyWith(applyToMode: mode);
    state = AsyncValue.data(updated);

    try {
      final repository = ref.read(oneCalendarPreferencesRepositoryProvider);
      final persisted = await repository.updatePreferences(updated);
      state = AsyncValue.data(persisted);
    } catch (e) {
      // Rollback on error
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  /// Update list of selected band IDs (when apply-to mode is 'selected_bands')
  Future<void> updateSelectedBands(List<String> bandIds) async {
    if (!state.hasValue) return;
    final current = state.value!;

    final updated = current.copyWith(selectedBandIds: bandIds);
    state = AsyncValue.data(updated);

    try {
      final repository = ref.read(oneCalendarPreferencesRepositoryProvider);
      final persisted = await repository.updatePreferences(updated);
      state = AsyncValue.data(persisted);
    } catch (e) {
      // Rollback on error
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  /// Toggle automatic conflict blocking on/off
  Future<void> toggleAutoBlockConflicts(bool enabled) async {
    if (!state.hasValue) return;
    final current = state.value!;

    final updated = current.copyWith(autoBlockConflictsEnabled: enabled);
    state = AsyncValue.data(updated);

    try {
      final repository = ref.read(oneCalendarPreferencesRepositoryProvider);
      final persisted = await repository.updatePreferences(updated);
      state = AsyncValue.data(persisted);
    } catch (e) {
      // Rollback on error
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}
