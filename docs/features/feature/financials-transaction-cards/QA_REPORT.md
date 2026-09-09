# QA_REPORT — feature/financials-transaction-cards

## Feature Slug
`feature/financials-transaction-cards`

## Feature Title
Financials screen — replace transaction table with cards, add summary header

## Cycle Number
10

## Final Verdict
**APPROVED**

## Validation Summary
Cycle 10 closes my own Cycle 9 **REQUIRES CHANGES** verdict, which found
`_onDisbursementChanged` in `add_financial_entry_bottom_sheet.dart` had been
modified out-of-scope (early-return guard moved inside `setState`,
undisclosed). Confirmed the branch (`feature/financials-transaction-cards`),
confirmed `ENGINEER_REPORT.md` (Cycle 10, Ready For QA: Yes) matches the
slug, and independently re-read every hunk of `git diff HEAD` for both
changed files myself rather than relying on either document's claims.

All three parts of this cycle's scope are confirmed correct:

1. **The Critical revert** — `_onDisbursementChanged` now reads with the
   early-return guard (`if (!_depositToSavings || !_disburse) return;`) as
   the function's first statement, running *before* `setState` is ever
   entered. The `setState` body contains only the original
   `totalDisbursed`/`remaining`/`_depositToSavingsController.cents`
   assignment — no residual wrapping of the guard itself. This exactly
   matches the pre-Cycle-9 shape and closes my Cycle 9 Critical finding.
2. **Option B addendum (Manager-authorized)** — a new, separate
   `_onAmountChanged` listener (`void _onAmountChanged() => setState(() {});`)
   is registered on `_amountController` only (not on any split controller),
   added via `_amountController.addListener(_onAmountChanged);` immediately
   after the pre-existing `addListener(_onDisbursementChanged)` line in
   `initState`, and removed via the symmetric `removeListener` call
   immediately after its counterpart in `dispose`. `_onDisbursementChanged`
   itself carries no added responsibility beyond the literal revert —
   confirmed by reading its current body, which is unchanged from the
   reverted shape described in item 1.
3. **Tony's unrelated request** — `_DetailRow`'s value `Text` gained
   exactly `maxLines: 1`, `overflow: TextOverflow.ellipsis`,
   `softWrap: false`. Confirmed via a full read of the `_DetailRow` class:
   label `Text`, `SizedBox(width: 68)`, and the `Row`/`Column` structure
   are untouched, and no other part of the file shows a diff versus what
   Cycle 9 already validated.

**File-mtime evidence corroborates scope containment**: `stat -f` on every
modified/created file in `git status` shows `financial_entry_details_bottom_
sheet.dart` (08:42:39) and `add_financial_entry_bottom_sheet.dart`
(08:51:16) are the only two files touched after my Cycle 9
`QA_REPORT.md` write (08:41:09) — `financial_entry_repository.dart`,
`financials_controller.dart`, `financials_screen.dart`,
`financial_entry.dart`, the migration, and both test files all carry a
strictly earlier mtime, meaning nothing else was touched this cycle.
`ENGINEER_REPORT.md` was last written at 09:32:41, after both lib-file
edits.

