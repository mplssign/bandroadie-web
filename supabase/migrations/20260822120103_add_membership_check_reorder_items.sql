-- ===========================================================================
-- Migration: Add membership check to reorder_setlist_items
-- Description: Adds auth.uid() + band_members authorization check to prevent
--              cross-tenant data tampering via reorder_setlist_items RPC
-- Feature: bug/setlist-rpc-missing-membership-check
-- Date: 2026-08-22
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.reorder_setlist_items(p_setlist_id uuid, p_row_ids uuid[])
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  v_band_id UUID;
  v_count INTEGER;
  v_expected INTEGER;
BEGIN
  -- ===========================================================================
  -- AUTHORIZATION CHECK (added 2026-08-22)
  -- ===========================================================================
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT band_id INTO v_band_id FROM setlists WHERE id = p_setlist_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Setlist not found');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN json_build_object('success', false, 'error', 'Access denied: not an active member of this band');
  END IF;

  -- ===========================================================================
  -- EXISTING LOGIC (unchanged below this point)
  -- ===========================================================================
  v_expected := array_length(p_row_ids, 1);

  -- Validate: all supplied row IDs must belong to the given setlist
  SELECT COUNT(*)
    INTO v_count
    FROM public.setlist_songs
   WHERE id = ANY(p_row_ids)
     AND setlist_id = p_setlist_id;

  IF v_count <> v_expected THEN
    RAISE EXCEPTION 'Row count mismatch: expected %, found % for setlist %',
      v_expected, v_count, p_setlist_id;
  END IF;

  -- Phase 1: assign temporary negative positions to avoid UNIQUE violation
  UPDATE public.setlist_songs
     SET position = -(ordinality::INTEGER)
    FROM unnest(p_row_ids) WITH ORDINALITY AS t(rid, ordinality)
   WHERE setlist_songs.id = t.rid;

  -- Phase 2: flip to final 0-based positions
  UPDATE public.setlist_songs
     SET position = (-position) - 1
   WHERE id = ANY(p_row_ids);

  RETURN json_build_object('success', TRUE, 'reordered_count', v_expected);
END;
$function$;

-- ===========================================================================
-- ROLLBACK (restore function body without authorization check)
-- To rollback: uncomment and run the following
-- ===========================================================================
/*
DROP FUNCTION IF EXISTS reorder_setlist_items(UUID, UUID[]);

CREATE OR REPLACE FUNCTION public.reorder_setlist_items(p_setlist_id uuid, p_row_ids uuid[])
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_count INTEGER;
  v_expected INTEGER;
BEGIN
  v_expected := array_length(p_row_ids, 1);

  -- Validate: all supplied row IDs must belong to the given setlist
  SELECT COUNT(*)
    INTO v_count
    FROM public.setlist_songs
   WHERE id = ANY(p_row_ids)
     AND setlist_id = p_setlist_id;

  IF v_count <> v_expected THEN
    RAISE EXCEPTION 'Row count mismatch: expected %, found % for setlist %',
      v_expected, v_count, p_setlist_id;
  END IF;

  -- Phase 1: assign temporary negative positions to avoid UNIQUE violation
  UPDATE public.setlist_songs
     SET position = -(ordinality::INTEGER)
    FROM unnest(p_row_ids) WITH ORDINALITY AS t(rid, ordinality)
   WHERE setlist_songs.id = t.rid;

  -- Phase 2: flip to final 0-based positions
  UPDATE public.setlist_songs
     SET position = (-position) - 1
   WHERE id = ANY(p_row_ids);

  RETURN json_build_object('success', TRUE, 'reordered_count', v_expected);
END;
$function$;
*/
