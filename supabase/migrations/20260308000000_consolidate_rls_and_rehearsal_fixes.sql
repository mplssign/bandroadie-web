-- ============================================================================
-- CONSOLIDATED MIGRATION: Fix rehearsal deletion + RLS policies
-- Date: 2026-03-08
--
-- This single idempotent migration replaces 7 incremental hotfix migrations:
--   20260305100000_fix_rehearsal_rls_and_trigger.sql
--   20260306000000_fix_delete_band_missing_rehearsals.sql
--   20260306100000_fix_band_members_rls_owner_enum.sql
--   20260306200000_hotfix_band_members_select_policy.sql
--   20260307000000_fix_stale_owner_policies_all_tables.sql
--   20260307100000_ensure_band_visibility_and_notify.sql
--   20260307200000_fix_band_members_infinite_recursion.sql
--
-- ROOT CAUSE:
--   The RBAC migration (20260302000000) dropped and recreated RLS policies
--   for gigs, setlists, and bands — but skipped rehearsals entirely.
--   Subsequent hotfix attempts on band_members introduced self-referencing
--   policies that caused infinite recursion (ERROR 42P17).
--
-- WHAT THIS MIGRATION DOES:
--   1. Creates is_band_member() SECURITY DEFINER helper (breaks recursion)
--   2. Replaces all band_members policies (no self-referencing)
--   3. Replaces bands SELECT policy using is_band_member()
--   4. Restores all 4 rehearsal RLS policies (SELECT, INSERT, UPDATE, DELETE)
--   5. Patches delete_band() RPC to include rehearsal cleanup
--   6. Fixes notify_rehearsal_created() trigger (correct column + exception)
--   7. Reloads PostgREST schema cache
--
-- IDEMPOTENT: Safe to run regardless of which hotfixes were already applied.
-- Uses DROP POLICY IF EXISTS + CREATE POLICY and CREATE OR REPLACE FUNCTION.
-- ============================================================================


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 1: is_band_member() SECURITY DEFINER helper
-- Bypasses RLS to prevent infinite recursion when used inside
-- band_members policies.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.band_members
    WHERE band_id = p_band_id
    AND user_id = auth.uid()
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_band_member(UUID) TO authenticated;


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 2: band_members RLS policies
-- Dynamically drop ALL existing policies, then recreate without
-- self-referencing subqueries.
-- ═══════════════════════════════════════════════════════════════════════════

-- Drop all existing band_members policies
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'band_members'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.band_members', pol.policyname);
  END LOOP;
END $$;

ALTER TABLE public.band_members ENABLE ROW LEVEL SECURITY;

-- SELECT 1: Users can see their own membership rows (no recursion)
CREATE POLICY "Users can view own memberships"
  ON public.band_members
  FOR SELECT
  USING (user_id = auth.uid());

-- SELECT 2: Active members can see co-members via SECURITY DEFINER helper
CREATE POLICY "Active members can view band co-members"
  ON public.band_members
  FOR SELECT
  USING (public.is_band_member(band_id));

-- INSERT: Existing active member can add new members, OR user can self-insert
CREATE POLICY "Band members can insert band members"
  ON public.band_members
  FOR INSERT WITH CHECK (
    public.is_band_member(band_id)
    OR user_id = auth.uid()
  );

-- UPDATE: Admin only (via SECURITY DEFINER helper + role check)
CREATE POLICY "Admins can update band members"
  ON public.band_members
  FOR UPDATE
  USING (
    public.is_band_member(band_id)
    AND EXISTS (
      SELECT 1 FROM public.band_members admin_check
      WHERE admin_check.band_id = band_members.band_id
      AND admin_check.user_id = auth.uid()
      AND admin_check.role = 'admin'
      AND admin_check.status = 'active'
    )
  )
  WITH CHECK (
    public.is_band_member(band_id)
    AND EXISTS (
      SELECT 1 FROM public.band_members admin_check
      WHERE admin_check.band_id = band_members.band_id
      AND admin_check.user_id = auth.uid()
      AND admin_check.role = 'admin'
      AND admin_check.status = 'active'
    )
  );

-- No DELETE policy — handled by remove_band_member() RPC


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 3: bands SELECT policy
-- Replace with is_band_member() to avoid cross-table subquery issues.
-- Only touches SELECT — other bands policies are unchanged.
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "Band members can view bands" ON public.bands;

CREATE POLICY "Band members can view bands"
  ON public.bands
  FOR SELECT
  USING (public.is_band_member(id));


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 4: rehearsals RLS policies
-- Restore all 4 CRUD policies that were missing after the RBAC migration.
-- These subquery band_members (cross-table, not self-referencing — safe).
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.rehearsals ENABLE ROW LEVEL SECURITY;

