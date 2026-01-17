import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/models/rehearsal.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/utils/time_formatter.dart';

// ============================================================================
// REHEARSAL CARD
// Figma: 361x111px, radius 16, border 1px gray-400 (#9ca3af)
// Gradient fill: blue-600 (#2563EB) to purple-600 (#9333EA) - ANIMATED
// "Next Rehearsal" title, date/time, location with pin, "Setlist" link,
// "New Songs" chip (92x32, radius 16, accent bg)
//
// Background opacity is reduced (~60%) to visually de-emphasize rehearsals
// vs confirmed gigs. This makes them feel "secondary" while still active.
// ============================================================================

class RehearsalCard extends StatefulWidget {
  final Rehearsal rehearsal;
  final VoidCallback? onTap;
  final String? setlistName;

  const RehearsalCard({
    super.key,
    required this.rehearsal,
    this.onTap,
    this.setlistName,
  });

  @override
  State<RehearsalCard> createState() => _RehearsalCardState();
}

class _RehearsalCardState extends State<RehearsalCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _gradientController;
  late Animation<Alignment> _beginAlignment;
  late Animation<Alignment> _endAlignment;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _gradientController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat(reverse: true);

    _beginAlignment =
        TweenSequence<Alignment>([
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

    _endAlignment =
        TweenSequence<Alignment>([
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
    // Wrap with AnimatedScale for subtle press feedback on tap
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap ?? () {},
      child: AnimatedScale(
        scale: _isPressed ? AnimScales.cardPressed : 1.0,
        duration: AppDurations.fast,
        curve: AppCurves.ease,
        child: AnimatedBuilder(
          animation: _gradientController,
          builder: (context, child) {
            return Container(
              height: Spacing.rehearsalCardHeight, // 130px
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: _beginAlignment.value,
                  end: _endAlignment.value,
                  colors: [
                    const Color(
                      0xFF2563EB,
                    ).withOpacity(0.60), // blue-600 (reduced)
                    const Color(
                      0xFF9333EA,
                    ).withOpacity(0.60), // purple-600 (reduced)
                  ],
                ),
                borderRadius: BorderRadius.circular(Spacing.cardRadius), // 16px
                border: Border.all(
                  color: const Color(0xFF9CA3AF), // gray-400
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(Spacing.space16),
              child: child,
            );
          },
          child: Column(
            children: [
              // Top row: Title on left, Date/Time on right
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left content - Title
                  Expanded(
                    child: Text(
                      'Next Rehearsal',
                      style: GoogleFonts.dmSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  // Right side - date/time (2 lines)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatDateLine(widget.rehearsal.date),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTimeLine(widget.rehearsal),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: Spacing.space16),

              // Bottom row: Two equal-width columns
              // Left column: Location | Right column: Setlist label + badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left column (50% width) - Location with pin icon
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.rehearsal.location,
                            style: AppTextStyles.footnote.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Right side - Setlist badge only (right-aligned, sized to content)
                  if (widget.rehearsal.setlistId != null &&
                      widget.setlistName != null)
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(
                          Spacing.chipRadius,
                        ), // 16px
                      ),
                      child: Center(
                        child: Text(
                          widget.setlistName!,
                          style: AppTextStyles.footnote.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Format the date line (e.g., "Mon Jan 1, 2026")
  String _formatDateLine(DateTime date) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${days[date.weekday - 1]} ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Format the time line using TimeFormatter for start-end range
  String _formatTimeLine(Rehearsal rehearsal) {
    return TimeFormatter.formatRange(rehearsal.startTime, rehearsal.endTime);
  }
}
