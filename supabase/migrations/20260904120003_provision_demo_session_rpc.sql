-- ============================================================================
-- Migration: 20260904120003_provision_demo_session_rpc.sql
-- provision_demo_session() — clones both template bands for the calling
-- anonymous auth user and returns their clone band IDs as JSONB.
--
-- Idempotent: calling twice with the same auth.uid() returns the existing
-- session's clone band IDs without creating duplicate data.
-- Single-transaction: any failure rolls back all inserts atomically.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.provision_demo_session()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id          UUID;
  v_session_id       UUID;
  v_bs_band_id       UUID;  -- cloned Banana Stand id
  v_mn_band_id       UUID;  -- cloned Modal Nodes id
  v_template         RECORD;
  v_clone_band_id    UUID;
  v_song             RECORD;
  v_old_song_id      UUID;
  v_new_song_id      UUID;
  v_setlist          RECORD;
  v_old_setlist_id   UUID;
  v_new_setlist_id   UUID;
  v_catalog_setlist_id UUID;
  v_gig              RECORD;
  v_old_gig_id       UUID;
  v_new_gig_id       UUID;
  v_rehearsal        RECORD;
  v_old_rehearsal_id UUID;
  v_new_rehearsal_id UUID;
  v_member           RECORD;
  v_contact          RECORD;
  v_old_contact_id   UUID;
  v_new_contact_id   UUID;
  v_venue            RECORD;
  v_old_venue_id     UUID;
  v_new_venue_id     UUID;
  v_fe               RECORD;
  v_gig_id_remap     JSONB := '{}';
  v_song_id_remap    JSONB := '{}';
  v_setlist_id_remap JSONB := '{}';
  v_venue_id_remap   JSONB := '{}';
  v_contact_id_remap JSONB := '{}';
  v_band_idx         INTEGER := 0;
  v_existing_clone_ids UUID[];
  v_max_concurrent   CONSTANT INTEGER := 30;  -- tune here; re-apply migration file
  v_live_count       INTEGER;
