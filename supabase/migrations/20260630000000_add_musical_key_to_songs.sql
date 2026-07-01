-- Add musical_key column to songs table.
-- Nullable TEXT — no CHECK constraint; values validated by client-side picker.
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS musical_key TEXT;

COMMENT ON COLUMN public.songs.musical_key IS
  'Musical key of the song (e.g. "C#", "Ebm"). Nullable free-text validated by client.';
