# QA_REPORT — bug/add-event-keyboard-overlap

## Feature Slug

`bug/add-event-keyboard-overlap`

## Feature Title

Add Event sheet content hidden behind keyboard when creating a gig

## Cycle Number

1

## Final Verdict

**APPROVED**

## Validation Summary

The implementation is a single 4-line addition (`margin:
EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)` plus a
one-line comment) to the outer `Container` in
`_EventEditorDrawerState.build()` in
[lib/features/events/widgets/event_editor_drawer.dart](../../../../lib/features/events/widgets/event_editor_drawer.dart).
It matches the Architect plan's "Exact shape of the change" verbatim. No
other files, methods, or lines were touched. Analyzer is clean, the full
test suite (340 tests) passes, and the diff is contained exactly within
the plan's change budget. This was code-path analysis (diff/analyzer/test
review) — no runtime/device verification was performed, consistent with
this mode's restrictions; a Tier 2 manual punch list is provided below for
Tony.

## Architect Scope Review

- Only file touched: [lib/features/events/widgets/event_editor_drawer.dart](../../../../lib/features/events/widgets/event_editor_drawer.dart)
  — matches the plan's sole "Files to Modify" entry.
- No off-limits file was touched: confirmed `git status` shows no changes
  to `add_edit_event_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`, any
  `event_form_fields.dart`/`gig_form_fields.dart`/`rehearsal_form_fields.dart`,
  any controller/repository, any migration, `main.dart`, or any existing
  test file.
- Branch slug (`bug/add-event-keyboard-overlap`) matches the slug in both
  `ARCHITECT_PLAN.md` and `ENGINEER_REPORT.md`.
- Merge base confirmed at `9bb2b5998dca93673fb8b5260388545fa39bc37d`,
  matching the plan's stated base `9bb2b599`.

## Completeness Check

The plan's single atomic Engineer task ("Apply the keyboard-inset margin")
is fully implemented, and task 2 ("Do not touch anything else") is
honored — no refactor, no `AnimatedPadding`, no nested-sheet changes, no
test file changes. No partial implementation or missed edge case; this is
a one-task plan and it is complete.

## Behavior Verification

Code-path analysis only (no runtime/device verification performed — see
Hard Rules). Confirmed by reading the diff:

- The added `margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)`
  sits on the outer `Container`, before `decoration:`, exactly as the plan
  specifies.
- When `viewInsets.bottom == 0` (no keyboard), the margin evaluates to
  `EdgeInsets.zero`, so the container's rendered geometry is unchanged
  from the pre-fix build — matching the plan's claim of byte-identical
  output with keyboard closed.
- The `Column`/`Expanded`/`SingleChildScrollView`/`_buildStickyFooter`
  structure is untouched, confirming no other layout behavior changed.
