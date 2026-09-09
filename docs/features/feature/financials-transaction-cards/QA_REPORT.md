# QA_REPORT — feature/financials-transaction-cards

## Feature Slug
`feature/financials-transaction-cards`

## Feature Title
Financials screen — replace transaction table with cards, add summary header

## Cycle Number
6

## Final Verdict
**APPROVED**

## Validation Summary
Cycle 6 is a design-reversal revision landing directly on the Cycle 4 tree: it reintroduces `FinancialDateFilter { allTime, thisYear, thisMonth }` (no `custom`) to replace Cycle 4's `selectedYear: int` scalar, defaults the filter to `thisYear`, wires an inline `AppDropdown<FinancialDateFilter>` into `_SummaryHeader` (rendering `'This year'` as literal text, not a numeral), swaps `FinancialsPdfPreviewScreen`'s constructor from `selectedYear: int` back to `dateFilter: FinancialDateFilter`, and preserves Cycle 5's never-implemented empty-state build restructuring verbatim (header/dropdown stay visible when the list is empty). Branch `feature/financials-transaction-cards` matches the slug in `ARCHITECT_PLAN.md` (Cycle 6 Scope Expansion section) and `ENGINEER_REPORT.md` (Cycle 6, Ready For QA: Yes). I read the full Cycle 6 plan section (Problem Summary through QA Regression Areas) and the full Engineer report, then independently reviewed every hunk of the uncommitted working-tree diff (`git diff HEAD`) rather than relying on the Engineer's line-by-line claims. Per the Manager's explicit note (and the Engineer report's own caveat), `git diff HEAD` conflates Cycles 1–6's uncommitted deltas into one net diff since nothing has been committed yet — this is expected, not a red flag, and I focused verification on confirming the Cycle 6 task list is present and correct in the diff's *end state*, not on reconciling the Change Budget table against a clean isolated diff. Analyzer and all four remaining financials widget test files were independently re-run and pass clean (39/39), matching the Engineer's claimed results exactly.

## Architect Scope Review
- `GIT_OPTIONAL_LOCKS=0 git status --porcelain` shows the working tree modifies exactly six files under `lib/`/`test/`: `financials_controller.dart`, `financials_pdf_preview_screen.dart`, `financials_screen.dart`, `summary_header_test.dart`, `transaction_card_test.dart`, `transactions_list_header_test.dart` — this is exactly the plan's Cycle 6 "Files to Modify" list, and matches the Engineer report's "Files Modified" list. No other `lib/`/`test/` file shows a diff.
- Confirmed `test/features/financials/widgets/year_selector_test.dart` is gone from the working tree (`test -e` → not found) and untracked (`git ls-files | grep` → empty) — matches the plan's Cycle 6 "Files to Delete" instruction and the Engineer report's claim.
- Confirmed zero diff on every Cycle 6 "Files Off-Limits" entry: `lib/features/financials/widgets/**` (details sheet, add/edit sheet, gig pay sheet), `lib/features/financials/financial_entry_repository.dart`, `lib/features/financials/models/financial_entry.dart`, `lib/features/financials/financials_report_builder.dart`, `lib/components/ui/app_dropdown.dart`, `lib/components/ui/README.md`, all `supabase/migrations/**`, and `pubspec.yaml` — verified via targeted `git status --porcelain` against each path, all empty.
- Grepped `lib/**` for `selectedYear|setSelectedYear|_availableYears|_YearSelector|FinancialDateFilter.custom|customStartDate|customEndDate|setCustomDateRange|_pickCustomRange|showDateRangePicker|_DateFilterRow|_FilterChip` — zero matches anywhere in production code. Also grepped for `forui` and `PopupMenuButton` in `financials_screen.dart`/`financials_pdf_preview_screen.dart` — zero matches, confirming all Forui access goes through `AppDropdown` and no legacy popup-menu control survives.
- No new provider, controller, repository, or model. `IntrinsicWidth` has two pre-existing precedents in the codebase (`lib/components/ui/app_date_picker.dart`, `lib/features/home/widgets/rehearsal_card.dart`) — the Cycle 6 call site follows an established pattern, not a new one.
- Two untracked, unrelated docs files remain in the working tree (`docs/features/bug/demo-session-cleanup-orphaned-anonymous-users/PR_BODY.md`, `docs/features/feature/financials-transaction-cards/PR_BODY.md`) — neither touches any file in this plan's scope, noted for Manager's awareness only.

