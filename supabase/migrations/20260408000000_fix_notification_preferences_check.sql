-- ============================================================================
-- FIX: Respect user notification preferences when creating notifications
-- Created: 2026-04-08
-- Purpose: Modify notify_band_members() to check should_receive_notification()
--          before inserting notification records
-- Bug: bug/event-created-notification-missing
-- ============================================================================

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
SET search_path = public
AS $$
DECLARE
  v_member RECORD;
BEGIN
  FOR v_member IN
    SELECT user_id
      FROM band_members
     WHERE band_id = p_band_id
       AND user_id != COALESCE(p_actor_user_id, '00000000-0000-0000-0000-000000000000'::uuid)
  LOOP
    -- Check if user wants this notification type
    IF should_receive_notification(v_member.user_id, p_notification_type) THEN
      BEGIN
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
          COALESCE(p_title, 'New Activity'),
          COALESCE(p_body, 'Something happened in your band'),
          COALESCE(p_metadata, '{}'::jsonb),
          p_actor_user_id
        );
      EXCEPTION
        WHEN OTHERS THEN
          RAISE WARNING 'notify_band_members: failed for user %: %',
            v_member.user_id, SQLERRM;
      END;
    END IF;
  END LOOP;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'notify_band_members failed entirely: %', SQLERRM;
END;
$$;
