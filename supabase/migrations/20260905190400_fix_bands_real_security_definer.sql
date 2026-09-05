-- ============================================================================
-- Fix bands_real security definer view (Supabase advisor: CRITICAL)
-- ============================================================================
-- bands_real (added in 20260904120000_demo_bands_schema.sql) had no
-- security_invoker setting, so it ran with the view owner's privileges and
-- bypassed the bands_select_members RLS policy on public.bands. Because the
-- view lives in the public schema, PostgREST auto-exposed it, so any
-- authenticated caller could read every real band in the system via
-- GET /rest/v1/bands_real, not just bands they're a member of.
--
-- This view is for internal admin/analytics use only (see comment in
-- 20260904120000); nothing in the app queries it (confirmed via grep).
--
-- Fix, applied directly to prod via SQL editor on 2026-09-05 and tracked
-- here for reproducibility:
--   1. security_invoker = true so RLS on the underlying bands table applies
--      to the querying user instead of the view owner.
--   2. Revoke anon/authenticated grants outright — this view has no
--      legitimate end-user consumer. Future admin/analytics tooling should
--      use service_role, which bypasses RLS/grants regardless of this
--      setting.
--
-- Rollback reference:
-- ALTER VIEW public.bands_real RESET (security_invoker);
-- GRANT SELECT ON public.bands_real TO anon, authenticated;
-- ============================================================================

ALTER VIEW public.bands_real SET (security_invoker = true);

REVOKE ALL ON public.bands_real FROM anon, authenticated;
