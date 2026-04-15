import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../components/ui/field_hint.dart';
import '../../setlists/models/setlist.dart';
import '../../setlists/setlists_screen.dart' show setlistsProvider;
import '../models/event_form_data.dart';
import 'event_editor_helpers.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

/// Shared form fields used by all event types: error banner, date picker,
/// time selector, duration selector, setlist selector, and notes field.
class EventFormFields extends ConsumerWidget {
  const EventFormFields({
    super.key,
    required this.eventType,
    required this.isSaving,
    required this.errorMessage,
    // Date state
    required this.selectedDate,
    required this.onDateTap,
    // Multi-date state (potential gigs only)
    required this.isPotentialGig,
    required this.isMultiDate,
    required this.additionalDates,
    required this.onAdditionalDateTap,
    required this.onAdditionalDateRemoved,
    required this.onAdditionalDateAdded,
    // Time state
    required this.selectedHour,
    required this.selectedMinutes,
    required this.isPM,
    required this.onHourChanged,
    required this.onMinutesChanged,
    required this.onAmPmChanged,
    // Duration state
    required this.durationMinutes,
    required this.onDurationDecremented,
    required this.onDurationIncremented,
    // Setlist state
    required this.selectedSetlistId,
    required this.onSetlistSelected,
    required this.onNavigateToCreateSetlist,
    // Notes
    required this.notesController,
    required this.notesHintController,
  });

  final EventType eventType;
  final bool isSaving;
  final String? errorMessage;

  // --- Date ---
  final DateTime selectedDate;
  final VoidCallback onDateTap;

  // --- Multi-date (potential gigs only) ---
  final bool isPotentialGig;
  final bool isMultiDate;
  final List<DateTime> additionalDates;
  final ValueChanged<int> onAdditionalDateTap;
  final ValueChanged<int> onAdditionalDateRemoved;
  final VoidCallback onAdditionalDateAdded;

  // --- Time ---
  final int selectedHour;
  final int selectedMinutes;
  final bool isPM;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinutesChanged;
  final ValueChanged<bool> onAmPmChanged;

  // --- Duration ---
  final int durationMinutes;
  final VoidCallback onDurationDecremented;
  final VoidCallback onDurationIncremented;

  // --- Setlist ---
  final String? selectedSetlistId;
  final void Function(String? id, String? name) onSetlistSelected;
  final VoidCallback onNavigateToCreateSetlist;

  // --- Notes ---
  final TextEditingController notesController;
  final FieldHintController notesHintController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Error banner
        if (errorMessage != null) ...[
          _buildErrorBanner(),
          const SizedBox(height: Spacing.space16),
        ],

        // Date Picker
        _buildDatePicker(context),

        const SizedBox(height: Spacing.space16),

        // Start Time Selectors
        _buildTimeSelector(context),

        const SizedBox(height: Spacing.space16),

        // Duration Selector
        _buildDurationSelector(context),

        const SizedBox(height: Spacing.space16),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Error Banner
  // ---------------------------------------------------------------------------

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            AppIcons.error,
            color: AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage!,
              style: AppTextStyles.callout.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Date Picker
  // ---------------------------------------------------------------------------

