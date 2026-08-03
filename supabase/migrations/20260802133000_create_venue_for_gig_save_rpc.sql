CREATE OR REPLACE FUNCTION public.create_venue_for_gig_save(
  p_band_id UUID,
  p_name TEXT,
  p_city TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_state TEXT DEFAULT NULL,
  p_is_potential BOOLEAN DEFAULT FALSE
)
RETURNS public.venues
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_member RECORD;
  v_can_create BOOLEAN := FALSE;
  v_name TEXT;
  v_city TEXT;
  v_existing public.venues%ROWTYPE;
  v_created public.venues%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_band_id IS NULL THEN
    RAISE EXCEPTION 'band_id is required';
  END IF;

  v_name := NULLIF(trim(p_name), '');
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'name is required';
  END IF;

  v_city := NULLIF(trim(p_city), '');

  SELECT bm.id, bm.role
  INTO v_member
  FROM public.band_members bm
  WHERE bm.band_id = p_band_id
    AND bm.user_id = v_user_id
    AND bm.status = 'active'
  LIMIT 1;

  IF v_member IS NULL THEN
    RAISE EXCEPTION 'User is not an active member of this band';
  END IF;

  IF v_member.role IN ('admin', 'member') THEN
    v_can_create := TRUE;
  ELSIF v_member.role = 'contributor' THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.contributor_permissions cp
      WHERE cp.band_member_id = v_member.id
        AND cp.can_create_gigs = TRUE
        AND (
          cp.can_create_potential_gigs_only = FALSE
          OR coalesce(p_is_potential, FALSE) = TRUE
        )
    )
    INTO v_can_create;
  END IF;

  IF NOT v_can_create THEN
    RAISE EXCEPTION 'Insufficient permissions to create venue for gig save';
  END IF;

  -- Dedupe by same band + case-insensitive venue name + null-safe city.
  SELECT v.*
  INTO v_existing
  FROM public.venues v
  WHERE v.band_id = p_band_id
    AND lower(v.name) = lower(v_name)
    AND (
      (v_city IS NULL AND NULLIF(trim(v.city), '') IS NULL)
      OR (v_city IS NOT NULL AND lower(v.city) = lower(v_city))
    )
  ORDER BY v.created_at ASC
  LIMIT 1;

  IF FOUND THEN
    RETURN v_existing;
  END IF;

  INSERT INTO public.venues (band_id, name, city, address, state)
  VALUES (
    p_band_id,
    v_name,
    v_city,
    NULLIF(trim(p_address), ''),
    NULLIF(upper(trim(p_state)), '')
  )
  RETURNING * INTO v_created;

  RETURN v_created;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_venue_for_gig_save(UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
