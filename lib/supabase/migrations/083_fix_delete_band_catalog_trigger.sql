-- 083_fix_delete_band_catalog_trigger.sql
-- Fix band deletion failing due to Catalog setlist protection trigger.
-- Allows CASCADE deletes when deleting a band, while still preventing
-- manual deletion of the Catalog setlist.

-- ------------------------------------------------------------
-- Trigger function: prevent manual deletion of Catalog setlist
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prevent_catalog_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Allow deletion if this delete is coming from a CASCADE
  -- (i.e. parent band is being deleted)
  IF pg_trigger_depth() > 1 THEN
    RETURN OLD;
  END IF;

  -- Block manual deletion of Catalog setlist
  IF COALESCE(OLD.is_catalog, false) = true THEN
    RAISE EXCEPTION 'Cannot delete Catalog setlist';
  END IF;

  RETURN OLD;
END;
$$;

-- Recreate trigger to ensure updated logic is active
DROP TRIGGER IF EXISTS prevent_catalog_deletion_trigger ON public.setlists;
CREATE TRIGGER prevent_catalog_deletion_trigger
  BEFORE DELETE ON public.setlists
  FOR EACH ROW
  EXECUTE FUNCTION public.prevent_catalog_deletion();

-- ------------------------------------------------------------
-- delete_band RPC: allow any active band member to delete band
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.delete_band(UUID);

CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_band_exists BOOLEAN;
  v_is_member BOOLEAN;
BEGIN
  SET search_path = public;

  -- Verify band exists
  SELECT EXISTS (
    SELECT 1 FROM public.bands WHERE id = band_uuid
  ) INTO v_band_exists;

  IF NOT v_band_exists THEN
    RAISE EXCEPTION 'Band not found';
  END IF;

  -- Verify caller is an active member of the band
  SELECT EXISTS (
    SELECT 1
    FROM public.band_members
    WHERE band_id = band_uuid
      AND user_id = auth.uid()
      AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Permission denied: only active band members can delete this band';
  END IF;

  -- Clean up tables that do NOT cascade automatically
  DELETE FROM public.gig_responses
    WHERE gig_id IN (
      SELECT id FROM public.gigs WHERE band_id = band_uuid
    );

  -- Delete the band FIRST
  -- This will CASCADE delete:
  -- - band_members
  -- - gigs
  -- - rehearsals
  -- - setlists (Catalog allowed via trigger)
  -- - songs
  -- - setlist_songs
  DELETE FROM public.bands WHERE id = band_uuid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Band deletion failed';
  END IF;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_band(UUID) TO authenticated;