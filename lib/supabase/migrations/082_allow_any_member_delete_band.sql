-- 082_allow_any_member_delete_band.sql
-- Allow any active band member to delete a band

-- Drop existing function first (return type changed from void to boolean)
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

  -- Check if band exists
  SELECT EXISTS (
    SELECT 1 FROM public.bands WHERE id = band_uuid
  ) INTO v_band_exists;

  IF NOT v_band_exists THEN
    RAISE EXCEPTION 'Band not found';
  END IF;

  -- Check if caller is an active member
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

  -- Delete dependent data
  DELETE FROM public.band_members WHERE band_id = band_uuid;
  DELETE FROM public.band_invitations WHERE band_id = band_uuid;
  DELETE FROM public.gig_responses
    WHERE gig_id IN (SELECT id FROM public.gigs WHERE band_id = band_uuid);
  DELETE FROM public.gigs WHERE band_id = band_uuid;
  DELETE FROM public.rehearsals WHERE band_id = band_uuid;
  DELETE FROM public.setlist_songs
    WHERE setlist_id IN (SELECT id FROM public.setlists WHERE band_id = band_uuid);
  DELETE FROM public.songs WHERE band_id = band_uuid;
  DELETE FROM public.setlists WHERE band_id = band_uuid;

  -- Delete the band itself
  DELETE FROM public.bands WHERE id = band_uuid;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_band(UUID) TO authenticated;