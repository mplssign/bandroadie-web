# QA Report

**Feature Slug:** fix-stale-currency-picker-assertions
**Feature Title:** Fix stale assertions in `band_currency_picker_test.dart` (post-PR #308)
**Cycle Number:** 1
**Final Verdict:** APPROVED

## Process Note (Out-of-Process Cycle)

This cycle skipped the Architect/Engineer stages by Tony's explicit authorization: a
trivial, test-only fix with no design decision involved. There is no
`ARCHITECT_PLAN.md` or `ENGINEER_REPORT.md` for this slug. Manager invoked QA
directly for independent review of Tony's own uncommitted diff on `main`, per the
standing rule that no commit/push/PR happens without a QA APPROVED verdict. Because
there is no Architect plan, the validation authority for this cycle is the actual
behavior of `lib/features/bands/currency/band_currency.dart` (the source of truth
for what the picker produces) — the assertions were checked against that code
directly rather than against a plan document.

## Validation Summary

Reviewed `git diff` of the single modified file directly (Tony's own diff, not an
Engineer's), cross-checked every changed assertion against
`lib/features/bands/currency/band_currency.dart`, confirmed no other files were
touched, and ran `flutter analyze` and the full `flutter test` suite myself.

## Architect Scope Review

N/A — no Architect plan for this cycle (explicitly authorized skip, documented above).

## Completeness Check

All four described stale assertions were updated:
1. Group cardinalities: America 3→4, Europe 16→17, South America unchanged at 11
   (total 30→32).
2. Uniqueness test updated from 30 to 32 unique entries/keys/values.
3. Composite-row test rewritten to assert two distinct USD rows
   (`United States — US Dollar (USD)`, `Ecuador — US Dollar (USD)`) and two distinct
   EUR rows (`Eurozone (generic) — Euro (EUR)`, `Bulgaria — Euro (EUR)`) instead of
   the old single-composite-row shape.
4. The "Ecuador absent" test was replaced with a test confirming Ecuador
   (`es_EC`) and Bulgaria (`bg_BG`) are present as their own rows with the correct
   locale values.

No partial updates or skipped assertions found.

## Behavior Verification

Confirmed by code-path analysis only (reading `band_currency.dart` and running the
test suite) — no manual/runtime device or app instance was launched, consistent
with QA's restriction on driving a live app instance.

Verified against `BandCurrency.shortlist` and `pickerGroups()` in
[band_currency.dart](lib/features/bands/currency/band_currency.dart):

- **Group cardinalities:** America = 4 (United States, Ecuador, Canada, Mexico),
  Europe = 17 (Eurozone (generic), Bulgaria, United Kingdom, Switzerland, Poland,
  Czechia, Hungary, Denmark, Sweden, Norway, Iceland, Romania, Serbia, Albania,
  North Macedonia, Moldova, Ukraine), South America = 11. Total = 32. Matches the
  new assertions exactly.
- **Ecuador row:** `countryLabel: 'Ecuador'`, `isoCode: 'USD'`, `locale: 'es_EC'` →
  `pickerLabel` = `'Ecuador — US Dollar (USD)'`. Matches test's expected label and
  locale value exactly.
- **Bulgaria row:** `countryLabel: 'Bulgaria'`, `isoCode: 'EUR'`,
  `locale: 'bg_BG'` → `pickerLabel` = `'Bulgaria — Euro (EUR)'`. Matches exactly.
- **Generic Eurozone row:** `countryLabel: 'Eurozone (generic)'`, `isoCode: 'EUR'`
  → `pickerLabel` = `'Eurozone (generic) — Euro (EUR)'`. Matches exactly.
- **Uniqueness:** manually enumerated all 32 `countryLabel` values (all distinct)
  and all 32 `locale` values (all distinct) in `shortlist` — confirms
  `hasLength(32)` on both the label-key set and locale-value set is correct, not
  just numerically coincidental.
- **USD/EUR row counts:** only two entries in `shortlist` carry `isoCode: 'USD'`
  (United States, Ecuador) and only two carry `isoCode: 'EUR'` (Eurozone (generic),
  Bulgaria) — confirms `hasLength(2)` for both `usdRows`/`eurRows` filters is
  correct and no other label accidentally contains the substrings `(USD)`/`(EUR)`.

This is a pure test-assertion fix. No application/shipped code was touched — the
underlying picker behavior (from PR #308) is unchanged by this diff; only the test
expectations were brought in line with it.

## Regression Check

**Risk: LOW.** Diff is confined to one test file; no source, migration, or config
file was modified (confirmed via `git status --short`, single file). No
auth/session, RPC, init-order, platform-parity, disposal, or `setState`-after-async
surfaces are touched. No regression risk to shipped behavior since the underlying
picker implementation is untouched — this fix only makes the test suite reflect
reality again.

## Database Safety

N/A — no migrations, no `.sql` files, no `SECURITY DEFINER` functions in the diff.

## Analyzer Results

```
flutter analyze test/features/bands/band_currency_picker_test.dart
Analyzing band_currency_picker_test.dart...
No issues found! (ran in 0.8s)
```

Clean at every severity.

## Test Results

Ran the full suite (`flutter test`), not just the changed file, since a
suite-wide regression check was warranted:

```
flutter test
...
01:20 +337: All tests passed!
```
Exit code: 0. Confirmed via direct grep of the log that all four
`band_currency_picker_test.dart` cases (`picker groups have the exact order and
cardinalities`, `picker rows have globally unique labels and locale values`, `USD
and EUR each have two distinct country rows`, `Ecuador and Bulgaria are their own
distinct rows, each with the correct locale`) ran and passed. The four "Failed
assertion" strings found elsewhere in the log are pre-existing, expected console
output from unrelated controller error-logging tests (Supabase not initialized in
that test's harness) and a literal test name (`A 502 accept_failed...`) — none are
related to this file or actual test failures.

## Diff Safety Review

No secrets/API keys. No `TODO`/`FIXME`/`debugPrint(` anywhere in the diff (checked
directly against the diff content). No leftover test scaffolding, no accidental
deletions, no unrelated formatting churn — diff is limited to the four test bodies
described.

## Change Budget Review

No Architect plan/Change Budget exists for this cycle (authorized skip). Diff
scope is proportionate to the stated problem: 4 assertion blocks changed to match
a known, already-merged behavior change (PR #308); no new files, no new
symbols/helpers, no dependency changes.

## Code Efficiency Review

No new symbols, helpers, providers, or abstractions introduced. Test rewrites use
existing `BandCurrency`/`pickerGroups()` API only. Nothing to flag.

## Manual Verification Punch List

None required. This change affects only test assertions and does not require
runtime/device verification.

## Issues Found

None.

### Critical
None.

### Warnings
None.

### Suggestions
None.
