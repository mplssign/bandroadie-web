-- ============================================================================
-- SETLIST SPECIAL ITEMS: Set Breaks & Pauses
-- 
-- Adds structured break/pause items to setlists. These are NOT songs and
-- do NOT belong in the band catalog. They are first-class ordered items
-- within setlists alongside songs.
-- ============================================================================

-- 1. Create enum for special item types
CREATE TYPE special_item_type AS ENUM ('set_break', 'pause');

-- 2. Create table for reusable break/pause templates
CREATE TABLE public.setlist_special_items (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  band_id UUID REFERENCES public.bands(id) ON DELETE CASCADE NOT NULL,
  type special_item_type NOT NULL,
  duration_minutes INTEGER,          -- Used for set_break (5-min increments)
  duration_seconds INTEGER,          -- Used for pause (optional, freeform)
  purposes TEXT[],                    -- Predefined pause purposes
  custom_purposes TEXT[],            -- User-defined pause purposes
  is_saved_template BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Add item_type and special_item_id to setlist_songs
--    item_type: 'song' (default for existing rows), 'set_break', 'pause'
--    special_item_id: FK to setlist_special_items (null for songs)
--    song_id: becomes nullable (null for breaks/pauses)
ALTER TABLE public.setlist_songs 
  ADD COLUMN item_type TEXT NOT NULL DEFAULT 'song',
  ADD COLUMN special_item_id UUID REFERENCES public.setlist_special_items(id) ON DELETE CASCADE;

-- Make song_id nullable (it was NOT NULL before, but breaks/pauses don't have songs)
ALTER TABLE public.setlist_songs 
  ALTER COLUMN song_id DROP NOT NULL;

-- 4. Drop the old unique constraint on (setlist_id, song_id) since song_id is now nullable
--    and we need to allow multiple breaks/pauses
ALTER TABLE public.setlist_songs 
  DROP CONSTRAINT IF EXISTS setlist_songs_setlist_id_song_id_key;

-- 5. Create new unique constraint: songs still unique per setlist, but only when item_type='song'
--    This uses a partial unique index
CREATE UNIQUE INDEX idx_setlist_songs_unique_song 
  ON public.setlist_songs (setlist_id, song_id) 
  WHERE item_type = 'song' AND song_id IS NOT NULL;

-- 6. Indexes for the new table
CREATE INDEX idx_special_items_band_id ON public.setlist_special_items(band_id);
CREATE INDEX idx_special_items_type ON public.setlist_special_items(type);
CREATE INDEX idx_setlist_songs_special_item ON public.setlist_songs(special_item_id) 
  WHERE special_item_id IS NOT NULL;
CREATE INDEX idx_setlist_songs_item_type ON public.setlist_songs(item_type);

-- 7. RLS policies for setlist_special_items
ALTER TABLE public.setlist_special_items ENABLE ROW LEVEL SECURITY;

-- Band members can view special items
CREATE POLICY "Band members can view special items" ON public.setlist_special_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlist_special_items.band_id 
      AND user_id = auth.uid()
    )
  );

-- Band members can create special items
CREATE POLICY "Band members can create special items" ON public.setlist_special_items
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlist_special_items.band_id 
      AND user_id = auth.uid()
    )
  );

-- Band members can update special items
CREATE POLICY "Band members can update special items" ON public.setlist_special_items
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlist_special_items.band_id 
      AND user_id = auth.uid()
    )
  );

-- Band members can delete special items
CREATE POLICY "Band members can delete special items" ON public.setlist_special_items
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlist_special_items.band_id 
      AND user_id = auth.uid()
    )
  );

-- 8. Add check constraint: song items must have song_id, special items must have special_item_id
ALTER TABLE public.setlist_songs
  ADD CONSTRAINT chk_item_type_refs CHECK (
    (item_type = 'song' AND song_id IS NOT NULL AND special_item_id IS NULL) OR
    (item_type IN ('set_break', 'pause') AND song_id IS NULL AND special_item_id IS NOT NULL)
  );
