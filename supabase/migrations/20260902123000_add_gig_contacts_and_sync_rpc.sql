-- ============================================================================
-- Migration: add_gig_contacts_and_sync_rpc
-- Adds band-scoped gig contact links plus an idempotent sync RPC.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.gig_contacts (
  gig_id UUID NOT NULL REFERENCES public.gigs(id) ON DELETE CASCADE,
  contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  band_id UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (gig_id, contact_id)
);

CREATE INDEX IF NOT EXISTS idx_gig_contacts_band_id ON public.gig_contacts(band_id);
CREATE INDEX IF NOT EXISTS idx_gig_contacts_contact_id ON public.gig_contacts(contact_id);

ALTER TABLE public.gig_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "gig_contacts_select_members" ON public.gig_contacts;
CREATE POLICY "gig_contacts_select_members" ON public.gig_contacts
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.band_members bm
    WHERE bm.band_id = gig_contacts.band_id
      AND bm.user_id = (select auth.uid())
      AND bm.status = 'active'
  )
);

DROP POLICY IF EXISTS "gig_contacts_insert_members" ON public.gig_contacts;
CREATE POLICY "gig_contacts_insert_members" ON public.gig_contacts
FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.band_members bm
    WHERE bm.band_id = gig_contacts.band_id
      AND bm.user_id = (select auth.uid())
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
  )
);

DROP POLICY IF EXISTS "gig_contacts_delete_members" ON public.gig_contacts;
CREATE POLICY "gig_contacts_delete_members" ON public.gig_contacts
FOR DELETE TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.band_members bm
    WHERE bm.band_id = gig_contacts.band_id
      AND bm.user_id = (select auth.uid())
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
  )
);

CREATE OR REPLACE FUNCTION public.sync_gig_contacts(
  p_gig_id UUID,
  p_band_id UUID,
  p_contact_ids UUID[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_gig_band_id UUID;
  v_is_member BOOLEAN;
  v_contact_ids UUID[];
  v_invalid_contact_count INTEGER;
BEGIN
  v_user_id := (select auth.uid());

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.band_members bm
    WHERE bm.band_id = p_band_id
      AND bm.user_id = v_user_id
      AND bm.status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RAISE EXCEPTION 'Access denied: not an active member of this band';
  END IF;

  SELECT g.band_id
  INTO v_gig_band_id
  FROM public.gigs g
  WHERE g.id = p_gig_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Gig not found';
  END IF;

  IF v_gig_band_id <> p_band_id THEN
    RAISE EXCEPTION 'Gig belongs to a different band';
  END IF;

  SELECT COALESCE(array_agg(contact_id ORDER BY contact_id), '{}'::UUID[])
  INTO v_contact_ids
  FROM (
    SELECT DISTINCT contact_id
    FROM unnest(COALESCE(p_contact_ids, '{}'::UUID[])) AS contact_id
    WHERE contact_id IS NOT NULL
  ) deduped;

  SELECT COUNT(*)
  INTO v_invalid_contact_count
  FROM unnest(v_contact_ids) AS input_contact_id
  LEFT JOIN public.contacts c
    ON c.id = input_contact_id
   AND c.band_id = p_band_id
  WHERE c.id IS NULL;

  IF v_invalid_contact_count > 0 THEN
    RAISE EXCEPTION 'One or more contacts do not belong to this band';
  END IF;

  DELETE FROM public.gig_contacts gc
  WHERE gc.gig_id = p_gig_id
    AND gc.band_id = p_band_id
    AND NOT (gc.contact_id = ANY(v_contact_ids));

  INSERT INTO public.gig_contacts (gig_id, contact_id, band_id)
  SELECT p_gig_id, input_contact_id, p_band_id
  FROM unnest(v_contact_ids) AS input_contact_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.gig_contacts gc
    WHERE gc.gig_id = p_gig_id
      AND gc.contact_id = input_contact_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.sync_gig_contacts(UUID, UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_gig_contacts(UUID, UUID, UUID[]) TO authenticated;

COMMENT ON FUNCTION public.sync_gig_contacts(UUID, UUID, UUID[]) IS
  'Sync shared contact links for a gig. Validates membership and band ownership, deduplicates contact ids deterministically, deletes stale rows, and inserts missing rows atomically.';