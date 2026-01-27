# BandRoadie Landing Page - Local Preview Guide

## 🎸 What Was Built

A beautiful, Zenity-inspired marketing landing page with:

### ✅ Completed Sections
1. **Hero Section** - App name, tagline, and CTAs (App Store + Web App)
2. **Features Grid** - 4 feature cards (Rehearsals, Gigs, Calendar, Setlists)
3. **Value Proposition** - "Everything Your Band Needs — In One Place"
4. **Screenshots Carousel** - Interactive PageView showcasing app screens
5. **Download CTA** - App Store + Google Play (coming soon) buttons
6. **Footer** - Privacy Policy, Terms, Support links

### 🎨 Design Features
- **Zenity-inspired** - Clean sections, large typography, modern spacing
- **Fully responsive** - Mobile + desktop layouts
- **Rose accent** (#BE123C) - Matches BandRoadie brand
- **Dark theme** - Consistent with app aesthetic
- **Smooth animations** - Scroll-to-top FAB, carousel transitions

### 🔀 Routing Configuration
- **`/`** → Landing page (Web only)
- **`/app`** → Existing web app (auth gate)
- **`/privacy`** → Privacy policy
- **`/auth/confirm`** → Magic link verification
- **Mobile apps** → Bypass landing, go straight to app

---

## 🧪 Local Preview Instructions

### Option 1: Flutter Web (Chrome) - Recommended
```bash
# Navigate to project directory
cd /Users/tonyholmes/Documents/Apps/bandroadie

# Run on Chrome with hot reload
flutter run -d chrome
```

**What to expect:**
- Landing page opens at `http://localhost:XXXX/`
- Hot reload enabled (press `r` in terminal)
- Full responsive testing via Chrome DevTools

**Test the flow:**
1. Landing page loads with hero section
2. Scroll through all 6 sections
3. Click "Use the Web App" → redirects to `/app` (login screen)
4. Click "Download on the App Store" → opens iOS App Store
5. Test responsive: DevTools > Toggle device toolbar (iPhone 14, iPad)

---

### Option 2: macOS Desktop App
```bash
# Run native macOS build
flutter run -d macos
```

**What to expect:**
- macOS window opens with landing page
- Native performance
- Good for testing desktop layout

**Note:** Landing page is only shown on Web builds. macOS will technically show it, but the intended flow is Web → Landing, Mobile → Direct to App.

---

### Option 3: Local Web Server (Production-like)
```bash
# Build production web bundle
flutter build web --release

# Serve locally (Python 3)
cd build/web
python3 -m http.server 8000
```

**What to expect:**
- Open browser to `http://localhost:8000`
- Production-optimized build (minified, tree-shaken)
- Slower rebuilds (no hot reload)
- Closest to deployed experience

---

## 📱 Responsive Testing Checklist

### Mobile (< 900px width)
- [ ] Hero section: Single column, logo 60px, tagline readable
- [ ] Features: 1 column, cards full-width
- [ ] Value: Stacked value points
- [ ] Screenshots: Carousel works, swipe-able
- [ ] Download: Buttons stack vertically
- [ ] Footer: Links wrap properly

### Desktop (≥ 900px width)
- [ ] Hero section: Two-column (content + phone mockup)
- [ ] Features: 2x2 grid
- [ ] Value: 3 points side-by-side
- [ ] Screenshots: Carousel with larger viewport
- [ ] Download: Buttons side-by-side
- [ ] Footer: Links inline

### Chrome DevTools Devices
```
iPhone SE (375px) - Smallest mobile
iPhone 14 Pro (430px) - Standard mobile
iPad Air (820px) - Just below desktop breakpoint
Desktop (1024px+) - Desktop layout
```

---

## 🔗 CTA Testing

### Primary CTAs
1. **"Download on the App Store"** - Hero & Download sections
   ```
   URL: https://apps.apple.com/us/app/band-roadie/id6757283775
   Opens: External browser (iOS App Store)
   ```

2. **"Use the Web App"** - Hero & Download sections
   ```
   Route: /app
   Result: Navigates to AuthGate (login screen)
   ```

3. **"Get it on Google Play"** - Download section
   ```
   URL: https://play.google.com/store/apps/details?id=com.bandroadie.app
   Status: Disabled (Coming Soon badge)
   ```

### Secondary Links
- **Privacy Policy** → `/privacy` (existing screen)
- **Terms of Service** → TODO (placeholder)
- **Support** → TODO (placeholder)

---

## 🐛 Known Issues / TODOs

### Visual Placeholders
- **Phone mockup** - Desktop hero has icon placeholder (160x320 gray box)
  - Replace with actual iPhone screenshot mockup
- **Screenshots carousel** - Currently shows icons
  - Replace with real app screenshots (Rehearsals, Calendar, Setlists, Gigs)

### Missing Pages
- Terms of Service page
- Support/Contact page

### Optional Enhancements
- Add logo image to hero (currently using SVG, could use horizontal PNG)
- Scroll animations (fade-in on scroll)
- Analytics tracking (commented hooks in code)
- Carousel auto-play option

---

## 🚀 Deployment Preview (Before Production)

### Vercel Preview Deployment
```bash
# Build web
flutter build web --release

# Deploy to preview URL
cd build/web
vercel

# Follow prompts - DO NOT use --prod flag yet
```

**Result:** Get a `https://web-xxx-tholmes.vercel.app` preview URL

**Test on real devices:**
- iPhone Safari (iOS)
- Android Chrome
- Desktop browsers (Chrome, Safari, Firefox)

---

## 🎯 Pre-Production Checklist

Before deploying to `bandroadie.com`:

- [ ] Landing page loads correctly on localhost
- [ ] All 6 sections render without errors
- [ ] Responsive layouts work (mobile + desktop)
- [ ] CTAs navigate correctly
  - [ ] App Store link opens
  - [ ] Web App button → /app
- [ ] Scroll-to-top FAB appears after scrolling
- [ ] Privacy Policy link works
- [ ] No console errors (check browser DevTools)
- [ ] Screenshots carousel swipes smoothly
- [ ] Page indicators animate correctly
- [ ] Text is readable on all screen sizes
- [ ] Colors match BandRoadie brand (rose accent)

---

## 📝 Code Structure

```
lib/features/landing/
├── landing_page.dart              # Main page with scroll controller
├── widgets/
    ├── hero_section.dart          # Hero with CTAs
    ├── features_section.dart      # 4 feature cards
    ├── value_section.dart         # 3 value points
    ├── screenshots_section.dart   # Carousel
    ├── download_section.dart      # App store buttons
    └── footer_section.dart        # Footer links

lib/shared/widgets/
└── responsive.dart                # Responsive breakpoint widget

lib/main.dart                      # Updated routing (/ → landing, /app → auth)
```

---

## 🔧 Quick Fixes

### If landing page doesn't show
```bash
# Check routing
flutter run -d chrome --verbose

# Look for "Navigator" logs
# Should see: "Route '/' → LandingPage"
```

### If images don't load
```bash
# Verify assets in pubspec.yaml
grep -A5 "assets:" pubspec.yaml

# Should include: assets/images/
```

### If colors look wrong
Check `lib/app/theme/design_tokens.dart`:
- `AppColors.accent` = #BE123C (rose)
- `AppColors.scaffoldBg` = #0A0A0A (black)

---

## ✅ Success Criteria

Landing page is ready when:

1. **Visual** - All sections render with correct spacing and colors
2. **Responsive** - Mobile and desktop layouts work smoothly
3. **Interactive** - CTAs navigate correctly, carousel swipes
4. **Performance** - No lag, smooth scrolling
5. **Branded** - Matches BandRoadie aesthetic (rose accent, dark theme)

---

## 🚢 Deployment (When Ready)

```bash
# Full production deployment
flutter clean
flutter pub get
flutter build web --release
cd build/web
vercel --prod

# Updates: https://bandroadie.com
```

**Post-deployment:**
- Test on real devices (iOS, Android, Desktop)
- Monitor analytics (if implemented)
- Gather user feedback
- Iterate on screenshots/content

---

## 📞 Need Help?

**Common Issues:**
- "Landing page not showing" → Check routing in main.dart
- "Colors are wrong" → Verify design_tokens.dart imports
- "SVG won't load" → Check `flutter_svg` in pubspec.yaml
- "Web app link broken" → Ensure AuthGate route is `/app`

**Next Steps:**
1. Run `flutter run -d chrome`
2. Test all sections and CTAs
3. Verify responsive behavior
4. Replace placeholder images
5. Deploy to Vercel preview
6. Test on real devices
7. Deploy to production

🎸 **Rock on!**
