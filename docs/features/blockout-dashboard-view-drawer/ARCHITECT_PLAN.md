# Feature Slug

`bug/blockout-dashboard-view-drawer`

---

# Problem Summary

Block-out dates tapped from the calendar's "This Month's Events" section (and the day detail sheet when tapping a calendar day) open the old `AddEditEventBottomSheet` drawer instead of the newer `BlockOutDrawer` widget. This creates inconsistent UX compared to the recently-fixed rehearsal feature (commit b4b5822), where confirmed events now open dedicated view drawers.

The `BlockOutDrawer` widget exists at `lib/features/calendar/widgets/add_block_out_drawer.dart` with proper viewOnly and edit modes, but it is never invoked anywhere in the codebase — the calendar still uses the old event editor.

---

# Root Cause

**Confidence Level: HIGH**

The calendar's `_openEditEventSheet` method (lines 193-213 in `calendar_tab_content.dart`) explicitly handles block-outs by opening `AddEditEventBottomSheet.show()` instead of the newer `BlockOutDrawer.show()`.

The old drawer is passed `viewOnly: !canEdit` to enable read-only mode for non-creators, but this provides an inferior UX compared to the dedicated `BlockOutDrawer` which has proper edit/viewOnly mode separation matching the gig/rehearsal patterns.

This is confirmed by direct code observation: `grep -r "BlockOutDrawer.show" lib/` returns only the drawer's own file — no call sites exist.

---

# Reference Docs Consulted

No domain-specific reference docs for block-outs or drawers exist in `docs/reference/`.

---

# Existing System Analysis

**Current Behavior:**

1. User taps a day on the calendar grid
2. `DayDetailBottomSheet` opens showing all events for that day
3. User taps a block-out event card → calls `onEventTap` → calls `_openEditEventSheet(event)`
4. `_openEditEventSheet` detects `event.isBlockOut` and opens `AddEditEventBottomSheet` with:
   - `mode: canEdit ? EventFormMode.edit : EventFormMode.create`
   - `initialType: EventType.blockOut`
   - `existingBlockOut: event.blockOutSpan`
   - `viewOnly: !canEdit`

OR:

1. User scrolls to "This Month's Events" section below the calendar grid
2. User taps a block-out event card → same flow as above

**Permission Check:**

- Uses `EventPermissionHelper.canEditEvent(event)` which checks if `currentUserId == event.blockOutSpan.userId` (only creator can edit)

**Affected Entry Points:**

1. `DayDetailBottomSheet` (lines 190-194 in `day_detail_bottom_sheet.dart`) — renders `CalendarEventCard` with `onTap: () => onEventTap?.call(event)`
2. `_EventsSection` (lines 540-548 in `calendar_tab_content.dart`) — renders `CalendarEventCard` with `onTap: () => onEventTap?.call(event)`

Both entry points route through the same `_openEditEventSheet` handler in `calendar_tab_content.dart`.

**Home/Dashboard Investigation:**
The feature input claimed home/dashboard surfaces render block-outs with stale handlers. Investigation confirms this is incorrect:

- `home_screen.dart` does NOT render `CalendarEvent` objects
- `home_tab_content.dart` does NOT render `CalendarEvent` objects
- Neither file imports or uses `CalendarEventCard`
- Home screens only render gigs and rehearsals via dedicated card widgets

The bug is isolated to the calendar tab.

---

# Proposed Solution

Replace the block-out handling in `_openEditEventSheet` to use `BlockOutDrawer` instead of `AddEditEventBottomSheet`.

**Changes:**

