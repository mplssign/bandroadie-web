-- ============================================================================
-- MIGRATION: 20260323100000_print_templates_per_section_fonts.sql
-- Adds per-section font size columns and show_tuning toggle.
-- Widens base_font_size CHECK constraint from 14-24 to 14-36.
-- ============================================================================

-- 1. ADD per-section font size columns and new toggles
ALTER TABLE public.print_templates
  ADD COLUMN IF NOT EXISTS show_tuning BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_pauses BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_band_name BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS number_font_size DOUBLE PRECISION NOT NULL DEFAULT 18.0
    CHECK (number_font_size >= 14.0 AND number_font_size <= 36.0),
  ADD COLUMN IF NOT EXISTS header_font_size DOUBLE PRECISION NOT NULL DEFAULT 28.0
    CHECK (header_font_size >= 14.0 AND header_font_size <= 36.0),
  ADD COLUMN IF NOT EXISTS band_name_font_size DOUBLE PRECISION NOT NULL DEFAULT 16.0
    CHECK (band_name_font_size >= 14.0 AND band_name_font_size <= 36.0),
  ADD COLUMN IF NOT EXISTS bpm_font_size DOUBLE PRECISION NOT NULL DEFAULT 16.0
    CHECK (bpm_font_size >= 14.0 AND bpm_font_size <= 36.0),
  ADD COLUMN IF NOT EXISTS tuning_font_size DOUBLE PRECISION NOT NULL DEFAULT 14.0
    CHECK (tuning_font_size >= 14.0 AND tuning_font_size <= 36.0),
  ADD COLUMN IF NOT EXISTS capo_font_size DOUBLE PRECISION NOT NULL DEFAULT 14.0
    CHECK (capo_font_size >= 14.0 AND capo_font_size <= 36.0),
  ADD COLUMN IF NOT EXISTS notes_font_size DOUBLE PRECISION NOT NULL DEFAULT 14.0
    CHECK (notes_font_size >= 14.0 AND notes_font_size <= 36.0),
  ADD COLUMN IF NOT EXISTS pause_font_size DOUBLE PRECISION NOT NULL DEFAULT 16.0
    CHECK (pause_font_size >= 14.0 AND pause_font_size <= 36.0);

-- 2. WIDEN base_font_size CHECK constraint from 14-24 to 14-36
ALTER TABLE public.print_templates
  DROP CONSTRAINT IF EXISTS print_templates_base_font_size_check;

ALTER TABLE public.print_templates
  ADD CONSTRAINT print_templates_base_font_size_check
  CHECK (base_font_size >= 14.0 AND base_font_size <= 36.0);
