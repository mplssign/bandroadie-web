-- ============================================================================
-- Migration: 20260601000000_create_financial_entries.sql
-- Creates the financial_entries table, RLS policies, and gig_pay sync trigger.
-- ============================================================================

-- 1. Create financial_entries table
CREATE TABLE IF NOT EXISTS public.financial_entries (
  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id          UUID         NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  entry_type       TEXT         NOT NULL CHECK (entry_type IN (
                                  'gig_pay', 'merch_sale', 'equipment_sale',
                                  'misc_income', 'expense'
                                )),
  category         TEXT         NOT NULL,
  amount_cents     INTEGER      NOT NULL CHECK (amount_cents >= 0),
  is_income        BOOLEAN      NOT NULL DEFAULT TRUE,
  description      TEXT,
  entry_date       DATE         NOT NULL,
  is_1099_expected BOOLEAN,
  payor_name       TEXT,
  paid_to_name     TEXT,
  paid_to_user_id  UUID         REFERENCES public.users(id) ON DELETE SET NULL,
  disbursements    JSONB,
  gig_id           UUID         REFERENCES public.gigs(id) ON DELETE SET NULL,
  created_by       UUID         NOT NULL REFERENCES public.users(id),
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- 2. Create indexes
CREATE INDEX IF NOT EXISTS idx_financial_entries_band_id
  ON public.financial_entries(band_id);

CREATE INDEX IF NOT EXISTS idx_financial_entries_gig_id
  ON public.financial_entries(gig_id);

CREATE INDEX IF NOT EXISTS idx_financial_entries_band_date
  ON public.financial_entries(band_id, entry_date DESC);

-- 3. Unique partial index: at most one gig_pay entry per gig
CREATE UNIQUE INDEX IF NOT EXISTS uniq_gig_pay_entry
  ON public.financial_entries(gig_id)
  WHERE entry_type = 'gig_pay';

-- 4. Enable Row Level Security
ALTER TABLE public.financial_entries ENABLE ROW LEVEL SECURITY;

-- 5. SECURITY DEFINER helper: check band membership
-- Using CREATE OR REPLACE to be safe if function already exists.
CREATE OR REPLACE FUNCTION public.check_band_member(p_band_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = auth.uid()
      AND status = 'active'
  );
$$;

-- 6. RLS Policies
DROP POLICY IF EXISTS "financial_entries_select" ON public.financial_entries;
CREATE POLICY "financial_entries_select"
  ON public.financial_entries
  FOR SELECT
  USING (public.check_band_member(band_id));

DROP POLICY IF EXISTS "financial_entries_insert" ON public.financial_entries;
CREATE POLICY "financial_entries_insert"
  ON public.financial_entries
  FOR INSERT
  WITH CHECK (
    public.check_band_member(band_id)
    AND created_by = auth.uid()
  );

DROP POLICY IF EXISTS "financial_entries_update" ON public.financial_entries;
CREATE POLICY "financial_entries_update"
  ON public.financial_entries
  FOR UPDATE
  USING (public.check_band_member(band_id));

DROP POLICY IF EXISTS "financial_entries_delete" ON public.financial_entries;
CREATE POLICY "financial_entries_delete"
  ON public.financial_entries
  FOR DELETE
  USING (public.check_band_member(band_id));

-- 7. Trigger function: sync gigs.gig_pay from financial_entries
CREATE OR REPLACE FUNCTION public.sync_gig_pay_from_financial_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.entry_type = 'gig_pay' AND OLD.gig_id IS NOT NULL THEN
      UPDATE public.gigs
        SET gig_pay = NULL, updated_at = NOW()
        WHERE id = OLD.gig_id;
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.entry_type = 'gig_pay' AND NEW.gig_id IS NOT NULL THEN
    UPDATE public.gigs
      SET gig_pay = (NEW.amount_cents / 100.0), updated_at = NOW()
      WHERE id = NEW.gig_id;
  END IF;

  RETURN NEW;
END;
$$;

-- 8. Create trigger (drop first for idempotency)
DROP TRIGGER IF EXISTS trg_sync_gig_pay ON public.financial_entries;
CREATE TRIGGER trg_sync_gig_pay
  AFTER INSERT OR UPDATE OR DELETE ON public.financial_entries
  FOR EACH ROW EXECUTE FUNCTION public.sync_gig_pay_from_financial_entry();
