# ARCHITECT_PLAN.md — Revision 2

**Revision History:**

- **v1** (QA-approved, rejected in device testing): Added Done + Edit footer to BlockOutDrawer viewOnly mode. Body showed disabled form fields.
- **v2** (this revision): Replace form-field body with proper view-drawer template matching gig/rehearsal pattern. Create dedicated ViewBlockOutDrawer widget.

**What changed from v1:**
Device testing revealed that the viewOnly mode body still renders the edit form with disabled inputs, contradicting the Edit button below. Users expect a proper read-only details view (like gig/rehearsal drawers), not disabled form fields. This revision creates a dedicated view drawer with detail-row presentation, matching the established pattern exactly.

---

## Feature Slug

`bug/blockout-creator-view-first`

## Problem Summary

Tapping a block-out event from the calendar opens `BlockOutDrawer` in edit mode when the viewer is the creator, violating the view-first interaction pattern established by `ViewGigDrawer` and `ViewRehearsalDrawer`. Users expect to see a read-only details view first, with an Edit affordance that transitions to edit mode when they are the creator.

Device testing of v1 implementation confirmed that while the footer was correct (Done + Edit buttons), the drawer body showed disabled form fields instead of a proper read-only details layout, creating confusion even for creators.

## Root Cause

**Confidence: HIGH**

Both call sites (`calendar_tab_content.dart:212`, `calendar_screen.dart:232`) and `BlockOutDrawer` itself conflate view and edit modes. The drawer uses disabled form fields in viewOnly mode instead of a dedicated read-only presentation. This violates the established pattern where view drawers present data in detail rows, not form fields.

**Reference pattern confirmed:**

- `ViewGigDrawer` (lib/features/gigs/widgets/view_gig_drawer.dart:241-442): Large header (name/location), date/time block, detail rows for optional fields, Done + Edit footer
- `ViewRehearsalDrawer` (lib/features/rehearsals/widgets/view_rehearsal_drawer.dart:136-302): Large header (date/time/location), detail rows for setlist/notes, Done + Edit footer

Neither uses form fields — both use detail-row presentation for read-only data.

## Reference Docs Consulted

Not applicable (no notifications domain involved).

## Existing System Analysis

### Current Block-Out Drawer (v1 implementation - uncommitted working tree)

**File**: `lib/features/calendar/widgets/add_block_out_drawer.dart`

- Line 49: `enum BlockOutDrawerMode { create, edit, viewOnly }`
- Lines 124-138: Title varies by mode
- Lines 646-682: Banner "Only the creator can edit or delete this block out" (shown only when `_isReadOnly`)
- Lines 704-730: **Form fields rendered for all modes** (disabled in viewOnly via lines 830, 857, 889)
  - Start Date field (line 704)
  - End Date field (line 714)
  - Reason text field (line 725)
- Lines 935-976: viewOnly footer (v1 implementation) — Done + Edit buttons (correct pattern, will be moved to ViewBlockOutDrawer)

**The problem**: Lines 704-730 render form fields even in viewOnly mode. The fields are disabled, but the layout is still a form, not a details view.

### View Drawer Pattern (confirmed)

**File**: `lib/features/gigs/widgets/view_gig_drawer.dart`

- Lines 279-329: Header block — name (headlineMedium), location (callout), Navigate button
- Lines 334-356: Date/Time block — full date (title3), time range (headline)
- Line 359: Divider
- Lines 362-399: Detail rows — load in, setlist, gig pay, notes (label/value pairs, some tappable)
- Lines 407-438: Footer — Done + Edit buttons (matching v1 block-out footer)
- Line 208: `_handleEdit` pops drawer, calls `onEdit()` callback

**File**: `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`

- Lines 182-228: Header block — full date (headlineMedium), time range (title3), location (callout), recurrence indicator
- Line 232: Divider
- Lines 235-259: Detail rows — setlist, notes
- Lines 267-298: Footer — Done + Edit buttons
- Line 48: `_handleEdit` pops drawer, calls `onEdit()` callback

**Shared structure:**

1. Large header block (date/name in prominent text)
2. Secondary info (time/location)
3. Divider
4. Detail rows for optional fields (label/value pairs)
5. Footer (Done + Edit if creator)

