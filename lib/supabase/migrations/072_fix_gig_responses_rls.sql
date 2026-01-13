-- ============================================================================
-- FIX GIG RESPONSES RLS POLICIES
-- Created: 2026-01-09
-- Issue: Band members getting "failed to update availability" error
-- Root cause: RLS policies may not properly check active membership
-- ============================================================================

-- Ensure RLS is enabled
ALTER TABLE public.gig_responses ENABLE ROW LEVEL SECURITY;

-- Drop existing policies
DROP POLICY IF EXISTS "Band members can view gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "Band members can create gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "Users can update their own gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "Band members can delete gig responses" ON public.gig_responses;

-- SELECT: Active band members can view responses for gigs in their bands
CREATE POLICY "Band members can view gig responses" ON public.gig_responses
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_responses.gig_id 
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
    )
  );

-- INSERT: Active band members can create responses for gigs in their bands
-- Note: user_id must match auth.uid() to prevent inserting on behalf of others
CREATE POLICY "Band members can create gig responses" ON public.gig_responses
  FOR INSERT WITH CHECK (
    -- User must be inserting for themselves
    user_id = auth.uid()
    AND
    -- User must be an active member of the band that owns the gig
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_id  -- Note: use column name directly, not table.column
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
    )
  );

-- UPDATE: Users can update their own gig responses (if still active member)
CREATE POLICY "Users can update their own gig responses" ON public.gig_responses
  FOR UPDATE USING (
    user_id = auth.uid()
    AND
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_responses.gig_id 
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
    )
  );

-- DELETE: Users can delete their own gig responses
CREATE POLICY "Band members can delete gig responses" ON public.gig_responses
  FOR DELETE USING (
    user_id = auth.uid()
  );

-- ============================================================================
-- DEBUG: Create a function to check why a user can't save availability
-- Run this in Supabase SQL Editor to diagnose issues:
-- 
-- SELECT check_gig_response_access('gig-uuid-here');
-- ============================================================================
CREATE OR REPLACE FUNCTION check_gig_response_access(p_gig_id UUID)
RETURNS TABLE (
  check_name TEXT,
  result BOOLEAN,
  details TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_band_id UUID;
BEGIN
  v_user_id := auth.uid();
  
  -- Check 1: Is user authenticated?
  RETURN QUERY SELECT 
    'User authenticated'::TEXT,
    v_user_id IS NOT NULL,
    COALESCE(v_user_id::TEXT, 'NULL');
  
  -- Check 2: Does gig exist?
  SELECT band_id INTO v_band_id FROM gigs WHERE id = p_gig_id;
  RETURN QUERY SELECT 
    'Gig exists'::TEXT,
    v_band_id IS NOT NULL,
    COALESCE('band_id: ' || v_band_id::TEXT, 'Gig not found');
  
  -- Check 3: Is user a band member?
  RETURN QUERY SELECT 
    'User is band member'::TEXT,
    EXISTS(SELECT 1 FROM band_members WHERE band_id = v_band_id AND user_id = v_user_id),
    (SELECT 'status: ' || COALESCE(status, 'NOT FOUND') || ', role: ' || COALESCE(role, 'N/A')
     FROM band_members WHERE band_id = v_band_id AND user_id = v_user_id);
  
  -- Check 4: Is member status active?
  RETURN QUERY SELECT 
    'Member status is active'::TEXT,
    EXISTS(SELECT 1 FROM band_members WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active'),
    (SELECT status FROM band_members WHERE band_id = v_band_id AND user_id = v_user_id);
  
  -- Check 5: Does existing response exist?
  RETURN QUERY SELECT 
    'Existing response'::TEXT,
    EXISTS(SELECT 1 FROM gig_responses WHERE gig_id = p_gig_id AND user_id = v_user_id),
    (SELECT response FROM gig_responses WHERE gig_id = p_gig_id AND user_id = v_user_id);
END;
$$;
