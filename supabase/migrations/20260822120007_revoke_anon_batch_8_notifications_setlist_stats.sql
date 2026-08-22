-- ============================================================================
-- BATCH 8: Revoke anon/PUBLIC execute from previously-missed notification and
-- setlist-stats functions (Manager gate correction — coverage gap found in
-- post-implementation verification, not in original classification)
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call notify_band_members (no internal auth check — can
-- inject arbitrary notifications into any band) and recompute_setlist_stats
-- Fix: Explicit revoke from PUBLIC and anon, re-grant to authenticated
--
-- SAFETY: Both functions are also called internally by SECURITY DEFINER
-- trigger functions already covered in Batch 1 (notify_band_members from
-- notify_gig_created, notify_rehearsal_created, and notify_blockout_created;
-- recompute_setlist_stats from trigger_recompute_setlist_stats). Internal
-- calls run as function owner and are unaffected by this revoke.
-- ============================================================================

-- Function 1: notify_band_members
REVOKE ALL ON FUNCTION notify_band_members(p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION notify_band_members(p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb) TO authenticated;

-- Function 2: recompute_setlist_stats
REVOKE ALL ON FUNCTION recompute_setlist_stats(p_setlist_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION recompute_setlist_stats(p_setlist_id uuid) TO authenticated;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state)
-- ===========================================================================
-- Both functions had PUBLIC grant in pre-migration state (confirmed via live
-- proacl query 2026-08-22). To rollback:
--
-- GRANT EXECUTE ON FUNCTION notify_band_members(p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION recompute_setlist_stats(p_setlist_id uuid) TO PUBLIC;
