-- ============================================================================
-- Migration: add_venue_id_to_gigs
-- Adds venue_id foreign key to gigs table for linking gigs to venues.
-- ============================================================================

ALTER TABLE public.gigs
  ADD COLUMN venue_id UUID REFERENCES public.venues(id) ON DELETE SET NULL;

CREATE INDEX idx_gigs_venue_id ON public.gigs(venue_id);
