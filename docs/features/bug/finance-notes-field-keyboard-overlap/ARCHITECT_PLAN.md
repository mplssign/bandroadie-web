# ARCHITECT_PLAN — bug/finance-notes-field-keyboard-overlap

## Feature Slug

`bug/finance-notes-field-keyboard-overlap`

## Feature Title

Notes field on Finance screen (Income/Expense forms) is hidden behind the keyboard

## Problem Summary

On the Financials → Add/Edit Transaction sheet (both Income and Expense
modes), tapping into the Notes field opens the on-screen keyboard which
completely covers the field. The user can't see what they're typing. The
Save/Cancel/Delete footer bar is also occluded by the keyboard for the same
underlying reason.

Reproduces on any platform with a software keyboard (iOS, Android). Desktop
and web with hardware keyboards are unaffected in practice because
`MediaQuery.viewInsets.bottom` stays 0 there.

## Root Cause

**Confidence: HIGH** — confirmed by direct read of the affected build
method and cross-referenced against the working keyboard-inset patterns used
elsewhere in the codebase.

File: [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart)
Method: `_AddFinancialEntryBottomSheetState.build()` (~lines 1484–1517).

The sheet is shown via `showModalBottomSheet(isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent)`. Per Flutter's
documented contract, `isScrollControlled: true` sheets do NOT auto-pad for
the software keyboard — the caller is responsible for reading
`MediaQuery.viewInsets.bottom` and shifting the sheet content upward. Every
other bottom-sheet in `lib/features/` that hosts a `TextField` does exactly
that (14 call sites; representative examples:
[lib/features/setlists/widgets/song_details_bottom_sheet.dart](lib/features/setlists/widgets/song_details_bottom_sheet.dart) L840;
[lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart](lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart) L88–L93;
[lib/features/setlists/widgets/song_notes_drawer.dart](lib/features/setlists/widgets/song_notes_drawer.dart) L86–L96).

This widget skips that step. Its outer container is:

```dart
Container(
  height: MediaQuery.of(context).size.height,  // <-- full screen, keyboard-blind
  ...
  child: Column(children: [
    Expanded(child: SingleChildScrollView(child: _buildScrollableBody(context))),
    _buildFixedBottomActions(),
  ]),
)
```

`_buildScrollableBody` renders the sections in fixed order and the `Notes`
`_SectionCard` is the LAST child (line 1332). When the software keyboard
opens, the modal-sheet layout still anchors this container at the bottom of
its parent (the modal barrier), so the bottom `viewInsets.bottom` pixels of
the container render BEHIND the keyboard. That occluded strip contains
`_buildFixedBottomActions()` and — once the user has scrolled the body down
to the Notes section — the Notes `AppTextField` itself.

Flutter's built-in `Scrollable.ensureVisible` (which TextField triggers on
focus) does scroll the `SingleChildScrollView`, but "visible" for it means
"inside the scroll viewport." The viewport is defined by the fixed
`height: MediaQuery.size.height` container — which does extend behind the
keyboard. So the auto-scroll parks the Notes field at the bottom of a
viewport that is itself under the keyboard, and the user sees nothing.

