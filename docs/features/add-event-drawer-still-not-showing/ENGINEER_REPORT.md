# ENGINEER REPORT

**Feature Slug:** `bug/add-event-drawer-still-not-showing`
**Feature Title:** Add Event drawer still not showing after 5 prior fix attempts
**Cycle Number:** 1

---

## Goal
Replace Forui's `showFSheet` (via `showAppBottomSheet`) with Flutter's native `showModalBottomSheet` for `EventEditorDrawer`, and remove the `LayoutBuilder` wrapper that caused `Container(height: double.infinity)` failures in edge-case Forui constraint chains.

---

## Architect Tasks Completed

- [x] Task 1: `add_edit_event_bottom_sheet.dart` — replaced `showAppBottomSheet` with `showModalBottomSheet`; removed `mainAxisMaxRatio` (not a parameter on the native API); removed now-unused `app_bottom_sheet.dart` import.
- [x] Task 2: `event_editor_drawer.dart` — replaced `LayoutBuilder { Container(width: constraints.maxWidth, height: constraints.maxHeight) }` with `Container(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height))` + `Column(mainAxisSize.min)` + `Flexible` scroll.

---

## Files Created
_None._

## Files Modified
- `lib/features/events/widgets/add_edit_event_bottom_sheet.dart`
- `lib/features/events/widgets/event_editor_drawer.dart`

---

## Analyzer Results
```
flutter analyze --no-pub lib/features/events/widgets/add_edit_event_bottom_sheet.dart lib/features/events/widgets/event_editor_drawer.dart
No issues found! (ran in 2.6s)
```

---

## Test Results
No tests cover this area (plan did not require running tests).

---

## Code Efficiency / Bloat Check

- No new helpers, extensions, or private widget classes introduced.
- `LayoutBuilder` wrapper removed (net deletion of 13 lines); no abstraction added.
- Existing helper search: `showModalBottomSheet` is Flutter's built-in — no custom wrapper exists or was needed.

---

## Verification (manual steps to perform post-deploy)
1. Tap "Add Event" — drawer must open and be visible.
2. Drawer slides up from bottom of screen.
3. Event type segmented control is visible with pill indicator.
4. Can switch between Rehearsal / Gig / Block Out.
5. Can save and cancel without error.

---

## Deviations From Plan
None. Changes match the plan exactly.

---

## Blockers Encountered
None.

---

## Ready For QA
**Yes**
