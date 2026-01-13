-- Fix delete song RPC functions - remove is_active check from band_members
-- The band_members table does not have an is_active column

-- =============================================================================
-- DELETE SONG FROM SETLIST (removes setlist_songs row only)
-- =============================================================================

CREATE OR REPLACE FUNCTION delete_song_from_setlist(
  p_setlist_id UUID,
  p_song_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_band_id UUID;
  v_user_id UUID;
  v_deleted_count INTEGER;
  v_max_position INTEGER;
BEGIN
  -- Get the current user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  -- Get band_id from setlist and verify user is a band member
  SELECT s.band_id INTO v_band_id
  FROM setlists s
  JOIN band_members bm ON s.band_id = bm.band_id
  WHERE s.id = p_setlist_id
    AND bm.user_id = v_user_id;
  
  IF v_band_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Setlist not found or access denied');
  END IF;
  
  -- Get the max position to use as offset for safe reordering
  SELECT COALESCE(MAX(position), 0) INTO v_max_position
  FROM setlist_songs
  WHERE setlist_id = p_setlist_id;
  
  -- Delete the setlist_songs row
  DELETE FROM setlist_songs
  WHERE setlist_id = p_setlist_id
    AND song_id = p_song_id;
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  
  IF v_deleted_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Song not found in setlist');
  END IF;
  
  -- Reorder positions safely by using a two-step process:
  -- Step 1: Add a large offset to all positions to avoid conflicts
  UPDATE setlist_songs
  SET position = position + v_max_position + 1000
  WHERE setlist_id = p_setlist_id;
  
  -- Step 2: Renumber from 0 sequentially
  WITH ordered_songs AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY position) - 1 as new_position
    FROM setlist_songs
    WHERE setlist_id = p_setlist_id
  )
  UPDATE setlist_songs ss
  SET position = os.new_position
  FROM ordered_songs os
  WHERE ss.id = os.id;
  
  RETURN json_build_object('success', true, 'deleted_count', v_deleted_count);
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION delete_song_from_setlist(UUID, UUID) TO authenticated;


-- =============================================================================
-- DELETE SONG FROM CATALOG (removes from ALL setlists + deletes song record)
-- =============================================================================

CREATE OR REPLACE FUNCTION delete_song_from_catalog(
  p_band_id UUID,
  p_song_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_setlist_count INTEGER;
  v_song_exists BOOLEAN;
  v_setlist RECORD;
  v_max_position INTEGER;
BEGIN
  -- Get the current user
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;
  
  -- Verify user is a band member (no is_active check - column doesn't exist)
  IF NOT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = v_user_id
  ) THEN
    RETURN json_build_object('success', false, 'error', 'Not a member of this band');
  END IF;
  
  -- Check if song exists (check both band-specific and legacy songs)
  SELECT EXISTS (
    SELECT 1 FROM songs
    WHERE id = p_song_id
      AND (band_id = p_band_id OR band_id IS NULL)
  ) INTO v_song_exists;
  
  IF NOT v_song_exists THEN
    RETURN json_build_object('success', false, 'error', 'Song not found');
  END IF;
  
  -- Step 1: For each setlist in this band that contains the song,
  -- delete it and safely reorder positions
  FOR v_setlist IN
    SELECT DISTINCT ss.setlist_id
    FROM setlist_songs ss
    JOIN setlists s ON ss.setlist_id = s.id
    WHERE ss.song_id = p_song_id
      AND s.band_id = p_band_id
  LOOP
    -- Get max position for this setlist
    SELECT COALESCE(MAX(position), 0) INTO v_max_position
    FROM setlist_songs
    WHERE setlist_id = v_setlist.setlist_id;
    
    -- Delete the song from this setlist
    DELETE FROM setlist_songs
    WHERE setlist_id = v_setlist.setlist_id
      AND song_id = p_song_id;
    
    -- Safely reorder remaining songs
    UPDATE setlist_songs
    SET position = position + v_max_position + 1000
    WHERE setlist_id = v_setlist.setlist_id;
    
    WITH ordered_songs AS (
      SELECT id, ROW_NUMBER() OVER (ORDER BY position) - 1 as new_position
      FROM setlist_songs
      WHERE setlist_id = v_setlist.setlist_id
    )
    UPDATE setlist_songs ss
    SET position = os.new_position
    FROM ordered_songs os
    WHERE ss.id = os.id;
    
    v_setlist_count := COALESCE(v_setlist_count, 0) + 1;
  END LOOP;
  
  -- Step 2: Delete the song record itself
  -- Handle both band-specific songs and legacy songs with NULL band_id
  DELETE FROM songs
  WHERE id = p_song_id
    AND (band_id = p_band_id OR band_id IS NULL);
  
  RETURN json_build_object(
    'success', true,
    'setlists_updated', COALESCE(v_setlist_count, 0)
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION delete_song_from_catalog(UUID, UUID) TO authenticated;
