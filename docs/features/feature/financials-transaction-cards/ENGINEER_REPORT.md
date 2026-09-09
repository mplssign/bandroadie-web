# ENGINEER_REPORT — feature/financials-transaction-cards

## Feature Slug
`feature/financials-transaction-cards`

## Feature Title
Financials screen — replace transaction table with cards, add summary header

## Cycle Number
7

## Goal
Two narrow, direct Tony requests during testing (not a new Architect plan):
1. Use the smallest Forui select size (`sm`) for the date-filter dropdown on
   the financials summary header.
2. Change the financial entry detail sheet's `_DetailRow` from a
   label-above-value stacked layout to a label-left/value-right side-by-side
   layout, matching the pattern already used in `view_gig_drawer.dart`'s
   `_DetailRow`.

## Architect Tasks Completed
N/A — this cycle was driven directly by Manager-relayed Tony requests, not a
new `ARCHITECT_PLAN.md` revision. Both requested changes were implemented as
specified:

1. **`AppDropdown<T>` size passthrough** — added an optional, nullable
   `size` constructor parameter of type `FTextFieldSizeVariant?` (default
   `null`) to `lib/components/ui/app_dropdown.dart`. Confirmed via
   `forui-0.26.0` source (`select/single/select.dart`,
   `select/single/basic_select.dart`) that `FSelect`'s underlying `size`
   field is non-nullable `FTextFieldSizeVariant`, defaulting to
   `FTextFieldSizeVariant.md` at the base factory. `build()` therefore
   passes `size: size ?? FTextFieldSizeVariant.md` to both `FSelect<T>.rich`
   call sites — identical resolved value to the pre-existing behavior when
   `size` is left unset, so this is 100% backward compatible. Grepped `lib/`
   for all `AppDropdown<` usages (7 call sites across
   `band_form_screen.dart`, `event_editor_helpers.dart`,
   `gig_expense_subview.dart` (x2), `financials_screen.dart`,
   `add_financial_entry_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`) —
   none pass `size`, so all resolve to `.md` exactly as before.
2. **Financials date-filter dropdown** — in
   `lib/features/financials/financials_screen.dart`, added
   `import 'package:forui/forui.dart';` (not previously present) and passed
   `size: FTextFieldSizeVariant.sm` to the `AppDropdown<FinancialDateFilter>`
   inside `_SummaryHeader`.
3. **Detail sheet side-by-side layout** — reworked `_DetailRow` in
   `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`
   from a single `Expanded > Column` (label above value) to a `Row` with a
   fixed `SizedBox(width: 68)` for the label (unchanged style: footnote /
   `textMuted`) and an `Expanded > Column` for the value (unchanged style:
   callout / `textPrimary`), mirroring `view_gig_drawer.dart`'s `_DetailRow`
   layout shape. Did not add `subtitle`, `showChevron`, `onTap`, or a
   per-row `Divider` — this file's `_DetailRow` has no equivalent for any of
   those and none were requested.

## Files Created
None.

## Files Modified
- `lib/components/ui/app_dropdown.dart`
- `lib/features/financials/financials_screen.dart`
- `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`
- `docs/features/feature/financials-transaction-cards/ENGINEER_REPORT.md`

## Analyzer Results
`flutter analyze` on the three changed files:
```
Analyzing 3 items...
No issues found! (ran in 2.7s)
```
Clean at every severity.

## Test Results
Ran the following via the test runner:
- `test/components/ui/app_dropdown_test.dart`
- `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart`
- `test/features/financials/widgets/transactions_list_header_test.dart`
- `test/features/financials/widgets/summary_header_test.dart`
- `test/features/financials/widgets/transaction_card_test.dart`

Result: **47 passed, 0 failed.** No test-side edits were needed — the
existing `financial_entry_details_bottom_sheet_test.dart` assertions
(text-content based, not position-based) were unaffected by the layout
change.

## Code Efficiency/Bloat Check
- No new helpers, extensions, utils, or private widget classes were added.
  The `size` field is a plain passthrough parameter on an existing widget;
  no new abstraction was introduced.
- No files exceeded their size targets as a result of this change (both
  touched files remain well under their respective limits).
- No dead code, unused imports, or AI-shaped patterns introduced.

## Verification (manual steps performed)
- Read `forui-0.26.0`'s `FSelect` source
  (`select/single/select.dart`, `select/single/basic_select.dart`) to confirm
  `size`'s type, nullability, and default (`FTextFieldSizeVariant.md`)
  before choosing the passthrough default, per the plan's instruction to
  check "FSelect's actual default/required-ness" first.
- Grepped all `AppDropdown<` call sites in `lib/` to confirm none pass
  `size` and none would change appearance.
- Read `view_gig_drawer.dart`'s `_DetailRow` (lines ~509–583) as the
  reference layout pattern and confirmed the financials sheet's current
  `_DetailRow` usage/styling (footnote/textMuted label, callout/textPrimary
  value, no subtitle/chevron/onTap/divider) before adapting only the
  side-by-side structure.
- Ran `flutter analyze` and the full targeted test suite (see above).
- Ran `dart format` on all three changed files (0 changed — already
  correctly formatted).

## Deviations From Plan
None. Both changes implemented exactly as specified by Manager.

## Blockers Encountered
None.

## Ready For QA
Ready For QA: Yes

