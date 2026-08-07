import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_animations.dart';
import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/time_formatter.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/app_snackbar.dart';
import '../gig_response_repository.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// AVAILABILITY PROMPT MODAL
// A blocking modal that requires the user to respond YES or NO to a potential gig.
//
// BLOCKING BEHAVIOR:
// - Cannot dismiss by tapping outside (barrierDismissible: false)
// - No close button
// - Android back button is blocked while modal is showing
// ============================================================================

/// Result of the availability prompt
enum AvailabilityResponse { yes, no }

class AvailabilityPromptModal extends StatefulWidget {
  final PendingPotentialGig gig;
  final String bandTimezone;
  final Future<void> Function(AvailabilityResponse response) onRespond;

  const AvailabilityPromptModal({
    super.key,
    required this.gig,
    required this.bandTimezone,
    required this.onRespond,
  });

  /// Show the modal and return the user's response.
  /// Returns null if modal was somehow dismissed without response (shouldn't happen).
  static Future<AvailabilityResponse?> show(
    BuildContext context, {
    required PendingPotentialGig gig,
    required String bandTimezone,
    required Future<void> Function(AvailabilityResponse response) onRespond,
  }) {
    return showDialog<AvailabilityResponse>(
      context: context,
      barrierDismissible: false, // Cannot tap outside to dismiss
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => AvailabilityPromptModal(
        gig: gig,
        bandTimezone: bandTimezone,
        onRespond: onRespond,
      ),
    );
  }

  @override
  State<AvailabilityPromptModal> createState() =>
      _AvailabilityPromptModalState();
}

class _AvailabilityPromptModalState extends State<AvailabilityPromptModal> {
  bool _isSubmitting = false;

  Future<void> _handleResponse(AvailabilityResponse response) async {
    debugPrint('[AvailabilityPromptModal] Button pressed: $response');
    debugPrint('[AvailabilityPromptModal] _isSubmitting: $_isSubmitting');

    if (_isSubmitting) {
      debugPrint('[AvailabilityPromptModal] Already submitting, returning');
      return;
    }

    setState(() => _isSubmitting = true);
    debugPrint('[AvailabilityPromptModal] Starting submission...');

    // Haptic feedback
    HapticFeedback.mediumImpact();

    try {
      debugPrint('[AvailabilityPromptModal] Calling onRespond...');
      await widget.onRespond(response);
      debugPrint('[AvailabilityPromptModal] onRespond completed successfully');
      if (mounted) {
        Navigator.of(context).pop(response);
      }
    } on GigResponseError catch (e) {
      debugPrint('[AvailabilityPromptModal] GigResponseError: ${e.message}');
      setState(() => _isSubmitting = false);
      if (mounted) {
        showAppSnackbar(
          context: context,
          message: e.userMessage,
          type: SnackbarType.error,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[AvailabilityPromptModal] Error submitting response: $e');
      debugPrint('[AvailabilityPromptModal] Stack trace: $stackTrace');
      setState(() => _isSubmitting = false);
      // Show error but keep modal open
      if (mounted) {
        showAppSnackbar(
          context: context,
          message: 'Something went wrong — try again in a moment.',
          type: SnackbarType.error,
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
                      'Potential Gig',
                      style: TextStyle(
                        fontSize: AppFontSizes.subhead,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Are you available?',
                      style: TextStyle(
                        fontSize: AppFontSizes.sectionTitle,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Gig details
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Gig name
                    Text(
                      widget.gig.name,
                      style: TextStyle(
                        fontSize: AppFontSizes.title2,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 16),

                    // Date
                    _DetailRow(
                      icon: AppIcons.calendar,
                      label: _formatDate(widget.gig.date),
                    ),

                    const SizedBox(height: 8),

                    // Time
                    _DetailRow(
                      icon: AppIcons.clock,
                      label: TimeFormatter.formatRangeLocal(
                        widget.gig.startTime,
                        widget.gig.endTime,
                        widget.gig.date,
                        widget.bandTimezone,
                      ),
                    ),

                    if (widget.gig.location.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _DetailRow(
                        icon: AppIcons.location,
                        label: widget.gig.location,
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
                            onPressed: () =>
                                _handleResponse(AvailabilityResponse.no),
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
                            onPressed: () =>
                                _handleResponse(AvailabilityResponse.yes),
                          ),
                        ),
                      ],
                    ),

                    // "Not Sure Yet" link - closes without saving, will show again next app open
                    const SizedBox(height: 16),
                    Center(
                      child: AppButton(
                        label: 'Not Sure Yet',
                        variant: AppButtonVariant.text,
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
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
              fontSize: AppFontSizes.body,
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
                        fontSize: AppFontSizes.title,
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
