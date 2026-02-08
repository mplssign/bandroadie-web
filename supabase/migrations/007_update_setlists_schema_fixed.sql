-- First, add missing columns to your existing setlists table
ALTER TABLE public.setlists 
ADD COLUMN IF NOT EXISTS total_duration INTEGER DEFAULT 0;

-- Create tuning enum if it doesn't exist
DO $$ BEGIN
    CREATE TYPE tuning_type AS ENUM ('standard', 'drop_d', 'half_step', 'full_step');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Create songs table
CREATE TABLE IF NOT EXISTS public.songs (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  is_live BOOLEAN DEFAULT FALSE,
  bpm INTEGER,
  tuning tuning_type DEFAULT 'standard',
  duration_seconds INTEGER,
  musicbrainz_id TEXT,
  spotify_id TEXT,
  deezer_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  -- Ensure unique song per title/artist combination
  UNIQUE(title, artist)
);

-- Create setlist_songs junction table
CREATE TABLE IF NOT EXISTS public.setlist_songs (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  setlist_id UUID REFERENCES public.setlists(id) ON DELETE CASCADE NOT NULL,
  song_id UUID REFERENCES public.songs(id) ON DELETE CASCADE NOT NULL,
  position INTEGER NOT NULL,
  bpm INTEGER,
  tuning tuning_type DEFAULT 'standard',
  duration_seconds INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  -- Ensure unique position per setlist
  UNIQUE(setlist_id, position),
  -- Ensure unique song per setlist
  UNIQUE(setlist_id, song_id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_songs_title_artist ON public.songs(title, artist);
CREATE INDEX IF NOT EXISTS idx_songs_bpm ON public.songs(bpm);
CREATE INDEX IF NOT EXISTS idx_setlists_band_id ON public.setlists(band_id);
CREATE INDEX IF NOT EXISTS idx_setlist_songs_setlist_id ON public.setlist_songs(setlist_id);
CREATE INDEX IF NOT EXISTS idx_setlist_songs_song_id ON public.setlist_songs(song_id);
CREATE INDEX IF NOT EXISTS idx_setlist_songs_position ON public.setlist_songs(setlist_id, position);

-- Enable RLS on new tables
ALTER TABLE public.songs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.setlist_songs ENABLE ROW LEVEL SECURITY;

-- Songs policies (songs are global but readable by all authenticated users)
DROP POLICY IF EXISTS "Songs are viewable by authenticated users" ON public.songs;
CREATE POLICY "Songs are viewable by authenticated users" ON public.songs
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Songs can be created by authenticated users" ON public.songs;
CREATE POLICY "Songs can be created by authenticated users" ON public.songs
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Setlists policies (only band members can access)
DROP POLICY IF EXISTS "Band members can view setlists" ON public.setlists;
CREATE POLICY "Band members can view setlists" ON public.setlists
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlists.band_id 
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Band members can create setlists" ON public.setlists;
CREATE POLICY "Band members can create setlists" ON public.setlists
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlists.band_id 
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Band members can update setlists" ON public.setlists;
CREATE POLICY "Band members can update setlists" ON public.setlists
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlists.band_id 
      AND user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Band members can delete setlists" ON public.setlists;
CREATE POLICY "Band members can delete setlists" ON public.setlists
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members 
      WHERE band_id = setlists.band_id 
      AND user_id = auth.uid()
    )
  );

-- Setlist songs policies (inherit from setlist access)
DROP POLICY IF EXISTS "Users can view setlist songs if they can view the setlist" ON public.setlist_songs;
CREATE POLICY "Users can view setlist songs if they can view the setlist" ON public.setlist_songs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can create setlist songs if they can access the setlist" ON public.setlist_songs;
CREATE POLICY "Users can create setlist songs if they can access the setlist" ON public.setlist_songs
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can update setlist songs if they can access the setlist" ON public.setlist_songs;
CREATE POLICY "Users can update setlist songs if they can access the setlist" ON public.setlist_songs
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs;
CREATE POLICY "Users can delete setlist songs if they can access the setlist" ON public.setlist_songs
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.setlists s
      JOIN public.band_members bm ON s.band_id = bm.band_id
      WHERE s.id = setlist_songs.setlist_id 
      AND bm.user_id = auth.uid()
    )
  );

-- Function to automatically update setlist total_duration
CREATE OR REPLACE FUNCTION update_setlist_duration()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.setlists 
  SET total_duration = (
    SELECT COALESCE(SUM(duration_seconds), 0)
    FROM public.setlist_songs
    WHERE setlist_id = COALESCE(NEW.setlist_id, OLD.setlist_id)
  ),
  updated_at = NOW()
  WHERE id = COALESCE(NEW.setlist_id, OLD.setlist_id);
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Triggers to update setlist duration
DROP TRIGGER IF EXISTS update_setlist_duration_on_insert ON public.setlist_songs;
CREATE TRIGGER update_setlist_duration_on_insert
  AFTER INSERT ON public.setlist_songs
  FOR EACH ROW EXECUTE FUNCTION update_setlist_duration();

DROP TRIGGER IF EXISTS update_setlist_duration_on_update ON public.setlist_songs;
CREATE TRIGGER update_setlist_duration_on_update
  AFTER UPDATE ON public.setlist_songs
  FOR EACH ROW EXECUTE FUNCTION update_setlist_duration();

DROP TRIGGER IF EXISTS update_setlist_duration_on_delete ON public.setlist_songs;
CREATE TRIGGER update_setlist_duration_on_delete
  AFTER DELETE ON public.setlist_songs
  FOR EACH ROW EXECUTE FUNCTION update_setlist_duration();

-- Function to automatically reorder positions when songs are added/removed
CREATE OR REPLACE FUNCTION reorder_setlist_positions()
RETURNS TRIGGER AS $$
BEGIN
  -- Reorder positions to be sequential starting from 1
  WITH ordered_songs AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY position) as new_position
    FROM public.setlist_songs
    WHERE setlist_id = COALESCE(NEW.setlist_id, OLD.setlist_id)
  )
  UPDATE public.setlist_songs
  SET position = ordered_songs.new_position
  FROM ordered_songs
  WHERE public.setlist_songs.id = ordered_songs.id;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to reorder positions after delete
DROP TRIGGER IF EXISTS reorder_setlist_positions_on_delete ON public.setlist_songs;
CREATE TRIGGER reorder_setlist_positions_on_delete
  AFTER DELETE ON public.setlist_songs
  FOR EACH ROW EXECUTE FUNCTION reorder_setlist_positions();