- Root cause (missing keyboard-inset handling on an `isScrollControlled:
  true` sheet, per Flutter's documented contract) is addressed directly at
  its source, not symptomatically — this mirrors the precedent fix cited
  in the plan.

## Regression Check

**LOW** — matches the plan's own risk rating.

- Auth/session, Supabase RPC signatures, init order (`main.dart`): not
  touched — confirmed by diff scope.
- Platform parity: the fix is inert (`margin` evaluates to zero) on
  macOS/Web where `viewInsets.bottom` stays 0; no native-only/web-only
  divergence introduced.
- Controller/FocusNode disposal, `setState` after async gaps, rebuild
  triggers: no controller, `State`, or async code was touched — the
  change is a single constructor argument on an existing widget tree
  node.
- Nested `GigPayBottomSheet` and other sub-sheets live in independent
  `showModalBottomSheet` scopes and are unaffected by the parent's
  container margin, consistent with the plan's System Impact Map.
- No existing test file was modified or is expected to be affected
  (`event_editor_drawer.dart` has no widget-test file today), and the full
  suite run below confirms no incidental breakage elsewhere.

## Database Safety

N/A — client-only layout change. No migration, RPC, RLS, or edge function
files in the diff. Confirmed via `git status`/`git diff`.

## Analyzer Results

```
flutter analyze
Analyzing bandroadie...
No issues found! (ran in 3.3s)
```

Zero errors, zero warnings, zero info-level issues at the full-workspace
level — exceeds the plan's requirement of matching main's pre-existing
warning count (here: zero either way).

## Test Results

```
flutter test
...
00:48 +340: All tests passed!
```

340 of 340 tests passed. No failures, no skips flagged as failures. The
plan noted tests were not required to be run by Engineer, but this mode's
Tier 1 process requires QA to run the full suite regardless — done here,
clean result.

## Diff Safety Review

- No secrets or API keys in the diff.
- No `TODO`, `FIXME`, or `debugPrint(` anywhere in the diff (grepped the
  full diff content directly).
- No leftover test scaffolding, no accidental deletions, no unrelated
  formatting churn — diff is exactly the 4 added lines described in the
  plan and Engineer report.

## Change Budget Review

- Plan budget: `event_editor_drawer.dart` **+4/-0**, 0 new files, 0 new
  public classes/methods, 0 new dependencies, 0 new test files.
- Actual (`git diff --stat HEAD`): `event_editor_drawer.dart | 4 ++++` →
  **+4/-0**, exactly one file. 0 new files, 0 new symbols, 0 new
  dependencies, 0 new test files.
- Actual matches budget exactly (1.0x) — no bloat.

## Code Efficiency Review

No new helper, method, provider, widget class, or abstraction introduced.
The change reuses `MediaQuery.of(context).viewInsets.bottom` inline per
the plan's explicit instruction not to extract a local variable, mirroring
the established pattern already used at
[lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](../../../../lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L1345).
No single-use builder methods, no unread fields, no dead code. Nothing to
flag here.

## Manual Verification Punch List (for Tony)

QA cannot launch or drive the app (Tier 1 only). Run this Tier 2 pass
before/at merge time — refined from the Architect plan:

**iOS — primary reported bug case:**

1. Launch the app on a physical iPhone 14,6 (iOS 26.6.1) or a similar
   small-viewport device/simulator (375×667).
2. Sign in, open a band, go to the calendar/event entry.
3. Tap "+ Add Event". The Add Event sheet opens.
4. Select the **Gig** event type.
5. Fill in name, date, time. Scroll toward "Notes".
   - Expected: sheet is full-height; sticky footer with Create button
     visible; no keyboard yet.
6. Tap into the Notes `TextField`.
   - Expected: keyboard slides up AND sheet content shifts up so the
     Notes field and the sticky footer (Create button) are both fully
     visible above the keyboard.
7. Type "keyboard test 12345" into Notes.
   - Expected: every character is visible as typed; caret visible; no
     occlusion.
8. Tap the visible Create button.
   - Expected: tap succeeds, gig is created, sheet dismisses, gig appears
     on the calendar with Notes = "keyboard test 12345".
9. Tap outside the field (before a second run):
   - Expected: sheet returns to original size; footer re-anchors at the
     bottom; typed Notes text persists.
10. Repeat steps 4–8 for the **Rehearsal** event type. Confirm identical
    behavior.
11. Open an existing gig → Edit → sheet reopens pre-filled. Scroll to
    Notes and repeat steps 6–7. Confirm edit mode behaves identically to
    create mode.
12. Repeat step 6 with the **Gig Name** and **Venue** autocomplete
    fields.
    - Expected: unchanged from `main` — these already had room above the
      keyboard without the fix.

**Android — parity check:**

13. Repeat steps 3–12 on an Android device/emulator with a small
    viewport. All expectations identical to iOS.

**macOS — hardware-keyboard regression check:**

14. Launch on macOS. Open the Add Event sheet.
15. Click into the Notes field.
    - Expected: hardware keyboard focuses the field; no on-screen
      keyboard appears; sheet size and sticky-footer position are
      visually identical to today's build; typing works normally.

If any step fails, do not merge — return to Architect for re-diagnosis.
