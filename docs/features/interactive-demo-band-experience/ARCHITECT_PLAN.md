# ARCHITECT_PLAN — Interactive Demo Band Experience

## Feature Slug

`feature/interactive-demo-band-experience`

## Feature Title

Public, self-resetting interactive demo bands ("Check Out the Demo Band")

## Problem Summary

BandRoadie's current demo entry point is a hidden 7-tap-on-the-logo gesture on the login screen that signs the tapper in as `hello@bandroadie.com` — a single shared real account that owns two poorly-populated demo bands ("The Banana Stand" and "Huge Mistake") plus a stray "Test" band. Because the account is shared and real, every reviewer or curious visitor edits the same underlying data: changes leak between sessions, canonical content drifts over time, and the mechanism can't be documented publicly for Google Play App Access reviewers without exposing the password. Additionally, the demo bands themselves are thin (Banana Stand: 24 songs / 4 setlists / 7 gigs / 4 rehearsals / 2 members; Huge Mistake: 11 songs / 3 setlists / 3 gigs / 0 rehearsals / 2 members), so most screens feel sparse when a reviewer first opens the app.

The Feature Input specifies replacing this with a visible "Check Out the Demo Band" button on the login screen that provisions each visitor a **fresh, private, fully-populated copy of both demo bands** using Supabase's anonymous-auth flow, plus retirement of the entire `DEMO_PASSWORD` build-time-secret pipeline. Tony has already decided the architectural approach — this plan designs the specifics.

## Root Cause

n/a (feature, not a bug)

**Approach confidence:** HIGH. Every piece of the design is verified against code in this session:

