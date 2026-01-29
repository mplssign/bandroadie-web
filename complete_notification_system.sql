-- Complete the notification system: in-app + push notifications
-- Run this in Supabase SQL Editor

-- Enable pg_net for HTTP calls to Edge Function
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Update notify_band_members to:
-- 1. Insert notification records (in-app feed)
-- 2. Call Edge Function (push notifications)
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
  -- 1. Insert notification records for all band members (except actor)
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

  -- 2. Call Edge Function for push notifications (async, fire-and-forget)
  PERFORM net.http_post(
    url := 'https://nekwjxvgbveheooyorjo.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('request.headers', true)::json->>'authorization'
    ),
    body := jsonb_build_object(
      'bandId', p_band_id,
      'actorUserId', p_actor_user_id,
      'notificationType', p_notification_type,
      'title', p_title,
      'body', p_body,
      'metadata', p_metadata
    )
  );
END;
$$;
