import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/notification_preferences.dart';
import 'notification_repository.dart';

// ============================================================================
// NOTIFICATION PREFERENCES CONTROLLER
// Manages notification preferences state with Riverpod
// ============================================================================

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(Supabase.instance.client);
});

final notificationPreferencesProvider =
    AsyncNotifierProvider<NotificationPreferencesController,
        NotificationPreferences>(() {
  return NotificationPreferencesController();
});

class NotificationPreferencesController
    extends AsyncNotifier<NotificationPreferences> {
  late final NotificationRepository _repository;

  @override
  Future<NotificationPreferences> build() async {
    _repository = ref.read(notificationRepositoryProvider);
    return await _repository.getOrCreatePreferences();
  }

  Future<void> updateNotificationsEnabled(bool enabled) async {
    if (!state.hasValue) return;
    final current = state.value!;

    final updated = current.copyWith(notificationsEnabled: enabled);
    state = AsyncValue.data(updated);

    try {
      await _repository.updatePreferences(updated);
    } catch (e, st) {
      // Rollback on error
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  Future<void> updateGigsEnabled(bool enabled) async {
    if (!state.hasValue) return;
    final current = state.value!;

    final updated = current.copyWith(gigsEnabled: enabled);
    state = AsyncValue.data(updated);

    try {
      await _repository.updatePreferences(updated);
    } catch (e, st) {
      // Rollback on error
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  Future<void> updatePotentialGigsEnabled(bool enabled) async {
    if (!state.hasValue) return;
    final current = state.value!;

    final updated = current.copyWith(potentialGigsEnabled: enabled);
    state = AsyncValue.data(updated);

    try {
      await _repository.updatePreferences(updated);
    } catch (e, st) {
      // Rollback on error
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  Future<void> updateRehearsalsEnabled(bool enabled) async {
    if (!state.hasValue) return;
    final current = state.value!;

    final updated = current.copyWith(rehearsalsEnabled: enabled);
    state = AsyncValue.data(updated);

    try {
      await _repository.updatePreferences(updated);
    } catch (e, st) {
      // Rollback on error
      state = AsyncValue.data(current);
      rethrow;
    }
  }

  Future<void> updateBlockoutsEnabled(bool enabled) async {
    if (!state.hasValue) return;
    final current = state.value!;

    final updated = current.copyWith(blockoutsEnabled: enabled);
    state = AsyncValue.data(updated);

    try {
      await _repository.updatePreferences(updated);
    } catch (e, st) {
      // Rollback on error
      state = AsyncValue.data(current);
      rethrow;
    }
  }
}
