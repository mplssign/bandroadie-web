-- Migration: Add deposit_to_savings_cents to financial_entries
-- Date: 2026-06-04
-- Branch: bug/deposit-to-savings-amount

ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS deposit_to_savings_cents INTEGER;
