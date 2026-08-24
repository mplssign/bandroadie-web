-- ===========================================================================
-- EMERGENCY ROLLBACK SCRIPT
-- ===========================================================================
-- Feature: bug/band-create-catalog-trigger-race
-- Purpose: Restore ensure_catalog_setlist to 2026-08-22 state (before bypass clause)
-- Project: nekwjxvgbveheooyorjo
-- 
-- ⚠️ WARNING: This REVERTS the fix and RE-BREAKS band creation
-- 
-- When to use this:
--   - Any Tier 2 test fails (especially Test 2.3 security regression check)
--   - Unexpected behavior observed after migration
--   - Security concern raised by QA or Architect
--
-- Effect:
--   - Band creation will fail again with "Access denied" error
--   - Restores known stable state from 2026-08-22 12:52 UTC
--   - All existing bands and data remain intact
--
-- After rollback:
--   - Document failure in ENGINEER_REPORT.md
--   - Investigate root cause with Architect
--   - Develop alternative fix
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ensure_catalog_setlist(p_band_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  catalog_id UUID;
  catalog_count INTEGER;
  oldest_catalog RECORD;
BEGIN
  -- ===========================================================================
  -- AUTHORIZATION CHECK (2026-08-22 version — NO BYPASS CLAUSE)
  -- ===========================================================================
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Simple membership check only — no band-creation race bypass
  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Access denied: not an active member of this band';
  END IF;

  -- ===========================================================================
  -- CATALOG LOGIC (unchanged)
  -- ===========================================================================

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
$function$;

-- ===========================================================================
-- ✅ ROLLBACK COMPLETE
-- ===========================================================================
-- The function is now restored to 2026-08-22 state (before bypass clause).
-- Band creation is BROKEN again (will fail with "Access denied").
--
-- Next Steps:
--   1. Document rollback in ENGINEER_REPORT.md with reason
--   2. Verify rollback with this query:
--      SELECT pg_get_functiondef('public.ensure_catalog_setlist(uuid)'::regprocedure)::text
--        NOT LIKE '%pg_trigger_depth%' AS "Rollback successful?";
--      Expected: TRUE (confirms bypass clause is removed)
--   3. Notify Architect and QA of rollback
--   4. Investigate failure cause
--   5. Develop alternative fix
-- ===========================================================================
