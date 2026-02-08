-- Fix RLS policies for gigs and rehearsals tables
-- Ensures band members can create, read, update, and delete events

-- =============================================================================
-- REHEARSALS TABLE RLS POLICIES
-- =============================================================================

-- Enable RLS if not already enabled
ALTER TABLE public.rehearsals ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to recreate them consistently
DROP POLICY IF EXISTS "Band members can view rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can create rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can update rehearsals" ON public.rehearsals;
DROP POLICY IF EXISTS "Band members can delete rehearsals" ON public.rehearsals;

-- SELECT: Band members can view rehearsals for their bands
CREATE POLICY "Band members can view rehearsals" ON public.rehearsals
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = rehearsals.band_id 
      AND user_id = auth.uid()
    )
  );

-- INSERT: Band members can create rehearsals for their bands
CREATE POLICY "Band members can create rehearsals" ON public.rehearsals
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = rehearsals.band_id 
      AND user_id = auth.uid()
    )
  );

-- UPDATE: Band members can update rehearsals for their bands
CREATE POLICY "Band members can update rehearsals" ON public.rehearsals
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = rehearsals.band_id 
      AND user_id = auth.uid()
    )
  );

-- DELETE: Band members can delete rehearsals for their bands
CREATE POLICY "Band members can delete rehearsals" ON public.rehearsals
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = rehearsals.band_id 
      AND user_id = auth.uid()
    )
  );

-- =============================================================================
-- GIGS TABLE RLS POLICIES
-- =============================================================================

-- Enable RLS if not already enabled
ALTER TABLE public.gigs ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to recreate them consistently
DROP POLICY IF EXISTS "Band members can view gigs" ON public.gigs;
DROP POLICY IF EXISTS "Band members can create gigs" ON public.gigs;
DROP POLICY IF EXISTS "Band members can update gigs" ON public.gigs;
DROP POLICY IF EXISTS "Band members can delete gigs" ON public.gigs;

-- SELECT: Band members can view gigs for their bands
CREATE POLICY "Band members can view gigs" ON public.gigs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = gigs.band_id 
      AND user_id = auth.uid()
    )
  );

-- INSERT: Band members can create gigs for their bands
CREATE POLICY "Band members can create gigs" ON public.gigs
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = gigs.band_id 
      AND user_id = auth.uid()
    )
  );

-- UPDATE: Band members can update gigs for their bands
CREATE POLICY "Band members can update gigs" ON public.gigs
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = gigs.band_id 
      AND user_id = auth.uid()
    )
  );

-- DELETE: Band members can delete gigs for their bands
CREATE POLICY "Band members can delete gigs" ON public.gigs
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = gigs.band_id 
      AND user_id = auth.uid()
    )
  );

-- =============================================================================
-- GIG_RESPONSES TABLE RLS POLICIES (if not already set)
-- =============================================================================

-- Enable RLS if not already enabled
ALTER TABLE public.gig_responses ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to recreate them consistently
DROP POLICY IF EXISTS "Band members can view gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "Band members can create gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "Band members can update gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "Users can update their own gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "Band members can delete gig responses" ON public.gig_responses;

-- SELECT: Band members can view responses for gigs in their bands
CREATE POLICY "Band members can view gig responses" ON public.gig_responses
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_responses.gig_id 
      AND bm.user_id = auth.uid()
    )
  );

-- INSERT: Band members can create responses for gigs in their bands
CREATE POLICY "Band members can create gig responses" ON public.gig_responses
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_responses.gig_id 
      AND bm.user_id = auth.uid()
    )
  );

-- UPDATE: Users can update their own gig responses
CREATE POLICY "Users can update their own gig responses" ON public.gig_responses
  FOR UPDATE USING (
    user_id = auth.uid()
  );

-- DELETE: Users can delete their own gig responses
CREATE POLICY "Band members can delete gig responses" ON public.gig_responses
  FOR DELETE USING (
    user_id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_responses.gig_id 
      AND bm.user_id = auth.uid()
    )
  );
