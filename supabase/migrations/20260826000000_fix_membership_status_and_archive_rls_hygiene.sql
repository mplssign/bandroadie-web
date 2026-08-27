-- ============================================================================
-- Fix membership status and archive RLS hygiene
-- ============================================================================
-- Pre-migration helper definition (rollback reference):
-- CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id uuid)
--  RETURNS boolean
--  LANGUAGE sql
--  STABLE SECURITY DEFINER
--  SET search_path = 'public'
-- AS $function$
--   SELECT EXISTS (
--     SELECT 1 FROM public.band_members
--     WHERE band_id = p_band_id
--       AND user_id = auth.uid()
--   );
-- $function$
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.band_members
    WHERE band_id = p_band_id
      AND user_id = auth.uid()
      AND status = 'active'::text
  );
$$;

DROP POLICY IF EXISTS "Band members can create special items" ON public.setlist_special_items;
CREATE POLICY "Band members can create special items" ON public.setlist_special_items
FOR INSERT
WITH CHECK ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = (select auth.uid())) AND (band_members.status = 'active'::text))))
);

DROP POLICY IF EXISTS "Band members can delete special items" ON public.setlist_special_items;
CREATE POLICY "Band members can delete special items" ON public.setlist_special_items
FOR DELETE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = (select auth.uid())) AND (band_members.status = 'active'::text))))
);

DROP POLICY IF EXISTS "Band members can update special items" ON public.setlist_special_items;
CREATE POLICY "Band members can update special items" ON public.setlist_special_items
FOR UPDATE
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = (select auth.uid())) AND (band_members.status = 'active'::text))))
);

DROP POLICY IF EXISTS "Band members can view special items" ON public.setlist_special_items;
CREATE POLICY "Band members can view special items" ON public.setlist_special_items
FOR SELECT
USING ((EXISTS ( SELECT 1
   FROM band_members
  WHERE ((band_members.band_id = setlist_special_items.band_id) AND (band_members.user_id = (select auth.uid())) AND (band_members.status = 'active'::text))))
);

ALTER TABLE archive.bands ENABLE ROW LEVEL SECURITY;
ALTER TABLE archive.band_members ENABLE ROW LEVEL SECURITY;
