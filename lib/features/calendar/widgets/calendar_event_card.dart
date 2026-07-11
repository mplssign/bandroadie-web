import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/time_formatter.dart';
import '../models/calendar_event.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// CALENDAR EVENT CARD
// Displays an event (gig or rehearsal) in the "This Month's Events" list.
// Figma: #334155 border, deep blue date badge on left, title/time/location on right
// ============================================================================

class CalendarEventCard extends StatefulWidget {
  final CalendarEvent event;
  final String bandTimezone;
  final VoidCallback? onTap;

  const CalendarEventCard({
    super.key,
    required this.event,
    required this.bandTimezone,
    this.onTap,
  });

  @override
  State<CalendarEventCard> createState() => _CalendarEventCardState();
}

class _CalendarEventCardState extends State<CalendarEventCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _scaleController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  /// Returns event-type-specific accent color for the indicator dot
  /// Confirmed gigs use green (matching calendar indicator), potential gigs use orange,
  /// rehearsals use blue, block outs use rose
  Color get _dotColor {
    if (widget.event.isBlockOut) {
      return AppColors.primary; // Rose for block outs
    }
    if (widget.event.isGig) {
      // Potential gigs use orange, confirmed gigs use green
      return widget.event.isPotentialGig
          ? const Color(0xFFF97316) // Orange for potential
          : const Color(
              0xFF65A30D,
            ); // Green for confirmed (matches MarkerColors.gigColor)
    }
    return const Color(0xFF3B82F6); // Blue for rehearsals
  }

  /// Check if this is a multi-day block out with an end date
  bool get _isMultiDayBlockOut {
    return widget.event.isBlockOut && widget.event.endDate != null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _scaleAnimation.value, child: child);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border.all(
              color: context.colors.border,
              width: StandardCardBorder.width,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // Date badge - deep blue/indigo background
                _DateBadge(
                  date: widget.event.date,
                  eventType: widget.event.type,
                ),

                // Divider
                Container(width: 1, color: context.colors.border),

                // Event details
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.space12,
                      vertical: Spacing.space12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Event title with type indicator
                        Row(
                          children: [
                            // Event type indicator dot
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.event.displayTitle,
                                style: AppTextStyles.calloutEmphasized,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // For block outs: show reason (if any); for other events: show time range
                        if (widget.event.isBlockOut) ...[
                          if (widget.event.notes?.isNotEmpty ?? false)
                            Text(
                              widget.event.notes!,
                              style: AppTextStyles.callout.copyWith(
                                color: context.colors.textSecondary,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ] else ...[
                          // Time - 12-hour format, converted to viewer's local timezone
                          Text(
                            TimeFormatter.formatRangeLocal(
                              widget.event.startTime,
                              widget.event.endTime,
                              widget.event.date,
                              widget.bandTimezone,
                            ),
                            style: AppTextStyles.callout.copyWith(
                              color: context.colors.textSecondary,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // For multi-day block outs: show end date badge instead of chevron
                // For other events: show chevron
                if (_isMultiDayBlockOut) ...[
                  Container(width: 1, color: context.colors.border),
                  _DateBadge(
                    date: widget.event.endDate!,
                    eventType: widget.event.type,
                  ),
                ] else ...[
                  // Chevron
                  Padding(
                    padding: const EdgeInsets.only(right: Spacing.space12),
                    child: Icon(
                      AppIcons.forward,
                      color: context.colors.textMuted,
                      size: 24,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Deep blue/indigo date badge matching Figma design
/// Month: uppercase, large and bold (e.g., JAN)
/// Day: very large, bold
class _DateBadge extends StatelessWidget {
  final DateTime date;
  final CalendarEventType eventType;

  const _DateBadge({required this.date, required this.eventType});

  String get _monthAbbreviation {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return months[date.month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateBoxColor =
        isDark ? const Color(0xFF1E3A5F) : const Color(0xFF333333);

    return Container(
      width: 68,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: dateBoxColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Month abbreviation - UPPERCASE, large and bold (e.g., "JAN")
          Text(
            _monthAbbreviation,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),

          // Day number - very large, bold (e.g., "22")
          Text(
            '${date.day}',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
