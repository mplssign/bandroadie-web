# QA Report — Forui Card Consolidation

**Feature Slug:** `forui-card-consolidation`  
**QA Date:** 2026-08-14  
**QA Agent:** AI Assistant  
**Branch:** `feature/forui-card-consolidation`  
**Engineer:** AI Assistant

---

## Executive Summary

**Verdict:** ✅ **APPROVED FOR DEVICE TESTING**

Code-level validation complete. All 18 files migrated successfully to AppCard facade, gradient animations removed, border rendering corrected, and static analysis clean (0 errors). Three unused import issues found and corrected during QA. Code is ready for mandatory device testing per Architect plan's HIGH regression risk assessment.

**Remaining gate:** Manual device testing required to confirm gesture preservation (drag-reorder, swipe-to-delete) and visual redesign acceptance before final APPROVED FOR MERGE.

---

## Validation Summary

### ✅ Code Quality — PASS

- **Analyzer:** 0 errors, 6 pre-existing warnings (test files + bulk_entry_screen), 3 info messages
- **Change set:** 18 files modified (17 cards + 1 facade), 1 file deleted (animated_gradient_border.dart)
- **Net impact:** -403 lines (gradient code removal)
- **Import hygiene:** Fixed 2 unused `BrandColors` imports in potential_gig_card.dart and rehearsal_card.dart (leftover from gradient removal)
- **Import correction:** Restored missing `brand_colors.dart` import in setlist_card.dart (required for `context.colors` extension)

### ✅ Architectural Compliance — PASS

- All 17 target card widgets migrated to AppCard facade
- AppCard extended with `height`, `borderRadius`, and `border` parameters as planned
- All gradient animations removed (AnimatedGradientBorder, CustomPaint, AnimationController for gradients)
- No off-limits files modified
- No opportunistic refactoring or scope creep

### ✅ Border Rendering Fix — CONFIRMED IN CODE

Engineer's post-implementation fix correctly addressed the border radius mismatch issue identified during Implementation Gate:

- **Before fix:** Nested `Container` with border inside `AppCard` → square border corners
- **After fix:** Border moved to `AppCard.border` parameter → passed through `DecorationDelta.boxDelta(borderRadius:..., border:...)` → cohesive rendering

**Affected files corrected:**

- [song_card.dart](lib/features/setlists/widgets/song_card.dart) — rose border (1.5px)
- [reorderable_song_card.dart](lib/features/setlists/widgets/reorderable_song_card.dart) — slate border (1.5px)
- [member_card.dart](lib/features/members/widgets/member_card.dart) — rose border (2px)

**Verification:** Code inspection confirms borders are now applied at the `FCard` decoration level via Forui's `DecorationDelta.boxDelta()`, ensuring border and borderRadius render together. Visual confirmation pending device testing.

### ✅ Gesture Structure Preservation — CONFIRMED IN CODE

Examined all 3 gesture-critical surfaces. Drag-reorder and swipe gesture patterns preserved in code:

#### 1. Song Cards (Drag-Reorder)

**File:** [reorderable_song_card.dart](lib/features/setlists/widgets/reorderable_song_card.dart)

- ✅ Left 36px strip (`SongCardLayout.contentLeftPadding`) wrapped in `ReorderableDragStartListener`
- ✅ Content area wrapped in `Listener` with `onPointerDown: (_) {}` to absorb pointer events → prevents drag from bubbling
- ✅ `Stack` + `Positioned` structure preserved
- ✅ Drag handle icon positioned at `left: 6px, top: 13px`

**Runtime validation required:** Confirm left-edge drag initiates reorder, tapping song content does not trigger drag.

#### 2. Setlist Cards (Drag-Reorder)

**File:** [setlist_card.dart](lib/features/setlists/widgets/setlist_card.dart)

- ✅ Draggable variant: `Row` layout with `ReorderableDragStartListener` wrapping left edge (36px SizedBox)
- ✅ Content area wrapped in separate `GestureDetector` with `onTap` → only content is tappable, only handle is draggable
- ✅ Non-draggable variant (Catalog): No drag handle rendered, entire card tappable
- ✅ Tap animation preserved via `AnimatedBuilder` + `Transform.scale`

**Runtime validation required:** Confirm left-edge drag initiates reorder, Catalog setlist rejects reorder, tapping content does not trigger drag.

