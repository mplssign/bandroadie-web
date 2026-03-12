# ARCHITECT PLAN

Feature Slug
bug/block-out-delete-unreachable-with-keyboard

Feature Title
Block Out delete and edit silently fail — missing parameter forwarding

---

## 1. Problem Summary

When editing a Block Out event on a physical iPhone:

1. Open an existing Block Out event
2. Tap Edit
3. Tap Delete Event
4. Nothing happens — event is not deleted

Save and Cancel buttons function normally for gigs and rehearsals. The Delete button is visible and tappable. This is a **functional bug**, not a layout or keyboard issue.

---

## 2. Root Cause Analysis

### PHASE 1 — System Entry Trace

Full execution path from UI tap to delete handler:

```
calendar_screen.dart → _openEditEventSheet()
  passes: existingBlockOut: event.blockOutSpan ✅

calendar_tab_content.dart → _openEditEventSheet()
  passes: existingBlockOut: event.blockOutSpan ✅

  ↓

AddEditEventBottomSheet.show()
  receives: BlockOutSpan? existingBlockOut ✅
  forwards to EventEditorDrawer: ❌ MISSING

  ↓

EventEditorDrawer (widget.existingBlockOut == null)
  initState: block out fields NOT populated from existing data
  _deleteBlockOut(): silent early return at guard
  _saveBlockOut(): takes create path instead of update path
```

### PHASE 2 — Code Path Verification

The delete handler in `event_editor_drawer.dart` line 1044:

```dart
Future<void> _deleteBlockOut() async {
  if (widget.existingBlockOut == null) return;  // ← SILENT EARLY RETURN
  ...
}
```

Because `widget.existingBlockOut` is always `null`, this guard triggers on every delete attempt. No confirmation dialog is shown. No repository call is made. The function silently returns.

The same null parameter also affects:

- **initState** (line 265): `if (widget.existingBlockOut != null)` — block out form fields (start date, end date, reason) are NOT populated from the existing event data.
- **\_saveBlockOut** (line 996): `if (_isEditMode && widget.existingBlockOut != null)` — the update path is never taken; the create path runs instead.

### PHASE 3 — Data Propagation Analysis

| Layer                                                    | Parameter                              | Passed?                     |
| -------------------------------------------------------- | -------------------------------------- | --------------------------- |
| `calendar_screen._openEditEventSheet()`                  | `existingBlockOut: event.blockOutSpan` | ✅ Yes                      |
| `calendar_tab_content._openEditEventSheet()`             | `existingBlockOut: event.blockOutSpan` | ✅ Yes                      |
| `AddEditEventBottomSheet.show()` method signature        | `BlockOutSpan? existingBlockOut`       | ✅ Declared                 |
| `AddEditEventBottomSheet.show()` → `EventEditorDrawer()` | `existingBlockOut:`                    | ❌ **NOT forwarded**        |
| `EventEditorDrawer` constructor                          | `this.existingBlockOut`                | ✅ Declared (receives null) |
| `_deleteBlockOut()` guard                                | `widget.existingBlockOut == null`      | ❌ Always true              |
| `_saveBlockOut()` edit guard                             | `widget.existingBlockOut != null`      | ❌ Always false             |

The break is at a single point: `AddEditEventBottomSheet.show()` line 68–76.

### PHASE 4 — Competing Hypotheses

| #   | Hypothesis                                        | Evidence For                                                                                      | Evidence Against                                                 | Conclusion                                 |
| --- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------ |
| H1  | Keyboard layout prevents Delete from being tapped | Previous keyboard fix context                                                                     | User confirms Delete IS visible and tappable but nothing happens | **Rejected**                               |
| H2  | Delete handler never fires                        | Delete button calls `_showDeleteConfirmation` which calls `_deleteBlockOut`                       | Handler fires but returns silently at null guard                 | **Rejected** (handler fires, guard blocks) |
| H3  | `existingBlockOut` not passed to editor           | `AddEditEventBottomSheet.show()` accepts parameter but does not forward it to `EventEditorDrawer` | Fix applied adds the forwarding                                  | **Confirmed**                              |
| H4  | Repository delete call failing                    | Repository code not reached due to null guard                                                     | No error is thrown; function never reaches repository            | **Rejected** (never reached)               |
| H5  | UI state mismatch (create vs edit mode)           | Mode is correctly set to `EventEditorMode.edit`                                                   | Mode is correct but `existingBlockOut` is null regardless        | **Rejected**                               |

**Selected cause: H3** — strongest evidence. The code path proves the parameter is accepted but not forwarded.

### PHASE 5 — Root Cause Proof

**File:** `lib/features/events/widgets/add_edit_event_bottom_sheet.dart`
**Function:** `AddEditEventBottomSheet.show()`
**Lines:** 68–76

Before fix:

```dart
builder: (context) => EventEditorDrawer(
  mode: editorMode,
  initialEventType: initialType,
  initialDate: initialDate,
  existingEventId: existingEventId,
  existingEvent: initialData,
  bandId: bandId,
  onSaved: onSaved,
  viewOnly: viewOnly,
  // existingBlockOut: existingBlockOut,  ← MISSING
),
```

