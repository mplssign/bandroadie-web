-- 085_add_load_in_time_to_gigs.sql
-- Add optional Load-in Time field to gigs and potential gigs
--
-- This allows bands to track when they need to arrive for setup
-- before the actual start time of a gig.

-- Add load_in_time column to gigs table (nullable TEXT in HH:MM AM/PM format)
ALTER TABLE gigs
ADD COLUMN load_in_time TEXT;

COMMENT ON COLUMN gigs.load_in_time IS 'Optional load-in/setup time before the gig start time. Format: HH:MM AM/PM (e.g., "6:00 PM")';

-- No need to update existing rows - NULL is the correct default
-- Existing gigs without load-in times will simply show no load-in time
