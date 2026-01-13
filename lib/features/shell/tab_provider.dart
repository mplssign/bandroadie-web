import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/widgets/animated_bottom_nav_bar.dart' show NavTabIndex;

// ============================================================================
// TAB NAVIGATION PROVIDER
// Single source of truth for the current tab index.
// Extracted to avoid circular imports.
// ============================================================================

/// Notifier for the current tab index
class TabNotifier extends Notifier<int> {
  @override
  int build() => NavTabIndex.dashboard;

  void setTab(int index) {
    state = index;
  }
}

/// Provider for the current tab index (single source of truth)
final currentTabProvider = NotifierProvider<TabNotifier, int>(TabNotifier.new);
