-- ============================================================================
-- BATCH 2: Revoke anon/PUBLIC execute from RLS/permission helper functions
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call permission-check helpers
-- Fix: Explicit revoke from PUBLIC and anon, re-grant to authenticated
-- 
-- SAFETY: These helpers are used in RLS policies USING clauses. All RLS
-- policies gate on auth.uid() matching, so anon gets zero rows regardless.
-- Revoking anon execute adds defense-in-depth.
-- 
-- OVERLOADED FUNCTIONS: is_band_admin has 2 signatures — both targeted explicitly
-- ============================================================================

-- Helper 1: check_band_member
REVOKE ALL ON FUNCTION check_band_member(p_band_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION check_band_member(p_band_id uuid) TO authenticated;

-- Helper 2: check_financial_view_permission
REVOKE ALL ON FUNCTION check_financial_view_permission(p_band_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION check_financial_view_permission(p_band_id uuid) TO authenticated;

-- Helper 3: check_gig_response_access
REVOKE ALL ON FUNCTION check_gig_response_access(p_gig_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION check_gig_response_access(p_gig_id uuid) TO authenticated;

-- Helper 4: check_rehearsal_response_access
REVOKE ALL ON FUNCTION check_rehearsal_response_access(p_rehearsal_id uuid, p_user_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION check_rehearsal_response_access(p_rehearsal_id uuid, p_user_id uuid) TO authenticated;

-- Helper 5a: is_band_admin (1-arg overload)
REVOKE ALL ON FUNCTION is_band_admin(p_band_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_band_admin(p_band_id uuid) TO authenticated;

-- Helper 5b: is_band_admin (2-arg overload)
REVOKE ALL ON FUNCTION is_band_admin(user_uuid uuid, check_band_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_band_admin(user_uuid uuid, check_band_id uuid) TO authenticated;

-- Helper 6: is_band_member_with_role
-- SPECIAL CASE: Pre-migration state has PUBLIC + service_role but NOT authenticated
-- End state: Only authenticated + service_role (revoke PUBLIC removes anon implicitly)
REVOKE ALL ON FUNCTION is_band_member_with_role(p_band_id uuid, p_roles text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_band_member_with_role(p_band_id uuid, p_roles text[]) TO authenticated;

-- Helper 7: get_bandmate_user_ids
REVOKE ALL ON FUNCTION get_bandmate_user_ids(user_uuid uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_bandmate_user_ids(user_uuid uuid) TO authenticated;

-- Helper 8: get_user_band_ids
REVOKE ALL ON FUNCTION get_user_band_ids(user_uuid uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_user_band_ids(user_uuid uuid) TO authenticated;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state from PRE_MIGRATION_ACL_STATE.md)
-- ===========================================================================
-- All helpers had PUBLIC grant in pre-migration state except is_band_member_with_role
-- (which had PUBLIC but not authenticated).
--
-- To rollback:
--
-- GRANT EXECUTE ON FUNCTION check_band_member(p_band_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION check_financial_view_permission(p_band_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION check_gig_response_access(p_gig_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION check_rehearsal_response_access(p_rehearsal_id uuid, p_user_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION is_band_admin(p_band_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION is_band_admin(user_uuid uuid, check_band_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION is_band_member_with_role(p_band_id uuid, p_roles text[]) TO PUBLIC;  -- Had PUBLIC but not authenticated pre-migration
-- GRANT EXECUTE ON FUNCTION get_bandmate_user_ids(user_uuid uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION get_user_band_ids(user_uuid uuid) TO PUBLIC;
