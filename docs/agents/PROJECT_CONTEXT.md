# BandRoadie — Project Context

This document is the authoritative project context for all agents. Read it in full before producing any Feature Input, Architect prompt, or gate review.

---

## What BandRoadie Is

BandRoadie is a cross-platform band management app for iOS, Android, macOS, and Web. It helps bands coordinate rehearsals, gigs, setlists, calendars, and members — built by a musician, with no ads and no data selling.

- **Live web app:** https://bandroadie.com
- **Version:** 1.4.0 (March 2026)
- **Status:** Active production app with 100+ bands

---

## Tech Stack

| Layer              | Technology                                                 |
| ------------------ | ---------------------------------------------------------- |
| Frontend           | Flutter 3.x / Dart 3.10.4                                  |
| State management   | Riverpod (`Notifier` + `NotifierProvider` pattern)         |
| Backend            | Supabase (PostgreSQL + Auth + Edge Functions + Storage)    |
| Auth               | Magic link / PKCE flow                                     |
| Push notifications | Firebase Cloud Messaging (FCM) via Supabase Edge Functions |
| Email              | Resend (transactional)                                     |
| Web deployment     | Vercel                                                     |
| Edge Functions     | Deno (TypeScript)                                          |

---

## Hosting and Domain Architecture

**Critical — read before any feature touching routing, URLs, or deployment.**

BandRoadie is a **single Vercel deployment** serving both the marketing site and the web app from the same Flutter build.

| Surface           | Hostname                                           | Entry point                             |
| ----------------- | -------------------------------------------------- | --------------------------------------- |
| Marketing site    | `bandroadie.com`                                   | `LandingPage` → `lib/features/landing/` |
| Web app           | Any non-marketing host (e.g. `app.bandroadie.com`) | `AuthGate`                              |
| Privacy policy    | `bandroadie.com/privacy`                           | Flutter route → `PrivacyPolicyScreen`   |
| Auth confirmation | `bandroadie.com/auth/confirm`                      | Flutter route → `AuthConfirmScreen`     |

Host detection happens in `lib/main.dart` via `_isMarketingHost()`. The `vercel.json` catch-all rewrite sends all requests to `index.html`; Flutter handles routing from there.

**Files that affect BOTH surfaces — always flag in the Architect plan:**

- `lib/main.dart` (routing, host detection, initialization)
- `vercel.json` (rewrites, headers)
- `web/index.html`

**Files scoped to marketing only:**

- `lib/features/landing/` (all landing page widgets)
- `web/privacy.html`
- `web/support.html`

**Files scoped to app only:**

- `lib/features/auth/`, `bands/`, `calendar/`, `gigs/`, `members/`, `profile/`, `rehearsals/`, `setlists/`, `home/`, `settings/`, `notifications/`

---

## App Initialization Order

**Non-negotiable. Never reorder without a logged decision in `docs/reference/general/AI_DECISIONS.md`.**

```
1. WidgetsFlutterBinding.ensureInitialized()
2. URL strategy (web only)
3. Portrait orientation lock
4. AppVersionService.init()
5. validateSupabaseConfig()     ← validates --dart-define values
6. Supabase.initialize()
7. Firebase.initializeApp()     ← iOS/Android only, skipped on web
8. DeepLinkService setup
9. runApp()
```

---

## Configuration Model

Config is **compile-time injection only** via `--dart-define`. No runtime `.env`, no `flutter_dotenv`.

| Key                 | Description                              |
| ------------------- | ---------------------------------------- |
| `SUPABASE_URL`      | Supabase project URL                     |
| `SUPABASE_ANON_KEY` | Supabase anon key — never `service_role` |

Production web builds are produced locally by `tools/deploy_web.sh`, which reads credentials from a local `.env` file and injects them as `--dart-define` flags. **Vercel does not run the build.** Do not set Supabase credentials as Vercel environment variables.

---

## Platform Differences