- `is_anonymous` field on `User` model is already deserialized by the vendored `supabase_flutter` client (grep of `main.dart.js` and `supabase_flutter` package confirms `is_anonymous` is parsed at [android/app/src/main/assets/public/main.dart.js:31835](android/app/src/main/assets/public/main.dart.js), meaning `supabase.auth.signInAnonymously()` and `session.user.isAnonymous` both work out of the box in the current pubspec).
- Existing RLS policies (e.g. venues, contacts, financial_entries, band_members) all key on `EXISTS (SELECT 1 FROM band_members WHERE user_id = auth.uid() AND status = 'active')`. Anonymous auth users receive a real `auth.uid()` and run under the PostgreSQL `authenticated` role (not `anon`), so they pass every existing band-scoped policy the moment a `band_members` row is inserted for them. No RLS rewrites required.
- The recent security-hardening migrations ([`20260822120000_revoke_anon_batch_1_triggers.sql`](supabase/migrations/20260822120000_revoke_anon_batch_1_triggers.sql) through [`20260822120007_revoke_anon_batch_8_notifications_setlist_stats.sql`](supabase/migrations/20260822120007_revoke_anon_batch_8_notifications_setlist_stats.sql)) revoke the PostgreSQL `anon` role, not anonymous auth users — the two are unrelated, and every guardrail that already exists continues to hold.
- [lib/features/settings/data_backup_service.dart](lib/features/settings/data_backup_service.dart) already encodes the complete band-scoped table set, FK ordering, and "reparent onto a trigger-created catalog setlist" logic needed for cloning. The provisioning RPC below reuses that exact ordering.
- [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart) has a clean, self-contained easter-egg block (`_logoTapCount`, `_logoTapResetTimer`, `_handleLogoTap`, `_triggerDemoLogin`, plus the `if (_logoTapCount >= 3 && _logoTapCount < 7)` hint at [lib/features/auth/login_screen.dart#L544](lib/features/auth/login_screen.dart#L544)) and a single import of [lib/app/constants/demo_credentials.dart](lib/app/constants/demo_credentials.dart). All of it is removable in one atomic pass.

The one MEDIUM-confidence item, called out for the Engineer to verify from code (not hypothesis) before writing the fix, is the exact set of band-scoped providers whose stale state bleeds through band-switching. See "Existing System Analysis" below.

## Existing System Analysis

### Current demo mechanism (surface area to retire)

| File                                                                               | Role                                                                                                                                                                                |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart)         | 7-tap gesture (`_handleLogoTap`, `_logoTapCount`, `_logoTapResetTimer`, tap-count hint at ~L544, `_triggerDemoLogin` calling `signInWithPassword`), imports `demo_credentials.dart` |
| [lib/app/constants/demo_credentials.dart](lib/app/constants/demo_credentials.dart) | `kDemoEmail = 'hello@bandroadie.com'`, `kDemoPassword = String.fromEnvironment('DEMO_PASSWORD')`                                                                                    |
| [run.sh](run.sh)                                                                   | Passes `--dart-define=DEMO_PASSWORD`                                                                                                                                                |
| [dart_defines.json](dart_defines.json)                                             | Contains `DEMO_PASSWORD` key                                                                                                                                                        |
| [tools/gen_dart_defines.sh](tools/gen_dart_defines.sh)                             | Emits `DEMO_PASSWORD` into `dart_defines.json`                                                                                                                                      |
| [tools/build_android.sh](tools/build_android.sh)                                   | Adds `--dart-define=DEMO_PASSWORD` to BUILD_ARGS                                                                                                                                    |
| [tools/build_ios.sh](tools/build_ios.sh)                                           | Adds `--dart-define=DEMO_PASSWORD` (verified in [docs/features/bug/auth-and-demo-login/ARCHITECT_PLAN.md](docs/features/bug/auth-and-demo-login/ARCHITECT_PLAN.md))                 |
| [tools/build_web.sh](tools/build_web.sh)                                           | Adds `--dart-define=DEMO_PASSWORD`                                                                                                                                                  |
| [tools/build_mobile_release.sh](tools/build_mobile_release.sh)                     | Validates `DEMO_PASSWORD` at L97 and asserts embed at build-verify time                                                                                                             |
| [tools/deploy_web.sh](tools/deploy_web.sh)                                         | Fails hard if `DEMO_PASSWORD` unset (L82)                                                                                                                                           |
| [.env.example](.env.example)                                                       | Documents the `DEMO_PASSWORD` variable                                                                                                                                              |

All of this must go, along with the shared `hello@bandroadie.com` auth user, its band memberships, and the stray "Test" band `fc379e2d-5ab9-474b-ad0f-34b0e17f23e6`. The stale comment `band_id: 9187f897-...` in `demo_credentials.dart` is retired along with the file.

### Anonymous auth compatibility with existing RLS/RPCs

Verified across the migrations directory:

- Every band-scoped RLS policy checks `band_members.user_id = auth.uid() AND status = 'active'` (or wraps that check in the helper `check_band_member(band_id)` from [supabase/migrations/20260601000000_create_financial_entries.sql](supabase/migrations/20260601000000_create_financial_entries.sql)). Anonymous auth users produce a real `auth.uid()`; if a `band_members` row exists for them on a cloned demo band, they get the same read/write access every real member gets.
- [supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql](supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql) revokes the PostgreSQL `anon` role from mutation RPCs, then re-grants `authenticated`. Anonymous auth users hold the `authenticated` role JWT, so they still execute those RPCs.
- The `create_band` RPC at [supabase/migrations/087_fix_create_band_no_profile.sql](supabase/migrations/087_fix_create_band_no_profile.sql) auto-creates the `public.users` row from `auth.users.email` if missing. For anonymous users, `auth.users.email` is NULL — we do **not** use `create_band` for provisioning demo clones; the new `provision_demo_session` RPC handles user-row creation and band setup atomically instead. This avoids diverging `create_band`'s behavior.

### Current demo bands (production state)

Confirmed by the Feature Input via direct Supabase query on project `nekwjxvgbveheooyorjo`:

- `hello@bandroadie.com` user id: `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925` — admin of three bands.
- The Banana Stand: `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d` — 24 songs / 4 setlists / 7 gigs / 4 rehearsals / 2 members.
- Huge Mistake: `f9184316-d670-40a5-8409-6197bd53147e` — 11 songs / 3 setlists / 3 gigs / 0 rehearsals / 2 members.
- Test (leftover): `fc379e2d-5ab9-474b-ad0f-34b0e17f23e6` — unrelated to demo, delete outright.

The old comment `band_id: 9187f897-...` in `demo_credentials.dart` is stale — the real Banana Stand id is `e89bea44-...`. Confirmed from the Feature Input; the plan does not depend on the stale UUID for any operation.

### Band-switching state bleed (in-scope defect)

[lib/features/bands/active_band_controller.dart#selectBand](lib/features/bands/active_band_controller.dart) currently only invalidates `currentUserPermissionsProvider`, clears `selectedSetlistProvider`, and resets the tab. It does **not** invalidate the band-scoped providers that hold cached lists (gigs, rehearsals, members, setlists list, contacts, venues, financial entries). PROJECT_CONTEXT.md flags this as a known Critical issue; for real users switching between two of their own bands the bleed is subtle, but a demo visitor toggling between an Arrested Development band and a Star Wars cantina band in the same sitting will see AD gigs on the SW dashboard until the provider refetches. Scope of the fix: enumerate the band-scoped controller/provider set actually used on Dashboard, Setlists, Calendar, Members, and Contacts tabs, and invalidate exactly that set inside `selectBand`. Full audit of the app's provider surface is **out of scope**.

Confidence on the set of providers to invalidate: MEDIUM. Engineer must grep for `activeBandIdProvider` / `activeBandProvider` reads in the `features/gigs`, `features/rehearsals`, `features/setlists`, `features/members`, `features/contacts`, and `features/settings` directories, list the top-level Notifier/AsyncNotifier providers that hold band-scoped state, and invalidate exactly those in `selectBand`. That set is small and finite; enumerating it during implementation (not now, from hypothesis) is the correct path.

## Proposed Solution

### 1. Two-layer data model: canonical templates + per-visit clones

Add three columns and one table:

- `bands.is_demo_template BOOLEAN NOT NULL DEFAULT false` — set to `true` on exactly two seed rows (the new canonical Banana Stand and Modal Nodes templates). Never writeable by anonymous auth users (guarded by trigger; see below).
- `bands.is_demo_clone BOOLEAN NOT NULL DEFAULT false` — set to `true` on every per-visit clone. Used by the cleanup sweep to distinguish clones from real bands.
- `bands.demo_session_id UUID REFERENCES public.demo_sessions(id) ON DELETE CASCADE` — nullable; set on clones, NULL on all other rows including templates. `ON DELETE CASCADE` is the mechanism the sweep uses: deleting one `demo_sessions` row nukes both cloned bands and all their child rows via existing `band_id` cascade chains.
- `public.demo_sessions` table: `(id uuid PK, auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE, provisioned_at timestamptz DEFAULT now(), last_seen_at timestamptz DEFAULT now(), expires_at timestamptz DEFAULT now() + interval '30 minutes', clone_band_ids uuid[] NOT NULL DEFAULT '{}')`. RLS: authenticated users can SELECT/UPDATE their own row only (`auth_user_id = auth.uid()`); nobody can INSERT/DELETE from the client (writes come from `provision_demo_session` and `exit_demo_session` RPCs).

### 2. Template seeding (one-time migration)

Seed once, at migration time, using postgres role privileges (which migrations run under):

- **12 dummy `auth.users` rows** (6 per template band) with `is_anonymous = true`, `raw_user_meta_data = '{"demo_placeholder": true, "display_name": "<full name>"}'::jsonb`, and NULL `email`. These are never signed in as; they exist only so `band_members.user_id` can reference a real row. Same 12 rows are reused for every visitor's clone (visitor's own auth.users row is the 13th and 14th — one per band, both admin).
- **12 matching `public.users` rows** mirroring the auth ids, with `first_name` and `last_name` populated from the display name so the roster renders human-readable names.
- **2 template `bands` rows** with `is_demo_template = true`, both `created_by =` a dedicated dummy "system" auth.users row (the 13th seed user). Cataloged content:
  - The Banana Stand (Arrested Development theme): 16 songs, 5 setlists (`90 min Set`, `2 Hour Set`, `1 Hour Set`, `Motherboy Fest`, `Sudden Valley Block Party`), 7 gigs with the specified fake OC/Newport Beach addresses, 4 rehearsals at Sudden Valley model home, 6 band members per the specified lineup, 4 venues, 4-6 contacts, 4-6 financial entries.
  - Figrin D'an and the Modal Nodes (Star Wars cantina theme, replacing "Huge Mistake"): 16 songs (original titles, no copyrighted lyrics/melodies), 5 setlists, 7 gigs with fictional-galaxy locations in the address field, 3-4 rehearsals at Chalmun's back room, 6 band members per the specified lineup, 4 venues, 4-6 contacts, 4-6 financial entries.

Songs are cataloged with realistic BPMs, durations (2:30–5:00 range), and mixed tunings so the tuning-badge UI has variety. Gigs are split ~40/60 past/future relative to the migration-apply date so both the "upcoming" and "past" dashboard sections have content.

**IP/trademark note:** All character and place names in the seed content come directly from the Feature Input's "SUGGESTED CONTENT" sections, which Tony has already flagged as a known trademark/copyright risk (not an oversight). No lyrics, dialogue, or artwork from the source properties is reproduced. This plan reproduces the Feature Input's naming verbatim; if Tony wants to swap out any specific title before Engineer implements, that direction lands in a Feature Input amendment, not here.

### 3. Provisioning RPC — `provision_demo_session()`

`SECURITY DEFINER`, `SET search_path = public`, returns `jsonb` of `{banana_stand_band_id, modal_nodes_band_id}`. Body outline:

1. Verify `(auth.jwt() ->> 'is_anonymous')::boolean = true`. Real users must not be able to call this; raise if not anonymous.
2. Verify `auth.uid()` is not already in `demo_sessions`. If it is, return the existing row's `clone_band_ids` (idempotent — makes retry-after-network-hiccup safe).
3. Insert the `public.users` row for `auth.uid()` with `first_name = 'Demo'`, `last_name = 'Visitor'`.
4. For each template band (query `WHERE is_demo_template = true`):
   - Insert new `bands` row (new UUID, same `name`/`avatar_color`/`image_url`/`timezone`, `created_by = auth.uid()`, `is_demo_clone = true`, `demo_session_id =` (see step 8)).
   - Insert 6 `band_members` rows for the seeded dummies with the exact roles from the template.
   - Insert one additional `band_members` row for `auth.uid()` with `role = 'admin'`, `status = 'active'`.
   - Bulk-insert `songs` (new UUIDs, `band_id =` new clone; build a `song_id_remap` CTE for step d).
   - Bulk-insert `setlists` — skip any `is_catalog = true` row from the template; instead, look up the auto-created catalog on the new clone (the [`ensure_catalog_setlist` / `auto_create_catalog_for_band`](supabase/migrations/20260824173132_fix_ensure_catalog_band_creation_race.sql) trigger fires on `bands` INSERT and creates it) and remap the template's catalog UUID to the auto-created one. This is the same pattern already used in [lib/features/settings/data_backup_service.dart#L363-L405](lib/features/settings/data_backup_service.dart) for restore.
   - Bulk-insert `setlist_special_items`, `setlist_songs` (using the remaps).
   - Bulk-insert `gigs`, `gig_dates`, `venues`, `venue_contacts`, `contacts`, `rehearsals`, `rehearsal_dates`.
   - Bulk-insert `financial_entries` with `created_by = auth.uid()` and `gig_id` remapped.
5. Insert the `demo_sessions` row referencing `auth.uid()` and both clone `band_id`s. Use this row's `id` for the `bands.demo_session_id` foreign key set in step 4.a — chicken-and-egg is resolved either by inserting `demo_sessions` first (with an empty `clone_band_ids` array, then UPDATE at the end) or by deferring the `demo_session_id` FK (implementation detail — Engineer picks).
6. Return the two clone band UUIDs as JSONB.

Executed in a single transaction. Any failure rolls back to a clean state, no orphan rows. Grants: `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated;`.

### 4. Teardown RPC — `exit_demo_session()`

`SECURITY DEFINER`, `SET search_path = public`, returns `void`. Body:

1. Verify `(auth.jwt() ->> 'is_anonymous')::boolean = true`.
2. `DELETE FROM demo_sessions WHERE auth_user_id = auth.uid()`. This CASCADEs the two cloned `bands` rows via `bands.demo_session_id` FK, which in turn CASCADEs every band-scoped child row (songs, setlists, gigs, rehearsals, contacts, financial_entries, venues, band_members) via the existing `ON DELETE CASCADE` on `band_id`.

Client responsibility after this RPC returns: call `supabase.auth.signOut()` and navigate to the login screen. The `auth.users` row for the visitor remains (deleting it needs `auth.admin.deleteUser()`, which requires service_role); it's cleaned up later by the sweep in §5. Grants: same as §3.

### 5. Cleanup sweep — `cleanup_expired_demo_sessions()`

`SECURITY DEFINER`, `SET search_path = public`. Body:

```sql
DELETE FROM public.demo_sessions
WHERE expires_at < now();
```

That single statement CASCADEs the two clone bands per session via `bands.demo_session_id`. Grants: `REVOKE ALL FROM PUBLIC, anon;` (not callable from clients — pg_cron only). Grant EXECUTE to the pg_cron owner role (typically `postgres`, which already has EXECUTE by default; safer to be explicit: `GRANT EXECUTE ... TO postgres`).

**Inactivity window:** 30 minutes (Feature Input suggested "~20–30 min"). Rationale: web sessions with browser tab left open want longer; abandoned mobile sessions want shorter. 30 min is the upper end of the suggested range and keeps hourly clone volume bounded.

**Heartbeat:** The Flutter app updates `demo_sessions.last_seen_at = now(), expires_at = now() + interval '30 minutes'` via a new `heartbeat_demo_session()` RPC (`SECURITY DEFINER`, checks `is_anonymous`) called from the existing periodic timer in [lib/features/auth/auth_gate.dart#L79-L100](lib/features/auth/auth_gate.dart) (`_startSessionSyncTimer`, already runs every 5 seconds — Engineer adds a branch: if `session.user.isAnonymous`, call the heartbeat RPC every 60 seconds by tracking a "last heartbeat" timestamp, not on every 5-second tick). This keeps the clone alive while the visitor is active.

**Scheduling:** pg_cron every 5 minutes: `SELECT cron.schedule('cleanup_demo_sessions', '*/5 * * * *', $$SELECT cleanup_expired_demo_sessions()$$);`. If pg_cron is not enabled in the project, migration includes `CREATE EXTENSION IF NOT EXISTS pg_cron;` — Tony must confirm at apply time that this extension can be enabled on this Supabase tier. If it can't, fallback is a scheduled Supabase Edge Function calling the same RPC via service_role; Engineer implements only the pg_cron path in the initial migration and defers the Edge Function fallback to a follow-up if pg_cron is unavailable. Orphaned anonymous `auth.users` rows (visitors who tapped the button, got provisioned, and were later swept) accumulate; this is accepted tech debt for v1, tracked in Out of Scope below.

### 6. Template-write safety trigger

A BEFORE INSERT OR UPDATE trigger on `public.bands` that raises if the row being written has `is_demo_template = true` AND the current session's `auth.jwt() ->> 'is_anonymous' = 'true'`. Belt-and-braces on top of the existing RLS (which already prevents anonymous users from touching templates because they have no `band_members` row on them). One-liner defense-in-depth against a future policy consolidation accidentally opening a hole.

Apply the same guard on `songs`, `setlists`, `gigs`, `rehearsals`, `venues`, `contacts`, `financial_entries`: any INSERT/UPDATE where the target `band_id` points to a template band is raised for anonymous users. Implementation: one trigger function reused across the seven tables (checks `EXISTS (SELECT 1 FROM bands WHERE id = NEW.band_id AND is_demo_template = true) AND auth.jwt() ->> 'is_anonymous' = 'true'`).

### 7. Login-screen entry point

Replace the 7-tap easter egg with a visible text button below the "Email Login Link" button on [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart). Copy: `"Check Out the Demo Band"`. Style: text button (`AppButton` with `variant = AppButtonVariant.text` or the closest existing text-link component in [lib/components/ui/](lib/components/ui/); Engineer verifies naming). Tap handler:

1. Set `_isLoading = true`.
2. `await supabase.auth.signInAnonymously()` — creates the `auth.users` row and issues a JWT with `is_anonymous = true`.
3. `await supabase.rpc('provision_demo_session')` — provisions both clones.
4. `await ref.read(activeBandProvider.notifier).loadUserBands()` — populates the band list from Supabase.
5. `await ref.read(activeBandProvider.notifier).selectBandById('<banana_stand_clone_id>')` — defaults into Banana Stand per Feature Input.
6. AuthGate's existing `signedIn` handler routes to AppShell. No demo-specific routing.

Errors: on any failure between steps 2–5, call `supabase.auth.signOut()` to discard the half-provisioned anonymous session and show an inline error like `"🎸 Couldn't load the demo — try again in a bit."` (brand-voice per [docs/agents/PROJECT_CONTEXT.md](docs/agents/PROJECT_CONTEXT.md) Brand Voice section).

### 8. Exit Demo action

Add a menu item labeled "Exit Demo" to the side drawer at [lib/features/home/widgets/side_drawer.dart](lib/features/home/widgets/side_drawer.dart), rendered **only when** `supabase.auth.currentUser?.isAnonymous == true`. Place it in the same section as "Log Out" (drawer already has a Log Out slot at ~L293–303), above Log Out. Tap handler:

1. `await supabase.rpc('exit_demo_session')` — deletes both clones and the demo_sessions row.
2. `await supabase.auth.signOut()`.
3. AuthGate's `signedOut` handler routes back to the login screen.

Do not modify `Log Out` behavior for anonymous users — Exit Demo is the sanctioned path. If a visitor hits Log Out instead, the sweep in §5 will clean up their orphaned clone within 30 minutes.

### 9. Band-switching state bleed fix (in-scope)

In [lib/features/bands/active_band_controller.dart#selectBand](lib/features/bands/active_band_controller.dart), add `ref.invalidate(...)` calls for every band-scoped top-level Notifier provider used by Dashboard / Setlists / Calendar / Members / Contacts. Engineer will enumerate the set by grepping `features/{gigs,rehearsals,setlists,members,contacts,settings}/*_controller.dart` and `*_provider.dart` for reads of `activeBandProvider` / `activeBandIdProvider`, then invalidate exactly those. Also apply the same invalidations to `selectBandById`, `loadAndSelectBand`, and `refreshBands` (which currently share the same defect).

Non-goal: refactoring providers to `ref.watch(activeBandIdProvider)`. Minimal `ref.invalidate` calls are sufficient and unambiguous.

## Database Impact

**Migrations to author (6 files, applied in order by Tony):**

| Migration file                                                               | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260904120000_demo_bands_schema.sql`                   | Create `demo_sessions` table + RLS. Add `bands.is_demo_template`, `bands.is_demo_clone`, `bands.demo_session_id`. Add template-write-guard trigger function and apply to `bands`, `songs`, `setlists`, `gigs`, `rehearsals`, `venues`, `contacts`, `financial_entries`.                                                                                                                                                                                                                                                    |
| `supabase/migrations/20260904120001_seed_demo_templates.sql`                 | Insert 13 dummy `auth.users` (12 band members + 1 "demo system" band creator), matching `public.users` rows, 2 template `bands`, 6 `band_members` per template, 16 `songs`, 5 `setlists`, `setlist_songs`, 7 `gigs`, `gig_dates`, 3–4 `rehearsals`, 4 `venues`, `venue_contacts`, 4–6 `contacts`, 4–6 `financial_entries` per template. Sets `is_demo_template = true` on both bands.                                                                                                                                      |
| `supabase/migrations/20260904120002_cleanup_old_demo_account.sql`            | `DELETE FROM auth.users WHERE id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'` (cascades old Banana Stand membership, old Huge Mistake membership, Test membership via existing `band_members.user_id` FK). Then explicit `DELETE FROM bands WHERE id IN ('e89bea44-8dd4-4e3d-b527-c0f75e94aa7d', 'f9184316-d670-40a5-8409-6197bd53147e', 'fc379e2d-5ab9-474b-ad0f-34b0e17f23e6')` to nuke any surviving old bands and their content. Runs **after** the template seed so there is never a moment where zero demo bands exist. |
| `supabase/migrations/20260904120003_provision_demo_session_rpc.sql`          | `CREATE FUNCTION provision_demo_session()`. `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated;`.                                                                                                                                                                                                                                                                                                                                                                                                               |
| `supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql` | `CREATE FUNCTION exit_demo_session()` and `heartbeat_demo_session()`. Same grant pattern.                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql`          | `CREATE EXTENSION IF NOT EXISTS pg_cron; CREATE FUNCTION cleanup_expired_demo_sessions();` `REVOKE ALL FROM PUBLIC, anon;` `SELECT cron.schedule(...)`. If pg_cron cannot be enabled at apply time, Tony pauses this migration and Engineer follows up with an Edge Function fallback in a subsequent feature.                                                                                                                                                                                                             |

**RLS:**

- New `demo_sessions` table: policy `demo_sessions_select_own` (`auth_user_id = auth.uid()`), policy `demo_sessions_update_own` (same). No client INSERT or DELETE policy — writes come from `SECURITY DEFINER` RPCs.
- Existing RLS on all other tables: **unchanged**. Anonymous auth users pass every band-scoped policy the moment `band_members` rows are inserted for them.

**Guardrail checklist per migration:**

- ☑ Every `SECURITY DEFINER` function declares `SET search_path = public` as a function attribute (not inside the body).
- ☑ Every new function has `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated;` (or `TO postgres` for `cleanup_expired_demo_sessions`, which is pg_cron-only).
- ☑ No RLS policy queries the table it protects (verified: policies on `demo_sessions` reference only `auth.uid()`, not the table itself).
- ☑ `provision_demo_session` is idempotent by design (returns existing session's band ids if called twice with the same `auth.uid()`) and executes in a single transaction (all-or-nothing).

## Flutter Architecture Changes

**No new controllers, providers, or repositories beyond what's genuinely required.** Reuse the existing pattern.

- `login_screen.dart` gets a `_triggerDemoSession()` method that owns the sign-in → RPC → activate-band flow (parallel to how `_triggerDemoLogin()` currently owns its flow). No new class.
- One thin service file `lib/features/auth/demo_session_service.dart` exposing static `Future<void> provisionAndEnter(WidgetRef ref)`, `Future<void> exit(WidgetRef ref)`, and `Future<void> heartbeat()`. Static methods only, no Notifier — this is a stateless RPC wrapper. Placing it in `features/auth` keeps demo entry co-located with the login screen it serves.
- Reuse the existing `AuthGate._sessionSyncTimer` to piggyback the heartbeat (feature-flag check on `session.user.isAnonymous`) — no new timer, no new provider.
- `active_band_controller.dart` gets ~6 lines of new `ref.invalidate` calls; no structural change.
- `side_drawer.dart` gets a conditional "Exit Demo" menu item; no widget refactor.

## Files to Create

| File                                                                         | Purpose                                                 | Approx size                 |
| ---------------------------------------------------------------------------- | ------------------------------------------------------- | --------------------------- |
| `supabase/migrations/20260904120000_demo_bands_schema.sql`                   | Schema: table + columns + guard trigger                 | ~90 lines                   |
| `supabase/migrations/20260904120001_seed_demo_templates.sql`                 | Seed both template bands + all content                  | ~600–900 lines (data-heavy) |
| `supabase/migrations/20260904120002_cleanup_old_demo_account.sql`            | Retire `hello@bandroadie.com` + old bands               | ~30 lines                   |
| `supabase/migrations/20260904120003_provision_demo_session_rpc.sql`          | Provisioning RPC                                        | ~200 lines                  |
| `supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql` | Teardown + heartbeat RPCs                               | ~60 lines                   |
| `supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql`          | Sweep function + pg_cron schedule                       | ~40 lines                   |
| `lib/features/auth/demo_session_service.dart`                                | Client wrapper for the three RPCs and provisioning flow | ~120 lines                  |
| `docs/features/interactive-demo-band-experience/ARCHITECT_PLAN.md`           | This document                                           | (existing)                  |

## Files to Modify

| File                                                                                             | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart)                       | **Remove:** import of `demo_credentials.dart`; `_logoTapCount`, `_logoTapResetTimer` fields; `_handleLogoTap()`, `_triggerDemoLogin()` methods; `GestureDetector(onTap: _handleLogoTap, ...)` wrapper on `_buildLogo()`; the `if (_logoTapCount >= 3 && _logoTapCount < 7)` hint Stack child. **Add:** "Check Out the Demo Band" text button below `_buildLoginButton`, calling `DemoSessionService.provisionAndEnter(ref)`. Screen becomes a `ConsumerStatefulWidget` (currently `StatefulWidget`) so it has `ref` — verify no other consumers break. |
| [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart) | Add `ref.invalidate(...)` calls in `selectBand`, `selectBandById`, `loadAndSelectBand`, `refreshBands` for the enumerated band-scoped provider set. Engineer produces the enumerated list from grepping the codebase — do not guess.                                                                                                                                                                                                                                                                                                                   |
| [lib/features/home/widgets/side_drawer.dart](lib/features/home/widgets/side_drawer.dart)         | Add conditional "Exit Demo" menu item above "Log Out" — visible only when `Supabase.instance.client.auth.currentUser?.isAnonymous == true`. Wire to `DemoSessionService.exit(ref)`.                                                                                                                                                                                                                                                                                                                                                                    |
| [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart)                           | Pass an `onExitDemoTap` callback into the drawer layer if the drawer widget needs it wired externally; otherwise no change.                                                                                                                                                                                                                                                                                                                                                                                                                            |
| [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart)                             | Inside `_startSessionSyncTimer`'s callback, add a branch: if `session?.user.isAnonymous == true` and it's been ≥60s since last heartbeat, call `DemoSessionService.heartbeat()`.                                                                                                                                                                                                                                                                                                                                                                       |
| [run.sh](run.sh)                                                                                 | Remove `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"` line.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| [dart_defines.json](dart_defines.json)                                                           | Remove `"DEMO_PASSWORD": "..."` key.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| [tools/gen_dart_defines.sh](tools/gen_dart_defines.sh)                                           | Remove the `"DEMO_PASSWORD"` line from the heredoc.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| [tools/build_android.sh](tools/build_android.sh)                                                 | Remove `--dart-define=DEMO_PASSWORD=...` from `DART_DEFINES`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| [tools/build_ios.sh](tools/build_ios.sh)                                                         | Remove both explicit `--dart-define=DEMO_PASSWORD` occurrences.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| [tools/build_web.sh](tools/build_web.sh)                                                         | Remove `--dart-define=DEMO_PASSWORD=...`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| [tools/build_mobile_release.sh](tools/build_mobile_release.sh)                                   | Remove `DEMO_PASSWORD` validation block (L96–99), remove `DEMO_PASSWORD` from BUILD_ARGS, remove the artifact-verification `strings ... grep DEMO_PASSWORD` block.                                                                                                                                                                                                                                                                                                                                                                                     |
| [tools/deploy_web.sh](tools/deploy_web.sh)                                                       | Remove `[[ -z "${DEMO_PASSWORD:-}" ]] && fail "DEMO_PASSWORD not set in .env"` and any `--dart-define=DEMO_PASSWORD` on the web build command.                                                                                                                                                                                                                                                                                                                                                                                                         |
| [.env.example](.env.example)                                                                     | Remove the `# ── Demo Account (Play Store App Access) ──` block and `DEMO_PASSWORD=` line.                                                                                                                                                                                                                                                                                                                                                                                                                                                             |

## Files to Delete

| File                                                                               | Reason                                      |
| ---------------------------------------------------------------------------------- | ------------------------------------------- |
| [lib/app/constants/demo_credentials.dart](lib/app/constants/demo_credentials.dart) | Password-based demo login is being retired. |

## Files Off-Limits

| Path                                                                                                                                                                                                 | Reason it must not change here                                                                                                                                                                                                                                                                                                            |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/main.dart](lib/main.dart) — init order block                                                                                                                                                    | Guardrail: init order (`WidgetsFlutterBinding` → URL strategy → orientation → `AppVersionService.init` → `validateSupabaseConfig` → `Supabase.initialize` → `Firebase.initializeApp` → `DeepLinkService` → `runApp`) is fixed. Anonymous auth uses the same `Supabase` client that's already initialized — no init-order change required. |
| [lib/main.dart](lib/main.dart) — routing block                                                                                                                                                       | Demo entry lands at AuthGate → AppShell via the existing signed-in code path. No new routes needed.                                                                                                                                                                                                                                       |
| [lib/app/supabase_config.dart](lib/app/supabase_config.dart), [lib/app/firebase_config.dart](lib/app/firebase_config.dart)                                                                           | No new `--dart-define` values — nothing to validate.                                                                                                                                                                                                                                                                                      |
| [lib/features/auth/auth_confirm_screen.dart](lib/features/auth/auth_confirm_screen.dart), [lib/app/services/deep_link_service.dart](lib/app/services/deep_link_service.dart)                         | Magic-link PKCE flow is untouched. Anonymous auth uses `signInAnonymously()`, not deep links.                                                                                                                                                                                                                                             |
| [lib/features/setlists/setlist_repository.dart](lib/features/setlists/setlist_repository.dart), [lib/features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart) | Mega files flagged by PROJECT_CONTEXT.md ("do not add to"). Cloning happens server-side in the provisioning RPC; the client reads through existing paths.                                                                                                                                                                                 |
| Existing RLS policies on `bands`, `band_members`, `songs`, `setlists`, `setlist_songs`, `gigs`, `rehearsals`, `contacts`, `venues`, `financial_entries`                                              | Verified compatible with anonymous auth users out of the box. Modifying them is out of scope and would cascade risk.                                                                                                                                                                                                                      |
| Existing SECURITY DEFINER functions (`create_band`, `delete_band`, `update_member_role`, `restore_band_members`, `check_band_member`, etc.)                                                          | Provisioning has its own dedicated RPC — do not overload existing ones.                                                                                                                                                                                                                                                                   |
| Existing notification triggers                                                                                                                                                                       | Anonymous demo user is always the actor of their own actions; the "never notify the actor" rule at [docs/agents/PROJECT_CONTEXT.md](docs/agents/PROJECT_CONTEXT.md) already handles this correctly.                                                                                                                                       |
| Google Play Console App Access declaration                                                                                                                                                           | Out-of-band Tony task, called out in Rollout below but not touched here.                                                                                                                                                                                                                                                                  |

## Change Budget

| File / area                                                                                                                                                                                                                                                                                                                                                                                      | Expected net line delta                                                    |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart)                                                                                                                                                                                                                                                                                                                       | **−80 to −40** (remove ~80 easter-egg lines, add ~30 button + handler).    |
| [lib/app/constants/demo_credentials.dart](lib/app/constants/demo_credentials.dart)                                                                                                                                                                                                                                                                                                               | **−22** (delete).                                                          |
| [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart)                                                                                                                                                                                                                                                                                                 | **+8 to +14** (invalidate calls in 4 methods).                             |
| [lib/features/home/widgets/side_drawer.dart](lib/features/home/widgets/side_drawer.dart)                                                                                                                                                                                                                                                                                                         | **+30 to +50** (conditional Exit Demo item + plumbing).                    |
| [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart)                                                                                                                                                                                                                                                                                                                           | **+5 to +15** (drawer callback wiring, only if drawer needs it).           |
| [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart)                                                                                                                                                                                                                                                                                                                             | **+10 to +20** (heartbeat branch inside existing timer).                   |
| [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart)                                                                                                                                                                                                                                                                                                       | **+120 new**.                                                              |
| [run.sh](run.sh), [dart_defines.json](dart_defines.json), [tools/gen_dart_defines.sh](tools/gen_dart_defines.sh), [tools/build_android.sh](tools/build_android.sh), [tools/build_ios.sh](tools/build_ios.sh), [tools/build_web.sh](tools/build_web.sh), [tools/build_mobile_release.sh](tools/build_mobile_release.sh), [tools/deploy_web.sh](tools/deploy_web.sh), [.env.example](.env.example) | **−30 to −20** combined (line removals only).                              |
| Migration files (six)                                                                                                                                                                                                                                                                                                                                                                            | **+900 to +1300** combined, dominated by seed content in `20260904120001`. |
| **Total net (excluding docs & seed SQL bulk)**                                                                                                                                                                                                                                                                                                                                                   | **~+130 to +200** application code, **~+900 to +1300** SQL.                |

**Expected new files:** 7 (six migrations + one `demo_session_service.dart`).
**Expected new public classes:** 1 (`DemoSessionService`).
**Expected new public methods:** 3 (`DemoSessionService.provisionAndEnter`, `.exit`, `.heartbeat`).
**Expected new dependencies:** 0.

## System Impact Map

| System                    | Affected?            | Notes                                                                                                                                                                                                                                                                                  |
| ------------------------- | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                      | Affected (data only) | Cloned demo bands hold gig rows that render through existing gig screens. Also indirectly affected by `active_band_controller.selectBand` invalidation change.                                                                                                                         |
| Rehearsals                | Affected (data only) | Same as Gigs.                                                                                                                                                                                                                                                                          |
| Setlists                  | Affected (data only) | Same.                                                                                                                                                                                                                                                                                  |
| Members                   | Affected (data only) | Cloned bands hold real `band_members` rows referencing dummy `auth.users`. Members roster renders normally.                                                                                                                                                                            |
| Auth                      | Affected             | New anonymous-auth entry point. Magic-link + PKCE flow unchanged.                                                                                                                                                                                                                      |
| Routing                   | Unaffected           | Demo entry uses existing `signedIn` → AuthGate → AppShell path.                                                                                                                                                                                                                        |
| Notifications             | Unaffected           | Anonymous demo user is always the actor; "never notify the actor" rule handles it.                                                                                                                                                                                                     |
| Push (FCM)                | Unaffected           | Anonymous users don't register FCM tokens (they hit `_registerPushToken` in AuthGate, which will try, but Supabase will accept a `device_tokens` row keyed on the anon `user_id`; it's harmless dead data that gets cleaned when the user is swept). Engineer to verify no crash path. |
| Platforms — iOS           | Affected             | Login button visible; `signInAnonymously` works via PKCE-configured client.                                                                                                                                                                                                            |
| Platforms — Android       | Affected             | Same.                                                                                                                                                                                                                                                                                  |
| Platforms — Web           | Affected             | Same.                                                                                                                                                                                                                                                                                  |
| Platforms — macOS         | Affected             | Same. `_isMarketingHost` unreachable from macOS (`kIsWeb` is false); no interaction.                                                                                                                                                                                                   |
| Platforms — Windows/Linux | Unknown              | Not in Feature Input's confirmed target list. If either is an active build target, the button appears identically (no platform-specific code path). No verification required for this feature.                                                                                         |

