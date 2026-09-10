# QA_REPORT — bug/finance-notes-field-keyboard-overlap

## Feature Slug

`bug/finance-notes-field-keyboard-overlap`

## Feature Title

Notes field on Finance screen (Income/Expense forms) is hidden behind the keyboard

## Cycle Number

1

## Final Verdict

**APPROVED**

## Validation Summary

The implementation matches the Architect plan exactly: a single `margin:
EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)` was added
to the outer `Container` in `_AddFinancialEntryBottomSheetState.build()`,
with the required one-line comment, and one new `testWidgets` case was added
to the existing `'_AddFinancialEntryBottomSheet sections'` group. Diff is
contained to the two planned files, `+4`/`+17` lines, no other files touched.
Analyzer is clean on both files. The focused test file passes 17/17. The
full suite has exactly one failure, in
`test/features/auth/login_screen_demo_button_test.dart`, which is unrelated
to this diff (see Regression Check for an important correction to the
Manager's framing of that failure).

This review was code-path analysis and static/mechanical verification
(analyzer, diff review, automated test runs) only. No manual/on-device/
runtime UI verification was performed — that is Tony's job per Tier 2 of the
plan (see Manual Verification Punch List below).

## Architect Scope Review

- Files touched: exactly the two files the plan authorized —
  [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](../../../../lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart)
  and
  [test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart](../../../../test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart).
- No off-limits file touched (`financials_screen.dart`,
  `financial_entry_details_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`,
  controller/repository/model files, migrations, `main.dart`, config — all
  untouched, confirmed via `git diff --stat`).
- No new provider, controller, repository, widget class, or shared helper
  introduced — matches "Flutter Architecture Changes: n/a."
- No database impact — matches "n/a."

## Completeness Check

Both Engineer Task Breakdown items are done:

1. **Margin applied** — confirmed at the exact site the plan specified (the
   `Container` with `height: MediaQuery.of(context).size.height`), with the
   exact comment text from the plan, without touching `height`, `decoration`,
   or the `Column`/`Expanded`/`SingleChildScrollView`/
   `_buildFixedBottomActions()` structure.
2. **Regression test added** — confirmed inside the existing
   `'_AddFinancialEntryBottomSheet sections'` group (verified via `grep` for
   `group(...)` locations: the new case sits between the two existing cases
   in that group, before the `footer` group begins). Uses
   `tester.view.viewInsets = const FakeViewPadding(bottom: 300)` +
   `addTearDown(tester.view.resetViewInsets)`, matching the plan's suggested
   approach. No existing group, case, or shared helper (`_pumpSheet`,
   `_baseOverrides`) was modified.

No partial implementation, no missing edge case relative to the plan's
scope.

## Behavior Verification

Root cause (missing keyboard-inset handling on an `isScrollControlled: true`
sheet) is fixed at its source: the fix reserves space via `margin` on the
same container the plan diagnosed, mirroring the established
`song_details_bottom_sheet.dart` pattern. No extra behavior was added beyond
the plan's scope (no `AnimatedPadding`, no refactor to
`constraints`/`maxHeight`, no touch to `gig_pay_bottom_sheet.dart` or other
sheets — all correctly out of scope per the plan).

