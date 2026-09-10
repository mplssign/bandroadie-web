# ARCHITECT_PLAN — feature/financials-transaction-cards-reconciliation

## Feature Slug

`feature/financials-transaction-cards-reconciliation`

## Feature Title

Financials reconciliation — port PR #273's list-screen redesign onto the post-PR #274 baseline, drop PR #273's redundant migration, and unify the read-only detail sheet

## Problem Summary

Two independently-built financials features landed on parallel branches that
never saw each other:

- **PR #273** (`feature/financials-transaction-cards`, open, not merged): redesigned
  the Financials **list screen** (table → cards + summary header + tri-state
  date-filter dropdown + sort toggle) AND, in later cycles, redesigned the
  read-only **detail sheet** (no icons, side-by-side rows, reordered rows,
  "Purchased by" label, "Needed for gig" row, notes row, `Done`+`Edit` footer)
  AND redesigned the Add/Edit **form** (Cycle 8: field reorder, "Purchased by"
  rename, "Needed for gig" picker, notes field) AND authored a `notes`-only
  migration.
- **PR #274** (`transaction-drawer-redesign`, already merged to `main` at `0ec74ff`
  with Tony's explicit approval): redesigned the Add/Edit **form** into a
  sectioned layout (About / Payment Details / Distribution / Reimbursement /
  Notes) with contact+venue autocomplete, auto-balancing distribution math, a
  dedicated Reimbursement section including a new `reimbursement_method`
  column, and a `Needed for gig` picker — all more complete than PR #273's
  Cycle 8 form work. Its migration added BOTH `notes` and `reimbursement_method`.
  Its detail-sheet touch was minimal and IS a functional regression relative to
  PR #273's Cycles 1–11: still icon-per-row, still "Payer"/"Paid To"/"Description"
  labels, still stacked (not side-by-side) rows, still `Edit Entry` sole footer,
  still no gig-link row, and its `_buildReimbursementDetailLine` never mentions
  the new `reimbursement_method`.

Tony's explicit direction: keep PR #273's list-screen redesign, keep PR #274's
Add/Edit form redesign (authoritative), reconcile the read-only detail sheet
to combine PR #273's UX with PR #274's new schema, and drop PR #273's redundant
migration. This plan describes exactly which pieces of PR #273 to port, which
to drop, and what the reconciled detail sheet looks like — targeting a **fresh
branch off current `main`** (branch cut: `feature/financials-transaction-cards-reconciliation`),
not a rebase of PR #273.

## Root Cause

**Confidence: HIGH** — confirmed by direct file/diff inspection of both
`origin/main@0ec74ff` and `origin/feature/financials-transaction-cards@bb414ea`.

Two branches diverged from a common merge-base `06bd222` (2026-09-09) and
independently rewrote the same widget classes with different internal
structures. Diff summary vs. current `main`:

| File | PR #273 vs `main` | Ownership decision |
|---|---|---|
| `financials_screen.dart` | 999 lines changed (approx +414/−585) | **PR #273** wins — list redesign |
| `widgets/add_financial_entry_bottom_sheet.dart` | +206 net lines | **`main`** wins — PR #274's form is authoritative |
| `widgets/financial_entry_details_bottom_sheet.dart` | ±249 lines | **Reconciled fresh** — PR #273 UX + PR #274 schema (`reimbursement_method`) |
| `financials_controller.dart` | ±66 lines | **Partial** — take only Cycle 6 tri-state date-filter delta (~30 lines); `notes`/`gigId` param threading is already on `main` |
| `financials_pdf_preview_screen.dart` | ±16 lines | **Cycle 6 delete-only patch** — drop `customStartDate`/`customEndDate` params and `custom` switch case |
| `financial_entry_repository.dart` | +8 net lines | **`main`** wins — repo already threads `notes` end-to-end |
| `models/financial_entry.dart` | +4 net lines | **`main`** wins — model already has `notes` + `reimbursementMethod` + `gigId` |
| `supabase/migrations/20260909120000_add_notes_to_financial_entries.sql` | +12 lines (new file) | **Dropped** — 100% redundant with `20260909000000` on `main` |

The `notes` schema collision is confirmed: `main`'s
`20260909000000_add_transaction_drawer_fields_to_financial_entries.sql` adds
BOTH `notes TEXT` and `reimbursement_method TEXT` (plus tightens the
reimbursement consistency `CHECK`). PR #273's later-timestamped
`20260909120000_add_notes_to_financial_entries.sql` only adds `notes` with
`IF NOT EXISTS` — technically a no-op on any DB that ran the earlier migration
first, but a dead file that must not ship.

