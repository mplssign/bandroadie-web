# QA Report

## Feature Slug

`feature/band-form-overlay-redesign`

## Feature Title

Band Form Overlay Redesign (Create & Edit) - Shared Header, Sectioned Layout, Currency Setting, Inline Backup/Restore

## Cycle Number

7

## Final Verdict

APPROVED

## Validation Summary

Cycle 7 closes the sole Cycle 6 blocking finding. The Engineer report no longer adds any configured prohibited work/debug marker literal, and the added-lines-only scan across the full tracked diff returns no matches. Cycle 7 is documentation-only: no application source, test, migration, configuration, or dependency changed during this cycle.

Independent SHA-256 checks exactly match the Engineer's frozen-state hashes for all three Cycle 6 Dart files. Focused analysis reports no issues and focused currency tests pass 10/10. The unchanged Cycle 6 full-suite evidence remains 355 passed, 0 failed, with full analysis reporting no issues.

The verified contract remains: USD is exactly `United States — US Dollar (USD)`, EUR is exactly `Eurozone / Bulgaria — Euro (EUR)`, no visible picker label contains `Ecuador`, and the picker remains 30 rows grouped 3 / 16 / 11. QA performed static code-path analysis and automated tests only. No app was launched and no database was contacted.

## Architect Scope Review

- Branch, plan, Engineer report, and requested slug match `feature/band-form-overlay-redesign`; the Engineer report records Cycle 7.
- Cycle 7's authorized implementation is restricted to `docs/features/band-form-overlay-redesign/ENGINEER_REPORT.md`; that report is the only Engineer-owned file changed this cycle.
- The three Cycle 6 Dart files are byte-identical to their previously verified label-correction state. Their independent hashes are `c1adf52a...02e6`, `b2a7ff2e...71a`, and `a1ca8d44...c5e3f` respectively.
- The current Dart diff still contains only the approved Cycle 6 label correction and focused assertion updates. No formatter, picker construction, ISO value, currency name, currency symbol, model, persistence path, provider, permission gate, initialization path, or platform code changed.
- No migration, RPC, RLS policy, function, dependency, configuration, or generated artifact changed in Cycle 7.
- `FEATURE_INPUT.md` and `PR_BODY.md` remain pre-existing untracked feature documents. The stale PR-body USD bullet remains an explicit Manager-sync residual.

## Completeness Check

- The Cycle 6 report-only blocker is closed: the Engineer report uses general documentation-safe wording, and the full added-lines scan passes.
- USD remains one America record with persisted/default ISO `USD`.
- The derived USD picker label is exactly `United States — US Dollar (USD)`.
- EUR remains one Europe record with exact picker label `Eurozone / Bulgaria — Euro (EUR)`.
- The picker remains 30 globally unique label/value rows grouped America 3, Europe 16, South America 11.
- No standalone Ecuador row exists and no visible picker label contains `Ecuador`.
- The exhaustive fixture still compares all 30 ordered records across country label, ISO code, currency name, and symbol/null.
- `band_currency_test.dart` is 160 lines, below the 220-line hard cap.
- Every cumulative Tier 1 gate required by the amended plan passed.

## Behavior Verification

Cycle 7 changed documentation only. The underlying behavior was reconfirmed through code-path analysis plus automated tests, not runtime app verification.

- Production USD has `countryLabel == 'United States'`; the unchanged `pickerLabel` getter derives `United States — US Dollar (USD)`.
- The exact 30-record test and picker test prove one USD row, default ISO `USD`, exact labels, cardinalities, and global ISO/label uniqueness.
- Picker-level negative coverage checks every visible key for the absence of `Ecuador`.
- EUR's Bulgaria composite and group placement remain covered and unchanged.
- Current formatting remains fixed to the existing `en_US` numeric pattern with two decimals. Locale-aware grouping, separator selection, and ISO-specific minor-unit precision were not implemented and remain an accepted out-of-scope product decision.

## Regression Check

