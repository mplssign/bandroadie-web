-- migrate_lyrics_to_chordpro.sql
-- One-time data migration: Convert songs.lyrics from JSON (LyricsData) to plain-text ChordPro
--
-- LOSSY CONVERSION (Tony-approved 2026-08-10):
-- - Extracts block[].text fields from JSON
-- - Concatenates blocks with double-newline separators
-- - Discards highlight, fontSize, isBold, defaultFontSize, defaultBold metadata
--
-- PRE-FLIGHT:
-- 1. Backup songs table: pg_dump or Supabase dashboard export
-- 2. Run on staging first, inspect sample outputs
-- 3. Confirm affected row count matches expectation (~325 songs as of 2026-08-10)
--
-- EXECUTION:
-- psql -h <db-host> -U postgres -d postgres -f migrate_lyrics_to_chordpro.sql
--
-- POST-FLIGHT:
-- 1. Verify no NULL lyrics for songs that had JSON before
-- 2. Spot-check 5-10 random songs for text accuracy (no truncation, line breaks preserved)

BEGIN;

-- Create a temporary backup table (optional, for rollback within session)
CREATE TEMP TABLE lyrics_backup AS
SELECT id, lyrics
FROM songs
WHERE lyrics IS NOT NULL;

-- Log pre-migration stats
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM songs WHERE lyrics IS NOT NULL;
  RAISE NOTICE 'Pre-migration: % songs with non-null lyrics', v_count;
END $$;

-- Main migration: Parse JSON, extract text, concatenate, write back
UPDATE songs
SET lyrics = (
  SELECT string_agg(block_text, E'\n\n')
  FROM (
    SELECT jsonb_array_elements(lyrics_json->'blocks')->>'text' AS block_text
    FROM (
      SELECT lyrics::jsonb AS lyrics_json
    ) parsed
  ) blocks
)
WHERE lyrics IS NOT NULL
  AND lyrics != ''
  AND lyrics::jsonb ? 'blocks'; -- Only convert valid LyricsData JSON

-- Log post-migration stats
DO $$
DECLARE
  v_count INTEGER;
  v_null_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM songs WHERE lyrics IS NOT NULL;
  SELECT COUNT(*) INTO v_null_count FROM lyrics_backup lb
    WHERE NOT EXISTS (
      SELECT 1 FROM songs s WHERE s.id = lb.id AND s.lyrics IS NOT NULL
    );
  RAISE NOTICE 'Post-migration: % songs with non-null lyrics', v_count;
  IF v_null_count > 0 THEN
    RAISE WARNING '% songs lost lyrics (JSON parse failures)', v_null_count;
  END IF;
END $$;

-- Sample output for manual inspection (first 3 converted songs)
DO $$
DECLARE
  r RECORD;
BEGIN
  RAISE NOTICE 'Sample conversions (first 3 songs):';
  FOR r IN
    SELECT s.id, s.title, s.artist, lb.lyrics AS old_lyrics, s.lyrics AS new_lyrics
    FROM songs s
    JOIN lyrics_backup lb ON lb.id = s.id
    WHERE s.lyrics IS NOT NULL
    LIMIT 3
  LOOP
    RAISE NOTICE 'Song: % by %', r.title, r.artist;
    RAISE NOTICE 'Old JSON: %', left(r.old_lyrics, 200);
    RAISE NOTICE 'New Text: %', left(r.new_lyrics, 200);
    RAISE NOTICE '---';
  END LOOP;
END $$;

COMMIT;

-- Post-migration validation query (run separately after COMMIT)
-- Confirms no songs lost lyrics unexpectedly
-- Example:
-- SELECT
--   COUNT(*) FILTER (WHERE lyrics IS NOT NULL) AS songs_with_lyrics,
--   COUNT(*) FILTER (WHERE lyrics IS NULL) AS songs_without_lyrics,
--   COUNT(*) FILTER (WHERE lyrics ~ '\[.+\]') AS songs_with_chords -- Expect 0 immediately after migration
-- FROM songs;
