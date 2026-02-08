-- Fix: Allow Catalog deletion when parent band is deleted (CASCADE)
-- The prevent_catalog_deletion trigger was blocking band deletion

CREATE OR REPLACE FUNCTION prevent_catalog_deletion()
RETURNS TRIGGER AS $$
BEGIN
  -- Allow deletion if the parent band is being deleted (CASCADE)
  -- Check if the band still exists
  IF NOT EXISTS (SELECT 1 FROM public.bands WHERE id = OLD.band_id) THEN
    RETURN OLD;
  END IF;
  
  -- Block direct deletion of Catalog
  IF OLD.setlist_type = 'catalog' OR OLD.is_catalog = true THEN
    RAISE EXCEPTION 'Cannot delete Catalog setlist';
  END IF;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
