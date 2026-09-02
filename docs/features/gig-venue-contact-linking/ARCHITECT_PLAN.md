# ARCHITECT_PLAN.md

## Feature Slug

`feature/gig-venue-contact-linking`

## Feature Title

Link band-wide Contacts to Gigs (autocomplete + inline create)

## Problem Summary

Gigs currently have no persistence model, form state, or detail UI for linking shared band contacts. The app already has a band-scoped `contacts` table and reusable contact detail/create surfaces, but gig create/edit only handles venue, city, dates, setlist, pay, and notes, and gig reads only hydrate `gig_dates`. The result is that users cannot attach shared contacts to gigs, cannot create a missing shared contact inline from the gig flow, and cannot open linked contact details from `ViewGigDrawer`.

## Root Cause (+confidence)

Primary root cause: gig-contact relationships do not exist anywhere in the current stack.

- Database: there is no `gig_contacts` join table and no gig-contact sync RPC.
- Domain model: `Gig` has no `contacts` field, and `EventFormData.fromGig()` has no `contactIds` state to round-trip edit data.
- Repository layer: `GigRepository` and `EventsRepository` only select `gig_dates` joins and never persist contact links after gig insert/update.
- UI layer: `EventEditorDrawer` preloads members and venues, but not contacts, and `GigFormFields` has no repeatable contacts section.

Confidence: `HIGH`

## Existing System Analysis

- Shared contacts already exist and are band-scoped. `ContactsRepository.fetchContacts()` reads `contacts` ordered by name with caching, and `createContact()` already supports the required fields including `company`.
- `Contact` already models `name`, `title`, `company`, `phone`, `email`, and `notes`, so the create-from-gig dialog can reuse the same data shape as `ContactFormScreen` without changing the contact model.
- `Gig` currently parses only scalar gig fields plus `gig_dates`; `GigRepository` uses a private `_gigSelectClause` that only joins `gig_dates`, and `EventsRepository.createGig()` / `updateGig()` refetch the same limited select.
- `EventFormData.fromGig()` already round-trips gig edit state such as additional dates, load-in time, setlist, venue, address, and pay. Contacts are the missing persisted edit field.
- `GigFormFields` already contains the relevant `FAutocomplete.text` pattern in `_buildGigNameAutocomplete()`, and `EventEditorDrawer` already owns repeatable form state for `additionalDates`, making it the correct place to own repeatable contact row draft state as well.
- `ViewGigDrawer` currently renders tappable `_DetailRow`s for setlist and notes, which is the right existing interaction pattern for opening `ContactDetailDrawer` without changing routing or startup behavior.
- Venue contact persistence is a separate legacy system (`venue_contacts`, `Venue.contacts`, venue form/detail screens). It is explicitly out of scope and must remain unchanged.

## Proposed Solution

Add a gig-only shared-contact linking path built on a dedicated join table and one idempotent sync RPC, then extend the existing gig form and gig detail drawer to use band-wide contacts only.

### Data and persistence

- Add `public.gig_contacts` with `gig_id`, `contact_id`, `band_id`, `created_at`, `UNIQUE (gig_id, contact_id)`, and foreign keys cascading on delete.
- Enable RLS on `gig_contacts` and follow the current hardened policy style using `(select auth.uid())` rather than raw `auth.uid()` calls.
- Add `sync_gig_contacts(p_gig_id uuid, p_band_id uuid, p_contact_ids uuid[])` as `SECURITY DEFINER` with `SET search_path = public`.
- The RPC must validate: caller is an active member of `p_band_id`, the target gig belongs to `p_band_id`, every `contact_id` belongs to `p_band_id`, and duplicate input IDs collapse deterministically before diffing.
- The RPC owns ordering/data integrity for the submission flow: delete stale join rows, insert missing ones, and leave identical input unchanged. This keeps sync logic server-side and makes repeated submits idempotent.
- Revoke default execute access from `PUBLIC, anon` and explicitly grant execute to `authenticated`. Verification must use `has_function_privilege(role, oid, 'EXECUTE')`.

### Gig read/write flow

- Extend `Gig` with `contacts: List<Contact>` and parse `gig_contacts(contact_id, contacts(*))` using the same nested-join style that `Venue.fromJson()` already uses for `venue_contacts`.
- Update `GigRepository._gigSelectClause` and the refetch queries inside `EventsRepository.createGig()` / `updateGig()` so every gig load path hydrates contacts consistently.
- Extend `EventFormData` with `List<String> contactIds`, wire it through the constructor, `copyWith()`, and `fromGig()`.
- After `createGig()` inserts the gig row and after `updateGig()` updates it, call `sync_gig_contacts()` before the final refetch. Keep `_createGigDates()` / `_syncGigDates()` behavior unchanged.

