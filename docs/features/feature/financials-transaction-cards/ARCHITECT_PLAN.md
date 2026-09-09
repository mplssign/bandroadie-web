# ARCHITECT_PLAN — feature/financials-transaction-cards

## Feature Slug
`feature/financials-transaction-cards`

## Feature Title
Financials screen — replace transaction table with cards, add summary header

## Cycle History

- **Cycle 1** (merged pending — commit `c46d6bb`): Original plan (this document below). Table → cards + summary header + sort toggle + details-sheet field-label normalization. Approved end-to-end (Architect → Engineer → QA).
- **Cycle 2** (merged pending — folded into `c46d6bb` per QA feedback): Minor summary-header refinements per Tony's PR read.
- **Cycle 3** (merged pending — commit `8dac09a`): `_SummaryHeader` content center-aligned.
- **Cycle 4** (uncommitted on working tree, QA-APPROVED): Replaced the four date-filter chips with a single year-select `PopupMenuButton<int>` chip (`_YearSelector` / `_YearSelectorChip`), merged the `_dateRangeLabel` and transaction-count into one line separated by `" • "`, and defaulted the displayed year to the actual current calendar year. **The `selectedYear: int` state shape and dynamic year-list derivation introduced here are superseded by Cycle 6.** See **Cycle 4 Scope Expansion** in the middle of this document, and the pointer notes at the top of that section.
- **Cycle 5** (planned, never implemented — superseded before Engineer started): Move the year picker inline into `_SummaryHeader`'s summary line via `AppDropdown<int>` (Forui `FSelect.rich` wrapper), delete the standalone `_YearSelector` / `_YearSelectorChip` row, and restructure `_FinancialsScreenState.build` so the summary header + list header render above the content area in every non-error state (loading, empty, and non-empty) — fixing the usability gap where the year picker vanished whenever `filteredEntries` was empty. **The inline-placement decision, empty-state build restructuring, and `AppDropdown`-via-`IntrinsicWidth` mechanic are preserved and re-adopted by Cycle 6 verbatim; the `AppDropdown<int>` typing and dynamic year-list items are superseded.** See **Cycle 5 Scope Expansion**, and the pointer notes at the top of that section.
- **Cycle 6** (this revision, planned but not yet implemented): Replace Cycle 4's `selectedYear: int` scalar with a `FinancialDateFilter { allTime, thisYear, thisMonth }` enum (default `thisYear`, no `custom` case). The inline dropdown in `_SummaryHeader` becomes `AppDropdown<FinancialDateFilter>` with `format` mapping `allTime → 'All time'`, `thisYear → 'This year'`, `thisMonth → 'This month'` — reversing Cycle 4's "display the numeric year" decision for the `thisYear` case. `_availableYears` helper is deleted. `FinancialsPdfPreviewScreen` swaps its constructor from `selectedYear: int` back to `dateFilter: FinancialDateFilter`. Cycle 5's inline placement and empty-state build restructuring are preserved verbatim. See **Cycle 6 Scope Expansion** in the middle of this document.
- **Cycle 7** (committed on branch — commit `22b38be`, QA-APPROVED, no formal plan section): Small three-item revision on top of Cycle 6 — (1) `AppDropdown<T>` gains an optional nullable `size: FTextFieldSizeVariant?` passthrough (defaults to `.md` when unset, zero call-site impact), (2) the financials date-filter dropdown passes `size: FTextFieldSizeVariant.sm`, and (3) the details sheet's `_DetailRow` changes from stacked label-above-value to side-by-side `Row(SizedBox(width: 68, label), SizedBox(width: Spacing.space8), Expanded(Column(value)))` — an exact structural match to `view_gig_drawer.dart`'s `_DetailRow`. Documented in `docs/features/feature/financials-transaction-cards/QA_REPORT.md` only; no `ARCHITECT_PLAN.md` section exists. **The `_DetailRow` shape and `size: FTextFieldSizeVariant.sm` decisions are the authoritative baseline for Cycle 8's edits to the details sheet and remain untouched.**
- **Cycle 8** (this revision, planned but not yet implemented): (A) Details drawer row-order swap to `Date / Description / Paid to / Purchased by / Needed for gig / Notes` (primary rows) with existing conditional rows (Reimbursed, Reimbursement detail, Deposit to Savings) appended below; footer restructured from a lone `Edit` primary to `Done` primary + `Edit` secondary matching `view_gig_drawer.dart`'s `SheetFooter(primaryLabel: 'Done', cancelLabel: 'Edit')` pattern. (B) Add/Edit form field-order swap to `Type / Amount / Date / Description / Paid to / Purchased by / Needed for gig / Notes`; **the current mode-conditional label swap on the two "payer"-adjacent fields is deleted — both fields render with fixed labels regardless of income/expense**: `Paid to` = the `paid_to_user_id` / `paid_to_name` member dropdown (existing `_paidToUserId` state), `Purchased by` = the `payer_name` / `payor_name` free-text field (existing `_payerController` state). New `Needed for gig` picker is a `Consumer`-wrapped `AppDropdown<String?>` over `gigProvider.allGigs` (matches the existing member-dropdown pattern in the same file). `_TypePillRow` becomes `StatefulWidget` and auto-scrolls the currently-selected type chip into view on first frame via `Scrollable.ensureVisible` on a `GlobalKey`. (C) `financial_entries` gains a new nullable `notes` text column via a new migration file authored under `supabase/migrations/` — **the migration is authored, not applied; Tony applies it manually on his own schedule**. `FinancialEntry` model, `FinancialEntryRepository.insertEntry` / `updateEntry`, `FinancialsNotifier.addEntry` / `updateEntry`, and the `_SaveCallback` typedef all take new `notes: String?` and `gigId: String?` parameters that flow through to the DB payload. `_TransactionCard`'s title-resolution logic in `financials_screen.dart` is untouched (it references field bindings, not display labels — the labeling change in the drawer/form is independent). See **Cycle 8 Scope Expansion** at the bottom of this document.

Sections below labeled without a cycle prefix are the original Cycle 1 plan, still authoritative for the shipped-in-Cycles-1–3 work — do not revisit any of it. Cycle 4 additions are scoped to the sections under **Cycle 4 Scope Expansion** (with Cycle-6 superseded parts flagged at the top of that section). Cycle 5 additions are scoped to the sections under **Cycle 5 Scope Expansion** (with Cycle-6 superseded parts flagged at the top of that section). Cycle 6 is the current authoritative design for the date-filter control, its state shape, the PDF preview screen's constructor, and everything the Cycle 4/5 sections marked as superseded — read Cycle 6, then Cycle 7 (in QA_REPORT.md), then Cycle 8 last, and treat later cycles as governing wherever they conflict with earlier ones. Cycle 7's `_DetailRow` shape and dropdown-`.sm` sizing are baseline for Cycle 8 and remain unchanged.

## Problem Summary
The Financials screen renders transactions as an 8-column horizontally-scrollable table (`_EntriesList` / `_TableHeader` / `_EntryTableRow` in [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart)) with dynamic amount-column width measurement, no visible totals or transaction count, and pins "View savings balance" / "Generate Report" as outlined buttons in `_BottomActionsRow`. The bottom sheet ([lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart)) uses icon-prefixed rows, silently omits "Reimbursed" when false, has no representation of the `gigId` relationship, and mislabels a few fields ("Payer" / "Description" / "Edit Entry"). Redesign the screen and sheet into a vertically-scrolling card list with a summary header, and normalise the sheet's field labels — no schema, RPC, or repository shape changes.

## Root Cause
n/a — this is a UI/UX redesign, not a defect. Confidence `HIGH` (design fully specified in the Feature Input; all target widgets confirmed by reading the files listed above).

## Existing System Analysis

### `financials_screen.dart` (current shape, from the file)
Top-to-bottom body layout inside `Scaffold` → `SafeArea` → `Column`:

1. `BackOnlyAppBar` (unchanged)
2. Page title "Financials" + `TextButton.icon` "Add" (gated by `canCreate`)
3. `_ViewModeToggle` (Income / Expenses, `Notifier` writes `viewMode`)
4. `_DateFilterRow` (All Time / This Year / This Month / Custom chips)
5. `_EntriesList` — the doomed 8-column table. Uses a `LayoutBuilder` + `_measureText` to compute `amountColumnWidth` from the widest row string, then wraps a `SingleChildScrollView(scrollDirection: horizontal)` around `_TableHeader` + a `ListView.separated` of `_EntryTableRow`. Columns: Amount, Date, Type, From, Paid To, Disbursed, Savings, 1099. Constants `_kDateWidth` / `_kTypeWidth` / `_kFromWidth` / `_kPaidToWidth` / `_kDisbursedWidth` / `_kSavingsWidth` / `_k1099Width` and `_kFixedColumnsWidth` all exist only to power this table.
6. `_BottomActionsRow` — `Divider` + horizontal `SingleChildScrollView` containing `_OutlinedActionButton("View savings balance")` (opens `_showSavingsSheet` → `_SavingsSheet`) and `_OutlinedActionButton("Generate Report")` (calls `_openCombinedReport`, which reads `activeBandProvider.activeBand?.name`, `membersProvider.members`, `financialsProvider.dateFilteredEntries` and pushes `FinancialsPdfPreviewScreen`).

Everything is driven by `financialsProvider` ([financials_controller.dart](lib/features/financials/financials_controller.dart)). Key existing facts I confirmed by reading the code:

- `FinancialsState.filteredEntries` already sorts newest-first via `_applyDateFilter` (`entries.sort((a, b) => b.entryDate.compareTo(a.entryDate))`). This is the default ("Newest first") for the new sort toggle; "Oldest first" is just `.reversed` over the same list — no controller change, no re-query, no change to `_applyDateFilter` needed.
- `FinancialsState.dateFilteredEntries` (both types, date-filtered only) is what the report already consumes — untouched by this feature. It also stays newest-first, since sort-toggle is a screen-local presentation concern and must not leak into the report data path.
- `_SavingsSheet` and `FinancialsPdfPreviewScreen` are opened by helper functions (`_showSavingsSheet(context, state.allEntries)` and `_openCombinedReport(context, ref, state)`) that stay identical — they just get wired to new call sites.

### `financial_entry_details_bottom_sheet.dart` (current shape)
`_FinancialEntryDetailsSheet` is a `StatelessWidget` that captures a `WidgetRef` (odd but functional) and renders: drag handle → amount + `_TypeBadge(category)` + optional `_Badge1099` + optional `_ReimbursedBadge` → `_DetailRow`s for Date / Payer / Paid To / (conditional Reimbursement) / (conditional Description) / (conditional Deposit to Savings) → `SheetFooter(primaryLabel: 'Edit Entry', primaryIcon: AppIcons.edit)`. `_DetailRow` renders `Icon(icon, size: 16, color: textMuted)` beside the label/value column.

### `FinancialEntry` model (relevant fields, verified in [financial_entry.dart](lib/features/financials/models/financial_entry.dart))
- `entryType: FinancialEntryType` (`isIncome` derived from it)
- `category`, `amountCents`, `entryDate`, `description`
- `payerName` (aliased from `payor_name`), `paidToName`, `paidToUserId`
- `isReimbursed` (default `false`), `reimbursedDate`
- `is1099Expected` (nullable)
- `disbursements: Map<String, int>?`
- `depositToSavings: bool?`, `depositToSavingsCents: int?`
- `gigId: String?` — populated on entries linked to a gig (gig_pay and gig-tab expenses). Not surfaced in the current UI.

### Where gig data lives
`gigProvider` ([gig_controller.dart](lib/features/gigs/gig_controller.dart)) exposes `GigState.allGigs`, which is populated from `bandFullStateProvider` ([band_full_state.dart](lib/features/bands/band_full_state.dart)). The backing RPC `get_band_full_state` ([supabase/migrations/20260521000000_add_start_time_to_date_tables.sql](supabase/migrations/20260521000000_add_start_time_to_date_tables.sql)) selects gigs with `WHERE g.band_id = p_band_id` and **no date filter** — every gig for the band, including past gigs, is already loaded whenever the financials screen is on-screen (since the user is inside an active band context). `Gig` has `final String name`. This is the "already-loaded gigs source" the Feature Input said to prefer.

## Proposed Solution

