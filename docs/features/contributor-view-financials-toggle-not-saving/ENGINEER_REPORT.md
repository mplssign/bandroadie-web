# Engineer Report

## Feature Slug

`bug/contributor-view-financials-toggle-not-saving`

---

## Feature Title

Fix update_member_role RPC to persist can_view_financials toggle

---

## Goal

The "Can view financials" permission toggle for Contributors does not persist when saved by an Admin. This fix adds the missing `can_view_financials` field to the `update_member_role` RPC function's UPDATE statement, enabling Admins to grant view-only financial access to Contributors.

---

## Architect Tasks Completed

- [x] **Task 1** — Created `supabase/migrations/20260711120000_fix_update_member_role_can_view_financials.sql` with the corrected RPC function. Added `can_view_financials = COALESCE((p_sub_permissions->>'can_view_financials')::boolean, FALSE),` to the UPDATE statement's SET clause (placed after `can_view_members`, before `updated_at`). Retained `SECURITY DEFINER`, `SET search_path = public`, and `GRANT EXECUTE` statement exactly as in the original.

**Tasks 2-4 not performed per user instructions:** Migration written but not applied. Tony will manually apply and verify after confirming project-ref configuration.

---

## Files Created

- `supabase/migrations/20260711120000_fix_update_member_role_can_view_financials.sql`

---

## Files Modified

None. This is a pure database fix with no Flutter code changes required.

---

## Analyzer Results

Not run — no Dart code changed.

---

## Test Results

**Not run by Engineer per project convention.** Tony will manually apply the migration and run verification tests after confirming Supabase CLI is linked to the correct project.

---

## Verification

### Manual Syntax Review

Migration file reviewed for:

- ✓ Function signature matches original exactly
- ✓ All parentheses balanced
- ✓ Column name `can_view_financials` spelled correctly
- ✓ Comma placement correct in SET clause
- ✓ `SECURITY DEFINER` retained
- ✓ `SET search_path = public` retained
- ✓ `GRANT EXECUTE` statement retained
- ✓ Default value `FALSE` matches schema and fail-closed philosophy

---

## SQL Test Scripts for Tony to Run Manually After Applying Migration

### Tier 1 Tests — Pre-deployment (Run Locally After `supabase db reset`)

**PRE-DEPLOY TEST 1: Verify column exists**

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'contributor_permissions'
  AND column_name = 'can_view_financials';
```

**Expected:** 1 row, `boolean`, default `false`.

---

**PRE-DEPLOY TEST 2: Verify RLS allows admin UPDATE**

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

### Tier 2 Tests — Post-deployment (Run After `supabase db push` Succeeds)

**POST-DEPLOY TEST 1: Verify function contains the fix**

```sql
SELECT pg_get_functiondef('public.update_member_role(uuid,uuid,text,jsonb)'::regprocedure)
LIKE '%can_view_financials%';
```

**Expected:** `true` (function body contains the string `can_view_financials`).

---

**POST-DEPLOY TEST 2: Full integration test with RPC call**

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

---

**POST-DEPLOY TEST 3: Verify other permissions unaffected**

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

---

**POST-DEPLOY TEST 4: Production integrity check**

```sql
-- Verify no existing contributor_permissions rows were corrupted.
-- This is a read-only check — safe to run in production.

SELECT COUNT(*) AS total_contrib_permissions,
       COUNT(*) FILTER (WHERE can_view_financials IS NULL) AS null_values
FROM public.contributor_permissions;
```

**Expected:** `null_values = 0` (all rows have a non-null value for `can_view_financials`).

---

## Deviations From Architect Plan

**Migration application deferred:** Per this project's established convention (see `feature/expense-delete-drawer` precedent), migrations are written by the Engineer but applied manually by Tony after verifying the Supabase CLI is linked to the correct project-ref. This project has a history of accidental deployments to the wrong environment.

Tasks 2-4 from the Architect plan (run `supabase db reset`, `supabase db push`, and run verification tests) were intentionally skipped per explicit user instructions. Migration file created and syntax-validated only.

---

## Blockers Encountered

None. Task 1 completed successfully.

---

## Ready For QA

**Not yet.** Migration must be applied by Tony first. After application:

1. Tony should run all Tier 1 and Tier 2 SQL tests above
2. If tests pass, proceed to manual QA per Architect plan's "QA Regression Areas" section:
   - Primary Validation Tests #1-3 (toggle persistence, dashboard visibility, other toggles unaffected)
   - Secondary Validation Tests #4-6 (cross-platform consistency, admin boundary, RBAC integration with expense-delete-drawer feature)

---

## Next Steps for Tony

1. Verify Supabase CLI is linked to correct project-ref
2. Apply migration: `supabase db push`
3. Run Tier 2 SQL tests (above) in production
4. If all tests pass, proceed to manual QA
5. If QA passes, merge this branch and unblock `feature/expense-delete-drawer` final verification
