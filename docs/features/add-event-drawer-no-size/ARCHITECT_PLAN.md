# ARCHITECT PLAN

**Feature Slug:** `bug/add-event-drawer-no-size`
**Feature Title:** Add Event drawer still fails to appear — "Cannot hit test a render box with no size"
**Branch:** `bug/add-event-drawer-no-size`
**Date:** 2026-09-03

---

## 1. Root Cause — HIGH confidence (confirmed in code)

Four prior PRs (#229–232) each fixed one layer of the problem. Two root-cause issues remain.

### Root Cause A — loose layout boundary → FAutocomplete overlay hits unsettled constraints

`EventEditorDrawer.build()` wraps content in:
```dart
Container(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height), ...)
```

`BoxConstraints(maxHeight: H)` with implicit `minHeight = 0` is a **LOOSE** constraint. Flutter only creates a relayout boundary when `parentUsesSize = false` OR when constraints are **tight** (`min == max`). Loose constraints → no relayout boundary.

Each `FAutocomplete` widget embeds `CompositedChild` → `RenderChildLayer`. When `RenderChildLayer` paints, it calls `notifier.notifyListeners()`. The linked `RenderOverlayLayer._schedule()` calls `SchedulerBinding.instance.scheduleTask(markNeedsLayout, Priority.touch)`. If this task runs while Forui's `_ShiftedSheet.performLayout()` is executing (or during pointer device update processing), the `!_debugDuringDeviceUpdate` assertion fires.

Because there is no relayout boundary between the FAutocomplete anchors and `_ShiftedSheet`, the `markNeedsLayout` propagates all the way up to the sheet's render tree during the pointer event frame, triggering:
- `'!_debugDuringDeviceUpdate': is not true` (mouse_tracker.dart)
- `Cannot hit test a render box with no size` (render boxes that had layout aborted mid-frame)

**Fix A:** Replace `Container(constraints: BoxConstraints(maxHeight: H))` with `LayoutBuilder` + `Container(width: constraints.maxWidth, height: constraints.maxHeight)`. The explicit `width` + `height` on `Container` forces TIGHT constraints (both min and max set to the same finite value), creating a relayout boundary. FAutocomplete's layout notifications are contained below this boundary.

`LayoutBuilder` at the root of `EventEditorDrawer.build()` is SAFE here because its parent chain is `Material → NotificationListener → ConstrainedBox → Align → SafeArea → Opacity → ShiftedSheet` — none of these are a `Column`/`Flex` mid-`performLayout` when LayoutBuilder runs. The recursive layout that affected `EventTypeSelector` (PR #232) only occurs when LayoutBuilder is inside a non-flex child of a Column whose `performLayout` hasn't finished. At the root of EventEditorDrawer, no such ancestor exists.

### Root Cause B — FractionallySizedBox pill has no height

PR #232 replaced `LayoutBuilder + Container(height: double.infinity)` with `FractionallySizedBox(widthFactor: 1/N) + Container(decoration: ...)`. The replacement omitted `heightFactor`, so the pill Container's incoming height constraint is loose `(0..38)` and the Container shrinks to height=0 (no child, no explicit height). The pill indicator is invisible.

**Fix B:** Add `heightFactor: 1.0` to the `FractionallySizedBox` in `EventTypeSelector`. This makes the pill container fill 100% of the track height (38px minus 6px padding) — mathematically equivalent to the original `height: double.infinity` behaviour in the bounded context of the Stack.

---

## 2. Solution Approach

### 2a. `event_editor_drawer.dart` — create tight layout boundary at root

Replace the current `build()`:
```dart
// BEFORE
return FTheme(
  data: buildEventEditorTheme(),
  child: Container(
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height),
    decoration: BoxDecoration(...),
    child: Column(...),
  ),
);

// AFTER
return LayoutBuilder(
  builder: (context, constraints) {
    return FTheme(
      data: buildEventEditorTheme(),
      child: Container(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        decoration: BoxDecoration(...),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [...],
        ),
      ),
    );
  },
);
```

Key changes:
- `LayoutBuilder` captures the parent-supplied constraints as concrete finite values
- `Container(width: W, height: H)` with explicit dimensions → tight BoxConstraints → relayout boundary
- Remove `BoxConstraints(maxHeight: ...)` wrapper since Container handles sizing directly
- Add `mainAxisSize: MainAxisSize.min` (matches every other working sheet in the app; Column with tight constraints still sizes to H because Flexible fills remaining space)

### 2b. `event_type_selector.dart` — restore pill height

```dart
// BEFORE
child: FractionallySizedBox(
  widthFactor: 1.0 / availableTypes.length,
  child: Container(decoration: BoxDecoration(...)),
),

// AFTER
child: FractionallySizedBox(
  widthFactor: 1.0 / availableTypes.length,
  heightFactor: 1.0,   // ← add this
  child: Container(decoration: BoxDecoration(...)),
),
```

---

## 3. Files to Modify

| File | Change | Off-limits |
|---|---|---|
| `lib/features/events/widgets/event_editor_drawer.dart` | Wrap build() in LayoutBuilder+Container(tight) | No |
| `lib/features/events/widgets/event_type_selector.dart` | Add `heightFactor: 1.0` to FractionallySizedBox pill | No |

**Off-limits (must not touch):**
- `lib/features/events/widgets/add_edit_event_bottom_sheet.dart`
- `lib/components/ui/app_bottom_sheet.dart`
- Any file not listed above

---

## 4. DB/RLS/RPC Impact

None — UI change only.

---

## 5. Verification Plan

**Tier 1 — Analyzer (required before Engineer marks Ready):**
- `flutter analyze --no-pub` → 0 errors

**Tier 2 — Manual (post-deploy):**
- Tap "Add Event" → drawer opens and is visible
- Event type segmented control shows pill indicator on selected type
- Tap between Rehearsal / Gig / Block Out — pill slides correctly
- No red exceptions in debug console

---

## 6. Task Breakdown

1. **event_editor_drawer.dart**: Wrap `build()` in `LayoutBuilder`, replace `Container(constraints: BoxConstraints(maxHeight: H), decoration: ...)` with `Container(width: constraints.maxWidth, height: constraints.maxHeight, decoration: ...)`, add `mainAxisSize: MainAxisSize.min` to root Column, remove the old `MediaQuery.of(context).size.height` call.
2. **event_type_selector.dart**: Add `heightFactor: 1.0` to the `FractionallySizedBox` that wraps the pill Container.
3. Run `flutter analyze --no-pub` and confirm 0 errors.
