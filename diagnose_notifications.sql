-- ============================================================================
-- NOTIFICATION SYSTEM DIAGNOSTIC
-- Run this in Supabase SQL Editor to diagnose notification issues
-- ============================================================================

-- 1. Check if triggers exist on gigs table
SELECT 'TRIGGERS ON GIGS TABLE:' as section;
SELECT 
  trigger_name,
  event_manipulation,
  action_timing
FROM information_schema.triggers
WHERE event_object_table = 'gigs'
ORDER BY trigger_name;

-- 2. Check the notify_gig_created function
SELECT 'NOTIFY_GIG_CREATED FUNCTION:' as section;
SELECT pg_get_functiondef('notify_gig_created'::regproc);

-- 3. Check the notify_band_members function (this is key!)
SELECT 'NOTIFY_BAND_MEMBERS FUNCTION:' as section;
SELECT pg_get_functiondef('notify_band_members'::regproc);

-- 4. Check if pg_net extension is enabled (required for HTTP calls)
SELECT 'PG_NET EXTENSION:' as section;
SELECT extname, extversion 
FROM pg_extension 
WHERE extname = 'pg_net';

-- 5. Check recent notifications in the database
SELECT 'RECENT NOTIFICATIONS (last 10):' as section;
SELECT 
  id,
  type,
  title,
  body,
  created_at,
  recipient_user_id
FROM notifications
ORDER BY created_at DESC
LIMIT 10;

-- 6. Check if your device token is registered
SELECT 'YOUR DEVICE TOKENS:' as section;
SELECT 
  id,
  user_id,
  platform,
  LEFT(fcm_token, 20) || '...' as token_preview,
  last_seen
FROM device_tokens
WHERE user_id = auth.uid()
ORDER BY last_seen DESC;

-- 7. Check your notification preferences
SELECT 'YOUR NOTIFICATION PREFERENCES:' as section;
SELECT *
FROM notification_preferences
WHERE user_id = auth.uid();

-- 8. Check band members for your active band (to verify you're not the only member)
SELECT 'BAND MEMBERS (you need other members to receive notifications):' as section;
SELECT 
  bm.user_id,
  COALESCE(u.first_name || ' ' || u.last_name, u.email) as member_name,
  u.email,
  CASE WHEN bm.user_id = auth.uid() THEN 'YOU' ELSE 'OTHER' END as is_you
FROM band_members bm
JOIN users u ON u.id = bm.user_id
WHERE bm.band_id IN (
  SELECT band_id FROM band_members WHERE user_id = auth.uid()
)
ORDER BY is_you DESC;

-- 9. Check if there are any recent gigs that should have triggered notifications
SELECT 'RECENT GIGS (last 5):' as section;
SELECT 
  id,
  name,
  date,
  is_potential,
  created_at,
  band_id
FROM gigs
ORDER BY created_at DESC
LIMIT 5;
