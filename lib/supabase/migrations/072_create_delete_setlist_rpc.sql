-- Create delete_setlist RPC function for reliable setlist deletion
-- This function handles:
-- 1. Band membership verification
-- 2. Catalog protection (cannot delete Catalog)
-- 3. Cascading deletion of setlist_songs
-- 4. Clearing setlist references from gigs and rehearsals

-- =============================================================================
-- DELETE SETLIST RPC
-- =============================================================================

CREATE OR REPLACE FUNCTION delete_setlist(
  p_band_id UUID,
  p_setlist_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_setlist_name TEXT;
  v_is_catalog BOOLEAN;
BEGIN
  -- Verify band membership
  IF NOT EXISTS (
    SELECT 1 FROM band_members 
    WHERE band_id = p_band_id 
    AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Access denied: Not a member of this band';
  END IF;

  -- Get setlist info
  SELECT name, COALESCE(is_catalog, FALSE)
  INTO v_setlist_name, v_is_catalog
  FROM setlists
  WHERE id = p_setlist_id AND band_id = p_band_id;

  -- Check if setlist exists
  IF v_setlist_name IS NULL THEN
    RAISE EXCEPTION 'Setlist not found or does not belong to this band';
  END IF;

  -- Prevent deletion of Catalog
  IF v_is_catalog OR v_setlist_name = 'Catalog' OR v_setlist_name = 'All Songs' THEN
    RAISE EXCEPTION 'Cannot delete the Catalog setlist';
  END IF;

  -- Clear setlist references from gigs (set to NULL instead of failing)
  UPDATE gigs 
  SET setlist_id = NULL, setlist_name = NULL
  WHERE setlist_id = p_setlist_id AND band_id = p_band_id;

  -- Clear setlist references from rehearsals (set to NULL instead of failing)
  UPDATE rehearsals 
  SET setlist_id = NULL
  WHERE setlist_id = p_setlist_id AND band_id = p_band_id;

  -- Delete setlist_songs (FK constraint would cascade, but be explicit)
  DELETE FROM setlist_songs WHERE setlist_id = p_setlist_id;

  -- Delete the setlist
  DELETE FROM setlists WHERE id = p_setlist_id AND band_id = p_band_id;

END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION delete_setlist(UUID, UUID) TO authenticated;

-- Add comment for documentation
COMMENT ON FUNCTION delete_setlist IS 
  'Deletes a setlist with proper permissions check and cascade cleanup. 
   Clears references from gigs/rehearsals and deletes setlist_songs.
   Protected: Cannot delete Catalog setlist.';
