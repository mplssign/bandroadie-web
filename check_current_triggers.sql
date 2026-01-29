-- Check current state of triggers and functions
-- Run this in Supabase SQL Editor to see what's actually deployed

-- 1. Check if the rehearsal trigger exists
SELECT 
  trigger_name,
  event_manipulation,
  action_statement
FROM information_schema.triggers
WHERE trigger_name = 'rehearsal_created_notification';

-- 2. Get the actual function definition
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'notify_rehearsal_created';

-- 3. Get notify_band_members function
SELECT pg_get_functiondef('notify_band_members'::regproc);
