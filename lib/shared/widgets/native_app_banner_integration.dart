// ============================================================================
// NATIVE APP BANNER INTEGRATION GUIDE
// ============================================================================
//
// This file demonstrates how to integrate the NativeAppBanner widget
// into your app shell. The banner automatically shows to mobile web users
// and encourages them to download the native app.
//
// ============================================================================

import 'package:flutter/material.dart';
import 'package:bandroadie/shared/widgets/native_app_banner.dart';

// ----------------------------------------------------------------------------
// INTEGRATION EXAMPLE 1: App Shell Level (Recommended)
// ----------------------------------------------------------------------------
// Add the banner to your AppShell so it appears globally across all tabs.
// This is the recommended approach for Band Roadie.

/*

// In lib/features/shell/app_shell.dart:

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(currentTabProvider);
    final overlayState = ref.watch(overlayStateProvider);
    // ... other state ...

    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Stack(
        children: [
          // Full-bleed content
          Positioned.fill(
            child: IndexedStack(
              index: currentTab,
              children: const [
                HomeTabContent(),
                SetlistsTabContent(),
                CalendarTabContent(),
                MembersTabContent(),
              ],
            ),
          ),

          // Bottom nav overlay
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

          // 🎸 ADD THE BANNER HERE
          const NativeAppBanner(
            delay: Duration(seconds: 4),
            position: BannerPosition.top,
            hideOnAuthPages: true,
          ),

          // ... other overlays (drawer, band switcher) ...
        ],
      ),
    );
  }
}

*/

// ----------------------------------------------------------------------------
// INTEGRATION EXAMPLE 2: Individual Screen
// ----------------------------------------------------------------------------
// Alternatively, you can add the banner to specific screens if you want
// more granular control.

class ExampleScreenWithBanner extends StatelessWidget {
  const ExampleScreenWithBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Example Screen')),
      body: Stack(
        children: [
          // Main content
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Your content here...'),
              // ... more widgets ...
            ],
          ),

          // Banner overlay
          const NativeAppBanner(
            delay: Duration(seconds: 5),
            position: BannerPosition.bottom, // Try bottom position
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// CONFIGURATION OPTIONS
// ----------------------------------------------------------------------------

class ConfigurationExamples {
  // Default configuration
  static const Widget defaultBanner = NativeAppBanner();

  // Custom delay (show after 3 seconds)
  static const Widget quickBanner = NativeAppBanner(
    delay: Duration(seconds: 3),
  );

  // Bottom position
  static const Widget bottomBanner = NativeAppBanner(
    position: BannerPosition.bottom,
  );

  // Show on auth pages too
  static const Widget alwaysShowBanner = NativeAppBanner(
    hideOnAuthPages: false,
  );

  // Full customization
  static const Widget customBanner = NativeAppBanner(
    delay: Duration(seconds: 5),
    position: BannerPosition.top,
    hideOnAuthPages: true,
  );
}

// ----------------------------------------------------------------------------
// TESTING & DEBUGGING
// ----------------------------------------------------------------------------

class TestingGuide {
  // To test the banner during development:
  //
  // 1. Run the web app:
  //    flutter run -d chrome
  //
  // 2. Open Chrome DevTools (F12)
  //
  // 3. Toggle device toolbar (Cmd+Shift+M on Mac, Ctrl+Shift+M on Windows)
  //
  // 4. Select a mobile device (e.g., iPhone 12 Pro, Pixel 5)
  //
  // 5. Refresh the page - banner should appear after the delay
  //
  // 6. Click "Not now" to dismiss
  //
  // 7. To reset dismissal and see banner again:
  //    - Open DevTools Console
  //    - Run: localStorage.removeItem('hideAppBanner')
  //    - Refresh the page
  //
  // 8. To test the 30-day re-show feature:
  //    - Dismiss the banner
  //    - In Console, run:
  //      const oldDate = new Date();
  //      oldDate.setDate(oldDate.getDate() - 31);
  //      localStorage.setItem('bannerDismissedAt', oldDate.toISOString());
  //    - Refresh the page - banner should appear again
}

// ----------------------------------------------------------------------------
// ANALYTICS INTEGRATION (Optional)
// ----------------------------------------------------------------------------

class AnalyticsExample {
  // If you want to track banner interactions, modify the NativeAppBanner
  // widget to add analytics calls:
  //
  // In _NativeAppBannerState:
  //
  // 1. Track impression (when banner appears):
  //    void _trackBannerShown() {
  //      // Your analytics service
  //      AnalyticsService.logEvent(
  //        'native_app_banner_shown',
  //        parameters: {
  //          'platform': isIOS ? 'ios' : 'android',
  //          'timestamp': DateTime.now().toIso8601String(),
  //        },
  //      );
  //    }
  //
  // 2. Track dismissal:
  //    void _trackBannerDismissed() {
  //      AnalyticsService.logEvent('native_app_banner_dismissed');
  //    }
  //
  // 3. Track download click:
  //    void _trackBannerClicked({required String platform}) {
  //      AnalyticsService.logEvent(
  //        'native_app_banner_clicked',
  //        parameters: {'platform': platform},
  //      );
  //    }
}

// ----------------------------------------------------------------------------
// TROUBLESHOOTING
// ----------------------------------------------------------------------------

class TroubleshootingGuide {
  // Banner not showing?
  //
  // Check:
  // 1. Running on Flutter Web (kIsWeb == true)
  // 2. Using mobile device emulation in Chrome DevTools
  // 3. Not running as PWA (should be in regular browser)
  // 4. Haven't dismissed the banner (check localStorage)
  // 5. Waited for the delay period (default 4 seconds)
  //
  // Banner showing on desktop?
  //
  // Check:
  // 1. Platform detection is working (open Console and run):
  //    navigator.userAgent
  //    Should contain 'iPhone', 'iPad', or 'Android'
  //
  // Banner not dismissing?
  //
  // Check:
  // 1. localStorage is available (not in incognito mode)
  // 2. Check DevTools Application tab -> Local Storage
  // 3. Should see 'hideAppBanner' = 'true' after dismissing
  //
  // Links not opening?
  //
  // Check:
  // 1. url_launcher package is installed (should already be in pubspec.yaml)
  // 2. Console for any errors when clicking "Download app"
  // 3. Browser popup blocker settings
}
