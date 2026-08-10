-- Extend update_song_metadata RPC to support dual-value BPM/key/tuning.
-- Phase 2.2 of Song Data Enrichment initiative.
--
-- DESIGN RATIONALE (addresses Manager gate review findings):
-- All 6 new dual-value columns use COALESCE (always-overwrite when param provided).
-- This matches tuning's existing behavior and prevents the write-once bug that existed
-- for bpm/musical_key (where second edit was silent no-op).
--
-- Enrichment fill-missing-only semantics are handled in orchestrator (NULL-check before call),
-- NOT in RPC. This separation allows:
-- - Enrichment: check if source_bpm IS NULL in orchestrator, only call RPC if true
-- - Direct user edits: always call RPC, always overwrite (user intent is explicit)
--
-- OLD PARAMETERS (p_bpm, p_musical_key, p_tuning) are KEPT for backward compatibility.
-- 9 existing call sites in setlist_repository.dart continue working unchanged.
-- Old params continue writing to old columns during rollout (will be dropped in Phase 2.3+).

DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION update_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  -- OLD single-value parameters (kept for backward compat with 9 call sites)
  p_bpm INTEGER DEFAULT NULL,
  p_duration_seconds INTEGER DEFAULT NULL,
  p_tuning TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL,
  p_youtube_links TEXT DEFAULT NULL,
  p_lyrics TEXT DEFAULT NULL,
  p_musical_key TEXT DEFAULT NULL,
  -- NEW: Dual-value parameters (Phase 2.2) — all use COALESCE (always overwrite)
  p_source_bpm INTEGER DEFAULT NULL,
  p_performance_bpm INTEGER DEFAULT NULL,
  p_source_musical_key TEXT DEFAULT NULL,
  p_performance_musical_key TEXT DEFAULT NULL,
  p_source_tuning TEXT DEFAULT NULL,
  p_performance_tuning TEXT DEFAULT NULL
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

  -- Capture BEFORE values for eligibility-aware verification (old columns only)
  SELECT bpm, duration_seconds, musical_key
  INTO v_before_bpm, v_before_duration, v_before_key
  FROM songs WHERE id = p_song_id;

  UPDATE songs
  SET
    -- NEW: Dual-value BPM — COALESCE = always overwrites when parameter provided
    source_bpm = COALESCE(p_source_bpm, source_bpm),
    performance_bpm = COALESCE(p_performance_bpm, performance_bpm),

    -- NEW: Dual-value musical key — COALESCE = always overwrites
    source_musical_key = COALESCE(p_source_musical_key, source_musical_key),
    performance_musical_key = COALESCE(p_performance_musical_key, performance_musical_key),

    -- NEW: Dual-value tuning — COALESCE = always overwrites (matches existing tuning behavior)
    source_tuning = COALESCE(p_source_tuning, source_tuning),
    performance_tuning = COALESCE(p_performance_tuning, performance_tuning),

    -- OLD single-value columns: kept unchanged for backward compat during rollout
    -- (These retain their existing CASE/COALESCE logic from 20260801120000 migration)
    bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END,
    duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END,
    tuning = COALESCE(p_tuning, tuning),
    musical_key = CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '') THEN p_musical_key ELSE musical_key END,

    -- Other fields (unchanged from current prod RPC)
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

  -- Eligibility-aware verification for OLD columns only (keep existing logic from 20260801120000)
  -- New dual-value columns use COALESCE (no verification needed — always succeed or fail atomically)

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
  'Update song metadata including dual-value BPM/key/tuning (Phase 2.2). All dual-value params use COALESCE (always overwrite when provided). Enrichment fill-missing-only logic handled in orchestrator layer via NULL-checks. Old params (p_bpm, p_musical_key, p_tuning) kept for backward compat with 9 existing call sites. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';
