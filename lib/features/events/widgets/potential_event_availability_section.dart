import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/app_icons.dart';
import '../../../components/ui/app_button.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../members/member_vm.dart';

class PotentialEventDateAvailability {
  final String responseKey;
  final DateTime date;
  final String timeRange;

  const PotentialEventDateAvailability({
    required this.responseKey,
    required this.date,
    required this.timeRange,
  });
}

class PotentialEventAvailabilitySection extends StatefulWidget {
  final List<PotentialEventDateAvailability> dates;
  final List<MemberVM> members;
  final bool isLoadingMembers;
  final String? currentUserId;
  final Future<Map<String, Map<String, String?>>> Function() loadResponses;
  final Future<void> Function(String responseKey, String response) onRespond;
  final Set<String> selectedOfficialDateKeys;
  final FutureOr<void> Function(PotentialEventDateAvailability date)?
      onMakeOfficial;

  const PotentialEventAvailabilitySection({
    super.key,
    required this.dates,
    required this.members,
    required this.isLoadingMembers,
    required this.currentUserId,
    required this.loadResponses,
    required this.onRespond,
    this.selectedOfficialDateKeys = const {},
    this.onMakeOfficial,
  });

  @override
  State<PotentialEventAvailabilitySection> createState() =>
      _PotentialEventAvailabilitySectionState();
}

class _PotentialEventAvailabilitySectionState
    extends State<PotentialEventAvailabilitySection> {
  late Future<Map<String, Map<String, String?>>> _responses;
  Map<String, Map<String, String?>>? _localResponses;
  final Set<String> _savingDateKeys = {};
  String? _makingOfficialDateKey;

  @override
  void initState() {
    super.initState();
    _responses = widget.loadResponses();
  }

  @override
  void didUpdateWidget(PotentialEventAvailabilitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKeys = oldWidget.dates.map((date) => date.responseKey).join('|');
    final newKeys = widget.dates.map((date) => date.responseKey).join('|');
    if (oldKeys != newKeys) {
      _responses = widget.loadResponses();
      _localResponses = null;
    }
  }

  Future<void> _handleResponse(
    String responseKey,
    String response,
  ) async {
    final userId = widget.currentUserId;
    if (userId == null || _savingDateKeys.contains(responseKey)) return;

    final previousResponse = _localResponses?[responseKey]?[userId];
    setState(() {
      _savingDateKeys.add(responseKey);
      _localResponses?[responseKey]?[userId] = response;
    });

    try {
      await widget.onRespond(responseKey, response);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localResponses?[responseKey]?[userId] = previousResponse;
      });
      showErrorSnackBar(
        context,
        message: 'Could not update your availability. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _savingDateKeys.remove(responseKey));
      }
    }
  }

  Future<void> _handleMakeOfficial(
    PotentialEventDateAvailability date,
  ) async {
    if (_makingOfficialDateKey != null) return;

    setState(() => _makingOfficialDateKey = date.responseKey);
    try {
      await widget.onMakeOfficial?.call(date);
    } catch (_) {
      if (!mounted) return;
      showErrorSnackBar(
        context,
        message: 'Could not make this date official. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _makingOfficialDateKey = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Map<String, String?>>>(
      future: _responses,
      builder: (context, snapshot) {
        if (widget.isLoadingMembers ||
            snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.space24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
              vertical: Spacing.space16,
            ),
            child: Text(
              'Availability could not be loaded.',
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textMuted,
              ),
            ),
          );
        }

        _localResponses ??= {
          for (final entry in (snapshot.data ?? const {}).entries)
            entry.key: Map<String, String?>.from(entry.value),
        };
        final responsesByDate = _localResponses!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final date in widget.dates)
              Container(
                key: ValueKey('potential-date-${date.responseKey}'),
                margin: const EdgeInsets.fromLTRB(
                  Spacing.pagePadding,
                  Spacing.space8,
                  Spacing.pagePadding,
                  Spacing.space8,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: Spacing.space8,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surfaceElevated,
                  border: Border.all(color: context.colors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.space16,
                        Spacing.space8,
                        Spacing.space16,
                        Spacing.space8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatFullDate(date.date),
                            style: AppTextStyles.title3.copyWith(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: Spacing.space4),
                          Text(
                            date.timeRange,
                            style: AppTextStyles.headline.copyWith(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.onMakeOfficial != null) ...[
                            const SizedBox(height: Spacing.space12),
                            AppButton(
                              label: widget.selectedOfficialDateKeys
                                      .contains(date.responseKey)
                                  ? 'Selected'
                                  : 'Make Official',
                              variant: widget.selectedOfficialDateKeys
                                      .contains(date.responseKey)
                                  ? AppButtonVariant.primary
                                  : AppButtonVariant.outlined,
                              fullWidth: true,
                              isLoading:
                                  _makingOfficialDateKey == date.responseKey,
                              onPressed: _makingOfficialDateKey == null
                                  ? () => _handleMakeOfficial(date)
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.members.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.space16,
                          vertical: Spacing.space8,
                        ),
                        child: Text(
                          'No band members found.',
                          style: AppTextStyles.callout.copyWith(
                            color: context.colors.textMuted,
                          ),
                        ),
                      )
                    else
                      for (final member in widget.members)
                        _MemberAvailabilityRow(
                          name: member.name,
                          response: responsesByDate[date.responseKey]
                              ?[member.userId],
                        ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.space16,
                        Spacing.space12,
                        Spacing.space16,
                        Spacing.space8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: 'NO',
                              icon: AppIcons.close,
                              variant: AppButtonVariant.destructive,
                              isLoading:
                                  _savingDateKeys.contains(date.responseKey),
                              onPressed: widget.currentUserId == null
                                  ? null
                                  : () => _handleResponse(
                                        date.responseKey,
                                        'no',
                                      ),
                            ),
                          ),
                          const SizedBox(width: Spacing.space12),
                          Expanded(
                            child: AppButton(
                              label: 'YES',
                              icon: AppIcons.success,
                              backgroundColor: context.colors.success,
                              isLoading:
                                  _savingDateKeys.contains(date.responseKey),
                              onPressed: widget.currentUserId == null
                                  ? null
                                  : () => _handleResponse(
                                        date.responseKey,
                                        'yes',
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatFullDate(DateTime date) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
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
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _MemberAvailabilityRow extends StatelessWidget {
  final String name;
  final String? response;

  const _MemberAvailabilityRow({
    required this.name,
    required this.response,
  });

  @override
  Widget build(BuildContext context) {
    final isYes = response == 'yes';
    final isNo = response == 'no';
    final label = isYes ? 'Yes' : (isNo ? 'No' : '??');
    final badgeColor = isYes
        ? context.colors.success
        : (isNo ? AppColors.primary : context.colors.textMuted);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space8,
      ),
      child: Row(
        children: [
          SizedBox(
            key: const ValueKey('availability-badge'),
            width: 44,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                vertical: Spacing.space4,
              ),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.16),
                border: Border.all(color: badgeColor),
                borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              ),
              child: Text(
                label,
                style: AppTextStyles.footnote.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: Spacing.space12),
          Expanded(
            child: Text(
              name,
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
