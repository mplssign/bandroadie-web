import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_icons.dart';
import '../../app/theme/brand_colors.dart';
import '../../app/theme/design_tokens.dart';
import '../bands/active_band_controller.dart';
import '../members/members_controller.dart';
import '../members/permissions/band_permissions_provider.dart';
import 'financials_controller.dart';
import 'financials_pdf_preview_screen.dart';
import 'models/financial_entry.dart';
import 'widgets/add_financial_entry_bottom_sheet.dart';
import 'widgets/financial_entry_details_bottom_sheet.dart';
import '../setlists/widgets/back_only_app_bar.dart';

// ============================================================================
// FINANCIALS SCREEN
// Top-level screen displaying aggregated financial entries.
// Pushed anonymously via Navigator.push from HomeTabContent.
// ============================================================================

class FinancialsScreen extends ConsumerStatefulWidget {
  const FinancialsScreen({super.key});

  @override
  ConsumerState<FinancialsScreen> createState() => _FinancialsScreenState();
}

class _FinancialsScreenState extends ConsumerState<FinancialsScreen> {
  bool _sortAscending = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _addEntry(FinancialsState state) async {
    final notifier = ref.read(financialsProvider.notifier);
    final isIncome = state.viewMode == FinancialViewMode.income;
    final members = ref.read(membersProvider).members;
    final savingsTotalCents = state.allEntries
        .where((e) => e.depositToSavings == true)
        .fold<int>(0, (sum, e) => sum + (e.depositToSavingsCents ?? 0));
    await showAddFinancialEntrySheet(
      context,
      initialIsIncome: isIncome,
      members: members,
      savingsTotalCents: savingsTotalCents,
      onSave: ({
        required entryType,
        required category,
        required amountCents,
        required entryDate,
        description,
        is1099Expected,
        payerName,
        paidToName,
        paidToUserId,
        disbursements,
        depositToSavings,
        depositToSavingsCents,
      }) async {
        await notifier.addEntry(
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
          depositToSavings: depositToSavings,
          depositToSavingsCents: depositToSavingsCents,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financialsProvider);
    final filtered = state.filteredEntries;
    final sortedEntries =
        _sortAscending ? filtered.reversed.toList() : filtered;
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final canCreate = permissionsAsync.when(
      data: (p) => p.canCreateFinancials,
      loading: () => false,
      error: (_, __) => false,
    );

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Back bar (matches setlist detail)
                BackOnlyAppBar(
                  onBack: () => Navigator.of(context).pop(),
                ),
                // Page content below app bar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Page title + add action
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.pagePadding,
                          Spacing.space20,
                          Spacing.pagePadding,
                          0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Financials',
                                style: AppTextStyles.pageTitle.copyWith(
                                    color: context.colors.textPrimary),
                              ),
                            ),
                            if (canCreate)
                              TextButton.icon(
                                onPressed: state.isLoading
                                    ? null
                                    : () => _addEntry(state),
                                icon: const Icon(AppIcons.add, size: 18),
                                label: const Text('Add'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Spacing.space16),
                      // Income / Expenses toggle
                      _ViewModeToggle(
                        current: state.viewMode,
                        onChanged: (m) => ref
                            .read(financialsProvider.notifier)
                            .setViewMode(m),
                      ),
                      const SizedBox(height: Spacing.space12),
                      // Date filter row
                      _DateFilterRow(
                        current: state.dateFilter,
                        customStartDate: state.customStartDate,
                        customEndDate: state.customEndDate,
                        onChanged: (f) => ref
                            .read(financialsProvider.notifier)
                            .setDateFilter(f),
                        onCustomRange: (start, end) => ref
                            .read(financialsProvider.notifier)
                            .setCustomDateRange(start, end),
                      ),
                      const SizedBox(height: Spacing.space16),
                      // Entries list
                      Expanded(
                        child: state.isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.primary),
                              )
                            : state.error != null
                                ? _ErrorState(message: state.error!)
                                : filtered.isEmpty
                                    ? const _EmptyState()
                                    : Column(
                                        children: [
                                          const _SummaryHeader(),
                                          _TransactionsListHeader(
                                            sortAscending: _sortAscending,
                                            onToggleSort: () => setState(() =>
                                                _sortAscending =
                                                    !_sortAscending),
                                          ),
                                          const SizedBox(
                                              height: Spacing.space8),
                                          Expanded(
                                            child: ListView.separated(
                                              padding: EdgeInsets.only(
                                                left: Spacing.pagePadding,
                                                right: Spacing.pagePadding,
                                                bottom: MediaQuery.of(context)
                                                        .padding
                                                        .bottom +
                                                    Spacing.space16,
                                              ),
                                              itemCount: sortedEntries.length,
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(
                                                      height: Spacing.space12),
                                              itemBuilder: (context, index) {
                                                final entry =
                                                    sortedEntries[index];
                                                return _TransactionCard(
                                                  entry: entry,
                                                  onTap: () =>
                                                      showFinancialEntryDetailsSheet(
                                                    context,
                                                    ref,
                                                    entry,
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SAVINGS SHEET
// ---------------------------------------------------------------------------

void _showSavingsSheet(BuildContext context, List<FinancialEntry> allEntries) {
  final entries = allEntries.where((e) => e.depositToSavings == true).toList()
    ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
  final totalCents =
      entries.fold<int>(0, (sum, e) => sum + (e.depositToSavingsCents ?? 0));

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SavingsSheet(entries: entries, totalCents: totalCents),
  );
}

class _SavingsSheet extends StatefulWidget {
  const _SavingsSheet({
    required this.entries,
    required this.totalCents,
  });

  final List<FinancialEntry> entries;
  final int totalCents;

  @override
  State<_SavingsSheet> createState() => _SavingsSheetState();
}

class _SavingsSheetState extends State<_SavingsSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countController;
  late final Animation<double> _countAnim;
  late final ConfettiController _confettiController;

  static const _countDuration = Duration(milliseconds: 1400);

  String _fmt(int cents) {
    final dollars = cents ~/ 100;
    final remainder = cents % 100;
    final formatted = NumberFormat('#,##0').format(dollars);
    return '\$$formatted.${remainder.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(milliseconds: 1800));
    _countController = AnimationController(
      vsync: this,
      duration: _countDuration,
    );
    _countAnim = CurvedAnimation(
      parent: _countController,
      curve: Curves.easeOut,
    );
    // Delay slightly so the sheet has finished sliding in
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _countController.forward();
      if (widget.totalCents > 0) _confettiController.play();
    });
  }

  @override
  void dispose() {
    _countController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Spacing.cardRadius),
                ),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.space16),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.colors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.space24),
                  // "Total Savings" label
                  Text(
                    'Total Savings',
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: Spacing.space8),
                  // Animated balance
                  AnimatedBuilder(
                    animation: _countAnim,
                    builder: (_, __) {
                      final displayed =
                          (widget.totalCents * _countAnim.value).round();
                      return Text(
                        _fmt(displayed),
                        style: AppTextStyles.displayLarge.copyWith(
                          color: context.colors.success,
                          fontWeight: FontWeight.w800,
                          fontSize: AppFontSizes.hero,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: Spacing.space4),
                  Text(
                    'Running total across all deposits to savings',
                    style: AppTextStyles.footnote
                        .copyWith(color: context.colors.textMuted),
                  ),
                  const SizedBox(height: Spacing.space20),
                  Divider(height: 1, color: context.colors.border),
                  // List
                  Expanded(
                    child: widget.entries.isEmpty
                        ? Center(
                            child: Text(
                              'No savings entries yet',
                              style: AppTextStyles.callout
                                  .copyWith(color: context.colors.textMuted),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                                vertical: Spacing.space8),
                            itemCount: widget.entries.length,
                            separatorBuilder: (_, __) => Divider(
                                height: 1, color: context.colors.border),
                            itemBuilder: (_, i) {
                              final e = widget.entries[i];
                              final dateStr =
                                  DateFormat('MMM d, yyyy').format(e.entryDate);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Spacing.pagePadding,
                                  vertical: Spacing.space12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.category,
                                            style: AppTextStyles.callout
                                                .copyWith(
                                                    color: context
                                                        .colors.textPrimary),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            dateStr,
                                            style: AppTextStyles.footnote
                                                .copyWith(
                                                    color: context
                                                        .colors.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      e.depositToSavingsCents != null
                                          ? _fmt(e.depositToSavingsCents!)
                                          : '—',
                                      style: AppTextStyles.callout.copyWith(
                                        color: context.colors.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            // Confetti fires from the top-centre
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 30,
              gravity: 0.25,
              emissionFrequency: 0.05,
              colors: const [
                AppColors.success,
                Color(0xFF86EFAC), // green-300
                Colors.white,
                AppColors.primary,
              ],
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// DATE FILTER ROW
// ---------------------------------------------------------------------------

class _DateFilterRow extends StatelessWidget {
  const _DateFilterRow({
    required this.current,
    required this.onChanged,
    required this.onCustomRange,
    this.customStartDate,
    this.customEndDate,
  });

  final FinancialDateFilter current;
  final ValueChanged<FinancialDateFilter> onChanged;
  final void Function(DateTime start, DateTime end) onCustomRange;
  final DateTime? customStartDate;
  final DateTime? customEndDate;

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 2),
      initialDateRange: (customStartDate != null && customEndDate != null)
          ? DateTimeRange(start: customStartDate!, end: customEndDate!)
          : DateTimeRange(
              start: DateTime(now.year, now.month),
              end: now,
            ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: Color(0xFF18181B),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      onCustomRange(picked.start, picked.end);
    }
  }

  String get _customLabel {
    if (current == FinancialDateFilter.custom &&
        customStartDate != null &&
        customEndDate != null) {
      final fmt = DateFormat('MMM d');
      final fmtYear = DateFormat('MMM d, yy');
      final sameYear = customStartDate!.year == customEndDate!.year;
      if (sameYear) {
        return '${fmt.format(customStartDate!)} – ${fmt.format(customEndDate!)}';
      }
      return '${fmtYear.format(customStartDate!)} – ${fmtYear.format(customEndDate!)}';
    }
    return 'Custom';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
      child: Row(
        children: [
          _FilterChip(
            label: 'All Time',
            active: current == FinancialDateFilter.allTime,
            onTap: () => onChanged(FinancialDateFilter.allTime),
          ),
          const SizedBox(width: Spacing.space8),
          _FilterChip(
            label: 'This Year',
            active: current == FinancialDateFilter.thisYear,
            onTap: () => onChanged(FinancialDateFilter.thisYear),
          ),
          const SizedBox(width: Spacing.space8),
          _FilterChip(
            label: 'This Month',
            active: current == FinancialDateFilter.thisMonth,
            onTap: () => onChanged(FinancialDateFilter.thisMonth),
          ),
          const SizedBox(width: Spacing.space8),
          _FilterChip(
            label: _customLabel,
            active: current == FinancialDateFilter.custom,
            onTap: () => _pickCustomRange(context),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space12,
          vertical: Spacing.space8,
        ),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.15)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(Spacing.chipRadius),
          border: Border.all(
            color: active ? AppColors.primary : context.colors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: active ? AppColors.primary : context.colors.textSecondary,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VIEW MODE TOGGLE
// ---------------------------------------------------------------------------

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.current, required this.onChanged});

  final FinancialViewMode current;
  final ValueChanged<FinancialViewMode> onChanged;

  static const _modes = [FinancialViewMode.income, FinancialViewMode.expenses];
  static const _labels = ['Income', 'Expenses'];

  @override
  Widget build(BuildContext context) {
    final currentIndex = _modes.indexOf(current).clamp(0, _modes.length - 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentWidth = constraints.maxWidth / _modes.length;
            return Stack(
              children: [
                // Sliding indicator
                AnimatedAlign(
                  alignment: Alignment(
                    -1.0 + (2.0 * currentIndex / (_modes.length - 1)),
                    0.0,
                  ),
                  duration: AppDurations.fast,
                  curve: AppCurves.ease,
                  child: Container(
                    width: segmentWidth,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                // Labels
                Row(
                  children: List.generate(_modes.length, (i) {
                    final isSelected = current == _modes[i];
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          onChanged(_modes[i]);
                          HapticFeedback.selectionClick();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: AppDurations.fast,
                            curve: AppCurves.ease,
                            style: TextStyle(
                              fontSize: AppFontSizes.subhead,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : context.colors.textPrimary,
                            ),
                            child: Text(_labels[i]),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// BOTTOM ACTIONS ROW
// ---------------------------------------------------------------------------

void _openCombinedReport(
  BuildContext context,
  WidgetRef ref,
  FinancialsState state,
) {
  final bandName = ref.read(activeBandProvider).activeBand?.name ?? 'Band';
  final members = ref.read(membersProvider).members;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FinancialsPdfPreviewScreen(
        entries: state.dateFilteredEntries,
        bandName: bandName,
        dateFilter: state.dateFilter,
        customStartDate: state.customStartDate,
        customEndDate: state.customEndDate,
        members: members,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// EMPTY + ERROR STATES
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.music,
              size: 48,
              color: context.colors.textMuted,
            ),
            const SizedBox(height: Spacing.space16),
            Text(
              'No entries yet',
              style: AppTextStyles.displayMedium
                  .copyWith(color: context.colors.textPrimary),
            ),
            const SizedBox(height: Spacing.space8),
            Text(
              'Add gig pay details to your gigs\nto see them here.',
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.body.copyWith(color: context.colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: AppColors.error),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SUMMARY HEADER
// ---------------------------------------------------------------------------

class _SummaryHeader extends ConsumerWidget {
  const _SummaryHeader();

  String _dateRangeLabel(FinancialsState state) {
    switch (state.dateFilter) {
      case FinancialDateFilter.allTime:
        return 'All time';
      case FinancialDateFilter.thisYear:
        return '${DateTime.now().year}';
      case FinancialDateFilter.thisMonth:
        return DateFormat('MMMM yyyy').format(DateTime.now());
      case FinancialDateFilter.custom:
        if (state.customStartDate != null && state.customEndDate != null) {
          final fmt = DateFormat('MMM d');
          final fmtYear = DateFormat('MMM d, yy');
          final sameYear =
              state.customStartDate!.year == state.customEndDate!.year;
          if (sameYear) {
            return '${fmt.format(state.customStartDate!)} – ${fmt.format(state.customEndDate!)}';
          }
          return '${fmtYear.format(state.customStartDate!)} – ${fmtYear.format(state.customEndDate!)}';
        }
        return 'Custom';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(financialsProvider);
    final isIncome = state.viewMode == FinancialViewMode.income;
    final totalCents =
        state.filteredEntries.fold<int>(0, (sum, e) => sum + e.amountCents);
    final totalDollars = totalCents ~/ 100;
    final totalRemainderCents = totalCents % 100;
    final totalFormatted =
        '\$${NumberFormat('#,##0').format(totalDollars)}.${totalRemainderCents.toString().padLeft(2, '0')}';
    final count = state.filteredEntries.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isIncome ? 'TOTAL INCOME' : 'TOTAL EXPENSES',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: Spacing.space4),
          Text(
            totalFormatted,
            style: AppTextStyles.displayLarge.copyWith(
              color: isIncome ? context.colors.success : AppColors.error,
            ),
          ),
          const SizedBox(height: Spacing.space4),
          Text(
            _dateRangeLabel(state),
            style: AppTextStyles.footnote
                .copyWith(color: context.colors.textMuted),
          ),
          Text(
            count == 1 ? '1 transaction' : '$count transactions',
            style: AppTextStyles.footnote
                .copyWith(color: context.colors.textMuted),
          ),
          const SizedBox(height: Spacing.space12),
          Row(
            children: [
              _InlineLinkButton(
                label: 'View Savings Balance',
                onTap: () => _showSavingsSheet(context, state.allEntries),
              ),
              const SizedBox(width: Spacing.space16),
              _InlineLinkButton(
                label: 'Generate Report',
                onTap: state.isLoading
                    ? null
                    : () => _openCombinedReport(context, ref, state),
              ),
            ],
          ),
          const SizedBox(height: Spacing.space16),
        ],
      ),
    );
  }
}

class _InlineLinkButton extends StatelessWidget {
  const _InlineLinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppColors.primary.withValues(alpha: 0.4)
        : AppColors.primary;
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.footnote.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: Spacing.space4),
          Icon(AppIcons.forward, size: 16, color: color),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TRANSACTIONS LIST HEADER
// ---------------------------------------------------------------------------

class _TransactionsListHeader extends StatelessWidget {
  const _TransactionsListHeader({
    required this.sortAscending,
    required this.onToggleSort,
  });

  final bool sortAscending;
  final VoidCallback onToggleSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Transactions',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textMuted,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          InkWell(
            onTap: onToggleSort,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  sortAscending ? 'Oldest first ▾' : 'Newest first ▾',
                  style: AppTextStyles.footnote
                      .copyWith(color: context.colors.textMuted),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TRANSACTION CARD
// ---------------------------------------------------------------------------

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.entry, required this.onTap});

  final FinancialEntry entry;
  final VoidCallback onTap;

  String get _title {
    if (entry.isIncome) {
      return (entry.payerName != null && entry.payerName!.trim().isNotEmpty)
          ? entry.payerName!
          : entry.category;
    }
    return (entry.paidToName != null && entry.paidToName!.trim().isNotEmpty)
        ? entry.paidToName!
        : entry.category;
  }

  @override
  Widget build(BuildContext context) {
    final amountColor =
        entry.isIncome ? context.colors.success : AppColors.error;
    final amountPrefix = entry.isIncome ? '' : '−';
    final dateStr = DateFormat('MMM d, yyyy').format(entry.entryDate);
    final showReimbursedBadge = !entry.isIncome && entry.isReimbursed;
    final showDisbursedBadge = entry.isIncome &&
        entry.disbursements != null &&
        entry.disbursements!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Spacing.cardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          border: Border.all(color: context.colors.border),
        ),
        padding: const EdgeInsets.all(Spacing.space16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Spacing.space4),
                  Text(
                    entry.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.footnote
                        .copyWith(color: context.colors.textMuted),
                  ),
                  const SizedBox(height: Spacing.space4),
                  Text(
                    dateStr,
                    style: AppTextStyles.footnote
                        .copyWith(color: context.colors.textMuted),
                  ),
                  if (showReimbursedBadge || showDisbursedBadge) ...[
                    const SizedBox(height: Spacing.space8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.space8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: context.colors.success),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        showReimbursedBadge ? 'Reimbursed' : 'Disbursed',
                        style: AppTextStyles.footnote.copyWith(
                          color: context.colors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Spacing.space12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$amountPrefix${entry.formattedAmount}',
                  style: AppTextStyles.callout.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Spacing.space8),
                Icon(AppIcons.forward,
                    size: 20, color: context.colors.textMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
