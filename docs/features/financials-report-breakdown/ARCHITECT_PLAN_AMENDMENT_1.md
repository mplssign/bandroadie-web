# ARCHITECT_PLAN_AMENDMENT_1.md

## 1. Feature Slug
`feature/financials-report-breakdown` (amendment to the plan already approved and built on
this branch)

---

## 2. Amendment Context
The original `ARCHITECT_PLAN.md` was implemented by the Engineer and **APPROVED** by QA
(see `ENGINEER_REPORT.md`, `QA_REPORT.md`). That work is **uncommitted** on
`feature/financials-report-breakdown`:
- `lib/features/financials/financials_report_builder.dart` (new file)
- `lib/features/financials/financials_pdf_preview_screen.dart` (modified)
- `lib/features/financials/financials_screen.dart` (modified)

Before committing, Tony requested changes to the shipped-but-uncommitted Income/Expenses
row layout, the Band Savings Account and Band Disbursements column sets, and section/total
title styling. This document amends the original plan; it does not replace it. Only the
delta described below is in scope. `ARCHITECT_PLAN.md` is left untouched.

---

## 3. Problem Summary
Tony's new requirements (verbatim, from the Feature Input):
1. Income and Expenses rows: single-row, multi-column layout — **Entry type, Payer, Paid
   to, Description (if entered), Amount** — with only Description wrapping.
2. Band Savings Account columns: **Date, Description, Amount** (already the case, per
   Existing System Analysis below).
3. Band Disbursements columns: **Member, description, amount** (already the case).
4. All four section titles (Income, Expenses, Band Savings Account, Band Disbursements)
   same font-size/weight; all four total rows same font-size/weight.
5. Report title: bold, "a little larger" font-size.

---

## 4. Investigation Findings (Root Cause / Gap Analysis)

### 4a. "Entry type" vs. `category` — CONFIRMED SAME UNDERLYING CONCEPT, different field name
`FinancialEntry` (`lib/features/financials/models/financial_entry.dart`) has **both** a
`category` field (free-text, e.g. "Gig Pay", "Rent", "Streaming Revenue") and a genuinely
separate `entryType` field (`FinancialEntryType` enum: `gigPay | merchSale | equipmentSale |
miscIncome | expense`). These are not interchangeable:

- `entryType` is **coarse and lossy**. In `add_financial_entry_bottom_sheet.dart`,
  `_labelToEntryType` (lines 48–63) maps every expense category — Rent, Marketing,
  Equipment, Website, Domain name, and any custom type — to the single value
  `FinancialEntryType.expense`. Every custom income type also collapses to
  `FinancialEntryType.miscIncome`. Rendering `entryType.displayName` in the report would
  print "Expense" on every expense row (redundant with the section title) and "Misc Income"
  on any custom income type, discarding the actual category the user chose.
- `entryType` is currently **write-only**: confirmed via repo-wide search, it is persisted
  (`entry_type` column, `financial_entry_repository.dart`) and round-tripped through
  `fromJson`/`toJson`, but no UI or report code anywhere reads `.displayName` or branches on
  it today.
- The add/edit entry form's own UI labels the `category`-producing selector control **"Type"**
  (`add_financial_entry_bottom_sheet.dart:632`, `Text('Type')` above the type-pill row that
  sets `_selectedTypeName` → `category`).
- This matches the original plan's own finding (§5): "the mockup's bold ITEM label is
  `entry.category`."

**Conclusion (HIGH confidence): "Entry type" in Tony's new request is `category`, renamed as
a column header — not the `entryType` enum.** Using the enum would be a regression (loses
per-entry specificity, duplicates the section title). No model change needed.

### 4b. "Payer" and "Paid to" — CONFIRMED THEY ALREADY EXIST. No data-model gap. No migration.
This directly contradicts the original plan's field inventory (§5), which listed only
`category, description, amountCents, entryDate, depositToSavingsCents, disbursements` as
available fields. That inventory was **incomplete/stale relative to the current model** —
`financial_entry.dart` (as it exists today, lines 66–69) also defines:
```dart
final bool? is1099Expected;
final String? payerName;
final String? paidToName;
final String? paidToUserId;
```
Confirmed end-to-end, not model-only dead fields:
- **Repository**: `financial_entry_repository.dart` writes `payor_name`, `paid_to_name`,
  `paid_to_user_id`, and `entry_type` on both `insertEntry`/`updateEntry` and
  `upsertGigPayEntry` — all four are genuinely sent to Supabase.
