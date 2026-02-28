-- ============================================================================
-- MIGRATION 085: Atomic RPC to add a special item to a setlist
-- ============================================================================
-- addToSetlist currently performs 2×N sequential HTTP calls to shift existing
-- items before inserting the new row.  Each UPDATE triggers
-- update_setlist_duration, which locks the setlists row, making this slow
-- even with sequential calls (round-trip latency per row).
--
-- This RPC appends the new row at the end of the setlist (max position + 1)
-- in a single transaction — one round-trip instead of 2N+1.
-- ============================================================================

CREATE OR REPLACE FUNCTION add_special_item_to_setlist(
  p_setlist_id      UUID,
  p_special_item_id UUID,
  p_item_type       TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
$$;
