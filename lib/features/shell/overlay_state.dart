import 'package:flutter_riverpod/flutter_riverpod.dart';

// ============================================================================
// OVERLAY STATE
// Manages the open/close state of full-screen overlays (drawers) that need
// to render above the bottom nav bar.
//
// This is managed at the AppShell level so overlays can be positioned above
// the bottom nav in the widget tree.
// ============================================================================

/// Which overlay is currently open (only one at a time)
enum ActiveOverlay { none, menuDrawer, bandSwitcher }

/// State notifier for managing overlay visibility
class OverlayStateNotifier extends Notifier<ActiveOverlay> {
  @override
  ActiveOverlay build() => ActiveOverlay.none;

  void openMenuDrawer() {
    state = ActiveOverlay.menuDrawer;
  }

  void openBandSwitcher() {
    state = ActiveOverlay.bandSwitcher;
  }

  void closeOverlay() {
    state = ActiveOverlay.none;
  }

  bool get isMenuDrawerOpen => state == ActiveOverlay.menuDrawer;
  bool get isBandSwitcherOpen => state == ActiveOverlay.bandSwitcher;
}

/// Provider for overlay state
final overlayStateProvider =
    NotifierProvider<OverlayStateNotifier, ActiveOverlay>(
      OverlayStateNotifier.new,
    );
