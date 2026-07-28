# Engineer Report

## Feature Slug
feature/financials-report-breakdown

## Feature Title
Financials PDF Report — Four-Section Breakdown Redesign

## Goal
Redesign the "Generate Report" PDF (`FinancialsPdfPreviewScreen`) from category-subtotal
rows into Tony's four-section mockup layout — itemized INCOME, itemized EXPENSES, BAND
SAVINGS ACCOUNT, and BAND DISBURSEMENTS — reusing existing `FinancialEntry` data with no
model, repository, or backend changes.

## Architect Tasks Completed
- [x] Task 1 — Open Questions 1–3 confirmed via Manager instruction prior to session start; proceeded on stated defaults (remove Net Income/Summary; omit description line when null/empty; disbursements remain income-only, `add_financial_entry_bottom_sheet.dart` untouched).
- [x] Task 2 — Created `financials_report_builder.dart`; moved `_buildSectionHeader`/`_buildLineItem`(→`_buildItemRow`/`_buildDateLineItem`)/`_buildSubtotalRow` logic into it as top-level functions; added `_buildThickDivider` helper distinct from the existing thin `dividerColor` rule.
- [x] Task 3 — Added `_buildHeader`: centered "Income and Expense Report" title, then bandName (left, bold, 24pt) / date-range (`_filterLabel`, right) row; dropped the "Generated {date}" stamp and `$_viewModeLabel Report` subtitle.
- [x] Task 4 — Added `_buildItemizedSection` (shared, parameterized by section title/empty-text/total-label/total-color): one row per entry sorted `entryDate` ascending, bold `category` + optional indented `description` + right-aligned `amountCents`; `TOTAL INCOME` / `TOTAL EXPENSES` closing row with thin rule above; preserved existing empty-state text.
- [x] Task 5 — Added `_buildBandSavingsSection`: filters `depositToSavings == true`, one row per entry (date / description-fallback-to-category / `depositToSavingsCents`), ascending sort, `TOTAL DEPOSITS` closing row; returns `const []` (renders nothing) when no entry qualifies.
- [x] Task 6 — Added `_buildBandDisbursementsSection`: flattens every `(userId, cents)` pair from every entry's `disbursements` map into per-entry line items tagged with description-or-category; grouped by `userId`, names resolved via `members` param with `"Member {id prefix}"` fallback for unmatched IDs; groups sorted by resolved name, line items within a group sorted by `entryDate` ascending; member name rendered once per group; `TOTAL DISBURSEMENTS` closing row with thick rule above **and** below; returns `const []` when no entry has a non-empty `disbursements` map.
- [x] Task 7 — Wired `buildFinancialsReportContent(...)` as the single entry point: header + Income + thick divider + Expenses + thick divider + Band Savings Account + Band Disbursements, preserving the existing empty-entries-overall guard.
- [x] Task 8 — In `financials_pdf_preview_screen.dart`: added `member_vm.dart` and `financials_report_builder.dart` imports; added `final List<MemberVM> members;` field (default `const []`); replaced `_buildPdf`'s inline body with a call to `buildFinancialsReportContent(...)`; removed `_buildNetIncomeRow`, `_buildSummaryBox`, `_buildSummaryLine` and the now-unused `netIncomeCents`/`savingsCents`-for-summary locals (per Open Question 1 default — remove, not retain).
- [x] Task 9 — In `financials_screen.dart`, `_openCombinedReport` now reads `ref.read(membersProvider).members` and passes it as `members:` into the `FinancialsPdfPreviewScreen(...)` call.
- [x] Task 10 — `flutter analyze` run; 0 errors, 0 warnings.

## Files Created
- `lib/features/financials/financials_report_builder.dart`

## Files Modified
- `lib/features/financials/financials_pdf_preview_screen.dart`
- `lib/features/financials/financials_screen.dart`

Note: the working tree also carries pre-existing, unrelated uncommitted changes to
`lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` and an untracked
`docs/features/bulk-import-flexible-columns/` directory. Per Manager instruction, these
predate this session, are not part of this feature, and were not touched — excluded from
the diff above and from this report's scope.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors / 0 warnings (ran against the full project after implementation and after formatting; also verified in isolation against the three affected files)

