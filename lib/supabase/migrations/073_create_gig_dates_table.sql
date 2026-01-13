-- ============================================================================
-- Migration 073: Create gig_dates table for multi-date potential gigs
-- 
-- This enables potential gigs to have multiple possible dates, each with 
-- independent availability tracking.
--
-- Design:
-- - gigs.date remains the "primary" date (first date or single date)
-- - gig_dates stores additional dates for multi-date potential gigs
-- - gig_responses gains optional gig_date_id for per-date availability
-- ============================================================================

-- =============================================================================
-- GIG_DATES TABLE
-- Stores additional dates for multi-date potential gigs
-- =============================================================================

CREATE TABLE public.gig_dates (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  gig_id UUID REFERENCES public.gigs(id) ON DELETE CASCADE NOT NULL,
  date DATE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Ensure no duplicate dates per gig
  UNIQUE(gig_id, date)
);

-- Create indexes for common queries
CREATE INDEX idx_gig_dates_gig_id ON public.gig_dates(gig_id);
CREATE INDEX idx_gig_dates_date ON public.gig_dates(date);

-- =============================================================================
-- UPDATE GIG_RESPONSES TABLE
-- Add gig_date_id for per-date availability tracking
-- =============================================================================

-- Add nullable gig_date_id column
-- NULL means the response is for the gig's primary date (backward compatible)
ALTER TABLE public.gig_responses 
ADD COLUMN IF NOT EXISTS gig_date_id UUID REFERENCES public.gig_dates(id) ON DELETE CASCADE;

-- Create index for per-date lookups
CREATE INDEX IF NOT EXISTS idx_gig_responses_gig_date_id ON public.gig_responses(gig_date_id);

-- Update unique constraint to include gig_date_id
-- First, drop the old constraint if it exists
ALTER TABLE public.gig_responses 
DROP CONSTRAINT IF EXISTS gig_responses_gig_id_user_id_key;

-- Create new unique constraint that allows one response per user per gig per date
-- Using a partial unique index to handle NULL gig_date_id properly
CREATE UNIQUE INDEX IF NOT EXISTS gig_responses_unique_user_gig_date 
ON public.gig_responses(gig_id, user_id, COALESCE(gig_date_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- =============================================================================
-- RLS POLICIES FOR GIG_DATES
-- =============================================================================

ALTER TABLE public.gig_dates ENABLE ROW LEVEL SECURITY;

-- SELECT: Band members can view gig dates for gigs in their bands
CREATE POLICY "Band members can view gig dates" ON public.gig_dates
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_dates.gig_id 
      AND bm.user_id = auth.uid()
    )
  );

-- INSERT: Band members can create gig dates for gigs in their bands
CREATE POLICY "Band members can create gig dates" ON public.gig_dates
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_dates.gig_id 
      AND bm.user_id = auth.uid()
    )
  );

-- UPDATE: Band members can update gig dates for gigs in their bands
CREATE POLICY "Band members can update gig dates" ON public.gig_dates
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_dates.gig_id 
      AND bm.user_id = auth.uid()
    )
  );

-- DELETE: Band members can delete gig dates for gigs in their bands
CREATE POLICY "Band members can delete gig dates" ON public.gig_dates
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.gigs g
      JOIN public.band_members bm ON g.band_id = bm.band_id
      WHERE g.id = gig_dates.gig_id 
      AND bm.user_id = auth.uid()
    )
  );
