-- Migration: Atomic setlist reordering RPC
-- Feature: bug/setlist-reorder-n-plus-one
-- Purpose: Replace client-side N+1 sequential updates with single atomic server-side transaction

CREATE OR REPLACE FUNCTION reorder_setlists(
  p_band_id UUID,
  p_setlist_ids UUID[]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_verified_count INT;
  v_expected_count INT;
  v_updated_count INT;
BEGIN
  -- Get authenticated user ID
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Not authenticated'
    );
  END IF;

  -- Validate user is an active member of the band
  IF NOT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = v_user_id
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'User is not a member of this band'
    );
  END IF;

  -- Verify all setlist IDs belong to the specified band
  v_expected_count := array_length(p_setlist_ids, 1);
  
  SELECT COUNT(*)
  INTO v_verified_count
  FROM setlists
  WHERE id = ANY(p_setlist_ids)
    AND band_id = p_band_id;

  IF v_verified_count != v_expected_count THEN
    RETURN json_build_object(
      'success', false,
      'error', format('Some setlist IDs do not belong to this band (expected: %s, verified: %s)', v_expected_count, v_verified_count)
    );
  END IF;

  -- Perform atomic reordering
  -- Position starts at 1 (position 0 is reserved for Catalog)
  UPDATE setlists
  SET position = subquery.new_position
  FROM unnest(p_setlist_ids) WITH ORDINALITY AS subquery(id, new_position)
  WHERE setlists.id = subquery.id
    AND setlists.band_id = p_band_id;

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;

  -- Return success response
  RETURN json_build_object(
    'success', true,
    'reordered_count', v_updated_count
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;
