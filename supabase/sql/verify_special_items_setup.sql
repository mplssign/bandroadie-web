-- ============================================================================
-- VERIFY & FIX: Special Items (Set Breaks & Pauses) Setup
-- 
-- Run this in the Supabase SQL Editor to check and fix any missing pieces.
-- Safe to run multiple times (idempotent).
-- ============================================================================

-- 1. Create the enum type if it doesn't exist
DO $$ BEGIN
    CREATE TYPE special_item_type AS ENUM ('set_break', 'pause');
EXCEPTION
    WHEN duplicate_object THEN 
        RAISE NOTICE 'enum special_item_type already exists — OK';
END $$;

-- 2. Create the setlist_special_items table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.setlist_special_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  band_id UUID REFERENCES public.bands(id) ON DELETE CASCADE NOT NULL,
  type special_item_type NOT NULL,
  duration_minutes INTEGER,
  duration_seconds INTEGER,
  purposes TEXT[],
  custom_purposes TEXT[],
  is_saved_template BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Add item_type column to setlist_songs if missing
DO $$ BEGIN
  ALTER TABLE public.setlist_songs 
    ADD COLUMN item_type TEXT NOT NULL DEFAULT 'song';
  RAISE NOTICE 'Added item_type column to setlist_songs';
EXCEPTION
  WHEN duplicate_column THEN
    RAISE NOTICE 'item_type column already exists — OK';
END $$;

-- 4. Add special_item_id column to setlist_songs if missing
DO $$ BEGIN
  ALTER TABLE public.setlist_songs 
    ADD COLUMN special_item_id UUID REFERENCES public.setlist_special_items(id) ON DELETE CASCADE;
  RAISE NOTICE 'Added special_item_id column to setlist_songs';
EXCEPTION
  WHEN duplicate_column THEN
    RAISE NOTICE 'special_item_id column already exists — OK';
END $$;

-- 5. Make song_id nullable (it was NOT NULL before)
ALTER TABLE public.setlist_songs 
  ALTER COLUMN song_id DROP NOT NULL;

-- 6. Drop old unique constraint on (setlist_id, song_id) if it exists
ALTER TABLE public.setlist_songs 
  DROP CONSTRAINT IF EXISTS setlist_songs_setlist_id_song_id_key;

-- 7. Create partial unique index for songs only (skip if already exists)
CREATE UNIQUE INDEX IF NOT EXISTS idx_setlist_songs_unique_song 
  ON public.setlist_songs (setlist_id, song_id) 
  WHERE item_type = 'song' AND song_id IS NOT NULL;

-- 8. Create indexes
CREATE INDEX IF NOT EXISTS idx_special_items_band_id ON public.setlist_special_items(band_id);
CREATE INDEX IF NOT EXISTS idx_special_items_type ON public.setlist_special_items(type);
CREATE INDEX IF NOT EXISTS idx_setlist_songs_item_type ON public.setlist_songs(item_type);

-- Conditional index for special_item_id (can't use IF NOT EXISTS on partial index easily)
DO $$ BEGIN
  CREATE INDEX idx_setlist_songs_special_item ON public.setlist_songs(special_item_id) 
    WHERE special_item_id IS NOT NULL;
EXCEPTION
  WHEN duplicate_table THEN
    RAISE NOTICE 'idx_setlist_songs_special_item already exists — OK';
END $$;

-- 9. Enable RLS on setlist_special_items
ALTER TABLE public.setlist_special_items ENABLE ROW LEVEL SECURITY;

-- 10. RLS policies for setlist_special_items (drop first to be idempotent)
DROP POLICY IF EXISTS "Band members can view special items" ON public.setlist_special_items;
CREATE POLICY "Band members can view special items" ON public.setlist_special_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlist_special_items.band_id 
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Band members can create special items" ON public.setlist_special_items;
CREATE POLICY "Band members can create special items" ON public.setlist_special_items
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlist_special_items.band_id 
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Band members can update special items" ON public.setlist_special_items;
CREATE POLICY "Band members can update special items" ON public.setlist_special_items
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlist_special_items.band_id 
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Band members can delete special items" ON public.setlist_special_items;
CREATE POLICY "Band members can delete special items" ON public.setlist_special_items
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlist_special_items.band_id 
      AND user_id = auth.uid()
    )
  );

-- 11. Add check constraint (drop first if it exists to avoid conflicts)
ALTER TABLE public.setlist_songs
  DROP CONSTRAINT IF EXISTS chk_item_type_refs;

ALTER TABLE public.setlist_songs
  ADD CONSTRAINT chk_item_type_refs CHECK (
    (item_type = 'song' AND song_id IS NOT NULL AND special_item_id IS NULL) OR
    (item_type IN ('set_break', 'pause') AND song_id IS NULL AND special_item_id IS NOT NULL)
  );

-- 12. Create or replace the increment_setlist_positions RPC
--     Using RETURNS VOID for maximum compatibility
CREATE OR REPLACE FUNCTION public.increment_setlist_positions(p_setlist_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.setlist_songs
    SET position = position + 1
  WHERE setlist_id = p_setlist_id;
END;
$$;

-- 13. Verification: check everything is in place
DO $$
DECLARE
  tbl_exists BOOLEAN;
  col_exists BOOLEAN;
  song_nullable BOOLEAN;
BEGIN
  -- Check table exists
  SELECT EXISTS(SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'setlist_special_items') 
    INTO tbl_exists;
  IF tbl_exists THEN
    RAISE NOTICE '✓ setlist_special_items table exists';
  ELSE
    RAISE WARNING '✗ setlist_special_items table MISSING';
  END IF;

  -- Check item_type column 
  SELECT EXISTS(SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'setlist_songs' AND column_name = 'item_type')
    INTO col_exists;
  IF col_exists THEN
    RAISE NOTICE '✓ item_type column exists on setlist_songs';
  ELSE
    RAISE WARNING '✗ item_type column MISSING on setlist_songs';
  END IF;

  -- Check special_item_id column
  SELECT EXISTS(SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'setlist_songs' AND column_name = 'special_item_id')
    INTO col_exists;
  IF col_exists THEN
    RAISE NOTICE '✓ special_item_id column exists on setlist_songs';
  ELSE
    RAISE WARNING '✗ special_item_id column MISSING on setlist_songs';
  END IF;

  -- Check song_id is nullable
  SELECT (is_nullable = 'YES') FROM information_schema.columns
    WHERE table_name = 'setlist_songs' AND column_name = 'song_id'
    INTO song_nullable;
  IF song_nullable THEN
    RAISE NOTICE '✓ song_id is nullable';
  ELSE
    RAISE WARNING '✗ song_id is NOT NULL — breaks/pauses will fail!';
  END IF;

  -- Check RPC exists
  IF EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'increment_setlist_positions') THEN
    RAISE NOTICE '✓ increment_setlist_positions RPC exists';
  ELSE
    RAISE WARNING '✗ increment_setlist_positions RPC MISSING';
  END IF;

  RAISE NOTICE '— Verification complete —';
END $$;
