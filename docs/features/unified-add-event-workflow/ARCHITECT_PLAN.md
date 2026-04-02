# ARCHITECT PLAN — Unified Add Event Workflow

**Feature Branch:** `feature/unified-add-event-workflow`
**Date:** 2026-03-07
**Status:** Architecture Complete — Ready for Engineer

---

## 1. Problem Summary

Event creation in BandRoadie is currently spread across multiple separate entry points and buttons:

- **Dashboard Quick Actions:** `+ Schedule Rehearsal`, `+ Create Gig`, `+ Block Out` (three separate buttons)
- **Calendar screen:** `Add Event` button (opens rehearsal/gig editor) and `Block Out` button (opens a completely separate drawer)

The Block Out workflow is isolated from the main event editor drawer, which already supports a Rehearsal/Gig toggle. This results in:

1. Multiple buttons performing related actions, increasing UI complexity
2. Inconsistent entry points for event creation
3. A separate Block Out drawer that cannot be reached from the unified event editor

The request is to consolidate all event creation into a single `+ Add Event` action that opens the existing event editor drawer with a three-way toggle: **Rehearsal | Gig | Block Out**.

---

## 2. Existing System Analysis

### 2.1 Event Editor Drawer (`lib/features/events/widgets/event_editor_drawer.dart`)

- Full-featured modal bottom sheet for creating/editing rehearsals and gigs
- Supports `EventEditorMode.create` and `EventEditorMode.edit`
- Has an event type toggle (`_buildEventTypeToggle()`) that renders `EventType.values` as selectable toggle buttons in a `Row`
- Toggle is disabled in edit mode (event type cannot change after creation)
- Currently `EventType` enum has two values: `rehearsal` and `gig`
- RBAC: Contributors see only available types (e.g., gig only); toggle hides rehearsal for contributors
- Form fields conditionally rendered based on `_eventType`

### 2.2 Block Out Drawer (`lib/features/calendar/widgets/add_block_out_drawer.dart`)

- Separate `ConsumerStatefulWidget` opened via `BlockOutDrawer.show()`
- Supports three modes: `create`, `edit`, `viewOnly`
- Form fields: Start Date, End Date (optional), Reason (optional)
- RBAC: Only admins and members can create block outs (contributors blocked)
- Only the creator can edit/delete their block out
- Uses `BlockOutRepository` for CRUD operations
- Saves to `block_dates` table via `blockOutRepositoryProvider`

### 2.3 Add/Edit Event Bottom Sheet (`lib/features/events/widgets/add_edit_event_bottom_sheet.dart`)

- Thin wrapper around `EventEditorDrawer` for backward compatibility
- All existing callers go through `AddEditEventBottomSheet.show()`
- Takes `initialType: EventType` to determine which toggle is pre-selected
- Validates band context before opening

### 2.4 Entry Points — Dashboard

**`home_screen.dart`:**

- `_openAddEventSheet(EventType)` — opens `AddEditEventBottomSheet.show()` with the given type
- `_handleBlockOut()` — opens `BlockOutDrawer.show()` separately
- `QuickActionsRow` renders `+ Schedule Rehearsal`, `+ Create Gig`, `+ Block Out` as separate buttons
- `EmptyHomeState` passes the same callbacks for the same buttons

**`home_tab_content.dart`:**

- Same pattern: `_openAddEventSheet(EventType)` and `_handleBlockOut()` as separate handlers
- Same `QuickActionsRow` with the same separate buttons

### 2.5 Entry Points — Calendar

**`calendar_screen.dart`:**

- `_handleAddEvent()` — opens `AddEditEventBottomSheet.show()` with default type based on permissions
- `_handleBlockOut()` — opens `BlockOutDrawer.show()` separately
- Renders two buttons: "Add Event" and "Block Out"

**`calendar_tab_content.dart`:**