- **Migrations**: `supabase/migrations/20260601000000_create_financial_entries.sql` defines
  `entry_type`, `payor_name`, `paid_to_user_id` on the original table;
  `20260601000001_add_paid_to_name.sql` adds `paid_to_name` as a follow-up. These are real,
  already-shipped columns.
- **Manual entry form**: `add_financial_entry_bottom_sheet.dart` collects both — a free-text
  field (`_payerController` → `payerName`) and a member-dropdown-or-free-text field
  (`_paidToUserId`/`_paidToOtherController` → `paidToUserId`/`paidToName`).
- **Gig pay flow**: `gig_pay_bottom_sheet.dart` collects the same two fields into
  `GigPayDetails`, which flows into `upsertGigPayEntry` and persists identically.

**Naming wrinkle to note for the Engineer:** the model field is `payerName` (Dart) /
`payor_name` (DB column) — not `payer_name`. `FinancialEntry.fromJson` maps
`json['payor_name']` → `payerName`. No functional impact, just spelling to get right when
referencing the field.

**A real nuance (not a data gap, but worth flagging — see Open Question 1 below):** the form
itself **relabels these two fields differently depending on income vs. expense**:
| Model field | Income form label | Expense form label |
|---|---|---|
| `payerName` | "Payer" (who paid the band) | "Paid To" (vendor the band paid) |
| `paidToUserId`/`paidToName` | "Paid To" (member who received it) | "Paid By" (member who fronted the cost) |

Tony's report request uses fixed column headers "Payer" and "Paid to" for both sections
uniformly (not per-section relabeling). §6 and Open Question 1 address how this plan
resolves that.

### 4c. Section title / total row styling — ALREADY UNIFORM, no change required
Read `financials_report_builder.dart` in full (current, as-built, 483 lines). All four
section titles ("Income", "Expenses", "Band Savings Account", "Band Disbursements") are
rendered by the **same** shared helper, `_buildSectionHeader` (line 417), with identical
styling: `fontSize: 13, fontWeight: pw.FontWeight.bold, color: _textDark`. All four total
rows ("TOTAL INCOME", "TOTAL EXPENSES", "TOTAL DEPOSITS", "TOTAL DISBURSEMENTS") are rendered
by the same shared helper, `_buildSubtotalRow` (line 442), with identical styling:
`fontSize: 12, fontWeight: pw.FontWeight.bold` for both label and amount. **These did not
drift during implementation — they were already built uniform because both helpers are
reused across all four sections.** No styling change is required to satisfy requirement #4;
this amendment states the confirmed current values as the target (unchanged) per the
Architect's obligation to specify concrete values rather than assume.

### 4d. Band Savings Account / Band Disbursements columns — ALREADY MATCH the new request
- `_buildBandSavingsSection` → `_buildDateLineItem`: Date / Description (fallback to
  category) / Amount. Matches "Date, Description, Amount" exactly. No change.
- `_buildBandDisbursementsSection` → member name header row + `_buildDisbursementLineItem`:
  Member (rendered once per group) / description / amount. Matches "Member, description,
  amount" exactly. No change.
- Both sections are built with a manual `pw.Row` + `pw.SizedBox`(fixed width) +
  `pw.Expanded`(wrapping) pattern — **not** a `pw.Table` primitive. No `pw.Table` widget is
  used anywhere in this file today. The new Income/Expenses row layout (§6) reuses this same
  Row/SizedBox/Expanded pattern rather than introducing `pw.Table`, consistent with
  Guardrails §7 ("no new abstractions unless existing pattern cannot solve the problem") —
  the existing pattern already solves a 3-column fixed+wrap layout for Band Savings Account;
  it extends cleanly to 5 columns.

### 4e. "Report title" — interpreted as the PDF's own heading text, not the app screen's AppBar
Two candidate "titles" exist:
1. `financials_pdf_preview_screen.dart:174` — the **on-screen Scaffold AppBar** title,
   `'$_viewModeLabel Report'`, styled `AppTextStyles.displayMedium`. This is app chrome
   around the PDF preview, not part of the generated report document.
