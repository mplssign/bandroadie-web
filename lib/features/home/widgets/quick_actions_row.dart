import 'package:flutter/material.dart';

import '../../../components/ui/brand_action_button.dart';

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
  final VoidCallback? onScheduleRehearsal;
  final VoidCallback? onCreateSetlist;
  final VoidCallback? onCreateGig;
  final VoidCallback? onBlockOut;

  /// Whether the "Create Gig" button should be shown (permission-gated)
  final bool showCreateGig;

  /// Whether the "Create Setlist" button should be shown (permission-gated)
  final bool showCreateSetlist;

  /// Whether the "Schedule Rehearsal" button should be shown (permission-gated)
  final bool showScheduleRehearsal;

  /// Whether the "Block Out" button should be shown (permission-gated)
  final bool showBlockOut;

  const QuickActionsRow({
    super.key,
    this.onScheduleRehearsal,
    this.onCreateSetlist,
    this.onCreateGig,
    this.onBlockOut,
    this.showCreateGig = true,
    this.showCreateSetlist = true,
    this.showScheduleRehearsal = true,
    this.showBlockOut = true,
  });

  /// Whether at least one button is visible.
  /// Use this to conditionally show the section header.
  bool get hasVisibleButtons =>
      showScheduleRehearsal ||
      showCreateSetlist ||
      showCreateGig ||
      showBlockOut;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    if (showScheduleRehearsal) {
      buttons.add(
        BrandActionButton(
          label: '+ Schedule Rehearsal',
          onPressed: onScheduleRehearsal,
        ),
      );
    }

    if (showCreateSetlist) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(
        BrandActionButton(
          label: '+ Create Setlist',
          onPressed: onCreateSetlist,
        ),
      );
    }

    if (showCreateGig) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(
        BrandActionButton(label: '+ Create Gig', onPressed: onCreateGig),
      );
    }

    if (showBlockOut) {
      if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 12));
      buttons.add(
        BrandActionButton(label: '+ Block Out', onPressed: onBlockOut),
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
