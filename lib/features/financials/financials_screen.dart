import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_icons.dart';
import '../../app/theme/brand_colors.dart';
import '../../app/theme/design_tokens.dart';
import '../bands/active_band_controller.dart';
import '../members/members_controller.dart';
import 'financials_controller.dart';
import 'financials_pdf_preview_screen.dart';
import 'models/financial_entry.dart';
import 'widgets/add_financial_entry_bottom_sheet.dart';
import 'widgets/financial_entry_details_bottom_sheet.dart';

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
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financialsProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          color: context.colors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Financials',
          style: AppTextStyles.displayMedium
              .copyWith(color: context.colors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.download,
                size: 20, color: AppColors.primary),
            tooltip: 'Export PDF',
            onPressed: state.isLoading
                ? null
                : () {
                    final bandName =
                        ref.read(activeBandProvider).activeBand?.name ?? 'Band';
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FinancialsPdfPreviewScreen(
                          entries: state.filteredEntries,
                          bandName: bandName,
                          dateFilter: state.dateFilter,
                          customStartDate: state.customStartDate,
                          customEndDate: state.customEndDate,
                          viewMode: state.viewMode,
                        ),
                      ),
                    );
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // Income / Expenses toggle
          _ViewModeToggle(
            current: state.viewMode,
            onChanged: (m) =>
                ref.read(financialsProvider.notifier).setViewMode(m),
          ),
          const SizedBox(height: Spacing.space12),
          // Date filter row
          _DateFilterRow(
            current: state.dateFilter,
            customStartDate: state.customStartDate,
            customEndDate: state.customEndDate,
            onChanged: (f) =>
                ref.read(financialsProvider.notifier).setDateFilter(f),
            onCustomRange: (start, end) => ref
                .read(financialsProvider.notifier)
                .setCustomDateRange(start, end),
          ),
          const SizedBox(height: Spacing.space16),
          // Entries list
          Expanded(
            child: state.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : state.error != null
                    ? _ErrorState(message: state.error!)
                    : _EntriesList(entries: state.filteredEntries),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Add entry',
        onPressed: state.isLoading
            ? null
            : () async {
                final notifier = ref.read(financialsProvider.notifier);
                final isIncome = state.viewMode == FinancialViewMode.income;
                final members = ref.read(membersProvider).members;
                await showAddFinancialEntrySheet(
                  context,
                  initialIsIncome: isIncome,
                  members: members,
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
                    );
                  },
                );
              },
        child: const Icon(Icons.add),
      ),
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
              start: DateTime(now.year, now.month, 1),
              end: now,
            ),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: Color(0xFF18181B),
            onSurface: Colors.white,
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
                              fontSize: 14,
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
// ENTRIES TABLE
// ---------------------------------------------------------------------------

class _EntriesList extends ConsumerWidget {
  const _EntriesList({required this.entries});

  final List<FinancialEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const _EmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute amount column width to fit the widest amount string
        final amountDataStyle =
            AppTextStyles.callout.copyWith(fontWeight: FontWeight.w600);
        final amountHeaderStyle = AppTextStyles.footnote
            .copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5);
        double maxAmountPx = _measureText('Amount', amountHeaderStyle);
        for (final e in entries) {
          final prefix = e.isIncome ? '' : '\u2212';
          final w =
              _measureText('$prefix${e.formattedAmount}', amountDataStyle);
          if (w > maxAmountPx) maxAmountPx = w;
        }
        // 4px cell padding each side + 8px buffer
        final amountColumnWidth = maxAmountPx + 16;

        final minWidth =
            amountColumnWidth + _kFixedColumnsWidth + Spacing.pagePadding * 2;
        final tableWidth =
            constraints.maxWidth < minWidth ? minWidth : constraints.maxWidth;
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      // Table header
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Spacing.pagePadding),
                        child:
                            _TableHeader(amountColumnWidth: amountColumnWidth),
                      ),
                      const Divider(height: 1),
                      // Rows
                      Expanded(
                        child: ListView.separated(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom +
                                Spacing.space16,
                          ),
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              indent: Spacing.pagePadding,
                              endIndent: Spacing.pagePadding),
                          itemBuilder: (context, index) {
                            return _EntryTableRow(
                              entry: entries[index],
                              amountColumnWidth: amountColumnWidth,
                              onTap: () => showFinancialEntryDetailsSheet(
                                context,
                                ref,
                                entries[index],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Total row — pinned outside the horizontal scroll view
            _TotalRow(entries: entries),
          ],
        );
      },
    );
  }
}

// Column widths: Amount is computed dynamically to fit content; all others are fixed.
const _kDateWidth = 110.0;
const _kTypeWidth = 110.0;
const _kFromWidth = 110.0;
const _kPaidToWidth = 110.0;
const _kDisbursedWidth = 96.0;
const _k1099Width = 50.0;
const _kFixedColumnsWidth = _kDateWidth +
    _kTypeWidth +
    _kFromWidth +
    _kPaidToWidth +
    _kDisbursedWidth +
    _k1099Width;

