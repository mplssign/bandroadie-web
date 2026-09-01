import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/models/rehearsal.dart';
import '../../../app/models/rehearsal_date.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/utils/time_formatter.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'potential_gig_card.dart' show AnimatedDateLabel;
import '../../../components/ui/app_card.dart';
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
  final Future<void> Function(String? response, String? rehearsalDateId)?
      onRespondForDate;

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
    with TickerProviderStateMixin {
  bool _isPressed = false;
  bool _isSubmitting = false;
  AnimationController? _pulseController;

  /// Current date index within _sortedDates.
  int _currentDateIndex = 0;

  /// Optimistic per-date response map: rehearsalDateId? → 'yes'/'no'/null.
  Map<String?, String?> _localResponses = {};

  /// Tracks in-flight saves per date to prevent premature state sync.
  final Map<String?, bool> _savingInProgress = {};

  /// Navigation direction: 1 = forward (right), -1 = backward (left)
  int _navigationDirection = 1;

  /// Focus nodes for keyboard navigation: [left nav, NO, YES, right nav]
  final List<FocusNode> _focusNodes = [];

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

  DateTime get _currentDate => _sortedDates[_currentDateIndex].$1;
  String? get _currentRehearsalDateId => _sortedDates[_currentDateIndex].$2;
  String? get _currentDateResponse => _localResponses[_currentRehearsalDateId];
  bool get _isMultiDate => widget.additionalDates.isNotEmpty;

  /// Get the start time for the currently displayed date.
  /// Falls back to primary rehearsal start time if the additional date has no specific time.
  String get _currentStartTime {
    final rehearsalDateId = _currentRehearsalDateId;
    if (rehearsalDateId == null) {
      // Primary date
      return widget.rehearsal.startTime;
    }
    // Additional date - find the RehearsalDate object
    final rehearsalDate = widget.additionalDates.firstWhere(
      (d) => d.id == rehearsalDateId,
    );
    return rehearsalDate.startTime ?? widget.rehearsal.startTime;
  }

  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _localResponses = Map.from(widget.perDateUserResponses ?? {});

    // Initialize focus nodes for keyboard navigation
    for (int i = 0; i < 4; i++) {
      _focusNodes.add(FocusNode());
    }

    // Pulse controller for potential cards - randomized duration (1000-3000ms)
    if (widget.rehearsal.isPotential) {
      final random = Random();
      final durationMs = 1000 + random.nextInt(2000); // 1000-3000ms
      _pulseController = AnimationController(
        duration: Duration(milliseconds: durationMs),
        vsync: this,
      )..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(RehearsalCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.perDateUserResponses != widget.perDateUserResponses) {
      // Sync from props, but skip dates currently being saved to preserve optimistic updates
      final newResponses = Map<String?, String?>.from(_localResponses);
      widget.perDateUserResponses?.forEach((dateId, response) {
        if (_savingInProgress[dateId] != true) {
          newResponses[dateId] = response;
        }
      });
      _localResponses = newResponses;
    }

    // Handle isPotential transitions (potential ↔ confirmed) on already-mounted widget
    if (widget.rehearsal.isPotential != oldWidget.rehearsal.isPotential) {
      if (widget.rehearsal.isPotential && _pulseController == null) {
        // Transitioning to potential: create controller
        final random = Random();
        final durationMs = 1000 + random.nextInt(2000);
        _pulseController = AnimationController(
          duration: Duration(milliseconds: durationMs),
          vsync: this,
        )..repeat(reverse: true);
      } else if (!widget.rehearsal.isPotential && _pulseController != null) {
        // Transitioning to confirmed: dispose controller
        _pulseController?.dispose();
        _pulseController = null;
      }
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    for (var node in _focusNodes) {
      node.dispose();
    }
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
        _savingInProgress[rehearsalDateId] = true;
        _localResponses = {..._localResponses, rehearsalDateId: null};
      });
      try {
        await widget.onRespondForDate!(null, rehearsalDateId);
      } catch (e) {
        debugPrint(
            '[RehearsalCard] Response save failed for date $rehearsalDateId: $e');
        if (mounted) {
          setState(() {
            _localResponses = {
              ..._localResponses,
              rehearsalDateId: widget.perDateUserResponses?[rehearsalDateId],
            };
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not save response — please try again.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _savingInProgress[rehearsalDateId] = false;
          });
        }
      }
      return;
    }

    // Normal selection flow
    HapticFeedback.selectionClick();
    setState(() {
      _isSubmitting = true;
      _savingInProgress[rehearsalDateId] = true;
      _localResponses = {..._localResponses, rehearsalDateId: response};
    });
    try {
      await widget.onRespondForDate!(response, rehearsalDateId);
    } catch (e) {
      debugPrint(
          '[RehearsalCard] Response save failed for date $rehearsalDateId: $e');
      if (mounted) {
        setState(() {
          _localResponses = {
            ..._localResponses,
            rehearsalDateId: widget.perDateUserResponses?[rehearsalDateId],
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save response — please try again.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _savingInProgress[rehearsalDateId] = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Keyboard navigation
  // ---------------------------------------------------------------------------

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Handle Enter and Space for activation
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      final dates = _sortedDates;
      final nodeIndex = _focusNodes.indexOf(node);

      if (_isMultiDate) {
        // Multi-date: [0]=left nav, [1]=NO, [2]=YES, [3]=right nav
        if (nodeIndex == 0 && _currentDateIndex > 0) {
          setState(() => _currentDateIndex--);
          return KeyEventResult.handled;
        } else if (nodeIndex == 1) {
          _handleResponse('no');
          return KeyEventResult.handled;
        } else if (nodeIndex == 2) {
          _handleResponse('yes');
          return KeyEventResult.handled;
        } else if (nodeIndex == 3 && _currentDateIndex < dates.length - 1) {
          setState(() => _currentDateIndex++);
          return KeyEventResult.handled;
        }
      } else {
        // Single-date: [1]=NO, [2]=YES
        if (nodeIndex == 1) {
          _handleResponse('no');
          return KeyEventResult.handled;
        } else if (nodeIndex == 2) {
          _handleResponse('yes');
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
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
    // Defensive null-safety: ensure controller exists before building animated content
    if (_pulseController == null) {
      // Lazily create controller if somehow missing (should not happen with proper lifecycle)
      final random = Random();
      final durationMs = 1000 + random.nextInt(2000);
      _pulseController = AnimationController(
        duration: Duration(milliseconds: durationMs),
        vsync: this,
      )..repeat(reverse: true);
    }

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
          animation: _pulseController!,
          builder: (context, child) {
            // Subtle pulse: animate border alpha and color temperature
            final pulseValue = _pulseController!.value;
            final alpha = 0.35 + (pulseValue * 0.45);

            // Lerp from orange-500 to orange-400 for a subtle attention cue
            const baseColor = Color(0xFFF97316); // orange-500
            const hotColor = Color(0xFFFB923C); // orange-400
            final borderColor = Color.lerp(baseColor, hotColor, pulseValue)!
                .withValues(alpha: alpha);

            return AppCard(
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(Spacing.cardRadius),
              color: const Color(0x14F97316), // orange-500 tint background
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color.lerp(
                    const Color(0xFFF97316),
                    const Color(0xFFFB923C),
                    pulseValue,
                  )!
                      .withValues(alpha: 0.18 + (pulseValue * 0.27)),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
              child: child!,
            );
          },
          child: Container(
            constraints:
                BoxConstraints(minHeight: Spacing.potentialGigCardHeight),
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
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: AppFontSizes.subhead,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF4A1F0F),
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (_isMultiDate)
                            TextSpan(
                              text: ': Multiple Dates',
                              style: TextStyle(
                                fontFamily: 'Geist',
                                fontSize: AppFontSizes.caption,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF4A1F0F),
                                letterSpacing: 0.3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Date (with recurring frequency prefix if applicable)
                  AnimatedDateLabel(
                    text: _formatDateWithRecurrence(),
                    direction: _navigationDirection,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Geist',
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
                  AnimatedDateLabel(
                    text: _formatTimeLine(widget.rehearsal),
                    direction: _navigationDirection,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: AppFontSizes.title,
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
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: AppFontSizes.title,
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
                            onTap: () => setState(() {
                              _navigationDirection = -1;
                              _currentDateIndex--;
                            }),
                            focusNode: _focusNodes[0],
                            onKey: _handleKeyEvent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FullWidthAvailabilityButton(
                              label: 'NO',
                              isSelected: _currentDateResponse == 'no',
                              isPositive: false,
                              isSubmitting: _isSubmitting,
                              isLoading:
                                  _savingInProgress[_currentRehearsalDateId] ??
                                      false,
                              onTap: () => _handleResponse('no'),
                              focusNode: _focusNodes[1],
                              onKey: _handleKeyEvent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _FullWidthAvailabilityButton(
                              label: 'YES',
                              isSelected: _currentDateResponse == 'yes',
                              isPositive: true,
                              isSubmitting: _isSubmitting,
                              isLoading:
                                  _savingInProgress[_currentRehearsalDateId] ??
                                      false,
                              onTap: () => _handleResponse('yes'),
                              focusNode: _focusNodes[2],
                              onKey: _handleKeyEvent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _RehearsalDateNavButton(
                            icon: Icons.chevron_right,
                            enabled: canGoNext,
                            onTap: () => setState(() {
                              _navigationDirection = 1;
                              _currentDateIndex++;
                            }),
                            focusNode: _focusNodes[3],
                            onKey: _handleKeyEvent,
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
                            isLoading:
                                _savingInProgress[_currentRehearsalDateId] ??
                                    false,
                            onTap: () => _handleResponse('no'),
                            focusNode: _focusNodes[1],
                            onKey: _handleKeyEvent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _FullWidthAvailabilityButton(
                            label: 'YES',
                            isSelected: _currentDateResponse == 'yes',
                            isPositive: true,
                            isSubmitting: _isSubmitting,
                            isLoading:
                                _savingInProgress[_currentRehearsalDateId] ??
                                    false,
                            onTap: () => _handleResponse('yes'),
                            focusNode: _focusNodes[2],
                            onKey: _handleKeyEvent,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
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
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          border: Border.all(
            color: const Color(0x330EA5E9), // sky-500 @ 20% alpha
            width: 1.5,
          ),
          color: const Color(0x140EA5E9), // sky-500 @ ~8% alpha background tint
          child: Container(
            constraints: BoxConstraints(
              minHeight: Spacing.rehearsalCardHeight,
            ),
            padding: const EdgeInsets.fromLTRB(
              Spacing.space16, // left
              Spacing.space16, // top
              Spacing.space16, // right
              Spacing.space8, // bottom
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top section: Date + Time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDateLine(_currentDate),
                      style: AppTextStyles.title3.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTimeLine(widget.rehearsal),
                      style: TextStyle(
                        fontSize: AppFontSizes.body,
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
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.location,
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.rehearsal.location.isNotEmpty
                              ? widget.rehearsal.location
                              : 'TBD',
                          style: TextStyle(
                            fontSize: AppFontSizes.body,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.75),
                            height: 1.2,
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
                            _truncatedSetlistName(widget.setlistName!),
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
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Formatters
  // ---------------------------------------------------------------------------

  static const int _setlistNameMaxLength = 25;

  String _truncatedSetlistName(String name) {
    if (name.length <= _setlistNameMaxLength) return name;
    return '${name.substring(0, _setlistNameMaxLength)}…';
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
    return TimeFormatter.formatRange(_currentStartTime, rehearsal.endTime);
  }

  String _formatDateWithRecurrence() {
    if (widget.rehearsal.isRecurring &&
        widget.rehearsal.recurrenceFrequency != null) {
      final frequency = widget.rehearsal.recurrenceFrequency!;
      final frequencyText =
          frequency.substring(0, 1).toUpperCase() + frequency.substring(1);
      return '$frequencyText starting ${_formatFullDate(_currentDate)}';
    }
    return _formatFullDate(_currentDate);
  }
}

// ============================================================================
// DATE NAVIGATION CHEVRON BUTTON (rehearsal variant)
// ============================================================================

class _RehearsalDateNavButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKey;

  const _RehearsalDateNavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.focusNode,
    this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: enabled
          ? onTap
          : () {}, // Empty callback prevents tap bubbling when disabled
      child: AnimatedContainer(
        duration: AppDurations.fast,
        width: 48,
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

    if (focusNode != null && onKey != null) {
      return Focus(
        focusNode: focusNode,
        onKeyEvent: onKey,
        child: button,
      );
    }
    return button;
  }
}

/// Full-width availability button for potential rehearsal cards
class _FullWidthAvailabilityButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isPositive;
  final bool isSubmitting;
  final bool isLoading;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKey;

  const _FullWidthAvailabilityButton({
    required this.label,
    required this.isSelected,
    required this.isPositive,
    required this.isSubmitting,
    this.isLoading = false,
    required this.onTap,
    this.focusNode,
    this.onKey,
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

    final button = GestureDetector(
      onTap: (isSubmitting || isLoading) ? null : onTap,
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
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: AppFontSizes.body,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );

    if (focusNode != null && onKey != null) {
      return Focus(
        focusNode: focusNode,
        onKeyEvent: onKey,
        child: button,
      );
    }
    return button;
  }
}
