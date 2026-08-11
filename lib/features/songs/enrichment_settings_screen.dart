import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/design_tokens.dart';
import '../../app/theme/brand_colors.dart';
import '../../app/theme/app_icons.dart';
import '../../components/ui/app_scaffold.dart';
import '../../components/ui/app_app_bar.dart';
import '../../components/ui/app_icon_button.dart';
import '../../components/ui/app_progress_indicator.dart';
import '../../components/ui/app_button.dart';
import '../../shared/utils/snackbar_helper.dart';
import 'enrichment_settings_controller.dart';
import 'models/enrichment_settings.dart';

/// Settings screen for configuring song enrichment behavior
class EnrichmentSettingsScreen extends ConsumerWidget {
  const EnrichmentSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(enrichmentSettingsProvider);

    return AppScaffold(
      backgroundColor: context.colors.background,
      appBar: AppAppBar(
        backgroundColor: context.colors.background,
        leading: AppIconButton(
          icon: AppIcons.arrowLeft,
          color: context.colors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Song Enrichment',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: AppFontSizes.title2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: settingsAsync.when(
        data: (settings) => _buildContent(context, ref, settings),
        loading: () => const Center(
          child: AppProgressIndicator(type: ProgressIndicatorType.circular),
        ),
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
                  'Failed to load settings',
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
                AppButton(
                  label: 'Retry',
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    ref.invalidate(enrichmentSettingsProvider);
                  },
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
    EnrichmentSettings settings,
  ) {
    return ListView(
      padding: const EdgeInsets.all(Spacing.pagePadding),
      children: [
        // Explainer text
        Text(
          'Configure how BandRoadie enriches songs with BPM, Duration, and Musical Key.',
          style: AppTextStyles.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: Spacing.space24),

        // New Song Behavior section
        Text(
          'NEW SONG BEHAVIOR',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: Spacing.space12),

        _RadioTile(
          title: 'Ask',
          subtitle: 'Review enriched values before adding songs',
          value: NewSongBehavior.ask,
          groupValue: settings.newSongBehavior,
          onChanged: (value) => _updateSettings(
            context,
            ref,
            newSongBehavior: value!,
            existingSongBehavior: settings.existingSongBehavior,
          ),
        ),
        const SizedBox(height: Spacing.space8),

        _RadioTile(
          title: 'Auto',
          subtitle: 'Automatically enrich in background, no review',
          value: NewSongBehavior.auto,
          groupValue: settings.newSongBehavior,
          onChanged: (value) => _updateSettings(
            context,
            ref,
            newSongBehavior: value!,
            existingSongBehavior: settings.existingSongBehavior,
          ),
        ),
        const SizedBox(height: Spacing.space8),

        _RadioTile(
          title: 'Off',
          subtitle: 'No enrichment, manual entry only',
          value: NewSongBehavior.off,
          groupValue: settings.newSongBehavior,
          onChanged: (value) => _updateSettings(
            context,
            ref,
            newSongBehavior: value!,
            existingSongBehavior: settings.existingSongBehavior,
          ),
        ),

        const SizedBox(height: Spacing.space32),

        // Existing Song Behavior section
        Text(
          'EXISTING SONG BEHAVIOR',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: Spacing.space12),

        _RadioTile(
          title: 'Fill Missing Only',
          subtitle: 'Only update fields that are currently empty',
          value: ExistingSongBehavior.fillMissingOnly,
          groupValue: settings.existingSongBehavior,
          onChanged: (value) => _updateSettings(
            context,
            ref,
            newSongBehavior: settings.newSongBehavior,
            existingSongBehavior: value!,
          ),
        ),
        const SizedBox(height: Spacing.space8),

        _RadioTile(
          title: 'Auto-Replace',
          subtitle: 'Update all fields, including existing values',
          value: ExistingSongBehavior.autoReplace,
          groupValue: settings.existingSongBehavior,
          onChanged: (value) => _updateSettings(
            context,
            ref,
            newSongBehavior: settings.newSongBehavior,
            existingSongBehavior: value!,
          ),
        ),
        const SizedBox(height: Spacing.space8),

        _RadioTile(
          title: 'Show Diffs',
          subtitle: 'Review changes before updating existing songs',
          value: ExistingSongBehavior.showDiffs,
          groupValue: settings.existingSongBehavior,
          onChanged: (value) => _updateSettings(
            context,
            ref,
            newSongBehavior: settings.newSongBehavior,
            existingSongBehavior: value!,
          ),
        ),

        const SizedBox(height: Spacing.space16),
      ],
    );
  }

  Future<void> _updateSettings(
    BuildContext context,
    WidgetRef ref, {
    required NewSongBehavior newSongBehavior,
    required ExistingSongBehavior existingSongBehavior,
  }) async {
    try {
      await ref.read(enrichmentSettingsProvider.notifier).updateSettings(
            newSongBehavior: newSongBehavior,
            existingSongBehavior: existingSongBehavior,
          );
      if (context.mounted) {
        showSuccessSnackBar(context, message: 'Settings updated');
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, message: 'Failed to update settings');
      }
    }
  }
}

/// Radio tile widget for enrichment settings
class _RadioTile<T> extends StatelessWidget {
  final String title;
  final String subtitle;
  final T value;
  final T groupValue;
  final ValueChanged<T?> onChanged;

  const _RadioTile({
    required this.title,
    required this.subtitle,
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
        padding: const EdgeInsets.all(Spacing.space16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? context.colors.primary : context.colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? context.colors.primary
                      : context.colors.textMuted,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.colors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: Spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Spacing.space4),
                  Text(
                    subtitle,
                    style: AppTextStyles.footnote.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
