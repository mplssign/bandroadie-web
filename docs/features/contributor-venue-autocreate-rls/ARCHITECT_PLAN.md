# ARCHITECT_PLAN

## 1. Feature Slug

`bug/contributor-venue-autocreate-rls`

## 2. Problem Summary

Contributors who can create gigs cannot auto-create a new venue during gig save when the typed venue does not already exist. The gig still saves, but `gigs.venue_id` remains null and no new `venues` row is created. The user sees a successful save with no indication venue creation failed.

This is a permissions-boundary mismatch: gig creation allows contributors (subject to contributor sub-permissions), while direct `venues` INSERT is restricted to admin/member.

## 3. Root Cause

### Primary failure

Venue auto-create in gig save uses direct table insert through `VenuesRepository.createVenue()`:

- `EventEditorDrawer._handleSave()` calls `venuesProvider.notifier.create(...)` when no venue match exists.
- `VenuesRepository.createVenue()` performs `supabase.from('venues').insert(...)`.

`venues` RLS explicitly allows INSERT only for `admin`/`member`, so contributor inserts are denied.

### Silent-failure amplifier

`VenuesNotifier.create()` catches repository errors and returns `null` instead of surfacing the failure. `EventEditorDrawer._handleSave()` treats `null` as "no venue created" and proceeds to create/update the gig anyway.

### Confidence

`HIGH` (confirmed directly in code and migration policies).

## 4. Reference Docs Consulted

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/agents/PROJECT_CONTEXT.md`
- `docs/features/gig-venue-autocomplete/ARCHITECT_PLAN.md` (Section 12 note about this known gap)

## 5. Existing System Analysis

Current save path for gigs:

1. User enters gig data in `EventEditorDrawer`.
2. If no venue match is found, `_handleSave()` attempts venue auto-create via `venuesProvider.notifier.create(...)`.
3. `VenuesRepository.createVenue()` executes direct `INSERT INTO venues` through Supabase client.
4. For contributor users, `venues` RLS denies insert because policy allows only `admin`/`member`.
5. Exception is swallowed in `VenuesNotifier.create()` and converted to `null`.
6. `_handleSave()` continues and saves gig without `venue_id` link.

Observed/confirmed failure mode mapping:

- Trigger not called: not applicable.
- Recipient resolution fails: not applicable.
- Preference gate blocks send: not applicable.
- Token missing/stale: not applicable.
- Backend error hidden from UI: yes (error is swallowed and save continues).
- RLS blocks required operation: yes (root authorization failure).

## 6. Proposed Solution

### Minimal-solution principle

Do not loosen direct `venues` table RLS for contributors. Keep venue-management permissions unchanged. Add one narrowly scoped SECURITY DEFINER RPC used only by gig-save auto-create flow.

### Design

1. Add new RPC `public.create_venue_for_gig_save(...)`:
   - `SECURITY DEFINER`
   - `SET search_path = public`
   - Validates caller is active band member in target band.
   - Authorizes if either:
     - role in (`admin`, `member`), or
     - role is `contributor` and contributor sub-permissions allow this gig type.
   - Use same permission semantics as gig create policy:
     - contributor must have `can_create_gigs = true`
     - if `can_create_potential_gigs_only = true`, only allow when `p_is_potential = true`
   - Inserts venue row (`name`, `city`, `address`, `state`) and returns inserted row.
   - Optionally dedupes by same band + case-insensitive `name` + null-safe `city` to avoid race duplicates in this specific flow.

2. Add repository method for this RPC (do not replace generic venue CRUD method):
   - New method in `VenuesRepository`, e.g. `createVenueForGigSave(...)`, calling `supabase.rpc(...)`.
   - Parse returned row into `Venue`.

3. Add notifier method dedicated to gig-save path:
   - New `VenuesNotifier.createForGigSave(...)` that calls repository RPC method.
   - Reload venue cache after success.
   - Do not swallow errors; rethrow so caller can surface save failure.

4. Update gig save flow:
   - In `EventEditorDrawer._handleSave()`, replace `venuesProvider.notifier.create(...)` with `createForGigSave(...)`.
   - If RPC fails, allow outer save catch to show error and stop save instead of silently continuing without link.

### What must not change

- Existing `venues` RLS policies for direct CRUD.
- Venue management UI permission model.
- Gig create/update schema and API contracts.
- Any unrelated event/rehearsal logic.

## 7. Database Impact

- **Migrations:** required (new SQL migration file).
- **RLS policies:** unchanged (no direct policy edits).
- **RPCs:** one new function `create_venue_for_gig_save`.
- **Triggers:** none.

RLS/RPC assessment:

- Current `venues` INSERT policy remains strict (`admin`/`member` only).
- Contributor venue creation occurs only via server-validated RPC path.
- RPC includes explicit role/sub-permission checks matching gig-create semantics.
- No self-referencing RLS policy changes introduced.

## 8. Flutter Architecture Changes

- No new providers/controllers/repositories at architecture level.
- Localized edits only:
  - `VenuesRepository`: add one RPC method.
  - `VenuesNotifier`: add one gig-save-specific method with error propagation.
  - `EventEditorDrawer`: switch call site to new method.

No widget tree redesign, no new state model, no dependency additions.

## 9. Files to Create

- `supabase/migrations/20260802133000_create_venue_for_gig_save_rpc.sql`
  - Adds `create_venue_for_gig_save` function and execute grant.

## 10. Files to Modify

| File                                                   | What changes                                                                                                                                    |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/venues_repository.dart`         | Add RPC-backed `createVenueForGigSave(...)` method for scoped venue creation in gig-save flow.                                                  |
| `lib/features/contacts/venues_controller.dart`         | Add `createForGigSave(...)` method that calls repository RPC method, reloads venues, and rethrows on failure.                                   |
| `lib/features/events/widgets/event_editor_drawer.dart` | Replace venue auto-create call in `_handleSave()` to use notifier `createForGigSave(...)` so contributor path succeeds and errors are surfaced. |

