-- Migration: Add recurrence fields to rehearsals table
-- This enables recurring rehearsals to persist their recurrence settings
-- and allows linking recurring instances together.

-- Add recurrence columns to rehearsals table
ALTER TABLE public.rehearsals
ADD COLUMN IF NOT EXISTS is_recurring BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS recurrence_frequency TEXT,  -- 'weekly', 'biweekly', 'monthly'
ADD COLUMN IF NOT EXISTS recurrence_days INTEGER[],  -- Array of day indices [0=Sun, 1=Mon, ..., 6=Sat]
ADD COLUMN IF NOT EXISTS recurrence_until DATE,
ADD COLUMN IF NOT EXISTS parent_rehearsal_id UUID REFERENCES public.rehearsals(id) ON DELETE SET NULL;

-- Index for efficient lookup of recurring series
CREATE INDEX IF NOT EXISTS idx_rehearsals_parent_id ON public.rehearsals(parent_rehearsal_id);
CREATE INDEX IF NOT EXISTS idx_rehearsals_is_recurring ON public.rehearsals(is_recurring);

-- Comment for documentation
COMMENT ON COLUMN public.rehearsals.is_recurring IS 'Whether this rehearsal is part of a recurring series';
COMMENT ON COLUMN public.rehearsals.recurrence_frequency IS 'Recurrence frequency: weekly, biweekly, monthly';
COMMENT ON COLUMN public.rehearsals.recurrence_days IS 'Days of week for recurrence [0=Sun, ..., 6=Sat]';
COMMENT ON COLUMN public.rehearsals.recurrence_until IS 'End date for recurring series';
COMMENT ON COLUMN public.rehearsals.parent_rehearsal_id IS 'Links child instances to the first rehearsal in a series';
