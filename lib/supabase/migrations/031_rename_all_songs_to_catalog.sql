-- Migration to rename "All Songs" to "Catalog"
-- This standardizes the master song list naming across the application

-- Step 1: Update the CHECK constraint to allow 'catalog' instead of 'all_songs'
ALTER TABLE public.setlists DROP CONSTRAINT IF EXISTS setlists_setlist_type_check;
ALTER TABLE public.setlists ADD CONSTRAINT setlists_setlist_type_check 
  CHECK (setlist_type IN ('regular', 'catalog'));

-- Step 2: Update all existing 'all_songs' entries to 'catalog'
UPDATE public.setlists 
SET setlist_type = 'catalog', name = 'Catalog'
WHERE setlist_type = 'all_songs' OR LOWER(name) = 'all songs';

-- Step 3: Drop the old unique index and create new one
DROP INDEX IF EXISTS idx_unique_all_songs_per_band;
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_catalog_per_band 
ON public.setlists(band_id) 
WHERE setlist_type = 'catalog';

-- Step 4: Update the function to create Catalog setlist for a band
CREATE OR REPLACE FUNCTION create_catalog_setlist(target_band_id UUID)
RETURNS UUID AS $$
DECLARE
  catalog_id UUID;
  existing_songs RECORD;
  song_position INTEGER := 1;
BEGIN
  -- Check if Catalog already exists for this band
  SELECT id INTO catalog_id 
  FROM public.setlists 
  WHERE band_id = target_band_id AND setlist_type = 'catalog';
  
  IF catalog_id IS NOT NULL THEN
    RETURN catalog_id;
  END IF;
  
  -- Create the Catalog setlist
  INSERT INTO public.setlists (band_id, name, setlist_type, total_duration)
  VALUES (target_band_id, 'Catalog', 'catalog', 0)
  RETURNING id INTO catalog_id;
  
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
    VALUES (catalog_id, existing_songs.song_id, song_position, existing_songs.duration_seconds, existing_songs.bpm, existing_songs.tuning)
    ON CONFLICT (setlist_id, song_id) DO NOTHING;
    
    song_position := song_position + 1;
  END LOOP;
  
  RETURN catalog_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old function
DROP FUNCTION IF EXISTS create_all_songs_setlist(UUID);

-- Step 5: Update trigger function to auto-add songs to Catalog
CREATE OR REPLACE FUNCTION auto_add_to_catalog()
RETURNS TRIGGER AS $$
DECLARE
  target_band_id UUID;
  catalog_id UUID;
  max_position INTEGER;
BEGIN
  -- Get the band_id for this setlist
  SELECT band_id INTO target_band_id 
  FROM public.setlists 
  WHERE id = NEW.setlist_id;
  
  -- Skip if this is already the Catalog setlist
  IF EXISTS (SELECT 1 FROM public.setlists WHERE id = NEW.setlist_id AND setlist_type = 'catalog') THEN
    RETURN NEW;
  END IF;
  
  -- Get or create the Catalog setlist
  SELECT create_catalog_setlist(target_band_id) INTO catalog_id;
  
  -- Check if song already exists in Catalog
  IF NOT EXISTS (SELECT 1 FROM public.setlist_songs WHERE setlist_id = catalog_id AND song_id = NEW.song_id) THEN
    -- Get the next position
    SELECT COALESCE(MAX(position), 0) + 1 INTO max_position
    FROM public.setlist_songs 
    WHERE setlist_id = catalog_id;
    
    -- Add the song to Catalog
    INSERT INTO public.setlist_songs (setlist_id, song_id, position, duration_seconds, bpm, tuning)
    VALUES (catalog_id, NEW.song_id, max_position, NEW.duration_seconds, NEW.bpm, NEW.tuning);
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old trigger and function
DROP TRIGGER IF EXISTS trigger_auto_add_to_all_songs ON public.setlist_songs;
DROP FUNCTION IF EXISTS auto_add_to_all_songs();

-- Create new trigger
DROP TRIGGER IF EXISTS trigger_auto_add_to_catalog ON public.setlist_songs;
CREATE TRIGGER trigger_auto_add_to_catalog
  AFTER INSERT ON public.setlist_songs
  FOR EACH ROW EXECUTE FUNCTION auto_add_to_catalog();

-- Step 6: Update deletion prevention function
CREATE OR REPLACE FUNCTION prevent_catalog_deletion()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.setlist_type = 'catalog' THEN
    RAISE EXCEPTION 'Cannot delete Catalog setlist';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old trigger and function
DROP TRIGGER IF EXISTS prevent_all_songs_deletion_trigger ON public.setlists;
DROP FUNCTION IF EXISTS prevent_all_songs_deletion();

-- Create new trigger
DROP TRIGGER IF EXISTS prevent_catalog_deletion_trigger ON public.setlists;
CREATE TRIGGER prevent_catalog_deletion_trigger
  BEFORE DELETE ON public.setlists
  FOR EACH ROW EXECUTE FUNCTION prevent_catalog_deletion();

-- Step 7: Update rename prevention function
CREATE OR REPLACE FUNCTION prevent_catalog_rename()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.setlist_type = 'catalog' AND NEW.name != 'Catalog' THEN
    RAISE EXCEPTION 'Cannot rename Catalog setlist';
  END IF;
  IF OLD.setlist_type = 'catalog' AND NEW.setlist_type != 'catalog' THEN
    RAISE EXCEPTION 'Cannot change type of Catalog setlist';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop old trigger and function
DROP TRIGGER IF EXISTS prevent_all_songs_rename_trigger ON public.setlists;
DROP FUNCTION IF EXISTS prevent_all_songs_rename();

-- Create new trigger
DROP TRIGGER IF EXISTS prevent_catalog_rename_trigger ON public.setlists;
CREATE TRIGGER prevent_catalog_rename_trigger
  BEFORE UPDATE ON public.setlists
  FOR EACH ROW EXECUTE FUNCTION prevent_catalog_rename();

-- Step 8: Ensure all bands have a Catalog setlist
DO $$
DECLARE
  band_record RECORD;
BEGIN
  FOR band_record IN SELECT id FROM public.bands
  LOOP
    PERFORM create_catalog_setlist(band_record.id);
  END LOOP;
END $$;
