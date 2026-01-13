-- Standalone migration to add Catalog setlist support
-- This creates all required columns, functions, and triggers from scratch

-- Step 1: Add setlist_type column if it doesn't exist
ALTER TABLE public.setlists 
ADD COLUMN IF NOT EXISTS setlist_type TEXT DEFAULT 'regular';

-- Add constraint (drop first if exists to avoid conflicts)
ALTER TABLE public.setlists DROP CONSTRAINT IF EXISTS setlists_setlist_type_check;
ALTER TABLE public.setlists ADD CONSTRAINT setlists_setlist_type_check 
  CHECK (setlist_type IN ('regular', 'catalog'));

-- Step 2: Add is_catalog boolean column for simpler queries
ALTER TABLE public.setlists 
ADD COLUMN IF NOT EXISTS is_catalog BOOLEAN DEFAULT false;

-- Step 3: Sync existing Catalog setlists (by name)
UPDATE public.setlists 
SET setlist_type = 'catalog', is_catalog = true
WHERE LOWER(name) IN ('catalog', 'all songs');

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_setlists_type_band ON public.setlists(band_id, setlist_type);
CREATE INDEX IF NOT EXISTS idx_setlists_is_catalog ON public.setlists(band_id, is_catalog) 
WHERE is_catalog = true;

-- Create unique constraint to ensure only one Catalog per band
DROP INDEX IF EXISTS idx_unique_catalog_per_band;
CREATE UNIQUE INDEX idx_unique_catalog_per_band 
ON public.setlists(band_id) 
WHERE setlist_type = 'catalog';

-- Step 4: Create ensure_catalog_setlist function
-- This is the main RPC called by the Flutter app
CREATE OR REPLACE FUNCTION ensure_catalog_setlist(p_band_id UUID)
RETURNS UUID AS $$
DECLARE
  catalog_id UUID;
  catalog_count INTEGER;
  oldest_catalog RECORD;
BEGIN
  -- Check how many Catalogs exist for this band
  SELECT COUNT(*) INTO catalog_count
  FROM public.setlists 
  WHERE band_id = p_band_id 
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'));
  
  -- If exactly one exists, return it
  IF catalog_count = 1 THEN
    SELECT id INTO catalog_id
    FROM public.setlists 
    WHERE band_id = p_band_id 
      AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
    LIMIT 1;
    
    -- Ensure metadata is correct
    UPDATE public.setlists 
    SET name = 'Catalog', setlist_type = 'catalog', is_catalog = true
    WHERE id = catalog_id AND (name != 'Catalog' OR setlist_type != 'catalog' OR is_catalog != true);
    
    RETURN catalog_id;
  END IF;
  
  -- If none exists, create one
  IF catalog_count = 0 THEN
    INSERT INTO public.setlists (band_id, name, setlist_type, is_catalog, total_duration)
    VALUES (p_band_id, 'Catalog', 'catalog', true, 0)
    RETURNING id INTO catalog_id;
    
    RETURN catalog_id;
  END IF;
  
  -- If multiple exist, keep the oldest one and merge songs from others
  SELECT id, name INTO oldest_catalog
  FROM public.setlists 
  WHERE band_id = p_band_id 
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
  ORDER BY created_at ASC
  LIMIT 1;
  
  catalog_id := oldest_catalog.id;
  
  -- Move songs from duplicate Catalogs to the primary one
  INSERT INTO public.setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds)
  SELECT 
    catalog_id,
    ss.song_id,
    COALESCE((SELECT MAX(position) FROM public.setlist_songs WHERE setlist_id = catalog_id), 0) + ROW_NUMBER() OVER (ORDER BY ss.position),
    ss.bpm,
    ss.tuning,
    ss.duration_seconds
  FROM public.setlist_songs ss
  JOIN public.setlists sl ON ss.setlist_id = sl.id
  WHERE sl.band_id = p_band_id 
    AND sl.id != catalog_id
    AND (sl.setlist_type = 'catalog' OR sl.is_catalog = true OR LOWER(sl.name) IN ('catalog', 'all songs'))
    AND NOT EXISTS (
      SELECT 1 FROM public.setlist_songs existing 
      WHERE existing.setlist_id = catalog_id AND existing.song_id = ss.song_id
    );
  
  -- Delete songs from duplicate Catalogs
  DELETE FROM public.setlist_songs 
  WHERE setlist_id IN (
    SELECT id FROM public.setlists 
    WHERE band_id = p_band_id 
      AND id != catalog_id
      AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'))
  );
  
  -- Delete duplicate Catalogs
  DELETE FROM public.setlists 
  WHERE band_id = p_band_id 
    AND id != catalog_id
    AND (setlist_type = 'catalog' OR is_catalog = true OR LOWER(name) IN ('catalog', 'all songs'));
  
  -- Ensure primary Catalog has correct metadata
  UPDATE public.setlists 
  SET name = 'Catalog', setlist_type = 'catalog', is_catalog = true
  WHERE id = catalog_id;
  
  RETURN catalog_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION ensure_catalog_setlist(UUID) TO authenticated;

-- Step 5: Ensure all existing bands have a Catalog
DO $$
DECLARE
  band_record RECORD;
BEGIN
  FOR band_record IN SELECT id FROM public.bands
  LOOP
    PERFORM ensure_catalog_setlist(band_record.id);
  END LOOP;
END $$;

-- Step 6: Create trigger to auto-create Catalog when a new band is created
CREATE OR REPLACE FUNCTION auto_create_catalog_for_band()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM ensure_catalog_setlist(NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_auto_create_catalog ON public.bands;
CREATE TRIGGER trigger_auto_create_catalog
  AFTER INSERT ON public.bands
  FOR EACH ROW EXECUTE FUNCTION auto_create_catalog_for_band();

-- Step 7: Prevent Catalog deletion
CREATE OR REPLACE FUNCTION prevent_catalog_deletion()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.setlist_type = 'catalog' OR OLD.is_catalog = true THEN
    RAISE EXCEPTION 'Cannot delete Catalog setlist';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS prevent_catalog_deletion_trigger ON public.setlists;
CREATE TRIGGER prevent_catalog_deletion_trigger
  BEFORE DELETE ON public.setlists
  FOR EACH ROW EXECUTE FUNCTION prevent_catalog_deletion();

-- Step 8: Prevent Catalog rename
CREATE OR REPLACE FUNCTION prevent_catalog_rename()
RETURNS TRIGGER AS $$
BEGIN
  IF (OLD.setlist_type = 'catalog' OR OLD.is_catalog = true) AND NEW.name != 'Catalog' THEN
    RAISE EXCEPTION 'Cannot rename Catalog setlist';
  END IF;
  IF (OLD.setlist_type = 'catalog' OR OLD.is_catalog = true) AND (NEW.setlist_type != 'catalog' OR NEW.is_catalog != true) THEN
    RAISE EXCEPTION 'Cannot change type of Catalog setlist';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS prevent_catalog_rename_trigger ON public.setlists;
CREATE TRIGGER prevent_catalog_rename_trigger
  BEFORE UPDATE ON public.setlists
  FOR EACH ROW EXECUTE FUNCTION prevent_catalog_rename();
