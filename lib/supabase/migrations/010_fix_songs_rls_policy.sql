-- Fix RLS policies for songs table to support upsert operations
-- Add missing UPDATE policy that allows authenticated users to update songs

CREATE POLICY "Songs can be updated by authenticated users" ON public.songs
  FOR UPDATE 
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');