-- ============================================================================
-- BATCH 7: Revoke anon/PUBLIC execute from band and member management functions
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call band and member management functions
-- Fix: Explicit revoke from PUBLIC and anon, re-grant to authenticated
-- 
-- SPECIAL HANDLING:
-- create_band — Like accept_band_invite and is_band_member, this function had
-- DIRECT grants (no PUBLIC in acl_array). Rollback must use explicit role grants.
-- 
-- is_band_member — Also has direct grants (no PUBLIC). Included here for completeness
-- though it's a helper, not a mutation function.
-- ============================================================================

-- Band management function 1: create_band
-- SPECIAL CASE: Pre-migration had postgres, anon, authenticated, service_role (no PUBLIC grant)
REVOKE ALL ON FUNCTION create_band(p_name text, p_avatar_color text, p_image_url text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_band(p_name text, p_avatar_color text, p_image_url text) TO authenticated;

-- Band management function 2: create_venue_for_gig_save
REVOKE ALL ON FUNCTION create_venue_for_gig_save(p_band_id uuid, p_name text, p_city text, p_address text, p_state text, p_is_potential boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_venue_for_gig_save(p_band_id uuid, p_name text, p_city text, p_address text, p_state text, p_is_potential boolean) TO authenticated;

-- Member management function 1: reorder_band_members
REVOKE ALL ON FUNCTION reorder_band_members(p_band_id uuid, p_member_ids uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reorder_band_members(p_band_id uuid, p_member_ids uuid[]) TO authenticated;

-- Member management function 2: restore_band_members
REVOKE ALL ON FUNCTION restore_band_members(p_band_id uuid, p_members jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION restore_band_members(p_band_id uuid, p_members jsonb) TO authenticated;

-- Helper function (included for completeness): is_band_member
-- SPECIAL CASE: Pre-migration had postgres, service_role, authenticated, anon (no PUBLIC grant)
REVOKE ALL ON FUNCTION is_band_member(p_band_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_band_member(p_band_id uuid) TO authenticated;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state from PRE_MIGRATION_ACL_STATE.md)
-- ===========================================================================
-- CRITICAL: create_band and is_band_member had DIRECT grants (no PUBLIC in acl_array).
-- Rollback must use explicit role grants, not PUBLIC.
--
-- create_band pre-migration: postgres, anon, authenticated, service_role
-- is_band_member pre-migration: postgres, service_role, authenticated, anon
-- Other 3 functions pre-migration: PUBLIC grant (which includes anon)
--
-- To rollback:
--
-- GRANT EXECUTE ON FUNCTION create_band(p_name text, p_avatar_color text, p_image_url text) TO anon;  -- Restore anon (authenticated already has)
-- GRANT EXECUTE ON FUNCTION create_venue_for_gig_save(p_band_id uuid, p_name text, p_city text, p_address text, p_state text, p_is_potential boolean) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION reorder_band_members(p_band_id uuid, p_member_ids uuid[]) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION restore_band_members(p_band_id uuid, p_members jsonb) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION is_band_member(p_band_id uuid) TO anon;  -- Restore anon (authenticated already has)
