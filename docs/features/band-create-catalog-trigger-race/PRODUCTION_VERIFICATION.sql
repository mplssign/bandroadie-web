-- ===========================================================================
-- PRODUCTION VERIFICATION SCRIPT
-- ===========================================================================
-- Feature: bug/band-create-catalog-trigger-race
-- Purpose: Consolidated script for manual verification in Supabase Dashboard SQL Editor
-- Project: nekwjxvgbveheooyorjo
-- WARNING: This will run directly against PRODUCTION (no branching available)
-- 
-- Execution Order:
--   1. Tier 1 Tests (1.1-1.4) — Pre-migration verification
--   2. Migration SQL — Fix function with bypass clause
--   3. Tier 2 Tests (2.1-2.5) — Post-migration verification
--
-- If any Tier 2 test fails, immediately run ROLLBACK script (see separate file)
-- ===========================================================================


-- ===========================================================================
-- SECTION 1: TIER 1 PRE-MIGRATION TESTS
-- ===========================================================================
-- These tests verify the current production state BEFORE applying the fix.
-- All should PASS before proceeding to migration.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Test 1.1: Verify create_band function exists and contains expected structure
-- EXPECTED: TRUE (confirms create_band has the correct INSERT order)
-- ---------------------------------------------------------------------------
SELECT
  pg_get_functiondef('public.create_band(text, text, text)'::regprocedure)::text
  LIKE '%INSERT INTO bands%RETURNING id INTO v_band_id%'
  AND pg_get_functiondef('public.create_band(text, text, text)'::regprocedure)::text
  LIKE '%INSERT INTO band_members%'
AS "Test 1.1 PASS?";

-- ---------------------------------------------------------------------------
-- Test 1.2: Verify trigger trigger_auto_create_catalog exists on bands table
-- EXPECTED: TRUE (confirms auto-catalog trigger is active)
-- ---------------------------------------------------------------------------
SELECT EXISTS(
  SELECT 1 FROM pg_trigger
  WHERE tgname = 'trigger_auto_create_catalog'
    AND tgrelid = 'public.bands'::regclass
) AS "Test 1.2 PASS?";

-- ---------------------------------------------------------------------------
-- Test 1.3: Verify auto_create_catalog_for_band function exists
-- EXPECTED: TRUE (confirms trigger function is defined)
-- ---------------------------------------------------------------------------
SELECT EXISTS(
  SELECT 1 FROM pg_proc
  WHERE proname = 'auto_create_catalog_for_band'
    AND pronamespace = 'public'::regnamespace
) AS "Test 1.3 PASS?";

