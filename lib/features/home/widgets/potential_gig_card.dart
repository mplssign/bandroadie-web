import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/models/gig.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/time_formatter.dart';

// ============================================================================
// POTENTIAL GIG CARD
// Chip label + day/date/time + location + inline YES/NO availability buttons.
// Orange→rose animated gradient, 300px wide in horizontal scroll.
// ============================================================================

class PotentialGigCard extends StatefulWidget {
  final Gig gig;
  final String bandTimezone;
  final VoidCallback? onTap;

  /// The current user's own response: 'yes', 'no', or null (not responded).
  final String? currentUserResponse;

  /// Called with 'yes', 'no', or null (for unselect) when the user taps a response button.
  final Future<void> Function(String? response)? onRespond;

  /// Optional fixed width for horizontal scroll mode.
  final double? width;

  const PotentialGigCard({
    super.key,
    required this.gig,
    required this.bandTimezone,
    this.onTap,
    this.currentUserResponse,
    this.onRespond,
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
  bool _isSubmitting = false;

  // Optimistic local state — updated instantly on tap
  String? _localResponse;

  @override
  void initState() {
    super.initState();
    _localResponse = widget.currentUserResponse;

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
  void didUpdateWidget(PotentialGigCard oldWidget) {
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
      _localResponse = response; // optimistic
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
              width: widget.width,
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
                    'POTENTIAL GIG',
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

                // Large Date
                Text(
                  _formatFullDate(widget.gig.date),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),

                const SizedBox(height: 8),

                // Time
                Text(
                  widget.gig.isMultiDate
                      ? 'Multiple dates'
                      : TimeFormatter.formatRangeLocal(
                          widget.gig.startTime,
                          widget.gig.endTime,
                          widget.gig.date,
                          widget.bandTimezone,
                        ),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                // Venue/Location
                Text(
                  widget.gig.location.isNotEmpty
                      ? widget.gig.location
                      : 'No venue specified',
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
}

// ============================================================================
// Shared sub-widgets (exported for use by rehearsal_card.dart)
// ============================================================================

/// White-outline chip label.
class PotentialChip extends StatelessWidget {
  final String label;
  const PotentialChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }
}

/// Full-width availability button for potential cards
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

/// "Your Availability  [NO] [YES]" row — kept for backward compatibility if needed elsewhere.
class AvailabilityRow extends StatelessWidget {
  final String? currentResponse;
  final bool isSubmitting;
  final Future<void> Function(String) onRespond;

  const AvailabilityRow({
    super.key,
    required this.currentResponse,
    required this.isSubmitting,
    required this.onRespond,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Your Availability',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const Spacer(),
        AvailabilityButton(
          label: 'NO',
          isSelected: currentResponse == 'no',
          isPositive: false,
          isSubmitting: isSubmitting,
          onTap: () => onRespond('no'),
        ),
        const SizedBox(width: 6),
        AvailabilityButton(
          label: 'YES',
          isSelected: currentResponse == 'yes',
          isPositive: true,
          isSubmitting: isSubmitting,
          onTap: () => onRespond('yes'),
        ),
      ],
    );
  }
}

/// Compact YES/NO pill button. Exported for rehearsal card reuse.
class AvailabilityButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isPositive;
  final bool isSubmitting;
  final VoidCallback onTap;

  const AvailabilityButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isPositive,
    required this.isSubmitting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = isPositive ? AppColors.success : AppColors.error;

    return GestureDetector(
      onTap: isSubmitting ? null : onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? baseColor.withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? baseColor : Colors.white.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
