-- Migration: Bulk Add Songs to Setlist RPC
-- Description: Add batch insert function for improved performance when adding multiple songs to a setlist
-- Created: 2026-07-23

CREATE OR REPLACE FUNCTION bulk_add_songs_to_setlist(
  p_band_id UUID,
  p_setlist_id UUID,
  p_song_ids UUID[]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_max_position INT;
  v_existing_song_ids UUID[];
  v_songs_to_add UUID[];
  v_added_count INT := 0;
  v_skipped_count INT := 0;
BEGIN
  -- Get current user ID
  v_user_id := auth.uid();

  -- Verify user is an active band member
  IF NOT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = v_user_id
      AND status = 'active'
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'User is not an active member of this band'
    );
  END IF;

  -- Verify target setlist belongs to the band
  IF NOT EXISTS (
    SELECT 1 FROM setlists
    WHERE id = p_setlist_id
      AND band_id = p_band_id
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Setlist does not belong to this band'
    );
  END IF;

  -- Get max position in target setlist
  SELECT COALESCE(MAX(position), -1)
  INTO v_max_position
  FROM setlist_songs
  WHERE setlist_id = p_setlist_id;

  -- Get existing songs in target setlist
  SELECT ARRAY_AGG(song_id)
  INTO v_existing_song_ids
  FROM setlist_songs
  WHERE setlist_id = p_setlist_id
    AND song_id = ANY(p_song_ids);

  -- Filter out songs that already exist
  IF v_existing_song_ids IS NULL THEN
    v_songs_to_add := p_song_ids;
    v_skipped_count := 0;
  ELSE
    SELECT ARRAY_AGG(song_id)
    INTO v_songs_to_add
    FROM UNNEST(p_song_ids) AS song_id
    WHERE song_id != ALL(v_existing_song_ids);

    v_skipped_count := array_length(v_existing_song_ids, 1);
  END IF;

  -- If there are songs to add, insert them
  IF v_songs_to_add IS NOT NULL AND array_length(v_songs_to_add, 1) > 0 THEN
    -- Batch insert all new songs with sequential positions
    INSERT INTO setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds)
    SELECT
      p_setlist_id,
      song_id,
      v_max_position + row_number,
      NULL,  -- Let song defaults override
      NULL,  -- Let song defaults override
      NULL   -- Let song defaults override
    FROM (
      SELECT
        song_id,
        ROW_NUMBER() OVER () AS row_number
      FROM UNNEST(v_songs_to_add) AS song_id
    ) AS numbered_songs;

    v_added_count := array_length(v_songs_to_add, 1);
  ELSE
    v_added_count := 0;
  END IF;

  -- Return success with counts
  RETURN json_build_object(
    'success', true,
    'added_count', v_added_count,
    'skipped_count', COALESCE(v_skipped_count, 0)
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;
