# Engineer Report

## Feature Slug

`dashboard-empty-state-event-defaults`

## Feature Title

Dashboard Empty-State Event Defaults

## Goal

Fix the dashboard empty-state component to correctly open the Add Event sheet with the appropriate event type pre-selected based on which button the user taps. The "Create Rehearsal" button should open with `EventType.rehearsal` selected, and the "Create Gig" button should open with `EventType.gig` selected. This is achieved by replacing the single generic `onAddEvent` callback with two specific callbacks (`onCreateRehearsal` and `onCreateGig`) and updating button labels for consistency.

## Architect Tasks Completed

- [x] **Task 1** — Update `EmptyHomeState` widget — COMPLETED
  - Removed `onAddEvent` parameter from constructor
  - Added `onCreateRehearsal` and `onCreateGig` parameters (both `VoidCallback?`)
  - Updated rehearsal `EmptySectionCard` button label from "Add Event" to "Create Rehearsal"
  - Bound rehearsal button to `widget.onCreateRehearsal`
  - Bound gig button to `widget.onCreateGig`
  - Updated Quick Actions visibility check to include all three callbacks

- [x] **Task 2** — Update `home_screen.dart` instantiation — COMPLETED
  - Removed `onAddEvent` parameter from `EmptyHomeState` instantiation
  - Added `onCreateRehearsal` callback with permission gating (null for contributors)
  - Added `onCreateGig` callback with permission gating (gated by `canCreateGig`)

- [x] **Task 3** — Update `home_tab_content.dart` instantiation — COMPLETED
  - Removed `onAddEvent` parameter from `EmptyHomeState` instantiation
  - Added `onCreateRehearsal` callback with permission gating (null for contributors)
  - Added `onCreateGig` callback with permission gating (gated by `canCreateGig`)

- [x] **Task 4** — Run Flutter Analyze — COMPLETED
  - Executed `flutter analyze`
  - Result: 0 errors, 0 warnings

- [x] **Task 5** — Manual Testing — PENDING QA
  - Implementation complete, ready for manual testing
  - Test cases documented in Architect plan (lines 300-370)

## Files Created

None — all required files existed.

## Files Modified

1. `lib/features/home/widgets/empty_home_state.dart`
   - Replaced `onAddEvent` parameter with `onCreateRehearsal` and `onCreateGig`
   - Updated rehearsal card button label from "Add Event" to "Create Rehearsal"
   - Updated rehearsal card to call `widget.onCreateRehearsal`
   - Updated gig card to call `widget.onCreateGig`
   - Updated Quick Actions visibility check to include all three callbacks
   - Updated Quick Actions row to use `onCreateRehearsal` as primary, fallback to `onCreateGig`

2. `lib/features/home/home_screen.dart`
   - Updated `EmptyHomeState` instantiation (line ~345)
   - Replaced `onAddEvent` with `onCreateRehearsal` and `onCreateGig`
   - Each callback correctly calls `_openAddEventSheet` with the appropriate `EventType`
   - Permission gating preserved: contributors cannot create rehearsals, gig creation requires `canCreateGig`

3. `lib/features/home/home_tab_content.dart`
   - Updated `EmptyHomeState` instantiation (line ~604)
   - Replaced `onAddEvent` with `onCreateRehearsal` and `onCreateGig`
   - Each callback correctly calls `_openAddEventSheet` with the appropriate `EventType`
   - Permission gating preserved: contributors cannot create rehearsals, gig creation requires `canCreateGig`

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors, 0 warnings

```
Analyzing bandroadie...
No issues found! (ran in 3.7s)
```

## Test Results

**Not run** — Manual testing required.

The Architect plan specifies manual testing only (Task 5). Automated unit tests were not required for this UI-only change. Manual test cases are documented in the Architect plan for QA execution:

### Test Cases (for QA)

**T1 — Admin/Member user on empty dashboard:**

