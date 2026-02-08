# Native App Banner for Flutter Web

A polished, dismissible banner that encourages mobile web users to download your native iOS or Android app.

## 🎸 Features

- **Smart Detection**: Only shows on mobile browsers (iOS Safari, Android Chrome)
- **Persistent Dismissal**: Uses localStorage to remember user preference
- **Auto Re-show**: Optionally re-appears after 30 days
- **Non-blocking UI**: Slides in smoothly without disrupting user flow
- **Material 3 Styling**: Dark mode compatible with Band Roadie design tokens
- **Platform-specific Links**: Automatically opens correct App Store or Google Play
- **PWA-aware**: Won't show if user is already running as standalone app

## 📁 Files Created

```
lib/shared/
├── utils/
│   ├── platform_detection.dart      # Conditional import facade
│   ├── platform_detection_stub.dart # Non-web stub implementation
│   ├── platform_detection_web.dart  # Web implementation with dart:html
│   ├── web_storage.dart            # Conditional import facade
│   ├── web_storage_stub.dart       # Non-web stub implementation
│   └── web_storage_web.dart        # Web localStorage implementation
└── widgets/
    ├── native_app_banner.dart              # Main banner widget
    └── native_app_banner_integration.dart  # Integration guide & examples
```

## 🚀 Quick Start

The banner is already integrated in [app_shell.dart](lib/features/shell/app_shell.dart):

```dart
// In the AppShell Stack, after bottom nav:
const NativeAppBanner(
  delay: Duration(seconds: 4),
  position: BannerPosition.top,
  hideOnAuthPages: true,
),
```

## 🎯 How It Works

### Platform Detection
Uses conditional imports to safely access `dart:html` only on web:
- `platform_detection.dart` - Main API (use this in your code)
- `platform_detection_web.dart` - Web implementation
- `platform_detection_stub.dart` - Returns `false` on non-web platforms

```dart
import 'package:bandroadie/shared/utils/platform_detection.dart';

if (isMobileWeb) {
  // User is on mobile browser, not PWA
}
```

### Storage
Uses localStorage to persist dismissal:
- Key: `hideAppBanner` = `'true'`
- Key: `bannerDismissedAt` = ISO8601 timestamp
- Auto-clears after 30 days to re-show banner

```dart
import 'package:bandroadie/shared/utils/web_storage.dart';

if (!dismissedAppBanner) {
  // Show banner
}

dismissAppBanner(); // User clicked "Not now"
```

### Show Logic
```dart
bool shouldShow = 
  kIsWeb &&           // Running on web
  !isStandalone &&    // Not running as PWA
  !dismissedAppBanner && // User hasn't dismissed
  (isIOS || isAndroid); // Mobile device
```

## 🎨 UI Design

- **Position**: Top or bottom of screen
- **Animation**: Smooth slide-in after configurable delay
- **Layout**: 
  - 🎸 emoji + title
  - Subtitle with benefits
  - Primary CTA: "Download app" (rose accent)
  - Secondary CTA: "Not now" (text button)
  - Close icon (top-right)
- **Styling**: Material 3 with dark mode support
- **Spacing**: Uses design tokens from [design_tokens.dart](lib/app/theme/design_tokens.dart)

## 📝 Configuration Options

```dart
const NativeAppBanner(
  // Delay before showing (default: 4 seconds)
  delay: Duration(seconds: 4),
  
  // Position on screen
  position: BannerPosition.top, // or BannerPosition.bottom
  
  // Hide on login/signup pages
  hideOnAuthPages: true,
)
```

## 🔗 Store Links

Hardcoded in [native_app_banner.dart](lib/shared/widgets/native_app_banner.dart):

- **iOS**: `https://apps.apple.com/us/app/band-roadie/id6757283775`
- **Android**: `https://play.google.com/store/apps/details?id=com.bandroadie.app`

Opens in new tab using `url_launcher` package.

## 🧪 Testing

### 1. Run web app in Chrome
```bash
flutter run -d chrome
```

