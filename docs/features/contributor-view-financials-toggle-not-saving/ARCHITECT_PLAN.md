# ARCHITECT_PLAN.md

## Feature Slug

`bug/contributor-view-financials-toggle-not-saving`

---

## Problem Summary

The "Can view financials" permission toggle for Contributors does not persist when saved by an Admin. The toggle appears to save with no error, but when the Admin reopens the same Contributor's permission settings, the toggle reverts to off. This prevents Contributors from gaining view-only access to the Financials section, even when explicitly granted by an Admin.

Reproduced twice consecutively on iPhone with consistent behavior. The affected Contributor's dashboard never displays the Financials button, consistent with the permission write never actually persisting.

---

## Root Cause

**Confidence: HIGH**

The `update_member_role` RPC function does not update the `can_view_financials` column when saving contributor permissions.

The RPC's UPDATE statement (lines 445-452 in migration `20260302000000_band_user_roles.sql`) writes to 5 permission columns but **omits `can_view_financials`**:

```sql
UPDATE public.contributor_permissions
SET
  can_create_gigs = COALESCE((p_sub_permissions->>'can_create_gigs')::boolean, TRUE),
  can_create_potential_gigs_only = COALESCE((p_sub_permissions->>'can_create_potential_gigs_only')::boolean, TRUE),
  can_view_setlists = COALESCE((p_sub_permissions->>'can_view_setlists')::boolean, TRUE),
  can_view_calendar = COALESCE((p_sub_permissions->>'can_view_calendar')::boolean, TRUE),
  can_view_members = COALESCE((p_sub_permissions->>'can_view_members')::boolean, TRUE),
  updated_at = NOW()
WHERE band_member_id = p_member_id;
```

The `can_view_financials` column was added to the table in June 2026 (migration `20260604000001_add_can_view_financials_to_contributor_permissions.sql`), but the RPC function was never updated to handle it.

**Why the bug is silent:**

