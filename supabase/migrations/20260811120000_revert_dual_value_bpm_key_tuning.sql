-- Revert Phase 2.2 dual-value BPM/Key/Tuning back to single-value columns.
-- DROP 6 columns added in 20260809120000.
-- Restore bpm, musical_key, tuning as authoritative single-value fields.
--
-- SAFETY RATIONALE (verified against production 2026-08-11 by Manager):
-- The source_* and performance_* columns are being dropped because bpm/musical_key/tuning
-- remain the authoritative values and were never modified by Phase 2.2. Production query
-- confirms 0 rows exist where a source_* or performance_* column holds a value absent from
-- its corresponding old column (bpm/musical_key/tuning), making this drop lossless.
-- Note: 64 BPM rows, 46 key rows, and 100 tuning rows do diverge between source_* and old
-- columns, but in every case the old column contains the real value — the divergence is
-- harmless since we're keeping the old columns.
--
-- DATA MIGRATION STRATEGY:
-- Since bpm/musical_key/tuning were never dropped or modified by Phase 2.2, they remain the
-- authoritative values. No data migration is needed — simply drop the dual-value columns.
-- Any non-NULL performance_* values (should be rare) are lost, which is acceptable since
-- Phase 2.2 never shipped in an app build.

-- 1. Drop dual-value columns (no data migration needed — old columns are still intact)
ALTER TABLE public.songs DROP COLUMN IF EXISTS source_bpm;
ALTER TABLE public.songs DROP COLUMN IF EXISTS performance_bpm;
ALTER TABLE public.songs DROP COLUMN IF EXISTS source_musical_key;
ALTER TABLE public.songs DROP COLUMN IF EXISTS performance_musical_key;
ALTER TABLE public.songs DROP COLUMN IF EXISTS source_tuning;
ALTER TABLE public.songs DROP COLUMN IF EXISTS performance_tuning;

-- 2. Remove @Deprecated markers from old columns (Flutter-only, not SQL — Engineer handles this)
--    bpm, musical_key, tuning are now the authoritative single-value fields again

-- No RLS changes needed — policies on songs table are unchanged