- Same pattern: `_handleAddEvent()` and `_handleBlockOut()` as separate handlers
- `_buildActionButtons()` renders an "Add Event" + "Block Out" row for admins/members
- Day tap on empty day opens `AddEditEventBottomSheet` with the tapped date
- Day tap on day with events opens `DayDetailBottomSheet` with an `onAddEvent` callback

### 2.6 Quick Actions Row (`lib/features/home/widgets/quick_actions_row.dart`)

- `StatelessWidget` with four optional callbacks: `onScheduleRehearsal`, `onCreateSetlist`, `onCreateGig`, `onBlockOut`
- Four visibility booleans: `showScheduleRehearsal`, `showCreateSetlist`, `showCreateGig`, `showBlockOut`
- Renders as a horizontal scrolling `ListView` of `BrandActionButton` widgets

### 2.7 Empty Home State (`lib/features/home/widgets/empty_home_state.dart`)

- Accepts callbacks: `onScheduleRehearsal`, `onCreateGig`, `onCreateSetlist`, `onBlockOut`
- Passes them through to `QuickActionsRow`

### 2.8 Event Form Data Model (`lib/features/events/models/event_form_data.dart`)

- `EventType` enum: `rehearsal`, `gig` (two values)
- Used for toggle display via `displayName` getter
- `EventFormData` class holds form state for serialization

### 2.9 RBAC Permission Model

- `BandPermissions` class (`lib/features/members/permissions/band_permissions.dart`)
- Block outs: admins and members only — contributors are blocked
- Gigs: admins, members, and contributors with `canCreateGigs` permission
- Rehearsals: admins and members only — contributors are blocked
- These rules must be preserved in the unified flow

### 2.10 Tips & Tricks

- `lib/components/overlays/tips_and_tricks_overlay.dart` references `"Tap + Schedule Rehearsal or + Create Gig"` — this text will need updating

---

## 3. Root Cause

Not applicable — this is a feature, not a bug.

---

## 4. Proposed Solution

### 4.1 Extend `EventType` Enum with `blockOut`

Add `blockOut` as a third value to the existing `EventType` enum in `event_form_data.dart`. This is the minimal change needed to enable the three-way toggle in the event editor drawer.

### 4.2 Integrate Block Out Form into Event Editor Drawer

When `_eventType == EventType.blockOut`, the event editor drawer renders the Block Out form fields (Start Date, End Date, Reason) instead of the rehearsal/gig fields. The Block Out save logic (currently in `BlockOutDrawer`) is incorporated into the event editor drawer's save handler.

Key behavior:

- Block Out form fields: Start Date (required), End Date (optional), Reason (optional) — same as current `BlockOutDrawer`
- Save uses existing `BlockOutRepository` via `blockOutRepositoryProvider`
- RBAC: Block Out toggle option is hidden for contributors (same as current behavior)
- Delete functionality is available in edit mode for block outs (creator-only)

### 4.3 Update `AddEditEventBottomSheet` Wrapper

The wrapper already accepts `initialType: EventType`. Since `EventType` gains a new value `blockOut`, the existing API naturally supports it. No breaking changes.

### 4.4 Consolidate Dashboard Quick Actions

Replace three separate event buttons with a single `+ Add Event` button:

