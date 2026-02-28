-- ============================================================================
-- MIGRATION 084: Atomic reorder for mixed setlist items (songs + specials)
-- ============================================================================
-- The existing reorder_setlist_songs RPC matches on song_id, which is NULL
-- for special items (set breaks, pauses).  This new RPC matches on the
-- setlist_songs row id (primary key) and works for every item type.
--
-- It uses a two-phase offset approach inside a single transaction so
-- the UNIQUE(setlist_id, position) constraint is never violated and
-- no per-row triggers can cause cross-transaction lock contention.
-- ============================================================================

CREATE OR REPLACE FUNCTION reorder_setlist_items(
  p_setlist_id UUID,
  p_row_ids    UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INT;
BEGIN
  -- Phase 1: shift every matched row to a high temporary range
  UPDATE public.setlist_songs
  SET position = 100000 + array_position(p_row_ids, id) - 1
  WHERE id = ANY(p_row_ids)
    AND setlist_id = p_setlist_id;

  -- Phase 2: set final 0-based positions from array order
  UPDATE public.setlist_songs
  SET position = array_position(p_row_ids, id) - 1
  WHERE id = ANY(p_row_ids)
    AND setlist_id = p_setlist_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'reordered_count', v_count
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;
