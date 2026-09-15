# QA Report

## Feature Slug

`feature/band-form-overlay-redesign`

## Feature Title

Band Form Overlay Redesign (Create & Edit) - Shared Header, Sectioned Layout, Currency Setting, Inline Backup/Restore

## Cycle Number

5

## Final Verdict

APPROVED

## Validation Summary

The complete uncommitted implementation matches the amended Architect plan. QA reviewed every tracked hunk and all six created implementation/test/migration files, then ran the full Tier 1 gate. Analyzer, focused tests, full tests, formatting, diff safety, static SQL, secret, and money-path checks all pass.

QA performed source-level code-path analysis and automated tests only. No app was launched and no database was contacted. Per the Cycle 5 amendment, runtime migration execution is an accepted owner-run dependency and is not a QA approval gate.

Prior finding closure:

- **C1 [root-cause-diagnosis]: CLOSED.** `ActiveBandState.==` and `hashCode` add only `activeBand?.currencyCode`. The focused test proves USD-to-CAD notification, stored CAD state, and identical-CAD deduplication.
- **C2 [code-quality]: CLOSED.** `band_currency_test.dart` is 161 lines, below the 220-line cap, while retaining the ordered 30-record, four-field fixture and focused formatter assertions.
- **W1 [code-quality]: CLOSED.** `gig_pay_bottom_sheet.dart` is net `+6`, exactly at the amended cap, with active-band symbol selection and USD fallback.
- **W2 [implementation-gap]: CLOSED.** `BandCurrency` and `BandCurrencyPickerGroup` use final fields and const constructors. No `package:meta/meta.dart` import or `pubspec.yaml` change exists.
- **C3 [database-safety]: CLOSED BY PLAN AMENDMENT.** Static SQL remains the QA gate. Runtime apply/reapply/default/CHECK execution is accepted as owner-run Tier 2 verification, with no code or migration change required.

## Architect Scope Review

- Branch, plan, report, and requested slug all match `feature/band-form-overlay-redesign`.
- Reviewed 22 modified source/test files and six created implementation/test/migration files. Pipeline documents remain confined to the feature directory.
- All touched application, test, and migration paths are plan-authorized. No additional implementation file, dependency, provider, notifier, repository, RPC, policy, trigger, or function was added.
- Off-limits `create_band`, `get_band_full_state`, RLS migrations, `data_backup_service.dart`, `band_repository.dart`, `edit_band_screen.dart`, `main.dart`, runtime configuration, and `pubspec.yaml` are unchanged.
- The active-band controller diff is exactly two additions in equality/hash. No controller method or timezone comparison changed.

## Completeness Check

- Create and Edit use `AppAppBar` with `AppIcons.arrowLeft`; back and cancel preserve edit-draft cancellation.
- About and Location section cards appear in both modes. Invite Members is create-only. Band Data is edit-only. Delete Band remains below Save Changes/Cancel and outside Band Data.
- Currency defaults to USD, initializes from the edited band, participates in dirty state, persists through create/edit payloads, and is copied into the updated active `Band`.
- Timezone/currency use `canEditBandSettings`; Backup uses `canExportBandData`; Restore/Delete use `canDeleteBand`.
- Backup and Restore call the existing export/import flows directly. The obsolete backup/restore sheet, panel widget, and unused export dialog are deleted.
- The picker is built only from `BandCurrency.pickerGroups()`: America 3, Europe 16, South America 11.
- Financials, PDF, Gigs, Events, input, details, savings, transaction, and View Gig money paths use active-band currency with USD fallback.

## Behavior Verification

This was source-level code-path analysis plus automated tests, not runtime app verification.

- The production shortlist and exhaustive fixture match in exact order across `countryLabel`, `isoCode`, `name`, and `symbol`/null for all 30 records.
- Picker values are exactly `USD,CAD,MXN,EUR,GBP,CHF,PLN,CZK,HUF,DKK,SEK,NOK,ISK,RON,RSD,ALL,MKD,MDL,UAH,ARS,BOB,BRL,CLP,COP,GYD,PYG,PEN,SRD,UYU,VES`, with 30 unique values and labels.
- USD and EUR labels are exactly `United States / Ecuador — US Dollar (USD)` and `Eurozone / Bulgaria — Euro (EUR)`; no standalone Bulgaria or Ecuador row exists.
- Corrected supplied records remain intact, including MXN `$`, GYD `G$`, MDL with no symbol, and the supplied accented names/symbols. CHF/RSD/MKD/MDL use ISO fallback where no symbol is configured.
- Create performs one post-RPC band update containing timezone and `currency_code`, then calls `loadAndSelectBand`. Edit updates `currency_code`, constructs the matching `Band`, and calls `updateActiveBand`.
- Currency-only active-band propagation is notification-safe and identical-state updates remain deduplicated.
- Five parameterless money getters were replaced by currency-aware methods; no legacy getter consumer remains in `lib/`.
- Shared currency input defaults remain USD-compatible, while every planned input call site supplies the active band's symbol.
- Existing backup export selects the full band row, existing-band restore upserts the band row, and `get_band_full_state` serializes `b.*`, so `currency_code` follows the established round-trip paths.

