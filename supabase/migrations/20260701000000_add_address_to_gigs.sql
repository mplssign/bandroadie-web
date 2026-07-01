-- Add optional street address to gigs table.
ALTER TABLE public.gigs
  ADD COLUMN IF NOT EXISTS address TEXT;
