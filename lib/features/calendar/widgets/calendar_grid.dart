import 'dart:math';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../app/utils/time_formatter.dart';
import '../calendar_colors.dart';
import '../calendar_controller.dart';
import '../calendar_markers.dart';
import '../models/calendar_event.dart';

// ============================================================================
// CALENDAR GRID
// Monthly calendar grid powered by Forui's FCalendar.wheel component.
// - Native swipe navigation and month/year wheel picker
// - Today highlighted with rose accent
// - Event indicator lines under dates (stacked by start time)
// - Tap on date to show day detail bottom sheet
// ============================================================================

class CalendarGrid extends StatelessWidget {
  final FWheelCalendarController controller;
  final CalendarState calendarState;
  final void Function(DateTime date)? onDayTap;

  const CalendarGrid({
    super.key,
    required this.controller,
    required this.calendarState,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Compute responsive day cell size to fill container width
        // Subtract FCalendar's internal horizontal padding (12px left + 12px right = 24px total)
        // Clamp to 0 minimum to prevent negative width when drawer overlay restricts constraints
        final availableWidth =
            (constraints.maxWidth - 24).clamp(0.0, double.infinity);
        final cellWidth = availableWidth / 7;

        // Cell height reduced by 30% from Amendment 2 baseline (cellWidth + 11)
        // With 40px minimum to prevent clipping on smallest phones (360px width)
        final cellHeight = max((cellWidth + 11) * 0.7, 40.0);
        final daySize = Size(cellWidth, cellHeight);

        // Compute marker width proportional to cell size (80% of cell width)
        final markerWidth = cellWidth * 0.8;

        // Build custom style with computed daySize and day cell borders
        final customStyle = FCalendarStyleDelta.delta(
          dayPickerStyle: FCalendarDayPickerStyleDelta.delta(
            daySize: daySize,
            dayStyles: FVariantsDelta.delta([
              // Apply neutral border to all day cells
              FVariantOperation.all(
                FCalendarDayStyleDelta.delta(
                  background: DecorationDelta.boxDelta(
                    border: Border.all(
                      color: context.theme.colors.border,
                      width: 1,
                    ),
                  ),
                ),
              ),
              // Override with rose border for today specifically
              FVariantOperation.exact(
                {FCalendarDayVariant.today},
                FCalendarDayStyleDelta.delta(
                  background: DecorationDelta.boxDelta(
                    border: Border.all(
                      color: AppColors.primary,
                      width: 1,
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );

        return FCalendar.wheel(
          control: FWheelCalendarControl(controller: controller),
          selectionControl: FDateSelectionControl.none(),
          style: customStyle,
          dayBuilder: (context, styles, localizations, date, variants) =>
              _buildDayWithMarkers(
                  context, styles, localizations, date, variants, markerWidth),
          onDayPress: (date) => onDayTap?.call(date),
          fixedWeeks: false,
        );
      },
    );
  }

  /// Custom day builder that renders event markers below each day cell
  Widget _buildDayWithMarkers(
    BuildContext context,
    FCalendarDayStyles styles,
    FLocalizations localizations,
    DateTime date,
    Set<FCalendarDayVariant> variants,
    double markerWidth,
  ) {
    final markers = calendarState.getMarkers(date);
    final style = styles.resolve(variants);

    // Get events for this day, sorted by start time for marker ordering
    final eventsForDay = calendarState.eventsForDate(date);
    final sortedEventTypes = _getSortedEventTypes(eventsForDay, markers);

    return DecoratedBox(
      decoration: style.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Day number cell
          DecoratedBox(
            decoration: style.foreground,
            child: Center(
              child: Text(
                DateFormat.d(localizations.localeName).format(date),
                style: style.textStyle,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Event marker stack
          _buildMarkerStack(sortedEventTypes, markers, markerWidth),
        ],
      ),
    );
  }

  /// Get event types sorted by start time for marker ordering.
  /// Block outs always come last (they have no start time).
  List<CalendarEventType> _getSortedEventTypes(
    List<CalendarEvent> events,
    CalendarDayMarkers markers,
  ) {
    if (events.isEmpty && !markers.hasAny) {
      return [];
    }

    // Filter to only gigs and rehearsals (we handle block outs separately)
    final timedEvents = events.where((e) => e.isGig || e.isRehearsal).toList();

    // Sort by start time
    timedEvents.sort((a, b) {
      if (a.startTime.isEmpty && b.startTime.isEmpty) return 0;
      if (a.startTime.isEmpty) return 1;
      if (b.startTime.isEmpty) return -1;

      final aTime = TimeFormatter.parse(a.startTime);
      final bTime = TimeFormatter.parse(b.startTime);
      return aTime.totalMinutes.compareTo(bTime.totalMinutes);
    });

    // Build ordered list of unique event types
    final orderedTypes = <CalendarEventType>[];
    final seenTypes = <CalendarEventType>{};

    for (final event in timedEvents) {
      if (!seenTypes.contains(event.type)) {
        orderedTypes.add(event.type);
        seenTypes.add(event.type);
      }
    }

    // Block outs always come last
    if (markers.blockOut) {
      orderedTypes.add(CalendarEventType.blockOut);
    }

    return orderedTypes;
  }

  /// Build stacked horizontal markers under the date.
  /// Order is based on start time - earliest event appears first (top).
  /// Block outs always come last since they have no specific time.
  Widget _buildMarkerStack(
    List<CalendarEventType> sortedEventTypes,
    CalendarDayMarkers markers,
    double markerWidth,
  ) {
    final activeMarkers = <Widget>[];

    // Add markers for confirmed events based on sorted order
    for (final eventType in sortedEventTypes) {
      switch (eventType) {
        case CalendarEventType.gig:
          activeMarkers.add(_buildGigMarker(markerWidth));
          break;
        case CalendarEventType.rehearsal:
          activeMarkers.add(_buildRehearsalMarker(markerWidth));
          break;
        case CalendarEventType.blockOut:
          activeMarkers
              .add(_buildBlockOutMarker(markers.blockOutCount, markerWidth));
          break;
      }
    }

    // Potential markers always append after confirmed — orange, one per type.
    if (markers.potentialGig && !markers.gig) {
      activeMarkers.add(_buildPotentialMarker(markerWidth));
    }
    if (markers.potentialRehearsal && !markers.rehearsal) {
      activeMarkers.add(_buildPotentialMarker(markerWidth));
    }
    // If both potential types are on the same day and neither confirmed type
    // is present, only show one orange line (they share a color).
    if (markers.potentialGig &&
        markers.potentialRehearsal &&
        !markers.gig &&
        !markers.rehearsal) {
      // The two adds above already added two entries — remove the duplicate.
      if (activeMarkers.length >= 2) activeMarkers.removeLast();
    }

    if (activeMarkers.isEmpty) {
      return const SizedBox(height: 14);
    }

    return SizedBox(
      height: 14,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          for (int i = 0; i < activeMarkers.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            activeMarkers[i],
          ],
        ],
      ),
    );
  }

  /// Build the gig marker (green)
  Widget _buildGigMarker(double width) {
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: CalendarColors.gigIndicator,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  /// Build the rehearsal marker (blue)
  Widget _buildRehearsalMarker(double width) {
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: CalendarColors.rehearsalIndicator,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  /// Build the potential event marker (orange — shared by potential gigs and
  /// potential rehearsals, matching the lighter gradient on potential cards).
  Widget _buildPotentialMarker(double width) {
    return Container(
      width: width,
      height: 3,
      decoration: BoxDecoration(
        color: CalendarColors.potentialIndicator,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  /// Build the block out marker, split into segments if multiple members
  Widget _buildBlockOutMarker(int blockOutCount, double markerWidth) {
    final count = blockOutCount > 0 ? blockOutCount : 1;

    if (count == 1) {
      // Single block out - full width line
      return Container(
        width: markerWidth,
        height: 3,
        decoration: BoxDecoration(
          color: CalendarColors.blockOutIndicator,
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
    }

    // Multiple block outs - split into segments with 1px gaps
    const gapWidth = 1.0;
    final totalGaps = count - 1;
    final segmentWidth = (markerWidth - (gapWidth * totalGaps)) / count;

    return SizedBox(
      width: markerWidth,
      height: 3,
      child: Row(
        children: [
          for (int i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: gapWidth),
            Container(
              width: segmentWidth,
              height: 3,
              decoration: BoxDecoration(
                color: CalendarColors.blockOutIndicator,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
