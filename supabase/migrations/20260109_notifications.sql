-- ============================================================================
-- NOTIFICATION SYSTEM SCHEMA
-- Created: 2026-01-09
-- Purpose: Push notifications, in-app activity feed, and user preferences
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. DEVICE TOKENS TABLE
-- Stores FCM tokens for push notification delivery
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web', 'macos')),
  device_name TEXT, -- Optional: "iPhone 15 Pro", "Chrome on macOS"
  last_seen TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  
  -- Ensure one token per device per user (token is unique per device)
  UNIQUE(fcm_token)
);

-- Index for efficient lookups when sending notifications to a user
CREATE INDEX idx_device_tokens_user_id ON device_tokens(user_id);

-- Enable RLS
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

-- Users can only manage their own tokens
CREATE POLICY "Users can view own device tokens"
  ON device_tokens FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own device tokens"
  ON device_tokens FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own device tokens"
  ON device_tokens FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own device tokens"
  ON device_tokens FOR DELETE
  USING (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- 2. NOTIFICATIONS TABLE
-- Stores all notifications (source of truth for activity feed)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id UUID REFERENCES bands(id) ON DELETE CASCADE,
  recipient_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Notification content
  type TEXT NOT NULL CHECK (type IN (
    'gig_created',
    'gig_updated', 
    'gig_cancelled',
    'gig_confirmed',
    'rehearsal_created',
    'rehearsal_updated',
    'rehearsal_cancelled',
    'setlist_updated',
    'availability_request',
    'availability_response',
    'member_joined',
    'member_left',
    'role_changed',
    'band_invitation'
  )),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  
  -- Optional metadata for deep linking
  metadata JSONB DEFAULT '{}',
  -- Example metadata:
  -- { "gig_id": "uuid", "rehearsal_id": "uuid", "setlist_id": "uuid" }
  
  -- Tracking
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  
  -- Who triggered this notification (NULL for system notifications)
  actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Indexes for efficient queries
CREATE INDEX idx_notifications_recipient ON notifications(recipient_user_id);
CREATE INDEX idx_notifications_band ON notifications(band_id);
CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);
CREATE INDEX idx_notifications_unread ON notifications(recipient_user_id, read_at) 
  WHERE read_at IS NULL;

-- Enable RLS
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Users can only see their own notifications
CREATE POLICY "Users can view own notifications"
  ON notifications FOR SELECT
  USING (auth.uid() = recipient_user_id);

-- Users can mark their own notifications as read
CREATE POLICY "Users can update own notifications"
  ON notifications FOR UPDATE
  USING (auth.uid() = recipient_user_id);

-- Only backend/service role can insert notifications
-- (No INSERT policy for regular users - notifications created server-side)

-- ----------------------------------------------------------------------------
-- 3. NOTIFICATION PREFERENCES TABLE
-- Per-user preferences for notification types
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Category toggles (default TRUE = enabled)
  gig_updates BOOLEAN DEFAULT true,
  rehearsal_updates BOOLEAN DEFAULT true,
  setlist_updates BOOLEAN DEFAULT true,
  availability_requests BOOLEAN DEFAULT true,
  member_updates BOOLEAN DEFAULT true,
  
  -- Delivery method toggles
  push_enabled BOOLEAN DEFAULT true,
  in_app_enabled BOOLEAN DEFAULT true,
  
  -- Quiet hours (optional)
  quiet_hours_start TIME, -- e.g., '22:00'
  quiet_hours_end TIME,   -- e.g., '08:00'
  timezone TEXT DEFAULT 'America/New_York',
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

-- Users can only manage their own preferences
CREATE POLICY "Users can view own notification preferences"
  ON notification_preferences FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own notification preferences"
  ON notification_preferences FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own notification preferences"
  ON notification_preferences FOR UPDATE
  USING (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- 4. HELPER FUNCTIONS
-- ----------------------------------------------------------------------------

-- Function to upsert device token (called from Flutter app)
CREATE OR REPLACE FUNCTION upsert_device_token(
  p_fcm_token TEXT,
  p_platform TEXT,
  p_device_name TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token_id UUID;
BEGIN
  INSERT INTO device_tokens (user_id, fcm_token, platform, device_name, last_seen)
  VALUES (auth.uid(), p_fcm_token, p_platform, p_device_name, now())
  ON CONFLICT (fcm_token) 
  DO UPDATE SET 
    user_id = auth.uid(),
    platform = p_platform,
    device_name = COALESCE(p_device_name, device_tokens.device_name),
    last_seen = now()
  RETURNING id INTO v_token_id;
  
  RETURN v_token_id;
END;
$$;

-- Function to get or create notification preferences
CREATE OR REPLACE FUNCTION get_or_create_notification_preferences()
RETURNS notification_preferences
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_prefs notification_preferences;
BEGIN
  -- Try to get existing preferences
  SELECT * INTO v_prefs
  FROM notification_preferences
  WHERE user_id = auth.uid();
  
  -- If not found, create default preferences
  IF v_prefs IS NULL THEN
    INSERT INTO notification_preferences (user_id)
    VALUES (auth.uid())
    RETURNING * INTO v_prefs;
  END IF;
  
  RETURN v_prefs;
END;
$$;

-- Function to mark all notifications as read
CREATE OR REPLACE FUNCTION mark_all_notifications_read()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE notifications
  SET read_at = now()
  WHERE recipient_user_id = auth.uid()
    AND read_at IS NULL;
  
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Function to get unread notification count
CREATE OR REPLACE FUNCTION get_unread_notification_count()
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COUNT(*)::INTEGER
  FROM notifications
  WHERE recipient_user_id = auth.uid()
    AND read_at IS NULL;
$$;

-- ----------------------------------------------------------------------------
-- 5. TRIGGER FOR UPDATED_AT
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_notification_preferences_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER notification_preferences_updated_at
  BEFORE UPDATE ON notification_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_notification_preferences_updated_at();
