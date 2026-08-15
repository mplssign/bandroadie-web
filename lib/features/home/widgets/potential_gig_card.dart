import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/models/gig.dart';
import '../../../app/models/gig_date.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/utils/time_formatter.dart';
import '../../../components/ui/app_card.dart';

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
  final Future<void> Function(String? response, String? gigDateId)?
      onRespondForDate;

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
  bool _isPressed = false;
  bool _isSubmitting = false;

  /// Current date index within _sortedDates.
  int _currentDateIndex = 0;

  /// Optimistic per-date response map: gigDateId? → 'yes'/'no'/null.
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

  /// Get the start time for the currently displayed date.
  /// Falls back to primary gig start time if the additional date has no specific time.
  String get _currentStartTime {
    final gigDateId = _currentGigDateId;
    if (gigDateId == null) {
      // Primary date
      return widget.gig.startTime;
    }
    // Additional date - find the GigDate object
    final gigDate = widget.gig.additionalDates.firstWhere(
      (d) => d.id == gigDateId,
    );
    return gigDate.startTime ?? widget.gig.startTime;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _localResponses = Map.from(widget.perDateUserResponses ?? {});

    // Initialize focus nodes for keyboard navigation
    for (int i = 0; i < 4; i++) {
      _focusNodes.add(FocusNode());
    }
  }

  @override
  void didUpdateWidget(PotentialGigCard oldWidget) {
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
  }

  @override
  void dispose() {
    for (var node in _focusNodes) {
      node.dispose();
    }
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
        _savingInProgress[gigDateId] = true;
        _localResponses = {..._localResponses, gigDateId: null};
      });
      try {
        await widget.onRespondForDate!(null, gigDateId);
      } catch (e) {
        debugPrint(
            '[PotentialGigCard] Response save failed for date $gigDateId: $e');
        if (mounted) {
          setState(() {
            _localResponses = {
              ..._localResponses,
              gigDateId: widget.perDateUserResponses?[gigDateId],
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
            _savingInProgress[gigDateId] = false;
          });
        }
      }
      return;
    }

    // Normal selection
    HapticFeedback.selectionClick();
    setState(() {
      _isSubmitting = true;
      _savingInProgress[gigDateId] = true;
      _localResponses = {..._localResponses, gigDateId: response};
    });
    try {
      await widget.onRespondForDate!(response, gigDateId);
    } catch (e) {
      debugPrint(
          '[PotentialGigCard] Response save failed for date $gigDateId: $e');
      if (mounted) {
        setState(() {
          _localResponses = {
            ..._localResponses,
            gigDateId: widget.perDateUserResponses?[gigDateId],
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
          _savingInProgress[gigDateId] = false;
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
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
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33F59E0B), // amber-500 @ 20%
              blurRadius: 6,
              spreadRadius: 4,
            ),
          ],
          child: Container(
            width: widget.width,
            constraints:
                BoxConstraints(minHeight: Spacing.potentialGigCardHeight),
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

                  // Current date
                  AnimatedDateLabel(
                    text: _formatFullDate(_currentDate),
                    direction: _navigationDirection,
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: AppFontSizes.pageTitle,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Time (index-aware for multi-date)
                  AnimatedDateLabel(
                    text: TimeFormatter.formatRangeLocal(
                      _currentStartTime,
                      widget.gig.endTime,
                      _currentDate,
                      widget.bandTimezone,
                    ),
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
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: AppFontSizes.title,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (widget.gig.location.isNotEmpty)
                          Text(
                            ' - ${widget.gig.locationDisplay}',
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: AppFontSizes.title,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.3,
                            ),
                          ),
                      ] else
                        Flexible(
                          child: Text(
                            widget.gig.location.isNotEmpty
                                ? widget.gig.locationDisplay
                                : 'No venue specified',
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
                                _savingInProgress[_currentGigDateId] ?? false,
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
                                _savingInProgress[_currentGigDateId] ?? false,
                            onTap: () => _handleResponse('yes'),
                            focusNode: _focusNodes[2],
                            onKey: _handleKeyEvent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _DateNavButton(
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
                            isLoading:
                                _savingInProgress[_currentGigDateId] ?? false,
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
                                _savingInProgress[_currentGigDateId] ?? false,
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
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKey;

  const _DateNavButton({
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
          fontSize: AppFontSizes.caption,
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
            fontSize: AppFontSizes.caption,
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
            fontSize: AppFontSizes.caption,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Animated date label with horizontal slide transition.
/// Slides out to the left when navigating forward, right when navigating backward.
class AnimatedDateLabel extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int direction; // 1 = forward, -1 = backward
  final int? maxLines;
  final TextOverflow? overflow;

  const AnimatedDateLabel({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.center,
    this.direction = 1,
    this.maxLines,
    this.overflow,
  });

  @override
  State<AnimatedDateLabel> createState() => _AnimatedDateLabelState();
}

class _AnimatedDateLabelState extends State<AnimatedDateLabel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _curved;
  String _previousText = '';
  String _currentText = '';

  @override
  void initState() {
    super.initState();
    _currentText = widget.text;
    _previousText = widget.text;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 750),
      vsync: this,
    );

    _curved = CurvedAnimation(
      parent: _controller,
      curve: AppCurves.ease,
    );
  }

  @override
  void didUpdateWidget(AnimatedDateLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.direction != widget.direction) {
      _previousText = _currentText;
      _currentText = widget.text;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dir = widget.direction.toDouble();
    return ClipRect(
      child: SizedBox(
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth +
                32; // Add card horizontal padding (16 * 2)
            return AnimatedBuilder(
              animation: _curved,
              builder: (context, _) {
                final t = _curved.value;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    if (t < 1.0)
                      Transform.translate(
                        offset: Offset(-dir * t * width, 0),
                        child: Text(
                          _previousText,
                          textAlign: widget.textAlign,
                          style: widget.style,
                          maxLines: widget.maxLines,
                          overflow: widget.overflow,
                        ),
                      ),
                    Transform.translate(
                      offset: Offset(dir * (1.0 - t) * width, 0),
                      child: Text(
                        _currentText,
                        textAlign: widget.textAlign,
                        style: widget.style,
                        maxLines: widget.maxLines,
                        overflow: widget.overflow,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
