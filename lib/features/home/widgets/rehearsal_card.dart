import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/models/rehearsal.dart';
import '../../../app/models/rehearsal_date.dart';
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

  /// Additional dates for multi-date potential rehearsals.
  /// Currently always empty until the Rehearsal model is extended.
  final List<RehearsalDate> additionalDates;

  /// Current user's responses keyed by rehearsalDateId (null = primary date).
  final Map<String?, String?>? perDateUserResponses;

  /// Called with response ('yes'/'no') or null (unselect), and the rehearsalDateId
  /// (null = primary date) for the currently displayed date.
  final Future<void> Function(String? response, String? rehearsalDateId)? onRespondForDate;

  const RehearsalCard({
    super.key,
    required this.rehearsal,
    required this.bandTimezone,
    this.onTap,
    this.setlistName,
    this.additionalDates = const [],
    this.perDateUserResponses,
    this.onRespondForDate,
  });

  @override
  State<RehearsalCard> createState() => _RehearsalCardState();
}

class _RehearsalCardState extends State<RehearsalCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _gradientController;
  bool _isPressed = false;
  bool _isSubmitting = false;

  /// Current date index within _sortedDates.
  int _currentDateIndex = 0;

  /// Optimistic per-date response map: rehearsalDateId? → 'yes'/'no'/null.
  Map<String?, String?> _localResponses = {};

  // ---------------------------------------------------------------------------
  // Date helpers
  // ---------------------------------------------------------------------------

  /// All dates (primary + additional) sorted chronologically.
  /// Each entry is (date, rehearsalDateId?): null id = primary date.
  List<(DateTime, String?)> get _sortedDates {
    final primary = (widget.rehearsal.date, null as String?);
    final additional = widget.additionalDates
        .map<(DateTime, String?)>((RehearsalDate d) => (d.date, d.id))
        .toList();
    final all = [primary, ...additional];
    all.sort((a, b) => a.$1.compareTo(b.$1));
    return all;
  }

  String? get _currentRehearsalDateId => _sortedDates[_currentDateIndex].$2;
  String? get _currentDateResponse => _localResponses[_currentRehearsalDateId];
  bool get _isMultiDate => widget.additionalDates.isNotEmpty;

  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _localResponses = Map.from(widget.perDateUserResponses ?? {});

    _gradientController = AnimationController(
      duration: const Duration(seconds: 6),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(RehearsalCard oldWidget) {
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

  Future<void> _handleResponse(String response) async {
    final rehearsalDateId = _currentRehearsalDateId;
    final currentResponse = _localResponses[rehearsalDateId];
    if (_isSubmitting || widget.onRespondForDate == null) return;

    // If tapping the same button that's already selected, unselect (delete)
    if (currentResponse == response) {
      HapticFeedback.selectionClick();
      setState(() {
        _isSubmitting = true;
        _localResponses = {..._localResponses, rehearsalDateId: null};
      });
      try {
        await widget.onRespondForDate!(null, rehearsalDateId);
      } catch (_) {
        if (mounted) {
          setState(() {
            _localResponses = {
              ..._localResponses,
              rehearsalDateId: widget.perDateUserResponses?[rehearsalDateId],
            };
          });
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
      return;
    }

    // Normal selection flow
    HapticFeedback.selectionClick();
    setState(() {
      _isSubmitting = true;
      _localResponses = {..._localResponses, rehearsalDateId: response};
    });
    try {
      await widget.onRespondForDate!(response, rehearsalDateId);
    } catch (_) {
      if (mounted) {
        setState(() {
          _localResponses = {
            ..._localResponses,
            rehearsalDateId: widget.perDateUserResponses?[rehearsalDateId],
          };
        });
      }
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
        Theme.of(context).brightness == Brightness.light ? 1.0 : 0.50;

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
                // Chip label with cream background - full width
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
                          text: 'POTENTIAL REHEARSAL',
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

                // Button row: [← nav] [NO] [YES] [nav →] when multi-date,
                // else just [NO] [YES].
                if (_isMultiDate)
                  Builder(builder: (context) {
                    final dates = _sortedDates;
                    final canGoPrev = _currentDateIndex > 0;
                    final canGoNext = _currentDateIndex < dates.length - 1;
                    return Row(
                      children: [
                        _RehearsalDateNavButton(
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
                        _RehearsalDateNavButton(
                          icon: Icons.chevron_right,
                          enabled: canGoNext,
                          onTap: () =>
                              setState(() => _currentDateIndex++),
                        ),
                      ],
                    );
                  })
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

  // ---------------------------------------------------------------------------
  // CONFIRMED VARIANT — unchanged blue→purple card
  // ---------------------------------------------------------------------------

  Widget _buildConfirmedCard(BuildContext context) {
    final gradientAlpha =
        Theme.of(context).brightness == Brightness.light ? 1.0 : 0.50;

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
                color: const Color(0xFF155DFC).withValues(alpha: gradientAlpha),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top section: Date + Time
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.75),
                      height: 1.2,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: Spacing.space16),

              // Bottom: Location + Setlist
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        AppIcons.location,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.rehearsal.location.isNotEmpty
                              ? widget.rehearsal.location
                              : 'TBD',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.75),
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (widget.rehearsal.setlistId != null &&
                      widget.setlistName != null) ...[
                    const SizedBox(height: 8),
                    IntrinsicWidth(
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(Spacing.chipRadius),
                          border: Border.all(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.centerLeft,
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
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
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
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
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

// ============================================================================
// DATE NAVIGATION CHEVRON BUTTON (rehearsal variant)
// ============================================================================

class _RehearsalDateNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _RehearsalDateNavButton({
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
