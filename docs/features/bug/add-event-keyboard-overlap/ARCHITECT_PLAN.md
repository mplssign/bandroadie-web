# ARCHITECT_PLAN — bug/add-event-keyboard-overlap

## Feature Slug

`bug/add-event-keyboard-overlap`

## Feature Title

Add Event sheet content hidden behind keyboard when creating a gig

## Problem Summary

On the Add Event sheet (both create and edit modes, and both Gig and
Rehearsal event types), tapping into the Notes `TextField` opens the
on-screen keyboard which covers the field and the sticky footer (the
Create/Save button). The user can't see what they're typing in Notes, and
cannot reach the Create button at all — blocking gig creation while the
keyboard is open. Two TestFlight reports from the same reporter (iPhone
14,6 / iOS 26.6.1, screen 375×667) describe this end-to-end block.

Reproduces on any platform with a software keyboard (iOS, Android). Desktop
(macOS) and web with hardware keyboards are unaffected in practice because
`MediaQuery.viewInsets.bottom` stays 0 there.

## Root Cause

**Confidence: HIGH** — confirmed by direct read of the affected `build()`
method and by structural comparison with the same-shape precedent bug
[docs/features/bug/finance-notes-field-keyboard-overlap/ARCHITECT_PLAN.md](docs/features/bug/finance-notes-field-keyboard-overlap/ARCHITECT_PLAN.md)
whose fix landed in [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart).

