-- ============================================================================
-- MIGRATION: Fix delete_band RPC — missing rehearsal cleanup
-- Date: 2026-03-06
--
-- ROOT CAUSE:
--   The RBAC migration (20260302000000_band_user_roles.sql) rewrote the
--   delete_band() function but omitted the rehearsal cleanup line that was
--   present in the original migration 082. This means deleting a band leaves
--   orphaned rehearsal rows (which would also block the band row delete due
--   to the band_id FK constraint).
--
-- FIX:
--   Add DELETE FROM public.rehearsals WHERE band_id = band_uuid before the
--   gigs deletion, restoring the cascade sequence from migration 082.
--
-- SECURITY:
--   - Function remains SECURITY DEFINER (same as current)
--   - Admin-only permission check unchanged
--   - No new privileges granted
-- ============================================================================

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

  -- Cascade delete
  DELETE FROM public.band_members WHERE band_id = band_uuid;
  DELETE FROM public.band_invitations WHERE band_id = band_uuid;
  DELETE FROM public.gig_responses
    WHERE gig_id IN (SELECT id FROM public.gigs WHERE band_id = band_uuid);
  DELETE FROM public.rehearsals WHERE band_id = band_uuid;
  DELETE FROM public.gigs WHERE band_id = band_uuid;
  DELETE FROM public.setlist_songs
    WHERE setlist_id IN (SELECT id FROM public.setlists WHERE band_id = band_uuid);
  DELETE FROM public.setlists WHERE band_id = band_uuid;
  DELETE FROM public.songs WHERE band_id = band_uuid;
  DELETE FROM public.bands WHERE id = band_uuid;

  RETURN TRUE;
END;
$$;
