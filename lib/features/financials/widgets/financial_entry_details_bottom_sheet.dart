import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_icons.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../members/members_controller.dart';
import '../financials_controller.dart';
import '../models/financial_entry.dart';
import 'add_financial_entry_bottom_sheet.dart';

// ============================================================================
// FINANCIAL ENTRY DETAILS BOTTOM SHEET
// Read-only view of a single financial entry with an Edit action button.
// ============================================================================

Future<void> showFinancialEntryDetailsSheet(
  BuildContext context,
  WidgetRef ref,
  FinancialEntry entry,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FinancialEntryDetailsSheet(entry: entry, ref: ref),
  );
}

class _FinancialEntryDetailsSheet extends StatelessWidget {
  const _FinancialEntryDetailsSheet({
    required this.entry,
    required this.ref,
  });

  final FinancialEntry entry;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final amountColor =
        entry.isIncome ? context.colors.success : AppColors.error;
    final amountPrefix = entry.isIncome ? '+' : '−';
    final dateStr = DateFormat('MMMM d, yyyy').format(entry.entryDate);

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Spacing.cardRadius),
        ),
      ),
      padding: EdgeInsets.only(
        left: Spacing.pagePadding,
        right: Spacing.pagePadding,
        top: Spacing.space24,
        bottom: Spacing.space24 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: Spacing.space20),

          // Amount + type row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$amountPrefix${entry.formattedAmount}',
                      style: AppTextStyles.displayLarge
                          .copyWith(color: amountColor),
                    ),
                    const SizedBox(height: Spacing.space4),
                    _TypeBadge(label: entry.category),
                  ],
                ),
              ),
              if (entry.is1099Expected == true) const _Badge1099(),
            ],
          ),

          const SizedBox(height: Spacing.space24),
          const Divider(height: 1),
          const SizedBox(height: Spacing.space16),

          // Details rows
          _DetailRow(icon: AppIcons.calendar, label: 'Date', value: dateStr),
          const SizedBox(height: Spacing.space12),
          _DetailRow(
            icon: AppIcons.user,
            label: 'Payer',
            value: (entry.payerName != null && entry.payerName!.isNotEmpty)
                ? entry.payerName!
                : '—',
          ),
          const SizedBox(height: Spacing.space12),
          _DetailRow(
            icon: AppIcons.user,
            label: 'Paid To',
            value: (entry.paidToName != null && entry.paidToName!.isNotEmpty)
                ? entry.paidToName!
                : '—',
          ),
          if (entry.description != null && entry.description!.isNotEmpty) ...[
            const SizedBox(height: Spacing.space12),
            _DetailRow(
              icon: AppIcons.edit,
              label: 'Description',
              value: entry.description!,
            ),
          ],

          const SizedBox(height: Spacing.space24),

          // Edit button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                final notifier = ref.read(financialsProvider.notifier);
                final members = ref.read(membersProvider).members;
                await showAddFinancialEntrySheet(
                  context,
                  initialEntry: entry,
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
                    await notifier.updateEntry(
                      entryId: entry.id,
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
              icon: const Icon(AppIcons.edit, size: 18),
              label: const Text('Edit Entry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
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
// Detail row helper
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: context.colors.textMuted),
        const SizedBox(width: Spacing.space8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.footnote
                  .copyWith(color: context.colors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: AppTextStyles.callout
                  .copyWith(color: context.colors.textPrimary),
            ),
          ],
        ),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTextStyles.footnote.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Badge1099 extends StatelessWidget {
  const _Badge1099();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '1099',
        style: AppTextStyles.footnote.copyWith(
          color: Colors.orange,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