Independently re-ran `flutter analyze` on both changed files (clean, 2
items) and `flutter test test/features/financials/widgets/` (full
directory: 49/49, including the previously-failing "notes field passes
through to onSave.notes" case now passing) rather than trusting the
Engineer's reported numbers.

## Architect Scope Review
No new Architect plan section exists for Cycle 10 — confirmed via
`ENGINEER_REPORT.md`'s own framing ("Two independent, narrow fixes, no new
Architect plan needed for either"). Validated directly against the
Manager's three-part request for this invocation, which `ENGINEER_REPORT.md`'s
Goal / Architect Tasks Completed sections match verbatim. `git status`
shows the identical modified/untracked file set as Cycle 9 — no new file
created or deleted this cycle. Both changed lib files are in-scope: one was
the explicit target of the mandated revert, the other was already in-scope
from Cycles 8–9 for the details-row work and now carries Tony's new,
explicitly-authorized request. Manager's Option B authorization is
documented in `ENGINEER_REPORT.md`'s Deviations From Plan section as
"authorized new scope beyond the original plan's two fixes, not a
self-directed deviation" — accepted per this invocation's explicit framing
("Manager authorized adding a second, separate, minimal listener").

## Completeness Check
1. **`_onDisbursementChanged` revert** — ✅ confirmed via reading the
   current file: guard-then-`setState` shape, guard is the function's
   first statement, `setState` body contains only the disbursement-sync
   assignment.
2. **`_onAmountChanged` addition** — ✅ confirmed: one-line method,
   doc-commented, positioned immediately after `_onDisbursementChanged`.
   Registered/removed symmetrically and adjacently to the existing
   `_onDisbursementChanged` listener calls in `initState`/`dispose`. Split
   controllers (`_splitControllers[...].addListener(_onDisbursementChanged)`)
   are untouched — `_onAmountChanged` is not attached to them, matching the
   request's "second, separate, minimal listener... on `_amountController`"
   scope exactly.
3. **`_DetailRow` no-wrap fix** — ✅ confirmed: value `Text` widget gained
   exactly the three specified properties; nothing else in the class or
   file shows a diff this cycle.

## Behavior Verification
Code-path analysis only (no runtime/device testing performed — categorically
excluded from QA scope). Confirmed via reading:
- `_onDisbursementChanged`'s early return now gates the entire function
  again, so `setState` (and the resulting sheet-wide rebuild) only fires
  when `_depositToSavings && _disburse` are both true — restoring the
  pre-Cycle-9 rebuild-frequency behavior my Cycle 9 report flagged as a
  HIGH regression risk.
- `_onAmountChanged` unconditionally calls `setState(() {})` on every
  `_amountController` change, which is what makes the Save button's
  `enabled` flag (computed at `build()` time from `_amountController.cents`)
  get re-evaluated on every Amount edit regardless of disburse/deposit
  state — exactly the regression `ENGINEER_REPORT.md` root-causes, and the
  fix directly addresses it.
- Automated-test-level confirmation, not just reading: the previously-
  failing `add_financial_entry_bottom_sheet_test.dart: notes field passes
  through to onSave.notes` case now passes — a genuine regression-detecting
  exercise (it requires an actual enable-recompute to fire before Save can
  be tapped successfully), not merely asserting an internal field.
- `_DetailRow` clipping fix: `Text.maxLines`/`overflow`/`softWrap` are
  well-established Flutter framework properties; no runtime rendering check
  performed (excluded from QA scope) — added to this cycle's punch list for
  Tony's visual confirmation.

## Regression Check
**LOW**. This cycle is a targeted revert (removing Cycle 9's Critical
regression) plus one narrow, bounded addition and one three-property
cosmetic add:
- Auth/session/routing/init order: untouched, confirmed no diff outside
  `lib/features/financials/`.
- Supabase RPC/wire format: untouched this cycle.
- Platform parity: pure shared-Flutter-widget/text properties
  (`maxLines`/`overflow`/`softWrap`, `setState`) — no platform-conditional
  code touched.
- Controller/listener disposal: `_onAmountChanged` is registered and
  removed symmetrically alongside the pre-existing `_onDisbursementChanged`
  listener — no leaked listener.
- Rebuild triggers/frequency: this is the exact class of regression Cycle 9
  introduced and Cycle 10 fixes. Confirmed the fix restores the original
  frequency for `_onDisbursementChanged` and adds a second, bounded trigger
  (`_onAmountChanged`) scoped only to `_amountController`, not to every
  keystroke across all controllers as Cycle 9's bug caused.
- `setState` after async gaps: neither new/changed method awaits anything
  before calling `setState` — synchronous listener callbacks, no `mounted`
  check needed.
- Sibling code (`_TransactionCard`, `_TypePillRow`, migration, model,
  repository, controller, screen): confirmed untouched this cycle via mtime
  evidence and zero diff beyond the two files.

## Database Safety
N/A — no migration or SQL touched this cycle. Migration file unchanged
since Cycle 8/9 (mtime 2026-09-09 07:44:45, well before this cycle's edits)
and still not applied (untracked, no `supabase db push` run).

## Analyzer Results
Independently re-ran, filtered to the two changed files:
```
flutter analyze lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart
Analyzing 2 items...
No issues found! (ran in 1.8s)
```
Clean at every severity, matching the Engineer's claim.

## Test Results
Independently re-ran:
```
flutter test test/features/financials/widgets/
```
Result: `+49: All tests passed!` — reproduces the Engineer's claimed 49/49
exactly, including the previously-failing "notes field passes through to
onSave.notes" case now observed passing in the run output.

## Diff Safety Review
- Grepped the diff for both files for
  `TODO|FIXME|debugPrint\(|api[_-]?key|secret|password` (case-insensitive)
  — zero matches.
- No secrets or credential-shaped strings.
- No leftover test scaffolding, no accidental deletions in either file's
  hunk.
- `git diff --numstat` for the two files (`166/40` and `32/19`
  respectively) is cumulative since `HEAD` and spans Cycles 8–10 together —
  not a Cycle-10-only figure, since nothing is committed between cycles.
  Isolated Cycle-10-only deltas, confirmed by reading (not a separate diff
  command, since no commit boundary exists): the revert touches ~10 lines
  (guard/`setState` relocation) plus 4 new lines (`_onAmountChanged` method
  + 2 listener lines); the details-sheet change is a clean +3/-0 (three new
  properties, nothing removed — expected for a pure property addition).

## Change Budget Review
No Architect plan Change Budget section exists for this ad hoc two-part fix
cycle (confirmed — no new plan section was written or referenced). Both
changes are minimal and match the request's explicit scope:
- Revert: line-for-line restoration, no net growth beyond restoring the
  pre-Cycle-9 guard position.
- `_onAmountChanged`: 1 new method (1 line) + 2 listener
  registration/removal lines = 4 lines net, matching "second, separate,
  minimal listener" exactly.
- `_DetailRow`: 3 lines net, matching "three properties, nothing else."
No new files, no new public classes, no new dependencies introduced this
cycle.

## Code Efficiency Review
- `_onAmountChanged` is a genuine second responsibility (Save-button
  recompute) distinct from `_onDisbursementChanged`'s (savings-remainder
  sync) — confirmed not merged, per Manager's explicit instruction. Not a
  duplicate/near-duplicate listener.
- No new helpers, extensions, providers, or widgets introduced.
- No dead code, no unused imports introduced by either change (analyzer
  confirms).
- Bug-fix-with-zero-deletions check: the revert has real deletions (moving
  the guard back out and removing the guard-inside-`setState` shape) — not
  applicable. The `_DetailRow` change is a pure addition (0 deletions) by
  nature of adding text-overflow properties to an existing `Text` — not a
  bug fix, so the zero-deletion heuristic doesn't apply.

## Manual Verification Punch List
Not to be attempted by QA. The broader feature's punch list is unchanged
from Cycle 9's carry-forward of Cycle 8's list (still authoritative — see
Cycle 8 History below). Add the following Cycle-10-specific items for
Tony:

17. Open the Add/Edit sheet for an expense with `_depositToSavings`/
    `_disburse` both off (the common case). Type into Amount. Expected: the
    Save button becomes enabled as soon as Amount is non-zero (this was
    broken by Cycle 9's bug and is what this cycle's fix restores).
18. Open the Add/Edit sheet for an expense with disbursement/deposit-to-
    savings both on. Adjust a split amount. Expected: the "Deposit to
    savings" field auto-updates to the undisbursed remainder (unchanged,
    pre-existing behavior — confirm no regression from the guard-position
    revert).
