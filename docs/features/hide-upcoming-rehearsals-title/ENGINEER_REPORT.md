# Engineer Report

## Feature Slug

`feature/hide-upcoming-rehearsals-title`

## Feature Title

Hide "Upcoming Rehearsals" Title When Only Potential Rehearsals Exist

## Goal

Conditionally render the "Upcoming Rehearsals" section (title + content) to hide it whenever there are no confirmed rehearsals — regardless of whether potential rehearsals exist or not. The section only renders when at least one confirmed rehearsal exists. This prevents an orphaned heading and improves UX.

## Architect Tasks Completed

- [x] Task 1 — Modify `home_tab_content.dart`: Split title from content, hide title when no confirmed rehearsals, show empty state when no rehearsals at all
- [x] Task 2 — Modify `home_screen.dart`: Split title from content, hide title when no confirmed rehearsals, show empty state when no potential gig
- [x] Task 3 — Run `flutter analyze`: PASSED (0 errors, 0 warnings)
- [x] Task 4 — Format changed files
- [x] Task 5 — Generate ENGINEER_REPORT.md

## Files Created

- docs/features/hide-upcoming-rehearsals-title/ENGINEER_REPORT.md

## Files Modified

- lib/features/home/home_tab_content.dart
- lib/features/home/home_screen.dart

## Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors, 0 warnings  
**Output:** `No issues found! (ran in 4.4s)`

## Test Results

Not run (manual QA verification required as per Architect plan Section 17)

## Verification

Manual static verification performed:

- ✅ Title conditional applied to `home_tab_content.dart` — shows only when `confirmedRehearsals.isNotEmpty`
- ✅ Content conditional applied to `home_tab_content.dart` — shows confirmed list OR empty state card when no rehearsals at all
- ✅ Title conditional applied to `home_screen.dart` — shows only when `nextRehearsal != null`
- ✅ Content conditional applied to `home_screen.dart` — shows rehearsal card OR empty state card when no potential gig
- ✅ Empty state card preserved in both files — displays when no rehearsals at all
- ✅ Comments updated to explain split conditional logic
- ✅ No changes to unrelated code
- ✅ Flutter analyze passed with no issues

## Deviations From Architect Plan

**Second scope correction applied after initial implementation:**

The first implementation (commit 1) hid the entire section (title + content) when there were no confirmed rehearsals. This was corrected to hide only the section when there were no confirmed rehearsals AND potential rehearsals existed.

After further review, the requirement was clarified again: **the title should hide when there are no confirmed rehearsals, but the empty state card must still appear when there are no rehearsals at all** (confirmed or potential).

**Final implementation (commit 2):**

- `home_tab_content.dart`:
  - Title renders only when `confirmedRehearsals.isNotEmpty`
  - Content renders confirmed list when available, OR empty state card when `potentialRehearsals.isEmpty`
  - Nothing renders when only potential rehearsals exist (they appear in "Potential Events" section)

- `home_screen.dart`:
  - Title renders only when `nextRehearsal != null`
  - Content renders rehearsal card when available, OR empty state card when `potentialGig == null`
  - Empty state provides context and action button for users with no events

**Key behavioral changes from original plan:**

- Original plan: Hide entire section when `confirmedRehearsals.isEmpty`
- First correction: Hide section only when potential rehearsals exist
- **Final correction: Split title from content — hide title when no confirmed rehearsals, preserve empty state when no rehearsals at all**

This ensures:

1. Users with only potential rehearsals don't see an orphaned title ✓
2. Users with no rehearsals at all see empty state with action button ✓
3. Users with confirmed rehearsals see title + content ✓

## Blockers Encountered

None

## Ready For QA

**Yes**

The implementation is complete and ready for QA verification with the final corrected scope. QA should test the following scenarios:

**Test Case 1: User with only potential rehearsals**

- Expected: "Potential Events" section visible with potential rehearsals
- Expected: "Upcoming Rehearsals" title NOT visible
- Expected: "Upcoming Rehearsals" empty state NOT visible
- Expected: No orphaned heading or empty space

**Test Case 2: User with at least one confirmed rehearsal**

- Expected: "Upcoming Rehearsals" title IS visible
- Expected: "Upcoming Rehearsals" content IS visible with horizontal scroll list

**Test Case 3: User with no rehearsals at all (confirmed or potential)**

- Expected: "Upcoming Rehearsals" title NOT visible
- Expected: "Upcoming Rehearsals" empty state card IS visible
- Expected: Empty state shows "No Rehearsal Scheduled" + "Schedule Rehearsal" button

**Test Case 4: Mixed scenario (both confirmed and potential rehearsals)**

- Expected: "Potential Events" section shows potential rehearsals
- Expected: "Upcoming Rehearsals" title IS visible
- Expected: "Upcoming Rehearsals" content shows confirmed rehearsals only

Both primary dashboard path (`HomeTabContent`) and secondary path (`HomeScreen`) have been updated for consistency.
