import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../../shared/widgets/toggle_tile.dart';
import '../../../components/ui/app_bottom_sheet.dart';
import '../../../components/ui/app_progress_indicator.dart';
import '../../../components/ui/app_button.dart';
import '../calendar_subscription_service.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// CALENDAR SUBSCRIPTION DIALOG
// Modal that shows the user's calendar subscription URL, feed content toggles,
// and platform setup instructions.
// ============================================================================

/// Show the calendar subscription bottom sheet
void showCalendarSubscriptionDialog(
  BuildContext context,
  WidgetRef ref, {
  required String bandId,
  required String bandName,
}) {
  showAppBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => CalendarSubscriptionDialog(
      bandId: bandId,
      bandName: bandName,
    ),
  );
}

class CalendarSubscriptionDialog extends ConsumerStatefulWidget {
  final String bandId;
  final String bandName;

  const CalendarSubscriptionDialog({
    super.key,
    required this.bandId,
    required this.bandName,
  });

  @override
  ConsumerState<CalendarSubscriptionDialog> createState() =>
      _CalendarSubscriptionDialogState();
}

class _CalendarSubscriptionDialogState
    extends ConsumerState<CalendarSubscriptionDialog> {
  bool _copied = false;

  // Feed preferences — held in local state for instant toggle response.
  // Loaded from DB once the URL provider resolves (which auto-creates the row).
  CalendarFeedPreferences _prefs = const CalendarFeedPreferences();
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final service = ref.read(calendarSubscriptionServiceProvider);
    final prefs = await service.getBandSubscriptionPreferences(widget.bandId);
    if (mounted) {
      setState(() {
        _prefs = prefs;
        _prefsLoaded = true;
      });
    }
  }

  Future<void> _updatePref(CalendarFeedPreferences updated) async {
    setState(() => _prefs = updated);
    final service = ref.read(calendarSubscriptionServiceProvider);
    try {
      await service.updateBandSubscriptionPreferences(widget.bandId, updated);
    } catch (_) {
      if (mounted) setState(() => _prefs = _prefs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    final subscriptionUrlAsync = ref.watch(
      calendarBandSubscriptionUrlProvider(widget.bandId),
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.of(context).size.height - keyboardHeight) * 0.9,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: Spacing.space16),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.pagePadding,
              ),
              child: Row(
                children: [
                  Icon(AppIcons.calendar, color: AppColors.primary, size: 22),
                  const SizedBox(width: Spacing.space12),
                  Expanded(
                    child: Text(
                      'Subscribe to ${widget.bandName} Calendar',
                      style: AppTextStyles.title3,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: context.colors.background,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        AppIcons.close,
                        size: 18,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: Spacing.space16),

            // Scrollable body
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  Spacing.pagePadding,
                  0,
                  Spacing.pagePadding,
                  Spacing.space24 + safeBottom,
                ),
                child: subscriptionUrlAsync.when(
                  data: (url) => _buildBody(context, url),
                  loading: () => _buildLoading(),
                  error: (e, _) => _buildError(e.toString()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppProgressIndicator(
            type: ProgressIndicatorType.circular,
            color: AppColors.primary,
          ),
          const SizedBox(height: Spacing.space16),
          Text(
            'Generating your calendar link...',
            style: TextStyle(color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.space24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.error, color: AppColors.error, size: 48),
          const SizedBox(height: Spacing.space16),
          Text(
            'Unable to generate calendar link',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: AppFontSizes.title,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Spacing.space8),
          Text(
            error,
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: AppFontSizes.subhead),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.space24),
          AppButton(
            label: 'Close',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, String? url) {
    if (url == null) {
      return _buildError(
        'Please sign in to access your calendar subscription.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Description
        Text(
          'Add your BandRoadie events to your favorite calendar app. '
          'Events will stay in sync automatically.',
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: AppFontSizes.subhead,
            height: 1.4,
          ),
        ),

        const SizedBox(height: Spacing.space20),

        // Subscription URL
        Container(
          padding: const EdgeInsets.all(Spacing.space12),
          decoration: BoxDecoration(
            color: context.colors.surfaceElevated,
            borderRadius: BorderRadius.circular(Spacing.buttonRadius),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: AppFontSizes.caption,
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

        const SizedBox(height: Spacing.space20),

        // Feed content toggles
        Text(
          'Include in feed:',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: AppFontSizes.subhead,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: Spacing.space8),

        if (_prefsLoaded) ...[
          AppToggleTile(
            title: 'Gigs',
            value: _prefs.includeGigs,
            onChanged: (v) => _updatePref(_prefs.copyWith(includeGigs: v)),
            compact: true,
          ),
          const SizedBox(height: Spacing.space4),
          AppToggleTile(
            title: 'Potential gigs',
            value: _prefs.includePotentialGigs,
            onChanged: (v) =>
                _updatePref(_prefs.copyWith(includePotentialGigs: v)),
            compact: true,
          ),
          const SizedBox(height: Spacing.space4),
          AppToggleTile(
            title: 'Rehearsals',
            value: _prefs.includeRehearsal,
            onChanged: (v) => _updatePref(_prefs.copyWith(includeRehearsal: v)),
            compact: true,
          ),
          const SizedBox(height: Spacing.space4),
          AppToggleTile(
            title: 'Potential rehearsals',
            value: _prefs.includePotentialRehearsal,
            onChanged: (v) =>
                _updatePref(_prefs.copyWith(includePotentialRehearsal: v)),
            compact: true,
          ),
          const SizedBox(height: Spacing.space4),
          AppToggleTile(
            title: 'Member block-out days',
            value: _prefs.includeBlockouts,
            onChanged: (v) => _updatePref(_prefs.copyWith(includeBlockouts: v)),
            compact: true,
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Spacing.space12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: AppProgressIndicator(
                  type: ProgressIndicatorType.circular,
                ),
              ),
            ),
          ),

        const SizedBox(height: Spacing.space20),

        // How to subscribe
        Text(
          'How to subscribe:',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: AppFontSizes.subhead,
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
          icon: AppIcons.calendarDays,
          title: 'Google Calendar',
          instruction: 'Other calendars → From URL → Paste link',
        ),

        const SizedBox(height: Spacing.space8),

        const _InstructionTile(
          icon: AppIcons.email,
          title: 'Outlook',
          instruction: 'Add calendar → Subscribe from web → Paste link',
        ),

        const SizedBox(height: Spacing.space20),

        // Notes
        Container(
          padding: const EdgeInsets.all(Spacing.space12),
          decoration: BoxDecoration(
            color: context.colors.surfaceElevated.withValues(alpha: 0.5),
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
      color: copied ? context.colors.success : AppColors.primary,
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
                copied ? AppIcons.check : AppIcons.copy,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                copied ? 'Copied' : 'Copy',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppFontSizes.caption,
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
        Icon(icon, size: 20, color: context.colors.textSecondary),
        const SizedBox(width: Spacing.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: AppFontSizes.caption,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                instruction,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: AppFontSizes.caption,
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
        Text(
          '•  ',
          style: TextStyle(
              color: context.colors.textMuted, fontSize: AppFontSizes.caption),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                color: context.colors.textMuted,
                fontSize: AppFontSizes.caption),
          ),
        ),
      ],
    );
  }
}
