import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../app/utils/time_formatter.dart';
import '../rehearsal_response_repository.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import '../../../components/ui/app_button.dart';
import '../../../components/ui/app_card.dart';
import '../../../components/ui/app_dialog.dart';

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

  static Future<RehearsalAvailabilityResponse?> show(
    BuildContext context, {
    required PendingPotentialRehearsal rehearsal,
    required String bandTimezone,
    required Future<void> Function(RehearsalAvailabilityResponse response)
        onRespond,
  }) {
    return showAppDialog<RehearsalAvailabilityResponse>(
      context: context,
      barrierDismissible: false,
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
    extends State<RehearsalAvailabilityPromptModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  RehearsalAvailabilityResponse? _selectedResponse;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final random = Random();
    final durationMs = 1000 + random.nextInt(2000);
    _pulseController = AnimationController(
      duration: Duration(milliseconds: durationMs),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleResponse(RehearsalAvailabilityResponse response) async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _selectedResponse = response;
    });
    HapticFeedback.mediumImpact();

    try {
      await widget.onRespond(response);
      if (mounted) {
        Navigator.of(context).pop(response);
      }
    } on RehearsalResponseError catch (e) {
      setState(() {
        _isSubmitting = false;
        _selectedResponse = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.userMessage), backgroundColor: Colors.red),
        );
      }
    } catch (e, stackTrace) {
      debugPrint(
          '[RehearsalAvailabilityPromptModal] Error submitting response: $e');
      debugPrint('[RehearsalAvailabilityPromptModal] Stack trace: $stackTrace');
      setState(() {
        _isSubmitting = false;
        _selectedResponse = null;
      });
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
    return PopScope(
      canPop: false,
      child: FDialog(
        builder: (context, dialogStyle) => AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final pulseValue = _pulseController.value;
            final borderColor = Color.lerp(
              const Color(0xFFF97316),
              const Color(0xFFFB923C),
              pulseValue,
            )!
                .withValues(alpha: 0.35 + pulseValue * 0.45);
            final glowColor = Color.lerp(
              const Color(0xFFF97316),
              const Color(0xFFFB923C),
              pulseValue,
            )!
                .withValues(alpha: 0.18 + (pulseValue * 0.27));

            return Container(
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: borderColor,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: glowColor,
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0x14F97316),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary
                                .withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            AppIcons.calendarCheck,
                            color: context.colors.textPrimary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Potential Rehearsal',
                          style: TextStyle(
                            fontSize: AppFontSizes.subhead,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Are you available?',
                          style: TextStyle(
                            fontSize: AppFontSizes.sectionTitle,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          _formatDate(widget.rehearsal.date),
                          style: TextStyle(
                            fontSize: AppFontSizes.title2,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        _DetailCard(
                          icon: AppIcons.clock,
                          text: TimeFormatter.formatRangeLocal(
                            widget.rehearsal.startTime,
                            widget.rehearsal.endTime,
                            widget.rehearsal.date,
                            widget.bandTimezone,
                          ),
                        ),
                        if (widget.rehearsal.location.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _DetailCard(
                            icon: AppIcons.location,
                            text: widget.rehearsal.location,
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                label: 'NO',
                                icon: AppIcons.close,
                                variant: AppButtonVariant.destructive,
                                isLoading: _isSubmitting,
                                onPressed: () => _handleResponse(
                                  RehearsalAvailabilityResponse.no,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppButton(
                                label: 'YES',
                                icon: AppIcons.check,
                                variant: AppButtonVariant.destructive,
                                backgroundColor: _selectedResponse ==
                                        RehearsalAvailabilityResponse.yes
                                    ? const Color(0xFF00A63E)
                                    : null,
                                isLoading: _isSubmitting,
                                onPressed: () => _handleResponse(
                                  RehearsalAvailabilityResponse.yes,
                                ),
                              ),
                            ),
                          ],
                        ),
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
            );
          },
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

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: AppColors.primary.withValues(alpha: 0.18),
        width: 1,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: context.colors.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppFontSizes.body,
                color: context.colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
