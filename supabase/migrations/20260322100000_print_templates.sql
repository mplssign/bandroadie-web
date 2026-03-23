-- ============================================================================
-- MIGRATION: 20260322100000_print_templates.sql
-- Adds print_templates table for saved print layout configurations,
-- and last_used_print_template_id column to bands table.
-- ============================================================================

-- 1. CREATE print_templates TABLE
CREATE TABLE IF NOT EXISTS public.print_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  tuning_display TEXT NOT NULL DEFAULT 'grouped'
    CHECK (tuning_display IN ('grouped', 'inline')),
  show_capo BOOLEAN NOT NULL DEFAULT true,
  show_bpm BOOLEAN NOT NULL DEFAULT true,
  show_notes BOOLEAN NOT NULL DEFAULT false,
  show_song_numbers BOOLEAN NOT NULL DEFAULT true,
  show_header BOOLEAN NOT NULL DEFAULT true,
  show_page_numbers BOOLEAN NOT NULL DEFAULT true,
  base_font_size DOUBLE PRECISION NOT NULL DEFAULT 18.0
    CHECK (base_font_size >= 14.0 AND base_font_size <= 24.0),
  paper_size TEXT NOT NULL DEFAULT 'letter'
    CHECK (paper_size IN ('letter', 'a4')),
  column_count INT NOT NULL DEFAULT 1
    CHECK (column_count IN (1, 2)),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. INDEX for band isolation and fast lookup
CREATE INDEX idx_print_templates_band_id ON public.print_templates(band_id);

-- 3. TRIGGER: auto-update updated_at on every UPDATE
CREATE OR REPLACE FUNCTION update_print_templates_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER print_templates_updated_at
  BEFORE UPDATE ON public.print_templates
  FOR EACH ROW
  EXECUTE FUNCTION update_print_templates_updated_at();

-- 4. ADD last_used_print_template_id to bands table
ALTER TABLE public.bands
  ADD COLUMN IF NOT EXISTS last_used_print_template_id UUID
  REFERENCES public.print_templates(id) ON DELETE SET NULL;

-- 5. RLS POLICY
ALTER TABLE public.print_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage print templates for their bands"
  ON public.print_templates
  FOR ALL
  USING (
    band_id IN (
      SELECT bm.band_id FROM public.band_members bm
      WHERE bm.user_id = auth.uid()
    )
  )
  WITH CHECK (
    band_id IN (
      SELECT bm.band_id FROM public.band_members bm
      WHERE bm.user_id = auth.uid()
    )
  );
