-- Add p_allow_enrich_overwrite parameter to update_song_metadata.
-- When true, BPM and musical key can overwrite existing values (enrichment use case).
-- When false (default), BPM and musical key use fill-missing-only (manual edit use case).
-- Also fixes duration_seconds to always-overwrite for all callers (incorporates bug/song-duration-edit-silently-fails fix).

-- Drop the 11-param version (CRITICAL: prevents PGRST203 "Multiple function overloads exist")
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
    -- BPM: conditional (fill-missing-only OR enrichment-overwrite)
    bpm = CASE
      WHEN p_bpm IS NOT NULL AND (p_allow_enrich_overwrite OR bpm IS NULL)
      THEN p_bpm
      ELSE bpm
    END,

    -- Duration: always-overwrite (fixes bug/song-duration-edit-silently-fails)
    duration_seconds = COALESCE(p_duration_seconds, duration_seconds),

    -- Tuning: always-overwrite (unchanged from previous migration)
    tuning = COALESCE(p_tuning, tuning),

    -- Musical key: conditional (fill-missing-only OR enrichment-overwrite)
    musical_key = CASE
      WHEN p_musical_key IS NOT NULL AND (p_allow_enrich_overwrite OR musical_key IS NULL OR TRIM(musical_key) = '')
      THEN p_musical_key
      ELSE musical_key
    END,

    -- Other fields (unchanged from previous migration)
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

  -- Eligibility-aware verification

  -- BPM: verify if eligible (was NULL OR enrichment-overwrite)
  IF p_bpm IS NOT NULL THEN
    IF v_before_bpm IS NULL OR p_allow_enrich_overwrite THEN
      IF v_new_bpm IS DISTINCT FROM p_bpm THEN
        RETURN json_build_object(
          'success', false,
          'error', 'BPM update failed: requested ' || p_bpm || ', got ' || COALESCE(v_new_bpm::text, 'NULL')
        );
      END IF;
    END IF;
  END IF;

  -- Duration: always eligible (always-overwrite)
  IF p_duration_seconds IS NOT NULL THEN
    IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN
      RETURN json_build_object(
        'success', false,
        'error', 'Duration update failed: requested ' || p_duration_seconds || ', got ' || COALESCE(v_new_duration::text, 'NULL')
      );
    END IF;
  END IF;

  -- Musical key: verify if eligible (was NULL/empty OR enrichment-overwrite)
  IF p_musical_key IS NOT NULL THEN
    IF v_before_key IS NULL OR TRIM(v_before_key) = '' OR p_allow_enrich_overwrite THEN
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

REVOKE ALL ON FUNCTION update_song_metadata(p_song_id uuid, p_band_id uuid, p_bpm integer, p_duration_seconds integer, p_tuning text, p_notes text, p_title text, p_artist text, p_youtube_links text, p_lyrics text, p_musical_key text, p_allow_enrich_overwrite boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_song_metadata TO authenticated;

COMMENT ON FUNCTION update_song_metadata IS
  'Update song metadata. BPM and musical key: fill-missing-only by default, overwrite when p_allow_enrich_overwrite=true (enrichment use case). Duration: always-overwrite (fixes manual edit bug). Tuning: always-overwrite. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';
