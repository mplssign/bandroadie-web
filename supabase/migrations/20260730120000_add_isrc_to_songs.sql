-- Add isrc column to songs table.
-- Nullable TEXT — International Standard Recording Code, intended as a future
-- high-confidence match key for external metadata providers. No CHECK constraint
-- (mirrors musical_key's precedent in 20260630000000_add_musical_key_to_songs.sql) —
-- format not enforced since not every source returns canonical ISRC formatting.
-- Not currently populated by any active code path — see
-- docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md §3/§6.5.
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS isrc TEXT;

COMMENT ON COLUMN public.songs.isrc IS
  'International Standard Recording Code, when known. Nullable — accepted by upsertExternalSong() for forward compatibility but not populated by any active identity-lookup path as of 2026-07.';