**File**: `lib/features/gigs/widgets/view_gig_drawer.dart:451-511` and `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart:305-365`

- `_DetailRow` widget: Label (68px fixed width), value (expanded), optional chevron
- Wraps in InkWell if tappable
- Divider below each row

### Block-Out Data Model

**File**: `lib/features/calendar/models/calendar_event.dart:24-44`

- `BlockOutSpan` fields: `startDate`, `endDate`, `reason`, `userId`, `userName`, `isMultiDay` (computed)
- No optional fields like load-in time or setlist — just date range and reason

### Call Sites (v1 changes - uncommitted)

**File**: `lib/features/calendar/calendar_tab_content.dart`

- Line 212: `mode: BlockOutDrawerMode.viewOnly,` (v1 change — always viewOnly)
- Line 214: `canEdit: canEdit,` (v1 change — passes permission)

**File**: `lib/features/calendar/calendar_screen.dart`

- Line 232: `mode: BlockOutDrawerMode.viewOnly,` (v1 change — always viewOnly)
- Line 234: `canEdit: canEdit,` (v1 change — passes permission)

## Proposed Solution

### Architecture Decision: Create Dedicated ViewBlockOutDrawer

Create `lib/features/calendar/widgets/view_block_out_drawer.dart` mirroring the `ViewRehearsalDrawer` pattern. This provides clean separation between view and edit modes, matching the established UX pattern exactly.

**Justification:**

1. **Pattern consistency**: Gigs and rehearsals use dedicated view drawers. Block-outs must follow this pattern.
2. **UI anti-pattern fix**: Disabled form fields are a poor UX pattern. View drawers use proper read-only presentation with detail rows.
3. **Clean separation**: View and edit are separate concerns. Mixing them in one widget with mode switching adds complexity.
4. **Dead code elimination**: `BlockOutDrawerMode.viewOnly` becomes unnecessary and will be removed entirely from `BlockOutDrawer`.

### View Drawer Layout

**Header block** (matching rehearsal pattern):

- If single day: Full date (headlineMedium), "Single day" or omit subtitle
- If multi-day: Start date (headlineMedium), "Through [end date]" (title3)

**Detail rows:**

- If reason is not empty: Detail row with label "Reason", value shows reason text

**Footer:**

- Done button (BrandActionButton, full width, dismisses drawer)
- If creator (`canEdit == true`): Edit button (TextButton, centered, primary color, 12px spacing above)
- If non-creator (`canEdit == false`): Done only

**Non-creator messaging:**
No banner needed. The absence of the Edit button is sufficient UX. ViewGigDrawer and ViewRehearsalDrawer show no banner for non-editors — they simply omit the Edit button. Match this pattern.

### Changes to BlockOutDrawer

Remove all viewOnly mode artifacts:

- Remove `BlockOutDrawerMode.viewOnly` from enum (line 49)
- Remove viewOnly branch from `_buildBottomButtons` (lines 935-976)
- Remove banner (lines 646-682)
- Remove `canEdit` parameter (no longer needed)
- Remove disabled field logic checks (lines 830, 857, 889)

BlockOutDrawer becomes edit-only (create or edit existing). No view mode.

### Changes to Call Sites

Replace calls to `BlockOutDrawer.show(mode: BlockOutDrawerMode.viewOnly)` with calls to `ViewBlockOutDrawer.show()`.

Both call sites (`calendar_tab_content.dart:209-217`, `calendar_screen.dart:228-236`) will:

1. Open `ViewBlockOutDrawer.show()` with `canEdit` and `onEdit` callback
2. `onEdit` callback: open `BlockOutDrawer.show()` in edit mode

This matches the gig/rehearsal pattern exactly.

## Database Impact

Not applicable.

## Flutter Architecture Changes

### State

No new state. `ViewBlockOutDrawer` is stateless (like `ViewGigDrawer` / `ViewRehearsalDrawer`). BlockOutDrawer state unchanged (edit mode only).

### Widgets

**Created**: `ViewBlockOutDrawer` (`lib/features/calendar/widgets/view_block_out_drawer.dart`)

