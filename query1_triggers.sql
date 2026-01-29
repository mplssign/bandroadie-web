-- Query 1: Check triggers on rehearsals table
SELECT trigger_name
FROM information_schema.triggers
WHERE event_object_table = 'rehearsals';