| Area       | Native (iOS / macOS / Android)                     | Web                                                                          |
| ---------- | -------------------------------------------------- | ---------------------------------------------------------------------------- |
| Auth flow  | PKCE                                               | PKCE (migrated from implicit — April 2026, see AI_DECISIONS.md DECISION-001) |
| Firebase   | Initialized                                        | Not initialized                                                              |
| Deep links | `bandroadie://login-callback/` via DeepLinkService | Not applicable                                                               |
| Config     | `--dart-define` only                               | `--dart-define` only                                                         |

---

## Codebase Structure

```
lib/
├── main.dart                  # Entry point, init order, routing
├── app/
│   ├── router/                # app_router.dart (currently empty — routing is in main.dart)
│   ├── theme/                 # Design tokens: Rose accent #BE123C / #F43F5E
│   ├── models/                # Shared data models
│   └── services/              # AppVersionService, supabase_client
├── features/                  # Feature-first structure (one folder per feature)
│   ├── auth/                  # Magic link login, auth confirm, auth gate
│   ├── bands/                 # Band creation, management, RBAC
│   ├── calendar/              # Calendar view, event aggregation
│   ├── gigs/                  # Gig CRUD, availability, setlist assignment
│   ├── home/                  # Dashboard, bottom nav
│   ├── landing/               # Marketing landing page (web only)
│   ├── members/               # Member directory, invitations
│   ├── notifications/         # Push notification preferences, FCM token management
│   ├── profile/               # User profile, roles
│   ├── rehearsals/            # Rehearsal scheduling
│   ├── setlists/              # Setlists, song catalog, drag-and-drop, BPM/duration/tuning
│   └── settings/              # App settings, data backup/export
├── components/ui/             # Shared base UI components
└── shared/                    # Shared utilities
supabase/
├── functions/                 # Edge Functions (Deno/TypeScript)
└── migrations/                # PostgreSQL migrations
```

---

## Database Tables

### Core Identity

| Table                     | Description                                                                                                       |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `users`                   | Profiles (first_name, last_name, phone, address, city, zip, birthday, roles[], profile_completed, calendar_token) |
| `profiles`                | Auth-linked profile (full_name, avatar_url, email, phone, bio) — legacy/supplementary                             |
| `bands`                   | Band entities (name, image_url, created_by, avatar_color, timezone)                                               |
| `band_members`            | Membership with role ENUM: `admin`, `member`, `contributor`; status: invited/active/inactive/removed              |
| `band_invitations`        | Pending invites (email, invited_by, token, status, expires_at)                                                    |
| `user_band_roles`         | Per-band instrument/musical roles for a user (separate from RBAC role)                                            |
| `contributor_permissions` | Fine-grained permissions for `contributor` role                                                                   |
| `feedback`                | In-app bug reports and feature requests (type: bug/feature, description, status)                                  |
| `app_config`              | Global key-value config table                                                                                     |

### Events