- Stateless widget
- Parameters: `existingBlockOut` (BlockOutSpan), `canEdit` (bool), `onEdit` (VoidCallback)
- Structure: Container → Column → [drag handle, Flexible(SingleChildScrollView(header, divider, detail rows)), footer]

**Modified**: `BlockOutDrawer` (`lib/features/calendar/widgets/add_block_out_drawer.dart`)

- Remove `BlockOutDrawerMode.viewOnly` from enum
- Remove `canEdit` parameter
- Remove viewOnly footer branch
- Remove banner
- Remove disabled field logic

### Repositories

None.

## Files to Create

| File                                                       | Justification                                                                                                                                                                                                   |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/calendar/widgets/view_block_out_drawer.dart` | Dedicated view drawer for block-outs, matching the pattern established by `ViewGigDrawer` and `ViewRehearsalDrawer`. Required to provide proper read-only details presentation instead of disabled form fields. |

## Files to Modify

| File                                                      | Changes                                                                                                                                                                                                                                                                                                                                                                                                                              |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/calendar/calendar_tab_content.dart`         | Replace `BlockOutDrawer.show()` call at line 209 with `ViewBlockOutDrawer.show()`. Pass `existingBlockOut`, `canEdit`, and `onEdit` callback. The `onEdit` callback will open `BlockOutDrawer` in edit mode.                                                                                                                                                                                                                         |
| `lib/features/calendar/calendar_screen.dart`              | Replace `BlockOutDrawer.show()` call at line 228 with `ViewBlockOutDrawer.show()`. Pass `existingBlockOut`, `canEdit`, and `onEdit` callback. The `onEdit` callback will open `BlockOutDrawer` in edit mode.                                                                                                                                                                                                                         |
| `lib/features/calendar/widgets/add_block_out_drawer.dart` | Remove `BlockOutDrawerMode.viewOnly` from enum (line 49). Remove `canEdit` parameter (lines 65, 76, 88). Remove viewOnly footer branch from `_buildBottomButtons` (lines 935-976). Remove banner (lines 646-682). Remove disabled field logic in `_buildDateField` (lines 830, 836-837, 850-852, 857-862) and `_buildTextField` (lines 889, 892-894, 902-904). Update `_drawerTitle` getter to remove viewOnly case (lines 130-138). |

## Files Off-Limits

| File                                                           | Reason                                                   |
| -------------------------------------------------------------- | -------------------------------------------------------- |
| `lib/main.dart`                                                | Init order must not change                               |
| `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`   | Event tap flow is correct; no changes needed             |
| `lib/features/calendar/calendar_controller.dart`               | No state changes required                                |
| `lib/features/calendar/block_out_repository.dart`              | No data layer changes required                           |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Out of scope; create mode for add/edit events unaffected |
| `lib/features/gigs/widgets/view_gig_drawer.dart`               | Reference pattern only; do not modify                    |
| `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`   | Reference pattern only; do not modify                    |

## System Impact Map

| System                                 | Impact                                                                    |
| -------------------------------------- | ------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                |
| Rehearsals                             | unaffected                                                                |
| Setlists / Catalog                     | unaffected                                                                |
| Members / RBAC                         | unaffected (reuses existing `EventPermissionHelper.canEditEvent()` logic) |
| Auth / Session                         | unaffected                                                                |
| Routing                                | unaffected                                                                |
| Notifications                          | unaffected                                                                |
| Platform (iOS / Android / Web / macOS) | unaffected                                                                |

## Regression Risk

**LOW**

Rationale:

- Changes are localized to block-out view flow only
- No changes to block-out creation, deletion, or data persistence
- Gig and rehearsal view/edit flows unchanged
- RBAC permission checks unchanged (reuses existing `EventPermissionHelper`)
- Pattern matches established view-first UX exactly
- No database, RLS, or RPC changes
- BlockOutDrawer edit mode unchanged (only viewOnly mode removed)

## Engineer Task Breakdown

### Starting Point: Uncommitted Working Tree

The working tree contains v1 implementation (QA-approved, rejected in device testing):

- `calendar_tab_content.dart`: Line 212 passes `viewOnly`, line 214 passes `canEdit`
- `calendar_screen.dart`: Line 232 passes `viewOnly`, line 234 passes `canEdit`
- `add_block_out_drawer.dart`: Has viewOnly mode with correct footer (lines 935-976) but disabled form fields body