## Regression Risk

**MEDIUM.**

Reasoning:

- Touches auth (adds a new sign-in path), the login screen (visible change), band-scoped state (invalidation fix), and the DB (six new migrations, one of which deletes production data). Each of those is individually low-risk; the combination is medium.
- Anonymous-auth path is isolated from magic-link path — no cross-contamination.
- The `active_band_controller.selectBand` invalidation change is additive: worst case is over-invalidation (extra refetches on band switch), which is a perf concern, not a correctness one. Better than the current bleed.
- The `hello@bandroadie.com` cleanup migration is destructive but scoped to three known band UUIDs and one known user UUID, all confirmed live by Feature Input. If the seed migration (`20260904120001`) hasn't already applied cleanly, `20260904120002` should not proceed; Engineer sequences the migrations so the cleanup only runs after the templates exist, and Tony applies them in order.
- pg_cron availability is a hard external dependency. If pg_cron isn't enabled on the project's Supabase tier, migration `20260904120005` fails at `CREATE EXTENSION` and Tony pauses. Engineer's fallback plan is a subsequent Edge Function feature — **not** attempted in this feature.
- The seed data is large (~800 lines of INSERTs). A single typo (unbalanced quote, wrong UUID) fails the whole seed atomically — no partial state to recover from.

## Engineer Task Breakdown

