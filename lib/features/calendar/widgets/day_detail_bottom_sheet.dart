import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../components/ui/brand_action_button.dart';
import '../models/calendar_event.dart';
import 'calendar_event_card.dart';

// ============================================================================
// DAY DETAIL BOTTOM SHEET
// Shows events for a specific date when user taps on a calendar day.
// ============================================================================

class DayDetailBottomSheet extends StatelessWidget {
  final DateTime date;
  final List<CalendarEvent> events;
  final void Function(CalendarEvent event)? onEventTap;
  final VoidCallback? onAddEvent;

  const DayDetailBottomSheet({
    super.key,
    required this.date,
    required this.events,
    this.onEventTap,
    this.onAddEvent,
  });

  /// Shows the bottom sheet modally
  static Future<void> show(
    BuildContext context, {
    required DateTime date,
    required List<CalendarEvent> events,
    void Function(CalendarEvent event)? onEventTap,
    VoidCallback? onAddEvent,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DayDetailBottomSheet(
        date: date,
        events: events,
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: Spacing.space16),

          // Date header
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(_formattedDate, style: AppTextStyles.title3),
                ),
                // Close button
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.scaffoldBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: Spacing.space8),

          // Events count
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${events.length} ${events.length == 1 ? 'event' : 'events'}',
                style: AppTextStyles.callout.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),

          const SizedBox(height: Spacing.space16),

          // Events list
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(Spacing.pagePadding),
                    child: Center(
                      child: Text(
                        'No events on this day',
                        style: AppTextStyles.callout.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
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
                        onTap: () => onEventTap?.call(event),
                      );
                    },
                  ),
          ),

          // Add Event button
          if (onAddEvent != null) ...[
            const SizedBox(height: Spacing.space16),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.pagePadding,
              ),
              child: BrandActionButton(
                label: 'Add Event',
                onPressed: onAddEvent,
                icon: Icons.add_rounded,
                fullWidth: true,
              ),
            ),
          ],

          // Bottom padding
          SizedBox(height: Spacing.space24 + bottomPadding),
        ],
      ),
    );
  }
}
