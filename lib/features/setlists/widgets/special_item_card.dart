import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/setlist_item.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

// ============================================================================
// SPECIAL ITEM CARD
// Compact card rendered in the setlist list for Set Breaks and Pauses.
// Visually distinct from song cards: shorter height, accent-tinted left bar.
//
// Set Break: rose accent (#BE123C), timer icon, duration in minutes.
// Pause:     amber accent (#F59E0B), pause icon, purpose chips + duration.
// ============================================================================

class SpecialItemCard extends StatelessWidget {
  final SetlistItem item;
  final int index;
  final bool isDraggable;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const SpecialItemCard({
    super.key,
    required this.item,
    required this.index,
    this.isDraggable = true,
    this.onTap,
    this.onDelete,
  });

  Color get _accentColor {
    return item.isSetBreak
        ? const Color(0xFFBE123C) // rose
        : const Color(0xFFF59E0B); // amber
  }

  IconData get _icon {
    return item.isSetBreak
        ? AppIcons.timer
        : Icons.pause_circle_outline_rounded;
  }

  String get _label {
    final special = item.specialItem;
    if (special == null) return item.type.displayName;

    if (item.isSetBreak) {
      final mins = special.durationMinutes ?? 0;
      return 'SET BREAK${mins > 0 ? ' – $mins mins' : ''}';
    }

    // Pause: join purposes with " - "
    final allPurposes = [...special.purposes, ...special.customPurposes];
    if (allPurposes.isNotEmpty) {
      return allPurposes.join(' - ').toUpperCase();
    }
    return 'PAUSE';
  }

  String? get _durationText {
    final special = item.specialItem;
    if (special == null) return null;

    if (item.isSetBreak) {
      // Duration shown inline in label for set breaks
      return null;
    } else {
      final secs = special.durationSeconds;
      if (secs == null || secs == 0) return null;
      final m = secs ~/ 60;
      final s = secs % 60;
      return '($m:${s.toString().padLeft(2, '0')})';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (item.isSetBreak) {
      return _buildSetBreakCard(context);
    }
    return _buildPauseCard(context);
  }

  /// Set Break: Red filled background, centered title "SET BREAK – 20 mins"
  Widget _buildSetBreakCard(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _accentColor,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        child: Row(
          children: [
            // Drag handle
            if (isDraggable)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    AppIcons.drag,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 20,
                  ),
                ),
              )
            else
              const SizedBox(width: 12),

            // Centered label
            Expanded(
              child: Center(
                child: Text(
                  _label,
                  style: AppTextStyles.headline.copyWith(
                    fontSize: 14,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            // Spacer to balance drag handle
            if (isDraggable)
              const SizedBox(width: 36)
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// Pause: Accent-tinted card with purpose titles and optional duration below
  Widget _buildPauseCard(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(
            color: _accentColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Left accent bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: _accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(Spacing.buttonRadius),
                  bottomLeft: Radius.circular(Spacing.buttonRadius),
                ),
              ),
            ),

            // Drag handle
            if (isDraggable)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    AppIcons.drag,
                    color: AppColors.textMuted.withValues(alpha: 0.5),
                    size: 20,
                  ),
                ),
              )
            else
              const SizedBox(width: 12),

            // Icon
            Icon(_icon, color: _accentColor, size: 18),
            const SizedBox(width: 8),

            // Label + optional duration subtitle
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _label,
                      style: AppTextStyles.headline.copyWith(
                        fontSize: 14,
                        color: _accentColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_durationText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _durationText!,
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
