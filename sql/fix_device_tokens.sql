-- Fix device_tokens constraints
-- The fcm_token should be unique PER DEVICE, meaning when a different user
-- logs in on the same device, we should UPDATE the user_id, not fail.
-- So we need UNIQUE on fcm_token only, and the upsert should work correctly.

-- First, drop any conflicting constraints
ALTER TABLE device_tokens DROP CONSTRAINT IF EXISTS device_tokens_user_id_fcm_token_key;

-- The ON CONFLICT (fcm_token) in our upsert function will handle updates
-- when the same device (fcm_token) is used by a different user
