# ENGINEER REPORT

## Feature Slug
`sheet-header-scroll-and-required-fields`

## Feature Title
Sheet Header Scroll + Required-Fields Button Gate

## Cycle Number
2

## Goal
**Cycle 2:** Fix QA W1 — double horizontal padding regression introduced when headers were moved inside `SingleChildScrollView` in Cycle 1. Remove the horizontal component of the moved header's inner `Padding` in 7 confirmed files + `event_editor_drawer.dart`.

**Cycle 1:** Implement all planned work in full:
- **Change 2, Files 1–5** (batch 1, already done): move fixed header widgets from the outer Column into each sheet's `SingleChildScrollView` Column.
- **Change 2, Files 6–9** (batch 2): same header-move for `song_notes_drawer`, `gig_notes_sheet`, `rehearsal_notes_sheet`, and `day_detail_bottom_sheet` (special: ConstrainedBox+ListView → Flexible+SingleChildScrollView+Column).
- **Change 1, File 10** (`event_editor_drawer.dart`): add `_canSave` getter and replace the inline `canSave` local variable in `_buildStickyFooter`.

## Architect Tasks Completed
**Cycle 2 (W1 fix):**
- `add_block_out_drawer.dart`: header `Padding(horizontal: pagePadding)` → `Padding(EdgeInsets.zero)` (scroll provides horizontal margin)
- `band_member_edit_drawer.dart`: header `Padding(fromLTRB(pagePadding, space16, pagePadding, 0))` → `Padding(only(top: space16))` (strip left/right, keep top)
- `gig_notes_sheet.dart`: header `Padding(horizontal: pagePadding)` → `Padding(EdgeInsets.zero)`
- `rehearsal_notes_sheet.dart`: same as gig_notes_sheet
- `song_details_bottom_sheet.dart`: `_buildHeader()` Padding `(horizontal: space16, vertical: space12)` → `(symmetric(vertical: space12))`
- `song_enrichment_review_sheet.dart`: same as song_details
- `song_notes_drawer.dart`: same as song_details
- `event_editor_drawer.dart`: `_buildStickyHeader` Padding `fromLTRB(24, 20, 20, 16)` → `only(top: 20, bottom: 16)` — header IS inside `SingleChildScrollView(padding: all(16))` via `_buildScrollableBody`, confirmed double-padding, fix applied

**Cycle 1:**
- Change 2, File 1: `event_editor_drawer.dart` — `_buildStickyHeader` + divider moved from `build()` outer Column into `_buildScrollableBody()` (all return paths including expense editing)
- Change 2, File 2: `add_block_out_drawer.dart` — title-row `Padding` + `SizedBox(16)` removed from outer Column; added as first children inside `SingleChildScrollView` Column
- Change 2, File 3: `band_member_edit_drawer.dart` — header `Padding`, `SizedBox(16)`, `Divider(height: 1)` removed from outer Column; added as first three children inside `SingleChildScrollView` Column
- Change 2, File 4: `song_details_bottom_sheet.dart` — `_buildHeader()` + `Divider` removed from outer Column; added as first two children inside `SingleChildScrollView` Column (via spread of the existing ternary)
- Change 2, File 5: `song_enrichment_review_sheet.dart` — `_buildHeader()` + `Divider` removed from outer Column; added as first two children inside `SingleChildScrollView` Column
- Change 2, File 6: `song_notes_drawer.dart` — `_buildHeader()` + `Divider` removed from outer Column; scroll view child changed from ternary to `Column([_buildHeader(), Divider, ternary])`. Also fixed two pre-existing `avoid_redundant_argument_values` info violations in the file.
- Change 2, File 7: `gig_notes_sheet.dart` — `SizedBox(16)`, gig name `Padding`, `SizedBox(16)`, `Divider(h:1)` removed from outer Column; scroll view child changed from `Text(notes)` to `Column([SizedBox(16), Padding(gigName), SizedBox(16), Divider(h:1), SizedBox(16), Text(notes)])`. Added `SizedBox(16)` after divider to preserve the visual gap that was previously provided by the scroll view's top padding.
- Change 2, File 8: `rehearsal_notes_sheet.dart` — same pattern as File 7 with 'Rehearsal Notes' title.
- Change 2, File 9: `day_detail_bottom_sheet.dart` — `SizedBox(16)`, date header `Padding`, `SizedBox(8)`, events-count `Padding`, `SizedBox(16)` removed from outer Column; `ConstrainedBox(ListView.separated)` removed; replaced with `Flexible → SingleChildScrollView → Column([header, events count, ...event cards with for-loop separators or empty state])`.
- Change 1, File 10: `event_editor_drawer.dart` — added `bool get _canSave` getter (guards on `_isEditingExpense`, `_isSaving`, `_isDeleting`, `widget.viewOnly`, edit-mode `_isDirty`, create-mode type-specific field checks); replaced `final canSave = !_isSaving && ...` 3-line local variable in `_buildStickyFooter` with `_canSave`.