- The Flutter client correctly sends `can_view_financials` in the JSONB payload
- The RPC receives the JSON but ignores the field during the UPDATE
- The database write succeeds with no error (it writes the 5 original fields successfully)
- The UI re-fetches the persisted value and displays `false` (the table's default)
- From the user's perspective, the toggle "doesn't save"

---

## Reference Docs Consulted

None exist for contributor permissions or RBAC domain.

---

## Existing System Analysis

**Current Data Flow (Role Management → Database):**

1. Admin opens role management sheet for a Contributor
2. `role_management_sheet.dart` calls `_loadExistingPermissions()` → fetches via `fetchContributorPermissions()`
3. User toggles "Can view financials" → updates local `_subPermissions` state via `copyWith(canViewFinancials: v)`
4. User taps Save → calls `membersProvider.notifier.updateRole()` with `_subPermissions`
5. Controller calls `_repository.updateMemberRole()` with full `ContributorPermissions` object
6. Repository serializes permissions to JSON via `toJson()` → includes `'can_view_financials': canViewFinancials`
7. Repository calls `supabase.rpc('update_member_role', params: {'p_sub_permissions': {...}})`
8. **RPC function writes 5 fields, ignores `can_view_financials`** ← BUG HERE
9. Database write succeeds (5 fields updated, `updated_at` refreshed)
10. UI invalidates permissions provider, reloads members, re-fetches permissions
11. Fetched value shows `can_view_financials: false` (unchanged from default)

**Why Other Toggles Work:**
All 5 original permission fields were present in the RPC function when it was created in March 2026. Only `can_view_financials` was added later (June 2026) and never integrated.

**RLS Policy Status:**

- Policy "Admins can manage contributor permissions" (FOR ALL operations) allows Admins to UPDATE the `contributor_permissions` table
- RLS is functioning correctly — the bug is in the RPC function, not access control

---

## Proposed Solution

Create a new migration that replaces the `update_member_role` RPC function with a corrected version that includes `can_view_financials` in the UPDATE statement.

**Single Change:**
Add one line to the UPDATE statement's SET clause:

```sql
can_view_financials = COALESCE((p_sub_permissions->>'can_view_financials')::boolean, FALSE),
```

**Default Value:**
Use `FALSE` to match the column's schema-level `DEFAULT FALSE` and the "fail-closed" philosophy documented in `contributor_permissions.dart` (`allDisabled` fallback).

**No Client Changes Required:**

- The Flutter model already includes the field
- The UI already renders the toggle and updates state correctly
- The repository already sends the field in the JSON payload
- All client code is correct — only the server-side RPC needs the fix

---

## Database Impact

**Migrations:** New migration required to replace the `update_member_role` function.

**RLS Policies:** Unaffected. The existing "Admins can manage contributor permissions" policy already permits this UPDATE. No RLS changes required.

**RPC Functions:** `update_member_role` must be replaced with `CREATE OR REPLACE FUNCTION` in the new migration.

**Triggers:** Unaffected.

**Tables:** Unaffected. The `contributor_permissions.can_view_financials` column already exists with the correct schema.

**Function Signature:** Unchanged. Parameters, return type, and security context remain identical. No client compatibility concerns.

---

## Flutter Architecture Changes

**None required.**

The Flutter codebase is already correct:

- Model: `ContributorPermissions.canViewFinancials` exists and serializes correctly
- UI: `role_management_sheet.dart` renders toggle and updates state correctly
- Repository: `members_repository.dart` passes full permissions JSON to RPC
- Controller: `members_controller.dart` orchestrates save flow correctly

All client-side code functions as designed. The bug is entirely server-side.

---

## Files to Create

| File                                                                                | Justification                                                                                                |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `supabase/migrations/20260711HHMMSS_fix_update_member_role_can_view_financials.sql` | Replace `update_member_role` RPC function to include missing `can_view_financials` field in UPDATE statement |

---

## Files to Modify

**None.**

This is a pure database fix. No Flutter code, config, or other migrations require modification.

---

## Files Off-Limits

| File                                                                                        | Reason                                                                  |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `lib/features/members/widgets/role_management_sheet.dart`                                   | UI already works correctly — sends the field in state                   |
| `lib/features/members/members_controller.dart`                                              | Controller already works correctly — passes permissions through         |
| `lib/features/members/members_repository.dart`                                              | Repository already works correctly — serializes and sends JSON          |
| `lib/features/members/permissions/contributor_permissions.dart`                             | Model already includes `canViewFinancials` field                        |
| `supabase/migrations/20260302000000_band_user_roles.sql`                                    | Never modify applied migrations — use new migration to replace function |
| `supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql` | Never modify applied migrations                                         |

---

## System Impact Map

| System                                 | Impact                                                                                   |
| -------------------------------------- | ---------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                               |
| Rehearsals                             | unaffected                                                                               |
| Setlists / Catalog                     | unaffected                                                                               |
| Members / RBAC                         | **affected** — fixes contributor permission persistence for `can_view_financials`        |
| Auth / Session                         | unaffected                                                                               |
| Routing                                | unaffected                                                                               |
| Notifications                          | unaffected                                                                               |
| Financials                             | **affected** — downstream visibility for Contributors depends on this permission working |
| Platform (iOS / Android / Web / macOS) | unaffected — server-side fix applies universally                                         |

---

## Regression Risk

**Level: LOW**

**Rationale:**

- Single RPC function affected
- Change is additive — adds one field to existing UPDATE, does not alter logic for other fields
- No RLS changes
- No trigger changes
- No auth flow changes
- No Flutter code changes
- Function signature unchanged — no client compatibility concerns
- Other permission fields continue to work identically
- No data migration or backfill required

**Mitigating Factors:**

- The bug only affects write persistence of `can_view_financials` — reads work correctly
- Contributors with `can_view_financials = true` (manually set via SQL) are unaffected
- The fix only enables the intended behavior — it does not change existing working functionality

**Dependency Note:**
This fix unblocks verification of the `feature/expense-delete-drawer` RBAC tightening. That branch restricted financial entry writes to admins/members only. This bug prevents testing whether Contributors with `can_view_financials = true` can successfully view (read-only) the Financials section.

---

## Engineer Task Breakdown

### Task 1: Create Migration File

Create `supabase/migrations/20260711HHMMSS_fix_update_member_role_can_view_financials.sql` with:

- Header comment documenting the fix
- `CREATE OR REPLACE FUNCTION public.update_member_role(...)` with identical signature
- Copy full function body from `20260302000000_band_user_roles.sql` lines 379-463
- Add `can_view_financials = COALESCE((p_sub_permissions->>'can_view_financials')::boolean, FALSE),` to the UPDATE statement's SET clause (after `can_view_members`, before `updated_at`)
- Retain all existing logic, security context (`SECURITY DEFINER`), and GRANT statement

### Task 2: Verify Migration Syntax

Run locally:

```bash
supabase db reset
```

Confirm:

- No syntax errors
- Function replaced successfully
- All tests pass (Tier 1 and Tier 2 — see Verification Plan)

### Task 3: Deploy to Production

```bash
supabase db push
```

### Task 4: Verify Production

Run post-deploy verification tests (Tier 2) to confirm:

- Function contains the new field
- Toggle save-and-reload works correctly
- Other permission fields unaffected

---

## Verification Plan

### Tier 1 — Pre-deployment (Run Before `supabase db push`)

These tests validate the fix logic without depending on the updated function. Run after `supabase db reset` completes locally.

**-- PRE-DEPLOY TEST 1: Verify column exists**

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'contributor_permissions'
  AND column_name = 'can_view_financials';
```

**Expected:** 1 row, `boolean`, default `false`.

**-- PRE-DEPLOY TEST 2: Verify RLS allows admin UPDATE**

```sql
-- This test validates the RLS policy without calling the function.
-- Must be run as a test admin user with a real band_members record.

DO $$
DECLARE
  v_test_band_id UUID;
  v_test_admin_member_id UUID;
  v_test_contrib_member_id UUID;
  v_test_admin_user_id UUID;
  v_result BOOLEAN;
BEGIN
  -- Create test band
  INSERT INTO public.bands (name, created_by, image_url)
  VALUES ('Test Band RLS', auth.uid(), '')
  RETURNING id INTO v_test_band_id;

  -- Create admin band_member for current user
  INSERT INTO public.band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, auth.uid(), 'admin', 'active')
  RETURNING id INTO v_test_admin_member_id;

  -- Create contributor band_member (fake user)
  INSERT INTO public.band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, gen_random_uuid(), 'contributor', 'active')
  RETURNING id INTO v_test_contrib_member_id;

  -- Create contributor_permissions row
  INSERT INTO public.contributor_permissions (band_member_id, can_view_financials)
  VALUES (v_test_contrib_member_id, FALSE);

  -- Attempt UPDATE via RLS (not via RPC)
  UPDATE public.contributor_permissions
  SET can_view_financials = TRUE
  WHERE band_member_id = v_test_contrib_member_id;

  -- Verify update succeeded
  SELECT can_view_financials INTO v_result
  FROM public.contributor_permissions
  WHERE band_member_id = v_test_contrib_member_id;

  IF v_result = TRUE THEN
    RAISE NOTICE 'PRE-DEPLOY TEST 2: PASS — RLS allows admin UPDATE';
  ELSE
    RAISE EXCEPTION 'PRE-DEPLOY TEST 2: FAIL — RLS blocked UPDATE or value not written';
  END IF;

  -- Cleanup
  DELETE FROM public.bands WHERE id = v_test_band_id;
