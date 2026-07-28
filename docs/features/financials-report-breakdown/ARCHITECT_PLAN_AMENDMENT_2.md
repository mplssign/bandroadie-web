# ARCHITECT_PLAN_AMENDMENT_2.md

## 1. Feature Slug
`feature/financials-report-breakdown` (second amendment to the plan already approved and
built on this branch)

---

## 2. Amendment Context
`ARCHITECT_PLAN.md` (original) and `ARCHITECT_PLAN_AMENDMENT_1.md` (first amendment) have
both been implemented; see `ENGINEER_REPORT.md`. Per `QA_REPORT.md`:
- The original round: **APPROVED**.
- The Amendment 1 round: **REQUIRES CHANGES** — one critical, must-fix defect in
  `_buildItemRow`'s Amount cell.

Work is still uncommitted on `feature/financials-report-breakdown`. Before committing, Tony
also requested two new styling changes. This document amends the plan a second time; it
does not replace `ARCHITECT_PLAN.md` or `ARCHITECT_PLAN_AMENDMENT_1.md`, both of which are
left untouched. Only the delta described below is in scope.

---

## 3. Problem Summary
Two independent items, both confined to `lib/features/financials/financials_report_builder.dart`:

1. **Mandatory fix** — QA's Amendment 1 critical finding: the Amount cell in `_buildItemRow`
   is missing `maxLines: 1` and `overflow: pw.TextOverflow.clip`, unlike the three sibling
   fixed-width cells (Entry type, Payer, Paid to) next to it. A wide formatted-currency
   string (e.g. `$12,345.67`) can wrap onto a second line inside the 60pt Amount column,
   breaking the single-line 5-column layout.
2. **New styling requirements from Tony (verbatim):** "All text should be black in the
   generated report. Remove the light gray background behind the section titles."

---

## 4. Investigation Findings

### 4a. Critical fix — confirmed against current code (no further investigation needed)
Read `financials_report_builder.dart` as currently on disk (567 lines). The Amount cell is
at **lines 284–291**, inside `_buildItemRow`:

```dart
        pw.SizedBox(
          width: _colWidthAmount,
          child: pw.Text(
            moneyFmt.format(entry.amountCents / 100),
            style: singleLineStyle,
            textAlign: pw.TextAlign.right,
          ),
        ),
```

Confirmed: no `maxLines` and no `overflow` set, while the Entry type (251–259), Payer
(260–268), and Paid to (269–277) cells immediately above it all set
`maxLines: 1, overflow: pw.TextOverflow.clip`. QA's citation is accurate against the current
file — the fix is exactly as QA specified: add those two properties to this `pw.Text`.

### 4b. Every distinct text color currently used — confirmed via full-file grep
The file defines 8 color constants (lines 17–24):

| Constant | Value | Line | Used for |
|---|---|---|---|
| `_sectionHeaderBg` | `0xFFF3F4F6` (light gray) | 17 | **Background** fill behind section-title rows (`_buildSectionHeader`) |
| `_subtotalBg` | `0xFFF9FAFB` (near-white tint) | 18 | **Background** fill behind total rows (`_buildSubtotalRow`) |
| `_dividerColor` | `0xFFE5E7EB` | 19 | Thin **border** under item/date/disbursement rows |
| `_thickDividerColor` | `0xFF111827` | 20 | Thick divider **bars** between sections |
| `_textDark` | `0xFF111827` (dark charcoal — confirmed NOT pure black) | 21 | **Text** color — primary/dark text throughout |
| `_textMuted` | `0xFF6B7280` (gray) | 22 | **Text** color — secondary/muted text throughout |
| `_incomeGreen` | `0xFF059669` (green) | 23 | **Text** color — `TOTAL INCOME` amount only |
| `_expenseRed` | `0xFFDC2626` (red) | 24 | **Text** color — `TOTAL EXPENSES` amount only |

Only 4 of these 8 are ever used as a `pw.TextStyle`'s `color:` (i.e., are genuinely "text
colors" for Tony's request): `_textDark`, `_textMuted`, `_incomeGreen`, `_expenseRed`. The
other 4 (`_sectionHeaderBg`, `_subtotalBg`, `_dividerColor`, `_thickDividerColor`) are
**backgrounds and borders**, not text — out of scope for "all text should be black" as
written, and not touched by this amendment except `_sectionHeaderBg` (item 4c below).

Every `pw.TextStyle(color: ...)` / color-parameter call site for the 4 text colors, as
currently on disk:

