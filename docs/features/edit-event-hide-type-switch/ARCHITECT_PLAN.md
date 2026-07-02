# ARCHITECT PLAN — Edit Event Hide Type Switch

## Feature Slug

`bug/edit-event-hide-type-switch`

---

## Problem Summary

The event create/edit UI includes a segmented switch to choose the event type: Rehearsal, Gig, or Block out. This switch currently displays in both create and edit modes. When a user opens an existing event to edit it, the type switch is still visible (though disabled with a hint message) even though the event's type is already fixed and cannot be changed. The switch should only appear when creating a new event. Once an event exists and is being edited, its type should not be changeable and the switch should not render at all.

---

## Root Cause

**Confidence: HIGH**

The `EventTypeSelector` widget is unconditionally rendered at line 2129 of `lib/features/events/widgets/event_editor_drawer.dart`, regardless of whether the form is in create or edit mode:

```dart
// Event Type Toggle
EventTypeSelector(
  selectedType: _eventType,
  availableTypes: _computeAvailableTypes(),
  isEditMode: _isEditMode,
  isSaving: _isSaving,
  onTypeChanged: _handleTypeChanged,
),
```

The widget receives `isEditMode: _isEditMode` and correctly disables the switch when in edit mode (line 28 of `event_type_selector.dart`: `final isDisabled = isEditMode || isSaving;`), but the widget itself still renders. The user requirement is that the switch should not be visible at all in edit mode.

The widget is also displayed with a hint text ("Event type cannot be changed after creation.") when in edit mode (lines 105-112 of `event_type_selector.dart`), but this disabled state is not the desired behavior — the entire widget should be hidden.

---

## Reference Docs Consulted

None available. No event/gig/rehearsal-specific reference documentation exists in `docs/reference/`.

---

## Existing System Analysis

**Current Behavior:**

1. User opens an existing event (gig, rehearsal, or block-out) for editing
2. All entry points correctly set `mode: EventFormMode.edit` when calling `AddEditEventBottomSheet.show()`
3. `AddEditEventBottomSheet` maps this to `EventEditorMode.edit` and passes it to `EventEditorDrawer`
4. `EventEditorDrawer` computes `_isEditMode` getter (line 939): `bool get _isEditMode => widget.mode == EventEditorMode.edit;`
5. `EventTypeSelector` receives `isEditMode: true`
6. Widget renders the switch in a disabled state with reduced opacity and shows a hint: "Event type cannot be changed after creation."
7. The switch is still visible on screen

**Data Flow Verification:**

- All edit entry points correctly pass `mode: EventFormMode.edit`:
  - `home_screen.dart` (lines 227, 282)
  - `home_tab_content.dart` (lines 414, 472)
  - `calendar_screen.dart` (lines 257, 276)
  - `calendar_tab_content.dart` (lines 236, 255)
- The mode parameter is reliable and correctly distinguishes create vs. edit across all three event types

**Form Layout and Logic:**

- The event type value (`_eventType`) is initialized from `widget.initialEventType` in create mode and from `widget.existingEvent.type` in edit mode
- Hiding the switch does not affect form layout — the widget is followed by consistent spacing (`const SizedBox(height: Spacing.space20)` at line 2137)
- No validation logic reads the switch UI state — validation operates on the `_eventType` field, which is already set correctly in edit mode
- The `onTypeChanged` callback is disabled when `isEditMode` is true, so hiding the widget does not remove any functional behavior

---

## Proposed Solution

Conditionally render the `EventTypeSelector` widget only in create mode. Wrap the widget and its trailing spacer in an `if (!_isEditMode)` block.

**Minimal Change:**
In `lib/features/events/widgets/event_editor_drawer.dart`, replace lines 2128-2137:

```dart
// Event Type Toggle
EventTypeSelector(
  selectedType: _eventType,
  availableTypes: _computeAvailableTypes(),
  isEditMode: _isEditMode,
  isSaving: _isSaving,
  onTypeChanged: _handleTypeChanged,
),

const SizedBox(height: Spacing.space20),
```

