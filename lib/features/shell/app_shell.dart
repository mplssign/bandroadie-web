import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/theme/app_animations.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/shared/widgets/native_app_banner.dart';
import 'package:bandroadie/shared/widgets/restricted_tab_content.dart';
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
import '../contacts/contacts_tab_content.dart';
import '../members/permissions/band_permissions.dart';
import '../members/permissions/band_permissions_provider.dart';
import '../members/permissions/contributor_permissions.dart';
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
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // Note: Notification registration is handled in iOS AppDelegate.swift
  // to properly register with APNs and appear in iOS Settings

  /// Handle tab tap — always navigates. Restricted tabs show the
  /// restricted page instead of real content.
  void _handleTabTap(int index, BandPermissions perms) {
    ref.read(currentTabProvider.notifier).setTab(index);
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = ref.watch(currentTabProvider);
    final overlayState = ref.watch(overlayStateProvider);
    final overlayNotifier = ref.read(overlayStateProvider.notifier);
    final bandState = ref.watch(activeBandProvider);

    // RBAC: Watch permissions for tab gating
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final perms = permissionsAsync.when(
      data: (p) => p,
      loading: () => BandPermissions.fromRole('contributor',
          subPerms:
              ContributorPermissions.allDisabled), // Fail-closed while loading
      error: (_, __) => BandPermissions.fromRole('contributor',
          subPerms: ContributorPermissions.allDisabled), // Fail-closed on error
    );

    // Build visible tabs list: all 4 tabs are always visible.
    // Restricted tabs navigate to a restricted-state page.
    final visibleTabs = <(int, NavItem)>[
      (NavTabIndex.dashboard, kDefaultNavItems[NavTabIndex.dashboard]),
      (NavTabIndex.setlists, kDefaultNavItems[NavTabIndex.setlists]),
      (NavTabIndex.calendar, kDefaultNavItems[NavTabIndex.calendar]),
      (NavTabIndex.members, kDefaultNavItems[NavTabIndex.members]),
    ];

    // Determine if current tab is hidden (should never happen now, but keep safe)
    final isCurrentTabVisible = visibleTabs.any((t) => t.$1 == currentTab);

    // Bounce back to Dashboard if current tab became hidden
    if (!isCurrentTabVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);
      });
    }

    // Compute visual selectedIndex from semantic currentTab
    final visualSelectedIndex =
        visibleTabs.indexWhere((t) => t.$1 == currentTab);
    final safeVisualIndex = visualSelectedIndex >= 0 ? visualSelectedIndex : 0;

    // Extract NavItem list for the nav bar
    final visibleNavItems = visibleTabs.map((t) => t.$2).toList();

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
      backgroundColor: context.colors.background,
      // Use Stack to position bottom nav as overlay (for glass transparency)
      // Drawer overlays are rendered ABOVE the bottom nav
      body: Stack(
        children: [
          // Full-bleed content (each tab handles its own bottom padding)
          Positioned.fill(
            child: IndexedStack(
              index: currentTab,
              children: [
                // Tab 0: Dashboard (always accessible)
                const HomeTabContent(),

                // Tab 1: Setlists (permission-gated)
                // Show real content while loading (optimistic) — only restrict
                // when permissions are definitively loaded and deny access.
                if (permissionsAsync.whenOrNull(
                        data: (p) => p.canViewSetlists) !=
                    false)
                  const SetlistsTabContent()
                else
                  const RestrictedTabContent(featureName: 'Setlists'),

                // Tab 2: Calendar (permission-gated for contributors)
                if (permissionsAsync.whenOrNull(
                        data: (p) => p.canViewCalendar) !=
                    false)
                  const CalendarTabContent()
                else
                  const RestrictedTabContent(featureName: 'Calendar'),

                // Tab 3: Contacts (permission-gated)
                if (permissionsAsync.whenOrNull(
                        data: (p) => p.canViewMembers) !=
                    false)
                  const ContactsTabContent()
                else
                  const RestrictedTabContent(featureName: 'Contacts'),
              ],
            ),
          ),

          // Bottom nav overlay (glass transparency shows content behind)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBottomNavBar(
              selectedIndex: safeVisualIndex,
              items: visibleNavItems,
              onItemTapped: (visualIndex) {
                // Map visual position back to semantic tab index
                if (visualIndex >= 0 && visualIndex < visibleTabs.length) {
                  final semanticIndex = visibleTabs[visualIndex].$1;
                  _handleTabTap(semanticIndex, perms);
                }
              },
            ),
          ),

          // Native app download banner (Web only, mobile browsers only)
          if (kIsWeb)
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

        final currentBandId = ref.read(activeBandIdProvider);
        if (band.id == currentBandId) return;
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
      // RBAC: Only show Edit Band button for admins
      onEditBand: ref.watch(currentUserPermissionsProvider).when(
                data: (p) => p.canEditBandSettings,
                loading: () => false,
                error: (_, __) => false,
              )
          ? () {
              final activeBand = ref.read(activeBandProvider).activeBand;
              if (activeBand != null) {
                onClose();
                Navigator.of(
                  context,
                ).push(fadeSlideRoute(page: EditBandScreen(band: activeBand)));
              }
            }
          : null,
    );
  }
}
