import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/models/rehearsal.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_animations.dart';
import '../../../components/ui/app_button.dart';
import '../../setlists/setlist_detail_screen.dart';
import '../../setlists/setlists_screen.dart' show setlistsProvider;
import 'rehearsal_notes_sheet.dart';

class ViewRehearsalDrawer extends ConsumerWidget {
  final Rehearsal rehearsal;
  final String bandTimezone;
  final bool canEdit;
  final VoidCallback onEdit;

  const ViewRehearsalDrawer({
    super.key,
    required this.rehearsal,
    required this.bandTimezone,
    required this.canEdit,
    required this.onEdit,
  });

  static Future<void> show(
    BuildContext context, {
    required Rehearsal rehearsal,
    required String bandTimezone,
    required bool canEdit,
    required VoidCallback onEdit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ViewRehearsalDrawer(
        rehearsal: rehearsal,
        bandTimezone: bandTimezone,
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

  String _formatRecurrenceIndicator() {
    if (!rehearsal.isRecurring) return '';

    final buffer = StringBuffer();

    // Frequency
    switch (rehearsal.recurrenceFrequency) {
      case 'weekly':
        buffer.write('Weekly');
        break;
      case 'biweekly':
        buffer.write('Biweekly');
        break;
      case 'monthly':
        buffer.write('Monthly');
        break;
      default:
        buffer.write('Recurring');
    }

    // Days
    if (rehearsal.recurrenceDays != null &&
        rehearsal.recurrenceDays!.isNotEmpty) {
      buffer.write(' · ');
      final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      final days = rehearsal.recurrenceDays!
          .map((index) => dayNames[index % 7])
          .join('/');
      buffer.write(days);
    }

    // Until date
    if (rehearsal.recurrenceUntil != null) {
      buffer.write(' until ');
      final until = rehearsal.recurrenceUntil!;
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      buffer.write('${months[until.month - 1]} ${until.day}');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setlistsState = ref.watch(setlistsProvider);
    final setlistName = rehearsal.setlistId != null
        ? setlistsState.setlists
            .where((s) => s.id == rehearsal.setlistId)
            .firstOrNull
            ?.name
        : null;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
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

          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Spacing.space16),

                  // Header block: date + time + location
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Day/date
                        Text(
                          _formatFullDate(rehearsal.date),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: context.colors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: Spacing.space4),
                        // Time range
                        Text(
                          rehearsal.timeRange,
                          style: AppTextStyles.title3.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                        // Location (if present)
                        if (rehearsal.location.isNotEmpty) ...[
                          const SizedBox(height: Spacing.space4),
                          Text(
                            rehearsal.location,
                            style: AppTextStyles.callout.copyWith(
                              color: context.colors.textMuted,
                            ),
                          ),
                        ],
                        // Recurrence indicator (if recurring)
                        if (rehearsal.isRecurring) ...[
                          const SizedBox(height: Spacing.space4),
                          Text(
                            _formatRecurrenceIndicator(),
                            style: AppTextStyles.callout.copyWith(
                              color: context.colors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: Spacing.space16),
                  const Divider(height: 1),

                  // Detail rows
                  if (rehearsal.setlistId != null && setlistName != null)
                    _DetailRow(
                      label: 'Setlist',
                      value: setlistName,
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(
                        fadeSlideRoute(
                          page: SetlistDetailScreen(
                            setlistId: rehearsal.setlistId!,
                            setlistName: setlistName,
                          ),
                        ),
                      ),
                    ),

                  if (rehearsal.notes != null && rehearsal.notes!.isNotEmpty)
                    _DetailRow(
                      label: 'Notes',
                      value: '',
                      showChevron: true,
                      onTap: () => RehearsalNotesSheet.show(
                        context,
                        notes: rehearsal.notes!,
                      ),
                    ),

                  const SizedBox(height: Spacing.space24),
                ],
              ),
            ),
          ),

          // Footer
          Padding(
            padding: EdgeInsets.only(
              left: Spacing.pagePadding,
              right: Spacing.pagePadding,
              bottom: MediaQuery.of(context).padding.bottom + Spacing.space16,
            ),
            child: Column(
              children: [
                AppButton(
                  label: 'Done',
                  fullWidth: true,
                  onPressed: () => Navigator.of(context).pop(),
                  variant: AppButtonVariant.primary,
                ),
                if (canEdit) ...[
                  const SizedBox(height: Spacing.space12),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: 'Edit',
                      variant: AppButtonVariant.text,
                      onPressed: () => _handleEdit(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showChevron;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.label,
    required this.value,
    this.showChevron = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
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
          const SizedBox(width: Spacing.space8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.start,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: Spacing.space4),
            Icon(
              AppIcons.forward,
              size: 16,
              color: context.colors.textMuted,
            ),
          ],
        ],
      ),
    );

    return Column(
      children: [
        onTap != null ? InkWell(onTap: onTap, child: row) : row,
        Divider(height: 1, color: context.colors.border),
      ],
    );
  }
}
