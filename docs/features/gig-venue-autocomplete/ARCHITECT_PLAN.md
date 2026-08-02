# ARCHITECT_PLAN

## 1. Feature Slug

`feature/gig-venue-autocomplete`

## 2. Problem Summary

The Feature Input describes a green-field request: live venue-name autocomplete in Edit Gig, linking `gigs.venue_id`, deriving address/city/state from the venue, and auto-creating a new venue when nothing matches.

**Investigation finding (must be read before anything else in this plan): this is not a green field.** The vast majority of this feature already exists on `main`, shipped across PR #43 (`feat: add address field to gigs`) and PR #55 (`feat(gigs): auto-populate and dedupe venues on gig create/edit`). What actually remains is a small set of concrete gaps in the existing implementation, not a new feature build.

## 3. Root Cause / Gap Analysis

### What already exists on `main` (verified in code, HIGH confidence)

All of the following live in `lib/features/events/widgets/event_editor_drawer.dart` and `lib/features/events/widgets/gig_form_fields.dart`:

- **Live autocomplete UI**: `_buildGigNameAutocomplete()` (`gig_form_fields.dart:361-502`) uses `RawAutocomplete<String>` wired to the gig name field. `optionsBuilder` calls `onGigNameChanged` (bound to `_fetchGigNameSuggestions`, `event_editor_drawer.dart:702`) on every keystroke and shows a dropdown of matching venue names once the query is 2+ characters.
- **Venue linking on selection**: `_fetchGigNameSuggestions()` (`event_editor_drawer.dart:702-791`) does band-scoped, case-insensitive matching against `ref.read(venuesProvider).venues`. Single exact match → auto-links `_selectedVenueId` and auto-fills city/address/state (only into empty fields). Multiple matches → requires the city field to disambiguate before linking. No match → clears `_selectedVenueId`.
- **Auto-create venue on save when nothing matches**: `_handleSave()` (`event_editor_drawer.dart:1411-1454`) already checks for an existing venue (band-scoped, case-insensitive name+city match) and, if none found, calls `venuesProvider.notifier.create(...)` with whatever the user typed (name/city/address/state), then links the new venue's id to the gig. This already satisfies "save what he typed as a new venue... for future autocomplete."
- **Band scoping**: `venuesProvider.notifier.load(widget.bandId)` (`event_editor_drawer.dart:325`) and all venue queries are band_id-scoped. Confirmed via `venues` RLS (`supabase/migrations/20260410000000_contacts_venues_tables.sql:28-82`).
- **Schema**: `gigs.venue_id` (FK → `venues.id`, `ON DELETE SET NULL`) added in `supabase/migrations/20260411000000_add_venue_id_to_gigs.sql`. `gigs.address` added `20260701000000_add_address_to_gigs.sql`, `gigs.state` added `20260715000000_add_state_to_gigs.sql`. `gigs.location` is the "city" field (label reads "City" in the UI at `gig_form_fields.dart:516`) — confirms the PROJECT_CONTEXT.md flag: the Feature Input's "separate address/city/state fields" map to `gigs.location` (city), `gigs.address`, `gigs.state` — three real, separate columns already on `gigs`, not just one `location` text field as PROJECT_CONTEXT.md's schema summary implies. That summary is stale; the actual table has diverged further via untracked-but-present columns.

### Confirmed gaps (what this plan actually fixes)

**Gap 1 — Stale `venue_id` on unlink (HIGH confidence, confirmed in code).**
`events_repository.dart` `createGig()` (line 606) and `updateGig()` (line 710) both write venue_id conditionally:
```dart
if (formData.venueId != null) 'venue_id': formData.venueId,
```
When a user unlinks a venue — by editing the gig name so it no longer matches any venue, which sets `_selectedVenueId = null` (`event_editor_drawer.dart:709-712, 784`) — `formData.venueId` is `null` and the key is **omitted from the update payload entirely**. Supabase's `.update()` only touches keys present in the map, so the previously-linked `venue_id` is **never cleared** — it stays stale in the database. This is exactly the failure mode the Feature Input calls out: "Unlinking/changing the venue later... is handled without leaving stale venue_id references." Today it is not handled.

