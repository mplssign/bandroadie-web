-- ============================================================================
-- SECURE PUSH NOTIFICATION TRIGGER
-- Created: 2026-02-20
-- Purpose: Fire-and-forget HTTP call to the send-push Edge Function whenever
--          a notification row is inserted. No privileged keys leave SQL.
--
-- SECURITY MODEL:
--   • The trigger sends ONLY the notification payload + a non-privileged
--     shared secret (push_trigger_secret) in the X-Internal-Secret header.
--   • NO service_role key, Authorization header, or Supabase key is ever
--     sent from SQL.
--   • The Edge Function independently reads SUPABASE_SERVICE_ROLE_KEY from
--     Deno.env to create its Supabase client.
--   • The Edge Function has verify_jwt = false (config.toml) so Supabase
--     does not reject the request for lacking a JWT.
--
-- PREREQUISITES:
--   1. pg_net extension enabled
--   2. Supabase Vault extension enabled
--   3. notifications table must exist. If it doesn't, run this FIRST:
--
--      PREREQUISITE SQL (paste in SQL Editor before this migration):
--      ─────────────────────────────────────────────────────────────
--      CREATE TABLE notifications (
--        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--        band_id UUID REFERENCES bands(id) ON DELETE CASCADE,
--        recipient_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
--        type TEXT NOT NULL,
--        title TEXT NOT NULL,
--        body TEXT NOT NULL,
--        metadata JSONB DEFAULT '{}',
--        read_at TIMESTAMPTZ,
--        created_at TIMESTAMPTZ DEFAULT now(),
--        actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL
--      );
--      CREATE INDEX idx_notifications_recipient ON notifications(recipient_user_id);
--      CREATE INDEX idx_notifications_band ON notifications(band_id);
--      CREATE INDEX idx_notifications_created_at ON notifications(created_at DESC);
--      CREATE INDEX idx_notifications_unread ON notifications(recipient_user_id, read_at)
--        WHERE read_at IS NULL;
--      ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
--      CREATE POLICY "Users can view own notifications" ON notifications
--        FOR SELECT USING (auth.uid() = recipient_user_id);
--      CREATE POLICY "Users can update own notifications" ON notifications
--        FOR UPDATE USING (auth.uid() = recipient_user_id);
--      ─────────────────────────────────────────────────────────────
--
--   4. After running this migration, store TWO secrets in Vault:
--
--      -- a) A random shared secret (NOT the service role key):
--      SELECT vault.create_secret(
--        'generate-a-random-string-here',   -- e.g. openssl rand -hex 32
--        'push_trigger_secret',
--        'Shared secret for SQL→Edge Function push trigger auth'
--      );
--
--      -- b) The project URL:
--      SELECT vault.create_secret(
--        'https://nekwjxvgbveheooyorjo.supabase.co',
--        'supabase_url',
--        'Supabase project URL for Edge Function calls'
--      );
--
--   5. Store the SAME shared secret as a Supabase Edge Function secret:
--      Dashboard → Edge Functions → Secrets → add PUSH_TRIGGER_SECRET
--      (must match the value stored in Vault above)
--
--   6. Delete the old Dashboard webhook "send_push_on_notification"
--      (Database → Webhooks → delete it)
--
-- ARCHITECTURE:
--   INSERT into notifications
--       → AFTER INSERT trigger fires
--       → trigger_send_push_notification() reads push_trigger_secret from Vault
--       → pg_net.http_post calls send-push with X-Internal-Secret header
--       → Edge Function validates X-Internal-Secret against its env var
--       → Edge Function uses Deno.env SUPABASE_SERVICE_ROLE_KEY for DB access
--       → Trigger never blocks the INSERT (fire-and-forget + exception handler)
-- ============================================================================

-- 1. Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault;

