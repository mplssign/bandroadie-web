-- Add optional 2-letter state abbreviation to gigs table.
-- Entered alongside city (the existing `location` field) in the gig editor's
-- City/State row; distinct from venues.state, which only applies when the
-- gig is linked to a saved venue.
ALTER TABLE public.gigs
  ADD COLUMN IF NOT EXISTS state TEXT;
