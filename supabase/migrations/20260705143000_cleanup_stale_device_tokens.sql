-- Migration: Cleanup stale device tokens on registration
-- When a device's FCM token refreshes, delete the old token to prevent duplicate pushes

-- Drop old RPC
DROP FUNCTION IF EXISTS upsert_device_token(TEXT, TEXT, TEXT);

-- Recreate with optional p_old_token parameter
CREATE OR REPLACE FUNCTION upsert_device_token(
  p_fcm_token TEXT,
  p_platform TEXT,
  p_device_name TEXT DEFAULT NULL,
  p_old_token TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token_id UUID;
BEGIN
  -- If old token provided, delete it (device-scoped cleanup for token refresh)
  IF p_old_token IS NOT NULL THEN
    DELETE FROM device_tokens
     WHERE user_id = auth.uid()
       AND fcm_token = p_old_token;
  END IF;

  -- Upsert the new token
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
