-- ============================================================================
-- MIGRATION: Band User Roles (RBAC)
-- Date: 2026-03-02
-- Branch: feature/band_user_roles
--
-- Introduces database-enforced Role-Based Access Control:
--   1. Collapse owner → admin
--   2. Promote ALL active members → admin (compatibility-first)
--   3. Create ENUM band_role_type (admin, member, contributor)
--   4. Alter band_members.role TEXT → ENUM
--   5. Default new members to 'member'
--   6. Drop legacy CHECK constraint
--   7. Create contributor_permissions table with RLS
--   8. Create/replace helper function get_user_band_role
--   9. Replace RLS policies on gigs, setlists, bands
--  10. Replace RPCs: delete_band, update_member_role, remove_band_member
--
-- INVARIANTS:
--   - No active member loses permissions at migration time
--   - At least one admin per band must always exist
--   - SECURITY DEFINER functions set search_path = public
--   - ENUM conversion must not fail due to leftover 'owner'
--   - No permissive DELETE policy may exist on bands
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 1: Role Value Migration
-- ═══════════════════════════════════════════════════════════════════════════

-- Step 1: Collapse owner → admin (before bulk promotion)
UPDATE public.band_members SET role = 'admin' WHERE role = 'owner';

-- Step 2: COMPATIBILITY MIGRATION — promote ALL existing active members to admin.
-- Before RBAC, every band member had unrestricted access. Promoting everyone to
-- admin ensures zero permission loss at deployment time. Band admins can then
-- reorganize roles manually using the Role Management UI.
-- Non-active rows (status = 'invited', 'inactive', 'removed') are left as-is
-- since they don't have functional access anyway.
UPDATE public.band_members SET role = 'admin' WHERE status = 'active';

-- Step 3: Create a PostgreSQL ENUM type for band roles
-- ENUM is stronger than a CHECK constraint: it is a distinct type enforced
-- at the storage layer, prevents typos in future queries, and is indexable.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'band_role_type') THEN
    CREATE TYPE public.band_role_type AS ENUM ('admin', 'member', 'contributor');
  END IF;
END $$;

-- Step 3.5: Pre-drop — remove ALL existing policies that depend on band_members.role
-- PostgreSQL cannot ALTER COLUMN TYPE when any RLS policy expression references
-- the column being altered. Rather than hard-coding every policy name (which
-- would miss dashboard-created policies), we dynamically discover and drop them.
-- Phases 4-6 below will recreate the correct RBAC-aware replacements.
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN
    SELECT policyname, schemaname, tablename
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (
        (qual IS NOT NULL AND qual::text LIKE '%band_members%' AND qual::text LIKE '%.role%')
        OR (with_check IS NOT NULL AND with_check::text LIKE '%band_members%' AND with_check::text LIKE '%.role%')
      )
  LOOP
    RAISE NOTICE 'Pre-RBAC: dropping policy "%" on %.%', pol.policyname, pol.schemaname, pol.tablename;
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', pol.policyname, pol.schemaname, pol.tablename);
  END LOOP;
END $$;

-- Step 4: Alter column from TEXT to ENUM
-- Requires an explicit USING cast since the column currently holds TEXT values.
-- All active rows are now 'admin'; non-active rows may still be 'member'.
-- Both are valid ENUM values, so the cast is safe.
-- NOTE: Must drop the existing TEXT default first — PostgreSQL cannot
-- automatically cast a TEXT default to an ENUM during ALTER COLUMN TYPE.
ALTER TABLE public.band_members
  ALTER COLUMN role DROP DEFAULT;

ALTER TABLE public.band_members
  ALTER COLUMN role TYPE public.band_role_type
  USING role::public.band_role_type;

-- Step 5: Default new members to 'member' (applies to future INSERTs only)
-- The band creator flow must explicitly set role = 'admin' for the creator.
ALTER TABLE public.band_members
  ALTER COLUMN role SET DEFAULT 'member'::public.band_role_type;