## Regression Check

- **Bands / active-band switching: MEDIUM.** Equality/hash changed only for currency and focused notify/dedup coverage passes. Timezone remains deliberately out of scope.
- **Band Form UI / persistence / permissions: MEDIUM.** Source paths and automated checks pass; visual layout and live persistence remain owner-run.
- **Financials and PDF: MEDIUM.** Every planned path is currency-aware and widget tests pass, including CAD rendering; generated PDF appearance remains owner-run.
- **Gigs and Events: MEDIUM.** Display and input consumers use active-band currency with USD fallback; live interaction remains owner-run.
- **Backup / restore: LOW.** Only entry-point UI changed; established full-row export/restore behavior remains intact.
- **Database / release ordering: MEDIUM.** Static migration review passes. Runtime execution is an explicit owner-run dependency before any client uses the new column.
- **Auth, routing, notifications, calendar, init order, and platform parity: LOW.** Their controlling files and native/web split are unchanged; auth compatibility and the full suite pass.
- **Controller/FocusNode disposal and async mounted safety: LOW.** Consumer conversions preserve disposal; touched async state writes are mounted-guarded; analyzer is clean.

## Database Safety

Migration status: **created, statically validated, and unapplied by this pipeline; no database was contacted**.

- Filename is uniquely `20260915120000_add_currency_code_to_bands.sql` and sorts after `20260912130000_demo_session_capacity_hardening.sql`.
- SQL contains `ADD COLUMN IF NOT EXISTS currency_code TEXT NOT NULL DEFAULT 'USD'` on `public.bands`.
- `DROP CONSTRAINT IF EXISTS bands_currency_code_check` precedes `ADD CONSTRAINT bands_currency_code_check`.
- Parsed CHECK order is exactly the 30-code application order; total is 30 and unique count is 30.
- The migration contains no function, RPC, RLS policy, trigger, cascade, `SECURITY DEFINER`, `GRANT`, or `REVOKE` statement. Function privilege checks are not applicable.
- Existing `bands_update_admins` remains row-scoped with matching `USING` and `WITH CHECK`; no authorization surface changed.
- Accepted residual: runtime DB execution is deferred to the owner-run Tier 2 punch list. Apply/reapply, invalid-code rejection, and default/backfill behavior are not runtime-confirmed by QA and do not block approval under the Cycle 5 amendment.

## Analyzer Results

- Full `flutter analyze`: PASS, no issues, 6.2 seconds.

## Test Results

- Focused Tier 1 suite: PASS, 95 passed, 0 failed.
- Full Flutter suite: PASS, 355 passed, 0 failed.
- Focused coverage includes the exact currency contract, picker cardinality/uniqueness/composites, model default/round-trip, C1 notify/dedup, auth compatibility, USD Financials regressions, and CAD transaction rendering.
- No live app, simulator, emulator, browser, or database test was run.

## Diff Safety Review

- `git diff --check`: PASS.
- `dart format --output=none --set-exit-if-changed` across all 27 changed/new Dart files: PASS, 0 changed.
- Added-line and created-file scans found no `TODO`, `FIXME`, `debugPrint(`, conflict marker, or temporary scaffolding.
- High-confidence credential, token, and private-key scan: no matches.
- Legacy money-getter and disallowed hardcoded-money scans: no matches. Dollar literals remain only in the curated currency data and backward-compatible USD defaults/comments in the shared currency input file.
- No accidental deletion, stale backup sheet, or generated artifact was found.

## Change Budget Review

- Tracked modifications: `+658/-679`, net `-21`.
- Six created implementation/test/migration files: 593 lines.
- Overall implementation/test/migration delta: `+1251/-679`, net `+572`, excluding pipeline documents and this report.
- `active_band_controller.dart`: net `+2` against cap `+3`.
- Active-band regression test: net `+48` against cap `+50`.
- `band_currency_test.dart`: 161 lines against hard cap 220 and target 110-180.
- `gig_pay_bottom_sheet.dart`: net `+6` against hard cap `+6`.
- `band_form_screen.dart`: net `-210`, within the planned `-350` to `-150` range.
- `band_currency.dart`: 267 lines versus the 210 estimate, 1.27x the upper bound and within the 1.5x tolerance; the Engineer supplied the required justification.
- All other new-file sizes and modified-file deltas are within tolerance or smaller through additional deletion.

## Code Efficiency Review

