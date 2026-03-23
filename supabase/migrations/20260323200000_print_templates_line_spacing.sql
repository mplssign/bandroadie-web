-- ============================================================================
-- MIGRATION: 20260323200000_print_templates_line_spacing.sql
-- Adds line_spacing column to print_templates.
-- ============================================================================

ALTER TABLE public.print_templates
  ADD COLUMN IF NOT EXISTS line_spacing DOUBLE PRECISION NOT NULL DEFAULT 1.0
    CHECK (line_spacing >= 0.0 AND line_spacing <= 3.0);
