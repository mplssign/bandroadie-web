# ARCHITECT_PLAN.md

## 1. Feature Slug
`feature/financials-report-breakdown`

---

## 2. Problem Summary
The Financials "Generate Report" PDF (`FinancialsPdfPreviewScreen`) currently renders
income and expenses as **category subtotals only** (one row per category, e.g. "Rent —
$1,200", summed across every entry in that category), plus a Net Income row, an optional
single-line Savings row, and a Summary box. It has **no itemized line-by-line view** and
**no per-member disbursement breakdown**.

Tony supplied a concrete mockup (transcribed in the Feature Input) specifying a different,
four-section report layout: **INCOME**, **EXPENSES**, **BAND SAVINGS ACCOUNT**, and **BAND
DISBURSEMENTS**. This plan redesigns the report to match that mockup, reusing existing data
— no new data model, repository, or backend logic is required.

This is a layout/presentation redesign of an existing report screen, not a bug fix and not
a new data feature.

---

## 3. Root Cause
Not applicable in the bug sense — this is a **confirmed layout gap**, not a defect.

**Confidence: HIGH**, confirmed by direct code reading of
`lib/features/financials/financials_pdf_preview_screen.dart` (672 lines):
- `_buildPdf` (lines 92–344) groups `FinancialEntry` rows by `category` for both income and
  expenses, and calls `_buildLineItem` once per **category**, passing the summed
  `categoryTotal` — individual entries are never rendered as their own row.
- There is no widget, section, or data path anywhere in the file that reads
  `FinancialEntry.disbursements` — per-member distribution data is loaded into memory
  (`FinancialsState.allEntries`) but never rendered.
- The header renders `bandName` + a dynamic `"$_viewModeLabel Report"` subtitle on the left
  and `_filterLabel` + a "Generated {date}" stamp on the right — no centered top title, and
  no thick section-divider styling anywhere in the file (`dividerColor` is a single thin
  0.5pt style used throughout).
- The report currently ends with a `Net Income` row (lines 299–307) and a `Summary` box
  (lines 324–334) — neither appears in the target mockup.

---

## 4. Reference Docs Consulted
Per Manager instruction, Phase 4 was adapted from its notifications-specific template to
the financials/reporting domain for this feature.

- Checked `docs/reference/` for a financials- or reporting-specific reference subfolder.
  **None exists.** Existing subfolders are: `architecture`, `audits`, `auth`, `banners`,
  `bpm`, `deployment`, `general`, `notifications`, `ui`. `docs/reference/notifications/`
  does not apply to this feature and was not consulted.
- In place of a reference doc, prior Financials-area feature plans were reviewed as
  instructed:
  - `docs/features/gig-pay-financials/ARCHITECT_PLAN.md` — confirms `category: 'Gig Pay'`
    is the exact category string written by the gig-pay flow (`upsertGigPayEntry`,
    `financial_entry_repository.dart:65`), and that disbursements are populated from gig
    pay splits.
  - `docs/features/deposit-to-savings-amount/ARCHITECT_PLAN.md` — confirms
    `deposit_to_savings_cents` already exists end-to-end (migration, model, repository,
    controller, form UI) as of a prior shipped feature — no new column or field is needed
    for the Band Savings Account section.
  - `docs/features/deposit-to-savings-toggle/ARCHITECT_PLAN.md` — confirms the origin of
    the `deposit_to_savings` boolean and that deposits are recorded as a property of an
    income `FinancialEntry`, not a separate ledger/table.
  - `docs/features/expense-delete-drawer/ARCHITECT_PLAN.md` — no report-relevant findings;
    scoped to entry deletion UI only.

**Additional Context (gap flagged per Manager instruction):** No financials/reporting
reference doc exists yet. Recommend that, after this feature ships, a short
`docs/reference/financials/REPORTING.md` be created documenting the report's data flow and
the category/description/disbursement conventions below — out of scope for this plan,
noted for future consideration only.

**Note on stale prior plan:** A prior `ARCHITECT_PLAN.md` already existed on disk at this
path (untracked, uncommitted) addressing an earlier, different version of this request
(itemize-by-category-with-subtotals + a separate aggregated "Distribution by Member"
section). It predates the mockup Tony provided for this session and does not match the
current Feature Input's four-section spec. This plan **supersedes and replaces** that file
in place; the prior version is not preserved separately since it was never committed.

---

## 5. Existing System Analysis

**Report generation is 100% client-side Flutter/Dart.** There is no edge function or
server-side rendering involved. `financials_pdf_preview_screen.dart` uses the `pdf` and
`printing` packages directly to build and preview/print/share a PDF in-process. Confirmed
unchanged from prior findings — no server-side component exists to redesign.

**Current data flow:**
```
FinancialsScreen (_openCombinedReport, line 1088)
  → reads state.dateFilteredEntries (all entries, income + expense, date-filtered,
    sorted entryDate DESC)
  → pushes FinancialsPdfPreviewScreen(entries: ..., bandName: ..., dateFilter: ...)
      → _buildPdf() groups entries by `category` (income and expense separately)
      → renders one row per category with the category's summed amount
      → renders Net Income, optional Savings summary row, and a Summary box
```
This is the **only** call site of `FinancialsPdfPreviewScreen` in the codebase (confirmed
via project-wide grep) — the `viewMode` constructor parameter (income-only /
expenses-only) is part of the public API but is never exercised today; the only live
report is the combined one.

**Data model — `FinancialEntry` (`lib/features/financials/models/financial_entry.dart`)
already contains every field needed for the mockup's four sections. No model, schema, or
repository change is required:**

| Mockup need | Existing field | Present? |
|---|---|---|
| Item name (Income/Expense rows) | `category` (free-text string) | Yes |
| Description subtext (Income/Expense rows) | `description` (nullable) | Yes |
| Amount (Income/Expense rows) | `amountCents` | Yes |
| Deposit date (Savings rows) | `entryDate` | Yes |
| Deposit description (Savings rows) | `description` | Yes |
| Deposit amount (Savings rows) | `depositToSavingsCents` (gated by `depositToSavings == true`) | Yes |
| Disbursement member + amount (Disbursements rows) | `disbursements` (`Map<userId, cents>`) | Yes |
| Disbursement description (Disbursements rows) | `description` of the entry the disbursement came from | Yes |

**Critical reconciliation — resolves the ambiguity flagged in the Feature Input (HIGH
confidence, confirmed by direct code reading, not guessed):**

The Feature Input asks whether the mockup's bold "item name" (e.g. "Gig pay", "Rent") maps
to a **category subtotal** (today's behavior) or an **individual entry**. Confirmed by
reading `add_financial_entry_bottom_sheet.dart`:
- Line 38: `const _kDefaultIncomeTypes = ['Gig Pay', 'Merch Sale', 'Equipment Sale'];`
- Line 39–45: `const _kDefaultExpenseTypes = ['Rent', 'Marketing', 'Equipment', 'Website', 'Domain name'];`
- Line 380: `category: _selectedTypeName` — `category` is literally the free-text "type"
  label the user picked or typed (via `_showAddTypeDialog`) when creating the entry, one
  per entry.

These default type lists are an **exact match** to the mockup's example rows: Income
("Gig pay", "Merch sales", "Equipment sale") and Expenses ("Rent", "Website", "Domain
name", "Equipment"). This confirms: **the mockup's bold ITEM label is `entry.category`, and
the indented description subtext is `entry.description`, rendered one row per
`FinancialEntry`** — not a category-level aggregate. Multiple entries may share the same
category string (e.g. two separate "Rent" entries in different months); each still renders
as its own row. This also resolves Tony's earlier request for full itemization
(date/description/amount/paid-by/category) — the mockup surfaces category (as the item
label) + description + amount per row, with date and paid-by intentionally omitted from
the visible columns; per the Feature Input's own reconciliation note, contextual detail
that would otherwise need a paid-by/date column is expected to live in the description
subtext instead. No data-model gap exists.

**Per-deposit and per-member disbursement data — confirmed existing, not new:**
- `depositToSavings` (bool) + `depositToSavingsCents` (int?) are properties of an income
  `FinancialEntry` — a "deposit" is not a separate row/table, it's an income entry flagged
  as partially or fully deposited to savings. The Band Savings Account section is built by
  filtering `widget.entries` (already date-filtered by the caller) for
  `depositToSavings == true`, one row per matching entry using `entryDate`, `description`
  (fallback needed — see Open Question 2 below), and `depositToSavingsCents`.
- `disbursements` (`Map<String, int>`, userId → cents) is a nullable field on income
  entries, populated by `add_financial_entry_bottom_sheet.dart` (`_save()`, lines 363–369)
  when the "Disburse to Band" toggle is used. **Confirmed constraint** (lines 223–225):
  `if (!isIncome && _disburse) { _disburse = false; }` — disbursement is force-cleared when
  switching to expense mode, so disbursement data only ever exists on income entries. This
  is a pre-existing constraint of the entry-creation form and is **out of scope** to change
  as part of a report-rendering redesign (see Open Question 3).
- `financials_screen.dart` already resolves band members via
  `ref.read(membersProvider).members` (from `../members/members_controller.dart`, used
  today for the add-entry sheet at line 43) — this is the existing lookup this feature
  reuses to resolve `disbursements` keys (`userId`) to display names
  (`MemberVM.name` / `MemberVM.userId`, `lib/features/members/member_vm.dart`). No new
  member-lookup logic is needed.

**Conclusion: all four mockup sections are additive/restructured surfacing of existing
data. No new model field, migration, repository query, or business-logic change is
required.**

---

## 6. Proposed Solution

Rewrite `_buildPdf` and its rendering helpers in `financials_pdf_preview_screen.dart` (and
extract the bulk of the rendering helpers into a new sibling file — see justification
below) to produce the four-section mockup layout:

**A. Header redesign:**
- Add a new centered, small title line above the existing name/date row:
  `"Income and Expense Report"` (the mockup's literal text — the only live call site is
  the combined report, so this static string is accurate; the existing dynamic
  `_viewModeLabel Report` computation is preserved as a fallback for the unused
  income-only/expenses-only constructor paths so the API contract doesn't silently break).
- Below it: one row with `bandName` (large, bold, left-aligned) and the date range
  (`_filterLabel`, right-aligned) — reusing the existing `_filterLabel` getter unchanged.
- Drop the current "Generated {date}" stamp and the `$_viewModeLabel Report` subtitle line
  — neither appears in the mockup.

**B. Income section — full itemization (replaces category-subtotal grouping):**
- One row per `FinancialEntry` where `isIncome == true`: bold `category` on the first line,
  `description` (if present) as a smaller indented line below it, `amountCents`
  right-aligned next to the bold line. Entries with no `description` render only the bold
  line (no empty indented line) — matches the file's existing null-handling convention.
- Sorted chronologically ascending (`entryDate`) within the section — a minor, low-risk
  design choice (existing `dateFilteredEntries` arrives sorted descending; reversing for
  report display reads more naturally top-to-bottom as a period narrative). Reversible by
  the Engineer without plan impact if Tony prefers descending.
- Closing row: `"TOTAL INCOME"` bold, right-aligned sum of all income entries in the
  report period, with a thin rule above (existing `dividerColor` styling, applied as a top
  border on the total row).
- Empty state ("No income during this period.") preserved unchanged.

**C. Thick divider** between Income and Expenses sections — new visual element, a new
darker/heavier `pw.Divider` (or bordered `Container`) distinct from the existing thin
0.5pt `dividerColor` rule already used for line items.

**D. Expenses section — same pattern as Income (§B), applied to `isIncome == false`
entries.** Closing row `"TOTAL EXPENSES"`.

**E. Thick divider** between Expenses and Band Savings Account (same style as §C).

**F. Band Savings Account section (new):**
- Filter `widget.entries` for `depositToSavings == true`.
- One row per matching entry: `DATE` (`entryDate`, short format e.g. `MMM d, yyyy`) /
  `DESCRIPTION` (`description`, fallback to `category` if null/empty — see Open Question 2)
  / `AMOUNT` (`depositToSavingsCents`, right-aligned).
- Sorted chronologically ascending by `entryDate`.
- Closing row: `"TOTAL DEPOSITS"` bold, right-aligned sum of `depositToSavingsCents` across
  matching entries.
- Section renders nothing (not even a header) when no entry has `depositToSavings == true`
  — matches the file's existing convention of hiding empty optional sections (see current
  Savings-section `if (savingsCents > 0)` guard).

**G. Band Disbursements section (new):**
- Aggregate every `(userId, cents)` pair from every entry's non-null `disbursements` map
  across `widget.entries`, retaining the source entry's `description` (fallback to
  `category`) as that line item's label — i.e. one line item per (entry, member) pair, not
  one aggregated total per member (this matches the mockup's example of two distinct
  line items for the same member from two different source entries).
- Group line items by `userId`, resolve to a display name via the new `members` parameter
  (`MemberVM.name`), sorted by resolved name; within a member's group, sort line items by
  the source entry's `entryDate` ascending.
- Member name rendered once per group (bold), followed by that member's description/amount
  line items (matches mockup: name once, then N sub-rows).
- Fallback for a `userId` not found in `members` (e.g. a removed band member): a truncated-
  id label, consistent with `MemberVM`'s own fallback convention (`"Member {id prefix}"`),
  not a silent drop or crash.
- Closing row: `"TOTAL DISBURSEMENTS"` bold, right-aligned sum of all disbursement cents
  across all members, with a thick rule above **and** below (per mockup — the only section
  with a rule on both sides of its total).
- Section renders nothing when no entry has a non-empty `disbursements` map.

**H. Net Income row and Summary box — removed.** See Open Question 1; default assumption
below.

**What changes:** `financials_pdf_preview_screen.dart` (state/scaffold/print/share,
largely unchanged), a new `financials_report_builder.dart` (all `pw.Widget` section-
building logic, net-new), `financials_screen.dart` (one call site passing `members`
through).
**What must not change:** `FinancialEntry` model, `FinancialEntryRepository`,
`FinancialsController`/`FinancialsState`, the add/edit entry forms, gig pay flow, savings
sheet, entry CRUD, `viewMode`/date-filter logic.

---

## 7. Open Questions for Tony (must be confirmed at Gate 2 before Engineer starts)

These are the points where the mockup is genuinely ambiguous or in tension with current
behavior, per the Feature Input's own instruction to flag rather than guess. A default
assumption is stated for each so the plan remains actionable; the Engineer must not
proceed past Gate 2 until these are confirmed or corrected.

1. **Net Income row and Summary box removal.** The mockup's four sections
   (INCOME/EXPENSES/BAND SAVINGS ACCOUNT/BAND DISBURSEMENTS) do not include a Net Income
   line or a closing Summary box, both of which exist in the current report. Is this
   deliberate (the mockup is the complete target, replacing them) — **assumed: yes,
   remove both** — or should Net Income / Summary be retained and simply appended after
   Band Disbursements, since the mockup transcription may only cover the sections Tony
   wanted to discuss in detail and not imply removal of the rest? **Assumption used in
   this plan: remove — matches "closely follow the mockup" instruction and the mockup's
   framing as "the target layout specification."**
2. **Fallback label when a category/description-carrying entry has no `description`.**
   Every Income/Expense mockup row shows both a bold item name and a description subtext;
   real entries frequently have a null `description` (it's an optional field). **Assumption
   used in this plan: omit the indented line entirely when `description` is null/empty**
   (no visual placeholder), consistent with the file's existing null-handling elsewhere.
   Alternative: fall back to a generic sentence per category — rejected as inventing
   content not present in the data.
3. **Disbursements are income-only by current form constraint** (`add_financial_entry_
   bottom_sheet.dart` force-clears the disburse toggle on expense entries). The mockup's
   Band Disbursements example shows a "Rehearsal snacks" line item, which reads more like
   an expense reimbursement than an income split. **This plan does not change that
   constraint** — Band Disbursements will only ever show data from income entries, exactly
   as the underlying data model already allows. If Tony intends disbursements to also
   originate from expense entries (e.g. reimbursing a member who fronted a cost), that is
   a data-entry-flow / business-logic change to `add_financial_entry_bottom_sheet.dart`,
   explicitly out of scope for a report-rendering redesign, and would need its own
   Architect plan.

---

## 8. Database Impact
**Not applicable.** No migrations, RLS changes, RPCs, or triggers. All data (`category`,
`description`, `disbursements`, `depositToSavings`, `depositToSavingsCents`) is already
fetched by the existing `fetchEntriesForBand` query; band members are already fetched by
the existing `membersProvider`. This is a pure read/render change.

---

## 9. Flutter Architecture Changes
- **`lib/features/financials/financials_report_builder.dart` (new file)**
  - Houses all `pw.Widget`-returning section builders for the report: header, income
    itemization, expenses itemization, band savings account, band disbursements, section
    totals, and the thick/thin divider helpers.
  - Justification for a new file rather than growing `financials_pdf_preview_screen.dart`
    in place: the existing file is already 672 lines (Guardrails §8 general-file target is
    500 lines); this redesign adds two net-new sections, a new header layout, and replaces
    the grouping logic, which would push the single file well past 900+ lines. Extracting
    pure rendering-helper functions (no state, no widget lifecycle) into a sibling file is
    a size/readability split, not a new architectural pattern — it does not introduce a
    new controller, provider, or repository, and the existing
    `_buildSectionHeader`/`_buildLineItem`/`_buildSubtotalRow` naming/visual conventions
    are preserved verbatim as the basis for the new helpers.
  - Exposes a single entry point, e.g. `List<pw.Widget> buildFinancialsReportContent({required List<FinancialEntry> entries, required String bandName, required String dateRangeLabel, required List<MemberVM> members})`, called from `_buildPdf`.
- **`lib/features/financials/financials_pdf_preview_screen.dart`**
  - Add a new constructor parameter: `final List<MemberVM> members;` (import from
    `../members/member_vm.dart`), defaulting to `const []` so no other caller is forced to
    pass it (there is only one caller today, but the default preserves the widget's
    existing safe-default convention).
  - `_buildPdf` delegates its `widgets` list construction to
    `buildFinancialsReportContent(...)` from the new builder file instead of its current
    inline category-grouping logic.
  - Remove the now-unused `_buildNetIncomeRow` and `_buildSummaryBox`/`_buildSummaryLine`
    methods (moved logic is replaced, not relocated, per Open Question 1's assumption) —
    or relocate them to the new builder file only if Tony's Gate 2 answer to Open Question
    1 is "retain them."
  - `_buildSectionHeader`, `_buildLineItem`, `_buildSubtotalRow` either move to the new
    builder file (preferred, keeps all `pw.Widget` builders together) or remain and are
    called from the builder file — Engineer's call based on which keeps the diff smallest;
    either is consistent with this plan.
- **`lib/features/financials/financials_screen.dart`**
  - In `_openCombinedReport` (line 1088), read `ref.read(membersProvider).members` (same
    call already used in `_addEntry`, line 43) and pass it as `members:` to the
    `FinancialsPdfPreviewScreen` constructor call (line 1096).

No controller, repository, or model changes. No new providers. No new dependencies.

---

## 10. Files to Create
| File | Justification |
|---|---|
| `lib/features/financials/financials_report_builder.dart` | Extracts the report's `pw.Widget` rendering helpers to keep `financials_pdf_preview_screen.dart` within Guardrails §8's file-size target given this redesign adds two new sections and a new header layout to an already 672-line file. See §9. |

---

## 11. Files to Modify
| File | What changes |
|---|---|
| `lib/features/financials/financials_pdf_preview_screen.dart` | Replace category-grouped `_buildPdf` body with a call into the new report builder; add `members` constructor parameter; remove (or relocate, pending Open Question 1) Net Income row and Summary box |
| `lib/features/financials/financials_screen.dart` | Pass `ref.read(membersProvider).members` into the `FinancialsPdfPreviewScreen` call in `_openCombinedReport` |

---

## 12. Files Off-Limits
| File | Reason |
|---|---|
| `lib/features/financials/models/financial_entry.dart` | All required fields already exist; no model change needed or permitted |
| `lib/features/financials/financial_entry_repository.dart` | No new queries needed; existing fetch already returns all required fields |
| `lib/features/financials/financials_controller.dart` | No state shape change needed; `dateFilteredEntries` already provides what the report needs |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | Entry CRUD form — explicitly out of scope per Feature Input; the income-only disbursement constraint here is not changed (see Open Question 3) |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | Entry CRUD/detail view — explicitly out of scope per Feature Input |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart` | Gig pay entry form — explicitly out of scope per Feature Input |
| Any `supabase/migrations/*` file | No database impact — see §8 |

---

## 13. System Impact Map
| System | Impact |
|---|---|
| Gigs | unaffected — gig pay entries are read the same way, only rendered differently in the report |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | affected (read-only) — reuses existing `membersProvider` read already performed elsewhere in the same screen; no new permission surface |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — report generation is client-side Dart (`pdf`/`printing` packages) and already runs on all four platforms today (confirmed: `_handlePrint` has a macOS-specific navigation workaround but `_buildPdf` itself is platform-agnostic); no new platform-specific code paths introduced by this redesign |

---

## 14. Regression Risk
**MEDIUM.**
- Only 2 files modified + 1 new file created, all confined to the report-rendering path;
  no state management, repository, model, or database changes.
- No changes to auth, session, routing, or app init order.
- Elevated from LOW because: (a) this is a near-total rewrite of `_buildPdf`'s body rather
  than an additive patch — the category-subtotal grouping behavior is being replaced, not
  extended, so a mistake in the itemization or totals math would be a visible, immediate
  regression; (b) Open Question 1 (removing Net Income/Summary) is a default assumption,
  not a confirmed instruction — if wrong, the Engineer's output will need a follow-up
  correction; (c) the new file introduces a hard-to-review-by-diff-alone amount of new
  rendering code (four sections, two new divider styles, regrouped disbursements).
- Worst-case failure mode is still confined to the PDF report screen itself; no other
  Financials functionality (entry CRUD, filters, savings sheet, gig pay) is touched, and
  print/share plumbing (`_handlePrint`/`_handleShare`) is untouched.

---

## 15. Engineer Task Breakdown
1. Confirm Open Questions 1–3 (§7) with Tony/Manager at Gate 2 before starting, or proceed
   with the stated default assumptions if Tony/Manager explicitly authorizes doing so.
2. Create `lib/features/financials/financials_report_builder.dart`. Move
   `_buildSectionHeader`, `_buildLineItem`, `_buildSubtotalRow` into it (as top-level
   functions or static methods — Engineer's choice, consistent naming). Add a new thick-
   divider helper (e.g. `_buildThickDivider`) distinct from the existing thin
   `dividerColor` styling.
3. In the new file, add a header-building function that renders the centered
   `"Income and Expense Report"` title followed by the existing bandName (left, bold,
   24pt) / date-range (`_filterLabel`, right) row, dropping the "Generated {date}" stamp
   and the `$_viewModeLabel Report` subtitle line.
4. Add an itemized-section builder (shared logic for Income and Expenses, parameterized by
   `isIncome`): one row per matching `FinancialEntry`, sorted `entryDate` ascending, bold
   `category` + optional indented `description` + right-aligned `amountCents`; closing
   `"TOTAL INCOME"` / `"TOTAL EXPENSES"` row with a thin rule above; preserve the existing
   "No income/expenses during this period." empty-state text.
5. Add a Band Savings Account section builder: filter for `depositToSavings == true`, one
   row per entry (`entryDate` short format / `description` fallback to `category` /
   `depositToSavingsCents`), sorted ascending, closing `"TOTAL DEPOSITS"` row; render
   nothing when no entry qualifies.
6. Add a Band Disbursements section builder: flatten every `(userId, cents)` pair from
   every entry's `disbursements` map into individual line items tagged with that entry's
   `description`-or-`category` and `entryDate`; group by `userId`, resolve names via the
   new `members` parameter with a truncated-id fallback for unmatched IDs, sort groups by
   resolved name and line items within a group by `entryDate` ascending; render the member
   name once per group followed by its line items; closing `"TOTAL DISBURSEMENTS"` row with
   a thick rule above and below; render nothing when no entry has a non-empty
   `disbursements` map.
7. Wire a single entry point function (e.g. `buildFinancialsReportContent(...)`) that
   assembles header + Income + thick divider + Expenses + thick divider + Band Savings
   Account + Band Disbursements, in that order, preserving the existing empty-entries-
   overall guard ("No financial activity during this reporting period.").
8. In `financials_pdf_preview_screen.dart`: add `import '../members/member_vm.dart';` and
   `import 'financials_report_builder.dart';`; add `final List<MemberVM> members;`
   constructor field (default `const []`); replace `_buildPdf`'s inline widget-building
   body with a call to `buildFinancialsReportContent(...)`; remove `_buildNetIncomeRow`,
   `_buildSummaryBox`, `_buildSummaryLine` (per Open Question 1 default) along with the
   now-unused `netIncomeCents`/`savingsCents`-for-summary local variables, unless Tony's
   Gate 2 answer says to retain them, in which case keep them appended after Band
   Disbursements instead of deleting.
9. In `financials_screen.dart`, update `_openCombinedReport` to read
   `ref.read(membersProvider).members` and pass it as `members:` into the
   `FinancialsPdfPreviewScreen(...)` call.
10. Run `flutter analyze` — must pass with 0 errors (Gate 3).

---

## 16. Verification Plan

**Database: not applicable** (§8) — there is no `supabase db push` step for this change, so
the Tier 1/Tier 2 split below is adapted to a build-time vs. runtime split instead of
pre/post-migration.

**Tier 1 — Pre-build (must pass before the Engineer reports done):**
- `-- PRE-DEPLOY TEST 1:` `flutter analyze` returns 0 errors on the three affected files.
- `-- PRE-DEPLOY TEST 2:` Manual code read confirming the Income and Expense section
  builders sum to the same `TOTAL INCOME` / `TOTAL EXPENSES` figures the old
  category-summed code would have produced for the same entry set (i.e., itemizing per
  entry instead of per category must not change the section total — no double counting, no
  dropped entries).
- `-- PRE-DEPLOY TEST 3:` Manual code read confirming the Band Savings Account and Band
  Disbursements builders each return an empty widget list (render nothing, not even a
  header) when no qualifying entry exists, so bands with no deposits/disbursements see no
  broken/empty section in the report.
- `-- PRE-DEPLOY TEST 4:` Manual code read confirming disbursement line items sum, across
  all members, to the total of all `disbursements` values across all entries in the report
  period (no member's cents dropped during flattening/grouping).

**Tier 2 — Post-build (run against a running app):**
- `-- POST-DEPLOY TEST 1:` Generate a combined report for a band with 2+ income entries
  sharing the same category (e.g. two "Gig Pay" entries) and 2+ expense entries across
  different categories — confirm every entry renders as its own row with correct
  category/description/amount, in ascending date order, and both section totals equal the
  sum of their entries.
- `-- POST-DEPLOY TEST 2:` Generate a report for a band with at least one entry that has
  `depositToSavings == true` — confirm the Band Savings Account section appears with
  correct date/description/amount per deposit and a correct `TOTAL DEPOSITS`.
- `-- POST-DEPLOY TEST 3:` Generate a report for a band with zero deposits — confirm the
  Band Savings Account section does not render at all (no header, no empty table).
- `-- POST-DEPLOY TEST 4:` Generate a report for a band with a disbursed income entry split
  across 2+ members, plus a second disbursed entry that includes one of the same members —
  confirm that member's group shows two separate line items (not one summed row), the
  member name renders once, and `TOTAL DISBURSEMENTS` equals the sum of every disbursement
  cents value in the period.
- `-- POST-DEPLOY TEST 5:` Generate a report for a band with zero disbursements — confirm
  the Band Disbursements section does not render at all.
- `-- POST-DEPLOY TEST 6:` Confirm the header shows the centered "Income and Expense
  Report" title, band name (bold, left) and date range (right) on one line, and no
  "Generated {date}" stamp.
- `-- POST-DEPLOY TEST 7:` Confirm Print and Share actions still function on at least one
  native platform and Web (no regression to `_handlePrint`/`_handleShare`, which are
  untouched by this plan but consume the same `_buildPdf` output).
- `-- POST-DEPLOY TEST 8:` If Open Question 1 was resolved as "retain Net Income/Summary,"
  confirm they render correctly after Band Disbursements; if resolved as "remove," confirm
  neither appears anywhere in the output.

---

## 17. QA Regression Areas
- Income/Expense itemization: every entry appears as its own row (not category-summed);
  bold category label; description subtext present only when `description` is non-null;
  amounts and section totals correct.
- Empty-section states (no income, no expenses, no deposits, no disbursements) each render
  their correct fallback (existing text for Income/Expenses; nothing at all for Savings
  Account/Disbursements) — no broken/empty headers.
- Band Savings Account: correct per-entry date/description/amount; `TOTAL DEPOSITS` math.
- Band Disbursements: correct per-member grouping with multiple line items per member when
  applicable; correct handling of a `disbursements` entry whose `userId` no longer matches
  any current band member (fallback label, no crash); `TOTAL DISBURSEMENTS` math.
- Header layout matches the mockup: centered title, band name + date range row, no
  "Generated" stamp.
- Thick vs. thin divider styling is visually distinct and placed exactly where specified
  (between Income/Expenses, between Expenses/Savings, above+below Disbursements total).
- Resolution of Open Question 1 (Net Income/Summary) matches what Tony actually confirmed
  at Gate 2, not just this plan's default assumption.
- No regression to entry CRUD (add/edit/delete), filters, view-mode toggle, or savings
  balance sheet — none of these files are touched.
- PDF print/share still functions across iOS, Android, macOS, and Web.
- `flutter analyze` passes with 0 errors.

---

## 18. Rollout / Migration Strategy
Not applicable — no database or backend deploy step. Ships as a normal client app release
once QA approves.

---

## 19. Out of Scope
- Changing the income-only constraint on `disbursements` (see Open Question 3) — that is a
  data-entry-flow/business-logic change to `add_financial_entry_bottom_sheet.dart`, not a
  report-rendering change.
- Inventing a new distribution/split calculation — this plan only surfaces the existing
  `disbursements` data already produced by the add-entry flow.
- Adding a category/type field to the data model (not needed — `category` already exists
  and is exactly what the mockup's item labels map to).
- Any change to entry CRUD forms (`add_financial_entry_bottom_sheet.dart`,
  `financial_entry_details_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`) beyond what's
  needed to read data for the report (none needed).
- Server-side/edge-function report generation — confirmed current generation is 100%
  client-side and this plan keeps it that way.
- Creating a `docs/reference/financials/` reference doc (flagged in §4 as a future
  recommendation only, not part of this feature).
- Income-only vs. expenses-only report variants (`viewMode` constructor param) — unused by
  any current call site; not redesigned to match the mockup since the mockup only depicts
  the combined report.
