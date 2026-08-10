-- Phase 2.3a: Enrichment Settings (Band-level enrichment preferences)
-- This migration creates the enrichment_settings table with RLS policies and RPC functions

-- Create enrichment_settings table
CREATE TABLE enrichment_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id UUID NOT NULL REFERENCES bands(id) ON DELETE CASCADE,
  new_song_behavior TEXT NOT NULL DEFAULT 'ask'
    CHECK (new_song_behavior IN ('ask', 'auto', 'off')),
  existing_song_behavior TEXT NOT NULL DEFAULT 'fill-missing-only'
    CHECK (existing_song_behavior IN ('fill-missing-only', 'auto-replace', 'show-diffs')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(band_id)
);

-- Create index for band_id lookups
CREATE INDEX idx_enrichment_settings_band_id ON enrichment_settings(band_id);

-- Enable Row Level Security
ALTER TABLE enrichment_settings ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Band members can view enrichment settings
CREATE POLICY "Band members can view enrichment settings" ON enrichment_settings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM band_members bm
      WHERE bm.band_id = enrichment_settings.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- RLS Policy: Band members can insert enrichment settings (needed for get_or_create RPC)
CREATE POLICY "Band members can insert enrichment settings" ON enrichment_settings
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM band_members bm
      WHERE bm.band_id = enrichment_settings.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- RLS Policy: Admins and members can update enrichment settings (contributors cannot)
CREATE POLICY "Admins and members can update enrichment settings" ON enrichment_settings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM band_members bm
      WHERE bm.band_id = enrichment_settings.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM band_members bm
      WHERE bm.band_id = enrichment_settings.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- RPC: Get or create enrichment settings (returns existing or creates default)
CREATE OR REPLACE FUNCTION get_or_create_enrichment_settings(p_band_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_settings JSONB;
BEGIN
  -- Try to get existing settings
  SELECT to_jsonb(enrichment_settings.*) INTO v_settings
  FROM enrichment_settings
  WHERE band_id = p_band_id;

  -- If no settings exist, create default
  IF v_settings IS NULL THEN
    INSERT INTO enrichment_settings (band_id)
    VALUES (p_band_id)
    RETURNING to_jsonb(enrichment_settings.*) INTO v_settings;
  END IF;

  RETURN v_settings;
END;
$$;

-- RPC: Update enrichment settings
CREATE OR REPLACE FUNCTION update_enrichment_settings(
  p_band_id UUID,
  p_new_song_behavior TEXT,
  p_existing_song_behavior TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_settings JSONB;
BEGIN
  -- Validate enum values
  IF p_new_song_behavior NOT IN ('ask', 'auto', 'off') THEN
    RAISE EXCEPTION 'Invalid new_song_behavior. Must be ask, auto, or off.';
  END IF;

  IF p_existing_song_behavior NOT IN ('fill-missing-only', 'auto-replace', 'show-diffs') THEN
    RAISE EXCEPTION 'Invalid existing_song_behavior. Must be fill-missing-only, auto-replace, or show-diffs.';
  END IF;

  -- Ensure settings exist
  PERFORM get_or_create_enrichment_settings(p_band_id);

  -- Update settings
  UPDATE enrichment_settings
  SET
    new_song_behavior = p_new_song_behavior,
    existing_song_behavior = p_existing_song_behavior,
    updated_at = now()
  WHERE band_id = p_band_id
  RETURNING to_jsonb(enrichment_settings.*) INTO v_settings;

  RETURN v_settings;
END;
$$;

-- Trigger: Update updated_at timestamp on enrichment_settings updates
CREATE TRIGGER update_enrichment_settings_updated_at
  BEFORE UPDATE ON enrichment_settings
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