### Layout of the redesigned screen (top-to-bottom)
1. `BackOnlyAppBar` — unchanged.
2. Page title + "Add" button — unchanged.
3. `_ViewModeToggle` (Income / Expenses) — unchanged.
4. `_DateFilterRow` (existing 4 chips) — unchanged position, unchanged behavior. **Not moving.**
5. **NEW** `_SummaryHeader` — displays, top to bottom:
   - Small-caps label: `TOTAL INCOME` or `TOTAL EXPENSES` based on `state.viewMode`. Style: `AppTextStyles.footnote` in `context.colors.textMuted` with `letterSpacing: 0.5` and upper-case string literal (the existing letterSpacing convention used throughout the app — see [financials_screen.dart line 301](lib/features/financials/financials_screen.dart#L301)).
   - Large total: sum of `amountCents` across `state.filteredEntries`, formatted with the same `NumberFormat('#,##0')` pattern used in `FinancialEntry.formattedAmount`. Style: `AppTextStyles.displayLarge` in `context.colors.success` (income) or `AppColors.error` (expenses). No `+` / `−` prefix on the header total (badge/list already convey direction).
   - Date-range sub-label: derived from `state.dateFilter` + `state.customStartDate/customEndDate`:
     - `allTime` → `"All time"`
     - `thisYear` → `"${DateTime.now().year}"`
     - `thisMonth` → `DateFormat('MMMM yyyy').format(DateTime.now())`
     - `custom` → same range formatting as `_DateFilterRow._customLabel` (`MMM d – MMM d` same-year, `MMM d, yy – MMM d, yy` cross-year)
   - Row: `"${state.filteredEntries.length} transactions"` (or `"1 transaction"`) — no year picker; the date-filter chips remain the source of truth. Written to match the resolved answer to Open Question 1.
   - Two inline text links with `AppIcons.forward` chevrons, side-by-side (Row): **"View Savings Balance"** (fixed casing) → `_showSavingsSheet(context, state.allEntries)`; **"Generate Report"** → `_openCombinedReport(context, ref, state)`. Disabled visual when `state.isLoading` for the report link (matches current `_BottomActionsRow` behavior).
6. **NEW** `_TransactionsListHeader` — `Row` with left text `"Transactions"` (`AppTextStyles.footnote` bold, small-caps letterSpacing) and a right-aligned **tappable** sort toggle. Label reflects current state: `"Newest first ▾"` (default) or `"Oldest first ▾"` (toggled). Both states use the same `▾` glyph as a plain character — no icon, no icon rotation, no direction change on the character; only the `"Newest"` / `"Oldest"` word changes. `AppTextStyles.footnote`, muted color. The right-side tap target is wrapped in an `InkWell` (or `GestureDetector`) with a `>=48px` hit area (per design tokens minimum touch target) that invokes `onToggleSort`. Two states only — no dropdown, no menu, no other sort axes (not amount, not category). `_TransactionsListHeader` itself is a `StatelessWidget` receiving `bool sortAscending` + `VoidCallback onToggleSort` as constructor params; it owns no state.

   **Where the sort-order state lives:** local widget state in `_FinancialsScreenState` (`bool _sortAscending = false`, default descending / newest-first, matching what `_applyDateFilter` already produces). Rationale: sort is presentation-only over `state.filteredEntries` — it doesn't affect which entries are loaded, doesn't affect the report data path (`dateFilteredEntries`), and doesn't need to survive band-switch, screen dismiss, or app-restart. `FinancialsState` currently holds only concerns that affect *which* entries are shown (`viewMode`, `dateFilter`, `customStart/EndDate`); adding a sort field would split that boundary for a purely visual concern and force a state-shape change the rest of the plan explicitly avoids. Not persisted across screen dismiss/re-open — accepted as a UI preference, not a saved setting.
7. **NEW** `_TransactionCard` list — `ListView.separated` (or `Column` inside `ListView` — Engineer's call for scroll perf; existing table was `ListView.separated`) of `_TransactionCard` widgets, one per entry in a **derived `sortedEntries` list**. Derivation, computed once in `build`: `final filtered = state.filteredEntries; final sortedEntries = _sortAscending ? filtered.reversed.toList() : filtered;`. `_SummaryHeader`'s total and count read from `state.filteredEntries` (order-agnostic aggregates), so a sort-toggle rebuild does not re-run the total/count calculation logic differently.
   - `_TransactionCard` layout: `InkWell` → `Card`-like container with `Spacing.cardRadius` and `context.colors.surface` background → `Row`:
     - Left column (`Expanded`): title (bold, `AppTextStyles.callout`), subtitle (`AppTextStyles.footnote` muted), date `DateFormat('MMM d, yyyy').format(entry.entryDate)` (footnote muted), and — when the entry qualifies — a green outlined badge below.
     - Right column: amount `"$prefix${entry.formattedAmount}"` (existing color + `−` for expenses / no prefix for income logic preserved verbatim from `_EntryTableRow`), `AppIcons.forward` chevron below or beside amount.
   - Title resolution: expenses → `entry.paidToName?.trim().isNotEmpty == true ? entry.paidToName! : entry.category`. Income → `entry.payerName?.trim().isNotEmpty == true ? entry.payerName! : entry.category`.
   - Subtitle: always `entry.category` (redundant with title on the fallback path — accepted per spec).
   - Badge rules (green outlined pill, `context.colors.success` border + text, transparent fill):
     - Expense entry with `entry.isReimbursed == true` → `"Reimbursed"` badge.
     - Income entry with `entry.disbursements != null && entry.disbursements!.isNotEmpty` → `"Disbursed"` badge.
     - Never both, never the opposite type.
   - **No leading icon.** `depositToSavings` / `is1099Expected` / disbursement details are **not** shown on the card — detail sheet only.
   - Tap → `showFinancialEntryDetailsSheet(context, ref, entry)` (unchanged call).
8. `_EmptyState` — unchanged.
9. `_ErrorState` — unchanged.

**Ordering rationale (explicit call-out):** the summary header goes *below* the date-filter chips because the total dollar figure is derived from the currently-selected date filter — placing the filter directly above the total makes the causality read left-to-right / top-to-bottom. Chips stay in their current slot, unchanged, which minimizes regression surface.

### Redesigned details sheet (`financial_entry_details_bottom_sheet.dart`)
Keep the file's `showFinancialEntryDetailsSheet(context, ref, entry)` entry point and the `SheetFooter` structure. Changes:

- Remove `icon` from `_DetailRow` — signature becomes `(String label, String value)`. Rows lose the `Icon` widget and the horizontal padding shifts left where the icon used to be. This is a modification, not a rename — no callers outside the file since `_DetailRow` is private.
- Rename displayed labels: `"Payer"` → `"Paid by"`, `"Description"` → `"Notes"`. Field lookup (`entry.payerName` / `entry.description`) is unchanged.
- **New row** always shown for expense entries: `"Reimbursed"` → `entry.isReimbursed ? "Yes" : "No"`. Insert directly under the existing conditional reimbursement-detail row (so the flow is: `Reimbursed: Yes/No` → optional `Reimbursement: Purchased … · Reimbursed … to …` when `isReimbursed == true`).
- **New row** always shown (income and expense): `"Related to gig"` → resolved by `ref.read(gigProvider).allGigs.firstWhereOrNull((g) => g.id == entry.gigId)`:
  - `entry.gigId == null` → `"No"`.
  - `entry.gigId != null` and gig found → `"Yes • ${gig.name}"` (plain text, not tappable — resolved final per Open Question 3).
  - `entry.gigId != null` and gig NOT in `allGigs` (edge case — RPC error, stale cache) → `"Yes"` alone. Graceful degradation, no crash, no fetch.
  - Uses `ref.read` (not `watch`) — the sheet is a modal snapshot, `allGigs` doesn't need reactive updates during the sheet's lifetime. The sheet already captures `WidgetRef` and uses `ref.read` for the Edit callback, so this fits the existing pattern (no `ConsumerWidget` conversion needed — see "Files Off-Limits" note on refactoring).
- `SheetFooter.primaryLabel`: `"Edit Entry"` → `"Edit"`. `primaryIcon` stays `AppIcons.edit`.

Unchanged in the sheet: the amount + `_TypeBadge(category)` + `_Badge1099` + `_ReimbursedBadge` top block (verified against the Feature Input: "`is1099Expected` badge, `depositToSavings` row, disbursement detail stay exactly as today"). `_ReimbursedBadge` stays as-is above the divider AND the explicit `Reimbursed: Yes/No` row goes below — matches the Feature Input's "Add explicit 'Reimbursed: Yes/No' row for expenses".

### What is deliberately deleted
- `_EntriesList` (replaced by summary header + list header + card list).
- `_TableHeader`, `_HeaderCell`, `_EntryTableRow` (dead once the table is gone).
- `_BottomActionsRow`, `_OutlinedActionButton` (dead once actions move into the summary header — actions become inline text links, `OutlinedButton` styling is not reused).
- All column-width constants (`_kDateWidth`, `_kTypeWidth`, `_kFromWidth`, `_kPaidToWidth`, `_kDisbursedWidth`, `_kSavingsWidth`, `_k1099Width`, `_kFixedColumnsWidth`).
- `_measureText` helper.
- `import 'dart:ui' as ui;` (only used by `_measureText`).

## Database Impact
not applicable — no schema change, no new RPC, no RLS change. The `financial_entries` SELECT policy ([supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql](supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql), routed through `check_financial_view_permission`) already gates the whole screen. The gigs table SELECT policy ([supabase/migrations/20260823120000_wrap_rls_auth_functions.sql line 685](supabase/migrations/20260823120000_wrap_rls_auth_functions.sql#L685)) lets any active band member read gigs — the `gigProvider` cache in scope already satisfies this. **No repository query change.** `FinancialEntryRepository.fetchEntriesForBand()` stays byte-identical.

## Flutter Architecture Changes
None to the state layer.
- No new provider.
- No new controller, notifier, or repository.
- No change to `FinancialsState` shape (no sort field, no year-selection field — sort lives as local widget state, not controller state; rationale in Proposed Solution → item 6).
- No change to `FinancialEntry` model (no `gigName` field).
- `financials_controller.dart` **is not modified** — the sheet reads `gigProvider.allGigs` directly from within its build method (already a `ConsumerWidget`-adjacent construct with `ref` in scope), and the sort toggle is a screen-local concern.
- One new local field on `_FinancialsScreenState`: `bool _sortAscending = false` (default descending / newest-first). Toggled from `_TransactionsListHeader.onToggleSort` via `setState(() => _sortAscending = !_sortAscending)`. Not persisted.
- All new widgets stay private (`_`-prefixed) to `financials_screen.dart`.

## Files to Create

Four widget/unit test files, mirroring `lib/features/financials/`. These are the only new files in the PR; no new production source files. Full per-file assertions live in Verification Plan → Tier 1 — the summaries below name the widget under test and the pump strategy only.

- `test/features/financials/widgets/transaction_card_test.dart` — `_TransactionCard` render behavior (title resolution, subtitle, date, badge rules, amount color/prefix, no-leading-icon regression guard). Screen-level pump with an overridden `financialsProvider`.
- `test/features/financials/widgets/summary_header_test.dart` — `_SummaryHeader` label (`"TOTAL INCOME"` / `"TOTAL EXPENSES"`), total formatting, count phrasing (`"1 transaction"` vs `"N transactions"`), date-range sub-label for each `FinancialDateFilter` case, and the two link labels (`"View Savings Balance"`, `"Generate Report"`) each followed by an `AppIcons.forward` chevron. Screen-level pump with an overridden `financialsProvider`.
- `test/features/financials/widgets/transactions_list_header_test.dart` — `_TransactionsListHeader` sort-toggle label (`"Newest first ▾"` ↔ `"Oldest first ▾"`), list-order reversal on tap, `≥48px` tap target height, non-mutation of `financialsProvider` state, and stable summary aggregates across the toggle. Screen-level pump with an overridden `financialsProvider` seeded with entries whose `entryDate`s and titles are distinguishable.
- `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart` — sheet regressions: no `Icon` inside `_DetailRow`s, new labels (`"Paid by"`, `"Notes"`, `"Related to gig"`) present and old strings (`"Payer"`, `"Description"`) absent as exact `Text` labels, `"Reimbursed: Yes/No"` row for expense entries, `"Related to gig"` three-case value resolution (`"No"` / `"Yes • <name>"` / `"Yes"` for the RPC-miss edge case), `_ReimbursedBadge` still present above the divider on reimbursed expenses, and footer button label `"Edit"` (not `"Edit Entry"`). Sheet-level pump via `showFinancialEntryDetailsSheet` with an overridden `gigProvider`.

All four widgets under test are private (`_`-prefixed). Per Task 6's preferred approach (option (b)), tests pump the enclosing screen or sheet inside a `ProviderScope` overriding the relevant provider(s) — no production code becomes `@visibleForTesting`, no widget is extracted to a public file. Any additional test-only imports (`flutter_test`, `flutter_riverpod` overrides) are confined to these four files and do not touch `lib/`.

## Files to Modify

### [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart)
- Remove: `_EntriesList`, `_TableHeader`, `_HeaderCell`, `_EntryTableRow`, `_BottomActionsRow`, `_OutlinedActionButton`, `_measureText`, all `_k*Width` constants, `import 'dart:ui' as ui;`, and any now-unused imports (audit `flutter/services.dart` / `AppIcons` fields — `HapticFeedback` is still used by `_ViewModeToggle`, `AppIcons` is still used elsewhere).
- Add: `_SummaryHeader` (`ConsumerWidget` — needs `ref` to read `financialsProvider` and dispatch to `_showSavingsSheet` / `_openCombinedReport`), `_TransactionsListHeader` (`StatelessWidget` with constructor params `{required bool sortAscending, required VoidCallback onToggleSort}`), `_TransactionCard` (`StatelessWidget`, receives `entry` + `onTap`), `_InlineLinkButton` (`StatelessWidget` — small helper for the two chevron-suffixed links; may be inlined instead if only used twice).
- Add local field on `_FinancialsScreenState`: `bool _sortAscending = false` (see Flutter Architecture Changes).
- Modify: the `_FinancialsScreenState.build` `Column` — swap the `Expanded(child: _EntriesList(...))` block for a `_SummaryHeader` + `_TransactionsListHeader` + `Expanded(child: ListView.separated(...))` sequence, feeding the list a `sortedEntries` derived from `state.filteredEntries` and `_sortAscending`. `_TransactionsListHeader.onToggleSort` calls `setState(() => _sortAscending = !_sortAscending)`. Keep `_ErrorState`, `_EmptyState`, loading spinner exactly as today.
- Preserve verbatim: `_ViewModeToggle`, `_DateFilterRow`, `_FilterChip`, `_showSavingsSheet`, `_SavingsSheet`, `_openCombinedReport`, `_EmptyState`, `_ErrorState`, `_addEntry`.

### [lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart)
- Modify `_DetailRow` to drop the `icon` parameter; remove `Icon(icon, size: 16, color: context.colors.textMuted)` and the trailing `SizedBox(width: Spacing.space8)`. All `_DetailRow(...)` call sites within the file drop `icon:`.
- Rename displayed label strings only: `"Payer"` → `"Paid by"`, `"Description"` → `"Notes"`.
- Add a `_DetailRow(label: 'Reimbursed', value: entry.isReimbursed ? 'Yes' : 'No')` row, **shown for all expense entries** (guarded by `entry.entryType == FinancialEntryType.expense`), placed immediately before the existing conditional reimbursement-detail row.
- Add a `_DetailRow(label: 'Related to gig', value: ...)` row, shown for **all** entries. Value resolves via `ref.read(gigProvider).allGigs` — see "Proposed Solution → Redesigned details sheet" above for the exact three cases. Requires adding `import '../../gigs/gig_controller.dart';` and (for `firstWhereOrNull`) `import 'package:collection/collection.dart';` — `collection` is already an indirect dep via `flutter`, but if analyzer flags it, use a plain `try/catch` around `firstWhere` or a manual loop. **No pubspec change.** Place row between Date and "Paid by".
- `SheetFooter(primaryLabel: 'Edit Entry', ...)` → `SheetFooter(primaryLabel: 'Edit', ...)`. `primaryIcon` stays `AppIcons.edit`.
- Do not remove `_TypeBadge`, `_Badge1099`, `_ReimbursedBadge`, or `_buildReimbursementDetailLine`.
- Do not change the `showFinancialEntryDetailsSheet` public signature.
- Do not convert `_FinancialEntryDetailsSheet` to a `ConsumerWidget`. It already receives `WidgetRef ref` via constructor, and adding `ref.read(gigProvider)` in `build` matches the existing pattern.

## Files Off-Limits

**Cycle 4 note:** two files listed below (`financials_controller.dart` and `financials_pdf_preview_screen.dart`) are **now legitimately in scope for Cycle 4 only** — see **Cycle 4 Scope Expansion → Files to Modify (Cycle 4)** for the exact surface area. Their appearance in this list refers strictly to Cycles 1–3.

- [lib/features/financials/financial_entry_repository.dart](lib/features/financials/financial_entry_repository.dart) — no query changes; the gig-name resolution uses `gigProvider`, not a repository join. Modifying `fetchEntriesForBand` to add `select('*, gigs(name)')` would work under RLS (both tables are readable to active members) but produces a shape change on the returned JSON, forcing a `FinancialEntry.fromJson` change and adding a `gigName` field to the model — all avoided.
- [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart) — model stays byte-identical.
- [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart) — no state-shape change (no sort, no year selection). **[Cycles 1–3 only — see Cycle 4 note above.]**
- [lib/features/financials/financials_pdf_preview_screen.dart](lib/features/financials/financials_pdf_preview_screen.dart) — report generation unchanged. **[Cycles 1–3 only — see Cycle 4 note above.]**
- [lib/features/financials/financials_report_builder.dart](lib/features/financials/financials_report_builder.dart) — report format unchanged.
- [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart) — do **not** add an `isReimbursed` toggle. This is a known pre-existing gap called out in the Feature Input as explicitly out of scope. See "System Impact Map" for how QA should read the resulting UX.
- [lib/features/financials/widgets/gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart) — no change.
- Every `supabase/migrations/**` file — no DB change.
- `pubspec.yaml` — no new dependency (the `collection` transitive dep is already available; if analyzer objects, drop it and use a manual scan).
- Anything under [lib/features/gigs/](lib/features/gigs/) — the read is against the existing `gigProvider`.

## Change Budget
Numbers are net line delta *per file* after Engineer implements the Task Breakdown; QA will diff against these. Being off by >~50 lines in either direction on `financials_screen.dart`, or any non-zero delta on the off-limits files, is a plan-vs-implementation gap that should be flagged.

| File | Expected net Δ lines | Rationale |
| --- | --- | --- |
| `lib/features/financials/financials_screen.dart` | **−200 to −70** | Remove ~430 lines of table plumbing (`_EntriesList` + `_TableHeader` + `_HeaderCell` + `_EntryTableRow` + `_BottomActionsRow` + `_OutlinedActionButton` + `_measureText` + width constants). Add ~260 lines of new widgets (`_SummaryHeader`, `_TransactionsListHeader` with tap-to-toggle sort, `_TransactionCard`, `_InlineLinkButton`) plus ~5 lines for local `_sortAscending` state + `sortedEntries` derivation. |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | **+10 to +30** | Two new `_DetailRow` invocations (Reimbursed, Related to gig) plus the gig-lookup helper (~15 lines). Icon removal from `_DetailRow` shaves ~5 lines. Label + button-label edits are inline. |
| Any other file | **0** | Off-limits. |

- Expected new files: **4** (all under `test/features/financials/widgets/`, per Files to Create — the four widget test files supporting Verification Plan → Tier 1). No new production source files.
- Expected new public classes / methods: **0** (all new widgets private; test files declare no public API).
- Expected new dependencies (pubspec.yaml): **0**.
- Expected migration files: **0**.

## System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Gigs | unaffected (read-only lookup) | `gigProvider` read from the details sheet; no state mutation, no fetch. |
| Rehearsals | unaffected | No cross-references. |
| Setlists | unaffected | No cross-references. |
| Members | unaffected | `membersProvider` still consumed by `_openCombinedReport` for the report only. |
| Auth | unaffected | No init-order change, no session change. |
| Routing | unaffected | Screen entry point (Navigator push from HomeTabContent) unchanged. |
| Notifications | unaffected | No triggers touched. |
| Platforms (iOS / Android / macOS / Web) | uniformly affected | Shared Flutter UI only; no `Platform.isIOS` / `kIsWeb` branching in scope. Web PWA / mobile builds render identically. |
| Financials → Add / Edit form | **user-visible side effect, not fixed** | The Feature Input's known-gap call-out. The redesigned card shows a `"Reimbursed"` badge based on `entry.isReimbursed`, and the detail sheet now always shows `Reimbursed: Yes/No`. A general-purpose expense created via the Add form has no way to be marked reimbursed (the form has no toggle — verified by `grep`), so it will always read `"Reimbursed: No"` in the redesign. Gig-tab expenses (via `gig_pay_bottom_sheet.dart` → `insertGigExpenseEntry`) can still be marked reimbursed. QA will see this and it is **expected behavior for this PR** — do not raise it as a bug. Fix is scheduled separately. |
| Reports (`FinancialsPdfPreviewScreen`) | unaffected | Same entry point (`_openCombinedReport`), same params. Only the trigger UI changes (outlined button → inline link with chevron). |
| Savings sheet (`_SavingsSheet`) | unaffected | Same call site (`_showSavingsSheet(context, state.allEntries)`). |
| Contributor permissions (`can_view_financials`) | unaffected | Screen navigation still gated externally; RLS still blocks contributors without the flag from ever seeing entries. |

## Regression Risk
**LOW**. Justification:

- No touch to auth, session, routing, init order, DB, RLS, RPCs, or platform-conditional code.
- No state-shape change (`FinancialsState` and `FinancialEntry` are byte-identical).
- No provider added or removed. One new *read* against an existing provider (`gigProvider`) in the details sheet.
- Data flow into `_SavingsSheet` and `FinancialsPdfPreviewScreen` is preserved verbatim — same helper function calls, same params.
- Change is scoped to one screen file + one sheet file, both inside `lib/features/financials/`.
- Table→card is a full presentational rewrite of the list body, but the state feeding it (`state.filteredEntries` — already newest-first) is unchanged.
- No new dependency, no new migration, no schema change.

The only realistic regression class is visual/layout (card sizing, badge placement, chevron alignment) — caught by widget tests and by the QA visual pass punch list below.

## Engineer Task Breakdown

Ordered, atomic. Each task is a self-contained diff that leaves the app compiling. **Do not merge tasks or invent extra sub-steps.**

1. **Redesign details sheet (`financial_entry_details_bottom_sheet.dart`).**
   - Drop the `icon` parameter from `_DetailRow` and remove the `Icon` widget from its `Row`. Update every `_DetailRow(...)` invocation inside the file to remove `icon:`.
   - Rename label strings `"Payer"` → `"Paid by"`, `"Description"` → `"Notes"`.
   - Change `SheetFooter(primaryLabel: 'Edit Entry', ...)` → `SheetFooter(primaryLabel: 'Edit', ...)`.
   - Add a new `_DetailRow(label: 'Reimbursed', value: entry.isReimbursed ? 'Yes' : 'No')` shown only when `entry.entryType == FinancialEntryType.expense`, placed immediately before the existing `if (isReimbursedExpense) ...[ _DetailRow(label: 'Reimbursement', ...) ]` block.
   - Add a new `_DetailRow(label: 'Related to gig', value: <resolved>)` shown for all entries. Resolve via `ref.read(gigProvider).allGigs` and the three rules above. Add `import '../../gigs/gig_controller.dart';`. Handle `entry.gigId != null` but no match by returning `'Yes'` alone. Prefer a manual `for` loop over `firstWhereOrNull` to avoid depending on `package:collection` — if you use `collection`, note it and verify no pubspec change was needed. Place the row between Date and "Paid by".
   - Do not touch `_TypeBadge`, `_Badge1099`, `_ReimbursedBadge`, `_buildReimbursementDetailLine`, or the amount/badge top block.
   - Verify with `flutter analyze` (Engineer runs this locally; QA re-runs).

2. **Introduce `_TransactionCard` in `financials_screen.dart`.**
   - Add the private widget at the bottom of the file. Signature: `_TransactionCard({required FinancialEntry entry, required VoidCallback onTap})`.
   - Amount color / prefix logic copied verbatim from `_EntryTableRow`:
     ```dart
     final amountColor = entry.isIncome ? context.colors.success : AppColors.error;
     final amountPrefix = entry.isIncome ? '' : '−';
     ```
   - Title resolves per the rules in "Proposed Solution → Redesigned details sheet". Subtitle is always `entry.category`. Date is `DateFormat('MMM d, yyyy').format(entry.entryDate)`.
   - Badge is a small outlined pill with `context.colors.success` border and text, no fill. Rendered only when the two exact rules match (never both, never the opposite type).
   - Trailing chevron: `Icon(AppIcons.forward, size: 20, color: context.colors.textMuted)`.
   - Card container: `Container(decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(Spacing.cardRadius), border: Border.all(color: context.colors.border)))` wrapped in `InkWell(onTap: onTap, borderRadius: BorderRadius.circular(Spacing.cardRadius))`.
   - Do not yet delete `_EntryTableRow`. This task must leave the screen compiling.

3. **Introduce `_SummaryHeader` and `_TransactionsListHeader` in `financials_screen.dart`.**
   - `_SummaryHeader` is a `ConsumerWidget`. In `build`, `ref.watch(financialsProvider)` (matches the existing pattern in `_BottomActionsRow`), then render the small-caps label + total + date-range + count + two-link row per "Proposed Solution".
   - Total: `state.filteredEntries.fold<int>(0, (sum, e) => sum + e.amountCents)` formatted with `NumberFormat('#,##0')`.
   - Date-range label: derive from `state.dateFilter` + `customStart/EndDate` per the four cases in "Proposed Solution → Redesigned screen → item 5". Use `DateTime.now()` for year/month labels — matches how `_applyDateFilter` derives "this year"/"this month".
   - Link row: two side-by-side `TextButton`s (or `GestureDetector`-wrapped `Row`s) with trailing `AppIcons.forward` chevron. `"View Savings Balance"` calls `_showSavingsSheet(context, state.allEntries)`; `"Generate Report"` calls `_openCombinedReport(context, ref, state)`, and is `null`-`onPressed` when `state.isLoading`.
   - `_TransactionsListHeader` is a `StatelessWidget` with constructor params `({required bool sortAscending, required VoidCallback onToggleSort})`. Renders a `Row` with `"Transactions"` on the left (`AppTextStyles.footnote`, bold, small-caps letterSpacing). Right side is an `InkWell` (or `GestureDetector`) with `onTap: onToggleSort`, hit area `>=48px` (wrap the `Text` in a `ConstrainedBox(constraints: BoxConstraints(minHeight: 48), child: Align(alignment: Alignment.centerRight, child: ...))` or equivalent — Engineer's call), containing a `Text` whose value is `sortAscending ? 'Oldest first ▾' : 'Newest first ▾'` in `AppTextStyles.footnote` muted. **Do not** change the `▾` glyph based on state; only the leading word (`"Newest"` / `"Oldest"`) changes. No dropdown, no menu, no other sort axes.
   - Do not yet swap the screen body. This task must leave the screen compiling.

4. **Swap the screen body in `_FinancialsScreenState.build` and introduce local sort state.**
   - Add `bool _sortAscending = false;` as a field on `_FinancialsScreenState` (initialised at declaration; the existing state class has no `initState` block and this addition doesn't require one).
   - In `build`, after `final state = ref.watch(financialsProvider);`, derive the list to render: `final filtered = state.filteredEntries; final sortedEntries = _sortAscending ? filtered.reversed.toList() : filtered;`.
   - Replace the `Expanded(child: state.isLoading ? ... : state.error != null ? _ErrorState(...) : _EntriesList(entries: state.filteredEntries))` block with:
     ```
     state.isLoading         → CircularProgressIndicator (unchanged)
     state.error != null     → _ErrorState (unchanged)
     filtered.isEmpty        → _EmptyState (unchanged — moved out of _EntriesList)
     else                    → Column:
                                  _SummaryHeader(),
                                  _TransactionsListHeader(
                                    sortAscending: _sortAscending,
                                    onToggleSort: () => setState(() => _sortAscending = !_sortAscending),
                                  ),
                                  Expanded(ListView.separated(itemCount: sortedEntries.length, itemBuilder: ...))
     ```
   - `ListView.separated` uses `EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + Spacing.space16)` for the bottom-safe area padding (matches existing `_EntriesList` behavior). Separator: `SizedBox(height: Spacing.space12)`.
   - Card `onTap` calls `showFinancialEntryDetailsSheet(context, ref, sortedEntries[index])` (indexed off the derived list so the tapped card matches the sheet contents in both sort orders).
   - Empty-state gate uses `filtered.isEmpty` (order-agnostic — equivalent to `sortedEntries.isEmpty` but avoids the reversed-list allocation on the empty path).
   - **`_BottomActionsRow` is not rendered anywhere in this new layout.** The links live inside `_SummaryHeader`.

5. **Delete dead code from `financials_screen.dart`.**
   - Remove `_EntriesList`, `_TableHeader`, `_HeaderCell`, `_EntryTableRow`, `_BottomActionsRow`, `_OutlinedActionButton`.
   - Remove `_measureText`.
   - Remove all `_k*Width` constants and `_kFixedColumnsWidth`.
   - Remove `import 'dart:ui' as ui;`. Audit remaining imports and remove any that only supported the deleted table (`AppIcons.success`, `AppIcons.check`, `AppIcons.dollar` may still be used elsewhere in the file — check before removing individual identifier imports).
   - Do not remove any `import` still used by `_ViewModeToggle`, `_DateFilterRow`, `_SavingsSheet`, `_addEntry`, or the new widgets.

6. **Add widget tests (see "Verification Plan → Tier 1").**

## Verification Plan

### Tier 1 — pre-deploy (QA gate, mechanically executable)

**QA gate for APPROVED requires all of the following to pass without running the app:**

1. `flutter analyze` clean (no new lints; existing baseline preserved).
2. `flutter test` passes, including new tests below.
3. Diff review confirms the off-limits files (`financial_entry_repository.dart`, `financial_entry.dart`, `financials_controller.dart`, `financials_pdf_preview_screen.dart`, `financials_report_builder.dart`, `add_financial_entry_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`, all `supabase/migrations/`, `pubspec.yaml`) are byte-identical to `main`.
4. Diff review confirms net line delta on the two modified files falls inside the ranges in "Change Budget".

**New unit / widget tests** (add to `test/features/financials/`, mirroring `lib/features/financials/`):

- `test/features/financials/widgets/transaction_card_test.dart` — widget tests over `_TransactionCard`. Since it's private, either (a) make it package-internal via a `@visibleForTesting` re-export in the same file, or (b) render it indirectly by rendering the screen with a mocked `financialsProvider`. Prefer (b). Assertions:
  - Expense with `paidToName = "Guitar Center"` → title text is `"Guitar Center"`; subtitle text is `entry.category`.
  - Expense with `paidToName = null` and `category = "Equipment"` → title text is `"Equipment"`.
  - Income with `payerName = "The Venue"` → title text is `"The Venue"`.
  - Expense with `isReimbursed = true` → `"Reimbursed"` badge visible; expense with `isReimbursed = false` → no badge.
  - Income with `disbursements = {"member-a-id": 5000}` → `"Disbursed"` badge visible; income with `disbursements = null` or `{}` → no badge.
  - Expense with `disbursements = {"m": 100}` → no `"Disbursed"` badge (never on the opposite type).
  - Income with `isReimbursed = true` (hypothetical) → no `"Reimbursed"` badge.
  - Amount rendered with `"−"` prefix + `AppColors.error` on expense; with no prefix + `context.colors.success` on income.
  - No `Icon` widget in the leading slot of the card (regression guard against reintroducing a category icon).
- `test/features/financials/widgets/summary_header_test.dart` — pump `_SummaryHeader` inside a `ProviderScope` overriding `financialsProvider` with a fixed state. Assertions:
  - Total for a list of `[+100.00, +250.50]` under `viewMode = income` displays `"$350.50"` (no prefix).
  - Label reads `"TOTAL INCOME"` under income mode; `"TOTAL EXPENSES"` under expenses mode.
  - Date-range sub-label matches the resolved value for each `FinancialDateFilter` case.
  - `"3 transactions"` for 3 entries; `"1 transaction"` for 1 entry.
  - `"View Savings Balance"` (capital S, capital B) and `"Generate Report"` text present; each is followed by an `AppIcons.forward` icon.
- `test/features/financials/widgets/transactions_list_header_test.dart` — widget tests over the `_TransactionsListHeader` sort toggle. Since `_TransactionsListHeader` is private, either mark it `@visibleForTesting` (matching the approach chosen for `_TransactionCard`) or exercise it via a screen-level pump with a controlled `financialsProvider` override (three entries with distinct `entryDate`s spread across three days). Assertions:
  - Default render (before any tap): right-side label reads `"Newest first ▾"` exactly.
  - After a single tap on the right-side label: label reads `"Oldest first ▾"` exactly, and the transaction list order is reversed relative to the initial render — verify by inspecting the first-vs-last `_TransactionCard` title (using entries whose titles are distinct).
  - After a second tap: label returns to `"Newest first ▾"` and list order returns to the original.
  - Tap on the sort label does **not** mutate `financialsProvider` state — assert by capturing `container.read(financialsProvider)` before and after the tap and confirming they are the same object (or same field values), and that `container.read(financialsProvider.notifier)` was not invoked. `ProviderContainer` observation is preferred over mock-notifier plumbing.
  - Tap hit area on the sort control is `>=48px` in height — assert via `tester.getSize(find.byType(InkWell))` or by locating the `ConstrainedBox` / `SizedBox` with `minHeight: 48`.
  - Summary header total, count, and date-range label are unchanged before and after the toggle (order-agnostic aggregates).
  - The `▾` glyph is present in the label string in **both** states (regression guard against accidental icon rotation or glyph swap).
- `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart` — pump the sheet with a controlled entry and a mocked `gigProvider`. Assertions:
  - Sheet has no `Icon` widgets inside `_DetailRow`s (regression guard for the icon removal).
  - Labels: `"Paid by"`, `"Notes"`, `"Related to gig"` present with expected values; strings `"Payer"` and `"Description"` are absent (except as substrings — assert on the exact `Text` widget label).
  - Expense with `isReimbursed = false` → row `"Reimbursed: No"` present.
  - Expense with `isReimbursed = true` → row `"Reimbursed: Yes"` present AND existing `_ReimbursedBadge` above the divider still present.
  - Entry with `gigId = null` → `"Related to gig: No"`.
  - Entry with `gigId = "gig-1"` and `gigProvider.allGigs` containing a gig with `id = "gig-1", name = "Summer Bash"` → `"Related to gig: Yes • Summer Bash"`.
  - Entry with `gigId = "gig-unknown"` and empty `allGigs` → `"Related to gig: Yes"` (no bullet, no name).
  - Footer button reads `"Edit"`, not `"Edit Entry"`.

**Owner-run punch list (Tony runs at PR-test time — QA writes this into the PR body verbatim, does not attempt it):**

QA cannot run the app. Tony walks the following steps in a preview build:

1. Sign in with a demo band that has both income and expense entries; open Financials.
   Expected: card list renders; no horizontal scroll; summary header shows `TOTAL <mode>` + total + date-range + `N transactions` + two chevron links.
2. Toggle Income ↔ Expenses.
   Expected: label + color of total switch (green → red), count updates, list updates.
3. Cycle All Time / This Year / This Month / Custom.
   Expected: total, count, and date-range label all update per selection. Custom picker still opens.
4. Tap the sort control (`"Newest first ▾"`) in the Transactions section header.
   Expected: label flips to `"Oldest first ▾"` in one paint; the list re-sorts so the oldest transaction is now at the top and the newest is at the bottom; summary header total, count, and date-range label do **not** change. Tap again → label returns to `"Newest first ▾"` and list returns to original order.
5. Pop back to the Home tab and re-open Financials.
   Expected: sort control resets to `"Newest first ▾"` (not persisted across screen dismiss — expected behavior, not a bug).
6. Tap "View Savings Balance".
   Expected: existing `_SavingsSheet` opens with the same animated total behavior as today.
7. Tap "Generate Report".
   Expected: existing `FinancialsPdfPreviewScreen` opens with the same combined report. **Sort order in the report is unchanged (newest-first) regardless of the on-screen sort toggle** — report reads from `dateFilteredEntries`, not the sorted UI list.
8. Tap a transaction card in the current sort order.
   Expected: details sheet opens for the exact tapped entry (verify by amount + date). Icons are gone from detail rows. Labels read "Paid by", "Notes". Explicit "Reimbursed: Yes/No" row visible on expense entries. "Related to gig" row present on every entry (No / Yes • name / Yes).
9. From details, tap Edit.
   Expected: Add sheet opens pre-filled — no regression on the edit flow. Save + return.
10. Add a new expense with `paidToName = "Test Vendor"`, verify a new card appears in the correct position for the current sort (top when "Newest first", bottom when "Oldest first") with title `"Test Vendor"`, subtitle = category. Total updates by the entered amount. Count increments.
11. Delete the entry via details sheet Delete button.
    Expected: card disappears, total decrements, count decrements.
12. Open Financials on a fresh band with zero entries → `_EmptyState` shows (same copy as today). Sort control still renders on the section header row (visible with no list under it is acceptable) or is hidden — either is fine as long as no overflow / no crash occurs. Confirm which and note in the PR.
13. Verify on iOS build, Android build, macOS build, and web build that:
    - No horizontal scroll appears on the transaction list at narrow widths (iPhone SE, ~320 px web).
    - Chevron links wrap gracefully at narrow widths (no overflow, no truncation).
    - Empty state still centers correctly.
    - Sort control tap target is comfortably reachable (not clipped by the section header padding) on all four platforms.

### Tier 2 — post-deploy
not applicable — no DB migration, no RPC change, no RLS change, no edge function change, no external API change. Nothing to validate against production data after apply.

## QA Regression Areas

Static analysis + widget tests + diff review are the mechanical gate. Beyond those, in the punch list above, QA must call attention to the following areas explicitly so Tony walks them:

1. **Contributor-role read path** — sign in as a contributor with `can_view_financials = true`; screen should render identically. With `can_view_financials = false`, contributor should not be able to reach the screen (existing behavior, not changed).
2. **Legacy gig-linked entries** — an entry with `gigId` pointing to a gig that still exists shows `"Yes • <name>"`. `financial_entries.gig_id` has `ON DELETE SET NULL`, so entries pointing to deleted gigs have `gigId = null` at rest and show `"No"`.
3. **Long paidToName / payerName** — cards must ellipsis, not overflow.
4. **Large totals** (e.g., $1,234,567.89) — must render on one line without wrapping the total figure.
5. **`_SavingsSheet` confetti + count-up animation** — should behave exactly as today (unchanged code path).
6. **Report PDF generation** — should behave exactly as today (unchanged code path). The on-screen sort toggle must **not** affect report row order — reports are driven by `dateFilteredEntries` (newest-first, unchanged).
7. **Add / Edit form** — the general Add sheet still has no `isReimbursed` toggle; expense entries created via it will always read `"Reimbursed: No"`. This is expected in this PR (see System Impact Map).
8. **Sort toggle** — tapping `"Newest first ▾"` / `"Oldest first ▾"` reliably reverses the list order in one paint, updates the label in the same paint, and does not invoke any `financialsProvider` mutation. Sort state resets on screen dismiss/re-open (not persisted — expected). Sort does not leak into `_SavingsSheet` or the combined report.

## Rollout Strategy
Single PR. No feature flag. No phased rollout. No DB migration to sequence with the app deploy. Merge to `main` → deploy to iOS / Android / macOS / web via the standard `tools/build_*.sh` + `tools/deploy_web.sh` pipeline. Rollback = revert the PR; no data changes to unwind.

## Out of Scope

**Cycle 4 note:** three of the bullets below (the year-picker bullet, the `FinancialsState`/`FinancialsNotifier` bullet, and the `FinancialsPdfPreviewScreen`/`_DateFilterRow`/`_FilterChip` bullet) are **flipped by Cycle 4** — see **Cycle 4 Scope Expansion** at the bottom of this document for the specific changes. The Cycle 1 bullets below are preserved verbatim as the historical record of what was out of scope for Cycles 1–3.

- Additional sort axes beyond newest/oldest date (not amount, not category, not payer/payee) — the toggle is strictly two-state.
- Persisting sort preference across screen dismiss, band switch, or app restart — not asked for, adds a preferences dependency not otherwise in scope.
- Sort control in `_SavingsSheet` or the combined report — sort is scoped to the main transactions list only.
- Year-picker date-range control — resolved final: keep existing 4 chips. **[Flipped by Cycle 4.]**
- Tappable gig name in "Related to gig" row — resolved final: plain text, no navigation.
- Colored circular category icons on cards — Tony explicitly excluded.
- Adding `isReimbursed` toggle to `add_financial_entry_bottom_sheet.dart` — known pre-existing gap, tracked separately.
- Any change to `FinancialEntry` model, `FinancialEntryRepository`, or `FinancialsState` / `FinancialsNotifier`. **[Partially flipped by Cycle 4 — `FinancialsState`/`FinancialsNotifier` change; `FinancialEntry` model and `FinancialEntryRepository` remain byte-identical.]**
- Any change to `FinancialsPdfPreviewScreen`, `_SavingsSheet`, `_ViewModeToggle`, `_DateFilterRow`, `_FilterChip`, `_EmptyState`, `_ErrorState`. **[Partially flipped by Cycle 4 — `FinancialsPdfPreviewScreen`, `_DateFilterRow`, `_FilterChip` change; `_SavingsSheet`, `_ViewModeToggle`, `_EmptyState`, `_ErrorState` remain byte-identical.]**
- Any change to gig data flow, `bandFullStateProvider`, or the `get_band_full_state` RPC.
- Any RLS or migration work.
- Any pubspec change.

---

# Cycle 4 Scope Expansion

> **Cycle 6 supersession notice.** Cycle 4 introduced `selectedYear: int` on `FinancialsState`, `setSelectedYear(int)` on the notifier, a fixed `int selectedYear` constructor param on `FinancialsPdfPreviewScreen`, an `_availableYears(...)` helper, and `_YearSelector` / `_YearSelectorChip` widgets. **All of that surface is superseded by Cycle 6** — the state field becomes `dateFilter: FinancialDateFilter`, the notifier method becomes `setDateFilter(FinancialDateFilter)`, the PDF screen takes `dateFilter: FinancialDateFilter` (no year int), `_availableYears` is deleted entirely, and the `_YearSelector` / `_YearSelectorChip` deletion planned by Cycle 5 stands. Cycle 4's "merge date-range and count onto a single centered line separated by ` • `" decision **survives** (still the target layout); Cycle 4's "the leading token in that line is the numeric year" decision is **reversed** for the `thisYear` case (now shows the text `'This year'`). Cycle 4's descending PDF filename form `"Year YYYY"` **survives** for the `thisYear` case only; `allTime` and `thisMonth` add their own label forms. Read Cycle 6 for the current authoritative design.

Cycle 4 is a scope-expansion revision landing on top of Cycles 1–3, on the same branch (`feature/financials-transaction-cards`), before PR #273 merges. The mechanical branch state at plan-write time: local `feature/financials-transaction-cards` at commit `8dac09a` (two commits ahead of `origin/main` at `06bd222`), `git merge-base main feature/financials-transaction-cards` equals current `main` HEAD — base is clean, no rebase needed.

## Cycle 4 Problem Summary

Tony tested the merged-pending PR and asked for three coordinated changes to the header area of `_SummaryHeader` and the surrounding filter-control row in [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart):

1. Merge the two-line `_dateRangeLabel` + transaction-count into a **single line** separated by `" • "` — example: `"2026 • 3 transactions"` (or `"2026 • 1 transaction"`).
2. The displayed year must be the **actual current calendar year** by default (`DateTime.now().year`), so the label reads `"2027 • …"` if the user runs the app on Jan 1 2027 without touching any control.
3. Replace the four existing date-filter chips (`_DateFilterRow` / `_FilterChip`: "All Time", "This Year", "This Month", "Custom") with a **single year-select dropdown control**, placed in the same slot in the header column.

The change applies identically to both Income and Expenses view modes — the summary header is already shared between them and does not need to diverge per mode. Verified by reading `_SummaryHeader.build` (which reads `state.viewMode` only for the `TOTAL INCOME`/`TOTAL EXPENSES` label and the total color, and reads `state.filteredEntries` for total + count — both already viewMode-aware via `FinancialsState.filteredEntries`).

## Cycle 4 Interpretation Confirmation

The Manager's interpretation — that "This Year" is *subsumed by* the new year-select dropdown (picking any year in the dropdown does what "This Year" used to do for whichever year is selected, with the current calendar year as the default), while "All Time", "This Month", and "Custom" (arbitrary date-range picking) are dropped entirely as filter options — **sanity-checks correctly against the current code and is committed to for this plan**. Rationale:

- `FinancialDateFilter.thisYear`'s existing behavior is exactly `e.entryDate.year == DateTime.now().year` ([financials_controller.dart line 82–84](lib/features/financials/financials_controller.dart#L82-L84)) — equivalent to the new dropdown's default of `selectedYear = DateTime.now().year` filtering by `e.entryDate.year == state.selectedYear`.
- The new dropdown generalizes this: users can now pick any year the band has data for (or the current year), whereas "This Year" was hardcoded to `DateTime.now().year`.
- "All Time" (cross-year totals) has no direct analogue in the new state — deliberately dropped. If Tony later wants to view all years, that's a separate feature (e.g., an "All years" option prepended to the dropdown), and is out of scope for Cycle 4.
- "This Month" (month-level filter) has no direct analogue — deliberately dropped.
- "Custom" (arbitrary date-range picking via `showDateRangePicker`) has no direct analogue — deliberately dropped, along with the entire `_pickCustomRange` code path and the `customStartDate` / `customEndDate` state fields.

**No reason to believe otherwise.** If Tony later asks for month-level filtering or arbitrary date ranges, that's Cycle 5+ and will require re-adding state fields; the Cycle 4 shape does not preclude such an expansion but does not include it.

## Cycle 4 Root Cause
n/a — UI/UX change. Confidence `HIGH` on the mechanical scope (all state fields, widgets, and PDF-report call sites confirmed by reading the files).

## Cycle 4 Existing System Analysis (post-Cycles 1–3 baseline)

Current state at commit `8dac09a`:

- **`FinancialsState`** ([financials_controller.dart line 19–100](lib/features/financials/financials_controller.dart#L19-L100)) holds `viewMode`, `dateFilter: FinancialDateFilter`, `customStartDate: DateTime?`, `customEndDate: DateTime?`. `_applyDateFilter` switches on `dateFilter` across four cases. `filteredEntries` (viewMode + date filter, newest-first sorted) and `dateFilteredEntries` (date filter only, newest-first sorted) both call `_applyDateFilter`. `setDateFilter(FinancialDateFilter)` and `setCustomDateRange(DateTime, DateTime)` are the two mutation methods; `setCustomDateRange` sets `dateFilter = FinancialDateFilter.custom` implicitly.
- **`_DateFilterRow`** + **`_FilterChip`** ([financials_screen.dart line 470–590](lib/features/financials/financials_screen.dart#L470-L590)) render the four chips in a horizontal scroll view, dispatching to `setDateFilter`/`setCustomDateRange`. `_pickCustomRange` opens `showDateRangePicker` bounded to `now.year - 10` … `now.year + 2`. `_customLabel` formats the picked range using `MMM d` / `MMM d, yy`. All of this is deleted in Cycle 4.
- **`_SummaryHeader._dateRangeLabel`** ([financials_screen.dart line 785–806](lib/features/financials/financials_screen.dart#L785-L806)) currently switches on `state.dateFilter` and returns one of four label forms. Cycle 4 simplifies to a single `'${state.selectedYear}'` branch, and the header body renders `"$year • $count $noun"` on one line instead of two separate `Text` widgets.
- **`FinancialsPdfPreviewScreen`** ([financials_pdf_preview_screen.dart line 27–83](lib/features/financials/financials_pdf_preview_screen.dart#L27-L83)) takes `dateFilter`, `customStartDate`, `customEndDate` as constructor params; `_filterLabel` returns one of `"All Time"` / `"Year 2026"` / `"April 2026"` / `"Mar 1, 2026 – Mar 20, 2026"` depending on the four filter cases. `_fileName` interpolates `_filterLabel` into the PDF filename. In Cycle 4 the constructor takes only `int selectedYear` and `_filterLabel` becomes `'Year $selectedYear'` (preserves the existing `"Year 2026"` form used by the PDF).
- **`_openCombinedReport`** ([financials_screen.dart line 696–716](lib/features/financials/financials_screen.dart#L696-L716)) is the sole call site of `FinancialsPdfPreviewScreen`, verified by workspace-wide grep. Passes `state.dateFilter`, `state.customStartDate`, `state.customEndDate` today — becomes `selectedYear: state.selectedYear` in Cycle 4.
- **Existing Cycle 1 tests** — `summary_header_test.dart` directly references `FinancialDateFilter.thisYear`, `.thisMonth`, `.custom`, `customStartDate`, `customEndDate`, and asserts on `"All time"` / `"Mar 1 – Mar 20"` label strings. Cycle 4 rewrites these cases (see **Cycle 4 Engineer Task Breakdown → Task 6**). `transaction_card_test.dart` and `transactions_list_header_test.dart` use only `allEntries` and `viewMode` on `FinancialsState`, so they remain source-compatible with the Cycle 4 state-shape change — but their test fixtures use a hardcoded `entryDate: DateTime(2026, 1, 15)` default in `_entry`, which becomes fragile once `DateTime.now().year != 2026` (any entry outside the current year will be filtered out of `filteredEntries` under Cycle 4 semantics). Fix mandated in Task 7 to make fixtures year-relative.

**No other files reference `FinancialDateFilter`, `customStartDate`, `customEndDate`, `setDateFilter`, or `setCustomDateRange` in the workspace** — confirmed by grep across `**/*.dart` (95 matches, all inside the four files above).

## Cycle 4 Proposed Solution

### State-shape decision — `FinancialsState`

Replace the enum entirely. New shape:

```dart
class FinancialsState {
  final List<FinancialEntry> allEntries;
  final bool isLoading;
  final String? error;
  final FinancialViewMode viewMode;
  final int selectedYear;               // NEW — default: DateTime.now().year

  const FinancialsState({
    this.allEntries = const [],
    this.isLoading = false,
    this.error,
    this.viewMode = FinancialViewMode.income,
    int? selectedYear,                  // Nullable in the constructor so the
  }) : selectedYear = selectedYear ??   // default can be a runtime value.
                     _defaultSelectedYear();

  static int _defaultSelectedYear() => DateTime.now().year;
  // ...
}
```

Deleted from `FinancialsState`: `dateFilter`, `customStartDate`, `customEndDate`, and the corresponding `copyWith` params (`dateFilter`, `customStartDate`, `customEndDate`, `clearCustomDates`). Added to `copyWith`: `int? selectedYear`. The `filteredEntries` / `dateFilteredEntries` getters keep their signatures; `_applyDateFilter` collapses to:

```dart
List<FinancialEntry> _applyDateFilter(Iterable<FinancialEntry> source) {
  final entries = source
      .where((e) => e.entryDate.year == selectedYear)
      .toList();
  entries.sort((a, b) => b.entryDate.compareTo(a.entryDate));
  return entries;
}
```

**Rationale for full enum removal vs. shrinking the enum:** shrinking `FinancialDateFilter` to a one-case enum (`{thisYear}`) plus a `selectedYear: int` field would leave dead switch cases and a redundant discriminator. Semantically there is only one filter mode now ("year"); modeling it as a scalar `int selectedYear` is honest about what the state actually represents and drops ~20 lines of enum plumbing (default value, copyWith case, switch dispatch, `clearCustomDates` flag). This is a bigger textual delta but a cleaner conceptual result. The rest of the plan (widget code, PDF screen, tests) reads more naturally against the scalar shape.

Deleted from `FinancialsNotifier`: `setDateFilter(FinancialDateFilter)`, `setCustomDateRange(DateTime, DateTime)`. Added: `setSelectedYear(int year)`:

```dart
void setSelectedYear(int year) {
  state = state.copyWith(selectedYear: year);
}
```

Note: `Notifier.copyWith` implementations in this repo do not support setting a field to a "changed" scalar directly if the constructor uses the nullable-default pattern above. The `copyWith` implementation for the new `selectedYear` field must be `selectedYear: selectedYear ?? this.selectedYear` — standard pattern, no special handling needed since `selectedYear` is a non-nullable `int` on the state (only nullable in the constructor for defaulting).

### Year-list derivation decision — dropdown items

The dropdown's menu items are computed on each rebuild of the new `_YearSelector` widget:

```dart
List<int> _availableYears(List<FinancialEntry> allEntries) {
  final years = <int>{DateTime.now().year};
  for (final e in allEntries) {
    years.add(e.entryDate.year);
  }
  final sorted = years.toList()..sort((a, b) => b.compareTo(a));  // descending
  return sorted;
}
```

**Rationale for "distinct years in data + always current year" vs. fixed range (`now.year - 10` … `now.year + 2`):**

- **Chose "distinct in data + current year"** because the dropdown is a *filter* control (shows the user which years they have data for), not a *creation* control (where a fixed range guarantees the user can pick any date). For a brand-new band with zero entries, the dropdown shows just the current year — which is fine and matches the default filter behavior; the user has nothing else to filter to. For a band with entries spread across 2023–2026 plus a future gig in 2027, the dropdown shows `[2027, 2026, 2025, 2024, 2023]` in descending order.
- Descending order (newest year first) matches the existing "newest-first" ordering the summary and list both use.
- Current year is always included even when there's no data for it, so a user landing on a fresh band on Jan 2 2027 still sees "2027" as the default and doesn't get a jarring "no year selected" dropdown state.
- **Rejected the fixed range** because it would show 13 years of empty selections for a new band, most of which the user would never touch — visual noise, and misleading (implies data might exist for those years). The Cycle 1 custom-picker used the fixed range because it was picking arbitrary dates from a continuous calendar; the dropdown picks from a discrete set the user has actually recorded data in.
- Edge case — if a user enters a typo'd date (e.g., 2999) into an entry, the dropdown will show `2999` as an option. Acceptable: dropdown reflects reality, and the user can immediately notice the misfiled entry and fix it via the edit sheet. Not worth guarding against.

Derivation reads `state.allEntries` (not `state.filteredEntries`) — the year list is viewMode-agnostic. A year with only expense entries should still be pickable while viewing income (the user might switch modes after picking), and vice versa.

### `_YearSelector` widget

Replaces `_DateFilterRow` in the same slot. New private widget in `financials_screen.dart`:

```dart
class _YearSelector extends ConsumerWidget {
  const _YearSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(financialsProvider);
    final years = _availableYears(state.allEntries);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PopupMenuButton<int>(
          initialValue: state.selectedYear,
          onSelected: (year) =>
              ref.read(financialsProvider.notifier).setSelectedYear(year),
          itemBuilder: (_) => years
              .map((y) => PopupMenuItem<int>(value: y, child: Text('$y')))
              .toList(),
          child: _YearSelectorChip(year: state.selectedYear),
        ),
      ),
    );
  }
}

class _YearSelectorChip extends StatelessWidget {
  const _YearSelectorChip({required this.year});
  final int year;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space12,
        vertical: Spacing.space8,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(Spacing.chipRadius),
        border: Border.all(color: AppColors.primary),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$year',
            style: AppTextStyles.footnote.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: Spacing.space4),
          const Icon(Icons.arrow_drop_down,
              size: 18, color: AppColors.primary),
        ],
      ),
    );
  }
}
```

**Visual rationale:** the chip child is styled to match the "active" state of the departing `_FilterChip` — same padding, same rounded pill, same `AppColors.primary` accent — so users see a familiar control replace the row of chips, just narrower and with a chevron indicating the popup. `PopupMenuButton` is chosen over `AppDropdown` (which wraps Forui's `FSelect` with full field chrome) because the visual weight of a form-field dropdown would break the header's compact filter-row rhythm; `PopupMenuButton` has one existing precedent in the codebase ([pending_invite_card.dart line 153](lib/features/members/widgets/pending_invite_card.dart#L153)) and produces a compact popup menu that fits this use case. **No new dependency, no Forui integration required.**

Left-aligned via `Align(alignment: Alignment.centerLeft)` inside the header padding — matches where the leftmost chip sat in `_DateFilterRow` today, minimizing visual regression on the header layout.

### `_SummaryHeader` — merged `_dateRangeLabel • count` line

The two consecutive `Text` widgets (`_dateRangeLabel(state)` and `count == 1 ? '1 transaction' : '$count transactions'`) in the current `_SummaryHeader.build` collapse into a single `Text` widget:

```dart
Text(
  '${state.selectedYear} • ${count == 1 ? '1 transaction' : '$count transactions'}',
  textAlign: TextAlign.center,
  style: AppTextStyles.footnote
      .copyWith(color: context.colors.textMuted),
),
```

- `_dateRangeLabel` helper method is **deleted** — no callers remain outside the merged line, and the single-branch year label is trivial enough to inline.
- The intermediate `SizedBox(height: Spacing.space4)` between the two lines is deleted along with one of the two `Text` widgets.
- Center alignment (Cycle 3) is preserved: `textAlign: TextAlign.center` stays, and the `Column` inside `_SummaryHeader` continues to render its children centered.
- The `TOTAL INCOME`/`TOTAL EXPENSES` label, the big total, and the two-link row (`View Savings Balance` / `Generate Report`) are all unchanged.

### `FinancialsPdfPreviewScreen` — constructor + label

Minimal surgical change:

- Constructor: drop `dateFilter`, `customStartDate`, `customEndDate`. Add `required int selectedYear`.
- `_filterLabel` getter: replace the four-case switch with `String get _filterLabel => 'Year ${widget.selectedYear}';`. This preserves the exact `"Year 2026"` string form used today for the `thisYear` case — the report header and PDF filename ("`{Band Name} – Financial Report (Year 2026).pdf`") both render identically for the current-year default, so the PDF/print/share output shape does not change.
- `_viewModeLabel`, `_fileName`, `_buildPdf`, `_handlePrint`, `_handleShare`, `build` — all unchanged.
- `buildFinancialsReportContent` in [financials_report_builder.dart](lib/features/financials/financials_report_builder.dart) takes `dateRangeLabel: String` — no signature change, still receives `_filterLabel`'s output.

Sole caller ([_openCombinedReport](lib/features/financials/financials_screen.dart#L696-L716)) drops the three chip-state params and passes `selectedYear: state.selectedYear`.

### Change applies identically to Income and Expenses modes

Confirmed by reading `_SummaryHeader.build`: the merged `_dateRangeLabel • count` line reads only `state.filteredEntries.length` for the count, which is already viewMode-aware, and the year label reads `state.selectedYear` which is viewMode-independent. The dropdown widget reads `state.allEntries` (viewMode-independent). Nothing needs to diverge per mode. No conditional branches added.

## Cycle 4 Database Impact
not applicable — no schema change, no new RPC, no RLS change, no migration. Selected-year state is transient Riverpod UI state; not persisted to Supabase.

## Cycle 4 Flutter Architecture Changes

- **`FinancialsState` shape changes** — `dateFilter`, `customStartDate`, `customEndDate` deleted; `selectedYear: int` added, defaulting to `DateTime.now().year` via a static default helper (`selectedYear = selectedYear ?? _defaultSelectedYear()` in the constructor initialiser list, since `DateTime.now()` can't be a compile-time default). `copyWith` signature updated accordingly.
- **`FinancialsNotifier` mutation methods** — `setDateFilter`, `setCustomDateRange` deleted; `setSelectedYear(int)` added. `build`, `_load`, `addEntry`, `updateEntry`, `deleteEntry`, `refresh` — all unchanged.
- **`FinancialDateFilter` enum** — deleted.
- **`_YearSelector` and `_YearSelectorChip`** — new private widgets in `financials_screen.dart`. `_YearSelector` is a `ConsumerWidget`; `_YearSelectorChip` is a `StatelessWidget`.
- **`_DateFilterRow`, `_FilterChip`** — deleted from `financials_screen.dart`. The `_pickCustomRange` helper and `_customLabel` getter go with them.
- **`_SummaryHeader._dateRangeLabel`** — deleted; label logic inlined into the merged single-line `Text` widget.
- **`FinancialsPdfPreviewScreen` constructor** — three params dropped, one added (see Proposed Solution). `_filterLabel` collapses to a single-line getter.
- No new provider, controller, repository, or model. No pubspec change.

## Cycle 4 Files to Create

None. All widget additions live inside existing files; existing test files are edited, not replaced.

## Cycle 4 Files to Modify

### [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart)
- Delete `enum FinancialDateFilter { allTime, thisYear, thisMonth, custom }`.
- Delete `dateFilter`, `customStartDate`, `customEndDate` fields on `FinancialsState`, their constructor params, their `copyWith` params, and the `clearCustomDates` flag.
- Add `final int selectedYear;` field. Constructor accepts a nullable `int? selectedYear` and initialises via `selectedYear = selectedYear ?? DateTime.now().year`.
- Update `copyWith` to accept `int? selectedYear` and merge with the existing pattern.
- Replace `_applyDateFilter` body with the single-year filter shown in Proposed Solution → State-shape decision.
- Delete `setDateFilter(FinancialDateFilter)` and `setCustomDateRange(DateTime, DateTime)` from `FinancialsNotifier`.
- Add `void setSelectedYear(int year) { state = state.copyWith(selectedYear: year); }`.

### [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart)
- Delete `_DateFilterRow`, `_FilterChip`, `_pickCustomRange`, `_customLabel`.
- Delete the `_DateFilterRow(...)` render call in `_FinancialsScreenState.build` (currently between the `_ViewModeToggle` render and the `SizedBox(height: Spacing.space16)`). Replace with a `const _YearSelector()` render call in the same slot.
- Add `_YearSelector` and `_YearSelectorChip` private widgets at the appropriate section boundary (after `_ViewModeToggle`'s section, replacing `_DateFilterRow`'s section).
- Merge the two `Text` widgets in `_SummaryHeader.build` (the `_dateRangeLabel(state)` line and the count line) into a single `Text` widget with the value `'${state.selectedYear} • ${count == 1 ? '1 transaction' : '$count transactions'}'`. Delete the `_dateRangeLabel` helper and one of the two intermediate `SizedBox(height: Spacing.space4)` spacings.
- In `_openCombinedReport`, replace `dateFilter: state.dateFilter, customStartDate: state.customStartDate, customEndDate: state.customEndDate` with `selectedYear: state.selectedYear`.
- Audit imports: `intl`'s `DateFormat` is still used by `_TransactionCard` and `_SavingsSheet`, so keep. No new imports required (`PopupMenuButton` and `Icons.arrow_drop_down` are already in `package:flutter/material.dart` which is already imported).

### [lib/features/financials/financials_pdf_preview_screen.dart](lib/features/financials/financials_pdf_preview_screen.dart)
- Delete constructor params `FinancialDateFilter dateFilter`, `DateTime? customStartDate`, `DateTime? customEndDate`. Add `required int selectedYear`.
- Delete the four-case `_filterLabel` switch. Replace with `String get _filterLabel => 'Year ${widget.selectedYear}';`.
- `_viewModeLabel`, `_fileName`, `_buildPdf`, `_handlePrint`, `_handleShare`, `build` — untouched.
- Audit imports: remove `import 'financials_controller.dart';` **only if** no other reference to `FinancialViewMode` (used by `_viewModeLabel`) remains — it does, so keep the import.

### [test/features/financials/widgets/summary_header_test.dart](test/features/financials/widgets/summary_header_test.dart)
- Delete the four "date-range sub-label matches the resolved value for X" test cases (`allTime`, `thisYear`, `thisMonth`, `custom`).
- Add three new cases in their place:
  - "displays the current calendar year by default" — pump a state with default `selectedYear`, assert `find.textContaining('${DateTime.now().year} • ')` finds one widget.
  - "displays the selected year when `setSelectedYear` sets a non-current year" — pump a state with `selectedYear: DateTime.now().year - 1` and one entry in that year, assert the previous-year value is shown.
  - "merges year and count into a single line separated by ' • '" — pump a state with three entries in the default year, assert `find.text('${DateTime.now().year} • 3 transactions')` finds one widget (and the two separate strings `'${DateTime.now().year}'` alone / `'3 transactions'` alone are NOT found as full-string `Text` matches on separate widgets).
- Update the existing "count phrasing is singular for one entry, plural for multiple entries" case to assert the merged form: `'${DateTime.now().year} • 1 transaction'` and `'${DateTime.now().year} • 3 transactions'`.
- Existing "total …", "label reads TOTAL INCOME/EXPENSES", and "View Savings Balance / Generate Report chevron" cases are unchanged — they don't depend on the deleted state fields.

### [test/features/financials/widgets/transaction_card_test.dart](test/features/financials/widgets/transaction_card_test.dart) and [test/features/financials/widgets/transactions_list_header_test.dart](test/features/financials/widgets/transactions_list_header_test.dart)
- **Necessary correction, not scope expansion:** the shared `_entry` / `_makeEntry` fixture in both files defaults `entryDate` to `DateTime(2026, 1, 15)`. Under Cycle 4 semantics, entries whose year != `state.selectedYear` (default = `DateTime.now().year`) are filtered out of `filteredEntries` — so once the wall clock rolls to 2027 these tests will render an empty list and fail. Update the defaults to `DateTime(DateTime.now().year, 1, 15)` (or the local equivalent) so the fixture stays valid across year rollovers.
- No other test-body changes required — these tests only read `allEntries` and `viewMode` off `FinancialsState`, both of which are unchanged.

### New Cycle 4 test file: [test/features/financials/widgets/year_selector_test.dart](test/features/financials/widgets/year_selector_test.dart)
- Widget test file for `_YearSelector`. Since the widget is private, pump the enclosing screen with an overridden `financialsProvider` — same pattern as the Cycle 1 tests. Assertions:
  - Renders the current `state.selectedYear` as the chip's visible text (e.g., `'2026'`).
  - Tapping the chip opens a popup menu containing exactly the derived year list (current year + distinct years across `allEntries`, descending). Verify with entries spanning `[2023, 2025, current, future=current+1]`.
  - Selecting a different year dispatches `setSelectedYear(int)` on the notifier — capture the notifier state via `container.read` before/after and confirm `selectedYear` updated to the tapped value.
  - Zero entries → dropdown has exactly one item (`current year`) and is still tappable / renders without crash.
  - Chip's `▾` chevron (`Icons.arrow_drop_down`) is present alongside the year text.

## Cycle 4 Change Budget

| File | Expected net Δ lines | Rationale |
| --- | --- | --- |
| `lib/features/financials/financials_controller.dart` | **−20 to −5** | Delete enum (2 lines), delete 3 state fields + constructor params + copyWith params + clearCustomDates flag (~30 lines), delete `setDateFilter` and `setCustomDateRange` (~10 lines), simplify `_applyDateFilter` (~15 lines removed). Add `selectedYear` field + constructor default + copyWith + `setSelectedYear` (~15 lines). Net: −20 to −5. |
| `lib/features/financials/financials_screen.dart` | **−140 to −80** | Delete `_DateFilterRow` (~94 lines), `_FilterChip` (~40 lines), and the two helper methods folded into `_DateFilterRow` (already counted). Delete `_SummaryHeader._dateRangeLabel` (~22 lines), merge two `Text` widgets + one `SizedBox` in `_SummaryHeader.build` (~15 lines removed). Update `_DateFilterRow(...)` render call in `_FinancialsScreenState.build` (~12 lines → 1 line). Update `_openCombinedReport` call site (3 lines replaced with 1). Add `_YearSelector` (~25 lines) + `_YearSelectorChip` (~30 lines). Net range accounts for whether widgets grow to accommodate final styling. |
| `lib/features/financials/financials_pdf_preview_screen.dart` | **−15 to −5** | Constructor: drop 3 params, add 1 (~6 lines removed). `_filterLabel`: replace 15-line switch with 3-line getter (~12 lines removed). Net: −15 to −5. |
| `test/features/financials/widgets/summary_header_test.dart` | **−30 to +20** | Delete 4 test cases (~90 lines), add 3 new cases (~60 lines), edit 1 case (~5 lines). Net wide range. |
| `test/features/financials/widgets/transaction_card_test.dart` | **0 to +2** | Fixture default `entryDate` swap only. |
| `test/features/financials/widgets/transactions_list_header_test.dart` | **0 to +2** | Fixture default `entryDate` swap only. |
| `test/features/financials/widgets/year_selector_test.dart` (new) | **+150 to +250** | New widget test file, ~5 test cases + `ProviderScope` setup + fake notifier. |
| Any other file | **0** | Off-limits (Cycle 4). |

- Expected new files: **1** (`year_selector_test.dart`).
- Expected new public classes / methods on production code: **0** (widgets and the notifier method all private / private-to-file).
- Expected new dependencies (pubspec.yaml): **0**.
- Expected migration files: **0**.

## Cycle 4 System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Financials → Screen | changed (in-scope) | Chip row → year dropdown; merged summary line. |
| Financials → Controller | changed (in-scope) | State shape simplifies (drop 3 fields, add 1). Method surface swaps. |
| Financials → PDF Report Screen | changed (in-scope) | Constructor + label helper simplified. Output PDF filename/header string preserved as `"Year YYYY"`. |
| Financials → PDF Report Builder | unaffected | Takes `dateRangeLabel: String`; still gets the same shape of string. |
| Financials → Add / Edit Sheet | unaffected | Independent of filter state. |
| Financials → Details Sheet | unaffected | Independent of filter state. |
| Financials → Savings Sheet | unaffected | Reads `state.allEntries` (unfiltered). |
| Gigs / Rehearsals / Setlists / Members | unaffected | No cross-references. |
| Auth / Routing / Notifications | unaffected | No init-order change, no session change. |
| Platforms (iOS / Android / macOS / Web) | uniformly affected | Shared Flutter UI only; `PopupMenuButton` renders natively on all four. No platform-conditional code. |
| Supabase schema / RLS / RPCs | unaffected | Client-only change. |
| pubspec.yaml | unaffected | No new dependency. |

## Cycle 4 Regression Risk
**LOW**. Justification:
- Still no touch to auth, session, routing, init order, DB, RLS, RPCs, or platform-conditional code.
- State-shape change is contained to one file, one notifier, three straightforward field edits.
- No new provider added. One method renamed on an existing notifier.
- No new dependency, no new migration.
- The PDF report's on-disk output format (filename, header string, row order) is preserved via the `"Year YYYY"` label form — regression surface on the report path is nil.
- Realistic regression classes: (a) forgetting to update the single `_openCombinedReport` call site — caught at compile time by the constructor signature change; (b) test fixtures rendering empty lists after wall-clock rollover — caught by Task 7's year-relative fixture update.

## Cycle 4 Engineer Task Breakdown

Ordered, atomic. Each task leaves the app compiling. **Do not merge tasks or invent extra sub-steps.**

1. **Update `FinancialsState` shape in `financials_controller.dart`.**
   - Delete the `FinancialDateFilter` enum.
   - Delete `dateFilter`, `customStartDate`, `customEndDate` fields, their constructor named params, their `copyWith` named params, and the `clearCustomDates` flag from `copyWith`.
   - Add `final int selectedYear;` field. Constructor param: `int? selectedYear`. Initialiser list: `selectedYear = selectedYear ?? DateTime.now().year`.
   - Add `int? selectedYear` to `copyWith` params; merge with the existing pattern (`selectedYear: selectedYear ?? this.selectedYear`).
   - Replace the `_applyDateFilter` body with the single-year filter from Proposed Solution → State-shape decision.
   - Delete `setDateFilter(FinancialDateFilter)` and `setCustomDateRange(DateTime, DateTime)` from `FinancialsNotifier`.
   - Add `void setSelectedYear(int year) { state = state.copyWith(selectedYear: year); }`.
   - `flutter analyze` will now flag broken references in `financials_screen.dart` and `financials_pdf_preview_screen.dart` — that's expected, resolved in Tasks 2 and 3.

2. **Update `financials_pdf_preview_screen.dart` for the new state shape.**
   - Constructor: delete the three chip-related params. Add `required int selectedYear`.
   - Replace `_filterLabel` with the single-line year form: `String get _filterLabel => 'Year ${widget.selectedYear}';`.
   - Nothing else changes in this file.

3. **Introduce `_YearSelector` and `_YearSelectorChip` in `financials_screen.dart`.**
   - Add the two private widgets per Proposed Solution → `_YearSelector` widget, in the section between `_ViewModeToggle` and `_DateFilterRow` (which will be deleted in Task 4).
   - Do not yet swap `_DateFilterRow` in the render tree — this task leaves both `_DateFilterRow` and `_YearSelector` defined in the file so it stays compiling if built in isolation, but only `_DateFilterRow` is currently referenced from the build tree.
   - Update the `_openCombinedReport` call site in this same task: replace `dateFilter: state.dateFilter, customStartDate: state.customStartDate, customEndDate: state.customEndDate` with `selectedYear: state.selectedYear`. This is necessary for the file to compile once Task 1 lands.

4. **Swap `_DateFilterRow` → `_YearSelector` in the `_FinancialsScreenState.build` tree and merge `_SummaryHeader`'s two lines.**
   - Replace the `_DateFilterRow(current: state.dateFilter, ...)` call in `build` with `const _YearSelector()`.
   - In `_SummaryHeader.build`, delete the `_dateRangeLabel` helper method.
   - Delete the two `Text` widgets that render the date-range label and the count separately (currently two consecutive children in the `Column`), along with the `SizedBox(height: Spacing.space4)` between them. Replace with a single `Text` widget rendering `'${state.selectedYear} • ${count == 1 ? '1 transaction' : '$count transactions'}'` using the existing footnote/muted style and `TextAlign.center`.
   - This task must leave the app running and the header visually updated.

5. **Delete dead code in `financials_screen.dart`.**
   - Delete `_DateFilterRow`, `_FilterChip`, `_pickCustomRange`, `_customLabel`.
   - Audit for any imports only these classes used — none expected, but confirm.

6. **Update `summary_header_test.dart` for the new label shape.**
   - Delete the four "date-range sub-label matches the resolved value for X" cases (`allTime`, `thisYear`, `thisMonth`, `custom`).
   - Add the three new cases per Files to Modify → `summary_header_test.dart`.
   - Update the "count phrasing" case to assert the merged form.
   - Existing "total …", "label reads TOTAL INCOME/EXPENSES", and "chevron" cases stay as-is.

7. **Update fixture defaults in `transaction_card_test.dart` and `transactions_list_header_test.dart`.**
   - Replace the hardcoded `DateTime(2026, 1, 15)` default in `_entry` / `_makeEntry` with `DateTime(DateTime.now().year, 1, 15)`.
   - No test-body changes required — the assertions still hold since all entries in a given test share the same year and match the default `selectedYear`.

8. **Add `year_selector_test.dart`.**
   - Create the new file under `test/features/financials/widgets/` following the same pattern as the Cycle 1 test files (`_FakeFinancialsNotifier`, `_pump` helper, `ProviderScope` override).
   - Implement the five assertions listed in Files to Modify → new `year_selector_test.dart`.

## Cycle 4 Verification Plan

### Cycle 4 Tier 1 — pre-deploy (QA gate, mechanically executable)

QA gate for APPROVED requires all of the following without running the app:

1. `flutter analyze` clean (no new lints).
2. `flutter test` passes, including the updated `summary_header_test.dart`, the fixture-updated `transaction_card_test.dart` and `transactions_list_header_test.dart`, and the new `year_selector_test.dart`.
3. Diff review confirms these files are byte-identical to `main`:
   - `lib/features/financials/financial_entry_repository.dart`
   - `lib/features/financials/models/financial_entry.dart`
   - `lib/features/financials/financials_report_builder.dart`
   - `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
   - `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`
   - `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` (changed in Cycles 1–3, no further change in Cycle 4)
   - All `supabase/migrations/**` files
   - `pubspec.yaml`
4. Diff review confirms net line delta per modified file falls inside **Cycle 4 Change Budget** ranges.
5. Diff review confirms `_DateFilterRow`, `_FilterChip`, `_pickCustomRange`, `_customLabel`, `FinancialDateFilter`, `setDateFilter`, `setCustomDateRange`, `customStartDate`, `customEndDate`, and `_dateRangeLabel` are absent from the tree (no dangling references).
6. Diff review confirms `PopupMenuButton<int>` is present in `financials_screen.dart` with `onSelected` wired to `setSelectedYear`, and that the year list is derived from `state.allEntries` (not a hardcoded range).

### Cycle 4 Tier 2 — post-deploy
not applicable — no DB migration, no RPC change, no RLS change, no edge function change, no external API change.

### Cycle 4 Owner-run punch list (Tony runs at PR-test time — QA writes this into the PR body verbatim, does not attempt it)

QA cannot run the app. Tony walks the following in a preview build (adds to the existing Cycles 1–3 punch list, doesn't replace it):

1. Sign in with a demo band containing entries in the current calendar year; open Financials.
   Expected: single year chip labeled with the current year is visible where the four filter chips used to be. Summary header line reads `"YYYY • N transactions"` on one line, where `YYYY` is the current calendar year and `N` is the transaction count for the current year.
2. Toggle Income ↔ Expenses.
   Expected: year in the summary line does not change; count and total update per the mode.
3. Tap the year chip.
   Expected: a popup menu opens showing the current year plus every distinct year the band has entries in, in descending order. No "All Time", no "This Month", no "Custom" options.
4. Select a previous year with data (e.g., last year).
   Expected: chip label updates to the selected year; summary line reads `"YYYY_prev • N transactions"` with `N` reflecting last year's count for the current view mode; transaction list re-renders showing only entries from that year; total updates accordingly.
5. Toggle Income ↔ Expenses while a non-current year is selected.
   Expected: year selection persists across the toggle; only the total and count change.
6. Sign in with a demo band containing zero entries in every year (fresh band).
   Expected: year chip shows the current calendar year; popup menu shows exactly one option (the current year); tapping it changes nothing; empty state renders below.
7. Tap "Generate Report" while a non-current year is selected.
   Expected: PDF preview opens with header/filename reading `"Year YYYY"` for the selected year (not the current year).
8. If the current calendar year has ticked over during testing (unlikely mid-session, but if reproducing on Jan 1): confirm the default `selectedYear` reflects the new year on a fresh screen entry.

## Cycle 4 QA Regression Areas

1. **PDF report filename/header** — still reads `"Year YYYY"` for whatever year is selected; no regression to the format.
2. **Sort toggle (Cycle 1)** — unaffected. Verify by cycling sort with the year selector at various years — sort still reverses the list order for the currently-filtered year.
3. **`_SavingsSheet`** — reads `state.allEntries` (viewMode-agnostic, year-agnostic). Confirm savings totals are unchanged regardless of the year selection.
4. **Empty state** — a band with entries only in past years, viewed with the current year selected, should render the empty state, not the transaction list. Confirm the empty state copy is unchanged.
5. **Fixture year-relativity** — confirm that `flutter test` remains passing without any date-mocking package needed (`DateTime.now()` in fixtures is intentional).

## Cycle 4 Rollout Strategy

Same PR as Cycles 1–3 (#273). Commits added on top of `8dac09a`. No feature flag, no phased rollout, no DB migration. Merge to `main` when Cycle 4 clears the QA gate + owner-run punch list.

## Cycle 4 Out of Scope

- Adding an "All years" option to the dropdown (cross-year totals). If Tony wants this, Cycle 5.
- Adding a "This Month" or arbitrary date-range option back. Cycle 5+ if requested.
- Persisting the selected year across screen dismiss, band switch, or app restart — not asked for; matches the Cycle 1 decision to keep filter state transient.
- Adding icons/badges to the year chip beyond the plain `▾` chevron.
- Changing the PDF report's row order or content shape.
- Any change to the transaction card, sort toggle, details sheet, savings sheet, `_ViewModeToggle`, `_EmptyState`, `_ErrorState` — all Cycle 1–3 concerns.
- Any change to `FinancialEntry`, `FinancialEntryRepository`, `financials_report_builder.dart`, gig data flow, RLS, migrations, or pubspec dependencies.

---

# Cycle 5 Scope Expansion

> **Cycle 6 supersession notice.** Cycle 5 was never implemented — Engineer stopped before Task 1 landed, Manager resolved an empty-state design conflict, then before Engineer could re-start Tony changed the filter-control design (three fixed options, not a dynamic year list). Cycle 6 supersedes Cycle 5's `AppDropdown<int>` typing, the `format: (year) => '$year'` callback, the `items: _availableYears(...).map(...)` derivation, the `_availableYears` helper retention, and the `summary_header_test.dart` `AppDropdown<int>`-typed assertions. **Cycle 5's other decisions survive verbatim and are re-adopted by Cycle 6:** the inline placement of the dropdown inside `_SummaryHeader`'s summary line (as the leading token of the ` • N transactions` row), the `IntrinsicWidth`-wrapped `AppDropdown` sizing pattern (with `SizedBox(width: 96)` fallback), the `_FinancialsScreenState.build` restructuring that keeps `_SummaryHeader` + `_TransactionsListHeader` visible in every non-error state (loading, empty, non-empty) so the filter control never vanishes, the deletion of `_YearSelector` / `_YearSelectorChip` and their standalone render call, the deletion of `year_selector_test.dart`, and the "no touch to `AppDropdown` wrapper file, no `import 'package:forui/forui.dart';` in feature code" wrapper-immutability guardrail. Read Cycle 6 for the current authoritative design of the dropdown's type, format, and items list; read the sections below for the layout, sizing, and empty-state-fix mechanics.

Cycle 5 is a follow-on revision landing on top of Cycles 1–4, on the same branch (`feature/financials-transaction-cards`), before PR #273 merges. Cycles 1–4 remain uncommitted on the working tree; Cycle 4 is already QA-APPROVED. **Do not touch the Cycle 1–4 diff.** Cycle 5 is additive — its edits land on top of the Cycle 4 tree, not by rewriting it.

Branch state at plan-write time: local `feature/financials-transaction-cards` at commit `8dac09a`, `git merge-base main HEAD` == `main` HEAD (`06bd222`) — **base is clean, no rebase needed** (confirmed by `git rev-parse` and `git merge-base` at plan-write time; matches Cycle 4's finding).

## Cycle 5 Problem Summary

Two coupled asks from Tony, landing together:

1. **Move the year picker inline into `_SummaryHeader`.** The current Cycle 4 shape renders `_YearSelector` (a `PopupMenuButton<int>`-backed chip styled with `AppColors.primary`) in its own row above the entries list, and separately renders the summary line `"YYYY • N transactions"` inside `_SummaryHeader` as static text. Tony wants the `YYYY` in that summary line to *be* the interactive year picker — one control, one place, inline in the summary line. The standalone `_YearSelector` row goes away entirely.

2. **Adopt Forui's `FSelect` via the existing `AppDropdown<T>` wrapper.** Tony linked https://forui.dev/docs/widgets/form/select and asked the year selector use Forui's `FSelect`. The project already has [lib/components/ui/app_dropdown.dart](lib/components/ui/app_dropdown.dart) — `AppDropdown<T>`, a thin wrapper around `FSelect.rich` — used by 4 direct call sites elsewhere in `lib/` (`band_form_screen.dart`, `event_editor_helpers.dart`, `gig_expense_subview.dart` x2, `add_financial_entry_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`). Do **not** introduce a new raw `FSelect` usage or a new wrapper; use `AppDropdown<int>` per the `lib/components/ui/README.md` convention ("All feature code uses these wrappers instead of calling Material or Forui widgets directly").

Engineer attempted (1) in isolation and correctly stopped when it exposed a **usability trap**: `_SummaryHeader` today is only rendered inside the `else` branch of `filtered.isEmpty ? _EmptyState : Column(children: [_SummaryHeader, ...])`. Moving the picker inside `_SummaryHeader` — while otherwise correct — means that when the user lands on a band whose data is all in a prior year (with zero entries for the currently-selected year), the summary header vanishes and the user has no reachable year control. They have to leave the screen and re-enter (which resets `selectedYear` to `DateTime.now().year`, which still shows the empty state) or switch bands and switch back — neither obvious, both frustrating. **The empty-state layout must be restructured so the year picker stays reachable.**

## Cycle 5 Root Cause
n/a for the widget swap (UI change per Tony's request).

For the empty-state trap: **root cause is the conditional in `_FinancialsScreenState.build` that renders `_SummaryHeader` only in the non-empty branch.** Confidence `HIGH` (verified in [financials_screen.dart lines ~154–225](lib/features/financials/financials_screen.dart) — the `filtered.isEmpty ? _EmptyState : Column(...)` conditional wraps *both* the header and the list, coupling them. The fix is to invert that conditional so the header sits above and only the list-content area swaps).

## Cycle 5 Existing System Analysis (post-Cycle 4 baseline)

Current state at commit `8dac09a` **plus the uncommitted Cycle 1–4 edits on the working tree**:

- **`_FinancialsScreenState.build`** ([financials_screen.dart line 154–225](lib/features/financials/financials_screen.dart#L154-L225)) — currently renders:
  ```
  Column(
    BackOnlyAppBar,
    Expanded(Column(
      PageTitle + Add button,
      SizedBox(space16),
      _ViewModeToggle,
      SizedBox(space12),
      const _YearSelector(),         ← Cycle 4 addition, to be deleted in Cycle 5
      SizedBox(space16),
      Expanded(
        state.isLoading   → CircularProgressIndicator
        : state.error != null → _ErrorState
        : filtered.isEmpty → _EmptyState                        ← header not rendered here
        : Column(                                               ← header only rendered here
            _SummaryHeader,
            _TransactionsListHeader,
            SizedBox(space8),
            Expanded(ListView.separated),
          ),
      ),
    )),
  )
  ```
- **`_YearSelector`** ([financials_screen.dart line 457–479](lib/features/financials/financials_screen.dart#L457-L479)) — the Cycle 4 `PopupMenuButton<int>`-based chip in its own row. Reads `state.allEntries` via `ref.watch(financialsProvider)`; dispatches `setSelectedYear` on selection; renders `_YearSelectorChip` as the tap target.
- **`_YearSelectorChip`** ([financials_screen.dart line 481–514](lib/features/financials/financials_screen.dart#L481-L514)) — the rose-accented pill-shaped chip displaying `state.selectedYear` + a `▾` chevron. Delete in Cycle 5 together with `_YearSelector`.
- **`_availableYears`** ([financials_screen.dart line 447–455](lib/features/financials/financials_screen.dart#L447-L455)) — a pure top-level helper that returns `[DateTime.now().year, ...distinct years in allEntries]` deduped, sorted descending. **Kept in Cycle 5** — its single caller moves from `_YearSelector` to `_SummaryHeader`, but its signature and behavior are unchanged.
- **`_SummaryHeader`** ([financials_screen.dart line 706–776](lib/features/financials/financials_screen.dart#L706-L776)) — currently a `ConsumerWidget` rendering `TOTAL <MODE>` + total + `"${state.selectedYear} • ${count == 1 ? '1 transaction' : '$count transactions'}"` (single `Text` widget) + `Row([_InlineLinkButton(View Savings Balance), _InlineLinkButton(Generate Report)])`. The single-line `Text` becomes a `Row(IntrinsicWidth(AppDropdown<int>), Text(' • N transactions'))` in Cycle 5.
- **`AppDropdown<T>`** ([lib/components/ui/app_dropdown.dart](lib/components/ui/app_dropdown.dart)) — thin wrapper around `FSelect<T>.rich` with `FSelectControl.lifted`. Renders as an `FTextField`-styled field (border, background, rounded corners, standard ~48px height and field padding — via `FTextField.defaultBuilder`). Constructor accepts `value`, `items: List<DropdownMenuItem<T>>?`, `children: List<FSelectItemMixin>?`, `onChanged: ValueChanged<T?>`, `format: String Function(T)?`, `labelBuilder` (alias for `format`), `enabled: bool`, plus `Form`-integration params (unused here). Assert requires **exactly one** of `items` or `children`. Currently used at 4 direct sites in `lib/features/*` — **all as full-width, form-field-style inputs with a label above them**. **No existing inline/compact usage in the codebase.** Cycle 5 establishes a new call-site pattern for `AppDropdown` (constrained width via `IntrinsicWidth`) — this is not a wrapper change, just a new usage constraint at the call site.
- **`_TransactionsListHeader`** ([financials_screen.dart line 803–843](lib/features/financials/financials_screen.dart#L803-L843)) — `Text("Transactions") + InkWell(sort toggle)`. Rendered today only when `filtered.isNotEmpty` (implicitly, via being inside the non-empty `Column`). In Cycle 5, per Manager's directive that "only the *list content area itself* swaps," this widget also renders unconditionally (whenever the header does). Showing a sort toggle over an empty list is minor visual noise but avoids conditional-render layout shifts as the year picker flips between years with data and years without.
- **`_EmptyState`** ([financials_screen.dart line 654–687](lib/features/financials/financials_screen.dart#L654-L687)) — `Center(Column(Icon + Text + Text))`, mainAxisAlignment center. When wrapped in `Expanded` inside a smaller area (below the summary header + list-header rows), it centers within the remaining vertical space — visually smaller than today's full-screen empty state but the same widget code. **No change to `_EmptyState` itself.** Copy stays as-is (Cycle 4's out-of-scope decision).

**No other files in `lib/` reference `_YearSelector`, `_YearSelectorChip`, or `_availableYears`** — confirmed by grep. All the Cycle 5 production edits land inside `financials_screen.dart`.

**Post-Cycle 4 tests on the working tree:**
- `test/features/financials/widgets/summary_header_test.dart` — asserts the merged single-string form `find.text('${DateTime.now().year} • 3 transactions')` in 3 cases. These break in Cycle 5 because the year moves into an `AppDropdown` widget, not the same `Text`. Must be rewritten to assert the split shape (dropdown + adjacent text).
- `test/features/financials/widgets/year_selector_test.dart` — targets `PopupMenuButton<int>` and `Icons.arrow_drop_down` by finder type. The widget it names is deleted in Cycle 5. The equivalent behaviors (renders current year, opens menu, dispatches `setSelectedYear`, zero-entries handling) move into `summary_header_test.dart` as new test cases targeting `AppDropdown<int>` and `FSelect`-internal finders. **Delete the file** rather than rewriting it in place — the widget-under-test name is gone from `lib/`, and keeping a file named after a deleted widget produces confusion.

## Cycle 5 Proposed Solution

### (a) Empty-state layout restructuring

Refactor `_FinancialsScreenState.build` so `_SummaryHeader` (containing the inline year picker after edit (b)) and `_TransactionsListHeader` always render whenever we're not in the error branch. Only the content area below them swaps between loading spinner / empty state / list. Concretely, the current:

```dart
Expanded(
  child: state.isLoading
      ? CircularProgressIndicator(...)
      : state.error != null
          ? _ErrorState(...)
          : filtered.isEmpty
              ? const _EmptyState()
              : Column(children: [
                  const _SummaryHeader(),
                  _TransactionsListHeader(sortAscending: _sortAscending, onToggleSort: ...),
                  SizedBox(height: Spacing.space8),
                  Expanded(child: ListView.separated(...)),
                ]),
),
```

becomes:

```dart
Expanded(
  child: state.error != null
      ? _ErrorState(message: state.error!)
      : Column(children: [
          const _SummaryHeader(),
          _TransactionsListHeader(
            sortAscending: _sortAscending,
            onToggleSort: () => setState(() => _sortAscending = !_sortAscending),
          ),
          const SizedBox(height: Spacing.space8),
          Expanded(
            child: state.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : filtered.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: EdgeInsets.only(
                          left: Spacing.pagePadding,
                          right: Spacing.pagePadding,
                          bottom: MediaQuery.of(context).padding.bottom +
                              Spacing.space16,
                        ),
                        itemCount: sortedEntries.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: Spacing.space12),
                        itemBuilder: (context, index) {
                          final entry = sortedEntries[index];
                          return _TransactionCard(
                            entry: entry,
                            onTap: () => showFinancialEntryDetailsSheet(
                                context, ref, entry),
                          );
                        },
                      ),
          ),
        ]),
),
```

**Behavior in each state:**
- **Error** — full-screen `_ErrorState` as today. Header hidden. Rationale: an error means the initial fetch failed; `state.allEntries` is `[]`, `selectedYear` defaults to `DateTime.now().year`, and rendering the header would show `$0.00 / N • 0 transactions` — misleading. User's action is "retry" not "browse years"; keep the branch as-is.
- **Loading** — header + list-header render on top; spinner centers in the content area below. During the (brief, sub-second on cached band data) initial load, the header shows `$0.00 / <currentYear> • 0 transactions`. This is a mild visual transient but not misleading — the user immediately sees the picker and can start interacting; the numbers update in one paint when `_load` completes. Matches Manager's directive "regardless of loading/empty state."
- **Empty (filtered.isEmpty on completed load)** — header + list-header render on top; `_EmptyState` centers in the smaller content area below. Header shows `$0.00 / <selectedYear> • 0 transactions`, dropdown lists every year in `state.allEntries` plus the current year. **Year picker is reachable.** User taps it, picks a year with data, list re-renders. This is the fix.
- **Non-empty** — same as Cycle 4 today.

`_TransactionsListHeader` renders unconditionally (whenever the header renders). Manager was explicit: "only the *list content area itself* swaps between the `_EmptyState`'s message and the `ListView` of cards." A sort toggle over an empty list is inert but not confusing (label reads "Newest first ▾"; tap does nothing meaningful but doesn't crash). Alternative rejected: hiding `_TransactionsListHeader` when empty would introduce conditional-render layout shifts as the user flips year selections, and require an extra `if (filtered.isNotEmpty)` branch — worse than the mild noise of always rendering it.

`_EmptyState` widget code stays byte-identical — just renders inside a smaller `Expanded` area (below the header). Its `Center` + `Column(mainAxisAlignment: center)` self-centers in whatever vertical space it's given.

### (b) Inline `AppDropdown<int>` for the year picker

Inside `_SummaryHeader.build`, replace the current single `Text` widget:

```dart
Text(
  '${state.selectedYear} • ${count == 1 ? '1 transaction' : '$count transactions'}',
  textAlign: TextAlign.center,
  style: AppTextStyles.footnote.copyWith(color: context.colors.textMuted),
),
```

with a `Row` containing an inline `AppDropdown<int>` followed by the `" • N transactions"` text:

```dart
Row(
  mainAxisSize: MainAxisSize.min,
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    IntrinsicWidth(
      child: AppDropdown<int>(
        value: state.selectedYear,
        onChanged: (year) {
          if (year == null) return;
          ref.read(financialsProvider.notifier).setSelectedYear(year);
        },
        format: (year) => '$year',
        items: _availableYears(state.allEntries)
            .map((y) => DropdownMenuItem<int>(
                  value: y,
                  child: Text('$y'),
                ))
            .toList(),
      ),
    ),
    Text(
      ' • ${count == 1 ? '1 transaction' : '$count transactions'}',
      style: AppTextStyles.footnote.copyWith(color: context.colors.textMuted),
    ),
  ],
),
```

**Sizing decision — why `IntrinsicWidth`:** `AppDropdown` renders `FSelect.rich` which uses `FTextField.defaultBuilder` for field chrome — full-width by default. Without a horizontal constraint the field stretches to the enclosing `Column`'s max width and the trailing `Text` renders far to the right on its own line — the "inline" design collapses. `IntrinsicWidth` sizes the field to its natural content width (the `format(int)` string `"2026"` plus FSelect's internal padding + chevron button), yielding roughly ~90–110 logical pixels. This lets the `Row` fit both the dropdown and the trailing text on one line centered under the total.

**Fallback authorized (do not need to re-consult):** if `IntrinsicWidth` breaks at layout time (some `FTextField` internals assert on `computeIntrinsicWidth`, though the four existing call sites don't exercise this path so we can't verify a priori), replace with `SizedBox(width: 96)`. Hardcoded but predictable, matches the natural width for 4-digit years at the current font size. Engineer picks whichever compiles + renders cleanly; if both work, `IntrinsicWidth` is preferred (self-adjusting if font size changes).

**Field chrome vs. surrounding footnote style — accepted asymmetry:** `AppDropdown` renders with FSelect's default field styling (border, background, ~48px height, primary text color) — visually heavier and taller than the muted footnote text on either side of it. This is an intentional trade-off:
- `AppDropdown` is a *facade wrapper*, deliberately opinionated per `lib/components/ui/README.md` — the whole point of using it is to inherit the project's standard FSelect styling. Overriding that styling per-call-site defeats the wrapper.
- The year picker being visually distinct is correct affordance: it's the only interactive control in the summary block, and users need to see it's tappable.
- The `Row(crossAxisAlignment: CrossAxisAlignment.center)` vertically centers the shorter `" • N transactions"` text against the taller field — visually acceptable.
- If Tony later wants a tighter/inline styling, that requires either a new Forui theme layer or a compact-mode variant on `AppDropdown` — both out of scope for Cycle 5 and both requiring Manager sign-off before touching the shared wrapper.

**No new dependency, no new wrapper.** `AppDropdown` is already used at 4 direct call sites in `lib/features/*`. The `IntrinsicWidth` constraint is a call-site pattern change, not an API change.

**`onChanged` wiring:** `AppDropdown<int>.onChanged(int?)` fires with the picked int (nullable because FSelect can theoretically clear). Guard the null case (`if (year == null) return;`) — since we don't render a null-value item, this branch is dead in practice, but the null-check keeps the signature contract honest and prevents accidental `setSelectedYear(null!)`-style crashes if Forui's behavior shifts in a future version.

**`format`:** returns `'$year'` — mirrors the existing `_YearSelectorChip` text formatting exactly.

**`_availableYears` helper:** kept at file top level, unchanged. Its single caller moves from `_YearSelector.build` to `_SummaryHeader.build` (reads `state.allEntries` via the existing `ref.watch(financialsProvider)` at the top of `_SummaryHeader.build` — no new provider read needed).

### (c) Delete `_YearSelector`, `_YearSelectorChip`, and their render call

- Delete widget classes `_YearSelector` and `_YearSelectorChip` in full.
- Delete the render call `const _YearSelector()` and its immediately-preceding `SizedBox(height: Spacing.space12)` and following `SizedBox(height: Spacing.space16)` from `_FinancialsScreenState.build`.
- The `_ViewModeToggle` render row directly precedes the `Expanded(...)` content area now — the section between them is empty. Add a single `SizedBox(height: Spacing.space16)` to preserve visual spacing between the toggle and the content column below (matches the current spacing budget between mode toggle and content — one gap, not two).
- Audit imports: `Icons.arrow_drop_down` was only used in `_YearSelectorChip`. Once that widget is deleted, `Icons` (from `package:flutter/material.dart`) may still be referenced by other Material widgets in the file (`MaterialPageRoute`, `CircularProgressIndicator`, etc. — verified by reading the file). `package:flutter/material.dart` stays as an import. No import removal expected.

## Cycle 5 Database Impact
not applicable — no schema change, no new RPC, no RLS change, no migration. Pure widget-tree edit.

## Cycle 5 Flutter Architecture Changes

- **No state-shape change.** `FinancialsState` unchanged; `selectedYear` field and `setSelectedYear(int)` method (both Cycle 4 additions) are reused as-is.
- **No new provider, controller, repository, or model.**
- **No change to `FinancialEntry`, `FinancialEntryRepository`, `FinancialsNotifier`, or `FinancialsPdfPreviewScreen`.**
- **New import in `financials_screen.dart`:** `import '../../components/ui/app_dropdown.dart';` — matches the existing wrapper convention. Confirmed not already present by grep (`app_dropdown` matches zero times in `lib/features/financials/financials_screen.dart` today; two matches in the two sibling `widgets/` files).
- **Deleted widgets:** `_YearSelector`, `_YearSelectorChip`. Both private; no external references.
- **New call-site pattern for `AppDropdown`:** `IntrinsicWidth`-wrapped inline usage. First occurrence in the codebase; not a wrapper API change.
- **`_availableYears`** helper stays at file top level, unchanged.

## Cycle 5 Files to Create

None. Test edits land in existing files; test-file deletion is via `git rm`, not a new file.

## Cycle 5 Files to Modify

### [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart)
- **Add** `import '../../components/ui/app_dropdown.dart';` at the top with the other feature imports (alphabetized among relative imports).
- **Restructure** `_FinancialsScreenState.build` per **Proposed Solution → (a)**: hoist `_SummaryHeader` and `_TransactionsListHeader` above the loading/empty conditional. Only the `Expanded(child: ...)` list-content area swaps between spinner / `_EmptyState` / `ListView.separated`.
- **Delete** the `const SizedBox(height: Spacing.space12)` + `const _YearSelector()` + `const SizedBox(height: Spacing.space16)` sequence in the outer `Column` (currently between `_ViewModeToggle` and the `Expanded(...)` content area). Replace with a single `const SizedBox(height: Spacing.space16)` to preserve toggle→content spacing.
- **Delete** the `_YearSelector` class (currently ~19 lines).
- **Delete** the `_YearSelectorChip` class (currently ~34 lines).
- **Keep** the `_availableYears` top-level helper (7 lines). Its single caller becomes `_SummaryHeader.build`.
- **Rewrite** the single-`Text` "YYYY • N transactions" line inside `_SummaryHeader.build` as `Row(mainAxisSize: min, mainAxisAlignment: center, crossAxisAlignment: center, [IntrinsicWidth(AppDropdown<int>), Text(' • N transactions')])` per **Proposed Solution → (b)**.
- **Preserve verbatim** everything else in `_SummaryHeader`: the `TOTAL <MODE>` label, total dollar formatting, the two `_InlineLinkButton`s for View Savings Balance / Generate Report.
- **Preserve verbatim** `_TransactionsListHeader`, `_TransactionCard`, `_InlineLinkButton`, `_ViewModeToggle`, `_SavingsSheet`, `_openCombinedReport`, `_EmptyState`, `_ErrorState`, `_addEntry`.

### [test/features/financials/widgets/summary_header_test.dart](test/features/financials/widgets/summary_header_test.dart)
- **Update** the three existing test cases that assert the merged single-string form (`'displays the current calendar year by default'`, `'displays the selected year when setSelectedYear sets a non-current year'`, `'merges year and count into a single line separated by " • "'`, `'count phrasing is singular for one entry, plural for multiple entries'`). The merged `find.text('${year} • 3 transactions')` finder will no longer match because the year is now inside an `AppDropdown`'s `FSelect` widget, not the surrounding `Text`. Replace with two-part assertions:
  - `find.text(' • 3 transactions')` (or `' • 1 transaction'`) — the trailing text widget.
  - `find.byWidgetPredicate((w) => w is AppDropdown<int> && w.value == year)` — the dropdown carrying the year value. Import `package:bandroadie/components/ui/app_dropdown.dart` in the test file.
- **Add** new test cases (5 total, mirroring what `year_selector_test.dart` currently covers, plus the empty-state fix):
  1. `'inline AppDropdown<int> is present with current selectedYear as its value'` — pump default state, assert `find.byWidgetPredicate((w) => w is AppDropdown<int> && w.value == DateTime.now().year)` finds one widget.
  2. `'inline AppDropdown<int> items reflect the derived year list (allEntries years ∪ currentYear, descending)'` — pump state with entries spanning `[2023, 2025, currentYear, currentYear+1]`, assert the `AppDropdown<int>.items!.map((i) => i.value).toList()` equals `[currentYear+1, currentYear, 2025, 2023]`.
  3. `'selecting a different year via AppDropdown.onChanged dispatches setSelectedYear on the notifier'` — pump state with a previous-year entry; capture `container.read(financialsProvider).selectedYear` (initially current year); locate the `AppDropdown<int>` widget, invoke its `onChanged(previousYear)` directly; `pumpAndSettle`; assert `container.read(financialsProvider).selectedYear == previousYear`. **Direct `onChanged` invocation is preferred over `tester.tap` + menu-item tap** because opening an `FSelect.rich` popup and tapping an internal `FSelectItem` requires reaching into Forui's internal widget tree, which is brittle and version-fragile; the widget-level assertion (the `onChanged` callback is wired to the notifier method) is the correct behavioral test.
  4. `'zero entries → AppDropdown items contain exactly one entry (the current year) and the widget builds without crashing'` — pump `FinancialsState()` (zero entries), assert `AppDropdown<int>.items!.length == 1`, assert `items!.first.value == DateTime.now().year`, assert `tester.takeException() == null`.
  5. **The core fix test: `'inline year picker remains visible and its onChanged callback is wired when filteredEntries is empty for the selectedYear'`** — pump `FinancialsState(allEntries: [entry in year X-1], selectedYear: X)` where X is the current year (so `filteredEntries` for X is empty). Assert:
     - The `_EmptyState` widget is rendered (`find.text('No entries yet')` finds one widget).
     - The `_SummaryHeader` is still rendered above it (`find.text('TOTAL INCOME')` finds one widget — or `TOTAL EXPENSES` under `viewMode.expenses`).
     - The `AppDropdown<int>` is present (`find.byType(AppDropdown<int>)` finds one widget).
     - The dropdown's `items!` still contains both `X` (current) and `X-1` (year with data), so the user can pick `X-1` to escape the empty state.
     - Invoking `AppDropdown<int>.onChanged(X-1)` directly, then `pumpAndSettle`, changes `container.read(financialsProvider).selectedYear` to `X-1`.
     - After the year switch, `_EmptyState` is gone and the `_TransactionCard` for the entry is rendered.

- Existing `'total for two income entries…'`, `'label reads TOTAL INCOME / TOTAL EXPENSES'`, `'View Savings Balance and Generate Report links chevron'` cases are **untouched** — they don't assert on the merged year-count line.

### [test/features/financials/widgets/year_selector_test.dart](test/features/financials/widgets/year_selector_test.dart)
- **Delete this file.** The widget it targets (`_YearSelector`, `_YearSelectorChip`, and their `PopupMenuButton<int>` machinery) is removed in Cycle 5. The equivalent test coverage moves into `summary_header_test.dart` as the five new cases enumerated above. Removal is via `git rm` (Engineer) — do not leave an empty file or a stub.

### [test/features/financials/widgets/transaction_card_test.dart](test/features/financials/widgets/transaction_card_test.dart) and [test/features/financials/widgets/transactions_list_header_test.dart](test/features/financials/widgets/transactions_list_header_test.dart)
- **No change.** These files were updated in Cycle 4 Task 7 (year-relative fixtures) and continue to pass under Cycle 5's widget tree — they read `allEntries` and `viewMode` off `FinancialsState`, both unchanged.

### [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart)
- **No change.** `selectedYear` and `setSelectedYear` (Cycle 4 additions) are consumed by Cycle 5; nothing needs to be added or renamed. **Confirmed:** the Manager's implicit expectation — "no controller/state change is needed since `selectedYear`/`setSelectedYear` already exist" — holds. Verified by reading the current controller and matching against the Cycle 5 widget code.

### [lib/features/financials/financials_pdf_preview_screen.dart](lib/features/financials/financials_pdf_preview_screen.dart)
- **No change.** Constructor and label logic are Cycle 4's; unchanged by Cycle 5.

## Cycle 5 Files Off-Limits

- [lib/features/financials/financial_entry_repository.dart](lib/features/financials/financial_entry_repository.dart) — no query changes.
- [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart) — model unchanged.
- [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart) — no state or notifier change beyond Cycle 4's additions.
- [lib/features/financials/financials_pdf_preview_screen.dart](lib/features/financials/financials_pdf_preview_screen.dart) — unchanged.
- [lib/features/financials/financials_report_builder.dart](lib/features/financials/financials_report_builder.dart) — unchanged.
- [lib/features/financials/widgets/**](lib/features/financials/widgets/) — every file in this folder (bottom sheets, details sheet, etc.) unchanged.
- [lib/components/ui/app_dropdown.dart](lib/components/ui/app_dropdown.dart) — **do not modify the wrapper.** Cycle 5 uses it as-is; adding a "compact" mode or styling knob to the wrapper is a separate concern requiring Manager sign-off. If `IntrinsicWidth` doesn't produce acceptable sizing, use `SizedBox(width: 96)` at the call site — do not touch the wrapper.
- [lib/components/ui/README.md](lib/components/ui/README.md) — no doc update required; the wrapper's API is unchanged.
- All `supabase/migrations/**` — no DB change.
- `pubspec.yaml` — no new dependency.
- Anything outside `lib/features/financials/`, `lib/components/ui/` (read-only), and the test files listed above.

## Cycle 5 Change Budget

Numbers are net line delta *per file* after Engineer implements the Task Breakdown; QA diffs against these.

| File | Expected net Δ lines | Rationale |
| --- | --- | --- |
| `lib/features/financials/financials_screen.dart` | **−40 to +5** | Delete `_YearSelector` (~19 lines), `_YearSelectorChip` (~34 lines), and the render-call block (`SizedBox` + `_YearSelector()` + `SizedBox` → single `SizedBox`, net ~−3 lines). Add `import app_dropdown.dart` (+1 line). Add `Row` + `IntrinsicWidth` + `AppDropdown<int>` in `_SummaryHeader` (~20 lines) replacing the single-line `Text` (~5 lines) — net ~+15 lines inside the header. Restructure build's `Expanded(child: ...)` (net ~+5 lines from nesting `Expanded` deeper + splitting the conditional). Net range accounts for whether the `AppDropdown` items list is expanded across multiple lines or inline. |
| `test/features/financials/widgets/summary_header_test.dart` | **+90 to +180** | Adjust 3 existing cases from single-string to two-part assertions (~+10 lines). Add 5 new cases (~+90 to +170 lines depending on fixture verbosity). |
| `test/features/financials/widgets/year_selector_test.dart` | **DELETED** | Full-file removal (~180 lines removed). Not counted against per-file delta budget since the file is gone. |
| `test/features/financials/widgets/transaction_card_test.dart` | **0** | Untouched. |
| `test/features/financials/widgets/transactions_list_header_test.dart` | **0** | Untouched. |
| Any other file | **0** | Off-limits. |

- Expected new files: **0**.
- Expected deleted files: **1** (`year_selector_test.dart`).
- Expected new public classes / methods on production code: **0**.
- Expected new dependencies (pubspec.yaml): **0**.
- Expected migration files: **0**.

## Cycle 5 System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Financials → Screen | changed (in-scope) | Year picker moves from standalone row into inline summary-line control; empty-state layout restructured so header stays reachable. |
| Financials → Controller | unaffected | State shape and mutation methods unchanged from Cycle 4. |
| Financials → PDF Report Screen | unaffected | Unchanged from Cycle 4. |
| Financials → PDF Report Builder | unaffected | Unchanged. |
| Financials → Add / Edit Sheet | unaffected | Unchanged. |
| Financials → Details Sheet | unaffected | Unchanged. |
| Financials → Savings Sheet | unaffected | Reads `state.allEntries` (unfiltered). |
| Gigs / Rehearsals / Setlists / Members | unaffected | No cross-references. |
| Auth / Routing / Notifications | unaffected | No init-order change, no session change. |
| Platforms (iOS / Android / macOS / Web) | uniformly affected | Shared Flutter UI only; `FSelect.rich` popup renders natively on all four (verified via Forui docs and existing 4-call-site coverage). No platform-conditional code. |
| Supabase schema / RLS / RPCs | unaffected | Client-only change. |
| Forui integration / `AppDropdown` wrapper | consumed, not modified | Cycle 5 adds a new call-site pattern for `AppDropdown` (inline via `IntrinsicWidth`); the wrapper itself is not modified. |
| `lib/components/ui/README.md` | unaffected (doc) | Doc's `AppDropdown` line says "10 call sites: 6 via EventDropdown, 4 direct" — Cycle 5 adds one direct call site (5 direct, 11 total). Doc string is not strictly wrong (still "10 call sites" was accurate at write time); optional to update. Left unchanged in Cycle 5 to keep the diff minimal. |
| pubspec.yaml | unaffected | No new dependency. |

## Cycle 5 Regression Risk
**LOW**. Justification:

- No touch to auth, session, routing, init order, DB, RLS, RPCs, or platform-conditional code.
- No state-shape change (`FinancialsState`, `FinancialsNotifier`, `FinancialEntry`, `FinancialEntryRepository` byte-identical to Cycle 4).
- No provider added or removed.
- No new dependency, no new migration, no schema change.
- Change is scoped to one production source file (`financials_screen.dart`) plus two test files (one edited, one deleted).
- The `AppDropdown` wrapper is used at 4 direct sites elsewhere in `lib/features/*` — behavior is well-exercised in production. Cycle 5 introduces only a new *call-site constraint* (`IntrinsicWidth`), not a wrapper edit.

**Realistic regression classes:**

1. **`IntrinsicWidth` incompatible with `FSelect.rich` internals.** Some `FTextField`-derived widgets throw on `computeIntrinsicWidth` calls if they rely on unbounded parent constraints. **Mitigated:** authorized fallback to `SizedBox(width: 96)` at the same call site — Engineer trials `IntrinsicWidth` first, swaps to `SizedBox` if layout throws. Both approaches are pre-approved by this plan; QA doesn't need to re-consult which one landed.
2. **`_EmptyState` visually cramped under the summary header.** With the header + list-header + spacing consuming the top ~200px of the content column, `_EmptyState` renders in the remaining vertical space. On short screens (iPhone SE, ~570px content height) the icon + two text lines may sit tight against the bottom safe area. **Mitigated:** owner-run punch list explicitly walks this on iPhone SE + narrow web widths. If cramped, Engineer can trim `_EmptyState`'s `Icon(size: 48)` to `size: 32` — but this is a fallback, not the default; try the current widget first.
3. **Load-state flash of `$0.00 / 0 transactions`.** Between initial screen entry and `_load` completion, the header briefly shows zero values. **Accepted** per Manager's directive that the header renders "regardless of loading/empty state." Duration is sub-second on cached band data; not a defect.

## Cycle 5 Engineer Task Breakdown

Ordered, atomic. Each task leaves the app compiling. **Do not merge tasks or invent extra sub-steps.**

1. **Rewrite the summary line in `_SummaryHeader.build`.**
   - Inside `financials_screen.dart`, add `import '../../components/ui/app_dropdown.dart';` alongside the other relative imports.
   - Replace the current `Text('${state.selectedYear} • ...')` widget with the `Row(...)` structure from **Proposed Solution → (b)**.
   - Wire `AppDropdown<int>.onChanged` to `ref.read(financialsProvider.notifier).setSelectedYear(year)` with a null-guard.
   - Wrap the `AppDropdown` in `IntrinsicWidth`. If layout throws at test/analyze time, swap to `SizedBox(width: 96)` — both authorized.
   - This task leaves `_YearSelector` and `_YearSelectorChip` still defined and still rendered above the entries list; the app now shows *two* year controls (temporarily). This is expected and cleaned up in Task 3.

2. **Restructure `_FinancialsScreenState.build` so the header always renders.**
   - Rewrite the outer `Expanded(child: state.isLoading ? ... : state.error != null ? ... : filtered.isEmpty ? ... : Column([_SummaryHeader, ...]))` per **Proposed Solution → (a)**.
   - Result: `state.error != null → _ErrorState`; else → `Column([_SummaryHeader, _TransactionsListHeader, SizedBox, Expanded(state.isLoading ? spinner : filtered.isEmpty ? _EmptyState : ListView.separated)])`.
   - Preserve `ListView.separated`'s existing `padding`, `itemCount`, `separatorBuilder`, `itemBuilder` verbatim — including the `showFinancialEntryDetailsSheet(context, ref, entry)` `onTap` wiring on `_TransactionCard`.
   - After this task, the empty-state trap is fixed: year picker (still inline in `_SummaryHeader`) remains reachable when `filtered.isEmpty`.

3. **Delete `_YearSelector`, `_YearSelectorChip`, and the standalone render call.**
   - Delete the `_YearSelector` class in full.
   - Delete the `_YearSelectorChip` class in full.
   - Delete the `SizedBox(height: Spacing.space12)` + `const _YearSelector()` + `SizedBox(height: Spacing.space16)` block in `_FinancialsScreenState.build`'s outer `Column`. Replace with a single `const SizedBox(height: Spacing.space16)` between `_ViewModeToggle` and the `Expanded(...)` content area.
   - Keep the `_availableYears` top-level helper unchanged — it's now called from `_SummaryHeader.build` only.
   - `flutter analyze` should now show no dangling references.

4. **Update `summary_header_test.dart`.**
   - Adjust the four existing test cases that assert `find.text('$year • N transactions')`. Rewrite as split assertions: `find.text(' • N transactions')` + `find.byWidgetPredicate((w) => w is AppDropdown<int> && w.value == year)`.
   - Add the five new test cases enumerated in **Files to Modify → summary_header_test.dart**.
   - Add `import 'package:bandroadie/components/ui/app_dropdown.dart';` at the test file's imports.
   - The "core fix" case (case 5 in the list) is the primary QA gate for the empty-state fix — it must be present, must assert `_EmptyState` is rendered simultaneously with the `AppDropdown` being visible + interactive, and must verify the `onChanged` callback still dispatches `setSelectedYear` when the current filter is empty.

5. **Delete `year_selector_test.dart`.**
   - `git rm test/features/financials/widgets/year_selector_test.dart` (Engineer runs this in the terminal, not by leaving an empty file).
   - After this task, the file is fully gone from the tree.

## Cycle 5 Verification Plan

### Cycle 5 Tier 1 — pre-deploy (QA gate, mechanically executable)

QA gate for APPROVED requires all of the following without running the app:

1. `flutter analyze` clean (no new lints; existing baseline preserved).
2. `flutter test` passes, including the updated `summary_header_test.dart` (with the 5 new cases) and the untouched `transaction_card_test.dart` / `transactions_list_header_test.dart`. `year_selector_test.dart` must no longer exist (verify via `git ls-files | grep year_selector_test` returns empty).
3. Diff review confirms these files are byte-identical to `main` (or, where applicable, byte-identical to their Cycle 4 shape on the working tree at plan-write time):
   - `lib/features/financials/financial_entry_repository.dart` — vs. `main`
   - `lib/features/financials/models/financial_entry.dart` — vs. `main`
   - `lib/features/financials/financials_controller.dart` — vs. Cycle 4 tree (Cycle 4 changed this file; Cycle 5 does not)
   - `lib/features/financials/financials_pdf_preview_screen.dart` — vs. Cycle 4 tree
   - `lib/features/financials/financials_report_builder.dart` — vs. `main`
   - `lib/features/financials/widgets/**` — every file, vs. its state on the Cycle 4 tree (Cycle 4 didn't touch these for the most part; details sheet was touched in Cycles 1–3)
   - `lib/components/ui/app_dropdown.dart` — vs. `main` (Cycle 5 must not modify the wrapper)
   - `lib/components/ui/README.md` — vs. `main`
   - All `supabase/migrations/**` files — vs. `main`
   - `pubspec.yaml` — vs. `main`
4. Diff review confirms net line delta per modified file falls inside **Cycle 5 Change Budget** ranges.
5. Diff review confirms `_YearSelector`, `_YearSelectorChip`, and the render-call block are absent from `financials_screen.dart`; `AppDropdown<int>` and the `IntrinsicWidth` wrapper (or `SizedBox(width: 96)` fallback) are present inside `_SummaryHeader`; and the `_availableYears` top-level helper is retained.
6. Diff review confirms `_FinancialsScreenState.build` no longer wraps `_SummaryHeader` inside the `filtered.isEmpty` conditional — the header renders at the same level regardless of empty/non-empty content (except in the error branch).
7. Diff review confirms `import '../../components/ui/app_dropdown.dart';` is added to `financials_screen.dart` and no other new import creeps in (no `import 'package:forui/forui.dart';` directly, no new `package:collection` etc.).
8. Diff review confirms the "core fix" widget test (case 5 in the summary_header_test list) is present, is named to reflect the empty-state scenario, and mechanically exercises: (a) empty state rendering, (b) `AppDropdown` visibility, (c) `onChanged` dispatch under the empty state, (d) recovery from empty state after year switch.

### Cycle 5 Tier 2 — post-deploy
not applicable — no DB migration, no RPC change, no RLS change, no edge function change, no external API change.

### Cycle 5 Owner-run punch list (Tony runs at PR-test time — QA writes this into the PR body verbatim, does not attempt it)

QA cannot run the app. Tony walks the following (adds to the existing Cycles 1–4 punch lists, does not replace them):

1. Sign in with a demo band containing entries in the current calendar year; open Financials.
   Expected: single control layout above the entries list — the year is a dropdown embedded inline in the summary line, no standalone chip row above. Summary line reads `[YYYY ▾] • N transactions` centered under the total.
2. Tap the year in the summary line.
   Expected: Forui `FSelect.rich` popup opens (styled like a standard form-field dropdown, not a `PopupMenu` sheet). Lists the current year plus every distinct year the band has entries in, in descending order.
3. Select a year with data.
   Expected: dropdown closes; year label updates; count and total update; list re-renders. Two paints max.
4. Sign in with (or switch to) a band whose data is entirely in a **prior** year (or manually set `selectedYear` to a year with no entries via the picker, then leave and re-enter — remember the picker resets to `DateTime.now().year` on re-entry).
   **The core fix scenario.** Expected: summary header renders on top with the year dropdown (showing `<currentYear>`), total ($0.00), count (0), and both link buttons. Below the header, the `_EmptyState` renders (`No entries yet` + subtitle). Tap the year dropdown → popup shows the current year plus the prior year(s) with data. Select a prior year with data → list populates, empty state disappears. **This step must pass end-to-end without leaving/re-entering the screen — that's the whole fix.**
5. Toggle Income ↔ Expenses while a non-current year is selected.
   Expected: year selection persists; count and total update per mode; dropdown remains inline in the summary line.
6. Tap "Generate Report" from the summary line while a non-current year is selected.
   Expected: PDF preview opens with header/filename reading `"Year YYYY"` for the selected year (unchanged from Cycle 4).
7. Tap "View Savings Balance."
   Expected: savings sheet opens with the same animated total behavior as today; year selection does not affect savings totals (they read `state.allEntries`).
8. Sort toggle: tap `"Newest first ▾"` in the transactions list header while entries are present.
   Expected: label flips, list reverses. Unchanged from Cycle 1.
9. With an empty filtered list (year has zero entries), verify the sort toggle in `_TransactionsListHeader` is visible but inert — tapping it doesn't crash, doesn't change label (there's nothing to sort). This is expected minor visual noise and not a defect.
10. Cross-platform visual check on iOS, Android, macOS, and web:
    - The inline year dropdown is sized appropriately (not stretched full-width, not clipped by field padding), and the `" • N transactions"` text sits next to it on the same line at all common widths (iPhone SE / narrow web / iPad / macOS full-window).
    - The FSelect popup opens correctly on each platform (not clipped by the safe area, not offset from the field).
    - `_EmptyState` centers correctly under the summary header on tall and short screens (no overflow, no clipping against the bottom safe area).
11. Verify (visual, subjective): the inline dropdown's field chrome (border, background) is acceptable next to the muted footnote text of `" • N transactions"`. If the visual weight feels wrong, note it in the PR — a future cycle can tune Forui theme or add a compact-mode wrapper. This cycle intentionally accepts the standard `FSelect` chrome.

## Cycle 5 QA Regression Areas

1. **Empty-state reachability** — the specific fix. Regression check: any change to `_FinancialsScreenState.build` that reintroduces `_SummaryHeader` inside the `filtered.isEmpty` conditional is a critical regression, because it re-creates the year-picker trap. QA punches this via test case 5 in the new `summary_header_test.dart` set.
2. **`AppDropdown` inline sizing** — regression check: `AppDropdown<int>` inside `_SummaryHeader` must be constrained by either `IntrinsicWidth` or `SizedBox`; if neither is present, the field stretches to column width and breaks the inline layout. QA verifies via diff review (Tier 1 gate #5) that one of the two wrappers surrounds the `AppDropdown`.
3. **Wrapper immutability** — `lib/components/ui/app_dropdown.dart` must be byte-identical to `main`. Cycle 5 changes only the *call site*, never the wrapper. QA punches this via Tier 1 gate #3.
4. **No raw `FSelect` usage** — regression check: `import 'package:forui/forui.dart';` must not appear in `financials_screen.dart` (or any feature file changed by Cycle 5). All Forui access goes through `AppDropdown`. QA verifies via grep in the diff.
5. **PDF report** — unchanged from Cycle 4. Filename/header still reads `"Year YYYY"`; row order still comes from `dateFilteredEntries` (not affected by the on-screen sort toggle).
6. **Sort toggle** — unchanged from Cycle 1. Tapping still reverses the list order for the current year filter.
7. **`_SavingsSheet`** — unchanged from Cycles 1–4. Reads `state.allEntries` (year-agnostic); totals unaffected by year selection.
8. **Details sheet** — unchanged from Cycles 1–3. Icons removed from `_DetailRow`, `"Paid by"` / `"Notes"` / `"Related to gig"` labels present, `"Reimbursed: Yes/No"` row on expenses, footer button reads `"Edit"`.
9. **Loading-state flash** — accept `$0.00 / 0 transactions` briefly visible during initial load. Not a defect. If load duration exceeds 1s consistently, that's a separate concern (backend perf) and not addressed here.

## Cycle 5 Rollout Strategy

Same PR as Cycles 1–4 (#273). Commits added on top of the Cycle 4 tree. No feature flag, no phased rollout, no DB migration. Merge to `main` when Cycle 5 clears the QA gate + owner-run punch list. Rollback = revert the PR; no data changes to unwind.

## Cycle 5 Out of Scope

- Any change to `AppDropdown` itself (adding a compact mode, dense variant, styling override, or new constructor). If `IntrinsicWidth`/`SizedBox` are both unacceptable, that's a separate cycle touching `lib/components/ui/app_dropdown.dart` under Manager review.
- Any change to the Forui theme layer (e.g., customizing `FTextField.defaultBuilder`, tightening field padding, reducing default height). Also a separate cycle.
- Changing `_EmptyState` copy or icon — Cycle 4 out-of-scope decision holds. If the empty-state message should acknowledge the year filter ("No entries for {year}"), that's a follow-up cycle.
- Adding an "All years" option to the dropdown. Same Cycle 4 out-of-scope decision.
- Persisting `selectedYear` across screen dismiss / band switch / app restart. Not asked for; matches the Cycle 1 / Cycle 4 stance on transient filter state.
- Any change to the sort toggle, transaction card, details sheet, savings sheet, `_ViewModeToggle`, `_ErrorState`, `_openCombinedReport`, or `_addEntry`.
- Any change to `FinancialEntry`, `FinancialEntryRepository`, `FinancialsState`, `FinancialsNotifier`, `FinancialsPdfPreviewScreen`, `financials_report_builder.dart`, gig data flow, RLS, migrations, or pubspec dependencies.
- Updating `lib/components/ui/README.md`'s "10 call sites" count to "11 direct + 6 via EventDropdown". The doc string is factual at write-time; Cycle 5 not obligated to touch documentation for a call-site addition, and the doc-file change is off-limits.

---

# Cycle 6 Scope Expansion

Cycle 6 is a design-reversal revision landing on top of Cycles 1–4 (and superseding the never-implemented Cycle 5 in the parts noted at the top of Cycle 5), on the same branch (`feature/financials-transaction-cards`), before PR #273 merges. Cycles 1–4 remain uncommitted on the working tree; Cycle 4 is QA-APPROVED (uncommitted). Cycle 5 was never implemented — its Task 1 diff never landed. **Cycle 6 lands directly on the Cycle 4 tree**, executing (a) the parts of Cycle 5 that survive (inline dropdown placement + empty-state build restructuring + widget deletions) and (b) the Cycle 6 state-shape swap, in one coherent revision.

Branch state at plan-write time: local `feature/financials-transaction-cards` at commit `8dac09a`; `GIT_OPTIONAL_LOCKS=0 git merge-base main HEAD` == `06bd222` == current `main` HEAD — **base is clean, no rebase needed**. Working tree has Cycles 1–4 modifications uncommitted across `lib/features/financials/**` and `test/features/financials/widgets/**`, plus the never-committed `test/features/financials/widgets/year_selector_test.dart` from Cycle 4. Cycle 6 is architected against that working tree (Cycle 4 tree), not against `main`.

## Cycle 6 Problem Summary

Tony reviewed Cycle 4 (year-select dropdown) after Manager staged the Cycle 5 redesign of it, and asked for a third revision to the date-filter control:

> "The 2026 dropdown would always have a selection. The default selection is 2026 (current year). Tapping the select component will reveal the select menu with the options 'All time', 'This year', This month. Change 2026 to 'This year' and use this component."

Concrete asks (this is the current authoritative interpretation, superseding Cycle 4/5 wherever they conflict):

1. **Reintroduce a three-value filter enum** — `{ allTime, thisYear, thisMonth }`. No `custom` case (Tony did not ask for arbitrary date ranges to come back, so the pre-Cycle-4 `custom` enum value and the `showDateRangePicker` code path stay deleted).
2. **Default filter is `thisYear`** — matches Cycle 4's "default to current year" intent, now expressed via the `thisYear` semantic rather than a scalar year.
3. **Dropdown always has a non-null selection** — the underlying state field is non-nullable and defaults to `thisYear`; the dropdown widget therefore never renders in an "unselected" state.
4. **`thisYear` renders textually, not as a numeral** — the collapsed dropdown label reads `'This year'`, not `'2026'`. This is a direct reversal of Cycle 4's "always show the numeral for `thisYear`" behavior. `'All time'` and `'This month'` were already textual, so no reversal is needed for the other two.
5. **The dropdown lives inline in `_SummaryHeader`** — same placement Cycle 5 spec'd (leading token of the ` • N transactions` line, `IntrinsicWidth`-wrapped `AppDropdown` inside a `Row`). Cycle 6 does not change that placement; only the type parameter and item list change.
6. **The Cycle 5 empty-state accessibility fix survives** — the header (with the dropdown) must remain visible and tappable when `filteredEntries` is empty for the current selection, so the user can escape a `thisYear`-with-no-current-year-data state by picking `allTime` or `thisMonth` without leaving the screen.

Cycle 4's "dynamic year-list derived from `state.allEntries`" mechanic and Cycle 5's `_availableYears` helper retention are both dropped — the item list is now a fixed 3-value enum literal, not a data-derived list.

## Cycle 6 Root Cause

n/a — UI/UX design reversal in response to Tony's testing feedback on Cycle 4 (before Cycle 4 shipped). Confidence `HIGH` on the mechanical scope: every referenced field, method, widget, PDF call site, and test assertion has been verified by reading the files on the current working tree at plan-write time.

## Cycle 6 Existing System Analysis (Cycle 4 tree — Cycle 5 unrealized)

Current state of the working tree, verified by reading the files:

- **`FinancialsState`** ([financials_controller.dart lines 17–67](lib/features/financials/financials_controller.dart#L17-L67)) — as introduced by Cycle 4. Holds `viewMode`, `selectedYear: int`. Constructor takes `int? selectedYear` and initialises via `selectedYear = selectedYear ?? DateTime.now().year` (nullable-in-constructor-for-runtime-default pattern). `copyWith` has `int? selectedYear`. `_applyDateFilter` is a single-line `.where((e) => e.entryDate.year == selectedYear)`. `filteredEntries` and `dateFilteredEntries` unchanged in signature.
- **`FinancialsNotifier.setSelectedYear(int)`** ([financials_controller.dart lines 114–116](lib/features/financials/financials_controller.dart#L114-L116)) — the Cycle 4 mutation method. Only caller: `_YearSelector.build`. Cycle 6 replaces it with `setDateFilter(FinancialDateFilter)`.
- **`_YearSelector`** ([financials_screen.dart lines 469–491](lib/features/financials/financials_screen.dart#L469-L491)) and **`_YearSelectorChip`** ([financials_screen.dart lines 493–526](lib/features/financials/financials_screen.dart#L493-L526)) — Cycle 4's `PopupMenuButton<int>`-based standalone chip row. Rendered from `_FinancialsScreenState.build` at [line 155](lib/features/financials/financials_screen.dart#L155). Cycle 6 deletes both (Cycle 5's spec, re-adopted).
- **`_availableYears`** ([financials_screen.dart lines 459–466](lib/features/financials/financials_screen.dart#L459-L466)) — Cycle 4's data-derived year list. Single caller: `_YearSelector.build`. Cycle 6 deletes the helper entirely (its only consumer goes away, and the new `AppDropdown` uses a static enum list, not data-derived items).
- **`_FinancialsScreenState.build`** ([financials_screen.dart lines 87–221](lib/features/financials/financials_screen.dart#L87-L221)) — Cycle 4 tree, structured as:
  ```
  Column(
    BackOnlyAppBar,
    Expanded(Column(
      PageTitle + Add button,
      SizedBox(space16),
      _ViewModeToggle,
      SizedBox(space12),
      const _YearSelector(),         ← Cycle 4; deleted in Cycle 6
      SizedBox(space16),
      Expanded(
        state.isLoading   → CircularProgressIndicator
        : state.error != null → _ErrorState
        : filtered.isEmpty → _EmptyState                        ← header hidden here
        : Column(                                               ← header only here
            _SummaryHeader,
            _TransactionsListHeader,
            SizedBox(space8),
            Expanded(ListView.separated),
          ),
      ),
    )),
  )
  ```
  Cycle 6 restructures this per Cycle 5's spec: `state.error != null → _ErrorState`; else → `Column([_SummaryHeader, _TransactionsListHeader, SizedBox(space8), Expanded(state.isLoading ? spinner : filtered.isEmpty ? _EmptyState : ListView.separated)])`. Header + list-header always render (in the non-error branch); only the content area swaps.
- **`_SummaryHeader.build`** ([financials_screen.dart lines 700–767](lib/features/financials/financials_screen.dart#L700-L767)) — Cycle 4 tree. Renders `TOTAL <MODE>` label, big total, single-line `Text('${state.selectedYear} • ${count == 1 ? '1 transaction' : '$count transactions'}')`, and the two-link row. Cycle 6 replaces the single `Text` with a `Row(IntrinsicWidth(AppDropdown<FinancialDateFilter>), Text(' • N transactions'))`; every other line inside `_SummaryHeader` is preserved verbatim.
- **`_openCombinedReport`** ([financials_screen.dart lines 618–637](lib/features/financials/financials_screen.dart#L618-L637)) — Cycle 4 tree. Passes `selectedYear: state.selectedYear` to `FinancialsPdfPreviewScreen`. Cycle 6 changes this to `dateFilter: state.dateFilter`.
- **`FinancialsPdfPreviewScreen`** ([financials_pdf_preview_screen.dart lines 23–71](lib/features/financials/financials_pdf_preview_screen.dart#L23-L71)) — Cycle 4 tree. Constructor: `entries`, `bandName`, `int selectedYear`, `viewMode`, `members`. `_filterLabel` returns `'Year ${widget.selectedYear}'`. Cycle 6 swaps `int selectedYear` → `FinancialDateFilter dateFilter` and rewrites `_filterLabel` as a 3-case switch: `allTime → 'All time'`, `thisYear → 'Year ${DateTime.now().year}'` (preserves the PDF filename form for the default case), `thisMonth → DateFormat('MMMM yyyy').format(DateTime.now())` (matches the pre-Cycle-4 `thisMonth` label form). Requires adding `import 'package:intl/intl.dart';` — `intl` is already in pubspec (used by `financials_screen.dart` and other feature files), no dep change.
- **`AppDropdown<T>`** ([lib/components/ui/app_dropdown.dart](lib/components/ui/app_dropdown.dart)) — Cycle 5 analysis holds byte-for-byte on the working tree (Cycle 5 wasn't implemented, so the wrapper is unchanged from `main`). `FSelect.rich` with `FSelectControl.lifted`, requires exactly one of `items` or `children`, `onChanged: ValueChanged<T?>`, `format: String Function(T)?`. Non-null `value` is fine (assertion checks `items`/`children` XOR, not value-nullness).
- **Test files on the working tree:**
  - `test/features/financials/widgets/summary_header_test.dart` — asserts the Cycle 4 merged form `find.text('${DateTime.now().year} • 3 transactions')` in several cases, and `find.textContaining('${DateTime.now().year} • ')` in others. Cycle 6 replaces these with two-part assertions (`AppDropdown<FinancialDateFilter>` + adjacent ` • N transactions` text), plus new cases per Cycle 6 requirements.
  - `test/features/financials/widgets/transaction_card_test.dart` — Cycle 4-updated fixtures default `entryDate` to `DateTime(DateTime.now().year, 1, 15)`. Under Cycle 6's default `dateFilter = thisYear`, these entries still match the filter → fixtures continue to work byte-identical. No test edits.
  - `test/features/financials/widgets/transactions_list_header_test.dart` — same story. Entries dated `DateTime(now.year, 3, ...)` match `thisYear`. No test edits.
  - `test/features/financials/widgets/year_selector_test.dart` — Cycle 4 additive test file, currently untracked (per `git status`). Cycle 5 planned to delete it; Cycle 6 executes that deletion (Engineer runs `git rm test/features/financials/widgets/year_selector_test.dart`, or `rm` since the file is untracked — either produces the same tree state).

**No other files in `lib/` or `test/` reference `selectedYear`, `setSelectedYear`, `_availableYears`, `_YearSelector`, `_YearSelectorChip`, `FinancialDateFilter`, `dateFilter`, or the four pre-Cycle-4 `dateFilter` case names** — confirmed by `grep_search` across `lib/**/*.dart` (20 matches, all in the three files above) and `test/features/financials/**` (30 state-related matches, all in the four files above). No other production code needs to change to accommodate this state-shape swap.

## Cycle 6 Proposed Solution

### (a) State-shape reconciliation — `financials_controller.dart`

Reintroduce the enum, delete `selectedYear`, add `dateFilter`.

```dart
enum FinancialDateFilter { allTime, thisYear, thisMonth }
```

Note two important differences from the pre-Cycle-4 enum shape (do not restore either behavior):

- No `custom` value. Tony did not request arbitrary date ranges to come back; the `showDateRangePicker` code path, the `customStartDate` / `customEndDate` state fields, and the `_pickCustomRange` helper (all deleted in Cycle 4) stay deleted. Any Engineer / QA temptation to add them "for completeness" is a plan violation.
- Default is `thisYear`, not `allTime` (pre-Cycle-4 didn't specify a default clearly; Cycle 6 pins it to `thisYear` per Tony's directive that current-year is the initial view).

Rewritten `FinancialsState`:

```dart
class FinancialsState {
  final List<FinancialEntry> allEntries;
  final bool isLoading;
  final String? error;
  final FinancialViewMode viewMode;
  final FinancialDateFilter dateFilter;

  const FinancialsState({
    this.allEntries = const [],
    this.isLoading = false,
    this.error,
    this.viewMode = FinancialViewMode.income,
    this.dateFilter = FinancialDateFilter.thisYear,
  });

  FinancialsState copyWith({
    List<FinancialEntry>? allEntries,
    bool? isLoading,
    String? error,
    FinancialViewMode? viewMode,
    FinancialDateFilter? dateFilter,
    bool clearError = false,
  }) {
    return FinancialsState(
      allEntries: allEntries ?? this.allEntries,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      viewMode: viewMode ?? this.viewMode,
      dateFilter: dateFilter ?? this.dateFilter,
    );
  }

  // filteredEntries and dateFilteredEntries getters unchanged in signature.

  List<FinancialEntry> _applyDateFilter(Iterable<FinancialEntry> source) {
    final now = DateTime.now();
    Iterable<FinancialEntry> filtered;
    switch (dateFilter) {
      case FinancialDateFilter.allTime:
        filtered = source;
        break;
      case FinancialDateFilter.thisYear:
        filtered = source.where((e) => e.entryDate.year == now.year);
        break;
      case FinancialDateFilter.thisMonth:
        filtered = source.where(
          (e) => e.entryDate.year == now.year && e.entryDate.month == now.month,
        );
        break;
    }
    final entries = filtered.toList();
    entries.sort((a, b) => b.entryDate.compareTo(a.entryDate));
    return entries;
  }
}
```

**Note the constructor becomes `const` again** (Cycle 4's `_defaultSelectedYear()` static helper hack is unneeded — enum values are compile-time constants, so `this.dateFilter = FinancialDateFilter.thisYear` is a valid const default). This restores the pre-Cycle-4 `const FinancialsState({...})` shape; any test that constructed a state via `const FinancialsState()` continues to work.

Rewritten `FinancialsNotifier` mutation surface:

```dart
void setDateFilter(FinancialDateFilter filter) {
  state = state.copyWith(dateFilter: filter);
}
```

Delete `setSelectedYear(int)`. `build`, `_load`, `addEntry`, `updateEntry`, `deleteEntry`, `refresh` — unchanged.

### (b) `AppDropdown<FinancialDateFilter>` wiring in `_SummaryHeader`

Inside `_SummaryHeader.build`, replace the Cycle 4 single-`Text` line:

```dart
Text(
  '${state.selectedYear} • ${count == 1 ? '1 transaction' : '$count transactions'}',
  textAlign: TextAlign.center,
  style: AppTextStyles.footnote.copyWith(color: context.colors.textMuted),
),
```

with:

```dart
Row(
  mainAxisSize: MainAxisSize.min,
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    IntrinsicWidth(
      child: AppDropdown<FinancialDateFilter>(
        value: state.dateFilter,
        onChanged: (filter) {
          if (filter == null) return;
          ref.read(financialsProvider.notifier).setDateFilter(filter);
        },
        format: _dateFilterLabel,
        items: FinancialDateFilter.values
            .map((f) => DropdownMenuItem<FinancialDateFilter>(
                  value: f,
                  child: Text(_dateFilterLabel(f)),
                ))
            .toList(),
      ),
    ),
    Text(
      ' • ${count == 1 ? '1 transaction' : '$count transactions'}',
      style:
          AppTextStyles.footnote.copyWith(color: context.colors.textMuted),
    ),
  ],
),
```

and add a top-level helper at file scope (near where `_availableYears` was, after that helper is deleted):

```dart
String _dateFilterLabel(FinancialDateFilter filter) {
  switch (filter) {
    case FinancialDateFilter.allTime:
      return 'All time';
    case FinancialDateFilter.thisYear:
      return 'This year';
    case FinancialDateFilter.thisMonth:
      return 'This month';
  }
}
```

**Label-mapping rationale.** Tony's exact strings: `'All time'`, `'This year'`, `'This month'`. Sentence-case, single space, no trailing punctuation. `_dateFilterLabel` is the single source of truth for both the collapsed dropdown label (via `format: _dateFilterLabel`) and each menu item's child text (`Text(_dateFilterLabel(f))`). Keeping them wired through the same function prevents label-drift bugs where the collapsed and expanded views could disagree.

**Non-null selection guarantee.** `state.dateFilter` is a non-nullable field with a compile-time-const default of `FinancialDateFilter.thisYear`. The `AppDropdown<FinancialDateFilter>.value` therefore is always a real enum value, never `null`. `AppDropdown` does not assert `value != null` (its only assertion is `items` XOR `children`), so passing a non-null value is compatible; the collapsed field renders `format(value)` and never falls into any "no selection" branch. The `onChanged` null-guard (`if (filter == null) return;`) is defensive against future Forui behavior changes and against a hypothetical "clear" affordance in `FSelect` — dead code in practice, kept for the same rationale Cycle 5 documented.

**`IntrinsicWidth` sizing pattern (Cycle 5 spec, re-adopted).** `AppDropdown` renders `FSelect.rich` which uses `FTextField.defaultBuilder` and stretches to the enclosing width by default. `IntrinsicWidth` sizes the field to its natural content — the widest of the three format strings (`'All time'` at ~8 chars, `'This year'` at ~9 chars, `'This month'` at ~10 chars, plus the built-in chevron button padding). **Authorized fallback (no re-consult needed):** if `IntrinsicWidth` throws at layout/analyze time because `FSelect.rich` internals reject `computeIntrinsicWidth`, replace with `SizedBox(width: 128)` at the same call site. `128` gives comfortable room for `'This month'` at the current footnote font size (versus Cycle 5's `96` which was sized for a 4-digit year); both approaches are pre-approved by this plan. Engineer picks whichever compiles and renders cleanly.

**Field chrome asymmetry (Cycle 5 rationale, re-adopted).** `AppDropdown` renders full FSelect field chrome (border, background, ~48px height, primary text color) next to muted footnote text on either side. This is the intentional trade-off — the wrapper is a facade per `lib/components/ui/README.md`, and the visual distinction correctly signals interactivity. `Row(crossAxisAlignment: CrossAxisAlignment.center)` vertically centers the shorter trailing text against the taller field. If Tony later wants tighter/inline styling, that's a wrapper-level or Forui-theme-level cycle, not this one.

### (c) `FinancialsPdfPreviewScreen` reconciliation

Swap the Cycle 4 `int selectedYear` constructor param back to a filter-type concept, and rewrite `_filterLabel` as a 3-case switch. Do **not** resurrect `customStartDate` / `customEndDate` — `custom` is not part of Cycle 6.

```dart
class FinancialsPdfPreviewScreen extends StatefulWidget {
  final List<FinancialEntry> entries;
  final String bandName;
  final FinancialDateFilter dateFilter;   // was: int selectedYear
  final List<MemberVM> members;
  final FinancialViewMode? viewMode;

  const FinancialsPdfPreviewScreen({
    super.key,
    required this.entries,
    required this.bandName,
    required this.dateFilter,
    this.viewMode,
    this.members = const [],
  });

  // ...
}

class _FinancialsPdfPreviewScreenState
    extends State<FinancialsPdfPreviewScreen> {
  // ...

  String get _filterLabel {
    final now = DateTime.now();
    switch (widget.dateFilter) {
      case FinancialDateFilter.allTime:
        return 'All time';
      case FinancialDateFilter.thisYear:
        return 'Year ${now.year}';
      case FinancialDateFilter.thisMonth:
        return DateFormat('MMMM yyyy').format(now);
    }
  }
}
```

**PDF filename shape.** `_fileName` interpolates `_filterLabel`, producing:

- `allTime` → `"{Band} – Financial Report (All time).pdf"`
- `thisYear` → `"{Band} – Financial Report (Year YYYY).pdf"` — **preserved verbatim from Cycle 4's default-case output**; users who generated PDFs on Cycle 4 will see the same filename form for the default filter, so the "PDF output shape unchanged" property Cycle 4's plan claimed for the current-year case still holds.
- `thisMonth` → `"{Band} – Financial Report (December 2026).pdf"` (or the applicable month/year).

**Requires** `import 'package:intl/intl.dart';` in `financials_pdf_preview_screen.dart` — verified by grep that it's not currently imported there. `intl` is in `pubspec.yaml` already (used by `financials_screen.dart`, `financials_report_builder.dart`, and many others); this is only a per-file import addition, not a dependency addition.

Sole caller (`_openCombinedReport`) changes:

```dart
// Before (Cycle 4):
selectedYear: state.selectedYear,

// After (Cycle 6):
dateFilter: state.dateFilter,
```

### (d) Empty-state accessibility fix (Cycle 5 preserved verbatim)

Rewrite `_FinancialsScreenState.build` per Cycle 5's Proposed Solution → (a). The `filtered.isEmpty` conditional no longer wraps `_SummaryHeader` + `_TransactionsListHeader`; only the content area (spinner / `_EmptyState` / `ListView.separated`) swaps. This is a mechanical restructuring copy-out from Cycle 5's plan, plus the deletion of the standalone `_YearSelector` render call (which Cycle 4 rendered above `Expanded(...)` and Cycle 5 spec'd deleting).

Result tree (unchanged from Cycle 5's spec — only the widget referenced in the `Expanded` block changes to the Cycle 6 dropdown):

```dart
Expanded(
  child: state.error != null
      ? _ErrorState(message: state.error!)
      : Column(children: [
          const _SummaryHeader(),
          _TransactionsListHeader(
            sortAscending: _sortAscending,
            onToggleSort: () => setState(() => _sortAscending = !_sortAscending),
          ),
          const SizedBox(height: Spacing.space8),
          Expanded(
            child: state.isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : filtered.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: EdgeInsets.only(
                          left: Spacing.pagePadding,
                          right: Spacing.pagePadding,
                          bottom: MediaQuery.of(context).padding.bottom +
                              Spacing.space16,
                        ),
                        itemCount: sortedEntries.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: Spacing.space12),
                        itemBuilder: (context, index) {
                          final entry = sortedEntries[index];
                          return _TransactionCard(
                            entry: entry,
                            onTap: () => showFinancialEntryDetailsSheet(
                                context, ref, entry),
                          );
                        },
                      ),
          ),
        ]),
),
```

And the outer `Column` between the page title and the `Expanded(...)` content area collapses the `SizedBox(height: Spacing.space12) + const _YearSelector() + SizedBox(height: Spacing.space16)` triple into a single `const SizedBox(height: Spacing.space16)` (Cycle 5's spec, re-adopted).

**Behavior in each state** (unchanged from Cycle 5's Proposed Solution → (a)):
- **Error** — full-screen `_ErrorState`. Header hidden. Same rationale as Cycle 5 (initial fetch failed, `allEntries = []`, showing `$0.00` header would be misleading).
- **Loading** — header + list-header render on top; spinner centers below. Header shows `$0.00 / [This year ▾] • 0 transactions` briefly during initial load. Same "sub-second transient, not misleading" rationale.
- **Empty** — header + list-header render on top; `_EmptyState` centers below. **This is the fix.** User sees the dropdown, picks `'All time'` or `'This month'`, list re-renders (or, if truly no data anywhere, empty state persists but the control is reachable and no trap exists).
- **Non-empty** — same layout, list renders normally.

### Empty state under `dateFilter = allTime` — deliberately unchanged

If a brand-new band with zero entries is opened, `_EmptyState` renders under all three filter selections (nothing to show under any filter). This is expected and acceptable; the dropdown is still reachable per (d). No copy change to `_EmptyState` (Cycle 4/5 out-of-scope decision holds).

## Cycle 6 Database Impact

not applicable — no schema change, no new RPC, no RLS change, no migration. Filter-selection state is transient Riverpod UI state; not persisted to Supabase.

## Cycle 6 Flutter Architecture Changes

- **`FinancialsState` shape changes** — `selectedYear: int` deleted; `dateFilter: FinancialDateFilter` added with compile-time-const default `FinancialDateFilter.thisYear`. `copyWith` signature updates; constructor becomes `const` again.
- **`FinancialsNotifier` mutation methods** — `setSelectedYear(int)` deleted; `setDateFilter(FinancialDateFilter)` added. `build`, `_load`, `addEntry`, `updateEntry`, `deleteEntry`, `refresh` — unchanged.
- **`FinancialDateFilter` enum** — **reintroduced** with exactly `{ allTime, thisYear, thisMonth }`. No `custom`.
- **`FinancialsPdfPreviewScreen` constructor** — `int selectedYear` swapped to `FinancialDateFilter dateFilter`. `_filterLabel` becomes a 3-case switch. `_viewModeLabel`, `_fileName`, `_buildPdf`, `_handlePrint`, `_handleShare`, `build` — unchanged.
- **`_YearSelector`, `_YearSelectorChip`** — deleted (Cycle 5 spec, re-adopted).
- **`_availableYears`** helper — deleted (superseded from Cycle 5, which planned to retain it; Cycle 6 has no consumer since the item list is a fixed enum).
- **`_dateFilterLabel(FinancialDateFilter) → String`** — new top-level helper in `financials_screen.dart`.
- **Inline `AppDropdown<FinancialDateFilter>`** — new call site inside `_SummaryHeader`; `IntrinsicWidth`-wrapped (with `SizedBox(width: 128)` fallback authorized). First `AppDropdown<FinancialDateFilter>` usage in the codebase; other `AppDropdown` call sites use `String` / model types. Not a wrapper API change.
- **`_FinancialsScreenState.build` restructuring** — Cycle 5's spec, re-adopted.
- **New import** in `financials_screen.dart`: `import '../../components/ui/app_dropdown.dart';` (Cycle 5's spec, re-adopted).
- **New import** in `financials_pdf_preview_screen.dart`: `import 'package:intl/intl.dart';` (`intl` already in pubspec).
- No new provider, controller, repository, or model. No pubspec change.

## Cycle 6 Files to Create

None. All widget/enum additions live inside existing files. `year_selector_test.dart` is deleted, not replaced.

## Cycle 6 Files to Modify

### [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart)
- **Reintroduce** `enum FinancialDateFilter { allTime, thisYear, thisMonth }`. No `custom` value.
- **Delete** the `selectedYear` field from `FinancialsState`, its constructor param, its `copyWith` param, and the `selectedYear = selectedYear ?? DateTime.now().year` initialiser.
- **Add** `final FinancialDateFilter dateFilter;` field. Constructor named param: `this.dateFilter = FinancialDateFilter.thisYear` (compile-time-const default). Restore the `const` constructor.
- **Update** `copyWith` to accept `FinancialDateFilter? dateFilter` and merge with the existing pattern.
- **Replace** `_applyDateFilter` body with the 3-case switch shown in Proposed Solution → (a). Preserve the `.sort((a, b) => b.entryDate.compareTo(a.entryDate))` newest-first sort (unchanged behavior — Cycle 1 sort semantics).
- **Delete** `setSelectedYear(int)` from `FinancialsNotifier`.
- **Add** `void setDateFilter(FinancialDateFilter filter) { state = state.copyWith(dateFilter: filter); }`.

### [lib/features/financials/financials_pdf_preview_screen.dart](lib/features/financials/financials_pdf_preview_screen.dart)
- **Add** `import 'package:intl/intl.dart';` with the other package imports (alphabetized among package imports).
- **Delete** constructor param `int selectedYear`. **Add** `required FinancialDateFilter dateFilter`.
- **Replace** `_filterLabel` with the 3-case switch shown in Proposed Solution → (c).
- `_viewModeLabel`, `_fileName`, `_buildPdf`, `_handlePrint`, `_handleShare`, `build` — untouched. `import 'financials_controller.dart';` stays (still used for `FinancialViewMode` and now for `FinancialDateFilter`).

### [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart)
- **Add** `import '../../components/ui/app_dropdown.dart';` alongside the other relative imports.
- **Delete** the `_YearSelector` class in full (~19 lines).
- **Delete** the `_YearSelectorChip` class in full (~34 lines).
- **Delete** the `_availableYears` top-level helper in full (~8 lines).
- **Delete** the `SizedBox(height: Spacing.space12)` + `const _YearSelector()` + `SizedBox(height: Spacing.space16)` sequence in `_FinancialsScreenState.build`'s outer `Column` (between `_ViewModeToggle` and the `Expanded(...)` content area). Replace with a single `const SizedBox(height: Spacing.space16)`.
- **Restructure** the `Expanded(child: state.isLoading ? ... : ... : filtered.isEmpty ? _EmptyState : Column([_SummaryHeader, ...]))` block per Proposed Solution → (d): pull `_SummaryHeader` and `_TransactionsListHeader` above the loading/empty conditional; only the inner `Expanded` swaps between spinner / `_EmptyState` / `ListView.separated`.
- **Add** the `_dateFilterLabel(FinancialDateFilter)` top-level helper (near the file's other top-level helpers).
- **Rewrite** the single `Text('${state.selectedYear} • ...')` line inside `_SummaryHeader.build` as the `Row(IntrinsicWidth(AppDropdown<FinancialDateFilter>), Text(' • N transactions'))` structure from Proposed Solution → (b).
- **Update** `_openCombinedReport` to pass `dateFilter: state.dateFilter` instead of `selectedYear: state.selectedYear`.
- **Preserve verbatim** everything else in `_SummaryHeader`: `TOTAL <MODE>` label, big total, `_InlineLinkButton`s.
- **Preserve verbatim** `_TransactionsListHeader`, `_TransactionCard`, `_InlineLinkButton`, `_ViewModeToggle`, `_SavingsSheet` + `_showSavingsSheet`, `_openCombinedReport`'s non-param body, `_EmptyState`, `_ErrorState`, `_addEntry`.
- **Audit imports:** `Icons.arrow_drop_down` was only used in `_YearSelectorChip`. After deletion, `package:flutter/material.dart` may still supply other `Icons` references (`Icons.print_rounded` in the PDF screen; not this file — verify grep in this file). The `PopupMenuButton` import (`package:flutter/material.dart`) is still needed for other Material widgets in the screen. No import removals expected — do the audit to confirm.

### [test/features/financials/widgets/summary_header_test.dart](test/features/financials/widgets/summary_header_test.dart)
- **Add** imports:
  - `import 'package:bandroadie/components/ui/app_dropdown.dart';`
  - `import 'package:flutter/material.dart';` (already imported — for `DropdownMenuItem<T>` type reference in assertions).
- **Update** the existing Cycle 4 test cases that assert `find.text('${year} • N transactions')` (`'displays the current calendar year by default'`, `'displays the selected year when setSelectedYear sets a non-current year'`, `'merges year and count into a single line separated by " • "'`, `'count phrasing is singular for one entry, plural for multiple entries'`):
  - The `'displays the current calendar year by default'` case is **replaced** by a new case `'default state has dateFilter = FinancialDateFilter.thisYear and the AppDropdown shows "This year"'` — asserting the enum default AND that the collapsed label reads the literal string `'This year'` (not the current year's numeral).
  - The `'displays the selected year when setSelectedYear sets a non-current year'` case is **replaced** by `'setting dateFilter to allTime causes the AppDropdown to render "All time" and the trailing text to read " • N transactions" for the unfiltered count'`.
  - The `'merges year and count into a single line separated by " • "'` case is **updated** to assert the split shape: `find.byWidgetPredicate((w) => w is AppDropdown<FinancialDateFilter>)` finds the dropdown, and `find.text(' • 3 transactions')` finds the trailing text widget. The single merged `find.text('$year • 3 transactions')` no longer matches (year is inside the dropdown, not the surrounding text).
  - The `'count phrasing is singular for one entry, plural for multiple entries'` case is **updated** to assert `find.text(' • 1 transaction')` and `find.text(' • 3 transactions')` (the leading token is inside the dropdown widget, not part of the same `Text`).
- **Add** these new Cycle 6 test cases:
  1. `'AppDropdown<FinancialDateFilter> value is non-null in every default state (thisYear)'` — pump `FinancialsState()` with defaults, locate the `AppDropdown<FinancialDateFilter>` widget, assert `w.value == FinancialDateFilter.thisYear` (and `w.value != null` for defensiveness).
  2. `'AppDropdown format renders "This year" text, not a year numeral, for the thisYear case'` — pump default state, assert `find.text('This year')` finds one widget (the collapsed dropdown label). Additionally assert that `find.text('${DateTime.now().year}')` (the pure numeral) does **not** find any widget as an exact-`Text` match anywhere in the header (guard against a regression that would reintroduce the numeral). This is the direct reversal of Cycle 4's "always show the numeral" behavior for `thisYear` and is the primary test gate for Tony's Cycle 6 requirement.
  3. `'AppDropdown items list contains exactly the three FinancialDateFilter values in enum-declaration order (allTime, thisYear, thisMonth)'` — locate the `AppDropdown<FinancialDateFilter>`, extract `w.items!.map((i) => i.value).toList()`, assert it equals `[FinancialDateFilter.allTime, FinancialDateFilter.thisYear, FinancialDateFilter.thisMonth]`.
  4. `'AppDropdown items render Text children with the exact strings "All time", "This year", "This month"'` — for each item in `w.items!`, unwrap the `child` (a `Text` widget) and assert its `data` matches the expected string for its `value`. Guard against accidental capitalization drift (`'All Time'`, `'This Year'`, etc.).
  5. `'invoking AppDropdown.onChanged(FinancialDateFilter.allTime) dispatches setDateFilter on the notifier'` — capture `container.read(financialsProvider).dateFilter` (initially `thisYear`), locate the `AppDropdown<FinancialDateFilter>`, invoke its `onChanged(FinancialDateFilter.allTime)` directly (per Cycle 5's rationale for preferring widget-level over `tester.tap` + menu-item-tap), `pumpAndSettle`, assert `container.read(financialsProvider).dateFilter == FinancialDateFilter.allTime`.
  6. **The core empty-state fix test (Cycle 5's case 5, re-adopted for Cycle 6):** `'inline dropdown remains visible and its onChanged callback wired when filteredEntries is empty for the selected filter'` — pump `FinancialsState(allEntries: [entry in prior year], dateFilter: FinancialDateFilter.thisYear)` where the entry's year is `DateTime.now().year - 1`. Assert:
     - `_EmptyState` is rendered (`find.text('No entries yet')` finds one widget).
     - `_SummaryHeader` is still rendered above it (`find.text('TOTAL INCOME')` — or `TOTAL EXPENSES` under `viewMode.expenses` — finds one widget).
     - `AppDropdown<FinancialDateFilter>` is present (`find.byType(AppDropdown<FinancialDateFilter>)` finds one widget).
     - The dropdown's `items!` contains all three enum values (unchanged — item list is fixed).
     - Invoking `AppDropdown.onChanged(FinancialDateFilter.allTime)` directly, then `pumpAndSettle`, changes `container.read(financialsProvider).dateFilter` to `allTime`.
     - After the filter switch, `_EmptyState` is gone and the `_TransactionCard` for the prior-year entry is rendered.
- Existing `'total for two income entries…'`, `'label reads TOTAL INCOME / TOTAL EXPENSES'`, `'View Savings Balance and Generate Report links chevron'` cases are **untouched** — they don't assert on the year-or-filter line.

### [test/features/financials/widgets/year_selector_test.dart](test/features/financials/widgets/year_selector_test.dart)
- **Delete this file.** Its target widgets (`_YearSelector`, `_YearSelectorChip`, `PopupMenuButton<int>`, `_availableYears`) all cease to exist in Cycle 6. Equivalent coverage lives in the updated `summary_header_test.dart` (cases 1–6 above). Deletion via `git rm` if tracked, or `rm` if still untracked (per `git status` on the working tree, it's currently `??`  untracked). Do not leave an empty file or a stub.

### [test/features/financials/widgets/transaction_card_test.dart](test/features/financials/widgets/transaction_card_test.dart) and [test/features/financials/widgets/transactions_list_header_test.dart](test/features/financials/widgets/transactions_list_header_test.dart)
- **No change.** Cycle 4's year-relative fixture defaults (`DateTime(DateTime.now().year, ...)`) keep entries inside the `thisYear` filter, so both test files continue to pass byte-identical under Cycle 6. `transactions_list_header_test.dart`'s `container.read(financialsProvider)` assertions read only the identity of the state object (for the "sort does not mutate provider" case), not the `selectedYear` field — no field-name dependency.

## Cycle 6 Files Off-Limits

- [lib/features/financials/financial_entry_repository.dart](lib/features/financials/financial_entry_repository.dart) — no query changes.
- [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart) — model unchanged.
- [lib/features/financials/financials_report_builder.dart](lib/features/financials/financials_report_builder.dart) — report format unchanged (still receives a `dateRangeLabel: String`, still gets a valid label string from `_filterLabel`).
- [lib/features/financials/widgets/**](lib/features/financials/widgets/) — every file in this folder (details sheet, add/edit sheet, gig pay sheet) unchanged.
- [lib/components/ui/app_dropdown.dart](lib/components/ui/app_dropdown.dart) — **do not modify the wrapper.** Cycle 6 uses it as-is; adding compact/dense modes, styling knobs, or a specialized enum-typed variant is a separate concern requiring Manager sign-off. If `IntrinsicWidth` doesn't produce acceptable sizing, use `SizedBox(width: 128)` at the call site — do not touch the wrapper.
- [lib/components/ui/README.md](lib/components/ui/README.md) — no doc update required; the wrapper's API is unchanged.
- All `supabase/migrations/**` files — no DB change.
- `pubspec.yaml` — no new dependency (`intl` already present).
- Anything outside `lib/features/financials/`, `lib/components/ui/` (read-only), and the test files listed above.

## Cycle 6 Change Budget

Numbers are net line delta *per file* after Engineer implements the Task Breakdown; QA diffs against these. Being off by >~40 lines in either direction on `financials_screen.dart` or `summary_header_test.dart`, or any non-zero delta on the off-limits files, is a plan-vs-implementation gap that should be flagged.

| File | Expected net Δ lines | Rationale |
| --- | --- | --- |
| `lib/features/financials/financials_controller.dart` | **+5 to +20** | Add enum (3 lines), swap `selectedYear` field for `dateFilter` field (net ~0 lines), restore `const` constructor (net −1 line since the `_defaultSelectedYear` helper hack goes away — the initialiser list `: selectedYear = selectedYear ?? _defaultSelectedYear()` shrinks to a compile-time-const default parameter), expand `_applyDateFilter` from a 3-line where-clause to a ~15-line switch, swap `setSelectedYear` method for `setDateFilter` method (net ~0 lines). |
| `lib/features/financials/financials_screen.dart` | **−35 to +5** | Delete `_YearSelector` (~19 lines), `_YearSelectorChip` (~34 lines), `_availableYears` (~8 lines), the standalone render-call block (net −3 lines: three widgets → one `SizedBox`). Add `_dateFilterLabel` helper (~10 lines), inline `Row(IntrinsicWidth(AppDropdown), Text)` structure (~20 lines replacing ~5 lines of the single `Text`). Restructure build's `Expanded(child: ...)` per Cycle 5 (net ~+5 lines). Add `import 'app_dropdown.dart';` (+1 line). |
| `lib/features/financials/financials_pdf_preview_screen.dart` | **+5 to +15** | Add `intl` import (+1 line). Constructor: swap `int selectedYear` param → `FinancialDateFilter dateFilter` (net ~0 lines). Replace 1-line `_filterLabel` with ~15-line switch. |
| `test/features/financials/widgets/summary_header_test.dart` | **+50 to +150** | Update 4 existing cases from single-string to split-shape assertions (~+10 lines). Add 6 new cases (~+120 to +180 lines depending on fixture verbosity). Add 1 import (+1 line). |
| `test/features/financials/widgets/year_selector_test.dart` | **DELETED** | Full-file removal (~180 lines removed). Not counted against per-file delta budget since the file is gone. |
| `test/features/financials/widgets/transaction_card_test.dart` | **0** | Untouched. |
| `test/features/financials/widgets/transactions_list_header_test.dart` | **0** | Untouched. |
| Any other file | **0** | Off-limits. |

- Expected new files: **0**.
- Expected deleted files: **1** (`year_selector_test.dart`).
- Expected new public classes / methods on production code: **0** (widgets, helper, and notifier method are all private / private-to-file; the reintroduced `FinancialDateFilter` enum is technically public but is a controller-file concern, matching the pre-Cycle-4 visibility).
- Expected new dependencies (pubspec.yaml): **0**.
- Expected migration files: **0**.

## Cycle 6 System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Financials → Screen | changed (in-scope) | Year picker replaced by three-option filter dropdown (`AppDropdown<FinancialDateFilter>`) inline in `_SummaryHeader`; standalone `_YearSelector` row deleted; empty-state layout restructured per Cycle 5. |
| Financials → Controller | changed (in-scope) | State field `selectedYear: int` swapped for `dateFilter: FinancialDateFilter`. Enum reintroduced (3 values, no `custom`). Notifier method swapped. |
| Financials → PDF Report Screen | changed (in-scope) | Constructor param swapped from `int selectedYear` to `FinancialDateFilter dateFilter`. `_filterLabel` becomes a 3-case switch producing `'All time'` / `'Year YYYY'` / `'MMMM yyyy'`. |
| Financials → PDF Report Builder | unaffected | Takes `dateRangeLabel: String`; still gets a valid label string. Output format unchanged. |
| Financials → Add / Edit Sheet | unaffected | Independent of filter state. |
| Financials → Details Sheet | unaffected | Independent of filter state. |
| Financials → Savings Sheet | unaffected | Reads `state.allEntries` (unfiltered). |
| Gigs / Rehearsals / Setlists / Members | unaffected | No cross-references. |
| Auth / Routing / Notifications | unaffected | No init-order change, no session change. |
| Platforms (iOS / Android / macOS / Web) | uniformly affected | Shared Flutter UI only; `FSelect.rich` popup renders natively on all four (Cycle 5's cross-platform analysis applies unchanged). No platform-conditional code. |
| Supabase schema / RLS / RPCs | unaffected | Client-only change. |
| Forui integration / `AppDropdown` wrapper | consumed, not modified | Cycle 6 adds a new call-site type parameter (`FinancialDateFilter`) but the wrapper's API is unchanged; `IntrinsicWidth` call-site pattern is from Cycle 5. |
| `lib/components/ui/README.md` | unaffected (doc) | Optional call-site-count update deferred (same rationale as Cycle 5). |
| pubspec.yaml | unaffected | No new dependency. |

## Cycle 6 Regression Risk

**LOW**. Justification:

- No touch to auth, session, routing, init order, DB, RLS, RPCs, or platform-conditional code.
- State-shape change is contained to one field on one state class and one notifier method; the field default is a compile-time-const enum value (simpler and safer than Cycle 4's runtime-default helper).
- No new provider added or removed.
- No new dependency, no new migration, no schema change.
- Change scoped to three production source files (`financials_controller.dart`, `financials_screen.dart`, `financials_pdf_preview_screen.dart`), one test file edited, one test file deleted.
- The `AppDropdown` wrapper is used at 4 direct sites elsewhere; the new call-site pattern (`IntrinsicWidth`-wrapped, enum-typed) is a moderate extension of the existing usage. Cycle 5's analysis of the wrapper's behavior applies unchanged.
- PDF report row order and content shape are unchanged (still driven by `dateFilteredEntries`, still newest-first).

**Realistic regression classes:**

1. **`IntrinsicWidth` incompatible with `FSelect.rich` internals.** Same risk Cycle 5 flagged. **Mitigated:** authorized `SizedBox(width: 128)` fallback at the same call site.
2. **Test fixtures whose year != `DateTime.now().year`.** Cycle 4's Task 7 fix (year-relative fixtures in `transaction_card_test.dart` and `transactions_list_header_test.dart`) makes both files robust to wall-clock rollover under the default `thisYear` filter. Cycle 6 doesn't reintroduce any year-hardcoded fixture. The one Cycle 6 test case that intentionally seeds a prior-year entry (`summary_header_test.dart` case 6, the empty-state fix test) does so explicitly with `DateTime.now().year - 1`, which is a computed value and safe across rollovers.
3. **PDF filename shape change for non-default filters.** Users who select `'All time'` or `'This month'` will see new filename forms (`"... (All time).pdf"`, `"... (December 2026).pdf"`). This is expected and the target behavior (matches pre-Cycle-4 form). The default-case filename (`"... (Year 2026).pdf"`) is preserved verbatim from Cycle 4, so existing users on the default filter see no filename change.
4. **Load-state flash of `$0.00 / [This year ▾] • 0 transactions`.** Sub-second, matches Cycle 5's accepted transient behavior. Not a defect.

## Cycle 6 Engineer Task Breakdown

Ordered, atomic. Each task leaves the app compiling once its immediate dependencies are met (Tasks 1 and 2 must complete before Tasks 3–5 compile; Tasks 3, 4, 5 are independent of each other). **Do not merge tasks or invent extra sub-steps.**

1. **Reintroduce `FinancialDateFilter` enum and swap `FinancialsState`'s field.**
   - In `lib/features/financials/financials_controller.dart`, add `enum FinancialDateFilter { allTime, thisYear, thisMonth }` near the top of the file (below `FinancialViewMode`).
   - Delete the `selectedYear` field, its constructor param `int? selectedYear`, its `copyWith` param, and the `selectedYear = selectedYear ?? DateTime.now().year` initialiser.
   - Add `final FinancialDateFilter dateFilter;` field. Named param: `this.dateFilter = FinancialDateFilter.thisYear`. Restore the `const` on the constructor.
   - Add `FinancialDateFilter? dateFilter` to `copyWith`, merge via `dateFilter: dateFilter ?? this.dateFilter`.
   - Replace `_applyDateFilter`'s body with the 3-case switch from Proposed Solution → (a). Keep the newest-first sort trailing the switch.
   - After Task 1, the controller compiles; `financials_screen.dart` and `financials_pdf_preview_screen.dart` won't compile until Tasks 2 and 3 land. This is expected and OK.

2. **Update the notifier's mutation method.**
   - In the same file, delete `void setSelectedYear(int year)`.
   - Add `void setDateFilter(FinancialDateFilter filter) { state = state.copyWith(dateFilter: filter); }` in the same slot in the method list.

3. **Update `FinancialsPdfPreviewScreen` for the new state shape.**
   - In `lib/features/financials/financials_pdf_preview_screen.dart`, add `import 'package:intl/intl.dart';` with the other package imports.
   - Constructor: delete `required this.selectedYear`, delete `final int selectedYear;`. Add `final FinancialDateFilter dateFilter;` and `required this.dateFilter` in the constructor's named-param list.
   - Replace `String get _filterLabel => 'Year ${widget.selectedYear}';` with the 3-case switch from Proposed Solution → (c).
   - Nothing else changes in this file.

4. **Introduce the inline `AppDropdown<FinancialDateFilter>` and its label helper in `financials_screen.dart`.**
   - In `lib/features/financials/financials_screen.dart`, add `import '../../components/ui/app_dropdown.dart';` alongside the other relative imports.
   - Add the top-level `String _dateFilterLabel(FinancialDateFilter filter) { switch (...) { ... } }` helper (Proposed Solution → (b)).
   - Rewrite the single `Text('${state.selectedYear} • ...')` widget in `_SummaryHeader.build` as the `Row(mainAxisSize: min, mainAxisAlignment: center, crossAxisAlignment: center, [IntrinsicWidth(AppDropdown<FinancialDateFilter>(...)), Text(' • N transactions')])` structure from Proposed Solution → (b). Wire `AppDropdown.onChanged` to `setDateFilter` with the null-guard. Provide `format: _dateFilterLabel` and `items:` mapped from `FinancialDateFilter.values`.
   - Wrap the `AppDropdown` in `IntrinsicWidth`. If layout throws at test/analyze time, swap to `SizedBox(width: 128)` — both authorized.
   - Update the `_openCombinedReport` call to pass `dateFilter: state.dateFilter` in place of `selectedYear: state.selectedYear`.
   - After this task, `_YearSelector` still renders above the entries list (temporarily two filter controls, one inline dropdown and one legacy chip). This is expected and cleaned up in Task 5.

5. **Restructure `_FinancialsScreenState.build` and delete the standalone `_YearSelector` row.**
   - Rewrite the outer `Expanded(child: ...)` per Proposed Solution → (d): `state.error != null → _ErrorState`; else → `Column([_SummaryHeader, _TransactionsListHeader, SizedBox(space8), Expanded(state.isLoading ? spinner : filtered.isEmpty ? _EmptyState : ListView.separated)])`.
   - Delete the `SizedBox(height: Spacing.space12)` + `const _YearSelector()` + `SizedBox(height: Spacing.space16)` triple. Replace with a single `const SizedBox(height: Spacing.space16)`.
   - Delete the `_YearSelector` class in full.
   - Delete the `_YearSelectorChip` class in full.
   - Delete the `_availableYears` top-level helper in full.
   - `flutter analyze` should now show no dangling references. Any `Icons.arrow_drop_down` (from `_YearSelectorChip`) is gone; `package:flutter/material.dart` remains imported for `PopupMenuButton` — but wait: `PopupMenuButton` was only used in `_YearSelector`, so if no other `PopupMenuButton` usage remains in the file (verify with grep in this file only), that's fine — the import is still needed for many other Material widgets (`AppBar`, `MaterialPageRoute`, `CircularProgressIndicator`, `ListView`, etc.). Do the grep audit.

6. **Update `summary_header_test.dart` for the Cycle 6 dropdown.**
   - Add `import 'package:bandroadie/components/ui/app_dropdown.dart';` at the test-file imports.
   - Replace/rewrite the 4 Cycle 4/5 test cases that assert the merged single-string form. Each replacement uses split-shape assertions (`AppDropdown<FinancialDateFilter>` + adjacent ` • N transactions` text) per Files to Modify → this file.
   - Add the 6 new Cycle 6 test cases enumerated in Files to Modify → this file. Case 2 (the "renders 'This year' text, not a numeral" test) is the primary test gate for Tony's Cycle 6 requirement and must be present with those exact assertions. Case 6 (the empty-state fix, adapted from Cycle 5's case 5) is the primary test gate for the empty-state accessibility fix.

7. **Delete `year_selector_test.dart`.**
   - `git rm test/features/financials/widgets/year_selector_test.dart` if the file is tracked; `rm test/features/financials/widgets/year_selector_test.dart` if it's still untracked (per `git status` at Cycle 6 plan-write time, the file is `??` untracked — either command removes it identically from the working tree).
   - After this task, the file is fully gone. QA verifies via `test -e` or `git ls-files | grep` returning empty.

## Cycle 6 Verification Plan

### Cycle 6 Tier 1 — pre-deploy (QA gate, mechanically executable)

QA gate for APPROVED requires all of the following without running the app:

1. `flutter analyze` clean (no new lints; existing baseline preserved).
2. `flutter test` passes, including:
   - The updated `summary_header_test.dart` with all 6 new Cycle 6 cases (plus the 4 rewritten Cycle 4/5 cases, plus the untouched Cycle 1 cases).
   - The untouched `transaction_card_test.dart` and `transactions_list_header_test.dart` (verify byte-identical to Cycle 4's Task 7 output — no re-edit).
   - `year_selector_test.dart` must no longer exist (verify via `test ! -e test/features/financials/widgets/year_selector_test.dart` or `git ls-files | grep year_selector_test` returning empty).
3. Diff review confirms these files are byte-identical to `main` (or, where applicable, to their state after Cycles 1–3 for files touched then):
   - `lib/features/financials/financial_entry_repository.dart` — vs. `main`
   - `lib/features/financials/models/financial_entry.dart` — vs. `main`
   - `lib/features/financials/financials_report_builder.dart` — vs. `main`
   - `lib/features/financials/widgets/**` — every file, vs. its Cycles 1–3 shape (details sheet was touched in Cycles 1–3; other widget files untouched by any cycle)
   - `lib/components/ui/app_dropdown.dart` — vs. `main` (Cycle 6 must not modify the wrapper)
   - `lib/components/ui/README.md` — vs. `main`
   - All `supabase/migrations/**` files — vs. `main`
   - `pubspec.yaml` — vs. `main` (no new dep)
4. Diff review confirms net line delta per modified file falls inside **Cycle 6 Change Budget** ranges.
5. Diff review of `financials_controller.dart` confirms:
   - `enum FinancialDateFilter { allTime, thisYear, thisMonth }` is present.
   - No `custom` value inside the enum (guard against accidental re-introduction).
   - No `customStartDate` / `customEndDate` field, no `setCustomDateRange` method (they stay deleted from Cycle 4's work).
   - `dateFilter` field is `final FinancialDateFilter`, default `FinancialDateFilter.thisYear`, non-nullable.
   - Constructor is declared `const` (verify).
   - `setDateFilter(FinancialDateFilter)` present; `setSelectedYear(int)` absent.
   - `selectedYear` field and its constructor/copyWith references are absent.
6. Diff review of `financials_screen.dart` confirms:
   - `import '../../components/ui/app_dropdown.dart';` present.
   - No `import 'package:forui/forui.dart';` (all Forui access is via `AppDropdown`).
   - `_YearSelector`, `_YearSelectorChip`, `_availableYears` are absent (grep returns zero matches).
   - `AppDropdown<FinancialDateFilter>` is present inside `_SummaryHeader` (grep finds one occurrence).
   - Either `IntrinsicWidth(child: AppDropdown<FinancialDateFilter>(...))` or `SizedBox(width: 128, child: AppDropdown<FinancialDateFilter>(...))` surrounds the dropdown at its call site — one of the two, not neither.
   - `_dateFilterLabel(FinancialDateFilter)` helper present at file top level.
   - The helper's switch body returns exactly `'All time'`, `'This year'`, `'This month'` for the three enum values (string-exact match; guard against `'All Time'` / `'This Year'` capitalization drift).
   - `_openCombinedReport` passes `dateFilter: state.dateFilter` (not `selectedYear:`).
   - `_FinancialsScreenState.build` does **not** wrap `_SummaryHeader` inside the `filtered.isEmpty` conditional — the header renders at the same level in every non-error branch.
7. Diff review of `financials_pdf_preview_screen.dart` confirms:
   - `import 'package:intl/intl.dart';` present.
   - Constructor param is `required FinancialDateFilter dateFilter`; no `selectedYear: int` param.
   - `_filterLabel` is a switch with cases `allTime → 'All time'`, `thisYear → 'Year ${now.year}'`, `thisMonth → DateFormat('MMMM yyyy').format(now)`.
8. Diff review of `summary_header_test.dart` confirms case 2 (`'AppDropdown format renders "This year" text, not a year numeral, for the thisYear case'`) is present and mechanically asserts both `find.text('This year')` finds a widget AND `find.text('${DateTime.now().year}')` as an exact-`Text` match finds none in the header. This is Tony's Cycle 6 directive gate; missing this case is a Critical plan violation.
9. Diff review of `summary_header_test.dart` confirms case 6 (the empty-state fix test) is present and mechanically exercises: (a) `_EmptyState` renders under `dateFilter = thisYear` when data is only in prior years, (b) the `AppDropdown` is visible in that same pumped tree, (c) `onChanged(FinancialDateFilter.allTime)` dispatches `setDateFilter` and updates the state, (d) after the dispatch the empty state disappears and the prior-year entry renders. This is the Cycle 5 empty-state-fix gate; missing this case is a Critical plan violation.

### Cycle 6 Tier 2 — post-deploy
not applicable — no DB migration, no RPC change, no RLS change, no edge function change, no external API change.

### Cycle 6 Owner-run punch list (Tony runs at PR-test time — QA writes this into the PR body verbatim, does not attempt it)

QA cannot run the app. Tony walks the following in a preview build (adds to the existing Cycles 1–4 punch lists, does not replace them; Cycle 5's punch list is superseded by this one since Cycle 5 was never implemented):

1. Sign in with a demo band containing entries in the current calendar year; open Financials.
   Expected: single filter control inline in the summary line — the collapsed dropdown label reads exactly `"This year"` (three characters `T`, `h`, `i` + `s` + space + `y`, `e`, `a`, `r`; **not the numeric year like "2026"**). Summary line reads `[This year ▾] • N transactions` centered under the total.
2. Tap the "This year" dropdown.
   Expected: FSelect popup opens showing exactly three options in enum order: `"All time"`, `"This year"`, `"This month"`. No numeric year options, no "Custom" option, no "All years" option. Popup styles as a standard Forui form-field dropdown (not a `PopupMenu` sheet).
3. Select `"All time"`.
   Expected: dropdown closes; collapsed label updates to `"All time"`; count and total update to reflect the full unfiltered set (all years' data); list re-renders. Two paints max.
4. Select `"This month"`.
   Expected: only current-month entries visible; total and count update accordingly. If the band has no current-month entries, `_EmptyState` renders with the dropdown still visible above it.
5. **The core Cycle 6 fix scenario:** switch to (or sign in with) a band whose data is entirely in prior years. On screen entry, the default filter is `thisYear` and the list is empty.
   Expected: summary header renders on top with the dropdown showing `"This year"`, total ($0.00), count (0), and both link buttons. Below the header, `_EmptyState` renders (`No entries yet`). Tap the dropdown → popup shows the three options. Select `"All time"` → list populates with prior-year entries, empty state disappears. **This step must work end-to-end without leaving/re-entering the screen — that's the whole empty-state fix.**
6. Toggle Income ↔ Expenses while any non-default filter is selected.
   Expected: filter selection persists across the toggle; only the total and count change.
7. Tap "Generate Report" while `dateFilter = allTime`.
   Expected: PDF preview opens with header/filename reading `"All time"` — filename becomes `"{Band} – Financial Report (All time).pdf"`.
8. Tap "Generate Report" while `dateFilter = thisMonth`.
   Expected: PDF preview opens with header/filename reading e.g. `"December 2026"` — filename becomes `"{Band} – Financial Report (December 2026).pdf"`.
9. Tap "Generate Report" while `dateFilter = thisYear` (default).
   Expected: PDF preview opens with header/filename reading e.g. `"Year 2026"` — filename becomes `"{Band} – Financial Report (Year 2026).pdf"`. **Verify this filename form is byte-identical to what Cycle 4 produced on the default filter** — this is the "backward-compat for default users" property.
10. Tap "View Savings Balance."
    Expected: savings sheet opens with the same animated total behavior as today; filter selection does not affect savings totals (they read `state.allEntries`, filter-agnostic).
11. Sort toggle: tap `"Newest first ▾"` in the transactions list header while entries are present.
    Expected: label flips, list reverses. Unchanged from Cycle 1.
12. With an empty filtered list (`dateFilter = thisYear` and no current-year entries), verify the sort toggle in `_TransactionsListHeader` is visible but inert — tapping it doesn't crash, doesn't change label (nothing to sort). Same expected mild noise as Cycle 5 documented.
13. Cross-platform visual check on iOS, Android, macOS, and web:
    - The inline dropdown is sized appropriately (not stretched full-width, not clipped by field padding), and the `" • N transactions"` text sits next to it on the same line at all common widths (iPhone SE / narrow web / iPad / macOS full-window). The dropdown's natural width should comfortably fit the longest label `"This month"` without clipping.
    - The FSelect popup opens correctly on each platform (not clipped by the safe area, not offset from the field).
    - `_EmptyState` centers correctly under the summary header on tall and short screens.
14. Verify (visual, subjective): the inline dropdown's field chrome is acceptable next to the muted footnote text. Same "if the visual weight feels wrong, note it in the PR — future cycle can tune" acceptance as Cycle 5.

## Cycle 6 QA Regression Areas

1. **Cycle 6's `'This year'` textual label (not numeral)** — **Tony's primary Cycle 6 directive.** Regression check: any accidental reintroduction of a numeric year (`'${year}'`, `'$currentYear'`, etc.) in the collapsed dropdown label or its format function is a Critical regression. Punched via test case 2 in `summary_header_test.dart` (mechanical gate) and punch-list step 1 (owner-run visual gate).
2. **Empty-state reachability** — the Cycle 5 fix, re-adopted for Cycle 6. Regression check: any change to `_FinancialsScreenState.build` that reintroduces `_SummaryHeader` inside a `filtered.isEmpty` conditional is a Critical regression. Punched via test case 6 in `summary_header_test.dart` (mechanical gate) and punch-list step 5 (owner-run functional gate).
3. **Non-null dropdown selection** — regression check: `state.dateFilter` must be non-nullable with a compile-time-const default. Punched via test case 1 in `summary_header_test.dart` (mechanically asserts the `AppDropdown.value` is a real enum value in the default state).
4. **No `custom` re-introduction** — regression check: any Engineer temptation to add a `FinancialDateFilter.custom` value "for completeness" or to restore Cycle 1's `_pickCustomRange` / `_customLabel` code is a plan violation. Punched via Tier 1 gate #5 (enum body has exactly the 3 named values).
5. **`AppDropdown` inline sizing** — regression check: `AppDropdown<FinancialDateFilter>` inside `_SummaryHeader` must be constrained by either `IntrinsicWidth` or `SizedBox(width: 128)`; unconstrained, it stretches to column width and breaks the inline layout. Punched via Tier 1 gate #6.
6. **Wrapper immutability** — `lib/components/ui/app_dropdown.dart` must be byte-identical to `main`. Punched via Tier 1 gate #3.
7. **No raw `FSelect` usage in feature code** — regression check: `import 'package:forui/forui.dart';` must not appear in `financials_screen.dart` or `financials_pdf_preview_screen.dart`. All Forui access goes through `AppDropdown`. Punched via Tier 1 gate #6 (grep gate).
8. **PDF report filename shape** — `thisYear` (default) case's filename must be byte-identical to Cycle 4's output for backward compat. `allTime` and `thisMonth` cases add new filename forms (`"All time"`, `"MMMM yyyy"`) — these are the target, not a regression.
9. **Sort toggle** — unchanged from Cycle 1. Punch-list step 11.
10. **`_SavingsSheet`** — unchanged from Cycles 1–4. Filter selection does not affect savings totals.
11. **Details sheet** — unchanged from Cycles 1–3. All Cycle 1 assertions still hold.
12. **Loading-state flash** — accept `$0.00 / [This year ▾] • 0 transactions` briefly visible during initial load. Same acceptance rationale as Cycle 5.

## Cycle 6 Rollout Strategy

Same PR as Cycles 1–4 (#273). Commits added on top of the Cycle 4 tree. No feature flag, no phased rollout, no DB migration. Merge to `main` when Cycle 6 clears the QA gate + owner-run punch list. Rollback = revert the PR; no data changes to unwind.

## Cycle 6 Out of Scope

- Adding a `FinancialDateFilter.custom` value or arbitrary date-range picker. Tony did not request this; the `showDateRangePicker` code path stays deleted from Cycle 4.
- Adding an "All years" or "Last N years" option to the dropdown. Not requested; enum stays at exactly 3 values.
- Persisting `dateFilter` across screen dismiss, band switch, or app restart — matches the Cycle 1 / Cycle 4 / Cycle 5 stance on transient filter state.
- Any change to the empty-state copy or icon to reflect the current filter (e.g., "No entries for This year"). Deferred; would require a `_EmptyState` copy variant per filter.
- Any change to `AppDropdown` itself (compact mode, dense variant, styling override, enum-specialized subclass). If `IntrinsicWidth`/`SizedBox` are both unacceptable, that's a separate cycle under Manager review.
- Any change to the Forui theme layer.
- Any change to the sort toggle, transaction card, details sheet, savings sheet, `_ViewModeToggle`, `_ErrorState`, `_addEntry`.
- Any change to `FinancialEntry`, `FinancialEntryRepository`, `financials_report_builder.dart`, gig data flow, RLS, migrations, or pubspec dependencies.
- Updating `lib/components/ui/README.md` call-site counts. Doc file remains off-limits.

---

# Cycle 8 Scope Expansion

> **This cycle authors a SQL migration file. It does NOT apply it.** The migration is a `supabase/migrations/*.sql` file that Tony applies manually on his own schedule. Manager, Engineer, and QA must never run `supabase db push`, `supabase migration up`, `psql`, or any equivalent apply command against production or a preview environment as part of this cycle. Authoring the file is an in-scope Engineer task; applying it is out of scope for every role in this pipeline. QA's static-review of the migration file (syntax, idempotency, RLS-impact reasoning) is the only migration-related check in the Verification Plan.

Cycle 8 is a scope-expansion revision landing on top of Cycles 1–7 (Cycles 1–6 uncommitted on the working tree per Cycle 6's Existing System Analysis, Cycle 7 committed to the branch at `22b38be` and pushed to PR #273). Cycle 6 remains the authoritative design for the date-filter control and its state shape; Cycle 7 remains authoritative for the details sheet's `_DetailRow` shape and the dropdown-`.sm` sizing. Cycle 8 does not touch either.

Branch state at plan-write time: local `feature/financials-transaction-cards` at commit `22b38be`; `GIT_OPTIONAL_LOCKS=0 git merge-base main HEAD` == `06bd222` == current `main` HEAD == current `origin/main` HEAD — **base is clean, no rebase needed** (confirmed by `git rev-parse` and `git merge-base`). Two untracked docs files present (`docs/features/bug/demo-session-cleanup-orphaned-anonymous-users/PR_BODY.md`, `docs/features/feature/financials-transaction-cards/PR_BODY.md`) — neither is in Cycle 8's diff scope; both are safe to ignore.

## Cycle 8 Problem Summary

Three coupled asks from Tony after testing the Cycle 7 tree:

**A. Details drawer** ([lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart)) — the primary rows should read, top to bottom, exactly:
1. Date
2. Description
3. Paid to
4. Purchased by
5. Needed for gig
6. Notes

Two implied consequences:
- Row 2 "Description" and row 6 "Notes" must be **two distinct fields**. Today only one free-text column exists on `financial_entries` (`description`, currently labeled "Notes" in the sheet per Cycle 1's rename). Cycle 8 introduces a new nullable `notes` text column via migration, keeps `description` for row 2 (label reverts to "Description"), and uses the new column for row 6 (label "Notes").
- The label previously rendered as "Paid by" (mapping `payerName`/`payor_name`) becomes "Purchased by"; the label previously rendered as "Paid To" (mapping `paidToName`/`paidToUserId`) becomes "Paid to" (sentence-case). The label previously rendered as "Related to gig" (mapping `gigId`) becomes "Needed for gig".

Footer restructure: today the sheet's `SheetFooter` has only `primaryLabel: 'Edit'` (rendered as a full-width filled rose button). Cycle 8 restructures it to `SheetFooter(primaryLabel: 'Done', onPrimary: () => Navigator.of(context).pop(), cancelLabel: 'Edit', onCancel: <existing edit flow>)` — an exact structural match to [lib/features/gigs/widgets/view_gig_drawer.dart line 491–496](lib/features/gigs/widgets/view_gig_drawer.dart#L491). Primary "Done" dismisses the sheet, secondary "Edit" opens the edit form via the existing callback body (which pops the details sheet then calls `showAddFinancialEntrySheet` — unchanged).

**B. Add/Edit form** ([lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart)) — the field order should read, top to bottom, exactly:
1. Type (existing `_TypePillRow`)
2. Amount (existing `CurrencyTextField` on `_amountController`)
3. Date (existing `_pickDate` outlined button)
4. Description (existing `_descriptionController`; **currently rendered below Paid To**, moves up to position 4)
5. Paid to (existing `_paidToUserId` `AppDropdown<String?>` + conditional `_paidToOtherController`)
6. Purchased by (existing `_payerController` `AppTextField`)
7. Needed for gig (NEW picker — tap to select from `gigProvider.allGigs`)
8. Notes (NEW `_notesController` `AppTextField` bound to the new `notes` column)

Three implied consequences:
- The current mode-conditional label swap on the two "payer"-adjacent fields — [line 618](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L618) (`_isIncome ? 'Payer (optional)' : 'Paid To (optional)'` on `_payerController`) and [line 627](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L627) (`_isIncome ? 'Paid To (optional)' : 'Paid By (optional)'` on `_paidToUserId`) — is **deleted**. Both fields render with fixed labels regardless of income/expense: `Paid to (optional)` for the member-dropdown field, `Purchased by (optional)` for the free-text field. The two fields also **swap render order** relative to today (currently `_payerController` renders first, `_paidToUserId` second; Cycle 8 renders `_paidToUserId` first at position 5, `_payerController` second at position 6).
- New "Needed for gig" picker at position 7 is a `Consumer(builder: ...)`-wrapped `AppDropdown<String?>` reading `ref.watch(gigProvider).allGigs`. Item list: a leading "No gig selected" (`value: null`) row plus one `DropdownMenuItem<String?>(value: gig.id, child: Text(gig.name))` per gig, sorted by `gig.date` descending (most recent first) to bias for the common case of linking an entry to a recent gig. Selection is persisted in a new `String? _selectedGigId` state field and threaded to `onSave` as `gigId`. Reuses the local-`Consumer` pattern already in the file (`_buildFixedBottomActions` uses the same pattern at [line 754–777](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L754) for the permissions read) — no `ConsumerStatefulWidget` conversion required.
- `_TypePillRow` becomes `StatefulWidget`, owns a `ScrollController` on its `SingleChildScrollView`, holds a `GlobalKey` on the currently-selected `_TypePill`, and calls `Scrollable.ensureVisible(_selectedKey.currentContext!, alignment: 0.5, duration: Duration.zero)` in a post-frame callback whenever the widget mounts or `widget.selected` changes. This scrolls the current selection into view when the sheet opens on an existing entry whose type sits off-screen to the right. **No stateful behavior beyond scroll positioning is added** — the widget continues to receive `selected: String` and callbacks via constructor params; parent state is unchanged.

**C. New `notes` column on `financial_entries`** — a nullable `TEXT` column added by a new migration file `supabase/migrations/20260909120000_add_notes_to_financial_entries.sql` (or Engineer's preferred `YYYYMMDDHHMMSS` timestamp for today). RLS impact: **none** — the existing `financial_entries` policies are column-agnostic (all four `financial_entries_select` / `financial_entries_insert` / `financial_entries_update` / `financial_entries_delete` policies from [20260601000000_create_financial_entries.sql](supabase/migrations/20260601000000_create_financial_entries.sql), the tightened Cycle 3 policies from [20260711081810](supabase/migrations/20260711081810_tighten_financial_entries_rbac.sql), the RBAC-hardened policies from [20260814120001](supabase/migrations/20260814120001_fix_financial_entries_select_rbac.sql), and the wrapped-`auth.uid()` variants from [20260823120000](supabase/migrations/20260823120000_wrap_rls_auth_functions.sql) — all gate on `band_id` membership via `check_band_member(band_id)` and never reference a specific data column). Adding a new column touches none of them; verified by grep across `supabase/migrations/**` for `notes|description` in policy bodies (zero column-level references). Backfill: not needed (nullable, defaults to NULL). Trigger impact: `trg_sync_gig_pay` reads only `entry_type`, `gig_id`, `amount_cents` (see [20260601000000 lines 92–120](supabase/migrations/20260601000000_create_financial_entries.sql#L92)) — unaffected. Constraint impact: `financial_entries_reimbursement_consistency` (from [20260803120000](supabase/migrations/20260803120000_add_reimbursement_fields_to_financial_entries.sql)) touches only reimbursement columns — unaffected.

Along with the column, the write path needs a `gigId` parameter that today doesn't exist on the general add/edit path: `FinancialEntryRepository.insertEntry` and `updateEntry` accept no `gigId` param and never write `'gig_id'` in their payload maps (verified by reading [financial_entry_repository.dart lines 236–286](lib/features/financials/financial_entry_repository.dart#L236) and [lines 288–336](lib/features/financials/financial_entry_repository.dart#L288)). Only the gig-tab-specific `insertGigExpenseEntry` and `upsertGigPayEntry` set `gig_id` today. The Feature Input flagged this all the way back in Cycle 1 as a known gap; Cycle 8 closes it. Both new params are optional (`String?` on the Dart side, nullable on the SQL side) and default to `null` when the user doesn't pick a gig — preserving the current "no gig" behavior for any caller who doesn't wire the new picker.

## Cycle 8 Interpretation Confirmation

Manager asked me to validate (or correct) three specific readings of Tony's asks. All three are **confirmed** as written, with one explicitly-noted UX trade-off on reading (2).

**(1) Description vs. Notes as two distinct fields.** Confirmed — Tony's exact words ("This means we need both a description and a notes field for both Income and expense records") plus his list showing rows 2 and 6 as separate entries force this. The `description` column stays (row 2 label: "Description" — reverts Cycle 1's "Description → Notes" rename); the new `notes` column is used for row 6 (label: "Notes"). Both are nullable and both render always-shown with an em-dash fallback in the details drawer (matches the existing "Paid to" / "Purchased by" always-shown pattern in Cycle 7).

**(2) "Paid to" and "Purchased by" as fixed, always-visible labels — Manager's reading confirmed.** Fixed labels regardless of income/expense type: **"Paid to" = the `paid_to_user_id` / `paid_to_name` member-selector field (existing `_paidToUserId` state, existing binding)**, **"Purchased by" = the `payor_name` free-text field (existing `_payerController` state, existing binding)**. No data-model change; no column renames. The mode-conditional label swap in the edit form (lines 618, 627) is deleted; both labels render as-is regardless of `_isIncome`. Rationale for confirming vs. flipping the reading:

- Cycle 1 renamed the details sheet's "Payer" (mapping `payerName`/`payor_name`) to "Paid by" — Cycle 8's rename "Paid by → Purchased by" is a direct textual chain applied to the same underlying field. Tony's ask ("Change 'Paid by' to 'Purchased by'") reads most naturally as continuing that chain.
- The alternative reading — swapping the two fields' bindings so "Paid to" maps `payor_name` and "Purchased by" maps `paid_to_user_id` — would produce cleaner semantics for expense entries ("Purchased by = the band member who made the purchase; Paid to = the vendor") but weaker semantics for income entries and would require the `_TransactionCard` title-resolution logic in `financials_screen.dart` to be re-checked and possibly flipped (since it references `payerName` for income titles today).
- Manager's reading preserves the existing data binding on both fields, which means (a) legacy entries render correctly with no code-driven data reassignment, (b) `_TransactionCard`'s title logic stays byte-identical (it references field bindings, not display labels), and (c) the PDF report's "Payer" / "Paid to" column headers (in [financials_report_builder.dart line 204–212](lib/features/financials/financials_report_builder.dart#L204)) stay untouched — the PDF is a separate UX context and Tony did not ask for report labels to change.
- **Accepted UX trade-off:** for income entries, calling `payor_name` "Purchased by" reads slightly oddly (an income entry's payer is the venue that paid the band, not a purchaser). The trade-off is Tony's directive; the plan does not silently override it. If Tony later dislikes the income-side reading, that's a separate follow-up cycle with a different design decision to make (add mode-conditional labels back, or rename columns, or split the fields).

**(3) Reuse an existing gig-picker paradigm.** No standalone "pick a gig from a list" widget exists in the codebase — confirmed by grep across `lib/**/*.dart` for `gig[ _]?[Pp]icker|selectGig|GigSelect|choose[ _]?gig|GigChooser|AppDropdown<Gig|List<Gig>.*items|allGigs\.map` (zero widget hits; `_showNavigationAppPicker` in `view_gig_drawer.dart` is the closest analogue, but it picks a `_NavigationApp` enum, not a gig, and uses `showAppBottomSheet<T>` which is a different UI paradigm than the field-embedded dropdown the edit form already uses for member selection). **Reuse decision: `AppDropdown<String?>` inside a `Consumer(builder: ...)` wrapper, matching the existing member-dropdown pattern at [add_financial_entry_bottom_sheet.dart line 632–658](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L632) verbatim** — same widget type, same nullable `String?` shape, same leading "No X selected" default option, same manual `for` loop over `.allGigs` for id → name lookup (not `firstWhereOrNull`, matches Cycle 1's `package:collection`-avoidance stance). This is the minimal-diff, minimal-new-paradigm choice: Engineer adds ~40 lines of picker widget code to an existing file and reuses the wrapper the file already imports (line 11: `import '../../../components/ui/app_dropdown.dart';`). **No new picker widget is created; no `showModalBottomSheet` variant is introduced.**

## Cycle 8 Root Cause

n/a — feature request. Confidence `HIGH` on the mechanical scope: every referenced widget, field, controller method, and repository method has been verified by reading the files on the current working tree at plan-write time. Confidence `HIGH` on the "Paid to" / "Purchased by" labeling reading, given the direct textual chain from Cycle 1's "Payer → Paid by" through Cycle 8's "Paid by → Purchased by" on the same field, and Tony's silence on the semantic trade-off.

## Cycle 8 Existing System Analysis (post-Cycle 7 baseline)

Current state at commit `22b38be` (Cycle 7's last commit), verified by reading each file:

- **`financial_entries` table** (from [20260601000000_create_financial_entries.sql lines 7–29](supabase/migrations/20260601000000_create_financial_entries.sql#L7)): columns `id`, `band_id`, `entry_type`, `category`, `amount_cents`, `is_income`, `description`, `entry_date`, `is_1099_expected`, `payor_name`, `paid_to_name`, `paid_to_user_id`, `disbursements`, `gig_id`, `created_by`, `created_at`, `updated_at`, plus later additions from subsequent migrations (`deposit_to_savings`, `deposit_to_savings_cents`, `is_reimbursed`, `reimbursed_date`). No `notes` column exists; verified by grep across `supabase/migrations/**` for `ADD COLUMN.*notes` (zero matches). RLS: four policies (SELECT / INSERT / UPDATE / DELETE) all gate on `check_band_member(band_id)` — column-agnostic, verified by reading each policy body.

- **`FinancialEntry` model** ([lib/features/financials/models/financial_entry.dart lines 55–159](lib/features/financials/models/financial_entry.dart#L55)): dataclass with fields matching the table (`payerName` aliased from `payor_name`). No `notes` field. `fromJson` and `toJson` both explicitly enumerate every column; adding a new column requires touching both.

- **`FinancialEntryRepository`** ([lib/features/financials/financial_entry_repository.dart](lib/features/financials/financial_entry_repository.dart)):
  - `insertEntry` (lines 236–286) — accepts `bandId`, `entryType`, `category`, `amountCents`, `entryDate`, `description`, `is1099Expected`, `payerName`, `paidToName`, `paidToUserId`, `disbursements`, `depositToSavings`, `depositToSavingsCents`. Builds a `payload` map with those columns; **no `gig_id` key, no `notes` key**. Cycle 8 adds both.
  - `updateEntry` (lines 288–336) — same param surface, same payload shape; **no `gig_id`, no `notes`**. Cycle 8 adds both.
  - `insertGigExpenseEntry` / `updateGigExpenseEntry` / `upsertGigPayEntry` — these DO write `gig_id` (they're the gig-tab-specific paths). **Not changed by Cycle 8** — they operate on a known `gigId` per their caller context (event editor) and don't participate in the general add/edit form flow.
  - `fetchEntriesForBand` — unchanged in Cycle 8 (SELECT `*` already returns any new columns automatically).

- **`FinancialsNotifier`** ([lib/features/financials/financials_controller.dart lines 134–228](lib/features/financials/financials_controller.dart#L134)): `addEntry` (lines 134–176) and `updateEntry` (lines 178–228) both take the same params as the repo methods they delegate to; both need the new `notes` and `gigId` params, threaded through to the repo call.

- **`add_financial_entry_bottom_sheet.dart`**:
  - `_SaveCallback` typedef (lines 30–43) declares the current param surface. Adding `notes` and `gigId` requires editing this typedef and every implementation.
  - Callers of `showAddFinancialEntrySheet`: three, verified by grep — `financials_screen.dart:50` (the `_addEntry` flow for creating a new entry), `financial_entry_details_bottom_sheet.dart:200` (the Edit callback from the details drawer). Both call sites thread `onSave` through to `notifier.addEntry` / `notifier.updateEntry` and forward every `_SaveCallback` param. Both need updating.
  - The mode-conditional label swap lives at lines 618 (`_payerController`'s label) and 627 (`_paidToUserId`'s label). Deleting both `? :` expressions and replacing with fixed strings is a two-line diff.
  - The current field order in `build()` is: Type pills → Amount → Date → **Payer/Paid To (`_payerController`)** → **Paid To/Paid By (`_paidToUserId`) [+ conditional `_paidToOtherController`]** → Description → 1099 toggle (conditional) → Disburse to Band (conditional) → Deposit to Savings (conditional). Cycle 8 reorders the middle block to: Type → Amount → Date → Description → **Paid to (`_paidToUserId` + conditional `_paidToOtherController`)** → **Purchased by (`_payerController`)** → **Needed for gig (NEW)** → **Notes (NEW `_notesController`)** → 1099 → Disburse → Deposit.
  - `_TypePillRow` (lines 1000–1035): stateless, wraps `SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row([...pills]))`. No auto-scroll behavior. Its parent (`_AddFinancialEntryBottomSheetState`) sets `_selectedTypeName` from `entry.category` in `initState` when editing, but the visible scroll position of the row stays at offset 0 — a selected pill sitting past the visible-width boundary is off-screen at open.

- **`financial_entry_details_bottom_sheet.dart`** (Cycle 7 state):
  - Rows are rendered in the order: Date → Related to gig → Paid by → Paid To → (conditional) Reimbursed → (conditional) Reimbursement → (conditional) Notes (currently maps `description`) → (conditional) Deposit to Savings. Cycle 8 reorders the primary six and appends the three conditional rows after.
  - `_DetailRow` (Cycle 7 shape, at [lines 262–304](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart#L262)) — side-by-side `Row(SizedBox(width: 68, label), SizedBox(width: Spacing.space8), Expanded(Column(value)))`. **Cycle 8 does not touch `_DetailRow`'s shape.**
  - Gig-lookup helper (lines 51–63) — manual `for` loop over `ref.read(gigProvider).allGigs`. Cycle 8 keeps this verbatim; only the label above changes (`'Related to gig'` → `'Needed for gig'`) and the row position changes (moves from #2 to #5).
  - `SheetFooter` (lines 185–239) — `primaryLabel: 'Edit', primaryIcon: AppIcons.edit, onPrimary: <edit-flow-callback>`. **No `onCancel` today**, so the footer renders as a single full-width filled rose button (per `SheetFooter.build` logic at [sheet_footer.dart line 68–79](lib/components/ui/sheet_footer.dart#L68), `onCancel: null` collapses the row into the primary alone). Cycle 8 restructures this to `SheetFooter(primaryLabel: 'Done', onPrimary: () => Navigator.of(context).pop(), cancelLabel: 'Edit', onCancel: <existing-edit-flow-callback>, primaryIcon: null)`. Icon is dropped from the primary because "Done" doesn't semantically fit an edit icon; secondary "Edit" is a text button per `SheetFooter`'s cancel-slot styling (`AppButtonVariant.text`, verified at [sheet_footer.dart line 74](lib/components/ui/sheet_footer.dart#L74)) and does not accept an icon.

- **`view_gig_drawer.dart`** (Cycle 8 baseline for the footer pattern): [line 491–496](lib/features/gigs/widgets/view_gig_drawer.dart#L491) renders `SheetFooter(primaryLabel: 'Done', onPrimary: () => Navigator.of(context).pop(), cancelLabel: 'Edit', onCancel: widget.canEdit ? () => _handleEdit(context) : null)`. Structural match target for Cycle 8's details-sheet footer. Cycle 8's `onCancel` guard is unconditional (no `canEdit`-equivalent gate at the details-sheet layer — the whole details sheet is already gated by the screen-level permission check), matching how Cycle 7 currently renders the primary Edit button unconditionally.

- **`gigProvider`** ([lib/features/gigs/gig_controller.dart](lib/features/gigs/gig_controller.dart)): `ref.watch(gigProvider).allGigs` returns `List<Gig>` for the active band. `Gig.id` (String) and `Gig.name` (String) and `Gig.date` (DateTime) are the three fields Cycle 8's picker needs. The whole list is already loaded whenever the financials screen is on-screen (verified in Cycle 1's Existing System Analysis) — no fetch, no repository change, no controller change.

- **Test files on the working tree at commit `22b38be`:**
  - `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart` — currently asserts the Cycle 7 labels ("Paid by", "Paid To", "Related to gig", "Notes" mapping `description`), the Cycle 7 footer (`primaryLabel: 'Edit'`, `primaryIcon: AppIcons.edit`), and the Cycle 7 row order. **Cycle 8 breaks every one of these assertions.** Must be updated in the same cycle to reflect the new labels ("Purchased by", "Paid to", "Needed for gig", "Description" + "Notes"), the new footer (`Done` primary + `Edit` cancel), and the new row order.
  - `test/features/financials/widgets/summary_header_test.dart` — untouched by Cycle 8 (no dependency on the changed labels or fields).
  - `test/features/financials/widgets/transaction_card_test.dart` — untouched by Cycle 8 (card title logic references field bindings, not labels — verified below).
  - `test/features/financials/widgets/transactions_list_header_test.dart` — untouched by Cycle 8.

- **`_TransactionCard._title` in `financials_screen.dart`** ([lines 816–830](lib/features/financials/financials_screen.dart#L816)): returns `entry.payerName` (fallback `entry.category`) for income, `entry.paidToName` (fallback `entry.category`) for expense. **Independent of the labeling change** — the underlying field bindings are unchanged in Cycle 8, so the card title logic stays byte-identical. Verified by tracing: Cycle 8's "Purchased by" label just re-labels the `payerName` field in the drawer/form, but `_TransactionCard` reads the field, not the label. **No `_TransactionCard` change needed.**

**No other files in `lib/` reference `notes` in a way that would conflict with the new column** — confirmed by grep across `lib/**/*.dart` for `entry\.notes|'notes'|\.notes\s*=|\bnotes:` (five matches, all pre-existing: two in `gig_pay_bottom_sheet.dart` referring to a `notes` param on gig-expense entries, two in `event_editor_drawer.dart` referring to gig notes, one in `financials_screen.dart` `notes:` param in a snackbar helper — none touch the `financial_entries` table's future `notes` column). Adding the new column and threading it through the general add/edit path does not collide with any of these.

## Cycle 8 Proposed Solution

Numbered by ask, mirroring the Problem Summary structure.

### (A) Details drawer

**Primary row order (all six always shown):**

1. `_DetailRow(label: 'Date', value: dateStr)` — unchanged binding.
2. `_DetailRow(label: 'Description', value: (entry.description?.trim().isNotEmpty ?? false) ? entry.description! : '—')` — reverts Cycle 1's `description → 'Notes'` label rename; always shown with `'—'` fallback (matches Cycle 7's always-shown pattern for the other free-text rows).
3. `_DetailRow(label: 'Paid to', value: (entry.paidToName != null && entry.paidToName!.isNotEmpty) ? entry.paidToName! : '—')` — sentence-case `t`; unchanged binding to `paidToName`.
4. `_DetailRow(label: 'Purchased by', value: (entry.payerName != null && entry.payerName!.isNotEmpty) ? entry.payerName! : '—')` — renamed from "Paid by"; unchanged binding to `payerName`.
5. `_DetailRow(label: 'Needed for gig', value: relatedToGigValue)` — renamed from "Related to gig"; the existing three-case resolution (`gigId == null → 'No'`; `gigId != null && match → 'Yes • $name'`; `gigId != null && no match → 'Yes'`) is preserved verbatim.
6. `_DetailRow(label: 'Notes', value: (entry.notes?.trim().isNotEmpty ?? false) ? entry.notes! : '—')` — new row bound to the new `notes` column; always shown with `'—'` fallback.

**Conditional / expense-only rows appended below (unchanged behavior — no re-ordering asked or done):**

7. Reimbursed (Yes/No) — expense-only.
8. Reimbursement detail — conditional on `isReimbursedExpense`.
9. Deposit to Savings — conditional on `depositToSavings == true`.

Rationale for keeping (7)/(8)/(9) in place: Tony's "row order should become" list specifies six primary rows; his silence on the conditional rows is not a delete directive. Cycles 1–7 established these three rows as expected UX for the applicable entry types; removing them would be silent scope creep in the deletion direction, and the semantic value they surface (was this expense reimbursed, when, to whom; how much of this income went to savings) is not captured anywhere else in the drawer. Preserve.

**Between-row spacing:** each `_DetailRow` continues to be separated by `const SizedBox(height: Spacing.space12)` — the current Cycle 7 pattern. No change.

**Footer restructure** (single `SheetFooter` call at the bottom of the sheet body):

```dart
SheetFooter(
  primaryLabel: 'Done',
  onPrimary: () => Navigator.of(context).pop(),
  cancelLabel: 'Edit',
  onCancel: () async {
    Navigator.of(context).pop();
    final notifier = ref.read(financialsProvider.notifier);
    final members = ref.read(membersProvider).members;
    final savingsTotalCents = ref
        .read(financialsProvider)
        .allEntries
        .where((e) => e.depositToSavings == true)
        .fold<int>(0, (sum, e) => sum + (e.depositToSavingsCents ?? 0));
    await showAddFinancialEntrySheet(
      context,
      initialEntry: entry,
      members: members,
      savingsTotalCents: savingsTotalCents,
      onSave: (/* all _SaveCallback params, including the new notes and gigId */) async {
        await notifier.updateEntry(/* threaded through */);
      },
      onDelete: () async {
        await notifier.deleteEntry(entry.id);
      },
    );
  },
)
```

- The primary "Done" callback is a bare `Navigator.of(context).pop()` — dismisses the sheet with no side effects.
- The secondary "Edit" callback is the **existing** primary callback body from Cycle 7 (moved from `onPrimary` to `onCancel`, unchanged internally except for the `notes` / `gigId` threading required by (C) below).
- `primaryIcon` is **not** set — "Done" doesn't take an icon; secondary cancel-slot buttons in `SheetFooter` don't accept an icon either. `AppIcons.edit` is fully removed from the sheet body (matches the `view_gig_drawer.dart` pattern which sets no icons on its footer).
- `SheetFooter` internally styles the primary as a filled rose `AppButton` and the cancel slot as `AppButtonVariant.text` — the visual distinction between "Done" (filled) and "Edit" (text) matches the gig drawer's read-only-then-edit affordance.

### (B) Add/Edit form

**New state fields on `_AddFinancialEntryBottomSheetState`:**

```dart
late final TextEditingController _notesController;
String? _selectedGigId;
```

Initialized in `initState`:
- Editing mode (`entry != null`): `_notesController = TextEditingController(text: entry.notes ?? '');` and `_selectedGigId = entry.gigId;`.
- Creating mode (`entry == null`): `_notesController = TextEditingController();` and `_selectedGigId = null;`.

Disposed in `dispose`: `_notesController.dispose();` alongside the other controllers.

**New field order in `build()` (middle block; other blocks unchanged):**

```
Type pills (_TypePillRow — see StatefulWidget change below)
SizedBox(space16)
CurrencyTextField (Amount)
SizedBox(space16)
Date label + OutlinedButton.icon(_pickDate)
SizedBox(space16)
Text('Description (optional)') + AppTextField(_descriptionController)  ← moved up from below
SizedBox(space16)
Text('Paid to (optional)') + AppDropdown<String?>(_paidToUserId) + conditional _paidToOtherController  ← fixed label, moved to position 5
SizedBox(space16 or space12 — see below)
Text('Purchased by (optional)') + AppTextField(_payerController)  ← fixed label, moved to position 6
SizedBox(space16)
Text('Needed for gig (optional)') + Consumer(builder: (context, ref, _) => AppDropdown<String?>(...))  ← NEW
SizedBox(space16)
Text('Notes (optional)') + AppTextField(_notesController)  ← NEW
SizedBox(space16)
Visibility(_isIncome, 1099 toggle)   [unchanged]
Disburse to Band (conditional, unchanged)
Deposit to Savings (conditional, unchanged)
```

**Label deletions (mode-conditional swap removed):**
- Line 627 today: `_isIncome ? 'Paid To (optional)' : 'Paid By (optional)'` → **`'Paid to (optional)'`** (fixed, sentence-case).
- Line 618 today: `_isIncome ? 'Payer (optional)' : 'Paid To (optional)'` → **`'Purchased by (optional)'`** (fixed).
- Adjacent comments `// Payer (income) / Paid To (expense)` (line 617) and `// Paid To (income) / Paid By (expense)` (line 625) get deleted with the ternaries.

**"Needed for gig" picker widget** (new; sits between the "Purchased by" text field and the "Notes" text field in the build tree):

```dart
Text(
  'Needed for gig (optional)',
  style: AppTextStyles.footnote.copyWith(color: context.colors.textSecondary),
),
const SizedBox(height: 6),
Consumer(builder: (context, ref, _) {
  final gigs = ref.watch(gigProvider).allGigs;
  final sortedGigs = List<Gig>.from(gigs)
    ..sort((a, b) => b.date.compareTo(a.date));

  String labelFor(String? id) {
    if (id == null) return 'No gig selected';
    for (final g in gigs) {
      if (g.id == id) return g.name;
    }
    return 'Unknown gig';
  }

  return AppDropdown<String?>(
    value: _selectedGigId,
    onChanged: (id) => setState(() => _selectedGigId = id),
    labelBuilder: labelFor,
    items: [
      DropdownMenuItem<String?>(
        value: null,
        child: Text(
          'No gig selected',
          style: AppTextStyles.callout
              .copyWith(color: context.colors.textMuted),
        ),
      ),
      ...sortedGigs.map(
        (g) => DropdownMenuItem<String?>(
          value: g.id,
          child: Text(g.name),
        ),
      ),
    ],
  );
}),
const SizedBox(height: Spacing.space16),
```

- Requires two new imports at the top of `add_financial_entry_bottom_sheet.dart`:
  - `import '../../gigs/gig_controller.dart';` — for `gigProvider`.
  - `import '../../../app/models/gig.dart';` — for the `Gig` type in `List<Gig>.from(gigs)` and the `.sort` comparator (`b.date.compareTo(a.date)`).
- Manual `for` loop over `gigs` for id → name lookup — matches Cycle 1's `package:collection`-avoidance stance; no `firstWhereOrNull`, no new dependency.
- Sort by `gig.date` descending places the most-recent gig at the top of the menu, biased for the common case (users linking a new expense to a recent gig).
- Sizing / styling inherits from `AppDropdown`'s `.md` default (per Cycle 7, `size` defaults to `FTextFieldSizeVariant.md` when unset). **No `size:` override on this call site** — the date-filter dropdown's `.sm` override in `_SummaryHeader` is a separate, header-specific concern.

**`_notesController` picker widget** (new; sits immediately after the gig picker):

```dart
Text(
  'Notes (optional)',
  style: AppTextStyles.footnote.copyWith(color: context.colors.textSecondary),
),
const SizedBox(height: 6),
AppTextField(
  controller: _notesController,
  textCapitalization: TextCapitalization.sentences,
  textInputAction: TextInputAction.done,
  hintText: 'e.g. Reimbursed via Venmo, receipt in email',
),
const SizedBox(height: Spacing.space16),
```

Matches the existing `_descriptionController` `AppTextField` shape (line 706–712) except for the hint text (which nudges the user toward "operational metadata" phrasing versus "primary detail" phrasing for the description).

**`_SaveCallback` typedef edit** (lines 30–43):

```dart
typedef _SaveCallback = Future<void> Function({
  required FinancialEntryType entryType,
  required String category,
  required int amountCents,
  required DateTime entryDate,
  String? description,
  String? notes,                       // NEW
  String? gigId,                       // NEW
  bool? is1099Expected,
  String? payerName,
  String? paidToName,
  String? paidToUserId,
  Map<String, int>? disbursements,
  bool? depositToSavings,
  int? depositToSavingsCents,
});
```

`_save()` (lines 388–425) passes the two new fields:

```dart
notes: _notesController.text.trim().isEmpty
    ? null
    : _notesController.text.trim(),
gigId: _selectedGigId,
```

**`_TypePillRow` StatefulWidget conversion (auto-scroll fix):**

```dart
class _TypePillRow extends StatefulWidget {
  const _TypePillRow({
    required this.labels,
    required this.selected,
    required this.isDeleteMode,
    required this.onSelect,
    required this.onAdd,
    required this.onToggleDelete,
    required this.onRemove,
  });

  final List<String> labels;
  final String selected;
  final bool isDeleteMode;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onToggleDelete;
  final ValueChanged<String> onRemove;

  @override
  State<_TypePillRow> createState() => _TypePillRowState();
}

class _TypePillRowState extends State<_TypePillRow> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _selectedPillKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(covariant _TypePillRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    final ctx = _selectedPillKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: Duration.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _TypePill(label: '+ Add', isSelected: false, isAddButton: true, onTap: widget.onAdd),
          const SizedBox(width: 8),
          _TypePill(
            label: widget.isDeleteMode ? 'Done' : 'Remove',
            isSelected: widget.isDeleteMode,
            isRemoveButton: true,
            onTap: widget.onToggleDelete,
          ),
          const SizedBox(width: 16),
          ...widget.labels.expand((label) {
            final isSelectedLabel =
                !widget.isDeleteMode && widget.selected == label;
            return [
              _TypePill(
                key: isSelectedLabel ? _selectedPillKey : null,
                label: label,
                isSelected: isSelectedLabel,
                showDeleteIcon: widget.isDeleteMode,
                onTap: widget.isDeleteMode
                    ? () => widget.onRemove(label)
                    : () => widget.onSelect(label),
              ),
              const SizedBox(width: 8),
            ];
          }),
        ],
      ),
    );
  }
}
```

- `_TypePill` stays unchanged (its existing `Key? key` param via `StatefulWidget`'s super handles the `GlobalKey` attachment).
- `Duration.zero` on the initial scroll avoids a visible jump when the sheet opens on an existing entry.
- The `didUpdateWidget` branch fires only when the parent state (`_selectedTypeName`) changes — user taps a chip in the currently-visible viewport; scroll re-centers on the tapped chip. Mild UX polish, not strictly required by Tony's ask (which spoke only to the on-open case), but the branch is cheap and prevents a stale scroll position after a mid-form add/remove.
- No new dependency; no change to the parent widget's constructor or state shape beyond the `TypePillRow` becoming stateful.

### (C) Data path (migration + model + repo + notifier + callback + call sites)

**Migration file** (new): `supabase/migrations/20260909120000_add_notes_to_financial_entries.sql`

```sql
-- Migration: Add notes column to financial_entries
-- Adds a nullable free-text `notes` column separate from the existing
-- `description` column. Existing entries have notes = NULL; no backfill.
-- RLS impact: none — the existing financial_entries policies gate on
-- band_id membership via check_band_member() and are column-agnostic.
-- Trigger impact: none — trg_sync_gig_pay reads only entry_type, gig_id,
-- amount_cents.
-- Constraint impact: none — the existing reimbursement-consistency
-- constraint touches only reimbursement columns.

ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS notes TEXT;
```

Idempotent (`IF NOT EXISTS`), no default, no NOT NULL constraint. Timestamp `20260909120000` matches today's date; Engineer may adjust the timestamp to their preferred format matching the sequence of the most recent migration on disk (last is `20260908194500_reduce_demo_session_ttl_to_15min.sql` per `ls supabase/migrations/`).

**`FinancialEntry` model edits** ([financial_entry.dart](lib/features/financials/models/financial_entry.dart)):

- Field: add `final String? notes;` after `description`.
- Constructor: add `this.notes,` after `this.description,` in the named-param list.
- `fromJson`: add `notes: json['notes'] as String?,` alongside the other `String?` columns.
- `toJson`: add `'notes': notes,` alongside `'description': description`.

**`FinancialEntryRepository.insertEntry` and `updateEntry`** ([financial_entry_repository.dart](lib/features/financials/financial_entry_repository.dart)):

- Both methods gain two new named params: `String? notes` and `String? gigId`, added after `description`.
- `insertEntry`'s payload map (line 259–275) adds:
  ```dart
  'notes': notes?.isEmpty == true ? null : notes,
  'gig_id': gigId,
  ```
- `updateEntry`'s payload map (line 305–319) adds the same two keys.
- No change to `insertGigExpenseEntry`, `updateGigExpenseEntry`, `upsertGigPayEntry`, `fetchEntriesForBand`, `fetchGigPayEntry`, `fetchGigExpenseEntries`, `deleteEntry` — those either don't use `notes` or already handle `gig_id` in their gig-specific way.

**`FinancialsNotifier.addEntry` and `updateEntry`** ([financials_controller.dart lines 134–228](lib/features/financials/financials_controller.dart#L134)):

Both methods gain two new named params (`String? notes`, `String? gigId`), threaded verbatim to the corresponding repository call. No state-shape change on `FinancialsState`; the loaded `entry` after the repo returns already contains the new fields via `FinancialEntry.fromJson`.

**Call sites of `showAddFinancialEntrySheet`** (both need updating in the same cycle):

1. **`_addEntry` in `financials_screen.dart`** (line 45–86) — the `onSave` callback body threads new `notes` and `gigId` params through to `notifier.addEntry`. Params are added to the destructured named-args block at line 57–65 and forwarded to `notifier.addEntry` at line 69–80.
2. **Edit callback in `financial_entry_details_bottom_sheet.dart`** (line 200–235) — the same threading pattern.

**`_TransactionCard` in `financials_screen.dart`** — untouched. Title-resolution logic (lines 816–830) references `entry.payerName` and `entry.paidToName` (field bindings), not the drawer/form's display labels. Verified above; noted here to prevent Engineer confusion.

**Empty-value display convention** in the drawer:
- Description and Notes: `'—'` fallback when empty (matches Cycle 7's "Paid to" / "Purchased by" always-shown pattern).
- Paid to and Purchased by: existing `'—'` fallback (unchanged from Cycle 7).
- Needed for gig: three-case value (`'No'` / `'Yes • <name>'` / `'Yes'`) unchanged from Cycle 7's logic.

## Cycle 8 Database Impact

**Migration authored, not applied.** Filed as `supabase/migrations/20260909120000_add_notes_to_financial_entries.sql` (or Engineer's preferred timestamp — must be lexically later than `20260908194500` to preserve migration ordering). Content is the single `ALTER TABLE ... ADD COLUMN IF NOT EXISTS notes TEXT;` shown in Proposed Solution → (C). No other DDL, no data manipulation, no policy change, no function/trigger change.

- **RLS**: unchanged. All four `financial_entries_*` policies gate on `check_band_member(band_id)` — verified in each migration touching those policies (`20260601000000`, `20260711081810`, `20260814120001`, `20260823120000`). None reference any specific column. Adding a new column requires no policy update.
- **`SECURITY DEFINER` functions**: none added; none modified. `check_band_member()` (which the policies call) is unchanged.
- **Triggers**: `trg_sync_gig_pay` reads only `entry_type`, `gig_id`, `amount_cents` — unchanged. Verified at [20260601000000 lines 92–120](supabase/migrations/20260601000000_create_financial_entries.sql#L92).
- **Constraints**: `financial_entries_reimbursement_consistency` (from `20260803120000`) touches only reimbursement columns — unaffected.
- **Indexes**: none added. The new `notes` column has no query pattern that would benefit from an index (never filtered on, never joined on, never aggregated over).
- **Backfill**: none needed. Existing rows have `notes = NULL`; the drawer's `'—'` fallback renders correctly; the edit form pre-fills the `_notesController` with `''` when `entry.notes == null`.
- **Application ordering vs. app deploy**: this cycle's DB change is **strictly additive** (new nullable column). The app deploy can precede or follow the migration apply, in either order, without breaking anything:
  - App deploy before migration: `insertEntry` / `updateEntry` payloads will include `'notes': ...` and `'gig_id': ...`. Supabase's PostgREST accepts unknown keys? **No — PostgREST rejects payloads with unknown columns.** So the app must not send a payload key for a column that doesn't exist yet. **Conclusion: migration must be applied BEFORE the app is deployed.** This is a genuine deploy-ordering constraint that Tony must observe manually.
  - App deploy after migration: safe. New column exists; app writes to it; existing entries still work because the column is nullable.

**Deploy-ordering note for Tony** (repeat in the Rollout Strategy section): apply the migration first, then deploy the app; not the reverse.

## Cycle 8 Flutter Architecture Changes

- **`FinancialEntry` model**: gains `final String? notes;` field. `fromJson` and `toJson` updated.
- **`FinancialEntryRepository.insertEntry` and `updateEntry`**: gain `String? notes` and `String? gigId` named params; payload maps gain `'notes'` and `'gig_id'` keys.
- **`FinancialsNotifier.addEntry` and `updateEntry`**: gain `String? notes` and `String? gigId` named params; threaded through to the repo.
- **`_SaveCallback` typedef** (`add_financial_entry_bottom_sheet.dart`): gains `String? notes` and `String? gigId` named params.
- **`_AddFinancialEntryBottomSheetState`**: gains `late final TextEditingController _notesController;` and `String? _selectedGigId;` fields; both initialized in `initState` and disposed in `dispose` (only `_notesController` needs disposal; `_selectedGigId` is a primitive).
- **`_TypePillRow`**: `StatelessWidget` → `StatefulWidget`; owns a `ScrollController` and a `GlobalKey`; `initState` and `didUpdateWidget` schedule a post-frame `Scrollable.ensureVisible` on the selected pill. No change to the widget's constructor surface.
- **`_FinancialEntryDetailsSheet.build`**: row order reshuffled; row labels renamed ("Paid by" → "Purchased by", "Paid To" → "Paid to", "Related to gig" → "Needed for gig", "Notes" reassigned from `description` to new `notes` column, "Description" reintroduced for `description`). Footer restructured to `Done` primary + `Edit` cancel. No change to the sheet's public entry point `showFinancialEntryDetailsSheet`.
- **`_AddFinancialEntryBottomSheetState.build`**: middle-block field order rewritten per Proposed Solution → (B). Two mode-conditional labels replaced with fixed labels. Two new fields (gig picker, notes text field) added.
- **No new providers, controllers, repositories, or models.**
- **No new imports beyond the two required in `add_financial_entry_bottom_sheet.dart`**: `../../gigs/gig_controller.dart` (for `gigProvider`) and `../../../app/models/gig.dart` (for the `Gig` type). No `package:collection` dep. No `package:forui/forui.dart` in feature code.

## Cycle 8 Files to Create

Two files:

- **`supabase/migrations/20260909120000_add_notes_to_financial_entries.sql`** — the migration file authored by this cycle. Content per Proposed Solution → (C). **Not applied by any role in this pipeline.**
- (No new production Dart source files.)

If the Verification Plan requires a new test file (see below), Engineer creates it as file #2. Not counted as a "production" file for Change Budget purposes.

## Cycle 8 Files to Modify

### [supabase/migrations/](supabase/migrations/) — new file only
See "Files to Create." Nothing else in `supabase/migrations/**` is touched.

### [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart)
- Add `final String? notes;` field (after `description`).
- Add `this.notes,` to the constructor named-param list.
- Add `notes: json['notes'] as String?,` to `fromJson`.
- Add `'notes': notes,` to `toJson`.

### [lib/features/financials/financial_entry_repository.dart](lib/features/financials/financial_entry_repository.dart)
- `insertEntry`: add `String? notes` and `String? gigId` named params after `description`; add `'notes': notes?.isEmpty == true ? null : notes,` and `'gig_id': gigId,` to the payload map.
- `updateEntry`: same param additions and same payload additions.
- No other method touched.

### [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart)
- `addEntry`: add `String? notes` and `String? gigId` params after `description`; pass through to `repo.insertEntry`.
- `updateEntry`: same.
- No state-shape change on `FinancialsState`. No new notifier method. No change to `setViewMode`, `setDateFilter`, `deleteEntry`, `refresh`, `build`, `_load`.

### [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart)
- Add imports: `import '../../gigs/gig_controller.dart';` and `import '../../../app/models/gig.dart';`.
- Update `_SaveCallback` typedef: add `String? notes` and `String? gigId` named params.
- Add `late final TextEditingController _notesController;` and `String? _selectedGigId;` fields on `_AddFinancialEntryBottomSheetState`.
- `initState`: initialize `_notesController` from `entry?.notes ?? ''`, initialize `_selectedGigId` from `entry?.gigId`.
- `dispose`: dispose `_notesController` alongside the other controllers.
- `_save`: pass `notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim()` and `gigId: _selectedGigId` to `widget.onSave`.
- `build`: reorder the middle-block widgets per Proposed Solution → (B). Delete the two mode-conditional label ternaries (lines 618, 627) and their preceding comment lines (617, 625); replace with fixed strings. Add the "Needed for gig" `Consumer`-wrapped `AppDropdown<String?>` block. Add the "Notes" `AppTextField` block.
- Convert `_TypePillRow` from `StatelessWidget` to `StatefulWidget` per Proposed Solution → (B); add `ScrollController`, `GlobalKey`, `initState`/`didUpdateWidget`/`dispose`, and `_scrollToSelected`.
- **Do not touch** `_TypePill` (individual pill widget), `_SegmentedToggle`, `_pickDate`, `_showAddTypeDialog`, `_populateSplits`, `_onDisburseToggle`, `_onDisbursementChanged`, `_shortName`, `_handleDelete`, `_buildFixedBottomActions`, or the Disburse/Deposit-to-Savings widget blocks in `build`.

### [lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart)
- Reshuffle row order in `_FinancialEntryDetailsSheet.build` per Proposed Solution → (A). Rename labels: `'Paid by'` → `'Purchased by'`, `'Paid To'` → `'Paid to'`, `'Related to gig'` → `'Needed for gig'`.
- Change the row currently labeled `'Notes'` (mapping `entry.description`) to `'Description'` (still mapping `entry.description`); remove its `if (entry.description != null && entry.description!.isNotEmpty) ...[]` conditional wrapper — replace with an always-shown row using `(entry.description?.trim().isNotEmpty ?? false) ? entry.description! : '—'` for the value.
- Add a new always-shown row labeled `'Notes'` mapping the new `entry.notes` column, using the same `'—'` fallback pattern.
- Restructure the `SheetFooter` call from `SheetFooter(primaryLabel: 'Edit', primaryIcon: AppIcons.edit, onPrimary: <edit-flow>)` to `SheetFooter(primaryLabel: 'Done', onPrimary: () => Navigator.of(context).pop(), cancelLabel: 'Edit', onCancel: <existing edit-flow, unchanged internally except for notes/gigId threading>)`. Remove `primaryIcon: AppIcons.edit`; do not add a `cancelIcon` (SheetFooter's cancel slot does not accept one — verified at [sheet_footer.dart line 74–79](lib/components/ui/sheet_footer.dart#L74)).
- Update the edit-flow callback body to thread `notes: ...` and `gigId: ...` into the `onSave` call and forward them to `notifier.updateEntry`.
- **Do not touch** `_DetailRow` (Cycle 7 shape — off-limits), `_TypeBadge`, `_Badge1099`, `_ReimbursedBadge`, `_buildReimbursementDetailLine`, the drag handle, the amount+badge top block, the `_ReimbursedBadge` above the divider, or the gig-lookup manual `for` loop (only the label above it changes).

### [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart)
- Update `_addEntry`'s `onSave` callback: add `notes` and `gigId` to the destructured named-args block; forward them to `notifier.addEntry`.
- **Do not touch** `_TransactionCard` (title-resolution logic references field bindings, not labels — verified), `_SummaryHeader`, `_TransactionsListHeader`, `_ViewModeToggle`, `_InlineLinkButton`, `_openCombinedReport`, `_showSavingsSheet`, `_SavingsSheet`, `_EmptyState`, `_ErrorState`, `_dateFilterLabel`, or the outer `_FinancialsScreenState.build` layout.

### [test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart](test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart)
Every existing assertion touching a renamed label or the changed footer must be updated:

- Any `find.text('Paid by')` → `find.text('Purchased by')`.
- Any `find.text('Paid To')` (exact-`Text` match) → `find.text('Paid to')` (sentence-case `t`).
- Any `find.text('Related to gig')` → `find.text('Needed for gig')`.
- Any `find.text('Notes')` (currently matching the row that showed `entry.description`) — either becomes `find.text('Description')` if the assertion is checking the row that maps `entry.description`, or stays as `find.text('Notes')` if a new case is added for the new `notes` column. Split into two assertions to cover both rows.
- The `'footer button reads "Edit", not "Edit Entry"'` case (line 253–260 in the current test file per grep) must be updated: assert that `find.text('Done')` finds exactly one widget (the primary), `find.text('Edit')` finds exactly one widget (the cancel), `find.text('Edit Entry')` finds none.
- The `'sheet renders exactly one Icon (the footer Edit icon)'` case (line 126–138) must be updated: the footer no longer has `primaryIcon: AppIcons.edit`; the primary "Done" button has no icon, the cancel "Edit" button has no icon. Assert that the icon count in the footer is **zero** (or update the count to whatever the drag-handle-plus-badge-plus-nothing-else total is — Engineer verifies by running the test). Rename the case to reflect the new expectation (e.g., `'sheet footer has no icons — Done primary and Edit cancel are both text-only'`).
- Add new cases (at least three):
  1. `'primary Done button dismisses the sheet via Navigator.pop'` — tap primary; verify sheet dismissed (`find.byType(_FinancialEntryDetailsSheet)` returns none, or the `Navigator` mock captures a `.pop` call).
  2. `'secondary Edit button opens the add sheet with the entry pre-filled'` — tap cancel; verify the add sheet appears with the entry's fields.
  3. `'Description and Notes render as separate rows for an entry with both fields populated'` — pump entry with `description: 'desc'` and `notes: 'notes'`; assert both `find.text('desc')` and `find.text('notes')` present; assert labels `'Description'` and `'Notes'` each find one widget.
  4. `'Notes row falls back to em-dash when entry.notes is null'` — pump entry with `notes: null`; assert `find.text('—')` present (with a scope-tightening `descendant of: 'Notes' row`, per how the file's existing fallback assertions are structured).
- If the test file already uses a fixture builder for `FinancialEntry`, add `notes: 'test notes'` (or similar) to the builder's optional params.

### [test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart](test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart) — new file
**Not present today** (no test file exists for the add/edit form; verified by `list_dir` on `test/features/financials/widgets/`). Cycle 8 introduces one to cover the new behaviors:

- `'field order matches spec: Type, Amount, Date, Description, Paid to, Purchased by, Needed for gig, Notes'` — pump the sheet in create mode; use `tester.getTopLeft` on each field's label `Text` widget to assert vertical ordering (label at row 1 has smaller `dy` than row 2, and so on).
- `'labels are fixed regardless of income/expense mode'` — pump in income mode; assert `find.text('Paid to (optional)')` and `find.text('Purchased by (optional)')` each find exactly one widget; tap the segmented toggle to switch to expense; assert both labels still present (not `'Paid To'` or `'Paid By'` or `'Payer'`).
- `'selecting a gig from the picker sets _selectedGigId and passes gigId through to onSave'` — pump with an overridden `gigProvider` containing one gig; open the gig dropdown, select the gig; tap Save; assert the captured `onSave` args contain `gigId: '<gig id>'`.
- `'notes field passes through to onSave.notes'` — pump; enter text into the Notes `AppTextField`; tap Save; assert captured `onSave` args contain the text.
- `'editing an entry with a mid-list type auto-scrolls the pill row so the selected type is visible'` — pump with an initialEntry whose `.category` is a type at position 5+ in the row (past the visible-width boundary at typical test viewport size); assert the selected pill's `Rect.center.dx` is within the visible viewport after the first frame — use `tester.pumpAndSettle()` + `tester.getRect(find.byKey(<selected pill's key>))` to measure.
- `'gig picker shows "No gig selected" as the default option when _selectedGigId is null'` — pump in create mode; assert the collapsed dropdown label reads `'No gig selected'`.

This file follows the same `ProviderScope`-override pattern as the existing test files under `test/features/financials/widgets/`, using a `_pump` helper that wires up `financialsProvider`, `gigProvider`, `membersProvider`, `activeBandProvider`, and `currentUserPermissionsProvider`. Given the sheet's complexity (multiple controllers, `Consumer`-wrapped picker, permissions read for the delete button), some scenarios may be exercised via a screen-level pump with a driver form rather than direct sheet pump. Engineer's call.

### [test/features/financials/widgets/summary_header_test.dart](test/features/financials/widgets/summary_header_test.dart), [transaction_card_test.dart](test/features/financials/widgets/transaction_card_test.dart), [transactions_list_header_test.dart](test/features/financials/widgets/transactions_list_header_test.dart)
- **No change.** No dependency on the changed labels, the changed fields, or the migration. Verified by grep across each file for `Paid by|Paid To|Related to gig|Notes|Description|payerName|paidToName|gigId|notes` (only `payerName` and `paidToName` appear in `transaction_card_test.dart`, and those references are through the fixture builder — they read the same `FinancialEntry` fields Cycle 8 leaves untouched).

## Cycle 8 Files Off-Limits

- [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart) — every widget except `_addEntry`'s `onSave` callback body is off-limits. Especially: `_TransactionCard._title` (field bindings unchanged; do not "align" the card title with the drawer's new labels; that's a separate design choice not asked for).
- [lib/features/financials/financials_pdf_preview_screen.dart](lib/features/financials/financials_pdf_preview_screen.dart) — no change.
- [lib/features/financials/financials_report_builder.dart](lib/features/financials/financials_report_builder.dart) — no change. The PDF column headers "Payer" and "Paid to" (from lines 204–212) stay as-is. They are semantically clearer than the new app labels and Tony did not ask for report labels to change.
- [lib/features/financials/widgets/gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart) — the gig-tab pay flow is a separate UX path; do not add a `notes` field or "Needed for gig" picker to it.
- [lib/features/events/widgets/gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart) — the gig-tab expense flow is a separate UX path with a known-gig context; do not add the picker.
- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) — unaffected. The gig-tab expense flow flushes through `insertGigExpenseEntry` / `updateGigExpenseEntry` which are Cycle 8-untouched.
- [lib/components/ui/app_dropdown.dart](lib/components/ui/app_dropdown.dart) — do not modify the wrapper. Cycle 8 uses it via existing API (no `size:` on the gig picker; picker follows the wrapper's `.md` default).
- [lib/components/ui/sheet_footer.dart](lib/components/ui/sheet_footer.dart) — do not modify. Cycle 8 uses `cancelLabel`/`onCancel` which are already supported.
- [lib/features/gigs/gig_controller.dart](lib/features/gigs/gig_controller.dart), [lib/app/models/gig.dart](lib/app/models/gig.dart) — read-only. No shape change.
- [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart)'s `FinancialsState` shape — unchanged. No new state field.
- Every existing `supabase/migrations/**` file — do not modify. The new migration is a NEW file, additive.
- `pubspec.yaml` — no new dependency (no `package:collection`, no anything else).
- Anything outside `lib/features/financials/`, `lib/features/financials/models/`, `lib/features/financials/widgets/`, `test/features/financials/widgets/`, and `supabase/migrations/` (new file only).

## Cycle 8 Change Budget

Numbers are net line delta *per file* after Engineer implements the Task Breakdown; QA diffs against these. Being off by >~40 lines in either direction on any single production file, or any non-zero delta on the off-limits files, is a plan-vs-implementation gap that should be flagged.

| File | Expected net Δ lines | Rationale |
| --- | --- | --- |
| `supabase/migrations/20260909120000_add_notes_to_financial_entries.sql` | **+12 to +18** | New file — comment header (~8 lines) + 2-line `ALTER TABLE` statement. |
| `lib/features/financials/models/financial_entry.dart` | **+4 to +8** | One field (~1 line), one constructor param (~1 line), one `fromJson` line, one `toJson` line, plus optional blank-line spacing. |
| `lib/features/financials/financial_entry_repository.dart` | **+6 to +12** | Two new params on `insertEntry` (2 lines) plus two new payload keys (2 lines); same for `updateEntry`. Formatting may push to +12. |
| `lib/features/financials/financials_controller.dart` | **+8 to +14** | Two new params on `addEntry` (2 lines) plus two forwarded to the repo (2 lines); same for `updateEntry`. |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | **+80 to +140** | Add 2 imports (+2). Update `_SaveCallback` typedef (+2). Add 2 state fields (+2), `initState` initialization (+3), `dispose` line (+1). Update `_save` to pass 2 new params (+3). Rewrite the middle-block widgets in `build`: move `Description` up (~0 net), rename 2 labels to fixed strings (−~4), swap the two rows' render order (~0 net), add the "Needed for gig" `Consumer` + `AppDropdown` block (~40 lines including sorting and label helper), add the "Notes" `AppTextField` block (~10 lines). Convert `_TypePillRow` from `StatelessWidget` to `StatefulWidget` with `ScrollController` + `GlobalKey` (~+45 lines: 5 lifecycle methods + `_scrollToSelected` helper + `build` rewrite that assigns `key` conditionally to the selected pill). Delete two mode-conditional label ternaries + 2 comments (~−6). |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | **+35 to +65** | Reshuffle 6 rows (~0 net; just reordering existing widgets), rename 3 labels (~0 net; string edits), reintroduce "Description" row for `entry.description` with fallback (~+5 lines vs. today's conditional), add new "Notes" row for `entry.notes` (+~5 lines), restructure `SheetFooter` from primary-only Edit to Done-primary + Edit-cancel (~+8 lines: adds `cancelLabel` + `onCancel` params, moves the edit-flow callback body from `onPrimary` to `onCancel`), thread `notes: ...` and `gigId: ...` into the edit-flow `onSave` and `notifier.updateEntry` (~+6 lines). Remove `primaryIcon: AppIcons.edit` (−1). |
| `lib/features/financials/financials_screen.dart` | **+4 to +8** | Update `_addEntry`'s `onSave` destructured args (+2) and forward them to `notifier.addEntry` (+2). |
| `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart` | **+40 to +100** | Update ~6 existing label/text assertions (~+6 lines net; string edits), rewrite the "footer button reads Edit" case for the new `Done` + `Edit` shape (~+10 lines), rewrite the "sheet renders exactly one Icon" case for the zero-icon footer (~+5 lines), add 3–4 new cases (`Done dismisses`, `Edit opens add sheet`, `Description and Notes render`, `Notes falls back to em-dash`) (~+50 lines). Update fixture to include `notes` (~+2 lines). |
| `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart` (new) | **+250 to +450** | New file — imports and `_pump` helper (~40 lines) plus 6 assertions (~40 lines each). Test file setup for `ProviderScope` overrides and `_FakeGigNotifier` / `_FakeFinancialsNotifier` scaffolding follows the same shape as the sibling test files under this folder. |
| Any other file | **0** | Off-limits (Cycle 8). |

- Expected new files: **2** (1 migration file, 1 test file).
- Expected deleted files: **0**.
- Expected new public classes / methods on production code: **0**. Every new widget/field/method inside modified files is private-to-file or private-to-class.
- Expected new dependencies (pubspec.yaml): **0**.
- Expected migration files: **1** (authored, not applied).

## Cycle 8 System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Financials → Screen | changed (in-scope, minimal) | Only `_addEntry`'s `onSave` params + forwarding are updated. `_TransactionCard` and all other screen widgets untouched. |
| Financials → Controller | changed (in-scope, minimal) | Two new params on `addEntry` and `updateEntry` — threaded through, no state-shape change. |
| Financials → Details Sheet | changed (in-scope) | Row order, labels, footer restructured. `_DetailRow` shape unchanged (Cycle 7 baseline). |
| Financials → Add/Edit Sheet | changed (in-scope) | Field order, labels, gig picker, notes field, `_TypePillRow` auto-scroll. |
| Financials → Repository | changed (in-scope, minimal) | Two new params on `insertEntry`/`updateEntry` + payload keys. |
| Financials → Model | changed (in-scope, minimal) | New `notes` field. |
| Financials → PDF Report | unaffected | Report reads `entry.description` and `entry.payerName` — unchanged column names. Report headers "Payer" / "Paid to" — unchanged. |
| Financials → Savings Sheet | unaffected | Reads only `depositToSavings`. |
| Gig-tab expense flow (event_editor_drawer + gig_expense_subview + insertGigExpenseEntry) | unaffected | Separate code path; no new params flow through it. Not asked to change. |
| Gig-tab pay flow (gig_pay_bottom_sheet + upsertGigPayEntry) | unaffected | Separate code path; not asked to change. |
| Gigs / Rehearsals / Setlists / Members / Auth / Routing / Notifications | unaffected | No cross-references, no init-order change, no session change. |
| Platforms (iOS / Android / macOS / Web) | uniformly affected | Shared Flutter UI only. `Scrollable.ensureVisible`, `AppDropdown`, and `SheetFooter` all render identically cross-platform. No `Platform.isIOS`/`kIsWeb` branch touched. |
| Supabase schema | changed (in-scope) | One new nullable column via new migration file. **Applied manually by Tony, not by this pipeline.** |
| Supabase RLS | unaffected | Existing `financial_entries` policies are column-agnostic; new column requires no policy update. |
| Supabase triggers / constraints | unaffected | `trg_sync_gig_pay` and `financial_entries_reimbursement_consistency` are unaffected. |
| `pubspec.yaml` | unaffected | No new dep. |
| `lib/components/ui/app_dropdown.dart` and `sheet_footer.dart` | unaffected (consumed) | Cycle 8 uses existing API. |

## Cycle 8 Regression Risk

**MEDIUM** (elevated from LOW compared to prior cycles). Justification:

- **First cycle in this feature that touches the DB schema.** Even though the schema change is strictly additive (new nullable column), a payload-shape mismatch during the app-deploy-before-migration window would cause `insertEntry` / `updateEntry` to fail with a PostgREST `PGRST204` (or similar) error, breaking the add/edit flow for every user until the migration lands. Mitigated by the Rollout Strategy → deploy ordering directive (migration first, then app).
- **Wire-format param addition on the repository.** Existing entries with `notes = NULL` are read correctly by `FinancialEntry.fromJson` (Dart's null-safety plus `as String?` handles the absent-key case gracefully — verified by tracing the current `deposit_to_savings_cents` handling at [line 129](lib/features/financials/models/financial_entry.dart#L129) which uses the same pattern). Regression here would come from JSON key typos (`notes` vs. `notes_text`, `gig_id` vs. `gigId`), which are trivially caught by the first `flutter analyze` + `flutter test` run.
- **`_TypePillRow` becomes stateful.** The lifecycle change (`ScrollController` disposal in `dispose`) is a genuine new resource to track. Missed disposal would leak a `ScrollController` per open-and-close of the sheet. Verified in the plan text; verified by QA via static diff review.
- **Labeling change breaks existing tests.** `financial_entry_details_bottom_sheet_test.dart` has multiple assertions on the old labels and footer shape; every failing assertion caught by `flutter test` before merge is the point.
- **UX ambiguity on "Purchased by" for income entries** (accepted trade-off per Interpretation Confirmation) — surfaced in the owner-run punch list so Tony can revisit if the reading feels wrong once he sees it in the app.

**Not-a-regression-class:**
- `_TransactionCard`'s title logic: byte-identical to Cycle 7; deliberate, verified in Existing System Analysis.
- Gig-tab flows: not touched; the parallel gig-expense and gig-pay paths continue to set `gig_id` via their own repo methods.
- PDF report: not touched; label semantics preserved.

## Cycle 8 Engineer Task Breakdown

Ordered, atomic. Each task leaves the app compiling once its dependencies are met. **Do not merge tasks or invent extra sub-steps.**

1. **Author the migration file.**
   - Create `supabase/migrations/20260909120000_add_notes_to_financial_entries.sql` with the exact content from Proposed Solution → (C). If the timestamp collides with a newer file already on disk, choose a lexically-later timestamp (e.g., `20260909130000`).
   - Do **not** apply the migration. Do not run `supabase db push`, `supabase migration up`, `psql`, or any equivalent. This is a static file authoring task only.

2. **Add `notes` to the `FinancialEntry` model.**
   - Edit `lib/features/financials/models/financial_entry.dart`: add `final String? notes;` after `description`, add the constructor param, add `notes: json['notes'] as String?,` in `fromJson`, add `'notes': notes,` in `toJson`.

3. **Add `notes` and `gigId` params to the repository.**
   - Edit `lib/features/financials/financial_entry_repository.dart`: `insertEntry` and `updateEntry` each gain `String? notes` and `String? gigId` named params (positioned after `description`), and each payload map gains `'notes': notes?.isEmpty == true ? null : notes,` and `'gig_id': gigId,`.
   - Do not touch `insertGigExpenseEntry`, `updateGigExpenseEntry`, `upsertGigPayEntry`, or any other method.

4. **Thread `notes` and `gigId` through the notifier.**
   - Edit `lib/features/financials/financials_controller.dart`: `addEntry` and `updateEntry` each gain `String? notes` and `String? gigId` params, passed to the repo call.
   - After Tasks 1–4, `flutter analyze` will flag broken call sites in `add_financial_entry_bottom_sheet.dart`, `financials_screen.dart`, and `financial_entry_details_bottom_sheet.dart` — expected, resolved in Tasks 5–7.

5. **Update `_SaveCallback` and the two call sites.**
   - Edit `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`: update `_SaveCallback` typedef to include `String? notes` and `String? gigId` named params. Add `late final TextEditingController _notesController;` and `String? _selectedGigId;` fields. Initialize in `initState` (`_notesController = TextEditingController(text: entry?.notes ?? '');`, `_selectedGigId = entry?.gigId;`) and dispose `_notesController` in `dispose`. Update `_save` to pass the two new params to `widget.onSave`.
   - Edit `lib/features/financials/financials_screen.dart`: add `notes,` and `gigId,` to `_addEntry`'s `onSave` destructured named-args block; forward both to `notifier.addEntry`.
   - Edit `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`: add `notes,` and `gigId,` to the edit-callback's `onSave` destructured args; forward to `notifier.updateEntry`. Leave the callback body's other lines untouched at this stage.

6. **Restructure the add/edit form layout.**
   - Edit `add_financial_entry_bottom_sheet.dart` `build`:
     - Add imports: `import '../../gigs/gig_controller.dart';` and `import '../../../app/models/gig.dart';`.
     - Move the "Description" `AppTextField` block up so it renders directly after the Date button.
     - Rename the label at line 618 to the fixed string `'Purchased by (optional)'`; delete the ternary. Delete the comment line above it (`// Payer (income) / Paid To (expense)`).
     - Rename the label at line 627 to the fixed string `'Paid to (optional)'`; delete the ternary. Delete the comment line above it (`// Paid To (income) / Paid By (expense)`).
     - Swap the render order of the two blocks so the `_paidToUserId` `AppDropdown` (and its conditional `_paidToOtherController`) renders BEFORE the `_payerController` `AppTextField`.
     - Add the "Needed for gig" `Consumer(builder: ...)` block per Proposed Solution → (B), positioned between the "Purchased by" field and the "Notes" field.
     - Add the "Notes" `AppTextField` block per Proposed Solution → (B), positioned between the gig picker and the 1099 toggle.
   - Do not touch the 1099 toggle, Disburse to Band, or Deposit to Savings blocks.

7. **Convert `_TypePillRow` to `StatefulWidget` with auto-scroll.**
   - Replace the `_TypePillRow` class in `add_financial_entry_bottom_sheet.dart` with the `StatefulWidget` + `_TypePillRowState` shape from Proposed Solution → (B). The parent widget's usage of `_TypePillRow(...)` is unchanged (same constructor surface, same callbacks).
   - Do not touch `_TypePill`, `_TypePillState`, or any of the pill styling.

8. **Restructure the details sheet.**
   - Edit `financial_entry_details_bottom_sheet.dart` `_FinancialEntryDetailsSheet.build`:
     - Reshuffle the primary rows to: Date → Description → Paid to → Purchased by → Needed for gig → Notes.
     - Rename labels: `'Paid by'` → `'Purchased by'`, `'Paid To'` → `'Paid to'`, `'Related to gig'` → `'Needed for gig'`.
     - Change the row that currently maps `entry.description` from the label `'Notes'` to `'Description'`. Remove its `if (entry.description != null ...) ...[]` conditional wrapper; render always-shown with `(entry.description?.trim().isNotEmpty ?? false) ? entry.description! : '—'` as the value.
     - Add a new always-shown row labeled `'Notes'` bound to `entry.notes` with the same `'—'` fallback.
     - Keep the conditional Reimbursed / Reimbursement / Deposit to Savings rows in place after the primary six.
   - Restructure the `SheetFooter` call:
     - Change `primaryLabel: 'Edit'` → `'Done'`.
     - Remove `primaryIcon: AppIcons.edit`.
     - Change `onPrimary: <edit-flow-callback>` → `() => Navigator.of(context).pop()`.
     - Add `cancelLabel: 'Edit'` and `onCancel: <the-original-edit-flow-callback>`.
     - Leave the internal body of the edit-flow callback unchanged from Task 5's edit (already threads `notes` and `gigId`).
   - If `AppIcons` is now unused in the file, remove the import — verify with grep in this file only.

9. **Update the existing details-sheet test file.**
   - Edit `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart` per Files to Modify → this file. Rewrite the footer / icon / label assertions; add the 3–4 new cases enumerated.

10. **Add the new add/edit form test file.**
    - Create `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart` per Files to Modify → new file. Follow the sibling test files' `ProviderScope` override pattern; wire up `financialsProvider`, `gigProvider`, `membersProvider`, `activeBandProvider`, `currentUserPermissionsProvider` with fakes.

## Cycle 8 Verification Plan

### Cycle 8 Tier 1 — pre-deploy (QA gate, mechanically executable)

QA cannot run the app or apply migrations. QA gate for APPROVED requires all of the following without either action:

1. `flutter analyze` clean (no new lints; existing baseline preserved). Includes the modified widgets, controller, repository, model, and both test files.
2. `flutter test` passes, including:
   - Updated `financial_entry_details_bottom_sheet_test.dart` (with new footer / label / row-order assertions).
   - New `add_financial_entry_bottom_sheet_test.dart` (6 new cases).
   - Existing `summary_header_test.dart`, `transaction_card_test.dart`, `transactions_list_header_test.dart` — must remain passing byte-identically (no fixture edits required per Files to Modify).
3. Static SQL review of the new migration file:
   - File exists at `supabase/migrations/YYYYMMDDHHMMSS_add_notes_to_financial_entries.sql` with lexically-later timestamp than `20260908194500`.
   - Contains exactly one `ALTER TABLE public.financial_entries ADD COLUMN IF NOT EXISTS notes TEXT;` statement (plus comment header).
   - No DDL beyond that single `ALTER TABLE`. No `DROP`, no `UPDATE`, no `CREATE FUNCTION`, no `CREATE TRIGGER`, no `GRANT`, no `REVOKE`, no `INSERT`. QA greps the file for each of those keywords and expects zero matches for anything other than `ALTER TABLE`.
   - Idempotent (`IF NOT EXISTS`).
   - Column type is `TEXT`, nullable, no default, no `NOT NULL`.
4. Ephemeral-DB apply-check on the migration (mechanical, headless — no production side effect):
   - Spin up a fresh Supabase local instance (or `pg_dump` clone into a scratch DB), apply all migrations up to and including the new one, and confirm `\d public.financial_entries` shows a `notes` column of type `text` nullable. This is the only DB-touching QA gate; runs against a scratch DB, never production. If the ephemeral instance is not available in QA's environment, this check is deferred to Tony's manual apply step (noted in the punch list).
5. Diff review confirms:
   - Off-limits files are byte-identical to `main` (or to their state at commit `22b38be`, whichever is relevant for the file). Specifically: `financials_pdf_preview_screen.dart`, `financials_report_builder.dart`, `gig_pay_bottom_sheet.dart`, `gig_expense_subview.dart`, `event_editor_drawer.dart`, `app_dropdown.dart`, `sheet_footer.dart`, `gig_controller.dart`, `gig.dart`, every pre-existing `supabase/migrations/**` file, `pubspec.yaml`.
   - Net line delta per modified file falls inside the Change Budget ranges.
   - `_TransactionCard._title` in `financials_screen.dart` is untouched (grep the diff for `_TransactionCard`/`_title` and confirm zero hunks).
   - `_DetailRow` in `financial_entry_details_bottom_sheet.dart` is untouched (grep for `class _DetailRow` and confirm zero hunks).
   - Both new imports (`gig_controller.dart` and `gig.dart`) are present in `add_financial_entry_bottom_sheet.dart`; no `import 'package:collection/collection.dart';` was added; no `import 'package:forui/forui.dart';` was added to any Cycle 8-touched feature file.
6. Sanity checks on the new migration file's expected RLS behavior (static reasoning, no DB apply required):
   - QA reads the current `financial_entries_select`, `financial_entries_insert`, `financial_entries_update`, `financial_entries_delete` policy bodies (across the four historical migrations that touch them) and confirms none reference a specific column name — only `check_band_member(band_id)` and `created_by`. This confirms the plan's "RLS impact: none" claim.
   - QA confirms `trg_sync_gig_pay`'s function body (in the create migration) reads only `entry_type`, `gig_id`, `amount_cents` — confirms "trigger impact: none."

**No `has_function_privilege` check required** — Cycle 8 introduces no new `SECURITY DEFINER` function.

### Cycle 8 Tier 2 — post-deploy

QA cannot run the app or drive a live instance. Tier 2 is scoped to what a static apply-time check can verify (Tony runs this manually as part of the migration apply). Tony runs these after applying `20260909120000_add_notes_to_financial_entries.sql` against production:

1. In the Supabase SQL editor, run `SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'financial_entries' AND column_name = 'notes';`. Expect one row with `text` / `YES`.
2. Run `\dt+ public.financial_entries` (or the equivalent). Confirm no unexpected column drops (a spot-check that the migration didn't accidentally include a `DROP`).
3. Read one existing `financial_entries` row via the Supabase client (either in the Table Editor or via `SELECT id, description, notes FROM public.financial_entries LIMIT 1;`). Confirm `notes` is `NULL` for the existing row (no backfill applied).
4. Deploy the new app build. Confirm the add/edit form's Save action produces a row with the new `notes` and `gig_id` values populated correctly (single spot-check).

### Cycle 8 Owner-run punch list (Tony runs at PR-test time — QA writes this into the PR body verbatim, does not attempt it)

QA cannot run the app. Tony walks the following in a preview build after applying the migration (adds to the Cycles 1–7 punch lists; does not replace them):

1. Apply the migration in production or the preview environment: `supabase db push --linked` (or Tony's equivalent apply command). Confirm the CLI reports success.
2. Sign in with a demo band containing at least one gig and open Financials → Add.
   Expected: field order top to bottom is Type / Amount / Date / Description / Paid to / Purchased by / Needed for gig / Notes (with 1099, Disburse, Deposit to Savings appearing below in the current-behavior positions when applicable to the mode).
3. Confirm the "Paid to" label reads `'Paid to (optional)'` (sentence-case `t`) and the "Purchased by" label reads `'Purchased by (optional)'`, regardless of whether the Income or Expense segmented toggle is selected. Toggle back and forth; labels must not change.
4. Tap the "Needed for gig" control.
   Expected: a Forui `FSelect` popup opens with "No gig selected" at the top and each band gig listed below in descending date order (most recent gig first).
5. Select a gig; tap Save; verify the new entry appears in the transaction list. Open its details drawer.
   Expected: the "Needed for gig" row reads `'Yes • <gig name>'`.
6. Enter a value in the "Notes" field of a new entry; tap Save. Open its details drawer.
   Expected: the "Notes" row shows the entered text; the "Description" row shows whatever was entered in the description field (or `'—'` if left blank).
7. Open an existing gig-linked entry (via the gig-tab pay flow) for editing.
   Expected: the "Needed for gig" picker pre-selects the linked gig by name; the "Notes" field is empty (legacy entries have no notes). Editing and saving preserves both fields.
8. Open an existing entry whose category type is at position 5+ in the type-pill row (or add several types via "+ Add" until the selection sits past the visible-width boundary at your device width). Open the entry for editing.
   Expected: the type-pill row is scrolled so the selected pill is visible (centered or near-centered) in the viewport when the sheet opens.
9. In the details drawer footer, tap "Done".
   Expected: the drawer dismisses; no navigation to any other screen.
10. Re-open the details drawer; tap "Edit" (the secondary text-button).
    Expected: the drawer dismisses and the add/edit sheet opens pre-filled with the entry's fields — same behavior as Cycle 7's Edit button.
11. Verify the "Paid to" and "Purchased by" labels in the details drawer read exactly those strings (case-sensitive). No `'Paid by'`, no `'Paid To'` (with capital T), no `'Payer'`.
12. Verify the "Needed for gig" row in the drawer reads exactly that (not `'Related to gig'`).
13. Verify the drawer's primary and cancel button strings: `'Done'` (primary, filled rose) and `'Edit'` (cancel, text-only).
14. **Semantic check on income "Purchased by":** create an income entry (e.g., Gig Pay with a Payer). Open its details drawer. Verify the "Purchased by" row shows the venue's name.
    Expected: the row displays correctly (the underlying data binding is unchanged), but Tony should confirm the label reads acceptably for the income case. If it feels wrong, note it in the PR — this is the accepted UX trade-off from Interpretation Confirmation (2), and a future cycle can reconsider.
15. Cross-platform visual check on iOS, Android, macOS, and web:
    - The gig picker's `FSelect` popup opens correctly on each platform (not clipped, not offset).
    - The `_TypePillRow` auto-scroll behavior works on each platform's viewport width (iPhone SE, iPad, narrow web, macOS full-window).
    - The details drawer's `Done` / `Edit` footer buttons are correctly sized and tappable on each platform.

## Cycle 8 QA Regression Areas

1. **Migration file is authored, not applied.** Any evidence in QA's environment or logs that a `supabase db push`, `supabase migration up`, or `psql` was run against ANY database (production, staging, local, preview) is a critical procedural violation.
2. **New column deploy ordering.** If the migration is not applied before the app deploy, the add/edit flow breaks with a payload-shape mismatch (PostgREST rejects unknown-column keys). The Rollout Strategy step 1 exists for this reason; Tony must observe the ordering. QA cannot verify this from static review; owner-run punch list step 1 makes it explicit.
3. **`_TransactionCard._title` untouched.** Any diff hunk touching `_title` in `financials_screen.dart` violates the plan's field-binding preservation stance and could re-align the card title with the new drawer label at the cost of legacy entry rendering.
4. **`_DetailRow` untouched.** Any diff hunk touching the `_DetailRow` class in `financial_entry_details_bottom_sheet.dart` violates Cycle 7's baseline (side-by-side label/value, `SizedBox(width: 68)` label column, `SizedBox(width: Spacing.space8)` gutter).
5. **Mode-conditional labels fully deleted.** Grep the edit form's diff for `? 'Paid To (optional)' :`, `? 'Paid By (optional)' :`, `? 'Payer (optional)' :` — all three ternary fragments must be absent from the post-diff file.
6. **No new dependency, no raw Forui import in feature code.** Standard hygiene check.
7. **Payload key exact-name check.** Grep the repo file for `'notes'` (must appear in both `insertEntry` and `updateEntry` payloads) and `'gig_id'` (same). Grep the model file's `fromJson` and `toJson` for the same. Any `'note'`, `'gigId'`, `'gig-id'` or other close-but-wrong variant is a wire-format defect.
8. **`_TypePillRow` disposes its `ScrollController`.** Grep the stateful class for `_scrollController.dispose()` inside `dispose()`.
9. **Gig picker sort order.** The picker must sort gigs by `gig.date` descending (most recent first). QA reads the picker code to confirm the comparator direction (`b.date.compareTo(a.date)`).
10. **Cycle 7 details-sheet baseline preserved.** `_DetailRow` shape, `size: FTextFieldSizeVariant.sm` on the summary-header dropdown, and Cycle 7's `financials_screen.dart` layout are all off-limits and unchanged.
11. **Existing three sibling test files pass byte-identically.** `summary_header_test.dart`, `transaction_card_test.dart`, `transactions_list_header_test.dart` — no fixture edits, no assertion edits. Any Cycle 8 diff touching them (other than through mechanical updates required by an analyzer-forced signature change on `FinancialsState`, which isn't happening — no state-shape change) is a scope violation.
12. **Semantic UX ambiguity flagged.** The punch list explicitly asks Tony to inspect the income-side "Purchased by" reading — QA does not gate on visual acceptance; Tony does.

## Cycle 8 Rollout Strategy

**Deploy ordering matters this cycle.** Same PR as Cycles 1–7 (#273). Commits added on top of the Cycle 7 tree.

1. **Tony applies the migration first** (`supabase db push --linked` against production, or the equivalent apply command). Confirm success in the Supabase logs.
2. **Tony deploys the new app build** via the standard `tools/build_*.sh` + `tools/deploy_web.sh` pipeline.
3. **Rollback plan** if the app deploy hits an unexpected issue:
   - **App-only rollback (migration stays)**: revert the PR, redeploy the previous app build. The `notes` column remains on the DB but no app writes to it; existing rows retain their `NULL` values. No data loss, no data corruption.
   - **Migration rollback (only if the migration itself corrupts the DB)**: not expected — the migration is `ALTER TABLE ... ADD COLUMN`, which is well-tested Postgres behavior. If needed, `ALTER TABLE public.financial_entries DROP COLUMN IF EXISTS notes;` reverts it; any `notes` values written between apply and rollback are lost, but the rest of the row survives.

No feature flag, no phased rollout — the schema and app changes are strictly additive and the risk of a bad interaction is low. Deploy ordering (migration → app, not the reverse) is the one non-obvious constraint Tony must observe.

## Cycle 8 Out of Scope

- Changing the underlying data bindings on `payer_name` / `paid_to_name` / `paid_to_user_id` (e.g., swapping which column "Paid to" or "Purchased by" reads from). Cycle 8 preserves bindings; labeling is the only change.
- Renaming the `payor_name` column to `payer_name` (or any other DB column). The Dart field is aliased to `payerName` in `fromJson`; leave the SQL column name alone.
- Renaming the PDF report's column headers ("Payer", "Paid to") to match the app's new labels. PDF is a separate UX context; not asked to change.
- Adding a `notes` column or "Needed for gig" picker to `gig_pay_bottom_sheet.dart` or `gig_expense_subview.dart`. Those flows have their own known-gig context and are out of scope.
- Backfilling `notes` from `description` for existing entries. `notes` starts null; users add new content over time.
- Adding a `gig_id` value to entries that don't have one yet, via a bulk "link to gig" flow. Users edit entries one at a time via the new picker.
- Persisting the type-pill row's scroll position across sheet dismiss/re-open. Auto-scroll fires on each open; scroll position resets between sessions.
- Adding a "Recent gigs only" filter to the gig picker, or grouping gigs by year in the popup. Simple flat list, sorted by date descending.
- Refactoring `_TransactionCard._title` to align with the new drawer labels. Card title stays byte-identical.
- Any change to `FinancialsState`, `FinancialsPdfPreviewScreen`, `financials_report_builder.dart`, `_TypePill` (individual pill widget), `_SegmentedToggle`, the Disburse-to-Band flow, the Deposit-to-Savings flow, or the 1099 toggle.
- Any change to auth, session, routing, init order, gig data flow, `bandFullStateProvider`, `get_band_full_state` RPC, or any RLS policy.
- Applying the migration. This pipeline authors migration files; Tony applies them.

