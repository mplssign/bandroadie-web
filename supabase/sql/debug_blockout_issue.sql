-- ============================================================================
-- DEBUG: Check for bad blockout data and notification trigger issues
-- ============================================================================

-- 1. Check the most recent block_out_dates entries
SELECT 
  id,
  band_id,
  user_id,
  start_date,
  end_date,
  created_at
FROM block_out_dates
ORDER BY created_at DESC
LIMIT 5;

-- 2. Check if there are any orphaned notification records
SELECT 
  id,
  band_id,
  recipient_user_id,
  type,
  title,
  body,
  created_at
FROM notifications
WHERE type = 'blockout_created'
ORDER BY created_at DESC
LIMIT 5;

-- 3. Check the current blockout trigger function
SELECT 
  routine_name,
  routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'notify_blockout_created';

-- 4. Check if the trigger exists
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE trigger_name = 'blockout_created_notification';
