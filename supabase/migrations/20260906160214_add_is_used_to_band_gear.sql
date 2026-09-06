-- Migration: Add is_used to band_gear
-- Date: 2026-09-06
-- Branch: feature/band-gear-management

ALTER TABLE public.band_gear
  ADD COLUMN IF NOT EXISTS is_used BOOLEAN NOT NULL DEFAULT FALSE;
