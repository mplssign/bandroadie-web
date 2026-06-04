ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS deposit_to_savings BOOLEAN DEFAULT FALSE;
