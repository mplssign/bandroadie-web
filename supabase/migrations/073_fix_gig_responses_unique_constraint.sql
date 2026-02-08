-- Fix unique constraint on gig_responses to support per-date responses
-- 
-- The existing constraint "gig_responses_gig_user_unique" only covers (gig_id, user_id)
-- but for multi-date potential gigs, we need to allow multiple rows per user
-- with different gig_date_id values.
--
-- This migration:
-- 1. Drops the old constraint
-- 2. Creates a new constraint that includes gig_date_id

-- Drop the old constraint
ALTER TABLE gig_responses 
DROP CONSTRAINT IF EXISTS gig_responses_gig_user_unique;

-- Create new constraint that properly handles per-date responses
-- Uses COALESCE to treat NULL gig_date_id as a special value for uniqueness
CREATE UNIQUE INDEX gig_responses_gig_user_date_unique 
ON gig_responses (gig_id, user_id, COALESCE(gig_date_id, '00000000-0000-0000-0000-000000000000'));

-- Add a comment explaining the constraint
COMMENT ON INDEX gig_responses_gig_user_date_unique IS 
'Ensures one response per user per date. NULL gig_date_id represents the primary date.';