### 2. Enable mobile emulation
- Open DevTools (F12)
- Toggle device toolbar (Cmd+Shift+M / Ctrl+Shift+M)
- Select iPhone or Pixel device

### 3. Test dismissal
Banner should appear after 4 seconds. Click "Not now" to dismiss.

### 4. Reset dismissal
Open Console and run:
```javascript
localStorage.removeItem('hideAppBanner');
localStorage.removeItem('bannerDismissedAt');
```
Refresh page to see banner again.

### 5. Test 30-day re-show
```javascript
// Dismiss banner first, then run:
const oldDate = new Date();
oldDate.setDate(oldDate.getDate() - 31); // 31 days ago
localStorage.setItem('bannerDismissedAt', oldDate.toISOString());
```
Refresh page - banner should reappear.

## 📊 Analytics (Optional)

To track banner interactions, add analytics calls in [native_app_banner.dart](lib/shared/widgets/native_app_banner.dart):

```dart
// When banner appears
void _trackBannerShown() {
  AnalyticsService.logEvent(
    'native_app_banner_shown',
    parameters: {
      'platform': isIOS ? 'ios' : 'android',
      'timestamp': DateTime.now().toIso8601String(),
    },
  );
}

// When dismissed
void _trackBannerDismissed() {
  AnalyticsService.logEvent('native_app_banner_dismissed');
}

// When clicked
void _trackBannerClicked({required String platform}) {
  AnalyticsService.logEvent(
    'native_app_banner_clicked',
    parameters: {'platform': platform},
  );
}
```

## 🐛 Troubleshooting

### Banner not showing?
1. ✅ Running on web (`kIsWeb == true`)
2. ✅ Mobile device emulation enabled
3. ✅ Not in PWA mode (check address bar)
4. ✅ Banner not dismissed (check localStorage)
5. ✅ Waited for delay (default 4 seconds)

### Check localStorage
DevTools → Application → Local Storage → `http://localhost:...`
- Should see `hideAppBanner: 'true'` after dismissing
- Should see `bannerDismissedAt: '2026-01-23T...'` with timestamp

### Banner showing on desktop?
User agent detection may be failing. Check Console:
```javascript
navigator.userAgent
```
Should contain `iPhone`, `iPad`, or `Android` for banner to show.

### Links not opening?
1. Check `url_launcher` is in [pubspec.yaml](pubspec.yaml) (should already be installed)
2. Check browser Console for errors
3. Check popup blocker settings

## 🎓 Integration Guide

See [native_app_banner_integration.dart](lib/shared/widgets/native_app_banner_integration.dart) for:
- Complete integration examples
- Configuration options
- Testing procedures
- Analytics setup
- Troubleshooting tips

## 📱 Production Checklist

Before deploying to production:

- [ ] Test on real iOS Safari (iPhone)
- [ ] Test on real Android Chrome
- [ ] Verify iOS App Store link works
- [ ] Verify Google Play link works
- [ ] Confirm banner doesn't show on desktop
- [ ] Confirm banner doesn't show in PWA mode
- [ ] Test dismissal persistence
- [ ] Test 30-day re-show (optional)
- [ ] Add analytics tracking (optional)
- [ ] Deploy to web: `flutter build web --release`

## 🎯 User Experience

The banner strikes a balance between:
- **Visibility**: Appears prominently but doesn't block content
- **Timing**: 4-second delay avoids immediate disruption
- **Persistence**: Remembers dismissal for 30 days
- **Convenience**: Direct links to app stores

Users who want the native app will download. Users who prefer web won't be nagged repeatedly.

## 🔄 Future Enhancements

Potential improvements:
- [ ] Add route-based hiding (skip auth pages)
- [ ] A/B test different copy
- [ ] Track conversion rate (banner click → app install)
- [ ] Customize delay per page
- [ ] Add animation when dismissing
- [ ] Smart targeting (show after X sessions)

---

Built with 🎸 for Band Roadie
