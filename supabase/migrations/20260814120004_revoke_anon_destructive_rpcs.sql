-- ============================================================================
-- Revoke anon access from destructive RPCs (defense in depth)
-- ============================================================================
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default
-- Risk: Anon role can attempt to call destructive operations
-- Mitigation: Functions already check auth.uid() internally, but explicit revocation
--              follows least-privilege principle
-- ============================================================================

-- Revoke PUBLIC and anon explicitly, grant only to authenticated
REVOKE ALL ON FUNCTION delete_band(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_band(UUID) TO authenticated;

REVOKE ALL ON FUNCTION update_member_role(UUID, UUID, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;

REVOKE ALL ON FUNCTION remove_band_member(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION remove_band_member(UUID, UUID) TO authenticated;

REVOKE ALL ON FUNCTION delete_user_account(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_user_account(UUID) TO authenticated;
