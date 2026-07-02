import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';

// ============================================================================
// APP TOGGLE TILE
// Shared toggle row used across notification preferences, calendar feed
// settings, and anywhere else a labelled on/off switch is needed.
//
// Usage:
//   AppToggleTile(
//     title: 'Gigs',
//     value: _prefs.includeGigs,
//     onChanged: (v) => _updatePref(_prefs.copyWith(includeGigs: v)),
//   )
//
//   AppToggleTile(
//     title: 'Push Notifications',
//     subtitle: 'Receive updates about gigs and rehearsals',
//     value: pushEnabled,
//     onChanged: (v) => controller.togglePush(v),
//   )
// ============================================================================

class AppToggleTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  /// Reduces vertical padding for use in grouped/compact lists (no subtitle).
  final bool compact;

  const AppToggleTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(
              horizontal: Spacing.space16,
              vertical: Spacing.space8,
            )
          : const EdgeInsets.all(Spacing.space16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: subtitle != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.body.copyWith(
                          color: enabled
                              ? context.colors.textPrimary
                              : context.colors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: Spacing.space4),
                      Text(
                        subtitle!,
                        style: AppTextStyles.footnote.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  )
                : Text(
                    title,
                    style: AppTextStyles.body.copyWith(
                      color: enabled
                          ? context.colors.textPrimary
                          : context.colors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: context.colors.surfaceOverlay,
            inactiveThumbColor: context.colors.textSecondary,
          ),
        ],
      ),
    );
  }
}
