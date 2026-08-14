-- Migration: Harden remaining SECURITY DEFINER functions with search_path
-- Description: Add SET search_path = public to 7 additional functions discovered during post-deployment audit
-- Ticket: Finding #4 (Search Path Privilege Escalation)

-- These 7 functions were missing from the initial bulk ALTER in migration 20260814120003
ALTER FUNCTION generate_invite_token() SET search_path = public;
ALTER FUNCTION get_band_full_state(p_band_id uuid) SET search_path = public;
ALTER FUNCTION should_receive_notification(p_user_id uuid, p_notification_type text) SET search_path = public;
ALTER FUNCTION update_notification_preferences_updated_at() SET search_path = public;
ALTER FUNCTION update_print_templates_updated_at() SET search_path = public;
ALTER FUNCTION update_updated_at_column() SET search_path = public;
ALTER FUNCTION update_user_calendar_preferences_updated_at() SET search_path = public;
