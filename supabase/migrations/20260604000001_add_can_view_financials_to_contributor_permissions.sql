-- Migration: Add can_view_financials to contributor_permissions
-- Date: 2026-06-04
-- Branch: bug/deposit-to-savings-amount

ALTER TABLE public.contributor_permissions
  ADD COLUMN IF NOT EXISTS can_view_financials BOOLEAN NOT NULL DEFAULT FALSE;
