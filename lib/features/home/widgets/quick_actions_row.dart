import 'package:flutter/material.dart';

import '../../../components/ui/brand_action_button.dart';

// ============================================================================
// QUICK ACTIONS ROW
// Figma: Horizontal scrolling row of outlined buttons
// Button specs: outlined Rose/500 border 1px, radius 8px
// Labels: "+ Schedule Rehearsal", "+ Create Setlist", "+ Create Gig"
// ============================================================================

class QuickActionsRow extends StatelessWidget {
  final VoidCallback? onScheduleRehearsal;
  final VoidCallback? onCreateSetlist;
  final VoidCallback? onCreateGig;
  final VoidCallback? onBlockOut;

  const QuickActionsRow({
    super.key,
    this.onScheduleRehearsal,
    this.onCreateSetlist,
    this.onCreateGig,
    this.onBlockOut,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          BrandActionButton(
            label: '+ Schedule Rehearsal',
            onPressed: onScheduleRehearsal,
          ),
          const SizedBox(width: 12),
          BrandActionButton(
            label: '+ Create Setlist',
            onPressed: onCreateSetlist,
          ),
          const SizedBox(width: 12),
          BrandActionButton(label: '+ Create Gig', onPressed: onCreateGig),
          const SizedBox(width: 12),
          BrandActionButton(label: '+ Block Out', onPressed: onBlockOut),
        ],
      ),
    );
  }
}
