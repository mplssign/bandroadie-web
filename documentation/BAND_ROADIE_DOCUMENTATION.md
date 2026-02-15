# BandRoadie - Complete Application Documentation

## Quick Reference for New AI Chat Sessions

> **IMPORTANT:** This section contains critical information for any AI assistant continuing development on this project.

### Project Identifiers
- **Package Name (Flutter):** `bandroadie`
- **Bundle Identifier (iOS/macOS):** `com.tonyholmes.bandroadie`
- **Application ID (Android):** `com.tonyholmes.bandroadie`
- **Deep Link Scheme:** `bandroadie://login-callback/`
- **Live Web App:** https://bandroadie.com
- **Vercel Deployment:** Web builds deployed via Vercel

### Critical Configuration Files
| File | Purpose |
|------|---------|
| `.env` | Supabase credentials (SUPABASE_URL, SUPABASE_ANON_KEY) |
| `android/app/build.gradle.kts` | Android Kotlin DSL config (namespace, applicationId) |
| `android/app/google-services.json` | Firebase Android config for push notifications |
| `android/app/src/main/AndroidManifest.xml` | Deep links, v2 embedding |
| `ios/Runner/Info.plist` | iOS URL schemes, UIBackgroundModes for push |
| `ios/Runner/GoogleService-Info.plist` | Firebase iOS config |
| `macos/Runner/Info.plist` | macOS URL schemes, app config |
| `macos/Runner/*.entitlements` | macOS network permissions |
| `lib/main.dart` | App entry point, Supabase init |

### Push Notification Architecture
The app uses **Firebase Cloud Messaging (FCM) with Supabase Edge Functions**:
1. User creates gig/rehearsal/blockout → Database trigger fires
2. Notification record inserted → Webhook triggers Edge Function
3. Edge Function authenticates via OAuth2 service account
4. FCM HTTP v1 API sends push to registered device tokens
5. Notification appears on recipient's device

**Key Push Files:**
- [lib/features/notifications/push_notification_service.dart](lib/features/notifications/push_notification_service.dart) - FCM token management
- [supabase/functions/send-push/index.ts](supabase/functions/send-push/index.ts) - FCM delivery Edge Function
- [NOTIFICATION_SYSTEM.md](NOTIFICATION_SYSTEM.md) - Complete notification documentation

**Required Supabase Secrets:**
| Secret | Description |
|--------|-------------|
| `FIREBASE_PROJECT_ID` | Firebase project ID (`bandroadie-65b18`) |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | Full JSON service account key |

### Authentication Architecture
The app uses **Supabase Magic Link Authentication with PKCE flow**:
1. User enters email → `signInWithOtp()` called with `emailRedirectTo`
2. Web: No redirect URL (uses Supabase default)
3. Native apps: Uses `bandroadie://login-callback/` redirect
4. Magic link email sent with confirmation URL
5. Web: Opens `/auth/confirm?token_hash=...` → `AuthConfirmScreen` handles
6. Native: Deep link opens app → Supabase SDK handles auth automatically

**Key Auth Files:**
- [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart) - Magic link request
- [lib/features/auth/auth_confirm_screen.dart](lib/features/auth/auth_confirm_screen.dart) - Web token verification

### Deep Link Configuration
Deep links are configured for magic link authentication on native platforms:

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="bandroadie" android:host="login-callback" android:pathPattern=".*"/>
</intent-filter>
```

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array><string>bandroadie</string></array>
    </dict>
</array>
```

**macOS** (`macos/Runner/Info.plist`): Same as iOS

### Supabase Dashboard Settings
The following settings must be configured in Supabase Dashboard:

1. **Authentication → URL Configuration → Redirect URLs:**
   - `https://bandroadie.com/auth/confirm`
   - `bandroadie://login-callback/`

2. **Authentication → Email Templates → Confirm signup:**
   - Template must use `{{ .ConfirmationURL }}` (NOT hardcoded URLs)

### macOS Network Requirements
macOS requires explicit network entitlements in:
- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Release.entitlements`

Both must include:
```xml
<key>com.apple.security.network.client</key>
<true/>
```

### Common Development Commands
```bash
# Run on platforms
flutter run -d macos
flutter run -d chrome
flutter run -d ios

# Clean rebuild
flutter clean && flutter pub get

# Build and deploy web
flutter build web --release
cd build/web && vercel --prod

