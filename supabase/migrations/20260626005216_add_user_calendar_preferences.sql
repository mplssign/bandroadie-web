-- Migration: Add user calendar preferences for One Calendar feature
-- Enables users to share block-out dates across multiple bands

-- Create user_calendar_preferences table
CREATE TABLE user_calendar_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  one_calendar_enabled BOOLEAN NOT NULL DEFAULT true,
  apply_to_mode TEXT NOT NULL DEFAULT 'all_bands' CHECK (apply_to_mode IN ('all_bands', 'selected_bands')),
  selected_band_ids UUID[] DEFAULT '{}',
  auto_block_conflicts_enabled BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE user_calendar_preferences ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only access their own preferences
CREATE POLICY "Users can view their own calendar preferences"
  ON user_calendar_preferences
  FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert their own calendar preferences"
  ON user_calendar_preferences
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own calendar preferences"
  ON user_calendar_preferences
  FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- No DELETE policy - preferences persist

-- RPC: Get or create calendar preferences (returns existing or creates default)
CREATE OR REPLACE FUNCTION get_or_create_calendar_preferences(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_prefs JSONB;
BEGIN
  -- Try to get existing preferences
  SELECT to_jsonb(user_calendar_preferences.*) INTO v_prefs
  FROM user_calendar_preferences
  WHERE user_id = p_user_id;

  -- If no preferences exist, create default
  IF v_prefs IS NULL THEN
    INSERT INTO user_calendar_preferences (user_id)
    VALUES (p_user_id)
    RETURNING to_jsonb(user_calendar_preferences.*) INTO v_prefs;
  END IF;

  RETURN v_prefs;
END;
$$;

-- RPC: Update calendar preferences
CREATE OR REPLACE FUNCTION update_calendar_preferences(
  p_user_id UUID,
  p_one_calendar_enabled BOOLEAN,
  p_apply_to_mode TEXT,
  p_selected_band_ids UUID[],
  p_auto_block_conflicts_enabled BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_prefs JSONB;
BEGIN
  -- Validate apply_to_mode
  IF p_apply_to_mode NOT IN ('all_bands', 'selected_bands') THEN
    RAISE EXCEPTION 'Invalid apply_to_mode. Must be all_bands or selected_bands.';
  END IF;

  -- Ensure preferences exist
  PERFORM get_or_create_calendar_preferences(p_user_id);

  -- Update preferences
  UPDATE user_calendar_preferences
  SET
    one_calendar_enabled = p_one_calendar_enabled,
    apply_to_mode = p_apply_to_mode,
    selected_band_ids = p_selected_band_ids,
    auto_block_conflicts_enabled = p_auto_block_conflicts_enabled,
    updated_at = now()
  WHERE user_id = p_user_id
  RETURNING to_jsonb(user_calendar_preferences.*) INTO v_prefs;

  RETURN v_prefs;
END;
$$;

-- Trigger: Update updated_at timestamp
CREATE TRIGGER update_user_calendar_preferences_updated_at
  BEFORE UPDATE ON user_calendar_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Create indexes for performance
CREATE INDEX idx_user_calendar_preferences_user_id ON user_calendar_preferences(user_id);
