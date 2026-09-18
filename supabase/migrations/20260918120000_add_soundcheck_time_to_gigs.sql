-- 20260918120000_add_soundcheck_time_to_gigs.sql
-- Add optional Soundcheck Time field to gigs
--
-- This allows bands to track when soundcheck happens ahead of the
-- actual start time of a gig, mirroring load_in_time.

-- Add soundcheck_time column to gigs table (nullable TEXT in HH:MM AM/PM format)
ALTER TABLE gigs
ADD COLUMN soundcheck_time TEXT;

COMMENT ON COLUMN gigs.soundcheck_time IS 'Optional soundcheck time before the gig start time. Format: HH:MM AM/PM (e.g., "6:00 PM")';

-- No need to update existing rows - NULL is the correct default
-- Existing gigs without soundcheck times will simply show no soundcheck time
