import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/event_editor_theme.dart';
import '../models/event_form_data.dart';

/// Event type toggle: Rehearsal / Gig / Block Out segmented control.
/// Restyled to event-editor spec: dark track, rose active pill.
/// Shows a disabled hint in edit mode.
class EventTypeSelector extends StatelessWidget {
  const EventTypeSelector({
    super.key,
    required this.selectedType,
    required this.availableTypes,
    required this.isEditMode,
    required this.isSaving,
    required this.onTypeChanged,
  });

  final EventType selectedType;
  final List<EventType> availableTypes;
  final bool isEditMode;
  final bool isSaving;
  final ValueChanged<EventType> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final isDisabled = isEditMode || isSaving;
    final colors = FTheme.of(context).colors;
    final currentIndex = availableTypes
        .indexOf(selectedType)
        .clamp(0, availableTypes.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: colors.secondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kEdSegmentedBorder),
          ),
          padding: const EdgeInsets.all(3),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth / availableTypes.length;
              return Stack(
                children: [
                  // Sliding rose indicator
                  AnimatedAlign(
                    alignment: Alignment(
                      availableTypes.length > 1
                          ? -1.0 +
                              (2.0 *
                                  currentIndex /
                                  (availableTypes.length - 1))
                          : 0.0,
                      0.0,
                    ),
                    duration: AppDurations.fast,
                    curve: AppCurves.ease,
                    child: Container(
                      width: segmentWidth,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: isDisabled
                            ? colors.primary.withValues(alpha: 0.5)
                            : colors.primary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                  // Labels
                  Row(
                    children: availableTypes.map((type) {
                      final isSelected = selectedType == type;
                      return Expanded(
                        child: GestureDetector(
                          onTap: isDisabled
                              ? null
                              : () {
                                  onTypeChanged(type);
                                  HapticFeedback.selectionClick();
                                },
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: AppDurations.fast,
                              curve: AppCurves.ease,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? (isDisabled
                                        ? Colors.white.withValues(alpha: 0.7)
                                        : Colors.white)
                                    : colors.secondaryForeground,
                              ),
                              child: Text(type.displayName),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ),
        if (isEditMode) ...[
          const SizedBox(height: 6),
          Text(
            'Event type cannot be changed after creation.',
            style: TextStyle(
              fontSize: AppFontSizes.caption,
              color: colors.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }
}
