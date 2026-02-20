-- ============================================================================
-- RPC: increment_setlist_positions
-- 
-- Atomically shifts all item positions in a setlist up by 1,
-- freeing position 0 for a new item to be inserted at the top.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.increment_setlist_positions(p_setlist_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  affected INTEGER;
BEGIN
  UPDATE public.setlist_songs
  SET position = position + 1
  WHERE setlist_id = p_setlist_id;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.increment_setlist_positions(UUID) TO authenticated;
