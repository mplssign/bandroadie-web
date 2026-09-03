# ARCHITECT PLAN

**Feature Slug:** `bug/add-event-drawer-still-not-showing`
**Feature Title:** Add Event drawer still not showing after 5 prior fix attempts
**Branch:** `bug/add-event-drawer-still-not-showing`
**Date:** 2026-09-03

---

## 1. Root Cause — HIGH confidence (confirmed in code + fix history)

Five PRs (#229–233) have individually addressed every identified symptom (mainAxisSize, Center, DecoratedBox→Container, LayoutBuilder recursion, tight boundary). The drawer still fails to appear on device. The common factor across all failures is `showFSheet` (Forui's `_ShiftedSheet` + `Align(heightFactor:1)` layout chain). No further symptom-chasing within the Forui path is warranted.

### Definitive root cause: `showFSheet` is incompatible with `EventEditorDrawer` in this configuration

Forui's `showFSheet` uses a custom `_ShiftedSheet` render object that:
1. Passes LOOSE height constraints through `Align(heightFactor:1).loosen()` to content
2. Uses the content's rendered size to compute the sheet's y-offset
3. Wraps in `capturedFTheme` + `capturedThemes` (InheritedTheme) which may reorder the inherited widget tree

`EventEditorDrawer` uses `FAutocomplete` widgets (Forui) whose `CompositedChild` layer calls `notifier.notifyListeners()` during paint, scheduling `markNeedsLayout` via `SchedulerBinding.scheduleTask(Priority.touch)`. In Forui's `_ShiftedSheet` context, this schedule runs during pointer event processing, violating the `!_debugDuringDeviceUpdate` assertion and aborting the layout mid-frame.

PR #233's tight `LayoutBuilder+Container` workaround was theoretically correct but introduces its own failure: `LayoutBuilder.constraints.maxHeight` is not guaranteed to be finite in all Forui sheet configurations (e.g., when `Align(heightFactor:1)` receives `maxHeight = double.infinity` from an edge-case constraint chain). `Container(height: double.infinity)` throws a `FlutterError` in debug mode, causing the drawer to fail silently.

### Fix: bypass `showFSheet` entirely for `EventEditorDrawer`

Replace `showAppBottomSheet` with Flutter's native `showModalBottomSheet` in `AddEditEventBottomSheet.show()`. Flutter's `showModalBottomSheet`:
- Uses a stable, well-tested constraint chain (no `Align(heightFactor:1)` complication)
- Gives content a bounded height up to the viewport (keyboard-adjusted)
- Works correctly with `FAutocomplete` within Material sheets (no `_debugDuringDeviceUpdate` issue)
- Supports `isScrollControlled: true` (full height) and `useSafeArea: true`

---

## 2. Solution Approach

### 2a. `add_edit_event_bottom_sheet.dart` — switch to `showModalBottomSheet`

Replace `showAppBottomSheet<bool>(...)` with `showModalBottomSheet<bool>(...)`:

```dart
return showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  useSafeArea: true,
  builder: (context) => EventEditorDrawer(...),
);
```

Remove unused `showAppBottomSheet` import if it becomes unused (check).

### 2b. `event_editor_drawer.dart` — revert to simple build(), remove LayoutBuilder

Replace the PR #233 `LayoutBuilder` with the pattern that works for `showModalBottomSheet`:

```dart
Widget build(BuildContext context) {
  return FTheme(
    data: buildEventEditorTheme(),
    child: Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height,
      ),
      decoration: BoxDecoration(
        color: kEdSurface,
        border: Border.all(color: kEdCardBorder),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 60,
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStickyHeader(context),
          Container(height: 1, color: kEdCardBorder),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildScrollableBody(context),
            ),
          ),
          _buildStickyFooter(context),
        ],
      ),
    ),
  );
}
```

With `showModalBottomSheet(isScrollControlled: true)`:
- Content receives bounded constraints from Flutter's bottom sheet layout (not Forui's Align)
- `Container(maxHeight: H)` + `Column(mainAxisSize.min)` + `Flexible` = standard working pattern
- `FAutocomplete` overlay portals work correctly within Material's overlay lifecycle

---

## 3. Files to Modify

| File | Change |
|---|---|
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Replace `showAppBottomSheet` → `showModalBottomSheet` |
| `lib/features/events/widgets/event_editor_drawer.dart` | Remove `LayoutBuilder`, restore `Container(maxHeight)+Column(min)` |

**Off-limits (must not touch):**
- `lib/components/ui/app_bottom_sheet.dart`
- Any file not listed above

---

## 4. DB/RLS/RPC Impact

None.

---

## 5. Verification Plan

**Tier 1:** `flutter analyze --no-pub` → 0 errors.

**Tier 2 (manual, post-deploy):**
- Tap "Add Event" → drawer opens and is visible
- Drawer slides up from bottom of screen
- Event type segmented control is visible with pill indicator
- Can switch between Rehearsal / Gig / Block Out
- Can save and cancel

---

## 6. Task Breakdown

1. `add_edit_event_bottom_sheet.dart`: Replace `showAppBottomSheet` call with `showModalBottomSheet`. Keep all other parameters identical (mode, initialType, etc.). Remove `app_bottom_sheet.dart` import if it's no longer used (check other usages in file first).
2. `event_editor_drawer.dart`: Replace `LayoutBuilder { Container(width:, height:) }` with `Container(constraints: BoxConstraints(maxHeight: H))` + `Column(mainAxisSize.min)` pattern. The `height` on Container uses `MediaQuery.of(context).size.height`.
3. Run `flutter analyze --no-pub`. Confirm 0 errors.