2. `financials_report_builder.dart:_buildHeader` (line 90–97) — the **PDF's own** static
   heading text, `"Income and Expense Report"`, currently `fontSize: 12, color: _textMuted`,
   **not bold**, centered above the bandName/date-range row.

Given the entire Feature Input is about the report's own content/layout (columns, section
titles, total rows), "the report title" is read as (2), the in-document heading. Flagged
explicitly as Open Question 2 rather than silently assumed, per Manager instruction.

---

## 5. Reference Docs Consulted
No `docs/reference/financials/` doc exists (confirmed in original plan §4, still true).
Consulted for this amendment: `ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, `QA_REPORT.md` (this
feature's own prior outputs — the authoritative record of what was built and approved), and
direct reading of `financial_entry.dart`, `financial_entry_repository.dart`,
`add_financial_entry_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`, and
`financials_report_builder.dart` as currently on disk (uncommitted, as-built).

---

## 6. Proposed Solution

**A. Income / Expenses — replace bold/subtext block with a 5-column single row.**
Replace `_buildItemRow` with a fixed-column-width row:

| Column | Source | Width | Wraps? | Style |
|---|---|---|---|---|
| Entry type | `entry.category` | 70pt, fixed | No (`maxLines: 1`) | 10pt, regular, `_textDark` |
| Payer | `entry.payerName` (blank if null) | 80pt, fixed | No (`maxLines: 1`) | 10pt, regular, `_textDark` |
| Paid to | resolved (see below), blank if null | 80pt, fixed | No (`maxLines: 1`) | 10pt, regular, `_textDark` |
| Description | `entry.description` (blank if null) | `pw.Expanded` (remaining width, ~158pt at default margins) | **Yes** | 9pt, regular, `_textMuted` |
| Amount | `entry.amountCents` | 60pt, fixed, right-aligned | No | 10pt, regular, `_textDark` |

- **Paid to resolution**: if `paidToUserId != null`, resolve via the already-available
  `members` parameter (same `membersById` pattern already used in
  `_buildBandDisbursementsSection`) for a live/current name, falling back to the stored
  `paidToName` if the id isn't found (matching the existing disbursements fallback
  convention, `"Member {id prefix}"`, for consistency); if `paidToUserId == null`, use
  `paidToName` directly (the free-text "Other" case) or blank if both are null. Engineer may
  extract this into a small shared helper reused by both the disbursements section and this
  new column, since both already need "resolve userId → live member name with fallback" —
  optional simplification, not required.
- **Payer**: `entry.payerName` directly, no member resolution (it's a plain free-text field
  in the form for both income and expense).
- Row keeps `crossAxisAlignment: pw.CrossAxisAlignment.start` (already the case) so a
  wrapped Description doesn't misalign the other four single-line cells.
- Applies identically to both Income and Expenses sections (both already route through the
  shared `_buildItemizedSection`/`_buildItemRow`).

**B. Add a column-header row per Income/Expenses section**, directly below the existing
section title (`_buildSectionHeader`) and above the item rows: small, muted, single-line
labels — "Entry type", "Payer", "Paid to", "Description", "Amount" — aligned to the exact
same column widths as the data rows above (9pt, `_textMuted`, medium weight, matching the
same Row/SizedBox/Expanded skeleton as the data rows so columns line up). This wasn't
explicitly requested in Tony's text but is necessary for a 5-column report to be legible as
a table — flagged as Open Question 3 (default: add it) rather than silently added.

**C. Band Savings Account, Band Disbursements — no changes.** Confirmed matching (§4d).

**D. Report title styling.** In `_buildHeader`, change the `"Income and Expense Report"`
`pw.Text` style from `fontSize: 12, color: _textMuted` (no weight specified → regular) to
`fontSize: 16, fontWeight: pw.FontWeight.bold, color: _textDark`. Rationale for the concrete
values: current file type scale is 9 / 10 / 11 / 12 / 13 / 24pt; 16pt sits cleanly between
the section-header size (13pt) and the band-name size (24pt), appropriate for a document
title that sits above every section. The color change (`_textMuted` → `_textDark`) is a
judgment call so bold text doesn't read washed-out in gray — flagged as Open Question 4
(default: change color too; Engineer may keep `_textMuted` if Tony prefers the smaller
change).

**E. Section titles, total rows — no changes** (§4c: already uniform at 13pt bold /
12pt bold respectively).

**What changes:** `financials_report_builder.dart` only — `_buildItemRow` rewritten, a new
column-header helper added, `_buildHeader`'s title style updated.
**What must not change:** `_buildSectionHeader`, `_buildSubtotalRow`, `_buildDateLineItem`,
`_buildBandSavingsSection`, `_buildBandDisbursementsSection`, `_buildDisbursementLineItem`,
`_buildThickDivider` — all already correct per Tony's new spec. `financials_pdf_preview_screen.dart`
and `financials_screen.dart` — `entries` already carries `payerName`/`paidToName`/
`paidToUserId`, and `members` is already threaded through from the original plan's work; no
new data needs to reach the builder function.

---

## 7. Open Questions for Tony (must be confirmed at Gate 2 before Engineer starts)

1. **Payer/Paid-to column semantics vs. the form's per-section relabeling (§4b).** Default
   assumption used in this plan: report columns are fixed — "Payer" always shows
   `payerName`, "Paid to" always shows the resolved `paidToUserId`/`paidToName` — regardless
   of income vs. expense, even though the *form* relabels these same fields ("Paid To"/"Paid
   By") for expense entries. Net effect: on an expense row, the vendor name (what the form
   calls "Paid To") will appear under the report's "Payer" heading, and the reimbursed
   member (what the form calls "Paid By") will appear under "Paid to." If Tony wants the
   report's column meaning to flip per section to mirror the form's labels, that's a
   different (more complex — dynamic-column-meaning) design; flag before Engineer starts.
2. **"Report title" = the PDF's in-document heading** (`"Income and Expense Report"`, 12pt
   muted → bold 16pt dark), not the on-screen AppBar title. Assumed per §4e's reasoning.
3. **Add a column-header row above Income/Expenses item rows** (labels for the 5 columns).
   Not explicitly requested; assumed necessary for the layout to read as a table. Default:
   add it.
4. **Report title color**: bold + 16pt is the literal ask; changing color from `_textMuted`
   to `_textDark` alongside it is an added judgment call for visual weight, not explicitly
   requested. Default: change it. Low-impact either way; Engineer can revert to `_textMuted`
   in one line if Tony prefers the minimal-diff version.

None of these require schema work or Manager escalation — they are presentation judgment
calls, resolvable the same way the original plan's Open Questions were (stated default,
Engineer proceeds unless corrected at Gate 2).

---

## 8. Database Impact
**Not applicable.** `payerName`, `paidToName`, `paidToUserId`, `category` are all already
persisted columns (confirmed via migration files and repository code, §4b), already fetched
by the existing `fetchEntriesForBand`-style query (same query the original plan's `entries`
list already relies on), and already present on every `FinancialEntry` object the report
builder receives. No new column, no new query, no migration. This is a pure rendering change
confined to one file.

---

## 9. Flutter Architecture Changes
- **`lib/features/financials/financials_report_builder.dart`** (only file touched):
  - Replace `_buildItemRow(FinancialEntry, NumberFormat)` with a 5-column row builder per
    §6A. Needs `members`/`membersById` in scope — `_buildItemizedSection` and
    `_buildItemRow` must be passed `members: List<MemberVM>` (currently
    `buildFinancialsReportContent` already receives `members` and passes it to
    `_buildBandDisbursementsSection`; thread it through to `_buildItemizedSection` /
    `_buildItemRow` as well).
  - Add a new column-header row helper (e.g. `_buildItemizedColumnHeaders()`), inserted once
    per section in `_buildItemizedSection`, directly after `_buildSectionHeader(...)`.
  - Update `_buildHeader`'s title `pw.TextStyle` per §6D.
  - No new files, no new providers, no new dependencies.
- No changes to `financials_pdf_preview_screen.dart` or `financials_screen.dart` — both
  already pass everything the builder needs.

---

## 10. Files to Create
None.

---

## 11. Files to Modify
| File | What changes |
|---|---|
| `lib/features/financials/financials_report_builder.dart` | Replace `_buildItemRow`'s bold/subtext block with a 5-column (Entry type/Payer/Paid to/Description/Amount) row; add column-header row per Income/Expenses section; thread `members` into `_buildItemizedSection`; restyle the report title text in `_buildHeader` (bold, 16pt, `_textDark`) |

---

## 12. Files Off-Limits
| File | Reason |
|---|---|
| `lib/features/financials/financials_pdf_preview_screen.dart` | Already passes `entries` (with payer/paidTo data) and `members` through unchanged; no new data needed |
| `lib/features/financials/financials_screen.dart` | Same — call site already correct from the original plan's work |
| `lib/features/financials/models/financial_entry.dart` | All required fields already exist (§4b); no model change needed or permitted |
| `lib/features/financials/financial_entry_repository.dart` | No new queries needed; existing fetch already returns `payor_name`/`paid_to_name`/`paid_to_user_id`/`entry_type` |
| `lib/features/financials/financials_controller.dart` | No state shape change needed |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | Entry form — out of scope; this is a report-rendering change only |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart` | Gig pay form — out of scope |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | Entry detail view — out of scope |
| Any `supabase/migrations/*` file | No database impact — see §8 |