## Test Results
Not run — no existing test suite covers this report-rendering path, and the Architect plan does not require new tests (Verification Plan §16 specifies manual/code-read checks instead).

## Verification
Manual steps performed (Tier 1 / Pre-build, per plan §16):
- `flutter analyze` returns 0 errors on the three affected files, and 0 errors/warnings project-wide.
- Confirmed by code read: `_buildItemizedSection`'s `totalCents` folds over the same `incomeEntries`/`expenseEntries` list passed in (not a per-category re-derivation), so the itemized total is mathematically identical to the prior category-summed total for the same entry set — no double counting, no dropped entries.
- Confirmed by code read: `_buildBandSavingsSection` and `_buildBandDisbursementsSection` each `return const []` before building any header/row when their respective filter (`depositToSavings == true`, non-empty `disbursements`) matches zero entries — no broken/empty section headers render for bands with no deposits/disbursements.
- Confirmed by code read: `_buildBandDisbursementsSection` accumulates `totalCents` by summing every `item.amountCents` across every `userId` group during rendering, covering every `(userId, cents)` pair flattened from every entry's `disbursements` map — no member's cents dropped during flattening or grouping, including unmatched `userId`s (fallback label still counted).
- Not performed (requires a running app): Tier 2 post-build checks (§16 POST-DEPLOY TESTs 1–8) — generating an actual PDF against live band data, visual confirmation of thick/thin divider styling, and Print/Share regression checks on device. Flagged for QA.

## Deviations From Architect Plan
None. Open Questions 1–3 were resolved via the stated default assumptions per explicit
pre-session confirmation (Net Income row/Summary box removed entirely; description
fallback omitted rather than placeholder text; disbursements remain income-only,
`add_financial_entry_bottom_sheet.dart` untouched).

## Blockers Encountered
None.

## Ready For QA
Yes.

---

# Amendment 1

Everything above this line describes the original implementation (already QA-approved,
still uncommitted). Everything below describes the delta implemented against
`ARCHITECT_PLAN_AMENDMENT_1.md` in this session. QA should treat the two sections as
separate rounds of review — the original scope is unchanged by this amendment.

## Feature Slug
feature/financials-report-breakdown (amendment)

## Goal
Rework the Income/Expenses row layout into a 5-column single-row table (Entry type, Payer,
Paid to, Description, Amount — only Description wraps), add a matching column-header row,
and restyle the report's in-document title to bold/16pt/dark. Section titles, total rows,
Band Savings Account, and Band Disbursements were confirmed already correct and left
untouched.

## Architect Tasks Completed (Amendment §15)
- [x] Task 1 — Open Questions 1–4 (§7) confirmed via Manager instruction prior to session start; proceeded on stated defaults (fixed Payer/Paid-to column semantics, report title = in-document heading, add column-header row, change title color to `_textDark`).
- [x] Task 2 — Added `_buildItemizedColumnHeaders()` in `financials_report_builder.dart`: a `pw.Row` with the same five column widths as the data row (70/80/80/Expanded/60), 9pt bold `_textMuted` labels — "Entry type", "Payer", "Paid to", "Description", "Amount" (right-aligned). Called once per section in `_buildItemizedSection`, immediately after `_buildSectionHeader(...)` (only when the section has entries — empty-state text is unchanged).
- [x] Task 3 — Rewrote `_buildItemRow` to accept `entry`, `membersById`, and `moneyFmt`, rendering the 5-column layout: fixed-width `pw.SizedBox` (70pt Entry type / 80pt Payer / 80pt Paid to / 60pt Amount, each `maxLines: 1` + `TextOverflow.clip`) plus a `pw.Expanded` Description cell (9pt, wraps, blank when null). Added `_resolvePaidTo(entry, membersById)`: resolves `paidToUserId` against `members` first (live name), falls back to stored `paidToName` if the id isn't found, falls back to blank if both are null — mirrors the existing `nameFor` fallback convention in `_buildBandDisbursementsSection` without modifying that function.
- [x] Task 4 — Threaded `members` into `_buildItemizedSection`'s signature (builds a local `membersById` map once per section) and into both `buildFinancialsReportContent` call sites (Income and Expenses).
- [x] Task 5 — In `_buildHeader`, changed the title `pw.Text`'s style from `pw.TextStyle(fontSize: 12, color: _textMuted)` to `pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: _textDark)`.
- [x] Task 6 — Confirmed by diff: `_buildSectionHeader`, `_buildSubtotalRow`, `_buildDateLineItem`, `_buildBandSavingsSection`, `_buildBandDisbursementsSection`, `_buildDisbursementLineItem`, `_buildThickDivider` are byte-for-byte unchanged from the QA-approved version.
- [x] Task 7 — `flutter analyze` run; 0 errors, 0 warnings.