double _measureText(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: ui.TextDirection.ltr,
  )..layout();
  return painter.width;
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.amountColumnWidth});

  final double amountColumnWidth;

  @override
  Widget build(BuildContext context) {
    final borderSide = BorderSide(color: context.colors.border, width: 0.5);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: amountColumnWidth,
            child: _HeaderCell('Amount', borderSide: borderSide),
          ),
          SizedBox(
            width: _kDateWidth,
            child: _HeaderCell('Date', borderSide: borderSide),
          ),
          SizedBox(
            width: _kTypeWidth,
            child: _HeaderCell('Type', borderSide: borderSide),
          ),
          SizedBox(
            width: _kFromWidth,
            child: _HeaderCell('From', borderSide: borderSide),
          ),
          SizedBox(
            width: _kPaidToWidth,
            child: _HeaderCell('Paid To', borderSide: borderSide),
          ),
          SizedBox(
            width: _kDisbursedWidth,
            child: _HeaderCell('Disbursed',
                textAlign: TextAlign.center, borderSide: borderSide),
          ),
          SizedBox(
            width: _k1099Width,
            child: _HeaderCell('1099', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text,
      {this.textAlign = TextAlign.left, this.borderSide});
  final String text;
  final TextAlign textAlign;
  final BorderSide? borderSide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: Spacing.space8,
        horizontal: 4,
      ),
      decoration: borderSide != null
          ? BoxDecoration(border: Border(right: borderSide!))
          : null,
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.footnote.copyWith(
          color: context.colors.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EntryTableRow extends StatelessWidget {
  const _EntryTableRow({
    required this.entry,
    required this.amountColumnWidth,
    required this.onTap,
  });

  final FinancialEntry entry;
  final double amountColumnWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amountColor =
        entry.isIncome ? context.colors.success : AppColors.error;
    final amountPrefix = entry.isIncome ? '' : '−';
    final dateStr = DateFormat('MMM d, yyyy').format(entry.entryDate);
    final fromValue = entry.payerName ?? '';
    final paidToValue = entry.paidToName ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Amount — width computed to fit widest value
              SizedBox(
                width: amountColumnWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: context.colors.border, width: 0.5))),
                  child: Text(
                    '$amountPrefix${entry.formattedAmount}',
                    style: AppTextStyles.callout.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
              // Date
              SizedBox(
                width: _kDateWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: context.colors.border, width: 0.5))),
                  child: Text(
                    dateStr,
                    style: AppTextStyles.callout
                        .copyWith(color: context.colors.textPrimary),
                    maxLines: 2,
                  ),
                ),
              ),
              // Type
              SizedBox(
                width: _kTypeWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: context.colors.border, width: 0.5))),
                  child: Text(
                    entry.category,
                    style: AppTextStyles.callout
                        .copyWith(color: context.colors.textPrimary),
                    maxLines: 2,
                  ),
                ),
              ),
              // From
              SizedBox(
                width: _kFromWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: context.colors.border, width: 0.5))),
                  child: Text(
                    fromValue,
                    style: AppTextStyles.callout
                        .copyWith(color: context.colors.textSecondary),
                    maxLines: 2,
                  ),
                ),
              ),
              // Paid To
              SizedBox(
                width: _kPaidToWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: context.colors.border, width: 0.5))),
                  child: Text(
                    paidToValue,
                    style: AppTextStyles.callout
                        .copyWith(color: context.colors.textSecondary),
                    maxLines: 2,
                  ),
                ),
              ),
              // Disbursed
              SizedBox(
                width: _kDisbursedWidth,
                child: Container(
                  decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(
                              color: context.colors.border, width: 0.5))),
                  child: Center(
                    child: (entry.disbursements != null &&
                            entry.disbursements!.isNotEmpty)
                        ? const Icon(
                            AppIcons.success,
                            size: 16,
                            color: Colors.green,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              // 1099
              SizedBox(
                width: _k1099Width,
                child: Center(
                  child: entry.is1099Expected == true
                      ? const Icon(
                          AppIcons.check,
                          size: 16,
                          color: Colors.orange,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TOTAL ROW
// ---------------------------------------------------------------------------

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.entries});

  final List<FinancialEntry> entries;

  @override
  Widget build(BuildContext context) {
    final totalCents = entries.fold<int>(0, (sum, e) => sum + e.amountCents);
    final dollars = totalCents ~/ 100;
    final cents = totalCents % 100;
    final dollarsFormatted = NumberFormat('#,##0').format(dollars);
    final totalStr = '\$$dollarsFormatted.${cents.toString().padLeft(2, '0')}';

    final isIncome = entries.isNotEmpty && entries.first.isIncome;
    final amountColor = isIncome ? context.colors.success : AppColors.error;
    final entryLabel =
        entries.length == 1 ? '1 entry' : '${entries.length} entries';

    return Column(
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.pagePadding,
            vertical: Spacing.space12,
          ),
          child: Row(
            children: [
              Text(
                totalStr,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.callout.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: Spacing.space12),
              Expanded(
                child: Text(
                  'Total ($entryLabel)',
                  textAlign: TextAlign.right,
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: _kDisbursedWidth + _k1099Width),
            ],
          ),
        ),
      ],
    );
  }
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
