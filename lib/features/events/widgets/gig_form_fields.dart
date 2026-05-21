import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/field_hint.dart';
import '../../../shared/widgets/currency_input_field.dart';
import '../../members/member_vm.dart';
import '../../members/members_controller.dart';
import '../models/event_form_data.dart';
import 'button_group_grid.dart';
import 'event_editor_helpers.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

/// Gig-specific form fields: venue name autocomplete, city autocomplete,
/// potential-gig toggle with member availability, load-in time, and gig pay.
class GigFormFields extends ConsumerWidget {
  const GigFormFields({
    super.key,
    required this.isSaving,
    required this.isEditMode,
    required this.existingEventId,
    // Gig name autocomplete
    required this.nameController,
    required this.venueHintController,
    required this.gigNameFocusNode,
    required this.gigNameSuggestions,
    required this.onGigNameChanged,
    required this.gigNameKey,
    required this.fieldErrors,
    // City autocomplete
    required this.locationController,
    required this.cityHintController,
    required this.gigCityFocusNode,
    required this.gigCitySuggestions,
    required this.onGigCityChanged,
    required this.gigLocationKey,
    // Potential gig
    required this.isPotentialGig,
    required this.forcePotentialOnly,
    required this.onPotentialGigToggled,
    // Member availability (edit mode)
    required this.memberAvailability,
    required this.isLoadingMemberAvailability,
    required this.perDateAvailability,
    required this.isLoadingPerDateAvailability,
    // User availability (edit mode)
    required this.currentUserResponse,
    required this.isLoadingUserResponse,
    required this.onUserResponseChanged,
    // Multi-date (potential gig)
    required this.additionalDates,
    required this.primaryStartTime,
    required this.selectedDate,
    required this.existingGigDateIds,
    required this.onPerDateResponseChanged,
    // Load-in time
    required this.loadInHour,
    required this.loadInMinutes,
    required this.loadInIsPM,
    required this.onLoadInTimeSet,
    required this.onLoadInTimeCleared,
    required this.onLoadInHourChanged,
    required this.onLoadInMinutesChanged,
    required this.onLoadInAmPmChanged,
    // Gig pay
    required this.gigPayController,
    // General
    required this.onMarkDirty,
    required this.currentUserId,
  });

  final bool isSaving;
  final bool isEditMode;
  final String? existingEventId;

  // --- Gig name autocomplete ---
  final TextEditingController nameController;
  final FieldHintController venueHintController;
  final FocusNode gigNameFocusNode;
  final List<String> gigNameSuggestions;
  final ValueChanged<String> onGigNameChanged;
  final GlobalKey gigNameKey;
  final Map<String, String> fieldErrors;

  // --- City autocomplete ---
  final TextEditingController locationController;
  final FieldHintController cityHintController;
  final FocusNode gigCityFocusNode;
  final List<String> gigCitySuggestions;
  final ValueChanged<String> onGigCityChanged;
  final GlobalKey gigLocationKey;

  // --- Potential gig ---
  final bool isPotentialGig;
  final bool forcePotentialOnly;
  final ValueChanged<bool> onPotentialGigToggled;

  // --- Member availability ---
  final Map<String, String?> memberAvailability;
  final bool isLoadingMemberAvailability;
  final Map<String, Map<String, String?>> perDateAvailability;
  final bool isLoadingPerDateAvailability;

  // --- User availability ---
  final String? currentUserResponse;
  final bool isLoadingUserResponse;
  final ValueChanged<String> onUserResponseChanged;

  // --- Multi-date ---
  final List<AdditionalDateEntry> additionalDates;
  final String primaryStartTime;
  final DateTime selectedDate;
  final Map<DateTime, String> existingGigDateIds;
  final void Function(DateTime date, bool isPrimaryDate, String response)
      onPerDateResponseChanged;