## Files Created
None.

## Files Modified
1. `lib/features/events/widgets/event_editor_drawer.dart`
2. `lib/features/calendar/widgets/add_block_out_drawer.dart`
3. `lib/features/contacts/widgets/band_member_edit_drawer.dart`
4. `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
5. `lib/features/setlists/widgets/song_enrichment_review_sheet.dart`
6. `lib/features/setlists/widgets/song_notes_drawer.dart`
7. `lib/features/gigs/widgets/gig_notes_sheet.dart`
8. `lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart`
9. `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`

(File 10 = same as File 1 — `event_editor_drawer.dart`. Total unique files: 9.)

## Analyzer Results
```
flutter analyze (8 changed files, Cycle 2): 0 errors, 0 warnings, 19 info issues (all pre-existing in untouched code lines).
```

**Cycle 1:**
Batch 1 result (files 1–5): 0 errors, 0 warnings, 19 info issues (all pre-existing in untouched code lines).
Batch 2 result (files 6–10): 0 issues. Two pre-existing `avoid_redundant_argument_values` info violations in `song_notes_drawer.dart` were fixed (trivial: `pop(null)` → `pop()` and `maxLines: null` removed).

## Test Results
```
flutter test: +198: All tests passed!
```
198 tests, all passed. Full suite run after Cycle 2 changes.

## Code Efficiency/Bloat Check

**Helper search**: Searched `lib/` for existing scroll-header helpers — none found. All changes are pure widget tree repositioning.

**`gig_notes_sheet.dart` / `rehearsal_notes_sheet.dart` — extra SizedBox after Divider**: The original visual gap between the Divider and the notes text was provided by the scroll view's `vertical: space16` top padding, which applied to the text as the first child of the scroll. After moving the header items inside, the scroll's top padding now applies to the first item in the Column (the moved SizedBox(16)), not the notes Text. A `const SizedBox(height: Spacing.space16)` was added after the Divider to preserve this gap — required to preserve behavior, not new functionality.

**`day_detail_bottom_sheet.dart` — ListView.separated → for-loop in Column**: The `ListView.separated` with `shrinkWrap: true` inside a `ConstrainedBox(maxHeight: 0.5 * screen)` was replaced with a Column + for-loop. The for-loop uses `if (i > 0) SizedBox(space12)` as separator, matching `separatorBuilder` behaviour exactly. The `shrinkWrap: true` ListView inside a `ConstrainedBox` was the "old" scroll pattern the plan explicitly replaces with `Flexible → SingleChildScrollView`. No `package:collection` equivalent for indexed for-loop-with-separator; hand-rolled is idiomatic here.

**`event_editor_drawer.dart` — `_canSave` getter**: `_isEditingExpense` and `widget.viewOnly` are redundant guards in the getter (the footer method already returns early for both), but their inclusion makes the getter a safe standalone predicate, and mirrors the plan's exact spec. Not AI-shaped bloat; consistent with the plan.

**`_ => true` catch-all removed from switch**: The plan showed `_ => true` as a catch-all. `EventType` is an exhaustive 3-value enum; the catch-all is dead code and would trigger an analyzer info warning. Dropped in favour of the 3 explicit cases.

**Line counts net delta (batch 2 files):**
- `song_notes_drawer.dart`: +5 lines (Column wrapper + 2 pre-existing violation fixes)
- `gig_notes_sheet.dart`: +20 lines (Column wrapper + added SizedBox-after-divider)
- `rehearsal_notes_sheet.dart`: +20 lines (same pattern)
- `day_detail_bottom_sheet.dart`: +14 lines (Flexible+ScrollView+Column replacing ConstrainedBox+ListView)
- `event_editor_drawer.dart`: +14 lines (getter + canSave replacement)

All within ±40-line budget per file.

## Verification (manual steps performed)
**Cycle 2:**
- Read each of the 8 files before editing to confirm exact current padding values.
- Confirmed scroll view's own horizontal padding in each file (16px) makes header's inner horizontal padding redundant.
- Confirmed `event_editor_drawer.dart` `_buildStickyHeader` IS inside `SingleChildScrollView(padding: all(16))` via `_buildScrollableBody` — double-padding confirmed; fix applied.
- `flutter analyze` (8 changed files): 0 errors, 0 warnings.
- `flutter test` (full suite): +198 all passed.
- `dart format` (8 files): 0 changed.

**Cycle 1:**
**Batch 1:**
- Confirmed `_buildStickyHeader` is still referenced in `_buildScrollableBody` and not in `build()`'s outer Column.
- Confirmed `_buildDragHandle()` remains in the outer Column in `song_details_bottom_sheet.dart` and `song_enrichment_review_sheet.dart`.
- Confirmed `_buildHeader()` / title Padding appears as first child inside `SingleChildScrollView` Column in all 5 files via grep.

**Batch 2:**
- Confirmed `_buildHeader()` is inside the `SingleChildScrollView` Column in `song_notes_drawer.dart`.
- Confirmed `SizedBox`, gigName/rehearsal `Padding`, `SizedBox`, `Divider` appear as first children in scroll Column in files 7 and 8.
- Confirmed `ConstrainedBox` is gone from `day_detail_bottom_sheet.dart`; `Flexible → SingleChildScrollView` present.
- Confirmed `_canSave` getter added to `event_editor_drawer.dart` and `final canSave = ...` lines removed.
- `dart format` run on all 5 batch-2 files; cosmetic reformatting in `day_detail_bottom_sheet.dart` and `event_editor_drawer.dart`.
- `flutter analyze` (5 files): No issues found.
- `flutter test` (full suite): 198 passed.

## Deviations From Plan
**Cycle 2:** None — all 8 files fixed per W1 specification.

**Cycle 1:**
**Batch 1:**
- `event_editor_drawer.dart` — expense editing path: See Batch 1 report notes. Expense path wrapped with header+divider to preserve full-screen title visibility.

**Batch 2:**
- **Files 7, 8 — extra `SizedBox(height: Spacing.space16)` after Divider**: The plan says to move `SizedBox`, title `Padding`, `SizedBox`, `Divider` as first children. This is done exactly. An additional `const SizedBox(height: Spacing.space16)` was placed after the Divider (not part of the moved items) to preserve the original visual spacing between the Divider and the notes text. Without it, the notes content would immediately follow the Divider with no gap. This is a preserve-behaviour addition, not a new feature.
- **File 9 — `ListView.separated` replaced with Column + for-loop**: The plan says "Flexible → SingleChildScrollView → Column([…event card items or empty state…])". A `ListView.separated` inside a `SingleChildScrollView` causes nested-scroll issues; converting to Column children with explicit separators is the standard approach. The for-loop matches the `separatorBuilder` (space12 between items) and `itemBuilder` exactly.
- **Change 1 — `_ => true` catch-all omitted**: The plan's sample getter included `_ => true` as a catch-all. `EventType` is exhaustive (3 values, all covered); the catch-all is dead code that would trigger an analyzer dead-code warning. Dropped.

## Blockers Encountered
None.

## Ready For QA
Yes

