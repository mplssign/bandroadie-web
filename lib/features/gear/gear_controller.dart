import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gear_repository.dart';
import 'models/gear_item.dart';

class GearState {
  final List<GearItem> items;
  final bool isLoading;
  final String? error;

  const GearState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  bool get hasItems => items.isNotEmpty;

  GearState copyWith({
    List<GearItem>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return GearState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class GearNotifier extends Notifier<GearState> {
  final GearRepository _repository = GearRepository();

  @override
  GearState build() => const GearState();

  Future<void> load(String? bandId) async {
    if (bandId == null || bandId.isEmpty) {
      state = state.copyWith(
        items: [],
        isLoading: false,
        error: 'No band selected',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items = await _repository.fetchGear(bandId: bandId);
      state = state.copyWith(
        items: items,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh(String? bandId) async {
    if (bandId == null || bandId.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final items =
          await _repository.fetchGear(bandId: bandId, forceRefresh: true);
      state = state.copyWith(
        items: items,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<GearItem?> create({
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final item = await _repository.createGear(bandId: bandId, data: data);
      await load(bandId);
      return item;
    } catch (e) {
      return null;
    }
  }

  Future<GearItem?> update({
    required String id,
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final item = await _repository.updateGear(id: id, data: data);
      await load(bandId);
      return item;
    } catch (e) {
      return null;
    }
  }

  Future<bool> delete({
    required String id,
    required String bandId,
  }) async {
    try {
      await _repository.deleteGear(id: id, bandId: bandId);
      await load(bandId);
      return true;
    } catch (e) {
      return false;
    }
  }

  void reset() {
    _repository.clearCache();
    state = const GearState();
  }
}

final gearProvider = NotifierProvider<GearNotifier, GearState>(
  GearNotifier.new,
);
