# Engineer Report

## Feature Slug

home-rehearsal-scroll-row

## Feature Title

Home Screen: Horizontal Scroll Row for Confirmed Rehearsals

## Goal

Replace the single "Next Rehearsal" card on the home screen with a horizontal scrollable row displaying all confirmed upcoming rehearsals, mirroring the existing "Upcoming Gigs" pattern. This improves rehearsal visibility and provides users with a complete view of their schedule without navigating to the calendar.

## Architect Tasks Completed

- [x] Task 1 — Add `_buildHorizontalRehearsalsList` method after `_buildHorizontalGigsList`, mirroring its pattern exactly
- [x] Task 2 — Update "Upcoming Rehearsals" section to call `_buildHorizontalRehearsalsList` when `confirmedRehearsals.isNotEmpty`, replacing single card render
- [x] Task 3 — Run `flutter analyze` and verify zero errors
- [x] Task 4 — Manual verification via git diff

## Files Created

None

## Files Modified

- lib/features/home/home_tab_content.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings

Initial run found 2 issues:

- Warning: unused local variable `nextRehearsal` (line 688)
- Error: undefined name `setlistProvider` (line 1049)

Both issues fixed:

- Removed unused `nextRehearsal` variable declaration
- Corrected typo: `setlistProvider` → `setlistsProvider`

Second run: No issues found! (ran in 2.4s)

## Test Results

Not run (no automated tests exist for home screen UI)

## Verification

Manual steps performed:

1. Verified git diff shows only home_tab_content.dart modified
2. Confirmed `_buildHorizontalRehearsalsList` method added after line 1040 (after `_buildHorizontalGigsList`)
3. Confirmed method signature matches pattern: `Widget _buildHorizontalRehearsalsList(RehearsalState rehearsalState)`
4. Confirmed method uses `Spacing.rehearsalCardHeight` for container height
5. Confirmed ListView.separated with `scrollDirection: Axis.horizontal` and `clipBehavior: Clip.none`
6. Confirmed separator uses `const SizedBox(width: 16)` matching gigs pattern
7. Confirmed setlist name lookup logic mirrors original single-card implementation
8. Confirmed "Upcoming Rehearsals" section condition changed from `nextRehearsal != null` to `rehearsalState.confirmedRehearsals.isNotEmpty`
9. Confirmed empty state logic preserved (SizedBox.shrink when potentials exist, EmptySectionCard when no rehearsals)
10. Confirmed code formatted with `dart format`

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes

Implementation complete per Architect specification. All tasks executed in order. Static analysis passes with zero errors. The horizontal scroll row for confirmed rehearsals now matches the existing "Upcoming Gigs" pattern.

QA should verify:

- Multiple confirmed rehearsals render in horizontal scroll row
- Single rehearsal renders correctly (not stretched to full width)
- Empty state displays when no rehearsals exist
- Setlist names appear correctly on rehearsal cards
- Tap on rehearsal card opens edit drawer (admin/member only)
- Potential rehearsals do NOT appear in confirmed section
- Platform consistency (iOS, Android, macOS, Web)
