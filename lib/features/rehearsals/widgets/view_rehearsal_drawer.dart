import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/models/rehearsal.dart';
import '../../../app/services/supabase_client.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/app_icons.dart';
import '../../../app/theme/app_animations.dart';
import '../../../app/utils/time_formatter.dart';
import '../../../components/ui/sheet_footer.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../calendar/calendar_controller.dart';
import '../../events/events_repository.dart';
import '../../events/models/event_form_data.dart';
import '../../events/widgets/potential_event_availability_section.dart';
import '../../gigs/gig_controller.dart';
import '../../members/members_controller.dart';
import '../../setlists/setlist_detail_screen.dart';
import '../../setlists/setlists_screen.dart' show setlistsProvider;
import '../rehearsal_response_repository.dart';
import '../rehearsal_controller.dart';
import 'rehearsal_notes_sheet.dart';

class ViewRehearsalDrawer extends ConsumerStatefulWidget {
  final Rehearsal rehearsal;
  final String bandTimezone;
  final bool canEdit;
  final VoidCallback onEdit;

  const ViewRehearsalDrawer({
    super.key,
    required this.rehearsal,
    required this.bandTimezone,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  ConsumerState<ViewRehearsalDrawer> createState() =>
      _ViewRehearsalDrawerState();

  static Future<void> show(
    BuildContext context, {
    required Rehearsal rehearsal,
    required String bandTimezone,
    required bool canEdit,
    required VoidCallback onEdit,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ViewRehearsalDrawer(
        rehearsal: rehearsal,
        bandTimezone: bandTimezone,
        canEdit: canEdit,
        onEdit: onEdit,
      ),
    );
  }
}

class _ViewRehearsalDrawerState extends ConsumerState<ViewRehearsalDrawer> {
  final Set<String> _selectedOfficialDateKeys = {};
  bool _isCreatingRehearsals = false;

  Rehearsal get rehearsal => widget.rehearsal;
  bool get canEdit => widget.canEdit;
  VoidCallback get onEdit => widget.onEdit;

  void _handleEdit(BuildContext context) {
    Navigator.of(context).pop();
    onEdit();
  }

  void _toggleOfficialDate(PotentialEventDateAvailability selectedDate) {
    setState(() {
      if (!_selectedOfficialDateKeys.add(selectedDate.responseKey)) {
        _selectedOfficialDateKeys.remove(selectedDate.responseKey);
      }
    });
  }

  EventFormData _officialFormDataFor(
    PotentialEventDateAvailability selectedDate,
  ) {
    final originalData = EventFormData.fromRehearsal(rehearsal);
    final selectedEntry = selectedDate.responseKey == 'primary'
        ? null
        : originalData.additionalDates.firstWhere(
            (entry) => entry.date == selectedDate.date,
          );
    return originalData.copyWith(
      date: selectedDate.date,
      hour: selectedEntry?.hour,
      minutes: selectedEntry?.minutes,
      isPM: selectedEntry?.isPM,
      isPotentialGig: false,
      additionalDates: const [],
    );
  }

  Future<void> _createSelectedRehearsals(
    List<PotentialEventDateAvailability> availabilityDates,
  ) async {
    if (_selectedOfficialDateKeys.isEmpty || _isCreatingRehearsals) return;

    final selectedDates = availabilityDates
        .where(
          (date) => _selectedOfficialDateKeys.contains(date.responseKey),
        )
        .toList();
    setState(() => _isCreatingRehearsals = true);

    try {
      final repository = ref.read(eventsRepositoryProvider);
      await repository.updateRehearsal(
        rehearsalId: rehearsal.id,
        bandId: rehearsal.bandId,
        formData: _officialFormDataFor(selectedDates.first),
        wasRecurring: rehearsal.isRecurring,
      );
      for (final selectedDate in selectedDates.skip(1)) {
        await repository.createRehearsal(
          bandId: rehearsal.bandId,
          formData: _officialFormDataFor(selectedDate),
        );
      }

      await Future.wait([
        ref.read(gigProvider.notifier).refresh(),
        ref.read(rehearsalProvider.notifier).refresh(),
        ref
            .read(calendarProvider.notifier)
            .invalidateAndRefresh(bandId: rehearsal.bandId),
      ]);

      if (!mounted) return;
      final count = selectedDates.length;
      showSuccessSnackBar(
        context,
        message: count == 1 ? 'Rehearsal created' : '$count rehearsals created',
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        message: 'Could not create the rehearsal. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingRehearsals = false);
      }
    }
  }

  String _formatFullDate(DateTime date) {
    const days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
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
    return '${days[date.weekday % 7]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatRecurrenceIndicator() {
    if (!rehearsal.isRecurring) return '';

    final buffer = StringBuffer();

    // Frequency
    switch (rehearsal.recurrenceFrequency) {
      case 'weekly':
        buffer.write('Weekly');
        break;
      case 'biweekly':
        buffer.write('Biweekly');
        break;
      case 'monthly':
        buffer.write('Monthly');
        break;
      default:
        buffer.write('Recurring');
    }

    // Days
    if (rehearsal.recurrenceDays != null &&
        rehearsal.recurrenceDays!.isNotEmpty) {
      buffer.write(' · ');
      final dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
      final days = rehearsal.recurrenceDays!
          .map((index) => dayNames[index % 7])
          .join('/');
      buffer.write(days);
    }

    // Until date
    if (rehearsal.recurrenceUntil != null) {
      buffer.write(' until ');
      final until = rehearsal.recurrenceUntil!;
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
      buffer.write('${months[until.month - 1]} ${until.day}');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final setlistsState = ref.watch(setlistsProvider);
    final membersState = ref.watch(membersProvider);
    if (rehearsal.isPotential &&
        membersState.members.isEmpty &&
        !membersState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(membersProvider.notifier).loadMembers(rehearsal.bandId);
      });
    }
    final setlistName = rehearsal.setlistId != null
        ? setlistsState.setlists
            .where((s) => s.id == rehearsal.setlistId)
            .firstOrNull
            ?.name
        : null;
    final availabilityDates = [
      PotentialEventDateAvailability(
        responseKey: 'primary',
        date: rehearsal.date,
        timeRange:
            TimeFormatter.formatRange(rehearsal.startTime, rehearsal.endTime),
      ),
      for (final additionalDate in rehearsal.additionalDates)
        PotentialEventDateAvailability(
          responseKey: additionalDate.id,
          date: additionalDate.date,
          timeRange: TimeFormatter.formatRange(
            additionalDate.startTime ?? rehearsal.startTime,
            rehearsal.endTime,
          ),
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.95,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Spacing.space16),

                  // Header block: date + time + location
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.pagePadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (rehearsal.isPotential)
                          Text(
                            'Potential Rehearsal',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: context.colors.textPrimary,
                                ),
                          )
                        else ...[
                          Text(
                            _formatFullDate(rehearsal.date),
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: context.colors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: Spacing.space4),
                          Text(
                            rehearsal.timeRange,
                            style: AppTextStyles.title3.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ],
                        // Location (if present)
                        if (rehearsal.location.isNotEmpty) ...[
                          const SizedBox(height: Spacing.space4),
                          Text(
                            rehearsal.location,
                            style: AppTextStyles.callout.copyWith(
                              color: context.colors.textMuted,
                            ),
                          ),
                        ],
                        // Recurrence indicator (if recurring)
                        if (rehearsal.isRecurring) ...[
                          const SizedBox(height: Spacing.space4),
                          Text(
                            _formatRecurrenceIndicator(),
                            style: AppTextStyles.callout.copyWith(
                              color: context.colors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: Spacing.space16),
                  const Divider(height: 1),

                  if (rehearsal.isPotential)
                    PotentialEventAvailabilitySection(
                      dates: availabilityDates,
                      members: membersState.members,
                      isLoadingMembers: membersState.isLoading,
                      currentUserId: supabase.auth.currentUser?.id,
                      loadResponses: () => ref
                          .read(rehearsalResponseRepositoryProvider)
                          .fetchAllDateResponses(
                            rehearsalId: rehearsal.id,
                            bandId: rehearsal.bandId,
                            rehearsalDateIds: rehearsal.additionalDates
                                .map((date) => date.id)
                                .toList(),
                          ),
                      onRespond: (responseKey, response) async {
                        final userId = supabase.auth.currentUser?.id;
                        if (userId == null) return;
                        await ref
                            .read(rehearsalResponseRepositoryProvider)
                            .upsertResponseForDate(
                              rehearsalId: rehearsal.id,
                              rehearsalDateId:
                                  responseKey == 'primary' ? null : responseKey,
                              userId: userId,
                              response: response,
                            );
                        ref.invalidate(currentUserRehearsalResponsesProvider);
                        ref.invalidate(
                            currentUserRehearsalAllDateResponsesProvider);
                        ref.invalidate(
                            potentialRehearsalResponseSummariesProvider);
                      },
                      selectedOfficialDateKeys: _selectedOfficialDateKeys,
                      onMakeOfficial: canEdit ? _toggleOfficialDate : null,
                    ),

                  // Detail rows
                  if (rehearsal.setlistId != null && setlistName != null)
                    _DetailRow(
                      label: 'Setlist',
                      value: setlistName,
                      showChevron: true,
                      onTap: () => Navigator.of(context).push(
                        fadeSlideRoute(
                          page: SetlistDetailScreen(
                            setlistId: rehearsal.setlistId!,
                            setlistName: setlistName,
                          ),
                        ),
                      ),
                    ),

                  if (rehearsal.notes != null && rehearsal.notes!.isNotEmpty)
                    _DetailRow(
                      label: 'Notes',
                      value: '',
                      showChevron: true,
                      onTap: () => RehearsalNotesSheet.show(
                        context,
                        notes: rehearsal.notes!,
                      ),
                    ),

                  const SizedBox(height: Spacing.space24),
                ],
              ),
            ),
          ),

          // Footer
          SheetFooter(
            primaryLabel: _selectedOfficialDateKeys.isEmpty
                ? 'Done'
                : _selectedOfficialDateKeys.length == 1
                    ? 'Create Rehearsal'
                    : 'Create (${_selectedOfficialDateKeys.length}) Rehearsals',
            primaryFlex: _selectedOfficialDateKeys.isEmpty ? 1 : 2,
            fitActionLabels: _selectedOfficialDateKeys.isNotEmpty,
            primaryIsLoading: _isCreatingRehearsals,
            onPrimary: _selectedOfficialDateKeys.isEmpty
                ? () => Navigator.of(context).pop()
                : () => _createSelectedRehearsals(availabilityDates),
            cancelLabel: _selectedOfficialDateKeys.isEmpty ? 'Edit' : 'Cancel',
            onCancel: !canEdit
                ? null
                : _selectedOfficialDateKeys.isEmpty
                    ? () => _handleEdit(context)
                    : () => setState(_selectedOfficialDateKeys.clear),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showChevron;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.label,
    required this.value,
    this.showChevron = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.pagePadding,
        vertical: Spacing.space12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: Spacing.space8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.start,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: Spacing.space4),
            Icon(
              AppIcons.forward,
              size: 16,
              color: context.colors.textMuted,
            ),
          ],
        ],
      ),
    );

    return Column(
      children: [
        onTap != null ? InkWell(onTap: onTap, child: row) : row,
        Divider(height: 1, color: context.colors.border),
      ],
    );
  }
}