The `existingBlockOut` parameter is accepted by `show()` at line 48 but never included in the `EventEditorDrawer` constructor call. The parameter is silently dropped, and `EventEditorDrawer.existingBlockOut` defaults to `null`.

This causes three downstream failures:

1. `initState` does not populate block out form fields from existing data
2. `_deleteBlockOut()` silently returns at the null guard (line 1045)
3. `_saveBlockOut()` takes the create path instead of update (line 996)

---

## 3. System Behavior Analysis

### What works

- Gig delete: uses `existingEventId` and `EventFormData` (different parameter path, correctly forwarded)
- Rehearsal delete: uses `existingEventId` and `EventFormData` (same correct path as gigs)
- Block out create: does not need `existingBlockOut` (creates new, no existing data required)
- Save/Cancel buttons: not dependent on `existingBlockOut`

### What fails

- Block out delete: requires `widget.existingBlockOut` for the repository call parameters (`userId`, `startDate`, `endDate`)
- Block out edit/update: requires `widget.existingBlockOut` to determine the update path and delete the old span
- Block out form population in edit mode: requires `widget.existingBlockOut` to show the existing start date, end date, and reason

---

## 4. Minimal Solution

**One-line fix.** Add the missing parameter forwarding.

**File:** `lib/features/events/widgets/add_edit_event_bottom_sheet.dart`
**Location:** Inside `showModalBottomSheet` builder, `EventEditorDrawer` constructor call

Add:

```dart
existingBlockOut: existingBlockOut,
```

This is the complete fix. No other files need changes. No refactoring required.

---

## 5. Files To Modify

| File                                                           | Change                                                                                      |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Add `existingBlockOut: existingBlockOut` to `EventEditorDrawer` constructor call (line ~75) |

---

## 6. Exact Code Strategy

### Before (line 68–76)

```dart
builder: (context) => EventEditorDrawer(
  mode: editorMode,
  initialEventType: initialType,
  initialDate: initialDate,
  existingEventId: existingEventId,
  existingEvent: initialData,
  bandId: bandId,
  onSaved: onSaved,
  viewOnly: viewOnly,
),
```

### After

```dart
builder: (context) => EventEditorDrawer(
  mode: editorMode,
  initialEventType: initialType,
  initialDate: initialDate,
  existingEventId: existingEventId,
  existingEvent: initialData,
  bandId: bandId,
  onSaved: onSaved,
  viewOnly: viewOnly,
  existingBlockOut: existingBlockOut,
),
```

One line added. No lines removed. No lines modified.

---

## 7. Database Impact

None.

---

## 8. Flutter Architecture Impact

None. The fix uses existing parameters and existing constructor fields. No new state, no new widgets, no new dependencies. The `EventEditorDrawer.existingBlockOut` field already exists and is already consumed by `initState`, `_deleteBlockOut`, and `_saveBlockOut`.

---

## 9. Risks / Edge Cases

| Risk                                                         | Assessment                                                                                                                                                               |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Regression to gig/rehearsal editing                          | **None.** Fix adds a named parameter that does not affect other event type paths. Gigs and rehearsals use `existingEventId` and `existingEvent`, which remain unchanged. |
| Block out create mode regression                             | **None.** When creating a new block out, `existingBlockOut` is not passed by callers, so it remains `null`. The create path in `_saveBlockOut` handles `null` correctly. |
| Double-delete if parameter was partially forwarded elsewhere | **None.** There is only one call site for `EventEditorDrawer` — inside `AddEditEventBottomSheet.show()`. No other code path constructs the drawer.                       |

---

## 10. Verification Plan

### Manual QA Steps

1. **Block Out — Delete**
   - Open an existing Block Out event
   - Tap Edit
   - Tap Delete Event
   - Confirm the delete confirmation dialog appears
   - Tap Delete in the dialog
   - Verify the block out is removed from the calendar

2. **Block Out — Edit/Update**
   - Open an existing Block Out event
   - Tap Edit
   - Verify the form is populated with the correct start date, end date, and reason
   - Change the reason text
   - Tap Save
   - Verify the block out is updated

3. **Block Out — Create (no regression)**
   - Tap Add Event
   - Select Block Out type
   - Set start date and reason
   - Tap Save
   - Verify the block out appears on the calendar

4. **Gig — Edit/Delete (no regression)**
   - Open an existing Gig
   - Verify edit and delete still work correctly

5. **Rehearsal — Edit/Delete (no regression)**
   - Open an existing Rehearsal
   - Verify edit and delete still work correctly

### Devices to Test

- Physical iPhone (primary reproduction device)
- iOS Simulator
- Android device or emulator

---

## 11. Engineer Task Breakdown

1. Open `lib/features/events/widgets/add_edit_event_bottom_sheet.dart`
2. Locate the `EventEditorDrawer` constructor call inside `showModalBottomSheet` builder (~line 68)
3. Add `existingBlockOut: existingBlockOut,` after the `viewOnly: viewOnly,` line
4. Run `flutter analyze` — expect 0 errors, 0 warnings
5. Test block out delete, block out edit, and block out create on a device
