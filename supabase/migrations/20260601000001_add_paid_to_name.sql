ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS paid_to_name TEXT;
