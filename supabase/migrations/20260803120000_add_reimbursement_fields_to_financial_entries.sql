-- Add reimbursement tracking fields to financial_entries
ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS is_reimbursed BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS reimbursed_date DATE;

-- Keep reimbursement data consistent: date is required only when reimbursed.
ALTER TABLE public.financial_entries
  DROP CONSTRAINT IF EXISTS financial_entries_reimbursement_consistency;

ALTER TABLE public.financial_entries
  ADD CONSTRAINT financial_entries_reimbursement_consistency
  CHECK (
    (is_reimbursed = FALSE AND reimbursed_date IS NULL)
    OR
    (is_reimbursed = TRUE AND reimbursed_date IS NOT NULL)
  );
