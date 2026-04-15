import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/field_hint.dart';
import '../../../shared/utils/title_case_formatter.dart';
import '../models/event_form_data.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

/// Rehearsal-specific form fields: location autocomplete, recurring toggle,
/// and the animated recurring section (day selector, frequency, until date).
class RehearsalFormFields extends StatelessWidget {
  const RehearsalFormFields({
    super.key,
    required this.isSaving,
    // Location autocomplete
    required this.locationController,
    required this.locationHintController,
    required this.locationSuggestions,
    // Recurring state
    required this.isRecurring,
    required this.onRecurringToggled,
    required this.recurringSlideAnimation,
    required this.recurringFadeAnimation,
    // Recurring section data
    required this.selectedDays,
    required this.onDayToggled,
    required this.frequency,
    required this.onFrequencyChanged,
    required this.untilDate,
    required this.onUntilDateTap,
    required this.onUntilDateCleared,
    required this.selectedDate,
    required this.onMarkDirty,
  });

  final bool isSaving;

  // --- Location autocomplete ---
  final TextEditingController locationController;
  final FieldHintController locationHintController;
  final List<String> locationSuggestions;

  // --- Recurring toggle ---
  final bool isRecurring;
  final ValueChanged<bool> onRecurringToggled;
  final Animation<Offset> recurringSlideAnimation;
  final Animation<double> recurringFadeAnimation;

  // --- Recurring section data ---
  final Set<Weekday> selectedDays;
  final ValueChanged<Weekday> onDayToggled;
  final RecurrenceFrequency frequency;
  final ValueChanged<RecurrenceFrequency> onFrequencyChanged;
  final DateTime? untilDate;
  final VoidCallback onUntilDateTap;
  final VoidCallback onUntilDateCleared;
  final DateTime selectedDate;
  final VoidCallback onMarkDirty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Location autocomplete
        _buildLocationAutocomplete(context),

        const SizedBox(height: Spacing.space16),

        // Recurring Toggle
        _buildRecurringToggle(context),

        // Recurring Section (animated with slide + fade)
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: isRecurring
              ? SlideTransition(
                  position: recurringSlideAnimation,
                  child: FadeTransition(
                    opacity: recurringFadeAnimation,
                    child: _buildRecurringSection(context),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Location Autocomplete
  // ---------------------------------------------------------------------------

  Widget _buildLocationAutocomplete(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Location',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: locationController.text),
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return const Iterable<String>.empty();
            }
            final query = textEditingValue.text.toLowerCase();
            return locationSuggestions
                .where((location) => location.toLowerCase().contains(query))
                .take(8);
          },
          onSelected: (String selection) {
            locationController.text = selection;
            debugPrint('[RehearsalLocation] selected suggestion: $selection');
          },
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController fieldController,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            fieldController.addListener(() {
              locationController.text = fieldController.text;
            });
            return TextField(
              controller: fieldController,
              focusNode: focusNode,
              enabled: !isSaving,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              inputFormatters: [TitleCaseTextFormatter()],
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g., Studio, Venue Address',
                hintStyle: AppTextStyles.callout.copyWith(
                  color: context.colors.textMuted,
                ),
                filled: true,
                fillColor: context.colors.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            );
          },
          optionsViewBuilder: (
            BuildContext context,
            AutocompleteOnSelected<String> onSelected,
            Iterable<String> options,
          ) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceElevated,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    border: Border.all(color: context.colors.border),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    itemBuilder: (BuildContext context, int index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(
                          option,
                          style: AppTextStyles.callout.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        FieldHint(
          text: "We'll remember locations you've used before.",
          controller: locationHintController,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Recurring Toggle
  // ---------------------------------------------------------------------------

  Widget _buildRecurringToggle(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Make this recurring',
            style: AppTextStyles.callout
                .copyWith(color: context.colors.textPrimary),
          ),
        ),
        Switch.adaptive(
          value: isRecurring,
          onChanged: isSaving ? null : onRecurringToggled,
          activeTrackColor: AppColors.primary,
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return null;
          }),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Recurring Section
  // ---------------------------------------------------------------------------

  Widget _buildRecurringSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Spacing.space16),

        // A) Days of the Week
        Text(
          'Repeat on',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: Weekday.values.map((day) {
            final isSelected = selectedDays.contains(day);
            return GestureDetector(
              onTap: isSaving
                  ? null
                  : () {
                      onDayToggled(day);
                      HapticFeedback.selectionClick();
                    },
              child: AnimatedContainer(
                duration: AppDurations.fast,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : context.colors.background,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        isSelected ? AppColors.primary : context.colors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  day.shortLabel,
                  style: AppTextStyles.footnote.copyWith(
                    color: isSelected
                        ? Colors.white
                        : context.colors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: Spacing.space16),

        // B) Frequency toggles
        Text(
          'Frequency',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: RecurrenceFrequency.values.map((freq) {
            final isSelected = frequency == freq;
            return Expanded(
              child: GestureDetector(
                onTap: isSaving
                    ? null
                    : () {
                        onFrequencyChanged(freq);
                        HapticFeedback.selectionClick();
                      },
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  margin: EdgeInsets.only(
                    right: freq != RecurrenceFrequency.monthly ? 8 : 0,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : context.colors.background,
                    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : context.colors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    freq.displayName,
                    style: AppTextStyles.footnote.copyWith(
                      color: isSelected
                          ? Colors.white
                          : context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: Spacing.space16),

        // C) Until date
        Text(
          'Until (optional)',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: isSaving ? null : onUntilDateTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.background,
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              border: Border.all(color: context.colors.border),
            ),
            child: Row(
              children: [
                Icon(
                  AppIcons.calendarDays,
                  size: 18,
                  color: context.colors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    untilDate != null
                        ? _formatDateDisplay(untilDate!)
                        : 'No end date',
                    style: AppTextStyles.callout.copyWith(
                      color: untilDate != null
                          ? context.colors.textPrimary
                          : context.colors.textMuted,
                    ),
                  ),
                ),
                if (untilDate != null)
                  GestureDetector(
                    onTap: onUntilDateCleared,
                    child: Icon(
                      AppIcons.close,
                      size: 18,
                      color: context.colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: Spacing.space16),

        // D) Recurrence Summary
        if (selectedDays.isNotEmpty) ...[
          Text(
            'Summary',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _buildRecurrenceSummary(),
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  String _buildRecurrenceSummary() {
    if (selectedDays.isEmpty) return '';

    final sortedDays = selectedDays.toList()
      ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));

    final dayNames = sortedDays.map((d) => d.pluralName).toList();

    String daysText;
    if (dayNames.length == 1) {
      daysText = dayNames.first;
    } else if (dayNames.length == 2) {
      daysText = '${dayNames[0]} and ${dayNames[1]}';
    } else {
      final allButLast = dayNames.sublist(0, dayNames.length - 1).join(', ');
      daysText = '$allButLast, and ${dayNames.last}';
    }

    final frequencyText = frequency.displayName;

    String? untilText;
    if (untilDate != null) {
      untilText = ' until ${_formatFullDate(untilDate!)}';
    }

    return '$frequencyText on $daysText${untilText ?? ''}';
  }

  static String _formatDateDisplay(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
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
    final dayName = days[date.weekday % 7];
    final monthName = months[date.month - 1];
    return '$dayName, $monthName ${date.day}, ${date.year}';
  }

  static String _formatFullDate(DateTime date) {
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
