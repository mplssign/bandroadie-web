-- ============================================================================
-- RPC: get_band_full_state
-- Returns all band-scoped data in a single database call.
--
-- Combines: band, members, gigs (with gig_dates), rehearsals, setlists
-- into one structured JSONB response to eliminate multiple HTTP round-trips.
--
-- SECURITY: Uses SECURITY INVOKER so all queries respect existing RLS policies.
-- Also performs an explicit band membership check for defense in depth.
-- ============================================================================

create or replace function get_band_full_state(p_band_id uuid)
returns jsonb
language plpgsql
security invoker
as $$
declare
  result jsonb;
  band_record jsonb;
  members_arr jsonb;
  gigs_arr jsonb;
  rehearsals_arr jsonb;
  setlists_arr jsonb;
begin
  -- =========================================
  -- BAND MEMBERSHIP CHECK — defense in depth
  -- RLS also enforces this, but we fail fast
  -- =========================================
  if not exists (
    select 1 from band_members
    where band_id = p_band_id
      and user_id = auth.uid()
  ) then
    raise exception 'Access denied: user is not a member of this band';
  end if;

  -- Fetch band record
  select row_to_json(b.*)::jsonb into band_record
  from bands b
  where b.id = p_band_id;

  if band_record is null then
    raise exception 'Band not found: %', p_band_id;
  end if;

  -- Fetch band members (only active/invited — matches MembersRepository filter)
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', bm.id,
      'band_id', bm.band_id,
      'user_id', bm.user_id,
      'role', bm.role,
      'joined_at', bm.joined_at
    )
  ), '[]'::jsonb) into members_arr
  from band_members bm
  where bm.band_id = p_band_id
    and bm.status in ('active', 'invited');

  -- Fetch gigs with nested gig_dates for multi-date support
  select coalesce(jsonb_agg(gig_row order by gig_row->>'date'), '[]'::jsonb)
  into gigs_arr
  from (
    select to_jsonb(g.*) || jsonb_build_object(
      'gig_dates', coalesce(
        (select jsonb_agg(
          jsonb_build_object(
            'id', gd.id,
            'gig_id', gd.gig_id,
            'date', gd.date,
            'created_at', gd.created_at,
            'updated_at', gd.updated_at
          ) order by gd.date
        ) from gig_dates gd where gd.gig_id = g.id),
        '[]'::jsonb
      )
    ) as gig_row
    from gigs g
    where g.band_id = p_band_id
  ) sub;

  -- Fetch rehearsals ordered by date
  select coalesce(jsonb_agg(to_jsonb(r.*) order by r.date), '[]'::jsonb)
  into rehearsals_arr
  from rehearsals r
  where r.band_id = p_band_id;

  -- Fetch setlists with computed song counts
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'name', s.name,
      'band_id', s.band_id,
      'total_duration', s.total_duration,
      'is_catalog', s.is_catalog,
      'position', s.position,
      'created_at', s.created_at,
      'updated_at', s.updated_at,
      'song_count', (select count(*) from setlist_songs ss where ss.setlist_id = s.id)
    ) order by s.position, s.name
  ), '[]'::jsonb) into setlists_arr
  from setlists s
  where s.band_id = p_band_id;

  -- Build final response
  result := jsonb_build_object(
    'band', band_record,
    'members', members_arr,
    'gigs', gigs_arr,
    'rehearsals', rehearsals_arr,
    'setlists', setlists_arr
  );

  return result;
end;
$$;
