-- 088_add_lyrics_youtube_to_update_song_rpc.sql
-- Add p_youtube_links and p_lyrics parameters to update_song_metadata RPC.
--
-- Previously the RPC only had 8 parameters (song_id, band_id, bpm,
-- duration_seconds, tuning, notes, title, artist). The Dart client was
-- sending p_youtube_links and p_lyrics but PostgREST silently ignored them,
-- so lyrics and YouTube links were never persisted via the RPC path.
--
-- The Dart client now uses direct UPDATE for lyrics/youtube_links, but this
-- migration ensures the RPC also supports them for completeness and for any
-- legacy songs with NULL band_id that require SECURITY DEFINER.

-- Drop all existing overloads to avoid signature conflicts
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

-- Recreate with 10 parameters (adding p_youtube_links and p_lyrics)
CREATE OR REPLACE FUNCTION update_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_bpm INTEGER DEFAULT NULL,
  p_duration_seconds INTEGER DEFAULT NULL,
  p_tuning TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL,
  p_youtube_links TEXT DEFAULT NULL,
  p_lyrics TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  v_song_band_id UUID;
  v_update_count INTEGER;
BEGIN
  -- Get the current user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  -- Verify user is an ACTIVE member of the band
  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id 
      AND user_id = v_user_id
      AND status = 'active'
  ) INTO v_is_member;
  
  IF NOT v_is_member THEN
    RETURN json_build_object('success', false, 'error', 'Access denied: not an active member of this band');
  END IF;
  
  -- Check if the song exists and get its band_id
  SELECT band_id INTO v_song_band_id
  FROM songs
  WHERE id = p_song_id;
  
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Song not found');
  END IF;
  
  -- Verify the song belongs to this band (or is a legacy song with NULL band_id)
  IF v_song_band_id IS NOT NULL AND v_song_band_id != p_band_id THEN
    RETURN json_build_object('success', false, 'error', 'Song belongs to a different band');
  END IF;
  
  -- Update the song with provided fields
  -- BPM only updates if currently NULL (prevents overwriting user edits)
  -- Other fields use COALESCE to preserve existing values when NULL is passed
  -- notes, youtube_links, and lyrics use explicit NULL check to allow clearing
  UPDATE songs
  SET
    bpm = CASE 
      WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm
      ELSE bpm
    END,
    duration_seconds = COALESCE(p_duration_seconds, duration_seconds),
    tuning = COALESCE(p_tuning, tuning),
    notes = CASE 
      WHEN p_notes IS NOT NULL THEN p_notes
      ELSE notes
    END,
    title = COALESCE(p_title, title),
    artist = COALESCE(p_artist, artist),
    youtube_links = CASE
      WHEN p_youtube_links IS NOT NULL THEN p_youtube_links
      ELSE youtube_links
    END,
    lyrics = CASE
      WHEN p_lyrics IS NOT NULL THEN p_lyrics
      ELSE lyrics
    END,
    updated_at = NOW()
  WHERE id = p_song_id;
  
  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;
  
  RETURN json_build_object('success', true);
END;
$$;

-- Grant execute permission (new 10-parameter signature)
GRANT EXECUTE ON FUNCTION update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION update_song_metadata IS 'Update song metadata including lyrics and YouTube links. BPM only updates when currently NULL to prevent overwriting user edits. Uses SECURITY DEFINER to bypass RLS for legacy songs.';