This was verified via code-path analysis (reading the diff against the
plan's exact prescribed change) and one automated widget test asserting the
margin value under a simulated `viewInsets` change. It was **not** verified
by manually running the app on a device/simulator with a real software
keyboard — that is Tier 2, an owner-run check per the plan's own
classification, and is out of scope for QA.

## Regression Check

**Risk: LOW**, consistent with the plan's own assessment.

- `viewInsets.bottom == 0` when the keyboard is closed → `margin` evaluates
  to `EdgeInsets.zero` → render is byte-identical to pre-fix behavior. This
  is the state under which all 16 pre-existing test cases in the affected
  file run, and all 16 still pass unchanged.
- No touch to state management, controllers, repositories, routing, auth,
  DB, RLS, RPCs, init order, or platform-conditional code.
- Full suite (`flutter test`): 275 passed, 1 failed. The 1 failure is in
  `test/features/auth/login_screen_demo_button_test.dart`
  (`Test A: "Check out the demo band" button is hidden on LoginScreen`),
  which is untouched by this diff.

  **Important correction to the framing given in this QA invocation's
  instructions:** the invocation stated this failure is expected on
  `origin/main` because its fix lives on a separate, not-yet-merged branch
  (`bug/demo-button-test-stale-after-271`). I verified this directly by
  checking out `origin/main` in a disposable `git worktree` (read-only,
  no writes to the working branch) and running the same test file there.
  **The test does *not* fail on current `origin/main`** — `origin/main`'s
  `HEAD` is commit `4b2adf0`, *"test(auth): update stale demo button test to
  match PR #271 non-web visibility (#276)"*, which already contains a fix
  for this exact test (renamed/rewritten to assert the button is *visible*,
  and it passes 2/2). The fix has already landed on `origin/main`, it is not
  on a separate not-yet-merged branch.

  This branch (`bug/finance-notes-field-keyboard-overlap`) is 1 commit
  behind `origin/main` — that missing commit is precisely this already-
  merged fix. The failure QA/Engineer observed is a byproduct of this
  feature branch being cut before that fix landed, not a regression
  introduced by this diff, and not evidence of an unmerged fix elsewhere.
  Manager should rebase/merge `origin/main` into this branch before/at
  merge time to pick up the already-landed fix; no action is needed from
  Engineer on this feature's diff. This does not affect this feature's
  verdict since the diff itself introduces no regression, but the framing
  in the invocation instructions was inaccurate and Manager should not carry
  that inaccurate framing forward to other in-flight branches.
- Platform parity: fix is client-side and inert (`margin` evaluates to zero)
  on any platform where `viewInsets.bottom` is 0, which per the plan is
  macOS and web today. No platform-conditional code was touched.

## Database Safety

N/A — no migrations, RPCs, RLS, or schema touched. Confirmed via diff (only
the two Dart files above changed).

## Analyzer Results

`flutter analyze lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`
→ **No issues found!** (0 errors, 0 warnings, 0 info-level lints.)

## Test Results

- `flutter test test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`
  → **17/17 passed**, including the new
  `'outer container shifts up by viewInsets.bottom when keyboard is open'`
  case.
- `flutter test` (full suite) → **275 passed, 1 failed.** The 1 failure
  (`test/features/auth/login_screen_demo_button_test.dart`) is unrelated to
  this diff — see Regression Check above for full detail and an important
  correction on why it is currently failing on this branch.

## Diff Safety Review

- No secrets, API keys, tokens, or credentials in the diff.
- No `TODO`/`FIXME`/`debugPrint(` anywhere in the diff (grepped explicitly).
- No leftover test scaffolding, no accidental deletions, no unrelated
  formatting churn — diff is exactly the two hunks the plan described.

## Change Budget Review

| File | Budgeted | Actual | Ratio |
| --- | --- | --- | --- |
| `add_financial_entry_bottom_sheet.dart` | +4 | +4 | 1.0x |
| `add_financial_entry_bottom_sheet_test.dart` | ~+20 | +17 | 0.85x |

Both files within budget. 0 new files, 0 new public classes/methods, 0 new
dependencies — matches the plan exactly.

## Code Efficiency Review

- No new helper, extension, util, or private widget class introduced.
- No new provider/notifier/state.
- The `margin:` expression reads `MediaQuery.of(context)` inline (not
  extracted to a local), exactly as the plan directed to keep the diff
  minimal and preserve automatic rebuild-on-inset-change — no unnecessary
  abstraction introduced.
- The new test reuses the existing `_pumpSheet` helper and the same
  `tester.view.*` fake-inset style already used elsewhere in the Flutter
  test suite conventions — no new mocking pattern introduced.
- Bug fix has 0 deleted lines (pure addition). This is justified: the bug
  was genuinely a missing `margin` argument, not a case of incorrect
  existing logic needing removal — consistent with the Engineer's report
  framing and the plan's own diagnosis ("restores missing handling").
- No file crosses a size target as a result of this change.

## Manual Verification Punch List

Per the plan's Tier 2 (owner-run, not a QA gate — QA cannot launch or drive
a running instance of the app). Tony should run this before/at PR-merge
time:

**iOS / Android — primary bug case:**

1. Launch the app, sign in, open a band → Financials tab.
2. Tap "+ Add Transaction." **Expected:** sheet opens full-height in Income
   mode, footer visible, no keyboard yet.
3. Scroll to the Notes card; tap into the Notes `TextField`.
   **Expected:** the software keyboard opens AND the sheet shifts up so the
   Notes field is fully visible above the keyboard and the Save/Cancel
   footer remains visible directly above the keyboard.
4. Type "keyboard test 12345". **Expected:** all characters visible, no
   occlusion.
5. Tap outside the field to dismiss the keyboard. **Expected:** sheet
   returns to original size, Notes field still reads the typed text, footer
   re-anchors at the sheet bottom.
6. Toggle to Expense mode, scroll to Notes (now after the Reimbursement
   section), repeat steps 3–5. **Expected:** identical behavior.
7. Discard the sheet. From the Financials list, tap an existing transaction
   → Details sheet → Edit → sheet re-opens pre-filled. Scroll to Notes,
   repeat steps 3–5. **Expected:** identical behavior in edit mode.

**macOS — parity check:**

8. Launch the app, sign in, open a band → Financials tab. Open Add
   Transaction, click into Notes. **Expected:** hardware keyboard focuses
   the field, no on-screen keyboard appears, sheet size/footer position
   visually identical to today's build; typing works normally.

If any step fails, do not merge — return to Architect for re-diagnosis (per
the plan's own instruction).

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

1. **[out-of-scope]** The Manager's invocation instructions characterized
   the `login_screen_demo_button_test.dart` failure as living on a separate,
   not-yet-merged branch/PR whose fix should still be pending on
   `origin/main`. Verified via a disposable read-only worktree of
   `origin/main` that this is incorrect: the fix (commit `4b2adf0`, PR #276)
   is already merged into `origin/main`. This branch is simply 1 commit
   behind and will pick up the fix on the next rebase/merge with
   `origin/main`. Not a defect in this feature's diff or Engineer's work;
   flagging so Manager doesn't carry the stale framing into other in-flight
   branches or future invocations.
