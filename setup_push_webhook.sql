-- ============================================================================
-- PUSH NOTIFICATION WEBHOOK SETUP
-- Run this in Supabase SQL Editor to enable push notifications
-- ============================================================================

-- This creates a database webhook that calls the send-push Edge Function
-- whenever a new notification is inserted into the notifications table.
--
-- IMPORTANT: You must also configure this in Supabase Dashboard:
-- 1. Go to Database → Webhooks
-- 2. Create a new webhook:
--    - Name: send_push_notification
--    - Table: notifications
--    - Events: INSERT
--    - Type: Supabase Edge Function
--    - Function: send-push
--    - HTTP Headers: (none needed, uses service role automatically)

-- Alternative: Use pg_net to call the Edge Function directly from the trigger
-- This requires the pg_net extension to be enabled

-- Enable pg_net extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Create a function that calls the Edge Function via HTTP
CREATE OR REPLACE FUNCTION trigger_send_push_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_supabase_url TEXT;
  v_service_key TEXT;
BEGIN
  -- Get Supabase URL from environment (set in Supabase dashboard)
  v_supabase_url := current_setting('app.settings.supabase_url', true);
  v_service_key := current_setting('app.settings.service_role_key', true);
  
  -- Only proceed if we have the required settings
  IF v_supabase_url IS NOT NULL AND v_service_key IS NOT NULL THEN
    -- Call the send-push Edge Function asynchronously
    PERFORM net.http_post(
      url := v_supabase_url || '/functions/v1/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service_key
      ),
      body := jsonb_build_object(
        'type', 'INSERT',
        'table', 'notifications',
        'record', jsonb_build_object(
          'id', NEW.id,
          'recipient_user_id', NEW.recipient_user_id,
          'band_id', NEW.band_id,
          'type', NEW.type,
          'title', NEW.title,
          'body', NEW.body,
          'metadata', NEW.metadata
        )
      )
    );
  END IF;
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Silent failure - never block the insert
    RAISE WARNING 'Failed to trigger push notification: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- Create trigger on notifications table
DROP TRIGGER IF EXISTS on_notification_inserted ON notifications;
CREATE TRIGGER on_notification_inserted
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION trigger_send_push_notification();

-- ============================================================================
-- CONFIGURE DATABASE SETTINGS
-- Run this to set the required config (replace with your actual values):
-- ============================================================================
-- ALTER DATABASE postgres SET app.settings.supabase_url TO 'https://nekwjxvgbveheooyorjo.supabase.co';
-- ALTER DATABASE postgres SET app.settings.service_role_key TO 'your-service-role-key-here';
--
-- NOTE: The service role key is sensitive! Only set it if you trust this approach.
-- The recommended approach is to use Supabase Database Webhooks instead.
