import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.scaffoldBg,
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
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
                  child: AnimatedContainer(
                    duration: AppDurations.fast,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDisabled
                              ? AppColors.accent.withValues(alpha: 0.5)
                              : AppColors.accent)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        Spacing.buttonRadius - 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      type.displayName,
                      style: AppTextStyles.calloutEmphasized.copyWith(
                        color: isSelected
                            ? (isDisabled
                                ? AppColors.textPrimary.withValues(alpha: 0.7)
                                : AppColors.textPrimary)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (isEditMode) ...[
          const SizedBox(height: 6),
          Text(
            'Event type cannot be changed after creation.',
            style: AppTextStyles.footnote.copyWith(color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}
