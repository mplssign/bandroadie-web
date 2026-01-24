import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/shared/widgets/native_app_banner.dart';
import '../bands/active_band_controller.dart';
import '../bands/create_band_screen.dart';
import '../bands/edit_band_screen.dart';
import '../calendar/calendar_tab_content.dart';
import '../feedback/bug_report_screen.dart';
import '../gigs/gig_controller.dart';
import '../home/home_tab_content.dart';
import '../home/widgets/animated_bottom_nav_bar.dart';
import '../home/widgets/band_switcher.dart';
import '../home/widgets/side_drawer.dart';
import '../members/members_tab_content.dart';
import '../profile/my_profile_screen.dart';
import '../profile/profile_screen.dart';
import '../rehearsals/rehearsal_controller.dart';
import '../setlists/setlists_tab_content.dart';
import '../settings/settings_screen.dart';
import '../tips/tips_and_tricks_screen.dart';
import 'overlay_state.dart';
import 'tab_provider.dart';

// ============================================================================
// APP SHELL
// Single navigation shell that owns:
// - The Scaffold
// - The BottomNavBar (positioned as overlay for glass transparency)
// - The active tab content via IndexedStack
//
// This ensures bottom nav works globally across all tabs.
// The bottom nav is positioned as an overlay (not in bottomNavigationBar slot)
// so that the glass blur effect can show content scrolling behind it.
// ============================================================================

// Re-export currentTabProvider for convenience
export 'tab_provider.dart';
export 'overlay_state.dart';

/// AppShell wraps all main tab screens in a single Scaffold with shared nav
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentTabProvider);
    final overlayState = ref.watch(overlayStateProvider);
    final overlayNotifier = ref.read(overlayStateProvider.notifier);
    final bandState = ref.watch(activeBandProvider);

    // Get user info for drawer - watch profile provider for first/last name
    final user = Supabase.instance.client.auth.currentUser;
    final userEmail = user?.email ?? '';

    // Watch the user profile provider to get first_name and last_name from database
    final profileAsync = ref.watch(userProfileProvider);
    final userName = profileAsync.when(
      data: (profile) {
        if (profile == null) return '';
        final first = profile.firstName ?? '';
        final last = profile.lastName ?? '';
        return [first, last].where((s) => s.isNotEmpty).join(' ');
      },
      loading: () => '',
      error: (_, __) => '',
    );

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      // Use Stack to position bottom nav as overlay (for glass transparency)
      // Drawer overlays are rendered ABOVE the bottom nav
      body: Stack(
        children: [
          // Full-bleed content (each tab handles its own bottom padding)
          Positioned.fill(
            child: IndexedStack(
              index: currentTab,
              children: const [
                // Tab 0: Dashboard
                HomeTabContent(),

                // Tab 1: Setlists
                SetlistsTabContent(),

                // Tab 2: Calendar
                CalendarTabContent(),

                // Tab 3: Members
                MembersTabContent(),
              ],
            ),
          ),

          // Bottom nav overlay (glass transparency shows content behind)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBottomNavBar(
              selectedIndex: currentTab,
              onItemTapped: (index) {
                ref.read(currentTabProvider.notifier).setTab(index);
              },
            ),
          ),

          // Native app download banner (Web only, mobile browsers only)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: const NativeAppBanner(
              delay: Duration(seconds: 4),
              position: BannerPosition.top,
              hideOnAuthPages: true,
            ),
          ),

          // ⚠️ CRITICAL: Overlay widgets MUST only be added to tree when open.
          // DO NOT change to "always in tree with isOpen: false" pattern!
          // That approach causes a blank screen bug on app startup because
          // the overlay widgets don't render correctly when initialized closed.
          // See: https://github.com/user/repo/issues/XXX (blank screen bug)
          //
          // Trade-off: No close slide-out animation, but app works reliably.
          if (overlayState == ActiveOverlay.menuDrawer)
            _MenuDrawerLayer(
              isOpen: true,
              onClose: overlayNotifier.closeOverlay,
              userName: userName,
              userEmail: userEmail,
            ),

          // Band switcher (same pattern - only in tree when open)
          if (overlayState == ActiveOverlay.bandSwitcher)
            _BandSwitcherLayer(
              isOpen: true,
              onClose: overlayNotifier.closeOverlay,
              bands: bandState.userBands,
              activeBandId: bandState.activeBand?.id,
            ),
        ],
      ),
    );
  }
}

/// Menu drawer layer - rendered at AppShell level above bottom nav
class _MenuDrawerLayer extends ConsumerWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final String userName;
  final String userEmail;

  const _MenuDrawerLayer({
    required this.isOpen,
    required this.onClose,
    required this.userName,
    required this.userEmail,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Always render - DrawerOverlayContent handles animation and renders
    // SizedBox.shrink() when fully closed
    return DrawerOverlayContent(
      isOpen: isOpen,
      onClose: onClose,
      userName: userName,
      userEmail: userEmail,
      onProfileTap: () {
        onClose();
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MyProfileScreen()));
      },
      onSettingsTap: () {
        onClose();
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      },
      onTipsAndTricksTap: () {
        onClose();
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TipsAndTricksScreen()));
      },
      onReportBugsTap: () {
        onClose();
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const BugReportScreen()));
      },
      onLogOutTap: () async {
        onClose();
        await Supabase.instance.client.auth.signOut();
      },
    );
  }
}

/// Band switcher layer - rendered at AppShell level above bottom nav
class _BandSwitcherLayer extends ConsumerWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final List<Band> bands;
  final String? activeBandId;

  const _BandSwitcherLayer({
    required this.isOpen,
    required this.onClose,
    required this.bands,
    this.activeBandId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Always render - BandSwitcherOverlayContent handles animation and renders
    // SizedBox.shrink() when fully closed
    return BandSwitcherOverlayContent(
      isOpen: isOpen,
      onClose: onClose,
      bands: bands,
      activeBandId: activeBandId,
      onBandSelected: (band) {
        onClose();
        ref.read(gigProvider.notifier).resetForBandChange();
        ref.read(rehearsalProvider.notifier).resetForBandChange();
        ref.read(activeBandProvider.notifier).selectBand(band);
        // Always navigate to Dashboard when switching bands
        ref.read(currentTabProvider.notifier).setTab(0);
      },
      onCreateBand: () {
        onClose();
        // Use custom fade+slide transition for smooth navigation
        Navigator.of(
          context,
        ).push(fadeSlideRoute(page: const CreateBandScreen()));
      },
      onEditBand: () {
        final activeBand = ref.read(activeBandProvider).activeBand;
        if (activeBand != null) {
          onClose();
          // Use custom fade+slide transition for smooth navigation
          Navigator.of(
            context,
          ).push(fadeSlideRoute(page: EditBandScreen(band: activeBand)));
        }
      },
    );
  }
}
