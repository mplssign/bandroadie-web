# ARCHITECT_PLAN_AMENDMENT_3.md

## 1. Feature Slug
`feature/financials-report-breakdown` (third amendment to the plan already approved and
built on this branch)

---

## 2. Amendment Context
`ARCHITECT_PLAN.md` (original), `ARCHITECT_PLAN_AMENDMENT_1.md`, and
`ARCHITECT_PLAN_AMENDMENT_2.md` have all been implemented; see `ENGINEER_REPORT.md`. Per
`QA_REPORT.md`:
- The original round: **APPROVED**.
- The Amendment 1 round: **REQUIRES CHANGES** (one critical Amount-cell defect).
- The Amendment 2 round: **APPROVED**, including the mandatory fix for Amendment 1's
  critical finding.

Work is still uncommitted on `feature/financials-report-breakdown`. Before committing, Tony
requested two more changes. This document amends the plan a third time; it does not replace
`ARCHITECT_PLAN.md`, `ARCHITECT_PLAN_AMENDMENT_1.md`, or `ARCHITECT_PLAN_AMENDMENT_2.md`, all
of which are left untouched. Only the delta described below is in scope.

---

## 3. Problem Summary
Two independent items, both confined to
`lib/features/financials/financials_report_builder.dart`:

1. Add a **Date** column before **Entry type** in the Income and Expenses row layout (making
   it a 6-column row: Date, Entry type, Payer, Paid to, Description, Amount).
2. **Remove the light gray background color behind the total rows** (`_subtotalBg`).

---

## 4. Investigation Findings

### 4a. Date column — data availability, CONFIRMED
`FinancialEntry.entryDate` (`lib/features/financials/models/financial_entry.dart:65`) is a
non-nullable `DateTime`. `_buildItemRow` (current file, lines 230–293) already receives the
full `entry` object as its first parameter, and `entry.entryDate` is already read one call
frame up, in `_buildItemizedSection` (line 157), to sort the section
(`sorted..sort((a, b) => a.entryDate.compareTo(b.entryDate))`) before rows are built. **No
new parameter or data plumbing is needed to reach `entryDate` inside `_buildItemRow`** — it
is already in scope via the existing `entry` argument.

### 4b. Existing date format for consistency — CONFIRMED, reuse verbatim
`_buildBandSavingsSection` (current file, line 308) already renders a date column in the
Band Savings Account section:
```dart
final dateFmt = DateFormat('MMM d, yyyy');
```
formatted per row via `dateFmt.format(entry.entryDate)` (line 321), rendered in
`_buildDateLineItem` at a **fixed width of 80** (line 353–354: `pw.SizedBox(width: 80, ...)`,
an inline literal, not a named constant).

**This is the only other date-rendering code in the file** (confirmed via full-file read;
`grep -n "DateFormat"` returns exactly one match). There is no competing format to choose
between — `'MMM d, yyyy'` (e.g. "Jan 5, 2026") is the file's sole precedent and is reused
verbatim for the new Income/Expenses Date column, at the same 80pt fixed width, for visual
consistency between the two sections of the same report.

### 4c. Column widths and page-width budget — CONFIRMED via direct math, fits without shrinking any column

**Page geometry** (confirmed by reading `financials_pdf_preview_screen.dart:96–104` and the
`pdf` package source, `pdf-3.13.0/lib/src/pdf/page_format.dart:57–61`):
- `_buildPdf` calls `pw.MultiPage(pageFormat: format, margin: const pw.EdgeInsets.all(50), ...)`
  with `format = PdfPageFormat.letter` (`financials_pdf_preview_screen.dart:134,154`).
- `PdfPageFormat.letter = PdfPageFormat(8.5 * inch, 11.0 * inch, ...)`, where `inch = 72.0`pt
  → page width = **612pt**.
- `MultiPage`'s explicit `margin: EdgeInsets.all(50)` is passed and overrides the
  page format's own default `marginAll`, so usable content width =
  `612 - 50 - 50 = 512pt`.

**Row-level padding** (confirmed, `_buildItemRow`, current line 242):
`pw.Container(... padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 16), child: pw.Row(...))`
→ available width for the Row's children = `512 - 16 - 16 = 480pt`. The column-header row
(`_buildItemizedColumnHeaders`, line 187) uses the identical `horizontal: 16` padding, so
both rows share the same 480pt budget and stay aligned.

