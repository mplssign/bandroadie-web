## Summary

- Format financial amounts with the band's selected country locale instead of US or device defaults.
- Restore separate United States/Ecuador and Eurozone/Bulgaria currency choices, and persist the locale alongside the currency code.
- Use the same locale-aware formatter for on-screen amounts and Financials PDF exports.
- Add an additive `bands.locale` migration with a deterministic backfill and a 32-pair currency/locale constraint.

## Behavior

- Chilean pesos render as `$1.234,50` through a narrowly scoped Chile placement override.
- Generic Eurozone euros render as `1.234,50 €`.
- Swiss francs render with the `CHF` glyph and apostrophe grouping.
- Every currency keeps two decimal places, preserving the existing integer-cents storage model.
- Locale-only changes for the same currency code now invalidate active-band state and rebuild dependent displays.

## Verification

- Full `flutter analyze`: no issues.
- Focused currency, band model, active-band invalidation, and transaction card tests: 22 passed.
- Financials PDF builder statically verified to use only `BandCurrency.format(int cents)` for money.
- Migration applied and exercised against a disposable local PostgreSQL cluster: backfill, reapplication, all 32 valid pairs, and invalid-pair rejection passed.
- Independent QA verdict: APPROVED.

## Database

This PR adds `supabase/migrations/20260915130000_add_locale_to_bands.sql`. Applying database migrations and shipping an app build remain outside this PR pipeline.

## Manual Verification

The rendered PDF export and on-device iOS/Android presentation still require owner testing before merge. See the QA punch list in `docs/features/currency-locale-formatting/QA_REPORT.md`.