**Do not stash, revert, or commit these changes.** Work from this baseline.

---

### Task 1: Create ViewBlockOutDrawer widget

Create `lib/features/calendar/widgets/view_block_out_drawer.dart` as a StatelessWidget mirroring the `ViewRehearsalDrawer` structure.

**Structure:**

- Import required dependencies (Flutter, models, theme, components)
- Parameters: `existingBlockOut` (BlockOutSpan), `canEdit` (bool), `onEdit` (VoidCallback)
- Static `show()` method for modal bottom sheet
- `_handleEdit` method: pops drawer, calls `onEdit()`
- `_formatFullDate` helper (or reuse from ViewRehearsalDrawer pattern)
- `build()` method:
  - Container with max height constraint (0.9 of screen height)
  - Column: [drag handle, Flexible(SingleChildScrollView(body)), footer]
  - Body: Header block, divider, detail rows
  - Footer: Done + Edit (if canEdit)
  - **NO title bar** — drag handle goes directly to header content (matches ViewGigDrawer/ViewRehearsalDrawer pattern)

**Header block:**

- If single day (`!existingBlockOut.isMultiDay`):
  - Full date (headlineMedium style): e.g., "Saturday, July 3, 2026"
- If multi-day:
  - Start date (headlineMedium): e.g., "Saturday, July 3, 2026"
  - SizedBox(height: 4)
  - Subtitle (title3 or callout): "Through [end date]" (e.g., "Through Sunday, July 5, 2026")

**Detail rows:**

- Use the same `_DetailRow` widget pattern from ViewGigDrawer/ViewRehearsalDrawer (label width 68px, value expanded, divider below)
- If reason is not empty: `_DetailRow(label: 'Reason', value: existingBlockOut.reason)`
- If reason is empty: omit the row entirely (block-outs often have no reason)

**Footer:**

- Padding with safe area bottom
- Column:
  - BrandActionButton(label: 'Done', fullWidth: true, onPressed: pop)
  - If canEdit: SizedBox(height: 12) + SizedBox(width: double.infinity) wrapping TextButton('Edit', onPressed: \_handleEdit, calloutEmphasized + primary color)

**Do NOT add:**

- No title bar (drag handle → header content directly)
- No banner for non-creators (absence of Edit button is sufficient)
- No loading state (this is view mode only)
- No error state
- No form fields

**Verification:**

- File compiles
- Matches ViewRehearsalDrawer structure (lines 136-302) closely
- `_handleEdit` pops then calls `onEdit()`
- Footer matches v1 block-out footer (lines 945-974)

---

### Task 2: Update call site in calendar_tab_content.dart

Modify `_openEditEventSheet` method (lines 195-217) block-out branch.

**Current state (v1, uncommitted):**

```dart
await BlockOutDrawer.show(
  context,
  ref: ref,
  bandId: activeBandId,
  mode: BlockOutDrawerMode.viewOnly,  // line 212
  existingBlockOut: event.blockOutSpan,
  canEdit: canEdit,                    // line 214
  onSaved: _refreshCalendarData,
);
```

**New state:**

```dart
await ViewBlockOutDrawer.show(
  context,
  existingBlockOut: event.blockOutSpan,
  canEdit: canEdit,
  onEdit: () {
    BlockOutDrawer.show(
      context,
      ref: ref,
      bandId: activeBandId,
      mode: BlockOutDrawerMode.edit,
      existingBlockOut: event.blockOutSpan,
      onSaved: _refreshCalendarData,
    );
  },
);
```

**Changes:**

- Replace `BlockOutDrawer.show()` with `ViewBlockOutDrawer.show()`
- Remove `ref`, `bandId`, `mode`, `onSaved` from view drawer call
- Pass `existingBlockOut`, `canEdit`, `onEdit` callback
- `onEdit` callback opens `BlockOutDrawer` in edit mode with original parameters
- Add import for ViewBlockOutDrawer at top of file

**Verification:**