**Current fixed-column total (5-column layout):**
| Column | Width |
|---|---|
| Entry type | 70pt |
| Payer | 80pt |
| Paid to | 80pt |
| Amount | 60pt |
| **Fixed total** | **290pt** |
| Description (`pw.Expanded`, remainder) | `480 − 290 = 190pt` |

**With the new Date column added at 80pt (per §4b, matching `_buildDateLineItem`):**
| Column | Width |
|---|---|
| Date (new) | 80pt |
| Entry type | 70pt |
| Payer | 80pt |
| Paid to | 80pt |
| Amount | 60pt |
| **Fixed total** | **370pt** |
| Description (`pw.Expanded`, remainder) | `480 − 370 = 110pt` |

**Conclusion (HIGH confidence, confirmed by arithmetic against the file's actual, already-
configured page format and margins — not assumed): the 6-column row fits within the page's
printable width without shrinking Entry type, Payer, Paid to, or Amount.** No column needs
an explicit width reduction. The only effect is that `Description` — which is already a
`pw.Expanded` (fills-remaining-space) cell, not a fixed width — automatically receives less
room: 110pt instead of 190pt, a consequence of `pw.Expanded`'s existing behavior, not a code
change. 110pt (roughly 1.5 cells' width, comparable to the Payer/Paid to column widths) is
still enough to wrap 2–3 words of description text; it is narrower than before but not
unreasonably cramped. This is **not** an open question requiring a design judgment call —
the math resolves it directly, so no fallback/shrink strategy is proposed or needed. Flagged
only as a QA visual-check item (§17) since the exact visual comfort of 110pt vs. 190pt is a
Tier 2 (real-rendering) concern, not a Tier 1 code-path concern.

### 4d. `_buildItemizedColumnHeaders()` — confirmed current structure, straightforward insertion point
Current header row (`_buildItemizedColumnHeaders`, lines 180–217) is a `pw.Row` with
`mainAxisAlignment: pw.MainAxisAlignment.spaceBetween` containing, in order: Entry type
(70pt) / Payer (80pt) / Paid to (80pt) / Description (`Expanded`) / Amount (60pt, right-
aligned). A "Date" label cell, styled identically to the other header cells
(`labelStyle`: 9pt, bold, `_textBlack`), inserted as the **first** child, before Entry type,
completes the mapping to the new data-row column order.

### 4e. `_subtotalBg` — confirmed every use site (supersedes Amendment 2's "do not touch" boundary)
`_subtotalBg = PdfColor.fromInt(0xFFF9FAFB)` (current file, line 17) is consumed in exactly
one place structurally — the `backgroundColor` parameter of `_buildSubtotalRow`
(lines 521–528, used at line 531: `decoration: pw.BoxDecoration(color: backgroundColor)`) —
and passed at exactly **3 call sites**, one per total row that uses it (confirmed via
`grep -n "_subtotalBg\|backgroundColor"`):
| Call site | Line | Total row |
|---|---|---|
| `_buildItemizedSection` | 167–168 | `TOTAL INCOME` / `TOTAL EXPENSES` |
| `_buildBandSavingsSection` | 330–331 | `TOTAL DEPOSITS` |
| `_buildBandDisbursementsSection` | 457–458 | `TOTAL DISBURSEMENTS` |

All four total rows in the report route through the same shared `_buildSubtotalRow` helper,
so removing the background is a single-function change plus 3 call-site argument drops —
structurally identical to how Amendment 2 §6C removed `_sectionHeaderBg` from
`_buildSectionHeader` (drop the parameter, drop the `decoration` line, update every call
site, delete the constant).

**Explicit supersession, stated as Amendment 2 itself required for changes to its own
predecessor's scope:** Amendment 2 §4c/§19 investigated `_subtotalBg` and explicitly left it
unchanged, because Tony's request at that time named only "the section titles," not the
total rows: *"Any change to `_subtotalBg` (total-row background) — not named in Tony's
request, which specifically said 'section titles.'"* **Tony is now asking for exactly that
— removal of the total-row background. This amendment supersedes Amendment 2 §4c and §19's
"do not touch `_subtotalBg`" boundary.** No other part of `_buildSubtotalRow` (font sizes,
weights, padding, label/amount text, the `totalAmountColor` parameter) changes — only the
background fill is removed, mirroring exactly how §6C of Amendment 2 removed
`_sectionHeaderBg` without touching any other property of `_buildSectionHeader`.

---

## 5. Reference Docs Consulted
No `docs/reference/financials/` doc exists (confirmed in the original plan §4, still true).
Consulted for this amendment: `ARCHITECT_PLAN.md`, `ARCHITECT_PLAN_AMENDMENT_1.md`,
`ARCHITECT_PLAN_AMENDMENT_2.md`, `ENGINEER_REPORT.md`, `QA_REPORT.md` (this feature's own
prior outputs — the authoritative record of what was built and approved), direct reading of
`financials_report_builder.dart` and `financials_pdf_preview_screen.dart` as currently on
disk (uncommitted, as-built through Amendment 2), and the `pdf` package source
(`pdf-3.13.0/lib/src/pdf/page_format.dart`, resolved from `~/.pub-cache`) to confirm
`PdfPageFormat.letter`'s literal dimensions rather than assuming them.

---

## 6. Proposed Solution

### A. Add a Date column before Entry type (6-column Income/Expenses row)

**1. New column-width constant**, alongside the existing four (current lines 175–178):
```dart
const double _colWidthDate = 80;
const double _colWidthEntryType = 70;
const double _colWidthPayer = 80;
const double _colWidthPaidTo = 80;
const double _colWidthAmount = 60;
```

**2. `_buildItemizedColumnHeaders()`** — insert a new first child, matching the existing
label-cell pattern exactly:
```dart
pw.SizedBox(
  width: _colWidthDate,
  child: pw.Text('Date', style: labelStyle),
),
```
placed immediately before the existing `Entry type` `SizedBox` (current line 191).

**3. `_buildItemRow`** — insert a new first cell in the `pw.Row`'s `children`, styled and
constrained identically to the Entry type/Payer/Paid to cells (fixed width, `maxLines: 1`,
`overflow: pw.TextOverflow.clip`, `singleLineStyle` — the file's established "no-wrap
fixed-width cell" convention, per §4c):
```dart
pw.SizedBox(
  width: _colWidthDate,
  child: pw.Text(
    dateFmt.format(entry.entryDate),
    style: singleLineStyle,
    maxLines: 1,
    overflow: pw.TextOverflow.clip,
  ),
),
```
placed immediately before the existing Entry type `SizedBox` (current line 247).

**4. Date formatting** — reuse `DateFormat('MMM d, yyyy')` verbatim (§4b). `_buildItemRow`
does not currently receive a `DateFormat`; the cleanest fit with the file's existing pattern
(it already threads a pre-built `moneyFmt: NumberFormat` all the way from
`buildFinancialsReportContent` down through `_buildItemizedSection` into `_buildItemRow`,
building it once rather than per-row) is to build `dateFmt` once in
`buildFinancialsReportContent` alongside the existing `moneyFmt` local, and thread it down
the same path:
- `buildFinancialsReportContent`: add `final dateFmt = DateFormat('MMM d, yyyy');` next to
  the existing `final moneyFmt = NumberFormat.currency(...)` (current line 30); pass
  `dateFmt: dateFmt` into both `_buildItemizedSection(...)` calls (Income and Expenses,
  current lines 53–61 and 65–73).
- `_buildItemizedSection`: add a `required DateFormat dateFmt` parameter; pass it through to
  each `_buildItemRow(entry, membersById, moneyFmt, dateFmt)` call (current line 162).
- `_buildItemRow`: add `DateFormat dateFmt` as a new parameter (order: append after the
  existing `moneyFmt` parameter, to minimize churn at the one call site).

**5. Column order (final, 6 columns):** Date (80pt) → Entry type (70pt) → Payer (80pt) →
Paid to (80pt) → Description (`Expanded`, ~110pt) → Amount (60pt, right-aligned). Fits the
480pt row budget without shrinking any fixed column — see §4c.

**What does NOT change:** `_resolvePaidTo`, the Entry type/Payer/Paid to/Amount cells'
existing widths and no-wrap styling, the Description cell's `Expanded`/wrapping behavior
(only its *effective* rendered width changes, automatically, as a result of adding a sibling
fixed column — no code touches Description directly), sort order (`entryDate` ascending,
unchanged), section totals math, empty-state handling, Band Savings Account, Band
Disbursements, `_buildSectionHeader`, `_buildThickDivider`.

### B. Remove the total-row background

In `_buildSubtotalRow` (current lines 521–554):
- Remove the `PdfColor backgroundColor` parameter from the function signature.
- Remove the `decoration: pw.BoxDecoration(color: backgroundColor)` line from the returned
  `pw.Container`. The container keeps its `padding` and `child` (the label/amount `pw.Row`)
  — the total row becomes plain text with no container fill, on the same row/line, at the
  same font sizes/weights, exactly as before minus the tint.
- Update all 3 call sites to drop the now-removed argument (§4e):
  - `_buildItemizedSection` (current lines 167–168):
    `_buildSubtotalRow(totalLabel, totalCents, moneyFmt, _subtotalBg, _textBlack, totalAmountColor)`
    → `_buildSubtotalRow(totalLabel, totalCents, moneyFmt, _textBlack, totalAmountColor)`
  - `_buildBandSavingsSection` (current lines 330–331):
    `_buildSubtotalRow('TOTAL DEPOSITS', totalCents, moneyFmt, _subtotalBg, _textBlack, _textBlack)`
    → `_buildSubtotalRow('TOTAL DEPOSITS', totalCents, moneyFmt, _textBlack, _textBlack)`
  - `_buildBandDisbursementsSection` (current lines 457–458):
    `_buildSubtotalRow('TOTAL DISBURSEMENTS', totalCents, moneyFmt, _subtotalBg, _textBlack, _textBlack)`
    → `_buildSubtotalRow('TOTAL DISBURSEMENTS', totalCents, moneyFmt, _textBlack, _textBlack)`
- Delete the now-unused `_subtotalBg` constant (current line 17).

**What does NOT change:** every other property of `_buildSubtotalRow` — padding, font
sizes/weights (12pt bold for both label and amount, per Amendment 1 §4c, unchanged), the
`textColor`/`amountColor` parameters and their `_textBlack`/`totalAmountColor` values (per
Amendment 2), `_dividerColor`, `_thickDividerColor`, and the thick-divider-above-and-below
placement specific to `TOTAL DISBURSEMENTS`.

**What changes overall:** `financials_report_builder.dart` only — `_buildItemizedColumnHeaders`,
`_buildItemRow`, `_buildItemizedSection`, `buildFinancialsReportContent` (Date column,
part A), and `_buildSubtotalRow` plus its 3 call sites (background removal, part B).
**What must not change:** `_buildSectionHeader`, `_buildDateLineItem`,
`_buildBandSavingsSection`'s and `_buildBandDisbursementsSection`'s own row/grouping/sorting
logic, `_buildDisbursementLineItem`, `_buildThickDivider`, `_resolvePaidTo`, `_dividerColor`,
`_thickDividerColor`, `_textBlack` — none of these are touched by either change.
`financials_pdf_preview_screen.dart` and `financials_screen.dart` — confirmed via the prior
amendment's grep that neither contains any `pw.Text`/`PdfColor`/date-formatting reference;
nothing in those files needs to change for either request.

---

## 7. Open Questions for Tony
**None.** Unlike Amendments 1 and 2, both changes in this amendment resolve to a single,
fully-determined design with no ambiguity requiring a default assumption:
- The Date column's format, width, and position are fixed by direct precedent
  (`_buildDateLineItem`'s existing `'MMM d, yyyy'` format and 80pt width, §4b) and direct
  arithmetic against the page's actual configured margins (§4c) — no judgment call was
  needed on which column to shrink, because none needs to shrink.
- The total-row background removal is a direct, narrowly-scoped mirror of a pattern already
  executed once in this feature (Amendment 2's `_sectionHeaderBg` removal) — no new judgment
  call.

---

## 8. Database Impact
**Not applicable.** Pure rendering change confined to one file. `entryDate` is already
fetched on every `FinancialEntry` (confirmed, §4a); no new column, query, or migration.

---

## 9. Flutter Architecture Changes
- **`lib/features/financials/financials_report_builder.dart`** (only file touched):
  - Add `const double _colWidthDate = 80;` to the column-width constants block.
  - `buildFinancialsReportContent`: add `final dateFmt = DateFormat('MMM d, yyyy');`; pass
    `dateFmt` into both `_buildItemizedSection(...)` calls.
  - `_buildItemizedSection`: add `required DateFormat dateFmt` parameter; pass through to
    `_buildItemRow`.
  - `_buildItemizedColumnHeaders`: add a "Date" label cell as the first `pw.Row` child.
  - `_buildItemRow`: add `DateFormat dateFmt` parameter; add a Date cell as the first `pw.Row`
    child, styled/constrained like its fixed-width siblings.
  - `_buildSubtotalRow`: remove the `backgroundColor` parameter and the `decoration` line
    from its returned `pw.Container`.
  - Update `_buildSubtotalRow`'s 3 call sites to drop the `_subtotalBg` argument.
  - Delete the `_subtotalBg` constant.
  - No new files, no new providers, no new dependencies. `DateFormat` is already imported
    (`package:intl/intl.dart`, current line 1) — no new import needed.
- No changes to `financials_pdf_preview_screen.dart` or `financials_screen.dart`.

---

## 10. Files to Create
None.

---

## 11. Files to Modify
| File | What changes |
|---|---|
| `lib/features/financials/financials_report_builder.dart` | (1) Add a Date column (80pt, `'MMM d, yyyy'` format, matching `_buildDateLineItem`'s existing convention) before Entry type in `_buildItemRow` and `_buildItemizedColumnHeaders`; thread a new `dateFmt: DateFormat` parameter from `buildFinancialsReportContent` through `_buildItemizedSection` into `_buildItemRow`. (2) Remove `_buildSubtotalRow`'s `backgroundColor` parameter and `decoration`; update its 3 call sites; delete the now-unused `_subtotalBg` constant. |

---

## 12. Files Off-Limits
| File | Reason |
|---|---|
| `lib/features/financials/financials_pdf_preview_screen.dart` | No `pw.Text`/`PdfColor`/date-formatting reference exists in this file (confirmed in Amendment 2 via grep, unchanged) — nothing here needs to change for either request |
| `lib/features/financials/financials_screen.dart` | Same — call site only, no report-document rendering |
| `lib/features/financials/models/financial_entry.dart` | `entryDate` already exists and is exactly the field needed; no model change needed or permitted |
| `lib/features/financials/financial_entry_repository.dart` | No new queries needed; `entry_date` is already fetched |
| `lib/features/financials/financials_controller.dart` | No state shape change needed |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | Entry form — out of scope |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart` | Gig pay form — out of scope |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | Entry detail view — out of scope |
| Any `supabase/migrations/*` file | No database impact — see §8 |

---

## 13. System Impact Map
| System | Impact |
|---|---|
| Gigs | unaffected — gig pay entries already populate `entryDate`; only rendered differently |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected — no change to `members`/`membersById` lookup logic |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — same client-side `pdf`/`printing` rendering path as every prior round; no new platform-specific code |

---

## 14. Regression Risk
**LOW.**
- Confined to a single file, no state/model/repository/database changes, no changes to
  sorting, grouping, or totals math (the Date column is purely additive display; the total
  row background removal touches only a `decoration` property).
- Both changes are narrow and mechanical, each following an established pattern already
  executed once in this feature: the Date column reuses `_buildDateLineItem`'s existing
  format/width verbatim (no new design decision); the background removal is a structural
  repeat of Amendment 2's `_sectionHeaderBg` removal.
- No Open Questions (§7) — unlike Amendments 1 and 2, there is no default-assumption risk of
  a follow-up correction, because the page-width arithmetic (§4c) fully resolves the one
  place this amendment could have required a judgment call.
- The one genuinely untested surface (unchanged limitation across every round of this
  feature) is real `pdf`-package text layout: whether the narrower ~110pt Description column
  wraps acceptably in practice. This is a Tier 2 visual concern, not a logic risk — worst
  case is a cosmetic follow-up, not a functional defect.

---

## 15. Engineer Task Breakdown
1. In `financials_report_builder.dart`, add `const double _colWidthDate = 80;` next to the
   existing `_colWidthEntryType`/`_colWidthPayer`/`_colWidthPaidTo`/`_colWidthAmount`
   constants (current lines 175–178).
2. In `buildFinancialsReportContent`, add `final dateFmt = DateFormat('MMM d, yyyy');` next
   to the existing `moneyFmt` local (current line 30); pass `dateFmt: dateFmt` into both
   `_buildItemizedSection(...)` calls (Income and Expenses).
3. Add `required DateFormat dateFmt` to `_buildItemizedSection`'s parameter list; pass it as
   an additional argument to the existing `_buildItemRow(entry, membersById, moneyFmt)` call
   inside its loop.
4. Add `DateFormat dateFmt` as a new parameter to `_buildItemRow` (appended after the
   existing `moneyFmt` parameter). Insert a new first `pw.Row` child — a `pw.SizedBox(width:
   _colWidthDate, child: pw.Text(dateFmt.format(entry.entryDate), style: singleLineStyle,
   maxLines: 1, overflow: pw.TextOverflow.clip))` — immediately before the existing Entry
   type `SizedBox`.
5. In `_buildItemizedColumnHeaders()`, insert a new first `pw.Row` child — a
   `pw.SizedBox(width: _colWidthDate, child: pw.Text('Date', style: labelStyle))` —
   immediately before the existing Entry type label cell.
6. In `_buildSubtotalRow`, remove the `PdfColor backgroundColor` parameter from the
   signature and remove the `decoration: pw.BoxDecoration(color: backgroundColor)` line from
   the returned `pw.Container` (keep `padding` and `child` unchanged).
7. Update all 3 `_buildSubtotalRow(...)` call sites (`_buildItemizedSection`,
   `_buildBandSavingsSection`, `_buildBandDisbursementsSection`) to drop the `_subtotalBg`
   argument in each call, per §6B's exact before/after listed above.
8. Delete the now-unused `_subtotalBg` constant (current line 17). Do this only after step 7
   is complete, so `flutter analyze` surfaces any missed call site as an undefined-identifier
   error before reporting done.
9. Do **not** touch `_buildSectionHeader`, `_buildDateLineItem`,
   `_buildBandSavingsSection`'s/`_buildBandDisbursementsSection`'s own grouping/sorting
   logic, `_buildDisbursementLineItem`, `_buildThickDivider`, `_resolvePaidTo`,
   `_dividerColor`, `_thickDividerColor`, `_textBlack`, or any `_colWidthEntryType`/
   `_colWidthPayer`/`_colWidthPaidTo`/`_colWidthAmount` value.
10. Run `flutter analyze` — must pass with 0 errors, 0 warnings (Gate 3).
11. Grep the file for `_subtotalBg` and confirm zero matches remain (belt-and-suspenders
    alongside the compile-error check from step 8).

---

## 16. Verification Plan

**Tier 1 — Pre-build (must pass before the Engineer reports done):**
- `-- PRE-DEPLOY TEST 1:` `flutter analyze` returns 0 errors, 0 warnings on the modified
  file.
- `-- PRE-DEPLOY TEST 2:` `grep -n "_subtotalBg" lib/features/financials/financials_report_builder.dart`
  returns zero matches.
- `-- PRE-DEPLOY TEST 3:` Manual code read confirming the Date cell in `_buildItemRow` uses
  `_colWidthDate` (80), `dateFmt.format(entry.entryDate)`, `maxLines: 1`, and
  `overflow: pw.TextOverflow.clip` — identical in form to the Entry type/Payer/Paid to/Amount
  cells.
- `-- PRE-DEPLOY TEST 4:` Manual code read confirming `_buildItemizedColumnHeaders()`'s new
  "Date" label cell uses `_colWidthDate` and appears in the same position (first) as the data
  row's Date cell, so headers and data stay column-aligned.
- `-- PRE-DEPLOY TEST 5:` Manual code read confirming `_buildSubtotalRow`'s returned
  `pw.Container` has no `decoration` property at all (not merely a transparent color) and
  still renders `label`/`amountCents` inside its existing `padding`.
- `-- PRE-DEPLOY TEST 6:` Manual code read confirming `_dividerColor`, `_thickDividerColor`,
  `_textBlack`, all five `_colWidth*` constants (including the new `_colWidthDate`), sort
  order, grouping logic, totals math, and empty-state guards are byte-for-byte unchanged from
  the Amendment-2-approved version — this diff should read as an additive Date column plus a
  background-property removal, nothing else.

**Tier 2 — Post-build (run against a running app):**
- `-- POST-DEPLOY TEST 1:` Generate a combined report; confirm every Income/Expenses row now
  shows Date as the first column, correctly formatted (e.g. "Jan 5, 2026"), followed by Entry
  type/Payer/Paid to/Description/Amount in the existing order.
- `-- POST-DEPLOY TEST 2:` Confirm the column-header row's "Date" label aligns with the data
  rows' Date column, and all six columns stay visually aligned between header and data rows.
- `-- POST-DEPLOY TEST 3:` Confirm Description still wraps correctly at its narrower
  effective width (~110pt) with a realistically long description — no text overlapping the
  Amount column, no broken row height.
- `-- POST-DEPLOY TEST 4:` Confirm all four total rows (`TOTAL INCOME`, `TOTAL EXPENSES`,
  `TOTAL DEPOSITS`, `TOTAL DISBURSEMENTS`) render with no background fill — plain page
  background behind the bold label/amount text, same vertical spacing and font
  sizes/weights as before.
- `-- POST-DEPLOY TEST 5:` Confirm the thin dividers between item rows and the thick dividers
  around `TOTAL DISBURSEMENTS` are visually unchanged.
- `-- POST-DEPLOY TEST 6:` Confirm Print and Share still function (untouched plumbing).

---

## 17. QA Regression Areas
- Date column: correct value (`entry.entryDate`, `'MMM d, yyyy'` format), correct position
  (first column), correct width (80pt), single-line/no-wrap, consistent with
  `_buildDateLineItem`'s existing Band Savings Account date rendering.
- Column-header row's "Date" label aligns with the data rows' Date column.
- Description column still wraps correctly at its new, narrower effective width; no visual
  breakage (overlap, clipping, row-height distortion).
- All four total rows (`TOTAL INCOME`/`TOTAL EXPENSES`/`TOTAL DEPOSITS`/`TOTAL DISBURSEMENTS`)
  have zero background fill; label/amount text, font sizes/weights, and padding are otherwise
  unchanged.
- `_dividerColor`, `_thickDividerColor`, and all divider placement (thin per-row, thick
  around Band Disbursements' total) — unchanged (confirm via diff/code read).
- Sort order, grouping logic, totals math, empty-state handling — unchanged (confirm via
  diff/code read); the Date column and background removal are purely additive/subtractive
  display changes with no logic-path modification.
- `flutter analyze` passes with 0 errors, 0 warnings.
- No regression to entry CRUD, gig pay flow, filters, Print/Share, Band Savings Account
  rendering, or Band Disbursements grouping — none of those code paths are touched by this
  amendment.

---

## 18. Rollout / Migration Strategy
Not applicable — no database or backend deploy step, same as every prior round.

---

## 19. Out of Scope
- Any change to `_dividerColor`/`_thickDividerColor` or divider placement/width/height —
  unrelated to either of Tony's two requests in this round.
- Any change to `_buildDateLineItem`'s own width/format — it is the source of truth this
  amendment reuses, not a target of modification.
- Resolving the 110pt Description width by proactively shrinking it further or widening the
  page margins — not requested, and §4c's arithmetic confirms it is not required for the
  6-column row to fit.
- Everything already covered as Out of Scope in `ARCHITECT_PLAN.md` §19,
  `ARCHITECT_PLAN_AMENDMENT_1.md` §19, and `ARCHITECT_PLAN_AMENDMENT_2.md` §19 remains out of
  scope here, **except** where explicitly superseded: Amendment 2's "do not touch
  `_subtotalBg`" boundary (§4c/§19) is superseded by this amendment's §4e/§6B — the total-row
  background is now in scope and removed.
