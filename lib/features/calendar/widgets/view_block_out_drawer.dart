import 'package:flutter/material.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../../../components/ui/collapsing_sheet_scaffold.dart';
import '../../../components/ui/sheet_footer.dart';
import '../models/calendar_event.dart';

class ViewBlockOutDrawer extends StatelessWidget {
  final BlockOutSpan existingBlockOut;
  final bool canEdit;
  final VoidCallback onEdit;

  const ViewBlockOutDrawer({
    super.key,
    required this.existingBlockOut,
    required this.canEdit,
    required this.onEdit,
  });

  static Future<void> show(
    BuildContext context, {
    required BlockOutSpan existingBlockOut,
    required bool canEdit,
    required VoidCallback onEdit,
  }) {
    return showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ViewBlockOutDrawer(
        existingBlockOut: existingBlockOut,
        canEdit: canEdit,
        onEdit: onEdit,
      ),
    );
  }

  void _handleEdit(BuildContext context) {
    Navigator.of(context).pop();
    onEdit();
  }

  String _formatFullDate(DateTime date) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${days[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.95,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: CollapsingSheetScaffold(
        dragHandle: Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: Spacing.space16),

              // Header block: date or date range
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pagePadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Start date (or single date if not multi-day)
                    Text(
                      _formatFullDate(existingBlockOut.startDate),
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: context.colors.textPrimary,
                              ),
                    ),
                    // End date subtitle (if multi-day)
                    if (existingBlockOut.isMultiDay) ...[
                      const SizedBox(height: Spacing.space4),
                      Text(
                        'Through ${_formatFullDate(existingBlockOut.endDate)}',
                        style: AppTextStyles.title3.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: Spacing.space16),
              const Divider(height: 1),

              // Detail rows
              if (existingBlockOut.reason.isNotEmpty)
                _DetailRow(
                  label: 'Reason',
                  value: existingBlockOut.reason,
                ),

              const SizedBox(height: Spacing.space24),
            ],
          ),
        ),
        footer: SheetFooter(
          primaryLabel: 'Done',
          onPrimary: () => Navigator.of(context).pop(),
          cancelLabel: 'Edit',
          onCancel: canEdit ? () => _handleEdit(context) : null,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.pagePadding,
            vertical: Spacing.space12,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                child: Text(
                  label,
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
