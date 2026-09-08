# ARCHITECT_PLAN — feature/financials-transaction-cards

## Feature Slug
`feature/financials-transaction-cards`

## Feature Title
Financials screen — replace transaction table with cards, add summary header

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

- [lib/features/financials/financial_entry_repository.dart](lib/features/financials/financial_entry_repository.dart) — no query changes; the gig-name resolution uses `gigProvider`, not a repository join. Modifying `fetchEntriesForBand` to add `select('*, gigs(name)')` would work under RLS (both tables are readable to active members) but produces a shape change on the returned JSON, forcing a `FinancialEntry.fromJson` change and adding a `gigName` field to the model — all avoided.
- [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart) — model stays byte-identical.
- [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart) — no state-shape change (no sort, no year selection).
- [lib/features/financials/financials_pdf_preview_screen.dart](lib/features/financials/financials_pdf_preview_screen.dart) — report generation unchanged.
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
- Additional sort axes beyond newest/oldest date (not amount, not category, not payer/payee) — the toggle is strictly two-state.
- Persisting sort preference across screen dismiss, band switch, or app restart — not asked for, adds a preferences dependency not otherwise in scope.
- Sort control in `_SavingsSheet` or the combined report — sort is scoped to the main transactions list only.
- Year-picker date-range control — resolved final: keep existing 4 chips.
- Tappable gig name in "Related to gig" row — resolved final: plain text, no navigation.
- Colored circular category icons on cards — Tony explicitly excluded.
- Adding `isReimbursed` toggle to `add_financial_entry_bottom_sheet.dart` — known pre-existing gap, tracked separately.
- Any change to `FinancialEntry` model, `FinancialEntryRepository`, or `FinancialsState` / `FinancialsNotifier`.
- Any change to `FinancialsPdfPreviewScreen`, `_SavingsSheet`, `_ViewModeToggle`, `_DateFilterRow`, `_FilterChip`, `_EmptyState`, `_ErrorState`.
- Any change to gig data flow, `bandFullStateProvider`, or the `get_band_full_state` RPC.
- Any RLS or migration work.
- Any pubspec change.
