-- Migration: Potential Events in Calendar Feed
-- Date: 2026-05-24
--
-- Adds per-user opt-in columns so subscribers can include potential gigs
-- and potential rehearsals in their calendar feed.
-- Defaults: both OFF (existing behaviour is preserved for all current subscribers).

-- ==========================================================================
-- 1. Add columns
-- ==========================================================================

ALTER TABLE band_calendar_subscriptions
    ADD COLUMN IF NOT EXISTS include_potential_gigs        BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS include_potential_rehearsals  BOOLEAN NOT NULL DEFAULT false;

-- ==========================================================================
-- 2. Replace RPC to accept the two new params
-- ==========================================================================

CREATE OR REPLACE FUNCTION update_band_calendar_preferences(
    p_band_id                    UUID,
    p_include_gigs               BOOLEAN,
    p_include_rehearsals         BOOLEAN,
    p_include_blockouts          BOOLEAN,
    p_include_potential_gigs     BOOLEAN DEFAULT false,
    p_include_potential_rehearsals BOOLEAN DEFAULT false
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
        include_gigs                   = p_include_gigs,
        include_rehearsals             = p_include_rehearsals,
        include_blockouts              = p_include_blockouts,
        include_potential_gigs         = p_include_potential_gigs,
        include_potential_rehearsals   = p_include_potential_rehearsals
    WHERE user_id = v_user_id AND band_id = p_band_id;
END;
$$;
