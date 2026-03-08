# Engineer Report — Unified Add Event Workflow

## 1) Feature Identity

- **Feature Slug:** unified-add-event-workflow
- **Feature Title:** Unified "+ Add Event" Workflow
- **Branch Name:** `feature/unified-add-event-workflow`
- **Docs Folder:** `docs/features/unified-add-event-workflow/`

---

## 2) Goal

Consolidate all event creation (rehearsal, gig, block out) into a single "+ Add Event" action that opens the existing Event Editor Drawer with a three-way toggle: **Rehearsal | Gig | Block Out**. Remove duplicate entry points (separate "Block Out" button, separate "Schedule Rehearsal" / "Create Gig" quick action buttons).

---

## 3) Current State (Before)

- Dashboard had 3–4 separate buttons: "+ Schedule Rehearsal", "+ Create Gig", "+ Block Out", "+ Create Setlist"
- Block out creation used a completely separate `BlockOutDrawer` (not the Event Editor)
- Calendar screen had two action buttons: "Add Event" + "Block Out"
- RBAC was handled per-button: admins/members saw all buttons, contributors saw only "Create Gig"

---

## 4) Constraints Followed

- Followed the Architect plan exactly
- Minimal changes — no unrelated refactors
- No initialization order changes
- No new dependencies
- Preserved RBAC enforcement at every level
- The standalone `add_block_out_drawer.dart` file is **retained** (not deleted) — it may still be used by other flows or future needs

---

## 5) Implementation Summary

### Task 1: Extend EventType enum

- Added `blockOut` value with `displayName` = `'Block Out'`

### Task 2: Block Out support in Event Editor Drawer

- Added `existingBlockOut` parameter to accept a `BlockOutSpan` for edit mode
- Added `_blockOutUntilDate` state and initialization from existing block out
- Updated `_buildEventTypeToggle()` RBAC filter — hides `blockOut` tab for contributors
- Added `_isFormValid` handling for block out (always valid — no required fields)
- Added `_saveBlockOut()` with RBAC check, date validation, create/update (delete-then-create pattern)
- Added `_deleteBlockOut()` with confirmation dialog
- Routed `_handleSave()` and `_showDeleteConfirmation()` to block out methods
- Added `_buildBlockOutForm()` with Start Date, End Date (optional), Reason (optional)
- Helper methods: `_buildBlockOutDateField`, `_selectBlockOutStartDate`, `_selectBlockOutUntilDate`, `_blockOutDatePickerTheme`, `_formatBlockOutDate`
- Wrapped gig/rehearsal form fields in `else` block so they don't render for block outs

### Task 3: Update AddEditEventBottomSheet wrapper

- Added `existingBlockOut` parameter, passed through to `EventEditorDrawer`

### Task 4: Simplify QuickActionsRow

- Replaced `onScheduleRehearsal`, `onCreateGig`, `onBlockOut` (and `show*` flags) with single `onAddEvent` / `showAddEvent`
- Kept `onCreateSetlist` / `showCreateSetlist` unchanged
- Now renders two buttons max: "+ Add Event" and "+ Create Setlist"

### Task 5: Update EmptyHomeState

- Replaced `onScheduleRehearsal`, `onCreateGig`, `onBlockOut` with single `onAddEvent`
- Both empty section cards ("No Rehearsal", "No Gigs") use `onAddEvent`
- QuickActionsRow invocation updated to match new API

### Task 6: Update dashboard screens

- **home_screen.dart**: Removed `add_block_out_drawer.dart` import, replaced `_handleBlockOut()` with `_handleAddEvent()` (RBAC-aware default type), updated `EmptyHomeState` and `QuickActionsRow` invocations
- **home_tab_content.dart**: Same changes applied

### Task 7: Update calendar screens

- **calendar_screen.dart**: Removed `_handleBlockOut()`, consolidated two action buttons into single "Add Event" button, updated `_openEditEventSheet()` block out flow to route through `AddEditEventBottomSheet` with `viewOnly` flag instead of `BlockOutDrawer`
- **calendar_tab_content.dart**: Same — removed `_handleBlockOut()`, consolidated `_buildActionButtons()` to single button, updated block out edit flow

### Task 8: Update tips & tricks text

- Updated tip from "Tap + Schedule Rehearsal or + Create Gig…" to reference "+ Add Event"

