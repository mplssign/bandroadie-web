import 'package:flutter/material.dart';

import '../../../app/models/gig.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/time_formatter.dart';
import '../../../components/ui/app_card.dart';

// ============================================================================
// CONFIRMED GIG CARD
// Figma: 271x126px, radius 8
// Animated rotating gradient border from blue (#2563EB) to rose (#F43F5E)
// Layout: Title 20px, Location gray-400 16px, Date 17px bold, Time gray-400
// ============================================================================

class ConfirmedGigCard extends StatefulWidget {
  final Gig gig;
  final String bandTimezone;
  final VoidCallback? onTap;
  final int index; // Used to create unique random speed per card

  const ConfirmedGigCard({
    super.key,
    required this.gig,
    required this.bandTimezone,
    this.onTap,
    this.index = 0,
  });

  @override
  State<ConfirmedGigCard> createState() => _ConfirmedGigCardState();
}

class _ConfirmedGigCardState extends State<ConfirmedGigCard> {
  bool _isPressed = false;

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
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3322C55E), // green-500 (#22C55E) @ 20%
              blurRadius: 6,
              spreadRadius: 4,
            ),
          ],
          child: Container(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 300),
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.space20,
              vertical: Spacing.space16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title - 20px Title3/Emphasized
                Text(
                  widget.gig.name,
                  style: AppTextStyles.title3.copyWith(
                    color: context.colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 2),

                // Location - 16px Callout/Regular, gray-400
                Text(
                  widget.gig.locationDisplay,
                  style: TextStyle(
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w400,
                    color: context.colors.textSecondary, // gray-400
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // Date - 17px Headline bold
                Text(
                  _formatFullDate(widget.gig.date),
                  style: TextStyle(
                    fontSize: AppFontSizes.headline,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 2),

                // Time - 16px Callout/Regular, gray-400
                Text(
                  TimeFormatter.formatRangeLocal(
                    widget.gig.startTime,
                    widget.gig.endTime,
                    widget.gig.date,
                    widget.bandTimezone,
                  ),
                  style: TextStyle(
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w400,
                    color: context.colors.textSecondary, // gray-400
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatFullDate(DateTime date) {
    final days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final months = [
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
}
