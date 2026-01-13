import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../app/utils/time_formatter.dart';
import '../calendar_controller.dart';
import '../calendar_markers.dart';
import '../models/calendar_event.dart';

// ============================================================================
// CALENDAR GRID
// Monthly calendar grid matching Figma design.
// - 7 columns (Su-Sa)
// - Today highlighted with rose accent
// - Event indicator lines under dates (stacked: blockout=rose, gig=green, rehearsal=blue)
// - Horizontal swipe for month navigation with physics-based animation
// - Tap on date to show day detail bottom sheet
// ============================================================================

/// Color constants for event indicators (from Figma design)
class CalendarColors {
  CalendarColors._();

  /// Blue indicator for rehearsals (#2563EB)
  static const Color rehearsalIndicator = Color(MarkerColors.rehearsalColor);

  /// Green indicator for gigs (#65A30D)
  static const Color gigIndicator = Color(MarkerColors.gigColor);

  /// Rose indicator for block outs (#F43F5E)
  static const Color blockOutIndicator = Color(MarkerColors.blockOutColor);

  /// Date cell background
  static const Color dateCellBg = Color(0xFF2C2C2C);

  /// Calendar container border
  static const Color containerBorder = Color(0xFF444444);
}

class CalendarGrid extends StatefulWidget {
  final DateTime selectedMonth;
  final CalendarState calendarState;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final void Function(DateTime date)? onDayTap;

  const CalendarGrid({
    super.key,
    required this.selectedMonth,
    required this.calendarState,
    required this.onPreviousMonth,
    required this.onNextMonth,
    this.onDayTap,
  });

  @override
  State<CalendarGrid> createState() => _CalendarGridState();
}

