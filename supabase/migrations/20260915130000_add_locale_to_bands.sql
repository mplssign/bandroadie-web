ALTER TABLE public.bands
  ADD COLUMN IF NOT EXISTS locale TEXT NOT NULL DEFAULT 'en_US';

UPDATE public.bands
SET locale = CASE currency_code
  WHEN 'USD' THEN 'en_US'
  WHEN 'CAD' THEN 'en_CA'
  WHEN 'MXN' THEN 'es_MX'
  WHEN 'EUR' THEN 'de_DE'
  WHEN 'GBP' THEN 'en_GB'
  WHEN 'CHF' THEN 'de_CH'
  WHEN 'PLN' THEN 'pl_PL'
  WHEN 'CZK' THEN 'cs_CZ'
  WHEN 'HUF' THEN 'hu_HU'
  WHEN 'DKK' THEN 'da_DK'
  WHEN 'SEK' THEN 'sv_SE'
  WHEN 'NOK' THEN 'nb_NO'
  WHEN 'ISK' THEN 'is_IS'
  WHEN 'RON' THEN 'ro_RO'
  WHEN 'RSD' THEN 'sr_RS'
  WHEN 'ALL' THEN 'sq_AL'
  WHEN 'MKD' THEN 'mk_MK'
  WHEN 'MDL' THEN 'ro_MD'
  WHEN 'UAH' THEN 'uk_UA'
  WHEN 'ARS' THEN 'es_AR'
  WHEN 'BOB' THEN 'es_BO'
  WHEN 'BRL' THEN 'pt_BR'
  WHEN 'CLP' THEN 'es_CL'
  WHEN 'COP' THEN 'es_CO'
  WHEN 'GYD' THEN 'en_GY'
  WHEN 'PYG' THEN 'es_PY'
  WHEN 'PEN' THEN 'es_PE'
  WHEN 'SRD' THEN 'nl_SR'
  WHEN 'UYU' THEN 'es_UY'
  WHEN 'VES' THEN 'es_VE'
END
WHERE (currency_code, locale) NOT IN (
  ('USD', 'en_US'),
  ('USD', 'es_EC'),
  ('CAD', 'en_CA'),
  ('MXN', 'es_MX'),
  ('EUR', 'de_DE'),
  ('EUR', 'bg_BG'),
  ('GBP', 'en_GB'),
  ('CHF', 'de_CH'),
  ('PLN', 'pl_PL'),
  ('CZK', 'cs_CZ'),
  ('HUF', 'hu_HU'),
  ('DKK', 'da_DK'),
  ('SEK', 'sv_SE'),
  ('NOK', 'nb_NO'),
  ('ISK', 'is_IS'),
  ('RON', 'ro_RO'),
  ('RSD', 'sr_RS'),
  ('ALL', 'sq_AL'),
  ('MKD', 'mk_MK'),
  ('MDL', 'ro_MD'),
  ('UAH', 'uk_UA'),
  ('ARS', 'es_AR'),
  ('BOB', 'es_BO'),
  ('BRL', 'pt_BR'),
  ('CLP', 'es_CL'),
  ('COP', 'es_CO'),
  ('GYD', 'en_GY'),
  ('PYG', 'es_PY'),
  ('PEN', 'es_PE'),
  ('SRD', 'nl_SR'),
  ('UYU', 'es_UY'),
  ('VES', 'es_VE')
);

ALTER TABLE public.bands
  DROP CONSTRAINT IF EXISTS bands_currency_locale_check;

ALTER TABLE public.bands
  ADD CONSTRAINT bands_currency_locale_check
  CHECK ((currency_code, locale) IN (
    ('USD', 'en_US'),
    ('USD', 'es_EC'),
    ('CAD', 'en_CA'),
    ('MXN', 'es_MX'),
    ('EUR', 'de_DE'),
    ('EUR', 'bg_BG'),
    ('GBP', 'en_GB'),
    ('CHF', 'de_CH'),
    ('PLN', 'pl_PL'),
    ('CZK', 'cs_CZ'),
    ('HUF', 'hu_HU'),
    ('DKK', 'da_DK'),
    ('SEK', 'sv_SE'),
    ('NOK', 'nb_NO'),
    ('ISK', 'is_IS'),
    ('RON', 'ro_RO'),
    ('RSD', 'sr_RS'),
    ('ALL', 'sq_AL'),
    ('MKD', 'mk_MK'),
    ('MDL', 'ro_MD'),
    ('UAH', 'uk_UA'),
    ('ARS', 'es_AR'),
    ('BOB', 'es_BO'),
    ('BRL', 'pt_BR'),
    ('CLP', 'es_CL'),
    ('COP', 'es_CO'),
    ('GYD', 'en_GY'),
    ('PYG', 'es_PY'),
    ('PEN', 'es_PE'),
    ('SRD', 'nl_SR'),
    ('UYU', 'es_UY'),
    ('VES', 'es_VE')
  ));

COMMENT ON COLUMN public.bands.locale IS
  'Locale for currency display formatting. Restricted to valid currency-locale pairs and defaults to en_US.';