BEGIN
  -- ── 1. Caller must be anonymous ──────────────────────────────────────────
  IF NOT ((auth.jwt() ->> 'is_anonymous')::boolean IS TRUE) THEN
    RAISE EXCEPTION 'Not an anonymous session';
  END IF;

  v_user_id := auth.uid();

  -- ── 2. Idempotency check ─────────────────────────────────────────────────
  SELECT id, clone_band_ids INTO v_session_id, v_existing_clone_ids
  FROM demo_sessions
  WHERE auth_user_id = v_user_id;

  IF FOUND THEN
    -- Session already exists — return the existing clone band IDs.
    RETURN jsonb_build_object(
      'banana_stand_band_id', v_existing_clone_ids[1]::text,
      'modal_nodes_band_id',  v_existing_clone_ids[2]::text
    );
  END IF;

  -- ── 2b. Concurrency ceiling ──────────────────────────────────────────────
  -- Only reached for genuinely-new provisions — returning visitors early-return
  -- above and are never blocked by the ceiling on their own existing clone.
  SELECT count(*) INTO v_live_count
  FROM demo_sessions
  WHERE expires_at > now();

  IF v_live_count >= v_max_concurrent THEN
    RAISE EXCEPTION 'demo_capacity_exceeded'
      USING ERRCODE = 'P0001',
            HINT = 'Retry in a few minutes; the interactive demo is at capacity.';
  END IF;

  -- ── 3. Insert public.users row for this visitor ──────────────────────────
  INSERT INTO users (id, email, first_name, last_name, phone, address, city, zip, birthday, roles, profile_completed)
  VALUES (
    v_user_id,
    'demo-' || left(v_user_id::text, 8) || '@bandroadie.com',
    'Demo', 'Visitor',
    '(123) 456-7890',
    '1060 W Addison St',
    'Chicago',
    '60613',
    '1990-11-09',
    ARRAY['Drums'],
    true
  )
  ON CONFLICT (id) DO NOTHING;

  -- ── 4. Insert demo_sessions row (clone_band_ids updated at the end) ──────
  BEGIN
    INSERT INTO demo_sessions (auth_user_id, clone_band_ids)
    VALUES (v_user_id, '{}')
    RETURNING id INTO v_session_id;
  EXCEPTION WHEN unique_violation THEN
    -- Race lost to a concurrent call by the same anon user; return the winner's clones.
    SELECT id, clone_band_ids INTO v_session_id, v_existing_clone_ids
    FROM demo_sessions
    WHERE auth_user_id = v_user_id;
    RETURN jsonb_build_object(
      'banana_stand_band_id', v_existing_clone_ids[1]::text,
      'modal_nodes_band_id',  v_existing_clone_ids[2]::text
    );
  END;

  -- ── 5. Clone each template band ──────────────────────────────────────────
  FOR v_template IN
    SELECT id, name, avatar_color, timezone, image_url
    FROM bands
    WHERE is_demo_template = true
    ORDER BY id ASC  -- deterministic order: Banana Stand (id ...0001) first, Modal Nodes (...0002) second
  LOOP
    v_band_idx := v_band_idx + 1;

    -- Reset per-band remaps
    v_song_id_remap    := '{}';
    v_setlist_id_remap := '{}';
    v_gig_id_remap     := '{}';
    v_venue_id_remap   := '{}';
    v_contact_id_remap := '{}';

    -- 5a. Insert clone band
    v_clone_band_id := gen_random_uuid();
    INSERT INTO bands (id, name, avatar_color, timezone, image_url, created_by, is_demo_clone, demo_session_id)
    VALUES (v_clone_band_id, v_template.name, v_template.avatar_color,
            v_template.timezone, v_template.image_url, v_user_id, true, v_session_id);

    -- The auto_create_catalog_for_band trigger fires here and creates the
    -- catalog setlist for v_clone_band_id.

    -- Capture the auto-created catalog setlist id
    SELECT id INTO v_catalog_setlist_id
    FROM setlists
    WHERE band_id = v_clone_band_id
      AND is_catalog = true
    LIMIT 1;

    -- 5b. Add visitor as admin band member
    INSERT INTO band_members (band_id, user_id, role, status, joined_at)
    VALUES (v_clone_band_id, v_user_id, 'admin', 'active', now());

    -- 5c. Copy dummy member rows from the template (same user_ids, same roles)
    FOR v_member IN
      SELECT user_id, role, status, joined_at
      FROM band_members
      WHERE band_id = v_template.id
    LOOP
      INSERT INTO band_members (band_id, user_id, role, status, joined_at)
      VALUES (v_clone_band_id, v_member.user_id, v_member.role,
              v_member.status, v_member.joined_at)
