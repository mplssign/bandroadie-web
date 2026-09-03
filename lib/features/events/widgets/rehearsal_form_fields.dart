import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/event_editor_theme.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/app_progress_indicator.dart';
import '../../../components/ui/app_switch.dart';
import '../../../components/ui/field_hint.dart';
import '../../../shared/utils/title_case_formatter.dart';
import '../models/event_form_data.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import '../../members/member_vm.dart';
import '../../members/members_controller.dart';
import 'button_group_grid.dart';
import 'event_editor_helpers.dart';

/// Rehearsal-specific form fields: location autocomplete, potential toggle,
/// recurring toggle, and the animated recurring section.
class RehearsalFormFields extends ConsumerWidget {
  const RehearsalFormFields({
    super.key,
    required this.isSaving,
    // Location autocomplete
    required this.locationAutocompleteController,
    required this.locationHintController,
    required this.locationSuggestions,
    required this.onLocationTextChanged,
    // Field validation
    required this.fieldErrors,
    // Potential rehearsal toggle
    required this.isPotential,
    required this.onPotentialToggled,
    // Multi-date (potential rehearsals)
    required this.additionalDates,
    required this.primaryStartTime,
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
    // Member availability (for potential rehearsals)
    required this.memberAvailability,
    required this.isLoadingMemberAvailability,
    required this.isLoadingUserResponse,
    this.currentUserResponse,
    this.onUserResponseChanged,
    this.isEditMode = false,
    this.existingEventId,
    // Per-date availability (multi-date potential rehearsals in edit mode)
    this.perDateAvailability = const {},
    this.isLoadingPerDateAvailability = false,
    this.existingDateIds = const {},
    this.onPerDateResponseChanged,
    this.currentUserId,
  });

  final bool isSaving;

  // --- Location autocomplete ---
  final FAutocompleteController locationAutocompleteController;
  final FieldHintController locationHintController;
  final List<String> locationSuggestions;
  final ValueChanged<String> onLocationTextChanged;

  // --- Field validation ---
  final Map<String, String> fieldErrors;

  // --- Potential rehearsal toggle ---
  final bool isPotential;
  final ValueChanged<bool> onPotentialToggled;

  // --- Multi-date ---
  final List<AdditionalDateEntry> additionalDates;
  final String primaryStartTime;

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

  // --- Member availability ---
  final Map<String, String?> memberAvailability;
  final bool isLoadingMemberAvailability;
  final String? currentUserResponse;
  final ValueChanged<String>? onUserResponseChanged;
  final bool isEditMode;
  final String? existingEventId;
  final bool isLoadingUserResponse;

  // Per-date availability
  final Map<String, Map<String, String?>> perDateAvailability;
  final bool isLoadingPerDateAvailability;
  final Map<DateTime, String> existingDateIds;
  final void Function(DateTime date, bool isPrimaryDate, String response)?
      onPerDateResponseChanged;
  final String? currentUserId;

