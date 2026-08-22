-- ============================================================================
-- BATCH 1: Revoke anon/PUBLIC execute from trigger-bound functions
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call functions that should require authentication
-- Fix: Explicit revoke from PUBLIC and anon for 16 trigger-bound functions
-- 
-- SAFETY: These functions return type 'trigger' — PostgreSQL refuses to invoke
-- them outside trigger context. Revoking anon/PUBLIC is pure hygiene with
-- zero functional impact.
-- ============================================================================

-- Trigger function 1: auto_create_catalog_for_band
REVOKE ALL ON FUNCTION auto_create_catalog_for_band() FROM PUBLIC, anon;

-- Trigger function 2: handle_new_user
REVOKE ALL ON FUNCTION handle_new_user() FROM PUBLIC, anon;

-- Trigger function 3: handle_new_user_profile
REVOKE ALL ON FUNCTION handle_new_user_profile() FROM PUBLIC, anon;

-- Trigger function 4: notify_blockout_created
REVOKE ALL ON FUNCTION notify_blockout_created() FROM PUBLIC, anon;

-- Trigger function 5: notify_gig_created
REVOKE ALL ON FUNCTION notify_gig_created() FROM PUBLIC, anon;

-- Trigger function 6: notify_new_band_member
REVOKE ALL ON FUNCTION notify_new_band_member() FROM PUBLIC, anon;

-- Trigger function 7: notify_rehearsal_created
REVOKE ALL ON FUNCTION notify_rehearsal_created() FROM PUBLIC, anon;

-- Trigger function 8: prevent_catalog_deletion
REVOKE ALL ON FUNCTION prevent_catalog_deletion() FROM PUBLIC, anon;

-- Trigger function 9: prevent_catalog_rename
REVOKE ALL ON FUNCTION prevent_catalog_rename() FROM PUBLIC, anon;

-- Trigger function 10: reorder_setlist_positions
REVOKE ALL ON FUNCTION reorder_setlist_positions() FROM PUBLIC, anon;

-- Trigger function 11: sync_gig_location_from_venue
REVOKE ALL ON FUNCTION sync_gig_location_from_venue() FROM PUBLIC, anon;

-- Trigger function 12: sync_gig_pay_from_financial_entry
REVOKE ALL ON FUNCTION sync_gig_pay_from_financial_entry() FROM PUBLIC, anon;

-- Trigger function 13: trigger_recompute_setlist_stats
REVOKE ALL ON FUNCTION trigger_recompute_setlist_stats() FROM PUBLIC, anon;

-- Trigger function 14: trigger_send_push_notification
REVOKE ALL ON FUNCTION trigger_send_push_notification() FROM PUBLIC, anon;

-- Trigger function 15: update_setlist_duration
REVOKE ALL ON FUNCTION update_setlist_duration() FROM PUBLIC, anon;

-- Trigger function 16: update_song_notes_updated_at
REVOKE ALL ON FUNCTION update_song_notes_updated_at() FROM PUBLIC, anon;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state from PRE_MIGRATION_ACL_STATE.md)
-- ===========================================================================
-- All 16 trigger functions had PUBLIC grant in pre-migration state.
-- To rollback, restore PUBLIC grant (which implicitly includes anon):
--
-- GRANT EXECUTE ON FUNCTION auto_create_catalog_for_band() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION handle_new_user() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION handle_new_user_profile() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION notify_blockout_created() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION notify_gig_created() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION notify_new_band_member() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION notify_rehearsal_created() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION prevent_catalog_deletion() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION prevent_catalog_rename() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION reorder_setlist_positions() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION sync_gig_location_from_venue() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION sync_gig_pay_from_financial_entry() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION trigger_recompute_setlist_stats() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION trigger_send_push_notification() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION update_setlist_duration() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION update_song_notes_updated_at() TO PUBLIC;