END;
$$;
```

**Expected:** Notice "PRE-DEPLOY TEST 2: PASS".

---

### Tier 2 — Post-deployment (Run After `supabase db push` Succeeds)

These tests validate the deployed function and full integration.

**-- POST-DEPLOY TEST 1: Verify function contains the fix**

```sql
SELECT pg_get_functiondef('public.update_member_role(uuid,uuid,text,jsonb)'::regprocedure)
LIKE '%can_view_financials%';
```

**Expected:** `true` (function body contains the string `can_view_financials`).

**-- POST-DEPLOY TEST 2: Full integration test with RPC call**

```sql
-- This test exercises the full RPC call path with can_view_financials.
-- Must be run as a test admin user with a real band_members record.

DO $$
DECLARE
  v_test_band_id UUID;
  v_test_admin_member_id UUID;
  v_test_contrib_member_id UUID;
  v_sub_permissions JSONB;
  v_result BOOLEAN;
BEGIN
  -- Create test band
  INSERT INTO public.bands (name, created_by, image_url)
  VALUES ('Test Band RPC', auth.uid(), '')
  RETURNING id INTO v_test_band_id;

  -- Create admin band_member for current user
  INSERT INTO public.band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, auth.uid(), 'admin', 'active')
  RETURNING id INTO v_test_admin_member_id;

  -- Create contributor band_member (fake user, any role initially)
  INSERT INTO public.band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, gen_random_uuid(), 'member', 'active')
  RETURNING id INTO v_test_contrib_member_id;

  -- Call RPC to change role to contributor with can_view_financials = TRUE
  v_sub_permissions := jsonb_build_object(
    'can_create_gigs', true,
    'can_create_potential_gigs_only', true,
    'can_view_setlists', true,
    'can_view_calendar', true,
    'can_view_members', true,
    'can_view_financials', true
  );

  PERFORM public.update_member_role(
    v_test_contrib_member_id,
    v_test_band_id,
    'contributor',
    v_sub_permissions
  );

  -- Verify can_view_financials was written
  SELECT can_view_financials INTO v_result
  FROM public.contributor_permissions
  WHERE band_member_id = v_test_contrib_member_id;

  IF v_result = TRUE THEN
    RAISE NOTICE 'POST-DEPLOY TEST 2: PASS — can_view_financials persisted via RPC';
  ELSE
    RAISE EXCEPTION 'POST-DEPLOY TEST 2: FAIL — can_view_financials not written (value: %)', v_result;
  END IF;

  -- Test toggle OFF (ensure FALSE writes correctly too)
  v_sub_permissions := jsonb_build_object(
    'can_create_gigs', true,
    'can_create_potential_gigs_only', true,
    'can_view_setlists', true,
    'can_view_calendar', true,
    'can_view_members', true,
    'can_view_financials', false
  );

  PERFORM public.update_member_role(
    v_test_contrib_member_id,
    v_test_band_id,
    'contributor',
    v_sub_permissions
  );

  SELECT can_view_financials INTO v_result
  FROM public.contributor_permissions
  WHERE band_member_id = v_test_contrib_member_id;

  IF v_result = FALSE THEN
    RAISE NOTICE 'POST-DEPLOY TEST 2: PASS — can_view_financials=FALSE persisted correctly';
  ELSE
    RAISE EXCEPTION 'POST-DEPLOY TEST 2: FAIL — can_view_financials=FALSE not written';
  END IF;

  -- Cleanup
  DELETE FROM public.bands WHERE id = v_test_band_id;
