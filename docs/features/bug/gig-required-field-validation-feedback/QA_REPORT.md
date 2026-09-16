# QA Report

## Feature Slug

`bug/gig-required-field-validation-feedback`

## Feature Title

Add Event form gives no indication of which required fields are missing

## Cycle Number

3

## Final Verdict

**APPROVED**

## Validation Summary

Branch `bug/gig-required-field-validation-feedback` matches the plan and
report slugs. Working tree has the same uncommitted changes as Cycle 2 (5
modified files + 1 new test file); nothing was committed, staged, or pushed
by QA. Cycle 3 is triggered solely by Architect re-baselining the Change
Budget entry for `test/features/events/widgets/event_dropdown_test.dart` in
`ARCHITECT_PLAN.md` — no source or test file changed since Cycle 2 (only the
plan document was edited). This re-review re-runs Tier 1 verification
(analyzer, full `flutter test`, diff-shape vs. the corrected budget); all
other Cycle 2 findings (scope, completeness, behavior, regression, database
safety, diff safety) were already clean and are unchanged since the diff
itself did not move.

## Architect Scope Review

All three source edits and all three test-file edits match the amended plan
(including the plan amendment adding `event_dropdown_test.dart` to Files to
Modify) exactly:

- `event_editor_drawer.dart`: `_canSave`'s create-mode `switch (_eventType)`
  collapsed to `return true;`. Edit-mode `_isDirty` gate and all other guards
  (`_isEditingExpense`, `_isSaving`, `_isDeleting`, `viewOnly`) untouched.
  `_handleSave` and `_fieldErrors` population (lines ~1836–1866) are byte-for-
  byte unchanged — confirmed via full diff.
- `gig_form_fields.dart`: only the two specified `Text(...)` literals changed
  (`'Gig Venue / Festival / Name *'`, `'City *'`). No other lines touched.
- `rehearsal_form_fields.dart`: only the specified `Text('Location *')`
  literal changed.
- `event_dropdown_test.dart`: edits confined to
  `group('EventEditorDrawer setlist selector (rehearsal)', ...)` as required.
  Existing case renamed and its three assertions changed exactly as
  specified (dropped initial `isNull`, flipped two `isNull` → `isNotNull`).
  New sibling case added with the exact assertions specified in task 5(b).
  The other three groups in the file (`'EventDropdown'`, `'AppDropdown Form
  integration'`, `'EventEditorDrawer layout'`) are untouched.
- `rehearsal_form_fields_test.dart` / `gig_form_fields_test.dart` (new): match
  task 4 — label + `fieldErrors` cases for location, gig name, and city.

Off-limits files (`event_form_data.dart`, `event_editor_actions.dart`,
`event_form_fields.dart`, any migrations/RPCs/routing/auth) are untouched —
confirmed via `git status`.

Note: an unrelated untracked directory,
`docs/features/bug/add-event-keyboard-overlap/`, exists in the working tree
but contains no changes to `lib/` or `test/` and is not part of this diff —
flagged here only for completeness, not a finding.

## Completeness Check

All 5 Engineer Task Breakdown items completed, including the Cycle 2
amendment item (task 5). No partial implementations, no skipped edge cases.

## Behavior Verification

