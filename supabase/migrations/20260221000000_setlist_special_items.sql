-- ============================================================================
-- MIGRATION: Setlist Special Items (Set Breaks & Pauses)
-- ============================================================================
-- Adds support for structured break/pause items in setlists.
-- These are NOT songs and NOT stored in the catalog.
-- ============================================================================

-- 1. Create the special_item_type enum
DO $$ BEGIN
  CREATE TYPE public.special_item_type AS ENUM ('set_break', 'pause');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- 2. Create the setlist_special_items table (reusable templates)
CREATE TABLE IF NOT EXISTS public.setlist_special_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  type public.special_item_type NOT NULL,
  duration_minutes INT,            -- for set_break
  duration_seconds INT,            -- for pause
  purposes TEXT[],                 -- e.g. {'guitar_change', 'tuning'}
  custom_purposes TEXT[],          -- user-defined purposes
  is_saved_template BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. Add item_type and special_item_id columns to setlist_songs
-- item_type discriminates between 'song', 'set_break', 'pause'
ALTER TABLE public.setlist_songs
  ADD COLUMN IF NOT EXISTS item_type TEXT NOT NULL DEFAULT 'song';

ALTER TABLE public.setlist_songs
  ADD COLUMN IF NOT EXISTS special_item_id UUID REFERENCES public.setlist_special_items(id) ON DELETE CASCADE;

-- 4. Make song_id nullable (special items don't have a song)
ALTER TABLE public.setlist_songs
  ALTER COLUMN song_id DROP NOT NULL;

-- 5. Enable RLS on setlist_special_items
ALTER TABLE public.setlist_special_items ENABLE ROW LEVEL SECURITY;

-- 6. RLS policies for setlist_special_items
-- Members of the band can read
CREATE POLICY "Band members can read special items"
  ON public.setlist_special_items
  FOR SELECT
  USING (
    band_id IN (
      SELECT bm.band_id FROM public.band_members bm
      WHERE bm.user_id = auth.uid()
    )
  );

-- Members of the band can insert
CREATE POLICY "Band members can insert special items"
  ON public.setlist_special_items
  FOR INSERT
  WITH CHECK (
    band_id IN (
      SELECT bm.band_id FROM public.band_members bm
      WHERE bm.user_id = auth.uid()
    )
  );

-- Members of the band can update
CREATE POLICY "Band members can update special items"
  ON public.setlist_special_items
  FOR UPDATE
  USING (
    band_id IN (
      SELECT bm.band_id FROM public.band_members bm
      WHERE bm.user_id = auth.uid()
    )
  );

-- Members of the band can delete
CREATE POLICY "Band members can delete special items"
  ON public.setlist_special_items
  FOR DELETE
  USING (
    band_id IN (
      SELECT bm.band_id FROM public.band_members bm
      WHERE bm.user_id = auth.uid()
    )
  );

-- 7. Index for fast lookup by band
CREATE INDEX IF NOT EXISTS idx_special_items_band_id
  ON public.setlist_special_items(band_id);

-- 8. Index for fast lookup of special items in setlist_songs
CREATE INDEX IF NOT EXISTS idx_setlist_songs_special_item_id
  ON public.setlist_songs(special_item_id)
  WHERE special_item_id IS NOT NULL;

-- 9. Index for item_type filtering on setlist_songs
CREATE INDEX IF NOT EXISTS idx_setlist_songs_item_type
  ON public.setlist_songs(item_type);