- **Cycle 7 documentation repair: LOW.** No executable file changed; the prohibited-marker scan, focused analyzer, and focused tests pass.
- **Cycle 6 currency label/picker: LOW.** The frozen one-literal production correction remains covered by 10 focused tests and the prior 355-test full-suite pass.
- **Bands / active-band switching: MEDIUM cumulative.** Currency notification behavior remains covered by the full suite; Cycle 6 does not touch provider/controller code.
- **Band form / persistence / permissions: MEDIUM cumulative.** No Cycle 6 code change; compilation and full tests pass. Live create/edit behavior remains owner-run.
- **Financials, PDF, Gigs, and Events: MEDIUM cumulative.** No formatter or consumer changed in Cycle 6; full analysis/tests pass. Generated output remains owner-run.
- **Backup / restore: LOW.** No Cycle 6 path change; live file-picker behavior remains owner-run.
- **Auth, routing, notifications, calendar, init order, and platform parity: LOW.** No controlling source or configuration changed.
- **Controller/FocusNode disposal, async mounted safety, and rebuild frequency: LOW.** Cycle 6 does not touch stateful widget or controller code; analyzer is clean.

## Database Safety

Cycle 7 does not modify any migration or database-facing source, and QA did not contact any database.

- Static review reconfirmed the existing migration has `currency_code TEXT NOT NULL DEFAULT 'USD'` and the drop-before-add idempotent CHECK shape.
- The parsed CHECK list remains exactly 30 codes in application order, with 30 unique values.
- The migration contains no function, `SECURITY DEFINER`, grant/revoke, RLS policy, or cascade statement; function privilege checks are not applicable.
- Runtime apply/reapply, invalid-code rejection, and default/backfill behavior remain owner-run accepted residuals under the Cycle 5/6 plan amendment.

## Analyzer Results

- Cycle 7 focused analysis of the three frozen Dart files: PASS, no issues, 0.8 seconds.
- Cycle 6 full `flutter analyze` evidence remains PASS with no issues; it was not rerun because Cycle 7 changed documentation only.

## Test Results

- Cycle 7 focused currency and picker tests: PASS, 10 passed, 0 failed.
- Cycle 6 full Flutter suite evidence remains PASS, 355 passed, 0 failed; the full suite was not rerun because the tested Dart files are byte-identical.
- No live app, simulator, emulator, browser, or database test was run.

## Diff Safety Review

- `git diff --check`: PASS.
- Added-lines-only configured prohibited-marker scan across the full tracked diff: PASS, no matches.
- Engineer-report-specific prohibited-marker scan: PASS, no matches.
- High-confidence credential/private-key scan: PASS, no matches.
- Conflict-marker scan: PASS, no matches.
- No application/test source changed in Cycle 7, and the three frozen Dart hashes match exactly.
- The Cycle 6 Critical documentation finding is CLOSED.

## Change Budget Review

- Cycle 7 is within its documentation-only budget: one Engineer report rewrite and zero application/test/migration/configuration changes.
- Frozen cumulative Cycle 6 deltas remain `+1/-1` for `band_currency.dart`, `+4/-5` for `band_currency_test.dart`, and `+3/-3` for `band_currency_picker_test.dart`, all within their amendment caps.
- `band_currency_test.dart` remains 160 lines, below the 220-line hard cap; the picker test remains 56 lines.
- No new source/test file, public class, method, provider, dependency, migration, RPC, function, or policy was introduced.

## Code Efficiency Review

- Cycle 7 adds no implementation symbol or abstraction, so no equivalent-helper search is applicable.
- The offending report sentence was removed rather than supplemented with another workaround.
- No duplicate state, formatting path, wrapper, provider, flag, enum case, dead field, or speculative implementation was added.

## Manual Verification Punch List

QA did not execute any item below because these checks require a running app or database access. Tony owns their execution. Locale-aware number formatting is not part of the expected behavior: the existing `en_US`, two-decimal rendering remains in place pending a separate product decision about locale source and per-currency precision.

### Owner-Run Migration Verification - Ephemeral Apply Drill

1. Apply `20260915120000_add_currency_code_to_bands.sql` once to a local Supabase stack or disposable scratch database. **Expected:** it completes without SQL errors.
2. Re-apply the same migration to that scratch database. **Expected:** it completes idempotently and preserves the column and constraint.
3. Write `currency_code = 'ZZZ'` to an authorized test row. **Expected:** `bands_currency_code_check` rejects the write.
4. Insert a band without `currency_code`, or inspect an existing row after apply. **Expected:** `currency_code` is non-null and reads `USD`.