class _CalendarGridState extends State<CalendarGrid>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  double _dragOffset = 0;
  bool _isDragging = false;

  // Threshold to trigger month change (% of width)
  static const _swipeThreshold = 0.2;
  // Velocity threshold to trigger month change on fling
  static const _velocityThreshold = 300.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _isDragging = true;
    _animationController.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dx;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _isDragging = false;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final width = context.size?.width ?? 300;
    final dragPercentage = _dragOffset.abs() / width;

    bool shouldNavigate = false;
    bool goToPrevious = false;

    // Check if we should navigate based on drag distance or velocity
    if (dragPercentage > _swipeThreshold ||
        velocity.abs() > _velocityThreshold) {
      shouldNavigate = true;
      goToPrevious = _dragOffset > 0 || velocity > _velocityThreshold;
    }

    if (shouldNavigate) {
      // Animate out and trigger navigation
      final targetOffset = goToPrevious ? width : -width;
      _animateToOffset(targetOffset, velocity, () {
        if (goToPrevious) {
          widget.onPreviousMonth();
        } else {
          widget.onNextMonth();
        }
        // Reset offset immediately after navigation
        setState(() {
          _dragOffset = 0;
        });
      });
    } else {
      // Snap back to center
      _animateToOffset(0, velocity, null);
    }
  }

  void _animateToOffset(
    double targetOffset,
    double velocity,
    VoidCallback? onComplete,
  ) {
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 300, damping: 25),
      _dragOffset,
      targetOffset,
      velocity / 1000,
    );

    _animationController.reset();
    _animationController.animateWith(simulation);

    late VoidCallback listener;
    listener = () {
      setState(() {
        _dragOffset =
            _animationController.value *
            (targetOffset - (_animationController.value > 0 ? 0 : _dragOffset));
      });

      if (_animationController.status == AnimationStatus.completed) {
        _animationController.removeListener(listener);
        onComplete?.call();
      }
    };

    // Use simpler tween animation for more predictable behavior
    final tween = Tween<double>(begin: _dragOffset, end: targetOffset);
    _animationController.duration = const Duration(milliseconds: 200);
    _animationController.reset();

    Animation<double> animation = tween.animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    void animationListener() {
      setState(() {
        _dragOffset = animation.value;
      });
    }

    void statusListener(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _animationController.removeListener(animationListener);
        _animationController.removeStatusListener(statusListener);
        onComplete?.call();
      }
    }

    _animationController.addListener(animationListener);
    _animationController.addStatusListener(statusListener);
    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Container(
        padding: const EdgeInsets.all(Spacing.space16),
        decoration: BoxDecoration(
          color: AppColors.scaffoldBg,
          border: Border.all(color: CalendarColors.containerBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Month header with navigation arrows
            _MonthHeader(
              selectedMonth: widget.selectedMonth,
              onPreviousMonth: widget.onPreviousMonth,
              onNextMonth: widget.onNextMonth,
            ),
            const SizedBox(height: Spacing.space16),

            // Day of week headers
            const _DayHeaders(),
            const SizedBox(height: Spacing.space8),

            // Calendar days grid with swipe offset
            ClipRect(
              child: Transform.translate(
                offset: Offset(_dragOffset, 0),
                child: AnimatedOpacity(
                  opacity: _isDragging ? 0.7 : 1.0,
                  duration: const Duration(milliseconds: 100),
                  child: _CalendarDaysGrid(
                    selectedMonth: widget.selectedMonth,
                    calendarState: widget.calendarState,
                    onDayTap: widget.onDayTap,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime selectedMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  const _MonthHeader({
    required this.selectedMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  String get _monthYearText {
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
    return '${months[selectedMonth.month - 1]} ${selectedMonth.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Previous month button
        GestureDetector(
          onTap: onPreviousMonth,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.chevron_left_rounded,
              color: AppColors.textPrimary,
              size: 24,
            ),
          ),
        ),

        // Month and year
        Text(
          _monthYearText,
          style: AppTextStyles.headline.copyWith(color: AppColors.textPrimary),
        ),

        // Next month button
        GestureDetector(
          onTap: onNextMonth,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textPrimary,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}

class _DayHeaders extends StatelessWidget {
  const _DayHeaders();

  static const _days = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _days.map((day) {
        return SizedBox(
          width: 40,
          child: Center(
            child: Text(
              day,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary.withValues(alpha: 0.7),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CalendarDaysGrid extends StatelessWidget {
  final DateTime selectedMonth;
  final CalendarState calendarState;
  final void Function(DateTime date)? onDayTap;

  const _CalendarDaysGrid({
    required this.selectedMonth,
    required this.calendarState,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(
      selectedMonth.year,
      selectedMonth.month + 1,
      0,
    ).day;
    final firstDayOfMonth = DateTime(
      selectedMonth.year,
      selectedMonth.month,
      1,
    );
    final startingWeekday = firstDayOfMonth.weekday % 7; // Sunday = 0

    final today = DateTime.now();
    final isCurrentMonth =
        today.year == selectedMonth.year && today.month == selectedMonth.month;

    // Build list of day cells
    final cells = <Widget>[];

    // Empty cells for days before the first day of the month
    for (var i = 0; i < startingWeekday; i++) {
      cells.add(const SizedBox(width: 40, height: 56));
    }

    // Day cells
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(selectedMonth.year, selectedMonth.month, day);
      final isToday = isCurrentMonth && today.day == day;

      // Get markers from the single source of truth
      final markers = calendarState.getMarkers(date);
      final hasAnyMarker = markers.hasAny;

      // Get events for this day, sorted by start time for marker ordering
      final eventsForDay = calendarState.eventsForDate(date);
      final sortedEventTypes = _getSortedEventTypes(eventsForDay, markers);

      cells.add(
        _DayCell(
          day: day,
          date: date,
          isToday: isToday,
          hasBlockOut: markers.blockOut,
          blockOutCount: markers.blockOutCount,
          hasGig: markers.gig,
          hasRehearsal: markers.rehearsal,
          sortedEventTypes: sortedEventTypes,
          onTap: hasAnyMarker
              ? () => onDayTap?.call(date)
              : () => onDayTap?.call(date),
        ),
      );
    }

    // Build rows (7 days per row)
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      final rowCells = cells.sublist(
        i,
        i + 7 > cells.length ? cells.length : i + 7,
      );

      // Pad last row if needed
      while (rowCells.length < 7) {
        rowCells.add(const SizedBox(width: 40, height: 56));
      }

      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: rowCells,
        ),
      );

      if (i + 7 < cells.length) {
        rows.add(const SizedBox(height: Spacing.space4));
      }
    }

    return Column(children: rows);
  }

  /// Get event types sorted by start time for marker ordering.
  /// Block outs always come last (they have no start time).
  List<CalendarEventType> _getSortedEventTypes(
    List<CalendarEvent> events,
    CalendarDayMarkers markers,
  ) {
    // If no events, return empty list
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
}

class _DayCell extends StatelessWidget {
  final int day;
  final DateTime date;
  final bool isToday;
  final bool hasBlockOut;
  final int blockOutCount;
  final bool hasGig;
  final bool hasRehearsal;
  final List<CalendarEventType> sortedEventTypes;
  final VoidCallback? onTap;

  const _DayCell({
    required this.day,
    required this.date,
    required this.isToday,
    required this.hasBlockOut,
    this.blockOutCount = 0,
    required this.hasGig,
    required this.hasRehearsal,
    this.sortedEventTypes = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasAnyMarker = hasBlockOut || hasGig || hasRehearsal;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 40,
        height: 56, // 40px cell + 16px for stacked indicator area
        child: Column(
          children: [
            // Date cell
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isToday ? AppColors.accent : CalendarColors.dateCellBg,
                borderRadius: BorderRadius.circular(8),
                border: hasAnyMarker && !isToday
                    ? Border.all(
                        color: AppColors.accent.withValues(alpha: 0.3),
                        width: 1,
                      )
                    : null,
              ),
              child: Center(
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                    color: const Color(0xFFF5F5F5),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 2),

            // Stacked event indicators (order: blockout, gig, rehearsal)
            _buildMarkerStack(),
          ],
        ),
      ),
    );
  }

  /// Build stacked horizontal markers under the date.
  /// Order is based on start time - earliest event appears first (top).
  /// Block outs always come last since they have no specific time.
  Widget _buildMarkerStack() {
    final activeMarkers = <Widget>[];

    // If we have sorted event types, use that order
    if (sortedEventTypes.isNotEmpty) {
      for (final eventType in sortedEventTypes) {
        switch (eventType) {
          case CalendarEventType.gig:
            activeMarkers.add(_buildGigMarker());
            break;
          case CalendarEventType.rehearsal:
            activeMarkers.add(_buildRehearsalMarker());
            break;
          case CalendarEventType.blockOut:
            activeMarkers.add(_buildBlockOutMarker());
            break;
        }
      }
    } else {
      // Fallback to old behavior if sortedEventTypes is empty
      if (hasBlockOut) {
        activeMarkers.add(_buildBlockOutMarker());
      }
      if (hasGig) {
        activeMarkers.add(_buildGigMarker());
      }
      if (hasRehearsal) {
        activeMarkers.add(_buildRehearsalMarker());
      }
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
  Widget _buildGigMarker() {
    return Container(
      width: 35,
      height: 3,
      decoration: BoxDecoration(
        color: CalendarColors.gigIndicator,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  /// Build the rehearsal marker (blue)
  Widget _buildRehearsalMarker() {
    return Container(
      width: 35,
      height: 3,
      decoration: BoxDecoration(
        color: CalendarColors.rehearsalIndicator,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  /// Build the block out marker, split into segments if multiple members
  Widget _buildBlockOutMarker() {
    final count = blockOutCount > 0 ? blockOutCount : 1;

    if (count == 1) {
      // Single block out - full width line
      return Container(
        width: 35,
        height: 3,
        decoration: BoxDecoration(
          color: CalendarColors.blockOutIndicator,
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
    }

    // Multiple block outs - split into segments with 1px gaps
    const totalWidth = 35.0;
    const gapWidth = 1.0;
    final totalGaps = count - 1;
    final segmentWidth = (totalWidth - (gapWidth * totalGaps)) / count;

    return SizedBox(
      width: 35,
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
