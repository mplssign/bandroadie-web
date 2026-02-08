-- Fix RLS policies - remove is_active check from band_members
-- The band_members table may not have an is_active column in production
-- This migration updates all RLS policies to not require is_active = true

-- =============================================================================
-- SETLISTS TABLE RLS POLICIES
-- =============================================================================

DROP POLICY IF EXISTS "Band members can view setlists" ON public.setlists;
CREATE POLICY "Band members can view setlists" ON public.setlists
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlists.band_id 
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Band members can create setlists" ON public.setlists;
CREATE POLICY "Band members can create setlists" ON public.setlists
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlists.band_id 
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Band members can update setlists" ON public.setlists;
CREATE POLICY "Band members can update setlists" ON public.setlists
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlists.band_id 
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Band members can delete setlists" ON public.setlists;
CREATE POLICY "Band members can delete setlists" ON public.setlists
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlists.band_id 
      AND user_id = auth.uid()
    )
  );

-- =============================================================================
-- SETLIST_SONGS TABLE RLS POLICIES
-- =============================================================================

DROP POLICY IF EXISTS "Users can view setlist songs if they can view the setlist" ON public.setlist_songs;
CREATE POLICY "Users can view setlist songs if they can view the setlist" ON public.setlist_songs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can create setlist songs if they can access the setlist" ON public.setlist_songs;
CREATE POLICY "Users can create setlist songs if they can access the setlist" ON public.setlist_songs
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can update setlist songs if they can access the setlist" ON public.setlist_songs;
CREATE POLICY "Users can update setlist songs if they can access the setlist" ON public.setlist_songs
  FOR UPDATE 
  USING (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs;
CREATE POLICY "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid()
    )
  );
