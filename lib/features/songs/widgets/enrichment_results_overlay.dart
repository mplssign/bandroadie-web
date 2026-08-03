import 'package:flutter/material.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';
import '../services/song_enrichment_orchestrator.dart';

// ============================================================================
// ENRICHMENT RESULTS OVERLAY
// Shows summary of enrichment batch results after completion.
// ============================================================================

/// Shows the enrichment results overlay as a full-screen modal.
Future<void> showEnrichmentResultsOverlay({
  required BuildContext context,
  required EnrichmentOrchestrationResult result,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return EnrichmentResultsOverlay(result: result);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInQuart,
      );

      return FadeTransition(
        opacity: curvedAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class EnrichmentResultsOverlay extends StatelessWidget {
  final EnrichmentOrchestrationResult result;

  const EnrichmentResultsOverlay({
    super.key,
    required this.result,
  });

  String get _title {
    if (result.enriched > 0) {
      return 'Enrichment Complete';
    }
    if (result.errors > 0) {
      return 'Enrichment Incomplete';
    }
    return 'No New Song Data Found';
  }

  String get _summary {
    if (result.enriched > 0) {
      return '${result.enriched} of ${result.total} songs enriched and saved';
    }
    if (result.errors > 0) {
      return 'No song data was saved because one or more lookups or updates failed';
    }
    return 'No new song data was found for the selected songs';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: context.colors.background,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(Spacing.space16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _title,
                      style: AppTextStyles.pageTitle.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Summary section
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.space16,
                vertical: Spacing.space16,
              ),
              child: Container(
                padding: const EdgeInsets.all(Spacing.space16),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(Spacing.cardRadius),
                ),
                child: Column(
                  children: [
                    // Primary stat
                    Text(
                      _summary,
                      style: AppTextStyles.title3.copyWith(
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (result.notFound > 0 || result.errors > 0) ...[
                      const SizedBox(height: Spacing.space8),
                      // Secondary stats
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (result.notFound > 0)
                            Text(
                              '• ${result.notFound} song${result.notFound == 1 ? "" : "s"} not recognized',
                              style: AppTextStyles.footnote.copyWith(
                                color: context.colors.textSecondary,
                              ),
                            ),
                          if (result.notFound > 0 && result.errors > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Spacing.space8,
                              ),
                              child: Text(
                                '•',
                                style: AppTextStyles.footnote.copyWith(
                                  color: context.colors.textSecondary,
                                ),
                              ),
                            ),
                          if (result.errors > 0)
                            Text(
                              '• ${result.errors} error${result.errors == 1 ? "" : "s"}',
                              style: AppTextStyles.footnote.copyWith(
                                color: context.colors.error,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Detail list header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.space16,
                vertical: Spacing.space8,
              ),
              child: Text(
                'Details',
                style: AppTextStyles.footnote.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),

            // Scrollable detail list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.space16,
                ),
                itemCount: result.details.length,
                itemBuilder: (context, index) {
                  final detail = result.details[index];
                  return _buildDetailCard(context, detail);
                },
              ),
            ),

            // Done button
            Padding(
              padding: const EdgeInsets.all(Spacing.space16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: Spacing.space16),
                    backgroundColor: context.colors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: AppTextStyles.button.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(
    BuildContext context,
    SongEnrichmentDetail detail,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.space12),
      padding: const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Song title and artist
          Text(
            detail.title,
            style: AppTextStyles.calloutEmphasized.copyWith(
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Spacing.space4),
          Text(
            detail.artist,
            style: AppTextStyles.caption.copyWith(
              color: context.colors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Spacing.space12),

          // Field results
          Row(
            children: [
              Expanded(
                child: _buildFieldResultBadge(
                  context,
                  'BPM',
                  detail.bpmResult,
                ),
              ),
              const SizedBox(width: Spacing.space8),
              Expanded(
                child: _buildFieldResultBadge(
                  context,
                  'Dur',
                  detail.durationResult,
                ),
              ),
              const SizedBox(width: Spacing.space8),
              Expanded(
                child: _buildFieldResultBadge(
                  context,
                  'Key',
                  detail.keyResult,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFieldResultBadge(
    BuildContext context,
    String label,
    EnrichmentFieldResult result,
  ) {
    final (icon, color, text) = _getResultDisplay(context, result);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space8,
        vertical: Spacing.space6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Spacing.space8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: Spacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: context.colors.textMuted,
                    fontSize: 10,
                  ),
                ),
                Text(
                  text,
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _getResultDisplay(
    BuildContext context,
    EnrichmentFieldResult result,
  ) {
    switch (result) {
      case EnrichmentFieldResult.updated:
        return (Icons.check_circle, Colors.green, 'Updated');
      case EnrichmentFieldResult.notFound:
        return (
          Icons.warning_amber_rounded,
          Colors.orange,
          'Not found',
        );
      case EnrichmentFieldResult.unchanged:
        return (
          Icons.remove_circle_outline,
          context.colors.textMuted,
          'Unchanged',
        );
      case EnrichmentFieldResult.notRequested:
        return (
          Icons.remove_circle_outline,
          context.colors.textMuted,
          '—',
        );
      case EnrichmentFieldResult.error:
        return (Icons.error, context.colors.error, 'Error');
    }
  }
}
