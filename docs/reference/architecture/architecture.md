# BandRoadie — Architecture Reference

*Last verified: 2026-04-14. For live database schema see `database_schema.md`. For Edge Functions see `supabase_functions.md`.*

---

## Overview

BandRoadie is a cross-platform band management app targeting iOS, Android, macOS, and Web from a single Flutter codebase. The backend is Supabase (PostgreSQL + Auth + Edge Functions + Storage). There are no separate native modules — everything is Flutter.

**Stack:**

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter 3.x / Dart 3.10.4 |
| State management | Riverpod (`Notifier` + `NotifierProvider`) |
| Backend | Supabase (PostgreSQL + Auth + Edge Functions) |
| Auth | Passwordless magic link, PKCE flow on all platforms |
| Push notifications | Firebase Cloud Messaging (FCM) HTTP v1 API |
| Email | Resend (transactional) |
| Web deployment | Vercel |
| Edge Functions | Deno (TypeScript) |

---

## Hosting and Domain Architecture

BandRoadie is a **single Vercel deployment** serving both the marketing site and the web app from the same Flutter build output.

| Surface | Hostname | Entry point |
|---------|----------|-------------|
| Marketing site | `bandroadie.com` | `LandingPage` → `lib/features/landing/` |
| Web app | `app.bandroadie.com` | `AuthGate` |
| Privacy policy | `bandroadie.com/privacy` | Flutter route → `PrivacyPolicyScreen` |
| Auth confirmation | `bandroadie.com/auth/confirm` | Flutter route → `AuthConfirmScreen` |

Both `bandroadie.com` and `app.bandroadie.com` are Vercel aliases pointing to the same deployment. Host detection happens in `lib/main.dart` via `_isMarketingHost()`. The `vercel.json` catch-all rewrite sends all requests to `index.html`; Flutter handles routing from there.

**Files that affect BOTH surfaces — always flag in Architect plans:**
- `lib/main.dart` (routing, host detection, initialization)
- `vercel.json` (rewrites, headers)
- `web/index.html`

---

## App Initialization Order

**Non-negotiable. Never reorder without a logged decision in `docs/reference/general/AI_DECISIONS.md`.**

```
1. WidgetsFlutterBinding.ensureInitialized()
2. URL strategy (web only)
3. Portrait orientation lock
4. AppVersionService.init()
5. validateSupabaseConfig()     ← validates --dart-define values, fails fast if missing
6. Supabase.initialize()
7. Firebase.initializeApp()     ← iOS/Android/macOS only, skipped on web
8. DeepLinkService setup
9. runApp()
```

Entry point: `lib/main.dart`

---

## Configuration Model

Compile-time injection only via `--dart-define`. There is no runtime `.env` loading and no `flutter_dotenv`.

| Key | Description |
|-----|-------------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anon key — never `service_role` |

**Web deployment:** `./tools/deploy_web.sh` reads credentials from a local `.env` file (git-ignored) and passes them as `--dart-define` flags to `flutter build web`. The compiled output is then uploaded to Vercel via CLI. **Vercel does not run the build.** Do not set Supabase credentials as Vercel environment variables.

`tools/build_web.sh` exists in the repo but is called by nothing. Do not reference it.

---

## Platform Differences

| Area | Native (iOS / macOS / Android) | Web |
|------|-------------------------------|-----|
| Config | `--dart-define` only | `--dart-define` only |
| Auth flow | PKCE | PKCE (migrated from implicit — April 2026, DECISION-001) |
| Firebase | Initialized | Not initialized |
| Deep links | `bandroadie://login-callback/` via `DeepLinkService` | Not applicable |

---

## Codebase Structure

```
lib/
├── main.dart                  # Entry point, init order, host detection, routing
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
│   ├── rehearsals/            # Rehearsal scheduling (including recurring)
│   ├── setlists/              # Setlists, song catalog, drag-and-drop, BPM/duration/tuning
│   └── settings/              # App settings, data backup/export
├── components/ui/             # Shared base UI components
└── shared/                    # Shared utilities
supabase/
├── functions/                 # Edge Functions (Deno/TypeScript)
└── migrations/                # PostgreSQL migrations (use timestamp naming for new ones)
```

---

## State Management

Riverpod `Notifier` + `NotifierProvider` pattern throughout. Key conventions:

- Band-scoped data loads when `activeBandProvider` changes
- All data writes go through repositories → Supabase → result returned to notifier
- UI reads state from notifiers via `ref.watch()`
- No UI state used as source of truth for persisted data

**Known pattern debt to avoid copying:**
- `_lastLoadedBandId` + `Future.microtask()` in `build()` — present in `GigNotifier` and `RehearsalNotifier`, causes side effects in build
- `catch (e) { return []; }` silent error swallowing — present in multiple repositories

---

## Authentication Architecture

- Passwordless magic link via Supabase Auth on all platforms
- All platforms use PKCE flow (web migrated from implicit in April 2026 — DECISION-001)
- Web email redirect: `https://app.bandroadie.com/auth/confirm?token_hash=...`
- Native deep link: `bandroadie://login-callback/`
- `AuthConfirmScreen` waits up to 5 seconds for auth state provider to sync before navigating (race condition fix — do not remove)

