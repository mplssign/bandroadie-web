-- Migration: Add source traceability to block_dates
-- Purpose: Enable lifecycle synchronization of cross-band block-outs with their source events
-- Ticket: bug/one-calendar-lifecycle-sync

-- Add nullable foreign key columns to track which gig or rehearsal created this block-out
ALTER TABLE public.block_dates
  ADD COLUMN source_gig_id UUID REFERENCES public.gigs(id) ON DELETE CASCADE,
  ADD COLUMN source_rehearsal_id UUID REFERENCES public.rehearsals(id) ON DELETE CASCADE;

-- Enforce mutual exclusivity: a block-out can be sourced from a gig OR a rehearsal, never both
-- NULL, NULL = manually created (untouched by event lifecycle sync)
ALTER TABLE public.block_dates
  ADD CONSTRAINT block_dates_single_source CHECK (
    NOT (source_gig_id IS NOT NULL AND source_rehearsal_id IS NOT NULL)
  );

-- Partial indexes for efficient lookup by source (only index non-NULL values)
CREATE INDEX idx_block_dates_source_gig_id
  ON public.block_dates (source_gig_id)
  WHERE source_gig_id IS NOT NULL;

CREATE INDEX idx_block_dates_source_rehearsal_id
  ON public.block_dates (source_rehearsal_id)
  WHERE source_rehearsal_id IS NOT NULL;