With:

```dart
// Event Type Toggle (create mode only)
if (!_isEditMode) ...[
  EventTypeSelector(
    selectedType: _eventType,
    availableTypes: _computeAvailableTypes(),
    isEditMode: _isEditMode,
    isSaving: _isSaving,
    onTypeChanged: _handleTypeChanged,
  ),
  const SizedBox(height: Spacing.space20),
],
```

This change:

- Hides the switch entirely in edit mode
- Preserves all existing behavior in create mode
- Does not affect form validation, save logic, or event type handling
- Maintains consistent spacing by including the trailing `SizedBox` in the conditional

---

## Database Impact

Not applicable. This is a UI-only change with no impact on:

- Database schema
- RLS policies
- RPC functions
- Triggers
- Migrations

---

## Flutter Architecture Changes

**State:**

- No state changes
- `_eventType` field continues to hold the correct value in both create and edit modes
- No new state variables introduced

**Widgets:**

- `EventEditorDrawer` — conditionally render `EventTypeSelector`
- No changes to `EventTypeSelector` widget itself

**Repositories:**

- No changes

---

## Files to Create

None.

---

## Files to Modify

| File                                                   | What changes                                                                                              |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | Wrap `EventTypeSelector` and trailing `SizedBox` in `if (!_isEditMode) ...[...]` block at lines 2128-2137 |

---

## Files Off-Limits

| File                                                           | Reason                                              |
| -------------------------------------------------------------- | --------------------------------------------------- |
| `lib/features/events/widgets/event_type_selector.dart`         | Widget behavior is correct; fix is at the call site |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Mode parameter mapping is correct                   |
| `lib/features/home/home_screen.dart`                           | Edit entry points correctly set mode                |
| `lib/features/home/home_tab_content.dart`                      | Edit entry points correctly set mode                |
| `lib/features/calendar/calendar_screen.dart`                   | Edit entry points correctly set mode                |
| `lib/features/calendar/calendar_tab_content.dart`              | Edit entry points correctly set mode                |
| `lib/features/events/models/event_form_data.dart`              | No changes to data model                            |
| `lib/main.dart`                                                | Init order must not change                          |

---

## System Impact Map

| System                                 | Impact                                                    |
| -------------------------------------- | --------------------------------------------------------- |
| Gigs                                   | unaffected                                                |
| Rehearsals                             | unaffected                                                |
| Setlists / Catalog                     | unaffected                                                |
| Members / RBAC                         | unaffected                                                |
| Auth / Session                         | unaffected                                                |
| Routing                                | unaffected                                                |
| Notifications                          | unaffected                                                |
| Platform (iOS / Android / Web / macOS) | unaffected (all platforms share the same Flutter UI code) |

---

## Regression Risk

**LOW**

**Rationale:**

- Single conditional change wrapping one widget
- No logic modifications to event type handling, validation, or save flow
- Event type is already immutable in edit mode (enforced by disabled state)
- Change only affects widget visibility, not behavior
- No impact on data flow or state management
- All three event types (gig, rehearsal, block-out) share the same render path

**Risk Factors:**

- The change is localized to a single location in the `build` method
- No changes to controller, repository, or model layers
- No changes to callback handlers or form submission logic
- The conditional check (`!_isEditMode`) is simple and unambiguous

---

## Engineer Task Breakdown

1. **Read and understand the ARCHITECT_PLAN.md** — Confirm all context and constraints
2. **Open `lib/features/events/widgets/event_editor_drawer.dart`** — Navigate to lines 2128-2137
3. **Locate the `EventTypeSelector` widget** — Confirm the exact lines to modify
4. **Wrap the widget in conditional render** — Replace lines 2128-2137 with the if-block specified in Proposed Solution
5. **Verify syntax** — Ensure correct Dart collection spread syntax (`if (!_isEditMode) ...[...]`)
6. **Run `flutter analyze`** — Confirm 0 errors, 0 warnings
7. **Test in create mode** — Open event creation for gig, rehearsal, and block-out; verify switch renders
8. **Test in edit mode** — Open event editing for gig, rehearsal, and block-out; verify switch is hidden
9. **Test form submission** — Save edits to existing events; confirm event type is preserved
10. **Write ENGINEER_REPORT.md** — Document completion of all tasks

