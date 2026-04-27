import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/models/gig.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/time_formatter.dart';

// ============================================================================
// POTENTIAL GIG CARD
// Figma: 361x130px, orange→rose gradient (ANIMATED), border gray-400, radius 16
// Title "Potential Gig", venue name, location, date/time right-aligned
// Tap into card to view availability details per member
//
// Background opacity is reduced (~60%) to visually de-emphasize potential gigs
// vs confirmed gigs. This makes them feel "secondary" while still active.
// ============================================================================

class PotentialGigCard extends StatefulWidget {
  final Gig gig;
  final String bandTimezone;
  final VoidCallback? onTap;

  /// Optional fixed width for horizontal scroll mode
  final double? width;

  const PotentialGigCard({
    super.key,
    required this.gig,
    required this.bandTimezone,
    this.onTap,
    this.width,
  });

  @override
  State<PotentialGigCard> createState() => _PotentialGigCardState();
}

class _PotentialGigCardState extends State<PotentialGigCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _gradientController;
  late Animation<Alignment> _beginAlignment;
  late Animation<Alignment> _endAlignment;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _gradientController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    )..repeat(reverse: true);

    _beginAlignment = TweenSequence<Alignment>([
      TweenSequenceItem(
        tween: Tween(begin: Alignment.centerLeft, end: Alignment.topLeft),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Alignment.topLeft, end: Alignment.topCenter),
        weight: 1,
      ),
    ]).animate(
      CurvedAnimation(parent: _gradientController, curve: Curves.easeInOut),
    );

    _endAlignment = TweenSequence<Alignment>([
      TweenSequenceItem(
        tween: Tween(
          begin: Alignment.centerRight,
          end: Alignment.bottomRight,
        ),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: Alignment.bottomRight,
          end: Alignment.bottomCenter,
        ),
        weight: 1,
      ),
    ]).animate(
      CurvedAnimation(parent: _gradientController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _gradientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gradientAlpha =
        Theme.of(context).brightness == Brightness.light ? 1.0 : 0.60;
    // Wrap with AnimatedScale for subtle press feedback on tap
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? AnimScales.cardPressed : 1.0,
        duration: AppDurations.fast,
        curve: AppCurves.ease,
        child: AnimatedBuilder(
          animation: _gradientController,
          builder: (context, child) {
            return Container(
              width: widget.width,
              constraints: const BoxConstraints(minHeight: 130),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: _beginAlignment.value,
                  end: _endAlignment.value,
                  colors: [
                    const Color(
                      0xFFF77800,
                    ).withValues(alpha: gradientAlpha), // orange
                    const Color(
                      0xFFE11D48,
                    ).withValues(alpha: gradientAlpha), // rose-600
                  ],
                ),
                borderRadius: BorderRadius.circular(Spacing.cardRadius), // 16px
                border: Border.all(
                  color: context.colors.textSecondary, // gray-400
                  width: 1,
                ),
              ),
              child: child,
            );
          },
          child: Stack(
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: Title on left, Date/Time on right
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side - Title
                        Text(
                          'Potential Gig',
                          style: GoogleFonts.dmSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Right side - date/time (or "Multiple options" for multi-date gigs)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                widget.gig.isMultiDate
                                    ? 'Multiple options'
                                    : _formatShortDate(widget.gig.date),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.gig.isMultiDate
                                    ? _formatMultiDateRange(widget.gig.allDates)
                                    : TimeFormatter.formatRangeLocal(
                                        widget.gig.startTime,
                                        widget.gig.endTime,
                                        widget.gig.date,
                                        widget.bandTimezone,
                                      ),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Event name - full width
                    Text(
                      widget.gig.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),

                    const SizedBox(height: 2),

                    // City - left aligned under name
                    Text(
                      widget.gig.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),

                    // Bottom padding
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shorter date format for compact card layout: "Feb 6, 2026"
  String _formatShortDate(DateTime date) {
    final months = [
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Format a range of dates for multi-date potential gigs
  /// Same month: "Jul 2026"
  /// Different months: "Jul - Aug, 2026"
  /// Different years: "Dec 2025 - Jan 2026"
  String _formatMultiDateRange(List<DateTime> dates) {
    if (dates.isEmpty) return '';

    final months = [
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

    final sortedDates = List<DateTime>.from(dates)..sort();
    final firstDate = sortedDates.first;
    final lastDate = sortedDates.last;

    final firstMonth = months[firstDate.month - 1];
    final lastMonth = months[lastDate.month - 1];

    if (firstDate.year == lastDate.year) {
      if (firstDate.month == lastDate.month) {
        // Same month: "Jul 2026"
        return '$firstMonth ${firstDate.year}';
      } else {
        // Different months, same year: "Jul - Aug, 2026"
        return '$firstMonth - $lastMonth, ${firstDate.year}';
      }
    } else {
      // Different years: "Dec 2025 - Jan 2026"
      return '$firstMonth ${firstDate.year} - $lastMonth ${lastDate.year}';
    }
  }
}