## 11. Files Off-Limits

| File/Area                                                       | Reason                                                    |
| --------------------------------------------------------------- | --------------------------------------------------------- |
| `lib/main.dart`                                                 | Initialization order is guardrailed and unrelated.        |
| `lib/features/contacts/widgets/venue_form_screen.dart`          | Direct venue management behavior must remain unchanged.   |
| `supabase/migrations/20260410000000_contacts_venues_tables.sql` | Existing RLS policy baseline should not be loosened.      |
| `lib/features/events/events_repository.dart`                    | Gig persistence logic is not the root cause for this bug. |
| Any notification, auth, setlist, rehearsal, or routing files    | Out of scope for this feature.                            |

## 12. System Impact Map

| System                                 | Impact                                           |
| -------------------------------------- | ------------------------------------------------ |
| Gigs                                   | affected                                         |
| Rehearsals                             | unaffected                                       |
| Setlists / Catalog                     | unaffected                                       |
| Members / RBAC                         | affected (authorization check reused in new RPC) |
| Auth / Session                         | unaffected                                       |
| Routing                                | unaffected                                       |
| Notifications                          | unaffected                                       |
| Platform (iOS / Android / Web / macOS) | affected (shared Flutter save path)              |

## 13. Regression Risk

`MEDIUM`

Rationale:

- Adds SECURITY DEFINER RPC for write path (security-sensitive area).
- Touches shared event save flow used on all platforms.
- Scope is still small (one migration + three targeted Flutter files) and avoids broad policy changes.

## 14. Engineer Task Breakdown

1. Create migration `supabase/migrations/20260802133000_create_venue_for_gig_save_rpc.sql`.
2. Implement `public.create_venue_for_gig_save(...)` with:
   - strict input validation (`band_id`, `name` required),
   - role/sub-permission checks,
   - insert (or dedupe+return existing),
   - `SECURITY DEFINER`, `SET search_path = public`,
   - `GRANT EXECUTE ... TO authenticated`.