- Independent search found no pre-existing shared currency formatter, picker-group builder, or public theme-aware `SectionCard` equivalent.
- Existing private fixed-dark `_SectionCard` implementations remain unchanged as required.
- No speculative provider, notifier, repository, dependency, barrel, flag, enum, field, or single-call wrapper was introduced.
- Currency data, picker labels, symbols, ISO fallback, and cent formatting are centralized in one module.
- C1 is a genuine missing equality-field check; its zero-deletion, two-line fix is justified in the Engineer report.
- Existing oversized touched files have explicit Engineer justifications, and no unrelated extraction or formatting churn was introduced.

## Manual Verification Punch List

QA did not execute any item below because each requires a running app or database access. Tony should execute these steps directly.

### Owner-Run Migration Verification - Ephemeral Apply Drill

1. On a local Supabase stack or disposable scratch database, apply `20260915120000_add_currency_code_to_bands.sql` once. **Expected:** it completes without SQL errors.
2. Re-apply the same migration to the same scratch database. **Expected:** it completes as an idempotent no-op and preserves the same column and constraint.
3. Insert or update an authorized test row with `currency_code = 'ZZZ'`. **Expected:** `bands_currency_code_check` rejects the write.
4. Insert a band without `currency_code`, or inspect an existing row after apply. **Expected:** `currency_code` reads `USD` and is non-null.

Stop and return to Architect if any ephemeral drill step fails.

### App PR Testing - Staging/Dev With Migration Applied

1. Open Create New Band. **Expected:** shared `AppAppBar`, left-facing back arrow, title `New Band`, and no `FrostedGlassBar`.
2. Scroll the form in light and dark themes. **Expected:** About, Location, and Invite Members are distinct rounded section cards with legible theme-aware text and borders.
3. Open the currency dropdown. **Expected:** exactly 30 selectable rows grouped as America 3, Europe 16, and South America 11, in that order; USD appears once as `United States / Ecuador — US Dollar (USD)`, EUR appears once as `Eurozone / Bulgaria — Euro (EUR)`, and no standalone Bulgaria or Ecuador row exists.
4. Select CAD. **Expected:** the collapsed field reads `Canada — Canadian Dollar (CAD)` with no error.
5. Enter a band name and invite email, then create the band. **Expected:** creation and invite behavior succeed, the dashboard opens on the new band, and the stored `currency_code` is `CAD`.
6. Open Financials for the CAD band. **Expected:** summary totals and every entry use `C$`, not `$`.
7. Open Add Financial Entry. **Expected:** amount, distribution, and savings input prefixes/hints use `C$`; POS-style entry is unchanged.
8. Open or create a gig with pay and expenses. **Expected:** gig pay input/display, expense input/display, event editor, and View Gig drawer use `C$`.
9. Open Edit Band. **Expected:** the header uses `AppAppBar` with a back arrow; About, Location, and Band Data appear; Delete Band remains at the bottom outside Band Data.
10. Tap Backup Data. **Expected:** the native save picker opens directly with no intermediate backup/restore sheet; saving succeeds.
11. As an admin, tap Restore Data and restore the saved file. **Expected:** the file picker and confirmation appear, restore succeeds, and Financials still uses `C$`.
12. Change only currency from CAD to EUR and save. **Expected:** save succeeds and provider-backed surfaces update to `€` without a band switch or unrelated edit.
13. Export and inspect a Financials PDF. **Expected:** every money figure uses `€`, two-decimal formatting/layout is unchanged, and no `$` or `C$` remains.
14. As a member, open Edit Band. **Expected:** timezone/currency are disabled with admin-only helper text; Backup is visible; Restore and Delete are hidden.
15. As a contributor, open Edit Band. **Expected:** timezone/currency are disabled; Backup, Restore, and Delete are hidden.

### Owner-Run Migration Verification - Apply/Release Time

16. Before production apply, capture the total band count. If the column is absent, query `currency_code`. **Expected:** total count succeeds and the currency query fails only because the migration is still unapplied.
17. Apply the migration to production before deploying the client. **Expected:** it completes without SQL errors.
18. Re-apply the migration. **Expected:** it completes as an idempotent no-op and preserves the same column and constraint.
19. Compare post-apply total bands with bands where `currency_code = 'USD'`. **Expected:** total band count is unchanged and every pre-existing band has `currency_code = 'USD'`.
20. Attempt an authorized valid non-USD update and an invalid `ZZZ` update. **Expected:** the valid update succeeds and `ZZZ` is rejected by `bands_currency_code_check`.
21. Change a production band's currency as an admin after migration and before/with the client release. **Expected:** save succeeds, older clients remain functional, and the new client Financials/PDF use the selected symbol.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.

## Accepted Residuals / Dependencies

- Runtime migration apply/reapply/default/CHECK behavior remains unexecuted by QA and is explicitly deferred to Tony's Tier 2 steps.
- The migration must be applied in each target environment before any client build that selects or writes `bands.currency_code` runs there.
- Visual layout, theme rendering, native file pickers, live role behavior, end-to-end persistence, and generated PDF appearance remain owner-run app checks.
- `activeBand.timezone` remains absent from equality/hash by explicit scope and is a documented follow-up.
