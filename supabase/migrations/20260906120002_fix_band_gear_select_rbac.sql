-- ============================================================================
-- Fix band_gear SELECT policy to honor can_view_gear permission
-- ============================================================================
-- Issue: Contributors with can_view_gear=false can still read gear data
-- Fix: Create helper function and update RLS policy to check permission
-- ============================================================================

-- Create helper function to check gear view permission
CREATE OR REPLACE FUNCTION public.check_gear_view_permission(p_band_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_role TEXT;
  v_can_view BOOLEAN;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Get user's role in the band
  SELECT role INTO v_role
  FROM band_members
  WHERE band_id = p_band_id
    AND user_id = v_user_id
    AND status = 'active';

  -- If not a member, deny access
  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Admin and member roles always have access
  IF v_role IN ('admin', 'member') THEN
    RETURN TRUE;
  END IF;

  -- Contributors only have access if can_view_gear is true
  IF v_role = 'contributor' THEN
    SELECT COALESCE(cp.can_view_gear, FALSE) INTO v_can_view
    FROM band_members bm
    LEFT JOIN contributor_permissions cp ON cp.band_member_id = bm.id
    WHERE bm.band_id = p_band_id
      AND bm.user_id = v_user_id
      AND bm.status = 'active';

    RETURN COALESCE(v_can_view, FALSE);
  END IF;

  -- Default deny
  RETURN FALSE;
END;
$$;

-- Lock down execute privileges: revoke from PUBLIC/anon, grant to authenticated
REVOKE ALL ON FUNCTION public.check_gear_view_permission(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.check_gear_view_permission(UUID) TO authenticated;

-- Replace the base SELECT policy to use the new helper function
DROP POLICY IF EXISTS "Band members can view gear" ON public.band_gear;

CREATE POLICY "Band members can view gear" ON public.band_gear
  FOR SELECT
  USING (public.check_gear_view_permission(band_id));
