import 'package:flutter/material.dart';

import '../../../components/ui/app_button.dart';

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
        AppButton(
          label: '+ Add Event',
          onPressed: onAddEvent,
          variant: AppButtonVariant.primary,
        ),
      );
    }

    if (showCreateSetlist) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(
        AppButton(
          label: '+ Create Setlist',
          onPressed: onCreateSetlist,
          variant: AppButtonVariant.primary,
        ),
      );
    }

    if (showFinancials) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(
        AppButton(
          label: 'Financials',
          onPressed: onFinancials,
          variant: AppButtonVariant.primary,
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
}
