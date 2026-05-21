import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/models/gig.dart';
import '../../../app/models/gig_date.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/time_formatter.dart';

// ============================================================================
// POTENTIAL GIG CARD
// Chip label + day/date/time + venue+city + inline YES/NO availability buttons.
// Multi-date gigs: left/right chevrons to navigate between dates.
// Orange→rose animated gradient, 340px wide in horizontal scroll.
// ============================================================================

class PotentialGigCard extends StatefulWidget {
  final Gig gig;
  final String bandTimezone;
  final VoidCallback? onTap;

  /// Current user's responses keyed by gigDateId (null = primary date).
  final Map<String?, String?>? perDateUserResponses;

  /// Called with response ('yes'/'no') or null (unselect), and the gigDateId
  /// (null = primary date) for the currently displayed date.
  final Future<void> Function(String? response, String? gigDateId)? onRespondForDate;

  /// Optional fixed width for horizontal scroll mode.
  final double? width;

  const PotentialGigCard({
    super.key,
    required this.gig,
    required this.bandTimezone,
    this.onTap,
    this.perDateUserResponses,
    this.onRespondForDate,
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

  /// Current date index within _sortedDates.
  int _currentDateIndex = 0;

  /// Optimistic per-date response map: gigDateId? → 'yes'/'no'/null.
  Map<String?, String?> _localResponses = {};

  // ---------------------------------------------------------------------------
  // Date helpers
  // ---------------------------------------------------------------------------

  /// All dates (primary + additional) sorted chronologically.
  /// Each entry is (date, gigDateId?): gigDateId is null for the primary date.
  List<(DateTime, String?)> get _sortedDates {
    final primary = (widget.gig.date, null as String?);
    final additional = widget.gig.additionalDates
        .map<(DateTime, String?)>((GigDate d) => (d.date, d.id))
        .toList();
    final all = [primary, ...additional];
    all.sort((a, b) => a.$1.compareTo(b.$1));
    return all;
  }

  DateTime get _currentDate => _sortedDates[_currentDateIndex].$1;
  String? get _currentGigDateId => _sortedDates[_currentDateIndex].$2;
  String? get _currentDateResponse => _localResponses[_currentGigDateId];
  bool get _isMultiDate => widget.gig.isMultiDate;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _localResponses = Map.from(widget.perDateUserResponses ?? {});

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
    if (oldWidget.perDateUserResponses != widget.perDateUserResponses) {
      _localResponses = Map.from(widget.perDateUserResponses ?? {});
    }
  }

  @override
  void dispose() {
    _gradientController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Response handling
  // ---------------------------------------------------------------------------

  Future<void> _handleResponse(String response) async {
    final gigDateId = _currentGigDateId;
    final currentResponse = _localResponses[gigDateId];
    if (_isSubmitting || widget.onRespondForDate == null) return;

    if (currentResponse == response) {
      // Tapping selected button → unselect (delete)
      HapticFeedback.selectionClick();
      setState(() {
        _isSubmitting = true;
        _localResponses = {..._localResponses, gigDateId: null};
      });
      try {
        await widget.onRespondForDate!(null, gigDateId);
      } catch (_) {
        if (mounted) {
          setState(() {
            _localResponses = {
              ..._localResponses,
              gigDateId: widget.perDateUserResponses?[gigDateId],
            };
          });
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
      return;
    }

    // Normal selection
    HapticFeedback.selectionClick();
    setState(() {
      _isSubmitting = true;
      _localResponses = {..._localResponses, gigDateId: response};
    });
    try {
      await widget.onRespondForDate!(response, gigDateId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _localResponses = {
            ..._localResponses,
            gigDateId: widget.perDateUserResponses?[gigDateId],
          };
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final gradientAlpha =
        Theme.of(context).brightness == Brightness.light ? 1.0 : 0.50;
    final dates = _sortedDates;
    final canGoPrev = _currentDateIndex > 0;
    final canGoNext = _currentDateIndex < dates.length - 1;

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
                color: const Color(0xFFF54900).withValues(alpha: gradientAlpha),
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
                // Chip label — cream background, full width
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF8F5),
                    borderRadius: BorderRadius.circular(Spacing.cardRadius),
                  ),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'POTENTIAL GIG',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF4A1F0F),
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (_isMultiDate)
                          TextSpan(
                            text: ': Multiple Dates',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF4A1F0F),
                              letterSpacing: 0.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Current date
                Text(
                  _formatFullDate(_currentDate),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),

                const SizedBox(height: 8),

                // Time (always actual time regardless of multi-date)
                Text(
                  TimeFormatter.formatRangeLocal(
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

                // Venue name + city: "First Avenue - Minneapolis"
                // Name truncates; city is never truncated.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.gig.name.isNotEmpty) ...[
                      Flexible(
                        child: Text(
                          widget.gig.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (widget.gig.location.isNotEmpty)
                        Text(
                          ' - ${widget.gig.location}',
                          style: GoogleFonts.dmSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                    ] else
                      Flexible(
                        child: Text(
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
                      ),
                  ],
                ),

                const Spacer(),

                // Button row: [← nav] [NO] [YES] [nav →] when multi-date,
                // else just [NO] [YES].
                if (_isMultiDate)
                  Row(
                    children: [
                      _DateNavButton(
                        icon: Icons.chevron_left,
                        enabled: canGoPrev,
                        onTap: () =>
                            setState(() => _currentDateIndex--),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FullWidthAvailabilityButton(
                          label: 'NO',
                          isSelected: _currentDateResponse == 'no',
                          isPositive: false,
                          isSubmitting: _isSubmitting,
                          onTap: () => _handleResponse('no'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FullWidthAvailabilityButton(
                          label: 'YES',
                          isSelected: _currentDateResponse == 'yes',
                          isPositive: true,
                          isSubmitting: _isSubmitting,
                          onTap: () => _handleResponse('yes'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _DateNavButton(
                        icon: Icons.chevron_right,
                        enabled: canGoNext,
                        onTap: () =>
                            setState(() => _currentDateIndex++),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _FullWidthAvailabilityButton(
                          label: 'NO',
                          isSelected: _currentDateResponse == 'no',
                          isPositive: false,
                          isSubmitting: _isSubmitting,
                          onTap: () => _handleResponse('no'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FullWidthAvailabilityButton(
                          label: 'YES',
                          isSelected: _currentDateResponse == 'yes',
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
// Date navigation chevron button
// ============================================================================

class _DateNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _DateNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        width: 36,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: enabled ? 0.5 : 0.2),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: enabled ? 1.0 : 0.3),
            size: 18,
          ),
        ),
      ),
    );
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
        backgroundColor = const Color(0xFF00A63E);
        borderColor = const Color(0xFF00A63E);
        textColor = Colors.white;
      } else {
        // NO - filled red
        backgroundColor = const Color(0xFFE7000B);
        borderColor = const Color(0xFFE7000B);
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
