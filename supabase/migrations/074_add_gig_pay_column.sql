-- ============================================================================
-- ADD GIG PAY COLUMN TO GIGS TABLE
-- Optional payment amount for gigs, stored as numeric(10,2) for precision.
-- ============================================================================

-- Add the gig_pay column to the gigs table
ALTER TABLE gigs
ADD COLUMN IF NOT EXISTS gig_pay NUMERIC(10, 2) DEFAULT NULL;

-- Add a comment explaining the column
COMMENT ON COLUMN gigs.gig_pay IS 'Payment amount for this gig in dollars (e.g., 150.00). NULL means no pay specified.';