Ordered, atomic. Each step ends in a state where the app compiles.

1. **Migration `20260904120000_demo_bands_schema.sql`.** Author: `demo_sessions` table + RLS; `bands.is_demo_template`, `bands.is_demo_clone`, `bands.demo_session_id` columns; template-write-guard trigger function; apply the trigger to `bands`, `songs`, `setlists`, `gigs`, `rehearsals`, `venues`, `contacts`, `financial_entries`.
2. **Migration `20260904120001_seed_demo_templates.sql`.** Author: 13 dummy `auth.users` rows (with fixed, deterministic UUIDs so subsequent migrations can reference them), 13 matching `public.users` rows, 2 template `bands` (with fixed UUIDs), all seed content (songs, setlists, setlist_songs, gigs, gig_dates, venues, venue_contacts, contacts, rehearsals, rehearsal_dates, financial_entries) per the Feature Input's SUGGESTED CONTENT sections. Every UUID literal in this file is deterministic (hand-picked or generated once) — no `gen_random_uuid()` calls in the seed body, because the provisioning RPC needs to be able to SELECT-FROM-templates by predictable IDs.
3. **Migration `20260904120002_cleanup_old_demo_account.sql`.** Author: `DELETE FROM auth.users WHERE id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'`; `DELETE FROM bands WHERE id IN ('e89bea44-8dd4-4e3d-b527-c0f75e94aa7d', 'f9184316-d670-40a5-8409-6197bd53147e', 'fc379e2d-5ab9-474b-ad0f-34b0e17f23e6')`. Add a preceding `DO $$ ... $$` block that RAISES if the template bands from step 2 don't yet exist (guard against Tony applying migrations out of order).
4. **Migration `20260904120003_provision_demo_session_rpc.sql`.** Author `provision_demo_session()` per §3 above. Grants: `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated;`.
5. **Migration `20260904120004_exit_and_heartbeat_demo_session_rpc.sql`.** Author `exit_demo_session()` and `heartbeat_demo_session()`. Grants: same.
6. **Migration `20260904120005_cleanup_demo_sessions_cron.sql`.** Author `cleanup_expired_demo_sessions()` and `cron.schedule(...)`. Grants: `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO postgres;`. Include `CREATE EXTENSION IF NOT EXISTS pg_cron;` at the top.
7. **Create `lib/features/auth/demo_session_service.dart`.** Static methods `provisionAndEnter(WidgetRef ref)`, `exit(WidgetRef ref)`, `heartbeat()`. Each method wraps the corresponding RPC with typed error handling (returns void, throws a `DemoSessionException` on failure that the caller surfaces to the user).
8. **Edit `lib/features/auth/login_screen.dart`.** Remove: `_logoTapCount`, `_logoTapResetTimer`, `_handleLogoTap`, `_triggerDemoLogin`, the `GestureDetector` wrapper around `_buildLogo`, the tap-count hint Stack child (~L544), the import of `demo_credentials.dart`. Convert `LoginScreen` from `StatefulWidget` to `ConsumerStatefulWidget` (and `_LoginScreenState` to `ConsumerState`) so it has `ref`. Add a text button below `_buildLoginButton` (see §7 above for behavior) that calls `DemoSessionService.provisionAndEnter(ref)` and shows a spinner + inline error on failure. Verify all other callers of `LoginScreen` still compile.
9. **Delete `lib/app/constants/demo_credentials.dart`.**
10. **Edit `lib/features/bands/active_band_controller.dart`.** Enumerate the band-scoped provider set: grep `features/{gigs,rehearsals,setlists,members,contacts,settings}/*_controller.dart` and `*_provider.dart` for `activeBandProvider`/`activeBandIdProvider` reads; list the top-level `Notifier`/`AsyncNotifier` providers found. Add `ref.invalidate(...)` calls for each of them in `selectBand`, `selectBandById`, `loadAndSelectBand`, and `refreshBands`. Document the enumerated list in a code comment above the first invalidation block so future readers understand the invariant.
11. **Edit `lib/features/home/widgets/side_drawer.dart` + `lib/features/shell/app_shell.dart`.** Add an "Exit Demo" menu item to the drawer above "Log Out", rendered only when `Supabase.instance.client.auth.currentUser?.isAnonymous == true`. Wire the tap through `AppShell._MenuDrawerLayer` to a new `onExitDemoTap` callback that calls `DemoSessionService.exit(ref)`.
12. **Edit `lib/features/auth/auth_gate.dart`.** Inside `_startSessionSyncTimer`'s existing `Timer.periodic` callback, add a branch: if `session?.user.isAnonymous == true` and it's been ≥60s since last heartbeat (track in a private `DateTime? _lastHeartbeatAt` field), call `DemoSessionService.heartbeat()`. Do not create a second timer.
13. **Strip `DEMO_PASSWORD` from build config.** Edit [run.sh](run.sh), [dart_defines.json](dart_defines.json), [tools/gen_dart_defines.sh](tools/gen_dart_defines.sh), [tools/build_android.sh](tools/build_android.sh), [tools/build_ios.sh](tools/build_ios.sh), [tools/build_web.sh](tools/build_web.sh), [tools/build_mobile_release.sh](tools/build_mobile_release.sh), [tools/deploy_web.sh](tools/deploy_web.sh), [.env.example](.env.example) per the "Files to Modify" table. Verify with `grep -r DEMO_PASSWORD` — the only remaining hits should be in `docs/features/*/ARCHITECT_PLAN.md` or `docs/features/*/QA_REPORT.md` (historical, not executable).
14. **Add tests.** See Verification Plan.