1. Import `add_block_out_drawer.dart` at the top of `calendar_tab_content.dart`
2. In `_openEditEventSheet` method, replace the block-out handling block (lines 194-213) with:

   ```dart
   if (event.isBlockOut && event.blockOutSpan != null) {
     final currentUserId = supabase.auth.currentUser?.id;
     final permissionHelper = EventPermissionHelper(
       currentUserId: currentUserId,
     );
     final canEdit = permissionHelper.canEditEvent(event);
     final activeBandId = ref.read(activeBandProvider).activeBand?.id;

     if (activeBandId == null) return;

     BlockOutDrawer.show(
       context,
       ref: ref,
       bandId: activeBandId,
       mode: canEdit ? BlockOutDrawerMode.edit : BlockOutDrawerMode.viewOnly,
       existingBlockOut: event.blockOutSpan,
       onSaved: _refreshCalendarData,
     );
     return;
   }
   ```

**Rationale:**

- Preserves the existing permission check logic (creator-only edit)
- Uses the dedicated block-out drawer which matches the UX pattern for gigs/rehearsals
- No changes to the drawer widget itself (already supports edit/viewOnly modes)
- No changes to any other event handling (gigs/rehearsals remain untouched)

---

# Database Impact

**Not applicable** — no database changes required.

---

# Flutter Architecture Changes

**State:**

- No state changes. Uses existing `activeBandProvider` to get band ID
- Continues to call `_refreshCalendarData` callback on save/delete

**Widgets:**

- No new widgets created
- No widget tree changes
- Only the tap handler implementation changes

**Repositories:**

- No repository changes (BlockOutDrawer already uses `BlockOutRepository` internally)

---

# Files to Create

**None** — the `BlockOutDrawer` widget already exists.

---

# Files to Modify

| File                                              | What changes                                                                                                                                                                          |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/calendar/calendar_tab_content.dart` | Add import for `add_block_out_drawer.dart`; replace lines 194-213 in `_openEditEventSheet` to call `BlockOutDrawer.show()` instead of `AddEditEventBottomSheet.show()` for block-outs |

---

# Files Off-Limits

| File                                                           | Reason                                           |
| -------------------------------------------------------------- | ------------------------------------------------ |
| `lib/main.dart`                                                | Init order must not change                       |
| `lib/features/calendar/calendar_screen.dart`                   | Dead code — do not touch                         |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`      | Do not modify the drawer widget itself           |
| `lib/features/calendar/widgets/calendar_event_card.dart`       | Event card rendering is correct                  |
| `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`   | Day sheet correctly passes events to tap handler |
| `lib/features/home/home_screen.dart`                           | Does not render block-outs                       |
| `lib/features/home/home_tab_content.dart`                      | Does not render block-outs                       |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Leave event editor untouched                     |

---

# System Impact Map

| System                                 | Impact                                           |
| -------------------------------------- | ------------------------------------------------ |
| Gigs                                   | unaffected                                       |
| Rehearsals                             | unaffected                                       |
| Setlists / Catalog                     | unaffected                                       |
| Members / RBAC                         | unaffected (preserves existing permission check) |
| Auth / Session                         | unaffected                                       |
| Routing                                | unaffected                                       |
| Notifications                          | unaffected                                       |
| Platform (iOS / Android / Web / macOS) | affected (all platforms render calendar)         |

---

# Regression Risk

**Level: LOW**

**Rationale:**

- Single file, single method change
- Block-outs are an isolated feature (no cross-feature dependencies)
- No database, RLS, auth, routing, or init order changes
- The `BlockOutDrawer` widget is fully implemented with proper modes (just never wired up)
- Existing permission logic is preserved exactly
- Gig and rehearsal tap handlers remain untouched
- If the drawer has issues, only block-out taps from the calendar are affected (user can still create/edit via "Add Event" button → event type selector)

---

# Engineer Task Breakdown

Execute in strict order:

1. **Add Import**
   - Add `import 'widgets/add_block_out_drawer.dart';` to the imports section of `calendar_tab_content.dart` (around line 28, after existing widget imports)

2. **Replace Block-Out Handler**
   - Locate the block-out handling block in `_openEditEventSheet` (lines 194-213)
   - Replace the entire block with the new `BlockOutDrawer.show()` call as specified in Proposed Solution
   - Ensure band ID null check is included before calling the drawer
   - Preserve the existing permission check logic