  /// Builds the Potential Rehearsal toggle + member availability grid.
  /// Called from the parent drawer so it renders BEFORE the date/time fields.
  Widget buildPotentialSection(BuildContext context, WidgetRef ref) {
    return _buildPotentialToggle(context, ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Location autocomplete
        _buildLocationAutocomplete(context),

        // Recurring Toggle + Section — hidden when Potential Rehearsal is ON
        if (!isPotential) ...[
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
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Location Autocomplete
  // ---------------------------------------------------------------------------

  Widget _buildLocationAutocomplete(BuildContext context) {
    final hasError = fieldErrors.containsKey('location');
    final errorText = hasError ? fieldErrors['location'] : null;

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
        FAutocomplete.text(
          items: locationSuggestions,
          control: FAutocompleteControl.managed(
            controller: locationAutocompleteController,
            onChange: (value) {
              onLocationTextChanged(value.text);
            },
          ),
          filter: (query) {
            if (query.isEmpty) return const Iterable<String>.empty();
            final lowerQuery = query.toLowerCase();
            return locationSuggestions
                .where(
                    (location) => location.toLowerCase().contains(lowerQuery))
                .take(8);
          },
          hint: 'e.g., Studio, Venue Address',
          enabled: !isSaving,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [TitleCaseTextFormatter()],
          forceErrorText: hasError ? errorText : null,
          onItemPress: (selection) {
            // No additional callback needed - text captured via onChange
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
  // Potential Toggle
  // ---------------------------------------------------------------------------

  Widget _buildPotentialToggle(BuildContext context, WidgetRef ref) {
    final membersState = ref.watch(membersProvider);
    final members = membersState.members;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(Spacing.space12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border:
            isPotential ? Border.all(color: AppColors.primary, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Potential Rehearsal',
                      style: AppTextStyles.callout.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Toggle off once confirmed to make it official.',
                      style: AppTextStyles.footnote.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppSwitch(
                value: isPotential,
                onChanged: isSaving ? null : onPotentialToggled,
                activeColor: const Color(0xFFfb2c5a),
                activeTrackColor: const Color(0xFFfb2c5a),
              ),
            ],
          ),
          // Member grid — shown when potential is ON
          if (isPotential) ...[
            const SizedBox(height: Spacing.space12),
            Builder(builder: (context) {
              final isMultiDateEditMode = isEditMode &&
                  existingEventId != null &&
                  additionalDates.isNotEmpty;
              if (isMultiDateEditMode) {
                return _buildMultiDateAvailabilitySection(
                    context, members, membersState.isLoading);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (additionalDates.isNotEmpty) ...[
                    _buildProposedDatesSection(context),
                    const SizedBox(height: Spacing.space12),
                  ],
                  if (membersState.isLoading || isLoadingMemberAvailability)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: AppProgressIndicator(
                          type: ProgressIndicatorType.circular,
                        ),
                      ),
                    )
                  else ...[
                    ButtonGroupGrid<MemberVM>(
                      items: members,
                      labelBuilder: (member) =>
                          _getMemberLabel(member, members),
                      labelWidgetBuilder: (member) => _buildMemberLabelWidget(
                          context, member, members, memberAvailability),
                      isSelected: (_) => false,
                      availabilityMode: true,
                      availabilityState: (member) {
                        final response = memberAvailability[member.userId];
                        if (response == 'yes') {
                          return AvailabilityState.available;
                        }
                        if (response == 'no') {
                          return AvailabilityState.notAvailable;
                        }
                        return AvailabilityState.notResponded;
                      },
                      onTap: null,
                    ),
                    if (isEditMode && existingEventId != null)
                      _buildUserAvailabilitySection(context),
                  ],
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Proposed Dates Section (multi-date potential rehearsals)
  // ---------------------------------------------------------------------------

  Widget _buildProposedDatesSection(BuildContext context) {
    // Build (date, timeDisplay) pairs sorted by date
    final allEntries = <(DateTime, String)>[
      (selectedDate, primaryStartTime),
      ...additionalDates.map((e) => (e.date, e.startTimeDisplay)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Proposed Dates',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        for (final entry in allEntries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  AppIcons.calendar,
                  size: 14,
                  color: context.colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_formatDateDisplay(entry.$1)} · ${entry.$2}',
                  style: AppTextStyles.footnote.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMultiDateAvailabilitySection(
    BuildContext context,
    List<MemberVM> members,
    bool isLoading,
  ) {
    final allEntries = <(DateTime, String)>[
      (selectedDate, primaryStartTime),
      ...additionalDates.map((e) => (e.date, e.startTimeDisplay)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < allEntries.length; i++) ...[
          if (i > 0) const SizedBox(height: Spacing.space16),
          _buildPerDateSection(
            context: context,
            date: allEntries[i].$1,
            timeDisplay: allEntries[i].$2,
            members: members,
            isLoading: isLoading,
            isPrimaryDate: allEntries[i].$1 == selectedDate,
          ),
        ],
      ],
    );
  }

  Widget _buildPerDateSection({
    required BuildContext context,
    required DateTime date,
    required String timeDisplay,
    required List<MemberVM> members,
    required bool isLoading,
    required bool isPrimaryDate,
  }) {
    final dateKey = isPrimaryDate ? 'primary' : existingDateIds[date];
    final availability = dateKey != null
        ? (perDateAvailability[dateKey] ?? {})
        : <String, String?>{};
    final userResponse =
        currentUserId != null ? availability[currentUserId] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_formatDateDisplay(date)} · $timeDisplay',
          style: AppTextStyles.calloutEmphasized.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        if (isLoading || isLoadingPerDateAvailability)
          const Center(
            child: AppProgressIndicator(
              type: ProgressIndicatorType.circular,
            ),
          )
        else if (members.isEmpty)
          Text('No members', style: AppTextStyles.footnote)
        else
          ButtonGroupGrid<MemberVM>(
            items: members,
            labelBuilder: (member) => _getMemberLabel(member, members),
            labelWidgetBuilder: (member) =>
                _buildMemberLabelWidget(context, member, members, availability),
            isSelected: (_) => false,
            availabilityMode: true,
            availabilityState: (member) {
              final r = availability[member.userId];
              if (r == 'yes') return AvailabilityState.available;
              if (r == 'no') return AvailabilityState.notAvailable;
              return AvailabilityState.notResponded;
            },
            onTap: null,
          ),
        const SizedBox(height: Spacing.space8),
        Text(
          'Your Availability',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        Row(
          children: [
            Expanded(
              child: AvailabilityButton(
                label: 'NO',
                icon: AppIcons.close,
                isSelected: userResponse == 'no',
                isPositive: false,
                isLoading: false,
                onPressed: () =>
                    onPerDateResponseChanged?.call(date, isPrimaryDate, 'no'),
              ),
            ),
            const SizedBox(width: Spacing.space12),
            Expanded(
              child: AvailabilityButton(
                label: 'YES',
                icon: AppIcons.check,
                isSelected: userResponse == 'yes',
                isPositive: true,
                isLoading: false,
                onPressed: () =>
                    onPerDateResponseChanged?.call(date, isPrimaryDate, 'yes'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Member label helpers (mirrors gig_form_fields.dart logic)
  // ---------------------------------------------------------------------------

  String _getMemberLabel(MemberVM member, List<MemberVM> allMembers) {
    final disambiguation = _getMemberDisambiguation(member, allMembers);
    if (disambiguation == null) {
      final name = member.name;
      return name.length > 10 ? '${name.substring(0, 9)}…' : name;
    }
    return disambiguation.line1;
  }

  Widget? _buildMemberLabelWidget(
    BuildContext context,
    MemberVM member,
    List<MemberVM> allMembers,
    Map<String, String?> memberAvailability,
  ) {
    final disambiguation = _getMemberDisambiguation(member, allMembers);
    if (disambiguation == null || !disambiguation.requiresTwoLines) return null;

    final textColor = context.colors.textSecondary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          disambiguation.line1,
          style: AppTextStyles.footnote.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: AppFontSizes.caption,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            disambiguation.line2!,
            style: AppTextStyles.navLabel.copyWith(
              color: textColor.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  MemberDisambiguation? _getMemberDisambiguation(
    MemberVM member,
    List<MemberVM> allMembers,
  ) {
    final firstName = member.firstName;
    if (firstName == null || firstName.isEmpty) return null;

    final sameFirstName =
        allMembers.where((m) => m.firstName == firstName).toList();

    if (sameFirstName.length <= 1) {
      final label =
          firstName.length > 10 ? '${firstName.substring(0, 9)}…' : firstName;
      return MemberDisambiguation(line1: label);
    }

    if (member.lastName == null || member.lastName!.isEmpty) {
      final label =
          firstName.length > 10 ? '${firstName.substring(0, 9)}…' : firstName;
      return MemberDisambiguation(line1: label);
    }

    final lastInitial = member.lastName![0].toUpperCase();
    final sameFirstAndInitial = sameFirstName.where((m) {
      final mLastName = m.lastName;
      if (mLastName == null || mLastName.isEmpty) return false;
      return mLastName[0].toUpperCase() == lastInitial;
    }).toList();

    if (sameFirstAndInitial.length <= 1) {
      final label = '$firstName $lastInitial.';
      return MemberDisambiguation(
        line1: label.length > 10 ? '${label.substring(0, 9)}…' : label,
      );
    }

    return MemberDisambiguation(
      line1:
          firstName.length > 10 ? '${firstName.substring(0, 9)}…' : firstName,
      line2: member.lastName!,
      requiresTwoLines: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Recurring Toggle
  // ---------------------------------------------------------------------------

  Widget _buildRecurringToggle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.space12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Make this recurring',
              style: AppTextStyles.callout
                  .copyWith(color: context.colors.textPrimary),
            ),
          ),
          AppSwitch(
            value: isRecurring,
            onChanged: isSaving ? null : onRecurringToggled,
            activeColor: const Color(0xFFfb2c5a),
            activeTrackColor: const Color(0xFFfb2c5a),
          ),
        ],
      ),
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
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kEdInputFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kEdCardBorder),
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

  // ---------------------------------------------------------------------------
  // User Availability Section (for editing potential rehearsals)
  // ---------------------------------------------------------------------------

  Widget _buildUserAvailabilitySection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            margin: const EdgeInsets.only(bottom: Spacing.space12),
            color: context.colors.border,
          ),
          Text(
            'Your Availability',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.space8),
          if (isLoadingUserResponse)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.space8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: AppProgressIndicator(
                    type: ProgressIndicatorType.circular,
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: AvailabilityButton(
                    label: 'NO',
                    icon: AppIcons.close,
                    isSelected: currentUserResponse == 'no',
                    isPositive: false,
                    isLoading: false,
                    onPressed: () => onUserResponseChanged?.call('no'),
                  ),
                ),
                const SizedBox(width: Spacing.space12),
                Expanded(
                  child: AvailabilityButton(
                    label: 'YES',
                    icon: AppIcons.check,
                    isSelected: currentUserResponse == 'yes',
                    isPositive: true,
                    isLoading: false,
                    onPressed: () => onUserResponseChanged?.call('yes'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
