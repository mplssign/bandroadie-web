# ENGINEER_REPORT

## Feature Slug

feature/band-gear-management

## Feature Title

Band Gear Management

## Cycle Number

4

## Goal

Implement the contributor visibility gate scope addition from the Architect
cycle-3 revision (three follow-up RBAC migrations + Dart parity edits) and
re-run the Tier 1 verification procedure. Cycle-3 uncommitted implementation
work is unchanged and rolls forward as-is.

## Architect Tasks Completed

Cycle 4 (this cycle):

- Task 2 — Migration 1 of 3 (sub-permission column): Completed. Added
  `supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql`
  with `ALTER TABLE public.contributor_permissions ADD COLUMN IF NOT EXISTS
can_view_gear BOOLEAN NOT NULL DEFAULT FALSE;`, direct mirror of
  `20260604000001_add_can_view_financials_to_contributor_permissions.sql`.
- Task 3 — Migration 2 of 3 (RPC fix): Completed. Added
  `supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql`
  with a full-body `CREATE OR REPLACE FUNCTION public.update_member_role(UUID,
UUID, TEXT, JSONB)` mirroring
  `20260711120000_fix_update_member_role_can_view_financials.sql`, adding
  exactly one SET-clause line `can_view_gear = COALESCE((p_sub_permissions->>
'can_view_gear')::boolean, FALSE),`. Terminates with `GRANT EXECUTE ON
FUNCTION public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;`.
- Task 4 — Migration 3 of 3 (RLS helper + SELECT policy swap): Completed.
  Added `supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql`
  with (a) `CREATE OR REPLACE FUNCTION public.check_gear_view_permission(
p_band_id UUID) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET
search_path = public` body mirroring `check_financial_view_permission`;
  (b) `REVOKE ALL ON FUNCTION public.check_gear_view_permission(UUID) FROM
PUBLIC, anon;` and `GRANT EXECUTE ON FUNCTION public.check_gear_view_permission(
UUID) TO authenticated;`; (c) `DROP POLICY IF EXISTS "Band members can view
gear" ON public.band_gear;` then `CREATE POLICY "Band members can view gear"
ON public.band_gear FOR SELECT USING (public.check_gear_view_permission(
band_id));`. INSERT / UPDATE / DELETE policies are not touched.
- Task 9 — Sub-permission field on Dart model: Completed. Edited
  `lib/features/members/permissions/contributor_permissions.dart` to add a
  `canViewGear` field with `fromJson` / `toJson` / `copyWith` / `allEnabled`
  / `allDisabled` / `toString` parity to `canViewFinancials`, defaulting
  `false` in the immutable constructor.
- Task 10 — Rewire `BandPermissions.canViewGear` body: Completed. Edited
  `lib/features/members/permissions/band_permissions.dart` to change the
  `canViewGear` getter body from `isAdmin || isMember || isContributor` to
  `isAdmin || isMember` for the admin/member branch and
  `subPermissions?.canViewGear ?? false` for the contributor branch.
  `canManageGear` unchanged.
- Task 11 — Role Management sheet toggle: Completed. Edited
  `lib/features/members/widgets/role_management_sheet.dart` to add one new
  `_buildPermissionToggle` "Can view gear" immediately after "Can view
  financials" (wired to `_subPermissions.canViewGear` /
  `copyWith(canViewGear: v)`), and extended `_permissionsEqual` to compare
  `a.canViewGear == b.canViewGear`.
- Task 16 — Model unit test: Verified (already added in cycle-3 uncommitted
  work as `test/features/gear/gear_item_test.dart`). Re-run in T1.2: 5/5
  pass.
- Task 17 — `flutter analyze` + `flutter test` iterate to green: Completed.
  Analyzer clean at every severity across the T1.1 file list; feature tests
  green; full-suite failure is the single accepted deviation A.

Inherited from cycle-3 uncommitted work (unchanged this cycle):

- Task 1 — Base migration
  `supabase/migrations/20260905201000_create_band_gear.sql` (table, indexes,
  RLS enable, four RLS policies, `set_band_gear_updated_at` trigger).
