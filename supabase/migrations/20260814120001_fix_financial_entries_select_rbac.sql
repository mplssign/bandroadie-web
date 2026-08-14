-- ============================================================================
-- Fix financial_entries SELECT policy to honor can_view_financials permission
-- ============================================================================
-- Issue: Contributors with can_view_financials=false can still read financial data
-- Fix: Create helper function and update RLS policy to check permission
-- ============================================================================

-- Create helper function to check financial view permission
CREATE OR REPLACE FUNCTION check_financial_view_permission(p_band_id UUID)
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
  
  -- Contributors only have access if can_view_financials is true
  IF v_role = 'contributor' THEN
    SELECT COALESCE(cp.can_view_financials, FALSE) INTO v_can_view
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

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION check_financial_view_permission(UUID) TO authenticated;

-- Replace the SELECT policy to use the new helper function
DROP POLICY IF EXISTS "financial_entries_select" ON public.financial_entries;

CREATE POLICY "financial_entries_select" ON public.financial_entries
  FOR SELECT
  USING (public.check_financial_view_permission(band_id));
