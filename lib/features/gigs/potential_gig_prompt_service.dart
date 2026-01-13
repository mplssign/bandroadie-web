import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services/supabase_client.dart';
import '../bands/active_band_controller.dart';
import 'gig_response_repository.dart';
import 'widgets/availability_prompt_modal.dart';

// ============================================================================
// POTENTIAL GIG PROMPT SERVICE
// Manages the lifecycle of potential gig availability prompts.
//
// RESPONSIBILITIES:
// - Check for pending potential gigs on app startup/resume
// - Show blocking modal for each pending gig (oldest first)
// - Prevent duplicate modals with lock mechanism
// - Band-scoped: only shows gigs for currently selected band
//
// USAGE:
// Call checkAndShowPendingPrompts() from app lifecycle hooks.
// ============================================================================

/// State for tracking prompt service
class PotentialGigPromptState {
  /// Whether a prompt is currently being shown
  final bool isShowingPrompt;

  /// Whether we're currently checking for pending gigs
  final bool isChecking;

  /// Number of pending gigs remaining
  final int pendingCount;

  const PotentialGigPromptState({
    this.isShowingPrompt = false,
    this.isChecking = false,
    this.pendingCount = 0,
  });

  PotentialGigPromptState copyWith({
    bool? isShowingPrompt,
    bool? isChecking,
    int? pendingCount,
  }) {
    return PotentialGigPromptState(
      isShowingPrompt: isShowingPrompt ?? this.isShowingPrompt,
      isChecking: isChecking ?? this.isChecking,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}

/// Notifier that manages potential gig prompts
class PotentialGigPromptNotifier extends Notifier<PotentialGigPromptState> {
  // In-memory lock to prevent duplicate modals
  bool _isShowingModal = false;

  @override
  PotentialGigPromptState build() {
    return const PotentialGigPromptState();
  }

  GigResponseRepository get _repository =>
      ref.read(gigResponseRepositoryProvider);

  /// Check for pending potential gigs and show prompts.
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
      debugPrint('[PotentialGigPrompt] Already showing/checking, skipping');
      return;
    }

    final bandId = ref.read(activeBandIdProvider);
    final userId = supabase.auth.currentUser?.id;

    if (bandId == null || userId == null) {
      debugPrint('[PotentialGigPrompt] No band or user, skipping check');
      return;
    }

    state = state.copyWith(isChecking: true);

    try {
      final pendingGigs = await _repository.fetchPendingPotentialGigs(
        bandId: bandId,
        userId: userId,
      );

      debugPrint(
        '[PotentialGigPrompt] Found ${pendingGigs.length} pending gigs for band $bandId',
      );

      state = state.copyWith(
        isChecking: false,
        pendingCount: pendingGigs.length,
      );

      if (pendingGigs.isEmpty) {
        return;
      }

      // Show prompts for each pending gig (oldest first - already sorted)
      await _showPromptsSequentially(
        context,
        pendingGigs: pendingGigs,
        bandId: bandId,
        userId: userId,
        onResponseSubmitted: onResponseSubmitted,
      );
    } catch (e) {
      debugPrint('[PotentialGigPrompt] Error checking pending gigs: $e');
      state = state.copyWith(isChecking: false);
    }
  }

  /// Show prompts sequentially for all pending gigs
  Future<void> _showPromptsSequentially(
    BuildContext context, {
    required List<PendingPotentialGig> pendingGigs,
    required String bandId,
    required String userId,
    VoidCallback? onResponseSubmitted,
  }) async {
    for (final gig in pendingGigs) {
      // Check if context is still valid
      if (!context.mounted) {
        debugPrint('[PotentialGigPrompt] Context no longer mounted, stopping');
        break;
      }

      // Check if band is still the same
      final currentBandId = ref.read(activeBandIdProvider);
      if (currentBandId != bandId) {
        debugPrint('[PotentialGigPrompt] Band changed, stopping prompts');
        break;
      }

      // Show the modal
      _isShowingModal = true;
      state = state.copyWith(isShowingPrompt: true);

      try {
        final response = await AvailabilityPromptModal.show(
          context,
          gig: gig,
          onRespond: (response) async {
            final responseStr = response == AvailabilityResponse.yes
                ? 'yes'
                : 'no';
            await _repository.upsertResponse(
              gigId: gig.gigId,
              bandId: bandId,
              userId: userId,
              response: responseStr,
            );
            debugPrint(
              '[PotentialGigPrompt] Submitted $responseStr for gig ${gig.gigId}',
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
        debugPrint('[PotentialGigPrompt] Error showing modal: $e');
      } finally {
        _isShowingModal = false;
        state = state.copyWith(isShowingPrompt: false);
      }

      // Small delay between modals for better UX
      if (context.mounted &&
          pendingGigs.indexOf(gig) < pendingGigs.length - 1) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  /// Manually trigger a check (useful after band switch)
  void triggerCheck() {
    // This will be called by the UI with context
    // Just reset state so next check can proceed
    state = const PotentialGigPromptState();
  }
}

/// Provider for the prompt service
final potentialGigPromptProvider =
    NotifierProvider<PotentialGigPromptNotifier, PotentialGigPromptState>(
      PotentialGigPromptNotifier.new,
    );
