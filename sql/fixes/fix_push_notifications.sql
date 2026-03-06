-- ============================================================================
-- FIX PUSH NOTIFICATIONS - RUN IN SUPABASE SQL EDITOR
-- ============================================================================

-- STEP 1: Fix notify_band_members to INSERT notification records
-- This is the KEY fix - the old version only used pg_notify() which does nothing
CREATE OR REPLACE FUNCTION notify_band_members(
  p_band_id UUID,
  p_actor_user_id UUID,
  p_notification_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_member RECORD;
BEGIN
  -- Insert notification records for all band members (except the actor)
  FOR v_member IN 
    SELECT user_id 
    FROM band_members 
    WHERE band_id = p_band_id 
    AND user_id != p_actor_user_id
  LOOP
    INSERT INTO notifications (
      band_id,
      recipient_user_id,
      type,
      title,
      body,
      metadata,
      actor_user_id
    ) VALUES (
      p_band_id,
      v_member.user_id,
      p_notification_type,
      p_title,
      p_body,
      p_metadata,
      p_actor_user_id
    );
  END LOOP;
END;
$$;

-- STEP 2: Verify the gig trigger exists
-- This should already exist from migrations
SELECT 'TRIGGERS ON GIGS TABLE:' as check_name;
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE event_object_table = 'gigs';

-- STEP 3: Check notifications table has required columns
SELECT 'NOTIFICATIONS TABLE COLUMNS:' as check_name;
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'notifications'
ORDER BY ordinal_position;

-- STEP 4: Verify device_tokens has the user's token
SELECT 'DEVICE TOKENS:' as check_name;
SELECT 
  dt.id,
  u.email,
  dt.platform,
  LEFT(dt.fcm_token, 30) || '...' as token_preview,
  dt.updated_at
FROM device_tokens dt
JOIN users u ON u.id = dt.user_id
ORDER BY dt.updated_at DESC
LIMIT 10;

-- After running this, create a gig again and check if notifications appear:
-- SELECT * FROM notifications ORDER BY created_at DESC LIMIT 5;
