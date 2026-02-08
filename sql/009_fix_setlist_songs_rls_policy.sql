-- Fix RLS policies for setlist_songs to support upsert operations
-- The UPDATE policy needs both USING and WITH CHECK clauses for upserts to work

DROP POLICY IF EXISTS "Users can update setlist songs if they can access the setlist" ON public.setlist_songs;

CREATE POLICY "Users can update setlist songs if they can access the setlist" ON public.setlist_songs
  FOR UPDATE 
  USING (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid() 
      AND bm.is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid() 
      AND bm.is_active = true
    )
  );