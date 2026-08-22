-- ============================================================================
-- BATCH 4: Revoke anon/PUBLIC execute from notification/preference functions
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call notification and preference functions
-- Fix: Explicit revoke from PUBLIC and anon, re-grant to authenticated
-- 
-- SAFETY: All 6 functions are called from authenticated user context (logged-in app).
-- Revoking anon access aligns grants with actual usage.
-- ============================================================================

-- Notification function 1: get_or_create_notification_preferences
REVOKE ALL ON FUNCTION get_or_create_notification_preferences() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_or_create_notification_preferences() TO authenticated;

-- Notification function 2: get_unread_notification_count
REVOKE ALL ON FUNCTION get_unread_notification_count() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_unread_notification_count() TO authenticated;

-- Notification function 3: mark_all_notifications_read
REVOKE ALL ON FUNCTION mark_all_notifications_read() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION mark_all_notifications_read() TO authenticated;

-- Notification function 4: upsert_device_token
REVOKE ALL ON FUNCTION upsert_device_token(p_fcm_token text, p_platform text, p_device_name text, p_old_token text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION upsert_device_token(p_fcm_token text, p_platform text, p_device_name text, p_old_token text) TO authenticated;

-- Preference function 1: get_or_create_calendar_preferences
REVOKE ALL ON FUNCTION get_or_create_calendar_preferences() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_or_create_calendar_preferences() TO authenticated;

-- Preference function 2: update_calendar_preferences
REVOKE ALL ON FUNCTION update_calendar_preferences(p_one_calendar_enabled boolean, p_apply_to_mode text, p_selected_band_ids uuid[], p_auto_block_conflicts_enabled boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_calendar_preferences(p_one_calendar_enabled boolean, p_apply_to_mode text, p_selected_band_ids uuid[], p_auto_block_conflicts_enabled boolean) TO authenticated;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state from PRE_MIGRATION_ACL_STATE.md)
-- ===========================================================================
-- All 6 functions had PUBLIC grant in pre-migration state.
--
-- To rollback:
--
-- GRANT EXECUTE ON FUNCTION get_or_create_notification_preferences() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION get_unread_notification_count() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION mark_all_notifications_read() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION upsert_device_token(p_fcm_token text, p_platform text, p_device_name text, p_old_token text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION get_or_create_calendar_preferences() TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION update_calendar_preferences(p_one_calendar_enabled boolean, p_apply_to_mode text, p_selected_band_ids uuid[], p_auto_block_conflicts_enabled boolean) TO PUBLIC;
