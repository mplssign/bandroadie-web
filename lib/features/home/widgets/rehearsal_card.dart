import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/models/rehearsal.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/time_formatter.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// REHEARSAL CARD
//
// Two visual variants driven by rehearsal.isPotential:
//
// CONFIRMED — blue→purple gradient, "Next Rehearsal" title, location + setlist.
//
// POTENTIAL — orange→rose gradient (matches PotentialGigCard), chip label,
//             day/date/time, location, inline YES/NO availability buttons.
// ============================================================================

class RehearsalCard extends StatefulWidget {
  final Rehearsal rehearsal;
  final String bandTimezone;
  final VoidCallback? onTap;
  final String? setlistName;

  // Potential-only props
  /// Current user's own response: 'yes', 'no', or null.
  final String? currentUserResponse;

  /// Called with 'yes', 'no', or null (for unselect) when the user taps a response button.
  final Future<void> Function(String? response)? onRespond;

  const RehearsalCard({
    super.key,
    required this.rehearsal,
    required this.bandTimezone,
    this.onTap,
    this.setlistName,
    this.currentUserResponse,
    this.onRespond,
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
  bool _isSubmitting = false;
  String? _localResponse;

  @override
  void initState() {
    super.initState();
    _localResponse = widget.currentUserResponse;

    _gradientController = AnimationController(
      duration: const Duration(seconds: 6),
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
        tween: Tween(begin: Alignment.centerRight, end: Alignment.bottomRight),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: Alignment.bottomRight, end: Alignment.bottomCenter),
        weight: 1,
      ),
    ]).animate(
      CurvedAnimation(parent: _gradientController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(RehearsalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUserResponse != widget.currentUserResponse) {
      _localResponse = widget.currentUserResponse;
    }
  }

  @override
  void dispose() {
    _gradientController.dispose();
    super.dispose();
  }

  Future<void> _handleResponse(String response) async {
    if (_isSubmitting || widget.onRespond == null) return;

    // If tapping the same button that's already selected, unselect (delete)
    if (_localResponse == response) {
      HapticFeedback.selectionClick();
      setState(() {
        _isSubmitting = true;
        _localResponse = null; // optimistic clear
      });
      try {
        await widget.onRespond!(null); // null means delete
      } catch (_) {
        if (mounted)
          setState(() => _localResponse = widget.currentUserResponse);
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
      return;
    }

    // Normal selection flow
    HapticFeedback.selectionClick();
    setState(() {
      _isSubmitting = true;
      _localResponse = response;
    });
    try {
      await widget.onRespond!(response);
    } catch (_) {
      if (mounted) setState(() => _localResponse = widget.currentUserResponse);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.rehearsal.isPotential
        ? _buildPotentialCard(context)
        : _buildConfirmedCard(context);
  }

  // ---------------------------------------------------------------------------
  // POTENTIAL VARIANT — matches PotentialGigCard layout
  // ---------------------------------------------------------------------------

  Widget _buildPotentialCard(BuildContext context) {
    final gradientAlpha =
        Theme.of(context).brightness == Brightness.light ? 1.0 : 0.60;

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
              constraints:
                  BoxConstraints(minHeight: Spacing.potentialGigCardHeight),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: _beginAlignment.value,
                  end: _endAlignment.value,
                  colors: [
                    const Color(0xFFF77800).withValues(alpha: gradientAlpha),
                    const Color(0xFFE11D48).withValues(alpha: gradientAlpha),
                  ],
                ),
                borderRadius: BorderRadius.circular(Spacing.cardRadius),
                border: Border.all(
                  color: context.colors.textSecondary,
                  width: 1,
                ),
              ),
              child: child,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Chip label with cream background - full width
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF8F5),
                    borderRadius: BorderRadius.circular(Spacing.cardRadius),
                  ),
                  child: Text(
                    'POTENTIAL REHEARSAL',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF4A1F0F),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Date (with recurring frequency prefix if applicable)
                Text(
                  _formatDateWithRecurrence(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: widget.rehearsal.isRecurring &&
                            widget.rehearsal.recurrenceFrequency != null
                        ? 17
                        : 21,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),

                const SizedBox(height: 8),

                // Time
                Text(
                  _formatTimeLine(widget.rehearsal),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                // Location
                Text(
                  widget.rehearsal.location.isNotEmpty
                      ? widget.rehearsal.location
                      : 'No location specified',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),

                const Spacer(),

                // Full-width YES/NO buttons
                Row(
                  children: [
                    Expanded(
                      child: _FullWidthAvailabilityButton(
                        label: 'NO',
                        isSelected: _localResponse == 'no',
                        isPositive: false,
                        isSubmitting: _isSubmitting,
                        onTap: () => _handleResponse('no'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _FullWidthAvailabilityButton(
                        label: 'YES',
                        isSelected: _localResponse == 'yes',
                        isPositive: true,
                        isSubmitting: _isSubmitting,
                        onTap: () => _handleResponse('yes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONFIRMED VARIANT — unchanged blue→purple card
  // ---------------------------------------------------------------------------

  Widget _buildConfirmedCard(BuildContext context) {
    final gradientAlpha =
        Theme.of(context).brightness == Brightness.light ? 1.0 : 0.60;

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
              constraints: BoxConstraints(
                minHeight: Spacing.rehearsalCardHeight,
              ),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: _beginAlignment.value,
                  end: _endAlignment.value,
                  colors: [
                    const Color(0xFF2563EB).withValues(alpha: gradientAlpha),
                    const Color(0xFF9333EA).withValues(alpha: gradientAlpha),
                  ],
                ),
                borderRadius: BorderRadius.circular(Spacing.cardRadius),
                border: Border.all(
                  color: context.colors.textSecondary,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(Spacing.space16),
              child: child,
            );
          },
          child: Column(
            children: [
              // Top row: Title + Date/Time
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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

              // Bottom: Location + Setlist
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.location,
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
                  if (widget.rehearsal.setlistId != null &&
                      widget.setlistName != null)
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(Spacing.chipRadius),
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

  // ---------------------------------------------------------------------------
  // Formatters
  // ---------------------------------------------------------------------------

  String _formatFullDate(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDateLine(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
    return '${days[date.weekday - 1]} ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTimeLine(Rehearsal rehearsal) {
    return TimeFormatter.formatRangeLocal(
      rehearsal.startTime,
      rehearsal.endTime,
      rehearsal.date,
      widget.bandTimezone,
    );
  }

  String _formatDateWithRecurrence() {
    if (widget.rehearsal.isRecurring &&
        widget.rehearsal.recurrenceFrequency != null) {
      final frequency = widget.rehearsal.recurrenceFrequency!;
      final frequencyText =
          frequency.substring(0, 1).toUpperCase() + frequency.substring(1);
      return '$frequencyText starting ${_formatFullDate(widget.rehearsal.date)}';
    }
    return _formatFullDate(widget.rehearsal.date);
  }
}

/// Full-width availability button for potential rehearsal cards
class _FullWidthAvailabilityButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isPositive;
  final bool isSubmitting;
  final VoidCallback onTap;

  const _FullWidthAvailabilityButton({
    required this.label,
    required this.isSelected,
    required this.isPositive,
    required this.isSubmitting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color borderColor;
    Color textColor;

    if (isSelected) {
      // Filled state when selected
      if (isPositive) {
        // YES - filled green
        backgroundColor = const Color(0xFF10B981);
        borderColor = const Color(0xFF10B981);
        textColor = Colors.white;
      } else {
        // NO - filled red
        backgroundColor = const Color(0xFFEF4444);
        borderColor = const Color(0xFFEF4444);
        textColor = Colors.white;
      }
    } else {
      // Outlined state when not selected
      backgroundColor = Colors.transparent;
      borderColor = Colors.white.withValues(alpha: 0.5);
      textColor = Colors.white;
    }

    return GestureDetector(
      onTap: isSubmitting ? null : onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        height: 48,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textColor,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
