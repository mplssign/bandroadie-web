-- ============================================================================
-- Fix band_members self-insert privilege escalation (CRITICAL)
-- ============================================================================
-- band_members_insert_self_or_member (added in
-- 20260825120000_consolidate_permissive_rls_policies.sql) allowed:
--   WITH CHECK (is_band_member(band_id) OR user_id = auth.uid())
--
-- The "OR user_id = auth.uid()" branch let ANY authenticated caller —
-- including anonymous demo sessions — insert themselves into ANY band's
-- membership directly via the REST API, with no invitation check:
--   POST /rest/v1/band_members {band_id: <any band>, user_id: <self>, role: "admin"}
-- role has no constraint blocking self-assignment and status defaults to
-- 'active', so this granted instant admin access to any band in the system.
--
-- Confirmed this branch is unused by any legitimate flow:
--   - Invite acceptance goes through the accept-invite edge function
--     (service_role, bypasses RLS entirely).
--   - Band creation goes through create_band(), which is SECURITY DEFINER
--     (also bypasses RLS).
--   - grep of lib/ found no direct client-side .insert() into band_members.
--
-- Applied directly to prod via SQL editor on 2026-09-05 and tracked here for
-- reproducibility.
--
-- Rollback reference:
-- DROP POLICY IF EXISTS "band_members_insert_self_or_member" ON public.band_members;
-- CREATE POLICY "band_members_insert_self_or_member" ON public.band_members
-- FOR INSERT TO authenticated
-- WITH CHECK (is_band_member(band_id) OR user_id = (select auth.uid()));
-- ============================================================================

DROP POLICY IF EXISTS "band_members_insert_self_or_member" ON public.band_members;

CREATE POLICY "band_members_insert_self_or_member" ON public.band_members
FOR INSERT TO authenticated
WITH CHECK (is_band_member(band_id));
