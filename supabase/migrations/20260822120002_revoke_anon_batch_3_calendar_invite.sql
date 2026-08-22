-- ============================================================================
-- BATCH 3: Revoke anon/PUBLIC execute from calendar and invite functions
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call calendar token and invite functions
-- Fix: Explicit revoke from PUBLIC and anon, re-grant to authenticated (except accept_band_invite)
-- 
-- SPECIAL HANDLING (Manager correction applied):
-- accept_band_invite — Currently has anon, authenticated, service_role grants
-- Called ONLY by accept-invite edge function via service_role key (not by client)
-- End state: service_role-only (revoke PUBLIC, anon, authenticated)
-- 
-- OVERLOADED FUNCTION: update_band_calendar_preferences has 2 signatures — both targeted
-- ============================================================================

-- Special case: accept_band_invite (service_role-only, edge function calls this)
REVOKE ALL ON FUNCTION accept_band_invite(p_invite_id uuid, p_user_id uuid) FROM PUBLIC, anon, authenticated;
-- No re-grant needed — service_role already has access, keep it that way

-- Calendar function 1: get_band_calendar_token
REVOKE ALL ON FUNCTION get_band_calendar_token(p_band_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_band_calendar_token(p_band_id uuid) TO authenticated;

-- Calendar function 2: get_my_calendar_token
REVOKE ALL ON FUNCTION get_my_calendar_token() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_my_calendar_token() TO authenticated;

-- Calendar function 3: regenerate_band_calendar_token
REVOKE ALL ON FUNCTION regenerate_band_calendar_token(p_band_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION regenerate_band_calendar_token(p_band_id uuid) TO authenticated;

-- Calendar function 4: regenerate_calendar_token
REVOKE ALL ON FUNCTION regenerate_calendar_token(p_user_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION regenerate_calendar_token(p_user_id uuid) TO authenticated;

-- Calendar function 5a: update_band_calendar_preferences (4-param overload)
REVOKE ALL ON FUNCTION update_band_calendar_preferences(p_band_id uuid, p_include_gigs boolean, p_include_rehearsals boolean, p_include_blockouts boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_band_calendar_preferences(p_band_id uuid, p_include_gigs boolean, p_include_rehearsals boolean, p_include_blockouts boolean) TO authenticated;

-- Calendar function 5b: update_band_calendar_preferences (6-param overload)
REVOKE ALL ON FUNCTION update_band_calendar_preferences(p_band_id uuid, p_include_gigs boolean, p_include_rehearsals boolean, p_include_blockouts boolean, p_include_potential_gigs boolean, p_include_potential_rehearsals boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_band_calendar_preferences(p_band_id uuid, p_include_gigs boolean, p_include_rehearsals boolean, p_include_blockouts boolean, p_include_potential_gigs boolean, p_include_potential_rehearsals boolean) TO authenticated;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state from PRE_MIGRATION_ACL_STATE.md)
-- ===========================================================================
-- CRITICAL: accept_band_invite, like is_band_member and create_band, had DIRECT grants
-- (no PUBLIC in acl_array) — rollback must use explicit role grants, not PUBLIC.
--
-- accept_band_invite pre-migration: postgres, anon, authenticated, service_role
-- All others pre-migration: PUBLIC grant (which includes anon)
--
-- To rollback:
--
-- GRANT EXECUTE ON FUNCTION accept_band_invite(p_invite_id uuid, p_user_id uuid) TO anon, authenticated;  -- Restore anon+authenticated (service_role already has)
-- GRANT EXECUTE ON FUNCTION get_band_calendar_token(p_band_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION get_my_calendar_token() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION regenerate_band_calendar_token(p_band_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION regenerate_calendar_token(p_user_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION update_band_calendar_preferences(p_band_id uuid, p_include_gigs boolean, p_include_rehearsals boolean, p_include_blockouts boolean) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION update_band_calendar_preferences(p_band_id uuid, p_include_gigs boolean, p_include_rehearsals boolean, p_include_blockouts boolean, p_include_potential_gigs boolean, p_include_potential_rehearsals boolean) TO PUBLIC;
