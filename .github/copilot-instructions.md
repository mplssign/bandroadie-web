# Band Roadie - AI Coding Instructions

## Project Overview
Band Roadie is a cross-platform Flutter app (iOS, Android, macOS, Web) for band management—rehearsals, gigs, setlists, and member coordination. Backend is Supabase (PostgreSQL + Auth + Edge Functions).

## Architecture

### Feature-First Structure
Code is organized by feature in `lib/features/`, not by layer:
```
lib/features/setlists/
├── models/              # Data models (SetlistSong, Setlist)
├── services/            # Pure business logic (parsers, validators)
├── widgets/             # UI components specific to this feature
├── tuning/              # Domain helpers (tuning_helpers.dart)
├── setlist_repository.dart      # Supabase data access
├── setlist_detail_controller.dart  # Riverpod state management
└── setlist_detail_screen.dart   # Screen widget
```

### State Management Pattern (Riverpod)
Use `Notifier` + `NotifierProvider` (not deprecated StateNotifier):
```dart
class SetlistDetailNotifier extends Notifier<SetlistDetailState> {
  @override
  SetlistDetailState build() => const SetlistDetailState();
  // Methods that mutate state...
}

final setlistDetailProvider = NotifierProvider<SetlistDetailNotifier, SetlistDetailState>(
  SetlistDetailNotifier.new,
);
```
Access via `ref.read(provider.notifier).methodName()` for actions, `ref.watch(provider)` for reactive UI.

### Band Isolation
All data is scoped to the active band via `activeBandProvider`. When switching bands, all band-scoped providers must refresh. Check `active_band_controller.dart` for the pattern.

### Repository Pattern
Repositories handle Supabase queries and return typed models. Example: `SetlistRepository.fetchSongsForSetlist()`. Error handling uses `SetlistQueryError` class with user-friendly messages.

## Key Conventions

### Theme & Design Tokens
- **Dark mode only**, rose accent `#F43F5E`
- Import from `lib/app/theme/design_tokens.dart` for spacing, colors, typography
- Use `Spacing.pagePadding`, `AppColors.primary`, `AppTypography.heading2`
- Card radius: 16px, button radius: 8px, minimum touch target: 48px

### Constants
Use `lib/app/constants/app_constants.dart` for shared values:
```dart
const String kCatalogSetlistName = 'Catalog';
bool isCatalogName(String name) => ...  // Check if setlist is the Catalog
```

### Inline Editing Pattern
Song cards use tap-to-edit for BPM, Duration, Tuning. Save on blur, show saving indicator, broadcast updates via `songUpdateBroadcasterProvider` so all open setlists stay in sync.

### Drag & Reorder
`ReorderableSongCard` restricts drag to grip icon only (left 36px). Touching elsewhere scrolls normally.

### RLS Bypass for Legacy Data
Songs with `NULL band_id` require RPC functions (`update_song_metadata`, `clear_song_metadata`) that use `SECURITY DEFINER` to bypass Row Level Security.

## Supabase Integration

### Authentication
Magic link with PKCE flow. Key files:
- `lib/features/auth/login_screen.dart` - `signInWithOtp()`
- `lib/features/auth/auth_confirm_screen.dart` - Web token verification with `verifyOTP()`
- Deep link scheme: `bandroadie://login-callback/`

### Database Queries
Use `supabase.from('table').select()` with explicit column lists. Join syntax:
```dart
.select('song_id, position, songs!inner(id, title, artist, bpm)')
```

### Edge Functions
Located in `supabase/functions/`. Used for external API integrations with token caching.

### Database Schema (Key Tables)
```sql
-- Core Tables
users              -- id, email, name, phone, birthday
bands              -- id, name, image_url, created_by
band_members       -- id, band_id, user_id, role
band_invitations   -- id, band_id, email, token, expires_at

-- Event Management
gigs               -- id, band_id, name, venue, date, is_potential, setlist_id
rehearsals         -- id, band_id, location, start_time, end_time
gig_responses      -- id, gig_id, user_id, response (yes/no/maybe)

-- Setlist Management
setlists           -- id, band_id, name (Catalog is special per-band)
songs              -- id, band_id, title, artist, bpm, duration_seconds, tuning
setlist_songs      -- id, setlist_id, song_id, position (ordering)
```

### RPC Functions
Use `SECURITY DEFINER` functions for operations that bypass RLS:
```dart
await supabase.rpc('update_song_metadata', params: {
  'p_song_id': songId,
  'p_band_id': bandId,
  'p_bpm': 120,
});
```

## Development Commands

```bash
# Run on platforms
flutter run -d macos
flutter run -d chrome
flutter run -d ios

# Clean rebuild (required after pubspec changes)
flutter clean && flutter pub get

# Build and deploy web
flutter build web --release
cd build/web && vercel --prod

# Analyze code
flutter analyze
```

## Platform-Specific Notes

### macOS
Requires network entitlements in `macos/Runner/*.entitlements`:
```xml
<key>com.apple.security.network.client</key>
<true/>
```

### Android
Uses Kotlin DSL (`build.gradle.kts`). Deep links configured in `AndroidManifest.xml`.

### Web
Deployed to Vercel at `bandroadie.com`. Auth confirmation handled via `/auth/confirm` route.

## File Naming
- Screens: `*_screen.dart`
- Widgets: `*_card.dart`, `*_overlay.dart`, `*_bottom_sheet.dart`
- Controllers: `*_controller.dart`
- Repositories: `*_repository.dart`
- Models: Singular noun (e.g., `setlist_song.dart`)

## Testing Conventions

Testing infrastructure exists but coverage is minimal. When adding tests:
- Place tests in `test/` mirroring `lib/` structure
- Use `flutter_test` for widget tests, `golden_toolkit` for visual regression
- Pure services (e.g., `bulk_song_parser.dart`) are good candidates for unit tests
- Run tests: `flutter test`

## Brand Voice & User Messages

User-facing messages use friendly "roadie" humor. Examples from the codebase:

```dart
// Duplicate song detection
'🎸 "$songTitle" is already in this setlist — great minds rehearse alike!'

// Catalog awareness
'🎸 "$songTitle" already exists in the Catalog. (The Catalog remembers everything… like a drummer.)'

// Enrichment feedback
'🎸 "$songTitle" already exists in the Catalog — updated with new info!'
```

**Guidelines:**
- Use 🎸 emoji for song-related feedback
- Keep messages short and playful, not corporate
- Reference music/band culture (drummers, rehearsals, roadies)
- Error messages should still be clear and actionable

Use `lib/shared/utils/snackbar_helper.dart` for consistent snackbar display: `showAppSnackBar()`, `showSuccessSnackBar()`, `showErrorSnackBar()`.

## Documentation
Refer to `BAND_ROADIE_DOCUMENTATION.md` for complete feature specs, database schema, troubleshooting guides, and version history.
