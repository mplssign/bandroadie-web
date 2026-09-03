# ARCHITECT PLAN

**Feature Slug:** `bug/add-event-drawer-renderbox-not-laid-out`
**Feature Title:** Add Event drawer — "BoxConstraints forces an infinite width" → cascade of "RenderBox was not laid out" (Android & iOS)
**Branch:** `bug/add-event-drawer-renderbox-not-laid-out`
**Date:** 2026-09-03

---

## 1. Root Cause — HIGH confidence on the error CLASS (reproduced headlessly); exact widget to be pinpointed via the oracle test

### Confirmed by a real, reproducing test
`test/features/events/widgets/event_dropdown_test.dart` (group `EventEditorDrawer layout`) pumps the full `EventEditorDrawer` (rehearsal) inside `showModalBottomSheet(isScrollControlled: true, backgroundColor: Colors.transparent)` on a 390×844 Android view. It reproduces the on-device failure in headless `flutter_test`. The PRIMARY error is:

```
FlutterError | BoxConstraints forces an infinite width.
These invalid constraints were provided to RenderPhysicalShape's layout() function
```

Every `RenderBox was not laid out` line (including the exact `RenderPhysicalShape relayoutBoundary=up4` and `RenderPointerListener relayoutBoundary=up1` seen in the user's device logs) is a CASCADE from that single unbounded-**width** failure. The failing subtree, bottom-up:

```
RenderPointerListener (up1)         ← Listener
RenderPositionedBox   (up2)         ← Center
RenderConstrainedBox  (up3)
RenderPhysicalShape   (up4)         ← Material  ← infinite width provided HERE
RenderCustomPaint     (up5)         ← InkWell splash
_RenderInkFeatures    (up6)         ← InkWell
RenderConstrainedBox  (up7)
RenderDecoratedBox    (up8)
RenderPadding         (up9)
RenderFlex            (up10)        ← Row/Column
RenderDecoratedBox    (up11)
RenderPadding         (up12)
RenderPadding         (up13)
RenderFlex            (up14)        ← Row/Column
RenderConstrainedBox  (up15)
RenderSemanticsAnnotations (up16)   ← Semantics
_RenderInputPadding   (up17)        ← Material button min-tap-target padding
RenderConstrainedBox  (up18)
```

`_RenderInputPadding` (up17) + `RenderPhysicalShape`/`_RenderInkFeatures`/`RenderPositionedBox`(Center)/`RenderPointerListener` is the internal render tree of a Material **`ButtonStyleButton` (TextButton/OutlinedButton/ElevatedButton) or `IconButton`**. So a Material button is being forced to infinite width.

### Why the width is infinite (mechanism)
Flutter's `showModalBottomSheet` gives the sheet content a TIGHT, BOUNDED width (`bottom_sheet.dart:617-624`: `minWidth = maxWidth = incoming.maxWidth` = screen width). So the host is NOT the cause. The infinite width is generated INSIDE the drawer: a `Row` gives each of its **non-`Expanded`** children an UNBOUNDED (`maxWidth: infinity`) constraint so it can measure their intrinsic width. A Material button placed directly as a non-`Expanded` child of a `Row` (rather than wrapped in `Expanded`/`Flexible`/a width-bounded box) receives that infinite width, and its `_RenderInputPadding`/`RenderPhysicalShape` asserts "BoxConstraints forces an infinite width." Its whole subtree then reports "RenderBox was not laid out."

This is why all 6 prior fixes failed: they changed the OUTER container height/host, never the inner Material button under an unbounded-width Row.

### Exact widget — pinpoint with the oracle, do not guess
The confirmed CLASS is "a Material button (ButtonStyleButton/IconButton) placed as a non-Expanded child of a Row somewhere on the rehearsal initial-open path." Candidate call sites exist across `event_editor_drawer.dart`, `event_form_fields.dart`, and `rehearsal_form_fields.dart`. The engineer MUST identify the exact widget using the reproducing test (see Task 1), not by guessing.

---

## 2. Solution Approach

1. Use the reproducing test to obtain the EXACT offending widget + source line (full `FlutterErrorDetails` attribution — the widget-inspector "error-causing widget" line).
2. Apply the minimal fix at that widget: wrap the Material button so it receives a bounded width — e.g. wrap it in `Expanded`/`Flexible` if it belongs in a Row that should stretch it, or in a tightly-sized box (`SizedBox(width: …)` / `ConstrainedBox`), or give the button a bounded `minimumSize` — whichever matches the intended layout. Do NOT introduce `double.infinity` widths.
3. If more than one Material button on the initial rehearsal/gig path shares the same unbounded-Row-child pattern, fix each (the test + a gig-path variant will reveal them).
4. Revert the ineffective `_bodyReady` defer change from the prior engineer pass (it does not address the width issue; errors fire on Frame 0 in the always-rendered chrome). Keep the drawer `build()` otherwise as-is.

---

## 3. Files to Modify

| File | Change |
|---|---|
| `lib/features/events/widgets/event_editor_drawer.dart` | Revert the `_bodyReady`/`addPostFrameCallback`/placeholder defer added in the prior pass. Fix the offending Material button(s) here if the pinpointed widget lives in this file (header/footer/section builders). |
| `lib/features/events/widgets/event_form_fields.dart` and/or `lib/features/events/widgets/rehearsal_form_fields.dart` | Fix the offending Material button(s) if the pinpointed widget lives here. Only touch the file(s) that actually contain the culprit. |
| `test/features/events/widgets/event_dropdown_test.dart` | Keep and refine the `EventEditorDrawer layout` reproducing test: filter out unrelated Supabase-not-initialized errors so the assertion is meaningful, and assert BOTH zero "BoxConstraints forces an infinite width" AND zero "RenderBox was not laid out". Remove any temporary full-attribution debug prints before finishing. Optionally add a gig-path variant. |

**Off-limits:** `lib/components/ui/app_bottom_sheet.dart`, `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` (host swapped in #234 — not the cause; the host provides bounded width).

---

## 4. DB/RLS/RPC Impact
None — layout-only.

---

## 5. Verification Plan (REAL reproduction — the thing missing from all 6 prior fixes)

- **Pre-fix (must reproduce):** `flutter test test/features/events/widgets/event_dropdown_test.dart` FAILS with "BoxConstraints forces an infinite width" + "RenderBox was not laid out". Confirmed already.
- **Post-fix (must pass):** same command passes; the `EventEditorDrawer layout` test asserts zero infinite-width and zero not-laid-out errors (after filtering the unrelated Supabase noise).
- `flutter analyze --no-pub` → 0 errors on all changed files.
- Device (Tony, post-merge): open Add Event from Dashboard on Android/iOS — drawer renders, no `RenderBox was not laid out` in the console.

---

## 6. Task Breakdown

### Task 1 — Pinpoint the exact widget via the oracle test
Temporarily change the `EventEditorDrawer layout` test's error handler to print the FULL details for the "infinite width" error, including widget attribution, e.g.:
```dart
FlutterError.onError = (details) {
  errors.add(details);
  // TEMP: full attribution to find the culprit widget + source line
  // ignore: avoid_print
  if (details.exceptionAsString().contains('infinite width')) {
    // ignore: avoid_print
    print(details.toString());
  }
};
```
Run `flutter test test/features/events/widgets/event_dropdown_test.dart 2>&1 | sed -n '/infinite width/,/^$/p'` and read the "The relevant error-causing widget was: <Widget> <file:line>" line. That is the widget to fix. Remove this temporary print before finishing.

### Task 2 — Fix the offending Material button
Wrap/bound it so it never receives infinite width (Expanded/Flexible/SizedBox/ConstrainedBox as appropriate to the intended design). Keep the change minimal and visually equivalent.

### Task 3 — Revert the ineffective defer
Remove `bool _bodyReady`, the extra `addPostFrameCallback` that sets it, and the placeholder conditional in `build()`; restore `child: _buildScrollableBody(context)`.

### Task 4 — Finalize the test
Filter unrelated Supabase errors; assert zero infinite-width + zero not-laid-out; remove temp prints. Optionally add a gig-path case.

### Task 5 — Verify
`flutter test test/features/events/widgets/event_dropdown_test.dart` passes; `flutter analyze --no-pub` clean.
