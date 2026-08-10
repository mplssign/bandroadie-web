import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../app/theme/brand_colors.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/app_progress_indicator.dart';
import '../../songs/services/inline_song_enrichment_service.dart';

/// Shows a dialog to confirm enrichment for a new song
///
/// Returns:
/// - `true` if user confirms enrichment
/// - `false` if user skips enrichment
/// - `null` if user cancels (dialog dismissed)
Future<bool?> showEnrichmentConfirmDialog(
  BuildContext context, {
  required String title,
  required String artist,
  int? durationSeconds,
  required InlineSongEnrichmentService enrichmentService,
}) async {
  HapticFeedback.lightImpact();

  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _EnrichmentConfirmDialog(
      title: title,
      artist: artist,
      durationSeconds: durationSeconds,
      enrichmentService: enrichmentService,
    ),
  );
}

class _EnrichmentConfirmDialog extends StatefulWidget {
  final String title;
  final String artist;
  final int? durationSeconds;
  final InlineSongEnrichmentService enrichmentService;

  const _EnrichmentConfirmDialog({
    required this.title,
    required this.artist,
    this.durationSeconds,
    required this.enrichmentService,
  });

  @override
  State<_EnrichmentConfirmDialog> createState() =>
      _EnrichmentConfirmDialogState();
}

class _EnrichmentConfirmDialogState extends State<_EnrichmentConfirmDialog> {
  bool _isLoading = true;
  InlineEnrichmentResult? _result;

  @override
  void initState() {
    super.initState();
    _fetchEnrichment();
  }

  Future<void> _fetchEnrichment() async {
    final result = await widget.enrichmentService.enrichSong(
      title: widget.title,
      artist: widget.artist,
      durationSeconds: widget.durationSeconds,
    );

    if (mounted) {
      setState(() {
        _result = result;
        _isLoading = false;
      });
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return 'Not found';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text(
              'Enrich Song?',
              style: AppTextStyles.title3.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.space8),

            // Song info
            Text(
              widget.title,
              style: AppTextStyles.body.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              widget.artist,
              style: AppTextStyles.footnote.copyWith(
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.space24),

            // Loading or results
            if (_isLoading)
              const Center(
                child: AppProgressIndicator(
                  type: ProgressIndicatorType.circular,
                ),
              )
            else
              _buildEnrichmentResults(),

            const SizedBox(height: Spacing.space24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Skip',
                    variant: AppButtonVariant.secondary,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(false);
                    },
                  ),
                ),
                const SizedBox(width: Spacing.space12),
                Expanded(
                  child: AppButton(
                    label: 'Add',
                    variant: AppButtonVariant.primary,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(true);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnrichmentResults() {
    if (_result == null) {
      return Text(
        'Enrichment failed',
        style: AppTextStyles.footnote.copyWith(
          color: context.colors.textSecondary,
        ),
        textAlign: TextAlign.center,
      );
    }

    return Container(
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        children: [
          _buildEnrichmentRow('BPM', _result!.bpm?.toString() ?? 'Not found'),
          const SizedBox(height: Spacing.space8),
          _buildEnrichmentRow(
            'Duration',
            _formatDuration(_result!.durationSeconds),
          ),
          const SizedBox(height: Spacing.space8),
          _buildEnrichmentRow('Key', _result!.musicalKey ?? 'Not found'),
        ],
      ),
    );
  }

  Widget _buildEnrichmentRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        Text(
          value,
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
