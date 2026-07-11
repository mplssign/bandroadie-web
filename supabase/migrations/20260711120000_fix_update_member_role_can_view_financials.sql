-- ============================================================================
-- Migration: Fix update_member_role to persist can_view_financials
-- Date: 2026-07-11
-- Branch: bug/contributor-view-financials-toggle-not-saving
-- ============================================================================
--
-- Problem: The update_member_role RPC function does not update the
-- can_view_financials column when saving contributor permissions, causing
-- the Admin UI toggle to appear to save but revert on reload.
--
-- Fix: Add can_view_financials to the UPDATE statement's SET clause.
--
-- Impact: Enables Admins to grant view-only financial access to Contributors.
-- No client changes required — Flutter code already sends this field correctly.
--
-- ============================================================================

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
        can_view_financials = COALESCE((p_sub_permissions->>'can_view_financials')::boolean, FALSE),
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
