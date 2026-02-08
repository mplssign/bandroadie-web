-- Simple diagnosis queries - run each one separately if needed

-- Query 1: Check ALL triggers on rehearsals
SELECT 
  trigger_name,
  event_manipulation,
  action_timing
FROM information_schema.triggers
WHERE event_object_table = 'rehearsals'
ORDER BY trigger_name;

-- Query 2: Get notify_rehearsal_created function
SELECT pg_get_functiondef('notify_rehearsal_created'::regproc);

-- Query 3: Get notify_band_members function
SELECT pg_get_functiondef('notify_band_members'::regproc);

-- Query 4: Verify rehearsals schema (confirm no name column)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'rehearsals'
ORDER BY ordinal_position;

-- Query 5: Search for functions that reference "name" with rehearsals
SELECT 
  p.proname as function_name
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE pg_get_functiondef(p.oid) ILIKE '%rehearsals%'
  AND pg_get_functiondef(p.oid) ILIKE '%name%'
  AND n.nspname = 'public';
