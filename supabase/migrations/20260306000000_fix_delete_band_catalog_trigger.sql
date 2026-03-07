-- Migration: fix_delete_band_catalog_trigger
-- Bug: delete_band RPC fails with "Cannot delete Catalog setlist"
-- Root cause: prevent_catalog_deletion trigger blocks all catalog setlist
--   deletions, including those performed by delete_band during band removal.
-- Fix: Use a transaction-local session variable (app.deleting_band) to allow
--   delete_band to bypass the trigger while preserving manual deletion protection.

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 1: Update prevent_catalog_deletion() trigger function
-- Add session variable bypass for band deletion context
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION prevent_catalog_deletion()
RETURNS TRIGGER AS $$
BEGIN
  -- Allow catalog deletion when called from delete_band (transaction-local flag)
  IF current_setting('app.deleting_band', true) = 'true' THEN
    RETURN OLD;
  END IF;

  IF OLD.setlist_type = 'catalog' OR OLD.is_catalog = true THEN
    RAISE EXCEPTION 'Cannot delete Catalog setlist';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- STEP 2: Update delete_band() RPC
-- Add set_config call before DELETE statements to set transaction-local flag
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.delete_band(band_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_band_exists BOOLEAN;
  v_is_admin BOOLEAN;
BEGIN
  SET search_path = public;

  -- Check band exists
  SELECT EXISTS (
    SELECT 1 FROM public.bands WHERE id = band_uuid
  ) INTO v_band_exists;
  IF NOT v_band_exists THEN
    RAISE EXCEPTION 'Band not found';
  END IF;

  -- Check: caller must be admin
  SELECT EXISTS (
    SELECT 1 FROM public.band_members
    WHERE band_id = band_uuid
      AND user_id = auth.uid()
      AND role = 'admin'
      AND status = 'active'
  ) INTO v_is_admin;
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Permission denied: only admins can delete this band';
  END IF;

  -- Set transaction-local flag to bypass catalog deletion trigger
  PERFORM set_config('app.deleting_band', 'true', true);

  -- Cascade delete (same as existing logic)
  DELETE FROM public.band_members WHERE band_id = band_uuid;
  DELETE FROM public.band_invitations WHERE band_id = band_uuid;
  DELETE FROM public.gig_responses
    WHERE gig_id IN (SELECT id FROM public.gigs WHERE band_id = band_uuid);
  DELETE FROM public.gigs WHERE band_id = band_uuid;
  DELETE FROM public.setlist_songs
    WHERE setlist_id IN (SELECT id FROM public.setlists WHERE band_id = band_uuid);
  DELETE FROM public.setlists WHERE band_id = band_uuid;
  DELETE FROM public.songs WHERE band_id = band_uuid;
  DELETE FROM public.bands WHERE id = band_uuid;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_band(UUID) TO authenticated;