-- Step 6: Drop any legacy CHECK constraint (now redundant with ENUM)
ALTER TABLE public.band_members
  DROP CONSTRAINT IF EXISTS band_members_role_check;

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 2: Contributor Sub-Permissions Table
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE public.contributor_permissions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  band_member_id UUID NOT NULL REFERENCES public.band_members(id) ON DELETE CASCADE,
  can_create_gigs BOOLEAN NOT NULL DEFAULT TRUE,
  can_create_potential_gigs_only BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_setlists BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_calendar BOOLEAN NOT NULL DEFAULT TRUE,
  can_view_members BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(band_member_id)
);

ALTER TABLE public.contributor_permissions ENABLE ROW LEVEL SECURITY;

-- RLS: band members can read permissions for members in their bands
CREATE POLICY "Band members can view contributor permissions"
  ON public.contributor_permissions FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm1
      JOIN public.band_members bm2 ON bm1.band_id = bm2.band_id
      WHERE bm2.id = contributor_permissions.band_member_id
      AND bm1.user_id = auth.uid()
      AND bm1.status = 'active'
    )
  );

-- RLS: only admins can INSERT/UPDATE/DELETE contributor permissions
-- Uses separate USING and WITH CHECK to cover both read-path and write-path.
CREATE POLICY "Admins can manage contributor permissions"
  ON public.contributor_permissions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members admin_bm
      JOIN public.band_members target_bm ON admin_bm.band_id = target_bm.band_id
      WHERE target_bm.id = contributor_permissions.band_member_id
      AND admin_bm.user_id = auth.uid()
      AND admin_bm.role = 'admin'
      AND admin_bm.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members admin_bm
      JOIN public.band_members target_bm ON admin_bm.band_id = target_bm.band_id
      WHERE target_bm.id = contributor_permissions.band_member_id
      AND admin_bm.user_id = auth.uid()
      AND admin_bm.role = 'admin'
      AND admin_bm.status = 'active'
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 3: Helper Function
-- ═══════════════════════════════════════════════════════════════════════════

-- Returns the role of the current user in a given band.
--
-- SECURITY DECISION: SECURITY DEFINER is REMOVED.
-- Rationale: This function only reads band_members where user_id = auth.uid(),
-- which is already permitted by the existing SELECT RLS policy on band_members.
-- Using SECURITY DEFINER here would allow the function to bypass RLS for no
-- benefit, while introducing a privilege-escalation surface. Running as
-- SECURITY INVOKER (the default) ensures the caller's own RLS policies apply.
CREATE OR REPLACE FUNCTION public.get_user_band_role(p_band_id UUID)
RETURNS TEXT AS $$
  SELECT role::TEXT FROM public.band_members
  WHERE band_id = p_band_id
    AND user_id = auth.uid()
    AND status = 'active'
  LIMIT 1;
$$ LANGUAGE sql STABLE;

-- Grant to authenticated (no SECURITY DEFINER, runs under caller's RLS)
GRANT EXECUTE ON FUNCTION public.get_user_band_role(UUID) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 4: Updated RLS Policies — Gigs
-- ═══════════════════════════════════════════════════════════════════════════

-- Gigs INSERT: admin & member unrestricted; contributor needs can_create_gigs
-- and if can_create_potential_gigs_only is set, must insert is_potential = true
DROP POLICY IF EXISTS "Band members can create gigs" ON public.gigs;
CREATE POLICY "Band members can create gigs" ON public.gigs
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND (
        -- Admin & member: unrestricted
        bm.role IN ('admin', 'member')
        OR (
          -- Contributor: must have can_create_gigs
          bm.role = 'contributor'
          AND EXISTS (
            SELECT 1 FROM public.contributor_permissions cp
            WHERE cp.band_member_id = bm.id
            AND cp.can_create_gigs = TRUE
            AND (
              -- If potential-only flag is set, enforce is_potential = true
              cp.can_create_potential_gigs_only = FALSE
              OR gigs.is_potential = TRUE
            )
          )
        )
      )
    )
  );

