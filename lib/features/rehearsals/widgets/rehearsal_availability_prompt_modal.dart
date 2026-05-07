import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/time_formatter.dart';
import '../rehearsal_response_repository.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// REHEARSAL AVAILABILITY PROMPT MODAL
// A blocking modal that requires the user to respond YES or NO to a potential rehearsal.
//
// BLOCKING BEHAVIOR:
// - Cannot dismiss by tapping outside (barrierDismissible: false)
// - No close button
// - Android back button is blocked while modal is showing
// ============================================================================

/// Result of the availability prompt
enum RehearsalAvailabilityResponse { yes, no }

class RehearsalAvailabilityPromptModal extends StatefulWidget {
  final PendingPotentialRehearsal rehearsal;
  final String bandTimezone;
  final Future<void> Function(RehearsalAvailabilityResponse response) onRespond;

  const RehearsalAvailabilityPromptModal({
    super.key,
    required this.rehearsal,
    required this.bandTimezone,
    required this.onRespond,
  });

  /// Show the modal and return the user's response.
  /// Returns null if modal was somehow dismissed without response (shouldn't happen).
  static Future<RehearsalAvailabilityResponse?> show(
    BuildContext context, {
    required PendingPotentialRehearsal rehearsal,
    required String bandTimezone,
    required Future<void> Function(RehearsalAvailabilityResponse response)
        onRespond,
  }) {
    return showDialog<RehearsalAvailabilityResponse>(
      context: context,
      barrierDismissible: false, // Cannot tap outside to dismiss
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => RehearsalAvailabilityPromptModal(
        rehearsal: rehearsal,
        bandTimezone: bandTimezone,
        onRespond: onRespond,
      ),
    );
  }

  @override
  State<RehearsalAvailabilityPromptModal> createState() =>
      _RehearsalAvailabilityPromptModalState();
}

class _RehearsalAvailabilityPromptModalState
    extends State<RehearsalAvailabilityPromptModal> {
  bool _isSubmitting = false;

  Future<void> _handleResponse(RehearsalAvailabilityResponse response) async {
    debugPrint('[RehearsalAvailabilityPromptModal] Button pressed: $response');
    debugPrint(
        '[RehearsalAvailabilityPromptModal] _isSubmitting: $_isSubmitting');

    if (_isSubmitting) {
      debugPrint(
          '[RehearsalAvailabilityPromptModal] Already submitting, returning');
      return;
    }

    setState(() => _isSubmitting = true);
    debugPrint('[RehearsalAvailabilityPromptModal] Starting submission...');

    // Haptic feedback
    HapticFeedback.mediumImpact();

    try {
      debugPrint('[RehearsalAvailabilityPromptModal] Calling onRespond...');
      await widget.onRespond(response);
      debugPrint(
          '[RehearsalAvailabilityPromptModal] onRespond completed successfully');
      if (mounted) {
        Navigator.of(context).pop(response);
      }
    } on RehearsalResponseError catch (e) {
      debugPrint(
          '[RehearsalAvailabilityPromptModal] RehearsalResponseError: ${e.message}');
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage), backgroundColor: Colors.red),
        );
      }
    } catch (e, stackTrace) {
      debugPrint(
          '[RehearsalAvailabilityPromptModal] Error submitting response: $e');
      debugPrint('[RehearsalAvailabilityPromptModal] Stack trace: $stackTrace');
      setState(() => _isSubmitting = false);
      // Show error but keep modal open
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong — try again in a moment.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Block Android back button
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFF77800), // orange
                      Color(0xFFE11D48), // rose-600
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    // Icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        AppIcons.calendarCheck,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Potential Rehearsal',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Are you available?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Rehearsal details
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Date (title-like)
                    Text(
                      _formatDate(widget.rehearsal.date),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Time
                    _DetailRow(
                      icon: AppIcons.clock,
                      label: TimeFormatter.formatRangeLocal(
                        widget.rehearsal.startTime,
                        widget.rehearsal.endTime,
                        widget.rehearsal.date,
                        widget.bandTimezone,
                      ),
                    ),

                    if (widget.rehearsal.location.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _DetailRow(
                        icon: AppIcons.location,
                        label: widget.rehearsal.location,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Buttons
                    Row(
                      children: [
                        // NO button
                        Expanded(
                          child: _ResponseButton(
                            label: 'NO',
                            icon: AppIcons.close,
                            isPositive: false,
                            isLoading: _isSubmitting,
                            onPressed: () => _handleResponse(
                                RehearsalAvailabilityResponse.no),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // YES button
                        Expanded(
                          child: _ResponseButton(
                            label: 'YES',
                            icon: AppIcons.check,
                            isPositive: true,
                            isLoading: _isSubmitting,
                            onPressed: () => _handleResponse(
                                RehearsalAvailabilityResponse.yes),
                          ),
                        ),
                      ],
                    ),

                    // "Not Sure Yet" link - closes without saving, will show again next app open
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: Text(
                          'Not Sure Yet',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _isSubmitting
                                ? context.colors.textMuted
                                    .withValues(alpha: 0.5)
                                : context.colors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
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
    return '${days[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

/// Detail row with icon and label
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: context.colors.textMuted),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: context.colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Response button (YES or NO) with press animation feedback.
class _ResponseButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPositive;
  final bool isLoading;
  final VoidCallback onPressed;

  const _ResponseButton({
    required this.label,
    required this.icon,
    required this.isPositive,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = isPositive
        ? context.colors.success // green-500
        : AppColors.error; // red-500

    // Wrap with AnimatedPressable for subtle press feedback
    return AnimatedPressable(
      enabled: !isLoading,
      onTap: onPressed,
      child: AnimatedContainer(
        // Smooth background/border transitions for state changes
        duration: AppDurations.fast,
        curve: AppCurves.ease,
        height: 56,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
