-- ============================================================================
-- Harden SECURITY DEFINER functions by adding SET search_path to function definition
-- ============================================================================
-- Issue: Functions have SET search_path inside body or missing entirely
-- Risk: Privilege escalation via search_path hijacking
-- Fix: ALTER functions to set search_path as a function attribute
-- ============================================================================

-- Functions with SET search_path in body (need to move to attribute)
ALTER FUNCTION delete_band(band_uuid uuid) SET search_path = public;
ALTER FUNCTION remove_band_member(p_member_id uuid, p_band_id uuid) SET search_path = public;
ALTER FUNCTION update_member_role(p_member_id uuid, p_band_id uuid, p_new_role text, p_sub_permissions jsonb) SET search_path = public;

-- Functions missing SET search_path entirely (need to add)
ALTER FUNCTION auto_create_catalog_for_band() SET search_path = public;
ALTER FUNCTION check_gig_response_access(p_gig_id uuid) SET search_path = public;
ALTER FUNCTION ensure_catalog_setlist(p_band_id uuid) SET search_path = public;
ALTER FUNCTION get_bandmate_user_ids(user_uuid uuid) SET search_path = public;
ALTER FUNCTION get_my_calendar_token() SET search_path = public;
ALTER FUNCTION get_or_create_notification_preferences() SET search_path = public;
ALTER FUNCTION get_unread_notification_count() SET search_path = public;
ALTER FUNCTION get_user_band_ids(user_uuid uuid) SET search_path = public;
ALTER FUNCTION increment_setlist_positions(p_setlist_id uuid) SET search_path = public;
ALTER FUNCTION is_band_member_with_role(p_band_id uuid, p_roles text[]) SET search_path = public;
ALTER FUNCTION mark_all_notifications_read() SET search_path = public;
ALTER FUNCTION notify_new_band_member() SET search_path = public;
ALTER FUNCTION prevent_catalog_deletion() SET search_path = public;
ALTER FUNCTION prevent_catalog_rename() SET search_path = public;
ALTER FUNCTION recompute_setlist_stats(p_setlist_id uuid) SET search_path = public;
ALTER FUNCTION trigger_recompute_setlist_stats() SET search_path = public;
ALTER FUNCTION update_setlist_duration() SET search_path = public;
ALTER FUNCTION update_song_notes_updated_at() SET search_path = public;
