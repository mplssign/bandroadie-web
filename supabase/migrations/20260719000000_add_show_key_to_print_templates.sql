-- ============================================================================
-- MIGRATION: 20260719000000_add_show_key_to_print_templates.sql
-- Adds show_key and key_font_size to print_templates.
-- ============================================================================

ALTER TABLE public.print_templates
  ADD COLUMN IF NOT EXISTS show_key BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS key_font_size DOUBLE PRECISION NOT NULL DEFAULT 14.0
    CHECK (key_font_size >= 14.0 AND key_font_size <= 36.0);