| Table             | Description                                                                                                                                                                   |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gigs`            | Gigs (band_id, name, date, start/end time, location, is_potential, setlist_id, notes, gig_pay, load_in_time, required_member_ids[], venue_id)                                 |
| `gig_dates`       | Multi-date support for gigs (gig_id, date)                                                                                                                                    |
| `gig_responses`   | RSVP per member (gig_id, user_id, response: yes/no, gig_date_id)                                                                                                              |
| `rehearsals`      | Rehearsal sessions (band_id, date, start/end time, location, notes, setlist_id, is_recurring, recurrence_frequency, recurrence_days[], recurrence_until, parent_rehearsal_id) |
| `rehearsal_dates` | Multi-date support for rehearsals (rehearsal_id, date)                                                                                                                        |
| `block_dates`     | Member block-out/unavailability dates (user_id, band_id, date, reason)                                                                                                        |

### Setlists & Songs

| Table                   | Description                                                                                                           |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `setlists`              | Setlists per band (name, setlist_type: regular/catalog, is_catalog, total_duration, position)                         |
| `songs`                 | Song catalog (title, artist, bpm, duration_seconds, tuning, notes, lyrics, album_artwork, spotify_id, musicbrainz_id) |
| `setlist_songs`         | Ordered items (setlist_id, song_id, position, bpm/duration/tuning overrides, item_type: song/special)                 |
| `setlist_special_items` | Set breaks and pauses (type: set_break/pause, duration, purposes[])                                                   |
| `song_notes`            | Per-song, per-band notes (song_id, band_id, content, created_by)                                                      |

### Venues & Contacts

| Table            | Description                                                          |
| ---------------- | -------------------------------------------------------------------- |
| `venues`         | Venue directory (band_id, name, address, city, state, phone, notes)  |
| `venue_contacts` | Venue contact persons (venue_id, band_id, name, title, phone, email) |
| `contacts`       | General band contacts — agents, promoters, etc.                      |

### Notifications

| Table                      | Description                                                                                                                                                      |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `notifications`            | Delivery queue (recipient_user_id, actor_user_id, band_id, type, title, body, metadata JSONB, read_at, sent_at)                                                  |
| `notification_preferences` | Per-user toggles — two generations of columns coexist (legacy: `gig_updates`, `rehearsal_updates`, etc.; current: `notifications_enabled`, `gigs_enabled`, etc.) |
| `device_tokens`            | FCM tokens (user_id, fcm_token unique, platform: ios/android/web/macos, device_name, last_seen)                                                                  |

### Calendar & Misc

| Table                         | Description                                                                                 |
| ----------------------------- | ------------------------------------------------------------------------------------------- |
| `band_calendar_subscriptions` | iCal feed subscriptions (user_id, band_id, token unique, include_gigs/rehearsals/blockouts) |
| `print_templates`             | Setlist print layouts per band (font sizes, column count, paper size, display toggles)      |
| `band_access_events`          | Access tracking (band_id, user_id, accessed_at)                                             |

---

## Role-Based Access Control (RBAC)

Three roles enforced at database level (PostgreSQL ENUM `band_role_type`):

| Role          | Capabilities                                                                |
| ------------- | --------------------------------------------------------------------------- |
| `admin`       | Full CRUD, delete band, remove members, manage roles                        |
| `member`      | Full CRUD for gigs/rehearsals/setlists — cannot delete band or change roles |
| `contributor` | Configurable via `contributor_permissions` table                            |

- RLS policies enforce roles — never bypass from the client
- Destructive RPCs (`delete_band`, `remove_band_member`, `update_member_role`) use `SECURITY DEFINER` with `SET search_path = public` and `FOR UPDATE` locking
- **Never create RLS policies that query the table they protect** — causes infinite recursion (PostgreSQL error 42P17)

---

## Authentication Architecture

- Passwordless magic link via Supabase Auth
- Web: PKCE flow (migrated from implicit — April 2026, DECISION-001), session in `localStorage`
- Native: PKCE flow, deep link `bandroadie://login-callback/`, session in secure storage
- `AuthConfirmScreen` waits up to 5 seconds for auth state provider to sync before navigating (race condition fix — do not remove)
- Supabase redirect URLs: `https://app.bandroadie.com/auth/confirm` and `bandroadie://login-callback/`

---

## Push Notification Architecture

- Notifications trigger on **CREATE only** — never on edit or delete
- Never notify the actor (person who performed the action)
- Notifications are non-blocking — never gate core app functionality
- Flow: DB INSERT → trigger creates notification record → webhook → Supabase Edge Function → FCM HTTP v1 API → device
- Firebase project: `bandroadie-65b18`
- Web push: **not yet implemented**
- macOS push: **not yet implemented**

---

## Setlist and Song Features

- **Catalog** is a special setlist that is the single source of truth for the band's song library
- Songs have: title, artist, BPM (20–300, editable), duration (mm:ss, editable), tuning (picker), spotify_id
- BPM is fetched from Spotify via Edge Function when songs are added via Song Lookup — non-blocking, falls back gracefully
- Drag-and-drop reordering uses position stored server-side via RPC
- Legacy songs with `NULL band_id` use `SECURITY DEFINER` RPCs (`update_song_metadata`, `clear_song_metadata`) to bypass RLS
- Share Setlist exports plain text via native share sheet

---

## Data Backup / Export

- Admin-only export in current production code (expansion to all members is a planned feature)
- Exports as versioned JSON (schema v1): band, members, songs, setlists, gigs, rehearsals, block-out dates
- Excludes: `device_tokens`, `notifications`, `band_calendar_subscriptions`
- File: `lib/features/settings/data_backup_service.dart`
- Import/restore is also supported (admin only)

