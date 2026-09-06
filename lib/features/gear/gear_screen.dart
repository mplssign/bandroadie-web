import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';

import '../bands/active_band_controller.dart';
import '../members/member_vm.dart';
import '../members/members_controller.dart';
import '../members/permissions/band_permissions_provider.dart';
import '../setlists/widgets/back_only_app_bar.dart';
import 'gear_controller.dart';
import 'models/gear_item.dart';
import 'widgets/gear_form_sheet.dart';

// ============================================================================
// GEAR SCREEN
// Top-level screen displaying band gear inventory as a table.
// Structural mirror of FinancialsScreen — same shell, filter row set, table.
// ============================================================================

class GearScreen extends ConsumerStatefulWidget {
  const GearScreen({super.key});

  @override
  ConsumerState<GearScreen> createState() => _GearScreenState();
}

class _GearScreenState extends ConsumerState<GearScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final bandId = ref.read(activeBandProvider).activeBandId;
      if (bandId != null) {
        ref.read(gearProvider.notifier).load(bandId);
        ref.read(membersProvider.notifier).loadMembers(bandId);
      }
    });
  }

  Future<void> _openForm({GearItem? item, required bool canManageGear}) async {
    final bandId = ref.read(activeBandProvider).activeBandId;
    if (bandId == null) return;

    final result = await GearFormSheet.show(
      context,
      bandId: bandId,
      item: item,
      canManageGear: canManageGear,
    );

    if (result == true && mounted) {
      await ref.read(gearProvider.notifier).refresh(bandId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gearProvider);
    final members = ref.watch(membersProvider).members;
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final canManageGear = permissionsAsync.when(
      data: (p) => p.canManageGear,
      loading: () => false,
      error: (_, __) => false,
    );

    ref.listen<ActiveBandState>(activeBandProvider, (previous, next) {
      if (previous?.activeBandId != next.activeBandId) {
        ref.read(gearProvider.notifier).reset();
        if (next.activeBandId != null) {
          ref.read(gearProvider.notifier).load(next.activeBandId);
          ref.read(membersProvider.notifier).loadMembers(next.activeBandId);
        }
      }
    });

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                BackOnlyAppBar(
                  onBack: () => Navigator.of(context).pop(),
                ),
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
                                'Gear',
                                style: AppTextStyles.pageTitle.copyWith(
                                    color: context.colors.textPrimary),
                              ),
                            ),
                            if (canManageGear)
                              TextButton.icon(
                                onPressed: state.isLoading
                                    ? null
                                    : () => _openForm(
                                          canManageGear: true,
                                        ),
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
                      // Owner filter toggle (All / Band-owned / Member-owned)
                      _OwnerFilterToggle(
                        current: state.ownerFilter,
                        onChanged: (f) =>
                            ref.read(gearProvider.notifier).setOwnerFilter(f),
                      ),
                      const SizedBox(height: Spacing.space12),
                      // Date filter row
                      _DateFilterRow(
                        current: state.dateFilter,
                        customStartDate: state.customStartDate,
                        customEndDate: state.customEndDate,
                        onChanged: (f) =>
                            ref.read(gearProvider.notifier).setDateFilter(f),
                        onCustomRange: (start, end) => ref
                            .read(gearProvider.notifier)
                            .setCustomDateRange(start, end),
                      ),
                      const SizedBox(height: Spacing.space16),
                      // Items list
                      Expanded(
                        child: state.isLoading && !state.hasItems
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.primary),
                              )
                            : state.error != null && !state.hasItems
                                ? _ErrorState(message: state.error!)
                                : _GearEntriesList(
                                    items: state.filteredItems,
                                    members: members,
                                    canManageGear: canManageGear,
                                    onTapItem: (item) => _openForm(
                                      item: item,
                                      canManageGear: canManageGear,
                                    ),
                                    onAdd: canManageGear
                                        ? () => _openForm(
                                              canManageGear: true,
                                            )
                                        : null,
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

  final GearDateFilter current;
  final ValueChanged<GearDateFilter> onChanged;
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
    if (current == GearDateFilter.custom &&
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
            active: current == GearDateFilter.allTime,
            onTap: () => onChanged(GearDateFilter.allTime),
          ),
          const SizedBox(width: Spacing.space8),
          _FilterChip(
            label: 'This Year',
            active: current == GearDateFilter.thisYear,
            onTap: () => onChanged(GearDateFilter.thisYear),
          ),
          const SizedBox(width: Spacing.space8),
          _FilterChip(
            label: 'This Month',
            active: current == GearDateFilter.thisMonth,
            onTap: () => onChanged(GearDateFilter.thisMonth),
          ),
          const SizedBox(width: Spacing.space8),
          _FilterChip(
            label: _customLabel,
            active: current == GearDateFilter.custom,
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
// OWNER FILTER TOGGLE (All / Band-owned / Member-owned)
// Structural mirror of financials' _ViewModeToggle, extended to 3 segments.
// ---------------------------------------------------------------------------

class _OwnerFilterToggle extends StatelessWidget {
  const _OwnerFilterToggle({required this.current, required this.onChanged});

  final GearOwnerFilter current;
  final ValueChanged<GearOwnerFilter> onChanged;

  static const _modes = [
    GearOwnerFilter.all,
    GearOwnerFilter.band,
    GearOwnerFilter.member,
  ];
  static const _labels = ['All', 'Band-owned', 'Member-owned'];

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
// GEAR ENTRIES TABLE
// ---------------------------------------------------------------------------

class _GearEntriesList extends StatelessWidget {
  const _GearEntriesList({
    required this.items,
    required this.members,
    required this.canManageGear,
    required this.onTapItem,
    required this.onAdd,
  });

  final List<GearItem> items;
  final List<MemberVM> members;
  final bool canManageGear;
  final ValueChanged<GearItem> onTapItem;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyState(canManageGear: canManageGear, onAdd: onAdd);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute price column width to fit the widest price string
        final priceDataStyle =
            AppTextStyles.callout.copyWith(fontWeight: FontWeight.w600);
        final priceHeaderStyle = AppTextStyles.footnote
            .copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.5);
        double maxPricePx = _measureText('Price', priceHeaderStyle);
        for (final item in items) {
          final label = _priceLabel(item);
          final w = _measureText(label, priceDataStyle);
          if (w > maxPricePx) maxPricePx = w;
        }
        // 4px cell padding each side + 8px buffer
        final priceColumnWidth = maxPricePx + 16;

        final minWidth = _kMinNameWidth +
            _kFixedColumnsWidth +
            priceColumnWidth +
            Spacing.pagePadding * 2;
        final tableWidth =
            constraints.maxWidth < minWidth ? minWidth : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                // Table header
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.pagePadding),
                  child: _TableHeader(priceColumnWidth: priceColumnWidth),
                ),
                const Divider(height: 1),
                // Rows
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom +
                          Spacing.space16,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        indent: Spacing.pagePadding,
                        endIndent: Spacing.pagePadding),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _GearTableRow(
                        item: item,
                        members: members,
                        priceColumnWidth: priceColumnWidth,
                        onTap: () => onTapItem(item),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Column widths: Name is Expanded; Price is computed dynamically; others fixed.
const _kMinNameWidth = 140.0;
const _kPurchasedOnWidth = 110.0;
const _kPurchasedFromWidth = 110.0;
const _kOwnerWidth = 110.0;
const _kFixedColumnsWidth =
    _kPurchasedOnWidth + _kPurchasedFromWidth + _kOwnerWidth;

double _measureText(String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: ui.TextDirection.ltr,
  )..layout();
  return painter.width;
}