---

## Verification Plan

### Tier 1 — Pre-deployment

Not applicable. No database changes.

### Tier 2 — Post-implementation (Manual UI Testing)

**Test 1: Create mode — gig**

1. Open BandRoadie on any platform (web, iOS, Android, macOS)
2. Navigate to Add Event (from dashboard, calendar, or home)
3. Verify the Rehearsal / Gig / Block out segmented switch is visible at the top of the form
4. Tap between the three options and verify the switch animates correctly
5. Cancel without saving

**Test 2: Create mode — rehearsal**

1. From a create flow, select Rehearsal type
2. Verify the switch is visible and the Rehearsal segment is highlighted
3. Cancel without saving

**Test 3: Create mode — block-out**

1. From a create flow, select Block out type
2. Verify the switch is visible and the Block out segment is highlighted
3. Cancel without saving

**Test 4: Edit mode — gig**

1. Open an existing gig (from dashboard card, calendar, or home tab)
2. Tap Edit
3. **VERIFY:** The Rehearsal / Gig / Block out segmented switch is NOT rendered at all
4. Verify the form displays correctly without the switch (date, time, venue, city fields visible)
5. Make a change (e.g., update venue name)
6. Save
7. Verify the gig is updated and remains a gig (type did not change)

**Test 5: Edit mode — rehearsal**

1. Open an existing rehearsal
2. Tap Edit
3. **VERIFY:** The Rehearsal / Gig / Block out segmented switch is NOT rendered at all
4. Verify the form displays correctly without the switch (date, time, location fields visible)
5. Make a change (e.g., update location)
6. Save
7. Verify the rehearsal is updated and remains a rehearsal (type did not change)

**Test 6: Edit mode — block-out**

1. Open an existing block-out
2. Tap Edit (if applicable) or view details
3. **VERIFY:** The Rehearsal / Gig / Block out segmented switch is NOT rendered at all
4. Verify the form displays correctly without the switch (start date, end date, reason fields visible)
5. If editable, make a change and save
6. Verify the block-out is updated and remains a block-out (type did not change)

**Test 7: Regression — form spacing**

1. In edit mode, verify there is no visual gap or layout shift where the switch was previously rendered
2. Verify the first visible field (gig name for gigs, date for rehearsals/block-outs) appears at the expected vertical position

**Test 8: Regression — form submission**

1. Edit an existing gig and save without changing any fields
2. Verify the save succeeds and the event type remains gig
3. Repeat for rehearsal and block-out

---

## QA Regression Areas

QA must specifically test:

1. **Event creation flows** — All three event types (gig, rehearsal, block-out) in create mode; verify switch is visible and functional
2. **Event editing flows** — All three event types in edit mode; verify switch is hidden
3. **Event type immutability** — Edit and save events; confirm type does not change
4. **Form layout** — Verify no visual gaps or layout shifts in edit mode where the switch was removed
5. **All entry points** — Test opening edit mode from:
   - Dashboard potential gig cards
   - Dashboard rehearsal cards
   - Home tab gig cards
   - Home tab rehearsal cards
   - Calendar screen day popover
   - Calendar tab day popover
6. **All platforms** — Web, iOS, Android, macOS (shared Flutter UI, but verify on at least two platforms)

---

## Rollout / Migration Strategy

Not applicable. No database migration or gradual rollout required. Deploy as a single atomic change after QA approval.

---

## Out of Scope

- Refactoring `EventTypeSelector` widget (not needed; fix is at the call site)
- Changing event type edit behavior (type is already immutable)
- Modifying entry points or mode parameter logic (already correct)
- UI polish or redesign of the event form (not requested)
- Changes to event creation or deletion flows (not affected)
