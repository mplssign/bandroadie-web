-- ============================================================================
-- Migration: 20260904120000_demo_bands_schema.sql
-- Interactive demo band experience — schema layer.
--
-- 1. demo_sessions table + RLS
-- 2. bands.is_demo_template, bands.is_demo_clone, bands.demo_session_id
-- 3. Template-write-guard trigger function applied to 8 tables
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. demo_sessions table
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.demo_sessions (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id     UUID        NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  provisioned_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ NOT NULL DEFAULT now() + interval '30 minutes',
  clone_band_ids   UUID[]      NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_demo_sessions_auth_user_id
  ON public.demo_sessions(auth_user_id);

CREATE INDEX IF NOT EXISTS idx_demo_sessions_expires_at
  ON public.demo_sessions(expires_at);

ALTER TABLE public.demo_sessions ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read their own demo session only.
-- Policy predicate references only auth.uid() — never queries demo_sessions itself.
DROP POLICY IF EXISTS demo_sessions_select_own ON public.demo_sessions;
CREATE POLICY demo_sessions_select_own ON public.demo_sessions
  FOR SELECT
  USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS demo_sessions_update_own ON public.demo_sessions;
CREATE POLICY demo_sessions_update_own ON public.demo_sessions
  FOR UPDATE
  USING (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());

-- No INSERT or DELETE policy — writes come exclusively from SECURITY DEFINER RPCs.

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. New columns on bands
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.bands
  ADD COLUMN IF NOT EXISTS is_demo_template BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_demo_clone    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS demo_session_id  UUID    REFERENCES public.demo_sessions(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_bands_is_demo_template
  ON public.bands(is_demo_template) WHERE is_demo_template = true;

CREATE INDEX IF NOT EXISTS idx_bands_demo_session_id
  ON public.bands(demo_session_id) WHERE demo_session_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Template-write-guard trigger
--    Prevents anonymous auth users from writing directly to template bands or
--    their child rows. Belt-and-braces on top of existing band-scoped RLS.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.prevent_anonymous_template_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only fires for anonymous JWT sessions (is_anonymous = 'true' in JWT claims).
  IF (auth.jwt() ->> 'is_anonymous')::boolean IS TRUE THEN
    IF TG_TABLE_NAME = 'bands' THEN
      IF NEW.is_demo_template = true THEN
        RAISE EXCEPTION 'Anonymous users may not write to demo template bands';
      END IF;
    ELSE
      -- For child tables: reject writes whose target band is a template.
      IF EXISTS (
        SELECT 1 FROM public.bands
        WHERE id = NEW.band_id
          AND is_demo_template = true
      ) THEN
        RAISE EXCEPTION 'Anonymous users may not write to demo template band data';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.prevent_anonymous_template_write() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prevent_anonymous_template_write() TO authenticated;

-- Apply trigger to bands table
DROP TRIGGER IF EXISTS trg_prevent_anon_template_write_bands ON public.bands;
CREATE TRIGGER trg_prevent_anon_template_write_bands
  BEFORE INSERT OR UPDATE ON public.bands
  FOR EACH ROW EXECUTE FUNCTION public.prevent_anonymous_template_write();

-- Apply trigger to child tables (band_id-scoped)
DROP TRIGGER IF EXISTS trg_prevent_anon_template_write_songs ON public.songs;
CREATE TRIGGER trg_prevent_anon_template_write_songs
  BEFORE INSERT OR UPDATE ON public.songs
  FOR EACH ROW EXECUTE FUNCTION public.prevent_anonymous_template_write();

DROP TRIGGER IF EXISTS trg_prevent_anon_template_write_setlists ON public.setlists;
CREATE TRIGGER trg_prevent_anon_template_write_setlists
  BEFORE INSERT OR UPDATE ON public.setlists
  FOR EACH ROW EXECUTE FUNCTION public.prevent_anonymous_template_write();

DROP TRIGGER IF EXISTS trg_prevent_anon_template_write_gigs ON public.gigs;
CREATE TRIGGER trg_prevent_anon_template_write_gigs
  BEFORE INSERT OR UPDATE ON public.gigs
  FOR EACH ROW EXECUTE FUNCTION public.prevent_anonymous_template_write();

DROP TRIGGER IF EXISTS trg_prevent_anon_template_write_rehearsals ON public.rehearsals;
CREATE TRIGGER trg_prevent_anon_template_write_rehearsals
  BEFORE INSERT OR UPDATE ON public.rehearsals
  FOR EACH ROW EXECUTE FUNCTION public.prevent_anonymous_template_write();

DROP TRIGGER IF EXISTS trg_prevent_anon_template_write_venues ON public.venues;
CREATE TRIGGER trg_prevent_anon_template_write_venues
  BEFORE INSERT OR UPDATE ON public.venues
  FOR EACH ROW EXECUTE FUNCTION public.prevent_anonymous_template_write();

DROP TRIGGER IF EXISTS trg_prevent_anon_template_write_contacts ON public.contacts;
CREATE TRIGGER trg_prevent_anon_template_write_contacts
  BEFORE INSERT OR UPDATE ON public.contacts
  FOR EACH ROW EXECUTE FUNCTION public.prevent_anonymous_template_write();

DROP TRIGGER IF EXISTS trg_prevent_anon_template_write_financial_entries ON public.financial_entries;
CREATE TRIGGER trg_prevent_anon_template_write_financial_entries
  BEFORE INSERT OR UPDATE ON public.financial_entries
  FOR EACH ROW EXECUTE FUNCTION public.prevent_anonymous_template_write();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. bands_real view — filters out demo templates and per-visitor clones so
--    admin/analytics queries don't silently count demo rows.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.bands_real AS
SELECT * FROM public.bands
WHERE is_demo_template = false
  AND is_demo_clone = false;
