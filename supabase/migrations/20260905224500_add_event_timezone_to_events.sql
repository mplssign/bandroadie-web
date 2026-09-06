-- Add optional per-event timezone overrides for gigs and rehearsals.
-- Null means use the band's default timezone.

ALTER TABLE public.gigs
ADD COLUMN IF NOT EXISTS event_timezone TEXT;

ALTER TABLE public.rehearsals
ADD COLUMN IF NOT EXISTS event_timezone TEXT;
