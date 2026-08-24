-- ===========================================================================
-- Migration: Fix ensure_catalog_setlist band creation race condition
-- Description: Extends authorization check to allow band creator during
--              trigger execution (before first band_members row exists)
-- Bug: bug/band-create-catalog-trigger-race
-- Root Cause: trigger_auto_create_catalog fires synchronously during bands
--             INSERT, before create_band() inserts creator's membership row
-- Date: 2026-08-24
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
  -- AUTHORIZATION CHECK
  -- ===========================================================================
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Check if user is an active member of the band
  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  -- If not a member, check for band-creation race exception:
  -- Allow if (1) we're in a trigger context AND (2) caller is band creator AND (3) no membership rows exist yet
  -- (this handles the trigger_auto_create_catalog race during create_band)
  -- The pg_trigger_depth() > 0 check ensures this bypass ONLY works during trigger execution,
  -- not for direct RPC calls from clients (closes re-introduction of cross-tenant tampering hole)
  IF NOT v_is_member THEN
    SELECT
      pg_trigger_depth() > 0
      AND EXISTS(SELECT 1 FROM bands WHERE id = p_band_id AND created_by = v_user_id)
      AND NOT EXISTS(SELECT 1 FROM band_members WHERE band_id = p_band_id)
    INTO v_is_member;
  END IF;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Access denied: not an active member of this band';
  END IF;

  -- ===========================================================================
  -- CATALOG LOGIC (unchanged from 20260822120101)
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
-- ACL: No changes — preserve existing grants
-- (authenticated has EXECUTE from prior migrations, anon was already revoked)
-- ===========================================================================

-- ===========================================================================
-- VERIFICATION QUERY (run after deploy)
-- Confirm function body contains the band-creation bypass clause
-- ===========================================================================
-- SELECT pg_get_functiondef('public.ensure_catalog_setlist(uuid)'::regprocedure)::text
--   LIKE '%created_by = v_user_id%' AS has_bypass_clause;
-- Expected: true