## Completeness Check
All 7 Cycle 6 Engineer tasks from the plan's Task Breakdown are present and correct in the current working-tree state, verified against the actual diff/file content (not just the report's checklist):
1. **Enum reintroduction + state-shape swap** — `enum FinancialDateFilter { allTime, thisYear, thisMonth }` present with exactly 3 cases, no `custom`. `selectedYear` field, its constructor/`copyWith` params, and its runtime-default initialiser are gone. `dateFilter: FinancialDateFilter` field added with a compile-time-`const` default of `FinancialDateFilter.thisYear`; the `FinancialsState` constructor is `const` again (verified in file). ✅
2. **Notifier mutation method swap** — `setSelectedYear(int)` absent; `setDateFilter(FinancialDateFilter filter) { state = state.copyWith(dateFilter: filter); }` present, matching the plan's exact body. ✅
3. **`FinancialsPdfPreviewScreen` reconciliation** — constructor takes `required FinancialDateFilter dateFilter` (no `selectedYear` param, no `customStartDate`/`customEndDate`); `_filterLabel` is the exact 3-case switch (`allTime → 'All time'`, `thisYear → 'Year ${now.year}'`, `thisMonth → DateFormat('MMMM yyyy').format(now)`); no `custom` case. `import 'package:intl/intl.dart';` present. ✅
4. **Inline `AppDropdown<FinancialDateFilter>` + label helper in `financials_screen.dart`** — `import '../../components/ui/app_dropdown.dart';` present; `_dateFilterLabel(FinancialDateFilter)` top-level helper present with the exact three strings (`'All time'`, `'This year'`, `'This month'`); `_SummaryHeader.build`'s single `Text('${state.selectedYear} • …')` line replaced with `Row([IntrinsicWidth(AppDropdown<FinancialDateFilter>(value: state.dateFilter, onChanged: ..., format: _dateFilterLabel, items: FinancialDateFilter.values.map(...))), Text(' • N transactions')])`. `_openCombinedReport` passes `dateFilter: state.dateFilter`. ✅
5. **Empty-state build restructuring (Cycle 5, re-adopted)** — `_FinancialsScreenState.build`'s `Expanded` block is `state.error != null ? _ErrorState : Column([_SummaryHeader, _TransactionsListHeader, SizedBox(space8), Expanded(isLoading ? spinner : filtered.isEmpty ? _EmptyState : ListView.separated)])` — `_SummaryHeader` is no longer nested inside the `filtered.isEmpty` conditional. Standalone filter-row render call and its surrounding `SizedBox`es are collapsed to a single `SizedBox(height: Spacing.space16)`. ✅
6. **`_YearSelector`/`_YearSelectorChip`/`_availableYears` deletion** — confirmed absent via grep across `lib/`. ✅
7. **Test updates** — `summary_header_test.dart` contains all 6 new Cycle 6 cases specified in the plan (default-`thisYear`-non-null, textual `'This year'` label with numeral-absence guard, 3-item enum-order list, exact label strings, `onChanged` dispatch, and the empty-state fix case), plus the 4 rewritten split-shape assertions replacing the Cycle 4 merged-string ones. `year_selector_test.dart` deleted. ✅

