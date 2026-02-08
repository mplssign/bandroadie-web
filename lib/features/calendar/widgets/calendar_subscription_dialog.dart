import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../calendar_subscription_service.dart';

// ============================================================================
// CALENDAR SUBSCRIPTION DIALOG
// Modal that shows the user's calendar subscription URL and instructions
// ============================================================================

/// Show the calendar subscription dialog
void showCalendarSubscriptionDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => const CalendarSubscriptionDialog(),
  );
}

class CalendarSubscriptionDialog extends ConsumerStatefulWidget {
  const CalendarSubscriptionDialog({super.key});

  @override
  ConsumerState<CalendarSubscriptionDialog> createState() =>
      _CalendarSubscriptionDialogState();
}

class _CalendarSubscriptionDialogState
    extends ConsumerState<CalendarSubscriptionDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final subscriptionUrlAsync = ref.watch(calendarSubscriptionUrlProvider);

    return Dialog(
      backgroundColor: AppColors.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.space24),
          child: subscriptionUrlAsync.when(
            data: (url) => _buildContent(context, url),
            loading: () => _buildLoading(),
            error: (e, _) => _buildError(e.toString()),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: AppColors.accent),
        const SizedBox(height: Spacing.space16),
        const Text(
          'Generating your calendar link...',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildError(String error) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 48),
        const SizedBox(height: Spacing.space16),
        const Text(
          'Unable to generate calendar link',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        Text(
          error,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Spacing.space24),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, String? url) {
    if (url == null) {
      return _buildError(
        'Please sign in to access your calendar subscription.',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.calendar_month, color: AppColors.accent, size: 28),
            const SizedBox(width: Spacing.space12),
            const Expanded(
              child: Text(
                'Subscribe to Calendar',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),

        const SizedBox(height: Spacing.space16),

        // Description
        const Text(
          'Add your BandRoadie events to your favorite calendar app. '
          'Events will stay in sync automatically.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
        ),

        const SizedBox(height: Spacing.space20),

        // Subscription URL with copy button
        Container(
          padding: const EdgeInsets.all(Spacing.space12),
          decoration: BoxDecoration(
            color: AppColors.cardBgElevated,
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(color: AppColors.borderMuted),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Spacing.space12),
              _CopyButton(
                url: url,
                copied: _copied,
                onCopied: () {
                  setState(() => _copied = true);
                  showSuccessSnackBar(
                    context,
                    message: 'Link copied to clipboard',
                  );
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _copied = false);
                  });
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: Spacing.space24),

        // Platform instructions
        const Text(
          'How to subscribe:',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: Spacing.space12),

        const _InstructionTile(
          icon: Icons.apple,
          title: 'Apple Calendar',
          instruction: 'File → New Calendar Subscription → Paste link',
        ),

        const SizedBox(height: Spacing.space8),

        const _InstructionTile(
          icon: Icons.event,
          title: 'Google Calendar',
          instruction: 'Other calendars → From URL → Paste link',
        ),

        const SizedBox(height: Spacing.space8),

        const _InstructionTile(
          icon: Icons.mail_outline,
          title: 'Outlook',
          instruction: 'Add calendar → Subscribe from web → Paste link',
        ),

        const SizedBox(height: Spacing.space20),

        // Notes
        Container(
          padding: const EdgeInsets.all(Spacing.space12),
          decoration: BoxDecoration(
            color: AppColors.cardBgElevated.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NoteBullet(text: 'Calendar is read-only'),
              SizedBox(height: 4),
              _NoteBullet(text: 'Updates sync automatically'),
              SizedBox(height: 4),
              _NoteBullet(
                text: 'Sync timing varies by app (usually 15min - 24hrs)',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// COPY BUTTON
// ============================================================================

class _CopyButton extends StatelessWidget {
  final String url;
  final bool copied;
  final VoidCallback onCopied;

  const _CopyButton({
    required this.url,
    required this.copied,
    required this.onCopied,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: copied ? AppColors.success : AppColors.accent,
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      child: InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: url));
          onCopied();
        },
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.space12,
            vertical: Spacing.space8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                copied ? Icons.check : Icons.copy,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                copied ? 'Copied' : 'Copy',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// INSTRUCTION TILE
// ============================================================================

class _InstructionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String instruction;

  const _InstructionTile({
    required this.icon,
    required this.title,
    required this.instruction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: Spacing.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                instruction,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// NOTE BULLET
// ============================================================================

class _NoteBullet extends StatelessWidget {
  final String text;

  const _NoteBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '•  ',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