-- Gigs UPDATE: admin & member only
DROP POLICY IF EXISTS "Band members can update gigs" ON public.gigs;
CREATE POLICY "Admins and members can update gigs" ON public.gigs
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- Gigs DELETE: admin & member only
DROP POLICY IF EXISTS "Band members can delete gigs" ON public.gigs;
CREATE POLICY "Admins and members can delete gigs" ON public.gigs
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 5: Updated RLS Policies — Setlists
-- ═══════════════════════════════════════════════════════════════════════════

-- Contributors get SELECT only (via existing/unchanged SELECT policy)

-- Setlists INSERT: admin & member only
DROP POLICY IF EXISTS "Band members can create setlists" ON public.setlists;
CREATE POLICY "Admins and members can create setlists" ON public.setlists
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- Setlists UPDATE (WITH CHECK ensures post-update row still passes)
DROP POLICY IF EXISTS "Band members can update setlists" ON public.setlists;
CREATE POLICY "Admins and members can update setlists" ON public.setlists
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- Setlists DELETE: admin & member only
DROP POLICY IF EXISTS "Band members can delete setlists" ON public.setlists;
CREATE POLICY "Admins and members can delete setlists" ON public.setlists
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 6: Updated RLS Policies — Bands (DELETE hardening)
-- ═══════════════════════════════════════════════════════════════════════════

-- Step 1: Remove any permissive DELETE policy on bands
DROP POLICY IF EXISTS "Band members can delete bands" ON public.bands;
DROP POLICY IF EXISTS "Anyone can delete bands" ON public.bands;
DROP POLICY IF EXISTS "Active members can delete bands" ON public.bands;

-- Step 2: Admin-only DELETE policy on bands table
CREATE POLICY "Only admins can delete bands" ON public.bands
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = bands.id
      AND bm.user_id = auth.uid()
      AND bm.role = 'admin'
      AND bm.status = 'active'
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 7: RPCs — delete_band (admin only, SECURITY DEFINER)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_band_exists BOOLEAN;
  v_is_admin BOOLEAN;