---

## 13. System Impact Map
| System | Impact |
|---|---|
| Gigs | unaffected — gig pay entries already populate `payerName`/`paidToName`/`paidToUserId`; only rendered differently |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | affected (read-only) — reuses the `members` parameter already threaded through by the original plan; no new permission surface |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — same client-side `pdf`/`printing` rendering path as the original plan; no new platform-specific code |

---

## 14. Regression Risk
**MEDIUM.**
- Confined to a single file, no state/model/repository/database changes.
- Elevated from LOW because: (a) this rewrites the Income/Expenses row layout a second time
  in the same feature — the highest-visual-risk part of the report — and introduces a fixed
  multi-column layout where text overflow/wrap behavior in the `pdf` package (not Flutter's
  own text layout engine) is the main untested risk; (b) three Open Questions (§7) are
  default assumptions, not confirmed instructions — if wrong, another follow-up correction is
  likely; (c) no automated test coverage exists for this rendering path (unchanged from the
  original plan's situation).
- Not HIGH: Band Savings Account, Band Disbursements, and both total-row/section-title
  helpers are explicitly unchanged and already confirmed correct; no risk of an unnoticed
  regression there since no code in those paths is touched.

---

## 15. Engineer Task Breakdown (delta only — original plan's Tasks 2, 3, 5, 6, 7, 9, 10 are unaffected and already complete)

1. Confirm Open Questions 1–4 (§7) with Tony/Manager at Gate 2, or proceed on the stated
   defaults if explicitly authorized.
2. In `financials_report_builder.dart`, add a `_buildItemizedColumnHeaders()` helper
   returning a `pw.Row` with the same five column widths as the data row (§6A), each cell a
   small (9pt), muted, single-line label: "Entry type", "Payer", "Paid to", "Description",
   "Amount" (right-aligned for Amount). Insert one call to it in `_buildItemizedSection`,
   immediately after `_buildSectionHeader(...)`.
3. Rewrite `_buildItemRow` to accept `entry` and `members` (in addition to `moneyFmt`) and
   render the 5-column layout per §6A: fixed-width `pw.SizedBox` (70pt Entry type / 80pt
   Payer / 80pt Paid to / 60pt Amount, `maxLines: 1` on each) plus `pw.Expanded` Description
   (9pt, wraps, blank when null). Resolve "Paid to" via `members`/`membersById` (`userId` →
   live name, fallback to stored `paidToName`, fallback to blank) using the same pattern
   already established in `_buildBandDisbursementsSection`'s `nameFor` helper — extracting a
   small shared helper is fine but not required.
4. Thread `members` from `_buildItemizedSection`'s signature down into `_buildItemRow` calls,
   and from `buildFinancialsReportContent`'s existing `_buildItemizedSection(...)` call sites
   (both Income and Expenses) — `members` is already a parameter of
   `buildFinancialsReportContent`, just not currently passed to this section.
5. In `_buildHeader`, change the title `pw.Text`'s style from
   `pw.TextStyle(fontSize: 12, color: _textMuted)` to
   `pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _textDark)`.
6. Do not touch `_buildSectionHeader`, `_buildSubtotalRow`, `_buildDateLineItem`,
   `_buildBandSavingsSection`, `_buildBandDisbursementsSection`,
   `_buildDisbursementLineItem`, or `_buildThickDivider` — all confirmed already correct.
7. Run `flutter analyze` — must pass with 0 errors (Gate 3).

---

## 16. Verification Plan

**Tier 1 — Pre-build (must pass before the Engineer reports done):**
- `-- PRE-DEPLOY TEST 1:` `flutter analyze` returns 0 errors on the modified file.
- `-- PRE-DEPLOY TEST 2:` Manual code read confirming Entry type/Payer/Paid to/Amount cells
  render with `maxLines: 1` (or equivalent non-wrap constraint) and Description is the only
  cell without such a constraint.
- `-- PRE-DEPLOY TEST 3:` Manual code read confirming the "Paid to" resolution checks
  `paidToUserId` against `members` first, falls back to `paidToName`, falls back to blank —
  no null-access crash when both are null.
- `-- PRE-DEPLOY TEST 4:` Manual code read confirming section title and total row helpers
  (`_buildSectionHeader`, `_buildSubtotalRow`) are unmodified byte-for-byte from the
  QA-approved version (diff should show zero changes to these two functions).

**Tier 2 — Post-build (run against a running app):**
- `-- POST-DEPLOY TEST 1:` Generate a combined report with income entries that have
  `payerName` set, `paidToUserId` set to a current band member, and a long `description` —
  confirm Entry type/Payer/Paid to/Amount stay on one line each and Description wraps to
  multiple lines without breaking row alignment.
- `-- POST-DEPLOY TEST 2:` Generate a report with an expense entry that has `payerName` set
  (vendor, per the form's "Paid To" label) and `paidToUserId` set to a band member (per the
  form's "Paid By" label) — confirm the values land in the "Payer" and "Paid to" report
  columns respectively, per Open Question 1's default, and that this reads sensibly to Tony.
- `-- POST-DEPLOY TEST 3:` Generate a report with entries that have null `payerName` and
  null `paidToName`/`paidToUserId` — confirm those cells render blank, not "null" or a crash.
- `-- POST-DEPLOY TEST 4:` Confirm the column-header row appears once per Income/Expenses
  section, directly under the section title, with columns visually aligned to the data rows
  below.
- `-- POST-DEPLOY TEST 5:` Confirm the report title reads visibly bolder and larger than the
  prior build, and confirm Band Savings Account / Band Disbursements sections render
  identically to the already-QA-approved build (no unintended regression).
- `-- POST-DEPLOY TEST 6:` Confirm Print and Share still function (untouched plumbing, but
  worth reconfirming after a rendering change to the same PDF document).

---

## 17. QA Regression Areas
- Income/Expenses: 5-column single-row layout renders correctly; only Description wraps;
  correct values in Entry type (=category), Payer (=payerName), Paid to (resolved
  member/free-text), Amount; blank (not "null") when optional fields are absent.
- Column-header row present, aligned, and legible above each Income/Expenses section.
- Report title is visibly bold and larger than the prior build.
- Section titles and total rows are **unchanged** from the already-approved build — confirm
  via diff that `_buildSectionHeader`/`_buildSubtotalRow` were not touched.
- Band Savings Account and Band Disbursements sections are **unchanged** — confirm via diff.
- No regression to entry CRUD, gig pay flow, filters, or Print/Share — none of those files
  are touched by this amendment.
- `flutter analyze` passes with 0 errors.

---

## 18. Rollout / Migration Strategy
Not applicable — no database or backend deploy step, same as the original plan.

---

## 19. Out of Scope
- Making "Payer"/"Paid to" column meaning dynamically flip between Income and Expenses
  sections to mirror the entry form's per-section relabeling (see Open Question 1) — this
  plan uses fixed column semantics; a dynamic-meaning design would need explicit sign-off.
- Any change to `add_financial_entry_bottom_sheet.dart` or `gig_pay_bottom_sheet.dart` — the
  confusing field/label mismatch described in §4b is a pre-existing characteristic of those
  forms, not something this report-rendering amendment changes.
- Reintroducing `entryType`/`FinancialEntryType.displayName` anywhere in the report (§4a) —
  confirmed to be the wrong field for "Entry type."
- Everything already covered as Out of Scope in the original `ARCHITECT_PLAN.md` §19
  remains out of scope here.
