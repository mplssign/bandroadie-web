-- Query 4: List all columns in rehearsals table
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'rehearsals'
ORDER BY ordinal_position;