**One completeness/reporting gap found, not blocking:** the Engineer report and the plan's own "Files to Modify" section both state `transaction_card_test.dart` and `transactions_list_header_test.dart` require "no edits"/"no change" under Cycle 6 (byte-identical to their Cycle 4 state). This is only true for `transaction_card_test.dart`. `transactions_list_header_test.dart` **was** edited under Cycle 6 — beyond the year-relative fixture default it already had, its two sort-toggle assertions were changed from Cycle 4's merged form (`find.text('$year • 3 transactions')`, per Cycle 4's own QA report) to Cycle 6's split form (`find.text(' • 3 transactions')`), which was a necessary correction once `_SummaryHeader` split into a dropdown + adjacent text. The change is correct and required — this is the same class of plan-assumption gap the Cycle 4 QA report already flagged once for this exact file — but neither this plan's "no change" claim nor the Engineer report's "no edits required" claim is accurate. See Issues Found → Suggestions.

## Behavior Verification
Code-path analysis only (no runtime/device testing performed — categorically excluded from QA scope; Manual Verification Punch List below is Tony's to run and is copied verbatim from the plan's Cycle 6 Owner-run punch list).
- `_applyDateFilter`'s 3-case switch (`allTime` → unfiltered, `thisYear` → year match, `thisMonth` → year+month match, trailing newest-first sort preserved) is byte-for-byte the plan's Proposed Solution → (a) body — confirmed by reading the current file content directly.
- `dateFilteredEntries` (report data path) still calls `_applyDateFilter(allEntries)` unchanged in structure, now filtered by `dateFilter` instead of `selectedYear` — the report continues to receive a filtered, newest-first list. `_openCombinedReport` passes `dateFilter: state.dateFilter`, matching the constructor's new required param — a mismatch here would be a compile error, and `flutter analyze` confirms none exists.
- `AppDropdown<FinancialDateFilter>.value` is always `state.dateFilter`, a non-nullable field with a compile-time-const default — the dropdown can never render in a null/unselected state, matching the plan's "non-null selection guarantee."
- `_dateFilterLabel` is the single source of truth for both the collapsed dropdown label (`format: _dateFilterLabel`) and each menu item's `Text` child, preventing label-drift between collapsed and expanded views — confirmed both call sites reference the same function.
- The empty-state fix: `_SummaryHeader` (and its dropdown) now render at the same level as the loading/error/list content in every non-error branch, per the restructured `Expanded` block — confirmed the header is never nested inside `filtered.isEmpty ? ... : ...`.

## Regression Check
**LOW**.
- Auth/session/routing/init order: untouched — `FinancialsNotifier.build()`'s `bandId` gating logic is unchanged; the only controller change is the state/enum shape and the two mutation methods.
- Supabase RPC signatures/params: n/a — no RPC touched, confirmed zero `supabase/migrations/**` diff.
- Platform parity: pure shared-Flutter-widget change (`AppDropdown`/`FSelect.rich` renders natively cross-platform); no `Platform.isIOS`/`kIsWeb` branch touched.
- Controller/FocusNode disposal, `setState` after async gaps, rebuild triggers: no new `StatefulWidget`, no new async gap, no new disposal-eligible resource introduced. `_SummaryHeader` remains a `ConsumerWidget` with no local state.
- One behavior-relevant, in-scope semantic shift (intended by the plan, not a regression): `thisYear`'s collapsed label now reads `'This year'` instead of the numeral — this is Tony's explicit Cycle 6 directive, not an accidental change, and is the primary test/punch-list gate.
- Sort toggle (Cycle 1), `_SavingsSheet` (filter-agnostic, reads `state.allEntries`), and the details sheet (untouched since Cycle 1–3) are untouched code paths — confirmed no diff touches any of them.

## Database Safety
Not applicable — no schema change, no new/changed RPC, no RLS change, no migration file in the diff. Confirmed via `git status --porcelain supabase/migrations/` showing zero touched files.

## Analyzer Results
Independently re-ran:
`flutter analyze lib/features/financials/financials_controller.dart lib/features/financials/financials_pdf_preview_screen.dart lib/features/financials/financials_screen.dart test/features/financials/widgets/summary_header_test.dart test/features/financials/widgets/transaction_card_test.dart test/features/financials/widgets/transactions_list_header_test.dart test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart`
Result: **`No issues found! (ran in 1.1s)`** — clean at every severity across all seven changed/touched files, matching the Engineer report's claim.

## Test Results
Independently re-ran:
`flutter test test/features/financials/widgets/transaction_card_test.dart test/features/financials/widgets/summary_header_test.dart test/features/financials/widgets/transactions_list_header_test.dart test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart`
Result: **39 passed, 0 failed** — matches the Engineer report's claimed result exactly. Confirmed the empty-state fix test (`'inline dropdown remains visible and its onChanged callback wired when filteredEntries is empty for the selected filter'`) and the numeral-absence guard test (`'AppDropdown format renders "This year" text, not a year numeral, for the thisYear case'`) are both present in the run and passing — these are the plan's two Critical test gates (Tier 1 items #8 and #9).

## Diff Safety Review
- No secrets/API keys found in the diff.
- Grepped the full `lib/`/`test/` diff for `TODO|FIXME|debugPrint\(|api[_-]?key|secret|password` — zero matches.
- No leftover test scaffolding, no accidental deletions outside the stated scope, no unrelated formatting churn.

## Change Budget Review
Per the Manager's explicit instruction, `git diff HEAD --numstat` conflates all of Cycles 1–6's uncommitted deltas (nothing has been committed since Cycle 3), so it cannot be mechanically reconciled against the plan's Cycle 6 Change Budget table, which was written for an isolated Cycle 4→6 diff. Numbers below are reported for transparency but were **not** used as the pass/fail gate — task-by-task correctness (Completeness Check above) was the gate instead, as directed.

| File | Cycle 6 budget (net Δ) | Actual net Δ vs. last-committed HEAD | Note |
| --- | --- | --- | --- |
| `financials_controller.dart` | +5 to +20 | −22 (18 ins / 40 del) | Not isolated to Cycle 6 — HEAD still has the pre-Cycle-4 4-value enum + custom-date fields, so this diff nets out Cycle 4's additions *and* Cycle 6's reversal together. Task-by-task read confirms the current file matches Cycle 6's spec exactly (see Completeness Check #1–2). |
| `financials_pdf_preview_screen.dart` | +5 to +15 | −10 (3 ins / 13 del) | Same conflation — HEAD still has the `custom`-case branch of `_filterLabel` that Cycle 4 removed. Current file matches Cycle 6's spec exactly (Completeness Check #3). |
| `financials_screen.dart` | −35 to +5 | −148 (85 ins / 233 del) | Same conflation — HEAD still has `_DateFilterRow`/`_FilterChip` (pre-Cycle-4), which this diff also removes. Current file matches Cycle 6's spec exactly (Completeness Check #4–6). |
| `summary_header_test.dart` | +50 to +150 | +149 (199 ins / 50 del) | Within range even under the conflated diff — the bulk of this file's content is net-new test cases added across Cycles 4 and 6 with little back-and-forth deletion. |
| `year_selector_test.dart` | DELETED | Confirmed gone from working tree and untracked. | Matches. |
| `transaction_card_test.dart` | 0 | 0 (1 ins / 1 del, single fixture value edit) | Matches — this is Cycle 4's carried-over year-relative fixture edit, unchanged by Cycle 6. |
| `transactions_list_header_test.dart` | 0 | −1 (6 ins / 7 del) | Plan/report both claim 0 — actually −1, and the edit **is** Cycle-6-attributable (see Completeness Check gap above), not carried over from Cycle 4 unmodified. Immaterial magnitude; flagged as a reporting-accuracy issue, not a bloat issue. |

No new file, public class, or dependency introduced beyond what the plan authorized. No `TODO`/config/enum-case additions beyond plan spec (`custom` was correctly *not* resurrected, confirmed by grep).

## Code Efficiency Review
- `_dateFilterLabel` is a single top-level pure function used at exactly two call sites within the same widget (`format:` and each menu item's `Text` child) — single source of truth, not duplicated, matching the plan's explicit rationale.
- `IntrinsicWidth` wrapping `AppDropdown` has two pre-existing precedents in the codebase (`app_date_picker.dart`, `rehearsal_card.dart`) — this is a reuse of an established sizing pattern, not a new one.
- `_YearSelector`, `_YearSelectorChip`, and `_availableYears` (Cycle 4 additions) are deleted in full rather than left dead — net reduction, not new bloat.
- `financials_screen.dart` remains over the informal 500-line size target (confirmed still >900 lines) — pre-existing per prior cycle reports; `ENGINEER_REPORT.md`'s Code Efficiency section states Cycle 6's net effect is a further reduction (dropdown swap removes more than it adds), which is consistent with the observed diff direction. Justification present — not flagged.
- `AppDropdown` (the project wrapper) is used, not raw `FSelect` — confirmed via grep, no `forui` import in either touched production file.
- No hand-rolled loop replacing a `package:collection` utility, no unread new field/param, no single-call-site wrapper abstraction beyond what's already covered above, no barrel file, no new provider/notifier for widget-local state.

## Manual Verification Punch List
QA cannot run the app — the following is the plan's Cycle 6 Owner-run punch list, written for Tony to execute directly in a preview build. This adds to the existing Cycles 1–4 punch lists (does not replace them); Cycle 5's punch list is superseded since Cycle 5 was never implemented.

1. Sign in with a demo band containing entries in the current calendar year; open Financials.
   Expected: single filter control inline in the summary line — the collapsed dropdown label reads exactly `"This year"` (not the numeric year like "2026"). Summary line reads `[This year ▾] • N transactions` centered under the total.
2. Tap the "This year" dropdown.
   Expected: FSelect popup opens showing exactly three options in enum order: `"All time"`, `"This year"`, `"This month"`. No numeric year options, no "Custom" option, no "All years" option.
3. Select `"All time"`.
   Expected: dropdown closes; collapsed label updates to `"All time"`; count and total update to reflect the full unfiltered set; list re-renders.
4. Select `"This month"`.
   Expected: only current-month entries visible; total and count update accordingly. If the band has no current-month entries, `_EmptyState` renders with the dropdown still visible above it.
5. **The core Cycle 6 fix scenario:** switch to (or sign in with) a band whose data is entirely in prior years. On screen entry, the default filter is `thisYear` and the list is empty.
   Expected: summary header renders on top with the dropdown showing `"This year"`, total ($0.00), count (0), and both link buttons. Below the header, `_EmptyState` renders (`No entries yet`). Tap the dropdown → popup shows the three options. Select `"All time"` → list populates with prior-year entries, empty state disappears. This step must work end-to-end without leaving/re-entering the screen.
6. Toggle Income ↔ Expenses while any non-default filter is selected.
   Expected: filter selection persists across the toggle; only total and count change.
7. Tap "Generate Report" while `dateFilter = allTime`.
   Expected: PDF preview opens with header/filename reading `"All time"` — filename becomes `"{Band} – Financial Report (All time).pdf"`.
8. Tap "Generate Report" while `dateFilter = thisMonth`.
   Expected: PDF preview opens with header/filename reading e.g. `"December 2026"` — filename becomes `"{Band} – Financial Report (December 2026).pdf"`.
9. Tap "Generate Report" while `dateFilter = thisYear` (default).
   Expected: PDF preview opens with header/filename reading e.g. `"Year 2026"` — filename becomes `"{Band} – Financial Report (Year 2026).pdf"`, byte-identical to Cycle 4's default-filter output.
10. Tap "View Savings Balance."
    Expected: savings sheet opens with the same animated total behavior as today; filter selection does not affect savings totals.
11. Sort toggle: tap `"Newest first ▾"` in the transactions list header while entries are present.
    Expected: label flips, list reverses. Unchanged from Cycle 1.
12. With an empty filtered list (`dateFilter = thisYear` and no current-year entries), verify the sort toggle in `_TransactionsListHeader` is visible but inert.
13. Cross-platform visual check on iOS, Android, macOS, and web: the inline dropdown is sized appropriately (not stretched full-width, not clipped), and the `" • N transactions"` text sits next to it on the same line at common widths. The FSelect popup opens correctly on each platform.
14. Verify (visual, subjective): the inline dropdown's field chrome is acceptable next to the muted footnote text.

## Issues Found

### Critical
None.

### Warnings
1. **[code-quality]** `ENGINEER_REPORT.md`'s "Files Modified" section and its explicit claim ("no edits required... remain byte-identical to their Cycle 4 state under Cycle 6") for `transactions_list_header_test.dart` is inaccurate — that file's two sort-toggle assertions were changed from Cycle 4's merged-text form to Cycle 6's split-text form, a real and necessary Cycle-6 edit. The plan's own "Files to Modify" section makes the same "No change" claim for this file, so this is a plan-assumption gap repeating the identical class of issue the Cycle 4 QA report already flagged for this same file once before. The change itself is correct, minimal (net −1 line), and required — not blocking, but the recurrence across two consecutive cycles on the same file is worth Architect's attention so the "no change" claim can be verified against the actual split-shape header before being stated in a future plan.

### Suggestions
1. **[code-quality]** The plan's Cycle 6 Change Budget table cannot be mechanically reconciled against `git diff HEAD --numstat` because Cycles 1–6 remain uncommitted and squashed into one diff — this was already flagged by the Engineer and accounted for per the Manager's instruction, but future cycle plans on this same feature could save QA effort by stating the Change Budget in terms of the actual base state (last commit) rather than a hypothetical isolated diff.
2. **[code-quality]** Minor style deviation from the plan's exact code sketch: the implemented `Row` inside `_SummaryHeader` omits the plan's explicit `crossAxisAlignment: CrossAxisAlignment.center` (Flutter's `Row` default is already `CrossAxisAlignment.center`, so behavior is identical) — cosmetic only, no functional difference, not blocking.

---

## Cycle 4 History (preserved for reference; superseded by Cycle 6 above)

Cycle 4 collapsed `FinancialsState`'s `FinancialDateFilter` enum + `customStartDate`/`customEndDate` into a single `selectedYear: int` field, replaced `_DateFilterRow`/`_FilterChip` with a `_YearSelector`/`_YearSelectorChip` `PopupMenuButton` control, merged `_SummaryHeader`'s date-range label and transaction-count into one line, and updated `FinancialsPdfPreviewScreen`'s constructor/`_filterLabel` accordingly. Verdict: **APPROVED**.

- Architect Scope Review: six files touched (`financials_controller.dart`, `financials_pdf_preview_screen.dart`, `financials_screen.dart`, `summary_header_test.dart`, `transaction_card_test.dart`, `transactions_list_header_test.dart`) plus new `year_selector_test.dart`, matching the Cycle 4 plan exactly; all Files Off-Limits entries byte-identical.
- Completeness: all 8 Cycle 4 Engineer tasks confirmed present; one cosmetic reporting gap noted (an unreported necessary assertion fix in `transactions_list_header_test.dart` — the same file flagged again under Cycle 6 above).
- Regression Check: LOW — no auth/session/routing/init-order/RPC/platform-conditional changes.
- Database Safety: not applicable.
- Analyzer: `No issues found!` across all seven changed/created files.
- Tests: 37 passed, 0 failed.
- Change Budget: `financials_controller.dart` net −38 (outside the −20 to −5 budget, Warning, fully explained by full diff read); `financials_pdf_preview_screen.dart` net −21 (1.4x nearest bound, note-and-move-on band); `financials_screen.dart` net −109 (within budget); `year_selector_test.dart` (new) net +171 (within budget).
- Code Efficiency: `_availableYears`/`PopupMenuButton<int>` reused an existing precedent (`pending_invite_card.dart`), not a new abstraction.
- Full owner-run Manual Verification Punch List (8 Cycle-4-specific steps) was written for Tony to execute against a preview build — superseded by Cycle 6's punch list above (Cycle 6 adds to, and in the case of the date-filter control, supersedes, Cycle 4's steps 1–4 and 7).

---

## Cycle 1–3 History (preserved for reference; superseded by Cycle 4/6 above)

Cycle 3 (narrow follow-up: center-align `_SummaryHeader`) was previously APPROVED. Cycle 1 covered the full feature redesign (table → cards + summary header, details sheet relabeling). Verdict: **APPROVED**.

- Architect Scope Review: only `financials_screen.dart` and `financial_entry_details_bottom_sheet.dart` changed; all Files Off-Limits entries were byte-identical; four new test files matched Files to Create exactly.
- Completeness: all 6 Engineer Task Breakdown items confirmed present (details sheet redesign, `_TransactionCard`, `_SummaryHeader`/`_TransactionsListHeader`, screen body swap, dead-code removal, four widget test files).
- Regression Check: LOW — no auth/session/routing/init-order/RPC/platform-conditional changes; no state-shape change.
- Database Safety: not applicable.
- Analyzer: `No issues found!` across all six changed/created files.
- Tests: 34 passed, 0 failed.
- Change Budget: `financials_screen.dart` net −140 (within −200 to −70 budget); `financial_entry_details_bottom_sheet.dart` net +19 (within +10 to +30 budget).
- Code Efficiency: one Warning — `_TransactionCard` reimplements card container styling instead of reusing the existing `AppCard` widget ([lib/components/ui/app_card.dart](lib/components/ui/app_card.dart)); classified as plan-directed (Architect Task 2 specified the construction verbatim), not an Engineer deviation, not blocking.
- Full owner-run Manual Verification Punch List (13 steps) was written for Tony to execute against a preview build — see Architect Plan's Verification Plan for the authoritative copy.
