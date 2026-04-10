-- ============================================================================
-- Migration: contacts_venues_tables
-- Creates venues, venue_contacts, and contacts tables for band contact management.
-- ============================================================================

-- ============================================================================
-- VENUES TABLE
-- ============================================================================

CREATE TABLE public.venues (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id    UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  address    TEXT,
  city       TEXT,
  state      TEXT,
  phone      TEXT,
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_venues_band_id ON public.venues(band_id);

ALTER TABLE public.venues ENABLE ROW LEVEL SECURITY;

-- SELECT: any active band member
CREATE POLICY "Band members can view venues" ON public.venues
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- INSERT: admins and members
CREATE POLICY "Admins and members can create venues" ON public.venues
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- UPDATE: admins and members
CREATE POLICY "Admins and members can update venues" ON public.venues
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE: admins only
CREATE POLICY "Admins can delete venues" ON public.venues
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role = 'admin'
    )
  );

-- ============================================================================
-- VENUE CONTACTS TABLE
-- ============================================================================

CREATE TABLE public.venue_contacts (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id   UUID NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  band_id    UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  title      TEXT,
  phone      TEXT,
  email      TEXT,
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_venue_contacts_venue_id ON public.venue_contacts(venue_id);
CREATE INDEX idx_venue_contacts_band_id ON public.venue_contacts(band_id);

ALTER TABLE public.venue_contacts ENABLE ROW LEVEL SECURITY;

-- SELECT: any active band member
CREATE POLICY "Band members can view venue contacts" ON public.venue_contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- INSERT: admins and members
CREATE POLICY "Admins and members can create venue contacts" ON public.venue_contacts
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- UPDATE: admins and members
CREATE POLICY "Admins and members can update venue contacts" ON public.venue_contacts
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE: admins and members
CREATE POLICY "Admins and members can delete venue contacts" ON public.venue_contacts
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- ============================================================================
-- CONTACTS TABLE (standalone contacts)
-- ============================================================================

CREATE TABLE public.contacts (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id    UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  title      TEXT,
  phone      TEXT,
  email      TEXT,
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_contacts_band_id ON public.contacts(band_id);

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

-- SELECT: any active band member
CREATE POLICY "Band members can view contacts" ON public.contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- INSERT: admins and members
CREATE POLICY "Admins and members can create contacts" ON public.contacts
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- UPDATE: admins and members
CREATE POLICY "Admins and members can update contacts" ON public.contacts
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE: admins and members
CREATE POLICY "Admins and members can delete contacts" ON public.contacts
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- ============================================================================
-- UPDATED_AT TRIGGERS
-- ============================================================================

-- Reusable trigger function (safe if already exists)
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_venues_updated_at
  BEFORE UPDATE ON public.venues
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_venue_contacts_updated_at
  BEFORE UPDATE ON public.venue_contacts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_contacts_updated_at
  BEFORE UPDATE ON public.contacts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
