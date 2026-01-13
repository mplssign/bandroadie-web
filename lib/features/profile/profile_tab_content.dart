import 'package:flutter/material.dart';

import 'my_profile_screen.dart';

// ============================================================================
// PROFILE TAB CONTENT
// Content wrapper for the Members/Profile tab in AppShell.
// Embeds MyProfileScreen directly as the tab content.
// ============================================================================

class ProfileTabContent extends StatelessWidget {
  const ProfileTabContent({super.key});

  @override
  Widget build(BuildContext context) {
    // MyProfileScreen has its own Scaffold, but since AppShell uses
    // IndexedStack, it will be overlaid properly. The bottom nav from
    // AppShell will show on top.
    return const MyProfileScreen();
  }
}
