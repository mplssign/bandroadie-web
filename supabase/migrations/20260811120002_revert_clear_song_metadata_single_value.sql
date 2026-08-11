-- Revert clear_song_metadata to pre-Phase-2.2 signature (4 clear flags).
-- Removes 6 dual-value clear flags added in 20260809120002.

-- Drop the 10-flag Phase 2.2 version (CRITICAL: must match exact production signature)
DROP FUNCTION IF EXISTS clear_song_metadata(UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN);

CREATE OR REPLACE FUNCTION clear_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_clear_bpm BOOLEAN DEFAULT FALSE,
  p_clear_duration BOOLEAN DEFAULT FALSE,
  p_clear_tuning BOOLEAN DEFAULT FALSE,
  p_clear_musical_key BOOLEAN DEFAULT FALSE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  v_song_band_id UUID;
  v_update_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN json_build_object('success', false, 'error', 'Access denied: not an active member of this band');
  END IF;

  SELECT band_id INTO v_song_band_id FROM songs WHERE id = p_song_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Song not found');
  END IF;

  IF v_song_band_id IS NOT NULL AND v_song_band_id != p_band_id THEN
    RETURN json_build_object('success', false, 'error', 'Song belongs to a different band');
  END IF;

  IF NOT (p_clear_bpm OR p_clear_duration OR p_clear_tuning OR p_clear_musical_key) THEN
    RETURN json_build_object('success', false, 'error', 'No clear flags provided');
  END IF;

  UPDATE songs
  SET
    bpm = CASE WHEN p_clear_bpm THEN NULL ELSE bpm END,
    duration_seconds = CASE WHEN p_clear_duration THEN 0 ELSE duration_seconds END,
    tuning = CASE WHEN p_clear_tuning THEN NULL ELSE tuning END,
    musical_key = CASE WHEN p_clear_musical_key THEN NULL ELSE musical_key END,
    updated_at = NOW()
  WHERE id = p_song_id;

  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION clear_song_metadata TO authenticated;

COMMENT ON FUNCTION clear_song_metadata IS
  'Clears selected song metadata fields. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id. Reverted from Phase 2.2 dual-value signature.';