| Text element | Color used | Line(s) |
|---|---|---|
| Overall empty-state text | `_textMuted` | 46 |
| `TOTAL INCOME` amount | `_incomeGreen` (via `totalAmountColor`) | 62 |
| `TOTAL EXPENSES` amount | `_expenseRed` (via `totalAmountColor`) | 74 |
| Report title "Income and Expense Report" | `_textDark` | 100 |
| Band name | `_textDark` | 114 |
| Date range label | `_textMuted` | 119 |
| `_buildSectionHeader` call (Income/Expenses title) | `_textDark` | 141 |
| Itemized-section empty text ("No income/expenses...") | `_textMuted` | 150 |
| `_buildSubtotalRow` call (Income/Expenses total label) | `_textDark` | 171 |
| `_buildItemizedColumnHeaders` labels | `_textMuted` | 188 |
| Entry type / Payer / Paid to cells (`singleLineStyle`) | `_textDark` | 239 |
| Description cell (item row) | `_textMuted` | 281 |
| Amount cell (item row) | `_textDark` (via `singleLineStyle`) | 288 |
| `_buildSectionHeader` call (Band Savings Account) | `_textDark` | 315 |
| `_buildSubtotalRow` call (Savings total, label + amount) | `_textDark`, `_textDark` | 333 |
| Date label (`_buildDateLineItem`) | `_textMuted` | 359 |
| Description (`_buildDateLineItem`) | `_textDark` | 365 |
| Amount (`_buildDateLineItem`) | `_textDark` | 370 |
| `_buildSectionHeader` call (Band Disbursements) | `_textDark` | 430 |
| Member name header (Disbursements) | `_textDark` | 445 |
| `_buildSubtotalRow` call (Disbursements total, label + amount) | `_textDark`, `_textDark` | 460 |
| Description (`_buildDisbursementLineItem`) | `_textMuted` | 484 |
| Amount (`_buildDisbursementLineItem`) | `_textDark` | 489 |

**Confirmed: `_textDark` (`0xFF111827`) is a dark charcoal, not pure black
(`0xFFFFFFFF`... i.e. `0xFF000000`).** Every text element in the current report is either
`_textDark`, `_textMuted`, `_incomeGreen`, or `_expenseRed` — none is currently pure black.

### 4c. "Light gray background behind the section titles" — confirmed location and value
`_sectionHeaderBg = PdfColor.fromInt(0xFFF3F4F6)` (line 17), applied in `_buildSectionHeader`
(lines 500–523) as `decoration: pw.BoxDecoration(color: backgroundColor)` on the
`pw.Container` that wraps the title text. `_buildSectionHeader` is called 3 times, once per
section, always passing `_sectionHeaderBg`: line 141 (Income/Expenses, via
`_buildItemizedSection`), line 315 (Band Savings Account), line 430 (Band Disbursements).
This is the exact element Tony is describing — confirmed, not guessed.

**`_subtotalBg` (`0xFFF9FAFB`) is a separate, much fainter near-white tint behind the total
rows (`_buildSubtotalRow`), not the section titles.** Tony's request names "the section
titles" specifically; `_subtotalBg` is not mentioned and is **not** touched by this
amendment (see §6, §7 Open Question B for the closest related judgment call).

---

