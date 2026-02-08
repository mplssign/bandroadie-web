-- Simple check - run each query one at a time
-- These won't error if things don't exist

-- 1. Check if gig trigger exists
SELECT trigger_name
FROM information_schema.triggers
WHERE event_object_table = 'gigs';

-- If empty, no triggers are installed
