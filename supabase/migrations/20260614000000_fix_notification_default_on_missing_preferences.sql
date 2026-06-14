-- ============================================================================
-- FIX: Default notification preferences to ON for missing rows and backfill
-- Created: 2026-06-14
-- Purpose: Ensure active band members receive event notifications even when
--          they have never visited Notification Settings.
-- ============================================================================

-- Replace helper semantics so a missing preferences row defaults to enabled.
CREATE OR REPLACE FUNCTION should_receive_notification(
  p_user_id UUID,
  p_notification_type TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_prefs notification_preferences;
  v_should_receive BOOLEAN := false;
BEGIN
  -- Get user preferences (use default if not found)
  SELECT * INTO v_prefs
  FROM notification_preferences
  WHERE user_id = p_user_id;

  -- If no preferences found, default to enabled.
  IF v_prefs IS NULL THEN
    RETURN true;
  END IF;

  -- If notifications are disabled globally, return false.
  IF NOT v_prefs.notifications_enabled THEN
    RETURN false;
  END IF;

  -- Check category-specific toggles
  CASE p_notification_type
    WHEN 'gig_created', 'gig_confirmed' THEN
      v_should_receive := v_prefs.gigs_enabled;
    WHEN 'potential_gig_created' THEN
      v_should_receive := v_prefs.potential_gigs_enabled;
    WHEN 'rehearsal_created' THEN
      v_should_receive := v_prefs.rehearsals_enabled;
    WHEN 'blockout_created' THEN
      v_should_receive := v_prefs.blockouts_enabled;
    ELSE
      -- For other types, default to enabled
      v_should_receive := true;
  END CASE;

  RETURN v_should_receive;
END;
$$;

-- Backfill default notification preferences for active band members who do not
-- yet have a row.
INSERT INTO notification_preferences (
  user_id
)
SELECT DISTINCT
  bm.user_id
FROM band_members bm
LEFT JOIN notification_preferences np
  ON np.user_id = bm.user_id
WHERE bm.status = 'active'
  AND np.user_id IS NULL
ON CONFLICT (user_id) DO NOTHING;