-- Check if notification records were created
SELECT 
  id,
  type,
  title,
  body,
  created_at,
  is_read
FROM notifications
ORDER BY created_at DESC
LIMIT 5;