## Files Created
- none

## Files Modified
- `lib/features/financials/financials_report_builder.dart` (only file touched by this amendment)

No other file was touched. `financials_pdf_preview_screen.dart` and `financials_screen.dart`
already pass `members` through from the original implementation; no new data needed to
reach the builder function.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors / 0 warnings (project-wide, after this amendment's changes and after `dart format`)

## Test Results
Not run — no existing test suite covers this rendering path; the amendment's Verification
Plan (§16) specifies manual/code-read checks instead of automated tests.

## Verification
Manual steps performed (Tier 1 / Pre-build, per amendment §16):
- `flutter analyze` returns 0 errors on the modified file, and 0 errors/warnings project-wide.
- Confirmed by code read: Entry type, Payer, Paid to, and Amount cells all use fixed-width `pw.SizedBox` with `maxLines: 1` and `overflow: pw.TextOverflow.clip`; Description is the only cell without a non-wrap constraint (plain `pw.Expanded` + `pw.Text`, default `softWrap`).
- Confirmed by code read: `_resolvePaidTo` checks `entry.paidToUserId` against `membersById` first, falls back to `entry.paidToName` when the id is non-null but unmatched, falls back to `''` when `paidToUserId` is null and `paidToName` is also null — no null-access crash in any branch.
- Confirmed by diff: `_buildSectionHeader` and `_buildSubtotalRow` (and all other off-limits helpers) show zero changes from the QA-approved version — verified by reading the full file after edits and comparing against the pre-amendment version described in `QA_REPORT.md`/original `ENGINEER_REPORT.md`.
- Not performed (requires a running app): Tier 2 post-build checks (§16 POST-DEPLOY TESTs 1–6) — generating an actual PDF with real payer/paid-to/member data, visual confirmation of column alignment and wrapping, and Print/Share regression checks on device. Flagged for QA.

## Deviations From Architect Plan
None. Open Questions 1–4 (§7) were resolved via the stated default assumptions per explicit
pre-session confirmation:
- Payer/Paid-to columns are fixed in meaning (not dynamically flipped between Income/Expenses).
- "Report title" = the PDF's in-document heading in `_buildHeader`, not the on-screen AppBar title.
- Column-header row added above each Income/Expenses section.
- Report title color changed from `_textMuted` to `_textDark` alongside the bold/16pt change.

## Blockers Encountered
None.

## Ready For QA
Yes.

---

# Amendment 2

Everything above this line describes the original implementation and Amendment 1 (Amendment
1's Income/Expenses row layout was QA-approved except for one critical Amount-cell defect,
fixed below). Everything below describes the delta implemented against
`ARCHITECT_PLAN_AMENDMENT_2.md` in this session. QA should treat this as a third round of
review — the original scope and Amendment 1's non-color changes are unchanged by this
amendment.

## Feature Slug
feature/financials-report-breakdown (second amendment)

## Goal
Fix QA's Amendment 1 critical finding (Amount cell missing `maxLines`/`overflow` in
`_buildItemRow`) and consolidate all report text to pure black with no background fill
behind section titles, per Tony's request. Both Open Questions (§7) were confirmed to
proceed on the literal-reading defaults: flatten the dark/muted two-tone hierarchy fully,
and flatten the green/red TOTAL INCOME/TOTAL EXPENSES amount colors fully — no color
distinctions preserved anywhere.

