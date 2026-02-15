-- ============================================================================
-- ADD POSITION COLUMN TO SETLISTS TABLE
-- Enables drag-to-reorder for setlist cards on the Setlists screen.
-- Catalog is always position 0; user setlists start at position 1.
-- Run this in the Supabase SQL Editor.
-- ============================================================================

-- Step 1: Add the position column (default 0, safe for existing rows)
ALTER TABLE public.setlists
  ADD COLUMN IF NOT EXISTS position INT DEFAULT 0;

-- Step 2: Backfill existing non-catalog setlists with sequential positions.
-- Catalog stays at 0; other setlists get 1, 2, 3, ... ordered by name.
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY band_id
           ORDER BY name ASC
         ) AS rn
  FROM public.setlists
  WHERE is_catalog IS NOT TRUE
)
UPDATE public.setlists s
SET position = r.rn
FROM ranked r
WHERE s.id = r.id;

-- Step 3: Ensure Catalog setlists are explicitly position 0
UPDATE public.setlists
SET position = 0
WHERE is_catalog = TRUE;

-- Verify
SELECT id, name, band_id, is_catalog, position
FROM public.setlists
ORDER BY band_id, position;