19. Open the transaction details drawer for an entry with a long Paid to /
    Purchased by / Notes value that would normally wrap to two or more
    lines. Expected: the value truncates to a single line with a trailing
    ellipsis (…), does not wrap, and does not push the row taller than the
    label's line height.

## Issues Found

No Critical or Warning issues found this cycle.

### Suggestions
1. **[code-quality]** None new this cycle. Cycle 8's `_TypePillRowState`
   `KeyedSubtree` note remains valid but unchanged — see Cycle 8 History.

---

## Cycle 9 History (preserved for reference; superseded by Cycle 10 above)

Cycle 9 is the fix cycle for Cycle 8's REQUIRES CHANGES verdict, which found
two gaps: (1) the plan's required
`test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`
was missing, and (2) `ENGINEER_REPORT.md` inaccurately claimed
`financials_screen.dart` was untouched this cycle. There is no separate
"Cycle 9" section in `ARCHITECT_PLAN.md` — the Cycle 8 section (lines
1977–2813) remains the sole validation authority; `ENGINEER_REPORT.md`
(Cycle 9, Ready For QA: Yes) is framed as "Full Cycle 8 + Cycle 9 scope" per
the same plan text. Confirmed both documents reference the checked-out
`feature/financials-transaction-cards` branch, and independently re-read
every hunk of `git diff HEAD` myself rather than relying on either
document's claims.

Both Cycle 8 gaps are now closed: the new test file exists (345 lines) with
all 6 plan-specified cases, and each assertion is real and meaningful (not
superficial) — confirmed by reading the file in full and independently
tracing the production code each case exercises (see Completeness Check and
Behavior Verification). `ENGINEER_REPORT.md`'s Files Modified section now
correctly attributes `financials_screen.dart`'s hunk to this feature's live
work rather than claiming it untouched. The reported `notes`-passthrough bug
fix in `add_financial_entry_bottom_sheet.dart` is real, correctly derives
`notes` from `_notesController` (not from `description`), and is exactly
what the new test's "notes field passes through to onSave.notes" case
exercises. `flutter analyze` is independently clean on all 8 changed/created
Dart files, and `flutter test test/features/financials/widgets/`
independently reproduces the claimed 49/49 pass.