- Task 5 — `lib/features/gear/models/gear_item.dart`.
- Task 6 — `lib/features/gear/gear_repository.dart`.
- Task 7 — `lib/features/gear/gear_controller.dart`.
- Task 8 — Cycle-3 `canViewGear` / `canManageGear` getters already present in
  `lib/features/members/permissions/band_permissions.dart` (task 10 above
  swaps `canViewGear`'s body only).
- Task 12 — `lib/features/gear/widgets/gear_empty_state.dart` and
  `lib/features/gear/widgets/gear_row.dart`.
- Task 13 — `lib/features/gear/widgets/gear_form_sheet.dart`.
- Task 14 — `lib/features/gear/gear_screen.dart`.
- Task 15 — Drawer + shell wiring in
  `lib/features/home/widgets/side_drawer.dart` and
  `lib/features/shell/app_shell.dart`.

## Files Created

Cycle 4 (new this cycle):

- supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql
- supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql
- supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql

Inherited from cycle-3 uncommitted work (byte-identical to cycle 3):

- supabase/migrations/20260905201000_create_band_gear.sql
- lib/features/gear/models/gear_item.dart
- lib/features/gear/gear_repository.dart
- lib/features/gear/gear_controller.dart
- lib/features/gear/gear_screen.dart
- lib/features/gear/widgets/gear_row.dart
- lib/features/gear/widgets/gear_form_sheet.dart
- lib/features/gear/widgets/gear_empty_state.dart
- test/features/gear/gear_item_test.dart
- docs/features/feature-band-gear-management/ENGINEER_REPORT.md

## Files Modified

Cycle 4 (new this cycle):

- lib/features/members/permissions/contributor_permissions.dart — added
  `canViewGear` field with `fromJson` / `toJson` / `copyWith` / `allEnabled`
  / `allDisabled` / `toString` parity to `canViewFinancials`.
- lib/features/members/permissions/band_permissions.dart — swapped the body
  of the existing `canViewGear` getter from unconditional
  `isAdmin || isMember || isContributor` to admin/member-always plus
  contributor-consults-sub-permission; `canManageGear` untouched.
- lib/features/members/widgets/role_management_sheet.dart — added one new
  "Can view gear" `_buildPermissionToggle` after the existing "Can view
  financials" toggle; extended `_permissionsEqual` with
  `a.canViewGear == b.canViewGear`.

Inherited from cycle-3 uncommitted work (byte-identical to cycle 3):

- lib/features/home/widgets/side_drawer.dart
- lib/features/shell/app_shell.dart

## Analyzer Results

Command run:

```
flutter analyze lib/features/gear lib/features/home/widgets/side_drawer.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart lib/features/shell/app_shell.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 7 items...
No issues found! (ran in 3.0s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`.

## Test Results

Commands run:

- `flutter test test/features/gear/gear_item_test.dart` (T1.2)
- `flutter test` (T1.3)

Results:

- T1.2 `flutter test test/features/gear/gear_item_test.dart`:
  `00:01 +5: All tests passed!` — 5/5 pass.
- T1.3 `flutter test`: `00:26 +218 -1: Some tests failed.` The single
  failure is:

  ```
  /Users/tonyholmes/apps/bandroadie/test/features/auth/login_screen_demo_button_test.dart: Test A: "Check Out the Demo Band" button is visible on LoginScreen
  ```

  This is Deviation A — the pre-existing, unrelated typo mismatch pre-
  approved by Tony's cycle-3 review. `lib/features/auth/login_screen.dart:657`
  renders `'Check out the demo band'` (lowercase `out`) while the test
  asserts title case; both files were last touched together in commit
  `5cd1996` and are unmodified by `feature/band-gear-management`. All 218
  other tests pass, satisfying the T1.3 gate per the plan's accepted-
  deviation clause.

## T1.4 Static SQL Evidence

Commands run in `supabase/migrations/`.

### 20260905201000_create_band_gear.sql (base, unchanged from cycle 3)

- `^CREATE POLICY`: **4** (SELECT / INSERT / UPDATE / DELETE)
- `ENABLE ROW LEVEL SECURITY`: **1**
- `^CREATE TRIGGER set_band_gear_updated_at`: **1**
- `^CREATE INDEX idx_band_gear_`: **2** (`_band_id`, `_owner_user_id`)
- `CONSTRAINT band_gear_owner_shape CHECK`: **1**
- `price_cents.*CHECK`: **1** (`price_cents INTEGER CHECK (price_cents IS
NULL OR price_cents >= 0)`)
- `REFERENCES public.bands(id) ON DELETE CASCADE`: **1**
- `REFERENCES public.users(id) ON DELETE SET NULL`: **2**
- `SECURITY DEFINER`: **0**
- `^GRANT|^REVOKE`: **0** (base migration relies solely on RLS)

### 20260906120000_add_can_view_gear_to_contributor_permissions.sql

- `ADD COLUMN IF NOT EXISTS can_view_gear BOOLEAN NOT NULL DEFAULT FALSE`:
  **1**
- Body is a single `ALTER TABLE public.contributor_permissions` statement;
  no other DDL/DML.

### 20260906120001_fix_update_member_role_can_view_gear.sql

- `CREATE OR REPLACE FUNCTION public.update_member_role`: **1**
- `^GRANT EXECUTE`: **1** (`GRANT EXECUTE ON FUNCTION
public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;`)
- `can_view_gear = COALESCE`: **1** (single new SET-clause line
  `can_view_gear = COALESCE((p_sub_permissions->>'can_view_gear')::boolean,
FALSE),`)
- Header carries `LANGUAGE plpgsql / SECURITY DEFINER`; body opens with
  `SET search_path = public;` per Architect guardrail.

### 20260906120002_fix_band_gear_select_rbac.sql

- `CREATE OR REPLACE FUNCTION public.check_gear_view_permission`: **1**
- `SECURITY DEFINER`: **1**
- `SET search_path = public`: **1**
- `REVOKE ALL ON FUNCTION public.check_gear_view_permission(UUID) FROM
PUBLIC, anon`: **1**
- `GRANT EXECUTE ON FUNCTION public.check_gear_view_permission(UUID) TO
authenticated`: **1**
- `DROP POLICY IF EXISTS "Band members can view gear" ON public.band_gear`:
  **1**
- `CREATE POLICY "Band members can view gear" ON public.band_gear`: **1**
- `USING (public.check_gear_view_permission(band_id))`: **1**
- `FOR INSERT|FOR UPDATE|FOR DELETE`: **0** — INSERT / UPDATE / DELETE
  policies untouched, as required.

## T1.5 — Isolated Migration Apply-Check

**Deferred to Tier 2** per accepted Deviation B. The isolated apply-check
remains blocked by the repo-wide broken-migration-chain infra defect at
`073_fix_gig_responses_unique_constraint.sql` (see plan's KNOWN INFRA
BLOCKER section). Per the demo-band precedent
(`docs/features/interactive-demo-band-experience/QA_REPORT.md#L15`), Tony
runs the migration apply at production apply time as part of the Rollout
Strategy. This deferral is pre-approved and does not block APPROVED.

## Code Efficiency/Bloat Check

Cycle 4 additions kept minimal by direct mirror of already-shipped
precedent files:

- Migration 1 mirrors
  `20260604000001_add_can_view_financials_to_contributor_permissions.sql`
  verbatim except `financials → gear`. No new helper, no rewrite.
- Migration 2 mirrors
  `20260711120000_fix_update_member_role_can_view_financials.sql` verbatim
  with the single new SET-clause line for `can_view_gear`. `CREATE OR
REPLACE` is used because the RPC already exists; not a fresh function
  definition.
- Migration 3 mirrors
  `20260814120001_fix_financial_entries_select_rbac.sql` for shape; the
  `REVOKE ALL FROM PUBLIC, anon` + `GRANT EXECUTE ... TO authenticated`
  pattern is inline in the same file (avoids the two-step pattern the
  financials feature had to ship later per
  `20260822120001_revoke_anon_batch_2_rls_helpers.sql`).
- `contributor_permissions.dart` edit reuses the existing field-parity
  pattern (`canViewFinancials`); no new helper, no new `copyWith` layout —
  one field added per method / static.
- `band_permissions.dart` change is a body swap on the existing
  `canViewGear` getter matching the exact shape of `canViewSetlists` /
  `canViewCalendar` / `canViewMembers` / `canViewFinancials`. No new
  getter, no removal, `canManageGear` untouched.
- `role_management_sheet.dart` change is one extra
  `_buildPermissionToggle` call reusing the existing helper, and one extra
  boolean AND in `_permissionsEqual`. No new widget, no new state field.
- Searched `lib/` for pre-existing "contributor toggle" or "permissions-
  equal" helpers before adding: the existing `_permissionsEqual` in
  `role_management_sheet.dart` is the only such helper and remains
  private; extending it in place is the least-bloat option.
- `dart fix --dry-run` executed against the changed files; no automated
  fixes applicable.
- No `TODO` / `FIXME` / `debugPrint(` introduced in cycle-4 edits.
- No new helpers, no barrel files, no new providers, no `_buildX()` single-
  use methods, no dead SQL grants.

## Verification (manual steps performed)

- Read the Architect cycle-3 revision in full; confirmed the scope
  addition targets only the six files this cycle actually touches (three
  new migrations + three modified Dart files) and does not require any
  edit to files off-limits.
- Confirmed the three modified Dart files still compile clean via T1.1.
- Confirmed `_permissionsEqual` covers all seven contributor sub-permission
  fields (`canCreateGigs`, `canCreatePotentialGigsOnly`, `canViewSetlists`,
  `canViewCalendar`, `canViewMembers`, `canViewFinancials`, `canViewGear`)
  so dirty-detection tracks the new toggle.
- Confirmed the new "Can view gear" toggle in `role_management_sheet.dart`
  sits immediately after the existing "Can view financials" toggle and
  uses the same `_buildPermissionToggle` shape.
- Confirmed migration 3 does not include any `FOR INSERT` / `FOR UPDATE`
  / `FOR DELETE` policy statements — INSERT / UPDATE / DELETE gates
  remain the base migration's admin-and-member-only policies (`grep -Ec
"FOR INSERT|FOR UPDATE|FOR DELETE"` returned 0).
- Confirmed T1.4 static counts against all four migrations (evidence
  block above).
- Confirmed `pipeline.lock` shows Manager holds the lock; this cycle did
  not acquire or release the lock.
- Confirmed working tree carries only the six expected cycle-4 code
  additions/modifications plus untracked doc/gear scaffolding from cycle
  3; no out-of-plan file changed.

## Deviations From Plan

- **Deviation A (pre-approved by Tony's cycle-3 review).** Tier 1.3 full-
  suite regression carries exactly one failure at
  `test/features/auth/login_screen_demo_button_test.dart` Test A. Root
  cause: `lib/features/auth/login_screen.dart:657` renders `'Check out the
demo band'` (lowercase `out`) but the test asserts title-case
  `'Check Out the Demo Band'`. Both files were last touched together in
  commit `5cd1996` and are unmodified by `feature/band-gear-management`.
  Filed as a separate one-line typo/bug fix. Per the plan's accepted-
  deviation clause, this failure does not block Ready For QA; all 218
  other tests pass.
- **Deviation B (pre-approved by Tony's cycle-3 review).** Tier 1.5
  isolated migration-apply check remains deferred to Tier 2 owner-run
  checks under the repo-wide broken-migration-chain infra blocker
  precedent used for
  `docs/features/interactive-demo-band-experience/QA_REPORT.md#L15`. Tony
  runs the migration apply at production apply time. This deferral does
  not block Ready For QA.

## Blockers Encountered

None.

## Ready For QA

Yes. Analyzer clean at every severity; feature tests green; full-suite
failure is the sole accepted Deviation A; T1.4 static SQL evidence matches
plan expectations for all four migrations; T1.5 deferred to Tier 2 per
accepted Deviation B.