- Call site compiles
- `onEdit` callback captures `ref`, `activeBandId`, `_refreshCalendarData` from closure
- ViewBlockOutDrawer opens first (view mode)
- Tapping Edit in ViewBlockOutDrawer opens BlockOutDrawer in edit mode

---

### Task 3: Update call site in calendar_screen.dart

Modify `_openEditEventSheet` method (lines 215-236) block-out branch.

**Current state (v1, uncommitted):**

```dart
await BlockOutDrawer.show(
  context,
  ref: ref,
  bandId: activeBandId,
  mode: BlockOutDrawerMode.viewOnly,  // line 232
  existingBlockOut: event.blockOutSpan,
  canEdit: canEdit,                    // line 234
  onSaved: _refreshCalendarData,
);
```

**New state:** Same replacement as Task 2.

**Changes:**

- Replace `BlockOutDrawer.show()` with `ViewBlockOutDrawer.show()`
- Remove `ref`, `bandId`, `mode`, `onSaved` from view drawer call
- Pass `existingBlockOut`, `canEdit`, `onEdit` callback
- `onEdit` callback opens `BlockOutDrawer` in edit mode with original parameters
- Add import for ViewBlockOutDrawer at top of file

**Verification:**

- Call site compiles
- `onEdit` callback captures `ref`, `activeBandId`, `_refreshCalendarData` from closure
- ViewBlockOutDrawer opens first (view mode)
- Tapping Edit in ViewBlockOutDrawer opens BlockOutDrawer in edit mode

---

### Task 4: Remove viewOnly mode from BlockOutDrawer

**File**: `lib/features/calendar/widgets/add_block_out_drawer.dart`

**Changes (in order):**

1. **Line 49**: Remove `viewOnly` from enum:

   ```dart
   enum BlockOutDrawerMode { create, edit }  // removed viewOnly
   ```

2. **Lines 65, 76, 88**: Remove `canEdit` parameter from class and static method (no longer needed — only ViewBlockOutDrawer uses it)

3. **Lines 130-138**: Update `_drawerTitle` getter — remove viewOnly case:

   ```dart
   String get _drawerTitle {
     return _isEditMode ? 'Edit Block Out' : 'Add Block Out';
   }
   ```

4. **Line 124**: Remove `_isReadOnly` getter (no longer used)

5. **Lines 646-682**: Remove entire banner block (viewOnly-only, not needed in edit mode)

6. **Lines 830, 836-837, 850-852, 857-862**: Remove disabled field logic from `_buildDateField`:
   - Line 830: Remove `|| _isReadOnly` from onTap null check
   - Lines 836-837, 850-852: Remove `_isReadOnly` ternary for fillColor and textColor
   - Lines 857-862: Remove `if (!_isReadOnly)` guard around calendar icon

7. **Lines 889, 892-894, 902-904**: Remove disabled field logic from `_buildTextField`:
   - Line 889: Remove `&& !_isReadOnly` from enabled check
   - Lines 892-894: Remove `_isReadOnly` ternary for textColor
   - Lines 902-904: Remove `_isReadOnly` ternary for fillColor

8. **Lines 935-976**: Remove entire viewOnly branch from `_buildBottomButtons`:
   - Delete lines 935-976 (entire `if (_isReadOnly)` block)
   - Method now only has edit mode and create mode branches

9. **Lines 164-175**: Remove `_handleEdit` method (no longer used — ViewBlockOutDrawer has its own)

10. **Line 101**: Remove `canEdit` forwarding to constructor in `show()` method

**Post-removal verification:**

- No references to `_isReadOnly` remain
- No references to `canEdit` remain
- No references to `BlockOutDrawerMode.viewOnly` remain
- `_buildBottomButtons` has only two branches: edit and create
- File compiles

---

### Task 5: Verify complete v1 artifact removal

**Check that no v1-specific code remains in BlockOutDrawer:**

- `BlockOutDrawerMode.viewOnly`: removed
- `canEdit` parameter: removed
- `_isReadOnly` getter: removed
- `_handleEdit` method: removed
- viewOnly banner (lines 646-682): removed
- viewOnly footer (lines 935-976): removed
- Disabled field logic: removed

**Check that v1 footer pattern moved to ViewBlockOutDrawer:**