**Why PKCE on web:** The implicit flow embedded a direct Supabase `/auth/v1/verify?token=...` URL in the email. Email security scanners (e.g., Microsoft Defender Safe Links) pre-fetched these URLs, consuming OTP tokens before users could click. PKCE requires a `code_verifier` stored in the user's `localStorage`, which scanners cannot access.

---

## Role-Based Access Control (RBAC)

Three roles enforced at the database level via PostgreSQL ENUM `band_role_type`:

| Role | Capabilities |
|------|-------------|
| `admin` | Full CRUD, delete band, remove members, manage roles |
| `member` | Full CRUD for gigs/rehearsals/setlists — cannot delete band or change roles |
| `contributor` | Configurable per-band via `contributor_permissions` table |

- RLS policies enforce roles — never bypass from the client
- Destructive RPCs (`delete_band`, `remove_band_member`, `update_member_role`) use `SECURITY DEFINER` with `SET search_path = public` and `FOR UPDATE` locking
- **Never create RLS policies that query the table they protect** — causes infinite recursion (PostgreSQL error 42P17)

---

## Push Notification Architecture

- Notifications trigger on **INSERT only** — never on update or delete
- Never notify the actor (the person who performed the action)
- Notifications are non-blocking — never gate core app functionality
- Firebase project: `bandroadie-65b18`
- Web push: **not implemented**
- macOS push: **not implemented**

**Delivery flow:**
```
DB INSERT → trigger creates notification record
         → pg_cron polls every 5 min → deliver-notifications Edge Function
         → FCM HTTP v1 API (OAuth2 service account)
         → device
```

Two delivery mechanisms exist in the codebase (`send-push` via webhook, `deliver-notifications` via pg_cron). `deliver-notifications` is the current architecture. See `docs/reference/notifications/` for full details.

---

## Routing

All routing currently lives in `lib/main.dart` via `onGenerateRoute` (lines ~131–187). `app/router/app_router.dart` exists but is empty. Do not add new routing logic to `main.dart` without Architect review.

The `_isMarketingHost()` check in `main.dart` determines whether to show the landing page (on `bandroadie.com`) or the app (on `app.bandroadie.com` or native).

---

## Setlist and Song Architecture

- **Catalog** is a special setlist that is the single source of truth for a band's song library
- Songs have: title, artist, BPM (20–300), duration (mm:ss), tuning, notes, lyrics, album artwork, Spotify ID
- `setlist_songs` stores per-setlist BPM/duration/tuning overrides on top of catalog values
- BPM is fetched from Spotify via Edge Function when songs are added — non-blocking, falls back gracefully
- Drag-and-drop reordering stores position server-side via RPC
- Legacy songs with `NULL band_id` use `SECURITY DEFINER` RPCs to bypass RLS

**Files to approach with caution:**
- `setlist_repository.dart` — 4,027 lines; isolate changes, do not add to it
- `setlist_detail_screen.dart` — 2,788 lines; same caution

---

## Data Backup / Export

- Admin-only export (expansion to all members is planned but not implemented)
- Exports as versioned JSON (schema v1): band, members, songs, setlists, gigs, rehearsals, block-out dates
- Excludes: `device_tokens`, `notifications`, `band_calendar_subscriptions`
- File: `lib/features/settings/data_backup_service.dart`
- Import/restore also supported (admin only)

---

## Design Tokens

- Accent color: `#BE123C` (rose) — referenced as `AppColors.accent` in `lib/app/theme/design_tokens.dart`
- Background: `#0A0A0A`
- Never add new global color definitions — always use `AppColors` from `design_tokens.dart`

---

## Architecture Debt (Do Not Replicate)

| Issue | Location | Rule |
|-------|----------|------|
| Routing in `main.dart` | `lib/main.dart:131–187` | Don't add more routing here |
| `_lastLoadedBandId` + microtask pattern | `gig_controller.dart`, `rehearsal_controller.dart` | Don't copy this pattern |
| `catch (e) { return []; }` | Multiple repositories | Don't copy this pattern |
| Monolithic files | `setlist_repository.dart`, `setlist_detail_screen.dart` | Don't add to them |
| Mixed migration naming | `supabase/migrations/` | Use timestamp format for all new migrations |

---

## Cross-References

| Topic | Document |
|-------|----------|
| Live database schema (28 tables, 54 RPCs) | `docs/reference/architecture/database_schema.md` |
| Deployed Edge Functions (11 functions) | `docs/reference/architecture/supabase_functions.md` |
| App init order + config | `docs/reference/general/RUNTIME_CONFIG.md` |
| Architectural decisions log | `docs/reference/general/AI_DECISIONS.md` |
| Notification system detail | `docs/reference/notifications/` |
| Auth / magic link detail | `docs/reference/auth/` |
| BPM / Spotify integration | `docs/reference/bpm/` |
| Deployment | `docs/reference/deployment/deployment.md` |
