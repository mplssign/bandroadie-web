## Problem

The Add Event drawer failed to appear after tapping "Add Event". Five previous PRs (#229–233) each addressed individual symptoms within Forui's `showFSheet` layout chain, but the drawer continued to fail on device.

## Root Cause

`showFSheet` (Forui's sheet implementation) is incompatible with `EventEditorDrawer` in this configuration. Forui's `_ShiftedSheet` uses `Align(heightFactor:1)` to size content, which passes loose height constraints. `EventEditorDrawer`'s `FAutocomplete` widgets use `CompositedChild` layer links that call `notifier.notifyListeners()` during paint — scheduling `markNeedsLayout` at `Priority.touch`. In Forui's sheet context, this runs during pointer device update processing, triggering the `!_debugDuringDeviceUpdate` Flutter assertion and aborting the frame layout. PR #233's `LayoutBuilder+Container(tight)` workaround introduced a new failure: `Container(height: double.infinity)` when constraints.maxHeight is unbounded in certain Forui sheet configurations.

## Fix

Replace `showAppBottomSheet` (backed by `showFSheet`) with Flutter's native `showModalBottomSheet` in `AddEditEventBottomSheet.show()`. Flutter's bottom sheet implementation:

- Provides stable, bounded height constraints directly (no `Align(heightFactor:1)` indirection)
- Handles `FAutocomplete` overlay portals correctly — Material overlay lifecycle does not conflict with `Priority.touch` scheduling
- Natively supports `isScrollControlled: true` (full-height sheet), `useSafeArea: true`, and `backgroundColor: Colors.transparent`

Also reverts `event_editor_drawer.dart` `build()` from the PR #233 `LayoutBuilder` approach back to the simpler `Container(maxHeight) + Column(mainAxisSize.min)` pattern — which is correct for `showModalBottomSheet`'s constraint chain.

## Changes

- `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` — `showModalBottomSheet` replaces `showAppBottomSheet`; unused `app_bottom_sheet.dart` import removed
- `lib/features/events/widgets/event_editor_drawer.dart` — `LayoutBuilder` removed; `Container(BoxConstraints(maxHeight:H))` + `Column(mainAxisSize.min)` restored

## Testing

- `flutter analyze --no-pub` → 0 issues
- No database migrations. No app build shipped by this PR.
