import 'package:flutter/material.dart';

import '../../home/widgets/animated_bottom_nav_bar.dart';

// ============================================================================
// CALENDAR BOTTOM NAV BAR - DEPRECATED
// Use AppShell with currentTabProvider instead.
// This is kept only for backward compatibility during migration.
// ============================================================================

/// @Deprecated: Use AppShell with currentTabProvider instead
class CalendarBottomNavBar extends StatelessWidget {
  final VoidCallback? onDashboardTap;
  final VoidCallback? onSetlistsTap;
  final VoidCallback? onMembersTap;

  const CalendarBottomNavBar({
    super.key,
    this.onDashboardTap,
    this.onSetlistsTap,
    this.onMembersTap,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[CalendarBottomNavBar] WARNING: Using deprecated nav bar. '
      'Migrate to AppShell with currentTabProvider.',
    );
    return AnimatedBottomNavBar(
      selectedIndex: NavTabIndex.calendar,
      onItemTapped: (index) {
        debugPrint('[CalendarBottomNavBar] Tap on index $index - not handled');
      },
    );
  }
}