3. **Verify Other Event Handling**
   - Confirm gig handling (lines 224-243) remains unchanged
   - Confirm rehearsal handling (lines 246-260) remains unchanged
   - Confirm the method signature and other logic is untouched

4. **Run Analysis**
   - Execute `flutter analyze` and confirm 0 errors
   - Fix any new warnings related to the changed code

5. **Generate Diff**
   - Run `git diff lib/features/calendar/calendar_tab_content.dart`
   - Confirm diff shows only:
     - One new import line
     - Replacement of the block-out handler block
     - No other changes

6. **Create Engineer Report**
   - Document completion of all tasks
   - Include the git diff output
   - Confirm `flutter analyze` passed
   - Report ready for QA

---

# Verification Plan

## Tier 1 — Pre-deployment

**Not applicable** — this is a client-only change with no database migrations.

## Tier 2 — Post-deployment

**Not applicable** — no database deployment required. Verification is manual UI testing only (see QA Regression Areas).

---

# QA Regression Areas

QA must specifically test:

**Primary - Block-Out Tap Paths:**

1. **Calendar Day Tap Flow:**
   - Tap a day on the calendar grid that has a block-out
   - Verify `DayDetailBottomSheet` opens showing the block-out event
   - Tap the block-out card → verify `BlockOutDrawer` opens (NOT the old event editor)
   - If you're the creator: verify drawer opens in edit mode with "Cancel" / "Update" buttons and "Delete Block Out" option
   - If you're not the creator: verify drawer opens in viewOnly mode with only a "Close" button and non-editable fields
   - Verify "Update" (if creator) or "Close" refreshes the calendar correctly

2. **This Month's Events Flow:**
   - Scroll to "This Month's Events" section below the calendar grid
   - Find a block-out event in the list
   - Tap it → verify `BlockOutDrawer` opens (NOT the old event editor)
   - Same permission checks as above

3. **Block-Out Creation (Unchanged):**
   - Tap "Add Event" button → tap "Block Out" type → verify old `AddEditEventBottomSheet` still works for creation
   - OR tap a day with no events → tap "Add Event" in day detail sheet → verify same

**Regression - Other Event Types:**

1. **Gigs:**
   - Tap a confirmed gig from day detail sheet → verify `ViewGigDrawer` opens (not affected)
   - Tap a confirmed gig from "This Month's Events" → verify same
   - Tap an unconfirmed/potential gig → verify event editor opens (not affected)

2. **Rehearsals:**
   - Tap a confirmed rehearsal from day detail sheet → verify `ViewRehearsalDrawer` opens (not affected)
   - Tap a confirmed rehearsal from "This Month's Events" → verify same
   - Tap an unconfirmed rehearsal → verify event editor opens (not affected)

**Cross-Platform:**

- Test on Web, iOS, Android, macOS to ensure drawer opens correctly on all platforms
- Verify responsive behavior (mobile vs desktop sizing)

**Edge Cases:**

- Block-out that spans multiple days (only created by creator should be editable)
- Block-out with long reason text (verify text wraps correctly in drawer)
- Block-out with no reason (verify optional field is empty/not broken)

---

# Rollout / Migration Strategy

**Not applicable** — client-only change. Deploy follows standard web deployment protocol.

---

# Out of Scope

Explicitly not part of this fix:

- Redesigning the `BlockOutDrawer` widget itself
- Changing block-out permissions model (remains creator-only edit)
- Changing block-out data model or database schema
- Updating the "Add Event" flow for creating new block-outs (still uses event type selector → event editor)
- Adding an "Edit" button to viewOnly mode (current design has no edit escape from viewOnly — by design, since only creator can edit)
- Fixing any home/dashboard surfaces (investigation confirmed none exist)
- Updating `calendar_screen.dart` (dead code)
