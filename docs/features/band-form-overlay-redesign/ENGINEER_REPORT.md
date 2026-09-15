# Engineer Report

## Feature Slug

`feature/band-form-overlay-redesign`

## Feature Title

Band Form Overlay Redesign (Create & Edit) — Shared Header, Sectioned Layout, Currency Setting, Inline Backup/Restore

## Cycle Number

4

## Goal

Resolve every Cycle 3 Critical and Warning finding without changing settled feature behavior, applying the migration, or touching a database.

## Architect Tasks Completed

1. Added the idempotent `bands.currency_code` migration with the exact 30-code CHECK constraint. The migration was created but never applied.
2. Added `Band.currencyCode` with USD defaults and JSON serialization coverage.
3. Added the 30-entry currency shortlist, symbol/cent formatting, and pure three-group picker builder.
4. Added the theme-aware shared `SectionCard`.
5. Added configurable currency symbols to shared currency inputs.
6. Converted the five model money getters to currency-aware methods and updated every production consumer.
7. Threaded currency through Financials PDF preview/report generation.
8. Updated Financials summaries, savings, transactions, details, add-entry inputs, gig pay, gig expenses, gig form fields, event editor, and view-gig displays.
9. Rebuilt Create/Edit Band with `AppAppBar`, About/Location/Invite Members/Band Data cards, permission-aware currency editing, dirty-state tracking, and currency persistence.
10. Moved Backup and Restore inline into Band Data and kept permission-gated Delete Band at the bottom; removed the obsolete backup sheet and unused export dialog.
11. Updated all five plan-listed Financials widget test fixtures and added non-USD transaction rendering coverage.
12. Corrected all 13 reported curated-data mismatches: MXN symbol, PLN/CZK/HUF/ISK/ALL/MKD/UAH/PYG/PEN/VES labels, MDL symbol absence, and GYD symbol.
13. Re-audited all 30 records and added one explicit ordered fixture comparing every country label, ISO code, currency name, and symbol/null. Preserved the intentional `United States / Ecuador` and `Eurozone / Bulgaria` composite rows with no standalone duplicates.
14. Added focused formatting assertions for MXN `$`, GYD `G$`, and MDL ISO-code fallback.
15. Resolved C1 by adding only `activeBand?.currencyCode` to `ActiveBandState.==` and `hashCode`; timezone and every controller method remain unchanged.
16. Added the C1 provider-listener regression: a USD-to-CAD-only update stores CAD and notifies with CAD, while an identical second CAD update adds no notification.
17. Resolved C2 by compacting `band_currency_test.dart` from 292 to 161 lines while retaining the ordered 30-record, four-field comparison and every cardinality, composite, symbol, fallback, and formatting assertion.
18. Resolved W1 by consolidating the gig-pay active-band fallback; `gig_pay_bottom_sheet.dart` is now net +6 versus HEAD with unchanged behavior.
19. Confirmed the amended W2 contract: no `package:meta/meta.dart` import, immutable final fields and const constructors remain, and `pubspec.yaml` is untouched.

## Files Created

- `supabase/migrations/20260915120000_add_currency_code_to_bands.sql`
- `lib/features/bands/currency/band_currency.dart`
- `lib/features/bands/widgets/section_card.dart`
- `test/features/bands/band_currency_test.dart`
- `test/features/bands/band_currency_picker_test.dart`
- `test/features/bands/band_model_test.dart`
- `docs/features/band-form-overlay-redesign/ENGINEER_REPORT.md`

## Files Modified

- `lib/app/models/band.dart`
- `lib/app/models/gig.dart`
- `lib/features/bands/active_band_controller.dart`
- `lib/features/bands/band_form_screen.dart`
- `lib/features/events/widgets/event_editor_drawer.dart`
- `lib/features/events/widgets/gig_expense_subview.dart`
- `lib/features/events/widgets/gig_form_fields.dart`
- `lib/features/financials/financials_pdf_preview_screen.dart`
- `lib/features/financials/financials_report_builder.dart`
- `lib/features/financials/financials_screen.dart`
- `lib/features/financials/models/financial_entry.dart`
- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
- `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`
- `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`
- `lib/features/gigs/widgets/view_gig_drawer.dart`
- `lib/shared/widgets/currency_input_field.dart`
- `test/features/bands/active_band_controller_invalidation_test.dart`
- `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`
- `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart`
- `test/features/financials/widgets/financials_screen_scroll_test.dart`
- `test/features/financials/widgets/summary_header_test.dart`
- `test/features/financials/widgets/transaction_card_test.dart`

## Analyzer Results

- `dart fix --dry-run`: nothing to fix.
- Editor diagnostics for all four Cycle 4 Dart files: no errors.
- Full `flutter analyze`: no issues (3.0 seconds).

## Test Results

