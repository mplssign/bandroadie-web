# ENGINEER REPORT — sheet-scroll-collapse-header-footer

## Feature Slug
`sheet-scroll-collapse-header-footer`

## Feature Title
Collapse sheet header on scroll-down and hide footer during scroll for maximum vertical space

## Cycle Number
1

## Goal
Build `CollapsingSheetScaffold` and migrate all 20 qualifying sheets/drawers to it:
10 Pattern A (footer-collapse only, header inside scroll body) and 10 Pattern B
(header + footer collapse). Single cycle covers scaffold creation, full test suite,
and all 20 adoptions.

## Architect Tasks Completed
- **Batch 1 — Scaffold + Tests**
  - Created `lib/components/ui/collapsing_sheet_scaffold.dart` with public API:
    `dragHandle`, `header`, `body`, `footer`, `alignment`/`axisAlignment` (see
    Deviations), reduced-motion bypass, >6.0 px strict scroll-direction threshold,
    `NotificationListener<Notification>` for `ScrollMetricsNotification` (see
    Deviations).
  - Created `test/components/ui/collapsing_sheet_scaffold_test.dart` — 11 test cases.

- **Batch 2 — Pattern A ×10 (footer-collapse only, `header: null`)**
  - `add_financial_entry_bottom_sheet.dart` migrated
  - `gig_pay_bottom_sheet.dart` migrated
  - `financial_entry_details_bottom_sheet.dart` migrated; explicit `SingleChildScrollView`
    added at call site (see Deviations)
  - `view_block_out_drawer.dart` migrated
  - `view_gig_drawer.dart` migrated
  - `view_rehearsal_drawer.dart` migrated
  - `band_member_detail_drawer.dart` migrated
  - `contact_detail_drawer.dart` migrated
  - `enrichment_selector_bottom_sheet.dart` migrated
  - `pause_creator.dart` migrated

- **Batch 3 — Pattern B ×10 (header + footer collapse)**
  - `day_detail_bottom_sheet.dart` migrated
  - `gig_notes_sheet.dart` migrated
  - `rehearsal_notes_sheet.dart` migrated
  - `song_notes_drawer.dart` migrated
  - `song_details_bottom_sheet.dart` migrated
  - `song_enrichment_review_sheet.dart` migrated
  - `setlist_picker_bottom_sheet.dart` migrated
  - `add_block_out_drawer.dart` migrated
  - `band_member_edit_drawer.dart` migrated
  - `event_editor_drawer.dart` migrated; header extracted into `header:` slot (collapses
    up); `viewInsets` keyboard padding, view-only/normal footer branches, and
    save/dirty/viewOnly gates all preserved (see Verification)

## Files Created
1. `lib/components/ui/collapsing_sheet_scaffold.dart`
2. `test/components/ui/collapsing_sheet_scaffold_test.dart`

## Files Modified
1. `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
2. `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`
3. `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`
4. `lib/features/calendar/widgets/view_block_out_drawer.dart`
5. `lib/features/gigs/widgets/view_gig_drawer.dart`
6. `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`
7. `lib/features/contacts/widgets/band_member_detail_drawer.dart`
8. `lib/features/contacts/widgets/contact_detail_drawer.dart`
9. `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`
10. `lib/features/setlists/widgets/pause_creator.dart`
11. `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`
12. `lib/features/gigs/widgets/gig_notes_sheet.dart`
13. `lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart`
14. `lib/features/setlists/widgets/song_notes_drawer.dart`
15. `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
16. `lib/features/setlists/widgets/song_enrichment_review_sheet.dart`
17. `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`
18. `lib/features/calendar/widgets/add_block_out_drawer.dart`
19. `lib/features/contacts/widgets/band_member_edit_drawer.dart`
20. `lib/features/gigs/widgets/event_editor_drawer.dart`

**Total touched files: 22** (2 created + 20 modified).

## Analyzer Results
```
flutter analyze (22 touched files):
  0 errors
  0 warnings
  0 infos in newly written code
  (pre-existing info lints in unchanged sections of some modified files —
   all confirmed pre-existing; none introduced by this feature)
```

## Test Results
```
flutter test
  00:XX +206: All tests passed!

  Breakdown:
    195 pre-existing passing tests (unchanged)
    11 new tests in test/components/ui/collapsing_sheet_scaffold_test.dart
    Total: 206/206
```

## Code Efficiency/Bloat Check

**Existing helper search:** Searched `lib/` for collapsing/collapse scroll scaffold
helpers before creating `CollapsingSheetScaffold` — none found. `SheetFooter` and
`showAppBottomSheet` were reused as-is; no modifications to either.

**No new helpers, extensions, utils, or private widget classes** added outside the
scaffold file itself.