#### 3. Band Member Cards (Drag-Reorder)

**File:** [reorderable_band_member_card.dart](lib/features/contacts/widgets/reorderable_band_member_card.dart)

- ✅ Left strip (`_contentLeftPadding = 36px`) wrapped in `ReorderableDragStartListener`
- ✅ Content area wrapped in `Listener` with `onPointerDown: (_) {}` to absorb pointer events
- ✅ `Stack` + `Positioned` structure preserved
- ✅ Drag handle icon positioned at `left: 6px`

**Runtime validation required:** Confirm left-edge drag initiates reorder, tapping member content does not trigger drag.

#### 4. Swipe Gestures (Dismissible Wrappers)

**Files NOT modified per plan:**

- `swipeable_setlist_card.dart` — Dismissible wrapper unchanged
- `setlist_detail_screen.dart` — Dismissible wrapper for songs unchanged

**Runtime validation required:** Confirm swipe left/right on songs and setlists triggers delete/duplicate/move actions.

#### 5. Tap Animations (AnimatedCardPressable Wrappers)

**Files using AnimatedCardPressable:**

- [venue_card.dart](lib/features/contacts/widgets/venue_card.dart)
- [contact_card.dart](lib/features/contacts/widgets/contact_card.dart)
- [band_member_card.dart](lib/features/contacts/widgets/band_member_card.dart) (non-reorderable variant)

**Files with inline tap animation:**

- [empty_section_card.dart](lib/features/home/widgets/empty_section_card.dart) — AnimationController for button scale
- All gig/rehearsal/setlist cards — inline `AnimatedBuilder` + `Transform.scale`

**Runtime validation required:** Confirm tap animation plays on press/release.

### ⚠️ Visual Redesign — PENDING SUBJECTIVE APPROVAL

Gradient removal completed as specified. Expected visual changes:

| Card Type             | Before                                           | After                           | Impact                     |
| --------------------- | ------------------------------------------------ | ------------------------------- | -------------------------- |
| Potential Gig         | Orange→rose animated gradient background         | Neutral FCard                   | Major appearance change    |
| Confirmed Gig         | Rotating blue→rose gradient border (CustomPaint) | Neutral FCard with slate border | Major appearance change    |
| Rehearsal (potential) | Orange→rose gradient background                  | Neutral FCard                   | Major appearance change    |
| Rehearsal (confirmed) | Blue→purple gradient background                  | Neutral FCard                   | Major appearance change    |
| Setlist               | AnimatedGradientBorder wrapper (orange→rose)     | Neutral FCard                   | Major appearance change    |
| Member                | Rose gradient overlay in Stack                   | Neutral FCard with rose border  | Moderate appearance change |

**Catalog setlist:** Star icon preserved, gradient removed → now appears identical to other setlists except for star indicator.

**QA note per Architect plan:** These 5 cards will look "significantly different" with neutral appearance. Design team must approve before merge. If new appearance "seems too plain or hurts readability," flag to Tony rather than auto-approving.

**Pending:** Visual confirmation on-device (all platforms: iOS, Android, macOS, Web).

### ✅ Content Layout — CONFIRMED IN CODE

Reviewed all 17 migrated cards for layout preservation:

- ✅ No clipped/truncated text found in code (all `Text` widgets have `maxLines` + `overflow: TextOverflow.ellipsis`)
- ✅ No layout structure changes beyond gradient/border removal
- ✅ Spacing, padding, and content positioning preserved
- ✅ Complex cards (potential gig, rehearsal) retain multi-date navigation, inline availability buttons, keyboard navigation structures
- ✅ Shimmer animation in [member_card_skeleton.dart](lib/features/members/widgets/member_card_skeleton.dart) preserved

**Runtime validation required:** Confirm no debug console overflow warnings, no visual clipping on-device.

### ✅ Cross-Platform Compatibility — CONFIRMED IN CODE

- No platform-specific code added
- AppCard facade uses Forui's FCard (already cross-platform)
- No iOS/Android/Web/macOS conditional logic introduced

**Runtime validation required:** Visual appearance consistency across iOS, Android, macOS, Web per Architect Test 8.

---

## Files Modified (Code Review)

### Core Facade (1 file)