## 5. Reference Docs Consulted
No `docs/reference/financials/` doc exists (confirmed in the original plan §4, still true).
Consulted for this amendment: `ARCHITECT_PLAN.md`, `ARCHITECT_PLAN_AMENDMENT_1.md`,
`ENGINEER_REPORT.md`, `QA_REPORT.md` (this feature's own prior outputs), and direct reading
of `financials_report_builder.dart` as currently on disk (uncommitted, as-built through
Amendment 1).

---

## 6. Proposed Solution

### A. Critical fix (mandatory, no open questions)
In `_buildItemRow`'s Amount cell (current lines 284–291), add `maxLines: 1` and
`overflow: pw.TextOverflow.clip` to the `pw.Text`, matching the Entry type/Payer/Paid to
cells exactly:

```dart
        pw.SizedBox(
          width: _colWidthAmount,
          child: pw.Text(
            moneyFmt.format(entry.amountCents / 100),
            style: singleLineStyle,
            textAlign: pw.TextAlign.right,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        ),
```

No other change to `_buildItemRow`'s structure, columns, or widths.

### B. Consolidate all report text to pure black
**Interpretation:** "All text should be black" is read literally — every `pw.Text` color in
the generated report becomes pure black (`0xFF000000`), not `_textDark`'s
`0xFF111827` charcoal. This is the default per Manager instruction to proceed with the
literal reading unless an existing distinction serves a legibility purpose worth flagging —
see §7 Open Questions A and B below, which flag exactly that tension rather than silently
deciding it.

**Design:**
1. Add one new constant: `const _textBlack = PdfColor.fromInt(0xFF000000);` in the existing
   color-constants block (near lines 17–24).
2. Replace every `color:`/color-parameter use of `_textDark`, `_textMuted`, `_incomeGreen`,
   and `_expenseRed` (all 24 call sites enumerated in §4b) with `_textBlack`.
3. Delete the four now-unused constants: `_textDark` (21), `_textMuted` (22),
   `_incomeGreen` (23), `_expenseRed` (24).
4. Do **not** touch `_subtotalBg`, `_dividerColor`, or `_thickDividerColor` — none are text
   colors (§4b).

**Why deleting the old constants is deliberate, not incidental:** because every one of the
24 call sites currently references `_textDark`/`_textMuted`/`_incomeGreen`/`_expenseRed` by
name, deleting the constants turns any missed replacement into an **`flutter analyze`
compile error** (undefined identifier) rather than a silent visual bug. This gives Gate 3 a
built-in completeness check for what is otherwise a wide, mechanical, easy-to-under-apply
diff — the Engineer cannot report done with a partially-converted file.

### C. Remove the section-title background
In `_buildSectionHeader` (lines 500–523):
- Remove the `backgroundColor` parameter.
- Remove the `decoration: pw.BoxDecoration(color: backgroundColor)` line from the returned
  `pw.Container`. The container keeps its `padding` and `child` (the title `pw.Row`/`pw.Text`)
  — the title becomes bold text with no container fill, still rendered on its own row/line,
  exactly as specified.
- Update the 3 call sites to drop the background argument:
  - Line 141: `_buildSectionHeader(title, _sectionHeaderBg, _textDark)` →
    `_buildSectionHeader(title, _textBlack)`
  - Line 315: `_buildSectionHeader('Band Savings Account', _sectionHeaderBg, _textDark)` →
    `_buildSectionHeader('Band Savings Account', _textBlack)`
  - Line 430: `_buildSectionHeader('Band Disbursements', _sectionHeaderBg, _textDark)` →
    `_buildSectionHeader('Band Disbursements', _textBlack)`
- Delete the now-unused `_sectionHeaderBg` constant (line 17).

**What changes:** `financials_report_builder.dart` only — color/background values in
`_buildHeader`, `_buildItemizedSection`, `_buildItemizedColumnHeaders`, `_buildItemRow`,
`_buildSectionHeader`, `_buildSubtotalRow`, `_buildDateLineItem`,
`_buildBandDisbursementsSection`, `_buildDisbursementLineItem`, plus the 2-property addition
to `_buildItemRow`'s Amount cell.
**What must not change:** every non-color property in every function above — column widths
(`_colWidthEntryType`/`_colWidthPayer`/`_colWidthPaidTo`/`_colWidthAmount`), padding/margins,
sort order, grouping logic, totals math, empty-state guards, `maxLines`/`overflow`
constraints on the other 3 fixed columns, `_subtotalBg`/`_dividerColor`/`_thickDividerColor`
values and where they're applied, and the overall section order in
`buildFinancialsReportContent`.

**Explicit supersession of Amendment 1 §6's "must not change" list:** Amendment 1 named
`_buildSectionHeader`, `_buildSubtotalRow`, `_buildDateLineItem`,
`_buildBandSavingsSection`, `_buildBandDisbursementsSection`, `_buildDisbursementLineItem`,
`_buildThickDivider` as off-limits. **This amendment supersedes that restriction for these
functions, and only for color/background property edits, as described above.** No other
behavior in these functions — layout, grouping, sorting, totals math, empty-state
handling, divider placement/width/height — may change. `_buildThickDivider` itself and
`_buildBandSavingsSection`'s/`_buildBandDisbursementsSection`'s non-color logic remain
untouched (their only edits are the call-site color arguments feeding into
`_buildSectionHeader`/`_buildSubtotalRow`, not their own bodies, except
`_buildDateLineItem`'s and `_buildDisbursementLineItem`'s own `color:` lines per §4b's
table).

---

## 7. Open Questions for Tony (must be confirmed at Gate 2 before Engineer starts)

Neither question blocks starting on the critical fix (§6A) or the mechanical black/no-background
conversion (§6B/§6C) — both proceed on the stated literal-reading defaults. These flag
where "all text black" trades away an existing visual signal, per the Manager's explicit
instruction not to silently decide this.

**A. Flattening the `_textDark`/`_textMuted` two-tone hierarchy.** Today, primary content
(category, band name, amounts, member names) is dark charcoal and secondary content
(descriptions, column headers, date labels, empty-state text) is gray — a deliberate
visual hierarchy that makes the report easier to scan (bold/dark item vs. quieter
supporting detail). Consolidating both to pure black removes that distinction; every
description and column header will read at the same visual weight as the primary
data next to it, which — reasonable people could differ here — may make a
dense 5-column table *harder* to scan, not easier. **Default used in this plan: flatten to
pure black (literal reading).** If Tony wants secondary text to stay visually quieter, the
narrower fix is: keep two tones, but make the "dark" tone pure black
(`0xFF111827` → `0xFF000000`) and leave `_textMuted` (`0xFF6B7280`) as the secondary gray —
i.e., only §6B step 2's `_textDark` replacements would apply, not the `_textMuted` ones.
Flagging explicitly rather than assuming which reading Tony intends.

**B. Flattening the green/red `TOTAL INCOME`/`TOTAL EXPENSES` amount colors.** This is a
different kind of signal than A — not a hierarchy cue but a semantic one (green = money in,
red = money out is a common financial-report convention), and arguably carries more
functional value than the muted/dark distinction. Under the literal reading, both totals
become plain black, indistinguishable by color from every other amount in the report (only
their row's bold "TOTAL INCOME"/"TOTAL EXPENSES" label and section position would
distinguish them). **Default used in this plan: flatten to pure black (literal reading),
consistent with "all text should be black" taken at face value.** If Tony wants to keep the
green/red distinction on just these two totals, the narrower fix is: exclude lines 62/74's
`totalAmountColor` from the §6B conversion, leaving `_incomeGreen`/`_expenseRed` (and their
constants) in place while every other text color still converts to black.

**Not an open question — out of scope, confirmed no ambiguity:** `_subtotalBg` (the faint
near-white background behind total rows) and the `_dividerColor`/`_thickDividerColor`
divider lines are backgrounds/borders, not text, and were not named in Tony's request
("behind the section titles" specifically). Left unchanged.

---

## 8. Database Impact
**Not applicable.** Pure rendering/styling change confined to one file. No migrations, RLS,
RPCs, triggers, or data reads affected.

---

## 9. Flutter Architecture Changes
- **`lib/features/financials/financials_report_builder.dart`** (only file touched):
  - `_buildItemRow`: add `maxLines: 1, overflow: pw.TextOverflow.clip` to the Amount cell's
    `pw.Text` (critical fix, §6A).
  - Add `const _textBlack = PdfColor.fromInt(0xFF000000);`; delete `_textDark`,
    `_textMuted`, `_incomeGreen`, `_expenseRed`, `_sectionHeaderBg` constants.
  - Replace all 24 text-color call sites (§4b table) with `_textBlack`.
  - `_buildSectionHeader`: drop the `backgroundColor` parameter and the container's
    `decoration`; update its 3 call sites to drop the background argument.
  - No changes to function signatures beyond `_buildSectionHeader` losing one parameter; no
    changes to sorting, grouping, totals math, empty-state guards, column widths, or divider
    styling.
- No changes to `financials_pdf_preview_screen.dart` or `financials_screen.dart` — confirmed
  via grep that neither file contains any `pw.Text` or `PdfColor` reference; all
  report-document text and color lives exclusively in `financials_report_builder.dart`.

---

## 10. Files to Create
None.

---

## 11. Files to Modify
| File | What changes |
|---|---|
| `lib/features/financials/financials_report_builder.dart` | (1) Add `maxLines: 1`/`overflow: pw.TextOverflow.clip` to `_buildItemRow`'s Amount cell (critical fix). (2) Consolidate all 24 text-color call sites to a new `_textBlack` (`0xFF000000`) constant; delete `_textDark`/`_textMuted`/`_incomeGreen`/`_expenseRed`. (3) Remove the background fill from `_buildSectionHeader` (drop `backgroundColor` param + `decoration`); update its 3 call sites; delete `_sectionHeaderBg`. |

---

## 12. Files Off-Limits
| File | Reason |
|---|---|
| `lib/features/financials/financials_pdf_preview_screen.dart` | No `pw.Text`/`PdfColor` reference exists in this file (confirmed via grep) — nothing here to change for a text-color/background request |
| `lib/features/financials/financials_screen.dart` | Same — call site only, no report-document rendering |
| `lib/features/financials/models/financial_entry.dart` | No model change needed or permitted |
| `lib/features/financials/financial_entry_repository.dart` | No new queries needed |
| `lib/features/financials/financials_controller.dart` | No state shape change needed |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | Entry form — out of scope |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart` | Gig pay form — out of scope |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | Entry detail view — out of scope |
| Any `supabase/migrations/*` file | No database impact — see §8 |

---

## 13. System Impact Map
| System | Impact |
|---|---|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected — no change to the `members`/`membersById` lookup logic, only to unrelated color constants in the same file |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — same client-side `pdf`/`printing` rendering path as prior rounds; no new platform-specific code |

---

## 14. Regression Risk
**MEDIUM.**
- Confined to a single file, no state/model/repository/database changes, no logic changes
  to sorting/grouping/totals/empty-state handling.
- Elevated from LOW because: (a) the diff touches roughly two dozen individual lines across
  nearly every function in the file — a wide *mechanical* footprint, even though each
  individual edit is a one-token color-constant swap; (b) §7's two open questions are
  default assumptions (literal "all text black"), not confirmed instructions — if Tony
  intended the narrower reading for either A or B, a third follow-up correction is likely;
  (c) real PDF rendering (page-break behavior, actual clip behavior of
  `pw.TextOverflow.clip` in the `pdf` package) remains an untested surface, same limitation
  every prior round of this feature has flagged.
- Not HIGH: deleting the old color constants converts "missed a call site" from a silent
  visual bug into a compile error (§6B), which meaningfully de-risks the mechanical breadth
  of this change. No sorting, grouping, math, or empty-state code is touched at all.

---

## 15. Engineer Task Breakdown

1. Confirm Open Questions A and B (§7) with Tony/Manager at Gate 2, or proceed on the
   stated literal-reading defaults (flatten both the dark/muted hierarchy and the
   green/red totals to pure black) if explicitly authorized.
2. In `_buildItemRow`, add `maxLines: 1` and `overflow: pw.TextOverflow.clip` to the Amount
   cell's `pw.Text` (current lines 284–291), matching the Entry type/Payer/Paid to cells.
   **This is the mandatory critical fix from QA — do this regardless of how Open Questions
   A/B resolve.**
3. Add `const _textBlack = PdfColor.fromInt(0xFF000000);` to the color-constants block.
4. Replace every `color:`/color-parameter occurrence of `_textDark`, `_textMuted`,
   `_incomeGreen`, and `_expenseRed` with `_textBlack` (all 24 call sites, §4b table) —
   subject to whatever narrower scope Open Questions A/B resolve to.
5. Delete the now-unused `_textDark`, `_textMuted`, `_incomeGreen`, `_expenseRed`
   constants (and `_sectionHeaderBg`, per Task 6) — do this only after step 4/6 is complete,
   so `flutter analyze` surfaces any missed call site as an undefined-identifier error
   before reporting done.
6. In `_buildSectionHeader`: remove the `backgroundColor` parameter and the
   `decoration: pw.BoxDecoration(color: backgroundColor)` line; keep the container's
   `padding` and `child` unchanged. Update all 3 call sites (Income/Expenses, Band Savings
   Account, Band Disbursements) to drop the background argument. Delete `_sectionHeaderBg`.
7. Do **not** touch `_subtotalBg`, `_dividerColor`, `_thickDividerColor`, column widths,
   padding/margin values, sort order, grouping logic, totals math, or empty-state guards
   anywhere in the file.
8. Run `flutter analyze` — must pass with 0 errors, 0 warnings (Gate 3). A leftover
   reference to any deleted constant will fail this step by design (§6B) — treat that as
   confirmation to go find the missed call site, not a plan defect.
9. Grep the file for `_textDark|_textMuted|_incomeGreen|_expenseRed|_sectionHeaderBg` and
   confirm zero matches remain (belt-and-suspenders alongside the compile-error check).

---

## 16. Verification Plan

**Tier 1 — Pre-build (must pass before the Engineer reports done):**
- `-- PRE-DEPLOY TEST 1:` `flutter analyze` returns 0 errors, 0 warnings on the modified
  file.
- `-- PRE-DEPLOY TEST 2:` `grep -n "_textDark\|_textMuted\|_incomeGreen\|_expenseRed\|_sectionHeaderBg" lib/features/financials/financials_report_builder.dart`
  returns zero matches.
- `-- PRE-DEPLOY TEST 3:` Manual code read confirming the Amount cell (`_buildItemRow`) now
  has `maxLines: 1` and `overflow: pw.TextOverflow.clip`, identical in form to the Entry
  type/Payer/Paid to cells.
- `-- PRE-DEPLOY TEST 4:` Manual code read confirming `_buildSectionHeader`'s returned
  `pw.Container` has no `decoration` property at all (not merely a transparent color) and
  still renders the title text inside its existing padding.
- `-- PRE-DEPLOY TEST 5:` Manual code read confirming `_subtotalBg`, `_dividerColor`,
  `_thickDividerColor`, all four `_colWidth*` constants, every sort (`compareTo`) call,
  every `fold` (totals) call, and every `isEmpty`/`return const []` empty-state guard are
  byte-for-byte unchanged from the Amendment-1-approved version — this diff should read as
  color/background token substitutions only, nothing else.

**Tier 2 — Post-build (run against a running app):**
- `-- POST-DEPLOY TEST 1:` Generate a combined report; visually confirm every text element
  (report title, band name, date range, section titles, column headers, item rows, totals,
  member names, disbursement lines, empty-state text) renders pure black — no gray, green,
  or red text anywhere, subject to however Open Questions A/B were resolved.
- `-- POST-DEPLOY TEST 2:` Visually confirm all four section-title rows (Income, Expenses,
  Band Savings Account, Band Disbursements) have no background fill — plain page background
  behind the bold title, still on its own row, same vertical spacing as before.
- `-- POST-DEPLOY TEST 3:` Generate a report with an income or expense entry whose
  formatted amount is wide (e.g. `$12,345.67`) — confirm it clips to a single line within
  the Amount column rather than wrapping (validates the critical fix under real `pdf`
  package text layout, not just a code read).
- `-- POST-DEPLOY TEST 4:` Confirm the total-row background tint (`_subtotalBg`) and both
  divider styles (thin/thick) are visually unchanged from the prior build.
- `-- POST-DEPLOY TEST 5:` Confirm Print and Share still function (untouched plumbing).
- `-- POST-DEPLOY TEST 6:` Tony reviews the rendered output against Open Questions A and B —
  confirm the literal-black reading reads correctly, or flag if either the muted hierarchy
  or the green/red totals should be restored (a follow-up amendment, not a defect in this
  one).

---

## 17. QA Regression Areas
- Critical fix: Amount cell behaves identically to its three sibling fixed-width cells
  (single line, clipped, no wrap) — confirm via code read and, ideally, a wide-amount test
  case.
- Every text element in the report renders pure black (`0xFF000000`), consistent with
  whatever Open Questions A/B were resolved to.
- Section-title rows have zero background fill; title text, padding, and row position are
  otherwise unchanged.
- `_subtotalBg`, `_dividerColor`, `_thickDividerColor` and all divider placement — unchanged
  (confirm via diff/code read that no line touching these three was altered).
- Column widths, sort order, grouping logic, totals math, empty-state handling — unchanged
  (confirm via diff/code read).
- `flutter analyze` passes with 0 errors, 0 warnings, with particular attention to whether
  any stray reference to a deleted color constant was left behind (would fail as a compile
  error, not silently).
- No regression to entry CRUD, gig pay flow, filters, Print/Share, or any file outside
  `financials_report_builder.dart` — none of those files are touched by this amendment.

---

## 18. Rollout / Migration Strategy
Not applicable — no database or backend deploy step, same as prior rounds.

---

## 19. Out of Scope
- Any change to `_subtotalBg` (total-row background) — not named in Tony's request, which
  specifically said "section titles."
- Any change to `_dividerColor`/`_thickDividerColor` or divider placement/width/height —
  these are lines/borders, not text.
- Any change to column widths, padding, margins, sort order, grouping, totals math, or
  empty-state handling — this amendment is a color/background-only edit.
- Resolving Open Questions A/B unilaterally — both proceed on the stated literal default but
  remain flagged for Tony's Gate 2 confirmation, not silently decided.
- Everything already covered as Out of Scope in `ARCHITECT_PLAN.md` §19 and
  `ARCHITECT_PLAN_AMENDMENT_1.md` §19 remains out of scope here.