File: [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
Method: `_EventEditorDrawerState.build()` (lines 2712–2745).

The drawer is shown from
[lib/features/events/widgets/add_edit_event_bottom_sheet.dart](lib/features/events/widgets/add_edit_event_bottom_sheet.dart#L64)
via `showModalBottomSheet(isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent)`.
Per Flutter's documented contract, `isScrollControlled: true` sheets do NOT
auto-pad for the software keyboard — the caller is responsible for reading
`MediaQuery.viewInsets.bottom` and shifting the sheet content upward. The
in-repo precedent widget (`add_financial_entry_bottom_sheet.dart`, ~L1345)
does exactly that after its bug fix.

`_EventEditorDrawerState.build()` skips that step. The outer container is:

```dart
Container(
  height: MediaQuery.of(context).size.height,  // full screen, keyboard-blind
  decoration: BoxDecoration(...),
  child: Column(children: [
    Expanded(child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildScrollableBody(context),
    )),
    _buildStickyFooter(context),
  ]),
)
```

When the software keyboard opens, the modal-sheet layout anchors this
container at the bottom of its parent (the modal barrier), so the bottom
`viewInsets.bottom` pixels of the container render BEHIND the keyboard.
That occluded strip contains `_buildStickyFooter(context)` (the Create/Save
button row) and — once the built-in `Scrollable.ensureVisible` from
`TextField` focus scrolls the Notes field down to the bottom of the scroll
viewport — the Notes `TextField` itself.

The bug's shape is identical to the finance-notes-field-keyboard-overlap
bug already fixed in this repo. Both widgets follow the same layout
recipe: a fixed-height outer container containing a `Column` with an
`Expanded` `SingleChildScrollView` above a fixed sticky footer. The fix
recipe is identical too: add `margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)`
to the outer container.

## Existing System Analysis

- **Widget invocation surfaces** — `EventEditorDrawer` is instantiated from
  two sites in the codebase:
  - [lib/features/events/widgets/add_edit_event_bottom_sheet.dart](lib/features/events/widgets/add_edit_event_bottom_sheet.dart#L67)
    — the primary "Add/Edit Event" entry, called from the calendar tab,
    the FAB, and the day-detail sheet. Uses `isScrollControlled: true`,
    `useSafeArea: true`, `backgroundColor: Colors.transparent`. This is
    the entry point the bug report exercises.
  - [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
    is referenced only from itself and from the wrapper above. There is no
    third call site.
  - Fixing the widget's `build()` covers both surfaces.
- **Nested modal inside the drawer** — line 2625 opens a nested
  `showModalBottomSheet` for `GigPayBottomSheet`. That is a separate widget
  outside this plan's scope, and its Notes-behind-keyboard behavior — if
  any — is not the reported bug.
- **Established keyboard-inset patterns in codebase** — all matching sheets
  read `MediaQuery.of(context).viewInsets.bottom` and apply it as `margin`
  on a fixed-height outer container, or as `Padding` on a flexible-height
  container. Representative fixed-height + sticky-footer form (the closest
  structural analogue to this widget):
  [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L1345)
  — literally the finance-notes-field-keyboard-overlap fix. No new
  abstraction is warranted; this plan mirrors that precedent verbatim.
- **Existing test coverage** — there is no widget-test file for
  `event_editor_drawer.dart`. The tests under `test/features/events/`
  cover `event_dropdown_test.dart`, `rehearsal_form_fields_test.dart`, and
  `potential_event_availability_section_test.dart` — none of them pump the
  drawer. See "Verification Plan" for why this plan does not create a new
  widget-test file for a 4-line margin fix.

## Proposed Solution

Apply the keyboard inset as a bottom margin on the outer `Container` in
`_EventEditorDrawerState.build()`. When the keyboard is closed,
`viewInsets.bottom == 0` and the render is byte-identical to today; when
the keyboard opens, the container shifts upward by exactly the keyboard
height, keeping the sticky footer AND the Notes field (once the built-in
`Scrollable.ensureVisible` scrolls it into view) above the keyboard.

Exact shape of the change, showing only what moves:

```dart
@override
Widget build(BuildContext context) {
  return FTheme(
    data: buildEventEditorTheme(),
    child: Container(
      height: MediaQuery.of(context).size.height,
      // Reserve room for the on-screen keyboard so the sticky footer and the
      // Notes field stay visible above it.
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(...),  // unchanged
      child: Column(...),              // unchanged
    ),
  );
}
```

Nothing else changes. No refactor of the fixed-height container model, no
switch to `maxHeight`/`minHeight`, no `AnimatedPadding`, no wrapping in an
extra `Padding` widget, no touch to `_buildScrollableBody`,
`_buildStickyFooter`, `_buildStickyHeader`, the `Column`/`Expanded`/
`SingleChildScrollView` structure, or any state or controller.

## Database Impact

n/a — client-only layout fix.

## Flutter Architecture Changes

n/a — no new provider, controller, repository, widget, or shared helper.
One existing `build()` method gains a three-line `margin:` argument (plus
one comment line) on an existing container.

## Files to Create

n/a

## Files to Modify

- [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  — add `margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)`
  to the outer `Container` in `_EventEditorDrawerState.build()` (currently
  at line 2715), plus a one-line explanatory comment immediately above the
  `margin:` line. This is the entire code change.

## Files Off-Limits

Everything else. Specifically:

- [lib/features/events/widgets/add_edit_event_bottom_sheet.dart](lib/features/events/widgets/add_edit_event_bottom_sheet.dart)
  — a call site of `EventEditorDrawer`. The keyboard-inset concern lives
  inside the drawer widget, not at the call site. `isScrollControlled:
  true`, `useSafeArea: true`, and `backgroundColor: Colors.transparent`
  are all correct at the call site and must stay unchanged.
- [lib/features/financials/widgets/gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart)
  — the nested "Gig Pay" sheet opened from inside the drawer. Even if it
  has a latent equivalent issue, the bug report is scoped to the Add Event
  sheet's own Notes field, not to the nested Gig Pay sheet.
- The other builder methods inside `event_editor_drawer.dart`
  (`_buildStickyFooter`, `_buildStickyHeader`, `_buildScrollableBody`,
  `_buildErrorBanner`, `_buildScrollBody*`, `_createEventFormFields`,
  etc.) — the fix belongs on the outer container in `build()`, not inside
  any child builder.
- [lib/features/events/widgets/event_form_fields.dart](lib/features/events/widgets/event_form_fields.dart),
  [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart),
  [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart),
  and any other widget under `lib/features/events/widgets/` other than
  `event_editor_drawer.dart` — these render the fields, not the sheet
  chrome; keyboard insets don't belong here.
- [lib/features/events/events_repository.dart](lib/features/events/events_repository.dart),
  [lib/features/gigs/gig_controller.dart](lib/features/gigs/gig_controller.dart),
  [lib/features/rehearsals/rehearsal_controller.dart](lib/features/rehearsals/rehearsal_controller.dart),
  and every other controller/repository — the bug is purely a layout
  issue; no state, data, or model work is warranted.
- Any migration under `supabase/migrations/`, any RPC, any RLS policy, any
  edge function — the bug is client-only.
- [lib/main.dart](lib/main.dart), any config file, any `--dart-define`
  handling, any deep-link or auth code — init order and cross-platform
  config are not touched.
- The three existing tests under `test/features/events/widgets/` — do not
  modify their setup, helpers, or assertions.

## Change Budget

- Net line delta:
  - `lib/features/events/widgets/event_editor_drawer.dart`: **+4 lines**
    (one comment line, three `margin:` argument lines — `margin:
    EdgeInsets.only(`, `  bottom: MediaQuery.of(context).viewInsets.bottom,`,
    `),`). Zero lines removed.
- New files: **0** (the plan file itself is not counted here — this is the
  code-change budget).
- New public classes / methods: **0**
- New dependencies: **0**
- New test files: **0** — see the Verification Plan for the rationale.

If Engineer's diff shows more than +4 net lines in
`event_editor_drawer.dart`, or touches any other source file, that
overshoots this budget and QA should flag it.

## System Impact Map

| Area | Status |
| --- | --- |
| Events — Add/Edit Event drawer (create & edit; Gig & Rehearsal) | **Affected** (the fix) |
| Events — Gig Pay nested sheet, view-only mode chrome | Unaffected (nested sheet & viewOnly path share the same outer container; the fix's margin becomes 0 when no keyboard is present, so those code paths are visually identical to today) |
| Events — other widgets (form fields, event type selector, expense subview) | Unaffected |
| Calendar, Gigs, Rehearsals, Block-outs, Setlists, Members, Contacts | Unaffected |
| Financials — Add/Edit Transaction sheet (precedent fix) | Unaffected — no code shared, no regression risk to it |
| Auth, Routing, Deep Links, Notifications | Unaffected |
| iOS | Affected — the fix targets on-screen software keyboards; matches the reporter's platform |
| Android | Affected — same |
| macOS | Unaffected in effect — `viewInsets.bottom` stays 0 with a hardware keyboard; margin evaluates to 0; render identical to today |
| Web | Unaffected in effect — same reasoning as macOS |
| Init order (main.dart), Firebase, DeepLinkService, SafeArea/URL-strategy setup | Unaffected |
| Supabase — schema, RLS, RPCs, edge functions | Unaffected |

## Regression Risk

**LOW.**

- Four added lines inside a single widget's `build()` method, all inside
  one existing container's constructor argument list.
- When the keyboard is closed (the common case), `viewInsets.bottom == 0`,
  the margin evaluates to `EdgeInsets.zero`, and the layout output is
  identical to today. Every existing screen state (create/edit, gig/
  rehearsal, view-only, expense subview, potential-gig, multi-date, RSVP)
  renders unchanged when no keyboard is present.
- The pattern is already proven in this repo by the precedent fix in
  `add_financial_entry_bottom_sheet.dart` (merged 2026-09-09 as
  `bug/finance-notes-field-keyboard-overlap`) which has the same-shape
  outer container and the same `Column` + `Expanded` + sticky-footer
  structure.
- No touch to state management, controllers, repository, routing, auth,
  DB, RLS, RPCs, init order, or platform-conditional code.
- No new dependency, no version bump, no config change.
- The desktop/web hardware-keyboard case is preserved because
  `viewInsets` reports 0 for hardware keyboards.
- Nested modals opened from inside the drawer (`GigPayBottomSheet`,
  expense subview modals, tuning/setlist pickers, etc.) live in their own
  `showModalBottomSheet` scope and are unaffected by a margin on the
  parent sheet's outer container.

## Engineer Task Breakdown

Execute in order. The single task is atomic.

1. **Apply the keyboard-inset margin.** In
   [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart),
   in `_EventEditorDrawerState.build()` (starts at the `@override` on line
   2711; the outer `Container(` is at line 2715 and its `height:
   MediaQuery.of(context).size.height,` is on line 2716), add a `margin`
   argument to that outer `Container` immediately after the `height:`
   line and immediately before the `decoration:` line:

   ```dart
   // Reserve room for the on-screen keyboard so the sticky footer and the Notes field stay visible above it.
   margin: EdgeInsets.only(
     bottom: MediaQuery.of(context).viewInsets.bottom,
   ),
   ```

   Preserve the existing indentation of the `Container(...)` argument
   list (8 spaces at the argument level as of the current file). Do not
   change `height:`, `decoration:`, the `Column`/`Expanded`/
   `SingleChildScrollView`/`_buildStickyFooter(context)` structure, or
   anything else in the `build()` method. Do not read `viewInsets` into a
   local variable — passing the `MediaQuery.of` inline keeps the diff
   minimal and rebuilds on inset change automatically. Do not add a
   `debugPrint`, `print`, or any log statement.

2. **Do not touch anything else.** No refactor of the drawer's layout
   model, no `AnimatedPadding`, no rename, no additional keyboard-
   avoidance treatment on the nested `GigPayBottomSheet` or any other
   sub-sheet, no changes to `add_edit_event_bottom_sheet.dart`, no
   changes to any test file, no new test file, no PR-body / engineer-
   report scaffolding beyond what QA/Manager instructs.

## Verification Plan

### Tier 1 — Static / mechanically-executable (QA gate, no running app required)

1. **Analyzer:** `flutter analyze lib/features/events/widgets/event_editor_drawer.dart`
   returns zero errors and zero warnings on the modified file.
2. **Full analyzer:** `flutter analyze` returns the same
   pre-existing-warning count as `main` at branch base
   `9bb2b599`. No new warnings introduced anywhere.
3. **Full test suite:** `flutter test` returns a passing result. Because
   no shared code is modified and the widget under change has no existing
   widget tests, no test in the suite should be affected. If any test
   fails, the failure is unrelated to this change and QA should report
   which test and its error surface.
4. **Diff-shape check:** `git diff --stat main...HEAD` shows exactly one
   modified source file (`lib/features/events/widgets/event_editor_drawer.dart`)
   with a net `+4 -0` line delta. `git diff main...HEAD -- lib/features/events/widgets/event_editor_drawer.dart`
   shows the change is contained to a single `Container(...)` constructor
   site inside `_EventEditorDrawerState.build()`; no import added; no
   variable extracted; no other method touched.

### Tier 2 — Owner-run manual punch list (Tony runs at PR-test / apply time; QA cannot launch or drive the app)

QA cannot launch the app or drive UI. The following is an exact,
numbered checklist for Tony to hand-execute. Run one full pass on iOS
(the reporter's platform), one on Android (parity), and one on macOS
(parity — hardware keyboard, to confirm no visible regression).

**iOS — the primary reported bug case:**

1. Launch the app on the physical iPhone 14,6 (iOS 26.6.1) that filed
   the report, or the closest available iOS device / simulator with a
   375×667 or similar small viewport.
2. Sign in, open a band, navigate to the calendar / event entry.
3. Tap "+ Add Event" (or the equivalent trigger). The Add Event sheet
   opens.
4. Select the **Gig** event type.
5. Fill in the required fields (name, date, time). Scroll the sheet
   downward toward the "Notes" section.
   - **Expected:** the sheet is full-height; the sticky footer with the
     Create button is visible at the bottom; no keyboard yet.
6. Tap into the Notes `TextField`.
   - **Expected:** the software keyboard slides up AND the sheet
     content shifts up so that (a) the Notes field is fully visible
     above the keyboard and (b) the sticky footer with the Create
     button is visible directly above the keyboard.
7. Type "keyboard test 12345" into Notes.
   - **Expected:** every typed character appears in the visible field;
     no occlusion; caret is visible.
8. Tap the visible Create button.
   - **Expected:** the Create button is tappable and the gig is
     created; the sheet dismisses; the gig appears in the calendar
     with Notes = "keyboard test 12345".
9. Tap outside the field before submitting a second run:
   - **Expected:** the sheet returns to its original size; the sticky
     footer re-anchors at the bottom of the sheet; the Notes field
     still shows the typed text.
10. Repeat steps 4–8 for the **Rehearsal** event type (which does not
    have the load-in / soundcheck rows but still has Notes and a
    sticky footer). Confirm behavior is identical.
11. From an existing gig on the calendar, open it → Edit → the Add/Edit
    Event sheet re-opens in edit mode with pre-filled fields. Scroll to
    Notes. Repeat steps 6–7 to confirm edit mode behaves identically.
12. Repeat step 6 with the **Gig Name** and **Venue** autocomplete
    fields (which sit above Notes but also open the keyboard).
    - **Expected:** these fields already have room above the keyboard
      without needing the fix, and behavior is unchanged from `main`.

**Android — parity check:**

13. Repeat steps 3–12 on an Android device or emulator with a small
    viewport. All expectations identical.

**macOS — hardware-keyboard regression check:**

14. Launch on macOS. Open the Add Event sheet.
15. Click into the Notes field.
    - **Expected:** the hardware keyboard focuses the field; no
      on-screen keyboard appears; the sheet's size and sticky-footer
      position are visually identical to today's build. Typing works
      normally.

If any step in Tier 2 fails, do not merge — return to Architect for
re-diagnosis.

### Why no new widget-test file for this fix

The precedent finance-notes fix added one `testWidgets` case to an
already-existing widget-test file with an already-existing `_pumpSheet`
helper and named groups. This widget (`event_editor_drawer.dart`) has
**no** existing widget-test file at all. Standing up a widget-test
harness for it from scratch would require mocking Supabase (bands, gigs,
contacts, venues, members, financials, setlists, gig responses, one-
calendar preferences), stubbing many Riverpod providers
(`activeBandIdProvider`, `membersProvider`, `contactsProvider`,
`venuesProvider`, `permissions`, `calendarController`,
`gigController`, `rehearsalController`), and initializing multiple
`FAutocompleteController` instances — a task disproportionate to a
4-line margin fix, and outside the scope guardrail "Verification tests
are proportional to risk — never a new test file where an existing
group can take one more case." Here there is no existing group, and
creating one purely to verify a single `Container.margin.bottom`
property assertion would add substantial new test infrastructure with
low incremental confidence beyond what Tier 1 (analyzer + `flutter
test` no-regression) plus Tier 2 (owner-run manual punch list on the
reporter's platform) already establish. If a broader event-editor
widget-test harness is created for a different reason in the future,
this margin assertion should be added to it at that time.

### Notes on classification

- Tier 1 is the QA-executable gate; APPROVED requires Tier 1 to pass.
- Tier 2 is an owner-run checklist because QA cannot launch or drive a
  running instance of the app. It is a PR-test / apply-time check for
  Tony personally, not a QA gate.

## QA Regression Areas

- Add Event (create mode) — Gig type — keyboard-closed layout, all
  sections (event type, name/venue/city, date/time, load-in,
  soundcheck, duration, setlist, potential-gig / multi-date, Notes),
  sticky footer visibility, scroll behavior of the
  `SingleChildScrollView`.
- Add Event (create mode) — Rehearsal type — same, without the gig-only
  rows.
- Edit Event — invoked from the calendar / event detail.
- View-only mode (contributor role) — the outer container gains the
  same margin; when the keyboard is dismissed (which is the norm in
  view-only mode), behavior is byte-identical to today.
- Nested modals opened from inside the drawer (Gig Pay sheet, expense
  editor subview, tuning / setlist pickers, member-selection sheets)
  — none share the outer container being modified; visual and
  interaction behavior identical to today.
- Non-keyboard states across iOS, Android, macOS, web — visually and
  behaviorally identical to today.

## Rollout Strategy

Ship as a straightforward bug-fix PR. No feature flag, no phased
rollout, no migration coordination. Single-file client-only fix.

## Out of Scope

- Converting `event_editor_drawer.dart` from a fixed `height:
  MediaQuery.size.height` container to a `constraints:
  BoxConstraints(maxHeight: ..., minHeight: ...)` model, or migrating
  the drawer to `DraggableScrollableSheet`. That would be a larger
  refactor beyond what the bug needs.
- Wrapping the layout in `AnimatedPadding` for a smoother
  keyboard-slide transition. Polish, not a bug fix.
- Applying the same keyboard-inset handling to the nested
  `GigPayBottomSheet` even if it has an equivalent latent issue — the
  bug report is scoped to the Add Event sheet's Notes / Create button,
  not to the Gig Pay sheet.
- Introducing any shared `KeyboardAwareBottomSheet` helper widget.
  The finance precedent chose inline `viewInsets.bottom` reads
  deliberately; a shared helper would need a much broader mandate than
  a one-line bug fix.
- Creating a widget-test harness for `event_editor_drawer.dart`. See
  the "Why no new widget-test file for this fix" note in the
  Verification Plan.
- Modifying any of the three existing test files under
  `test/features/events/widgets/`.