**[lib/components/ui/app_card.dart](lib/components/ui/app_card.dart)**

✅ **Extended with 3 new optional parameters:**

- `height` (double?) — for fixed-height song cards (121px)
- `borderRadius` (BorderRadius?) — for custom card radii (8, 12, 16, 20, 24)
- `border` (BoxBorder?) — for rose/slate accent borders

✅ **Implementation:** Parameters passed via `FCardStyleDelta.delta()` with `DecorationDelta.boxDelta()` for border + borderRadius cohesion.

✅ **Backward compatible:** Existing usage in `setlist_detail_screen.dart` unchanged.

### Card Widgets (17 files)

#### Low-Risk Simple Cards (6 files) — Reviewed ✅

1. **[empty_section_card.dart](lib/features/home/widgets/empty_section_card.dart)** — Container → AppCard, button animation controller preserved
2. **[calendar_event_card.dart](lib/features/calendar/widgets/calendar_event_card.dart)** — Container → AppCard(borderRadius: 12), date badge + event indicator preserved
3. **[pending_invite_card.dart](lib/features/members/widgets/pending_invite_card.dart)** — Container → AppCard(borderRadius: 16), status badge preserved
4. **[band_member_card.dart](lib/features/contacts/widgets/band_member_card.dart)** — Container → AppCard(borderRadius: 16), AnimatedCardPressable wrapper preserved
5. **[venue_card.dart](lib/features/contacts/widgets/venue_card.dart)** — Container → AppCard(borderRadius: 16), AnimatedCardPressable wrapper preserved
6. **[contact_card.dart](lib/features/contacts/widgets/contact_card.dart)** — Container → AppCard(borderRadius: 16), AnimatedCardPressable wrapper preserved

#### Song Cards (2 files) — Reviewed ✅

7. **[song_card.dart](lib/features/setlists/widgets/song_card.dart)** — Container → AppCard(height: 121, borderRadius: 8, border: rose 1.5px), metrics row preserved, drag handle icon preserved
8. **[reorderable_song_card.dart](lib/features/setlists/widgets/reorderable_song_card.dart)** — Container → AppCard(height: 121, borderRadius: 8, border: slate 1.5px), drag handle Stack + Listener preserved

#### Setlist Cards (1 file) — Reviewed ✅

9. **[setlist_card.dart](lib/features/setlists/widgets/setlist_card.dart)** — AnimatedGradientBorder removed, Container → AppCard(borderRadius: 20), draggable variant uses Row + ReorderableDragStartListener, Catalog star icon preserved

#### Member Cards (3 files) — Reviewed ✅

10. **[member_card.dart](lib/features/members/widgets/member_card.dart)** — Gradient overlay removed from Stack, Container → AppCard(borderRadius: 24, border: rose 2px), role pills + contact rows preserved
11. **[reorderable_band_member_card.dart](lib/features/contacts/widgets/reorderable_band_member_card.dart)** — Container → AppCard(borderRadius: 16), drag handle Stack + Listener preserved
12. **[member_card_skeleton.dart](lib/features/members/widgets/member_card_skeleton.dart)** — Container → AppCard(borderRadius: 24), shimmer AnimationController + gradient animation preserved

#### Gig Cards (2 files) — Reviewed ✅

13. **[potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart)** — AnimatedBuilder + gradient controller removed, Container → AppCard(borderRadius: 8), multi-date navigation + YES/NO buttons + keyboard FocusNode preserved
14. **[confirmed_gig_card.dart](lib/features/home/widgets/confirmed_gig_card.dart)** — CustomPaint + \_GradientBorderPainter removed, rotation AnimationController removed, Container → AppCard(borderRadius: 8), content layout preserved

#### Rehearsal Cards (2 files) — Reviewed ✅

15. **[rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart)** — AnimatedBuilder + gradient controller removed for both potential (orange→rose) and confirmed (blue→purple) variants, Container → AppCard(borderRadius: 16), multi-date navigation + YES/NO buttons + keyboard FocusNode preserved
16. **[load_more_rehearsals_card.dart](lib/features/home/widgets/load_more_rehearsals_card.dart)** — Container → AppCard(borderRadius: 16), primary color accent preserved inside card content

### Files Deleted (1 file)