# Hot reload: Press 'r' in terminal while app is running
```

---

## Application Overview

**Band Roadie** is a comprehensive cross-platform application designed for band management and coordination. Built with Flutter and Supabase, it provides bands with tools to manage rehearsals, gigs, setlists, member coordination, and more. The app runs on iOS, Android, macOS, and Web.

### Core Identity
- **Name:** Band Roadie
- **Version:** 1.3.1
- **Tagline:** "Ultimate Band Management"
- **Description:** Manage your band's rehearsals, gigs, and setlists
- **Live Web App:** https://bandroadie.com

## Technology Stack

### Frontend
- **Framework:** Flutter 3.x with Dart 3.10.4
- **State Management:** Riverpod for reactive state
- **UI Design:** Custom dark theme with Rose accent (#f43f5e)
- **Animation:** Flutter built-in animations + custom controllers
- **Platforms:** iOS, Android, macOS, Web

### Backend & Database
- **Backend:** Supabase (PostgreSQL + Auth + Real-time + Edge Functions)
- **Authentication:** Supabase Auth with PKCE flow and magic links
- **Database:** PostgreSQL via Supabase with Row Level Security (RLS)
- **Email:** Resend for transactional emails
- **File Storage:** Supabase Storage
- **Edge Functions:** Deno-based serverless functions for external API integrations

### Key Dependencies
- `flutter_riverpod` - State management
- `supabase_flutter` - Supabase SDK for Flutter
- `go_router` - Declarative routing
- `share_plus` - Native share sheet integration
- `url_launcher` - External URL handling
- `intl` - Internationalization and date formatting

## Application Architecture

### Directory Structure
```
band-roadie/
├── lib/                          # Flutter source code
│   ├── main.dart                 # App entry point
│   ├── app/                      # App configuration
│   │   ├── router/               # GoRouter configuration
│   │   └── theme/                # Design tokens and theming
│   ├── components/               # Shared UI components
│   │   └── ui/                   # Base UI components
│   ├── contexts/                 # App-wide contexts
│   ├── features/                 # Feature modules
│   │   ├── auth/                 # Authentication screens
│   │   ├── bands/                # Band management
│   │   ├── calendar/             # Calendar views
│   │   ├── events/               # Event editor drawer (gigs, rehearsals)
│   │   ├── gigs/                 # Gig management
│   │   ├── home/                 # Home/Dashboard
│   │   ├── members/              # Member management
│   │   ├── onboarding/           # Animated first-time onboarding
│   │   ├── profile/              # User profile
│   │   ├── rehearsals/           # Rehearsal scheduling
│   │   └── setlists/             # Setlist management
│   │       ├── models/           # Data models
│   │       ├── services/         # Business logic
│   │       ├── tuning/           # Tuning helpers
│   │       └── widgets/          # UI components
│   └── shared/                   # Shared utilities
├── assets/                       # Static assets (images, fonts)
├── supabase/                     # Supabase configuration
│   ├── functions/                # Edge Functions
│   └── migrations/               # Database migrations
├── ios/                          # iOS platform code
├── android/                      # Android platform code
├── macos/                        # macOS platform code
├── web/                          # Web platform code
└── test/                         # Unit and widget tests
```

## Core Features

### 1. Authentication System
- **Magic Link Authentication:** Passwordless login via email
- **PKCE Flow:** Secure authentication flow
- **Animated Onboarding:** Cinematic first-time experience with splash screen, 3-step wizard (name, zip, birthday), and confetti celebration
- **Session Management:** Persistent sessions with automatic refresh
- **Protected Routes:** Middleware-based route protection

### 2. Band Management
- **Multi-Band Support:** Users can belong to multiple bands
- **Band Creation:** Create new bands with member invitations
- **Band Switching:** Easy switching between bands
- **Member Management:** Invite, manage, and remove band members
- **Role-Based Access:** Different permission levels for band members

### 3. Dashboard
- **Centralized Hub:** Overview of upcoming events and quick actions
- **Next Rehearsal Display:** Shows upcoming rehearsal details
- **Potential Gig Alerts:** Highlights gigs needing confirmation
- **Quick Actions:** Fast access to create setlists, gigs, rehearsals
- **Welcome Screen:** Onboarding for new users without bands

### 4. Event Management
#### Rehearsals
- **Scheduling:** Create and manage rehearsal sessions
- **Location Tracking:** Venue and location management
- **Time Management:** Start and end time coordination
- **Notes:** Additional rehearsal information

#### Gigs
- **Gig Creation:** Schedule performances and shows
- **Venue Management:** Track performance locations
- **Potential Gigs:** Mark uncertain gigs for later confirmation
- **Multi-Date Potential Gigs:** Add multiple date options directly when potential gig is enabled (no separate toggle needed)
- **Event Title:** User-typed capitalization is preserved exactly (no auto title-case)
- **Member Responses:** Track who can/cannot attend
- **Setlist Assignment:** Link setlists to specific gigs

### 5. Setlist Management
- **Setlist Creation:** Build song lists for performances
- **Catalog:** Maintain band's master song repertoire (single source of truth)
- **Drag-and-Drop Ordering:** Intuitive song arrangement via drag handle
- **BPM Tracking:** Tap-to-edit BPM values with inline editing (20-300 range)
- **Duration Tracking:** Tap-to-edit duration in mm:ss format
- **Tuning Information:** Track instrument tunings per song with bottom sheet picker
- **Tuning Sort Modes:** Sort by tuning groups (Standard first, then Half-Step, etc.)
- **Custom Ordering:** Standard sort mode preserves user's custom song order
- **Song Metadata RPC:** Server-side functions bypass RLS for legacy song updates
- **Inline Editing:** Tap BPM, Duration, or Tuning badges to edit in place
- **Override Indicators:** Rose border on badges when song has custom values

### 6. Song Card UX
- **Drag Handle:** Reorder songs by dragging the grip icon on left side only
- **Scroll-Friendly:** Touching anywhere except drag handle scrolls normally
- **Card Layout:** Title, Artist, Delete button, and metrics row (BPM, Duration, Tuning)
- **Micro-Interactions:** Scale/opacity feedback on tap, elevation on drag
- **Save on Blur:** Editing automatically saves when focus leaves the field

### 7. Member Coordination
- **Invitation System:** Email-based band invitations
- **Member Directory:** View all band members and their roles
- **Role Management:** Assign and manage member roles (vocals, guitar, etc.)
- **Contact Information:** Access to member contact details
- **Attendance Tracking:** Monitor member availability for events

### 8. External Song Lookup
- **Search External APIs:** Find songs not in your Catalog from online databases
- **Auto-Add to Catalog:** Selected external songs are automatically added
- **BPM Enrichment:** BPM is pulled from external sources when available
- **Album Artwork:** External results display album art when available
- **Edge Functions:** Supabase Edge Functions handle API token caching and rate limits

### 9. Profile Management
- **Personal Information:** Name, phone, address, birthday
- **Musical Roles:** Assign and manage musical roles/instruments
- **Custom Roles:** Create custom roles beyond standard instruments
- **Profile Completion:** Handled via animated onboarding flow (see User Experience Flow)
- **Settings:** User preferences and account settings

## User Experience Flow

### New User Journey (Animated Onboarding)
1. **Registration:** Email-based registration with magic link
2. **Cinematic Splash:** Logo scales in with bounce animation, tagline fades in with blur-to-sharp effect, radial rose glow on black background
3. **Onboarding Wizard:** 3-step fluid card transitions with spring-based animations:
   - **Step 1 — Name:** "What should we call you?" (first name only)
   - **Step 2 — Zip Code:** Location input with shake validation
   - **Step 3 — Birthday:** Month pills (ALL CAPS, rose outline/filled) + day selector
4. **Completion Celebration:** Confetti burst, logo reappear, "You're all set!" message
5. **Skip Option:** "Skip for now" available on every step, routes to band access
6. **Band Access:** Create new band or accept invitation
7. **Dashboard:** Access to main application features

**Key files:**
- `lib/features/onboarding/onboarding_screen.dart` — Full onboarding experience (splash, wizard, celebration)
- `lib/features/auth/auth_gate.dart` — Routes new users to `OnboardingGateScreen`

### Existing User Journey
1. **Login:** Magic link authentication
2. **Dashboard:** Immediate access to band information
3. **Band Operations:** Manage rehearsals, gigs, setlists, members
4. **Multi-Band:** Switch between different bands if member of multiple

### Invitation Flow
1. **Invitation:** Band member sends email invitation
2. **Registration:** Recipient creates account via magic link
3. **Profile Setup:** Complete profile information
4. **Band Access:** Automatic addition to inviting band

## Technical Implementation Details

### Authentication Flow
- **Magic Links:** Passwordless authentication via email
- **PKCE:** Proof Key for Code Exchange for security
- **Session Management:** Supabase handles session persistence
- **Auth Gate:** App-level authentication checking with Riverpod
- **Profile Validation:** Ensures complete profiles before access

### State Management
- **Riverpod:** Application-wide state management with providers
- **StateNotifier:** Controllers for complex state (setlists, gigs, etc.)
- **AsyncValue:** Loading, error, and data states handled uniformly
- **Supabase Real-time:** Live updates for collaborative features

### Database Schema
```sql
-- Core Tables
users              # User profiles and authentication
bands              # Band information
band_members       # Many-to-many band membership
band_invitations   # Email invitations to join bands