### Gig form UX

- Add a `Contacts` section to the gig flow in `EventEditorDrawer` + `GigFormFields` only.
- Use the existing `FAutocomplete.text` interaction pattern from `_buildGigNameAutocomplete()` for each contact row.
- Support unbounded rows with the same user-facing pattern as `additionalDates`: existing rows plus an `Add another` control.
- Autocomplete suggestions must come only from the band's shared `contacts` dataset loaded through the existing contacts stack. No band-member names or venue contacts are valid suggestion sources.
- A row is only valid when it resolves to an existing `contact_id` or the user explicitly confirms the create-contact dialog. Free text never persists by itself.
- On blur/submit of an unmatched non-empty name, show the explicit dialog: `"<name>" is not in your contacts list` plus fields for Title, Company, Phone, Email, Notes. Confirm creates the contact and stores the returned `contact_id`; cancel clears or reverts that row.
- Keep any typed-name / resolved-id pairing as local drawer UI state rather than expanding shared domain models beyond `EventFormData.contactIds`.

### Gig detail UX

- Add a `Contacts` section to `ViewGigDrawer`.
- Render one `_DetailRow(showChevron: true, onTap: ...)` per linked contact.
- Primary text is the contact name; secondary text should show the best available company/title summary.
- Tapping a row opens `ContactDetailDrawer` and dismissing that drawer returns to the still-open `ViewGigDrawer`.

## Database Impact

Migration required: `yes`

- New table: `public.gig_contacts`
- New RPC: `public.sync_gig_contacts(uuid, uuid, uuid[])`
- RLS changes: `gig_contacts` policies only
- Triggers: `n/a`
- Backfill: `n/a`
- Edge Functions: `n/a`

The migration must follow the hardened conventions established in the 2026-08-14 through 2026-08-25 security migrations:

- use `(select auth.uid())` in policies
- `SET search_path = public` on the `SECURITY DEFINER` RPC
- `REVOKE ALL ... FROM PUBLIC, anon`
- `GRANT EXECUTE ... TO authenticated`
- avoid self-referential RLS policy queries on the table being protected

## Flutter Architecture Changes

- Reuse the existing contacts data path; do not add a new repository or provider family.
- Keep contact-row draft state local to `EventEditorDrawer`, with `GigFormFields` rendering that state and emitting row-level actions.
- Extend existing gig model/form/repository surfaces only; do not introduce a new controller or a parallel gig-contact feature module.
- `ContactDetailDrawer` remains reusable as-is for the gig detail tap-through flow.
- App init order, routing, band switching mechanics, and platform-conditional Firebase / deep-link behavior remain unchanged.

## Files to Create

- `supabase/migrations/<timestamp>_add_gig_contacts_and_sync_rpc.sql`

## Files to Modify

- `lib/app/models/gig.dart`
  Add `contacts: List<Contact>` and parse nested `gig_contacts(...contacts(*))` rows.
- `lib/features/gigs/gig_repository.dart`
  Extend `_gigSelectClause` to join linked contacts on every gig fetch.
- `lib/features/events/events_repository.dart`
  Call `sync_gig_contacts()` after gig insert/update and refetch gigs with the expanded select clause.
- `lib/features/events/models/event_form_data.dart`
  Add `contactIds`, propagate through constructor, `copyWith()`, and `fromGig()`.
- `lib/features/events/widgets/event_editor_drawer.dart`
  Load band contacts for the gig form, own repeatable contact draft state, enforce unresolved-row resolution before save, and handle the explicit create-contact dialog.
- `lib/features/events/widgets/gig_form_fields.dart`
  Render the repeatable contacts section using the existing autocomplete pattern.
- `lib/features/gigs/widgets/view_gig_drawer.dart`
  Add tappable contact rows that open `ContactDetailDrawer`.
- `test/app/models/gig_test.dart`
  Extend the existing gig model tests with contact parsing coverage.

## Files Off-Limits

- `lib/features/contacts/models/venue.dart`
  Venue contact hydration is explicitly out of scope.
- `lib/features/contacts/venues_repository.dart`
  No venue query or save-path changes.
- `lib/features/contacts/widgets/venue_form_screen.dart`
  No venue form UX changes.
- `lib/features/contacts/widgets/venue_detail_screen.dart`
  No venue detail drawer changes.
