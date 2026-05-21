-- ============================================================================
-- MIGRATION: Add Multi-Date Support for Potential Rehearsals
--
-- Purpose: Enable potential rehearsals to have multiple dates (mirrors gig_dates)
--
-- Changes:
-- 1. Create rehearsal_dates table
-- 2. Add RLS policies for rehearsal_dates
-- 3. Add rehearsal_date_id column to rehearsal_responses
-- 4. Update unique constraint on rehearsal_responses
-- 5. Add updated_at trigger for rehearsal_dates
-- 6. Add table/column comments
-- 7. Update get_band_full_state RPC to include rehearsal_dates
-- ============================================================================

-- =============================================================================
-- PHASE 1: Create rehearsal_dates table
-- =============================================================================

CREATE TABLE public.rehearsal_dates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rehearsal_id UUID NOT NULL REFERENCES public.rehearsals(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for efficient lookups by rehearsal_id
CREATE INDEX idx_rehearsal_dates_rehearsal_id ON public.rehearsal_dates(rehearsal_id);

-- =============================================================================
-- PHASE 2: Add RLS policies for rehearsal_dates
-- =============================================================================

ALTER TABLE public.rehearsal_dates ENABLE ROW LEVEL SECURITY;

-- Band members can view rehearsal dates
CREATE POLICY "Band members can view rehearsal dates"
  ON public.rehearsal_dates FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM public.rehearsals r
    JOIN public.band_members bm ON bm.band_id = r.band_id
    WHERE r.id = rehearsal_dates.rehearsal_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
  ));

-- Band members can insert rehearsal dates
CREATE POLICY "Band members can insert rehearsal dates"
  ON public.rehearsal_dates FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.rehearsals r
    JOIN public.band_members bm ON bm.band_id = r.band_id
    WHERE r.id = rehearsal_dates.rehearsal_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
  ));

-- Band members can delete rehearsal dates
CREATE POLICY "Band members can delete rehearsal dates"
  ON public.rehearsal_dates FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM public.rehearsals r
    JOIN public.band_members bm ON bm.band_id = r.band_id
    WHERE r.id = rehearsal_dates.rehearsal_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
  ));

-- =============================================================================
-- PHASE 3: Add rehearsal_date_id column to rehearsal_responses
-- =============================================================================

ALTER TABLE public.rehearsal_responses
ADD COLUMN rehearsal_date_id UUID REFERENCES public.rehearsal_dates(id) ON DELETE CASCADE;

-- =============================================================================
-- PHASE 4: Update unique constraint on rehearsal_responses
-- =============================================================================

-- Drop old constraint if it exists
DROP INDEX IF EXISTS rehearsal_responses_rehearsal_user_unique;

-- Create new unique constraint that allows one response per user per date
-- NULL rehearsal_date_id represents the primary date
CREATE UNIQUE INDEX rehearsal_responses_rehearsal_user_date_unique
ON public.rehearsal_responses (
  rehearsal_id, 
  user_id, 
  COALESCE(rehearsal_date_id, '00000000-0000-0000-0000-000000000000'::uuid)
);

-- =============================================================================
-- PHASE 5: Add updated_at trigger for rehearsal_dates
-- =============================================================================

-- Create trigger to auto-update updated_at timestamp
CREATE TRIGGER set_rehearsal_dates_updated_at
  BEFORE UPDATE ON public.rehearsal_dates
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- PHASE 6: Add table and column comments
-- =============================================================================

COMMENT ON TABLE public.rehearsal_dates IS 
'Additional dates for multi-date potential rehearsals. Only potential rehearsals can have multiple dates. The primary date is stored in rehearsals.date.';

COMMENT ON COLUMN public.rehearsal_dates.rehearsal_id IS 
'Foreign key to the parent rehearsal. Cascades on delete.';

COMMENT ON COLUMN public.rehearsal_dates.date IS 
'Additional date for this multi-date potential rehearsal.';

COMMENT ON COLUMN public.rehearsal_responses.rehearsal_date_id IS 
'Links response to a specific date for multi-date rehearsals. NULL = response is for the primary date (rehearsals.date).';

COMMENT ON INDEX rehearsal_responses_rehearsal_user_date_unique IS 
'Ensures one response per user per date. NULL rehearsal_date_id represents the primary date.';

-- =============================================================================
-- PHASE 7: Update get_band_full_state RPC to include rehearsal_dates
-- =============================================================================

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
  -- =========================================
  -- BAND MEMBERSHIP CHECK — defense in depth
  -- RLS also enforces this, but we fail fast
  -- =========================================
  IF NOT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Access denied: user is not a member of this band';
  END IF;

  -- Fetch band record
  SELECT row_to_json(b.*)::jsonb INTO band_record
  FROM bands b
  WHERE b.id = p_band_id;

  IF band_record IS NULL THEN
    RAISE EXCEPTION 'Band not found: %', p_band_id;
  END IF;

  -- Fetch band members (only active/invited — matches MembersRepository filter)
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

  -- Fetch gigs with nested gig_dates for multi-date support
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

  -- Fetch rehearsals with nested rehearsal_dates for multi-date support
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

  -- Fetch setlists with computed song counts
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

  -- Build final response
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
'Returns all band-scoped data in a single call. Updated to include rehearsal_dates for multi-date support.';
