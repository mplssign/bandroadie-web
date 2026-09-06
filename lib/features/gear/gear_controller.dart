import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gear_repository.dart';
import 'models/gear_item.dart';

enum GearOwnerFilter { all, band, member }

enum GearDateFilter { allTime, thisYear, thisMonth, custom }

class GearState {
  final List<GearItem> items;
  final bool isLoading;
  final String? error;
  final GearOwnerFilter ownerFilter;
  final GearDateFilter dateFilter;
  final DateTime? customStartDate;
  final DateTime? customEndDate;

  const GearState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.ownerFilter = GearOwnerFilter.all,
    this.dateFilter = GearDateFilter.allTime,
    this.customStartDate,
    this.customEndDate,
  });

  bool get hasItems => items.isNotEmpty;

  GearState copyWith({
    List<GearItem>? items,
    bool? isLoading,
    String? error,
    GearOwnerFilter? ownerFilter,
    GearDateFilter? dateFilter,
    DateTime? customStartDate,
    DateTime? customEndDate,
    bool clearError = false,
    bool clearCustomDates = false,
  }) {
    return GearState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      ownerFilter: ownerFilter ?? this.ownerFilter,
      dateFilter: dateFilter ?? this.dateFilter,
      customStartDate:
          clearCustomDates ? null : (customStartDate ?? this.customStartDate),
      customEndDate:
          clearCustomDates ? null : (customEndDate ?? this.customEndDate),
    );
  }

  /// Items after owner + date filters, sorted newest-purchased first.
  /// Rows with `purchasedOn == null` only survive when
  /// `dateFilter == GearDateFilter.allTime`; every bounded filter drops them.
  List<GearItem> get filteredItems {
    final now = DateTime.now();
    final filtered = items.where((item) {
      switch (ownerFilter) {
        case GearOwnerFilter.all:
          break;
        case GearOwnerFilter.band:
          if (item.ownerType != GearOwnerType.band) return false;
          break;
        case GearOwnerFilter.member:
          if (item.ownerType != GearOwnerType.member) return false;
          break;
      }
      switch (dateFilter) {
        case GearDateFilter.allTime:
          return true;
        case GearDateFilter.thisYear:
          final d = item.purchasedOn;
          if (d == null) return false;
          return d.year == now.year;
        case GearDateFilter.thisMonth:
          final d = item.purchasedOn;
          if (d == null) return false;
          return d.year == now.year && d.month == now.month;
        case GearDateFilter.custom:
          if (customStartDate == null || customEndDate == null) return true;
          final d = item.purchasedOn;
          if (d == null) return false;
          final start = DateTime(customStartDate!.year, customStartDate!.month,
              customStartDate!.day);
          final end = DateTime(customEndDate!.year, customEndDate!.month,
              customEndDate!.day, 23, 59, 59);
          return !d.isBefore(start) && !d.isAfter(end);
      }
    }).toList();
    filtered.sort((a, b) {
      final ad = a.purchasedOn;
      final bd = b.purchasedOn;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return filtered;
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

  void setOwnerFilter(GearOwnerFilter filter) {
    state = state.copyWith(ownerFilter: filter);
  }

  void setDateFilter(GearDateFilter filter) {
    state = state.copyWith(dateFilter: filter);
  }

  void setCustomDateRange(DateTime start, DateTime end) {
    state = state.copyWith(
      dateFilter: GearDateFilter.custom,
      customStartDate: start,
      customEndDate: end,
    );
  }

  void reset() {
    _repository.clearCache();
    state = const GearState();
  }
}

final gearProvider = NotifierProvider<GearNotifier, GearState>(
  GearNotifier.new,
);
