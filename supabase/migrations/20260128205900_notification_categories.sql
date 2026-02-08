-- ============================================================================
-- NOTIFICATION CATEGORIES UPDATE
-- Created: 2026-01-28
-- Purpose: Simplify notification preferences to 4 event-driven categories
-- ============================================================================

-- Add new simplified category columns to notification_preferences
ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS notifications_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS gigs_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS potential_gigs_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS rehearsals_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS blockouts_enabled BOOLEAN DEFAULT true;

-- Add new notification types for block-outs
ALTER TABLE notifications 
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE notifications
  ADD CONSTRAINT notifications_type_check CHECK (type IN (
    'gig_created',
    'gig_updated', 
    'gig_cancelled',
    'gig_confirmed',
    'potential_gig_created',
    'rehearsal_created',
    'rehearsal_updated',
    'rehearsal_cancelled',
    'blockout_created',
    'setlist_updated',
    'availability_request',
    'availability_response',
    'member_joined',
    'member_left',
    'role_changed',
    'band_invitation'
  ));

-- Update existing rows to enable new categories by default
UPDATE notification_preferences
SET 
  notifications_enabled = COALESCE(notifications_enabled, true),
  gigs_enabled = COALESCE(gigs_enabled, true),
  potential_gigs_enabled = COALESCE(potential_gigs_enabled, true),
  rehearsals_enabled = COALESCE(rehearsals_enabled, true),
  blockouts_enabled = COALESCE(blockouts_enabled, true);

-- Create a helper function to check if user should receive notification
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
  
  -- If no preferences found or notifications disabled globally, return false
  IF v_prefs IS NULL OR NOT v_prefs.notifications_enabled THEN
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
