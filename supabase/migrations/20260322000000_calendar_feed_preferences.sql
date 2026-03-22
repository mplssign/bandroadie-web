-- Migration: Calendar Feed Preferences
-- Date: 2026-03-22
--
-- Adds per-user feed preference columns to band_calendar_subscriptions so
-- each subscriber can control what event types appear in their calendar feed.
-- Defaults: gigs ON, rehearsals ON, block-out days OFF.
-- Potential gigs are excluded from the feed unconditionally (handled in edge function).

-- ==========================================================================
-- 1. Add preference columns to band_calendar_subscriptions
-- ==========================================================================

ALTER TABLE band_calendar_subscriptions
    ADD COLUMN IF NOT EXISTS include_gigs        BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS include_rehearsals  BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS include_blockouts   BOOLEAN NOT NULL DEFAULT false;

-- ==========================================================================
-- 2. RPC: update_band_calendar_preferences
-- ==========================================================================

CREATE OR REPLACE FUNCTION update_band_calendar_preferences(
    p_band_id           UUID,
    p_include_gigs      BOOLEAN,
    p_include_rehearsals BOOLEAN,
    p_include_blockouts BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Verify user is a band member
    IF NOT EXISTS (
        SELECT 1 FROM band_members
        WHERE band_id = p_band_id AND user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Not a member of this band';
    END IF;

    -- Auto-create the subscription row if it doesn't exist yet
    PERFORM get_band_calendar_token(p_band_id);

    UPDATE band_calendar_subscriptions
    SET
        include_gigs        = p_include_gigs,
        include_rehearsals  = p_include_rehearsals,
        include_blockouts   = p_include_blockouts
    WHERE user_id = v_user_id AND band_id = p_band_id;
END;
$$;
