-- ============================================================================
-- BATCH 6: Revoke anon/PUBLIC execute from song and setlist management functions
-- ============================================================================
-- Feature: security-definer-revoke-public
-- Issue: PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION
-- Risk: Anon role can call song and setlist management functions
-- Fix: Explicit revoke from PUBLIC and anon, re-grant to authenticated
-- 
-- SAFETY: All functions have internal auth.uid() checks and verify band membership
-- before mutating. Revoking anon access aligns grants with actual authenticated usage.
-- ============================================================================

-- Song management function 1: bulk_add_songs_to_setlist
REVOKE ALL ON FUNCTION bulk_add_songs_to_setlist(p_band_id uuid, p_setlist_id uuid, p_song_ids uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION bulk_add_songs_to_setlist(p_band_id uuid, p_setlist_id uuid, p_song_ids uuid[]) TO authenticated;

-- Song management function 2: clear_song_metadata
REVOKE ALL ON FUNCTION clear_song_metadata(p_song_id uuid, p_band_id uuid, p_clear_bpm boolean, p_clear_duration boolean, p_clear_tuning boolean, p_clear_musical_key boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION clear_song_metadata(p_song_id uuid, p_band_id uuid, p_clear_bpm boolean, p_clear_duration boolean, p_clear_tuning boolean, p_clear_musical_key boolean) TO authenticated;

-- Song management function 3: delete_song_from_catalog
REVOKE ALL ON FUNCTION delete_song_from_catalog(p_band_id uuid, p_song_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_song_from_catalog(p_band_id uuid, p_song_id uuid) TO authenticated;

-- Song management function 4: delete_song_from_setlist
REVOKE ALL ON FUNCTION delete_song_from_setlist(p_setlist_id uuid, p_song_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_song_from_setlist(p_setlist_id uuid, p_song_id uuid) TO authenticated;

-- Song management function 5: move_song_between_setlists
REVOKE ALL ON FUNCTION move_song_between_setlists(p_source_setlist_id uuid, p_target_setlist_id uuid, p_song_id uuid, p_band_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION move_song_between_setlists(p_source_setlist_id uuid, p_target_setlist_id uuid, p_song_id uuid, p_band_id uuid) TO authenticated;

-- Song management function 6: update_song_metadata
REVOKE ALL ON FUNCTION update_song_metadata(p_song_id uuid, p_band_id uuid, p_bpm integer, p_duration_seconds integer, p_tuning text, p_notes text, p_title text, p_artist text, p_youtube_links text, p_lyrics text, p_musical_key text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_song_metadata(p_song_id uuid, p_band_id uuid, p_bpm integer, p_duration_seconds integer, p_tuning text, p_notes text, p_title text, p_artist text, p_youtube_links text, p_lyrics text, p_musical_key text) TO authenticated;

-- Setlist management function 1: delete_setlist
REVOKE ALL ON FUNCTION delete_setlist(p_band_id uuid, p_setlist_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION delete_setlist(p_band_id uuid, p_setlist_id uuid) TO authenticated;

-- Setlist management function 2: reorder_setlists
REVOKE ALL ON FUNCTION reorder_setlists(p_band_id uuid, p_setlist_ids uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION reorder_setlists(p_band_id uuid, p_setlist_ids uuid[]) TO authenticated;

-- ===========================================================================
-- ROLLBACK (restore exact pre-migration ACL state from PRE_MIGRATION_ACL_STATE.md)
-- ===========================================================================
-- All 8 functions had PUBLIC grant in pre-migration state.
--
-- To rollback:
--
-- GRANT EXECUTE ON FUNCTION bulk_add_songs_to_setlist(p_band_id uuid, p_setlist_id uuid, p_song_ids uuid[]) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION clear_song_metadata(p_song_id uuid, p_band_id uuid, p_clear_bpm boolean, p_clear_duration boolean, p_clear_tuning boolean, p_clear_musical_key boolean) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION delete_song_from_catalog(p_band_id uuid, p_song_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION delete_song_from_setlist(p_setlist_id uuid, p_song_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION move_song_between_setlists(p_source_setlist_id uuid, p_target_setlist_id uuid, p_song_id uuid, p_band_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION update_song_metadata(p_song_id uuid, p_band_id uuid, p_bpm integer, p_duration_seconds integer, p_tuning text, p_notes text, p_title text, p_artist text, p_youtube_links text, p_lyrics text, p_musical_key text) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION delete_setlist(p_band_id uuid, p_setlist_id uuid) TO PUBLIC;
-- GRANT EXECUTE ON FUNCTION reorder_setlists(p_band_id uuid, p_setlist_ids uuid[]) TO PUBLIC;
