-- ============================================================================
-- Revoke anon access from check_band_export_permission (defense in depth)
-- ============================================================================
-- Issue: Migration 20260821120000 included REVOKE FROM PUBLIC but not anon
-- Risk: Anon role can invoke the function (though it returns FALSE internally)
-- Fix: Explicit REVOKE FROM anon per established pattern (20260814120004)
-- ============================================================================

REVOKE ALL ON FUNCTION check_band_export_permission(UUID) FROM PUBLIC, anon;
