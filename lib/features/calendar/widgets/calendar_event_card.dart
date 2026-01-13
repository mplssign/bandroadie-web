import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/calendar_event.dart';

// ============================================================================
// CALENDAR EVENT CARD
// Displays an event (gig or rehearsal) in the "This Month's Events" list.
// Figma: #334155 border, deep blue date badge on left, title/time/location on right
// ============================================================================

/// Figma-spec border color (strict)
const _kCardBorderColor = Color(0xFF334155);

class CalendarEventCard extends StatefulWidget {
  final CalendarEvent event;
  final VoidCallback? onTap;

  const CalendarEventCard({super.key, required this.event, this.onTap});

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
      return const Color(0xFFF43F5E); // Rose for block outs
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
            color: AppColors.scaffoldBg,
            border: Border.all(color: _kCardBorderColor, width: 1.5),
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
                Container(width: 1, color: AppColors.borderMuted),

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
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ] else ...[
                          // Time - 12-hour format (stored as "7:30 PM - 10:00 PM" in DB)
                          Text(
                            widget.event.timeRange,
                            style: AppTextStyles.callout.copyWith(
                              color: AppColors.textSecondary,
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
                  Container(width: 1, color: AppColors.borderMuted),
                  _DateBadge(
                    date: widget.event.endDate!,
                    eventType: widget.event.type,
                  ),
                ] else ...[
                  // Chevron
                  Padding(
                    padding: const EdgeInsets.only(right: Spacing.space12),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
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
/// Weekday: uppercase, large and bold (e.g., SAT)
/// Day: very large, bold
class _DateBadge extends StatelessWidget {
  final DateTime date;
  final CalendarEventType eventType;

  const _DateBadge({required this.date, required this.eventType});

  String get _dayOfWeek {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    // Deep blue/indigo background for date badge per Figma
    const dateBoxColor = Color(0xFF1E3A5F);

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
          // Day of week - UPPERCASE, large and bold (e.g., "SAT")
          Text(
            _dayOfWeek,
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