3. Add `createVenueForGigSave(...)` to `VenuesRepository` using `supabase.rpc`.
4. Add `createForGigSave(...)` to `VenuesNotifier`; reload cache on success; rethrow errors.
5. Update `EventEditorDrawer._handleSave()` auto-create branch to call `createForGigSave(...)`.
6. Ensure failure path does not silently continue without venue link when auto-create was attempted.
7. Run `flutter analyze` and targeted manual verification.
8. Produce `ENGINEER_REPORT.md` with exact diff and behavior notes.

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

```sql
-- PRE-DEPLOY TEST 1:
-- Confirm venues INSERT policy is still admin/member only before migration.
SELECT policyname, cmd, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'venues'
  AND cmd = 'INSERT';

-- PRE-DEPLOY TEST 2:
-- Confirm contributor_permissions schema includes gig flags the RPC will rely on.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'contributor_permissions'
  AND column_name IN ('can_create_gigs', 'can_create_potential_gigs_only');

-- PRE-DEPLOY TEST 3:
-- Confirm function does not already exist (clean replacement target).
SELECT proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'create_venue_for_gig_save';
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

```sql
-- POST-DEPLOY TEST 1:
-- Verify function exists and has required security properties.
SELECT pg_get_functiondef('public.create_venue_for_gig_save(uuid,text,text,text,text,boolean)'::regprocedure) LIKE '%SECURITY DEFINER%'
   AND pg_get_functiondef('public.create_venue_for_gig_save(uuid,text,text,text,text,boolean)'::regprocedure) LIKE '%search_path = public%';

-- POST-DEPLOY TEST 2:
-- Verify grant exists for authenticated role.
SELECT has_function_privilege('authenticated', 'public.create_venue_for_gig_save(uuid,text,text,text,text,boolean)', 'EXECUTE');

-- POST-DEPLOY TEST 3:
-- Production safety check: identify gigs with typed venue text but missing venue_id
-- in recent window (should trend down after fix).
SELECT count(*)
FROM public.gigs
WHERE created_at >= now() - interval '7 days'
  AND venue_id IS NULL
  AND coalesce(trim(name), '') <> ''
  AND coalesce(trim(location), '') <> '';
```

Manual/app integration verification (required):

1. Contributor with `can_create_gigs=true` creates confirmed gig with brand-new venue name -> venue row created and linked.
2. Contributor with potential-only permissions creates potential gig with brand-new venue -> venue created and linked.
3. Same potential-only contributor attempts confirmed gig -> save blocked by existing gig permission rules (no privilege escalation).
4. Admin/member behavior unchanged.
5. Venue management screens still enforce existing contributor restrictions.

## 16. QA Regression Areas

- Primary: contributor auto-create venue on Add Gig and Edit Gig.
- Contributor permission matrix: `can_create_gigs`, `can_create_potential_gigs_only` combinations.
- Error surfacing: failed auto-create must not silently save without venue link.
- Venue directory dedupe behavior under existing name/city matching.
- Admin/member venue auto-create flow remains working.
- Cross-platform parity: web, iOS, Android, macOS save path.

## 17. Rollout / Migration Strategy

1. Apply migration first (`supabase db push`) so RPC exists before client usage.
2. Deploy app changes that call new RPC.
3. Perform manual RBAC matrix verification in staging/production-safe environment.
4. Monitor for unexpected increase in venue duplicates or RPC permission errors.

No edge function deploy required.

## 18. Out of Scope

- Broad venue CRUD permission redesign.
- Any direct RLS policy loosening for `venues` table CRUD.
- Refactoring `VenuesNotifier`/repository beyond what is required for this bug.
- Gig venue autocomplete UX redesign.
- Notification, auth, rehearsal, setlist, or routing changes.