- ViewBlockOutDrawer has Done + Edit footer
- Structure matches v1 lines 945-974 (BrandActionButton + TextButton with spacing)

**Verify call sites:**

- Both call sites open ViewBlockOutDrawer first
- Both pass canEdit to ViewBlockOutDrawer (not BlockOutDrawer)
- Both have onEdit callback that opens BlockOutDrawer in edit mode

---

## Verification Plan

### Tier 1 — Pre-deployment (Flutter Code Verification)

No database changes; no pre-deploy SQL tests required.

**CODE STRUCTURE VERIFICATION:**

**TEST 1: ViewBlockOutDrawer structure matches reference pattern**

1. Read `lib/features/calendar/widgets/view_block_out_drawer.dart`
2. Verify structure matches ViewRehearsalDrawer:
   - Stateless widget
   - Parameters: existingBlockOut, canEdit, onEdit
   - Static show() method
   - \_handleEdit method pops and calls onEdit()
   - Body: header block, divider, detail rows
   - Footer: Done + Edit (if canEdit)
3. Verify no form fields in body (only detail rows)
4. Verify no banner for non-creators

**TEST 2: BlockOutDrawer has no viewOnly artifacts**

1. Read `lib/features/calendar/widgets/add_block_out_drawer.dart`
2. Verify BlockOutDrawerMode enum has only `create` and `edit` (no `viewOnly`)
3. Verify no `canEdit` parameter
4. Verify no `_isReadOnly` getter
5. Verify no `_handleEdit` method
6. Verify no banner (lines 646-682 removed)
7. Verify no viewOnly footer (lines 935-976 removed)
8. Verify no disabled field logic in `_buildDateField` or `_buildTextField`

**TEST 3: Call sites use ViewBlockOutDrawer**

1. Read `lib/features/calendar/calendar_tab_content.dart` line 209
2. Verify calls `ViewBlockOutDrawer.show()` (not `BlockOutDrawer.show()`)
3. Verify passes `existingBlockOut`, `canEdit`, `onEdit` callback
4. Verify `onEdit` callback opens `BlockOutDrawer` in edit mode
5. Repeat for `lib/features/calendar/calendar_screen.dart` line 228

**TEST 4: Run flutter analyze**

```bash
flutter analyze lib/features/calendar/
```

Verify 0 errors in calendar feature (pre-existing deprecation warnings in setlists are expected and unrelated).

### Tier 2 — Post-deployment (Manual UI Testing)

**TEST 1: "This Month's Events" tap — creator view-first**

1. As creator, tap a block-out event from "This Month's Events" list
2. Verify `ViewBlockOutDrawer` opens (not `BlockOutDrawer`)
3. Verify NO title bar (drag handle goes directly to date header)
4. Verify header shows date (single day) or date range (multi-day) in large text — NOT form fields
5. Verify detail row shows reason (if present) — NOT a disabled text field
6. Verify footer shows "Done" button (primary)
7. Verify footer shows "Edit" text button below Done (centered, primary color)
8. Tap "Edit"
9. Verify drawer transitions to `BlockOutDrawer` in edit mode
10. Verify title bar appears: "Edit Block Out"
11. Verify form fields are now enabled (date pickers, reason field)
12. Verify footer shows "Cancel" + "Update" buttons

**TEST 2: "This Month's Events" tap — non-creator view-only**

1. As non-creator, tap a block-out event from "This Month's Events" list
2. Verify `ViewBlockOutDrawer` opens
3. Verify header shows date/date-range (large text)
4. Verify detail row shows reason (if present)
5. Verify footer shows "Done" button only (no Edit button)
6. Verify NO banner about "only the creator can edit" (absence of Edit button is sufficient UX)
7. Tap "Done"
8. Verify drawer dismisses

**TEST 3: Calendar grid day tap — creator view-first**

1. As creator, tap a calendar day containing a block-out
2. Verify `DayDetailBottomSheet` opens showing the block-out event
3. Tap the block-out event card
4. Verify day sheet closes
5. Verify `ViewBlockOutDrawer` opens with NO title bar
6. Verify header shows date/date-range (large text, NOT form fields)
7. Verify footer shows "Done" + "Edit" buttons
8. Tap "Edit"
9. Verify drawer transitions to `BlockOutDrawer` in edit mode with title bar "Edit Block Out"
10. Verify form fields are enabled

