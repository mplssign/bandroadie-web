import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';

// ============================================================================
// QUICK ACTIONS ROW
// Figma: Horizontal scrolling row of outlined buttons
// Button specs: outlined Rose/500 border 1px, radius 8px
// Labels: "+ Schedule Rehearsal", "+ Create Setlist", "+ Create Gig"
//
// RBAC: Visibility of buttons is controlled by the parent via nullable
// callbacks. A null callback hides the button entirely.
// ============================================================================

class QuickActionsRow extends StatelessWidget {
  final VoidCallback? onAddEvent;
  final VoidCallback? onCreateSetlist;
  final VoidCallback? onFinancials;

  /// Whether the "+ Add Event" button should be shown (permission-gated)
  final bool showAddEvent;

  /// Whether the "Create Setlist" button should be shown (permission-gated)
  final bool showCreateSetlist;

  /// Whether the "Financials" button should be shown (role-gated)
  final bool showFinancials;

  const QuickActionsRow({
    super.key,
    this.onAddEvent,
    this.onCreateSetlist,
    this.onFinancials,
    this.showAddEvent = true,
    this.showCreateSetlist = true,
    this.showFinancials = true,
  });

  /// Whether at least one button is visible.
  /// Use this to conditionally show the section header.
  bool get hasVisibleButtons =>
      showAddEvent || showCreateSetlist || showFinancials;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    if (showAddEvent) {
      buttons.add(
        _buildQuickActionButton(
          label: '+ Add Event',
          onPressed: onAddEvent,
        ),
      );
    }

    if (showCreateSetlist) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(
        _buildQuickActionButton(
          label: '+ Create Setlist',
          onPressed: onCreateSetlist,
        ),
      );
    }

    if (showFinancials) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(
        _buildQuickActionButton(
          label: 'Financials',
          onPressed: onFinancials,
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: buttons,
      ),
    );
  }

  Widget _buildQuickActionButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        foregroundColor: AppColors.primary,
        side: const BorderSide(
          color: AppColors.primary,
          width: 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Text(label),
    );
  }
}