- `QuickActionsRow` removes `onScheduleRehearsal`, `onBlockOut`, and their visibility flags
- Replaces them with a single `onAddEvent` callback
- The `+ Create Setlist` button remains separate (it's a different workflow, not an event)
- Callers (`home_screen.dart`, `home_tab_content.dart`, `empty_home_state.dart`) consolidate their handlers

When `+ Add Event` is tapped:

- Opens the event editor drawer via `AddEditEventBottomSheet.show()` with `initialType: EventType.rehearsal` (default for admins/members) or `EventType.gig` (for contributors with gig permission)
- The three-way toggle inside the drawer lets users switch to any permitted type

### 4.5 Consolidate Calendar Action Buttons

Replace the two-button layout ("Add Event" + "Block Out") with a single "+ Add Event" button:

- `_buildActionButtons()` in `calendar_tab_content.dart` renders a single `BrandActionButton`
- `_handleBlockOut()` method is removed from calendar screens — block out creation is now accessed via the event editor toggle
- Same change in `calendar_screen.dart`

### 4.6 Preserve Existing Edit Flows

When tapping an existing event to edit:

- Gigs → open event editor with `EventType.gig` (unchanged)
- Rehearsals → open event editor with `EventType.rehearsal` (unchanged)
- Block outs → open event editor with `EventType.blockOut` and `viewOnly`/`edit` mode based on creator check (replaces current `BlockOutDrawer.show()` for edit/view)

### 4.7 RBAC Preservation

The toggle visibility rules in the unified drawer:

- **Admin/Member:** all three toggles visible (Rehearsal, Gig, Block Out)
- **Contributor with gig permission:** only Gig toggle visible (same as current — no rehearsal, no block out)
- **Contributor without gig permission:** no event creation at all (same as current)

### 4.8 Backward Compatibility

- `BlockOutDrawer` is retained in the codebase but no longer invoked from dashboard or calendar creation flows
- It remains available for any other callers if needed, and can be deprecated/removed in a future cleanup
- All existing data, RLS policies, and database schema are unchanged

---

## 5. Database Impact

**None.** This is a pure Flutter UI refactor. No schema, table, column, or data changes are required. The Block Out form continues to use the same `block_dates` table and `BlockOutRepository`.

---

## 6. RLS / RPC Changes

**None.** No RLS policies, RPC functions, or database triggers are affected. The existing block_dates RLS policies remain valid and enforced.

---

## 7. Flutter Architecture Changes

### 7.1 `EventType` Enum Extension

`lib/features/events/models/event_form_data.dart`:

- Add `EventType.blockOut` with `displayName` = `'Block Out'`

### 7.2 Event Editor Drawer Changes

`lib/features/events/widgets/event_editor_drawer.dart`:

**Toggle:** `_buildEventTypeToggle()` already renders `EventType.values`. Adding `blockOut` to the enum automatically populates the third toggle. RBAC filtering already excludes types for contributors — extend this to also exclude `blockOut` for contributors.

**Form rendering:** Add a conditional block: when `_eventType == EventType.blockOut`, render the block out form fields (Start Date, End Date, Reason) instead of the rehearsal/gig form fields.

**State:** Reuse `_selectedDate` for block out start date. Add `_untilDate` as a new nullable `DateTime` for block out end date. Add a dedicated `_reasonController` (`TextEditingController`) for block out reason — do **not** reuse `_notesController`, as that would cause state bleed when a user has typed rehearsal/gig notes before switching to Block Out.

**Save logic:** Add a `_saveBlockOut()` method that delegates to `BlockOutRepository.createBlockOut()` (within `_handleSave()`). For edit mode, add `_updateBlockOut()` and `_deleteBlockOut()` methods mirroring the current `BlockOutDrawer` logic.

**Edit mode for block outs:** The drawer needs to accept block out data for editing. Add optional `existingBlockOut` parameter (type `BlockOutSpan?`) and populate form state from it in `initState()`.

### 7.3 `AddEditEventBottomSheet` Wrapper

`lib/features/events/widgets/add_edit_event_bottom_sheet.dart`:

- Pass through the new `existingBlockOut` parameter to `EventEditorDrawer`
- No other changes needed — the wrapper already accepts `EventType`

### 7.4 Quick Actions Row Simplification

`lib/features/home/widgets/quick_actions_row.dart`:

**Revised approach:** Replace all event-related buttons with a single `+ Add Event`:

- Remove: `onScheduleRehearsal`, `onCreateGig`, `onBlockOut` and their `show*` flags
- Add: `onAddEvent`, `showAddEvent`
- Keep: `onCreateSetlist`, `showCreateSetlist` (setlist creation is separate)

### 7.5 Empty Home State

`lib/features/home/widgets/empty_home_state.dart`:

- Replace `onScheduleRehearsal`, `onCreateGig`, `onBlockOut` with `onAddEvent`
- Update `QuickActionsRow` invocation

### 7.6 Dashboard Screens

`lib/features/home/home_screen.dart`:

- Replace `_openAddEventSheet(EventType.rehearsal)` and `_openAddEventSheet(EventType.gig)` calls from `QuickActionsRow` with a single `_handleAddEvent()`
- Remove `_handleBlockOut()` (block out creation now accessed via drawer toggle)
- `_handleAddEvent()` opens `AddEditEventBottomSheet.show()` with default type (rehearsal for admin/member, gig for contributor with gig permission)
- Block out edit flow: `home_screen.dart` does not have a dedicated block out edit path — block out taps are handled from the calendar. No block out edit changes are required in this file.

`lib/features/home/home_tab_content.dart`:

- Same Quick Actions consolidation as `home_screen.dart`
- No block out edit changes required in this file either

### 7.7 Calendar Screens

`lib/features/calendar/calendar_tab_content.dart`:

- `_buildActionButtons()`: render single `+ Add Event` button instead of two buttons
- Remove `_handleBlockOut()` method
- `_openEditEventSheet()`: when `event.isBlockOut` is true, open `AddEditEventBottomSheet.show()` with `initialType: EventType.blockOut`, `mode: EventFormMode.edit`, and `existingBlockOut: blockOutSpan` instead of `BlockOutDrawer.show()`
- `_handleDayTap()` on empty day: opens `AddEditEventBottomSheet.show()` with default type and `initialDate` (unchanged behavior, just no separate block out option)

`lib/features/calendar/calendar_screen.dart`:

- Same consolidation: remove `_handleBlockOut()`, single `+ Add Event` button
- Same `_openEditEventSheet()` update for block out edit detection

### 7.8 Tips & Tricks Text Update

`lib/components/overlays/tips_and_tricks_overlay.dart`:

- Update `'Tap + Schedule Rehearsal or + Create Gig to get things on the calendar fast.'` to reference `+ Add Event`

---

## 8. Exact Files to Create

None. This feature does not require new files. All changes are modifications to existing files.

---

## 9. Exact Files to Modify

| File                                                           | Change                                                                                                                                            |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/models/event_form_data.dart`              | Add `blockOut` to `EventType` enum with `displayName`                                                                                             |
| `lib/features/events/widgets/event_editor_drawer.dart`         | Add block out form fields, `_reasonController`, save/edit/delete logic, `existingBlockOut` parameter, RBAC toggle filtering for `blockOut`        |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Pass through `existingBlockOut` parameter to `EventEditorDrawer`                                                                                  |
| `lib/features/home/widgets/quick_actions_row.dart`             | Replace `onScheduleRehearsal`, `onCreateGig`, `onBlockOut` with single `onAddEvent`; keep `onCreateSetlist`                                       |
| `lib/features/home/widgets/empty_home_state.dart`              | Replace `onScheduleRehearsal`, `onCreateGig`, `onBlockOut` with `onAddEvent`                                                                      |
| `lib/features/home/home_screen.dart`                           | Consolidate event creation into single `_handleAddEvent()`; remove `_handleBlockOut()`; update `QuickActionsRow` and `EmptyHomeState` invocations |
| `lib/features/home/home_tab_content.dart`                      | Same Quick Actions consolidation as `home_screen.dart`                                                                                            |
| `lib/features/calendar/calendar_tab_content.dart`              | Consolidate to single `+ Add Event` button; remove `_handleBlockOut()`; update `_openEditEventSheet()` for block out edit detection               |
| `lib/features/calendar/calendar_screen.dart`                   | Same consolidation; update `_openEditEventSheet()` for block out edit detection                                                                   |
| `lib/components/overlays/tips_and_tricks_overlay.dart`         | Update tip text referencing old button names                                                                                                      |

---

## 10. Risks / Edge Cases

### 10.1 Event Type Toggle in Edit Mode

The toggle is disabled in edit mode — this means when editing a block out, the type will be locked to "Block Out" and users cannot switch it to gig/rehearsal. This is correct and consistent with current behavior.

### 10.2 Block Out Creator-Only Editing

Block outs can only be edited by their creator. The event editor must enforce this same rule by passing `viewOnly: true` when the current user is not the block out creator. This is critical and must match the existing `BlockOutDrawer` behavior.

### 10.3 Block Out RBAC Gate

Contributors cannot create block outs. The `_buildEventTypeToggle()` already filters `EventType.values` based on RBAC. The new `blockOut` type must be filtered out for contributors, matching the existing gate in `_handleBlockOut()`.

### 10.4 Block Out Form State Isolation

The event editor drawer has extensive state for rehearsal/gig forms (location, gig name, recurring options, potential gig, member selection, setlists, etc.). When `blockOut` is selected, only the block out fields should be active. The save handler must distinguish the event type and call the appropriate save logic. Risk: accidentally including gig/rehearsal fields in block out saves. Mitigation: clear separation in `_handleSave()` and a dedicated `_reasonController` (not shared with `_notesController`).

### 10.5 Block Out Edit Data Mapping

Currently `EventFormData.fromCalendarEvent()` maps gig/rehearsal events. A new mapping path is needed for block out events to populate the editor in edit mode. The `BlockOutSpan` data must be converted to populate `_selectedDate`, `_untilDate`, and `_reasonController.text` in `initState()`.

### 10.6 Existing `BlockOutDrawer` Callers

The `BlockOutDrawer` is currently called from `calendar_screen.dart`, `calendar_tab_content.dart`, `home_screen.dart`, and `home_tab_content.dart`. All these callers must be updated. If any caller is missed, users would see the old separate drawer.

### 10.7 Day Detail Bottom Sheet — Add Event Callback

`DayDetailBottomSheet` has an `onAddEvent` callback that opens the event editor from within the day detail view. This needs no structural change — it already opens `AddEditEventBottomSheet.show()`. However, the default event type must still follow RBAC rules.

### 10.8 Empty Home State Gig Card "Create Gig" Button

The `EmptyHomeState` widget has an `EmptySectionCard` with "Create Gig" button. This card-level CTA should continue to open the event editor with `EventType.gig` pre-selected, not the generic add flow.

---

## 11. Verification Plan

### After Implementation

```bash
flutter analyze
```

No errors or new warnings expected.

### Manual Verification Matrix

**Dashboard (admin/member):**

1. Quick Actions shows `+ Add Event` and `+ Create Setlist` (no separate rehearsal/gig/block out buttons)
2. Tapping `+ Add Event` opens event editor with three-way toggle: Rehearsal | Gig | Block Out
3. Can switch between all three types
4. Creating a rehearsal works correctly
5. Creating a gig works correctly
6. Selecting Block Out shows: Start Date, End Date (optional), Reason (optional)
7. Creating a block out works correctly and appears on calendar

**Dashboard (contributor with gig permission):**

8. Quick Actions shows `+ Add Event` and no setlist button
9. Event editor toggle shows only "Gig" (no rehearsal, no block out)

**Dashboard (contributor without gig permission):**

10. No `+ Add Event` button shown

**Calendar (admin/member):**

11. Single `+ Add Event` button (no separate Block Out button)
12. Tapping `+ Add Event` opens event editor with three-way toggle
13. Tapping empty day opens event editor with date pre-filled
14. Tapping existing block out opens event editor in edit mode with block out data
15. Non-creator viewing block out sees read-only view
16. Creator can edit and delete block out through event editor

**Calendar (contributor):**

17. Appropriate buttons shown/hidden based on permissions

**Edit flows:**

18. Editing existing rehearsal → type locked, correct form fields
19. Editing existing gig → type locked, correct form fields
20. Editing existing block out (creator) → type locked, block out fields, can save/delete
21. Viewing existing block out (non-creator) → view-only, cannot save/delete

**Empty state:**

22. Empty home state shows `+ Add Event` instead of separate buttons
23. "Create Gig" on empty gig card still opens with gig pre-selected

**Regression:**

24. Block out data persists correctly (start date, end date, reason)
25. Block out calendar indicators display correctly
26. Block out spans display correctly in day detail
27. Recurring rehearsal creation still works
28. Potential gig creation still works
29. Multi-date gig creation still works

---

## 12. Engineer Task Breakdown

### Task 1: Extend EventType Enum

- Add `blockOut` to `EventType` enum in `event_form_data.dart`
- Add `displayName` = `'Block Out'`
- **File:** `lib/features/events/models/event_form_data.dart`

### Task 2: Add Block Out Support to Event Editor Drawer

- Add `existingBlockOut` parameter (type `BlockOutSpan?`) to `EventEditorDrawer`
- Add block out form state:
  - Reuse `_selectedDate` for block out start date
  - Add `_untilDate` as a new nullable `DateTime` for block out end date
  - Add a dedicated `_reasonController` (`TextEditingController`) for block out reason — do NOT reuse `_notesController`
- Dispose `_reasonController` in `dispose()`
- Add `_buildBlockOutForm()` method rendering Start Date, End Date (optional), Reason (optional)
- In `_buildEventTypeToggle()`: filter out `EventType.blockOut` for contributors
- In the scrollable form content: conditionally render `_buildBlockOutForm()` when `_eventType == EventType.blockOut`
- Add `_saveBlockOut()` method using `blockOutRepositoryProvider`
- Add `_updateBlockOut()` method for edit mode
- Add `_deleteBlockOut()` method for edit mode (creator-only)
- In `initState()`: when `existingBlockOut != null`, populate `_selectedDate`, `_untilDate`, and `_reasonController.text` from the block out data
- Handle `viewOnly` mode for block outs (non-creator viewing): disable form fields and hide save/delete buttons
- **File:** `lib/features/events/widgets/event_editor_drawer.dart`

### Task 3: Update AddEditEventBottomSheet Wrapper

- Add optional `existingBlockOut` parameter (`BlockOutSpan?`)
- Pass it through to `EventEditorDrawer`
- **File:** `lib/features/events/widgets/add_edit_event_bottom_sheet.dart`

### Task 4: Simplify Quick Actions Row

- Remove `onScheduleRehearsal`, `onCreateGig`, `onBlockOut` and their `show*` flags
- Add `onAddEvent` (`VoidCallback?`), `showAddEvent` (`bool`)
- Render single `+ Add Event` button (followed by `+ Create Setlist` if shown)
- **File:** `lib/features/home/widgets/quick_actions_row.dart`

### Task 5: Update Empty Home State

- Replace `onScheduleRehearsal`, `onCreateGig`, `onBlockOut` with `onAddEvent`
- Update `QuickActionsRow` invocation
- **File:** `lib/features/home/widgets/empty_home_state.dart`

### Task 6: Update Dashboard Screens

- `home_screen.dart`:
  - Create `_handleAddEvent()` that opens `AddEditEventBottomSheet.show()` with `initialType: EventType.rehearsal` for admin/member or `EventType.gig` for contributor with gig permission
  - Remove `_handleBlockOut()`
  - Update `QuickActionsRow` invocations in `_buildContentScreen()` and `EmptyHomeState` to use `onAddEvent: _handleAddEvent`
  - No block out edit changes required (block out taps originate from calendar, not home screen)
- `home_tab_content.dart`: same Quick Actions consolidation
- **Files:** `lib/features/home/home_screen.dart`, `lib/features/home/home_tab_content.dart`

### Task 7: Update Calendar Screens

- `calendar_tab_content.dart`:
  - Update `_buildActionButtons()` to render single `+ Add Event` button
  - Remove `_handleBlockOut()` method
  - Update `_openEditEventSheet()`: when `event.isBlockOut == true`, open `AddEditEventBottomSheet.show()` with `initialType: EventType.blockOut`, `mode: EventFormMode.edit`, and `existingBlockOut: blockOutSpan` instead of calling `BlockOutDrawer.show()`
- `calendar_screen.dart`: same consolidation and same `_openEditEventSheet()` update
- **Files:** `lib/features/calendar/calendar_tab_content.dart`, `lib/features/calendar/calendar_screen.dart`

### Task 8: Update Tips & Tricks Text

- Update tip text that references old button names
- Search: `'Tap + Schedule Rehearsal or + Create Gig'`
- Replace with: `'Tap + Add Event'`
- **File:** `lib/components/overlays/tips_and_tricks_overlay.dart`

### Task 9: Run Verification

- Run `flutter analyze`
- Manual verification of all flows per verification matrix in Section 11
- Test on at least one platform (macOS or web)

---

## 13. Rollout / Migration Strategy

### Single Deployment

This is a **pure Flutter UI change** with no database, RLS, or backend modifications. It can be deployed in a single release.

### No Data Migration

No user data is affected. Block out records continue to use the same `block_dates` table and schema. No migration scripts needed.

### Backward Compatibility

- `BlockOutDrawer` widget class remains in the codebase (unused by main flows, but not deleted)
- No changes to the block out data model or repository
- External calendar feeds are unaffected
- All existing block out records display and edit correctly

### Rollback Plan

If issues are discovered post-deployment, reverting the feature branch restores all original entry points and flows. No data cleanup is needed.

---

## 14. Out of Scope

- **Deleting `BlockOutDrawer`:** The old drawer widget is not removed in this feature. It can be cleaned up in a separate task after verification.
- **Block out recurrence:** The current block out form supports multi-day spans but not recurring patterns. Adding block out recurrence is a separate feature.
- **Event type changing in edit mode:** Event types remain locked after creation. Allowing type changes would be a separate design decision.
- **Notification changes:** Block out creation/deletion notifications (if any exist) are not modified.
- **Help text in `BAND_ROADIE_DOCUMENTATION.md`:** The main documentation references may mention separate actions — updating that is out of scope for this feature unless explicitly requested.
- **New database migrations or schema changes:** None needed or planned.
- **Refactoring the event editor into smaller components:** The drawer is already large; splitting it is a separate concern.

---

## 15. Widget Contracts (Public API)

### `EventType` (`lib/features/events/models/event_form_data.dart`)

```dart
enum EventType { rehearsal, gig, blockOut }
// blockOut.displayName == 'Block Out'
```

### `EventEditorDrawer` (`lib/features/events/widgets/event_editor_drawer.dart`)

```dart
// New optional parameter added:
final BlockOutSpan? existingBlockOut;
```

All other existing parameters remain unchanged.

### `AddEditEventBottomSheet.show()` (`lib/features/events/widgets/add_edit_event_bottom_sheet.dart`)

```dart
// New optional parameter added and passed through to EventEditorDrawer:
BlockOutSpan? existingBlockOut
```

All other existing parameters remain unchanged.

### `QuickActionsRow` (`lib/features/home/widgets/quick_actions_row.dart`)

```dart
// Removed parameters:
//   onScheduleRehearsal (VoidCallback?)
//   onCreateGig (VoidCallback?)
//   onBlockOut (VoidCallback?)
//   showScheduleRehearsal (bool)
//   showCreateGig (bool)
//   showBlockOut (bool)

// Added parameters:
final VoidCallback? onAddEvent;
final bool showAddEvent;

// Unchanged parameters:
//   onCreateSetlist (VoidCallback?)
//   showCreateSetlist (bool)
```

### `EmptyHomeState` (`lib/features/home/widgets/empty_home_state.dart`)

```dart
// Removed parameters:
//   onScheduleRehearsal (VoidCallback?)
//   onCreateGig (VoidCallback?)
//   onBlockOut (VoidCallback?)

// Added parameter:
final VoidCallback? onAddEvent;

// Unchanged parameters:
//   onCreateSetlist (VoidCallback?)
```

---

## 16. Data Flow Architecture

### Create Flow — New Unified Path

```
User taps "+ Add Event"
  → _handleAddEvent() [home_screen / home_tab_content / calendar screens]
  → AddEditEventBottomSheet.show(initialType: EventType.rehearsal | gig)
  → EventEditorDrawer renders three-way toggle (filtered by RBAC)
  → User selects Block Out tab
  → _buildBlockOutForm() renders Start Date, End Date (opt), Reason (opt)
  → User taps Save
  → _handleSave() detects _eventType == EventType.blockOut
  → _saveBlockOut()
  → BlockOutRepository.createBlockOut()
  → block_dates table (schema unchanged)
```

### Edit Flow — Block Out

```
User taps existing block out on calendar
  → _openEditEventSheet() detects event.isBlockOut == true
  → AddEditEventBottomSheet.show(
        initialType: EventType.blockOut,
        mode: EventFormMode.edit,
        existingBlockOut: blockOutSpan
    )
  → EventEditorDrawer.initState() populates:
        _selectedDate = existingBlockOut.startDate
        _untilDate    = existingBlockOut.endDate
        _reasonController.text = existingBlockOut.reason ?? ''
  → If current user is creator:
        save and delete buttons enabled
  → If current user is NOT creator:
        viewOnly: true — form fields disabled, save/delete hidden
```

### RBAC Gate — Toggle Visibility

```
Admin / Member
  → toggle shows: [Rehearsal] [Gig] [Block Out]

Contributor (canCreateGigs == true)
  → toggle shows: [Gig] only
  → Rehearsal and Block Out filtered out in _buildEventTypeToggle()

Contributor (canCreateGigs == false)
  → Add Event button hidden entirely — no drawer opened
```

### Default Type Selection in `_handleAddEvent()`

```
If user is admin or member:
  → initialType = EventType.rehearsal

If user is contributor with canCreateGigs:
  → initialType = EventType.gig

If user has no event creation permissions:
  → _handleAddEvent() is never called (button is hidden)
```

---

## 17. Exact Code Locations

### EventType Enum — Add `blockOut`

```
lib/features/events/models/event_form_data.dart
  enum EventType { rehearsal, gig }
  ↳ Add: blockOut
  ↳ Add displayName case: blockOut → 'Block Out'
```

### RBAC Toggle Filter — Extend for `blockOut`

```
lib/features/events/widgets/event_editor_drawer.dart
  _buildEventTypeToggle()
  ↳ Locate the filter that removes EventType.rehearsal for contributors
  ↳ Extend the same filter to also remove EventType.blockOut for contributors
```

### Block Out Form Rendering

```
lib/features/events/widgets/event_editor_drawer.dart
  Scrollable form content area (where rehearsal/gig fields are rendered)
  ↳ Add: if (_eventType == EventType.blockOut) return _buildBlockOutForm()
```

### Save Dispatch

```
lib/features/events/widgets/event_editor_drawer.dart
  _handleSave()
  ↳ Add at top of handler:
      if (_eventType == EventType.blockOut) { _saveBlockOut(); return; }
```

### Block Out Edit Detection — Calendar

```
lib/features/calendar/calendar_tab_content.dart
lib/features/calendar/calendar_screen.dart
  _openEditEventSheet()
  ↳ Add: if (event.isBlockOut) {
        AddEditEventBottomSheet.show(
          ...,
          initialType: EventType.blockOut,
          mode: EventFormMode.edit,
          existingBlockOut: blockOutSpan,
        );
        return;
    }
```

### Tips & Tricks String

```
lib/components/overlays/tips_and_tricks_overlay.dart
  ↳ Search:  'Tap + Schedule Rehearsal or + Create Gig'
  ↳ Replace: 'Tap + Add Event'
```

### `_reasonController` Disposal

```
lib/features/events/widgets/event_editor_drawer.dart
  dispose()
  ↳ Add: _reasonController.dispose();
```