  // --- Load-in time ---
  final int? loadInHour;
  final int? loadInMinutes;
  final bool? loadInIsPM;
  final VoidCallback onLoadInTimeSet;
  final VoidCallback onLoadInTimeCleared;
  final ValueChanged<int> onLoadInHourChanged;
  final ValueChanged<int> onLoadInMinutesChanged;
  final ValueChanged<bool> onLoadInAmPmChanged;

  // --- Gig pay ---
  final CurrencyInputController gigPayController;

  // --- General ---
  final VoidCallback onMarkDirty;
  final String? currentUserId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gig Name autocomplete
        _buildGigNameAutocomplete(context),
        const SizedBox(height: Spacing.space16),

        // Potential Gig container with member availability
        _buildPotentialGigContainer(context, ref),
        const SizedBox(height: Spacing.space12),
      ],
    );
  }

  /// Builds the city autocomplete field (called from parent build method).
  Widget buildCityAutocomplete(BuildContext context) {
    return _buildGigCityAutocomplete(context);
  }

  /// Builds the load-in time selector (called from parent build method).
  Widget buildLoadInTimeSelector(BuildContext context) {
    return _buildLoadInTimeSelector(context);
  }

  /// Builds the gig pay field (called from parent build method).
  Widget buildGigPayField() {
    return CurrencyTextField(
      controller: gigPayController,
      label: 'Gig Pay (optional)',
      hint: '\$0.00',
      enabled: !isSaving,
      onChanged: onMarkDirty,
    );
  }

  // ---------------------------------------------------------------------------
  // Gig Name Autocomplete
  // ---------------------------------------------------------------------------

  Widget _buildGigNameAutocomplete(BuildContext context) {
    final hasError = fieldErrors.containsKey('name');
    final errorText = hasError ? fieldErrors['name'] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gig Venue / Festival / Name',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        RawAutocomplete<String>(
          key: gigNameKey,
          textEditingController: nameController,
          focusNode: gigNameFocusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            onGigNameChanged(textEditingValue.text);
            if (textEditingValue.text.length < 2) {
              return const Iterable<String>.empty();
            }
            return gigNameSuggestions;
          },
          onSelected: (String selection) {
            nameController.text = selection;
            nameController.selection = TextSelection.collapsed(
              offset: selection.length,
            );
          },
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController controller,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !isSaving,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
              onChanged: (_) => onMarkDirty(),
              decoration: InputDecoration(
                hintText: 'e.g., The Blue Note, SummerFest 2026',
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
                  borderSide: BorderSide(
                    color: hasError ? AppColors.error : context.colors.border,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(
                    color: hasError ? AppColors.error : context.colors.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(
                    color: hasError ? AppColors.error : AppColors.primary,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: const BorderSide(color: AppColors.error),
                ),
              ),
            );
          },
          optionsViewBuilder: (
            BuildContext context,
            AutocompleteOnSelected<String> onSelected,
            Iterable<String> options,
          ) {
            if (options.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  width: MediaQuery.of(context).size.width -
                      (Spacing.pagePadding * 2),
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
        if (hasError && errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText,
            style: AppTextStyles.footnote.copyWith(color: AppColors.error),
          ),
        ],
        FieldHint(
          text: "Start typing to reuse past venues.",
          controller: venueHintController,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // City Autocomplete
  // ---------------------------------------------------------------------------

  Widget _buildGigCityAutocomplete(BuildContext context) {
    final hasError = fieldErrors.containsKey('city');
    final errorText = hasError ? fieldErrors['city'] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'City',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        RawAutocomplete<String>(
          key: gigLocationKey,
          textEditingController: locationController,
          focusNode: gigCityFocusNode,
          optionsBuilder: (TextEditingValue textEditingValue) {
            onGigCityChanged(textEditingValue.text);
            if (textEditingValue.text.length < 2) {
              return const Iterable<String>.empty();
            }
            return gigCitySuggestions;
          },
          onSelected: (String selection) {
            locationController.text = selection;
            locationController.selection = TextSelection.collapsed(
              offset: selection.length,
            );
          },
          fieldViewBuilder: (
            BuildContext context,
            TextEditingController controller,
            FocusNode focusNode,
            VoidCallback onFieldSubmitted,
          ) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !isSaving,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
              onChanged: (_) => onMarkDirty(),
              decoration: InputDecoration(
                hintText: 'e.g., Chicago, IL',
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
                  borderSide: BorderSide(
                    color: hasError ? AppColors.error : context.colors.border,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(
                    color: hasError ? AppColors.error : context.colors.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: BorderSide(
                    color: hasError ? AppColors.error : AppColors.primary,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                  borderSide: const BorderSide(color: AppColors.error),
                ),
              ),
            );
          },
          optionsViewBuilder: (
            BuildContext context,
            AutocompleteOnSelected<String> onSelected,
            Iterable<String> options,
          ) {
            if (options.isEmpty) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  width: MediaQuery.of(context).size.width -
                      (Spacing.pagePadding * 2),
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
        if (hasError && errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText,
            style: AppTextStyles.footnote.copyWith(color: AppColors.error),
          ),
        ],
        FieldHint(
          text: "Auto-fills based on past gigs.",
          controller: cityHintController,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Potential Gig Container
  // ---------------------------------------------------------------------------

  Widget _buildPotentialGigContainer(BuildContext context, WidgetRef ref) {
    final membersState = ref.watch(membersProvider);
    final members = membersState.members;

    final isMultiDateEditMode = isEditMode &&
        existingEventId != null &&
        additionalDates.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(Spacing.space12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: isPotentialGig
            ? Border.all(color: AppColors.primary, width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: Title + Toggle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Potential Gig',
                      style: AppTextStyles.callout.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Requires member confirmation before gig is official.',
                      style: AppTextStyles.footnote.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isPotentialGig,
                onChanged: (isSaving || forcePotentialOnly)
                    ? null
                    : onPotentialGigToggled,
                activeTrackColor: AppColors.primary,
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return null;
                }),
              ),
            ],
          ),

          // Member grid (only visible when toggle is ON)
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: isPotentialGig
                ? isMultiDateEditMode
                    ? _buildMultiDateAvailabilitySection(
                        context, members, membersState.isLoading)
                    : Column(
                        children: [
                          _buildMemberSelectionGrid(
                              context, members, membersState.isLoading),
                          if (isEditMode && existingEventId != null)
                            _buildUserAvailabilitySection(context),
                        ],
                      )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Multi-Date Availability
  // ---------------------------------------------------------------------------

  Widget _buildMultiDateAvailabilitySection(
    BuildContext context,
    List<MemberVM> members,
    bool isLoading,
  ) {
    // Build (date, timeDisplay) pairs sorted by date
    final allEntries = <(DateTime, String)>[
      (selectedDate, primaryStartTime),
      ...additionalDates.map((e) => (e.date, e.startTimeDisplay)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Spacing.space12),
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
    final dateKey = isPrimaryDate ? 'primary' : existingGigDateIds[date];
    final availability = dateKey != null
        ? perDateAvailability[dateKey] ?? {}
        : <String, String?>{};

    final userResponse =
        currentUserId != null ? availability[currentUserId] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date + time header
        Container(
          padding: const EdgeInsets.symmetric(vertical: Spacing.space8),
          child: Text(
            '${_formatDateDisplay(date)} · $timeDisplay',
            style: AppTextStyles.calloutEmphasized.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),

        // Member availability grid
        if (isLoading || isLoadingPerDateAvailability)
          Container(
            padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
            child: Text(
              'No members to notify',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          )
        else
          ButtonGroupGrid<MemberVM>(
            items: members,
            labelBuilder: (member) => _getMemberLabel(member, members),
            labelWidgetBuilder: (member) =>
                _buildMemberLabelWidget(context, member, members, availability),
            isSelected: (member) => false,
            availabilityMode: true,
            availabilityState: (member) {
              final response = availability[member.userId];
              if (response == 'yes') return AvailabilityState.available;
              if (response == 'no') return AvailabilityState.notAvailable;
              return AvailabilityState.notResponded;
            },
            onTap: null,
            columns: 4,
            buttonHeight: 48,
          ),

        // Your Availability for this date
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
                    onPerDateResponseChanged(date, isPrimaryDate, 'no'),
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
                    onPerDateResponseChanged(date, isPrimaryDate, 'yes'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // User Availability Section (single-date)
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
                  child: CircularProgressIndicator(strokeWidth: 2),
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
                    onPressed: () => onUserResponseChanged('no'),
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
                    onPressed: () => onUserResponseChanged('yes'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Member Selection Grid
  // ---------------------------------------------------------------------------

  Widget _buildMemberSelectionGrid(
      BuildContext context, List<MemberVM> members, bool isLoading) {
    if (isLoading || isLoadingMemberAvailability) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
        child: Text(
          'No members to notify',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.space12),
      child: ButtonGroupGrid<MemberVM>(
        items: members,
        labelBuilder: (member) => _getMemberLabel(member, members),
        labelWidgetBuilder: (member) => _buildMemberLabelWidget(
            context, member, members, memberAvailability),
        isSelected: (member) => false,
        availabilityMode: true,
        availabilityState: (member) {
          final response = memberAvailability[member.userId];
          if (response == 'yes') return AvailabilityState.available;
          if (response == 'no') return AvailabilityState.notAvailable;
          return AvailabilityState.notResponded;
        },
        onTap: null,
        columns: 4,
        buttonHeight: 48,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Load-in Time Selector
  // ---------------------------------------------------------------------------

  Widget _buildLoadInTimeSelector(BuildContext context) {
    if (loadInHour == null || loadInMinutes == null || loadInIsPM == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Load-in Time',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: isSaving ? null : onLoadInTimeSet,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    AppIcons.add,
                    color: context.colors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Set Load-in Time (Optional)',
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Load-in Time',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            GestureDetector(
              onTap: isSaving ? null : onLoadInTimeCleared,
              child: Text(
                'Clear',
                style: AppTextStyles.footnote.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            // Hour dropdown
            Expanded(
              child: EventDropdown<int>(
                value: loadInHour!,
                items: List.generate(12, (i) => i + 1),
                onChanged: (v) {
                  if (v != null) onLoadInHourChanged(v);
                },
                labelBuilder: (v) => v.toString(),
                isSaving: isSaving,
              ),
            ),
            const SizedBox(width: 8),
            // Minutes dropdown
            Expanded(
              child: EventDropdown<int>(
                value: loadInMinutes!,
                items: const [0, 15, 30, 45],
                onChanged: (v) {
                  if (v != null) onLoadInMinutesChanged(v);
                },
                labelBuilder: (v) => ':${v.toString().padLeft(2, '0')}',
                isSaving: isSaving,
              ),
            ),
            const SizedBox(width: 8),
            // AM/PM toggle
            Container(
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AmPmToggleButton(
                    label: 'AM',
                    isSelected: !loadInIsPM!,
                    isSaving: isSaving,
                    onTap: () => onLoadInAmPmChanged(false),
                  ),
                  AmPmToggleButton(
                    label: 'PM',
                    isSelected: loadInIsPM!,
                    isSaving: isSaving,
                    onTap: () => onLoadInAmPmChanged(true),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Member Label Helpers
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
    Map<String, String?> availability,
  ) {
    final disambiguation = _getMemberDisambiguation(member, allMembers);
    if (disambiguation == null || !disambiguation.requiresTwoLines) {
      return null;
    }

    final response = availability[member.userId];
    final textColor = (response == 'yes' || response == 'no')
        ? Colors.white
        : context.colors.textSecondary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          disambiguation.line1,
          style: AppTextStyles.footnote.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
            fontSize: 12,
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
  // Utilities
  // ---------------------------------------------------------------------------

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
}
