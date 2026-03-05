-- Migration: Band-Scoped Calendar Subscriptions
-- Date: 2026-03-05
-- Feature: band-scoped-calendar-feed
--
-- Creates band_calendar_subscriptions table for per-band calendar tokens,
-- adds timezone column to bands, and creates RPC functions.

-- ==========================================================================
-- 1. New table: band_calendar_subscriptions
-- ==========================================================================

CREATE TABLE band_calendar_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    band_id UUID NOT NULL REFERENCES bands(id) ON DELETE CASCADE,
    token UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, band_id)
);

CREATE INDEX idx_band_calendar_subs_token ON band_calendar_subscriptions(token);

-- ==========================================================================
-- 2. RLS on band_calendar_subscriptions
-- ==========================================================================

ALTER TABLE band_calendar_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own calendar subscriptions"
    ON band_calendar_subscriptions
    FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- ==========================================================================
-- 3. Add timezone column to bands
-- ==========================================================================

ALTER TABLE bands ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'America/Chicago';

-- ==========================================================================
-- 4. RPC: get_band_calendar_token(p_band_id UUID)
-- ==========================================================================

CREATE OR REPLACE FUNCTION get_band_calendar_token(p_band_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_token UUID;
BEGIN
    -- Get the current user
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Verify user is a member of the band
    IF NOT EXISTS (
        SELECT 1 FROM band_members
        WHERE band_id = p_band_id AND user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Not a member of this band';
    END IF;

    -- Return existing token if one exists
    SELECT token INTO v_token
    FROM band_calendar_subscriptions
    WHERE user_id = v_user_id AND band_id = p_band_id;

    IF v_token IS NOT NULL THEN
        RETURN v_token;
    END IF;

    -- Create new subscription and return token
    INSERT INTO band_calendar_subscriptions (user_id, band_id)
    VALUES (v_user_id, p_band_id)
    RETURNING token INTO v_token;

    RETURN v_token;
END;
$$;

-- ==========================================================================
-- 5. RPC: regenerate_band_calendar_token(p_band_id UUID)
-- ==========================================================================

CREATE OR REPLACE FUNCTION regenerate_band_calendar_token(p_band_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_token UUID;
BEGIN
    -- Get the current user
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Verify user is a member of the band
    IF NOT EXISTS (
        SELECT 1 FROM band_members
        WHERE band_id = p_band_id AND user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'Not a member of this band';
    END IF;

    -- Update existing token or insert new one
    INSERT INTO band_calendar_subscriptions (user_id, band_id, token)
    VALUES (v_user_id, p_band_id, gen_random_uuid())
    ON CONFLICT (user_id, band_id)
    DO UPDATE SET token = gen_random_uuid()
    RETURNING token INTO v_token;

    RETURN v_token;
END;
$$;
