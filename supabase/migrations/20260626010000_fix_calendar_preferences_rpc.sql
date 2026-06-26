-- Fix: Update calendar preferences RPC functions to match notification preferences pattern
-- Changes:
-- 1. Remove p_user_id parameter, use auth.uid() directly
-- 2. Change SECURITY INVOKER to SECURITY DEFINER
-- 3. This prevents RLS issues and matches the established codebase pattern

-- Drop existing functions
DROP FUNCTION IF EXISTS get_or_create_calendar_preferences(UUID);
DROP FUNCTION IF EXISTS update_calendar_preferences(UUID, BOOLEAN, TEXT, UUID[], BOOLEAN);

-- Recreated RPC: Get or create calendar preferences (no parameters, uses auth.uid())
CREATE OR REPLACE FUNCTION get_or_create_calendar_preferences()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefs JSONB;
  v_user_id UUID;
BEGIN
  -- Get current user ID
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User not authenticated';
  END IF;
  
  -- Try to get existing preferences
  SELECT to_jsonb(user_calendar_preferences.*) INTO v_prefs
  FROM user_calendar_preferences
  WHERE user_id = v_user_id;

  -- If no preferences exist, create default
  IF v_prefs IS NULL THEN
    INSERT INTO user_calendar_preferences (user_id)
    VALUES (v_user_id)
    RETURNING to_jsonb(user_calendar_preferences.*) INTO v_prefs;
  END IF;

  RETURN v_prefs;
END;
$$;

-- Recreated RPC: Update calendar preferences (no p_user_id parameter, uses auth.uid())
CREATE OR REPLACE FUNCTION update_calendar_preferences(
  p_one_calendar_enabled BOOLEAN,
  p_apply_to_mode TEXT,
  p_selected_band_ids UUID[],
  p_auto_block_conflicts_enabled BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefs JSONB;
  v_user_id UUID;
BEGIN
  -- Get current user ID
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User not authenticated';
  END IF;
  
  -- Validate apply_to_mode
  IF p_apply_to_mode NOT IN ('all_bands', 'selected_bands') THEN
    RAISE EXCEPTION 'Invalid apply_to_mode. Must be all_bands or selected_bands.';
  END IF;

  -- Ensure preferences exist (call get_or_create)
  PERFORM get_or_create_calendar_preferences();

  -- Update preferences
  UPDATE user_calendar_preferences
  SET
    one_calendar_enabled = p_one_calendar_enabled,
    apply_to_mode = p_apply_to_mode,
    selected_band_ids = p_selected_band_ids,
    auto_block_conflicts_enabled = p_auto_block_conflicts_enabled,
    updated_at = now()
  WHERE user_id = v_user_id
  RETURNING to_jsonb(user_calendar_preferences.*) INTO v_prefs;

  RETURN v_prefs;
END;
$$;