**File sizes:** `collapsing_sheet_scaffold.dart` stays within the 500-line target.
Net line count across the 20 modified files is negative (structural simplification
removes per-sheet boilerplate).
`test/components/ui/collapsing_sheet_scaffold_test.dart` is ~539 lines, exceeding the
plan's ~180–260 line budget; the overage is Flutter widget-test boilerplate (pump,
pumpAndSettle, tester scaffolding), not extra scope — all 539 lines serve exactly the
11 plan-required test cases.

**Anti-bloat pass:**
- No `_buildX()` helper methods added in any migration.
- No new providers, repositories, or services.
- No `TODO`/`FIXME`/`debugPrint` left in diff.
- No config flags or enum cases added for future use.

## Verification (manual steps performed)

1. `grep -rl CollapsingSheetScaffold lib/features | wc -l` → **20** (confirms all 20
   feature files use the scaffold).
2. Outer wrappers preserved **outside** the scaffold in every file that had them:
   - `PopScope` (unsaved-changes back-press guard) — confirmed present and wrapping
     the scaffold in all Pattern B files that had it (`song_notes_drawer.dart`,
     `song_details_bottom_sheet.dart`, `song_enrichment_review_sheet.dart`).
   - Entrance `AnimatedBuilder` (sheet slide-in animation) — confirmed wrapping the
     scaffold in `pause_creator.dart` (line 156) and equivalently in Pattern B sheets.
   - Keyboard `viewInsets.bottom` padding — confirmed as outer `Container`/`Padding`
     wrapping the scaffold in `add_financial_entry_bottom_sheet.dart`,
     `enrichment_selector_bottom_sheet.dart`, `pause_creator.dart`, and
     `event_editor_drawer.dart`.
   - Outer `Container`/`Material` chrome — preserved outside the scaffold where present.
3. Reduced-motion bypass, keyboard-suppression logic, and anti-flicker behavior live
   **inside** `CollapsingSheetScaffold`, not duplicated per sheet.
4. `event_editor_drawer.dart` — header extracted into `header:` slot (collapses up on
   scroll-down); view-only/normal footer branches, `viewInsets` keyboard inset, and
   save/dirty/viewOnly gates all preserved.
5. Pattern A files: `header: null` on all 10 (title remains inside scroll body).
6. Pattern B files: `header:` slot populated on all 10.
7. `flutter test test/components/ui/collapsing_sheet_scaffold_test.dart` → 11/11 pass.
8. `flutter test` (full suite) → 206/206 pass.
9. No Off-Limits files (`sheet_footer.dart`, `app_bottom_sheet.dart`) touched.

## Deviations From Plan

1. **`NotificationListener<Notification>` instead of `NotificationListener<ScrollMetricsNotification>`.**
   Plan referenced `ScrollMetricsNotification` directly. Flutter's `ScrollMetricsNotification`
   is a subtype of `Notification` but not of `ScrollNotification`, so it does not flow through
   a `ScrollNotification`-typed listener. Using the broader `Notification` base type and
   filtering by `is ScrollUpdateNotification || is ScrollMetricsNotification` inside the
   handler captures both scroll-delta events and initial-metrics events without false positives.
   Behavior is identical to what the plan described; the type parameter is the only difference.

2. **`alignment` / `axisAlignment` naming.**
   Plan's proposed API used a single `axisAlignment` parameter. Implementation exposes
   `alignment` (an `Alignment` value controlling footer slide direction) with the equivalent
   `Alignment.bottomCenter` default. Functionally identical; naming is marginally clearer for
   callers who may want to customise direction.

3. **Strict >6.0 px threshold (not ≥6.0).**
   Plan specified a 6 px scroll-delta threshold to debounce micro-jitter. Implementation
   uses `> 6.0` (strict greater-than) rather than `>= 6.0`. Effectively identical at
   runtime; strict inequality avoids toggling on exactly-6 px events from trackpad inertia.

4. **`financial_entry_details_bottom_sheet.dart` — caller provides `SingleChildScrollView`.**
   The scaffold's `body:` slot is not auto-wrapped in a scroll view (it uses
   `Expanded(child: NotificationListener(child: widget.body))`). This file's content was
   not already wrapped, so a `SingleChildScrollView` was added at the call site as `body:`.
   Identical UX outcome — content scrollable on small screens; chrome stays visible when
   content fits.

5. **Drag-handle extraction from inside scroll content (Pattern A: 4 files).**
   In `add_financial_entry`, `gig_pay`, `enrichment_selector`, and `pause_creator` the drag
   handle originally lived inside the `SingleChildScrollView` child. It was moved to the
   `dragHandle:` slot. The trailing `SizedBox(height: space20)` below each was also removed;
   the scroll view's existing top padding provides equivalent visual separation.

## Blockers Encountered
None.

## Ready For QA
Yes