The list-screen call-site divergence is trivial: PR #274's only change to
`financials_screen.dart` (measured directly from `git diff 0ec74ff^..0ec74ff`)
was adding 5 params (`gigId`, `isReimbursed`, `reimbursedDate`,
`reimbursementMethod`, `notes`) to `_addEntry`'s `onSave` destructure and
pass-through. PR #273 also updated the same destructure (to add `notes` +
`gigId` only). The reconciled `financials_screen.dart` must destructure and
forward all 5 params (matching `main`'s current `_SaveCallback` typedef),
not PR #273's subset of 2.

## Existing System Analysis

**On `main` (post-PR #274, authoritative baseline):**

- [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart)
  (1689 lines): fully sectioned redesign with `_SectionCard`s for About,
  Payment Details, Distribution (income), Reimbursement (expense), Notes.
  `_SaveCallback` typedef (lines 38–57) carries `gigId`, `isReimbursed`,
  `reimbursedDate`, `reimbursementMethod`, `notes`. Reimbursement method
  captured via `_reimbursementMethod` dropdown + `_reimbursementMethodOtherController`
  free-text (persisted as the effective string, never the literal `'Other'`).
  **Off-limits — verbatim keep.**
- [lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart):
  regressed shape. Row order: Date → Payer → Paid To → (Reimbursement) →
  (Description) → (Deposit to Savings). Icon on every row, stacked
  label-above-value layout, `Edit Entry` sole footer. `_buildReimbursementDetailLine`
  produces `"Purchased ... · Reimbursed <date> to <payer>"` — does NOT
  include `reimbursementMethod`. **Rebuilt fresh in this plan.**
- [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart)
  (1200+ lines): still the pre-#273 shape — `_TableHeader`, `_EntryTableRow`,
  `_EntriesList`, `_HeaderCell`, `_BottomActionsRow`, `_OutlinedActionButton`,
  `_DateFilterRow` (4 chips), `_FilterChip`, `_measureText`, `_kAmountWidth`
  / `_kDateWidth` / etc. `_addEntry` `onSave` destructure already includes
  all 5 new params. **List body rebuilt to PR #273's card+summary shape;
  everything outside the list body preserved verbatim.**
- [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart):
  `FinancialDateFilter` has 4 cases (`allTime`, `thisYear`, `thisMonth`, `custom`),
  default `allTime`. `FinancialsState` has `customStartDate` / `customEndDate`
  fields + `clearCustomDates` copyWith flag. `setCustomDateRange` method
  exists. `addEntry` / `updateEntry` already thread all 5 new params. **Only
  the Cycle 6 tri-state pieces get deleted; `addEntry` / `updateEntry` bodies
  stay verbatim.**
- [lib/features/financials/financials_pdf_preview_screen.dart](lib/features/financials/financials_pdf_preview_screen.dart):
  constructor takes `customStartDate` / `customEndDate`; `_filterLabel`
  handles `FinancialDateFilter.custom`. **Only these three references get
  deleted.**
- [supabase/migrations/20260909000000_add_transaction_drawer_fields_to_financial_entries.sql](supabase/migrations/20260909000000_add_transaction_drawer_fields_to_financial_entries.sql):
  adds `notes` + `reimbursement_method`, tightens reimbursement consistency
  `CHECK`. **Verbatim keep, off-limits.**
- [test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart](test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart)
  (558 lines): PR #274's comprehensive tests over the sectioned form.
  **Verbatim keep, off-limits.**

**On `origin/feature/financials-transaction-cards@bb414ea` (source of the ported pieces):**

- `financials_screen.dart`: `_SummaryHeader` (inline `AppDropdown<FinancialDateFilter>`
  with `size: FTextFieldSizeVariant.sm`), `_TransactionsListHeader` (sort toggle),
  `_TransactionCard`, `_InlineLinkButton`, `_dateFilterLabel` free function.
  `_FinancialsScreenState` gains `bool _sortAscending = false;`. Empty-state
  build restructuring so the summary header renders above every non-error state.
- `financial_entry_details_bottom_sheet.dart`: side-by-side `_DetailRow`
  (`SizedBox(width: 148, label)` + 8px gap + `Expanded(Column(value))`, label
  `maxLines: 1, softWrap: false, overflow: visible`). Row order: Date →
  Description → Paid to → Purchased by → Needed for gig → Notes →
  (Reimbursed: Yes/No, expense only) → (Reimbursement compound line, if
  isReimbursed) → (Deposit to Savings, if applicable). No icons. Footer:
  `SheetFooter(primaryLabel: 'Done', cancelLabel: 'Edit')`. Uses
  `ref.read(gigProvider).allGigs` to resolve `gigId → gig name`.
- `financials_controller.dart`: tri-state `FinancialDateFilter { allTime,
  thisYear, thisMonth }`, default `thisYear`. No `customStartDate` /
  `customEndDate`. `_applyDateFilter` uses simple 3-case switch.
- `financials_pdf_preview_screen.dart`: constructor without `customStartDate` /
  `customEndDate`; `_filterLabel` switch without `custom` case.
- `add_financial_entry_bottom_sheet.dart` (Cycle 8 rewrite): **DO NOT PORT.**
  PR #274's version supersedes it.
- `financial_entry_repository.dart`, `models/financial_entry.dart`,
  `supabase/migrations/20260909120000_add_notes_to_financial_entries.sql`:
  **DO NOT PORT.** All redundant with `main`.
- Tests: `financial_entry_details_bottom_sheet_test.dart`,
  `summary_header_test.dart`, `transaction_card_test.dart`,
  `transactions_list_header_test.dart` — port and update to reconciled shape.
  PR #273's `add_financial_entry_bottom_sheet_test.dart` — **DO NOT PORT**
  (main's PR #274 version is comprehensive and matches the form we're keeping).

**Other in-flight collisions (checked via `gh pr list` + `git diff` against
every remote branch touching `lib/features/financials/**`):**

- **PR #261 `feature/band-gear-management`** — touches `financials_screen.dart`
  with a 4-line cosmetic patch (`textAlign: TextAlign.right` on two `_HeaderCell`s
  and two `_EntryTableRow` `Text` widgets). All four targets are inside the
  old table code that this reconciliation deletes. The change becomes a
  deleted-code merge conflict on PR #261's rebase against `main` after this
  reconciliation merges. **Flag for Manager/Tony**: PR #261 should either
  drop those 4 lines (they're cosmetic and the table is gone) or land before
  this reconciliation (then this reconciliation subsumes them). Not this
  plan's problem to fix, but Manager should know.
- **`origin/rescue/pre-feature-main-dirty`** — a rescue snapshot commit
  (`66e2c10`) predating both PR #273 and PR #274. Touches `financials_screen.dart`
  with an amount-column-width adjustment inside the old table. Also
  auto-obsoleted by this reconciliation. No action needed.
- No other open PRs touch `lib/features/financials/**` or the two involved
  migration files.

## Proposed Solution

**Branch strategy: fresh branch off current `main` (`0ec74ff`), NOT a rebase
of PR #273.** Branch cut: `feature/financials-transaction-cards-reconciliation`
(already created at this plan's write time).

Justification for the fresh-branch approach:

1. **Every file needing a change has an unambiguous winner** — either main's
   version wins verbatim (form, repository, model, migration, form test), or
   PR #273's version wins verbatim (list-screen redesign, tri-state
   controller delta, PDF preview delete), or it's a fresh reconciliation
   (detail sheet). There is no file where the correct answer is "merge PR
   #273's version with main's version"; a rebase would repeatedly force
   git's merge algorithm to attempt merges where a fresh branch just picks
   the winner directly.
2. **The dominant reconciliation risk is silently reverting PR #274's
   authoritative sectioned form.** Cycle 8 of PR #273 rewrote
   `add_financial_entry_bottom_sheet.dart` with its own (less complete)
   sectioned reorder. Rebasing would produce a large merge conflict in that
   file whose correct resolution is "throw away PR #273's entire hunk". A
   fresh branch never sees PR #273's version of that file, eliminating the
   class of mistake.
3. **PR #273's redundant migration file is naturally a "don't cherry-pick
   this" in a fresh branch**, vs. an explicit `git rm` step after rebase.
4. **QA review surface is minimized.** `git diff main...HEAD` on the fresh
   branch shows exactly the reconciled work; a rebased branch would show
   PR #273's cumulative history plus manual conflict resolution notes.
5. **The plan doc for PR #273** (`docs/features/feature/financials-transaction-cards/ARCHITECT_PLAN.md`)
   is 11-cycle-deep and prescribes work now unwanted (Cycle 8 form rewrite,
   notes migration). A fresh plan under a new slug is clearer for Engineer
   to implement literally.

### File-by-file plan

#### `lib/features/financials/financials_screen.dart` (rebuild list body)

Port PR #273 branch's final state, adjusted so the `_addEntry` `onSave`
destructure carries all 5 new params (`gigId`, `isReimbursed`,
`reimbursedDate`, `reimbursementMethod`, `notes`) — matching `main`'s current
`_SaveCallback` typedef, not PR #273's subset of 2.

Concrete deltas:

1. **Delete** the old table stack: `_EntriesList`, `_TableHeader`, `_HeaderCell`,
   `_EntryTableRow`, `_BottomActionsRow`, `_OutlinedActionButton`, `_DateFilterRow`,
   `_FilterChip`, `_measureText`, `_kAmountWidth` / `_kDateWidth` / `_kTypeWidth`
   / `_kCategoryWidth` / etc. column-width constants.
2. **Delete** the `import 'dart:ui' as ui;` line (was only used for `_measureText`).
3. **Add** `bool _sortAscending = false;` to `_FinancialsScreenState`.
4. **Add** private widgets at the bottom of the file (verbatim ports from
   PR #273 branch, byte-identical except imports adjusted):
   - `_SummaryHeader` (`ConsumerWidget`) — small-caps `TOTAL <mode>` label,
     total, inline `AppDropdown<FinancialDateFilter>` with `size:
     FTextFieldSizeVariant.sm`, count line, two `_InlineLinkButton` links
     ("View Savings Balance", "Generate Report").
   - `_TransactionsListHeader` (`StatelessWidget`) — sort toggle row with
     `"Newest first ▾"` / `"Oldest first ▾"` label. ≥48px tap target.
   - `_TransactionCard` (`StatelessWidget`) — card layout with title, category
     subtitle, date, amount, chevron; conditional `"Disbursed"`/`"Reimbursed"`
     badge with the rules from PR #273's Cycle 1 plan (never on the opposite
     type).
   - `_InlineLinkButton` (`StatelessWidget`) — text + trailing chevron with
     `onPressed`.
5. **Add** the `_dateFilterLabel(FinancialDateFilter)` free function (returns
   `'All time'` / `'This year'` / `'This month'`).
6. **Replace** the `Expanded(child: state.isLoading ? ... : state.error != null
   ? _ErrorState(...) : _EntriesList(entries: state.filteredEntries))` block
   in `_FinancialsScreenState.build` with PR #273's Cycle 5 empty-state
   restructuring — summary header + list header render above the content
   area in every non-error state (loading, empty, non-empty). List uses
   `ListView.separated` with `_sortAscending ? filtered.reversed.toList() :
   filtered` and `SizedBox(height: Spacing.space12)` separators.
7. **Update** `_openCombinedReport` — remove `customStartDate: state.customStartDate,`
   and `customEndDate: state.customEndDate,` from the `FinancialsPdfPreviewScreen(...)`
   call (companion to the constructor delete in step 8 below).
8. **Preserve verbatim**: `FinancialsScreen`, `_FinancialsScreenState.dispose`,
   `_FinancialsScreenState._addEntry` (both the destructure and the
   pass-through must forward all 5 new params — do NOT drop `isReimbursed`,
   `reimbursedDate`, `reimbursementMethod` from either), `_showSavingsSheet`,
   `_SavingsSheet` + `_SavingsSheetState` (confetti + count-up animation
   untouched), `_ViewModeToggle`, `_EmptyState`, `_ErrorState`.

Expected net delta: approximately **−585/+414 lines** (matches PR #273
branch's actual delta against merge-base).

#### `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` (rebuild fresh — reconciled)

Rebuild in full to match PR #273's Cycles 7–11 target UX, plus one small
extension for `reimbursement_method` (unique to this reconciliation, not
present in either PR).

Concrete shape:

**Header (above divider), unchanged from main and PR #273 branch:**

- Drag handle
- Amount (colored, with `+` on income, `−` on expense)
- `Wrap` of `_TypeBadge(entry.category)` + optional `_ReimbursedBadge`
- Optional trailing `_Badge1099`

**Details rows (below divider), reconciled order:**

Every row uses the side-by-side `_DetailRow` shape from PR #273 Cycle 7
(`SizedBox(width: 148, label)` + 8px gap + `Expanded(Column(value))`; label
style: `AppTextStyles.footnote` textMuted, `maxLines: 1, softWrap: false,
overflow: TextOverflow.visible`; value style: `AppTextStyles.callout`
textPrimary, wraps naturally). **No icons on any row.** 12px separator
between rows (`SizedBox(height: Spacing.space12)`).

Fixed order (both income and expense):

1. **Date** — `DateFormat('MMMM d, yyyy').format(entry.entryDate)`
2. **Description** — `entry.description` (or `'—'` if null/empty/whitespace)
3. **Paid to** — `entry.paidToName` (or `'—'`) — this preserves the existing
   semantic inversion documented in PR #274's plan
4. **Purchased by** — `entry.payerName` (or `'—'`)
5. **Needed for gig** — resolved from `entry.gigId` against
   `ref.read(gigProvider).allGigs`:
   - `gigId == null` → `'No'`
   - matched gig found → `'Yes • $gigName'`
   - `gigId != null` but no matching gig (e.g., deleted, or list not yet
     loaded) → `'Yes'`
6. **Notes** — `entry.notes` (or `'—'` if null/empty/whitespace)

Conditional rows (appear only when applicable, appended in this order after
Notes):

7. **Reimbursed** (expense only, always shown for expenses) — `entry.isReimbursed
   ? 'Yes' : 'No'`
8. **Reimbursement** (only when `entry.entryType == expense && entry.isReimbursed`)
   — compound line from `_buildReimbursementDetailLine(entry)`, **extended
   in this reconciliation** to append `" via $method"` when
   `entry.reimbursementMethod != null && entry.reimbursementMethod!.trim().isNotEmpty`.
   Full format: `'Purchased $entryDate · Reimbursed $reimbursedDate to $reimbursedTo[
    via $method]'`. Falls back to the existing 3-segment sentence when method
   is null.
9. **Deposit to Savings** (only when `entry.depositToSavings == true`) —
   `entry.formattedDepositToSavings ?? 'Yes'`

**Footer (below rows):**

`SheetFooter(primaryLabel: 'Done', onPrimary: () => Navigator.of(context).pop(),
cancelLabel: 'Edit', onCancel: <existing edit-launch handler>)`. The
`onCancel` (Edit) handler stays exactly as PR #273 wrote it: pops the sheet,
reads `financialsProvider.notifier` + `membersProvider` + `savingsTotalCents`,
calls `showAddFinancialEntrySheet` with the full 5-param `onSave`
destructure/pass-through — matching `main`'s `_SaveCallback` typedef, not
PR #273's subset of 2. **This is the one place where PR #273 branch's
`financial_entry_details_bottom_sheet.dart` needs a signature widening** —
it currently passes `notes` and `gigId` but not `isReimbursed` /
`reimbursedDate` / `reimbursementMethod`. Engineer must add all three
missing forwards.

**Imports:** matches PR #273 branch's imports (remove `app_icons.dart`, add
`gig_controller.dart`).

**Existing regression not fixed here** (flagged in Out of Scope): the
`_buildReimbursementDetailLine`'s `reimbursedTo` binding reads `entry.payerName`,
which maps to `payor_name` in the DB. In expense mode, `payor_name` binds to
the "Paid to" (vendor) label — NOT the member who paid out-of-pocket. So the
sentence semantically reads "Reimbursed <date> to <vendor>" instead of
"Reimbursed <date> to <member>". This is pre-existing on both `main` and PR
#273 branch — a real bug but out of scope for this reconciliation.

#### `lib/features/financials/financials_controller.dart` (surgical Cycle 6 delete)

Delete only, no additions:

1. **Change** `enum FinancialDateFilter { allTime, thisYear, thisMonth, custom }`
   → `enum FinancialDateFilter { allTime, thisYear, thisMonth }`.
2. **Remove** `final DateTime? customStartDate;` and `final DateTime? customEndDate;`
   fields from `FinancialsState`.
3. **Change** default `this.dateFilter = FinancialDateFilter.allTime` →
   `this.dateFilter = FinancialDateFilter.thisYear`.
4. **Remove** `this.customStartDate,` and `this.customEndDate,` from the
   `FinancialsState` constructor.
5. **Remove** `customStartDate` / `customEndDate` params and `clearCustomDates`
   flag from `copyWith`, and the corresponding assignment logic.
6. **Simplify** `_applyDateFilter` to a 3-case switch (delete the `custom`
   arm). Preserve the final `.toList()` and descending `.sort` unchanged.
7. **Remove** the `setCustomDateRange` method from `FinancialsNotifier`.
8. **Preserve verbatim**: `addEntry` and `updateEntry` bodies (they already
   thread all 5 new params correctly via `main`), `FinancialsNotifier.build`,
   `_load`, `_isMounted`, `setViewMode`, `setDateFilter`, `deleteEntry`,
   `financialsProvider` definition.

Expected net delta: approximately **−35/+3 lines**.

#### `lib/features/financials/financials_pdf_preview_screen.dart` (surgical Cycle 6 delete)

Delete only, no additions:

1. **Remove** `final DateTime? customStartDate;` and `final DateTime? customEndDate;`
   fields.
2. **Remove** the corresponding constructor params (`this.customStartDate,`
   and `this.customEndDate,`).
3. **Simplify** `_filterLabel` — delete the `case FinancialDateFilter.custom:`
   arm; hoist `final now = DateTime.now();` to the top of the getter (the
   `thisMonth` case already uses it).
4. **Adjust** casing of the `allTime` label from `'All Time'` to `'All time'`
   to match the summary-header dropdown label (Cycle 6 style).
5. **Preserve everything else verbatim** — this file is otherwise unchanged.

Expected net delta: approximately **−10/+2 lines**.

#### `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` — off-limits

Byte-identical to `main`. Do NOT touch.

#### `lib/features/financials/financial_entry_repository.dart` — off-limits

Byte-identical to `main`. Do NOT touch. `main`'s repository already threads
`notes`, `gig_id`, `is_reimbursed`, `reimbursed_date`, `reimbursement_method`
in the insert/update payloads.

#### `lib/features/financials/models/financial_entry.dart` — off-limits

Byte-identical to `main`. Do NOT touch. Model already has `notes`,
`reimbursementMethod`, `gigId`, `isReimbursed`, `reimbursedDate` fields with
`fromJson`/`toJson` wired.

#### `supabase/migrations/20260909000000_add_transaction_drawer_fields_to_financial_entries.sql` — off-limits

Verbatim keep. This is the authoritative migration.

#### `supabase/migrations/20260909120000_add_notes_to_financial_entries.sql` — NOT CREATED

PR #273 branch has this file. This reconciliation does NOT port it. The new
branch never has this file. **Do NOT create it.**

#### `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart` — off-limits

Byte-identical to `main` (PR #274's 558-line comprehensive form tests).
Do NOT touch.

#### `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart` — created fresh

Port PR #273 branch's version, updated for the reconciled detail sheet:

- All assertions from PR #273 branch's version.
- **Add** one new assertion for the reimbursement method extension: an entry
  with `entryType = expense`, `isReimbursed = true`, `reimbursedDate` set,
  and `reimbursementMethod = 'Zelle'` renders a `Reimbursement` row whose
  value string contains `'via Zelle'` (regex-match, not exact-match — the
  full sentence still starts with `'Purchased ...'`).
- **Add** one new assertion: same as above with `reimbursementMethod = null`
  produces a `Reimbursement` row whose value string does NOT contain `'via '`.
- **Add** one assertion: Edit button (`SheetFooter.cancelLabel`) tap triggers
  `showAddFinancialEntrySheet` with an `onSave` handler that, when invoked
  with a synthetic call carrying `isReimbursed: true, reimbursedDate: <date>,
  reimbursementMethod: 'Cash'`, forwards those three fields to the
  `FinancialsNotifier.updateEntry` call — regression guard against the
  signature-widening step above.

#### `test/features/financials/widgets/summary_header_test.dart` — created fresh

Port PR #273 branch's version verbatim (already targets the tri-state
dropdown, count, total, links). One micro-adjust: the label-under-thisYear
assertion should read `'This year'` (not `'Year 2026'`) — Cycle 6 shape.

#### `test/features/financials/widgets/transaction_card_test.dart` — created fresh

Port PR #273 branch's version verbatim.

#### `test/features/financials/widgets/transactions_list_header_test.dart` — created fresh

Port PR #273 branch's version verbatim.

## Database Impact

**No new migrations. No schema changes.**

`main`'s `20260909000000_add_transaction_drawer_fields_to_financial_entries.sql`
is the sole authoritative migration for the reconciled feature set. It
already provides `notes TEXT`, `reimbursement_method TEXT`, and the tightened
`financial_entries_reimbursement_consistency` `CHECK` constraint that
covers both fields.

**PR #273's `20260909120000_add_notes_to_financial_entries.sql` is dropped
entirely** — never ported, never committed on the reconciliation branch.

RLS: no change. `financial_entries` policies (last rewritten in
`20260823120000_wrap_rls_auth_functions.sql`) are column-agnostic; both
`notes` and `reimbursement_method` are covered by the existing `SELECT`/
`INSERT`/`UPDATE`/`DELETE` policies.

No new RPCs. No `SECURITY DEFINER` functions. No `REVOKE`/`GRANT` review
needed.

## Flutter Architecture Changes

**None.** State management continues via `FinancialsNotifier` (`Notifier` +
`NotifierProvider`). No new providers, no new repositories, no new services.

The one non-cosmetic state change — tri-state `FinancialDateFilter` +
default `thisYear` + removal of `customStartDate`/`customEndDate` — is
scoped to `FinancialsState` and its consumers within the financials
feature. No cross-feature ripple: `financialsProvider` is only referenced
externally by `lib/features/events/widgets/event_editor_drawer.dart`, and
that reference is `ref.invalidate(financialsProvider)` — safe against any
state-shape change.

## Files to Create

- `docs/features/feature/financials-transaction-cards-reconciliation/ARCHITECT_PLAN.md`
  (this document)
- `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart`
- `test/features/financials/widgets/summary_header_test.dart`
- `test/features/financials/widgets/transaction_card_test.dart`
- `test/features/financials/widgets/transactions_list_header_test.dart`

## Files to Modify

- `lib/features/financials/financials_screen.dart` (rebuild list body per
  PR #273 shape; preserve full 5-param `_addEntry` `onSave` destructure)
- `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`
  (rebuild fresh — PR #273 UX + reimbursement_method extension +
  Edit-callback signature widening to forward all 5 params)
- `lib/features/financials/financials_controller.dart` (Cycle 6 tri-state
  delete-only patch)
- `lib/features/financials/financials_pdf_preview_screen.dart` (Cycle 6
  delete-only patch)

## Files Off-Limits

- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` —
  PR #274's authoritative sectioned form
- `lib/features/financials/financial_entry_repository.dart` — already threads
  all 5 fields
- `lib/features/financials/models/financial_entry.dart` — already has all 5
  fields
- `supabase/migrations/20260909000000_add_transaction_drawer_fields_to_financial_entries.sql`
- `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart` —
  PR #274's authoritative form tests
- Everything under `supabase/migrations/` other than the explicit off-limits
  file above
- `pubspec.yaml`, `pubspec.lock`
- Every file outside `lib/features/financials/**` and `test/features/financials/**`
  except this plan doc

**Explicitly forbidden**: creating
`supabase/migrations/20260909120000_add_notes_to_financial_entries.sql` or
any migration adding `notes` or `reimbursement_method`.

## Change Budget

Expected net line delta per file (Engineer's actual diff will be measured
against these):

| File | Expected net delta | Expected new public classes/methods |
|---|---|---|
| `lib/features/financials/financials_screen.dart` | approximately −585/+414 (net −171) | 0 (all new widgets are `_`-prefixed private) |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | approximately −80/+140 (net +60) | 0 |
| `lib/features/financials/financials_controller.dart` | approximately −35/+3 (net −32) | 0 |
| `lib/features/financials/financials_pdf_preview_screen.dart` | approximately −10/+2 (net −8) | 0 |
| `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart` | +200 (new file) | 0 |
| `test/features/financials/widgets/summary_header_test.dart` | +140 (new file) | 0 |
| `test/features/financials/widgets/transaction_card_test.dart` | +180 (new file) | 0 |
| `test/features/financials/widgets/transactions_list_header_test.dart` | +130 (new file) | 0 |
| `docs/features/feature/financials-transaction-cards-reconciliation/ARCHITECT_PLAN.md` | this file only | n/a |

Expected new files: 5 (this plan + 4 test files).
Expected new public classes/methods: **0**.
Expected new dependencies: **0**.

## System Impact Map

- **Gigs** — unaffected. `financialsProvider` reads `gigProvider.allGigs`
  (already the case on `main` for the reimbursement flow); this
  reconciliation adds one more read site (detail sheet's `Needed for gig`
  resolver). Read-only, no write path.
- **Rehearsals** — unaffected.
- **Setlists** — unaffected.
- **Members** — unaffected. Detail sheet's Edit callback reads
  `membersProvider` exactly as `main` does today.
- **Auth** — unaffected. Zero touch on auth/session/PKCE/deep-link/routing
  code. Zero touch on the pinned init order.
- **Routing** — unaffected. `FinancialsScreen` push/pop path unchanged;
  detail sheet and add sheet routes unchanged.
- **Notifications** — unaffected.
- **Platforms**:
  - iOS: unaffected (no platform-conditional code touched).
  - Android: unaffected.
  - macOS: unaffected.
  - Web: unaffected. No Firebase/DeepLinkService/`--dart-define` touch.

## Regression Risk

**LOW.**

- No auth touch, no session touch, no routing touch, no init-order touch.
- No DB migration, no RLS change, no RPC change, no `SECURITY DEFINER` addition.
- No cross-feature provider signatures changed. The only state-shape change
  (`FinancialDateFilter` losing the `custom` case, `FinancialsState` losing
  `customStartDate`/`customEndDate`) is scoped to the financials feature and
  fully covered by static analysis after removing all `custom`/`customStartDate`/
  `customEndDate`/`setCustomDateRange` references.
- The one behavior change externally-visible: **default date filter flips
  from `allTime` to `thisYear`.** Users who previously saw all history by
  default now see only current year by default — they can still pick "All
  time" from the dropdown. This is Tony's Cycle 6 design decision, not a
  reconciliation-introduced regression, but should be called out on the PR
  body for pre-merge review.
- The `notes` column already exists on `main`; existing rows have `notes =
  NULL` and the reconciled UI treats null/empty as `'—'`. Zero data
  migration risk.
- The `reimbursement_method` column already exists on `main`; the reconciled
  detail sheet's new `via <method>` fragment only appears when
  `reimbursement_method` is non-null (existing rows have `NULL`, so nothing
  visible changes for them).

Elevated-attention areas (not risks, but places QA and Tony should walk in
the punch list):

- The Edit callback signature-widening in the detail sheet — Engineer must
  forward `isReimbursed`, `reimbursedDate`, `reimbursementMethod` in
  addition to what PR #273 branch already forwarded. Missing any of these
  three would silently null the column on save.
- Empty-state UI: the summary header + list header must render above the
  empty state, per Cycle 5 restructuring. Regression guard: assert that
  when `filteredEntries.isEmpty`, the tri-state dropdown is still visible
  and interactable.

## Engineer Task Breakdown

Ordered, atomic tasks. Engineer implements literally.

1. **Delete `custom` from `FinancialDateFilter` and drop `customStartDate` /
   `customEndDate` from `FinancialsState`.** In
   `lib/features/financials/financials_controller.dart`, apply the 8-point
   surgical patch under "File-by-file plan → `financials_controller.dart`".
   Leave `addEntry`/`updateEntry`/`deleteEntry`/`_load` bodies unchanged.
   Confirm the file still compiles (there will be temporary breaks in
   `financials_screen.dart` and `financials_pdf_preview_screen.dart` — those
   get fixed in the next steps).
2. **Drop `customStartDate` / `customEndDate` from `FinancialsPdfPreviewScreen`.**
   In `lib/features/financials/financials_pdf_preview_screen.dart`, apply
   the 5-point surgical patch under "File-by-file plan →
   `financials_pdf_preview_screen.dart`". After this task, both this file
   and `financials_controller.dart` should compile cleanly on their own;
   only `financials_screen.dart` still has broken references (`state.customStartDate`,
   `_DateFilterRow`, `_FilterChip`, `FinancialDateFilter.custom`, etc.),
   which is fine — task 3 handles it.
3. **Rebuild the list body of `financials_screen.dart`.** Apply the 8-point
   patch under "File-by-file plan → `financials_screen.dart`". Port
   `_SummaryHeader`, `_TransactionsListHeader`, `_TransactionCard`,
   `_InlineLinkButton`, and `_dateFilterLabel` verbatim from
   `origin/feature/financials-transaction-cards`. Delete the old table
   stack. Restructure `_FinancialsScreenState.build` per Cycle 5. Preserve
   `_addEntry`'s full 5-param destructure and pass-through (do NOT reduce
   to PR #273 branch's 2-param subset). After this task, `flutter analyze
   lib/features/financials/` should be clean.
4. **Rebuild `financial_entry_details_bottom_sheet.dart` fresh.** Follow
   the "Details rows (below divider), reconciled order" specification
   above exactly:
   - Delete `import 'app_icons.dart'`; add `import '../../gigs/gig_controller.dart'`.
   - Replace `_DetailRow` with the side-by-side PR #273 Cycle 7 shape
     (label width 148, no icon).
   - Emit rows in exact order: Date, Description, Paid to, Purchased by,
     Needed for gig, Notes, then conditional: (Reimbursed, expense only),
     (Reimbursement compound line, if `isReimbursedExpense`), (Deposit to
     Savings, if `entry.depositToSavings == true`).
   - Extend `_buildReimbursementDetailLine` to append `' via $method'` when
     `entry.reimbursementMethod != null && entry.reimbursementMethod!.trim().isNotEmpty`.
     Do not modify the pre-existing 3-segment sentence otherwise.
   - Replace the footer with `SheetFooter(primaryLabel: 'Done', onPrimary:
     () => Navigator.of(context).pop(), cancelLabel: 'Edit', onCancel:
     <edit-launch handler>)`.
   - **Widen the Edit-launch handler's `onSave` destructure and pass-through**
     to include all 5 new fields: `gigId`, `isReimbursed`, `reimbursedDate`,
     `reimbursementMethod`, `notes` — matching `main`'s `_SaveCallback` typedef.
5. **Add widget test files.** In `test/features/financials/widgets/`, create
   the four fresh test files listed above. Port assertions from PR #273
   branch verbatim except where the reconciled shape differs (specifically:
   `summary_header_test.dart` `'This year'` label case; the two new
   `reimbursement_method` assertions and one Edit-signature-forwarding
   assertion in `financial_entry_details_bottom_sheet_test.dart`).
6. **Verify off-limits files are byte-identical to `main`.** Run
   `git diff main -- lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart
   lib/features/financials/financial_entry_repository.dart
   lib/features/financials/models/financial_entry.dart
   supabase/migrations/
   test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`
   — must show zero output. This is the anti-regression guard against
   accidentally reverting PR #274's form work.
7. **Verify PR #273's redundant migration file is NOT present on the
   branch.** Run `test ! -f supabase/migrations/20260909120000_add_notes_to_financial_entries.sql
   && echo OK`.
8. **Run `flutter analyze` and `flutter test` locally.** Both must pass
   with zero new lint warnings. If any new lint appears, fix it before
   handing off to QA — QA's `flutter analyze` gate is intolerant of new
   warnings.

## Verification Plan

### Tier 1 — pre-deploy (QA gate, mechanically executable)

QA cannot launch, build, or drive a running instance of the app. QA's gate
is limited to what's mechanically executable without a running app.

**QA gate for APPROVED requires all of the following to pass:**

1. **`flutter analyze`** clean on the branch — zero new warnings vs. `main`.
2. **`flutter test`** passes end-to-end, including all four new test files
   listed above, without touching or breaking any existing test.
3. **Off-limits diff review** — `git diff main -- <off-limits paths>` (per
   Task 6 above) must return zero output. Any non-empty diff on the
   off-limits set is an automatic Warning/Critical against this plan.
4. **Migration presence check** — `test ! -f supabase/migrations/20260909120000_add_notes_to_financial_entries.sql`
   must succeed (file must not exist on the branch).
5. **Static SQL review** — the two migration files under `supabase/migrations/`
   affected by this feature set (`20260601000000_create_financial_entries.sql`
   and `20260909000000_add_transaction_drawer_fields_to_financial_entries.sql`)
   must be byte-identical to `main`. `git diff main -- supabase/migrations/`
   must return zero output.
6. **Change-budget review** — Engineer's actual diff sizes per file are
   within ±20% of the "Change Budget" table above. Larger deviations flag
   Warning; deviations >50% flag Critical.
7. **Signature-forwarding review (specific)** — grep `financial_entry_details_bottom_sheet.dart`
   for `isReimbursed:` — it must appear in BOTH the destructure and the
   `notifier.updateEntry(...)` pass-through of the Edit-launch handler.
   Same for `reimbursedDate:` and `reimbursementMethod:`. If any of the
   three is missing from either half, this is Critical — silently drops
   fields on save.

**Owner-run punch list (Tony walks in a preview build — QA writes this into
the PR body verbatim, does not attempt it):**

QA cannot run the app. Tony walks the following in a preview build.

1. **Sign in with a demo band that has both income and expense entries; open
   Financials.**
   Expected: card list renders (no horizontal-scroll table); summary header
   shows `TOTAL <mode>` + total + tri-state dropdown labeled `This year` +
   count line + two chevron links (`View Savings Balance`, `Generate
   Report`).
2. **Toggle Income ↔ Expenses.**
   Expected: label + color of total switch (green ↔ red), count updates,
   list updates. Dropdown selection persists across the toggle.
3. **Change the date-filter dropdown between `All time`, `This year`, `This
   month`.**
   Expected: total, count, and card list update; sort control does not
   reset; report on next tap of `Generate Report` uses the selected filter.
4. **Tap the sort control (`Newest first ▾`).**
   Expected: label flips to `Oldest first ▾`; list re-sorts in one paint;
   summary header total/count/date-range do NOT change. Tap again → label
   and list return to original state.
5. **Pop back to Home and re-open Financials.**
   Expected: sort control resets to `Newest first ▾` (not persisted). Date
   filter dropdown resets to `This year` (Cycle 6 default — this is a new
   behavior vs. today's `All Time`; call out on PR body).
6. **Tap `View Savings Balance`.**
   Expected: existing `_SavingsSheet` opens (unchanged animation).
7. **Tap `Generate Report`.**
   Expected: existing `FinancialsPdfPreviewScreen` opens with combined
   report. Sort order in the report unchanged regardless of on-screen sort
   toggle. Report title reflects the tri-state filter (`All time` / `This
   year` / this-month formatted date).
8. **Tap a transaction card.**
   Expected: detail sheet opens. **Icons ARE NOT present on any row.**
   Row order top-to-bottom: Date, Description, Paid to, Purchased by,
   Needed for gig, Notes, and (expense only) Reimbursed. Labels use
   fixed-width column, values wrap. Footer has TWO buttons: `Done`
   (primary) and `Edit` (cancel-slot).
9. **On a reimbursed expense entry with `reimbursement_method = 'Zelle'`
   set via the Add form:** verify the `Reimbursement` row's value contains
   `via Zelle`. On a reimbursed expense with method `null`: verify the
   `Reimbursement` row's value does NOT contain `via`.
10. **On an entry with `gigId` pointing to an existing gig:** verify
    `Needed for gig` row reads `Yes • <gig name>`. On an entry with `gigId
    = null`: reads `No`. On an entry with `gigId` set but no matching gig
    in the loaded list: reads `Yes` (no bullet, no name).
11. **From details, tap Edit.**
    Expected: Add sheet opens pre-filled — no regression on the edit flow.
    Modify the Reimbursement fields (toggle on, pick a method, pick a
    date). Save. Return to details sheet.
    Expected: detail sheet reflects the updated method (no `via` fragment
    if method was cleared, `via <method>` if set).
12. **Add a new expense** with `Paid to = "Test Vendor"`, verify a new
    card appears at the correct sort position with title `Test Vendor`.
    Total updates by the entered amount; count increments.
13. **Delete the entry via detail sheet Edit → Delete flow.**
    Expected: card disappears, total decrements, count decrements.
14. **Open Financials on a fresh band with zero entries.**
    Expected: `_EmptyState` shows AS BEFORE, AND the summary header + list
    header are still visible above the empty state (Cycle 5 restructuring).
    Tri-state dropdown is interactable even with zero entries.
15. **On iOS, Android, macOS, and web builds:**
    - No horizontal scroll on the transaction list at narrow widths.
    - Detail sheet's fixed-width label column does not clip long labels
      like `Needed for gig` (width 148 chosen to fit the longest reconciled
      label without wrap).
    - Chevron links wrap gracefully at narrow widths.

### Tier 2 — post-deploy

**not applicable** — no DB migration ships with this feature, no RPC
change, no RLS change, no edge function change, no external API change.
Nothing to validate against production data after apply.

## QA Regression Areas

Beyond the mechanical gate above, QA must call attention to the following
areas in the PR body punch list so Tony walks them:

1. **Default date filter change** — `main` today defaults to `All Time`;
   this reconciliation defaults to `This year`. Call out explicitly.
2. **Reimbursement compound line** — verify the extended `_buildReimbursementDetailLine`
   handles the `null` method case identically to today (no `via`
   fragment), the empty-string case identically to null (no `via` fragment
   — because trim().isNotEmpty guard), and the non-null case appends `via
   <method>` with a leading space.
3. **Pre-existing reimbursement semantic** — the `Reimbursement` row's
   `reimbursedTo` binding reads `entry.payerName` (which maps to `payor_name`
   = vendor in expense mode, not the member who paid). This is
   **pre-existing on `main` and PR #273 branch both**, and NOT a
   reconciliation-introduced bug. Note in the PR body so Tony knows to look
   at it, but do not classify as a regression.
4. **PR #261 collision** — `feature/band-gear-management` touches
   `financials_screen.dart` with 4 lines of `textAlign: TextAlign.right`
   inside the old table code that this reconciliation deletes. Flag to
   Manager for coordination — PR #261 either drops those 4 lines or lands
   before this reconciliation.
5. **Empty-state rendering** — verify summary header + list header render
   above `_EmptyState` in the empty-band case (regression guard for the
   Cycle 5 restructuring).
6. **`_SavingsSheet` behavior** — unchanged code path. Confetti + count-up
   animation should look identical to today.
7. **Report PDF** — verify the report title now reads `All time` (not `All
   Time`) for the all-time filter, and does NOT include a custom-date
   branch (regression guard against accidentally reintroducing the
   deleted `custom` case).
8. **Contributor role read path** — sign in as contributor with
   `can_view_financials = true`; screen should render identically.
9. **Long `paidToName` / `payerName`** — cards must ellipsis, not overflow.
   Detail rows must wrap the value column, not the fixed label column.
10. **Large totals** ($1,234,567.89) — must render on one line in summary
    header without wrapping.
11. **The `_addEntry` → `showAddFinancialEntrySheet` signature** —
    reconfirm the full 5-param destructure/pass-through survives on
    `financials_screen.dart` after the list rebuild. Missing any of these
    5 would silently null the column on save from the add sheet.

## Rollout Strategy

Single PR. No feature flag. No phased rollout. No DB migration to sequence
with the app deploy. Merge to `main` → deploy to iOS / Android / macOS /
web via the standard `tools/build_*.sh` + `tools/deploy_web.sh` pipeline.
Rollback = revert the PR; no data changes to unwind.

**Disposition of PR #273** (Manager/Tony decides at Release time, not
this Architect):

- **Recommendation**: close PR #273 in favor of the new reconciled PR from
  branch `feature/financials-transaction-cards-reconciliation`. Leave a
  brief close comment linking to the new PR so the history trail is
  obvious. Do NOT delete the `feature/financials-transaction-cards` branch
  — retention preserves the 11 cycles of design context (Cycles 1–3
  shipped-shape, Cycles 4–8 design evolution, QA reports) for future
  reference. Do NOT force-update PR #273's branch pointer — that would
  invalidate its CI history and existing review conversations.
- The reconciled PR body should explicitly link to PR #273 and PR #274 in
  its "History" section, so future readers understand why the reconciled
  branch exists.

## Out of Scope

- **Fixing the pre-existing "Reimbursed to <vendor>" semantic bug in
  `_buildReimbursementDetailLine`** — the `reimbursedTo` binding reads
  `entry.payerName` (which is the vendor in expense mode, not the member
  who paid). Pre-existing on `main` and PR #273. Flagged in QA Regression
  Areas item 3. Fix belongs in a separate feature/bug cycle.
- **Adding an `isReimbursed` toggle to the Add form for entries that are
  NOT gig-linked expenses** — PR #273's original "known pre-existing
  out-of-scope gap" is now moot: PR #274's Add form has a full Reimbursement
  section for every expense entry. This out-of-scope note in PR #273 is
  resolved.
- **Persisting sort preference / date-filter selection across screen
  dismiss, band switch, or app restart** — not asked for; sort resets to
  `Newest first ▾` and date filter resets to `This year` on every open.
- **Sort control in `_SavingsSheet` or the combined report** — sort is
  scoped to the main transactions list only.
- **Tappable gig name in `Needed for gig` row** — plain text, no navigation.
- **Colored circular category icons on cards** — explicitly excluded per
  PR #273 Cycle 1.
- **Any change to `add_financial_entry_bottom_sheet.dart`** — PR #274's
  form is authoritative; no PR #273 Cycle 8 changes get ported.
- **Any change to `FinancialEntry` model, `FinancialEntryRepository`, or
  `financials_provider` outside the specific tri-state date-filter delta.**
- **Any change to gig data flow, `bandFullStateProvider`, or the
  `get_band_full_state` RPC.**
- **Any RLS or migration work.**
- **Coordinating with or modifying PR #261 (band-gear-management).**
  Flagged for Manager; not this reconciliation's job to fix.