## Architect Tasks Completed (Amendment 2 §15)
- [x] Task 1 — Open Questions A and B (§7) confirmed via pre-session instruction; proceeded on the full-flatten defaults (no muted/dark hierarchy retained, no green/red total distinction retained).
- [x] Task 2 — Added `maxLines: 1` and `overflow: pw.TextOverflow.clip` to the Amount cell's `pw.Text` in `_buildItemRow`, matching the Entry type/Payer/Paid to cells exactly. Mandatory critical fix, done regardless of Open Questions A/B.
- [x] Task 3 — Added `const _textBlack = PdfColor.fromInt(0xFF000000);` to the color-constants block.
- [x] Task 4 — Replaced every `color:`/color-parameter occurrence of `_textDark`, `_textMuted`, `_incomeGreen`, and `_expenseRed` with `_textBlack` (all 24 call sites), per the full-flatten default for both Open Questions.
- [x] Task 5 — Deleted the now-unused `_textDark`, `_textMuted`, `_incomeGreen`, `_expenseRed` constants (and `_sectionHeaderBg`, per Task 6) only after all call sites were converted, so `flutter analyze` would surface any missed reference as a compile error before reporting done.
- [x] Task 6 — In `_buildSectionHeader`: removed the `backgroundColor` parameter and the `decoration: pw.BoxDecoration(color: backgroundColor)` line; container keeps its `padding` and `child` unchanged. Updated all 3 call sites (Income/Expenses, Band Savings Account, Band Disbursements) to drop the background argument. Deleted `_sectionHeaderBg`.
- [x] Task 7 — Confirmed by code read: `_subtotalBg`, `_dividerColor`, `_thickDividerColor`, all four `_colWidth*` constants, column widths, padding/margins, sort order, grouping logic, totals math, and empty-state guards are untouched — this diff is color/background token substitutions plus the one Amount-cell overflow fix, nothing else.
- [x] Task 8 — `flutter analyze` run; 0 errors, 0 warnings (both in isolation on the modified file and project-wide).
- [x] Task 9 — `grep -n "_textDark\|_textMuted\|_incomeGreen\|_expenseRed\|_sectionHeaderBg" lib/features/financials/financials_report_builder.dart` returns zero matches — confirmed no leftover references to any deleted constant.

## Files Created
- none

## Files Modified
- `lib/features/financials/financials_report_builder.dart` (only file touched by this amendment)

No other file was touched. `financials_pdf_preview_screen.dart` and `financials_screen.dart`
contain no `pw.Text`/`PdfColor` reference (confirmed via grep prior to editing) — nothing in
those files needed to change for this text-color/background request.

Note: the working tree still carries pre-existing, unrelated uncommitted changes to
`lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` and an untracked
`docs/features/bulk-import-flexible-columns/` directory, flagged in every prior round of
this feature. These predate this session, are not part of this feature, and were not
touched — excluded from this report's scope.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors / 0 warnings (ran in isolation against the modified file, and project-wide
after this amendment's changes and after `dart format`)

## Test Results
Not run — no existing test suite covers this rendering path; the amendment's Verification
Plan (§16) specifies manual/code-read checks instead of automated tests.

