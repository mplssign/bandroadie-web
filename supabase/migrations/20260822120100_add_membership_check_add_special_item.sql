-- ===========================================================================
-- Add authorization check to add_special_item_to_setlist
-- ===========================================================================
-- Adds auth.uid() + band_members check to prevent cross-tenant data tampering
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.add_special_item_to_setlist(p_setlist_id uuid, p_special_item_id uuid, p_item_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  v_band_id UUID;
  v_existing_count INT;
  v_max_position   INT;
  v_new_position   INT;
  v_new_row_id     UUID;
BEGIN
  -- AUTHORIZATION CHECK
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT band_id INTO v_band_id FROM setlists WHERE id = p_setlist_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Setlist not found');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN jsonb_build_object('success', false, 'error', 'Access denied: not an active member of this band');
  END IF;

  -- EXISTING LOGIC (unchanged below this point)
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

-- ===========================================================================
-- ROLLBACK (restore function body without authorization check)
-- ===========================================================================
-- DROP FUNCTION IF EXISTS add_special_item_to_setlist(UUID, UUID, TEXT);
-- 
-- CREATE OR REPLACE FUNCTION public.add_special_item_to_setlist(p_setlist_id uuid, p_special_item_id uuid, p_item_type text)
--  RETURNS jsonb
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path = public
-- AS $function$
-- DECLARE
--   v_existing_count INT;
--   v_max_position   INT;
--   v_new_position   INT;
--   v_new_row_id     UUID;
-- BEGIN
--   -- Count existing items and find the max position
--   SELECT COUNT(*), COALESCE(MAX(position), -1)
--     INTO v_existing_count, v_max_position
--     FROM public.setlist_songs
--    WHERE setlist_id = p_setlist_id;
-- 
--   v_new_position := v_max_position + 1;
-- 
--   -- Insert the new special item at the end
--   INSERT INTO public.setlist_songs (
--     setlist_id,
--     song_id,
--     special_item_id,
--     item_type,
--     position
--   ) VALUES (
--     p_setlist_id,
--     NULL,
--     p_special_item_id,
--     p_item_type,
--     v_new_position
--   )
--   RETURNING id INTO v_new_row_id;
-- 
--   RETURN jsonb_build_object(
--     'success', true,
--     'new_row_id', v_new_row_id,
--     'new_position', v_new_position,
--     'existing_count', v_existing_count
--   );
-- 
-- EXCEPTION WHEN OTHERS THEN
--   RETURN jsonb_build_object(
--     'success', false,
--     'error', SQLERRM
--   );
-- END;
-- $function$;
-- 
-- GRANT EXECUTE ON FUNCTION add_special_item_to_setlist(UUID, UUID, TEXT) TO authenticated;