END;
$$;
```

**Expected:** Two notices: both PASS messages.

**-- POST-DEPLOY TEST 3: Verify other permissions unaffected**

```sql
-- Verify all 5 original permission fields still write correctly.

DO $$
DECLARE
  v_test_band_id UUID;
  v_test_contrib_member_id UUID;
  v_sub_permissions JSONB;
  v_row RECORD;
BEGIN
  -- Create test band
  INSERT INTO public.bands (name, created_by, image_url)
  VALUES ('Test Band Regression', auth.uid(), '')
  RETURNING id INTO v_test_band_id;

  -- Create admin band_member
  INSERT INTO public.band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, auth.uid(), 'admin', 'active');

  -- Create contributor band_member
  INSERT INTO public.band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, gen_random_uuid(), 'member', 'active')
  RETURNING id INTO v_test_contrib_member_id;

  -- Call RPC with specific values for all fields
  v_sub_permissions := jsonb_build_object(
    'can_create_gigs', false,
    'can_create_potential_gigs_only', false,
    'can_view_setlists', false,
    'can_view_calendar', false,
    'can_view_members', false,
    'can_view_financials', true
  );

  PERFORM public.update_member_role(
    v_test_contrib_member_id,
    v_test_band_id,
    'contributor',
    v_sub_permissions
  );

  -- Verify all fields
  SELECT * INTO v_row
  FROM public.contributor_permissions
  WHERE band_member_id = v_test_contrib_member_id;

  IF v_row.can_create_gigs = FALSE
    AND v_row.can_create_potential_gigs_only = FALSE
    AND v_row.can_view_setlists = FALSE
    AND v_row.can_view_calendar = FALSE
    AND v_row.can_view_members = FALSE
    AND v_row.can_view_financials = TRUE
  THEN
    RAISE NOTICE 'POST-DEPLOY TEST 3: PASS — All permission fields written correctly';
  ELSE
    RAISE EXCEPTION 'POST-DEPLOY TEST 3: FAIL — Unexpected values: %', v_row;
  END IF;

  -- Cleanup
  DELETE FROM public.bands WHERE id = v_test_band_id;