;
    END LOOP;

    -- 5d. Clone songs (new UUIDs)
    FOR v_song IN
      SELECT id, title, artist, bpm, tuning, duration_seconds
      FROM songs
      WHERE band_id = v_template.id
    LOOP
      v_old_song_id := v_song.id;
      v_new_song_id := gen_random_uuid();
      v_song_id_remap := v_song_id_remap || jsonb_build_object(v_old_song_id::text, v_new_song_id::text);

      INSERT INTO songs (id, band_id, title, artist, bpm, tuning, duration_seconds)
      VALUES (v_new_song_id, v_clone_band_id, v_song.title, v_song.artist,
              v_song.bpm, v_song.tuning, v_song.duration_seconds);
    END LOOP;

    -- 5e. Clone non-catalog setlists (skip is_catalog=true rows from template;
    --     the auto-created catalog on the clone is already in v_catalog_setlist_id).
    FOR v_setlist IN
      SELECT id, name, position
      FROM setlists
      WHERE band_id = v_template.id
        AND is_catalog = false
      ORDER BY position
    LOOP
      v_old_setlist_id := v_setlist.id;
      v_new_setlist_id := gen_random_uuid();
      v_setlist_id_remap := v_setlist_id_remap
        || jsonb_build_object(v_old_setlist_id::text, v_new_setlist_id::text);

      INSERT INTO setlists (id, band_id, name, position, is_catalog)
      VALUES (v_new_setlist_id, v_clone_band_id, v_setlist.name, v_setlist.position, false);

      -- Clone setlist_songs for this setlist
      INSERT INTO setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds)
      SELECT v_new_setlist_id,
             (v_song_id_remap ->> ss.song_id::text)::uuid,
             ss.position,
             ss.bpm,
             ss.tuning,
             ss.duration_seconds
      FROM setlist_songs ss
      WHERE ss.setlist_id = v_old_setlist_id
        AND v_song_id_remap ? ss.song_id::text;
    END LOOP;

    -- Also populate the catalog setlist with all cloned songs
    INSERT INTO setlist_songs (setlist_id, song_id, position, bpm, tuning, duration_seconds)
    SELECT v_catalog_setlist_id,
           (v_song_id_remap ->> s.id::text)::uuid,
           row_number() OVER (ORDER BY s.title) AS position,
           s.bpm,
           s.tuning,
           s.duration_seconds
    FROM songs s
    WHERE s.band_id = v_template.id
      AND v_song_id_remap ? s.id::text;

    -- 5f. Clone venues
    FOR v_venue IN
      SELECT id, name, address, city, state, phone, notes
      FROM venues
      WHERE band_id = v_template.id
    LOOP
      v_old_venue_id := v_venue.id;
      v_new_venue_id := gen_random_uuid();
      v_venue_id_remap := v_venue_id_remap
        || jsonb_build_object(v_old_venue_id::text, v_new_venue_id::text);

      INSERT INTO venues (id, band_id, name, address, city, state, phone, notes)
      VALUES (v_new_venue_id, v_clone_band_id, v_venue.name, v_venue.address,
              v_venue.city, v_venue.state, v_venue.phone, v_venue.notes);
    END LOOP;

    -- 5g. Clone contacts
    FOR v_contact IN
      SELECT id, name, title, company, phone, email, notes
      FROM contacts
      WHERE band_id = v_template.id
    LOOP
      v_old_contact_id := v_contact.id;
      v_new_contact_id := gen_random_uuid();
      v_contact_id_remap := v_contact_id_remap
        || jsonb_build_object(v_old_contact_id::text, v_new_contact_id::text);

      INSERT INTO contacts (id, band_id, name, title, company, phone, email, notes)
      VALUES (v_new_contact_id, v_clone_band_id, v_contact.name, v_contact.title,
              v_contact.company, v_contact.phone, v_contact.email, v_contact.notes);
    END LOOP;

    -- Clone venue_contacts (inline name/title/phone/email — no contact_id FK)
    INSERT INTO venue_contacts (id, venue_id, band_id, name, title, phone, email)
    SELECT gen_random_uuid(),
           (v_venue_id_remap ->> vc.venue_id::text)::uuid,
           v_clone_band_id,
           vc.name, vc.title, vc.phone, vc.email
    FROM venue_contacts vc
    WHERE vc.band_id = v_template.id
      AND v_venue_id_remap ? vc.venue_id::text;

    -- 5h. Clone gigs (new UUIDs; remap setlist_id and venue_id)
    FOR v_gig IN
      SELECT id, name, date, start_time, end_time, load_in_time,
             location, address, state, setlist_id, setlist_name,
             notes, gig_pay, venue_id, is_potential
      FROM gigs
      WHERE band_id = v_template.id
    LOOP
      v_old_gig_id := v_gig.id;
      v_new_gig_id := gen_random_uuid();
      v_gig_id_remap := v_gig_id_remap
        || jsonb_build_object(v_old_gig_id::text, v_new_gig_id::text);

      INSERT INTO gigs (id, band_id, name, date, start_time, end_time, load_in_time,
                        location, address, state, setlist_id, setlist_name,
                        notes, gig_pay, venue_id, is_potential)
      VALUES (
        v_new_gig_id, v_clone_band_id,
        v_gig.name, v_gig.date, v_gig.start_time, v_gig.end_time, v_gig.load_in_time,
        v_gig.location, v_gig.address, v_gig.state,
        CASE WHEN v_gig.setlist_id IS NOT NULL
             THEN (v_setlist_id_remap ->> v_gig.setlist_id::text)::uuid
             ELSE NULL END,
        -- Look up the clone setlist name (template setlist_name is null)
        CASE WHEN v_gig.setlist_id IS NOT NULL AND v_setlist_id_remap ? v_gig.setlist_id::text THEN
          (SELECT name FROM setlists WHERE id = (v_setlist_id_remap ->> v_gig.setlist_id::text)::uuid LIMIT 1)
        ELSE v_gig.setlist_name END,
        v_gig.notes, v_gig.gig_pay,
        CASE WHEN v_gig.venue_id IS NOT NULL
             THEN (v_venue_id_remap ->> v_gig.venue_id::text)::uuid
             ELSE NULL END,
        v_gig.is_potential
      );

      -- Clone gig_dates
      INSERT INTO gig_dates (id, gig_id, date, start_time)
      SELECT gen_random_uuid(), v_new_gig_id, gd.date, gd.start_time
      FROM gig_dates gd
      WHERE gd.gig_id = v_old_gig_id;
    END LOOP;

    -- 5i. Clone rehearsals
    FOR v_rehearsal IN
      SELECT id, date, start_time, end_time, location, notes, setlist_id, is_potential
      FROM rehearsals
      WHERE band_id = v_template.id
    LOOP
      v_old_rehearsal_id := v_rehearsal.id;
      v_new_rehearsal_id := gen_random_uuid();

      INSERT INTO rehearsals (id, band_id, date, start_time, end_time, location, notes, setlist_id, is_potential)
      VALUES (
        v_new_rehearsal_id, v_clone_band_id,
        v_rehearsal.date, v_rehearsal.start_time, v_rehearsal.end_time,
        v_rehearsal.location, v_rehearsal.notes,
        CASE WHEN v_rehearsal.setlist_id IS NOT NULL
             THEN (v_setlist_id_remap ->> v_rehearsal.setlist_id::text)::uuid
             ELSE NULL END,
        v_rehearsal.is_potential
      );

      -- Clone rehearsal_dates
      INSERT INTO rehearsal_dates (id, rehearsal_id, date, start_time)
      SELECT gen_random_uuid(), v_new_rehearsal_id, rd.date, rd.start_time
      FROM rehearsal_dates rd
      WHERE rd.rehearsal_id = v_old_rehearsal_id;
    END LOOP;

    -- 5j. Clone financial_entries (remap gig_id; created_by = visitor)
    FOR v_fe IN
      SELECT entry_type, category, amount_cents, is_income, description, entry_date, gig_id
      FROM financial_entries
      WHERE band_id = v_template.id
    LOOP
      INSERT INTO financial_entries
        (id, band_id, entry_type, category, amount_cents, is_income, description, entry_date, created_by, gig_id)
      VALUES (
        gen_random_uuid(), v_clone_band_id,
        v_fe.entry_type, v_fe.category, v_fe.amount_cents, v_fe.is_income,
        v_fe.description, v_fe.entry_date, v_user_id,
        CASE WHEN v_fe.gig_id IS NOT NULL
             THEN (v_gig_id_remap ->> v_fe.gig_id::text)::uuid
             ELSE NULL END
      );
    END LOOP;

    -- Track clone band IDs by index (Banana Stand = alphabetically first)
    IF v_band_idx = 1 THEN
      v_bs_band_id := v_clone_band_id;
    ELSE
      v_mn_band_id := v_clone_band_id;
    END IF;

  END LOOP;

  -- ── 6. Update demo_sessions with the two clone band IDs ──────────────────
  UPDATE demo_sessions
  SET clone_band_ids = ARRAY[v_bs_band_id, v_mn_band_id]
  WHERE id = v_session_id;

  RETURN jsonb_build_object(
    'banana_stand_band_id', v_bs_band_id,
    'modal_nodes_band_id',  v_mn_band_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.provision_demo_session() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.provision_demo_session() TO authenticated;
