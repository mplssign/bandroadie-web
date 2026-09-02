-- Fix update_song_metadata: manual edits now always-write + set override flag (fixes Bug 2).
-- Enrichment respects bpm_manual_override / musical_key_manual_override (fixes Bug 1).
-- Fix clear_song_metadata: clearing a field also resets its override flag.

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
  p_musical_key TEXT DEFAULT NULL,
  p_allow_enrich_overwrite BOOLEAN DEFAULT FALSE
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
  v_before_bpm_override BOOLEAN;
  v_before_key_override BOOLEAN;
  v_bpm_write_eligible BOOLEAN;
  v_key_write_eligible BOOLEAN;
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

  -- Capture BEFORE values including override flags for eligibility check
  SELECT bpm, duration_seconds, musical_key, bpm_manual_override, musical_key_manual_override
  INTO v_before_bpm, v_before_duration, v_before_key, v_before_bpm_override, v_before_key_override
  FROM songs WHERE id = p_song_id;

  -- Manual edit (p_allow_enrich_overwrite=FALSE): always eligible (fixes Bug 2).
  -- Enrichment (p_allow_enrich_overwrite=TRUE): eligible only if not user-locked.
  v_bpm_write_eligible := p_bpm IS NOT NULL AND (
    NOT p_allow_enrich_overwrite
    OR NOT COALESCE(v_before_bpm_override, FALSE)
  );
  v_key_write_eligible := p_musical_key IS NOT NULL AND (
    NOT p_allow_enrich_overwrite
    OR NOT COALESCE(v_before_key_override, FALSE)
  );

  UPDATE songs
  SET
    bpm = CASE WHEN v_bpm_write_eligible THEN p_bpm ELSE bpm END,

    bpm_manual_override = CASE
      WHEN p_bpm IS NOT NULL AND NOT p_allow_enrich_overwrite THEN TRUE
      ELSE bpm_manual_override
    END,

    -- Duration: always-overwrite (unchanged)
    duration_seconds = COALESCE(p_duration_seconds, duration_seconds),

    -- Tuning: always-overwrite (unchanged)
    tuning = COALESCE(p_tuning, tuning),

    musical_key = CASE WHEN v_key_write_eligible THEN p_musical_key ELSE musical_key END,

    musical_key_manual_override = CASE
      WHEN p_musical_key IS NOT NULL AND NOT p_allow_enrich_overwrite THEN TRUE
      ELSE musical_key_manual_override
    END,

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

  IF p_bpm IS NOT NULL AND v_bpm_write_eligible THEN
    IF v_new_bpm IS DISTINCT FROM p_bpm THEN
      RETURN json_build_object('success', false, 'error',
        'BPM update failed: requested ' || p_bpm || ', got ' || COALESCE(v_new_bpm::text, 'NULL'));
    END IF;
  END IF;

  IF p_duration_seconds IS NOT NULL THEN
    IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN
      RETURN json_build_object('success', false, 'error',
        'Duration update failed: requested ' || p_duration_seconds || ', got ' || COALESCE(v_new_duration::text, 'NULL'));
    END IF;
  END IF;

  IF p_musical_key IS NOT NULL AND v_key_write_eligible THEN
    IF v_new_key IS DISTINCT FROM p_musical_key THEN
      RETURN json_build_object('success', false, 'error',
        'Musical key update failed: requested ' || p_musical_key || ', got ' || COALESCE(v_new_key, 'NULL'));
    END IF;
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION update_song_metadata(
  uuid, uuid, integer, integer, text, text, text, text, text, text, text, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_song_metadata(
  uuid, uuid, integer, integer, text, text, text, text, text, text, text, boolean
) TO authenticated;

COMMENT ON FUNCTION update_song_metadata IS
  'Update song metadata. Manual edit (p_allow_enrich_overwrite=FALSE): always writes BPM/key and sets override flag. Enrichment (p_allow_enrich_overwrite=TRUE): skips BPM/key if user-locked. Duration/tuning: always-overwrite. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';

-- ---------------------------------------------------------------------------

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
    bpm_manual_override = CASE WHEN p_clear_bpm THEN FALSE ELSE bpm_manual_override END,
    duration_seconds = CASE WHEN p_clear_duration THEN 0 ELSE duration_seconds END,
    tuning = CASE WHEN p_clear_tuning THEN NULL ELSE tuning END,
    musical_key = CASE WHEN p_clear_musical_key THEN NULL ELSE musical_key END,
    musical_key_manual_override = CASE WHEN p_clear_musical_key THEN FALSE ELSE musical_key_manual_override END,
    updated_at = NOW()
  WHERE id = p_song_id;

  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION clear_song_metadata(
  uuid, uuid, boolean, boolean, boolean, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION clear_song_metadata(
  uuid, uuid, boolean, boolean, boolean, boolean
) TO authenticated;

COMMENT ON FUNCTION clear_song_metadata IS
  'Clears selected song metadata fields and resets their override flags. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';
