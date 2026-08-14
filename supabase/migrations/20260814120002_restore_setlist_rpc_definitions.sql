-- ============================================================================
-- Restore missing setlist RPC definitions to version control
-- ============================================================================
-- These functions exist in production but were never tracked in migrations.
-- This migration adds them with proper SECURITY DEFINER and SET search_path.
-- ============================================================================

-- Function 1: reorder_setlist_songs (one-line delegate to reorder_setlist_items)
CREATE OR REPLACE FUNCTION public.reorder_setlist_songs(p_setlist_id uuid, p_row_ids uuid[])
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path = public
AS $function$
  SELECT public.reorder_setlist_items(p_setlist_id, p_row_ids);
$function$;

GRANT EXECUTE ON FUNCTION reorder_setlist_songs(UUID, UUID[]) TO authenticated;

-- Function 2: reorder_setlist_items (atomic reordering logic)
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

GRANT EXECUTE ON FUNCTION reorder_setlist_items(UUID, UUID[]) TO authenticated;

-- Function 3: add_special_item_to_setlist
CREATE OR REPLACE FUNCTION public.add_special_item_to_setlist(p_setlist_id uuid, p_special_item_id uuid, p_item_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_existing_count INT;
  v_max_position   INT;
  v_new_position   INT;
  v_new_row_id     UUID;
BEGIN
  -- Count existing items and find the max position
  SELECT COUNT(*), COALESCE(MAX(position), -1)
    INTO v_existing_count, v_max_position
    FROM public.setlist_songs
   WHERE setlist_id = p_setlist_id;

  v_new_position := v_max_position + 1;

  -- Insert the new special item at the end
  INSERT INTO public.setlist_songs (
    setlist_id,
    song_id,
    special_item_id,
    item_type,
    position
  ) VALUES (
    p_setlist_id,
    NULL,
    p_special_item_id,
    p_item_type,
    v_new_position
  )
  RETURNING id INTO v_new_row_id;

  RETURN jsonb_build_object(
    'success', true,
    'new_row_id', v_new_row_id,
    'new_position', v_new_position,
    'existing_count', v_existing_count
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION add_special_item_to_setlist(UUID, UUID, TEXT) TO authenticated;

-- Function 4: delete_setlist (re-issue with SET search_path in definition)
CREATE OR REPLACE FUNCTION delete_setlist(
  p_band_id UUID,
  p_setlist_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_setlist_name TEXT;
  v_is_catalog BOOLEAN;
BEGIN
  -- Verify band membership
  IF NOT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
    AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Access denied: Not a member of this band';
  END IF;

  -- Get setlist info (use COALESCE for environments without is_catalog)
  SELECT name, COALESCE(is_catalog, FALSE)
  INTO v_setlist_name, v_is_catalog
  FROM setlists
  WHERE id = p_setlist_id AND band_id = p_band_id;

  -- Check if setlist exists
  IF v_setlist_name IS NULL THEN
    RAISE EXCEPTION 'Setlist not found or does not belong to this band';
  END IF;

  -- Prevent deletion of Catalog
  IF v_is_catalog OR v_setlist_name = 'Catalog' OR v_setlist_name = 'All Songs' THEN
    RAISE EXCEPTION 'Cannot delete the Catalog setlist';
  END IF;

  -- Clear setlist references from gigs (set to NULL instead of failing)
  UPDATE gigs
  SET setlist_id = NULL
  WHERE setlist_id = p_setlist_id AND band_id = p_band_id;

  -- Clear setlist references from rehearsals (set to NULL instead of failing)
  UPDATE rehearsals
  SET setlist_id = NULL
  WHERE setlist_id = p_setlist_id AND band_id = p_band_id;

  -- Delete setlist_songs (FK constraint would cascade, but be explicit)
  DELETE FROM setlist_songs WHERE setlist_id = p_setlist_id;

  -- Delete the setlist
  DELETE FROM setlists WHERE id = p_setlist_id AND band_id = p_band_id;

END;
$$;

GRANT EXECUTE ON FUNCTION delete_setlist(UUID, UUID) TO authenticated;