-- Event Management
rehearsals         # Rehearsal scheduling
gigs               # Performance scheduling
gig_responses      # Member attendance responses
block_dates        # Member availability/unavailability

-- Setlist Management
setlists           # Song collections (including Catalog per band)
songs              # Individual song information
setlist_songs      # Many-to-many with position ordering

-- Additional Features
roles              # Custom role definitions
tunings            # Instrument tuning definitions
```

### RPC Functions (Supabase)
The app uses PostgreSQL functions with `SECURITY DEFINER` to handle operations that bypass Row Level Security:

```sql
-- Update song metadata (BPM, duration, tuning) for legacy songs
update_song_metadata(p_song_id, p_band_id, p_bpm, p_duration_seconds, p_tuning)

-- Clear song metadata fields
clear_song_metadata(p_song_id, p_band_id, p_clear_bpm, p_clear_duration, p_clear_tuning)
```

These RPCs are necessary because some legacy songs have `NULL` band_id values and would be blocked by RLS policies.

### Flutter Architecture
- **Feature-First:** Code organized by feature, not layer
- **Repository Pattern:** Data access abstracted behind repositories
- **Controllers:** StateNotifier classes manage feature state
- **Widgets:** Stateless where possible, stateful for animations/editing

## Cross-Platform Support

### Platforms
- **iOS:** Native iOS app via Flutter
- **Android:** Native Android app via Flutter
- **macOS:** Desktop app via Flutter
- **Web:** Progressive Web App deployed to Vercel

### Web Deployment (Vercel)
- **URL:** https://bandroadie.com
- **Build:** `flutter build web --release` (via `scripts/build_web.sh`)
- **Hosting:** Vercel with SPA routing configuration
- **Caching:** Static assets cached with long TTLs

#### Environment Variables (Vercel)
Vercel **must have the following environment variables** set for the build to succeed:

| Variable | Description | Source |
|----------|-------------|--------|
| `SUPABASE_URL` | Supabase project URL | Supabase Dashboard > Settings > API |
| `SUPABASE_ANON_KEY` | Supabase anonymous publishable key | Supabase Dashboard > Settings > API > Project API keys |

**Setup Instructions:**
1. Go to Vercel Dashboard → Project Settings → Environment Variables
2. Add `SUPABASE_URL` with value from Supabase project
3. Add `SUPABASE_ANON_KEY` with value from Supabase (use the "anon public" key)
4. Set both to apply to Production
5. Redeploy the project

**Note:** The `build_web.sh` script passes these as `--dart-define` flags to the Flutter build. Without these variables, the app will show a configuration error screen.

### Mobile-First Design
- **Responsive Design:** Optimized for mobile devices first
- **Touch Interactions:** Large touch targets (48px minimum)
- **Bottom Navigation:** Mobile-first navigation pattern
- **Gesture Support:** Swipe, drag, and tap gestures

## Security & Privacy

### Authentication Security
- **PKCE Flow:** Industry-standard secure authentication
- **Magic Links:** No password storage or transmission
- **Session Security:** Secure cookie handling
- **CSRF Protection:** Cross-site request forgery protection

### Data Protection
- **Supabase Security:** Row-level security policies
- **User Isolation:** Users only access their own data
- **Band Privacy:** Members only see their bands' information
- **Invitation Security:** Time-limited invitation links

## Development & Deployment

### Development Setup
```bash
# Install Flutter dependencies
flutter pub get

# Run on macOS
flutter run -d macos

# Run on iOS Simulator
flutter run -d ios

# Run on Chrome (Web)
flutter run -d chrome

# Build for web production
flutter build web --release

# Deploy to Vercel
cd build/web && vercel --prod
```

### Environment Variables
```
# Set in Supabase Dashboard and app configuration
SUPABASE_URL=              # Supabase project URL
SUPABASE_ANON_KEY=         # Supabase anonymous key
RESEND_API_KEY=            # Resend email API key (Edge Functions)
```

### Testing Strategy
- **Unit Tests:** Dart tests for models, utilities, and services
- **Widget Tests:** Flutter widget testing
- **Integration Tests:** End-to-end user flow testing
- **Analysis:** `flutter analyze` for static analysis

## Current State & Recent Changes

### Version 1.3.2 (January 2026)

#### Android Build System Migration
- **Problem:** Android build was using deprecated v1 embedding and old Groovy Gradle files, causing build failures
- **Solution:** Replaced entire `android/` folder with fresh Flutter v2 structure using Kotlin DSL
- **Files:** `android/build.gradle.kts`, `android/app/build.gradle.kts`, `android/settings.gradle.kts`
- **Key Changes:**
  - Namespace and applicationId set to `com.tonyholmes.bandroadie`
  - `flutterEmbedding` value set to `2` in AndroidManifest.xml
  - Deep link intent-filter added for `bandroadie://login-callback`

#### Magic Link Authentication Fix
- **Problem:** Magic link emails were redirecting to web instead of native app, and web confirmation was failing with "Token has expired or is invalid"
- **Root Cause 1:** Supabase email template had hardcoded URL instead of `{{ .ConfirmationURL }}`
- **Root Cause 2:** `AuthConfirmScreen` was using deprecated `exchangeCodeForSession()` method
- **Solution:**
  1. Updated Supabase email template to use `{{ .ConfirmationURL }}`
  2. Rewrote `auth_confirm_screen.dart` to use `verifyOTP()` with PKCE token detection
- **PKCE Detection Logic:** Tokens starting with `pkce_` use `OtpType.magiclink`, others use `OtpType.email`

#### macOS Network Entitlements
- **Problem:** macOS app couldn't make network requests (Supabase calls failing)
- **Solution:** Added `com.apple.security.network.client` entitlement to both Debug and Release entitlements

#### App Branding Updates
- **Change:** Replaced header bar logo from `bandroadie_stacked.png` to `bandroadie_horiz.png`
- **Files Updated:**
  - `lib/features/home/widgets/home_app_bar.dart`
  - `lib/features/setlists/widgets/setlists_app_bar.dart`
  - `lib/features/calendar/widgets/calendar_app_bar.dart`

### Version 1.3.1 (December 2025)

#### Song Card Drag Handle Fix
- **Problem:** Touching anywhere on song cards would trigger drag-to-reorder, making scrolling difficult
- **Solution:** Restricted drag initiation to only the grip icon area (left 36px of card)
- **Files:** `reorderable_song_card.dart`, `setlist_detail_screen.dart`, `new_setlist_screen.dart`