END;
$$;
```

**Expected:** Notice "POST-DEPLOY TEST 3: PASS".

**-- POST-DEPLOY TEST 4: Production integrity check**

```sql
-- Verify no existing contributor_permissions rows were corrupted.
-- This is a read-only check — safe to run in production.

SELECT COUNT(*) AS total_contrib_permissions,
       COUNT(*) FILTER (WHERE can_view_financials IS NULL) AS null_values
FROM public.contributor_permissions;
```

**Expected:** `null_values = 0` (all rows have a non-null value for `can_view_financials`).

---

## QA Regression Areas

### Primary Validation (Critical)

1. **Toggle persistence (iPhone & Android):**
   - Log in as Admin
   - Change a Member to Contributor
   - Open Contributor's permission settings
   - Toggle "Can view financials" ON
   - Save and navigate away
   - Reopen Contributor's permission settings
   - **Expected:** Toggle remains ON
   - Repeat: Toggle OFF, save, reload → **Expected:** Toggle remains OFF

2. **Contributor dashboard visibility:**
   - Log in as the affected Contributor (with `can_view_financials = true`)
   - Navigate to dashboard
   - **Expected:** Financials button visible (view-only)
   - Tap Financials → **Expected:** Read-only list of financial entries

3. **Verify other permission toggles unaffected:**
   - Toggle each of the 5 other permissions (gigs, potential gigs, setlists, calendar, members) ON and OFF
   - Save and reload
   - **Expected:** All toggles persist correctly as before

### Secondary Validation (Recommended)

4. **Cross-platform consistency:**
   - Perform Test #1 on iPhone (toggle on iPhone, verify persistence)
   - Verify same Contributor on Android shows consistent state
   - Perform Test #1 on Web (toggle on Web, verify on mobile)

5. **Admin permission boundary:**
   - Log in as a non-Admin (Member or Contributor)
   - Attempt to open another member's permission settings
   - **Expected:** UI does not allow access (existing RBAC enforcement)

6. **Financial entries RBAC integration:**
   - Verify `feature/expense-delete-drawer` RBAC changes work as expected with Contributors who have `can_view_financials = true`:
     - Contributor can view financial entries (read-only)
     - Contributor cannot create, update, or delete financial entries
   - This was previously untestable due to this bug

---

## Rollout / Migration Strategy

**No special rollout required.**

This is a pure database fix with no client changes. Deploy via:

```bash
supabase db push
```

**Migration Order:**

1. Run Tier 1 tests locally after `supabase db reset`
2. If tests pass, deploy to production: `supabase db push`
3. Run Tier 2 tests in production (read-only checks, isolated test bands)
4. Perform QA manual validation (Primary tests #1-3)
5. Merge `bug/contributor-view-financials-toggle-not-saving` to main
6. Proceed with `feature/expense-delete-drawer` QA validation (previously blocked)

**Backfill:**
Not required. Existing `contributor_permissions` rows with `can_view_financials = false` are correct defaults. No production Contributor currently has `can_view_financials = true` because the write path has never worked. This fix enables future writes only.

**Rollback:**
If the migration causes issues, roll back by redeploying the previous function definition from `20260302000000_band_user_roles.sql` lines 379-463 (without the `can_view_financials` line). However, this is extremely low risk — the change is additive and does not alter existing logic.

---

## Out of Scope

- UI redesign of permission toggles
- Changes to RLS policies (existing policies are correct)
- Backfill of existing Contributor permissions (no production data requires updating)
- Performance optimization of `update_member_role` function
- Audit logging for permission changes (not currently implemented elsewhere)
- Changes to other RPC functions or migrations
- Flutter client updates (none needed)
