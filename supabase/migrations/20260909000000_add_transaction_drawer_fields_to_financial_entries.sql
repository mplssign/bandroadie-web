-- Add reimbursement_method + notes columns for the redesigned transaction drawer.
-- No security definer additions; RLS already covers new columns.
ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS reimbursement_method TEXT,
  ADD COLUMN IF NOT EXISTS notes                TEXT;

-- Tighten the reimbursement consistency check so method can only be set when reimbursed.
ALTER TABLE public.financial_entries
  DROP CONSTRAINT IF EXISTS financial_entries_reimbursement_consistency;

ALTER TABLE public.financial_entries
  ADD CONSTRAINT financial_entries_reimbursement_consistency
  CHECK (
    (is_reimbursed = FALSE AND reimbursed_date IS NULL AND reimbursement_method IS NULL)
    OR
    (is_reimbursed = TRUE  AND reimbursed_date IS NOT NULL)
  );