#### Song Metadata RPC Functions
- **Problem:** BPM, Duration, and Tuning edits failed for legacy songs with NULL band_id due to RLS
- **Solution:** Created `update_song_metadata` and `clear_song_metadata` PostgreSQL functions with SECURITY DEFINER
- **Migration:** `064_update_song_metadata_rpc.sql`

#### Song Metadata Save Failure (PGRST203) Fix
- **Problem:** Song metadata edits (BPM, Duration, Tuning, Notes, Title/Artist) failed with Supabase error `PGRST203: "Could not choose the best candidate function"`
- **Root Cause:** Multiple overloaded versions of `update_song_metadata()` existed in the database with different parameter counts (5, 6, 7, and 8 parameters), causing PostgREST to fail to resolve which function to call
- **Solution:**
  1. Updated all 6 RPC calls in `setlist_repository.dart` to explicitly pass all 8 parameters (using `null` for unused fields)
  2. Created migration `078_drop_old_update_song_metadata_overloads.sql` to drop old function overloads
  3. Kept single 8-parameter `update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT)` function
- **Key Insight:** Supabase PostgREST cannot resolve function overloads when called with partial parameter lists, even if parameters have DEFAULT values. Must pass all parameters explicitly.
- **Files Modified:**
  - `lib/features/setlists/setlist_repository.dart` - Updated methods: `updateSongBpmOverride()`, `updateSongDurationOverride()`, `updateSongTuningOverride()`, `updateSongNotes()`, `updateSongTitleArtist()`, Spotify BPM enrichment
- **Migration:** `lib/supabase/migrations/078_drop_old_update_song_metadata_overloads.sql`