## Verification
Manual steps performed (Tier 1 / Pre-build, per amendment §16):
- `flutter analyze` returns 0 errors, 0 warnings on the modified file, and project-wide.
- `grep -n "_textDark\|_textMuted\|_incomeGreen\|_expenseRed\|_sectionHeaderBg" lib/features/financials/financials_report_builder.dart` returns zero matches.
- Confirmed by code read: the Amount cell in `_buildItemRow` now has `maxLines: 1` and `overflow: pw.TextOverflow.clip`, identical in form to the Entry type/Payer/Paid to cells immediately above it.
- Confirmed by code read: `_buildSectionHeader`'s returned `pw.Container` has no `decoration` property at all (removed entirely, not set to transparent) and still renders the title text inside its existing `padding`.
- Confirmed by code read: `_subtotalBg`, `_dividerColor`, `_thickDividerColor`, all four `_colWidth*` constants, every sort (`compareTo`) call, every `fold` (totals) call, and every `isEmpty`/`return const []` empty-state guard are unchanged from the Amendment-1-approved version — this diff reads as color/background token substitutions plus the one Amount-cell fix, nothing else.
- Not performed (requires a running app): Tier 2 post-build checks (§16 POST-DEPLOY TESTs 1–6) — visual confirmation that all text renders pure black, section-title rows have no background fill, a wide formatted amount clips to one line under real `pdf` package text layout, the total-row background tint and dividers are visually unchanged, and Print/Share still function. Flagged for QA.

## Deviations From Architect Plan
None. Open Questions A and B (§7) were resolved via the stated literal-reading defaults per
explicit pre-session confirmation:
- Open Question A: the `_textDark`/`_textMuted` two-tone hierarchy is fully flattened to pure black — no secondary/muted tone preserved anywhere.
- Open Question B: the green/red `TOTAL INCOME`/`TOTAL EXPENSES` amount colors are fully flattened to pure black — no semantic color distinction preserved on either total.

## Blockers Encountered
None.

## Ready For QA
Yes.

---

# Amendment 3

Everything above this line describes the original implementation, Amendment 1, and
Amendment 2 (all previously QA-approved, still uncommitted). Everything below describes the
delta implemented against `ARCHITECT_PLAN_AMENDMENT_3.md` in this session. QA should treat
this as a fourth round of review — the original scope and Amendments 1–2's changes are
unchanged by this amendment.

## Feature Slug
feature/financials-report-breakdown (third amendment)

## Goal
Add a Date column (80pt, `'MMM d, yyyy'`, matching `_buildDateLineItem`'s existing
convention) as the first column in the Income/Expenses item rows and column-header row, and
remove the light-gray background fill behind all four total rows (`_subtotalBg`). No Open
Questions this round — the plan was fully determined.

## Architect Tasks Completed (Amendment 3 §15)
- [x] Task 1 — Added `const double _colWidthDate = 80;` alongside the existing `_colWidthEntryType`/`_colWidthPayer`/`_colWidthPaidTo`/`_colWidthAmount` constants.
- [x] Task 2 — Added `final dateFmt = DateFormat('MMM d, yyyy');` in `buildFinancialsReportContent`, next to the existing `moneyFmt` local; passed `dateFmt:` into both `_buildItemizedSection(...)` calls (Income and Expenses).
- [x] Task 3 — Added `required DateFormat dateFmt` to `_buildItemizedSection`'s parameter list; passed it through to each `_buildItemRow(entry, membersById, moneyFmt, dateFmt)` call.
- [x] Task 4 — Added `DateFormat dateFmt` as a new parameter to `_buildItemRow` (appended after the existing `moneyFmt` parameter). Inserted a new first `pw.Row` child — a `pw.SizedBox(width: _colWidthDate, ...)` rendering `dateFmt.format(entry.entryDate)` with `singleLineStyle`, `maxLines: 1`, `overflow: pw.TextOverflow.clip` — immediately before the existing Entry type cell.
- [x] Task 5 — In `_buildItemizedColumnHeaders()`, inserted a new first `pw.Row` child — a `pw.SizedBox(width: _colWidthDate, child: pw.Text('Date', style: labelStyle))` — immediately before the existing Entry type label cell.
- [x] Task 6 — In `_buildSubtotalRow`, removed the `PdfColor backgroundColor` parameter from the signature and the `decoration: pw.BoxDecoration(color: backgroundColor)` line from the returned `pw.Container`; `padding` and `child` unchanged.
- [x] Task 7 — Updated all 3 `_buildSubtotalRow(...)` call sites (`_buildItemizedSection`, `_buildBandSavingsSection`, `_buildBandDisbursementsSection`) to drop the `_subtotalBg` argument.
- [x] Task 8 — Deleted the now-unused `_subtotalBg` constant, done only after all 3 call sites were updated (step 7), so `flutter analyze` would have surfaced any missed call site as an undefined-identifier error before reporting done.
- [x] Task 9 — Confirmed by code read: `_buildSectionHeader`, `_buildDateLineItem`, `_buildBandSavingsSection`'s/`_buildBandDisbursementsSection`'s own grouping/sorting logic, `_buildDisbursementLineItem`, `_buildThickDivider`, `_resolvePaidTo`, `_dividerColor`, `_thickDividerColor`, `_textBlack`, and the existing `_colWidthEntryType`/`_colWidthPayer`/`_colWidthPaidTo`/`_colWidthAmount` values are untouched — this diff is an additive Date column plus a `_subtotalBg`/`backgroundColor` removal, nothing else.
- [x] Task 10 — `flutter analyze` run; 0 errors, 0 warnings (in isolation on the modified file, and project-wide).
- [x] Task 11 — `grep -n "_subtotalBg" lib/features/financials/financials_report_builder.dart` returns zero matches — confirmed no leftover reference to the deleted constant.

