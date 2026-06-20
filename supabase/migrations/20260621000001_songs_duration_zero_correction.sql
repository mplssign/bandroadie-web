-- Migration: Correct product error in songs.duration_seconds default value
-- Previous migration (20260621000000) backfilled 915 songs with 180-second default
-- Correct behavior: songs with no duration should have duration_seconds = 0 and display as 0:00
-- This migration resets all 180-second values to 0 and changes default from 180 to 0

-- Step 1: Reset all songs with duration_seconds = 180 to 0
-- This includes the 915 backfilled rows plus any songs created after the previous migration
UPDATE songs
SET duration_seconds = 0
WHERE duration_seconds = 180;

-- Step 2: Change the column default from 180 to 0
ALTER TABLE songs
ALTER COLUMN duration_seconds SET DEFAULT 0;

-- Step 3: NOT NULL constraint already in place from previous migration (no change needed)

-- Verification: Confirm no songs have duration_seconds = 180
DO $$
DECLARE
  songs_with_180 INTEGER;
  total_zero INTEGER;
BEGIN
  SELECT COUNT(*) INTO songs_with_180
  FROM songs
  WHERE duration_seconds = 180;
  
  IF songs_with_180 > 0 THEN
    RAISE EXCEPTION 'Migration failed: % songs still have duration_seconds = 180', songs_with_180;
  END IF;
  
  SELECT COUNT(*) INTO total_zero
  FROM songs
  WHERE duration_seconds = 0;
  
  RAISE NOTICE 'Migration successful: % songs reset to 0 seconds, default changed to 0', total_zero;
END $$;
