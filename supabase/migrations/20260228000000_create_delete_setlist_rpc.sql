-- ============================================================================
-- Create delete_setlist RPC function for reliable setlist deletion
-- ============================================================================
-- This function handles:
-- 1. Band membership verification
-- 2. Catalog protection (cannot delete Catalog)
-- 3. Clearing setlist references from gigs and rehearsals (FK cleanup)
-- 4. Cascading deletion of setlist_songs
-- ============================================================================

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

  -- Get setlist info (use COALESCE for environments without is_catalog)
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
  SET setlist_id = NULL
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

-- Ensure DELETE RLS policies exist on setlists and setlist_songs
-- (these may already exist, but ensure they're present)
DO $$
BEGIN
  -- setlists DELETE policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'setlists'
    AND policyname = 'Band members can delete setlists'
  ) THEN
    CREATE POLICY "Band members can delete setlists" ON public.setlists
      FOR DELETE USING (
        EXISTS (
          SELECT 1 FROM public.band_members
          WHERE band_id = setlists.band_id
          AND user_id = auth.uid()
        )
      );
  END IF;

  -- setlist_songs DELETE policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'setlist_songs'
    AND policyname = 'Users can delete setlist songs if they can access the setlist'
  ) THEN
    CREATE POLICY "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs
      FOR DELETE USING (
        EXISTS (
          SELECT 1 FROM public.setlists s
          JOIN public.band_members bm ON s.band_id = bm.band_id
          WHERE s.id = setlist_songs.setlist_id
          AND bm.user_id = auth.uid()
        )
      );
  END IF;
END $$;

COMMENT ON FUNCTION delete_setlist IS
  'Deletes a setlist with proper permissions check and cascade cleanup.
   Clears references from gigs/rehearsals and deletes setlist_songs.
   Protected: Cannot delete Catalog setlist.';