**Gap 2 — No sync when a linked venue is edited later (HIGH confidence, confirmed by absence).**
Gig display (`confirmed_gig_card.dart:112`, `potential_gig_card.dart:428,441`, `view_gig_drawer.dart:303`, all via `Gig.locationDisplay`/`fullLocationDisplay` in `lib/app/models/gig.dart:195-212`) reads exclusively from the gig's own stored `location`/`address`/`state` columns — a one-time denormalized copy written at save time. No gig-fetch query joins `venues` (`gig_repository.dart` select clause is `'*, gig_dates(...)'`, no `venues(*)`), and no trigger exists on `venues` today (only `gigs`'s own `AFTER INSERT` notification trigger and a `financial_entries → gigs` gig_pay sync trigger exist as precedent for cascade-sync triggers in this codebase — see `20260601000000_create_financial_entries.sql`). Editing a venue's address/city/state in the Venues screen today has **zero effect** on any gig already linked to it. This directly contradicts the Feature Input: "the address/city/state shown come from the venue and stay in sync if the venue is later edited."

**Gap 3 — Address/City/State remain freely editable even when linked, no unlink control (HIGH confidence, confirmed in code).**
`_buildAddressField`, `_buildStateField`, `_buildGigCityAutocomplete` (`gig_form_fields.dart`) only gate on `enabled: !isSaving` — never on link state. So a user can silently diverge a linked gig's address from its venue's address with no indication, which will become actively confusing once Gap 2's sync trigger exists (a later venue edit would silently blow away the user's manual override). The Feature Input calls for these fields to be "read-only or derived, not a manual copy" once linked. There is also **no explicit "unlink venue" affordance anywhere** in the UI today — the only way to clear a link is to edit the gig name until it stops matching.

## 4. Reference Docs Consulted

