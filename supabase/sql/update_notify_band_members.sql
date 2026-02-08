-- Update the rehearsal notification trigger to call the Edge Function
-- Run this in Supabase SQL Editor

-- First, enable pg_net extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Update the notify_band_members helper to call the Edge Function
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
  v_response_id BIGINT;
BEGIN
  -- Call the send-notification Edge Function via pg_net
  SELECT net.http_post(
    url := 'https://nekwjxvgbveheooyorjo.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := jsonb_build_object(
      'bandId', p_band_id,
      'actorUserId', p_actor_user_id,
      'notificationType', p_notification_type,
      'title', p_title,
      'body', p_body,
      'metadata', p_metadata
    )
  ) INTO v_response_id;
  
  -- Log the request ID (optional)
  RAISE LOG 'Sent notification via Edge Function, request ID: %', v_response_id;
END;
$$;
