-- Add per-band currency setting.
-- Restricted to the curated shortlist from feature/band-form-overlay-redesign.
-- DEFAULT 'USD' applies to all existing rows (no backfill needed).
-- RLS: bands_update_admins already gates writes; bands_select_members
-- already gates reads -- column-level authorization is inherited from the
-- row-level policies with no change required.

ALTER TABLE public.bands
  ADD COLUMN IF NOT EXISTS currency_code TEXT NOT NULL DEFAULT 'USD';

ALTER TABLE public.bands
  DROP CONSTRAINT IF EXISTS bands_currency_code_check;

ALTER TABLE public.bands
  ADD CONSTRAINT bands_currency_code_check
  CHECK (currency_code IN (
    'USD','CAD','MXN',
    'EUR','GBP','CHF','PLN','CZK','HUF','DKK','SEK','NOK','ISK',
    'RON','RSD','ALL','MKD','MDL','UAH',
    'ARS','BOB','BRL','CLP','COP','GYD','PYG','PEN','SRD','UYU','VES'
  ));

COMMENT ON COLUMN public.bands.currency_code IS
  'ISO 4217 currency code for this band. Restricted to the curated shortlist '
  'from feature/band-form-overlay-redesign. Defaults to USD.';