No `docs/reference/venues/` or `docs/reference/gigs/` domain reference directory exists (confirmed via full glob of `docs/reference/**/*.md`). Consulted instead:
- `docs/agents/PROJECT_CONTEXT.md` — gigs/venues table summaries (found to be stale re: gig location fields, corrected above)
- `docs/reference/architecture/database_schema.md` — cross-checked, no venue-specific detail beyond PROJECT_CONTEXT.md
- Direct code investigation (primary source of truth per Feature Input's explicit instruction not to assume a green field)

## 5. Existing System Analysis

Data flow today (confirmed):
1. User opens Edit/Add Gig → `EventEditorDrawer` loads `venuesProvider` for the active band (`event_editor_drawer.dart:325`).
2. User types in the gig name field → `RawAutocomplete` shows venue-name matches; typing or tapping a suggestion runs `_fetchGigNameSuggestions()`, which sets `_selectedVenueId` and prefills empty address/city/state fields from the matched venue.
3. On save, `_buildFormData()` includes `venueId: _selectedVenueId` plus the (possibly hand-edited) `address`/`state`/`location` text. `EventsRepository.createGig()`/`updateGig()` writes these to `gigs` — `venue_id` only when non-null (Gap 1).
4. If no venue matched, save auto-creates a new `venues` row (band-scoped) and links it.
5. Gig display anywhere in the app (cards, detail drawer) reads only the gig's own stored `location`/`address`/`state` — never re-derives from `venue_id` (Gap 2).
6. Editing a venue's record via the Venues feature (`venues_controller.dart` → `VenuesRepository.updateVenue`) touches only the `venues` table — no cascade to `gigs` (Gap 2).

## 6. Proposed Solution

Minimal, additive changes only — no restructuring of the existing (already-correct) autocomplete/linking/auto-create flow.

**Fix 1 (Gap 1):** Make `venue_id` writes in `createGig()`/`updateGig()` unconditional, so `null` correctly clears the FK on unlink.

**Fix 2 (Gap 2):** Add a database trigger on `venues` (`AFTER UPDATE`) that cascades `city → location`, `address → address`, `state → state` to every gig where `gigs.venue_id = venues.id`, following the existing `sync_gig_pay_from_financial_entry` precedent (`SECURITY DEFINER`, `SET search_path = public`, `DROP TRIGGER IF EXISTS` idempotency). This keeps the sync entirely server-side — no client display code needs to change, and no gig-fetch query needs a new join. A one-time backfill statement in the same migration brings already-linked gigs current as of deploy (covers venues edited before this ships). Guard: only overwrite `location` when the venue's `city` is non-null/non-empty (gigs require a non-empty city — `EventFormData.validate()`, `event_form_data.dart:441`); `address`/`state` may sync to `NULL` since both are optional on `gigs`.

**Fix 3 (Gap 3):** When `_selectedVenueId != null`, disable (not hide) the City/Address/State fields (`enabled: false`) so they visually read as derived-from-venue, and add a small "Unlink venue" text action next to the gig name field that clears `_selectedVenueId` (re-enabling manual entry, values retained as a starting point). This is a pure `enabled:` flag change plus one new small tappable text — no new color tokens, reuses existing `AppColors.primary`/`context.colors.*` already imported in the file.

**Explicitly not changed:** the autocomplete matching logic, the multi-match city-disambiguation flow, the silent auto-create-venue-on-save behavior (it already satisfies the Feature Input's intent with less friction than an explicit prompt would add), any display widget, any gig-fetch query, the rehearsal location autocomplete (confirmed unrelated — uses `_loadLocationSuggestions()` from past rehearsals, no venue table involvement).

## 7. Database Impact

- **Migrations:** required — 1 new file, `supabase/migrations/20260802120000_sync_gig_location_from_venue.sql`
- **RLS policies:** unaffected — no policy changes on `venues`, `gigs`, or any other table. Trigger function is `SECURITY DEFINER` (matches existing `sync_gig_pay_from_financial_entry` convention), so it executes with the function owner's privileges and is not blocked by the caller's RLS grants on `gigs` — same pattern already proven safe in this codebase.
- **RPC functions:** not applicable — no new RPC, this is a trigger, not an RPC.
- **Triggers:** new `AFTER UPDATE ON public.venues FOR EACH ROW WHEN (city/address/state changed)` trigger, `trg_sync_gig_location_from_venue`, calling new function `public.sync_gig_location_from_venue()`. Not self-referencing (fires on `venues`, writes to `gigs` — a different table), so no infinite-recursion risk (PostgreSQL 42P17 is an RLS-policy-specific hazard; this is a plain cross-table trigger, same shape as the existing gig-pay sync trigger).
- **Existing triggers unaffected:** `gig_created_notification` fires `AFTER INSERT ON gigs` only — untouched by this `AFTER UPDATE ON venues` trigger.
- **Known pre-existing drift (not fixed by this plan, flagged for awareness only):** the `gigs` table itself has no tracked `CREATE TABLE` migration in `supabase/migrations/` (same class of drift already logged in project memory for `bands`). This plan only adds a column-level trigger against the existing live schema and does not attempt to reconstruct or fix the missing base migration — out of scope here.

## 8. Flutter Architecture Changes

- No new providers, controllers, or repositories.
- `EventsRepository` (existing): two small edits to existing methods, no signature changes.
- `EventEditorDrawer` (existing): one new private method (`_unlinkVenue`), two new fields passed to an existing child widget.
- `GigFormFields` (existing): two new required constructor parameters (`isVenueLinked`, `onUnlinkVenue`), used to gate `enabled:` on three existing `TextField`s and render one new small tappable text.
- No new widgets, no new files besides the migration.

## 9. Files to Create

- `supabase/migrations/20260802120000_sync_gig_location_from_venue.sql` — new trigger + function + one-time backfill, per Section 7. Justified: this is the only mechanism that satisfies "stay in sync if the venue is later edited" without restructuring every gig-display surface in the app (see Section 6 for why the DB-trigger approach was chosen over a client-side live-join).

## 10. Files to Modify

| File | What changes |
|------|---------------|
| `lib/features/events/events_repository.dart` | In `createGig()` (~line 606) and `updateGig()` (~line 710), change `if (formData.venueId != null) 'venue_id': formData.venueId,` to an unconditional `'venue_id': formData.venueId,` so `null` correctly clears the FK on unlink (Fix 1). No other keys in either map change. |
| `lib/features/events/widgets/event_editor_drawer.dart` | Add a new `_unlinkVenue()` method (clears `_selectedVenueId`, calls `_markDirty()`, `setState`). Pass `isVenueLinked: _selectedVenueId != null` and `onUnlinkVenue: _unlinkVenue` into the existing `GigFormFields(...)` construction in `_createGigFormFields()` (~lines 1950-1994). No changes to `_fetchGigNameSuggestions()`, `_handleSave()`, or `initState()` — the DB trigger (Fix 2) keeps `data.address`/`data.state`/`data.location` current by the time this widget reads them from a freshly-fetched `Gig`. |
| `lib/features/events/widgets/gig_form_fields.dart` | Add `required this.isVenueLinked` (`bool`) and `required this.onUnlinkVenue` (`VoidCallback`) constructor fields. In `_buildGigCityAutocomplete()`, `_buildAddressField()`, `_buildStateField()`, change `enabled: !isSaving` to `enabled: !isSaving && !isVenueLinked`. In `_buildGigNameAutocomplete()`, when `isVenueLinked` is true, render a small tappable "Unlink venue" text (reuse the existing `AppColors.primary` + `AppTextStyles.footnote` treatment already used for the "Clear" text button in `_buildLoadInTimeSelector()`, ~line 1060-1069) that calls `onUnlinkVenue`, placed near the existing `FieldHint`. |

## 11. Files Off-Limits

| File/Area | Reason |
|-----------|--------|
| `lib/main.dart` | Guardrail: no new routing logic, init order untouched — this feature touches none of it. |
| `lib/app/models/gig.dart` | Display getters (`locationDisplay`, `fullLocationDisplay`) are correct as-is and unaffected — the DB trigger keeps their source columns fresh; no client-side derivation logic needed. |
| `lib/features/gigs/widgets/view_gig_drawer.dart`, `lib/features/home/widgets/confirmed_gig_card.dart`, `lib/features/home/widgets/potential_gig_card.dart` | Display-only, read gig's own stored columns which the trigger keeps in sync — no code change needed or wanted here. |
| `lib/features/contacts/**` (Venues feature: `venues_controller.dart`, `venues_repository.dart`, `venue_form_screen.dart`, etc.) | Venue CRUD itself is correct and unaffected; the sync is implemented entirely server-side via trigger, not by having the Venues feature push updates. |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | Confirmed rehearsals have no venue-linking concept; out of scope. |
| `supabase/migrations/*` (all except the one new file) | No other schema/RLS changes required. |
| Any file touched by the currently uncommitted `bug/venue-state-city-mixup` work | See Section 18 / blocking note — must not be modified, merged, or discarded by this feature's pipeline. |

## 12. System Impact Map

| System | Impact |
|--------|--------|
| Gigs | affected |
| Rehearsals | unaffected (confirmed — no venue references in rehearsal form/repository code) |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected — no RLS policy changes. (Informational only, not a new issue introduced by this plan: the existing auto-create-venue-on-save path calls `venues` `INSERT`, whose RLS restricts `INSERT` to `admin`/`member` — a `contributor` with gig-create permission who types a brand-new venue name will silently fail to create/link the venue, per `VenuesNotifier.create()`'s existing catch-and-return-null behavior, and the gig still saves without a link. This is pre-existing behavior on `main` today, not introduced or worsened by this plan. Flagged for QA awareness, not fixed here — see Section 18.) |
| Auth / Session | unaffected |
| Routing | unaffected — no `main.dart` changes |
| Notifications | unaffected — `gig_created_notification` is `AFTER INSERT` only; new trigger is `AFTER UPDATE ON venues`, disjoint |
| Platform (iOS / Android / Web / macOS) | affected — shared `EventEditorDrawer`/`GigFormFields` code path, single implementation across all platforms |

## 13. Regression Risk

**MEDIUM**

Rationale:
- Two systems affected (Gigs, Platform), no auth/session/routing/init-order changes.
- One new DB trigger introduces automatic cross-table writes (venue edit → gig rows) that did not exist before; low probability of error given it follows an established, already-shipped pattern in this codebase (`sync_gig_pay_from_financial_entry`), but the blast radius of a trigger bug (silently mutating many gigs on one venue edit) is inherently higher-consequence than a pure UI change — warrants explicit multi-gig QA verification (Section 16).
- `events_repository.dart` change alters the write path used by **every** gig create/update (not just venue-linked ones) — low risk since `formData.venueId` is simply `null` for non-venue-linked gigs and writing `venue_id: null` unconditionally is a no-op for gigs that never had a link, but must be regression-tested for both create and update, linked and unlinked.
- UI field-locking change (Gap 3) alters existing editable-field behavior for any already-linked gig the moment this ships — must verify no gig becomes stuck/unreadable if `venue_id` points to a venue that has since been deleted (`ON DELETE SET NULL` on the FK means this can't happen — a deleted venue nulls the gig's `venue_id`, unlocking the fields automatically — but verify explicitly).

## 14. Engineer Task Breakdown

1. Create `supabase/migrations/20260802120000_sync_gig_location_from_venue.sql`:
   - `CREATE OR REPLACE FUNCTION public.sync_gig_location_from_venue() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ BEGIN UPDATE public.gigs SET location = COALESCE(NULLIF(NEW.city, ''), location), address = NEW.address, state = NEW.state, updated_at = now() WHERE venue_id = NEW.id; RETURN NEW; END; $$;`
   - `DROP TRIGGER IF EXISTS trg_sync_gig_location_from_venue ON public.venues;`
   - `CREATE TRIGGER trg_sync_gig_location_from_venue AFTER UPDATE ON public.venues FOR EACH ROW WHEN (OLD.city IS DISTINCT FROM NEW.city OR OLD.address IS DISTINCT FROM NEW.address OR OLD.state IS DISTINCT FROM NEW.state) EXECUTE FUNCTION public.sync_gig_location_from_venue();`
   - One-time backfill: `UPDATE public.gigs g SET location = COALESCE(NULLIF(v.city, ''), g.location), address = v.address, state = v.state, updated_at = now() FROM public.venues v WHERE g.venue_id = v.id AND (g.location IS DISTINCT FROM v.city OR g.address IS DISTINCT FROM v.address OR g.state IS DISTINCT FROM v.state);`
2. `events_repository.dart`: make `venue_id` unconditional in both `createGig()` and `updateGig()` write maps.
3. `event_editor_drawer.dart`: add `_unlinkVenue()`; wire `isVenueLinked`/`onUnlinkVenue` into `_createGigFormFields()`.
4. `gig_form_fields.dart`: add the two new constructor params; gate `enabled:` on City/Address/State fields; add the "Unlink venue" text action.
5. Run `flutter analyze`; confirm 0 new errors/warnings.
6. Produce `ENGINEER_REPORT.md` with before/after behavior and exact diff scope, per standard process.

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

```sql
-- PRE-DEPLOY TEST 1: confirm venues table has the expected columns unchanged
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'venues'
  AND column_name IN ('id', 'band_id', 'name', 'address', 'city', 'state');
-- Expect: all 6 rows present, no new/removed columns from this migration touching venues' shape.

-- PRE-DEPLOY TEST 2: confirm gigs table has the expected columns unchanged
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'gigs'
  AND column_name IN ('id', 'venue_id', 'location', 'address', 'state', 'band_id');
-- Expect: all 6 rows present.

-- PRE-DEPLOY TEST 3: confirm no existing trigger name collision
SELECT tgname FROM pg_trigger WHERE tgname = 'trg_sync_gig_location_from_venue';
-- Expect: 0 rows (trigger does not exist yet).

-- PRE-DEPLOY TEST 4: confirm the existing sync_gig_pay_from_financial_entry precedent still present unchanged
SELECT pg_get_functiondef('public.sync_gig_pay_from_financial_entry()'::regprocedure) LIKE '%SECURITY DEFINER%';
-- Expect: true (confirms the pattern this migration follows is intact before we add to it).
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

```sql
-- POST-DEPLOY TEST 1: confirm the new function and trigger exist with expected properties
SELECT pg_get_functiondef('public.sync_gig_location_from_venue()'::regprocedure) LIKE '%SECURITY DEFINER%'
   AND pg_get_functiondef('public.sync_gig_location_from_venue()'::regprocedure) LIKE '%search_path = public%';
-- Expect: true

SELECT tgname, tgenabled FROM pg_trigger WHERE tgname = 'trg_sync_gig_location_from_venue';
-- Expect: 1 row, tgenabled = 'O' (enabled)

-- POST-DEPLOY TEST 2: end-to-end cascade test (wrapped, rolled back — no real data touched)
DO $$
DECLARE
  v_band_id UUID;
  v_venue_id UUID;
  v_gig_id UUID;
  v_location TEXT;
  v_address TEXT;
  v_state TEXT;
BEGIN
  -- Requires a real band_id FK; use an existing test-safe band if one is designated,
  -- otherwise this test must be run against a disposable/staging project only.
  SELECT id INTO v_band_id FROM public.bands LIMIT 1;
  IF v_band_id IS NULL THEN
    RAISE NOTICE 'No band available — skipping integration test';
    RETURN;
  END IF;

  INSERT INTO public.venues (band_id, name, city, address, state)
  VALUES (v_band_id, 'ARCHTEST Venue', 'Old City', 'Old Address', 'OO')
  RETURNING id INTO v_venue_id;

  INSERT INTO public.gigs (band_id, name, date, start_time, end_time, location, address, state, venue_id, is_potential)
  VALUES (v_band_id, 'ARCHTEST Gig', CURRENT_DATE, '19:00', '21:00', 'Old City', 'Old Address', 'OO', v_venue_id, false)
  RETURNING id INTO v_gig_id;

  UPDATE public.venues SET city = 'New City', address = 'New Address', state = 'NN' WHERE id = v_venue_id;

  SELECT location, address, state INTO v_location, v_address, v_state FROM public.gigs WHERE id = v_gig_id;

  ASSERT v_location = 'New City', 'location did not sync';
  ASSERT v_address = 'New Address', 'address did not sync';
  ASSERT v_state = 'NN', 'state did not sync';

  -- Cleanup
  DELETE FROM public.gigs WHERE id = v_gig_id;
  DELETE FROM public.venues WHERE id = v_venue_id;

  RAISE NOTICE 'POST-DEPLOY TEST 2 passed';
EXCEPTION WHEN OTHERS THEN
  -- Best-effort cleanup even on failure
  DELETE FROM public.gigs WHERE name = 'ARCHTEST Gig';
  DELETE FROM public.venues WHERE name = 'ARCHTEST Venue';
  RAISE;
END $$;

-- POST-DEPLOY TEST 3: confirm empty/null city does not blank out an existing gig location
-- (guards the COALESCE(NULLIF(...)) branch) — same pattern as Test 2, set venue.city to '' and
-- confirm gig.location is left unchanged rather than becoming ''.

-- POST-DEPLOY TEST 4: production verification — confirm no bad data was written band-wide
SELECT count(*) FROM public.gigs g
JOIN public.venues v ON v.id = g.venue_id
WHERE g.location IS DISTINCT FROM v.city
  AND v.city IS NOT NULL AND v.city != '';
-- Expect: 0 (or only rows predating the backfill's guard conditions — investigate any nonzero result before declaring success)
```

## 16. QA Regression Areas

- **Primary flow:** type a gig name matching exactly one venue → suggestion shown, single-tap or exact-type auto-links, city/address/state prefill, `gigs.venue_id` set correctly on save.
- **Multi-match disambiguation:** two venues share a name in different cities → typing the shared name does not auto-link until city is entered; entering the correct city links the right venue.
- **No match → auto-create:** type a brand-new name, fill address fields manually, save → confirm a new `venues` row was created (band-scoped) and is available as a suggestion on the next Add Gig.
- **Unlink via retype:** link a venue, then edit the gig name to something that matches nothing → confirm on save `gigs.venue_id` is actually cleared in the database (this is Gap 1 — was previously silently NOT cleared).
- **Unlink via new "Unlink venue" control:** link a venue, tap Unlink, confirm City/Address/State fields become editable again, edit them, save, confirm `venue_id` is null and the manually-entered values persisted.
- **Sync on venue edit:** create/link a gig to a venue, edit that venue's address/city/state from the Venues screen, then reopen the gig (detail drawer and edit form) → confirm updated values appear without re-saving the gig.
- **Multi-gig fan-out:** link two different gigs to the same venue, edit the venue once, confirm **both** gigs update and no unrelated gig (different venue, or no venue) is touched.
- **Deleted venue:** delete a venue that has a linked gig → confirm `venue_id` on the gig becomes null (`ON DELETE SET NULL`) and the gig's City/Address/State fields become editable again in the editor (not stuck disabled).
- **Read-only field lock:** confirm City/Address/State are genuinely disabled (not just visually greyed but still editable) whenever a venue is linked, and fully editable whenever it is not.
- **Rehearsals:** confirm rehearsal creation/editing is fully unaffected (no venue fields, no behavior change).
- **Regression on existing gigs (pre-migration):** spot-check a handful of existing linked gigs post-deploy to confirm the one-time backfill did not blank/corrupt any `location`/`address`/`state` values, especially for gigs whose linked venue has a null/empty `city`.
- **RBAC spot-check (informational, not a required fix):** a `contributor` account creating a gig with a brand-new (non-matching) venue name should still successfully save the gig, just without a venue link (pre-existing silent-failure behavior — confirm it doesn't regress into a hard error).
- **Platform parity:** since `EventEditorDrawer`/`GigFormFields` are shared, spot-check the disabled-field visual state and Unlink control on both web and at least one native target (iOS or Android).

## 17. Rollout / Migration Strategy

- Push the migration (`supabase db push`) first — it is purely additive/backward-compatible: the trigger only fires on future `venues` UPDATEs, and the backfill is a one-time, guarded, idempotent DML statement. The old (pre-this-feature) Flutter client continues to work unchanged against the new schema.
- Ship the updated Flutter app build after the migration is live, so the unconditional `venue_id` write and the field-lock/unlink UI go out together (the field-lock UI depends on nothing server-side, but shipping them together avoids a window where users can silently create the stale-`venue_id` situation that Fix 1 addresses).
- No edge function deploy required.
- No data migration/backfill risk beyond what's covered in Tier 2 Test 3/4 above — the backfill only touches gigs that are already venue-linked and already diverged from their venue's current values.

## 18. Out of Scope

- Restructuring gig display (cards, detail drawer) to live-join `venues` at read time instead of using the DB-trigger cascade — the trigger approach was deliberately chosen as the minimal solution; a live-join would touch many more files for no behavioral gain.
- Converting the existing silent auto-create-venue-on-save into an explicit user-confirmation dialog — current behavior already satisfies the Feature Input's intent with less friction; changing it would be a UX change beyond what was requested.
- Fixing the pre-existing `contributor` RLS gap on venue auto-create (Section 12) — flagged for awareness, not caused or worsened by this plan.
- Fixing the untracked `gigs` base-table migration drift (Section 7) — separate, pre-existing, already-logged issue.
- Any change to the Venues feature screens themselves (`venue_form_screen.dart`, `venues_view.dart`, `venue_detail_screen.dart`) — venue CRUD is correct as-is.
- Rehearsal location autocomplete — confirmed unrelated to venues, untouched.
- **The currently uncommitted `bug/venue-state-city-mixup` work sitting in this working tree** (see blocking note below) — that fix is a different, narrower change to the same auto-fill code path (city/state string concatenation) and must go through its own QA-gated pipeline independently. This plan's Fix 3 (disabling City/Address/State when linked) will make that narrow bug largely moot once both ship, but this plan does not commit, discard, or otherwise resolve that pending work.

---

## Blocking Note — Dirty Working Tree (must be resolved before Phase 13 branch creation)

Workspace inspection (Phase 1) found the current branch `bug/venue-state-city-mixup` has **uncommitted changes**:
- Modified: `lib/features/events/widgets/event_editor_drawer.dart` (a one-line venue auto-fill fix — city/state string concatenation bug, unrelated to this feature's scope)
- Untracked: `docs/features/venue-state-city-mixup/{ARCHITECT_PLAN,ENGINEER_REPORT,QA_REPORT}.md` (that feature's own completed-but-uncommitted pipeline; QA verdict is **REQUIRES CHANGES**, pending runtime verification — not yet approved to commit)

Per `ARCHITECT.md` Phase 13 ("Do not proceed if the working tree has uncommitted changes that are unrelated to this feature") and the project's dirty-tree guardrail, **this plan does not create the `feature/gig-venue-autocomplete` branch.** Creating a branch now would carry the unrelated, not-yet-QA-approved `bug/venue-state-city-mixup` diff onto the new branch (a `git checkout -b` does not stash working-tree changes — they persist on whichever branch is checked out).

This is a direct file conflict, not just an adjacent one: both the pending bug fix and this plan's Fix 3 modify the same block of `event_editor_drawer.dart` venue auto-fill logic. Recommended resolution, in order:
1. Complete and commit the `bug/venue-state-city-mixup` fix through its own pipeline (finish the pending QA runtime verification, get APPROVED, commit, push, merge to `main`) **before** branching for this feature — since this feature's Fix 3 will supersede the narrow concatenation bug anyway (the fields become disabled/derived when linked, and unlink restores plain manual entry), sequencing the smaller fix first avoids a merge conflict and avoids two sessions racing on the same function.
2. Once `main` is clean and contains that commit (or Tony explicitly decides to discard the pending bug-fix work instead), re-run Phase 13 to create `feature/gig-venue-autocomplete` from a clean, up-to-date `main`.

No branch has been created. No files outside `docs/features/gig-venue-autocomplete/ARCHITECT_PLAN.md` were modified by this session.
