-- 080_grant_delete_band_rpc.sql
-- Grant execute permission for delete_band RPC function.
-- This was commented out in the original migration 002_delete_band_function.sql.
-- Now granting it so authenticated users can delete bands they own.

-- Update the delete_band function to include ownership verification
CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)
RETURNS void AS $$
DECLARE
  v_caller_role TEXT;
  v_band_creator UUID;
BEGIN
  -- Check if caller is the band creator or an owner/admin
  SELECT created_by INTO v_band_creator
  FROM public.bands
  WHERE id = band_uuid;

  IF v_band_creator IS NULL THEN
    RAISE EXCEPTION 'Band not found';
  END IF;

  -- Allow if user is the creator
  IF v_band_creator = auth.uid() THEN
    -- Proceed with deletion
    NULL;
  ELSE
    -- Check if user is an admin/owner of the band
    SELECT role INTO v_caller_role
    FROM public.band_members
    WHERE band_id = band_uuid
      AND user_id = auth.uid()
      AND status = 'active';

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin', 'owner') THEN
      RAISE EXCEPTION 'Permission denied: only band creator or admin can delete a band';
    END IF;
  END IF;

  -- Remove dependent rows in a deterministic order
  DELETE FROM public.band_members WHERE band_id = band_uuid;
  DELETE FROM public.band_invitations WHERE band_id = band_uuid;
  DELETE FROM public.gig_responses WHERE gig_id IN (SELECT id FROM public.gigs WHERE band_id = band_uuid);
  DELETE FROM public.gigs WHERE band_id = band_uuid;
  DELETE FROM public.rehearsals WHERE band_id = band_uuid;
  DELETE FROM public.setlist_songs WHERE setlist_id IN (SELECT id FROM public.setlists WHERE band_id = band_uuid);
  DELETE FROM public.songs WHERE band_id = band_uuid;
  DELETE FROM public.setlists WHERE band_id = band_uuid;

  -- Finally remove the band row
  DELETE FROM public.bands WHERE id = band_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.delete_band(UUID) TO authenticated;
