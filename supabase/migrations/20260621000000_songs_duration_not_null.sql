-- Migration: Make songs.duration_seconds NOT NULL with default value
-- Addresses bug where 915 songs have NULL duration causing "0h 00m" display
-- Sets 180 seconds (3 minutes) as default for songs with NULL duration

-- Step 1: Set default value for the column
ALTER TABLE songs
ALTER COLUMN duration_seconds SET DEFAULT 180;

-- Step 2: Backfill NULL values with default (180 seconds = 3 minutes)
UPDATE songs
SET duration_seconds = 180
WHERE duration_seconds IS NULL;

-- Step 3: Add NOT NULL constraint
ALTER TABLE songs
ALTER COLUMN duration_seconds SET NOT NULL;

-- Verification: Confirm no NULL values remain
DO $$
DECLARE
  null_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO null_count
  FROM songs
  WHERE duration_seconds IS NULL;
  
  IF null_count > 0 THEN
    RAISE EXCEPTION 'Migration failed: % songs still have NULL duration_seconds', null_count;
  END IF;
  
  RAISE NOTICE 'Migration successful: All songs now have non-NULL duration_seconds';
END $$;
