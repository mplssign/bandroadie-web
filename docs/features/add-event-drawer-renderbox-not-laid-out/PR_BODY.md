## Problem

Tapping "Add Event" from the Dashboard opened the modal bottom sheet but the drawer failed to render, throwing repeated exceptions on **Android and iOS**:

```
RenderBox was not laid out: RenderPointerListener#… relayoutBoundary=up1
RenderBox was not laid out: RenderPhysicalShape#… relayoutBoundary=up4
```

Six prior PRs (#229–#234) each adjusted the drawer's outer container / height / host bottom-sheet mechanism and all shipped broken, because none addressed the true cause.

## Root Cause

The primary error — surfaced by a new widget test that reproduces the failure headlessly — is `BoxConstraints forces an infinite width`, provided to a Material button's `RenderPhysicalShape`. Every "RenderBox was not laid out" line cascades from it.

`AppTheme.darkTheme` globally applies `ElevatedButton` `minimumSize: Size(double.infinity, 52)` (intended so full-width buttons stretch). The event editor's footer primary-action `ElevatedButton` (in `_buildPrimaryActionButton`, rendered for every event type) is a **non-`Expanded` child of the footer `Row`**. A `Row` hands its non-flexible children an unbounded (`maxWidth: infinity`) constraint to measure their intrinsic width; combined with the theme's infinite `minimumSize.width`, the button's constraints resolved to `minWidth == maxWidth == infinity`, tripping the assertion and leaving its entire subtree (the `RenderPhysicalShape`/`RenderPointerListener` seen in the device logs) un-laid-out.

Flutter's `showModalBottomSheet` provides a **bounded** width to its content (`bottom_sheet.dart`), so the host was never the cause — the infinite width was generated inside the drawer by this button.

## Fix

- Override the theme default on both `ElevatedButton` instances in `_buildPrimaryActionButton` with a bounded `minimumSize: const Size(0, 40)`. Visually identical; removes the infinite-width demand.
- Reverted the ineffective one-frame body-defer added during diagnosis (the crash fires on the always-rendered footer, so deferring the body did nothing).

Other drawer buttons were audited: the footer Cancel button already has a bounded `minimumSize`; the view-only Close and soundcheck buttons are wrapped in bounded `SizedBox`es; delete buttons are `Column` children (bounded width). No other button on any event-type or edit-mode path is a non-`Expanded` Row child, so no further changes are needed.

## Verification

- **New widget test** `test/features/events/widgets/event_dropdown_test.dart` (`EventEditorDrawer layout` group) pumps the full `EventEditorDrawer` inside `showModalBottomSheet` on an Android view and asserts zero `BoxConstraints forces an infinite width` and zero `RenderBox was not laid out` errors. It **fails on the pre-fix code and passes after the fix** — the first real reproduction of this bug in the pipeline.
- `flutter test test/features/events/widgets/event_dropdown_test.dart` → all pass.
- `flutter analyze --no-pub` → 0 errors.
- No database migrations. No app build shipped by this PR.
