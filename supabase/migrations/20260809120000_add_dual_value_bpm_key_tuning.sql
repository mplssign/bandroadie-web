-- Add dual-value storage for BPM, musical key, and tuning.
-- Phase 2.2 of Song Data Enrichment initiative.
--
-- "source" = original recording metadata (from enrichment or manual entry)
-- "performance" = band's performance choice (user-controlled, never touched by enrichment)
--
-- Existing single-value columns (bpm, musical_key, tuning) are migrated to source_* columns.
-- Performance columns default to NULL (no override set yet).

-- 1. Add new columns
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS source_bpm INTEGER;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS performance_bpm INTEGER;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS source_musical_key TEXT;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS performance_musical_key TEXT;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS source_tuning TEXT;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS performance_tuning TEXT;

COMMENT ON COLUMN public.songs.source_bpm IS
  'BPM of the original recording. Populated by enrichment or manual entry. Editable.';
COMMENT ON COLUMN public.songs.performance_bpm IS
  'BPM this band plays (performance override). User-controlled. NULL = no override, use source.';
COMMENT ON COLUMN public.songs.source_musical_key IS
  'Musical key of the original recording. Populated by enrichment or manual entry. Editable.';
COMMENT ON COLUMN public.songs.performance_musical_key IS
  'Musical key this band plays (performance override). User-controlled. NULL = no override, use source.';
COMMENT ON COLUMN public.songs.source_tuning IS
  'Tuning of the original recording. Populated by enrichment or manual entry. Editable.';
COMMENT ON COLUMN public.songs.performance_tuning IS
  'Tuning this band plays (performance override). User-controlled. NULL = no override, use source.';

-- 2. Migrate existing data: single-value columns → source columns
--    Performance columns stay NULL (no override was possible before this migration)
UPDATE public.songs
SET
  source_bpm = bpm,
  source_musical_key = musical_key,
  source_tuning = tuning
WHERE
  source_bpm IS NULL
  OR source_musical_key IS NULL
  OR source_tuning IS NULL;

-- 3. Old columns are kept for now (backward compatibility during rollout)
--    They are NOT dropped in this migration — that's a follow-up decision
--    after confirming all code paths use the new dual-value columns.
--
--    Deprecation note: As of Phase 2.2, `bpm`, `musical_key`, `tuning` columns
--    are considered deprecated. New code should use `source_*` / `performance_*`.

-- No RLS changes needed — new columns inherit existing RLS policies on songs table.