The bug did not exist before the Notes section was added — it landed in the
transaction-drawer-redesign (PR #274 at `0ec74ff`, merged 2026-09-09) which
introduced the sectioned layout and the trailing Notes `_SectionCard` without
adding the keyboard-inset handling that every other multi-field bottom sheet
in this codebase already carries. This plan restores that missing handling.

## Existing System Analysis

- **Widget invocation surface** — `showAddFinancialEntrySheet()` is called
  from two sites: [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart#L53)
  (primary Add Transaction FAB flow) and
  [lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart#L206)
  (Edit flow from the read-only details sheet). Both instantiate the same
  `_AddFinancialEntryBottomSheet` widget — fixing that widget covers both.
- **Sibling widgets in `lib/features/financials/widgets/`** —
  `financial_entry_details_bottom_sheet.dart` (read-only, no TextField, not
  affected), `gig_pay_bottom_sheet.dart` (separate gig-pay flow, no Notes
  field, out of scope even if it has a latent equivalent issue),
  `savings_sheet` inside `financials_screen.dart` (read-only list, no
  TextField).
- **Established keyboard-inset patterns in codebase** — all use
  `MediaQuery.of(context).viewInsets.bottom` applied as `margin` (fixed-height
  container form, e.g. `song_details_bottom_sheet.dart`) or as `Padding`
  (flexible-height form, e.g. `enrichment_selector_bottom_sheet.dart`). No
  new abstraction is warranted; this plan mirrors the closest existing form.
- **Existing test coverage** — [test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart](test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart)
  exists with a `_pumpSheet` helper and 6 named groups. Its viewport is
  hard-coded to 800×2400 (no keyboard simulation), so none of its existing
  cases repro or regress on this fix. One new `testWidgets` case fits in an
  existing group; no new test file is needed.

## Proposed Solution

Apply the keyboard inset as a bottom margin on the outer container in
`_AddFinancialEntryBottomSheetState.build()`. This mirrors the pattern
already used by `song_details_bottom_sheet.dart` (the closest structural
analogue: full-height sheet, `Column` with an `Expanded` scroller plus a
fixed footer). When the keyboard is closed, `viewInsets.bottom == 0` and the
render is byte-identical to today; when the keyboard opens, the container
shifts upward by exactly the keyboard height, keeping the fixed footer AND
the Notes field (once the built-in `Scrollable.ensureVisible` scrolls it
into view) above the keyboard.

Exact shape of the change, showing only what moves:

```dart
@override
Widget build(BuildContext context) {
  return FTheme(
    data: buildEventEditorTheme(),
    child: Container(
      height: MediaQuery.of(context).size.height,
      // Reserve room for the on-screen keyboard so the fixed footer and the
      // Notes section (last card in the scroll body) stay above it.
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(...),  // unchanged
      child: Column(...),               // unchanged
    ),
  );
}
```

Nothing else changes. No refactor of the fixed-height container model, no
switch to `maxHeight`/`minHeight`, no `AnimatedPadding`, no wrapping in an
extra `Padding` widget, no touch to `_buildScrollableBody`,
`_buildNotesSection`, `_buildFixedBottomActions`, or any state.

## Database Impact

n/a

## Flutter Architecture Changes

n/a — no new provider, controller, repository, widget, or shared helper. One
existing `build()` method gains a two-argument `margin` on an existing
container.

## Files to Create

n/a

## Files to Modify

- [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart) —
  add `margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)`
  to the outer `Container` in `_AddFinancialEntryBottomSheetState.build()`
  (currently ~line 1490), plus a one-line explanatory comment immediately
  above the margin line.
- [test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart](test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart) —
  add a single `testWidgets` case to the existing `'_AddFinancialEntryBottomSheet sections'`
  group asserting that when `MediaQuery.viewInsets.bottom` is non-zero, the
  outer `Container`'s bottom edge in the render tree sits at least that many
  logical pixels above the ancestor bottom (see Verification Plan for the
  specific assertion shape). No new test file, no new group.

## Files Off-Limits

Everything else. Specifically:

- [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart) —
  a call site of `showAddFinancialEntrySheet`. The keyboard-inset concern
  lives inside the sheet widget, not at the call site.
- [lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart) —
  the other call site of `showAddFinancialEntrySheet`, and a read-only sheet
  itself. Not affected.
- [lib/features/financials/widgets/gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart) —
  separate widget; even if it has a latent equivalent issue, it is not in the
  bug's scope and Notes isn't among its fields.
- [lib/features/financials/financials_controller.dart](lib/features/financials/financials_controller.dart),
  [lib/features/financials/financial_entry_repository.dart](lib/features/financials/financial_entry_repository.dart),
  [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart) —
  the bug is purely a keyboard-inset layout issue; no state, data, or model
  work is warranted.
- Any migration under `supabase/migrations/`, any RPC, any RLS policy, any
  edge function — the bug is client-only.
- [lib/main.dart](lib/main.dart), any config file, any `--dart-define`
  handling, any deep-link or auth code — init order and cross-platform config
  are not touched.
- Existing tests in the test file OTHER than the one new case — do not modify
  the shared `_pumpSheet` helper, the base overrides, or any existing named
  group's setup or assertions.

## Change Budget

- Net line delta:
  - `add_financial_entry_bottom_sheet.dart`: **+4 lines** (one blank line for
    readability, one comment line, three `margin:` argument lines).
  - `add_financial_entry_bottom_sheet_test.dart`: **+20 lines** (roughly)
    for one `testWidgets` case with a `MediaQuery` override wrapper and a
    single assertion.
- New files: **0**
- New public classes / methods: **0**
- New dependencies: **0**

## System Impact Map

| Area | Status |
| --- | --- |
| Financials — Add/Edit Transaction sheet | **Affected** (the fix) |
| Financials — Details sheet, Savings sheet, Gig Pay sheet | Unaffected |
| Financials — list screen, controller, repository, models | Unaffected |
| Gigs, Rehearsals, Setlists, Members, Contacts | Unaffected |
| Auth, Routing, Deep Links, Notifications | Unaffected |
| iOS | Affected — the fix targets on-screen software keyboards |
| Android | Affected — same |
| macOS | Unaffected in effect — `viewInsets.bottom` stays 0 with a hardware keyboard; margin evaluates to 0; render is identical to today |
| Web | Unaffected in effect — same reasoning as macOS |
| Init order (main.dart), Firebase, DeepLinkService, SafeArea/URL-strategy setup | Unaffected |
| Supabase — schema, RLS, RPCs, edge functions | Unaffected |

## Regression Risk

**LOW.**

- One line added inside a single widget's `build()` method.
- When the keyboard is closed (the common case), `viewInsets.bottom == 0`,
  the margin evaluates to `EdgeInsets.zero`, and the layout output is
  identical to today. The existing 22 test cases in the affected test file
  all run under a keyboard-closed viewport and will not regress.
- The pattern is already proven at two other call sites in the codebase.
- No touch to state management, controllers, repository, routing, auth, DB,
  RLS, RPCs, init order, or platform-conditional code.
- No new dependency, no version bump.
- The desktop/web hardware-keyboard case is preserved because `viewInsets`
  reports 0 for hardware keyboards.

## Engineer Task Breakdown

Execute in order. Each step is atomic and independently testable.

1. **Apply the keyboard-inset margin.** In
   [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart),
   in `_AddFinancialEntryBottomSheetState.build()`, add a `margin` argument to
   the outer `Container` (the one with `height: MediaQuery.of(context).size.height`):

   ```dart
   margin: EdgeInsets.only(
     bottom: MediaQuery.of(context).viewInsets.bottom,
   ),
   ```

   Place a single-line comment immediately above the `margin:` line:
   `// Reserve room for the on-screen keyboard so the fixed footer and the Notes section stay visible above it.`

   Do not change `height`, `decoration`, or the `Column`/`Expanded`/
   `SingleChildScrollView`/`_buildFixedBottomActions()` structure. Do not
   read `viewInsets` into a local variable — passing the `MediaQuery.of`
   inline keeps the diff minimal and rebuilds on inset change automatically.

2. **Add one keyboard-inset regression test.** In
   [test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart](test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart),
   inside the existing `group('_AddFinancialEntryBottomSheet sections', ...)`
   block, add one `testWidgets` case (name suggestion:
   `'outer container shifts up by viewInsets.bottom when keyboard is open'`)
   that:
   - Pumps the sheet using the existing `_pumpSheet` helper.
   - After the sheet is visible, wraps the app under test in a
     `MediaQuery(data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)), child: ...)`
     override, or (simpler) uses `tester.binding.window.viewInsetsTestValue`
     / `tester.view.viewInsets = const FakeViewPadding(bottom: 300)` and
     `tester.pumpAndSettle()` to force the sheet to rebuild with the fake
     inset. Prefer whichever the existing test helpers already reach for
     elsewhere in the file — do not introduce a new mocking style.
   - Uses `find.byWidgetPredicate` to locate the outer `Container` that has
     `height == tester.view.physicalSize.height / tester.view.devicePixelRatio`
     (or, more robustly, the container whose `margin` is expected to become
     non-zero), and asserts:
     `expect((tester.widget<Container>(finder).margin as EdgeInsets).bottom, 300);`
   - Resets the fake inset in an `addTearDown` if not already reset by the
     existing helper.

   Do not modify the shared `_pumpSheet` helper, existing overrides, or any
   existing case. Do not add a new group. Do not add a new file.

3. **Do not touch anything else.** No refactor of the sheet's layout model,
   no `AnimatedPadding`, no rename, no additional keyboard-avoidance
   treatment on the Payer/Description/Reimbursement fields, no PR-body /
   engineer-report scaffolding beyond what QA/Manager instructs.

## Verification Plan

### Tier 1 — Static / mechanically-executable (QA gate, no running app required)

1. **Analyzer:** `flutter analyze lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`
   returns zero errors and zero warnings on the modified files.
2. **Focused unit / widget tests:** `flutter test test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`
   — all 22 existing cases pass unchanged AND the new keyboard-inset case
   from Task 2 passes.
3. **Full test suite:** `flutter test` returns a passing result. No test
   outside `test/features/financials/widgets/` is expected to be affected
   because no shared code is modified.
4. **Diff-shape check:** the diff for `add_financial_entry_bottom_sheet.dart`
   is contained to a single `Container(...)` constructor site inside
   `_AddFinancialEntryBottomSheetState.build()`; no import added; no
   variable extracted; no other method touched. QA verifies this with
   `git diff --stat` and a targeted `git diff` review.

### Tier 2 — Owner-run manual punch list (Tony runs at PR-test/apply time; QA cannot launch or drive the app)

Run one full pass on iOS (device or simulator), one on Android (device or
emulator), and one on macOS (hardware keyboard, to confirm no visible
regression).

**iOS / Android — the primary bug case:**

1. Launch the app, sign in, open a band → Financials tab.
2. Tap the "+ Add Transaction" affordance. The sheet opens in Income mode.
3. **Expected:** the sheet is full-height, footer visible at the bottom, no
   keyboard yet.
4. Scroll the sheet down until the Notes card is visible; tap into the Notes
   `TextField`.
5. **Expected:** the software keyboard slides up AND the sheet content
   shifts up so that (a) the Notes field is fully visible above the keyboard,
   (b) the fixed Save/Cancel footer is visible directly above the keyboard.
6. Type "keyboard test 12345".
7. **Expected:** all typed characters appear in the visible field, no
   occlusion.
8. Tap outside the field to dismiss the keyboard.
9. **Expected:** the sheet returns to its original size, the Notes field
   still reads "keyboard test 12345", the footer re-anchors at the bottom of
   the sheet.
10. Toggle the segmented control to Expense. Scroll to Notes. Repeat steps
    4–9. Confirm behavior is identical for Expense mode (which additionally
    exposes the Reimbursement section between Payment Details and Notes).
11. Discard the sheet.
12. From the Financials list, tap any existing transaction row → the
    read-only Details sheet opens → tap Edit → the Add/Edit sheet re-opens
    in edit mode with pre-filled fields. Scroll to Notes. Repeat steps 4–9.
    Confirm edit mode behaves identically.

**macOS — parity check:**

13. Launch the app, sign in, open a band → Financials tab.
14. Open the Add Transaction sheet. Click into the Notes field.
15. **Expected:** the hardware keyboard focuses the field; no on-screen
    keyboard appears; the sheet's size and footer position are visually
    identical to today's build. Typing works normally.

If any step in Tier 2 fails, do not merge — return to Architect for
re-diagnosis.

### Notes on classification

- Tier 1 is the QA-executable gate; APPROVED requires Tier 1 to pass.
- Tier 2 is an owner-run checklist because QA cannot launch or drive a
  running instance of the app. It is a PR-test / apply-time check for Tony
  personally, not a QA gate.

## QA Regression Areas

- Add Transaction (Income) sheet — keyboard-closed layout, all sections
  (About / Payment Details / Distribution / Notes), footer visibility,
  scroll behavior of the `SingleChildScrollView`, all existing test cases
  in `add_financial_entry_bottom_sheet_test.dart`.
- Add Transaction (Expense) sheet — same, plus Reimbursement section.
- Edit Transaction — invoked from Details sheet → Edit action.
- Non-keyboard states across iOS, Android, macOS, web — visually and
  behaviorally identical to today.

## Rollout Strategy

Ship as a straightforward bug-fix PR. No feature flag, no phased rollout, no
migration coordination. Single-file client-only fix.

## Out of Scope

- Converting `add_financial_entry_bottom_sheet.dart` from a fixed
  `height: MediaQuery.size.height` container to a `constraints: BoxConstraints(maxHeight: ..., minHeight: ...)`
  model to match `song_details_bottom_sheet.dart` exactly. That would be a
  larger refactor beyond what the bug needs.
- Wrapping the layout in `AnimatedPadding` for a smoother keyboard-slide
  transition. Polish, not a bug fix.
- Applying the same keyboard-inset handling to
  `gig_pay_bottom_sheet.dart` even if it has an equivalent latent issue —
  the bug report is scoped to Income/Expense (Notes), not gig-pay.
- Introducing any shared `KeyboardAwareBottomSheet` helper widget. The
  existing 14 sites use inline `viewInsets.bottom` reads; a shared helper
  would need a much broader mandate than a one-line bug fix.
- Modifying any of the existing 22 widget-test cases in
  `add_financial_entry_bottom_sheet_test.dart`.
