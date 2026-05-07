-- ============================================================================
-- MIGRATION: Add Rehearsal Responses (RSVP for Potential Rehearsals)
-- Date: 2026-05-07
-- Branch: feature/potential-rehearsal-availability
--
-- Adds member availability/RSVP system for potential rehearsals, mirroring
-- the proven gig_responses pattern. This enables:
--   - Members respond yes/no to potential rehearsals
--   - Availability counts displayed on rehearsal cards
--   - App-open prompts for pending responses
--   - Full parity with potential gig RSVP system
--
-- CRITICAL NOTES:
--   - Rehearsals are single-date only (no rehearsal_date_id column needed)
--   - RLS helper function prevents infinite recursion (PostgreSQL 42P17)
--   - Unique constraint enforces one response per member per rehearsal
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 1: Table Creation
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.rehearsal_responses (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  rehearsal_id UUID NOT NULL REFERENCES public.rehearsals(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  response TEXT NOT NULL CHECK (response IN ('yes', 'no')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique constraint: one response per member per rehearsal
CREATE UNIQUE INDEX IF NOT EXISTS rehearsal_responses_rehearsal_user_unique 
ON public.rehearsal_responses (rehearsal_id, user_id);

-- Add table comment for documentation
COMMENT ON TABLE public.rehearsal_responses IS 
'Member RSVP responses for potential rehearsals. Each member can respond yes/no to indicate availability.';

COMMENT ON COLUMN public.rehearsal_responses.response IS 
'Member response: yes (available) or no (unavailable). Enforced by CHECK constraint.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 2: RLS Helper Function (SECURITY DEFINER)
-- ═══════════════════════════════════════════════════════════════════════════

-- Helper function to check if a user has access to a rehearsal's responses.
-- Used by RLS policies to avoid infinite recursion (PostgreSQL error 42P17).
-- 
-- Returns TRUE if the user is an active member of the rehearsal's band.
-- SECURITY DEFINER allows this function to bypass RLS and query band_members
-- without triggering recursive policy checks.
CREATE OR REPLACE FUNCTION public.check_rehearsal_response_access(
  p_rehearsal_id UUID,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if user is an active member of the rehearsal's band
  RETURN EXISTS (
    SELECT 1
    FROM public.rehearsals r
    JOIN public.band_members bm ON bm.band_id = r.band_id
    WHERE r.id = p_rehearsal_id
      AND bm.user_id = p_user_id
      AND bm.status = 'active'
  );
END;
$$;

COMMENT ON FUNCTION public.check_rehearsal_response_access(UUID, UUID) IS 
'RLS helper: checks if user is active member of rehearsal''s band. Used by rehearsal_responses policies.';

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 3: Row Level Security (RLS)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.rehearsal_responses ENABLE ROW LEVEL SECURITY;

-- Policy 1: SELECT - Band members can view responses for rehearsals in their bands
CREATE POLICY "Band members can view rehearsal responses"
  ON public.rehearsal_responses
  FOR SELECT
  USING (
    public.check_rehearsal_response_access(rehearsal_id, auth.uid())
  );

-- Policy 2: INSERT - Users can insert their own responses for rehearsals in their bands
CREATE POLICY "Users can insert own rehearsal responses"
  ON public.rehearsal_responses
  FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND public.check_rehearsal_response_access(rehearsal_id, auth.uid())
  );

-- Policy 3: UPDATE - Users can update their own responses
CREATE POLICY "Users can update own rehearsal responses"
  ON public.rehearsal_responses
  FOR UPDATE
  USING (
    user_id = auth.uid()
    AND public.check_rehearsal_response_access(rehearsal_id, auth.uid())
  )
  WITH CHECK (
    user_id = auth.uid()
    AND public.check_rehearsal_response_access(rehearsal_id, auth.uid())
  );

-- Policy 4: DELETE - Users can delete their own responses
CREATE POLICY "Users can delete own rehearsal responses"
  ON public.rehearsal_responses
  FOR DELETE
  USING (
    user_id = auth.uid()
    AND public.check_rehearsal_response_access(rehearsal_id, auth.uid())
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 4: Updated_at Trigger
-- ═══════════════════════════════════════════════════════════════════════════

-- Add trigger to automatically update updated_at timestamp
-- (assumes update_updated_at_column() function already exists from earlier migration)
CREATE TRIGGER rehearsal_responses_updated_at
  BEFORE UPDATE ON public.rehearsal_responses
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- ═══════════════════════════════════════════════════════════════════════════
-- END OF MIGRATION
-- ═══════════════════════════════════════════════════════════════════════════