---

## 6) Files Changed

| File                                                           | Change                                                                |
| -------------------------------------------------------------- | --------------------------------------------------------------------- |
| `lib/features/events/models/event_form_data.dart`              | Added `blockOut` to `EventType` enum                                  |
| `lib/features/events/widgets/event_editor_drawer.dart`         | Block out form, save/delete logic, RBAC toggle filtering (+379 lines) |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Added `existingBlockOut` passthrough                                  |
| `lib/features/home/widgets/quick_actions_row.dart`             | Simplified to `onAddEvent` / `showAddEvent`                           |
| `lib/features/home/widgets/empty_home_state.dart`              | Simplified to `onAddEvent`                                            |
| `lib/features/home/home_screen.dart`                           | Consolidated event creation handlers                                  |
| `lib/features/home/home_tab_content.dart`                      | Consolidated event creation handlers                                  |
| `lib/features/calendar/calendar_screen.dart`                   | Single action button, unified block out editing                       |
| `lib/features/calendar/calendar_tab_content.dart`              | Single action button, unified block out editing                       |
| `lib/components/overlays/tips_and_tricks_overlay.dart`         | Updated tip text                                                      |

**10 files changed, +456 / -279 lines**

No files created. No files deleted. No migrations.

---

## 7) Verification

### Commands run:

- `flutter analyze` — **No issues found** (0 errors, 0 warnings)

### Manual QA flows to verify:

1. **Dashboard (Admin/Member)**:
   - Tap "+ Add Event" → Event Editor opens with Rehearsal tab selected
   - Toggle shows 3 tabs: Rehearsal | Gig | Block Out
   - Create a rehearsal → saves correctly, calendar & dashboard refresh
   - Create a gig → saves correctly
   - Select "Block Out" tab → shows Start Date, End Date (optional), Reason (optional)
   - Create a block out with just a start date → saves correctly
   - Create a block out with date range and reason → saves correctly

2. **Dashboard (Contributor with gig permission)**:
   - Tap "+ Add Event" → opens with Gig tab selected
   - Toggle shows only: Rehearsal | Gig (no Block Out tab)
   - Can create gigs

3. **Dashboard (Contributor without gig permission)**:
   - No "+ Add Event" button visible
   - "+ Create Setlist" still visible if they have setlist permission

4. **Calendar (Admin/Member)**:
   - Single "Add Event" button (no separate "Block Out" button)
   - Tap "Add Event" → opens Event Editor with toggle
   - Tap existing block out → opens Event Editor in edit mode with block out data populated
   - Tap someone else's block out → opens in view-only mode (grayed out, Close button only)

5. **Calendar (Contributor)**:
   - Single "Add Event" button if they have gig permission, no button otherwise

6. **Empty state**:
   - When no events exist, empty state shows "+ Add Event" button
   - Tapping it opens unified Event Editor

7. **Tips & Tricks**:
   - Verify dashboard tip text references "+ Add Event"

8. **Block Out edit flow**:
   - Edit existing block out → changes reason → saves (delete-then-create)
   - Delete block out via red "Delete Block Out" button → confirms → deletes

---

## 8) QA Focus Areas

- **RBAC enforcement**: Contributors must NOT see Block Out tab. Contributors without `canCreateGigs` must not see any event creation buttons.
- **Block out save pattern**: Uses delete-then-create for updates (same as original `BlockOutDrawer`). Verify no orphaned `block_dates` rows after edits.
- **Calendar refresh**: After creating/editing/deleting block outs, calendar markers should update immediately.
- **View-only mode**: Tapping another user's block out should show data but not allow saving/deleting.
- **Empty section cards**: "Schedule Rehearsal" and "Create Gig" buttons on empty section cards still work (they open Event Editor pre-set to the correct type).
- **Regression**: Gig and rehearsal creation/editing flows should be completely unaffected.

---

## 9) Diff Reference

- Git diff included: **see below** (run `git diff` from the branch)
- Key sections to inspect:
  - `event_editor_drawer.dart` — largest change, verify `_saveBlockOut()` RBAC checks and date validation
  - `quick_actions_row.dart` and `empty_home_state.dart` — API simplification, ensure no broken call sites
  - Calendar screens — `_openEditEventSheet` block out routing now uses `AddEditEventBottomSheet` with `viewOnly` flag