### App PR Testing - Staging/Dev With Migration Applied

1. Open Create New Band. **Expected:** `AppAppBar` shows a left-facing back arrow and title `New Band`; no `FrostedGlassBar` appears.
2. Scroll in light and dark themes. **Expected:** About, Location, and Invite Members are distinct, legible section cards.
3. Open the currency dropdown. **Expected:** exactly 30 rows appear as America 3, Europe 16, South America 11; USD appears once as `United States — US Dollar (USD)`; EUR appears once as `Eurozone / Bulgaria — Euro (EUR)`; no visible label contains `Ecuador`; no standalone Bulgaria or Ecuador row exists.
4. Select CAD. **Expected:** the collapsed field reads `Canada — Canadian Dollar (CAD)` without error.
5. Create a band with a name and invite email. **Expected:** creation/invite succeeds, the dashboard selects the new band, and stored `currency_code` is `CAD`.
6. Open Financials for the CAD band. **Expected:** summary totals and entries use `C$`, not `$`.
7. Open Add Financial Entry. **Expected:** amount, distribution, and savings inputs use `C$`; POS-style entry is unchanged.
8. Open or create a gig with pay and expenses. **Expected:** gig pay, expenses, event editor, and View Gig use `C$`.
9. Open Edit Band. **Expected:** `AppAppBar` has a back arrow; About, Location, and Band Data appear; Delete Band remains below the form outside Band Data.
10. Tap Backup Data. **Expected:** the native save picker opens directly without an intermediate sheet, and saving succeeds.
11. As an admin, restore the saved file. **Expected:** picker and confirmation appear, restore succeeds, and Financials still uses `C$`.
12. Change only currency from CAD to EUR and save. **Expected:** provider-backed surfaces update to `€` without a band switch or unrelated edit.
13. Export a Financials PDF. **Expected:** every money figure uses `€`; the existing two-decimal `en_US` numeric layout is unchanged. This does not validate locale-aware formatting.
14. As a member, open Edit Band. **Expected:** timezone/currency are disabled with admin-only helper text; Backup is visible; Restore and Delete are hidden.
15. As a contributor, open Edit Band. **Expected:** timezone/currency are disabled; Backup, Restore, and Delete are hidden.

### Owner-Run Migration Verification - Apply/Release Time

16. Before production apply, capture the total band count and query `currency_code` if the column is absent. **Expected:** total count succeeds; the currency query fails only because the migration is unapplied.
17. Apply the migration before deploying the client. **Expected:** it completes without SQL errors.
18. Re-apply the migration. **Expected:** it is an idempotent no-op preserving the same column and constraint.
19. Compare total bands with bands where `currency_code = 'USD'`. **Expected:** total count is unchanged and every pre-existing band defaults to `USD`.
20. Attempt one valid non-USD update and one invalid `ZZZ` update. **Expected:** the valid update succeeds and the invalid update is rejected.
21. Change a production band's currency as an admin. **Expected:** save succeeds, older clients remain functional, and the new client Financials/PDF use the selected symbol.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

1. **[implementation-gap] Stale Architect-plan compaction example.** [ARCHITECT_PLAN.md](docs/features/band-form-overlay-redesign/ARCHITECT_PLAN.md#L1290) still names the pre-Cycle-6 USD composite assertion. The Cycle 6 amendment and verification gates unambiguously supersede it, so this does not undermine the implementation result, but Architect should update the example to `United States` for internal consistency.

## Accepted Residuals / Dependencies

- Runtime migration behavior is deferred to Tony's owner-run checks; QA made no database connection or mutation.
- The migration must be applied in each target environment before a client that reads or writes `bands.currency_code` is deployed there.
- Visual layout, native file pickers, live role behavior, end-to-end persistence, and generated PDF appearance remain owner-run.
- The PR body still has the old USD bullet and requires Manager sync after QA re-verification.
- Locale-aware numeric formatting remains unresolved and explicitly out of scope. The feature still uses `en_US` grouping and two decimal places; no locale source or ISO-specific minor-unit policy has been selected or implemented.
- `activeBand.timezone` equality remains the previously accepted out-of-scope follow-up.
