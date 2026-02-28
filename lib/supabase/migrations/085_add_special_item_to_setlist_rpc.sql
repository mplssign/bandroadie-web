-- ============================================================================
-- MIGRATION 085: Atomic RPC to add a special item to a setlist
-- ============================================================================
-- addToSetlist currently performs 2×N sequential HTTP calls to shift existing
-- items before inserting the new row.  Each UPDATE triggers
-- update_setlist_duration, which locks the setlists row, making this slow
-- even with sequential calls (round-trip latency per row).
--
-- This RPC shifts all existing positions +1 and inserts the new row at
-- position 0 in a single transaction — one round-trip instead of 2N+1.
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
  v_new_row_id     UUID;
BEGIN
  -- Count existing items (for the return value)
  SELECT COUNT(*)
    INTO v_existing_count
    FROM public.setlist_songs
   WHERE setlist_id = p_setlist_id;

  IF v_existing_count > 0 THEN
    -- Phase 1: shift all items to a high temporary range to avoid
    -- UNIQUE(setlist_id, position) violations during the shift.
    UPDATE public.setlist_songs
       SET position = position + 100000
     WHERE setlist_id = p_setlist_id;

    -- Phase 2: set final positions (original + 1)
    UPDATE public.setlist_songs
       SET position = position - 100000 + 1
     WHERE setlist_id = p_setlist_id
       AND position >= 100000;
  END IF;

  -- Insert the new special item at position 0
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
    0
  )
  RETURNING id INTO v_new_row_id;

  RETURN jsonb_build_object(
    'success', true,
    'new_row_id', v_new_row_id,
    'shifted_count', v_existing_count
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;