- Verify "Create Rehearsal" button opens Add Event sheet with Rehearsal tab selected
- Verify "Create Gig" button opens Add Event sheet with Gig tab selected

**T2 — Contributor user (no gig permission) on empty dashboard:**

- Verify both buttons are disabled (grayed out)
- Verify buttons do not respond to taps

**T3 — Contributor user (with gig permission) on empty dashboard:**

- Verify "Create Rehearsal" button is disabled
- Verify "Create Gig" button is active and opens Add Event sheet with Gig tab selected

**T4 — Quick Actions "+ Add Event" button (regression check):**

- Verify Quick Actions "+ Add Event" button still works correctly
- Should default to Rehearsal for admin/member users (unchanged behavior)

## Verification

### Code Review Verification

1. **Empty state widget constructor** — Confirmed `onAddEvent` removed, `onCreateRehearsal` and `onCreateGig` added
2. **Button labels** — Confirmed rehearsal button label changed from "Add Event" to "Create Rehearsal"
3. **Button bindings** — Confirmed each `EmptySectionCard` uses the correct callback
4. **Call site updates** — Confirmed both `home_screen.dart` and `home_tab_content.dart` pass the correct closures
5. **Event type parameters** — Confirmed `EventType.rehearsal` and `EventType.gig` are passed correctly to `_openAddEventSheet`
6. **Permission gating** — Confirmed existing permission logic preserved:
   - Contributors cannot create rehearsals (`isContributor ? null : ...`)
   - Gig creation requires `canCreateGig` flag
7. **Quick Actions** — Confirmed Quick Actions row still receives a callback (prioritizes rehearsal, falls back to gig)

### Flutter Analyze Verification

- **Errors:** 0
- **Warnings:** 0
- **Status:** PASS

### Formatting Verification

All three modified files formatted successfully:

```
Formatted lib/features/home/widgets/empty_home_state.dart
Formatted lib/features/home/home_screen.dart
Formatted lib/features/home/home_tab_content.dart
```

### Manual Runtime Verification

**Manual testing pending** — implementation is code-complete and ready for QA.

To test, QA should:

1. Run the app on iOS or Web
2. Create or select a band with no gigs or rehearsals
3. Verify empty-state dashboard appears with correct button labels
4. Test each button to confirm correct event type is pre-selected in Add Event sheet
5. Test as different user roles (admin, member, contributor with/without gig permission)
6. Verify Quick Actions "+ Add Event" button still works (regression check)

## Deviations From Architect Plan

None.

All implementation tasks were completed exactly as specified in the Architect plan. No files outside the approved list were modified. No additional changes, refactoring, or "while I'm here" edits were made.

## Blockers Encountered

None.

Implementation was straightforward. All required methods (`_openAddEventSheet`) and permission flags (`isContributor`, `canCreateGig`) already existed. No database, state management, or routing changes were required.

## Ready For QA

**Yes**

### Implementation Status

- ✓ All code changes implemented as specified
- ✓ Flutter Analyze passes with 0 errors, 0 warnings
- ✓ Files formatted correctly
- ✓ No deviations from Architect plan
- ✓ No blockers encountered
- ✓ Permission gating preserved
- ✓ No database or backend changes required
- ✓ Branch is clean and ready for commit

### QA Checklist

QA should verify:

1. "Create Rehearsal" button opens Add Event sheet with Rehearsal tab selected
2. "Create Gig" button opens Add Event sheet with Gig tab selected
3. Permission gating works correctly for different user roles
4. Button labels are correct ("Create Rehearsal", "Create Gig")
5. Quick Actions "+ Add Event" button still works (no regression)
6. Behavior is consistent across platforms (iOS, Web)

### Next Steps

1. QA performs manual testing as per test cases in Architect plan
2. If tests pass, QA creates QA_REPORT.md with APPROVED verdict
3. If tests fail, QA documents failures and returns to Engineer for fixes
4. Upon QA approval, commit changes with message: `fix(home): use correct event type for empty-state buttons`