## Files Created
- none

## Files Modified
- `lib/features/financials/financials_report_builder.dart` (only file touched by this amendment)

No other file was touched. `financials_pdf_preview_screen.dart` and `financials_screen.dart`
contain no `pw.Text`/`PdfColor`/date-formatting reference (confirmed via grep in Amendment
2, unchanged) — nothing in those files needed to change for either of this round's requests.

Note: the working tree still carries pre-existing, unrelated uncommitted changes to
`lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` and an untracked
`docs/features/bulk-import-flexible-columns/` directory, flagged in every prior round of
this feature. These predate this session, are not part of this feature, and were not
touched — excluded from this report's scope.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors / 0 warnings (ran in isolation against the modified file, and project-wide
after this amendment's changes and after `dart format`)

## Test Results
Not run — no existing test suite covers this rendering path; the amendment's Verification
Plan (§16) specifies manual/code-read checks instead of automated tests.

## Verification
Manual steps performed (Tier 1 / Pre-build, per amendment §16):
- `flutter analyze` returns 0 errors, 0 warnings on the modified file, and project-wide.
- `grep -n "_subtotalBg" lib/features/financials/financials_report_builder.dart` returns zero matches.
- Confirmed by code read: the Date cell in `_buildItemRow` uses `_colWidthDate` (80), `dateFmt.format(entry.entryDate)`, `maxLines: 1`, and `overflow: pw.TextOverflow.clip` — identical in form to the Entry type/Payer/Paid to/Amount cells.
- Confirmed by code read: `_buildItemizedColumnHeaders()`'s new "Date" label cell uses `_colWidthDate` and appears first, in the same position as the data row's Date cell, so headers and data stay column-aligned.
- Confirmed by code read: `_buildSubtotalRow`'s returned `pw.Container` has no `decoration` property at all (removed entirely, not set to transparent) and still renders `label`/`amountCents` inside its existing `padding`.
- Confirmed by code read: `_dividerColor`, `_thickDividerColor`, `_textBlack`, all five `_colWidth*` constants (including the new `_colWidthDate`), sort order, grouping logic, totals math, and empty-state guards are unchanged from the Amendment-2-approved version — this diff reads as an additive Date column plus a background-property removal, nothing else.
- Not performed (requires a running app): Tier 2 post-build checks (§16 POST-DEPLOY TESTs 1–6) — visual confirmation that Date renders as the first column with correct formatting and alignment between header/data rows, Description still wraps acceptably at its narrower ~110pt effective width, all four total rows render with no background fill, dividers are visually unchanged, and Print/Share still function. Flagged for QA.

## Deviations From Architect Plan
None. No Open Questions this round (§7) — both changes resolved to a single, fully-determined
design with no default assumption required.

## Blockers Encountered
None.

## Ready For QA
Yes.
