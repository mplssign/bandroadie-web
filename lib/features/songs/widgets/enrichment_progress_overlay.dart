import 'package:flutter/material.dart';

import '../../../app/theme/brand_colors.dart';
import '../../../app/theme/design_tokens.dart';

// ============================================================================
// ENRICHMENT PROGRESS OVERLAY
// Shows progress during long-running catalog-wide enrichment.
// ============================================================================

/// Shows the enrichment progress overlay as a full-screen modal.
///
/// Returns a function to update progress. Call with (completed, total, currentSongTitle).
Future<void Function(int, int, String)> showEnrichmentProgressOverlay({
  required BuildContext context,
}) async {
  final controller = EnrichmentProgressController();

  // Show the dialog
  unawaited(
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return EnrichmentProgressOverlay(controller: controller);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutQuart,
          reverseCurve: Curves.easeInQuart,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: child,
        );
      },
    ),
  );

  // Return update function
  return controller.updateProgress;
}

/// Helper extension for unawaited futures
extension _FutureExtension on Future<void> {}

void unawaited(Future<void> future) {}

/// Controller for updating progress overlay state.
class EnrichmentProgressController extends ChangeNotifier {
  int _completed = 0;
  int _total = 0;
  String _currentSong = '';

  int get completed => _completed;
  int get total => _total;
  String get currentSong => _currentSong;
  double get progress => _total > 0 ? _completed / _total : 0.0;

  void updateProgress(int completed, int total, String currentSong) {
    _completed = completed;
    _total = total;
    _currentSong = currentSong;
    notifyListeners();
  }
}

class EnrichmentProgressOverlay extends StatelessWidget {
  final EnrichmentProgressController controller;

  const EnrichmentProgressOverlay({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space24),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Text(
                  'Enriching Songs...',
                  style: AppTextStyles.headline.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: Spacing.space16),

                // Activity spinner
                SizedBox(
                  width: Spacing.space24,
                  height: Spacing.space24,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      context.colors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.space24),

                // Progress count
                Text(
                  '${controller.completed} of ${controller.total} songs processed',
                  style: AppTextStyles.callout.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                const SizedBox(height: Spacing.space16),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(Spacing.space8),
                  child: LinearProgressIndicator(
                    value: controller.progress,
                    minHeight: Spacing.space8,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      context.colors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.space16),

                // Percentage
                Text(
                  '${(controller.progress * 100).round()}%',
                  style: AppTextStyles.headline.copyWith(
                    color: context.colors.primary,
                  ),
                ),
                const SizedBox(height: Spacing.space16),

                // Currently processing
                if (controller.currentSong.isNotEmpty) ...[
                  Text(
                    'Currently:',
                    style: AppTextStyles.caption.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: Spacing.space4),
                  Text(
                    controller.currentSong,
                    style: AppTextStyles.callout.copyWith(
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