---

## Edge Functions

Located in `supabase/functions/`. All 10 deployed functions:

| Function                 | verify_jwt | Purpose                                                      |
| ------------------------ | :--------: | ------------------------------------------------------------ |
| `spotify_search`         |     ✅     | Spotify track search with token caching                      |
| `spotify_audio_features` |     ✅     | Fetch BPM/tempo for a Spotify track ID                       |
| `musicbrainz_search`     |     ✅     | Fallback song search via MusicBrainz                         |
| `send-band-invite`       |     ✅     | Send band invitation email via Resend                        |
| `send-bug-report`        |     ✅     | Send in-app bug/feature report email via Resend              |
| `auth-confirm`           |     ✅     | PKCE token exchange handler                                  |
| `accept-invite`          |     ✅     | Process invite acceptance — validates token, adds member     |
| `acousticbrainz_bpm`     |     ✅     | ⚠️ DEAD — AcousticBrainz API shut down Nov 2022              |
| `send-push`              |     ❌     | FCM HTTP v1 push delivery (current production push delivery) |
| `calendar-feed`          |     ❌     | iCal feed — public URL auth via token param                  |

Functions with `verify_jwt: false` use either service role key (notification delivery) or token param (calendar feed), not JWT.

---

## Deployment

### Web

```bash
./tools/deploy_web.sh          # production deploy (reads local .env for --dart-define)
./tools/deploy_web.sh --preview  # preview URL
```

### Supabase

```bash
supabase db push                          # Apply migrations
supabase functions deploy <name>         # Deploy edge functions
```

Post-deploy checklist: incognito load, PWA install, auth flow (magic link), setlist reorder, bulk entry, RPC integrity check.

---

## Known Issues and Audit Findings

These are documented issues the Architect should be aware of — solutions must not worsen them.

**Critical:**

- Band switching does not fully reset band-scoped state (`ref.invalidate()` not called in `selectBand()`) — data from previous band can bleed through
- Silent error swallowing in repositories (`catch (e) { return []; }`) — user sees empty state instead of error
- Zero meaningful test coverage — regressions go undetected

**Architecture debt:**

- Routing logic lives in `main.dart` (not in `app_router.dart` which is empty) — do not add more routing logic to main.dart without Architect review
- `setlist_repository.dart` is 4,027 lines — avoid adding to it; isolate changes
- `setlist_detail_screen.dart` is 2,788 lines — same caution
- Mixed migration naming formats in `supabase/migrations/` — use timestamp format for all new migrations

**Do not:**

- Add new routing logic to `main.dart` without flagging it
- Copy the `catch (e) { return []; }` pattern
- Add new global color definitions — use `AppColors` from `design_tokens.dart`

---

## Brand Voice

Error messages and UI copy use a friendly, musician-aware tone with 🎸 emoji where appropriate.

Examples:

- `"🎸 Couldn't fetch BPM — the tempo gods were busy."`
- `"🎸 BPM not available for this track."`

---

## Key File Locations

| What                        | Where                                                       |
| --------------------------- | ----------------------------------------------------------- |
| App entry point + routing   | `lib/main.dart`                                             |
| Auth flow                   | `lib/features/auth/`                                        |
| Landing page                | `lib/features/landing/`                                     |
| Setlist logic               | `lib/features/setlists/`                                    |
| Data backup                 | `lib/features/settings/data_backup_service.dart`            |
| Design tokens               | `lib/app/theme/design_tokens.dart`                          |
| Push service                | `lib/features/notifications/push_notification_service.dart` |
| Supabase client             | `lib/app/services/supabase_client.dart`                     |
| Migrations                  | `supabase/migrations/`                                      |
| Edge Functions              | `supabase/functions/`                                       |
| Agent docs                  | `docs/agents/`                                              |
| Architectural decisions log | `docs/reference/general/AI_DECISIONS.md`                    |
| Runtime config reference    | `docs/reference/general/RUNTIME_CONFIG.md`                  |