**TEST 4: Calendar grid day tap — non-creator view-only**

1. As non-creator, tap a calendar day containing a block-out
2. Verify `DayDetailBottomSheet` opens
3. Tap the block-out event card
4. Verify day sheet closes
5. Verify `ViewBlockOutDrawer` opens
6. Verify header shows date/date-range (large text)
7. Verify footer shows "Done" button only (no Edit button)
8. Verify no banner

**TEST 5: Create mode unchanged**

1. Tap "Add Event" (or equivalent block-out creation entry point)
2. Verify `BlockOutDrawer` opens in create mode (title: "Add Block Out")
3. Verify form fields are enabled
4. Verify footer shows "Cancel" + "Add Block Out" buttons (unchanged)

**TEST 6: Edit mode unchanged**

1. Open a block-out as creator
2. Tap "Edit" in ViewBlockOutDrawer
3. Verify `BlockOutDrawer` opens in edit mode
4. Verify form fields are enabled
5. Verify footer shows "Cancel" + "Update" buttons
6. Verify "Delete Block Out" button present in scrollable content

**TEST 7: Multi-day block-out presentation**

1. As creator, create a multi-day block-out (e.g., July 3-5)
2. Tap the block-out from calendar
3. Verify ViewBlockOutDrawer header shows:
   - Line 1: Start date (large): "Saturday, July 3, 2026"
   - Line 2: Subtitle: "Through Sunday, July 5, 2026"
4. Verify NO form fields (detail row presentation only)

**TEST 8: Single-day block-out presentation**

1. As creator, create a single-day block-out
2. Tap the block-out from calendar
3. Verify ViewBlockOutDrawer header shows:
   - Full date (large): "Saturday, July 3, 2026"
   - No subtitle (or "Single day" if implemented)
4. Verify NO form fields

**TEST 9: Block-out with no reason**

1. Create a block-out with no reason text
2. Tap the block-out from calendar
3. Verify ViewBlockOutDrawer shows header (date) and footer (Done/Edit)
4. Verify NO detail rows (reason row omitted when empty)
5. Verify still opens correctly (not broken by missing data)

## QA Regression Areas

### Primary Test Areas

1. **View-first flow**: Verify both entry paths (list tap and day tap) open ViewBlockOutDrawer first for all users
2. **Creator Edit transition**: Verify Edit button in ViewBlockOutDrawer footer transitions to BlockOutDrawer edit mode correctly
3. **Non-creator view**: Verify non-creators see ViewBlockOutDrawer with Done only (no Edit button, no banner)
4. **View drawer body**: Verify header (date/date-range) and detail rows (reason) match gig/rehearsal pattern — NO form fields
5. **Multi-day vs. single-day**: Verify header format differs correctly based on isMultiDay

### Secondary Test Areas (Regression)

1. **Block-out creation**: Verify "Add Block Out" flow unchanged (create mode footer still shows Cancel + Add Block Out)
2. **Block-out editing**: Verify edit mode unchanged (form fields enabled, Cancel + Update buttons)
3. **Block-out deletion**: Verify delete button still present in edit mode scrollable content
4. **Gig view-first**: Verify confirmed gigs still open `ViewGigDrawer` in view mode first (unaffected)
5. **Rehearsal view-first**: Verify confirmed rehearsals still open `ViewRehearsalDrawer` in view mode first (unaffected)
6. **Day detail sheet**: Verify `DayDetailBottomSheet` "Add Event" footer still renders correctly (unaffected)

## Rollout / Migration Strategy

Not applicable. UI-only change with no data migration or backend deployment.

## Out of Scope

- Block-out creation flow (`BlockOutDrawerMode.create`) — unchanged
- Block-out deletion logic — unchanged
- `DayDetailBottomSheet` — unchanged
- Gig and rehearsal view/edit flows — unchanged (reference pattern only)
- Permission logic changes — reuses existing `EventPermissionHelper.canEditEvent()`
- Any changes to block-out data persistence, RPC calls, or RLS policies
- Banner or messaging for non-creators in ViewBlockOutDrawer (absence of Edit button is sufficient UX)