String _priceLabel(GearItem item) {
  if (item.priceCents == null) return '';
  final fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$');
  return fmt.format(item.priceCents! / 100);
}

String _ownerLabel(GearItem item, List<MemberVM> members) {
  if (item.ownerType == GearOwnerType.band) return 'Band';
  final ownerId = item.ownerUserId;
  if (ownerId == null) return 'Member';
  MemberVM? member;
  for (final m in members) {
    if (m.userId == ownerId) {
      member = m;
      break;
    }
  }
  if (member == null) return 'Member';
  final first = (member.firstName ?? '').trim();
  final last = (member.lastName ?? '').trim();
  if (first.isNotEmpty && last.isNotEmpty) {
    return '$first ${last[0]}.';
  }
  if (first.isNotEmpty) return first;
  if (last.isNotEmpty) return '${last[0]}.';
  return member.name;
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.priceColumnWidth});

  final double priceColumnWidth;

  @override
  Widget build(BuildContext context) {
    final borderSide = BorderSide(color: context.colors.border);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _HeaderCell('Name', borderSide: borderSide)),
          SizedBox(
            width: _kPurchasedOnWidth,
            child: _HeaderCell('Purchased On', borderSide: borderSide),
          ),
          SizedBox(
            width: _kPurchasedFromWidth,
            child: _HeaderCell('Purchased From', borderSide: borderSide),
          ),
          SizedBox(
            width: _kOwnerWidth,
            child: _HeaderCell('Owner', borderSide: borderSide),
          ),
          SizedBox(
            width: priceColumnWidth,
            child: const _HeaderCell('Price', textAlign: TextAlign.right),
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

class _GearTableRow extends StatelessWidget {
  const _GearTableRow({
    required this.item,
    required this.members,
    required this.priceColumnWidth,
    required this.onTap,
  });

  final GearItem item;
  final List<MemberVM> members;
  final double priceColumnWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateStr = item.purchasedOn != null
        ? DateFormat('MMM d, y').format(item.purchasedOn!)
        : '';
    final purchasedFromValue = item.purchasedFrom ?? '';
    final ownerValue = _ownerLabel(item, members);
    final priceValue = _priceLabel(item);
    final borderSide = BorderSide(color: context.colors.border);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name — Expanded
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  decoration: BoxDecoration(border: Border(right: borderSide)),
                  child: Text(
                    item.name,
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                  ),
                ),
              ),
              // Purchased On
              SizedBox(
                width: _kPurchasedOnWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  decoration: BoxDecoration(border: Border(right: borderSide)),
                  child: Text(
                    dateStr,
                    style: AppTextStyles.callout
                        .copyWith(color: context.colors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Purchased From
              SizedBox(
                width: _kPurchasedFromWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  decoration: BoxDecoration(border: Border(right: borderSide)),
                  child: Text(
                    purchasedFromValue,
                    style: AppTextStyles.callout
                        .copyWith(color: context.colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Owner
              SizedBox(
                width: _kOwnerWidth,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  decoration: BoxDecoration(border: Border(right: borderSide)),
                  child: Text(
                    ownerValue,
                    style: AppTextStyles.callout
                        .copyWith(color: context.colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // Price — dynamic width, right-aligned
              SizedBox(
                width: priceColumnWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: Spacing.space16, horizontal: 4),
                  child: Text(
                    priceValue,
                    textAlign: TextAlign.right,
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  ),
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
// EMPTY + ERROR STATES
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canManageGear, required this.onAdd});

  final bool canManageGear;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              AppIcons.library,
              size: 48,
              color: context.colors.textMuted,
            ),
            const SizedBox(height: Spacing.space16),
            Text(
              'No gear yet',
              style: AppTextStyles.displayMedium
                  .copyWith(color: context.colors.textPrimary),
            ),
            const SizedBox(height: Spacing.space8),
            Text(
              'Add your first item to keep\nthe band battle-ready.',
              textAlign: TextAlign.center,
              style:
                  AppTextStyles.body.copyWith(color: context.colors.textMuted),
            ),
            if (canManageGear && onAdd != null) ...[
              const SizedBox(height: Spacing.space24),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(AppIcons.add, size: 18),
                label: const Text('Add Gear'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
            ],
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
