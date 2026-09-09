-- Migration: Add notes column to financial_entries
-- Adds a nullable free-text `notes` column separate from the existing
-- `description` column. Existing entries have notes = NULL; no backfill.
-- RLS impact: none — the existing financial_entries policies gate on
-- band_id membership via check_band_member() and are column-agnostic.
-- Trigger impact: none — trg_sync_gig_pay reads only entry_type, gig_id,
-- amount_cents.
-- Constraint impact: none — the existing reimbursement-consistency
-- constraint touches only reimbursement columns.

ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS notes TEXT;
