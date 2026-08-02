-- Fix false-success bug in update_song_metadata RPC.
-- Adds RETURNING clause and eligibility-aware value verification to detect when CASE logic results in no-op updates.
-- Previously, ROW_COUNT > 0 reported success even when values didn't change (row matched but not modified).
-- This fix makes genuine enrichment failures visible while NOT erroring on expected no-ops (fill-only CASE design).
-- Captures BEFORE values to determine field eligibility, only errors if field WAS eligible but still didn't persist.
-- Required for bug/enrichment-refresh-clears-fields.

DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION update_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_bpm INTEGER DEFAULT NULL,
  p_duration_seconds INTEGER DEFAULT NULL,
  p_tuning TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL,
  p_youtube_links TEXT DEFAULT NULL,
  p_lyrics TEXT DEFAULT NULL,
  p_musical_key TEXT DEFAULT NULL
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
  v_before_bpm INTEGER;
  v_before_duration INTEGER;
  v_before_key TEXT;
  v_new_bpm INTEGER;
  v_new_duration INTEGER;
  v_new_key TEXT;
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

  -- Capture BEFORE values to determine field eligibility for verification
  SELECT bpm, duration_seconds, musical_key
  INTO v_before_bpm, v_before_duration, v_before_key
  FROM songs WHERE id = p_song_id;

  UPDATE songs
  SET
    bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END,
    duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END,
    tuning = COALESCE(p_tuning, tuning),
    notes = CASE WHEN p_notes IS NOT NULL THEN p_notes ELSE notes END,
    title = COALESCE(p_title, title),
    artist = COALESCE(p_artist, artist),
    youtube_links = CASE WHEN p_youtube_links IS NOT NULL THEN p_youtube_links ELSE youtube_links END,
    lyrics = CASE WHEN p_lyrics IS NOT NULL THEN p_lyrics ELSE lyrics END,
    musical_key = CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '') THEN p_musical_key ELSE musical_key END,
    updated_at = NOW()
  WHERE id = p_song_id
  RETURNING bpm, duration_seconds, musical_key INTO v_new_bpm, v_new_duration, v_new_key;

  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;

  -- Eligibility-aware verification: Only error if field WAS eligible for fill but value didn't persist
  -- Do NOT error if field was not eligible (already had value) - that's expected per fill-only CASE design

  -- BPM verification: eligible if before value was NULL
  IF p_bpm IS NOT NULL THEN
    IF v_before_bpm IS NULL THEN
      -- Field was eligible for fill, check if it actually updated
      IF v_new_bpm IS DISTINCT FROM p_bpm THEN
        RETURN json_build_object(
          'success', false, 
          'error', 'BPM update failed: requested ' || p_bpm || ', got ' || COALESCE(v_new_bpm::text, 'NULL')
        );
      END IF;
    END IF;
    -- If field was not eligible (already had value), skip verification (expected no-op)
  END IF;

  -- Duration verification: eligible if before value was 0
  IF p_duration_seconds IS NOT NULL THEN
    IF v_before_duration = 0 THEN
      -- Field was eligible for fill, check if it actually updated
      IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN
        RETURN json_build_object(
          'success', false, 
          'error', 'Duration update failed: requested ' || p_duration_seconds || ', got ' || COALESCE(v_new_duration::text, 'NULL')
        );
      END IF;
    END IF;
    -- If field was not eligible (already had value != 0), skip verification (expected no-op)
  END IF;

  -- Musical key verification: eligible if before value was NULL, empty, or whitespace-only
  IF p_musical_key IS NOT NULL THEN
    IF v_before_key IS NULL OR TRIM(v_before_key) = '' THEN
      -- Field was eligible for fill, check if it actually updated
      IF v_new_key IS DISTINCT FROM p_musical_key THEN
        RETURN json_build_object(
          'success', false, 
          'error', 'Musical key update failed: requested ' || p_musical_key || ', got ' || COALESCE(v_new_key, 'NULL')
        );
      END IF;
    END IF;
    -- If field was not eligible (already had non-empty value), skip verification (expected no-op)
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION update_song_metadata IS
  'Update song metadata including musical key and duration. BPM only updates when currently NULL. Duration only updates when currently 0 (non-overwrite). Musical key updates when NULL, empty, or whitespace-only. Uses RETURNING clause and eligibility-aware verification to detect genuine persistence failures while not erroring on expected no-ops per fill-only CASE design. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';
