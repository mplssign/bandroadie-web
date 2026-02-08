-- 081_fix_update_song_metadata_rpc.sql
-- Fix update_song_metadata RPC function to properly handle song updates.
--
-- Issues Fixed:
-- 1. Add status='active' filter to band_members check
-- 2. Better error messages to distinguish between authorization and song not found
-- 3. Handle songs that may have been created under a different band

-- First drop any remaining function overloads that might cause PGRST203
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, tuning_type);
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT);
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT);
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT);

-- Recreate the definitive 8-parameter version
CREATE OR REPLACE FUNCTION update_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_bpm INTEGER DEFAULT NULL,
  p_duration_seconds INTEGER DEFAULT NULL,
  p_tuning TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL
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
  
  -- First, check if the song exists and get its band_id
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
  -- Only update fields that are explicitly passed (not null)
  UPDATE songs
  SET
    bpm = COALESCE(p_bpm, bpm),
    duration_seconds = COALESCE(p_duration_seconds, duration_seconds),
    tuning = COALESCE(p_tuning, tuning),
    notes = CASE 
      WHEN p_notes IS NOT NULL THEN p_notes
      ELSE notes
    END,
    title = COALESCE(p_title, title),
    artist = COALESCE(p_artist, artist),
    updated_at = NOW()
  WHERE id = p_song_id;
  
  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  
  -- This should always succeed since we verified the song exists above
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;
  
  RETURN json_build_object('success', true);
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- Also fix clear_song_metadata with the same improvements
CREATE OR REPLACE FUNCTION clear_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_clear_bpm BOOLEAN DEFAULT FALSE,
  p_clear_duration BOOLEAN DEFAULT FALSE,
  p_clear_tuning BOOLEAN DEFAULT FALSE
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
  
  -- First, check if the song exists and get its band_id
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
  
  -- Update the song, clearing specified fields to NULL
  UPDATE songs
  SET
    bpm = CASE WHEN p_clear_bpm THEN NULL ELSE bpm END,
    duration_seconds = CASE WHEN p_clear_duration THEN NULL ELSE duration_seconds END,
    tuning = CASE WHEN p_clear_tuning THEN NULL ELSE tuning END,
    updated_at = NOW()
  WHERE id = p_song_id;
  
  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Clear failed unexpectedly');
  END IF;
  
  RETURN json_build_object('success', true);
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION clear_song_metadata(UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated;
