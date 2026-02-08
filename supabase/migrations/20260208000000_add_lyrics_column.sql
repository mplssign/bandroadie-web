-- ============================================================================
-- Migration: Add lyrics column to songs table + update RPC
-- Run in Supabase SQL Editor
-- ============================================================================

-- 1. Add lyrics TEXT column to songs table
-- Stores JSON string of LyricsData (blocks with formatting metadata)
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS lyrics TEXT;

-- 2. Drop the old RPC and create new one with p_lyrics parameter
-- The old function has 9 params, new one needs 10
DROP FUNCTION IF EXISTS public.update_song_metadata(UUID, UUID, INT, INT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.update_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_bpm INT DEFAULT NULL,
  p_duration_seconds INT DEFAULT NULL,
  p_tuning TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL,
  p_youtube_links TEXT DEFAULT NULL,
  p_lyrics TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_updated BOOLEAN := FALSE;
  v_song_exists BOOLEAN;
BEGIN
  -- Verify the song exists
  SELECT EXISTS(
    SELECT 1 FROM public.songs WHERE id = p_song_id
  ) INTO v_song_exists;

  IF NOT v_song_exists THEN
    RETURN jsonb_build_object('success', false, 'error', 'Song not found');
  END IF;

  -- Build dynamic update - only update non-null parameters
  -- This allows callers to update specific fields without affecting others
  UPDATE public.songs
  SET
    bpm = COALESCE(p_bpm, bpm),
    duration_seconds = COALESCE(p_duration_seconds, duration_seconds),
    tuning = COALESCE(p_tuning, tuning),
    notes = CASE WHEN p_notes IS NOT NULL THEN p_notes ELSE notes END,
    title = COALESCE(p_title, title),
    artist = COALESCE(p_artist, artist),
    youtube_links = CASE WHEN p_youtube_links IS NOT NULL THEN p_youtube_links ELSE youtube_links END,
    lyrics = CASE WHEN p_lyrics IS NOT NULL THEN p_lyrics ELSE lyrics END,
    updated_at = NOW()
  WHERE id = p_song_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 3. Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.update_song_metadata(UUID, UUID, INT, INT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 4. Verify
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'songs' AND column_name = 'lyrics';
