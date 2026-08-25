-- Fix: tenant-isolation critical gaps (narrowed scope)
-- Description: tighten songs access to band membership and remove stale anon grants on songs.

DROP POLICY IF EXISTS "songs_insert_authenticated" ON public.songs;
DROP POLICY IF EXISTS "songs_select_authenticated" ON public.songs;

CREATE POLICY "songs_insert_authenticated"
ON public.songs
FOR INSERT TO authenticated
WITH CHECK (is_band_member(band_id));

CREATE POLICY "songs_select_authenticated"
ON public.songs
FOR SELECT TO authenticated
USING (is_band_member(band_id));

REVOKE ALL ON TABLE public.songs FROM anon;