- `lib/features/contacts/widgets/venue_contact_block.dart`
  Venue contact widget remains untouched.
- `supabase/migrations/20260410000000_contacts_venues_tables.sql`
  Existing venue/contact base migration is reference only; do not edit historical migrations.
- `lib/features/members/**`
  Members must not appear in gig contact autocomplete or gig contact UI.
- `lib/main.dart`
  Init order and platform bootstrap are unrelated and guarded.
- `android/**`, `ios/**`, `macos/**`, `web/**`
  No platform-native changes are needed.

## Change Budget

- Expected net line delta per file:
  - `lib/app/models/gig.dart`: `+17 to +26`
  - `lib/features/gigs/gig_repository.dart`: `+18 to +28`
  - `lib/features/events/events_repository.dart`: `+34 to +51 / -3 to -5`
  - `lib/features/events/models/event_form_data.dart`: `+6 to +9`
  - `lib/features/events/widgets/event_editor_drawer.dart`: `+145 to +220`
  - `lib/features/events/widgets/gig_form_fields.dart`: `+420 to +520 / -10 to -25`
  - `lib/features/gigs/widgets/view_gig_drawer.dart`: `+85 to +130 / -7 to -12`
  - `test/app/models/gig_test.dart`: `+46 to +69`
  - `supabase/migrations/<timestamp>_add_gig_contacts_and_sync_rpc.sql`: `+116 to +174`
- Expected new files: `1`
- Expected new public classes/methods: `0 to 1 small public UI helper at most; prefer private/local state instead`
- Expected new dependencies: `0`
- Budget revision note: the original estimates for `lib/features/events/widgets/event_editor_drawer.dart` and `lib/features/events/widgets/gig_form_fields.dart` were too optimistic. The implemented shape placed the contact state management (`GigContactRowsController`) and the inline create dialog in `gig_form_fields.dart` rather than `event_editor_drawer.dart` to keep the drawer delta within bounds, so both file budgets are revised here to match the actual delivered code with a small buffer.

## System Impact Map

- Gigs: `affected`
- Rehearsals: `unaffected`
- Setlists: `unaffected`
- Members: `unaffected` for data model and UI; explicit exclusion from autocomplete source
- Contacts: `affected` through reuse of existing shared contacts CRUD/detail surfaces
- Auth / Session: `unaffected`
- Routing: `unaffected`
- Notifications: `unaffected`
- Platforms (iOS / Android / macOS / Web): `affected via shared Flutter + Supabase code only; native/web init behavior unchanged`

## Regression Risk

`MEDIUM`

Reasoning: the change touches shared gig persistence, model hydration, and RLS/RPC authorization, but the scope is materially smaller than the prior plan because venues and band-member contact blending are excluded. The main regression risk is incomplete sync between `EventFormData.contactIds`, the new RPC, and the expanded gig selects.

## Engineer Task Breakdown

1. Add one new Supabase migration that creates `gig_contacts`, enables RLS, defines the required policies, creates `sync_gig_contacts(...)`, revokes `PUBLIC, anon`, and grants execute to `authenticated`.
2. Extend `Gig` parsing and `GigRepository` select clauses to hydrate linked `Contact` rows from `gig_contacts(contact_id, contacts(*))`.
3. Extend `EventFormData` with `contactIds` and populate it in `fromGig()`.
4. Update `EventsRepository.createGig()` and `updateGig()` to call `sync_gig_contacts()` after the gig row exists and before the final refetch.
5. In `EventEditorDrawer`, load the band's shared contacts for gig editing, keep local repeatable contact draft state, and block save when any contact row is unresolved.
6. In `GigFormFields`, add the repeatable `Contacts` section with `FAutocomplete.text` rows and an `Add another` control matching the existing additional-dates UX pattern.
7. Implement the explicit `"<name>" is not in your contacts list` dialog using the same field set as `ContactFormScreen`; confirm creates a shared contact and stores its id, cancel clears or reverts the row.
8. Update `ViewGigDrawer` to show one tappable row per linked contact and open `ContactDetailDrawer` without closing the parent gig drawer.
9. Extend the existing gig model tests for contact parsing and add the narrowest existing widget/repository coverage only if needed for the unresolved-row save guard or RPC call sequencing.

## Verification Plan

### Tier 1 pre-deploy tests

These checks must pass before applying the new migration and must not call `sync_gig_contacts()`.

