-- ============================================================================
-- Migration: create_band_gear
-- Creates band gear inventory table with band-scoped RLS policies.
-- ============================================================================

CREATE TABLE public.band_gear (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id         UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  purchased_on    DATE,
  purchased_from  TEXT,
  price_cents     INTEGER CHECK (price_cents IS NULL OR price_cents >= 0),
  owner_type      TEXT NOT NULL CHECK (owner_type IN ('band', 'member')),
  owner_user_id   UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT band_gear_owner_shape CHECK (
    (owner_type = 'band' AND owner_user_id IS NULL) OR
    (owner_type = 'member' AND owner_user_id IS NOT NULL)
  )
);

CREATE INDEX idx_band_gear_band_id ON public.band_gear(band_id);
CREATE INDEX idx_band_gear_owner_user_id ON public.band_gear(owner_user_id);

ALTER TABLE public.band_gear ENABLE ROW LEVEL SECURITY;

-- SELECT: any active band member
CREATE POLICY "Band members can view gear" ON public.band_gear
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = band_gear.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- INSERT: admins and members
CREATE POLICY "Admins and members can create gear" ON public.band_gear
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = band_gear.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- UPDATE: admins and members
CREATE POLICY "Admins and members can update gear" ON public.band_gear
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = band_gear.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = band_gear.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE: admins and members
CREATE POLICY "Admins and members can delete gear" ON public.band_gear
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = band_gear.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

CREATE TRIGGER set_band_gear_updated_at
  BEFORE UPDATE ON public.band_gear
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
