-- Migration: Add move_song_between_setlists RPC for atomic song moves
-- Feature: setlist-swipe-move-song
-- Purpose: Atomically move a song from source setlist to target setlist (insert + delete in one transaction)

CREATE OR REPLACE FUNCTION move_song_between_setlists(
  p_source_setlist_id UUID,
  p_target_setlist_id UUID,
  p_song_id UUID,
  p_band_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_position INTEGER;
  v_source_band_id UUID;
  v_target_band_id UUID;
  v_user_is_member BOOLEAN;
BEGIN
  -- Verify user is active member of band
  SELECT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
    AND user_id = auth.uid()
  ) INTO v_user_is_member;

  IF NOT v_user_is_member THEN
    RETURN json_build_object(
      'success', false,
      'error', 'User is not a member of this band'
    );
  END IF;

  -- Verify source setlist belongs to band
  SELECT band_id INTO v_source_band_id
  FROM setlists
  WHERE id = p_source_setlist_id;

  IF v_source_band_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Source setlist not found'
    );
  END IF;

  IF v_source_band_id != p_band_id THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Source setlist does not belong to this band'
    );
  END IF;

  -- Verify target setlist belongs to band
  SELECT band_id INTO v_target_band_id
  FROM setlists
  WHERE id = p_target_setlist_id;

  IF v_target_band_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Target setlist not found'
    );
  END IF;

  IF v_target_band_id != p_band_id THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Target setlist does not belong to this band'
    );
  END IF;

  -- Check if song already exists in target setlist
  IF EXISTS (
    SELECT 1 FROM setlist_songs
    WHERE setlist_id = p_target_setlist_id
    AND song_id = p_song_id
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Song already exists in target setlist'
    );
  END IF;

  -- Get max position in target setlist
  SELECT COALESCE(MAX(position), -1) INTO v_max_position
  FROM setlist_songs
  WHERE setlist_id = p_target_setlist_id;

  -- Delete from source setlist FIRST
  -- This prevents any temporary constraint violations if a song can only be in one setlist at a time
  DELETE FROM setlist_songs
  WHERE setlist_id = p_source_setlist_id
  AND song_id = p_song_id;

  -- Then insert into target setlist at next position
  -- IMPORTANT: Explicitly set override fields to NULL to prevent DB defaults
  -- from applying (e.g., tuning DEFAULT 'standard' would override song's actual tuning)
  -- If this INSERT fails, the DELETE above is rolled back (atomic transaction)
  INSERT INTO setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds)
  VALUES (p_target_setlist_id, p_song_id, v_max_position + 1, NULL, NULL, NULL);

  -- Return success
  RETURN json_build_object(
    'success', true,
    'moved_count', 1
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;
