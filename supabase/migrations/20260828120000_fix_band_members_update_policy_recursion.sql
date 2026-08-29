-- ============================================================================
-- Fix band_members UPDATE policy recursion
-- ============================================================================
-- Pre-migration rollback reference:
-- DROP POLICY IF EXISTS "band_members_update_admins" ON public.band_members;
-- CREATE POLICY "band_members_update_admins" ON public.band_members
-- FOR UPDATE TO authenticated
-- USING (is_band_admin(band_id))
-- WITH CHECK (is_band_admin(band_id));
-- ============================================================================

DROP POLICY IF EXISTS "band_members_update_admins" ON public.band_members;

CREATE POLICY "band_members_update_admins" ON public.band_members
FOR UPDATE TO authenticated
USING (is_band_admin(band_id))
WITH CHECK (is_band_admin(band_id));
