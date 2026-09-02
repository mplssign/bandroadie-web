-- Add per-field manual-override flags to songs.
-- FALSE (default): field may be overwritten by enrichment.
-- TRUE: user explicitly set this field; enrichment must not overwrite it.

ALTER TABLE public.songs
  ADD COLUMN IF NOT EXISTS bpm_manual_override BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS musical_key_manual_override BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.songs.bpm_manual_override IS
  'TRUE when user has manually set BPM. Enrichment will not overwrite while this flag is set. Cleared when user explicitly clears BPM.';
COMMENT ON COLUMN public.songs.musical_key_manual_override IS
  'TRUE when user has manually set musical key. Enrichment will not overwrite while this flag is set. Cleared when user explicitly clears the key.';
