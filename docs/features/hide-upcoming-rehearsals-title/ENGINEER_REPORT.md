# Engineer Report

## Feature Slug

`feature/hide-upcoming-rehearsals-title`

## Feature Title

Hide "Upcoming Rehearsals" Title When Only Potential Rehearsals Exist

## Goal

Conditionally render the "Upcoming Rehearsals" section (title + content) to hide it whenever there are no confirmed rehearsals — regardless of whether potential rehearsals exist or not. The section only renders when at least one confirmed rehearsal exists. This prevents an orphaned heading and improves UX.

## Architect Tasks Completed

- [x] Task 1 — Modify `home_tab_content.dart`: Wrap "Upcoming Rehearsals" section in conditional `if (rehearsalState.confirmedRehearsals.isNotEmpty)`
- [x] Task 2 — Modify `home_screen.dart`: Wrap "Upcoming Rehearsals" section in conditional `if (nextRehearsal != null)`
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

- ✅ Conditional wrapping applied to `home_tab_content.dart` — simplified to `if (rehearsalState.confirmedRehearsals.isNotEmpty)`
- ✅ Conditional wrapping applied to `home_screen.dart` — simplified to `if (nextRehearsal != null)`
- ✅ Inner ternary in both files removed — section always shows content when condition is true
- ✅ Empty state cards removed from both files — section hidden when no confirmed rehearsals
- ✅ Comments updated to explain conditional logic
- ✅ Spread operator syntax `...[...]` correctly applied to wrap multiple widgets
- ✅ No changes to unrelated code
- ✅ Flutter analyze passed with no issues

## Deviations From Architect Plan

**Scope correction applied after initial implementation:**

The original Architect plan specified hiding the section when there were no confirmed rehearsals AND only potential rehearsals existed, while keeping the section visible (with empty state) when there were no rehearsals at all.

After implementation review, the requirement was clarified: the section must be hidden whenever there are no confirmed rehearsals — regardless of whether potential rehearsals exist or not. The section should only render when at least one confirmed rehearsal exists.

**Changes from original plan:**
- `home_tab_content.dart`: Conditional simplified from `if (rehearsalState.confirmedRehearsals.isNotEmpty || rehearsalState.potentialRehearsals.isEmpty)` to `if (rehearsalState.confirmedRehearsals.isNotEmpty)`
- `home_screen.dart`: Conditional simplified from `if (nextRehearsal != null || potentialGig == null)` to `if (nextRehearsal != null)`
- Empty state cards removed from both conditional blocks (no longer reachable)

## Blockers Encountered

None

## Ready For QA

**Yes**

The implementation is complete and ready for QA verification with the updated scope. QA should test the following scenarios:

1. **User with only potential rehearsals:** "Upcoming Rehearsals" section should be hidden
2. **User with at least one confirmed rehearsal:** "Upcoming Rehearsals" section should be visible with content
3. **User with no rehearsals at all:** "Upcoming Rehearsals" section should be hidden (empty state removed from this section)

Note: The empty state for "no rehearsals at all" is now shown in other parts of the dashboard, not in the "Upcoming Rehearsals" section.

Both primary dashboard path (`HomeTabContent`) and secondary path (`HomeScreen`) have been updated for consistency.
