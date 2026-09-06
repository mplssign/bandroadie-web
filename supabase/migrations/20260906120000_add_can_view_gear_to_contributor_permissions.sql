-- Migration: Add can_view_gear to contributor_permissions
-- Date: 2026-09-06
-- Branch: feature/band-gear-management

ALTER TABLE public.contributor_permissions
  ADD COLUMN IF NOT EXISTS can_view_gear BOOLEAN NOT NULL DEFAULT FALSE;
