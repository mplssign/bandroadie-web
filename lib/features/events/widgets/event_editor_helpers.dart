import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// Shared reusable building blocks for event editor form field widgets.
// ============================================================================

/// Styled text field with label, error display, and optional multiline support.
class EventTextField extends StatelessWidget {
  const EventTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.maxLines = 1,
    required this.isSaving,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? error;
  final int maxLines;
  final bool isSaving;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final isMultiline = maxLines > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !isSaving,
          maxLines: isMultiline ? null : maxLines,
          minLines: isMultiline ? maxLines : null,
          keyboardType:
              isMultiline ? TextInputType.multiline : TextInputType.text,
          textInputAction:
              isMultiline ? TextInputAction.newline : TextInputAction.done,
          textCapitalization: isMultiline
              ? TextCapitalization.sentences
              : TextCapitalization.none,
          style: AppTextStyles.callout.copyWith(color: AppColors.textPrimary),
          onChanged: onChanged != null ? (_) => onChanged!() : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.callout.copyWith(
              color: AppColors.textMuted,
            ),
            filled: true,
            fillColor: AppColors.scaffoldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(
                color: error != null ? AppColors.error : AppColors.borderMuted,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(
                color: error != null ? AppColors.error : AppColors.borderMuted,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(
                color: error != null ? AppColors.error : AppColors.accent,
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: AppTextStyles.footnote.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

/// Styled dropdown selector.
class EventDropdown<T> extends StatelessWidget {
  const EventDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelBuilder,
    required this.isSaving,
  });

  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T) labelBuilder;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.scaffoldBg,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.cardBgElevated,
          style: AppTextStyles.callout.copyWith(color: AppColors.textPrimary),
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
          ),
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(labelBuilder(item)),
            );
          }).toList(),
          onChanged: isSaving ? null : onChanged,
        ),
      ),
    );
  }
}

/// AM/PM toggle button (used for start time and load-in time).
class AmPmToggleButton extends StatelessWidget {
  const AmPmToggleButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isSaving,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isSaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isSaving ? null : onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius - 2),
        ),
        child: Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// YES/NO availability response button with animated state transitions.
class AvailabilityButton extends StatelessWidget {
  const AvailabilityButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isPositive,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isPositive;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final activeColor = isPositive
        ? const Color(0xFF22C55E) // green-500
        : const Color(0xFFEF4444); // red-500

    final backgroundColor =
        isSelected ? activeColor.withValues(alpha: 0.2) : AppColors.scaffoldBg;

    final borderColor = isSelected ? activeColor : AppColors.borderMuted;

    final contentColor = isSelected ? activeColor : AppColors.textSecondary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: AppCurves.ease,
          height: 44,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: activeColor,
                    ),
                  )
                : AnimatedSwitcher(
                    duration: AppDurations.fast,
                    child: Row(
                      key: ValueKey('$label-$isSelected'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 20, color: contentColor),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: contentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Helper data class for member name disambiguation.
class MemberDisambiguation {
  const MemberDisambiguation({
    required this.line1,
    this.line2,
    this.requiresTwoLines = false,
  });

  final String line1;
  final String? line2;
  final bool requiresTwoLines;
}
