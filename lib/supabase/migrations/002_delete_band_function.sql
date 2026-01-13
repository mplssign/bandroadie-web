-- 002_delete_band_function.sql
-- Atomic deletion function for a band and its dependent rows.

CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)
RETURNS void AS $$
BEGIN
  -- Remove dependent rows in a deterministic order
  DELETE FROM public.band_members WHERE band_id = band_uuid;
  DELETE FROM public.band_invitations WHERE band_id = band_uuid;
  DELETE FROM public.gigs WHERE band_id = band_uuid;
  DELETE FROM public.rehearsals WHERE band_id = band_uuid;
  DELETE FROM public.setlists WHERE band_id = band_uuid;

  -- Finally remove the band row
  DELETE FROM public.bands WHERE id = band_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated role if needed (optional; keep restricted)
-- GRANT EXECUTE ON FUNCTION public.delete_band(UUID) TO authenticated;
