# Architect Plan — feature/band-gear-management

## Feature Slug

`feature/band-gear-management`

## Feature Title

Band Gear Management

## Cycle 3 re-diagnosis note (Verification-only revision)

This revision does **not** change the feature architecture, the DB schema,
the client code plan, files-to-create, files-off-limits, or the change
budget. QA cycles 1 and 2 both returned REQUIRES CHANGES on a single
repeating Critical `database-safety` finding: neither cycle could
complete an isolated managed-Supabase-branch migration-apply because
this repo's tracked migration chain is broken project-wide at
`073_fix_gig_responses_unique_constraint.sql`. That is a repo-level
infra defect, not a defect of this feature, and no per-feature workaround
Engineer can add to `create_band_gear.sql` will change it.

The only sections rewritten in this cycle are
[Verification Plan](#verification-plan) and
[Rollout Strategy](#rollout-strategy). Verification now defines a
fully-QA-reproducible, non-production, non-managed-branch migration
apply-check (ephemeral local Postgres 17 + inline fixture) that is the
Tier 1 gate for APPROVED, and moves the runtime RLS-behavior checks that
require Supabase's real `auth.uid()` semantics to Tier 2 as Tony's
owner-run gate at apply time — matching the demo-band precedent that
was APPROVED under this same infra blocker
([interactive-demo-band-experience/QA_REPORT.md](docs/features/interactive-demo-band-experience/QA_REPORT.md#L15)).
Engineer's cycle-2 implementation is unchanged by this revision; QA should
re-verify against the new Tier 1 procedure only, without touching the
managed staging project or a preview branch.

## Cycle 3 revision — scope addition (contributor visibility gate)

Tony reviewed the cycle-3 BLOCKED escalation and directed three
outcomes that this revision folds into the plan. This is **additive** to
everything already in the plan — the schema/screen/controller/
repository/drawer/shell wiring stays exactly as cycle-3 Engineer left
it. Nothing in cycle-3's implementation gets rewritten.

**1. Tier 1.3 exception (accepted).** The
`test/features/auth/login_screen_demo_button_test.dart` failure that
blocked cycle-3's [T1.3 full-suite regression
guard](#t13--full-suite-regression-guard) is a **pre-existing, unrelated**
typo bug. `lib/features/auth/login_screen.dart:657` renders
`'Check out the demo band'` (lowercase `out`) but the test asserts
`'Check Out the Demo Band'` (title case). Both files were last touched
together in commit `5cd1996` and are unmodified by
`feature/band-gear-management`. Filing this as a separate one-line
typo/bug fix, out of this feature's scope. QA is authorized to record
this specific assertion mismatch as an accepted deviation in the cycle-4
QA report, cite `5cd1996` as evidence, and treat the rest of the suite
as the T1.3 gate — a single unrelated pre-existing failure does **not**
block APPROVED. Any _new_ failure in that suite still does.

**2. Tier 1.5 deferral to Tier 2 (accepted).** The isolated
migration-apply portion of [T1.5](#t15--isolated-migration-apply-check-ephemeral-local-postgres)
remains deferred to Tier 2 owner-run checks under the same repo-wide
broken-migration-chain infra blocker precedent used for
[interactive-demo-band-experience](docs/features/interactive-demo-band-experience/QA_REPORT.md#L15).
Tony runs the migration apply at production apply time as part of the
[Rollout Strategy](#rollout-strategy). QA is not expected to reproduce
the apply against a managed branch — this deferral is expected and
does not block APPROVED.

**3. Scope addition — contributor visibility toggle.** Cycle-3's
implementation grants gear-view to any active contributor via the
current `canViewGear => isAdmin || isMember || isContributor` getter
and the base SELECT policy in
`supabase/migrations/20260905201000_create_band_gear.sql`. Tony's
decision: gear visibility for contributors must be **gated by a per-band
sub-permission**, matching the exact 3-part pattern this repo already
uses for `can_view_financials`. That pattern is:

- **(a)** add `can_view_gear BOOLEAN NOT NULL DEFAULT FALSE` to
  `contributor_permissions` (mirror
  [`20260604000001_add_can_view_financials_to_contributor_permissions.sql`](supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql));
- **(b)** fix the `update_member_role` RPC's `UPDATE ... SET` clause to
  persist `can_view_gear` from `p_sub_permissions`, so the toggle
  doesn't appear to save but silently revert on reload — the exact bug
  [`20260711120000_fix_update_member_role_can_view_financials.sql`](supabase/migrations/20260711120000_fix_update_member_role_can_view_financials.sql)
  had to be shipped to fix for financials. Engineer must **explicitly**
  include `can_view_gear` in the SET clause; skipping this is the known
  first-pass mistake;
- **(c)** replace the base `band_gear` SELECT policy with a
  `check_gear_view_permission(band_id)` `SECURITY DEFINER` helper that
  server-side gates contributors on the toggle (mirror
  [`20260814120001_fix_financial_entries_select_rbac.sql`](supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql)).
  A client-only toggle is a real RBAC bypass — same class of bug
  financials had (contributor with the toggle OFF could still read
  rows by bypassing the UI). Admins and members always pass through the
  helper; contributors pass only when their `can_view_gear = TRUE`;
- **(d)** add `canViewGear` to
  [`lib/features/members/permissions/contributor_permissions.dart`](lib/features/members/permissions/contributor_permissions.dart)
  with `fromJson` / `toJson` / `copyWith` / `allDisabled` parity to the
  existing `canViewFinancials` field, and change the
  [`BandPermissions.canViewGear`](lib/features/members/permissions/band_permissions.dart)
  getter's contributor branch to consult the sub-permission (currently
  hardcoded `isAdmin || isMember || isContributor`). `canManageGear`
  stays unchanged (admin || member);
- **(e)** wire the "Can view gear" toggle into
  [`lib/features/members/widgets/role_management_sheet.dart`](lib/features/members/widgets/role_management_sheet.dart)
  next to the existing "Can view financials" toggle, matching its exact
  UX and save/load semantics.

**RLS INSERT / UPDATE / DELETE stay unchanged** — still admin+member
only, contributors always blocked regardless of the toggle. The toggle
governs visibility only. This is explicitly confirmed in
[Database Impact](#database-impact) and enforced in
[T1.4](#t14--static-sql-review-of-the-migration) and
[T1.5](#t15--isolated-migration-apply-check-ephemeral-local-postgres).

**Off-limits list is unchanged.** No new files or systems are added to
[Files Off-Limits](#files-off-limits); the scope addition touches only
files already in scope for this feature plus one new sub-permission
edit and one role-management-sheet toggle edit.

## Problem Summary

BandRoadie has no place to record equipment owned by a band or by individual
members. Bands need a band-scoped inventory list where members can add items,
review a small set of purchase details, and mark each item as either
band-owned or owned by a specific current band member. Everything else
(maintenance history, insurance, depreciation, receipts, photos, serial
numbers, lending/check-out, per-event assignments) is explicitly out of scope
for v1 — this is inventory management only.

## Root Cause

Confidence: `HIGH` — read-confirmed.

There is no existing gear/equipment feature in the codebase or database. This
is a new-capability request, not a defect. Verified:

- `grep_search` for `gear` under `lib/**` and `supabase/**` returned zero
  matches. The only workspace hit is an unrelated icon-audit doc.
- `lib/features/` has no `gear/` directory.
- No `band_gear` (or similar) table appears in
  [docs/reference/architecture/database_schema.md](docs/reference/architecture/database_schema.md)
  or in the migrations directory.

Root cause of the missing capability: the feature has not been built yet.
This plan defines the smallest additive surface that satisfies the Feature
Input, modeled directly on the existing `contacts` feature (a peer-level,
simple, band-scoped, table-driven CRUD surface).

## Existing System Analysis

Reference patterns that this plan reuses verbatim (no new architecture
introduced):

- **Band-scoped table + RLS**, per
  [supabase/migrations/20260410000000_contacts_venues_tables.sql](supabase/migrations/20260410000000_contacts_venues_tables.sql):
  `band_id UUID NOT NULL REFERENCES bands(id) ON DELETE CASCADE`, four RLS
  policies (SELECT for active members; INSERT/UPDATE/DELETE for
  `role IN ('admin','member')`), plus a `set_..._updated_at` trigger that
  reuses `public.update_updated_at_column()`.
- **Repository + Notifier**, per
  [lib/features/contacts/contacts_repository.dart](lib/features/contacts/contacts_repository.dart)
  and
  [lib/features/contacts/contacts_controller.dart](lib/features/contacts/contacts_controller.dart):
  in-memory per-band cache, non-null `bandId` guard that throws
  `NoBandSelected...Error`, `Notifier` + `NotifierProvider` state, `reset()`
  on band change.
- **Money as integer cents**, per
  [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart#L60)
  (`amount_cents INTEGER`). Gear uses the identical convention (`price_cents`).
- **Member reference to `users.id`**, per `financial_entries.paid_to_user_id`
  in
  [supabase/migrations/20260601000001_add_paid_to_name.sql](supabase/migrations/20260601000001_add_paid_to_name.sql).
  Gear ownership references `users(id)` — not `band_members(id)` — so that
  ownership survives membership status changes and lines up with existing
  patterns.
- **RBAC gating**, per
  [lib/features/members/permissions/band_permissions.dart](lib/features/members/permissions/band_permissions.dart)
  and
  [lib/features/members/permissions/band_permissions_provider.dart](lib/features/members/permissions/band_permissions_provider.dart).
  Gear adds `canViewGear` / `canManageGear` getters shaped exactly like
  `canViewCalendar` / `canCreateSetlists`.
- **Screen surfacing via side drawer**, per
  [lib/features/home/widgets/side_drawer.dart](lib/features/home/widgets/side_drawer.dart)
  and
  [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart#L285).
  Settings, Tips & Tricks, and Report Bugs already push their screens from
  drawer taps via `Navigator.of(context).push(MaterialPageRoute(...))` — no
  named-route registration required. Gear reuses this pattern; the bottom
  nav (4 fixed tabs) is not modified.
- **Active-band state and reset-on-switch**, per
  [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart#L498)
  and the `ref.listen<ActiveBandState>` block in
  [lib/features/contacts/contacts_tab_content.dart](lib/features/contacts/contacts_tab_content.dart).
- **Active members data source**, per
  [lib/features/members/members_repository.dart](lib/features/members/members_repository.dart)
  and `membersProvider` in
  [lib/features/members/members_controller.dart](lib/features/members/members_controller.dart#L285).
  The owner picker reads from `membersProvider` and filters to
  `status == 'active'` — no new members query is introduced.

## Proposed Solution

Add a new `gear` feature that is a small, band-scoped inventory CRUD, modeled
1:1 on `contacts`. Access it from a new "Gear" entry in the side drawer,
pushed as a full-screen route — no bottom-nav change.

Resolved design decisions (called out so Engineer implements literally):

1. **List UI, not a literal HTML table.** The Feature Input's phrase
   "table/list that makes the important information easy to review" describes
   information density. Every peer feature (contacts, venues, songs,
   members) uses a scrolling list of cards/rows; using the same idiom keeps
   the UI consistent across screen widths and matches the design tokens
   already in the codebase. Row content: name (primary), owner (secondary),
   price + purchase date (tertiary). Purchased-from surfaces on the
   detail/edit sheet.
2. **Ownership storage is a discriminated pair, not two separate flags.**
   `owner_type` is `'band'` or `'member'`; `owner_user_id` is `NULL` when
   `owner_type = 'band'` and non-null when `owner_type = 'member'`. Enforced
   with a `CHECK` constraint so the two mutually-exclusive states in the
   Feature Input (band-owned vs. individually-owned by a specific member)
   can never be recorded inconsistently. The UI presents this to the user as
   a single "Owner" control (band vs. member picker).
3. **Member picker sources from `membersProvider` filtered to
   `status == 'active'`**, so ownership can only be assigned to a real
   current member of the active band — never free text. The Feature Input
   requires this explicitly.
4. **Permission model — gated contributor visibility (revised in cycle 3
   scope addition).** `admin` and `member` always see and manage gear.
   Contributors see gear **only** when their `contributor_permissions.
can_view_gear = TRUE`; they never insert, update, or delete gear.
   Enforcement is defense-in-depth at three layers:
   - Client-side gating on `BandPermissions.canViewGear` (contributor
     branch consults sub-permission — see [Files to
     Modify](#files-to-modify)).
   - Server-side gating in the `band_gear` SELECT policy via a
     `check_gear_view_permission(band_id)` `SECURITY DEFINER` helper
     (identical shape to `check_financial_view_permission`).
   - Sub-permission persisted server-side via `update_member_role`'s
     `SET` clause — the RPC MUST include `can_view_gear` explicitly (see
     [Database Impact](#database-impact)); omitting it is the exact bug
     that shipped for financials and had to be fixed in
     [`20260711120000_fix_update_member_role_can_view_financials.sql`](supabase/migrations/20260711120000_fix_update_member_role_can_view_financials.sql).

   INSERT / UPDATE / DELETE policies on `band_gear` stay
   admin-and-member-only — contributors are never allowed to write to
   `band_gear` regardless of the toggle.

5. **One `SECURITY DEFINER` helper only.** `check_gear_view_permission`
   is the only new function; it must be created with `SET search_path =
public`, `REVOKE ALL ... FROM PUBLIC, anon`, and explicit `GRANT EXECUTE
   ... TO authenticated` — same shape as
   [`20260822120001_revoke_anon_batch_2_rls_helpers.sql`](supabase/migrations/20260822120001_revoke_anon_batch_2_rls_helpers.sql)
   applied retroactively to the financials helper. Doing this in the
   same migration file that creates the helper avoids the two-step
   pattern the financials feature ended up needing.
6. **No notifications for v1.** Gear operations do not fan out to
   `notify_band_members`. This is consistent with contacts and venues
   (both silent).
7. **Nullable purchase fields.** `purchased_on`, `purchased_from`,
   `price_cents`, and `owner_user_id` are all nullable at the DB level.
   Users often add gear they've owned for years without remembering exact
   details; the only required fields at v1 are `name`, `band_id`, and
   `owner_type`. The UI enforces the additional "if member-owned, a member
   must be selected" rule at form-validation time and the DB backs it up
   with the `CHECK` constraint.

## Database Impact

**Scope:** one new table (already in the cycle-3 base migration), four
RLS policies on that table (the SELECT policy will be replaced by a
helper-based policy in the follow-up RBAC migration), one trigger, two
indexes, **one new column on `contributor_permissions`**, **one
`SECURITY DEFINER` helper function**, and **one `CREATE OR REPLACE` of
the existing `update_member_role` RPC** to persist the new sub-permission.
No changes to any other existing table, policy, function, or trigger.
No new grants beyond RLS defaults for `band_gear` itself; the new helper
gets the standard `REVOKE ALL FROM PUBLIC, anon` + `GRANT EXECUTE ... TO
authenticated` pattern.

### Base migration (already in cycle-3 uncommitted work, unchanged shape)

The cycle-3 base migration
[`supabase/migrations/20260905201000_create_band_gear.sql`](supabase/migrations/20260905201000_create_band_gear.sql)
creates the table exactly as specified below. Its SELECT policy will be
**superseded** by the helper-based policy shipped in the RBAC follow-up
migration (see [Contributor visibility gating](#contributor-visibility-gating-3-part-rbac-follow-up)
below); Engineer does **not** rewrite `20260905201000_create_band_gear.sql`
in place — the follow-up migration issues `DROP POLICY IF EXISTS ...`
then `CREATE POLICY ... USING (public.check_gear_view_permission(band_id))`.
Keeping the base migration byte-identical to the cycle-3 file avoids
churning a migration QA already reviewed.

Base table shape (unchanged):

```sql
CREATE TABLE public.band_gear (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id         UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  purchased_on    DATE,
  purchased_from  TEXT,
  price_cents     INTEGER CHECK (price_cents IS NULL OR price_cents >= 0),
  owner_type      TEXT NOT NULL CHECK (owner_type IN ('band', 'member')),
  owner_user_id   UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT band_gear_owner_shape CHECK (
    (owner_type = 'band'   AND owner_user_id IS NULL) OR
    (owner_type = 'member' AND owner_user_id IS NOT NULL)
  )
);

CREATE INDEX idx_band_gear_band_id       ON public.band_gear(band_id);
CREATE INDEX idx_band_gear_owner_user_id ON public.band_gear(owner_user_id);

ALTER TABLE public.band_gear ENABLE ROW LEVEL SECURITY;
```

RLS policies (four total, mirroring `public.contacts` exactly — same
`EXISTS ... band_members ... status = 'active' ... role IN (...)` shape,
same policy naming style):

- `SELECT` — any `status = 'active'` `band_member` of `band_gear.band_id`.
- `INSERT` — `role IN ('admin', 'member')`.
- `UPDATE` — `role IN ('admin', 'member')` in both `USING` and `WITH CHECK`.
- `DELETE` — `role IN ('admin', 'member')`.

The recursion analysis for these policies is consolidated in the [RLS
recursion & recursion guard](#rls-recursion--recursion-guard) subsection
below (covering both the base SELECT policy and the helper-based
replacement).

Trigger (reuses existing helper):

```sql
CREATE TRIGGER set_band_gear_updated_at
  BEFORE UPDATE ON public.band_gear
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
```

**Grants and `SECURITY DEFINER`:** the base table needs none — RLS
alone gates `band_gear`. The RBAC follow-up (below) adds one new
`SECURITY DEFINER` helper function (`check_gear_view_permission`) and
replaces the base SELECT policy to call it.

**Cascade behavior:** deleting a band cascades gear rows away. Deleting a
`users` row sets `owner_user_id` / `created_by` to `NULL` (the gear row
survives). This matches how existing tables treat these two FK targets.

Base migration filename (already committed as cycle-3 uncommitted work):
[`supabase/migrations/20260905201000_create_band_gear.sql`](supabase/migrations/20260905201000_create_band_gear.sql).
Not re-timestamped in this revision.

### Contributor visibility gating (3-part RBAC follow-up)

Cycle 3 adds three new migration files after the base migration, in
this exact order, each an atomic commit (see [Engineer Task
Breakdown](#engineer-task-breakdown)). Each migration mirrors an
already-shipped precedent in this repo one-for-one — Engineer copies
the referenced file's shape and substitutes `financials` → `gear`
throughout.

#### Migration 1 of 3 — `<UTC>_add_can_view_gear_to_contributor_permissions.sql`

Direct mirror of
[`20260604000001_add_can_view_financials_to_contributor_permissions.sql`](supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql).
Adds a single nullable-safe column with a fail-closed default:

```sql
ALTER TABLE public.contributor_permissions
  ADD COLUMN IF NOT EXISTS can_view_gear BOOLEAN NOT NULL DEFAULT FALSE;
```

- **Default is `FALSE`** (fail-closed). Existing contributor rows do
  not gain gear visibility automatically; Tony flips them on per-
  contributor via the Role Management sheet.
- No backfill required — the `NOT NULL DEFAULT FALSE` fills existing
  rows atomically.
- Engineer picks the timestamp so it sorts after
  `20260905201000_create_band_gear.sql` and after every migration
  currently on `main` at merge time.

#### Migration 2 of 3 — `<UTC>_fix_update_member_role_can_view_gear.sql`

Direct mirror of
[`20260711120000_fix_update_member_role_can_view_financials.sql`](supabase/migrations/20260711120000_fix_update_member_role_can_view_financials.sql).
This is the step that was forgotten on the first pass for financials —
the client sent `can_view_financials` correctly but the RPC's `UPDATE
... SET` clause didn't persist it, so the toggle appeared to save then
reverted on reload. Engineer MUST **explicitly** add `can_view_gear` to
the SET clause; do not rely on `p_sub_permissions` being applied
generically.

Full-body `CREATE OR REPLACE` of `public.update_member_role(UUID, UUID,
TEXT, JSONB)` with `SECURITY DEFINER`, `SET search_path = public`
inside the body, and the SET clause extended by one line:

```sql
-- Inside IF p_new_role = 'contributor' ... IF p_sub_permissions IS NOT NULL THEN block:
UPDATE public.contributor_permissions
SET
  can_create_gigs                = COALESCE((p_sub_permissions->>'can_create_gigs')::boolean, TRUE),
  can_create_potential_gigs_only = COALESCE((p_sub_permissions->>'can_create_potential_gigs_only')::boolean, TRUE),
  can_view_setlists              = COALESCE((p_sub_permissions->>'can_view_setlists')::boolean, TRUE),
  can_view_calendar              = COALESCE((p_sub_permissions->>'can_view_calendar')::boolean, TRUE),
  can_view_members               = COALESCE((p_sub_permissions->>'can_view_members')::boolean, TRUE),
  can_view_financials            = COALESCE((p_sub_permissions->>'can_view_financials')::boolean, FALSE),
  can_view_gear                  = COALESCE((p_sub_permissions->>'can_view_gear')::boolean, FALSE),  -- NEW
  updated_at                     = NOW()
WHERE band_member_id = p_member_id;
```

- All other lines of the function body remain byte-identical to
  `20260711120000_fix_update_member_role_can_view_financials.sql`.
- Migration ends with the standard
  `GRANT EXECUTE ON FUNCTION public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;`
  as in the referenced file.
- Default for the extracted JSON key is `FALSE` — fail-closed, matching
  the column default from Migration 1.

#### Migration 3 of 3 — `<UTC>_fix_band_gear_select_rbac.sql`

Direct mirror of
[`20260814120001_fix_financial_entries_select_rbac.sql`](supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql),
with the anon-revoke inline (avoiding the second follow-up file
[`20260822120001_revoke_anon_batch_2_rls_helpers.sql`](supabase/migrations/20260822120001_revoke_anon_batch_2_rls_helpers.sql)
had to add for financials).

Three top-level statements, in this order:

**a. Create helper.** `check_gear_view_permission(p_band_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path =
public`. Body flow, identical shape to `check_financial_view_permission`:

```sql
-- 1. v_user_id := auth.uid(); if NULL → RETURN FALSE
-- 2. SELECT role FROM band_members WHERE band_id=p_band_id
--       AND user_id=v_user_id AND status='active' INTO v_role
-- 3. If v_role IS NULL → RETURN FALSE
-- 4. If v_role IN ('admin','member') → RETURN TRUE  (always pass)
-- 5. If v_role = 'contributor':
--      SELECT COALESCE(cp.can_view_gear, FALSE)
--        FROM band_members bm
--        LEFT JOIN contributor_permissions cp ON cp.band_member_id = bm.id
--       WHERE bm.band_id=p_band_id AND bm.user_id=v_user_id
--         AND bm.status='active' INTO v_can_view
--      RETURN COALESCE(v_can_view, FALSE)
-- 6. Default RETURN FALSE
```

**b. Grants (inline, not deferred).** Ship `REVOKE ALL FROM PUBLIC, anon`

- explicit `GRANT EXECUTE ... TO authenticated` in the same file:

```sql
REVOKE ALL ON FUNCTION public.check_gear_view_permission(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_gear_view_permission(UUID) TO authenticated;
```

**c. Swap the SELECT policy.** Drop the base SELECT policy from
Migration `20260905201000_create_band_gear.sql` and recreate it to
call the helper:

```sql
DROP POLICY IF EXISTS "Band members can view gear" ON public.band_gear;

CREATE POLICY "Band members can view gear" ON public.band_gear
  FOR SELECT
  USING (public.check_gear_view_permission(band_id));
```

- Policy name is preserved verbatim so QA structural checks still match
  by name.
- `USING` predicate is now delegated entirely to the helper; the
  admin/member/contributor branching lives in one place server-side.
- **INSERT / UPDATE / DELETE policies are NOT touched** — they remain
  admin+member only from the base migration. Contributors are still
  server-side blocked from writing to `band_gear` regardless of
  `can_view_gear`. This is confirmed in
  [T1.4](#t14--static-sql-review-of-the-migration) and
  [T1.5](#t15--isolated-migration-apply-check-ephemeral-local-postgres).

### RLS recursion & recursion guard

None of the four `band_gear` policies (before or after the SELECT
swap) query `band_gear` itself — they only query `band_members`
directly or via the helper. The helper queries `band_members` and
`contributor_permissions`, never `band_gear`. This avoids the
recursion class documented in
[`docs/features/band-members-rls-recursion/`](docs/features/band-members-rls-recursion/).

## Flutter Architecture Changes

None architectural. All Dart edits are additive, one-field / one-getter
/ one-toggle changes that follow existing shipped patterns:

- New feature folder `lib/features/gear/` follows the same shape as
  `lib/features/contacts/` — feature-first directory, `models/`,
  `widgets/`, one repository, one controller, one screen.
- State via `Notifier` + `NotifierProvider` — no `StateNotifier`.
- Riverpod access pattern: `ref.watch(gearProvider)` for reactive UI,
  `ref.read(gearProvider.notifier).<action>()` for actions.
- Cache lives in the repository (`Map<String, _CacheEntry>` keyed by
  `bandId`), 5-minute TTL — identical to contacts.
- Non-null `bandId` guard at the repository boundary throwing
  `NoBandSelectedGearError`.
- `ref.listen<ActiveBandState>` inside the screen (or a small wrapper) to
  reset gear state when the active band changes, matching
  `ContactsTabContent`.
- **`ContributorPermissions` gains one `canViewGear` field** with the
  same `fromJson` / `toJson` / `copyWith` / `allDisabled` /
  `allEnabled` / `toString` parity as the existing `canViewFinancials`
  field. Default in the immutable constructor is `false` (fail-closed),
  matching `canViewFinancials`.
- **`BandPermissions.canViewGear` getter body changes shape** from the
  current `isAdmin || isMember || isContributor` to the same
  admin/member-always-pass, contributor-consults-sub-permission shape
  used by `canViewFinancials`:

  ```dart
  bool get canViewGear {
    if (isAdmin || isMember) return true;
    if (isContributor) {
      return subPermissions?.canViewGear ?? false;
    }
    return false;
  }
  ```

  `canManageGear` is **unchanged** — still `isAdmin || isMember`.

- **`RoleManagementSheet` gains one new "Can view gear" toggle**
  alongside "Can view financials", using the existing
  `_buildPermissionToggle` helper with the same save-on-Save-button,
  dirty-state-via-`_permissionsEqual`, load-existing-permissions-in-
  `_loadExistingPermissions` semantics. The `_permissionsEqual` helper
  and `_subPermissions.copyWith(...)` calls are extended to include
  `canViewGear`.

Init order (main.dart), routing, host detection, auth flow, deep-link
service, and bottom-nav tab structure are **not** touched.

## Files to Create

1. `supabase/migrations/20260905201000_create_band_gear.sql` — **already
   present in cycle-3 uncommitted work.** Base table, RLS, `updated_at`
   trigger, indexes. Shape unchanged from cycle-3; its SELECT policy is
   superseded by Migration 3-of-3 below. Do not rewrite this file — the
   RBAC follow-up issues `DROP POLICY IF EXISTS ...` +
   `CREATE POLICY ...`.
2. `supabase/migrations/<UTC>_add_can_view_gear_to_contributor_permissions.sql`
   — Migration 1 of 3 from [Contributor visibility
   gating](#contributor-visibility-gating-3-part-rbac-follow-up). Single
   `ALTER TABLE ... ADD COLUMN IF NOT EXISTS can_view_gear BOOLEAN NOT
NULL DEFAULT FALSE`. Direct mirror of
   [`20260604000001_add_can_view_financials_to_contributor_permissions.sql`](supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql).
3. `supabase/migrations/<UTC>_fix_update_member_role_can_view_gear.sql`
   — Migration 2 of 3. Full-body `CREATE OR REPLACE FUNCTION public.
update_member_role(UUID, UUID, TEXT, JSONB)` with `can_view_gear` added
   to the SET clause; body byte-identical to
   [`20260711120000_fix_update_member_role_can_view_financials.sql`](supabase/migrations/20260711120000_fix_update_member_role_can_view_financials.sql)
   otherwise. Ends with `GRANT EXECUTE ... TO authenticated;` line
   unchanged.
4. `supabase/migrations/<UTC>_fix_band_gear_select_rbac.sql` —
   Migration 3 of 3. `CREATE OR REPLACE FUNCTION public.
check_gear_view_permission(UUID)` (`SECURITY DEFINER`, `SET search_path
   = public`), inline `REVOKE ALL FROM PUBLIC, anon` + `GRANT EXECUTE ...
   TO authenticated`, then `DROP POLICY IF EXISTS "Band members can view
gear" ON public.band_gear` + `CREATE POLICY "Band members can view gear"
... USING (public.check_gear_view_permission(band_id))`. Direct mirror
   of
   [`20260814120001_fix_financial_entries_select_rbac.sql`](supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql)
   with the anon-revoke inline.
5. `lib/features/gear/models/gear_item.dart` — `GearItem` data class
   (immutable, `fromJson` / `toJson`), plus an `enum GearOwnerType { band,
member }` with `dbValue` / `fromDbValue` helpers mirroring
   `FinancialEntryType`.
6. `lib/features/gear/gear_repository.dart` — `GearRepository` with
   `fetchGear`, `createGear`, `updateGear`, `deleteGear`, per-band cache,
   `NoBandSelectedGearError`. Mirrors `ContactsRepository` line-for-line
   structurally.
7. `lib/features/gear/gear_controller.dart` — `GearState`, `GearNotifier`
   extends `Notifier<GearState>`, and `final gearProvider =
NotifierProvider<GearNotifier, GearState>(GearNotifier.new);`. Public
   methods: `load`, `refresh`, `create`, `update`, `delete`, `reset`.
8. `lib/features/gear/gear_screen.dart` — `GearScreen` full-page screen
   pushed from the side drawer. Reads `gearProvider`, `activeBandProvider`,
   and `currentUserPermissionsProvider`. Shows list of rows, empty state,
   and an "Add Gear" affordance visible only when `perms.canManageGear`.
9. `lib/features/gear/widgets/gear_row.dart` — one gear item row (name,
   owner label, price, purchase date). Tap opens the edit sheet if the user
   `canManageGear`, otherwise a read-only detail view.
10. `lib/features/gear/widgets/gear_form_sheet.dart` — bottom-sheet form
    for create/edit. Contains an owner selector (band vs. member), and
    when "member" is selected shows an inline picker sourced from
    `membersProvider` filtered to `status == 'active'`. Handles form
    validation, save, delete-with-confirmation.
11. `lib/features/gear/widgets/gear_empty_state.dart` — friendly empty
    state with an "Add Your First Item" CTA (only when `canManageGear`).
12. `test/features/gear/gear_item_test.dart` — pure model tests (fromJson/
    toJson round-trip, `GearOwnerType.fromDbValue` mapping,
    `band_gear_owner_shape` invariant enforced at the model layer as an
    `assert` in the constructor). Existing `test/` structure already
    mirrors `lib/`.

No new dependencies (`pubspec.yaml` is off-limits).

## Files to Modify

Five files, all additive edits — no behavior changes to unrelated code
paths.

1. `lib/features/members/permissions/contributor_permissions.dart` —
   add one `canViewGear` field to `ContributorPermissions` with the
   same parity treatment `canViewFinancials` already has:
   - immutable constructor parameter `this.canViewGear = false`
     (fail-closed default);
   - `allEnabled` static includes `canViewGear: true`; `allDisabled`
     static includes `canViewGear: false`;
   - `fromJson` reads `json['can_view_gear'] as bool? ?? false`;
   - `toJson` writes `'can_view_gear': canViewGear`;
   - `copyWith` accepts an optional `bool? canViewGear`;
   - `toString` appends `gear=$canViewGear`.
     No other changes to that file.
2. `lib/features/members/permissions/band_permissions.dart` — change
   the **body** of the existing `canViewGear` getter from `isAdmin ||
isMember || isContributor` to the admin/member-always-pass,
   contributor-consults-sub-permission shape shown in [Flutter
   Architecture Changes](#flutter-architecture-changes). Do not rename
   the getter, do not change its signature, do not touch `canManageGear`.
3. `lib/features/members/widgets/role_management_sheet.dart` — add one
   new `_buildPermissionToggle` call for `"Can view gear"` immediately
   after the existing "Can view financials" toggle inside the
   `if (_selectedRole == 'contributor') ...` block; extend
   `_permissionsEqual` to compare `a.canViewGear == b.canViewGear`;
   the `_subPermissions.copyWith(canViewGear: v)` call inside
   `onChanged` follows the exact pattern of the financials toggle. No
   other changes to that file. Both `_loadExistingPermissions` (which
   just calls `fetchContributorPermissions`) and `_saveRole` (which
   just forwards `_subPermissions` through `updateRole` → RPC) already
   handle the new field transparently once `ContributorPermissions`
   knows about it, so no repo/controller edits are required.
4. `lib/features/home/widgets/side_drawer.dart` — **already modified in
   cycle-3 uncommitted work.** Adds one new `DrawerNavItem` for
   "Gear" plus a `VoidCallback onGearTap` on the `SideDrawer`
   constructor. Unchanged by this revision.
5. `lib/features/shell/app_shell.dart` — **already modified in cycle-3
   uncommitted work.** Wires `onGearTap` on the `_MenuDrawerLayer`'s
   `DrawerOverlayContent` call to push `const GearScreen()` via
   `MaterialPageRoute`. Unchanged by this revision.

## Files Off-Limits

- `lib/main.dart` — init order, host detection, routing table. Gear does
  not need a named route; the drawer-push pattern is already established.
- `lib/app/services/deep_link_service.dart`, `lib/app/supabase_config.dart`,
  `lib/app/firebase_config.dart`, `lib/app/services/app_version_service.dart`
  — untouched.
- `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`,
  `devtools_options.yaml` — no new dependencies.
- All native platform config: `ios/`, `android/`, `macos/`, `linux/`,
  `windows/`, `web/index.html`, `web/manifest.json`, `vercel.json`. Gear is
  pure Flutter + Supabase — no platform-conditional code.
- Any existing table, RLS policy, function, or trigger in `supabase/`.
- Any file under `lib/features/auth/`, `lib/features/bands/`,
  `lib/features/calendar/`, `lib/features/gigs/`, `lib/features/rehearsals/`,
  `lib/features/setlists/`, `lib/features/financials/`,
  `lib/features/notifications/`, `lib/features/contacts/`,
  `lib/features/members/` (**except** the single additive edit to
  `permissions/band_permissions.dart` listed above).
- Bottom navigation structure in `AppShell` (`visibleTabs` list,
  `IndexedStack` children, `visibleNavItems`) — unchanged.
- `docs/reference/general/RUNTIME_CONFIG.md` and
  `docs/reference/general/AI_DECISIONS.md` — not touched (no init-order,
  platform-parity, or config change).

## Change Budget

Engineer, QA measures actual diff against these numbers — implement
literally.

| File / Area                                                                        | Expected net line delta |
| ---------------------------------------------------------------------------------- | ----------------------: |
| `supabase/migrations/20260905201000_create_band_gear.sql` (already present)        |                       0 |
| `supabase/migrations/<UTC>_add_can_view_gear_to_contributor_permissions.sql` (new) |               +6 to +12 |
| `supabase/migrations/<UTC>_fix_update_member_role_can_view_gear.sql` (new)         |            +100 to +115 |
| `supabase/migrations/<UTC>_fix_band_gear_select_rbac.sql` (new)                    |              +55 to +80 |
| `lib/features/gear/models/gear_item.dart` (new)                                    |             +90 to +130 |
| `lib/features/gear/gear_repository.dart` (new)                                     |            +130 to +180 |
| `lib/features/gear/gear_controller.dart` (new)                                     |            +130 to +180 |
| `lib/features/gear/gear_screen.dart` (new)                                         |            +200 to +300 |
| `lib/features/gear/widgets/gear_row.dart` (new)                                    |             +80 to +130 |
| `lib/features/gear/widgets/gear_form_sheet.dart` (new)                             |            +250 to +380 |
| `lib/features/gear/widgets/gear_empty_state.dart` (new)                            |              +40 to +70 |
| `test/features/gear/gear_item_test.dart` (new)                                     |             +60 to +100 |
| `lib/features/members/permissions/contributor_permissions.dart`                    |               +8 to +14 |
| `lib/features/members/permissions/band_permissions.dart` (getter body swap)        |               +5 to +10 |
| `lib/features/members/widgets/role_management_sheet.dart` (one toggle + equality)  |              +10 to +16 |
| `lib/features/home/widgets/side_drawer.dart` (cycle-3, already applied)            |                       0 |
| `lib/features/shell/app_shell.dart` (cycle-3, already applied)                     |                       0 |

- Expected new files: **11** (7 code, 3 migration, 1 test).
- Expected new public classes / top-level members: `GearItem`,
  `GearOwnerType` (enum), `NoBandSelectedGearError`, `GearRepository`,
  `GearState`, `GearNotifier`, `gearProvider`, `GearScreen`, `GearRow`,
  `GearFormSheet`, `GearEmptyState`, plus one new
  `ContributorPermissions.canViewGear` field, one new
  `public.check_gear_view_permission(UUID)` SQL function, and one new
  `contributor_permissions.can_view_gear` column. `BandPermissions.
canViewGear` and `.canManageGear` remain (they exist in cycle-3
  work); only `canViewGear`'s **body** changes shape.
- Expected new dependencies: **0**.
- Expected new named routes in `main.dart`: **0**.
- Expected new tabs, edge functions, notification types, or triggers:
  **0**.
- Expected new RPCs: **0** net-new. The existing `update_member_role`
  RPC is `CREATE OR REPLACE`'d with `can_view_gear` added to its SET
  clause; signature `(UUID, UUID, TEXT, JSONB)` is unchanged.

## System Impact Map

| System                                     | Status                          | Notes                                                                                                                                                                                                                              |
| ------------------------------------------ | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Auth / Session                             | Unaffected                      | No init-order, PKCE, deep-link, or magic-link change.                                                                                                                                                                              |
| Routing                                    | Unaffected                      | No `onGenerateRoute` change; `GearScreen` is pushed via `MaterialPageRoute` from the side drawer, matching Settings/Tips/BugReport.                                                                                                |
| Bottom nav / `AppShell` tab structure      | Unaffected                      | `visibleTabs`, `IndexedStack`, `visibleNavItems` untouched.                                                                                                                                                                        |
| Side drawer                                | Affected (additive)             | One new `DrawerNavItem`, one new callback plumbed from `AppShell`.                                                                                                                                                                 |
| RBAC / `BandPermissions`                   | Affected (body swap + additive) | `canViewGear` getter **body** swapped from `isAdmin \|\| isMember \|\| isContributor` to the standard admin/member-always, contributor-consults-sub-permission shape (mirrors `canViewFinancials`). `canManageGear` unchanged.     |
| RBAC / `ContributorPermissions`            | Affected (additive)             | One new `canViewGear` field with `fromJson` / `toJson` / `copyWith` / `allEnabled` / `allDisabled` parity to `canViewFinancials`. All other fields unchanged.                                                                      |
| Members / Role Management sheet            | Affected (additive)             | One new "Can view gear" toggle next to "Can view financials"; `_permissionsEqual` extended by one field. Load / save flow already forwards `_subPermissions` through `updateRole` → RPC unchanged.                                 |
| Members RPC (`update_member_role`)         | Affected (SET clause + 1 line)  | `CREATE OR REPLACE` with `can_view_gear = COALESCE((p_sub_permissions->>'can_view_gear')::boolean, FALSE)` added to the UPDATE SET clause. Signature and all other behavior unchanged. Fail-closed default matches column default. |
| Members / `contributor_permissions` table  | Affected (additive)             | One new `can_view_gear BOOLEAN NOT NULL DEFAULT FALSE` column. Fail-closed for existing rows; no backfill.                                                                                                                         |
| Bands / `activeBandProvider`               | Read-only dependency            | Gear reads `activeBandId`, listens for band switches, calls `reset()` on switch. Provider itself unchanged.                                                                                                                        |
| Members (owner picker)                     | Read-only dependency            | Owner picker reads `membersProvider` filtered to `status == 'active'`. No writes to `band_members` or `users`.                                                                                                                     |
| Gigs                                       | Unaffected                      | No coupling.                                                                                                                                                                                                                       |
| Rehearsals                                 | Unaffected                      | No coupling.                                                                                                                                                                                                                       |
| Setlists / Songs / Catalog                 | Unaffected                      | No coupling.                                                                                                                                                                                                                       |
| Contacts / Venues                          | Unaffected                      | Gear is a peer feature — no shared state or providers.                                                                                                                                                                             |
| Financials                                 | Unaffected                      | Gear reuses the `_cents INTEGER` convention but does not read from or write to any financial table.                                                                                                                                |
| Notifications                              | Unaffected                      | v1 does not fan out gear events. `notifications.type` enum unchanged.                                                                                                                                                              |
| Calendar / iCal feed                       | Unaffected                      | Gear does not surface on the calendar.                                                                                                                                                                                             |
| Push (FCM / `send-push`)                   | Unaffected                      | No new device-token or webhook interactions.                                                                                                                                                                                       |
| Web push                                   | Unaffected                      | Not applicable to gear.                                                                                                                                                                                                            |
| Platforms (iOS / Android / macOS / Web)    | All affected identically        | Pure Flutter + Supabase; no platform-conditional code required.                                                                                                                                                                    |
| Init order (`main.dart`)                   | Unaffected                      | Not modified.                                                                                                                                                                                                                      |
| Marketing host (`bandroadie.com`)          | Unaffected                      | Gear is inside `AuthGate`, invisible on the marketing host.                                                                                                                                                                        |
| Demo mode (`demo_bands_schema` migrations) | Unknown → Engineer verifies     | Demo templates may want a small seed of example gear so demo users see the feature populated. **Not required for v1** — flag for follow-up. Empty demo gear is acceptable.                                                         |

## Regression Risk

**LOW.**

Reasoning:

- Zero edits to existing DB objects **except** `CREATE OR REPLACE` of
  `public.update_member_role` — same signature, same body except for
  one added SET-clause line, `SECURITY DEFINER`, `SET search_path =
public`, same `GRANT EXECUTE ... TO authenticated` at the tail.
  The other two new migrations are strictly additive: one new column
  with a fail-closed default on `contributor_permissions`, and one new
  `SECURITY DEFINER` helper that swaps only the SELECT policy on the
  cycle-3 base migration's fresh `band_gear` table.
- The `band_gear` table policies only read from `band_members`,
  `contributor_permissions`, and the helper — no recursion class.
- INSERT / UPDATE / DELETE on `band_gear` are **unchanged** by the RBAC
  follow-up (still admin+member only). The visibility toggle governs
  read access only. This preserves the invariant that contributors
  cannot write gear regardless of the toggle.
- The Dart edits are three additive files (`contributor_permissions.
dart` gains one field with full parity; `band_permissions.dart`'s
  `canViewGear` body is swapped from a three-branch OR to the standard
  admin/member/contributor gate already used by `canViewFinancials`
  in the same file; `role_management_sheet.dart` gains one toggle
  matching the existing financials toggle byte-for-byte). No existing
  branches, methods, or state transitions are altered.
- Every step is a **one-for-one mirror** of a pattern this repo has
  already shipped and stabilized for `can_view_financials`. Regression
  surface is limited to the specific bugs that shipped for financials
  on first pass, all of which are explicitly guarded in the Engineer
  Task Breakdown and re-checked in [Verification Plan](#verification-plan).
- No touching of auth, session, routing, init order, notifications,
  push, deep links, or platform-conditional code.
- No new dependencies. No new named routes. No new tabs.

## Engineer Task Breakdown

Ordered, atomic. Each task is one commit's worth. Cycle-3 uncommitted
work covers tasks 1, 5, 6, 7, 8, 12, 13, and 14 — Engineer starts from
that state, commits those as-is, then adds tasks 2–4 and 9–11 for the
scope addition and finishes with task 15.

1. **Base migration** (already present as
   [`supabase/migrations/20260905201000_create_band_gear.sql`](supabase/migrations/20260905201000_create_band_gear.sql)):
   table, two indexes, `ENABLE ROW LEVEL SECURITY`, four RLS policies
   (named to match `contacts` style), `set_band_gear_updated_at`
   trigger. Kept byte-identical from cycle-3.
2. **Migration 1 of 3 — sub-permission column.**
   Add
   `supabase/migrations/<UTC>_add_can_view_gear_to_contributor_permissions.sql`
   with the single `ALTER TABLE ... ADD COLUMN IF NOT EXISTS
can_view_gear BOOLEAN NOT NULL DEFAULT FALSE`. Direct mirror of
   [`20260604000001_add_can_view_financials_to_contributor_permissions.sql`](supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql).
   One atomic commit.
3. **Migration 2 of 3 — RPC fix (do not skip this).**
   Add
   `supabase/migrations/<UTC>_fix_update_member_role_can_view_gear.sql`
   with a full-body `CREATE OR REPLACE FUNCTION public.
update_member_role(UUID, UUID, TEXT, JSONB)`. Body byte-identical to
   [`20260711120000_fix_update_member_role_can_view_financials.sql`](supabase/migrations/20260711120000_fix_update_member_role_can_view_financials.sql)
   except for one new line in the `UPDATE public.contributor_permissions
SET ...` clause:
   `can_view_gear = COALESCE((p_sub_permissions->>'can_view_gear')::boolean, FALSE),`.
   End with the standard `GRANT EXECUTE ... TO authenticated;` line.
   **Do not** rely on the RPC applying `p_sub_permissions` generically —
   this is the exact bug that shipped for financials and had to be
   patched. One atomic commit.
4. **Migration 3 of 3 — RLS helper + SELECT policy swap.**
   Add `supabase/migrations/<UTC>_fix_band_gear_select_rbac.sql` with,
   in order: (a) `CREATE OR REPLACE FUNCTION public.
check_gear_view_permission(p_band_id UUID) RETURNS BOOLEAN LANGUAGE
plpgsql SECURITY DEFINER SET search_path = public` — body mirrors
   `check_financial_view_permission` verbatim with `can_view_gear`
   substituted for `can_view_financials`; (b) `REVOKE ALL ON FUNCTION
public.check_gear_view_permission(UUID) FROM PUBLIC, anon;` and `GRANT
EXECUTE ON FUNCTION public.check_gear_view_permission(UUID) TO
authenticated;` inline; (c) `DROP POLICY IF EXISTS "Band members can
view gear" ON public.band_gear;` then `CREATE POLICY "Band members can
view gear" ON public.band_gear FOR SELECT USING
(public.check_gear_view_permission(band_id));`. INSERT/UPDATE/DELETE
   policies are **not touched**. One atomic commit.
5. **Add the gear model.**
   Create `lib/features/gear/models/gear_item.dart`. Define
   `GearOwnerType` enum with `dbValue` / `fromDbValue`, then the `GearItem`
   immutable class with `fromJson` / `toJson`. Enforce the owner-shape
   invariant with an `assert` in the constructor that mirrors the DB
   `CHECK`.
6. **Add the gear repository.**
   Create `lib/features/gear/gear_repository.dart` matching the shape of
   `ContactsRepository`: per-band `Map<String, _CacheEntry>`, non-null
   `bandId` guard throwing `NoBandSelectedGearError`, and CRUD methods
   returning typed `GearItem`.
7. **Add the gear controller.**
   Create `lib/features/gear/gear_controller.dart` with `GearState`
   (`items`, `isLoading`, `error`, `searchQuery`, `filteredItems`),
   `GearNotifier extends Notifier<GearState>`, and `gearProvider =
NotifierProvider<GearNotifier, GearState>(GearNotifier.new)`.
8. **Cycle-3 permission getters (already in place).**
   `lib/features/members/permissions/band_permissions.dart` already
   defines `canViewGear` and `canManageGear` from cycle-3. Task 10
   below **changes the body** of `canViewGear` only; do not create
   duplicate getters and do not touch `canManageGear`.
9. **Add the sub-permission field on the Dart model.**
   Edit `lib/features/members/permissions/contributor_permissions.dart`
   to add `canViewGear` with `fromJson` / `toJson` / `copyWith` /
   `allEnabled` / `allDisabled` / `toString` parity to the existing
   `canViewFinancials` field. Default `false` in the immutable
   constructor. One atomic commit.
10. **Rewire the `BandPermissions.canViewGear` body.**
    Edit `lib/features/members/permissions/band_permissions.dart` to
    change the body of the existing `canViewGear` getter from `isAdmin
|| isMember || isContributor` to the standard admin/member-always,
    contributor-consults-sub-permission shape shown in [Flutter
    Architecture Changes](#flutter-architecture-changes). Do not touch
    `canManageGear`. One atomic commit.
11. **Wire the Role Management sheet toggle.**
    Edit `lib/features/members/widgets/role_management_sheet.dart` to
    add one new `_buildPermissionToggle` call for `"Can view gear"`
    immediately after the existing "Can view financials" toggle, and
    extend `_permissionsEqual` to compare `a.canViewGear ==
b.canViewGear`. One atomic commit.
12. **Add the gear empty state and row widgets.**
    Create `lib/features/gear/widgets/gear_empty_state.dart` and
    `lib/features/gear/widgets/gear_row.dart` following design-token
    conventions in `AppColors`, `Spacing`, `AppTypography`. Show name,
    owner label ("Band-owned" or member first name + last initial),
    formatted price (via `intl` NumberFormat.currency), and formatted
    purchase date.
13. **Add the gear form sheet.**
    Create `lib/features/gear/widgets/gear_form_sheet.dart` with fields
    for name, purchased-on (date picker), purchased-from, price
    (dollar input converted to cents on save), owner control (band /
    member toggle plus member picker sourced from `membersProvider`
    filtered to `status == 'active'`), and Save / Delete affordances.
    Enforce client-side validation matching the DB `CHECK`
    (member-owned requires a selected member). Use `showAppSnackBar`
    / `showSuccessSnackBar` / `showErrorSnackBar` for feedback.
14. **Add the gear screen.**
    Create `lib/features/gear/gear_screen.dart`. Load gear on init,
    listen for `activeBandProvider` changes and call
    `gearProvider.notifier.reset()` then reload on band switch, gate
    all mutating affordances behind `canManageGear`, and render empty /
    loading / error / list states. No bottom nav — this is a
    full-screen pushed route.
15. **Drawer + shell wiring** (already applied in cycle-3).
    `lib/features/home/widgets/side_drawer.dart` adds one
    `DrawerNavItem` "Gear" and an `onGearTap` callback;
    `lib/features/shell/app_shell.dart` wires it to `Navigator.of(context).
push(MaterialPageRoute(builder: (_) => const GearScreen()))`. Kept
    byte-identical from cycle-3.
16. **Add the model unit test.**
    Create `test/features/gear/gear_item_test.dart` with a
    `fromJson`/`toJson` round-trip case (both `owner_type` values) and
    a `GearOwnerType.fromDbValue` mapping case. Do not test the
    repository or controller against a live Supabase — that's covered
    in Tier 2.
17. **Run `flutter analyze` and `flutter test`, iterate to green.**
    Engineer's normal close-out gate. QA re-verifies.

## Verification Plan

Verification is proportional to the surface — one new table, three
follow-up RBAC migrations mirroring already-shipped precedents, one new
screen, additive drawer entry, one new sub-permission field, one
`BandPermissions` getter body swap, and one new toggle in the Role
Management sheet. There is no complex idempotent submission flow (each
gear write is a single-row `INSERT` or `UPDATE`), so no
serialize-then-re-parse property test is required.

### Accepted deviations (cycle-4 QA report MUST record these)

Two deviations are pre-approved for cycle 4 by Tony's cycle-3
BLOCKED-escalation review. QA is authorized to record them as accepted
and continue toward APPROVED; they do **not** block the verdict.

**Deviation A — Tier 1.3 pre-existing typo failure.** The single failing
case in `test/features/auth/login_screen_demo_button_test.dart` is a
**pre-existing, unrelated** typo bug in
`lib/features/auth/login_screen.dart:657` (renders `'Check out the demo
band'` with lowercase `out`) versus a title-case assertion in the test.
Both files were last touched together in commit `5cd1996` and are
**unmodified by feature/band-gear-management** — QA can confirm by
running `git log --oneline -1 -- lib/features/auth/login_screen.dart
test/features/auth/login_screen_demo_button_test.dart` (expected: a
single common commit `5cd1996`). Filed separately as a one-line
typo/bug fix. Cycle-4 QA reports this specific assertion mismatch as
an accepted deviation, treats the rest of the suite as the T1.3 gate,
and does not block APPROVED on it. Any _new_ failure in that suite
still blocks.

**Deviation B — Tier 1.5 deferral to Tier 2.** The isolated
migration-apply portion of [T1.5](#t15--isolated-migration-apply-check-ephemeral-local-postgres)
remains deferred to Tier 2 owner-run checks under the same repo-wide
broken-migration-chain infra blocker precedent used for
[interactive-demo-band-experience](docs/features/interactive-demo-band-experience/QA_REPORT.md#L15).
Tony runs the migration apply at production apply time. QA marks Tier 1.5
as **DEFERRED to Tier 2** in the cycle-4 report; this is expected, is
recorded as an accepted deviation, and does not block APPROVED.

### KNOWN INFRA BLOCKER — read first

Managed Supabase branch verification (`supabase branches create` +
`supabase db push --project-ref …`) is broken project-wide at historical
migration `073_fix_gig_responses_unique_constraint.sql`, because the
tracked chain in `supabase/migrations/` starts mid-history and references
`public.gig_responses` before it appears in a tracked file. Every fresh
managed branch enters `MIGRATIONS_FAILED` or errors with `relation
"gig_responses" does not exist`. This has now been observed on three
separate features in this repo
([interactive-demo-band-experience](docs/features/interactive-demo-band-experience/ARCHITECT_PLAN.md#L342),
[gig-venue-contact-linking](docs/features/gig-venue-contact-linking/QA_REPORT.md),
and cycle-1 + cycle-2 of this feature). It is a repo-level infra defect,
not a defect of this feature, and fixing it is explicitly [out of
scope](#out-of-scope).

The QA verification path defined below therefore does **not** depend on
managed-branch apply. It uses an ephemeral local Postgres 17 instance
(Docker, `supabase start`, or any locally-installed Postgres 17+) seeded
with a minimal parent-table fixture that is fully specified inline. This
gives QA a reproducible, non-production, non-managed-branch way to
independently confirm the migration parses, applies, and enforces its
constraints. Runtime RLS-behavior checks that require Supabase's real
`auth.uid()` semantics against a populated schema are moved to
[Tier 2](#tier-2--owner-run-at-apply-time-not-a-qa-gate) as
Tony's owner-run gate at apply time, matching the demo-band precedent
that was APPROVED under the same infra blocker.

### Tier 1 — QA gate (must pass for APPROVED verdict)

All Tier 1 steps run against the developer's / QA's local machine only.
Nothing here touches production, the managed staging project, or a
Supabase preview branch.

#### T1.1 — Client analyzer clean

`flutter analyze lib/features/gear lib/features/home/home_tab_content.dart lib/features/home/widgets/quick_actions_row.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart test/features/gear/gear_item_test.dart`
returns `No issues found` at every severity (0 errors, 0 warnings, 0
infos), per the `analysis_options.yaml` policy that promotes AI-slop lints
to error.

Cycle-6 scope note: `side_drawer.dart` and `app_shell.dart` were fully
reverted to `main` (byte-identical, 0 diff) and are no longer feature-
touched — dropped from this command per the standard "pre-existing lints
in files a feature doesn't touch are not that feature's gate" rule that
applies to every other unmodified file in the repo.

#### T1.2 — Feature unit tests green

`flutter test test/features/gear/gear_item_test.dart` — all cases pass
(model `fromJson` / `toJson` round-trip both `owner_type` values;
`GearOwnerType.fromDbValue` mapping; owner-shape `assert` invariant
enforced in-constructor).

#### T1.3 — Full-suite regression guard

`flutter test` (whole suite) green — protects the modified files
(`contributor_permissions.dart`, `band_permissions.dart`,
`role_management_sheet.dart`, `side_drawer.dart`, `app_shell.dart`)
from introducing a regression in an existing test group.

**Accepted deviation** (see [Accepted deviations](#accepted-deviations-cycle-4-qa-report-must-record-these)):
the single pre-existing failing case in
`test/features/auth/login_screen_demo_button_test.dart` (`'Check Out
the Demo Band'` title-case assertion vs. `'Check out the demo band'`
lowercase source string in `login_screen.dart:657`) is unrelated to
this feature and is authorized to remain failing in cycle-4 QA
without blocking APPROVED. Confirm via `git log --oneline -1 --
lib/features/auth/login_screen.dart
test/features/auth/login_screen_demo_button_test.dart` returning
`5cd1996`. Any _other_ new failure in the suite still blocks.

#### T1.4 — Static SQL review of the migrations

Codified per-line checks, grouped by migration file. Each check is a
grep-friendly command and its expected result. Any deviation from the
Expected column is a Critical `database-safety` finding.

**Migration A —
`supabase/migrations/20260905201000_create_band_gear.sql` (base, cycle-3):**

| Check                                                               | Command                                                                                | Expected                         |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | -------------------------------- |
| No `SECURITY DEFINER` (matches plan — base file)                    | `grep -c 'SECURITY DEFINER' <file>`                                                    | `0`                              |
| No new grants beyond RLS defaults (base file)                       | `grep -Ec 'GRANT\|REVOKE' <file>`                                                      | `0`                              |
| RLS enabled on `band_gear`                                          | `grep -c 'ENABLE ROW LEVEL SECURITY' <file>`                                           | `1`                              |
| Exactly 4 policies                                                  | `grep -c '^CREATE POLICY' <file>`                                                      | `4`                              |
| No policy references `band_gear` in its predicate (recursion guard) | `awk '/CREATE POLICY/,/;/' <file> \| grep -c 'FROM public\.band_gear\|FROM band_gear'` | `0`                              |
| Owner-shape `CHECK` constraint present                              | `grep -c 'band_gear_owner_shape' <file>`                                               | `≥ 1`                            |
| `price_cents` non-negative guard                                    | `grep -c 'price_cents IS NULL OR price_cents >= 0' <file>`                             | `1`                              |
| `ON DELETE CASCADE` on `band_id` FK                                 | `grep -c 'REFERENCES public.bands(id) ON DELETE CASCADE' <file>`                       | `1`                              |
| `ON DELETE SET NULL` on `owner_user_id` FK                          | `grep -c 'REFERENCES public.users(id) ON DELETE SET NULL' <file>`                      | `2` (owner_user_id + created_by) |
| Reuses existing `update_updated_at_column` (no re-declaration)      | `grep -c 'CREATE.*FUNCTION.*update_updated_at_column' <file>`                          | `0`                              |
| `set_band_gear_updated_at` trigger present                          | `grep -c 'set_band_gear_updated_at' <file>`                                            | `1`                              |
| Both expected indexes present                                       | `grep -c 'CREATE INDEX idx_band_gear_' <file>`                                         | `2`                              |
| Base SELECT policy exists (will be superseded by Migration D)       | `grep -c '"Band members can view gear" ON public.band_gear' <file>`                    | `1`                              |

**Migration B —
`supabase/migrations/<UTC>_add_can_view_gear_to_contributor_permissions.sql`:**

| Check                                                    | Command                                                          | Expected |
| -------------------------------------------------------- | ---------------------------------------------------------------- | -------- |
| Adds exactly one column                                  | `grep -Ec '^ALTER TABLE' <file>`                                 | `1`      |
| Targets `contributor_permissions`                        | `grep -c 'contributor_permissions' <file>`                       | `≥ 1`    |
| Column name is `can_view_gear`                           | `grep -c 'can_view_gear' <file>`                                 | `≥ 1`    |
| Column is `BOOLEAN NOT NULL DEFAULT FALSE` (fail-closed) | `grep -Ec 'can_view_gear BOOLEAN NOT NULL DEFAULT FALSE' <file>` | `1`      |
| Uses `IF NOT EXISTS` (idempotent replay-safe)            | `grep -c 'ADD COLUMN IF NOT EXISTS' <file>`                      | `1`      |
| No new function or policy                                | `grep -Ec 'CREATE .*FUNCTION\|CREATE POLICY' <file>`             | `0`      |
| No `SECURITY DEFINER`                                    | `grep -c 'SECURITY DEFINER' <file>`                              | `0`      |

**Migration C —
`supabase/migrations/<UTC>_fix_update_member_role_can_view_gear.sql`:**

| Check                                                                                         | Command                                                                                               | Expected |
| --------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | -------- |
| Single `CREATE OR REPLACE FUNCTION public.update_member_role(...)`                            | `grep -Ec '^CREATE OR REPLACE FUNCTION public\.update_member_role' <file>`                            | `1`      |
| Signature matches `(UUID, UUID, TEXT, JSONB)`                                                 | `grep -c 'update_member_role(' <file>` and manual signature review                                    | `≥ 2`    |
| Function is `SECURITY DEFINER` with `SET search_path = public`                                | `grep -c 'SECURITY DEFINER' <file>` and `grep -c 'SET search_path = public' <file>`                   | `1` each |
| **SET clause writes `can_view_gear`** (this is the step that shipped as a bug for financials) | `grep -Ec "can_view_gear\s*=\s*COALESCE\(\(p_sub_permissions->>'can_view_gear'\)" <file>`             | `1`      |
| SET clause default for `can_view_gear` is `FALSE` (fail-closed)                               | `grep -Ec "COALESCE\(\(p_sub_permissions->>'can_view_gear'\)::boolean, FALSE\)" <file>`               | `1`      |
| Preserves `can_view_financials` line unchanged                                                | `grep -Ec "can_view_financials\s*=\s*COALESCE\(\(p_sub_permissions->>'can_view_financials'\)" <file>` | `1`      |
| Ends with `GRANT EXECUTE ... TO authenticated`                                                | `grep -Ec 'GRANT EXECUTE ON FUNCTION public\.update_member_role.*TO authenticated' <file>`            | `1`      |
| No unrelated new policies                                                                     | `grep -c '^CREATE POLICY' <file>`                                                                     | `0`      |

**Migration D —
`supabase/migrations/<UTC>_fix_band_gear_select_rbac.sql`:**

| Check                                                                             | Command                                                                                                     | Expected                |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------- |
| Creates helper `check_gear_view_permission(UUID)` as `SECURITY DEFINER`           | `grep -Ec '^CREATE OR REPLACE FUNCTION.*check_gear_view_permission\(.*UUID\)' <file>`                       | `1`                     |
| Helper sets `search_path = public`                                                | `grep -c 'SET search_path = public' <file>`                                                                 | `≥ 1`                   |
| Helper returns `BOOLEAN`                                                          | `grep -Ec 'RETURNS BOOLEAN' <file>`                                                                         | `1`                     |
| Helper body checks role and `can_view_gear`                                       | `grep -c 'can_view_gear' <file>` and `grep -c "IN \('admin', ?'member'\)" <file>`                           | `≥ 1` each              |
| Inline `REVOKE ALL ... FROM PUBLIC, anon`                                         | `grep -Ec 'REVOKE ALL ON FUNCTION.*check_gear_view_permission.*FROM PUBLIC, ?anon' <file>`                  | `1`                     |
| Inline `GRANT EXECUTE ... TO authenticated`                                       | `grep -Ec 'GRANT EXECUTE ON FUNCTION.*check_gear_view_permission.*TO authenticated' <file>`                 | `1`                     |
| Drops the base SELECT policy by exact name                                        | `grep -c 'DROP POLICY IF EXISTS "Band members can view gear" ON public.band_gear' <file>`                   | `1`                     |
| Recreates SELECT policy using the helper                                          | `grep -Ec 'USING \(public\.check_gear_view_permission\(band_id\)\)' <file>`                                 | `1`                     |
| **INSERT/UPDATE/DELETE policies NOT touched** (contributor write block preserved) | `grep -Ec 'INSERT\|UPDATE\|DELETE' <file>` reviewed manually to confirm none reference `band_gear` policies | 0 policy edits on I/U/D |
| No new columns or triggers                                                        | `grep -Ec '^ALTER TABLE\|^CREATE TRIGGER' <file>`                                                           | `0`                     |

#### T1.5 — Isolated migration apply-check (ephemeral local Postgres)

This is the QA-runnable substitute for the managed-branch apply check that
the KNOWN INFRA BLOCKER makes impossible. It confirms the migration
parses and applies cleanly against the exact minimum parent-table shape
it references, and it exercises the constraint semantics that don't need
`auth.uid()`. Runs entirely on QA's local machine against an ephemeral
container that is destroyed at the end.

**Setup (any one of the three options).** Container image is Postgres 17
to match `supabase/config.toml`'s `[db].major_version = 17`.

- **Option A (preferred, most portable):** `docker run --rm -d --name
qa-gear-pg -e POSTGRES_PASSWORD=postgres -p 55432:5432 postgres:17`;
  connection string `postgresql://postgres:postgres@localhost:55432/postgres`.
- **Option B:** `supabase start` (uses Docker under the hood) and use the
  local dev DB URL from `supabase status`. Use the local dev DB, not
  `supabase db reset` — a reset will attempt to replay the tracked
  chain and hit the same `073` chain defect. Instead, apply the fixture
  and the new migration directly with `psql` against the local dev DB.
- **Option C:** any local Postgres 17+ instance QA already has installed.

**Step 1 — apply the fixture** (paste the block below into a file
`/tmp/qa_gear_fixture.sql`, then `psql "$CONN" -v ON_ERROR_STOP=1 -f
/tmp/qa_gear_fixture.sql`):

```sql
-- QA fixture: minimum parent-table stubs required by the gear migrations
-- (base + 3-part RBAC follow-up). Deliberately trimmed to just the columns
-- the migrations' FKs, RLS policies, RPC, and helper reference. NOT a
-- substitute for the real prod schema.

CREATE SCHEMA IF NOT EXISTS auth;

-- Supabase role stubs so `GRANT EXECUTE ... TO authenticated` and
-- `REVOKE ... FROM anon` in the migrations don't error against the
-- ephemeral fixture. NOLOGIN keeps them non-loginable; SET LOCAL ROLE
-- uses them purely to exercise RLS behavior under a specific role name.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
END $$;

-- Stub auth.uid() so RLS policies can execute against a caller identity
-- controlled by SET LOCAL request.jwt.claim.sub. Standard technique for
-- local RLS testing.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

CREATE TABLE public.bands (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.users (
  id UUID PRIMARY KEY,
  email TEXT
);

-- band_role_type ENUM matches the production shape referenced by
-- update_member_role's `p_new_role::public.band_role_type` cast.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'band_role_type') THEN
    CREATE TYPE public.band_role_type AS ENUM ('admin','member','contributor');
  END IF;
END $$;

CREATE TABLE public.band_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role   public.band_role_type NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive'))
);

-- contributor_permissions matches the production shape update_member_role's
-- UPDATE SET clause writes to. Migration B adds `can_view_gear` to this table.
CREATE TABLE public.contributor_permissions (
  band_member_id UUID PRIMARY KEY REFERENCES public.band_members(id) ON DELETE CASCADE,
  can_create_gigs                BOOLEAN NOT NULL DEFAULT TRUE,
  can_create_potential_gigs_only BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_setlists              BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_calendar              BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_members               BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_financials            BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- The migrations reference this helper for the updated_at trigger.
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
```

**Step 2 — apply the base gear migration:**

```
psql "$CONN" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/20260905201000_create_band_gear.sql
```

Expected: `CREATE TABLE`, two `CREATE INDEX`, `ALTER TABLE`, four `CREATE
POLICY`, one `CREATE TRIGGER`. No warnings, no errors.

**Step 3 — structural assertions** (paste into `/tmp/qa_gear_asserts.sql`
and `psql "$CONN" -v ON_ERROR_STOP=1 -f`):

```sql
-- 1. Table exists and RLS is enabled.
SELECT to_regclass('public.band_gear') AS table_present;             -- expect: band_gear
SELECT relrowsecurity FROM pg_class WHERE relname = 'band_gear';    -- expect: t

-- 2. Exactly four policies exist.
SELECT COUNT(*) AS policy_count FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'band_gear';            -- expect: 4

-- 3. Both indexes exist.
SELECT indexname FROM pg_indexes
WHERE schemaname = 'public' AND tablename = 'band_gear'
ORDER BY indexname;
-- expect rows including: idx_band_gear_band_id, idx_band_gear_owner_user_id

-- 4. Constraint semantics (all four MUST behave as specified):

-- 4a. Owner-shape: band + non-null owner_user_id → CHECK violation.
DO $$
DECLARE ok boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.bands(id, name) VALUES ('00000000-0000-0000-0000-000000000001','B1');
    INSERT INTO public.users(id) VALUES ('00000000-0000-0000-0000-000000000009');
    INSERT INTO public.band_gear(band_id, name, owner_type, owner_user_id)
    VALUES ('00000000-0000-0000-0000-000000000001','x','band',
            '00000000-0000-0000-0000-000000000009');
  EXCEPTION WHEN check_violation THEN ok := true;
  END;
  IF NOT ok THEN RAISE EXCEPTION 'T1.5.4a FAILED — band+non-null owner accepted'; END IF;
END $$;

-- 4b. Owner-shape: member + null owner_user_id → CHECK violation.
DO $$
DECLARE ok boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.band_gear(band_id, name, owner_type, owner_user_id)
    VALUES ('00000000-0000-0000-0000-000000000001','x','member',NULL);
  EXCEPTION WHEN check_violation THEN ok := true;
  END;
  IF NOT ok THEN RAISE EXCEPTION 'T1.5.4b FAILED — member+null owner accepted'; END IF;
END $$;

-- 4c. price_cents = -1 → CHECK violation.
DO $$
DECLARE ok boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.band_gear(band_id, name, owner_type, price_cents)
    VALUES ('00000000-0000-0000-0000-000000000001','x','band',-1);
  EXCEPTION WHEN check_violation THEN ok := true;
  END;
  IF NOT ok THEN RAISE EXCEPTION 'T1.5.4c FAILED — negative price accepted'; END IF;
END $$;

-- 4d. Valid band-owned and valid member-owned inserts both succeed.
INSERT INTO public.band_gear(band_id, name, owner_type)
VALUES ('00000000-0000-0000-0000-000000000001','amp','band');
INSERT INTO public.band_gear(band_id, name, owner_type, owner_user_id)
VALUES ('00000000-0000-0000-0000-000000000001','guitar','member',
        '00000000-0000-0000-0000-000000000009');
SELECT COUNT(*) AS valid_row_count FROM public.band_gear;           -- expect: 2

-- 5. updated_at trigger bumps updated_at on UPDATE.
DO $$
DECLARE t0 timestamptz; t1 timestamptz;
BEGIN
  SELECT updated_at INTO t0 FROM public.band_gear WHERE name='amp';
  PERFORM pg_sleep(0.05);
  UPDATE public.band_gear SET name='amp2' WHERE name='amp';
  SELECT updated_at INTO t1 FROM public.band_gear WHERE name='amp2';
  IF NOT (t1 > t0) THEN RAISE EXCEPTION 'T1.5.5 FAILED — updated_at did not advance'; END IF;
END $$;

-- 6. ON DELETE CASCADE from bands wipes gear.
DELETE FROM public.bands WHERE id='00000000-0000-0000-0000-000000000001';
SELECT COUNT(*) AS cascade_check FROM public.band_gear;             -- expect: 0

-- 7. Recreate a band/user, add gear, then delete the user → owner_user_id
--    becomes NULL, row survives.
INSERT INTO public.bands(id,name) VALUES ('00000000-0000-0000-0000-000000000002','B2');
INSERT INTO public.users(id) VALUES ('00000000-0000-0000-0000-00000000000A');
INSERT INTO public.band_gear(band_id,name,owner_type,owner_user_id)
VALUES ('00000000-0000-0000-0000-000000000002','bass','member',
        '00000000-0000-0000-0000-00000000000A');
DELETE FROM public.users WHERE id='00000000-0000-0000-0000-00000000000A';
SELECT COUNT(*) FILTER (WHERE owner_user_id IS NULL) AS null_owner_after_user_delete,
       COUNT(*) AS row_still_present
FROM public.band_gear WHERE name='bass';                            -- expect: 1, 1
```

Every `DO $$` block raises with an explicit failure message if the
expected constraint semantics are wrong. Every `SELECT` row is compared
against the `-- expect:` comment. Any mismatch is a Critical
`database-safety` finding.

**Step 4 — apply the 3-part RBAC follow-up migrations, in order:**

```
psql "$CONN" -v ON_ERROR_STOP=1 \
  -f supabase/migrations/<UTC>_add_can_view_gear_to_contributor_permissions.sql \
  -f supabase/migrations/<UTC>_fix_update_member_role_can_view_gear.sql \
  -f supabase/migrations/<UTC>_fix_band_gear_select_rbac.sql
```

Expected: one `ALTER TABLE`, two `CREATE OR REPLACE FUNCTION`, one
`REVOKE`, two `GRANT`, one `DROP POLICY`, one `CREATE POLICY`. No
warnings, no errors.

**Step 5 — RBAC structural + behavior assertions** (paste into
`/tmp/qa_gear_rbac_asserts.sql` and
`psql "$CONN" -v ON_ERROR_STOP=1 -f`). These cover the contributor
visibility gate end-to-end: column schema, RPC SET clause, helper
function, revised SELECT policy, and full role-behavior matrix.

```sql
-- 8. Sub-permission column present with fail-closed default.
SELECT column_name, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name='contributor_permissions'
  AND column_name='can_view_gear';
-- expect: can_view_gear | NO | false

-- 9. Helper function exists with the right shape.
SELECT
  p.proname                 AS name,
  p.prosecdef               AS is_security_definer,   -- expect: t
  pg_get_function_result(p.oid) AS result_type,       -- expect: boolean
  array_to_string(p.proconfig, ',') AS config          -- expect: search_path=public
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='check_gear_view_permission';

-- 10. Revised SELECT policy on band_gear references the helper.
SELECT policyname, cmd, qual
FROM pg_policies
WHERE schemaname='public' AND tablename='band_gear' AND cmd='SELECT';
-- expect: policyname='Band members can view gear', cmd='SELECT',
-- qual contains 'check_gear_view_permission(band_id)'

-- 11. Full RBAC visibility matrix.
--     Fixture: band B3, one admin, one member, two contributors
--     (one with can_view_gear=TRUE, one with =FALSE), two gear rows.

INSERT INTO public.bands(id,name) VALUES
  ('00000000-0000-0000-0000-000000000003','B3');
INSERT INTO public.users(id) VALUES
  ('00000000-0000-0000-0000-0000000000A1'),  -- admin_u
  ('00000000-0000-0000-0000-0000000000A2'),  -- member_u
  ('00000000-0000-0000-0000-0000000000A3'),  -- contrib_u (toggle OFF)
  ('00000000-0000-0000-0000-0000000000A4');  -- contrib_u (toggle ON)

INSERT INTO public.band_members(id, band_id, user_id, role, status) VALUES
  ('00000000-0000-0000-0000-0000000000B1','00000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-0000000000A1','admin','active'),
  ('00000000-0000-0000-0000-0000000000B2','00000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-0000000000A2','member','active'),
  ('00000000-0000-0000-0000-0000000000B3','00000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-0000000000A3','contributor','active'),
  ('00000000-0000-0000-0000-0000000000B4','00000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-0000000000A4','contributor','active');

INSERT INTO public.contributor_permissions(band_member_id, can_view_gear) VALUES
  ('00000000-0000-0000-0000-0000000000B3', FALSE),
  ('00000000-0000-0000-0000-0000000000B4', TRUE);

INSERT INTO public.band_gear(band_id, name, owner_type) VALUES
  ('00000000-0000-0000-0000-000000000003','snare','band'),
  ('00000000-0000-0000-0000-000000000003','kick','band');

-- Use a helper procedure that runs each check as a specific caller identity
-- inside a transaction with SET LOCAL request.jwt.claim.sub.
-- 11a. admin sees both rows regardless of any toggle.
DO $$
DECLARE n bigint;
BEGIN
  SET LOCAL row_security = on;
  SET LOCAL role = 'authenticated';
  PERFORM set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-0000000000A1', true);
  SELECT COUNT(*) INTO n FROM public.band_gear
    WHERE band_id='00000000-0000-0000-0000-000000000003';
  IF n <> 2 THEN RAISE EXCEPTION 'T1.5.11a FAILED — admin saw % rows, expected 2', n; END IF;
END $$;

-- 11b. member sees both rows regardless of any toggle.
DO $$
DECLARE n bigint;
BEGIN
  SET LOCAL row_security = on;
  SET LOCAL role = 'authenticated';
  PERFORM set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-0000000000A2', true);
  SELECT COUNT(*) INTO n FROM public.band_gear
    WHERE band_id='00000000-0000-0000-0000-000000000003';
  IF n <> 2 THEN RAISE EXCEPTION 'T1.5.11b FAILED — member saw % rows, expected 2', n; END IF;
END $$;

-- 11c. contributor with can_view_gear=FALSE sees ZERO rows.
DO $$
DECLARE n bigint;
BEGIN
  SET LOCAL row_security = on;
  SET LOCAL role = 'authenticated';
  PERFORM set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-0000000000A3', true);
  SELECT COUNT(*) INTO n FROM public.band_gear
    WHERE band_id='00000000-0000-0000-0000-000000000003';
  IF n <> 0 THEN RAISE EXCEPTION 'T1.5.11c FAILED — contributor(toggle=FALSE) saw % rows, expected 0 — RBAC BYPASS', n; END IF;
END $$;

-- 11d. contributor with can_view_gear=TRUE sees BOTH rows.
DO $$
DECLARE n bigint;
BEGIN
  SET LOCAL row_security = on;
  SET LOCAL role = 'authenticated';
  PERFORM set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-0000000000A4', true);
  SELECT COUNT(*) INTO n FROM public.band_gear
    WHERE band_id='00000000-0000-0000-0000-000000000003';
  IF n <> 2 THEN RAISE EXCEPTION 'T1.5.11d FAILED — contributor(toggle=TRUE) saw % rows, expected 2', n; END IF;
END $$;

-- 12. INSERT / UPDATE / DELETE must still block contributors even when
--     can_view_gear=TRUE — the visibility toggle governs read access only.
--     Both contributor B3 (toggle OFF) and contributor B4 (toggle ON) are
--     denied writes.
DO $$
DECLARE ok boolean := false;
BEGIN
  SET LOCAL row_security = on;
  SET LOCAL role = 'authenticated';
  PERFORM set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-0000000000A4', true);  -- toggle=TRUE
  BEGIN
    INSERT INTO public.band_gear(band_id, name, owner_type)
    VALUES ('00000000-0000-0000-0000-000000000003','forbidden-insert','band');
  EXCEPTION WHEN insufficient_privilege OR check_violation THEN ok := true;
  END;
  IF NOT ok THEN
    RAISE EXCEPTION 'T1.5.12 INSERT FAILED — contributor with toggle=TRUE could still INSERT — CONTRIBUTOR WRITE BYPASS';
  END IF;
END $$;

DO $$
DECLARE ok boolean := false;
BEGIN
  SET LOCAL row_security = on;
  SET LOCAL role = 'authenticated';
  PERFORM set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-0000000000A4', true);
  BEGIN
    UPDATE public.band_gear SET name='forbidden-update'
    WHERE band_id='00000000-0000-0000-0000-000000000003' AND name='snare';
    -- RLS in Postgres does not raise on 0-row updates from a policy mismatch;
    -- it silently updates 0 rows. Confirm 0 rows were touched.
    IF FOUND THEN ok := false; ELSE ok := true; END IF;
  END;
  IF NOT ok THEN
    RAISE EXCEPTION 'T1.5.12 UPDATE FAILED — contributor with toggle=TRUE mutated a gear row';
  END IF;
END $$;

DO $$
DECLARE ok boolean := false;
BEGIN
  SET LOCAL row_security = on;
  SET LOCAL role = 'authenticated';
  PERFORM set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-0000000000A4', true);
  BEGIN
    DELETE FROM public.band_gear
    WHERE band_id='00000000-0000-0000-0000-000000000003' AND name='snare';
    IF FOUND THEN ok := false; ELSE ok := true; END IF;
  END;
  IF NOT ok THEN
    RAISE EXCEPTION 'T1.5.12 DELETE FAILED — contributor with toggle=TRUE deleted a gear row';
  END IF;
END $$;

-- 13. update_member_role RPC persists can_view_gear (the bug that shipped
--     for financials must not re-ship for gear).
DO $$
DECLARE saved BOOLEAN;
BEGIN
  SET LOCAL row_security = on;
  -- Call as an authenticated admin of the band.
  PERFORM set_config('request.jwt.claim.sub',
    '00000000-0000-0000-0000-0000000000A1', true);  -- admin_u
  -- Flip contributor B3's can_view_gear from FALSE → TRUE via the RPC.
  PERFORM public.update_member_role(
    '00000000-0000-0000-0000-0000000000B3'::uuid,
    '00000000-0000-0000-0000-000000000003'::uuid,
    'contributor',
    jsonb_build_object('can_view_gear', TRUE)
  );
  SELECT can_view_gear INTO saved
  FROM public.contributor_permissions
  WHERE band_member_id='00000000-0000-0000-0000-0000000000B3';
  IF saved IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'T1.5.13 FAILED — update_member_role did not persist can_view_gear (still %). This is the exact bug that shipped for financials in 20260604 → 20260711.', saved;
  END IF;
END $$;
```

Every `DO $$` block raises with an explicit failure message if the
expected constraint or RBAC semantics are wrong. Every `SELECT` row
is compared against the `-- expect:` comment. Any mismatch is a
Critical `database-safety` finding.

**Step 6 — teardown.** `docker rm -f qa-gear-pg` (Option A) or
`supabase stop` (Option B). The ephemeral container carries no state
between runs.

Success on T1.5 is what QA cites as the "migrations apply cleanly and
enforce their documented constraints and RBAC gates" evidence in the
QA report, replacing the managed-branch apply check that this repo's
infra does not support. **Under cycle 4's accepted deviation ([Deviation
B](#accepted-deviations-cycle-4-qa-report-must-record-these)), the full
T1.5 block is deferred to Tier 2 owner-run at apply time — QA marks
T1.5 as DEFERRED and does not attempt to execute it in cycle 4.**

#### T1.6 — Engineer manual smoke (already performed)

Switch to a band as `admin`, open drawer → Gear, add / edit / delete a
band-owned item and a member-owned item, verify member picker only lists
active members of the active band, switch bands and confirm gear list
swaps. Engineer executes on macOS or Chrome and records the outcome in
`ENGINEER_REPORT.md`. QA does not re-run this — its role in Tier 1 is
that Engineer performed it and reported honestly.

### Tier 2 — Owner-run at apply time (NOT a QA gate)

Runtime RLS-behavior checks that require Supabase's real `auth.uid()`
and JWT-claim wiring, plus the `anon`/`authenticated`/`service_role`
grant sanity checks on the real production role set, cannot be
reproduced faithfully against the T1.5 ephemeral container (its
`auth.uid()` is a local stub; `anon` / `authenticated` / `service_role`
are role stubs, not the real Supabase-managed roles). Tony runs these
checks manually at apply time against production or a scratch project
of his choosing. QA marks Tier 2 as DEFERRED per the KNOWN INFRA
BLOCKER and [Deviation
B](#accepted-deviations-cycle-4-qa-report-must-record-these); this is
expected and does not block APPROVED.

**Migration apply order (Tony runs these in order at apply time):**

1. `supabase/migrations/20260905201000_create_band_gear.sql`
2. `supabase/migrations/<UTC>_add_can_view_gear_to_contributor_permissions.sql`
3. `supabase/migrations/<UTC>_fix_update_member_role_can_view_gear.sql`
4. `supabase/migrations/<UTC>_fix_band_gear_select_rbac.sql`

Applying them in the wrong order — specifically, applying Migration 4
before Migration 2 — will error on the missing `can_view_gear`
column reference inside the helper. Apply top-to-bottom.

**Owner-run checks at apply time (post-apply):**

_Base table grant sanity:_

1. `SELECT has_table_privilege('anon', 'public.band_gear', 'SELECT');`
   → `false`. No anon exposure.
2. `SELECT has_table_privilege('anon', 'public.band_gear', 'INSERT');`
   → `false`.
3. `SELECT has_table_privilege('authenticated', 'public.band_gear', 'SELECT');`
   → `true` (RLS still gates the actual rows visible).

_Sub-permission column + helper function grants:_

4. Sub-permission column exists with fail-closed default:

   ```sql
   SELECT column_name, is_nullable, column_default
   FROM information_schema.columns
   WHERE table_schema='public'
     AND table_name='contributor_permissions'
     AND column_name='can_view_gear';
   -- expect: (can_view_gear, NO, false)
   ```

5. Helper function has correct execute grants — verify via
   `has_function_privilege` (never string-match on the raw ACL, since a
   `PUBLIC` grant satisfies a role-specific check for every role even
   when no explicit named grant exists):

   ```sql
   SELECT
     has_function_privilege('authenticated',
       'public.check_gear_view_permission(uuid)'::regprocedure,
       'EXECUTE')  AS authenticated_can_execute,       -- expect: t
     has_function_privilege('anon',
       'public.check_gear_view_permission(uuid)'::regprocedure,
       'EXECUTE')  AS anon_can_execute,                 -- expect: f
     has_function_privilege('PUBLIC',
       'public.check_gear_view_permission(uuid)'::regprocedure,
       'EXECUTE')  AS public_can_execute;              -- expect: f
   ```

6. Helper is `SECURITY DEFINER` with `search_path` locked to `public`:

   ```sql
   SELECT
     p.prosecdef                        AS is_security_definer,   -- expect: t
     array_to_string(p.proconfig, ',')  AS config                 -- expect: contains 'search_path=public'
   FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='check_gear_view_permission';
   ```

7. Revised SELECT policy on `band_gear` calls the helper:

   ```sql
   SELECT policyname, cmd, qual
   FROM pg_policies
   WHERE schemaname='public' AND tablename='band_gear' AND cmd='SELECT';
   -- expect: qual contains 'check_gear_view_permission(band_id)'
   ```

_Live app RBAC walkthrough (numbered punch list for Tony, verbatim):_

8. Sign in as an active `admin` of a real band. Insert / update / delete
   a gear row through the app UI, confirm success on both platforms
   Tony is deploying to that day.
   - Expected: all three operations succeed.
9. Sign in as an active `member` of the same band. Repeat step 8.
   - Expected: all three operations succeed.
10. Sign in as an active `contributor` of the same band **whose
    `contributor_permissions.can_view_gear = FALSE`** (Tony can set
    this via the Role Management sheet's "Can view gear" toggle before
    running this step, or via `UPDATE public.contributor_permissions
SET can_view_gear = FALSE WHERE band_member_id = '<contributor's
band_member_id>';`). Confirm: - Expected: the Gear entry may still appear in the side drawer
    (client-side visibility is a UX choice) **but** the Gear list is
    empty; a direct SELECT via a Supabase client using the
    contributor's JWT returns 0 rows for that band; Add/Edit/Delete
    affordances are hidden by the UI; a direct `insert`/`update`/
    `delete` bypassing the UI is refused (INSERT: `new row violates
row-level security policy for table "band_gear"`; UPDATE/DELETE:
    silently affects 0 rows).
11. Flip that contributor's `can_view_gear` to `TRUE` via the Role
    Management sheet, save, re-open the sheet as the admin, confirm the
    toggle **persists as TRUE** on reload (this is the exact
    "toggle appears to save but reverts on reload" bug the RPC-fix
    migration prevents).
    - Expected: reload shows `can_view_gear = TRUE`.
12. Sign back in as that contributor. Confirm:
    - Expected: Gear list now shows all rows for that band; Add / Edit
      / Delete affordances **remain hidden** (visibility toggle does
      NOT grant write access); a direct `insert`/`update`/`delete`
      bypassing the UI is still refused.
13. Sign in as a user who is not a member of that band. Confirm zero
    `band_gear` rows are returned for that band's UUID.
14. Confirm the four expected policies exist and target the right
    commands:

    ```sql
    SELECT policyname, cmd, roles
    FROM pg_policies
    WHERE schemaname='public' AND tablename='band_gear'
    ORDER BY policyname;
    -- expect: 4 rows, SELECT/INSERT/UPDATE/DELETE, all targeting {public}
    -- (RLS-gated) — the SELECT row's policyname is "Band members can view gear"
    -- and its qual references public.check_gear_view_permission.
    ```

If any check surprises Tony, he uses the rollback path in
[Rollout Strategy](#rollout-strategy).

## QA Regression Areas

QA focus, in priority order:

1. **Side drawer navigation** — every existing item (My Profile,
   Settings, Tips & Tricks, Report Bugs, Exit Demo, Log Out) still opens
   the correct screen; drawer stagger animations unchanged; new Gear entry
   appears and pushes correctly on all four platforms.
2. **Permission gating — RBAC toggle end-to-end.** `admin` and `member`
   always see Add / Edit / Delete affordances; `contributor` with
   `can_view_gear = FALSE` sees no gear list; `contributor` with
   `can_view_gear = TRUE` sees the list but no mutating controls;
   direct writes attempted by any contributor (either toggle state) are
   refused by RLS. **Verify toggle persistence:** flip "Can view gear"
   in the Role Management sheet for a contributor, save, close, re-open
   — the toggle must still be TRUE (this catches the exact bug the
   RPC-fix migration prevents). Sign in as each role on the same band
   and verify.
3. **Band isolation** — as a user in two bands, add gear to band A, switch
   to band B, confirm gear list is empty (not band A's list); switch back
   to A and confirm gear reappears with no stale cache leakage. Verify the
   `activeBandProvider` listener fires `reset()`.
4. **No-band state** — a user with no bands must not see the Gear entry
   crash; either the drawer entry is hidden or the screen renders a
   no-band empty state. (Engineer picks whichever matches existing
   drawer-entry behavior for band-scoped screens.)
5. **Owner constraint** — try to save a member-owned item without
   selecting a member; form validation must block, and if the client is
   bypassed the DB `CHECK` blocks.
6. **Contacts / Venues / Members / Setlists / Gigs / Rehearsals /
   Calendar / Financials smoke** — quick visit to each on a shared band,
   nothing changed; permission gates on those screens unchanged. Any
   regression here is a red flag because the only shared touch-point is
   `BandPermissions`.
7. **Marketing host** — visit `bandroadie.com` on web; the landing page is
   unchanged and no gear surface leaks onto the marketing host.
8. **Init / cold start** — cold-start on iOS, Android, macOS, and Web;
   log the init-order sequence and confirm it matches the documented
   `WidgetsFlutterBinding → URL strategy → orientation lock →
AppVersionService.init → validateSupabaseConfig → Supabase.initialize →
Firebase.initializeApp (native only) → DeepLinkService → runApp` order.

## Rollout Strategy

1. **Migration deploy.** Tony applies the four migrations in order,
   top-to-bottom, to production manually (`supabase db push --linked`
   or equivalent — his standard flow, outside this pipeline):
   1. `supabase/migrations/20260905201000_create_band_gear.sql`
   2. `supabase/migrations/<UTC>_add_can_view_gear_to_contributor_permissions.sql`
   3. `supabase/migrations/<UTC>_fix_update_member_role_can_view_gear.sql`
   4. `supabase/migrations/<UTC>_fix_band_gear_select_rbac.sql`

   Applying Migration 4 before Migration 2 errors on a missing
   `can_view_gear` column reference in the helper — so ordering matters.
   Immediately after apply, Tony runs the [Tier 2 owner-run
   checks](#tier-2--owner-run-at-apply-time-not-a-qa-gate) against
   production to confirm RLS behavior, RBAC toggle behavior, function
   grants (`has_function_privilege(...)`), and `anon` grant sanity all
   match the plan. No data backfill required — table starts empty; the
   sub-permission column has a fail-closed `FALSE` default for existing
   contributor rows.

2. **App deploy.** Standard Vercel web deploy via `tools/deploy_web.sh`,
   followed by native TestFlight / internal-track builds on the normal
   release cadence.
3. **No feature flag.** The feature ships behind existing permission gates
   (RLS + `canManageGear` for writes, RLS + `canViewGear` +
   `check_gear_view_permission` for reads) — those are sufficient
   control surfaces.
4. **Rollback path.** Additive; rolling back the app deploy hides the
   surface with no data impact. Rolling back the RBAC follow-up
   migrations (Migrations 2–4) is:

   ```sql
   -- Reverse Migration 4 (restore base SELECT policy)
   DROP POLICY IF EXISTS "Band members can view gear" ON public.band_gear;
   CREATE POLICY "Band members can view gear" ON public.band_gear
     FOR SELECT USING (
       EXISTS (SELECT 1 FROM public.band_members bm
               WHERE bm.band_id = band_gear.band_id
                 AND bm.user_id = auth.uid()
                 AND bm.status = 'active')
     );
   DROP FUNCTION IF EXISTS public.check_gear_view_permission(uuid);

   -- Reverse Migration 3 (revert update_member_role to pre-can_view_gear
   -- shape — re-apply 20260711120000_fix_update_member_role_can_view_financials.sql
   -- verbatim)

   -- Reverse Migration 2 (drop the sub-permission column)
   ALTER TABLE public.contributor_permissions DROP COLUMN IF EXISTS can_view_gear;
   ```

   Rolling back the base migration is `DROP TABLE public.band_gear
CASCADE;` — no other object depends on it, and cascade only removes
   RLS policies + trigger + indexes on that table. If both are rolled
   back, drop the RBAC layer first, then the base table.

5. **Docs.** After merge, Engineer or Tony updates
   [docs/reference/architecture/database_schema.md](docs/reference/architecture/database_schema.md)
   to list `band_gear` under a new "Gear" section, and adds
   `can_view_gear` to the existing `contributor_permissions` column
   list next to `can_view_financials`. `RUNTIME_CONFIG.md` and
   `AI_DECISIONS.md` need **no** update — no init-order, platform-parity,
   or config decision was made.

## Out of Scope

Explicitly not part of v1 — do not implement, do not scaffold, do not add
DB columns "in preparation":

- Maintenance / service history logs
- Insurance values, replacement values, depreciation
- Receipts, photos, file attachments, image URLs, storage buckets
- Serial numbers, model numbers, purchase order numbers
- Lending / check-out / return workflows
- Per-gig or per-rehearsal equipment assignments
- Bulk import / CSV ingestion of gear
- Gear-specific notifications, push, or email
- Reporting, financial roll-ups, or cross-references from `financial_entries`
- Search / filter beyond simple name substring (add later if requested)
- Reordering / manual sort of gear rows
- Gear-level permissions or per-item ACLs
- Category / tag / instrument-type taxonomy
- Cross-band gear sharing
- **Fixing the repo-wide managed-Supabase-branch chain defect at
  historical migration `073`.** This blocks `supabase branches create` +
  `supabase db push --project-ref …` on any feature that adds a migration.
  It has to be resolved separately (its own feature/bug) — either by
  backfilling the missing pre-`073` migrations into
  `supabase/migrations/`, or by adopting `supabase db dump --schema public`
  as a baseline snapshot the tracked chain rebases onto. The verification
  approach defined in this plan explicitly routes around this defect so
  gear can ship without waiting on the fix.