## Verification Plan

**Constraint:** Managed Supabase branch verification (`supabase branches create`) is broken project-wide at migration 073 per the Feature Input's KNOWN INFRA BLOCKER. Tier 2 SQL verification below is executed either by Tony against a **scratch project** (not production, not a managed branch) or by careful manual SQL review at apply time. QA does not run destructive SQL against production.

### Tier 1 — Pre-deploy (never calls the new RPCs)

Tier 1 tests exercise the code paths that don't require the new RPCs to already exist. They run against the current production Supabase before the migrations apply.

- **T1.1 — `grep -r 'DEMO_PASSWORD' .` returns zero matches in `lib/`, `tools/`, `run.sh`, `dart_defines.json`, `.env.example`.** (Docs allowed to still mention it.) One-line command in QA report.
- **T1.2 — `grep -r 'demo_credentials' lib/` returns zero matches.** File deletion verified.
- **T1.3 — `flutter analyze` returns clean.** No new warnings or errors introduced.
- **T1.4 — Widget test: login screen renders "Check Out the Demo Band" button.** New test file `test/features/auth/login_screen_demo_button_test.dart` pumping `LoginScreen` inside a `ProviderScope` with a mock Supabase client, verifying the button is present, tappable, and shows a loading spinner when tapped. Verifies the button appears on all `MediaQuery` sizes commonly tested (phone / tablet). Does **not** call `signInAnonymously` — the mock intercepts.
- **T1.5 — Widget test: 7-tap logo no longer signs in.** Same test file: tap the logo 8 times, assert `signInWithPassword` is never called on the mock client and no navigation occurs.
- **T1.6 — Unit test: `active_band_controller.selectBand` invalidates the enumerated band-scoped provider set.** New test file `test/features/bands/active_band_controller_invalidation_test.dart` that constructs a `ProviderContainer`, primes each enumerated provider, calls `selectBand(otherBand)`, and asserts each provider returns to its initial state (or `AsyncLoading`) on the next read. One test case per provider in the enumerated set.
- **T1.7 — Static SQL review of every new migration.** Cross-check against these guardrails, documented in QA report table:
  - Every `SECURITY DEFINER` function has `SET search_path = public` as a function attribute (`grep -A2 'SECURITY DEFINER' | grep 'SET search_path'`).
  - Every new function has `REVOKE ALL ... FROM PUBLIC, anon;` and an explicit `GRANT EXECUTE TO <role>` on the following line.
  - No RLS policy on `demo_sessions` references `demo_sessions` in its predicate.
  - Seed migration uses only deterministic literal UUIDs (no `gen_random_uuid()` in the INSERT-into-templates statements — grep confirms).
  - The cleanup-old-demo-account migration has the `DO $$ ... RAISE` guard against the templates not existing yet.