#### Standard Sort Mode Fix
- **Problem:** "Standard" tuning sort mode was sorting songs instead of preserving user's custom order
- **Solution:** Standard mode now returns songs in their database position order (user's custom order)
- **File:** `setlist_detail_controller.dart`

### Version 1.3.0 (December 2025)
- External Song Lookup via Supabase Edge Functions
- Supabase Edge Functions for API token caching
- Edit icon to rename setlists from detail page
- "+ New" button in Setlists header
- Database triggers for accurate duration stats

### Bulk Add Songs Feature

The Bulk Add Songs feature allows users to quickly import multiple songs from a spreadsheet into their setlist and band Catalog.

**UI Flow:**
1. User taps "Bulk Paste" button on Setlist Detail screen
2. Modal overlay opens with multi-line text input
3. User pastes tab-delimited data (or 2+ space separated)
4. Live preview shows parsed rows with validation status
5. Invalid rows display inline error badges; warnings display inline warning badges
6. "Add Songs" button becomes enabled when valid rows exist
7. On submit: songs are created in Supabase and added to both Catalog and current setlist

**UI Copy:**
- Title: "Bulk Add Songs"
- Subtext Line 1: "Paste data from your Spreadsheet"
- Subtext Line 2: "Columns: ARTIST, SONG, BPM, TUNING"
- Helper: "You can also type song info by typing ARTIST, then hitting the Tab key, SONG, then Tab, BPM, then Tab, TUNING."

**Expected Input Format:**
```
ARTIST    SONG    BPM    TUNING
The Beatles    Come Together    82    Standard
Led Zeppelin    Whole Lotta Love    91    Drop D
```

**Row Limits:**
- Maximum 500 rows per paste
- If >500 rows pasted, shows error banner and processes only first 500

**Parsing Rules:**
- Columns: ARTIST, SONG (required), BPM (optional), TUNING (optional)
- Delimiter: TAB preferred, falls back to 2+ spaces
- BPM: Integer 1-300 or empty; invalid BPM → warning (row still valid, BPM set to null)
- Tuning normalization: Maps common variations to internal IDs
  - "Standard", "E Standard", "E", "Standard (E A D G B e)" → `standard_e`
  - "Half-Step", "Eb Standard", "E♭" → `half_step_down`
  - "Drop D", "Drop D tuning" → `drop_d`
  - "Drop C", "Drop B", "Drop A", etc.
  - "Open G", "Open G (D G D G B D)" → `open_g`
  - Parenthetical info and trailing "tuning" word are stripped before matching
  - Unknown tuning → warning (row still valid, tuning set to null)
- De-duplication: Same artist+song (case-insensitive) within batch → only first processed
- Missing song title → error (row invalid)

**Database Behavior:**
1. Ensures Catalog setlist exists for the band
2. For each valid row: Create/upsert song in `public.songs` (de-duped by band_id + title + artist)
3. Add song to Catalog setlist (always)
4. Add song to current setlist (if not already Catalog)
5. Duplicate inserts silently ignored (unique constraint)

**Files:**
- `lib/features/setlists/models/bulk_song_row.dart` - Parsed row model with warning support
- `lib/features/setlists/services/bulk_song_parser.dart` - Pure parsing logic with fuzzy tuning matching
- `lib/features/setlists/widgets/bulk_add_songs_overlay.dart` - Overlay UI with 500-row limit
- `lib/features/setlists/setlist_repository.dart` - `bulkAddSongs()` method

### Share Setlist Feature (Flutter App)

The Share Setlist feature allows users to share a plain-text version of their setlist via the native share sheet.

**UI Flow:**
1. User taps the Share icon (iOS share icon) in the Setlist Detail action buttons row
2. Native share sheet opens with formatted plain-text content
3. User can share via Messages, Mail, Notes, AirDrop, etc.

**Output Format:**
```
Setlist Name
49 songs • 1h 39m

Song Title
Artist Name                       125 BPM • Standard

Another Song
Another Artist                    - BPM • Drop D
```

**Formatting Rules:**
- **Header:** Setlist name on line 1, song count + total duration on line 2
- **Duration format:** `< 60 min` → "Xm" or "Xm Ys", `>= 60 min` → "Hh Mm"
- **Song block:** Title on first line, artist + BPM/tuning on second line
- **Two-column alignment:** Artist left-aligned, BPM/tuning right-aligned within 56-char width
- **BPM:** Shows "- BPM" if null/zero, otherwise "{bpm} BPM"
- **Tuning:** Uses short badge labels (Standard, Half-Step, Drop D, etc.)
- **Overflow handling:** If artist + metadata exceeds width, metadata wraps to indented next line

**Dependencies:**
- `share_plus: ^10.1.4` - Native share sheet integration

**Files:**
- `lib/features/setlists/setlist_detail_screen.dart` - `_handleShare()` and formatting helpers

### Active Issues
- **Supabase RLS:** Legacy songs with NULL band_id require RPC functions for updates

### Known Working Configurations
- **macOS:** Magic link authentication tested and working (January 2026)
- **Web:** Magic link authentication tested and working (January 2026)
- **Android:** Deep link configuration in place, needs device testing
- **iOS:** Deep link configuration in place, needs device testing

### Troubleshooting Guide

#### Web App Blank White Screen in Production
**Problem:** App loads but shows blank white screen at https://bandroadie.com

**Root Cause:** Supabase credentials (SUPABASE_URL, SUPABASE_ANON_KEY) are not set as Vercel environment variables during the build.

**Solution:**
1. Go to Vercel Dashboard → BandRoadie Project → Settings → Environment Variables
2. Add `SUPABASE_URL` = your Supabase project URL
3. Add `SUPABASE_ANON_KEY` = your Supabase anonymous key (from Dashboard > Settings > API > Project API keys)
4. Ensure both are set for **Production**
5. **Redeploy** the project (git push or manual redeploy from Vercel)

**Technical Details:** The `build_web.sh` script passes these as `--dart-define` flags to the Flutter build. Without these, `validateSupabaseConfig()` fails and shows a config error (though it may appear as blank screen due to theme rendering).

**Files Involved:**
- `scripts/build_web.sh` - Passes environment variables to build
- `lib/app/supabase_config.dart` - Validates credentials

#### Magic Link Not Opening Native App
1. Check Supabase Dashboard → Authentication → URL Configuration → Redirect URLs includes `bandroadie://login-callback/`
2. Verify Supabase email template uses `{{ .ConfirmationURL }}` not hardcoded URL
3. Check platform-specific URL scheme is registered (Info.plist for iOS/macOS, AndroidManifest.xml for Android)
4. For macOS: Ensure network entitlements are present

#### "Token has expired or is invalid" Error on Web
1. Verify `auth_confirm_screen.dart` is using `verifyOTP()` method
2. Check token is being passed correctly from URL query parameters
3. Ensure PKCE tokens (starting with `pkce_`) use `OtpType.magiclink`

#### Network Errors on macOS
1. Check `macos/Runner/DebugProfile.entitlements` has `com.apple.security.network.client`
2. Check `macos/Runner/Release.entitlements` has same entitlement
3. Run `flutter clean && flutter pub get` and rebuild

#### Android Build Failures
1. Ensure `android/app/build.gradle.kts` uses Kotlin DSL (not Groovy)
2. Verify `flutterEmbedding` is `2` in AndroidManifest.xml
3. Check namespace matches applicationId in build.gradle.kts

### Planned Enhancements
- **Calendar Integration:** Visual calendar for events
- **Advanced Setlist Features:** Tempo mapping, key changes
- **Native App Store Releases:** iOS App Store and Google Play
- **Payment Integration:** Premium features and subscriptions

## Key Files Reference

### Authentication
| File | Purpose |
|------|----------|
| `lib/features/auth/login_screen.dart` | Magic link login UI, `signInWithOtp()` call |
| `lib/features/auth/auth_confirm_screen.dart` | Web token verification with `verifyOTP()` |
| `lib/features/auth/auth_gate.dart` | Auth routing: Login → Onboarding → NoBandShell/AppShell |
| `lib/features/onboarding/onboarding_screen.dart` | Animated onboarding (splash, wizard, celebration) |
| `lib/main.dart` | Supabase initialization, deep link handling |

### Platform Configuration
| File | Purpose |
|------|---------|
| `android/app/build.gradle.kts` | Android namespace, applicationId, SDK versions |
| `android/app/src/main/AndroidManifest.xml` | Deep link intent-filter, v2 embedding |
| `ios/Runner/Info.plist` | iOS URL schemes, bundle config |
| `macos/Runner/Info.plist` | macOS URL schemes, bundle config |
| `macos/Runner/DebugProfile.entitlements` | macOS debug permissions (network) |
| `macos/Runner/Release.entitlements` | macOS release permissions (network) |

### Setlist Management
| File | Purpose |
|------|---------|
| `lib/features/setlists/setlist_repository.dart` | Database operations, RPC calls |
| `lib/features/setlists/setlist_detail_controller.dart` | State management, sorting logic |
| `lib/features/setlists/setlist_detail_screen.dart` | Main setlist UI screen |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | Song card with inline editing |
| `lib/features/setlists/services/bulk_song_parser.dart` | Bulk paste parsing logic |
| `lib/features/setlists/tuning/tuning_helpers.dart` | Tuning normalization and display |

### Event Management
| File | Purpose |
|------|---------|
| `lib/features/events/widgets/event_editor_drawer.dart` | Add/Edit Event drawer (~4000 lines, gigs + rehearsals) |
| `lib/features/events/models/event_form_data.dart` | Event form data model with `EventType`, `EventFormData` |
| `lib/app/models/gig_date.dart` | `GigDate` model for multi-date potential gigs |
| `lib/shared/utils/title_case_formatter.dart` | `TitleCaseTextFormatter` (used by location/city fields, NOT event title) |

### Database Migrations
| Migration | Purpose |
|-----------|---------|
| `064_update_song_metadata_rpc.sql` | RPC functions for metadata updates |
| `068_ensure_catalog_setlist_rpc_standalone.sql` | Catalog setlist support (columns, RPC, triggers) |
| `069_fix_rls_remove_is_active.sql` | Fix RLS policies removing is_active check |
| `070_fix_catalog_deletion_cascade.sql` | Allow Catalog deletion on band cascade |
| `078_drop_old_update_song_metadata_overloads.sql` | Drop old function overloads, keep single 8-parameter version |

## Support & Documentation

### User Support
- **In-App Guidance:** Contextual help and onboarding
- **Error Handling:** Graceful error messages with snackbar feedback
- **Responsive Design:** Works across all device sizes

### Developer Resources
- **Dart/Flutter:** Full type safety throughout application
- **Feature Modules:** Self-contained feature directories
- **Repository Pattern:** Clean data access abstraction
- **Database Migrations:** Version-controlled schema changes in `supabase/migrations/`

## Environment Setup

### Required Environment Variables (.env file)
```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here
```

**IMPORTANT:** The `.env` file must be in the project root and is loaded at runtime. It's included in `pubspec.yaml` assets.

### Supabase Dashboard Configuration Checklist
- [ ] **URL Configuration:** Add `bandroadie://login-callback/` to Redirect URLs
- [ ] **URL Configuration:** Add `https://bandroadie.com/auth/confirm` to Redirect URLs
- [ ] **Email Templates → Confirm signup:** Use `{{ .ConfirmationURL }}` in link href
- [ ] **Email Templates → Magic Link:** Use `{{ .ConfirmationURL }}` in link href

### Build Requirements
- Flutter SDK ^3.10.4
- Dart SDK ^3.10.4
- Xcode (for iOS/macOS)
- Android Studio or Android SDK (for Android)
- CocoaPods (for iOS/macOS dependencies)

---

## Changelog

### February 14, 2026

#### Animated Onboarding Experience (New)
- **Goal:** Replace the static profile completion screen with a premium, cinematic first-time user experience
- **New File:** `lib/features/onboarding/onboarding_screen.dart` (~1550 lines)
- **Phases:**
  1. **Cinematic Splash:** Logo scales 0.85→1.0 with `easeOutBack` bounce, tagline fades in with blur-to-sharp effect, radial rose glow fades to pure black on transition
  2. **3-Step Wizard:** Spring-based card transitions with animated progress dots
     - Step 1: "What should we call you?" (first name only)
     - Step 2: Zip code with shake validation on invalid input
     - Step 3: Birthday — month pills (ALL CAPS, rose outline always, filled when selected) + day pills
  3. **Completion Celebration:** Confetti burst via `confetti` package, logo reappear, "You're all set!" message
- **Design:** Pure black background (`#000000`), rose accent (`#BE123C`), DM Sans font, equal-width Back/Next buttons, "Skip for now" in white on every step
- **Data:** Upserts first_name, zip, birthday to Supabase `users` table
- **Routing:** "Done" and "Skip for now" both route through `onSkip` callback in `auth_gate.dart`
- **Auth Gate Changes:** `lib/features/auth/auth_gate.dart` now routes to `OnboardingGateScreen` instead of the old `ProfileGateScreen` for first-time users
- **Dependency Added:** `confetti: ^0.8.0` in `pubspec.yaml`

#### Event Editor — Multi-Date UX Simplified
- **Goal:** Make multi-date support for potential gigs more discoverable by removing the hidden "Multiple" toggle
- **Changes:**
  - Removed `_isMultiDate` state variable, `_toggleMultiDate()` method, and `_buildMultipleDatesToggle()` widget
  - When **Potential Gig is ON**, a "+ Add another date" button now appears directly below the primary date picker — no extra toggle needed
  - When **Potential Gig is OFF**, additional dates are automatically cleared
  - Removed `showAddButton` / `onAdd` params from `_buildSingleDatePicker()` (inline + button removed from date rows)
  - All `_isMultiDate` references replaced with `_isPotentialGig`-based or `_additionalDates.isNotEmpty`-based logic
  - "+ Add another date" button uses rose accent border with 0.4 alpha and bold text for visibility
- **File:** `lib/features/events/widgets/event_editor_drawer.dart`

#### Event Title — Removed Auto Title-Case Formatting
- **Goal:** Allow users full control over event title capitalization (acronyms like NAMM, SXSW, DIY FEST)
- **Changes:**
  - Removed `TitleCaseTextFormatter()` input formatter from event name/title field
  - Changed `TextCapitalization.words` to `TextCapitalization.sentences` for standard keyboard behavior
  - Location and city fields remain unchanged (still title-cased)
- **Backward Compatibility:** Existing saved event titles are NOT reformatted — change is forward-only
- **File:** `lib/features/events/widgets/event_editor_drawer.dart`

### January 29, 2026 - Build 30 (v1.0.13+30)

#### In-App Notification UI Removed
- **Goal:** Transition to push-only notification model by removing in-app notification UI elements
- **Removed Components:**
  - Notification bell icon from app header
  - Full notification feed screen (`notifications_screen.dart`)
  - Notification card widget (`notification_card.dart`)
  - Notification navigation service for deep linking
  - All routes and navigation to notification screens
- **Preserved Infrastructure:**
  - Backend notification system (database tables, triggers, Edge Functions)
  - Notification repository for data access
  - Notification controller for state management
  - Notification preferences screen and settings
  - Push notification service infrastructure (not yet initialized)
  - Device token management RPCs
- **Impact:** App now has dormant backend notification system ready for future push notification implementation
- **Code Quality:** App compiles cleanly, `flutter analyze` passes with 0 errors

#### Comprehensive Code Review Conducted
- **Type:** READ-ONLY architecture and safety analysis
- **Scope:** Repository pattern, band isolation, state management, memory management, production readiness
- **Critical Findings:**
  - 🔴 C1: StreamSubscription memory leak risk in AuthStateNotifier
  - 🔴 C2: Band switching does NOT reset all band-scoped state (stale data risk)
  - 🔴 C3: No repository cache invalidation after band switch
  - 🟠 H1-H4: High-priority risks in notification triggers, concurrent edits, PKCE verifier, unbounded caches
- **12 Edge Cases Documented:** Authentication, band switching, concurrent edits, RLS, platform-specific scenarios
- **Guardrails Established:** NON-NEGOTIABLE patterns for database safety, architecture, and code style
- **Production Assessment:** Functional and deployable, but band switching state isolation (C2) is critical bug to fix
- **Documentation:** Full review added to [BAND_ROADIE_DOCUMENTATION.md](BAND_ROADIE_DOCUMENTATION.md#code-review--architecture-analysis-january-29-2026)

#### Database Triggers Created
| Migration File | Purpose |
|----------------|---------|
| `20260128210000_notification_triggers.sql` | Auto-create notification records when gigs, rehearsals, or blockouts are created. Uses `RETURN NEW` pattern (safe - never blocks writes), fires AFTER INSERT only, SECURITY DEFINER for RLS bypass |

### January 14, 2026

#### Keyboard Handling Fixes
- **Setlist Picker Bottom Sheet:** Fixed keyboard covering the text input when creating a new setlist from Catalog. Added `AnimatedPadding` with `viewInsets.bottom` to push the sheet content above the keyboard.
- **Event Editor Drawer:** Fixed keyboard covering Cancel/Update buttons when editing event text fields. Updated `_buildBottomButtons` to accept keyboard height and add it to bottom padding.

#### Recurring Events - "Coming Soon" Status
- **Problem:** Enabling "Make this recurring" when creating rehearsals would block the save action with an error.
- **Root Cause:** Backend database doesn't support recurring events yet, but the UI allowed enabling the feature.
- **Solution:** 
  - Added "Coming Soon" badge (rose accent) next to the recurring toggle
  - Dimmed the toggle label to indicate unavailability
  - Shows friendly snackbar "🎸 Recurring events coming soon! Stay tuned." when toggle is tapped
  - Prevents the toggle from activating

#### Setlists Loading State Fix
- **Problem:** After creating a new setlist, making changes, and exiting, the Setlists screen would get stuck on "Loading setlists" indefinitely.
- **Root Cause:** `SetlistsNotifier.build()` returned `isLoading: true` even when band ID hadn't changed, combined with `ref.invalidate()` usage that triggered rebuilds without new loads.
- **Solution:**
  - Added `_cachedState` to `SetlistsNotifier` to preserve loaded data across rebuilds
  - `build()` now returns cached state when band ID hasn't changed
  - Changed `ref.invalidate(setlistsProvider)` to `ref.read(setlistsProvider.notifier).refresh()` in `setlist_detail_screen.dart`

#### Band Avatar Image Upload - Debug Logging
- **Enhancement:** Added comprehensive debug logging to trace band avatar image picker and upload flow:
  - `[PickImage]` logs for image selection, file validation, state updates
  - `[Upload]` logs for user ID, file name, bytes, and URL
  - `[BandAvatar]` logs for image loading errors (local and network)
  - Added error snackbar when image upload fails

#### Database Migration Created
| Migration File | Purpose |
|----------------|---------|
| `076_tuning_to_text.sql` | Changes `tuning` column from enum to TEXT to support all guitar tunings |

#### Tuning System Restored
- **Problem:** Tuning picker only showed 4 options after enum constraint was discovered.
- **Solution:** 
  - Created migration to change `tuning` column from `tuning_type` enum to `TEXT`
  - Restored all 16+ tuning options in `TuningOption` class
  - Added comprehensive alias mapping in `findTuningByIdOrName()` for 80+ variations
  - Tuning picker now shows full list: Standard, Drop D, Drop C#, Drop C, Drop B, Drop A, Open G, Open D, Open E, Open A, DADGAD, Half Step Down, Full Step Down, Baritone, 7-String Standard, 7-String Drop A

### January 6, 2026

#### Web Branding Update
- Updated browser tab title from "bandroadie_fresh" to "BandRoadie"
- Updated `web/manifest.json` with proper app name and theme colors (rose `#F43F5E`, dark background `#1A1A1A`)
- Updated `web/index.html` meta description and apple-mobile-web-app-title
- Replaced favicon with BandRoadie logo

#### Setlist Detail Screen
- Added "Delete Setlist" text button at bottom of setlist detail screen (non-Catalog only)
- Delete shows confirmation dialog explaining songs remain in Catalog
- Added `deleteSetlist()` method to `SetlistDetailNotifier` controller

#### Rehearsal Card UI Fix
- Fixed setlist badge width in rehearsal card to only be as wide as the setlist name (removed `Flexible` wrapper and `minWidth` constraint)

#### Database Migrations Created

| Migration File | Purpose |
|----------------|---------|
| `068_ensure_catalog_setlist_rpc_standalone.sql` | Standalone migration for Catalog support - adds `setlist_type` and `is_catalog` columns, creates `ensure_catalog_setlist` RPC function, triggers for auto-creation and protection |
| `069_fix_rls_remove_is_active.sql` | Fixes RLS policies by removing `is_active` check from `band_members` (column may not exist in production) |
| `070_fix_catalog_deletion_cascade.sql` | Fixes Catalog deletion trigger to allow cascade when parent band is deleted |

#### Edge Function Fix (send-bug-report)
- Fixed CORS issue blocking bug report submissions from web
- Added `x-client-info` and `apikey` to `Access-Control-Allow-Headers`
- Added CORS headers to all response returns (not just OPTIONS preflight)
- Deployed updated function to Supabase

#### Known Issues Identified
- **RLS `is_active` column:** Production database may not have `is_active` column on `band_members` table, causing RLS policies to fail. Run migration `069_fix_rls_remove_is_active.sql` to fix.
- **Catalog columns:** Production database may be missing `setlist_type` and `is_catalog` columns. Run migration `068_ensure_catalog_setlist_rpc_standalone.sql` to add them.

#### Pending Migrations to Run in Supabase SQL Editor
1. `068_ensure_catalog_setlist_rpc_standalone.sql` - Catalog setlist support
2. `069_fix_rls_remove_is_active.sql` - Fix RLS policies
3. `070_fix_catalog_deletion_cascade.sql` - Fix band deletion cascade

---

## Code Review & Architecture Analysis (January 29, 2026)

### Version at Review
- **Version:** 1.0.13+30 (Build 30)
- **Review Type:** Comprehensive READ-ONLY analysis
- **Scope:** Architecture, data safety, state management, memory management, production readiness

### ✅ What Is Solid

#### Repository Pattern & Data Layer
- Clean separation between data access (repositories) and state management (controllers)
- Consistent error handling with custom error types (`SetlistQueryError`, `NoBandSelectedError`)
- Strong type safety - all repositories return typed models, not raw JSON

#### Band Isolation Architecture
- Every operation requires `bandId` - enforced at repository level
- RLS policies mirror application logic (band_members join pattern)
- Catalog setlist properly scoped per-band with `is_catalog` flag
- Active band persistence via SharedPreferences with graceful fallbacks

#### Database Trigger Safety
- All notification triggers use `RETURN NEW` pattern (never blocks writes)
- Fire `AFTER INSERT` only (not UPDATE/DELETE)
- Use `SECURITY DEFINER` appropriately for RLS bypass where needed
- Consistent date formatting across triggers

#### State Management (Riverpod 3.x)
- Modern `Notifier` pattern (not deprecated StateNotifier)
- Provider disposal hooks properly used for cleanup
- Appropriate use of `ref.invalidate()` for cache busting

#### Resource Cleanup
- Controllers cancel debounce timers in `dispose()`
- Animation controllers properly disposed
- Text controllers and focus nodes cleaned up
- `ref.onDispose()` used for StreamSubscription cancellation

### ⚠️ Critical Risks Identified

#### 🔴 C1: StreamSubscription Memory Leak in AuthStateNotifier
- **File:** `lib/features/auth/auth_state_provider.dart` (lines 51-70)
- **Issue:** `_authSubscription` created in `build()` method
- **Risk:** If notifier is rebuilt without disposal, old subscription leaks
- **Impact:** Memory growth on iOS/Android after hours of use, battery drain
- **Why Critical:** Auth events fire frequently (token refresh every 60min)
- **Test:** Open app → Background → Foreground 20x → Check memory
- **Mitigation:** Verify `ref.onDispose()` always cancels subscription

#### 🔴 C2: Band Switching Does NOT Reset All Band-Scoped State
- **File:** `lib/features/bands/active_band_controller.dart` (lines 318-325)
- **Critical Comment:** "When switching bands, all band-scoped data should be reset"
- **Issue:** Comment says it happens, but NO code triggers invalidation
- **Risk:** Stale data from previous band visible after switch
- **Missing:** No `ref.invalidate()` calls for:
  - `setlistsProvider`
  - `gigsProvider`
  - `rehearsalsProvider`
  - `membersProvider`
  - Notification feed
- **Impact:** User sees Band A's setlists when Band B is active
- **Test:** Create event in Band A → Switch to Band B → Check if Band A's events still visible

#### 🔴 C3: No Repository Invalidation After Band Switch
- **Files:** All `*_repository.dart` files with cache
- **Issue:** Repositories have in-memory caches keyed by bandId, but no global invalidation
- **Risk:** After band switch, cached data from previous band may persist if bandId lookup fails
- **Missing:** No listener in repositories for `activeBandProvider` changes

### ⚠️ High Priority Risks

#### 🟠 H1: Notification Triggers Have No Error Recovery
- **File:** `supabase/migrations/20260128210000_notification_triggers.sql`
- **Issue:** Triggers use `EXCEPTION WHEN OTHERS THEN NULL;` pattern (silent failure)
- **Risk:** If notification creation fails, no audit trail or retry mechanism
- **Impact:** Users miss critical notifications (gig invites, rehearsal changes)
- **Recommendation:** Log to `notification_errors` table for debugging

#### 🟠 H2: Race Condition in Concurrent Setlist Edits
- **File:** `lib/features/setlists/setlist_repository.dart`
- **Issue:** No optimistic locking or version field on `setlist_songs.position`
- **Risk:** Two users reorder songs simultaneously → last write wins, positions corrupt
- **Impact:** Song order shuffled, duplicate positions possible
- **Test:** User A drags song to position 3 → User B drags different song to position 3 → Both save

#### 🟠 H3: PKCE Verifier Lost on App Restart
- **File:** `lib/app/services/deep_link_service.dart` (lines 147-150)
- **Comment:** "This usually means the code verifier was lost"
- **Risk:** User clicks magic link → App restarts → Auth fails with cryptic error
- **Impact:** Login broken for cold-start users, requires re-sending magic link
- **Root Cause:** PKCE verifier stored in memory, not persisted

#### 🟠 H4: Repositories Have No Max Cache Size
- **Files:** `lib/features/events/events_repository.dart`, `lib/features/setlists/setlist_repository.dart`
- **Issue:** Cache grows unbounded (`Map<String, _CacheEntry>`)
- **Risk:** User in 20 bands viewing 12 months of events → 240 cache entries
- **Impact:** Memory pressure on iOS, app killed in background

### 🧪 Critical Edge Cases to Test

#### Authentication & Session
1. **PKCE Verifier Loss:** Start login → Close app → Click magic link → App cold-starts
2. **Concurrent Logins:** Login on Device A → Login on Device B → Check Device A
3. **Token Expiry Mid-Operation:** Open app → Wait 61 minutes → Create rehearsal

#### Band Switching
4. **Band Switch During Active Edit:** Open event editor → Switch bands → Save event
5. **Band Switch with Stale Cache:** Load Band A's setlists → Switch to Band B → Pull-to-refresh
6. **Switching to Band with Same-Named Setlist:** Both bands have "Rock Covers" setlist

#### Concurrent Edits
7. **Simultaneous Song Reorder:** Device A reorders songs → Device B reorders same setlist → Both save
8. **Notification Preference Toggle Race:** Toggle "Gigs Enabled" on iPhone → Simultaneously toggle on iPad

#### Notification Triggers
9. **Trigger Exception During Event Creation:** Create gig → Notification trigger fails
10. **Notification Trigger Creates Duplicate:** Create recurring rehearsal (10 instances)

#### RLS & Data Access
11. **User Removed from Band Mid-Session:** User A opens Band X → Admin removes User A → User A tries to edit setlist
12. **Legacy Songs with NULL band_id:** Update BPM of legacy song → Uses `update_song_metadata` RPC

### 🧱 Guardrails to Keep (NON-NEGOTIABLE)

#### Database Safety
- ✅ **Triggers always `RETURN NEW`** - Never block writes
- ✅ **Triggers only `AFTER INSERT`** - No UPDATE/DELETE side effects
- ✅ **RLS uses `band_members` join** - Never trust `auth.uid()` alone
- ✅ **SECURITY DEFINER only for legacy data** - RLS bypass must be documented

#### Application Architecture
- ✅ **Repositories never depend on notification system** - Already preserved
- ✅ **Every query requires bandId** - `NoBandSelectedError` pattern
- ✅ **Catalog is per-band** - Never global
- ✅ **Comment: "Switching bands MUST reset all band-scoped state"** - MUST BE ENFORCED

#### Code Patterns
- ✅ **Notifier pattern** - Not deprecated StateNotifier
- ✅ **ref.onDispose() for cleanup** - Prevents memory leaks
- ✅ **User-friendly error messages** - No raw SQL errors to users
- ✅ **Brand voice in feedback** - 🎸 emoji + roadie humor

### 🧭 Recommended Improvements

#### Top 3 Priorities Before Next Major Release
1. **Fix C2:** Implement band switching state reset (add `ref.invalidate()` calls to `selectBand()`)
2. **Fix C1:** Verify StreamSubscription cleanup in AuthStateNotifier (test with memory profiler)
3. **Fix H2:** Add optimistic locking to setlist song reordering (prevent corruption)

#### Architecture Enhancements
- **Global State Reset on Band Switch:** Add `BandSwitchCoordinator` that calls `ref.invalidate()` for all band-scoped providers
- **Repository Base Class:** Extract common patterns (caching, error handling, bandId validation)
- **Cache with LRU Eviction:** Limit cache size (e.g., 50 entries per repository)

#### Data Safety
- **Optimistic Locking for Setlist Songs:** Add `version` field to `setlist_songs` table
- **Notification Trigger Error Logging:** Create `notification_errors` table for failed executions
- **PKCE Verifier Persistence:** Store verifier in secure storage (Keychain/Keystore)

#### User Experience
- **Band Switch Confirmation:** Show bottom sheet: "Switch to Band X? Unsaved changes will be lost."
- **Expired Invitation Handling:** Check `expires_at` before showing "Join Band" UI
- **Session Expiry Warning:** 5 minutes before token expires, show warning to save work

### Production Readiness Assessment

| Category | Status | Notes |
|----------|--------|-------|
| **Architecture** | 🟢 Solid | Feature-first structure, clean separation |
| **Data Safety** | 🟡 Good | RLS + triggers safe, but no optimistic locking |
| **State Management** | 🟡 Good | Riverpod 3.x used correctly, band switching incomplete |
| **Memory Management** | 🟠 Needs Work | StreamSubscriptions cleaned up, but unbounded caches |
| **Error Handling** | 🟢 Solid | Comprehensive try-catch, typed exceptions |
| **Production Ready** | 🟠 Mostly | Functional, but critical band switching bug exists |

**Overall Assessment:** Application is functional and deployable, but the band switching state isolation issue (C2) is a critical bug that should be fixed before promoting multi-band usage. Memory management concerns (C1, H4) should be addressed for long-term stability.

---

This comprehensive documentation provides everything needed to understand, develop, and maintain the BandRoadie application. The app represents a complete band management solution with modern cross-platform technologies and user-centered design.