- Focused active-band regression: 2 passed, 0 failed.
- Focused band currency/picker/model and five Financials widget files: 86 passed, 0 failed.
- Full `flutter test`: 355 passed, 0 failed.
- SQL/static gate: one matching migration filename; exact ordered set of 30 codes; 30 total and 30 unique; required idempotent SQL present; zero `SECURITY DEFINER`, policy, grant, or revoke hits.
- Legacy money-getter search: zero matches in `lib/`. Dollar-literal search found matches only in the plan-approved `band_currency.dart` data and `currency_input_field.dart` USD defaults/comments.
- `git diff --check`: passed with no output.
- Ephemeral database apply/reapply and CHECK/default behavior tests were not run because Cycle 4 explicitly prohibited touching any database.

## Code Efficiency/Bloat Check

- Searched `lib/` for existing currency formatters/picker builders and section-card equivalents. No shared currency helper existed; the existing `_SectionCard` implementations are private and fixed-dark, so the plan-listed theme-aware widget was required.
- No provider, notifier, repository, dependency, barrel file, speculative flag, or unrelated abstraction was added.
- `band_form_screen.dart` remains above the container-widget target at 2,215 lines, but this change removes 210 net lines while retaining existing upload/backup/restore behavior in the plan-required file.
- Other touched files already above their applicable targets (`event_editor_drawer.dart`, `gig_expense_subview.dart`, `gig_form_fields.dart`, `financials_report_builder.dart`, `financials_screen.dart`, `add_financial_entry_bottom_sheet.dart`, `financial_entry_details_bottom_sheet.dart`, `view_gig_drawer.dart`, and `currency_input_field.dart`) received only required currency plumbing; extracting them would exceed the plan-listed scope.
- `band_currency.dart` is 267 lines versus the 150–210 estimate because it keeps all 30 required records explicit and reviewable; it remains below the 500-line Dart target.
- No `TODO`, `FIXME`, new `debugPrint`, dead formatter getter, or obsolete backup-sheet entry point remains in the changed implementation.
- Cycle 4 added no helper, widget, provider, abstraction, dependency, or production branch. The ordered fixture uses one `List<Map<String, Object?>>` and executes four indexed field assertions for each of all 30 records.
- The Cycle 3 defect was incorrect existing data, so the fix replaces/removes the defective values rather than layering checks over them.
- C1 is a genuine missing equality-field check, so its root-cause fix necessarily adds two lines without deleting existing controller code.
- Final Cycle 4 budgets: `active_band_controller.dart` net +2 (cap +3); active-band regression test net +48 (cap +50); `band_currency_test.dart` 161 lines (cap 220, target 110–180); `gig_pay_bottom_sheet.dart` net +6 (cap +6).

## Verification

- Verified Create mode section order: About, Location, Invite Members.
- Verified Edit mode section order: About, Location, Band Data, followed by Save Changes, Cancel, and permission-gated Delete Band.
- Verified Backup uses `canExportBandData`, Restore/Delete use `canDeleteBand`, and currency/timezone use `canEditBandSettings`.
- Verified the currency picker is built solely from the tested pure builder: America 3, Europe 16, South America 11.
- Verified create and edit persistence include `currency_code`, and active-band state receives the edited value.
- Verified all money input/display/PDF paths resolve currency from the active band with USD fallback.
- Re-audited every production record against the explicit expected fixture, including accents and null symbols; the fixture passes as an ordered equality check.
- Verified MXN formats as `$1,500.00`, GYD as `G$1,500.00`, and MDL as `MDL1,500.00`.
- Verified a currency-only USD-to-CAD `updateActiveBand` stores CAD and emits a listener notification; repeating the identical CAD state emits no additional notification.
- Ran `dart format` on the four Cycle 4 Dart files; final check reported 0 changes.
- `git diff --check`: passed with no output.
- Verified `active_band_controller.dart` has exactly two added lines, no timezone change, and no controller-method change.
- Verified no `package:meta/meta.dart` import or legacy formatted-money getter remains in `lib/`; `pubspec.yaml` is unchanged.
- No live app or database verification was performed; owner-run staging/production steps remain as listed in the Architect Plan.

## Deviations From Plan

- No Cycle 4 code deviation. The amended plan explicitly approves immutable-by-final-fields/const constructors without `package:meta` and keeps `pubspec.yaml` off-limits.
- Did not run ephemeral database apply/reapply checks because Cycle 4 explicitly prohibited applying the migration or touching a database. The migration was statically validated and remains unapplied.
- The explicit currency data module is 267 lines rather than the estimated 150–210 lines; no records or required behavior were omitted to meet the estimate.
- Cycle 4 changed only the four authorized Dart files and this report. All existing uncommitted implementation was preserved.

## Blockers Encountered

None.

## Ready For QA

Yes.