  Widget _buildDatePicker(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Date',
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Primary date picker
        _buildSingleDatePicker(
          context: context,
          date: selectedDate,
          onTap: isSaving ? null : onDateTap,
          showRemoveButton: false,
        ),
        // Additional date pickers (shown if any additional dates exist)
        if (additionalDates.isNotEmpty) ...[
          for (int i = 0; i < additionalDates.length; i++) ...[
            const SizedBox(height: 8),
            _buildSingleDatePicker(
              context: context,
              date: additionalDates[i],
              onTap: isSaving ? null : () => onAdditionalDateTap(i),
              showRemoveButton: true,
              onRemove: () => onAdditionalDateRemoved(i),
            ),
          ],
        ],
        // Always show "+ Add Another Date" when potential gig
        if (eventType == EventType.gig && isPotentialGig) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: isSaving ? null : onAdditionalDateAdded,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                border: Border.all(
                  color: context.colors.border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.add, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Add another date',
                    style: AppTextStyles.callout.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSingleDatePicker({
    required BuildContext context,
    required DateTime date,
    required VoidCallback? onTap,
    required bool showRemoveButton,
    bool showAddButton = false,
    VoidCallback? onRemove,
    VoidCallback? onAdd,
  }) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    AppIcons.calendar,
                    size: 18,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _formatDateDisplay(date),
                    style: AppTextStyles.callout.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showRemoveButton || showAddButton) ...[
          const SizedBox(width: 8),
          if (showRemoveButton)
            GestureDetector(
              onTap: isSaving ? null : onRemove,
              child: Container(
                width: 36,
                height: 44,
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.colors.border),
                ),
                child: Icon(
                  AppIcons.remove,
                  size: 20,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          if (showRemoveButton && showAddButton) const SizedBox(width: 4),
          if (showAddButton)
            GestureDetector(
              onTap: isSaving ? null : onAdd,
              child: Container(
                width: 36,
                height: 44,
                decoration: BoxDecoration(
                  color: context.colors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.colors.border),
                ),
                child: const Icon(
                  AppIcons.add,
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Time Selector
  // ---------------------------------------------------------------------------

  Widget _buildTimeSelector(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start Time',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: EventDropdown<int>(
                value: selectedHour,
                items: List.generate(12, (i) => i + 1),
                onChanged: (v) {
                  if (v != null) onHourChanged(v);
                },
                labelBuilder: (v) => v.toString(),
                isSaving: isSaving,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: EventDropdown<int>(
                value: selectedMinutes,
                items: const [0, 15, 30, 45],
                onChanged: (v) {
                  if (v != null) onMinutesChanged(v);
                },
                labelBuilder: (v) => ':${v.toString().padLeft(2, '0')}',
                isSaving: isSaving,
              ),
            ),
            const SizedBox(width: 8),
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
                    isSelected: !isPM,
                    isSaving: isSaving,
                    onTap: () => onAmPmChanged(false),
                  ),
                  AmPmToggleButton(
                    label: 'PM',
                    isSelected: isPM,
                    isSaving: isSaving,
                    onTap: () => onAmPmChanged(true),
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
  // Duration Selector
  // ---------------------------------------------------------------------------

  Widget _buildDurationSelector(BuildContext context) {
    const minDuration = 15;
    const roseColor = AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Duration',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: isSaving || durationMinutes <= minDuration
                  ? null
                  : onDurationDecremented,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: durationMinutes <= minDuration
                        ? roseColor.withValues(alpha: 0.4)
                        : roseColor,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '-15',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: durationMinutes <= minDuration
                          ? roseColor.withValues(alpha: 0.4)
                          : roseColor,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Center(
                child: Text(
                  _formatDurationMinutes(durationMinutes),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: isSaving ? null : onDurationIncremented,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: roseColor, width: 2),
                ),
                child: Center(
                  child: Text(
                    '+15',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: roseColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Setlist Selector
  // ---------------------------------------------------------------------------

  /// Builds the setlist selector. Called by parent build method as a separate
  /// section below the main EventFormFields.build() output.
  Widget buildSetlistSelector(BuildContext context, WidgetRef ref) {
    final setlistsState = ref.watch(setlistsProvider);
    final setlists = setlistsState.setlists;
    final isLoading = setlistsState.isLoading;
    final error = setlistsState.error;

    final userSetlists = _sortSetlists(setlists);
    final hasNoSetlists = userSetlists.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Setlist',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        if (isLoading)
          Container(
            height: 42,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Setting up the stage...',
                  style: AppTextStyles.footnote.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
              ],
            ),
          )
        else if (error != null && setlists.isEmpty)
          Container(
            height: 42,
            alignment: Alignment.centerLeft,
            child: Text(
              "Couldn't load setlists",
              style: AppTextStyles.footnote.copyWith(color: AppColors.error),
            ),
          )
        else
          SizedBox(
            height: 42,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSetlistPill(
                    context: context,
                    id: null,
                    name: 'None',
                    isSelected: selectedSetlistId == null,
                  ),
                  const SizedBox(width: 8),
                  if (hasNoSetlists)
                    GestureDetector(
                      onTap: isSaving ? null : onNavigateToCreateSetlist,
                      child: Text(
                        '+ Create Setlist',
                        style: AppTextStyles.footnote.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    ...userSetlists.map((setlist) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildSetlistPill(
                          context: context,
                          id: setlist.id,
                          name: setlist.name,
                          isSelected: selectedSetlistId == setlist.id,
                          isCatalog: setlist.isCatalog,
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSetlistPill({
    required BuildContext context,
    required String? id,
    required String name,
    required bool isSelected,
    bool isCatalog = false,
  }) {
    return GestureDetector(
      onTap: isSaving
          ? null
          : () {
              onSetlistSelected(id, id != null ? name : null);
              HapticFeedback.selectionClick();
            },
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : context.colors.background,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(
            color: isSelected ? AppColors.primary : context.colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCatalog) ...[
              Icon(
                AppIcons.library,
                size: 14,
                color: isSelected ? Colors.white : context.colors.textSecondary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              name,
              style: AppTextStyles.footnote.copyWith(
                color: isSelected ? Colors.white : context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Notes Section
  // ---------------------------------------------------------------------------

  /// Builds the notes text field and hint. Called by parent build method
  /// as a separate section.
  Widget buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EventTextField(
          label: 'Notes (optional)',
          controller: notesController,
          hint: 'Any additional details...',
          maxLines: 3,
          isSaving: isSaving,
          onChanged: null,
        ),
        FieldHint(
          text: "Optional — visible only to band members.",
          controller: notesHintController,
        ),
      ],
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

  static String _formatDurationMinutes(int minutes) {
    if (minutes < 60) {
      return '${minutes}m';
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) {
      return '${hours}h';
    }
    return '${hours}h ${mins}m';
  }

  static List<Setlist> _sortSetlists(List<Setlist> setlists) {
    final filtered = setlists.where((s) => !s.isCatalog).toList();
    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return filtered;
  }
}
