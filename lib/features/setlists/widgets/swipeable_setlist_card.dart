import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/design_tokens.dart';
import '../models/setlist.dart';
import 'setlist_card.dart';

// ============================================================================
// SWIPEABLE SETLIST CARD
// Wraps SetlistCard with Dismissible for swipe gestures:
// - Swipe LEFT → Delete (red background, trash icon)
// - Swipe RIGHT → Duplicate (green background, copy icon)
//
// CATALOG PROTECTION:
// The "Catalog" setlist cannot be deleted or duplicated.
// If the user tries to swipe on Catalog, we show a snackbar.
// ============================================================================

/// Callback type for setlist actions that need confirmation
typedef SetlistActionCallback = Future<bool> Function(Setlist setlist);

class SwipeableSetlistCard extends StatefulWidget {
  final Setlist setlist;
  final VoidCallback? onTap;
  final VoidCallback? onEditName;
  final SetlistActionCallback? onDeleteConfirmed;
  final SetlistActionCallback? onDuplicateConfirmed;

  const SwipeableSetlistCard({
    super.key,
    required this.setlist,
    this.onTap,
    this.onEditName,
    this.onDeleteConfirmed,
    this.onDuplicateConfirmed,
  });

  @override
  State<SwipeableSetlistCard> createState() => _SwipeableSetlistCardState();
}

class _SwipeableSetlistCardState extends State<SwipeableSetlistCard>
    with SingleTickerProviderStateMixin {
  // Track if we've passed the action threshold for haptic feedback
  bool _passedThreshold = false;
  DismissDirection? _currentDirection;

  // Threshold percentage for triggering haptic feedback
  static const double _hapticThreshold = 0.3;

  @override
  Widget build(BuildContext context) {
    // Catalog setlist can only be duplicated (swipe right), never deleted
    final swipeDirection = widget.setlist.isCatalog
        ? DismissDirection
              .startToEnd // Only allow swipe right (duplicate)
        : DismissDirection.horizontal; // Allow both directions

    return Dismissible(
      key: Key('swipeable_setlist_${widget.setlist.id}'),
      direction: swipeDirection,
      confirmDismiss: _handleConfirmDismiss,
      onUpdate: _handleDismissUpdate,
      dismissThresholds: const {
        DismissDirection.endToStart: 0.4, // Delete - swipe left
        DismissDirection.startToEnd: 0.4, // Duplicate - swipe right
      },
      movementDuration: AppDurations.medium,
      background: _buildDuplicateBackground(), // Shown when swiping right
      secondaryBackground: _buildDeleteBackground(), // Shown when swiping left
      child: SetlistCard(
        setlist: widget.setlist,
        onTap: widget.onTap,
        onEditName: widget.onEditName,
      ),
    );
  }

  /// Handle dismiss update for haptic feedback
  void _handleDismissUpdate(DismissUpdateDetails details) {
    final progress = details.progress;
    final direction = details.direction;

    // Reset threshold tracking when direction changes
    if (direction != _currentDirection) {
      _passedThreshold = false;
      _currentDirection = direction;
    }

    // Trigger haptic when crossing the threshold
    if (progress >= _hapticThreshold && !_passedThreshold) {
      _passedThreshold = true;
      HapticFeedback.mediumImpact();
    } else if (progress < _hapticThreshold && _passedThreshold) {
      _passedThreshold = false;
    }
  }

  /// Confirm dismiss and trigger appropriate action
  Future<bool> _handleConfirmDismiss(DismissDirection direction) async {
    if (direction == DismissDirection.endToStart) {
      // Swipe left → Delete
      if (widget.onDeleteConfirmed != null) {
        final confirmed = await widget.onDeleteConfirmed!(widget.setlist);
        if (confirmed) {
          HapticFeedback.heavyImpact();
        }
        return confirmed;
      }
    } else if (direction == DismissDirection.startToEnd) {
      // Swipe right → Duplicate
      if (widget.onDuplicateConfirmed != null) {
        final confirmed = await widget.onDuplicateConfirmed!(widget.setlist);
        if (confirmed) {
          HapticFeedback.lightImpact();
        }
        // Never actually dismiss for duplicate - we want the card to stay
        return false;
      }
    }
    return false;
  }

  /// Red background with trash icon (swipe left to delete)
  Widget _buildDeleteBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: Spacing.space24),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Delete',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          SizedBox(width: Spacing.space8),
          Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
        ],
      ),
    );
  }

  /// Green background with copy icon (swipe right to duplicate)
  Widget _buildDuplicateBackground() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: Spacing.space24),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.copy_rounded, color: Colors.white, size: 28),
          SizedBox(width: Spacing.space8),
          Text(
            'Duplicate',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
