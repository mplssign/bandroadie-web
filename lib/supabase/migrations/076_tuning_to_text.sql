-- Migration: Change tuning column from enum to TEXT
-- This allows storing any tuning value, not just the 4 original enum values.
--
-- Original enum: tuning_type AS ENUM ('standard', 'drop_d', 'half_step', 'full_step')
-- New: TEXT column that accepts any tuning ID

-- Step 1: Alter the songs table - change tuning from enum to TEXT
ALTER TABLE public.songs
  ALTER COLUMN tuning TYPE TEXT USING tuning::TEXT;

-- Step 2: Set a sensible default
ALTER TABLE public.songs
  ALTER COLUMN tuning SET DEFAULT 'standard_e';

-- Step 3: Update the RPC function to remove the enum cast
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
  
  -- Update the song with provided fields
  -- Only update fields that are explicitly passed (not null)
  -- NOTE: tuning is now TEXT, no enum cast needed
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
  WHERE id = p_song_id
    AND (band_id = p_band_id OR band_id IS NULL);
  
  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Song not found or access denied');
  END IF;
  
  RETURN json_build_object('success', true);
END;
$$;

-- Re-grant execute permission
GRANT EXECUTE ON FUNCTION update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- Optional: Drop the old enum type if no longer needed
-- (Commenting out in case other tables use it)
-- DROP TYPE IF EXISTS tuning_type;
