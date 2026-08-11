-- Constrain existing_song_behavior to fill-missing-only only.
-- Removes auto-replace and show-diffs as valid enum values.
-- Updates any bands currently set to auto-replace or show-diffs to fill-missing-only (safe default).

-- 1. Update existing rows that use deprecated values
UPDATE enrichment_settings
SET existing_song_behavior = 'fill-missing-only',
    updated_at = now()
WHERE existing_song_behavior IN ('auto-replace', 'show-diffs');

-- 2. Drop old CHECK constraint
ALTER TABLE enrichment_settings DROP CONSTRAINT IF EXISTS enrichment_settings_existing_song_behavior_check;

-- 3. Add new CHECK constraint (only one allowed value)
ALTER TABLE enrichment_settings ADD CONSTRAINT enrichment_settings_existing_song_behavior_check
  CHECK (existing_song_behavior = 'fill-missing-only');

COMMENT ON COLUMN enrichment_settings.existing_song_behavior IS
  'Existing-song enrichment behavior. Only fill-missing-only is allowed (enrichment never overwrites populated fields). Auto-replace and show-diffs removed in scope reduction (2026-08-11).';
