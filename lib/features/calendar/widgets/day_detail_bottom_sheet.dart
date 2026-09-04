import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/collapsing_sheet_scaffold.dart';
import '../../../components/ui/sheet_footer.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../models/calendar_event.dart';
import 'calendar_event_card.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// DAY DETAIL BOTTOM SHEET
// Shows events for a specific date when user taps on a calendar day.
// ============================================================================

class DayDetailBottomSheet extends StatelessWidget {
  final DateTime date;
  final List<CalendarEvent> events;
  final String bandTimezone;
  final void Function(CalendarEvent event)? onEventTap;
  final VoidCallback? onAddEvent;

  const DayDetailBottomSheet({
    super.key,
    required this.date,
    required this.events,
    required this.bandTimezone,
    this.onEventTap,
    this.onAddEvent,
  });

  /// Shows the bottom sheet modally
  static Future<void> show(
    BuildContext context, {
    required DateTime date,
    required List<CalendarEvent> events,
    required String bandTimezone,
    void Function(CalendarEvent event)? onEventTap,
    VoidCallback? onAddEvent,
  }) {
    return showAppBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DayDetailBottomSheet(
        date: date,
        events: events,
        bandTimezone: bandTimezone,
        onEventTap: onEventTap,
        onAddEvent: onAddEvent,
      ),
    );
  }

  String get _formattedDate {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
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

    final dayName = days[date.weekday - 1];
    final monthName = months[date.month - 1];
    return '$dayName, $monthName ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: context.colors.background,
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
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: Spacing.space16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pagePadding,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_formattedDate, style: AppTextStyles.title3),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: context.colors.background,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          AppIcons.close,
                          color: context.colors.textSecondary,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.space8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pagePadding,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${events.length} ${events.length == 1 ? 'event' : 'events'}',
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Spacing.space16),
            ],
          ),
          body: events.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Spacing.pagePadding),
                  child: Center(
                    child: Text(
                      'No events on this day',
                      style: AppTextStyles.callout.copyWith(
                        color: context.colors.textMuted,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.pagePadding,
                  ),
                  itemCount: events.length,
                  separatorBuilder: (_, index) =>
                      const SizedBox(height: Spacing.space12),
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return CalendarEventCard(
                      event: event,
                      bandTimezone: bandTimezone,
                      onTap: () => onEventTap?.call(event),
                    );
                  },
                ),
          footer: onAddEvent != null
              ? SheetFooter(
                  primaryLabel: 'Add Event',
                  primaryIcon: AppIcons.add,
                  onPrimary: onAddEvent,
                )
              : null,
        ),
    );
  }
}