-- 2. Pre-flight: verify notifications table exists
--    (Created by 20260109_notifications.sql — run that first if this fails)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = 'notifications'
  ) THEN
    RAISE EXCEPTION 'notifications table does not exist. Run the prerequisite migration first (see PREREQUISITE SQL in header comments).';
  END IF;
END $$;

-- 3. Drop old trigger if it exists
DROP TRIGGER IF EXISTS on_notification_inserted ON notifications;

-- 4. Create the trigger function
--    SECURITY DEFINER so it can read vault.decrypted_secrets.
--    SET search_path to prevent search-path injection.
CREATE OR REPLACE FUNCTION trigger_send_push_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_internal_secret TEXT;
  v_supabase_url    TEXT;
BEGIN
  -- Read the shared secret from Vault (NOT the service role key)
  SELECT decrypted_secret INTO v_internal_secret
    FROM vault.decrypted_secrets
   WHERE name = 'push_trigger_secret'
   LIMIT 1;

  -- Read the project URL from Vault
  SELECT decrypted_secret INTO v_supabase_url
    FROM vault.decrypted_secrets
   WHERE name = 'supabase_url'
   LIMIT 1;

  -- Guard: skip push if secrets are not configured yet
  IF v_internal_secret IS NULL OR v_supabase_url IS NULL THEN
    RAISE WARNING 'Push notification skipped: Vault secrets not configured (push_trigger_secret or supabase_url)';
    RETURN NEW;
  END IF;

  -- Fire-and-forget HTTP POST via pg_net (runs async after tx commits)
  -- Only sends notification data + X-Internal-Secret. No Authorization header.
  PERFORM net.http_post(
    url     := v_supabase_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',      'application/json',
      'X-Internal-Secret', v_internal_secret
    ),
    body    := jsonb_build_object(
      'type',   TG_OP,
      'table',  TG_TABLE_NAME,
      'record', jsonb_build_object(
        'id',                NEW.id,
        'recipient_user_id', NEW.recipient_user_id,
        'band_id',           NEW.band_id,
        'type',              NEW.type,
        'title',             NEW.title,
        'body',              NEW.body,
        'metadata',          COALESCE(NEW.metadata, '{}'::jsonb)
      )
    )
  );

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    -- Never block the notification INSERT — log warning and continue
    RAISE WARNING 'trigger_send_push_notification failed: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- 5. Attach the trigger (AFTER INSERT so the row is visible to the Edge Function)
CREATE TRIGGER on_notification_inserted
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION trigger_send_push_notification();

-- 6. Ensure notify_band_members only inserts rows (no direct HTTP calls).
--    Push delivery is handled by the trigger above.
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

-- ============================================================================
-- POST-MIGRATION STEPS (run manually in SQL Editor):
--
-- 1. Generate a random shared secret:
--      openssl rand -hex 32
--
-- 2. Store it in Vault:
--      SELECT vault.create_secret(
--        '<random-hex-string>',
--        'push_trigger_secret',
--        'Shared secret for SQL→Edge Function push trigger auth'
--      );
--
-- 3. Store project URL in Vault:
--      SELECT vault.create_secret(
--        'https://nekwjxvgbveheooyorjo.supabase.co',
--        'supabase_url',
--        'Supabase project URL for Edge Function calls'
--      );
--
-- 4. Add the SAME secret as an Edge Function secret:
--      Dashboard → Edge Functions → Secrets → PUSH_TRIGGER_SECRET
--
-- 5. Delete the old Dashboard webhook:
--      Dashboard → Database → Webhooks → delete "send_push_on_notification"
--
-- 6. Deploy the updated send-push Edge Function:
--      supabase functions deploy send-push --project-ref nekwjxvgbveheooyorjo
--
-- 7. Test:
--      INSERT INTO notifications (band_id, recipient_user_id, type, title, body)
--      VALUES ('<band_id>', '<user_id>', 'gig_created', 'Test', 'Test push');
--      -- Then check: supabase functions logs send-push
-- ============================================================================
