-- Revert update_song_metadata to pre-Phase-2.2 signature (11 params).
-- Removes 6 dual-value params added in 20260809120001.
-- Restores fill-missing-only CASE logic for bpm/musical_key (write-once behavior).
-- COALESCE for tuning (always-overwrite) is unchanged from pre-Phase-2.2 baseline.

-- Drop the 17-param Phase 2.2 version (CRITICAL: must match exact production signature)
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT);

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

  -- Capture BEFORE values for eligibility-aware verification
  SELECT bpm, duration_seconds, musical_key
  INTO v_before_bpm, v_before_duration, v_before_key
  FROM songs WHERE id = p_song_id;

  UPDATE songs
  SET
    -- BPM: fill-missing-only (CASE — only updates when currently NULL)
    bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END,

    -- Duration: fill-missing-only (CASE — only updates when currently 0)
    duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0
                            THEN p_duration_seconds ELSE duration_seconds END,

    -- Tuning: always-overwrite (COALESCE — matches pre-Phase-2.2 baseline)
    tuning = COALESCE(p_tuning, tuning),

    -- Musical key: fill-missing-only (CASE — only updates when NULL or empty)
    musical_key = CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '')
                       THEN p_musical_key ELSE musical_key END,

    -- Other fields (unchanged from pre-Phase-2.2)
    notes = CASE WHEN p_notes IS NOT NULL THEN p_notes ELSE notes END,
    title = COALESCE(p_title, title),
    artist = COALESCE(p_artist, artist),
    youtube_links = CASE WHEN p_youtube_links IS NOT NULL THEN p_youtube_links ELSE youtube_links END,
    lyrics = CASE WHEN p_lyrics IS NOT NULL THEN p_lyrics ELSE lyrics END,

    updated_at = NOW()
  WHERE id = p_song_id
  RETURNING bpm, duration_seconds, musical_key INTO v_new_bpm, v_new_duration, v_new_key;

  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;

  -- Eligibility-aware verification (copied from 20260801120000)

  IF p_bpm IS NOT NULL THEN
    IF v_before_bpm IS NULL THEN
      IF v_new_bpm IS DISTINCT FROM p_bpm THEN
        RETURN json_build_object(
          'success', false,
          'error', 'BPM update failed: requested ' || p_bpm || ', got ' || COALESCE(v_new_bpm::text, 'NULL')
        );
      END IF;
    END IF;
  END IF;

  IF p_duration_seconds IS NOT NULL THEN
    IF v_before_duration = 0 THEN
      IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN
        RETURN json_build_object(
          'success', false,
          'error', 'Duration update failed: requested ' || p_duration_seconds || ', got ' || COALESCE(v_new_duration::text, 'NULL')
        );
      END IF;
    END IF;
  END IF;

  IF p_musical_key IS NOT NULL THEN
    IF v_before_key IS NULL OR TRIM(v_before_key) = '' THEN
      IF v_new_key IS DISTINCT FROM p_musical_key THEN
        RETURN json_build_object(
          'success', false,
          'error', 'Musical key update failed: requested ' || p_musical_key || ', got ' || COALESCE(v_new_key, 'NULL')
        );
      END IF;
    END IF;
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION update_song_metadata TO authenticated;

COMMENT ON FUNCTION update_song_metadata IS
  'Update song metadata. BPM and musical key use fill-missing-only (write-once). Tuning uses always-overwrite. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id. Reverted from Phase 2.2 dual-value signature.';
