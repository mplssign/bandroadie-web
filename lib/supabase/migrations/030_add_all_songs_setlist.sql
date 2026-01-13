-- Migration to add support for special "All Songs" setlist
-- This adds a setlist_type field and creates "All Songs" setlists for existing bands

-- Add setlist_type column to support special setlists
ALTER TABLE public.setlists 
ADD COLUMN IF NOT EXISTS setlist_type TEXT DEFAULT 'regular' CHECK (setlist_type IN ('regular', 'all_songs'));

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_setlists_type_band ON public.setlists(band_id, setlist_type);

-- Create unique constraint to ensure only one "All Songs" per band
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_all_songs_per_band 
ON public.setlists(band_id) 
WHERE setlist_type = 'all_songs';

-- Function to create "All Songs" setlist for a band
CREATE OR REPLACE FUNCTION create_all_songs_setlist(target_band_id UUID)
RETURNS UUID AS $$
DECLARE
  all_songs_id UUID;
  existing_songs RECORD;
  song_position INTEGER := 1;
BEGIN
  -- Check if "All Songs" already exists for this band
  SELECT id INTO all_songs_id 
  FROM public.setlists 
  WHERE band_id = target_band_id AND setlist_type = 'all_songs';
  
  IF all_songs_id IS NOT NULL THEN
    RETURN all_songs_id;
  END IF;
  
  -- Create the "All Songs" setlist
  INSERT INTO public.setlists (band_id, name, setlist_type, total_duration)
  VALUES (target_band_id, 'All Songs', 'all_songs', 0)
  RETURNING id INTO all_songs_id;
  
  -- Backfill with all existing songs from other setlists for this band
  FOR existing_songs IN 
    SELECT DISTINCT ss.song_id, s.duration_seconds, ss.bpm, ss.tuning
    FROM public.setlist_songs ss
    JOIN public.setlists sl ON ss.setlist_id = sl.id
    JOIN public.songs s ON ss.song_id = s.id
    WHERE sl.band_id = target_band_id 
    AND sl.setlist_type = 'regular'
    ORDER BY s.title, s.artist
  LOOP
    INSERT INTO public.setlist_songs (setlist_id, song_id, position, duration_seconds, bpm, tuning)
    VALUES (all_songs_id, existing_songs.song_id, song_position, existing_songs.duration_seconds, existing_songs.bpm, existing_songs.tuning)
    ON CONFLICT (setlist_id, song_id) DO NOTHING; -- Prevent duplicates
    
    song_position := song_position + 1;
  END LOOP;
  
  RETURN all_songs_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to automatically add songs to "All Songs" when added to other setlists
CREATE OR REPLACE FUNCTION auto_add_to_all_songs()
RETURNS TRIGGER AS $$
DECLARE
  target_band_id UUID;
  all_songs_id UUID;
  max_position INTEGER;
BEGIN
  -- Get the band_id for this setlist
  SELECT band_id INTO target_band_id 
  FROM public.setlists 
  WHERE id = NEW.setlist_id;
  
  -- Skip if this is already the "All Songs" setlist
  IF EXISTS (SELECT 1 FROM public.setlists WHERE id = NEW.setlist_id AND setlist_type = 'all_songs') THEN
    RETURN NEW;
  END IF;
  
  -- Get or create the "All Songs" setlist
  SELECT create_all_songs_setlist(target_band_id) INTO all_songs_id;
  
  -- Check if song already exists in "All Songs"
  IF NOT EXISTS (SELECT 1 FROM public.setlist_songs WHERE setlist_id = all_songs_id AND song_id = NEW.song_id) THEN
    -- Get the next position
    SELECT COALESCE(MAX(position), 0) + 1 INTO max_position
    FROM public.setlist_songs 
    WHERE setlist_id = all_songs_id;
    
    -- Add the song to "All Songs"
    INSERT INTO public.setlist_songs (setlist_id, song_id, position, duration_seconds, bpm, tuning)
    VALUES (all_songs_id, NEW.song_id, max_position, NEW.duration_seconds, NEW.bpm, NEW.tuning);
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger to auto-add songs to "All Songs"
DROP TRIGGER IF EXISTS trigger_auto_add_to_all_songs ON public.setlist_songs;
CREATE TRIGGER trigger_auto_add_to_all_songs
  AFTER INSERT ON public.setlist_songs
  FOR EACH ROW EXECUTE FUNCTION auto_add_to_all_songs();

-- Create "All Songs" setlist for all existing bands
INSERT INTO public.setlists (band_id, name, setlist_type, total_duration)
SELECT DISTINCT b.id, 'All Songs', 'all_songs', 0
FROM public.bands b
WHERE NOT EXISTS (
  SELECT 1 FROM public.setlists s 
  WHERE s.band_id = b.id AND s.setlist_type = 'all_songs'
);

-- Backfill "All Songs" for all bands with existing setlists
DO $$
DECLARE
  band_record RECORD;
BEGIN
  FOR band_record IN SELECT id FROM public.bands
  LOOP
    PERFORM create_all_songs_setlist(band_record.id);
  END LOOP;
END $$;

-- Update policies to allow access to "All Songs" setlists
-- (The existing policies should already cover this since they're band-scoped)

-- Prevent deletion of "All Songs" setlists at the database level
CREATE OR REPLACE FUNCTION prevent_all_songs_deletion()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.setlist_type = 'all_songs' THEN
    RAISE EXCEPTION 'Cannot delete "All Songs" setlist';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS prevent_all_songs_deletion_trigger ON public.setlists;
CREATE TRIGGER prevent_all_songs_deletion_trigger
  BEFORE DELETE ON public.setlists
  FOR EACH ROW EXECUTE FUNCTION prevent_all_songs_deletion();

-- Prevent renaming of "All Songs" setlists
CREATE OR REPLACE FUNCTION prevent_all_songs_rename()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.setlist_type = 'all_songs' AND NEW.name != 'All Songs' THEN
    RAISE EXCEPTION 'Cannot rename "All Songs" setlist';
  END IF;
  IF OLD.setlist_type = 'all_songs' AND NEW.setlist_type != 'all_songs' THEN
    RAISE EXCEPTION 'Cannot change type of "All Songs" setlist';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS prevent_all_songs_rename_trigger ON public.setlists;
CREATE TRIGGER prevent_all_songs_rename_trigger
  BEFORE UPDATE ON public.setlists
  FOR EACH ROW EXECUTE FUNCTION prevent_all_songs_rename();