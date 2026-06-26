import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/shared/utils/snackbar_helper.dart';
import 'package:bandroadie/features/calendar/models/one_calendar_preferences.dart';
import 'package:bandroadie/features/calendar/one_calendar_preferences_controller.dart';
import 'package:bandroadie/features/bands/active_band_controller.dart';

// ============================================================================
// ONE CALENDAR SETTINGS SCREEN
// Allows users to share block-out dates across multiple bands
// ============================================================================

class OneCalendarSettingsScreen extends ConsumerWidget {
  const OneCalendarSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(oneCalendarPreferencesProvider);
    final activeBandState = ref.watch(activeBandProvider);
    final userBands = activeBandState.userBands;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(AppIcons.arrowLeft, color: context.colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'One Calendar',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: prefsAsync.when(
        data: (prefs) => _buildContent(context, ref, prefs, userBands),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.pagePadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  AppIcons.error,
                  color: context.colors.error,
                  size: 48,
                ),
                const SizedBox(height: Spacing.space16),
                Text(
                  'Failed to load preferences',
                  style: AppTextStyles.title3.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: Spacing.space8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space24),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(oneCalendarPreferencesProvider);
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    OneCalendarPreferences prefs,
    List userBands,
  ) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.pagePadding),
      children: [
        // Explainer text
        Text(
          'Share your unavailable dates across all your bands in one place. '
          'Block out a date once and it applies everywhere.',
          style: AppTextStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.space24),

        // Master toggle: One Calendar
        _MasterToggleCard(
          enabled: prefs.oneCalendarEnabled,
          onChanged: (value) async {
            try {
              await ref
                  .read(oneCalendarPreferencesProvider.notifier)
                  .toggleOneCalendar(value);
            } catch (e) {
              if (context.mounted) {
                showErrorSnackBar(context, message: 'Update failed');
              }
            }
          },
        ),

        // Apply To section (shown only when One Calendar is enabled)
        if (prefs.oneCalendarEnabled) ...[
          const SizedBox(height: Spacing.space24),
          Text(
            'APPLY BLOCK-OUT DATES TO',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: Spacing.space12),

          // Radio: All bands
          _ApplyToRadioTile(
            label: 'All bands',
            value: ApplyToMode.allBands,
            groupValue: prefs.applyToMode,
            onChanged: (mode) async {
              try {
                await ref
                    .read(oneCalendarPreferencesProvider.notifier)
                    .setApplyToMode(mode!);
              } catch (e) {
                if (context.mounted) {
                  showErrorSnackBar(context, message: 'Update failed');
                }
              }
            },
          ),
          const SizedBox(height: Spacing.space8),

          // Radio: Selected bands only
          _ApplyToRadioTile(
            label: 'Selected bands only',
            value: ApplyToMode.selectedBands,
            groupValue: prefs.applyToMode,
            onChanged: (mode) async {
              try {
                await ref
                    .read(oneCalendarPreferencesProvider.notifier)
                    .setApplyToMode(mode!);
              } catch (e) {
                if (context.mounted) {
                  showErrorSnackBar(context, message: 'Update failed');
                }
              }
            },
          ),

          // Multi-select list (shown only when "Selected bands only" is active)
          if (prefs.applyToMode == ApplyToMode.selectedBands) ...[
            const SizedBox(height: Spacing.space12),
            ...userBands.map((band) {
              final isSelected = prefs.selectedBandIds.contains(band.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: Spacing.space8),
                child: _BandCheckboxTile(
                  bandName: band.name,
                  isSelected: isSelected,
                  onChanged: (selected) async {
                    final updatedIds = List<String>.from(prefs.selectedBandIds);
                    if (selected == true) {
                      if (!updatedIds.contains(band.id)) {
                        updatedIds.add(band.id);
                      }
                    } else {
                      updatedIds.remove(band.id);
                    }

                    try {
                      await ref
                          .read(oneCalendarPreferencesProvider.notifier)
                          .updateSelectedBands(updatedIds);
                    } catch (e) {
                      if (context.mounted) {
                        showErrorSnackBar(context, message: 'Update failed');
                      }
                    }
                  },
                ),
              );
            }),
          ],

          const SizedBox(height: Spacing.space24),

          // Automatic Conflict Blocking section
          Text(
            'AUTOMATIC CONFLICT BLOCKING',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: Spacing.space12),

          _AutoConflictToggleCard(
            enabled: prefs.autoBlockConflictsEnabled,
            onChanged: (value) async {
              try {
                await ref
                    .read(oneCalendarPreferencesProvider.notifier)
                    .toggleAutoBlockConflicts(value);
              } catch (e) {
                if (context.mounted) {
                  showErrorSnackBar(context, message: 'Update failed');
                }
              }
            },
          ),

          const SizedBox(height: Spacing.space12),

          Text(
            'When you confirm a gig or rehearsal in one band, automatically '
            'mark yourself unavailable on your other bands for that date.',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// MASTER TOGGLE CARD
// ============================================================================

class _MasterToggleCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _MasterToggleCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            AppIcons.calendar,
            color: enabled ? AppColors.primary : context.colors.textMuted,
            size: 28,
          ),
          const SizedBox(width: Spacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('One Calendar', style: AppTextStyles.calloutEmphasized),
                const SizedBox(height: 4),
                Text(
                  enabled
                      ? 'Sharing block-out dates across bands'
                      : 'Each band has separate block-out dates',
                  style: AppTextStyles.footnote.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// APPLY TO RADIO TILE
// ============================================================================

class _ApplyToRadioTile extends StatelessWidget {
  final String label;
  final ApplyToMode value;
  final ApplyToMode groupValue;
  final ValueChanged<ApplyToMode?> onChanged;

  const _ApplyToRadioTile({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;

    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space16,
          vertical: Spacing.space12,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border.all(
            color: isSelected ? AppColors.primary : context.colors.border,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Radio<ApplyToMode>(
              value: value,
              groupValue: groupValue,
              onChanged: onChanged,
              activeColor: AppColors.primary,
            ),
            const SizedBox(width: Spacing.space8),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.callout.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// BAND CHECKBOX TILE
// ============================================================================

class _BandCheckboxTile extends StatelessWidget {
  final String bandName;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _BandCheckboxTile({
    required this.bandName,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space12,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            side: BorderSide(
              color: context.colors.border,
            ),
          ),
          const SizedBox(width: Spacing.space8),
          Expanded(
            child: Text(
              bandName,
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

// ============================================================================
// AUTO CONFLICT TOGGLE CARD
// ============================================================================

class _AutoConflictToggleCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AutoConflictToggleCard({
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border.all(color: context.colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            AppIcons.ban,
            color: enabled ? AppColors.primary : context.colors.textMuted,
            size: 24,
          ),
          const SizedBox(width: Spacing.space12),
          Expanded(
            child: Text(
              'Automatically block conflicting dates',
              style: AppTextStyles.callout.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