Code-path analysis only (no runtime/device testing performed — that is
Tony's job per the Tier 2 punch list below). Confirmed by reading the diff
and surrounding code:

- Root cause fixed at the source: `_canSave` no longer gates Create on field
  content in create mode, so `_handleSave`'s pre-existing
  `EventFormData.validate()` / rehearsal-location-guard / `_fieldErrors`
  population path is now reachable. This is a root-cause fix (button
  reachability), not a symptom patch.
- Edit-mode behavior (`_isDirty` gate) is byte-for-byte unchanged.
- Block-out create behavior (`_canSave` already returned `true`) is
  unchanged.
- No new behavior was added beyond plan scope — three label edits, one
  boolean-getter simplification, matching test updates.

## Regression Check

**LOW**, consistent with the plan's own risk rating. Reviewed:

- **Auth/session**: untouched.
- **Supabase RPC signatures/param order**: untouched — no RPC calls in the
  diff.
- **Init order**: untouched.
- **Platform parity**: fix lives in shared widgets used by all four
  platforms; no platform-conditional code touched.
- **Controller/FocusNode disposal**: no controller/FocusNode lifecycle code
  touched.
- **setState after async gaps / rebuild frequency**: `_canSave` is a pure
  getter; no async or rebuild-trigger changes.
- Full `flutter test` run (346 tests) passes with zero regressions anywhere
  in the repo, not just the touched files.

## Database Safety

N/A — no migrations, RPCs, edge functions, or schema touched. Confirmed via
`git status`.

## Analyzer Results

```
flutter analyze <6 touched files: event_editor_drawer.dart, gig_form_fields.dart,
rehearsal_form_fields.dart, event_dropdown_test.dart,
rehearsal_form_fields_test.dart, gig_form_fields_test.dart>
No issues found! (ran in 2.6s)
```

Re-ran clean at every severity on all 3 source files and all 3 test files.

## Test Results

- Full-suite `flutter test` — **346 tests, all pass**, zero failures. Same
  count as Cycle 2, confirming no drift since the source/test diff did not
  change between cycles. This full run supersedes the individual per-file
  runs called out in the plan's Tier 1 Verification Plan — all of
  `event_dropdown_test.dart`, `rehearsal_form_fields_test.dart`, and
  `gig_form_fields_test.dart` are included in it.

## Diff Safety Review

- No secrets, API keys, tokens, or credentials in the diff (grepped for
  `TODO|FIXME|debugPrint(|api[_-]?key|secret|password` across the full
  diff — zero hits).
- No leftover test scaffolding, no accidental deletions, no unrelated
  formatting churn.

## Change Budget Review

Re-measured `git diff --numstat HEAD`:

| File | Budgeted net | Actual (+/-) | Actual net | Ratio | Verdict |
|---|---|---|---|---|---|
| `event_editor_drawer.dart` | ~-4 | +1/-7 | -6 | 1.5x | within tolerance |
| `gig_form_fields.dart` | 0 | +2/-2 | 0 | exact match | OK |
| `rehearsal_form_fields.dart` | 0 | +1/-1 | 0 | exact match | OK |
| `event_dropdown_test.dart` | ~+60 (re-baselined Cycle 3) | +65/-5 | +60 | **exact match** | **resolved** |
| `rehearsal_form_fields_test.dart` | (no line figure given — "extended in place") | +83/-0 | +83 | n/a | not applicable |
| `gig_form_fields_test.dart` (new) | new file, 0-line figure given | 150 lines | n/a | n/a (file itself was pre-approved by name) | OK |

The Cycle 2 Critical finding is resolved: Architect's plan re-baseline now
states the Change Budget for `event_dropdown_test.dart` as "net delta ~+60
lines... QA-measured `+65`/`-5` = `+60` net", broken into ~-2 net on the
amended existing case and +62 on the new sibling case (composed of
plan-mandated verbatim boilerplate duplication). No source or test file was
touched in this cycle, so the diff is byte-for-byte identical to what Cycle
2 measured — re-measurement confirms the actual `+65`/`-5` = `+60` net
exactly matches the corrected budget, with zero ratio overrun. No file
exceeds its budget; no new file/public class/dependency outside what the
budget lists.

## Code Efficiency Review

- No new production helpers/abstractions. `_canSave` change is a net-line
  reduction, not an addition.
- New test-file symbols (`_StubMembersNotifier`, `_pumpGigFields`,
  `_GigFieldsWrapper`, `_pumpLocationField`, `_LocationFieldWrapper`) are all
  file-private and follow the existing `_PotentialSectionWrapper` pattern
  already established in `rehearsal_form_fields_test.dart` — no duplicate
  pre-existing helper found via grep of `test/features/events/widgets/`.
- No new public classes, methods, or dependencies introduced anywhere in the
  diff.
- The `event_dropdown_test.dart` boilerplate duplication (see Change Budget
  Review) is plan-mandated, not an engineer efficiency lapse.
- No file crosses a size target with an unexplained justification gap.

## Manual Verification Punch List

QA did not launch the app, boot a simulator/emulator, or drive a running
instance. The following is Tony's Tier 2 owner-run verification, taken
verbatim from the Architect plan's Verification Plan:

1. On iOS build, open the Add Event sheet, select **Gig**. Expected: the gig
   name and city field labels read `Gig Venue / Festival / Name *` and
   `City *`; the Create button is enabled (not greyed out).
2. Tap Create without touching any field. Expected: `Gig name is required`
   appears in red directly under the gig name field; `City is required`
   appears in red under the city field; the top-of-form error banner shows
   `Gig name is required` (first validation error).
3. Type any character into the gig name field. Expected: the inline
   `Gig name is required` under the gig name field disappears immediately;
   the city inline error stays; the banner stays.
4. Clear the gig name field again and tap Create. Expected: `Gig name is
   required` returns inline.
5. Fill gig name and city with real values, tap Create. Expected: gig
   creates successfully — the fix has not blocked the happy path.
6. Switch to **Rehearsal**. Expected: label reads `Location *`, Create
   button is enabled.
7. Tap Create without filling location. Expected: `Location is required`
   inline under the location field and in the banner.
8. Fill location, tap Create. Expected: rehearsal creates successfully.
9. Switch to **Block Out**. Expected: no `*` labels added (out of scope),
   Save still works exactly as it does today.
10. Open an existing gig in edit mode without modifying anything. Expected:
    Save button is disabled (edit-mode `_isDirty` gate still in effect).
    Change any field and re-check: Save becomes enabled.
11. Repeat step 2 on Android, macOS, and Web builds. Expected: identical
    behavior on all four platforms.

## Issues Found

None. No Critical, Warning, or Suggestion findings this cycle. The single
Cycle 2 blocker (Critical, `code-quality` — Change Budget arithmetic overrun
on `event_dropdown_test.dart`) is resolved by Architect's plan re-baseline;
re-measurement confirms the actual diff (`+65`/`-5` = `+60` net) now matches
the corrected budget exactly, with zero ratio overrun.

### Critical

None.

### Warnings

None.

### Suggestions

None.