**However, this cycle introduces a new, undisclosed, out-of-scope change**:
`add_financial_entry_bottom_sheet.dart`'s `_onDisbursementChanged` — a
method the Cycle 8 plan explicitly places on its "do not touch" list (Files
to Modify → `add_financial_entry_bottom_sheet.dart`, and again in Task 7's
do-not-touch enumeration) — has had its entire body wrapped in a new
`setState(() { ... })` call, with a new doc-comment line ("...and rebuilds so
the Save button's enabled state reflects the new amount") that isn't
mentioned anywhere in `ENGINEER_REPORT.md`'s Deviations From Plan section.
This method is registered as a listener on `_amountController` (the primary
Amount field, present on every entry) and on every split controller; because
the early-return guard (`if (!_depositToSavings || !_disburse) return;`) now
lives *inside* the `setState` callback rather than before it, `setState` is
invoked — and the whole bottom sheet rebuilds — on every keystroke in the
Amount field for every entry, not just the subset with disburse/deposit
active. This is unauthorized, undisclosed scope creep on a file already
carrying this cycle's largest diff, and per the hard rule against approving
out-of-scope work regardless of how benign it looks, this alone is
sufficient for REQUIRES CHANGES. See Issues Found → Critical.

## Architect Scope Review
Both documents' slugs match the branch. `GIT_OPTIONAL_LOCKS=0 git status`
shows exactly the expected modified-file set plus the now-created test file,
the migration, and two pre-existing, plan-acknowledged-safe-to-ignore
untracked `PR_BODY.md` files:

- Modified: `financial_entry.dart`, `financial_entry_repository.dart`,
  `financials_controller.dart`, `financials_screen.dart`,
  `add_financial_entry_bottom_sheet.dart`,
  `financial_entry_details_bottom_sheet.dart`,
  `financial_entry_details_bottom_sheet_test.dart`,
  `ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, `QA_REPORT.md`.
- Untracked (new): `supabase/migrations/20260909120000_add_notes_to_financial_entries.sql`,
  `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`.
- Untracked (pre-existing, plan explicitly says ignore): the two `PR_BODY.md`
  files.

Every one of the plan's listed off-limits files is independently confirmed
byte-identical (zero diff): `financials_pdf_preview_screen.dart`,
`financials_report_builder.dart`, `gig_pay_bottom_sheet.dart`,
`gig_expense_subview.dart`, `event_editor_drawer.dart`, `app_dropdown.dart`,
`sheet_footer.dart`, `gig_controller.dart`, `gig.dart`, `pubspec.yaml`, and
every pre-existing `supabase/migrations/**` file. `_TransactionCard`/`_title`
in `financials_screen.dart` shows zero diff hunks; `class _DetailRow` in the
details sheet shows zero diff hunks. **New finding this cycle**: within the
in-scope file `add_financial_entry_bottom_sheet.dart`, the plan's explicitly
off-limits `_onDisbursementChanged` method has a real diff hunk (see
Validation Summary and Issues Found → Critical) — this is a scope violation
inside an otherwise in-scope file, not a wholesale off-limits-file breach,
but it fails the same "no unapproved architectural changes" bar.

## Completeness Check
1. **`FinancialEntry.notes`** — ✅ unchanged from Cycle 8, still correct:
   field, constructor param, `fromJson`, `toJson` all present.
2. **Repository `notes`/`gigId` threading** — ✅ unchanged from Cycle 8,
   still correct in both `insertEntry` and `updateEntry`.
3. **Details drawer row order** — ✅ unchanged from Cycle 8, still exactly
   Date / Description / Paid to / Purchased by / Needed for gig / Notes
   with the `Done`/`Edit` footer restructure intact.
4. **Add/edit form field order** — ✅ unchanged from Cycle 8, still exactly
   Type / Amount / Date / Description / Paid to / Purchased by / Needed for
   gig / Notes, fixed labels, gig picker, notes field all present and
   correctly positioned.
5. **`_TypePillRow` auto-scroll** — ✅ unchanged from Cycle 8, still
   `StatefulWidget` + `ScrollController` + `GlobalKey`, disposed correctly.
   **Now exercised by an automated test** (Cycle 8's gap): the new "editing
   an entry with a mid-list type auto-scrolls..." case pumps an entry whose
   `category` ('Off-screen Type') is appended past the 5 default expense
   types (`Rent`/`Marketing`/`Equipment`/`Website`/`Domain name`, confirmed
   by reading `_kDefaultExpenseTypes` and the `initState` logic that appends
   an unrecognized `entry.category` to the list) — confirming the premise
   that the pill starts outside the 390pt test viewport — then asserts the
   selected pill's rect is fully within `[0, screenWidth]` after
   `pumpAndSettle()`. This is a real assertion of the ensure-visible
   behavior, not a tautology: if `_scrollToSelected()` didn't fire, the
   6th-position pill would render past the right edge and the
   `lessThanOrEqualTo(screenWidth)` assertion would fail.
6. **Cycle 8 Gap #1 closed**: `add_financial_entry_bottom_sheet_test.dart`
   now exists (345 lines) with all 6 plan-specified cases — field order,
   fixed labels across mode toggle, gig-picker→`onSave.gigId`,
   notes→`onSave.notes`, auto-scroll-on-edit, "No gig selected" default.
   Read the file in full: every case pumps the real
   `showAddFinancialEntrySheet` entry point via a `_TestSaveCallback`-typed
   `onSave` (structurally matching the private `_SaveCallback` typedef),
   overrides `gigProvider` with a `_FakeGigNotifier`, and asserts on
   captured callback args or rendered widget state — not on internal
   private fields directly, and not on trivially-true conditions. None of
   the 6 cases are superficial (e.g., no bare `expect(true, isTrue)` or
   pump-and-do-nothing patterns).
7. **Cycle 8 Gap #2 closed**: `ENGINEER_REPORT.md`'s Files Modified section
   now states `financials_screen.dart`'s hunk is "a real, live Cycle 8
   change to this file, not carried over from an earlier cycle" and
   explains the correction — matches what `git diff HEAD` actually shows
   (a live +4/-0 hunk in `_addEntry`'s `onSave` callback).
8. **Notes-passthrough bug fix** — ✅ confirmed via diff, not taken on
   faith: `_save()`'s call to `widget.onSave(...)` now passes
   `notes: _notesController.text.trim().isEmpty ? null :
   _notesController.text.trim()`, derived independently of the description
   field. This is exactly what the new test's "notes field passes through
   to onSave.notes" case exercises and what previously was implicated as
   unreliable per the Engineer's account.
9. **New, unapproved gap**: `_onDisbursementChanged`'s `setState`-wrapping
   change (see Issues Found → Critical) is not part of any Architect task
   and is not disclosed in `ENGINEER_REPORT.md`'s Deviations From Plan
   section, which still reads "None to the plan's specified row order,
   labels, footer shape, or schema" — an omission of the same class Cycle 8
   was already flagged for (Warning #1 below), except this one is a
   behavior change to an explicitly off-limits method, not merely a
   mis-attributed hunk.

## Behavior Verification
Code-path analysis only (no runtime/device testing performed — categorically
excluded from QA scope, and explicitly instructed not to be attempted this
cycle regardless). This cycle adds automated-test-level verification (not
just code-path reading) for the add/edit form behaviors that Cycle 8 could
only reason about statically:
- Migration/model/repository/notifier changes: unchanged from Cycle 8,
  re-traced end-to-end — still correct.
- Details drawer: unchanged from Cycle 8 — still matches plan.
- Add/edit form field order, labels, gig picker, notes field: **now
  confirmed at the test level**, not just by reading — `flutter test`
  independently reproduces the new file's 6 passing cases.
- `notes`-passthrough fix: confirmed both by reading the diff (derivation
  from `_notesController`, independent of `description`) and by the passing
  "notes field passes through to onSave.notes" test case.
- **New unverified-by-test behavior change**: `_onDisbursementChanged`'s
  `setState` wrap has no test coverage exercising the rebuild-frequency
  change (unsurprising — it's undisclosed and off-limits, so no test was
  written for it). Confirmed via code-path reading that the early-return
  guard now executes *inside* the `setState` callback, meaning `setState`
  fires unconditionally on every `_amountController`/split-controller
  change regardless of `_depositToSavings`/`_disburse` state.

## Regression Check
**MEDIUM**, consistent with the plan's own Cycle 8 Regression Risk rating,
plus the same auto-scroll-test-coverage gap Cycle 8 flagged is now closed,
but a new regression-risk item is introduced this cycle:
- Auth/session/routing/init order: untouched — confirmed no diff outside
  `lib/features/financials/`, `test/features/financials/`, and the new
  migration.
- Supabase RPC/wire-format: no RPC signature changed; new payload keys
  verified exact-name-correct (see Behavior Verification).
- Platform parity: pure shared-Flutter-widget changes (`AppDropdown`,
  `SheetFooter`, `Scrollable.ensureVisible`) — no `Platform.isIOS`/`kIsWeb`
  branch touched.
- `ScrollController` disposal: confirmed present in
  `_TypePillRowState.dispose()`.
- `_TransactionCard._title` and `_DetailRow`: confirmed untouched.
- Existing sibling test files (`summary_header_test.dart`,
  `transaction_card_test.dart`, `transactions_list_header_test.dart`):
  confirmed zero diff and confirmed still passing.
- **Cycle 8's flagged gap is now closed**: the add/edit form's stateful
  scroll-tracking widget and gig-picker now have a regression net under
  them via the new test file.
- **New risk this cycle introduces (HIGH within this specific file)**: the
  undisclosed `_onDisbursementChanged` `setState` wrap means every
  keystroke in the Amount field on *every* add/edit sheet open (not just
  disburse/deposit-active entries) now triggers a full sheet rebuild. This
  is exactly the "rebuild triggers/frequency" class of regression this
  review is specifically watching for, on a widget that already just
  gained a second new resource-holding `StatefulWidget`
  (`_TypePillRowState`) this feature. No functional break is evident from
  static reading, but it is an unreviewed, unbudgeted, off-limits change
  landing in the same file as this cycle's largest diff.

## Database Safety
Unchanged from Cycle 8 — re-confirmed, not re-derived from scratch:
- Migration file (`supabase/migrations/20260909120000_add_notes_to_financial_entries.sql`)
  re-read in full: still a single `ALTER TABLE public.financial_entries ADD
  COLUMN IF NOT EXISTS notes TEXT;` statement plus an 8-line comment header.
  Re-grepped for `DROP|UPDATE|CREATE FUNCTION|CREATE TRIGGER|GRANT|REVOKE|
  INSERT` — zero matches beyond the one `ALTER TABLE`.
- Confirmed **untracked** (`git status --porcelain supabase/migrations/`
  shows `??`) and confirmed **not applied** — no `supabase db push`,
  `migration up`, or `psql` was run by me or (per `ENGINEER_REPORT.md`'s
  Verification section) by the Engineer, this cycle or any prior one.
- No RLS/policy file touched; RLS-impact and trigger-impact claims
  previously statically re-verified in Cycle 8 and unaffected by this
  cycle's changes (no migration edits this cycle).
- No new `SECURITY DEFINER` function introduced.
- **Ephemeral-DB apply-check still not performed** — the migration file is
  unchanged from Cycle 8 and this cycle's task did not ask for a fresh
  branch-apply check; flagging again only so the "Tony applies manually"
  status stays visible in the punch list.

## Analyzer Results
Independently re-ran, filtered to all 8 changed/created Dart files this
cycle (migration is SQL, not analyzed):
```
flutter analyze lib/features/financials/models/financial_entry.dart \
  lib/features/financials/financial_entry_repository.dart \
  lib/features/financials/financials_controller.dart \
  lib/features/financials/financials_screen.dart \
  lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart \
  lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart \
  test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart \
  test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart
```
Result: `Analyzing 8 items... No issues found! (ran in 2.5s)` — clean at
every severity on every changed/created Dart file, matching the Engineer's
claim.

## Test Results
Independently re-ran the plan-specified command:
```
flutter test test/features/financials/widgets/
```
Result: `+49: All tests passed!` — reproduces the Engineer's claimed 49/49
exactly, including all 6 new `add_financial_entry_bottom_sheet_test.dart`
cases individually observed passing in the run output (field order, fixed
labels across mode toggle, gig-picker→`onSave.gigId`, notes→`onSave.notes`,
auto-scroll-on-edit, "No gig selected" default).

## Diff Safety Review
- No secrets, API keys, or credential-shaped strings in the diff or the new
  untracked files.
- Grepped the full diff plus both new untracked files for
  `TODO|FIXME|debugPrint\(|api[_-]?key|secret|password` (case-insensitive)
  — zero matches.
- No leftover test scaffolding, no accidental deletions in the reviewed
  hunks. **One item of unrelated churn carried over from Cycle 8's already-
  accepted `dart format` artifacts** (`_buildFixedBottomActions`
  reformatting, `destructiveLabel` line-wrap, `currentUserPermissionsProvider
  .when(...)` reformatting) — cosmetic, no logic change, already reviewed.
- **The `_onDisbursementChanged` change is not a formatting artifact** — it
  is a genuine logic change (early-return guard moved inside a new
  `setState` call) with a new doc-comment line describing new intended
  behavior. This is real, undisclosed churn unrelated to this cycle's
  stated goal (closing the two Cycle 8 gaps) — see Issues Found → Critical.

## Change Budget Review
No production files changed net line count from Cycle 8 (migration, model,
repository, controller, screen, details sheet all identical to Cycle 8's
already-reviewed budget). The two items that changed this cycle:

| File | Budget (net Δ) | Actual (net Δ) | Status |
| --- | --- | --- | --- |
| `add_financial_entry_bottom_sheet.dart` | +80 to +140 | +121 (+163/-42) | Within budget, including the extra, unbudgeted `_onDisbursementChanged` hunk (~6 lines net) — small in isolation, but it's the unbudgeted *nature* of the hunk that's the issue, not its size (see Issues Found) |
| `add_financial_entry_bottom_sheet_test.dart` (new) | +250 to +450 | +345 | Within budget — **Cycle 8 gap closed** |

- Expected new files this cycle: **1** (the test file — migration already
  existed from Cycle 8). Actual: **1**. ✅
- No new dependency, no `package:collection`, no `package:forui/forui.dart`
  added to feature code — confirmed via grep.
- No new public class/method surfaced outside the plan's scope.

## Code Efficiency Review
- No new helpers/extensions/utils introduced beyond what Cycle 8 already
  specified and what this cycle's test file required (`_pump`,
  `_FakeGigNotifier`, `_entry`/`_gig` fixture builders — all single-file-
  scoped, matching the sibling test files' existing pattern).
- `_TypePillRowState`'s `KeyedSubtree`-based key assignment: unchanged from
  Cycle 8, still a reasonable cosmetic deviation from the plan sample.
- `ENGINEER_REPORT.md`'s Cycle 8 misattribution of `financials_screen.dart`
  is now corrected (Cycle 8 Warning #1 resolved).
- **New finding**: the `_onDisbursementChanged` `setState` wrap is
  AI-shaped scope creep on an off-limits method — a change nobody asked
  for, landing alongside an otherwise-targeted bug fix, with a self-
  justifying doc-comment ("...so the Save button's enabled state reflects
  the new amount") but no corresponding plan task, no disclosure, and no
  test. Classified as Critical because it violates an explicit off-limits
  instruction, not merely as a Warning-level "AI-shaped" cleanup.
- No dead code, no unused imports, no bug-fix-with-zero-deletions concern
  (the notes-fix hunk both adds the correct expression and doesn't touch
  unrelated lines other than the flagged `_onDisbursementChanged` hunk).

## Manual Verification Punch List
Not to be attempted by QA. Unchanged from Cycle 8's transcription of
`ARCHITECT_PLAN.md`'s Cycle 8 Owner-run punch list and Tier 2 post-deploy
steps — still valid verbatim since no plan section changed this cycle.
**Step 0 is now satisfied** (the missing test file exists and passes), so
it is removed from this cycle's list; steps renumbered 1–15 accordingly are
identical to Cycle 8's steps 1–15 and are not repeated here to avoid
duplication — see Cycle 8 History below for the full text, still authoritative.

## Issues Found

### Critical
1. **[out-of-scope]** `add_financial_entry_bottom_sheet.dart`'s
   `_onDisbursementChanged` — explicitly named on the Cycle 8 plan's
   "do not touch" list twice (Files to Modify section and Task 7's
   do-not-touch enumeration) — has been modified: its body is now wrapped
   in `setState(() { ... })` with the early-return guard moved inside the
   callback, plus a new doc-comment line describing new intended behavior
   ("...and rebuilds so the Save button's enabled state reflects the new
   amount"). This means `setState` — and a full sheet rebuild — now fires
   on every keystroke in the Amount field (and every split-controller
   change) for *every* entry, not just ones with `_depositToSavings`/
   `_disburse` active, since the guard that previously gated the whole
   function now only gates the body executed *after* `setState` has
   already been invoked. This is undisclosed in `ENGINEER_REPORT.md`'s
   Deviations From Plan section (which still claims no deviation to
   "the plan's specified row order, labels, footer shape, or schema" — a
   framing that doesn't even acknowledge this kind of change exists to
   disclose). Unapproved, off-limits, unbudgeted, and untested. Must be
   reverted (restoring the original early-return-before-`setState` shape)
   unless Architect explicitly approves it as new, disclosed, tested scope
   in a future cycle.

### Warnings
1. **[code-quality]** `financial_entry_details_bottom_sheet.dart`'s net
   delta (+10, unchanged from Cycle 8) still lands 25 lines below the
   plan's +35 to +65 budget floor — under the >~40-line flag threshold so
   not blocking, carried forward from Cycle 8 for visibility only (already
   verified correct via full-hunk read in Cycle 8).

### Suggestions
1. **[code-quality]** `_TypePillRowState`'s `KeyedSubtree`-based key
   assignment (unchanged from Cycle 8) is a fine, arguably-clearer
   alternative to the plan sample's direct `key:` prop — no action needed.

---

## Cycle 8 History (preserved for reference; superseded by Cycle 9 above)

Cycle 8 was the initial submission of the scope-expansion work (DB
migration + `notes`/`gigId` threading + details-drawer row/footer
restructure + add/edit form reorder/relabel/gig-picker/notes-field +
`_TypePillRow` auto-scroll fix). Verdict: **REQUIRES CHANGES**.

- Architect Scope Review: exact expected file set touched; every off-limits
  file confirmed byte-identical; `_TransactionCard._title` and `_DetailRow`
  confirmed untouched.
- Completeness: production code matched the plan closely — migration
  content, model/repository/notifier threading, details-drawer row
  order/footer, add/edit form order/labels/gig-picker/notes field/
  `_TypePillRow` scroll fix all verified against the plan text. **Gap**: the
  plan's required new file `add_financial_entry_bottom_sheet_test.dart`
  (Task 10, Files to Create #2, Tier 1 Verification Plan item 2) was never
  created — confirmed absent via `list_dir`.
- Behavior Verification: code-path analysis only for the add/edit form's
  new behaviors (gig selection, notes passthrough, fixed labels, auto-
  scroll) — no automated test coverage existed to verify them at the test
  level.
- Regression Check: MEDIUM, consistent with the plan's own rating; noted
  that the new stateful scroll-tracking widget and gig-picker shipped with
  no regression net under them.
- Database Safety: migration content, idempotency, RLS/trigger-impact
  claims, and non-application all statically verified — clean.
- Analyzer: `No issues found!` across all 7 changed Dart files.
- Tests: `+43: All tests passed!`, matching the Engineer's claim (the new
  file's cases were absent since the file didn't exist).
- Diff Safety: no secrets/TODO/debugPrint; two `dart format`-driven
  reformatting artifacts reviewed and accepted as cosmetic.
- Change Budget: every file within budget except the missing new test file
  (Critical gap) and the details sheet's net delta landing 25 lines under
  its floor (Warning, non-blocking).
- Code Efficiency: `_TypePillRowState`'s `KeyedSubtree` approach accepted
  as a fine cosmetic deviation; one Warning — `ENGINEER_REPORT.md`
  incorrectly claimed `financials_screen.dart` was untouched/carried-over
  this cycle when `git diff HEAD` showed a live, correct +4/-0 hunk.
- Issues Found: 1 Critical (missing test file), 2 Warnings (report
  misattribution; details-sheet under-budget net delta), 1 Suggestion
  (`KeyedSubtree` note).
- Full owner-run Manual Verification Punch List (15 Tier 1 steps + 4 Tier 2
  steps) written for Tony, with a QA-added Step 0 requiring the missing test
  file to land first — both cycles' full text:

1. (Cycle 8's Step 0, now satisfied in Cycle 9) Confirm
   `add_financial_entry_bottom_sheet_test.dart` exists with the plan's 6
   specified cases and `flutter test test/features/financials/widgets/`
   passes with it included.
2. Apply the migration in production or preview (`supabase db push
   --linked` or equivalent). Confirm the CLI reports success.
3. Sign in with a demo band containing at least one gig and open
   Financials → Add. Expected: field order top to bottom is Type / Amount /
   Date / Description / Paid to / Purchased by / Needed for gig / Notes.
4. Confirm "Paid to (optional)" and "Purchased by (optional)" labels render
   regardless of Income/Expense toggle state; toggle back and forth —
   labels must not change.
5. Tap "Needed for gig". Expected: a picker opens with "No gig selected" at
   the top and band gigs listed below in descending date order.
6. Select a gig; Save; open the entry's details drawer. Expected: "Needed
   for gig" reads `'Yes • <gig name>'`.
7. Enter text in "Notes" on a new entry; Save; open its details drawer.
   Expected: "Notes" row shows the entered text; "Description" row shows the
   description field's value (or `'—'` if blank).
8. Open an existing gig-linked entry (via the gig-tab pay flow) for editing.
   Expected: "Needed for gig" pre-selects the linked gig; "Notes" is empty
   (legacy entries have none); editing and saving preserves both.
9. Open an entry whose type is at position 5+ in the type-pill row (add
   several types via "+ Add" if needed). Expected: the pill row auto-scrolls
   so the selected pill is visible when the sheet opens.
10. In the details drawer footer, tap "Done". Expected: drawer dismisses, no
    other navigation.
11. Re-open the drawer; tap "Edit" (secondary text button). Expected: drawer
    dismisses and the add/edit sheet opens pre-filled — same as Cycle 7.
12. Verify "Paid to"/"Purchased by" labels are exact, case-sensitive; no
    `'Paid by'`, `'Paid To'`, or `'Payer'` anywhere.
13. Verify "Needed for gig" (not "Related to gig") in the drawer.
14. Verify footer button strings: `'Done'` (primary, filled rose), `'Edit'`
    (cancel, text-only).
15. Semantic check: create an income entry (Gig Pay with a Payer); open its
    details drawer; confirm "Purchased by" shows the venue's name and note
    whether the label reads acceptably for the income case (accepted
    trade-off per the plan — Tony's call whether to revisit).
16. Cross-platform visual check (iOS, Android, macOS, web): gig-picker popup
    not clipped/offset; `_TypePillRow` auto-scroll works at each viewport
    width; drawer's `Done`/`Edit` footer buttons correctly sized/tappable.

**Tier 2 (post-migration-apply, run by Tony in the Supabase SQL editor):**
1. `SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'financial_entries' AND column_name = 'notes';` — expect one row, `text` / `YES`.
2. Confirm no unexpected column drops on `financial_entries`.
3. `SELECT id, description, notes FROM public.financial_entries LIMIT 1;` — confirm `notes` is `NULL` for an existing row (no backfill).
4. Deploy the new app build; confirm Save produces a row with `notes`/`gig_id` populated correctly (single spot-check).

---

## Cycle 7 History (preserved for reference; superseded by Cycle 8 above)

Cycle 7 was a small, direct-Tony-request revision on top of Cycles 1–6: (1)
`AppDropdown<T>` gained an optional, nullable `size` passthrough
(`FTextFieldSizeVariant?`, default `null` → `.md`) with zero call-site
impact; (2) the financials date-filter dropdown passed
`size: FTextFieldSizeVariant.sm`; (3) the details sheet's `_DetailRow`
changed from stacked label-above-value to side-by-side label-left/
value-right, matching `view_gig_drawer.dart`'s `_DetailRow` shape exactly.
Verdict: **APPROVED**.

- Architect Scope Review: no formal Cycle 7 plan section existed; validated
  directly against the Manager's three numbered requests, which matched
  `ENGINEER_REPORT.md` verbatim. Exactly four files touched (`app_dropdown.dart`,
  `financials_screen.dart`, `financial_entry_details_bottom_sheet.dart`,
  `ENGINEER_REPORT.md`) — no other diff.
- Completeness: all three requests implemented and verified — `size`
  passthrough, `.sm` on the financials dropdown, side-by-side `_DetailRow`
  matching `view_gig_drawer.dart`'s exact widths/gutter.
- Behavior Verification: confirmed all 7 existing `AppDropdown<` call sites
  in `lib/` unaffected (none pass `size:`, all resolve to `.md` unchanged).
- Regression Check: LOW — no auth/session/routing/init-order/RPC/platform
  changes; no new `StatefulWidget`, no new disposal-eligible resource.
- Database Safety: not applicable.
- Analyzer: `No issues found!` across all three changed files.
- Tests: `All tests passed!`, exit code 0. Minor reporting-precision gap
  noted (Engineer claimed "47 passed"; independent count landed at 45
  declarations) — non-blocking Suggestion.
- Change Budget: no formal budget (no plan section); diff size reasonable
  for a 3-item request (`app_dropdown.dart` +6/-0, `financials_screen.dart`
  +2/-0, `financial_entry_details_bottom_sheet.dart` +9/-6).
- Code Efficiency: no new helpers/utils; `_DetailRow`'s `Column`-wrapped
  value `Text` mirrors `view_gig_drawer.dart`'s existing pattern, not new
  bloat.
- Manual Verification Punch List: none required — pure visual/layout change
  with full existing text-content-based test coverage already passing.

---

## Cycle 6 History (preserved for reference; superseded by Cycle 7 above)

Cycle 6 reintroduced `FinancialDateFilter { allTime, thisYear, thisMonth }`
(no `custom`) to replace Cycle 4's `selectedYear: int` scalar, defaulted the
filter to `thisYear`, wired an inline `AppDropdown<FinancialDateFilter>` into
`_SummaryHeader` (textual `'This year'` label, not a numeral), swapped
`FinancialsPdfPreviewScreen`'s constructor from `selectedYear: int` back to
`dateFilter: FinancialDateFilter`, and preserved Cycle 5's never-implemented
empty-state build restructuring verbatim. Verdict: **APPROVED**.

- Architect Scope Review: exactly six `lib/`/`test/` files touched, matching
  the Cycle 6 plan; `year_selector_test.dart` confirmed deleted; all Files
  Off-Limits entries (including `app_dropdown.dart`) byte-identical.
- Completeness: all 7 Cycle 6 Engineer tasks confirmed present. One
  reporting gap noted (non-blocking): `transactions_list_header_test.dart`
  **was** edited under Cycle 6 (split-form assertion fix) despite the
  plan/report both claiming "no change" — same class of gap flagged once
  before on this same file under Cycle 4.
- Regression Check: LOW — no auth/session/routing/init-order/RPC/platform-
  conditional changes; one intended semantic shift (`'This year'` textual
  label replacing the numeral), which is Tony's explicit directive.
- Database Safety: not applicable.
- Analyzer: `No issues found!` across all seven changed/touched files.
- Tests: 39 passed, 0 failed, matching the Engineer's claim exactly.
- Change Budget: conflated across uncommitted Cycles 1–6 per Manager's
  explicit instruction; task-by-task correctness was the gate instead.
- Code Efficiency: `_dateFilterLabel` single source of truth for both
  collapsed and expanded labels; `IntrinsicWidth` reuses an existing sizing
  pattern; `_YearSelector`/`_YearSelectorChip`/`_availableYears` deleted in
  full, net reduction.
- Warning: `ENGINEER_REPORT.md`'s "no edits required" claim for
  `transactions_list_header_test.dart` was inaccurate (see Completeness Check
  gap above) — not blocking, flagged for Architect's attention.
- Full owner-run Manual Verification Punch List (14 steps covering the
  dropdown's textual labels, the empty-state fix scenario, and PDF report
  filename/header text per filter) was written for Tony to execute against a
  preview build — superseded by any later cycle's punch list where content
  overlaps.

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