**[lib/features/setlists/widgets/animated_gradient_border.dart](lib/features/setlists/widgets/animated_gradient_border.dart)** — Deleted after confirming zero references with grep. SetlistCard was its only consumer.

---

## Issues Found and Corrected During QA

### Issue 1: Unused BrandColors Imports (Analyzer Warnings)

**Found in:**

- [potential_gig_card.dart](lib/features/home/widgets/potential_gig_card.dart):8
- [rehearsal_card.dart](lib/features/home/widgets/rehearsal_card.dart):8

**Root cause:** Imports leftover from gradient removal. Files used `BrandColors.primaryOrange`, `BrandColors.primary`, etc. for gradient colors. After migration to AppCard, gradient code deleted but imports remained.

**Action taken:** Removed unused imports.

**Status:** ✅ Fixed

---

### Issue 2: Missing BrandColors Import (Analyzer Errors)

**Found in:**

- [setlist_card.dart](lib/features/setlists/widgets/setlist_card.dart):94, 160 — `undefined_getter: context.colors`

**Root cause:** QA initially removed `brand_colors.dart` import during cleanup of Issue 1, not recognizing that `BrandColorsX` extension provides `context.colors` getter used throughout the file.

**Lesson:** `import 'package:bandroadie/app/theme/brand_colors.dart';` is required for `context.colors` extension, even if `BrandColors` class itself is not directly referenced.

**Action taken:** Restored `brand_colors.dart` import to setlist_card.dart.

**Status:** ✅ Fixed

---

### Issue 3: Flutter Analyzer Info Message (Style Suggestion)

**Found in:**

- [reorderable_song_card.dart](lib/features/setlists/widgets/reorderable_song_card.dart):190 — `sized_box_for_whitespace: Use a 'SizedBox' to add whitespace`

**Context:** `Container(width: double.infinity)` used as wrapper inside AppCard. Analyzer suggests `SizedBox` for empty containers.

**Action taken:** None. This is a pre-existing style suggestion, not a functional issue. Container is used for width constraint, not just whitespace.

**Status:** ℹ️ Info message (non-blocking)

---

## Regression Risk Assessment

**QA Classification:** ⚠️ **HIGH RISK (Confirmed)**

Architect plan rated this HIGH due to:

1. **Scope size:** 18 files modified (largest Forui retrofit to date)
2. **Visual redesign magnitude:** 5 cards lose defining gradients
3. **Gesture interaction risk:** 3 surfaces with drag-reorder + swipe
4. **Shared UI wrapper component:** AppCard extended — prior history shows constraint-composition bugs only visible on-device
5. **High-traffic surfaces:** Home screen, Setlists tab, Catalog, Members screen

**QA agrees with HIGH risk rating.** Code-level validation passed, but runtime gesture and visual validation mandatory before merge.

---

## Completeness Check

### Architect Task Breakdown — All 13 Tasks Completed ✅

- [x] Task 1: Extend AppCard facade (height, borderRadius, border)
- [x] Task 2: Migrate 6 low-risk simple cards
- [x] Task 3: Migrate song_card.dart
- [x] Task 4: Migrate reorderable_song_card.dart (HIGH-RISK)
- [x] Task 5: Migrate setlist_card.dart (HIGH-RISK)
- [x] Task 6: Delete AnimatedGradientBorder widget
- [x] Task 7: Migrate reorderable_band_member_card.dart (HIGH-RISK)
- [x] Task 8: Migrate potential_gig_card.dart and confirmed_gig_card.dart
- [x] Task 9: Migrate rehearsal_card.dart
- [x] Task 10: Migrate load_more_rehearsals_card.dart
- [x] Task 11: Migrate member_card.dart and member_card_skeleton.dart
- [x] Task 12: Final verification pass (flutter analyze 0 errors)
- [x] Task 13: Create ENGINEER_REPORT.md

### Edge Cases — Reviewed ✅

- ✅ Catalog setlist: Star icon preserved, no drag handle rendered (per `isDraggable=false`)
- ✅ Long song titles: `maxLines: 2` + `overflow: TextOverflow.ellipsis` preserved
- ✅ Long venue names: `maxLines: 1` + `overflow: TextOverflow.ellipsis` preserved
- ✅ Member card skeleton: Shimmer animation preserved
- ✅ Empty state card: Button animation preserved