```sql
-- Confirm the shared contacts table has the fields the inline-create dialog needs.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'contacts'
  AND column_name IN ('name', 'title', 'company', 'phone', 'email', 'notes')
ORDER BY column_name;

-- Confirm gig_contacts does not already exist in the target environment.
SELECT to_regclass('public.gig_contacts') AS gig_contacts_table;

-- Confirm there is no pre-existing sync_gig_contacts RPC signature clash.
SELECT p.oid::regprocedure AS function_signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'sync_gig_contacts';

-- Inspect the current gig table columns that the refetch path already depends on.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'gigs'
  AND column_name IN ('id', 'band_id', 'name', 'date', 'start_time', 'end_time');
```

Tier 1 Flutter tests:

- extend `test/app/models/gig_test.dart` with nested join parsing coverage for `gig_contacts -> contacts(*)`
- if a focused widget test is added, keep it in the nearest existing events widget test group and limit it to the unresolved-contact save guard or add/remove row behavior

### Tier 2 post-deploy tests

Schema and privilege verification:

```sql
-- Confirm the table now exists.
SELECT to_regclass('public.gig_contacts') AS gig_contacts_table;

-- Confirm the RPC exists with the expected signature.
SELECT p.oid::regprocedure AS function_signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'sync_gig_contacts';

-- Confirm authenticated can execute and anon/public cannot rely on default grants.
WITH target_fn AS (
  SELECT p.oid
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname = 'sync_gig_contacts'
)
SELECT
  has_function_privilege('authenticated', (SELECT oid FROM target_fn), 'EXECUTE') AS authenticated_can_execute,
  has_function_privilege('anon', (SELECT oid FROM target_fn), 'EXECUTE') AS anon_can_execute,
  has_function_privilege('public', (SELECT oid FROM target_fn), 'EXECUTE') AS public_can_execute;
```

Behavior verification in a non-production environment using a throwaway authenticated band member and throwaway gig/contact rows:

1. Create one test band, one active member session, one gig, and two shared contacts for that same band.
2. Call `sync_gig_contacts()` with both contact ids and verify exactly two `gig_contacts` rows exist.
3. Call `sync_gig_contacts()` again with the same ids in the same order and verify row count and linked ids are unchanged.
4. Call `sync_gig_contacts()` with one id removed and verify only the stale join row is deleted.
5. Call `sync_gig_contacts()` with a contact from another band and verify the function rejects it.
6. Roll back the transaction or explicitly delete the throwaway band/gig/contact rows during cleanup.

Post-deploy UI verification on all supported platforms:

1. Create a gig with one existing shared contact and verify the saved gig reopens with that contact still selected.
2. Create a gig with a typed unmatched name, confirm the dialog, create the new shared contact, and verify both the new contact record and the gig link exist after save.
3. Repeat the unmatched-name flow but cancel the dialog and verify the unresolved row is cleared/reverted and no contact is created.
4. Remove a linked contact from an existing gig and verify the underlying `contacts` row still exists in the Contacts feature.
5. Open `ViewGigDrawer`, tap each contact row, and verify `ContactDetailDrawer` opens and dismisses back to the still-open gig drawer.

Submission-flow idempotence check:

- Save the same gig twice without changing its resolved contact ids and verify the second save produces no duplicate `gig_contacts` rows and re-parses into the same `EventFormData.contactIds` / `Gig.contacts` state.

## QA Regression Areas

- Gig create flow with zero contacts, one contact, and multiple contacts
- Gig edit flow round-trip for pre-existing linked contacts
- Unmatched-name dialog confirm vs cancel behavior
- Potential gigs with additional dates plus contacts in the same save
- Gig save/update paths with setlist, venue, pay, address, and notes still behaving unchanged
- `ViewGigDrawer` navigation stack behavior when opening and dismissing `ContactDetailDrawer`
- Contacts cache refresh behavior after inline create
- Cross-band rejection for contact ids at the RPC layer

## Rollout Strategy

- Ship as one migration plus one shared Flutter release.
- Apply the migration before releasing the client build that calls `sync_gig_contacts()`.
- No data backfill is required because this is a net-new gig capability.
- If rollback is required, first roll back the client or gate the UI path, then remove the migration in the normal rollback process; do not leave a client build calling a missing RPC.

## Out of Scope

- Venue contact migration, venue contact linking, or any change to venue models/screens/repositories/widgets
- Using band members as contact suggestions or as gig contact link targets
- Any change to contact permissions beyond existing shared-contact CRUD behavior
- Rehearsal contact linking
- Startup/init-order, routing, native platform config, or new dependencies
