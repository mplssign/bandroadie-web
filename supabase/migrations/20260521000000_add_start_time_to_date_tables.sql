-- ============================================================================
-- MIGRATION: Add start_time to gig_dates and rehearsal_dates
--
-- Purpose: Each candidate date in a multi-date potential gig/rehearsal
--   can now have its own start time, separate from the parent event's
--   start_time.  NULL means "inherit the parent event's start_time"
--   (backward-compatible default).
--
-- Changes:
--   1. Add nullable start_time TEXT to gig_dates
--   2. Add nullable start_time TEXT to rehearsal_dates
--   3. Update get_band_full_state RPC to surface start_time in both
-- ============================================================================

-- 1. gig_dates
ALTER TABLE public.gig_dates
  ADD COLUMN IF NOT EXISTS start_time TEXT;

COMMENT ON COLUMN public.gig_dates.start_time IS
'Optional start time for this specific candidate date (e.g. "7:00 PM"). '
'NULL = inherit the parent gig''s start_time.';

-- 2. rehearsal_dates
ALTER TABLE public.rehearsal_dates
  ADD COLUMN IF NOT EXISTS start_time TEXT;

COMMENT ON COLUMN public.rehearsal_dates.start_time IS
'Optional start time for this specific candidate date (e.g. "7:00 PM"). '
'NULL = inherit the parent rehearsal''s start_time.';

-- 3. Update get_band_full_state to surface start_time in nested date objects
CREATE OR REPLACE FUNCTION get_band_full_state(p_band_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  result jsonb;
  band_record jsonb;
  members_arr jsonb;
  gigs_arr jsonb;
  rehearsals_arr jsonb;
  setlists_arr jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Access denied: user is not a member of this band';
  END IF;

  SELECT row_to_json(b.*)::jsonb INTO band_record
  FROM bands b
  WHERE b.id = p_band_id;

  IF band_record IS NULL THEN
    RAISE EXCEPTION 'Band not found: %', p_band_id;
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', bm.id,
      'band_id', bm.band_id,
      'user_id', bm.user_id,
      'role', bm.role,
      'joined_at', bm.joined_at
    )
  ), '[]'::jsonb) INTO members_arr
  FROM band_members bm
  WHERE bm.band_id = p_band_id
    AND bm.status IN ('active', 'invited');

  -- Gigs with nested gig_dates (now includes start_time)
  SELECT COALESCE(jsonb_agg(gig_row ORDER BY gig_row->>'date'), '[]'::jsonb)
  INTO gigs_arr
  FROM (
    SELECT to_jsonb(g.*) || jsonb_build_object(
      'gig_dates', COALESCE(
        (SELECT jsonb_agg(
          jsonb_build_object(
            'id', gd.id,
            'gig_id', gd.gig_id,
            'date', gd.date,
            'start_time', gd.start_time,
            'created_at', gd.created_at,
            'updated_at', gd.updated_at
          ) ORDER BY gd.date
        ) FROM gig_dates gd WHERE gd.gig_id = g.id),
        '[]'::jsonb
      )
    ) AS gig_row
    FROM gigs g
    WHERE g.band_id = p_band_id
  ) sub;

  -- Rehearsals with nested rehearsal_dates (now includes start_time)
  SELECT COALESCE(jsonb_agg(rehearsal_row ORDER BY rehearsal_row->>'date'), '[]'::jsonb)
  INTO rehearsals_arr
  FROM (
    SELECT to_jsonb(r.*) || jsonb_build_object(
      'rehearsal_dates', COALESCE(
        (SELECT jsonb_agg(
          jsonb_build_object(
            'id', rd.id,
            'rehearsal_id', rd.rehearsal_id,
            'date', rd.date,
            'start_time', rd.start_time,
            'created_at', rd.created_at,
            'updated_at', rd.updated_at
          ) ORDER BY rd.date
        ) FROM rehearsal_dates rd WHERE rd.rehearsal_id = r.id),
        '[]'::jsonb
      )
    ) AS rehearsal_row
    FROM rehearsals r
    WHERE r.band_id = p_band_id
  ) sub;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'name', s.name,
      'band_id', s.band_id,
      'total_duration', s.total_duration,
      'is_catalog', s.is_catalog,
      'position', s.position,
      'created_at', s.created_at,
      'updated_at', s.updated_at,
      'song_count', (SELECT count(*) FROM setlist_songs ss WHERE ss.setlist_id = s.id)
    ) ORDER BY s.position, s.name
  ), '[]'::jsonb) INTO setlists_arr
  FROM setlists s
  WHERE s.band_id = p_band_id;

  result := jsonb_build_object(
    'band', band_record,
    'members', members_arr,
    'gigs', gigs_arr,
    'rehearsals', rehearsals_arr,
    'setlists', setlists_arr
  );

  RETURN result;
END;
$$;

COMMENT ON FUNCTION get_band_full_state(uuid) IS
'Returns all band-scoped data in a single call. Updated to include start_time in gig_dates and rehearsal_dates.';