---

## Database Safety

**Status:** ✅ **Not Applicable**

Pure client-side UI migration. No database, RLS, RPC, migration, or backend changes.

---

## Test Results

### Static Analysis — PASS ✅

```bash
flutter analyze
```

**Result:** 0 errors, 6 warnings (pre-existing), 3 info messages

**Pre-existing warnings (not introduced by this feature):**

- bulk_entry_screen.dart: unused import (supabase_flutter), unused variable (processedCount)
- original_song_screen.dart: use_build_context_synchronously
- test files: unused variables (submittedValue, editingCompleted, tapped)

**Info messages:**

- bulk_entry_screen.dart: use_build_context_synchronously (pre-existing)
- reorderable_song_card.dart: sized_box_for_whitespace (style suggestion, non-blocking)

### Unit Tests — NOT RUN

Per Engineer report and QA.md Phase 9:

> Run tests only if: The Architect plan requires them, the Engineer report says they were run, the changed area has relevant test coverage.

**Status:** Architect plan did not require test execution. Minimal test coverage exists for card widgets. Tests were not modified.

### Device Testing — REQUIRED, NOT YET PERFORMED

Per Architect plan:

> **Known constraint:** Several target surfaces have gesture-based functionality (drag-reorder, swipe left/right actions) that must survive the migration unchanged. Prior history shows shared UI wrapper components can cause constraint-composition bugs only visible on-device, so **QA must include device/visual confirmation before APPROVED**.

**Required validation:**

#### Test 1: Song Card Drag-Reorder (iOS/Android)

- [ ] Open Setlist detail screen with 5+ songs
- [ ] Drag song by left edge (36px strip) to reorder
- [ ] Verify drag initiates smoothly, no hitching
- [ ] Tap song content (non-drag area) to edit
- [ ] Verify tap does not trigger drag

#### Test 2: Song Card Swipe Actions (iOS/Android)

- [ ] Open Setlist detail screen
- [ ] Swipe song left → delete confirmation appears
- [ ] Swipe song right → move/copy modal appears
- [ ] Verify no gesture conflicts with drag handle

#### Test 3: Setlist Card Drag-Reorder (iOS/Android)

- [ ] Open Setlists tab with 3+ setlists
- [ ] Drag non-Catalog setlist by left edge to reorder
- [ ] Verify drag initiates smoothly
- [ ] Tap setlist content to open detail
- [ ] Verify tap does not trigger drag

#### Test 4: Setlist Card Swipe Actions (iOS/Android)

- [ ] Open Setlists tab
- [ ] Swipe non-Catalog setlist left → delete confirmation
- [ ] Swipe non-Catalog setlist right → duplicate modal
- [ ] Verify Catalog setlist rejects swipe and reorder

#### Test 5: Band Member Card Drag-Reorder (iOS/Android)

- [ ] Open Members screen with 3+ members
- [ ] Drag member by left edge to reorder
- [ ] Verify drag initiates smoothly
- [ ] Tap member content to open profile
- [ ] Verify tap does not trigger drag

#### Test 6: Visual Redesign Acceptance (All Platforms)

- [ ] Home screen: Potential gig cards (neutral, no orange gradient)
- [ ] Home screen: Confirmed gig cards (neutral, no rotating gradient border)
- [ ] Home screen: Rehearsal cards (neutral, no blue/purple/orange gradients)
- [ ] Setlists tab: Setlist cards (neutral, no gradient borders)
- [ ] Setlist detail: Catalog indicator (star icon visible)
- [ ] Members screen: Member cards (neutral, no gradient overlay, rose border visible)
- [ ] Confirm neutral appearance is acceptable (not too plain, readability preserved)

#### Test 7: Border Rendering (All Platforms)

- [ ] Song cards: Rose border (1.5px) follows rounded corners (8px radius), no square artifacts
- [ ] Reorderable song cards: Slate border (1.5px) follows rounded corners (8px radius), no square artifacts
- [ ] Member cards: Rose border (2px) follows rounded corners (24px radius), no square artifacts

#### Test 8: Cross-Platform Pass (iOS/Android/Web/macOS)

- [ ] All cards render correctly on iOS
- [ ] All cards render correctly on Android
- [ ] All cards render correctly on Web (Chrome)
- [ ] All cards render correctly on macOS
- [ ] Gesture behavior consistent across platforms

