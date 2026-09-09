# ENGINEER_REPORT — feature/financials-transaction-cards

## Feature Slug
`feature/financials-transaction-cards`

## Feature Title
Financials screen — replace transaction table with cards, add summary header

## Cycle Number
6

## Goal
Cycle 6 is a design-reversal revision landing on the Cycle 4 tree: reintroduce a
three-value `FinancialDateFilter { allTime, thisYear, thisMonth }` enum (no
`custom` case) to replace Cycle 4's `selectedYear: int` scalar, default the
filter to `thisYear`, and render it as an inline `AppDropdown<FinancialDateFilter>`
inside `_SummaryHeader` (format: `'All time'` / `'This year'` / `'This month'` —
`thisYear` renders textually, not as a numeral, reversing Cycle 4's behavior).
`FinancialsPdfPreviewScreen`'s constructor swaps back from `selectedYear: int` to
`dateFilter: FinancialDateFilter` with a 3-case `_filterLabel`. Cycle 5's inline
placement and empty-state build restructuring (header/dropdown stay visible when
the list is empty) are preserved verbatim.

## Architect Tasks Completed
1. `financials_controller.dart`: reintroduced `enum FinancialDateFilter { allTime, thisYear, thisMonth }` (no `custom`). Deleted the `selectedYear` field, its constructor/`copyWith` params, and the runtime-default initialiser. Added `final FinancialDateFilter dateFilter` with a compile-time-const default of `FinancialDateFilter.thisYear`; restored the `const` constructor. `copyWith` updated to take `FinancialDateFilter? dateFilter`. `_applyDateFilter` rewritten as a 3-case switch (`allTime` → unfiltered, `thisYear` → `entryDate.year == now.year`, `thisMonth` → year+month match), preserving the trailing newest-first sort. `setSelectedYear(int)` deleted; `setDateFilter(FinancialDateFilter)` added.
2. `financials_pdf_preview_screen.dart`: constructor's `int selectedYear` swapped for `required FinancialDateFilter dateFilter`. `_filterLabel` rewritten as a 3-case switch: `allTime → 'All time'`, `thisYear → 'Year ${now.year}'` (preserves the Cycle 4 default-case filename shape), `thisMonth → DateFormat('MMMM yyyy').format(now)`.
3. `financials_screen.dart`: added `import '../../components/ui/app_dropdown.dart';`. Deleted `_YearSelector`, `_YearSelectorChip`, `_availableYears`. Added top-level `_dateFilterLabel(FinancialDateFilter)` helper returning the three exact label strings. Replaced the single `Text('${state.selectedYear} • ...')` line inside `_SummaryHeader` with `Row(IntrinsicWidth(AppDropdown<FinancialDateFilter>(value: state.dateFilter, onChanged: ..., format: _dateFilterLabel, items: FinancialDateFilter.values.map(...))), Text(' • N transactions'))`. `_openCombinedReport` now passes `dateFilter: state.dateFilter` instead of `selectedYear:`. Removed the standalone `_YearSelector` render call and its surrounding `SizedBox`es, collapsing them to one `SizedBox(height: Spacing.space16)`. Restructured `_FinancialsScreenState.build`'s `Expanded` block per Cycle 5: `_SummaryHeader` + `_TransactionsListHeader` now render in every non-error branch; only the inner content area swaps between spinner / `_EmptyState` / `ListView.separated`.
4. `test/features/financials/widgets/year_selector_test.dart` deleted — its target widgets (`_YearSelector`, `_YearSelectorChip`, `_availableYears`) no longer exist.
5. `summary_header_test.dart` updated: the Cycle 4 merged single-`Text` assertions (`'${year} • N transactions'`) replaced with split-shape assertions against `AppDropdown<FinancialDateFilter>` plus adjacent `' • N transactions'` text; added cases for the non-null `thisYear` default, the textual (non-numeral) `'This year'` label, the fixed 3-item enum-order item list, exact item label strings, `onChanged` dispatching `setDateFilter`, and the empty-state case (dropdown/header stay visible and usable when `filteredEntries` is empty for the selected filter).
6. `transaction_card_test.dart` and `transactions_list_header_test.dart`: no edits required — their year-relative fixture defaults (`DateTime(DateTime.now().year, ...)`) already match the default `thisYear` filter, so both remain byte-identical to their Cycle 4 state under Cycle 6.

## Files Created
None.

## Files Modified
- `lib/features/financials/financials_controller.dart`
- `lib/features/financials/financials_pdf_preview_screen.dart`
- `lib/features/financials/financials_screen.dart`
- `test/features/financials/widgets/summary_header_test.dart`
- `test/features/financials/widgets/transaction_card_test.dart`
- `test/features/financials/widgets/transactions_list_header_test.dart`
- `docs/features/feature/financials-transaction-cards/ENGINEER_REPORT.md`

## Files Deleted
- `test/features/financials/widgets/year_selector_test.dart`

`lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` was not touched in Cycle 6 (no Cycle 6 task targets it).

## Analyzer Results
Command run (re-verified independently this cycle):

`flutter analyze lib/features/financials/financials_controller.dart lib/features/financials/financials_pdf_preview_screen.dart lib/features/financials/financials_screen.dart test/features/financials/widgets/summary_header_test.dart test/features/financials/widgets/transaction_card_test.dart test/features/financials/widgets/transactions_list_header_test.dart test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart`

Result: `No issues found! (ran in 1.8s)` — clean across all 7 changed files.

## Test Results
Command run (re-verified independently this cycle):

`flutter test test/features/financials/widgets/transaction_card_test.dart test/features/financials/widgets/summary_header_test.dart test/features/financials/widgets/transactions_list_header_test.dart test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart`

Result: **39 passed, 0 failed**. (`year_selector_test.dart` is deleted, not run — its coverage is folded into `summary_header_test.dart`'s new Cycle 6 cases.)

## Code Efficiency/Bloat Check
- No new provider, controller, repository, or model. `setDateFilter` replaces `setSelectedYear` 1-for-1; `dateFilter` replaces `selectedYear` 1-for-1 on `FinancialsState`.
- `_availableYears` (Cycle 4's data-derived year-list helper) is deleted outright — Cycle 6's dropdown uses a fixed 3-value enum literal (`FinancialDateFilter.values`), so no replacement helper of that kind was needed.
- `_dateFilterLabel` is a single top-level pure function used at two call sites within the same widget (`format:` and each menu item's `Text` child) — kept as one function rather than duplicating the switch, per the plan's explicit "single source of truth" rationale.
- `_YearSelector`, `_YearSelectorChip`, and `_availableYears` (Cycle 4 additions) are fully removed rather than left dead — net code reduction on `financials_screen.dart` from this cycle's dropdown swap.
- No `TODO`/`FIXME`/`debugPrint` introduced. No enum case added "for future use" — `custom` was deliberately left out per the plan's explicit instruction not to resurrect it.
- `financials_screen.dart` remains above the 500-line file-size target; this predates Cycle 6 (noted in prior cycle reports) and Cycle 6's net effect is a further reduction (dropdown swap removes more than it adds), not new bloat.
- Line-delta note for QA: the plan's Cycle 6 Change Budget table was written against a hypothetical isolated Cycle 4→Cycle 6 diff. Since Cycles 1–5 were never committed to `main`, a plain `git diff` against `main` conflates every uncommitted cycle's deltas (e.g. `financials_pdf_preview_screen.dart` shows a net −10 vs. `main`, which includes Cycle 1–3's `customStartDate`/`customEndDate` additions being removed again by Cycle 6, not a Cycle-6-only figure). Line-by-line diff review (not raw numstat) confirms the actual Cycle 6-only changes match the plan's Task Breakdown exactly — no extra logic, no missing piece.

## Verification (manual steps performed)
- Read the full `ARCHITECT_PLAN.md`, including the Cycle 6 Scope Expansion section, before writing this report.
- Independently re-ran `flutter analyze` on all 7 changed files — clean.
- Independently re-ran `flutter test` on the 4 remaining widget test files — 39 passed, 0 failed.
- Confirmed via `grep`/`test -e` that `test/features/financials/widgets/year_selector_test.dart` no longer exists.
- Confirmed via `grep` in `financials_controller.dart` diff: `FinancialDateFilter` enum has exactly `{allTime, thisYear, thisMonth}` (no `custom`), `dateFilter` defaults to `FinancialDateFilter.thisYear`, `setDateFilter` present, `setSelectedYear` and `customStartDate`/`customEndDate`/`setCustomDateRange` absent.
- Confirmed via `grep` in `financials_screen.dart`: `import '../../components/ui/app_dropdown.dart';` present, `AppDropdown<FinancialDateFilter>` wired with `value: state.dateFilter` / `format: _dateFilterLabel`, `_openCombinedReport` passes `dateFilter: state.dateFilter`, and `_YearSelector`/`_YearSelectorChip`/`_availableYears` no longer appear in the file.
- Confirmed via diff review that `financials_pdf_preview_screen.dart`'s constructor takes `FinancialDateFilter dateFilter` and `_filterLabel` is a 3-case switch producing `'All time'` / `'Year YYYY'` / month-year strings, with no `custom` case.

## Deviations From Plan
None found. Every Cycle 6 task in the plan's Engineer Task Breakdown (enum reintroduction, state-shape swap, PDF screen constructor swap, inline `AppDropdown` wiring, empty-state build restructuring, test file updates/deletion) is present in the diff exactly as specified. The only note (not a deviation, a reporting caveat) is that raw `git diff --numstat` against `main` cannot cleanly isolate a Cycle-6-only line delta because Cycles 1–5 were never committed separately — see Code Efficiency/Bloat Check above.

## Blockers Encountered
None.

## Ready For QA
Ready For QA: Yes