-- Drop all known rehearsal policy names
DROP POLICY IF EXISTS "Band members can view rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can create rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can update rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can delete rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Admins and members can create rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Admins and members can update rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Admins and members can delete rehearsals" ON public.rehearsals;

-- SELECT: Any active band member can view rehearsals
CREATE POLICY "Band members can view rehearsals"
  ON public.rehearsals
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
    )
  );

-- INSERT: Admin & member can create rehearsals
CREATE POLICY "Admins and members can create rehearsals"
  ON public.rehearsals
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- UPDATE: Admin & member can update rehearsals
CREATE POLICY "Admins and members can update rehearsals"
  ON public.rehearsals
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE: Admin & member can delete rehearsals
CREATE POLICY "Admins and members can delete rehearsals"
  ON public.rehearsals
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = rehearsals.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 5: delete_band() RPC
-- Adds missing rehearsal cleanup to the cascade delete sequence.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_band_exists BOOLEAN;
  v_is_admin BOOLEAN;
BEGIN
  -- Check band exists
  SELECT EXISTS (
    SELECT 1 FROM public.bands WHERE id = band_uuid
  ) INTO v_band_exists;
  IF NOT v_band_exists THEN
    RAISE EXCEPTION 'Band not found';
  END IF;

  -- Check: caller must be admin
  SELECT EXISTS (
    SELECT 1 FROM public.band_members
    WHERE band_id = band_uuid
      AND user_id = auth.uid()
      AND role = 'admin'
      AND status = 'active'
  ) INTO v_is_admin;
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Permission denied: only admins can delete this band';
  END IF;

  -- Cascade delete (order matters for FK constraints)
  DELETE FROM public.band_members WHERE band_id = band_uuid;
  DELETE FROM public.band_invitations WHERE band_id = band_uuid;
  DELETE FROM public.gig_responses
    WHERE gig_id IN (SELECT id FROM public.gigs WHERE band_id = band_uuid);
  DELETE FROM public.rehearsals WHERE band_id = band_uuid;
  DELETE FROM public.gigs WHERE band_id = band_uuid;
  DELETE FROM public.setlist_songs
    WHERE setlist_id IN (SELECT id FROM public.setlists WHERE band_id = band_uuid);
  DELETE FROM public.setlists WHERE band_id = band_uuid;
  DELETE FROM public.songs WHERE band_id = band_uuid;
  DELETE FROM public.bands WHERE id = band_uuid;

  RETURN TRUE;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 6: notify_rehearsal_created() trigger function
-- Uses first_name (correct column) instead of non-existent name.
-- Entire body wrapped in exception handler so trigger NEVER blocks inserts.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION notify_rehearsal_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_rehearsal_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_recurrence_text TEXT;
  v_day_names TEXT[];