-- ---------------------------------------------------------------------------
-- Test 1.4: Verify current ensure_catalog_setlist has membership check
-- EXPECTED: TRUE (confirms we're fixing the right function with 2026-08-22 auth)
-- ---------------------------------------------------------------------------
SELECT
  pg_get_functiondef('public.ensure_catalog_setlist(uuid)'::regprocedure)::text
  LIKE '%Access denied: not an active member of this band%'
AS "Test 1.4 PASS?";

-- ===========================================================================
-- ✋ CHECKPOINT: All Tier 1 tests should return TRUE
-- If any test returns FALSE, STOP and investigate before proceeding
-- ===========================================================================


-- ===========================================================================
-- SECTION 2: MIGRATION — FIX ENSURE_CATALOG_SETLIST
-- ===========================================================================
-- This replaces the function body to add the band-creation bypass clause.
-- After this runs, band creation should work again.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ensure_catalog_setlist(p_band_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  catalog_id UUID;
  catalog_count INTEGER;
  oldest_catalog RECORD;
BEGIN
  -- ===========================================================================
  -- AUTHORIZATION CHECK
  -- ===========================================================================
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Check if user is an active member of the band
  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  -- If not a member, check for band-creation race exception:
  -- Allow if (1) we're in a trigger context AND (2) caller is band creator AND (3) no membership rows exist yet
  -- (this handles the trigger_auto_create_catalog race during create_band)
  -- The pg_trigger_depth() > 0 check ensures this bypass ONLY works during trigger execution,
  -- not for direct RPC calls from clients (closes re-introduction of cross-tenant tampering hole)
  IF NOT v_is_member THEN
    SELECT
      pg_trigger_depth() > 0
      AND EXISTS(SELECT 1 FROM bands WHERE id = p_band_id AND created_by = v_user_id)
      AND NOT EXISTS(SELECT 1 FROM band_members WHERE band_id = p_band_id)
    INTO v_is_member;
  END IF;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Access denied: not an active member of this band';
  END IF;

  -- ===========================================================================
  -- CATALOG LOGIC (unchanged from 20260822120101)
  -- ===========================================================================

  -- Check how many Catalogs exist for this band
  SELECT COUNT(*) INTO catalog_count
  FROM public.setlists
  WHERE band_id = p_band_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'));

  -- If exactly one exists, return it
  IF catalog_count = 1 THEN
    SELECT id INTO catalog_id
    FROM public.setlists
    WHERE band_id = p_band_id
      AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
    LIMIT 1;

    -- Ensure metadata is correct
    UPDATE public.setlists
    SET name = 'Catalog', setlist_type = 'catalog', is_catalog = true
    WHERE id = catalog_id AND (name != 'Catalog' OR setlist_type != 'catalog' OR is_catalog != true);

    RETURN catalog_id;
  END IF;

  -- If none exists, create one
  IF catalog_count = 0 THEN
    INSERT INTO public.setlists (band_id, name, setlist_type, is_catalog, total_duration)
    VALUES (p_band_id, 'Catalog', 'catalog', true, 0)
    RETURNING id INTO catalog_id;

    RETURN catalog_id;
  END IF;

  -- If multiple exist, keep the oldest one and merge songs from others
  SELECT id, name INTO oldest_catalog
  FROM public.setlists
  WHERE band_id = p_band_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
  ORDER BY created_at ASC
  LIMIT 1;

  catalog_id := oldest_catalog.id;

  -- Move songs from duplicate Catalogs to the primary one
  INSERT INTO public.setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds)
  SELECT
    catalog_id,
    ss.song_id,
    COALESCE((SELECT MAX(position) FROM public.setlist_songs WHERE setlist_id = catalog_id), 0) + ROW_NUMBER() OVER (ORDER BY ss.position),
    ss.bpm,
    ss.tuning,
    ss.duration_seconds
  FROM public.setlist_songs ss
  JOIN public.setlists sl ON ss.setlist_id = sl.id
  WHERE sl.band_id = p_band_id
    AND sl.id != catalog_id
    AND (sl.setlist_type = 'catalog' OR sl.is_catalog = true OR LOWER(sl.name) IN ('catalog', 'all songs'))
    AND NOT EXISTS (
      SELECT 1 FROM public.setlist_songs existing
      WHERE existing.setlist_id = catalog_id AND existing.song_id = ss.song_id
    );

  -- Delete songs from duplicate Catalogs
  DELETE FROM public.setlist_songs
  WHERE setlist_id IN (
    SELECT id FROM public.setlists
    WHERE band_id = p_band_id
      AND id != catalog_id
      AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
  );

  -- Delete duplicate Catalogs
  DELETE FROM public.setlists
  WHERE band_id = p_band_id
    AND id != catalog_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'));

  -- Ensure primary Catalog has correct metadata
  UPDATE public.setlists
  SET name = 'Catalog', setlist_type = 'catalog', is_catalog = true
  WHERE id = catalog_id;

  RETURN catalog_id;
END;
$function$;

-- ===========================================================================
-- ✅ MIGRATION COMPLETE
-- The function now has the band-creation bypass clause.
-- Proceed to Tier 2 verification tests below.
-- ===========================================================================


-- ===========================================================================
-- SECTION 3: TIER 2 POST-MIGRATION TESTS
-- ===========================================================================
-- These tests verify the fix works correctly and doesn't regress security.
-- All must PASS before marking the fix as production-ready.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Test 2.1: Verify bypass clause was added to function
-- EXPECTED: TRUE (confirms migration applied successfully)
-- ---------------------------------------------------------------------------
SELECT
  pg_get_functiondef('public.ensure_catalog_setlist(uuid)'::regprocedure)::text
  LIKE '%created_by = v_user_id%'
  AND pg_get_functiondef('public.ensure_catalog_setlist(uuid)'::regprocedure)::text
  LIKE '%NOT EXISTS(SELECT 1 FROM band_members WHERE band_id = p_band_id)%'
AS "Test 2.1 PASS?";

-- ---------------------------------------------------------------------------
-- Test 2.2: Verify create_band succeeds end-to-end (THE FIX)
-- EXPECTED: NOTICE "Test 2.2 PASSED" (confirms band creation works)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  test_band_id UUID;
  test_catalog_id UUID;
  test_member_count INT;
BEGIN
  -- Create a test band (this should now succeed)
  SELECT public.create_band('Test Band ' || gen_random_uuid()::text, '#F43F5E', NULL)
  INTO test_band_id;

  -- Verify band was created
  IF NOT EXISTS(SELECT 1 FROM bands WHERE id = test_band_id) THEN
    RAISE EXCEPTION 'Band creation failed';
  END IF;

  -- Verify creator was added as admin member
  SELECT COUNT(*) INTO test_member_count
  FROM band_members
  WHERE band_id = test_band_id AND user_id = auth.uid() AND status = 'active' AND role = 'admin';

  IF test_member_count != 1 THEN
    RAISE EXCEPTION 'Creator membership not created (expected 1, got %)', test_member_count;
  END IF;

  -- Verify Catalog setlist was auto-created by trigger
  SELECT id INTO test_catalog_id
  FROM setlists
  WHERE band_id = test_band_id AND setlist_type = 'catalog' AND is_catalog = true;

  IF test_catalog_id IS NULL THEN
    RAISE EXCEPTION 'Catalog setlist not auto-created';
  END IF;

  -- Cleanup: delete test data
  DELETE FROM band_members WHERE band_id = test_band_id;
  DELETE FROM setlists WHERE band_id = test_band_id;
  DELETE FROM bands WHERE id = test_band_id;

  RAISE NOTICE 'Test 2.2 PASSED: create_band succeeded, catalog auto-created';
END $$;

-- ---------------------------------------------------------------------------
-- Test 2.3: SECURITY REGRESSION CHECK — Verify bypass does NOT work for
--           direct RPC calls from creator of abandoned band
-- EXPECTED: NOTICE "Test 2.3 PASSED" (confirms pg_trigger_depth() blocks direct calls)
-- CRITICAL: This test ensures the cross-tenant tampering hole stays closed
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  test_band_id UUID;
  test_user_id UUID;
  call_succeeded BOOLEAN := FALSE;
BEGIN
  test_user_id := auth.uid();

  -- Create a test band (should succeed via normal flow)
  SELECT public.create_band('Abandoned Band Security Test ' || gen_random_uuid()::text, '#F43F5E', NULL)
  INTO test_band_id;

  -- Verify band was created with creator as admin
  IF NOT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = test_band_id AND user_id = test_user_id AND status = 'active' AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Test setup failed: creator not added as admin';
  END IF;

  -- Simulate abandonment: remove all members (including creator)
  DELETE FROM band_members WHERE band_id = test_band_id;

  -- Verify band now has zero members
  IF EXISTS(SELECT 1 FROM band_members WHERE band_id = test_band_id) THEN
    RAISE EXCEPTION 'Test setup failed: band still has members after delete';
  END IF;

  -- Verify creator relationship is intact
  IF NOT EXISTS(SELECT 1 FROM bands WHERE id = test_band_id AND created_by = test_user_id) THEN
    RAISE EXCEPTION 'Test setup failed: creator relationship lost';
  END IF;

  -- NOW THE CRITICAL TEST:
  -- Try to call ensure_catalog_setlist directly (not via trigger)
  -- Bypass conditions: pg_trigger_depth() > 0 (FALSE for direct call)
  --                    created_by = v_user_id (TRUE)
  --                    NOT EXISTS(band_members) (TRUE)
  -- Result: bypass should NOT fire because pg_trigger_depth() = 0
  -- Expected: 'Access denied: not an active member of this band'
  BEGIN
    PERFORM public.ensure_catalog_setlist(test_band_id);
    call_succeeded := TRUE;  -- Should not reach here
  EXCEPTION
    WHEN OTHERS THEN
      -- Expected exception
      IF SQLERRM NOT LIKE '%Access denied%' AND SQLERRM NOT LIKE '%not an active member%' THEN
        -- Cleanup before re-raising
        DELETE FROM setlists WHERE band_id = test_band_id;
        DELETE FROM bands WHERE id = test_band_id;
        RAISE EXCEPTION 'Test 2.3 FAILED: Got unexpected exception: %', SQLERRM;
      END IF;
      -- Correct exception received
  END;

  -- Verify the call actually failed
  IF call_succeeded THEN
    -- Cleanup
    DELETE FROM setlists WHERE band_id = test_band_id;
    DELETE FROM bands WHERE id = test_band_id;
    RAISE EXCEPTION 'Test 2.3 FAILED: Direct call to ensure_catalog_setlist succeeded for creator of abandoned band (bypass should be blocked by pg_trigger_depth() = 0)';
  END IF;

  -- Cleanup
  DELETE FROM setlists WHERE band_id = test_band_id;
  DELETE FROM bands WHERE id = test_band_id;

  RAISE NOTICE 'Test 2.3 PASSED: Direct call from creator of abandoned band correctly denied (pg_trigger_depth() = 0 blocks bypass)';
END $$;

-- ---------------------------------------------------------------------------
-- Test 2.4: Verify no orphaned bands exist since bug started
-- EXPECTED: 0 rows (all create_band calls failed completely, no partial data)
-- ---------------------------------------------------------------------------
SELECT
  b.id,
  b.name,
  b.created_at,
  b.created_by,
  (SELECT COUNT(*) FROM band_members WHERE band_id = b.id) AS member_count
FROM bands b
WHERE b.created_at >= '2026-08-22 12:52:00+00'::timestamptz
  AND NOT EXISTS(SELECT 1 FROM band_members WHERE band_id = b.id)
ORDER BY b.created_at DESC;
-- If this returns rows, investigate — should be 0 rows since bug aborted transactions

-- ---------------------------------------------------------------------------
-- Test 2.5: Verify existing bands' catalog operations still require membership
-- EXPECTED: NOTICE "Test 2.5 PASSED" or "Test 2.5 SKIPPED"
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  test_band_id UUID;
  test_user_id UUID;
BEGIN
  test_user_id := auth.uid();

  -- Find a band where current user is an active member
  SELECT band_id INTO test_band_id
  FROM band_members
  WHERE user_id = test_user_id AND status = 'active'
  LIMIT 1;

  IF test_band_id IS NULL THEN
    RAISE NOTICE 'Test 2.5 SKIPPED: current user is not a member of any band';
    RETURN;
  END IF;

  -- Call ensure_catalog_setlist (should succeed)
  BEGIN
    PERFORM public.ensure_catalog_setlist(test_band_id);
    RAISE NOTICE 'Test 2.5 PASSED: ensure_catalog_setlist succeeded for member of existing band';
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Test 2.5 FAILED: ensure_catalog_setlist failed for active member: %', SQLERRM;
  END;
END $$;

-- ===========================================================================
-- ✅ VERIFICATION COMPLETE
-- ===========================================================================
-- Expected Results Summary:
--   Tier 1 (1.1-1.4): All should return TRUE
--   Tier 2 (2.1):     Should return TRUE
--   Tier 2 (2.2):     Should show NOTICE "Test 2.2 PASSED"
--   Tier 2 (2.3):     Should show NOTICE "Test 2.3 PASSED" ⚠️ CRITICAL SECURITY CHECK
--   Tier 2 (2.4):     Should return 0 rows
--   Tier 2 (2.5):     Should show NOTICE "Test 2.5 PASSED" or "SKIPPED"
--
-- If all tests pass:
--   ✅ Mark ENGINEER_REPORT as verified with production results
--   ✅ Proceed to QA regression testing
--
-- If ANY Tier 2 test fails:
--   ⚠️ Immediately run ROLLBACK script (see PRODUCTION_ROLLBACK.sql)
--   ⚠️ Document failure in ENGINEER_REPORT
--   ⚠️ Do NOT proceed to QA
-- ===========================================================================
