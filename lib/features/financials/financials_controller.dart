import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bands/active_band_controller.dart';
import 'financial_entry_repository.dart';
import 'models/financial_entry.dart';

// ============================================================================
// FINANCIALS CONTROLLER
// State management for the Financials screen.
// Follows GigNotifier pattern: watches activeBandIdProvider in build()
// for automatic band-change reactivity.
// ============================================================================

enum FinancialViewMode { income, expenses }

enum FinancialDateFilter { allTime, thisYear, thisMonth, custom }

class FinancialsState {
  final List<FinancialEntry> allEntries;
  final bool isLoading;
  final String? error;
  final FinancialViewMode viewMode;
  final FinancialDateFilter dateFilter;
  final DateTime? customStartDate;
  final DateTime? customEndDate;

  const FinancialsState({
    this.allEntries = const [],
    this.isLoading = false,
    this.error,
    this.viewMode = FinancialViewMode.income,
    this.dateFilter = FinancialDateFilter.allTime,
    this.customStartDate,
    this.customEndDate,
  });

  FinancialsState copyWith({
    List<FinancialEntry>? allEntries,
    bool? isLoading,
    String? error,
    FinancialViewMode? viewMode,
    FinancialDateFilter? dateFilter,
    DateTime? customStartDate,
    DateTime? customEndDate,
    bool clearError = false,
    bool clearCustomDates = false,
  }) {
    return FinancialsState(
      allEntries: allEntries ?? this.allEntries,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      viewMode: viewMode ?? this.viewMode,
      dateFilter: dateFilter ?? this.dateFilter,
      customStartDate:
          clearCustomDates ? null : (customStartDate ?? this.customStartDate),
      customEndDate:
          clearCustomDates ? null : (customEndDate ?? this.customEndDate),
    );
  }

  List<FinancialEntry> get filteredEntries {
    final now = DateTime.now();
    List<FinancialEntry> entries = allEntries.where((e) {
      // Filter by income/expense mode
      if (viewMode == FinancialViewMode.income && !e.isIncome) return false;
      if (viewMode == FinancialViewMode.expenses && e.isIncome) return false;
      // Filter by date range
      switch (dateFilter) {
        case FinancialDateFilter.allTime:
          return true;
        case FinancialDateFilter.thisYear:
          return e.entryDate.year == now.year;
        case FinancialDateFilter.thisMonth:
          return e.entryDate.year == now.year && e.entryDate.month == now.month;
        case FinancialDateFilter.custom:
          if (customStartDate == null || customEndDate == null) return true;
          final start = DateTime(customStartDate!.year, customStartDate!.month,
              customStartDate!.day);
          final end = DateTime(customEndDate!.year, customEndDate!.month,
              customEndDate!.day, 23, 59, 59);
          return !e.entryDate.isBefore(start) && !e.entryDate.isAfter(end);
      }
    }).toList();
    entries.sort((a, b) => b.entryDate.compareTo(a.entryDate));
    return entries;
  }
}

class FinancialsNotifier extends Notifier<FinancialsState> {
  @override
  FinancialsState build() {
    final bandId = ref.watch(activeBandIdProvider);
    if (bandId == null) return const FinancialsState();

    Future.microtask(() => _load(bandId));
    return const FinancialsState(isLoading: true);
  }

  Future<void> _load(String bandId) async {
    final repo = ref.read(financialEntryRepositoryProvider);
    try {
      final entries = await repo.fetchEntriesForBand(bandId);
      if (!_isMounted) return;
      state = state.copyWith(
        allEntries: entries,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      if (!_isMounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load financials. Please try again.',
      );
    }
  }

  bool get _isMounted {
    try {
      // Accessing state throws if the notifier has been disposed
      // ignore: unnecessary_statements
      state;
      return true;
    } catch (_) {
      return false;
    }
  }

  void setViewMode(FinancialViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }

  void setDateFilter(FinancialDateFilter filter) {
    state = state.copyWith(dateFilter: filter);
  }

  void setCustomDateRange(DateTime start, DateTime end) {
    state = state.copyWith(
      dateFilter: FinancialDateFilter.custom,
      customStartDate: start,
      customEndDate: end,
    );
  }

  Future<void> addEntry({
    required FinancialEntryType entryType,
    required String category,
    required int amountCents,
    required DateTime entryDate,
    String? description,
    bool? is1099Expected,
    String? payerName,
    String? paidToName,
    String? paidToUserId,
    Map<String, int>? disbursements,
  }) async {
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) throw StateError('No band selected');

    final repo = ref.read(financialEntryRepositoryProvider);
    try {
      final entry = await repo.insertEntry(
        bandId: bandId,
        entryType: entryType,
        category: category,
        amountCents: amountCents,
        entryDate: entryDate,
        description: description,
        is1099Expected: is1099Expected,
        payerName: payerName,
        paidToName: paidToName,
        paidToUserId: paidToUserId,
        disbursements: disbursements,
      );
      state = state.copyWith(
        allEntries: [entry, ...state.allEntries],
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('addEntry failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> updateEntry({
    required String entryId,
    required FinancialEntryType entryType,
    required String category,
    required int amountCents,
    required DateTime entryDate,
    String? description,
    bool? is1099Expected,
    String? payerName,
    String? paidToName,
    String? paidToUserId,
    Map<String, int>? disbursements,
  }) async {
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) throw StateError('No band selected');

    final repo = ref.read(financialEntryRepositoryProvider);
    try {
      final updated = await repo.updateEntry(
        entryId: entryId,
        bandId: bandId,
        entryType: entryType,
        category: category,
        amountCents: amountCents,
        entryDate: entryDate,
        description: description,
        is1099Expected: is1099Expected,
        payerName: payerName,
        paidToName: paidToName,
        paidToUserId: paidToUserId,
        disbursements: disbursements,
      );
      state = state.copyWith(
        allEntries:
            state.allEntries.map((e) => e.id == entryId ? updated : e).toList(),
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('updateEntry failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> refresh() async {
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null) return;
    state = state.copyWith(isLoading: true, clearError: true);
    await _load(bandId);
  }
}

final financialsProvider =
    NotifierProvider<FinancialsNotifier, FinancialsState>(
  FinancialsNotifier.new,
);