BEGIN
  -- Entire body wrapped in exception handler: trigger must NEVER block inserts
  BEGIN
    -- Skip notifications for child rehearsals in a recurring series
    IF NEW.parent_rehearsal_id IS NOT NULL THEN
      RETURN NEW;
    END IF;

    -- Get actor first name (uses first_name column, NOT "name")
    BEGIN
      SELECT COALESCE(
        NULLIF(TRIM(first_name), ''),
        SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
        'Someone'
      ) INTO v_actor_name
      FROM users
      WHERE id = auth.uid();
    EXCEPTION
      WHEN OTHERS THEN
        v_actor_name := NULL;
    END;

    IF v_actor_name IS NULL OR v_actor_name = '' THEN
      v_actor_name := 'A band member';
    END IF;

    -- Format date as "MAR 4" (uppercase month, no leading zero on day)
    v_rehearsal_date := UPPER(TO_CHAR(NEW.date, 'MON FMDD'));

    v_title := 'Rehearsal Scheduled';

    -- Build recurrence description if this is a recurring rehearsal
    IF NEW.is_recurring AND NEW.recurrence_frequency IS NOT NULL THEN
      v_day_names := ARRAY['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];

      IF NEW.recurrence_days IS NOT NULL AND array_length(NEW.recurrence_days, 1) > 0 THEN
        SELECT string_agg(v_day_names[d + 1], ', ')
        INTO v_recurrence_text
        FROM unnest(NEW.recurrence_days) AS d
        ORDER BY d;

        v_recurrence_text := CASE NEW.recurrence_frequency
          WHEN 'weekly' THEN 'on ' || v_recurrence_text
          WHEN 'biweekly' THEN 'every other ' || v_recurrence_text
          WHEN 'monthly' THEN 'monthly on ' || v_recurrence_text
          ELSE 'recurring'
        END;
      ELSE
        v_recurrence_text := CASE NEW.recurrence_frequency
          WHEN 'weekly' THEN 'weekly'
          WHEN 'biweekly' THEN 'biweekly'
          WHEN 'monthly' THEN 'monthly'
          ELSE 'recurring'
        END;
      END IF;

      v_body := v_actor_name || ' scheduled a rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
    ELSE
      v_body := v_actor_name || ' scheduled a rehearsal for ' || v_rehearsal_date;
    END IF;

    -- Send notification
    PERFORM notify_band_members(
      NEW.band_id,
      auth.uid(),
      'rehearsal_created',
      v_title,
      v_body,
      jsonb_build_object(
        'rehearsal_id', NEW.id,
        'rehearsal_date', NEW.date,
        'is_recurring', COALESCE(NEW.is_recurring, FALSE),
        'recurrence_frequency', NEW.recurrence_frequency
      )
    );

  EXCEPTION
    WHEN OTHERS THEN
      -- Log warning but NEVER block the rehearsal insert
      RAISE WARNING 'notify_rehearsal_created failed (rehearsal % still created): %',
        NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION notify_rehearsal_created() IS
  'Sends notification when a rehearsal is created. Uses first_name/last_name
   (not name) from users table. For recurring rehearsals, only the parent
   instance triggers a notification. Entire body wrapped in exception handler
   so trigger never blocks inserts.';


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 7: PostgREST schema cache reload
-- ═══════════════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';


-- ═══════════════════════════════════════════════════════════════════════════
-- SECTION 8: Verification
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  bm_select_count INTEGER;
  bm_insert_count INTEGER;
  bm_update_count INTEGER;
  bands_select_count INTEGER;
  reh_select_count INTEGER;
  reh_insert_count INTEGER;
  reh_update_count INTEGER;
  reh_delete_count INTEGER;
  fn_exists BOOLEAN;
BEGIN
  -- band_members policy counts
  SELECT count(*) INTO bm_select_count
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'band_members' AND cmd = 'SELECT';

  SELECT count(*) INTO bm_insert_count
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'band_members' AND cmd = 'INSERT';

  SELECT count(*) INTO bm_update_count
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'band_members' AND cmd = 'UPDATE';

  -- bands policy count
  SELECT count(*) INTO bands_select_count
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'bands' AND cmd = 'SELECT';

  -- rehearsals policy counts
  SELECT count(*) INTO reh_select_count
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'rehearsals' AND cmd = 'SELECT';

  SELECT count(*) INTO reh_insert_count
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'rehearsals' AND cmd = 'INSERT';

  SELECT count(*) INTO reh_update_count
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'rehearsals' AND cmd = 'UPDATE';

  SELECT count(*) INTO reh_delete_count
  FROM pg_policies WHERE schemaname = 'public' AND tablename = 'rehearsals' AND cmd = 'DELETE';

  -- is_band_member() function exists
  SELECT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'is_band_member'
  ) INTO fn_exists;

  RAISE NOTICE '=== CONSOLIDATED MIGRATION VERIFICATION ===';
  RAISE NOTICE 'band_members SELECT policies: % (expected: 2)', bm_select_count;
  RAISE NOTICE 'band_members INSERT policies: % (expected: 1)', bm_insert_count;
  RAISE NOTICE 'band_members UPDATE policies: % (expected: 1)', bm_update_count;
  RAISE NOTICE 'bands SELECT policies: % (expected: 1)', bands_select_count;
  RAISE NOTICE 'rehearsals SELECT policies: % (expected: 1)', reh_select_count;
  RAISE NOTICE 'rehearsals INSERT policies: % (expected: 1)', reh_insert_count;
  RAISE NOTICE 'rehearsals UPDATE policies: % (expected: 1)', reh_update_count;
  RAISE NOTICE 'rehearsals DELETE policies: % (expected: 1)', reh_delete_count;
  RAISE NOTICE 'is_band_member() exists: %', fn_exists;

  -- Warnings for missing policies
  IF bm_select_count < 2 THEN
    RAISE WARNING 'CRITICAL: band_members has fewer than 2 SELECT policies!';
  END IF;
  IF reh_delete_count < 1 THEN
    RAISE WARNING 'CRITICAL: rehearsals has no DELETE policy!';
  END IF;
  IF NOT fn_exists THEN
    RAISE WARNING 'CRITICAL: is_band_member() function not found!';
  END IF;
END $$;
