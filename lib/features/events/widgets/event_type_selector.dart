import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../models/event_form_data.dart';

/// Event type toggle: Rehearsal / Gig / Block Out segmented control.
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
    final currentIndex = availableTypes
        .indexOf(selectedType)
        .clamp(0, availableTypes.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(3),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth / availableTypes.length;
              return Stack(
                children: [
                  // Sliding indicator
                  AnimatedAlign(
                    alignment: Alignment(
                      -1.0 + (2.0 * currentIndex / (availableTypes.length - 1)),
                      0.0,
                    ),
                    duration: AppDurations.fast,
                    curve: AppCurves.ease,
                    child: Container(
                      width: segmentWidth,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: isDisabled
                            ? AppColors.primary.withValues(alpha: 0.5)
                            : AppColors.primary,
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
                                    : context.colors.textPrimary,
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
            style: AppTextStyles.footnote
                .copyWith(color: context.colors.textMuted),
          ),
        ],
      ],
    );
  }
}
