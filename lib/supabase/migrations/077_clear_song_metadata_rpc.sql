-- Migration: Add clear_song_metadata RPC function
-- This function allows clearing BPM, duration, or tuning to NULL
-- Uses SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id
--
-- Why this is needed:
-- The update_song_metadata RPC uses COALESCE which preserves existing values when NULL is passed.
-- This makes it impossible to clear a field to NULL using that function.
-- This new function specifically handles clearing fields to NULL.

-- Drop existing function if it exists (required when changing return type)
DROP FUNCTION IF EXISTS clear_song_metadata(UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN);

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
  v_update_count INTEGER;
BEGIN
  -- Get the current user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  -- Verify user is a member of the band
  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id
  ) INTO v_is_member;
  
  IF NOT v_is_member THEN
    RETURN json_build_object('success', false, 'error', 'Access denied');
  END IF;
  
  -- Update the song, clearing specified fields to NULL
  UPDATE songs
  SET
    bpm = CASE WHEN p_clear_bpm THEN NULL ELSE bpm END,
    duration_seconds = CASE WHEN p_clear_duration THEN NULL ELSE duration_seconds END,
    tuning = CASE WHEN p_clear_tuning THEN NULL ELSE tuning END,
    updated_at = NOW()
  WHERE id = p_song_id
    AND (band_id = p_band_id OR band_id IS NULL);
  
  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Song not found or access denied');
  END IF;
  
  RETURN json_build_object('success', true);
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION clear_song_metadata(UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated;
