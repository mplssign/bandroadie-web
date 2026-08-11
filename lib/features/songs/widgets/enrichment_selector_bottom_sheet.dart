import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';

// ============================================================================
// ENRICHMENT SELECTOR BOTTOM SHEET
// Lets user select which fields to enrich (BPM, Duration, Key).
// ============================================================================

/// Result returned when user confirms field selection.
class EnrichmentSelectorResult {
  final bool bpmSelected;
  final bool durationSelected;
  final bool keySelected;
  final bool overwriteExisting;
  final bool isShowDiffsHandledInternally;

  const EnrichmentSelectorResult({
    required this.bpmSelected,
    required this.durationSelected,
    required this.keySelected,
    required this.overwriteExisting,
    this.isShowDiffsHandledInternally = false,
  });

  bool get hasAnySelection => bpmSelected || durationSelected || keySelected;
}

/// Shows enrichment field selector bottom sheet.
///
/// For Show Diffs mode, provide [bandId] and [songIds] to enable the
/// diff review flow. Returns [EnrichmentSelectorResult] if user confirms,
/// null if cancelled.
Future<EnrichmentSelectorResult?> showEnrichmentSelectorBottomSheet(
  BuildContext context, {
  required int songCount,
  String? bandId,
  List<String>? songIds,
}) async {
  return showModalBottomSheet<EnrichmentSelectorResult>(
    context: context,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (context) => _EnrichmentSelectorBottomSheet(
      songCount: songCount,
      bandId: bandId,
      songIds: songIds ?? [],
    ),
  );
}

class _EnrichmentSelectorBottomSheet extends ConsumerStatefulWidget {
  final int songCount;
  final String? bandId;
  final List<String> songIds;

  const _EnrichmentSelectorBottomSheet({
    required this.songCount,
    this.bandId,
    required this.songIds,
  });

  @override
  ConsumerState<_EnrichmentSelectorBottomSheet> createState() =>
      _EnrichmentSelectorBottomSheetState();
}

class _EnrichmentSelectorBottomSheetState
    extends ConsumerState<_EnrichmentSelectorBottomSheet> {
  bool _bpmSelected = true;
  bool _durationSelected = true;
  bool _keySelected = true;

  @override
  Widget build(BuildContext context) {
    final hasSelection = _bpmSelected || _durationSelected || _keySelected;

    // Read enrichment settings (always fill-missing-only after revert)
    final subtitleText = 'Select data to auto-enrich for ${widget.songCount} '
        '${widget.songCount == 1 ? "song" : "songs"}. Only missing '
        'values will be filled — existing data is never overwritten.';

    // Always use fill-missing-only behavior (never overwrite)
    const bool overwriteExisting = false;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: Spacing.space12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: Spacing.space16),

            // Title
            Text(
              'Enrich Song Data',
              style: AppTextStyles.headline.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: Spacing.space12),

            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.space16),
              child: Text(
                subtitleText,
                style: AppTextStyles.callout.copyWith(
                  color: context.colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Spacing.space24),

            // Selectable fields
            _buildCheckboxTile(
              title: 'BPM',
              subtitle: 'Tempo in beats per minute',
              value: _bpmSelected,
              onChanged: (value) => setState(() => _bpmSelected = value!),
            ),
            _buildCheckboxTile(
              title: 'Duration',
              subtitle: 'Song length in minutes:seconds',
              value: _durationSelected,
              onChanged: (value) => setState(() => _durationSelected = value!),
            ),
            _buildCheckboxTile(
              title: 'Key',
              subtitle: 'Musical key (e.g., C, Am, F#)',
              value: _keySelected,
              onChanged: (value) => setState(() => _keySelected = value!),
            ),

            const SizedBox(height: Spacing.space8),

            // Informational fields (not available in Phase 2.1)
            _buildInfoTile(
              title: 'Tuning',
              subtitle: 'Tuning can vary by band and must be set manually per '
                  'song.',
            ),
            _buildInfoTile(
              title: 'Lyrics',
              subtitle: 'Lyrics require manual entry due to copyright '
                  'restrictions.',
            ),

            const SizedBox(height: Spacing.space24),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.space16,
                vertical: Spacing.space16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Enrich button (full width)
                  FilledButton(
                    onPressed: hasSelection
                        ? () => _handleEnrichSongs(context, overwriteExisting)
                        : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: Spacing.space16,
                      ),
                      backgroundColor: context.colors.primary,
                      disabledBackgroundColor:
                          Colors.white.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(Spacing.buttonRadius),
                      ),
                    ),
                    child: Text(
                      'Enrich Songs',
                      style: AppTextStyles.button.copyWith(
                        color: hasSelection
                            ? Colors.white
                            : context.colors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: Spacing.space8),

                  // Cancel button (rose text below)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: Spacing.space12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: AppTextStyles.button.copyWith(
                        color: context.colors.primary,
                      ),
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

  Future<void> _handleEnrichSongs(
    BuildContext context,
    bool overwriteExisting,
  ) async {
    // Always return selection for caller to handle (fill-missing-only only after revert)
    Navigator.of(context).pop(
      EnrichmentSelectorResult(
        bpmSelected: _bpmSelected,
        durationSelected: _durationSelected,
        keySelected: _keySelected,
        overwriteExisting: overwriteExisting,
      ),
    );
  }

  Widget _buildCheckboxTile({
    required String title,
    required String subtitle,
    required bool value,
    required void Function(bool?)? onChanged,
    bool enabled = true,
  }) {
    return CheckboxListTile(
      title: Text(
        title,
        style: AppTextStyles.callout.copyWith(
          color: enabled ? Colors.white : context.colors.textMuted,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTextStyles.caption.copyWith(
          color:
              enabled ? context.colors.textSecondary : context.colors.textMuted,
        ),
      ),
      value: value,
      onChanged: enabled ? onChanged : null,
      activeColor: context.colors.primary,
      checkColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space4,
      ),
    );
  }

  Widget _buildInfoTile({
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space4,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.space12,
          vertical: Spacing.space12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(color: context.colors.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.callout.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: Spacing.space4),
            Text(
              subtitle,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
