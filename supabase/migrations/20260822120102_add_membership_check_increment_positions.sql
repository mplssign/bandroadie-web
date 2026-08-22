-- ===========================================================================
-- Migration: Add membership check to increment_setlist_positions
-- Description: Adds auth.uid() + band_members authorization check to prevent
--              cross-tenant data tampering via increment_setlist_positions RPC
-- Feature: bug/setlist-rpc-missing-membership-check
-- Date: 2026-08-22
-- Engineer Note: Using reference body captured 2026-08-22 as current production
--                 state (verified no substantive drift since capture)
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.increment_setlist_positions(p_setlist_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  v_band_id UUID;
BEGIN
  -- ===========================================================================
  -- AUTHORIZATION CHECK (added 2026-08-22)
  -- ===========================================================================
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT band_id INTO v_band_id FROM setlists WHERE id = p_setlist_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Setlist not found';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = v_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Access denied: not an active member of this band';
  END IF;

  -- ===========================================================================
  -- EXISTING LOGIC (unchanged below this point)
  -- ===========================================================================
  UPDATE public.setlist_songs
    SET position = position + 1
  WHERE setlist_id = p_setlist_id;
END;
$function$;

-- ===========================================================================
-- ROLLBACK (restore function body without authorization check)
-- To rollback: uncomment and run the following
-- ===========================================================================
/*
DROP FUNCTION IF EXISTS increment_setlist_positions(UUID);

CREATE OR REPLACE FUNCTION public.increment_setlist_positions(p_setlist_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.setlist_songs
    SET position = position + 1
  WHERE setlist_id = p_setlist_id;
END;
$function$;
*/