BEGIN
  SET search_path = public;

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

  -- Cascade delete (same as existing 082 migration)
  DELETE FROM public.band_members WHERE band_id = band_uuid;
  DELETE FROM public.band_invitations WHERE band_id = band_uuid;
  DELETE FROM public.gig_responses
    WHERE gig_id IN (SELECT id FROM public.gigs WHERE band_id = band_uuid);
  DELETE FROM public.gigs WHERE band_id = band_uuid;
  DELETE FROM public.setlist_songs
    WHERE setlist_id IN (SELECT id FROM public.setlists WHERE band_id = band_uuid);
  DELETE FROM public.setlists WHERE band_id = band_uuid;
  DELETE FROM public.songs WHERE band_id = band_uuid;
  DELETE FROM public.bands WHERE id = band_uuid;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_band(UUID) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 8: RPCs — update_member_role (admin only, SECURITY DEFINER)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_member_role(
  p_member_id UUID,
  p_band_id UUID,
  p_new_role TEXT,
  p_sub_permissions JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_role TEXT;
  v_target_current_role TEXT;
  v_admin_count INT;
BEGIN
  SET search_path = public;

  -- Caller must be admin
  SELECT role::TEXT INTO v_caller_role
  FROM public.band_members
  WHERE band_id = p_band_id AND user_id = auth.uid() AND status = 'active';

  IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
    RAISE EXCEPTION 'Permission denied: only admins can change roles';
  END IF;

  -- Validate new role (defense-in-depth; ENUM type also enforces this)
  IF p_new_role NOT IN ('admin', 'member', 'contributor') THEN
    RAISE EXCEPTION 'Invalid role: %', p_new_role;
  END IF;

  -- Get target's current role
  SELECT role::TEXT INTO v_target_current_role
  FROM public.band_members
  WHERE id = p_member_id AND band_id = p_band_id AND status = 'active';

  IF v_target_current_role IS NULL THEN
    RAISE EXCEPTION 'Member not found in this band';
  END IF;

  -- Prevent last admin demotion
  -- FOR UPDATE locks matching admin rows to prevent concurrent demotion race.
  IF v_target_current_role = 'admin' AND p_new_role != 'admin' THEN
    SELECT COUNT(*) INTO v_admin_count
    FROM public.band_members
    WHERE band_id = p_band_id AND role = 'admin' AND status = 'active'
    FOR UPDATE;

    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot demote: at least one admin must remain';
    END IF;
  END IF;

  -- Update role (cast text to enum)
  UPDATE public.band_members
  SET role = p_new_role::public.band_role_type
  WHERE id = p_member_id AND band_id = p_band_id;

  -- Handle contributor permissions
  IF p_new_role = 'contributor' THEN
    -- Upsert contributor permissions (defaults all to TRUE)
    INSERT INTO public.contributor_permissions (band_member_id)
    VALUES (p_member_id)
    ON CONFLICT (band_member_id) DO NOTHING;

    -- Apply sub-permissions if provided
    IF p_sub_permissions IS NOT NULL THEN
      UPDATE public.contributor_permissions
      SET
        can_create_gigs = COALESCE((p_sub_permissions->>'can_create_gigs')::boolean, TRUE),
        can_create_potential_gigs_only = COALESCE((p_sub_permissions->>'can_create_potential_gigs_only')::boolean, TRUE),
        can_view_setlists = COALESCE((p_sub_permissions->>'can_view_setlists')::boolean, TRUE),
        can_view_calendar = COALESCE((p_sub_permissions->>'can_view_calendar')::boolean, TRUE),
        can_view_members = COALESCE((p_sub_permissions->>'can_view_members')::boolean, TRUE),
        updated_at = NOW()
      WHERE band_member_id = p_member_id;
    END IF;
  ELSE
    -- Clean up contributor permissions if role changed away from contributor
    DELETE FROM public.contributor_permissions WHERE band_member_id = p_member_id;
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 9: RPCs — remove_band_member (admin only, SECURITY DEFINER)
-- ═══════════════════════════════════════════════════════════════════════════

-- Only admins can remove members (not self-remove)
-- Also prevents removing the last admin.
CREATE OR REPLACE FUNCTION public.remove_band_member(p_member_id UUID, p_band_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_role TEXT;
  v_target_user_id UUID;
  v_target_role TEXT;
  v_admin_count INT;
BEGIN
  SET search_path = public;

  -- Verify caller is admin
  SELECT role::TEXT INTO v_caller_role
  FROM public.band_members
  WHERE band_id = p_band_id AND user_id = auth.uid() AND status = 'active';

  IF v_caller_role IS NULL OR v_caller_role != 'admin' THEN
    RAISE EXCEPTION 'Permission denied: only admins can remove members';
  END IF;

  -- Get target member info
  SELECT user_id, role::TEXT INTO v_target_user_id, v_target_role
  FROM public.band_members
  WHERE id = p_member_id AND band_id = p_band_id;

  IF v_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  IF v_target_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot remove yourself';
  END IF;

  -- Prevent removing the last admin
  IF v_target_role = 'admin' THEN
    SELECT COUNT(*) INTO v_admin_count
    FROM public.band_members
    WHERE band_id = p_band_id AND role = 'admin' AND status = 'active'
    FOR UPDATE;

    IF v_admin_count <= 1 THEN
      RAISE EXCEPTION 'Cannot remove the last admin';
    END IF;
  END IF;

  DELETE FROM public.band_members WHERE id = p_member_id AND band_id = p_band_id;
  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_band_member(UUID, UUID) TO authenticated;
