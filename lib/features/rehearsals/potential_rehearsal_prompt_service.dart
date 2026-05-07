import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services/supabase_client.dart';
import '../bands/active_band_controller.dart';
import 'rehearsal_response_repository.dart';
import 'widgets/rehearsal_availability_prompt_modal.dart';

// ============================================================================
// POTENTIAL REHEARSAL PROMPT SERVICE
// Manages the lifecycle of potential rehearsal availability prompts.
//
// RESPONSIBILITIES:
// - Check for pending potential rehearsals on app startup/resume
// - Show blocking modal for each pending rehearsal (oldest first)
// - Prevent duplicate modals with lock mechanism
// - Band-scoped: only shows rehearsals for currently selected band
//
// USAGE:
// Call checkAndShowPendingPrompts() from app lifecycle hooks.
// ============================================================================

/// State for tracking prompt service
class PotentialRehearsalPromptState {
  /// Whether a prompt is currently being shown
  final bool isShowingPrompt;

  /// Whether we're currently checking for pending rehearsals
  final bool isChecking;

  /// Number of pending rehearsals remaining
  final int pendingCount;

  const PotentialRehearsalPromptState({
    this.isShowingPrompt = false,
    this.isChecking = false,
    this.pendingCount = 0,
  });

  PotentialRehearsalPromptState copyWith({
    bool? isShowingPrompt,
    bool? isChecking,
    int? pendingCount,
  }) {
    return PotentialRehearsalPromptState(
      isShowingPrompt: isShowingPrompt ?? this.isShowingPrompt,
      isChecking: isChecking ?? this.isChecking,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}

/// Notifier that manages potential rehearsal prompts
class PotentialRehearsalPromptNotifier
    extends Notifier<PotentialRehearsalPromptState> {
  // In-memory lock to prevent duplicate modals
  bool _isShowingModal = false;

  @override
  PotentialRehearsalPromptState build() {
    return const PotentialRehearsalPromptState();
  }

  RehearsalResponseRepository get _repository =>
      ref.read(rehearsalResponseRepositoryProvider);

  /// Check for pending potential rehearsals and show prompts.
  /// Call this on app startup and AppLifecycleState.resumed.
  ///
  /// [context] - BuildContext for showing dialog
  /// [onResponseSubmitted] - Optional callback after each response
  Future<void> checkAndShowPendingPrompts(
    BuildContext context, {
    VoidCallback? onResponseSubmitted,
  }) async {
    // Prevent duplicate checks
    if (_isShowingModal || state.isChecking) {
      debugPrint(
          '[PotentialRehearsalPrompt] Already showing/checking, skipping');
      return;
    }

    final bandId = ref.read(activeBandIdProvider);
    final userId = supabase.auth.currentUser?.id;

    if (bandId == null || userId == null) {
      debugPrint('[PotentialRehearsalPrompt] No band or user, skipping check');
      return;
    }

    state = state.copyWith(isChecking: true);

    try {
      final pendingRehearsals =
          await _repository.fetchPendingPotentialRehearsals(
        bandId: bandId,
        userId: userId,
      );

      debugPrint(
        '[PotentialRehearsalPrompt] Found ${pendingRehearsals.length} pending rehearsals for band $bandId',
      );

      state = state.copyWith(
        isChecking: false,
        pendingCount: pendingRehearsals.length,
      );

      if (pendingRehearsals.isEmpty) {
        return;
      }

      // Show prompts for each pending rehearsal (oldest first - already sorted)
      if (!context.mounted) return;
      await _showPromptsSequentially(
        context,
        pendingRehearsals: pendingRehearsals,
        bandId: bandId,
        userId: userId,
        onResponseSubmitted: onResponseSubmitted,
      );
    } catch (e) {
      debugPrint(
          '[PotentialRehearsalPrompt] Error checking pending rehearsals: $e');
      state = state.copyWith(isChecking: false);
    }
  }

  /// Show prompts sequentially for all pending rehearsals
  Future<void> _showPromptsSequentially(
    BuildContext context, {
    required List<PendingPotentialRehearsal> pendingRehearsals,
    required String bandId,
    required String userId,
    VoidCallback? onResponseSubmitted,
  }) async {
    for (final rehearsal in pendingRehearsals) {
      // Check if context is still valid
      if (!context.mounted) {
        debugPrint(
            '[PotentialRehearsalPrompt] Context no longer mounted, stopping');
        break;
      }

      // Check if band is still the same
      final currentBandId = ref.read(activeBandIdProvider);
      if (currentBandId != bandId) {
        debugPrint('[PotentialRehearsalPrompt] Band changed, stopping prompts');
        break;
      }

      // Show the modal
      _isShowingModal = true;
      state = state.copyWith(isShowingPrompt: true);

      final bandTimezone = ref.read(activeBandProvider).activeBand?.timezone ??
          'America/Chicago';

      try {
        final response = await RehearsalAvailabilityPromptModal.show(
          context,
          rehearsal: rehearsal,
          bandTimezone: bandTimezone,
          onRespond: (response) async {
            final responseStr =
                response == RehearsalAvailabilityResponse.yes ? 'yes' : 'no';
            // Save response
            await _repository.upsertResponse(
              rehearsalId: rehearsal.rehearsalId,
              bandId: bandId,
              userId: userId,
              response: responseStr,
            );
            debugPrint(
              '[PotentialRehearsalPrompt] Submitted $responseStr for rehearsal ${rehearsal.rehearsalId}',
            );
          },
        );

        if (response != null) {
          // Update pending count
          state = state.copyWith(
            pendingCount: state.pendingCount > 0 ? state.pendingCount - 1 : 0,
          );

          // Call callback
          onResponseSubmitted?.call();
        }
      } catch (e) {
        debugPrint('[PotentialRehearsalPrompt] Error showing modal: $e');
      } finally {
        _isShowingModal = false;
        state = state.copyWith(isShowingPrompt: false);
      }

      // Small delay between modals for better UX
      if (context.mounted &&
          pendingRehearsals.indexOf(rehearsal) < pendingRehearsals.length - 1) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  /// Manually trigger a check (useful after band switch)
  void triggerCheck() {
    // This will be called by the UI with context
    // Just reset state so next check can proceed
    state = const PotentialRehearsalPromptState();
  }
}

/// Provider for the prompt service
final potentialRehearsalPromptProvider = NotifierProvider<
    PotentialRehearsalPromptNotifier, PotentialRehearsalPromptState>(
  PotentialRehearsalPromptNotifier.new,
);
