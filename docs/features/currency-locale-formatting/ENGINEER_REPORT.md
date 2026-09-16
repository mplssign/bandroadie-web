# Engineer Report

## Feature Slug

currency-locale-formatting

## Feature Title

Currency amounts format with US conventions regardless of the band's selected currency/country

## Cycle Number

3

## Goal

Format every financial display amount with the band's selected locale and currency, including the Financials PDF.

## Architect Tasks Completed

- Completed all ten architect tasks.
- Added locale-bound currency entries, a locale resolver, fallback, glyph, and Chile-only prefix override.
- Added `Band.locale` and locale-aware active-band equality.
- Migrated all planned money display call sites and the Financials PDF to `BandCurrency.format(int cents)`.
- Updated the band picker and both band update payloads to persist a valid currency-code/locale pair.
- Added the additive locale migration with invalid-only backfill and a 32-pair composite check.
- Updated all four planned test files for the locale-aware APIs and rendering behavior.

## Files Created

- supabase/migrations/20260915130000_add_locale_to_bands.sql

## Files Modified

- docs/features/currency-locale-formatting/ENGINEER_REPORT.md
- lib/app/models/band.dart
- lib/app/models/gig.dart
- lib/features/bands/active_band_controller.dart
- lib/features/bands/band_form_screen.dart
- lib/features/bands/currency/band_currency.dart
- lib/features/events/widgets/gig_expense_subview.dart
- lib/features/events/widgets/gig_form_fields.dart
- lib/features/financials/financials_pdf_preview_screen.dart
- lib/features/financials/financials_report_builder.dart
- lib/features/financials/financials_screen.dart
- lib/features/financials/models/financial_entry.dart
- lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart
- lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart
- lib/features/financials/widgets/gig_pay_bottom_sheet.dart
- lib/features/gigs/widgets/view_gig_drawer.dart
- test/features/bands/active_band_controller_invalidation_test.dart
- test/features/bands/band_currency_test.dart
- test/features/bands/band_model_test.dart
- test/features/financials/widgets/transaction_card_test.dart

## Analyzer Results

Yes. `flutter analyze` on all 19 changed Dart files completed with no issues.

## Test Results

Yes. Focused tests for the four planned test files passed: 24 passed, 0 failed.

## Code Efficiency/Bloat Check

- No new helper, extension, utility, provider, or private widget was added.
- Searched the existing currency formatting surface before implementation; no reusable locale-aware currency formatter existed. `BandCurrency` is the required owner of the new public API.
- `dart fix --dry-run` completed with nothing to fix.
- Reviewed the diff for redundant abstractions, dead APIs, unused parameters, comments, TODO/FIXME/debug output, and out-of-scope changes. None found.
- Changed Dart files remain within the plan's file-size targets; no exception is needed.

## Verification

- Yes. Verified branch `bug/currency-locale-formatting` with only the expected feature changes.
- Yes. Formatted only the 19 changed Dart files with `dart format`.
- Yes. Verified `BandCurrency.byLocale['es_CL']!.format(123450)` is `$1.234,50`; Argentina remains intl's suffix output.
- Yes. Static PDF check confirmed `financials_report_builder.dart` has no `NumberFormat.currency(` or `moneyFmt.format(`, has exactly four `currency.format(` money render sites, and accepts `required BandCurrency currency`.
- Yes. Static migration review confirmed column, invalid-only backfill, check, and comment ordering; no trigger or function; and retained the existing currency-code check migration unchanged.
- No. Did not run the ephemeral database apply-check or owner-run device/PDF export checks: this engineering session did not establish a throwaway database or launch the app, and production access is prohibited.

## Deviations From Plan

None.

## Blockers Encountered

None.

## Ready For QA

Yes