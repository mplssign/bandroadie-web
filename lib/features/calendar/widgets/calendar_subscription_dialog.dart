import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../../shared/utils/snackbar_helper.dart';
import '../../../shared/widgets/toggle_tile.dart';
import '../calendar_subscription_service.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// CALENDAR SUBSCRIPTION DIALOG
// Modal that shows the user's calendar subscription URL, feed content toggles,
// and platform setup instructions.
// ============================================================================

/// Show the calendar subscription dialog
void showCalendarSubscriptionDialog(
  BuildContext context,
  WidgetRef ref, {
  required String bandId,
  required String bandName,
}) {
  showDialog(
    context: context,
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
    // Optimistic update — reflect change immediately, persist in background
    setState(() => _prefs = updated);
    final service = ref.read(calendarSubscriptionServiceProvider);
    try {
      await service.updateBandSubscriptionPreferences(widget.bandId, updated);
    } catch (_) {
      // Roll back if the save fails
      if (mounted) setState(() => _prefs = _prefs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionUrlAsync = ref.watch(
      calendarBandSubscriptionUrlProvider(widget.bandId),
    );

    return Dialog(
      backgroundColor: context.colors.surface,
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
        CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: Spacing.space16),
        Text(
          'Generating your calendar link...',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildError(String error) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(AppIcons.error, color: AppColors.error, size: 48),
        const SizedBox(height: Spacing.space16),
        Text(
          'Unable to generate calendar link',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Spacing.space8),
        Text(
          error,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
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

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Row(
            children: [
              Icon(AppIcons.calendar, color: AppColors.primary, size: 28),
              const SizedBox(width: Spacing.space12),
              Expanded(
                child: Text(
                  'Subscribe to ${widget.bandName} Calendar',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(AppIcons.close, color: context.colors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: Spacing.space16),

          // ── Description ─────────────────────────────────────────────────────
          Text(
            'Add your BandRoadie events to your favorite calendar app. '
            'Events will stay in sync automatically.',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),

          const SizedBox(height: Spacing.space20),

          // ── Subscription URL ─────────────────────────────────────────────────
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

          const SizedBox(height: Spacing.space20),

          // ── Feed content toggles ─────────────────────────────────────────────
          Text(
            'Include in feed:',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 14,
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
              onChanged: (v) =>
                  _updatePref(_prefs.copyWith(includeRehearsal: v)),
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
              onChanged: (v) =>
                  _updatePref(_prefs.copyWith(includeBlockouts: v)),
              compact: true,
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.space12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          const SizedBox(height: Spacing.space20),

          // ── Platform instructions ────────────────────────────────────────────
          Text(
            'How to subscribe:',
            style: TextStyle(
              color: context.colors.textPrimary,
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

          // ── Notes ────────────────────────────────────────────────────────────
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
      ),
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
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                instruction,
                style: TextStyle(
                  color: context.colors.textSecondary,
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
        Text(
          '•  ',
          style: TextStyle(color: context.colors.textMuted, fontSize: 12),
        ),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: context.colors.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
