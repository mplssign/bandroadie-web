## Problem

Tapping "Add Event" showed the modal barrier (dark overlay) but the drawer itself never rendered. Repeated "Cannot hit test a render box with no size" and `!_debugDuringDeviceUpdate` exceptions fired in the debug console. Four previous fix PRs (#229–232) each addressed one contributing factor but left two root causes unresolved.

## Root Causes Fixed

**Root Cause A — loose layout constraint, no relayout boundary**

`EventEditorDrawer.build()` used `Container(constraints: BoxConstraints(maxHeight: H))` with implicit `minHeight = 0` — a *loose* constraint. Flutter only creates a relayout boundary when constraints are *tight* (`min == max`). Without a relayout boundary, `FAutocomplete`'s `CompositedChild.notifier.notifyListeners()` (called during paint) could propagate `markNeedsLayout` all the way up to Forui's `_ShiftedSheet` during pointer device update processing, triggering:
- `'!_debugDuringDeviceUpdate': is not true` (mouse_tracker.dart)
- `Cannot hit test a render box with no size` (render boxes whose layout was aborted)

Fix: wrap `build()` in `LayoutBuilder` and use `Container(width: constraints.maxWidth, height: constraints.maxHeight)`. Explicit finite dimensions force tight `BoxConstraints`, creating a proper relayout boundary that contains `FAutocomplete` layout notifications below the drawer root.

**Root Cause B — pill indicator invisible (height=0)**

PR #232's `FractionallySizedBox` replacement omitted `heightFactor`, so the pill `Container(decoration: ...)` received loose height constraints `(0..38px)` and collapsed to height=0. The segmented control's sliding indicator was invisible.

Fix: add `heightFactor: 1.0` to `FractionallySizedBox` so the pill fills the full track height.

## Changes

- `lib/features/events/widgets/event_editor_drawer.dart` — wrap `build()` in `LayoutBuilder`; replace loose `BoxConstraints(maxHeight:)` with tight `width`/`height` on the root `Container`; add `mainAxisSize: MainAxisSize.min` to root Column
- `lib/features/events/widgets/event_type_selector.dart` — add `heightFactor: 1.0` to `FractionallySizedBox` pill

## Testing

- `flutter analyze --no-pub` → 0 issues
- No database migrations required
- No app build shipped by this PR