#### Test 9: Content Layout Verification (All Platforms)

- [ ] No clipped/truncated text in any card
- [ ] No debug console overflow warnings
- [ ] Long titles display ellipsis correctly
- [ ] Skeleton shimmer animation plays during member card load
- [ ] Empty state card button press animation works

#### Test 10: Tap Animation Verification (All Platforms)

- [ ] Venue cards: Tap animation plays
- [ ] Contact cards: Tap animation plays
- [ ] Band member cards (non-reorderable): Tap animation plays
- [ ] Gig/rehearsal/setlist cards: Inline tap animation plays

---

## Pass Criteria

### Code Quality — ✅ MET

- ✅ 0 analyzer errors
- ✅ No new warnings introduced
- ✅ All imports cleaned up
- ✅ Code compiles successfully

### Architectural Compliance — ✅ MET

- ✅ All 17 target cards migrated to AppCard
- ✅ All gradient animations removed
- ✅ AppCard facade extended per plan
- ✅ No off-limits files modified
- ✅ No scope creep

### Device Testing — ⏳ PENDING

- ⏳ Gesture preservation (Tests 1-5)
- ⏳ Visual redesign acceptance (Test 6)
- ⏳ Border rendering (Test 7)
- ⏳ Cross-platform compatibility (Test 8)
- ⏳ Content layout verification (Test 9)
- ⏳ Tap animation verification (Test 10)

---

## Final Verdict

**Status:** ✅ **APPROVED FOR DEVICE TESTING**

### Summary

Code-level QA **PASS** with all issues corrected:

- ✅ Static analysis clean (0 errors)
- ✅ 18 files migrated correctly
- ✅ Gradient removal complete
- ✅ Gesture structure preserved in code
- ✅ Border rendering corrected
- ✅ Content layout preserved
- ✅ No architectural violations

### Remaining Gate

Per Architect plan's HIGH regression risk assessment and explicit requirement:

> **device/visual confirmation is required before you can mark this APPROVED. Do not approve on code review alone.**

**Device testing required before APPROVED FOR MERGE:**

- Gesture regression verification (drag-reorder, swipe-to-delete)
- Visual redesign acceptance (5 de-gradiented cards)
- Border rendering visual confirmation (3 corrected cards)
- Cross-platform appearance consistency (iOS/Android/Web/macOS)

### Recommendation

**Proceed to device testing.** Code quality gate passed. Manual validation of gesture behavior and visual redesign required per Architect plan before merge approval.

---

## QA Sign-Off

**QA Agent:** AI Assistant  
**Date:** 2026-08-14  
**Validation Level:** Code analysis (comprehensive), runtime behavior (not validated)  
**Next Step:** Device testing by Tony or designated tester

---

## Appendix: Validation Methodology

### What QA Validated (Code Analysis)

- ✅ All 18 files read and reviewed
- ✅ AppCard facade extension implementation
- ✅ Gradient removal (AnimatedBuilder, CustomPaint, AnimationController deletions confirmed)
- ✅ Border fix implementation (DecorationDelta.boxDelta usage confirmed)
- ✅ Gesture structure preservation (ReorderableDragStartListener, Listener wrappers, Stack layouts confirmed)
- ✅ Content layout preservation (Text widgets, spacing, padding confirmed)
- ✅ Import dependencies resolved
- ✅ Flutter analyzer output reviewed
- ✅ Git diff reviewed for scope compliance

### What QA Could Not Validate (Runtime Behavior)

- ❌ Drag-reorder gesture initiation and smoothness
- ❌ Swipe-to-delete gesture triggering
- ❌ Tap animation playback
- ❌ Visual appearance of neutral cards (gradient removal acceptance)
- ❌ Border rendering on-device (rounded corner artifacts)
- ❌ Content overflow/clipping on-device
- ❌ Skeleton shimmer animation playback
- ❌ Cross-platform appearance consistency
- ❌ Performance impact (if any)

### Validation Standard

Per QA.md Phase 6:

> State clearly: was this validated via code-path analysis only, or was runtime behavior exercised?

**This QA report:** Code-path analysis only. Runtime behavior not exercised. Device testing required before final merge approval.
