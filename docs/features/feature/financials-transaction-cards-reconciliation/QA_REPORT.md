# QA_REPORT — feature/financials-transaction-cards-reconciliation

## Feature Slug

`feature/financials-transaction-cards-reconciliation`

## Feature Title

Financials reconciliation — replace the bordered date-filter select field with
a plain text-link-with-chevron control matching `_InlineLinkButton`'s visual
style (Engineer Cycle 3, direct Tony visual tweak against already-open PR
#275)

## Cycle Number

2 (this QA slug's first report, below the divider, was Cycle 1 / APPROVED,
covering a different, earlier engineer cycle's reconciliation-port work.
This is a new QA pass on top, covering the subsequent date-filter restyle.
No `ARCHITECT_PLAN.md` update accompanies this engineer cycle — Manager's
instructions to the Engineer stated none was needed for this narrow,
single-widget change, so this review validates directly against
`ENGINEER_REPORT.md`'s stated scope and the explicit checklist in Manager's
invocation, in place of a plan.)

## Final Verdict

**APPROVED**

## Validation Summary

Confirmed branch `feature/financials-transaction-cards-reconciliation` is
checked out with a clean-except-expected working tree (3 modified tracked
files, all in scope; unrelated untracked docs for other slugs present but
irrelevant). Resolved `ENGINEER_REPORT.md`'s latest section (Cycle 3, "Ready
For QA: Yes") describing the `AppDropdown` → `PopupMenuButton` restyle.
Reviewed the full uncommitted diff for both changed files directly
(`git diff HEAD`). Independently re-ran `flutter analyze` on the two changed
files (clean) and `flutter test` on the full
`test/features/financials/widgets/` directory (62/62 passing — confirmed by
actually re-running, not taken on faith from either number mentioned in the
invocation). All validation below is code-path/static analysis plus
independent test-suite execution — no running app instance was used (see
Manual Verification Punch List for the one item that genuinely requires
Tony's eyes on a live build).

## Cycle 2 Architect Scope Review

No `ARCHITECT_PLAN.md` update exists for this engineer cycle, and none was
required per Manager's explicit instruction to the Engineer (confirmed in
`ENGINEER_REPORT.md`'s Cycle 3 header: "no `ARCHITECT_PLAN.md` update —
Manager's instructions stated no Architect plan was needed for this narrow,
single-widget change"). This is a plan-review gap worth flagging to
Architect/Manager as a process note, not a defect in this implementation —
the change is narrow enough (one control, one file, matching test file) that
`ENGINEER_REPORT.md` + Manager's five-point checklist served as an adequate
substitute validation authority for this cycle.

Manager's five checklist items, verified directly:

1. **Visual property match vs. `_InlineLinkButton`** — confirmed by reading
   both blocks side by side in
   [financials_screen.dart](lib/features/financials/financials_screen.dart#L605-L629)
   and
   [financials_screen.dart](lib/features/financials/financials_screen.dart#L664-L692):
   both use `AppTextStyles.footnote.copyWith(color: AppColors.primary,
   fontWeight: FontWeight.w600)` for the label, a `SizedBox(width:
   Spacing.space4)` gap (confirmed `Spacing.space4 == 4.0` in
   [design_tokens.dart](lib/app/theme/design_tokens.dart#L12)), and a 16px
   `Icon(AppIcons.forward, ..., color: AppColors.primary)`. The new control
   is always in its "enabled" state (no disabled/null-callback branch),
   which correctly matches `_InlineLinkButton`'s `onTap != null` color branch
   — there is no disabled state needed for a menu trigger that's always
   tappable. Match confirmed, not "close enough."
2. **`AppDropdown` import-removal safety** — grepped `AppDropdown` across
   `lib/`: 15 matches across 7 files, none in
   `financials_screen.dart`. The only prior usage in that file was the one
   block replaced this cycle. Import removal is safe.
3. **All three `FinancialDateFilter` options selectable and dispatching
   correctly** — confirmed in the diff:
   `itemBuilder` maps `FinancialDateFilter.values` (all three:
   `allTime`/`thisYear`/`thisMonth`) to `PopupMenuItem`s, and `onSelected`
   calls `ref.read(financialsProvider.notifier).setDateFilter(filter)`
   unconditionally for whichever value is selected — same underlying
   dispatch as the prior `AppDropdown.onChanged`. Also confirmed by the
   independently-passing test `date filter menu contains exactly the three
   FinancialDateFilter values in enum-declaration order` and `invoking
   PopupMenuButton.onSelected(FinancialDateFilter.allTime) dispatches
   setDateFilter on the notifier`.
4. **Updated tests preserve original intent** — compared every renamed test
   in the diff against its pre-change version line-by-line: each rewritten
   test asserts the same conditions the original did (default selection,
   full item list + labels in order, selection dispatch, visibility when the
   filtered list is empty), only retargeted from
   `AppDropdown<T>.value`/`.items`/`.onChanged` to
   `PopupMenuButton<T>.itemBuilder(context)`/`.onSelected`. No assertion was
   dropped, weakened, or replaced with a trivially-true check. Descriptions
   were reworded from "AppDropdown" to "date filter control"/"date filter
   menu" for accuracy only.
5. **Diff scope** — `git status --short` and `git diff --stat HEAD` both
   confirm exactly 3 modified tracked files:
   `lib/features/financials/financials_screen.dart`,
   `test/features/financials/widgets/summary_header_test.dart`, and
   `ENGINEER_REPORT.md` itself. Untracked docs for unrelated slugs
   (`bug/demo-session-cleanup-orphaned-anonymous-users`,
   `transaction-drawer-redesign`, a stray
   `feature/financials-transaction-cards/` dir) exist in the tree but are not
   part of this diff and were not touched.

## Cycle 2 Completeness Check

All three tasks in `ENGINEER_REPORT.md`'s Cycle 3 "Tasks Completed" are
present in the diff: (1) `PopupMenuButton` replacement with matching
`child` styling, (2) unused `app_dropdown.dart` import removed from both the
production file and the test file, (3) no changes outside
`financials_screen.dart`/`summary_header_test.dart`. No partial
implementation found.

## Cycle 2 Behavior Verification

Code-path analysis only (no running app). The restyle is behavior-preserving:
same `FinancialDateFilter` enum, same `setDateFilter` dispatch, same three
options in the same order. No extra behavior was added (no new state, no new
provider, no persistence of the last-selected filter beyond what
`financialsProvider` already holds).

## Cycle 2 Regression Check

**Risk: LOW.** Single-widget, single-file production change; no touches to
auth/session, Supabase RPC signatures, provider init order, or
platform-specific code. `financialsProvider`'s `setDateFilter` call
signature and call site are unchanged — only the calling widget type
changed. Confirmed no other file in the repo depends on
`AppDropdown` inside `financials_screen.dart` (grep above). Test suite for
the whole `financials/widgets` area (62 tests across 5 files, including
unrelated `add_financial_entry_bottom_sheet_test.dart`,
`financial_entry_details_bottom_sheet_test.dart`, `transaction_card_test.dart`,
`transactions_list_header_test.dart`) passes with 0 failures, indicating no
cross-widget regression in the same screen.

## Cycle 2 Database Safety

Not applicable — no migrations, RPC, or schema touched by this diff.

## Cycle 2 Analyzer Results

Independently ran:

```
flutter analyze lib/features/financials/financials_screen.dart test/features/financials/widgets/summary_header_test.dart
Analyzing 2 items...
No issues found! (ran in 2.0s)
```

Clean at every severity (no info/warning/error).

## Cycle 2 Test Results

Independently ran the full directory (not just the one changed test file):

```
flutter test test/features/financials/widgets/
...
+62: All tests passed!
```

62/62 passing, 0 failures. All `summary_header_test.dart` tests (12 through
31 in the run's numbering) pass, including every test touching the new
`PopupMenuButton` structure.

## Cycle 2 Diff Safety Review

Grepped the diff for `TODO|FIXME|debugPrint\(|api[_-]?key|secret|password`
(case-insensitive) — zero matches. No secrets, no debug artifacts, no
leftover scaffolding. No accidental deletions or unrelated formatting churn
detected in either file's hunks.

## Cycle 2 Change Budget Review

No plan Change Budget section exists for this cycle to compare against (see
Cycle 2 Architect Scope Review). Raw `--numstat`: `financials_screen.dart`
+23/-15, `summary_header_test.dart` +50/-39. Both are proportionate to a
single-control restyle plus its matching test updates — no new files, no new
public classes/widgets, no new dependencies. The `PopupMenuButton`'s `child`
`Row` is inlined at its single call site, consistent with the existing
`_InlineLinkButton` pattern it mirrors, rather than extracted into a new
unnecessary helper/widget.

## Cycle 2 Code Efficiency Review

No new helpers, providers, notifiers, or private widget classes were added.
No hand-rolled loops or wrapper abstractions introduced. The change reuses
existing design tokens (`AppTextStyles.footnote`, `AppColors.primary`,
`Spacing.space4`, `AppIcons.forward`) rather than introducing new ones.
Nothing flagged.

## Cycle 2 Manual Verification Punch List

The following requires Tony to visually confirm on a running build — QA does
not launch or drive the app per its operating constraints.

1. Open the Financials screen on any platform build, in the income or
   expense view. **Expected:** the date-filter control (currently reading
   "This year") renders as plain text + chevron in the rose/primary accent
   color, at the same visual weight/size as "View Savings Balance" and
   "Generate Report" below it — no bordered box, no dropdown chrome.
2. Tap the date-filter control. **Expected:** a popup menu appears listing
   "All time", "This year", "This month".
3. Select each of the three options in turn. **Expected:** the control's
   label updates to match the selection, and the transaction list/total
   updates to reflect the new date filter each time.

## Cycle 2 Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

- **[out-of-scope]** No `ARCHITECT_PLAN.md` update exists for this engineer
  cycle. Manager confirmed this was intentional for a narrow, single-widget
  change, so it is not a blocking defect here, but it means there is no
  Change Budget section to hold future similar direct-tweak cycles
  accountable to — worth an Architect/Manager process note if this pattern
  (Manager-authorized plan-skip) recurs for anything less narrow than a
  single-control restyle.

---

# Cycle 1 (historical — APPROVED, earlier engineer cycle)

## Feature Title (Cycle 1)

Financials reconciliation — port PR #273's list-screen redesign onto the post-PR #274 baseline, drop PR #273's redundant migration, and unify the read-only detail sheet

## Final Verdict (Cycle 1)

**APPROVED**

## Validation Summary

Reviewed `ARCHITECT_PLAN.md` and `ENGINEER_REPORT.md` (Ready For QA: Yes),
inspected the full uncommitted working-tree diff (`git diff HEAD`) plus all
4 new test files, independently re-ran `flutter analyze` and `flutter test`
on the 8 in-scope files, and confirmed the off-limits set is byte-identical
to `main`. Branch is a fresh cut off `main@0ec74ff` (confirmed via
`git merge-base main HEAD` == `HEAD` == `main`), matching the plan's stated
branch strategy. All validation below is code-path/static analysis — no
running app instance was used or needed (this cycle requires no manual
verification punch list; nothing in the plan's Verification Plan calls for
a live app).

## Architect Scope Review

- Branch/slug match confirmed: plan, engineer report, and branch name all
  read `feature/financials-transaction-cards-reconciliation`.
- Files Modified matches plan's "Files to Modify" exactly (4 files):
  `financials_controller.dart`, `financials_pdf_preview_screen.dart`,
  `financials_screen.dart`, `widgets/financial_entry_details_bottom_sheet.dart`.
- Files Created matches plan's "Files to Create" (4 test files, plus this
  QA report and the Engineer's own report/plan docs).
- **Off-limits diff check (Task 6 / Tier 1 gate #3):**
  `git diff HEAD -- lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart lib/features/financials/financial_entry_repository.dart lib/features/financials/models/financial_entry.dart supabase/migrations/ test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`
  returned **zero output**. `add_financial_entry_bottom_sheet.dart` is
  byte-identical to `main` — the single most important check in this cycle
  passes.
- **Migration presence check (Tier 1 gate #4):** `test ! -f supabase/migrations/20260909120000_add_notes_to_financial_entries.sql && echo OK` → `OK`. File not present, not created.
- **Static SQL review (Tier 1 gate #5):** `git diff HEAD -- supabase/migrations/` returned zero output for every file under that directory, not just the two named migrations.
- No unapproved architectural changes or unrelated formatting churn observed outside the 4 in-scope production files and 4 new test files.

## Completeness Check

All 8 Engineer Task Breakdown items verified done:

1. `FinancialDateFilter` reduced to 3 cases, `customStartDate`/`customEndDate`/`clearCustomDates`/`setCustomDateRange` all removed, default flipped to `thisYear` — confirmed via direct diff read.
2. `FinancialsPdfPreviewScreen` custom-date params/case removed, `'All Time'` → `'All time'` label fix applied, `now` hoisted — confirmed via direct diff read.
3. `financials_screen.dart` list body rebuilt: old table stack (`_EntriesList`, `_TableHeader`, `_HeaderCell`, `_EntryTableRow`, `_BottomActionsRow`, `_OutlinedActionButton`, `_DateFilterRow`, `_FilterChip`, `_measureText`, column-width constants) is gone; `_SummaryHeader`, `_TransactionsListHeader`, `_TransactionCard`, `_InlineLinkButton`, `_dateFilterLabel` all present; `_sortAscending` field added; empty/loading/non-empty states all render summary header + list header above content, matching Cycle 5 restructuring.
4. `financial_entry_details_bottom_sheet.dart` rebuilt fresh per spec (see Behavior Verification below).
5. All 4 test files created; contain the plan-required additional assertions (verified below).
6. Off-limits byte-identical check passed (see above).
7. Migration-absence check passed (see above).
8. Analyzer/test gates independently reconfirmed clean (see Analyzer/Test Results below).

No partial implementations or skipped edge cases found.

## Behavior Verification

Code-path analysis only (no running app was launched, per QA mode constraints — not required here since the plan's Verification Plan Tier 1 is fully mechanical).

- `financials_screen.dart`: `_addEntry`'s `onSave` destructure/pass-through carries all 5 fields (`gigId`, `isReimbursed`, `reimbursedDate`, `reimbursementMethod`, `notes`) into `notifier.addEntry(...)` — confirmed by direct read, not just Engineer's claim. Badge rule confirmed never-opposite-type: `showReimbursedBadge = !entry.isIncome && entry.isReimbursed`, `showDisbursedBadge = entry.isIncome && disbursements.isNotEmpty`.
- `financial_entry_details_bottom_sheet.dart`: confirmed by direct read —
  - No icons anywhere in the row-rendering code (`_TypeBadge`/`_Badge1099`/`_ReimbursedBadge` are status pills, not per-row icons).
  - `_DetailRow` is side-by-side: `SizedBox(width: 148)` label + 8px gap + `Expanded` value column; label uses `maxLines: 1, softWrap: false, overflow: TextOverflow.visible` — "Deposit to Savings" (18 chars) will not wrap given the 148px column and `footnote` style.
  - Row order exactly: Date → Description → Paid to → Purchased by → Needed for gig → Notes → (conditional) Reimbursed → (conditional) Reimbursement → (conditional) Deposit to Savings.
  - Footer is `SheetFooter(primaryLabel: 'Done', ..., cancelLabel: 'Edit', ...)` — not `Edit Entry`.
  - Edit-launch `onCancel` handler's `onSave` destructure/pass-through into `notifier.updateEntry(...)` forwards all 5 fields including `isReimbursed`, `reimbursedDate`, `reimbursementMethod` — this is the exact regression named in the request, and it is real in the code, not just claimed in the Engineer report. `grep` for `isReimbursed:`/`reimbursedDate:`/`reimbursementMethod:` confirms each appears in both the destructure and the pass-through (Tier 1 gate #7 — signature-forwarding review).
  - `_buildReimbursementDetailLine` appends `' via $method'` only when `reimbursementMethod` is non-null/non-blank; falls back to the original 3-segment sentence otherwise. Matches spec.
- `financials_controller.dart` / `financials_pdf_preview_screen.dart`: tri-state enum (`allTime`/`thisYear`/`thisMonth`, no `custom`) confirmed in both files; `addEntry`/`updateEntry` bodies untouched (diff shows no changes to those methods).

## Regression Check

**Risk: LOW**, matching plan's own assessment.

- No auth/session/routing/init-order touch — confirmed no diff outside `lib/features/financials/**` and `test/features/financials/**` (aside from doc files).
- No platform-conditional code touched.
- `financialsProvider`'s only external consumer, `lib/features/events/widgets/event_editor_drawer.dart`, only calls `ref.invalidate(financialsProvider)` (5 call sites) — unaffected by the `FinancialsState` shape change, confirmed by grep.
- Confirmed zero remaining references to `customStartDate`, `customEndDate`, `FinancialDateFilter.custom`, or `setCustomDateRange` anywhere in `lib/` or `test/` (grep across the whole workspace only found matches inside the plan doc itself, which is expected/descriptive text).
- `Controller`/`FocusNode` disposal, `setState`-after-async-gap, and rebuild-frequency concerns: `_FinancialsScreenState.dispose()` is a no-op override (was already a no-op pre-change; not newly introduced), no new `StatefulWidget`s with disposable resources were added, no new async-gap `setState` calls in the diff.

## Database Safety

**N/A — no DB changes.** `supabase/migrations/` shows zero diff, confirmed via `git diff HEAD -- supabase/migrations/`. No RPC, no `SECURITY DEFINER`, no RLS touch. Migration-branch apply-check (step 8 of the QA process) was not needed since there is no new or changed `.sql` file in this diff.

## Analyzer Results

Independently re-run (not taken on faith from `ENGINEER_REPORT.md`):

```
flutter analyze lib/features/financials/financials_controller.dart \
  lib/features/financials/financials_pdf_preview_screen.dart \
  lib/features/financials/financials_screen.dart \
  lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart \
  test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart \
  test/features/financials/widgets/summary_header_test.dart \
  test/features/financials/widgets/transaction_card_test.dart \
  test/features/financials/widgets/transactions_list_header_test.dart

Analyzing 8 items...
No issues found! (ran in 3.7s)
```

Zero issues at every severity. Matches Engineer's claim.

## Test Results

Independently re-run (not taken on faith):

```
flutter test test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart \
  test/features/financials/widgets/summary_header_test.dart \
  test/features/financials/widgets/transaction_card_test.dart \
  test/features/financials/widgets/transactions_list_header_test.dart

00:03 +46: All tests passed!
```

**46/46 passing**, matches Engineer's claim exactly. Confirmed the two
previously-failing tests ("Edit-launch handler forwards isReimbursed,
reimbursedDate, and reimbursementMethod..." and the paired edit-prefill test)
are present and green. Confirmed the `_pumpSheet` viewport widening
(`390x844`→ logical `800x1600`, `devicePixelRatio: 3.0`) is test-scaffolding
only, inside the in-scope test file, with a clear inline comment; the width
(800 logical px) matches the off-limits form's own test convention
(`Size(800, 2400)` at ratio 1.0) as Engineer claimed.

## Diff Safety Review

- No secrets/API keys found in the diff (`grep -niE` for key/secret/password/token patterns → empty).
- No `TODO`/`FIXME`/`debugPrint(` anywhere in the diff (grep → empty).
- No leftover test scaffolding or accidental deletions found outside the intended surgical deletes described in the plan.
- Some pre-existing untracked doc files unrelated to this diff exist in the working tree (`docs/features/bug/demo-session-cleanup-orphaned-anonymous-users/PR_BODY.md`, `docs/features/feature/financials-transaction-cards/`, `docs/features/transaction-drawer-redesign/PR_BODY.md`) — these are leftovers from other pipeline runs, not created or touched by this Engineer turn, and outside `lib/`/`test/`. Not a finding against this cycle's scope, noted for completeness.

## Change Budget Review

| File | Budget (net) | Actual (+/-) | Ratio vs budget total lines | Verdict |
|---|---|---|---|---|
| `financials_controller.dart` | −35/+3 (net −32) | +2/−28 (net −26) | 30/38 = 0.79x | within budget |
| `financials_pdf_preview_screen.dart` | −10/+2 (net −8) | +3/−13 (net −10) | 16/12 = 1.33x | within ~1.5x |
| `financials_screen.dart` | −585/+414 (net −171) | +293/−570 (net −277) | 863/999 = 0.86x | within budget |
| `financial_entry_details_bottom_sheet.dart` | −80/+140 (net +60) | +72/−42 (net +30) | 114/220 = 0.52x | within budget |
| `financial_entry_details_bottom_sheet_test.dart` (new) | ~200 lines | 529 lines | 2.65x vs rough estimate | see note below |
| `summary_header_test.dart` (new) | ~140 lines | 414 lines | see note below | verbatim port, verified |
| `transaction_card_test.dart` (new) | ~180 lines | 366 lines | see note below | verbatim port, verified |
| `transactions_list_header_test.dart` (new) | ~130 lines | 253 lines | see note below | verbatim port, verified |

The plan's per-file line estimates for the 4 new test files were rough
guesses, not measurements. Cross-checked against the actual source
(`origin/feature/financials-transaction-cards`) versions: `summary_header_test.dart`
(414/414), `transaction_card_test.dart` (366/366), and
`transactions_list_header_test.dart` (253/253) are **verbatim ports, exact
line-count match** — no bloat. `financial_entry_details_bottom_sheet_test.dart`
grew from the source's 331 lines to 529 (+198) — larger than the plan's
"+200" new-file estimate would suggest for a from-331 baseline, but the
growth is accounted for: a new `_CapturingFinancialsNotifier` fake class plus
setup needed for the Edit-forwarding regression guard (a test the source file
never had), and the two `reimbursement_method` assertions. Read through the
file; no duplicated/dead test code found. Not flagged as bloat.

No new production public classes/methods were introduced (matches "Expected
new public classes/methods: 0"). No new dependencies added (`pubspec.yaml`
untouched, confirmed via off-limits diff check).

## Code Efficiency Review

- No new helpers/abstractions beyond what the plan specifies; all new
  widgets (`_SummaryHeader`, `_TransactionsListHeader`, `_TransactionCard`,
  `_InlineLinkButton`) are private, plan-specified, and each is used at
  exactly the call site the plan describes (not single-use-`_buildX()`
  methods masquerading as widgets — they're already proper widget classes).
- Grepped `lib/` for pre-existing equivalents of the new symbols
  (`_SummaryHeader`, `_TransactionsListHeader`, `_TransactionCard`,
  `_InlineLinkButton`, `_dateFilterLabel`) — none found; these are genuinely
  new to this file, ported per plan, not a rebuild of existing utility.
- `financials_controller.dart` and `financials_pdf_preview_screen.dart`
  diffs have deletions with no matching net additions (delete-only patches,
  as the plan explicitly specifies) — no "zero deletions" bloat flag applies
  since these are the surgical-delete files.
- **One minor undisclosed deviation found:** the plan's file-by-file spec
  for `financials_screen.dart` describes porting `_SummaryHeader`'s inline
  `AppDropdown<FinancialDateFilter>` "with `size: FTextFieldSizeVariant.sm`"
  verbatim from the source branch. The source branch's `_SummaryHeader`
  does pass `size: FTextFieldSizeVariant.sm`, but that requires a `size`
  parameter on `lib/components/ui/app_dropdown.dart` that only exists on the
  source branch, not on `main` — and `app_dropdown.dart` is outside
  `lib/features/financials/**`, i.e. off-limits per this plan's "Files
  Off-Limits" list ("Every file outside `lib/features/financials/**` and
  `test/features/financials/**`... except this plan doc"). Engineer
  correctly declined to touch `app_dropdown.dart` (confirmed zero diff on
  that file) and instead omitted the `size:` argument entirely, so the
  dropdown renders at the component's default `md` size rather than `sm`.
  This is the right call given the off-limits constraint (which takes
  precedence over a "port verbatim" instruction the plan itself didn't
  reconcile against the off-limits list), and has no functional impact —
  purely a cosmetic sizing difference in one dropdown. However,
  `ENGINEER_REPORT.md`'s "Deviations From Plan" section states "None,"
  which is not quite accurate; this silent, correct omission should have
  been disclosed. **Suggestion-level, not blocking** — flagging for
  Architect/Tony awareness, not a defect requiring rework.

## Manual Verification Punch List

None required. Every check in the plan's Verification Plan (Tier 1) is
mechanically executable and was executed above; the plan does not require
any live-app/manual check for this cycle.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

1. **[code-quality]** `ENGINEER_REPORT.md`'s "Deviations From Plan" section
   says "None," but the Engineer silently dropped the `size:
   FTextFieldSizeVariant.sm` argument on the summary header's
   `AppDropdown<FinancialDateFilter>` (correctly, since adding it would
   require editing the off-limits `lib/components/ui/app_dropdown.dart`).
   This was the right implementation choice but should have been logged as
   a deviation for visibility. Purely cosmetic (dropdown renders at default
   `md` size instead of `sm`); does not block this cycle's approval.