### Tier 2 — Post-deploy (calls the new RPCs)

Tier 2 runs against the scratch project or, at apply time, production (Tony's discretion). Every SQL test either rolls back inside a transaction or uses fresh UUIDs and cleans them up. **No SQL test hardcodes a production UUID other than the three explicit deletion targets in `20260904120002_cleanup_old_demo_account.sql`.**

- **T2.1 — Schema shape.** `SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'bands' AND column_name IN ('is_demo_template', 'is_demo_clone', 'demo_session_id');` returns 3 rows. `SELECT * FROM pg_tables WHERE tablename = 'demo_sessions';` returns 1 row. `SELECT policyname FROM pg_policies WHERE tablename = 'demo_sessions';` returns exactly 2 rows (`demo_sessions_select_own`, `demo_sessions_update_own`) and neither policy references `demo_sessions` in its predicate.
- **T2.2 — Seed data shape per template.** For each template band UUID:

  ```sql
  SELECT
    (SELECT COUNT(*) FROM band_members WHERE band_id = $1) AS members,
    (SELECT COUNT(*) FROM songs WHERE band_id = $1) AS songs,
    (SELECT COUNT(*) FROM setlists WHERE band_id = $1) AS setlists,
    (SELECT COUNT(*) FROM gigs WHERE band_id = $1) AS gigs,
    (SELECT COUNT(*) FROM rehearsals WHERE band_id = $1) AS rehearsals,
    (SELECT COUNT(*) FROM venues WHERE band_id = $1) AS venues,
    (SELECT COUNT(*) FROM contacts WHERE band_id = $1) AS contacts,
    (SELECT COUNT(*) FROM financial_entries WHERE band_id = $1) AS financial_entries;
  ```

  Expected: members = 6, songs = 16, setlists = 5, gigs = 7, rehearsals ∈ [3,4], venues ≥ 4, contacts ∈ [4,6], financial_entries ∈ [4,6]. Both bands.

- **T2.3 — Setlist names per template.** `SELECT name FROM setlists WHERE band_id = <banana_stand_template> ORDER BY name;` returns exactly `1 Hour Set`, `2 Hour Set`, `90 min Set`, `Catalog` (auto-created), `Motherboy Fest`, `Sudden Valley Block Party` — matching Feature Input's exact 5-setlist list plus the auto-Catalog. Same shape for Modal Nodes with its specified 5 setlists.
- **T2.4 — Old demo account cleanup.** `SELECT COUNT(*) FROM auth.users WHERE id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925';` returns 0. `SELECT COUNT(*) FROM bands WHERE id IN ('e89bea44-8dd4-4e3d-b527-c0f75e94aa7d', 'f9184316-d670-40a5-8409-6197bd53147e', 'fc379e2d-5ab9-474b-ad0f-34b0e17f23e6');` returns 0.
- **T2.5 — RPC grant hygiene.** For each of `provision_demo_session`, `exit_demo_session`, `heartbeat_demo_session`, `cleanup_expired_demo_sessions`, `template_write_guard`:

  ```sql
  SELECT
    has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_ok,
    has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_should_be_false,
    has_function_privilege('service_role', p.oid, 'EXECUTE')  AS svc_ok
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = '<function_name>';
  ```

  Expected: `auth_ok = true` for `provision_demo_session`, `exit_demo_session`, `heartbeat_demo_session`; `auth_ok = false` for `cleanup_expired_demo_sessions`; `anon_should_be_false = false` for all five. `has_function_privilege` (not a `grep` of the raw ACL) is the correct check per guardrails — a PUBLIC grant would satisfy a naïve string match on every role.

- **T2.6 — pg_cron schedule.** `SELECT jobname, schedule, command FROM cron.job WHERE jobname = 'cleanup_demo_sessions';` returns 1 row with `schedule = '*/5 * * * *'` and `command LIKE 'SELECT cleanup_expired_demo_sessions()%'`.
- **T2.7 — Provisioning happy path (idempotent, produces identical output).** In a transaction:

  ```sql
  BEGIN;
  -- Simulate an anonymous session
  SET LOCAL request.jwt.claims TO '{"role": "authenticated", "is_anonymous": "true", "sub": "11111111-1111-1111-1111-111111111111"}';
  -- Set up the anon user row so FK constraints pass
  INSERT INTO auth.users (id, is_anonymous, aud, role, instance_id, created_at, updated_at) VALUES ('11111111-1111-1111-1111-111111111111', true, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now(), now());
  SELECT provision_demo_session();   -- Call once
  SELECT provision_demo_session();   -- Call again (should be idempotent)
  SELECT COUNT(*) FROM bands WHERE demo_session_id = (SELECT id FROM demo_sessions WHERE auth_user_id = '11111111-1111-1111-1111-111111111111');
  -- Expected: 2 (still only 2 clone bands, not 4)
  ROLLBACK;
  ```

  Verifies the RPC is idempotent (submission-flow guardrail) and produces identical output on identical input. This test rolls back — no residue.

- **T2.8 — Provisioning refused for non-anonymous user.**

  ```sql
  BEGIN;
  SET LOCAL request.jwt.claims TO '{"role": "authenticated", "is_anonymous": "false", "sub": "<any-real-user-uuid>"}';
  -- Expect: raises 'Not an anonymous session'
  SELECT provision_demo_session();
  ROLLBACK;
  ```

- **T2.9 — Isolation between two concurrent provisioned sessions.** Two `BEGIN; ... provision_demo_session(); ...` blocks in separate psql sessions, verify each sees only their own clone bands via `SELECT id FROM bands WHERE demo_session_id = <mine>`. Cross-visibility check: session A tries `SELECT * FROM bands WHERE demo_session_id = <session B's id>` — expected: 0 rows (RLS on `bands` still requires membership, which A doesn't have on B's clones).
- **T2.10 — Teardown cleans everything for one visitor.** After T2.7's provisioning (in a fresh transaction), call `exit_demo_session()` — expected: `demo_sessions` row for that user is gone, both clone `bands` rows are gone, and `SELECT COUNT(*) FROM songs WHERE band_id IN (<the two clone ids>)` returns 0 (CASCADE proved). Rollback.
- **T2.11 — Cleanup sweep on expired session.**

  ```sql
  BEGIN;
  -- Set up a session already expired
  INSERT INTO auth.users (id, is_anonymous, ...) VALUES ('22222222-...', true, ...);
  SET LOCAL request.jwt.claims TO '{"role":"authenticated","is_anonymous":"true","sub":"22222222-..."}';
  SELECT provision_demo_session();
  UPDATE demo_sessions SET expires_at = now() - interval '1 minute' WHERE auth_user_id = '22222222-...';
  RESET request.jwt.claims;
  SELECT cleanup_expired_demo_sessions();
  SELECT COUNT(*) FROM demo_sessions WHERE auth_user_id = '22222222-...';   -- 0
  SELECT COUNT(*) FROM bands WHERE created_by = '22222222-...';             -- 0
  ROLLBACK;
  ```

- **T2.12 — End-to-end manual smoke, all four platforms.** After migrations applied and Flutter build deployed:
  1. Load login screen. Verify "Check Out the Demo Band" button visible. Verify tapping the logo 7× does nothing.
  2. Tap the button. Verify no credential prompt; land in AppShell with Banana Stand active.
  3. Switch to Figrin D'an via band switcher. Verify dashboard shows Modal Nodes gigs/rehearsals — no Banana Stand bleed. Switch back to Banana Stand. Verify same.
  4. Add a gig on Banana Stand. Open a second incognito window / device. Tap "Check Out the Demo Band" there. Verify the second visitor does NOT see the first visitor's added gig.
  5. On the first visitor's session, tap Exit Demo. Verify sign-out lands back at login screen. Optionally query DB: `SELECT COUNT(*) FROM bands WHERE created_by = <first_visitor_uid>` returns 0.
  6. Kill the second visitor's tab without tapping Exit Demo. Wait 35 min. Query: `SELECT COUNT(*) FROM demo_sessions WHERE auth_user_id = <second_visitor_uid>` returns 0.

## QA Regression Areas

Areas to smoke-test that are not directly changed but sit next to changes:

- **Real user magic-link login.** Regression test: enter email, receive magic link, click link, land in AppShell. Confirms `signInWithOtp` path is unchanged.
- **Band switching for real users with 2+ bands.** Regression: switch between two real bands, verify each band's Dashboard / Setlists / Calendar / Members / Contacts render correct data with no stale content from the other band. This actually improves as a result of Task 10.
- **Band creation via `create_band` RPC.** Regression: create a new real band from Home. Confirms the seed migration didn't break `bands`/`band_members` constraints.
- **Data backup export.** Regression: export a real band. Confirms the new columns on `bands` don't break the JSON round-trip in [lib/features/settings/data_backup_service.dart](lib/features/settings/data_backup_service.dart). New columns should serialize as `is_demo_template: false`, `is_demo_clone: false`, `demo_session_id: null` for real bands.
- **iOS/Android push notification registration** for real users. Regression: real login → verify FCM token registers. Confirms anonymous users' `_registerPushToken` path (even if it no-ops, must not crash).
- **Play Store login screen rendering.** Regression: verify no orphaned tap-count hint UI ever appears (should be removed cleanly).

## Rollout Strategy

1. Author all six migrations + code changes on `feature/interactive-demo-band-experience`. Engineer runs Tier 1 tests locally.
2. QA reviews plan compliance + Tier 1 test results.
3. Tony applies migrations in order to production (his manual action):
   - `20260904120000_demo_bands_schema.sql`
   - `20260904120001_seed_demo_templates.sql`
   - `20260904120002_cleanup_old_demo_account.sql`
   - `20260904120003_provision_demo_session_rpc.sql`
   - `20260904120004_exit_and_heartbeat_demo_session_rpc.sql`
   - `20260904120005_cleanup_demo_sessions_cron.sql` — **pause here if pg_cron cannot be enabled on this Supabase tier**; if paused, defer to a follow-up feature and manually run `cleanup_expired_demo_sessions()` as a bridge.
4. Tony (or QA) runs Tier 2 SQL checks (T2.1 – T2.11) against production or a scratch project post-apply.
5. Deploy Flutter builds:
   - Web: `tools/deploy_web.sh`
   - iOS/Android: `tools/build_mobile_release.sh`, upload to stores
6. Tony updates the Google Play Console **App Access declaration** to instruct reviewers: "On the login screen, tap 'Check Out the Demo Band'. No credentials required." Remove the old email/password. This is an out-of-band Tony action, not code, but is what enabled retiring the DEMO_PASSWORD pipeline in the first place.
7. Monitor `demo_sessions` row count for 24 hours after production deploy. Expected: rows appear as visitors tap the button, disappear within 30 minutes of last heartbeat. Any row surviving > 45 minutes indicates the sweep is not running — investigate.

## Out of Scope

- **Deleting orphaned anonymous `auth.users` rows.** After `demo_sessions` and clone bands are swept, the anonymous `auth.users` row remains (deleting it requires `auth.admin.deleteUser()` via service_role). Rows accumulate at roughly one per demo visit. At typical demo traffic this is negligible for months; when it becomes a concern, a follow-up feature adds a service-role Edge Function called by pg_cron to sweep them.
- **Reworking the entire band-scoped provider surface** to `ref.watch(activeBandIdProvider)`. The `ref.invalidate` fix in `selectBand` is the minimum viable correctness fix; a proper refactor is a separate architecture initiative.
- **Adding tests for the full demo band data pipeline.** Only the entry point (login button), the invalidation fix, and the RPC grant hygiene are tested here. Full seed-data coverage is not proportional to the risk.
- **Windows/Linux platform verification.** Not in the Feature Input's confirmed target list.
- **Updating the Google Play Console App Access declaration.** Tony's manual out-of-band action.
- **Fixing the underlying Supabase branch-verification infrastructure (migration 073).** Referenced only as the reason Tier 2 uses a scratch project instead; not fixed here.
- **IP/trademark clearance for the seed content.** The Feature Input calls this out explicitly as Tony's known risk, not an oversight. Plan reproduces the specified content verbatim.
- **Any change to the init order, PKCE flow, deep-link handling, or magic-link auth.**
- **Cross-band data leakage tests beyond the two concurrent-visitors scenario in T2.9.** More thorough concurrency modeling is future work if traffic warrants it.
- **Documentation cleanup.** Historical `docs/features/*/ARCHITECT_PLAN.md` files mentioning `DEMO_PASSWORD` remain as-is; they're archival records, not executable.
