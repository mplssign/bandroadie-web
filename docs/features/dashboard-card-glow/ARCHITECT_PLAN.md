# Architect Plan — Dashboard Card Visual Treatment (Revised)

**Feature Identifier:** `feature/dashboard-card-glow`  
**Type:** feature (design revision)  
**Branch:** `feature/forui-card-consolidation` (amending unpushed commit `0d27ac7`)  
**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-08-15 (revised 2026-08-16)  
**Revision:** 2 — replaces box-shadow glow with solid borders (confirmed cards) and animated chasing-beam effect (potential cards)

---

## Executive Summary

**Design Revision Context:**  
The initial box-shadow glow implementation (commit `0d27ac7`) was shipped and tested on-device. Visual inspection revealed the glow effect is too subtle and not visually effective for at-a-glance card type identification. This revision replaces the box-shadow approach with:

1. **Confirmed cards (rehearsals/gigs):** Solid color-coded borders, no shadows, no animations — clean and stable
2. **Potential cards (rehearsals/gigs):** Amber border + subtle ambient glow + animated "chasing beam" effect (a moving arc of brighter amber light traveling around the border perimeter)

**Approach:**

- Confirmed cards: straightforward border swap (use `AppCard.border` param, which already exists)
- Potential cards: recover and adapt `AnimatedGradientBorder` widget (deleted in commit `ff6689e`, was originally multi-color for setlist cards) to create a single-color amber "comet" effect

**Root Cause Confidence:** N/A (feature revision, not a bug fix)  
**Database Impact:** None  
**Migration Required:** No  
**Affected Platforms:** Web, iOS, Android, macOS

---

## Problem Description

After the Forui card consolidation (commits `ff6689e` and `ae65ab2`), dashboard cards used neutral AppCard styling with no visual type differentiation. The initial glow implementation (commit `0d27ac7`) added color-coded box-shadow glows to address this, but on-device testing showed the effect is insufficiently visible—users still cannot distinguish card types at a glance.

**User Impact:**  
Users scanning the home dashboard cannot quickly distinguish:

- Rehearsals from gigs
- Confirmed events from potential events

**Design Goal:**  
Provide clear, immediate visual type identification without overwhelming the neutral card surfaces. Confirmed cards should feel stable and definitive; potential cards should feel dynamic and awaiting response.

---

## Expected Behavior (Revised Design Spec)

### Confirmed Rehearsal Cards (`rehearsal_card.dart`, confirmed state)

- **Border:** Solid blue (`#2563EB`, 1.5px width)
- **Shadow:** None
- **Animation:** None
- **Rationale:** Stable, confirmed event—no need for visual motion

### Confirmed Gig Cards (`confirmed_gig_card.dart`)

- **Border:** Solid green (`#22C55E`, 1.5px width)
- **Shadow:** None
- **Animation:** None
- **Rationale:** Stable, confirmed event—no need for visual motion

### Potential Rehearsal Cards (`rehearsal_card.dart`, potential state)

- **Border:** Amber (`#F59E0B`, 1.5px width)
- **Ambient Glow:** Subtle box-shadow (amber @ 20% opacity, `blurRadius: 6`, `spreadRadius: 2`)
- **Animated Effect:** Chasing beam—a brighter arc of amber light continuously travels around the border perimeter (comet/spotlight effect, not a uniform ring)
- **Rationale:** Dynamic, awaiting response—animation draws attention without being distracting

### Potential Gig Cards (`potential_gig_card.dart`)

- **Border:** Amber (`#F59E0B`, 1.5px width)
- **Ambient Glow:** Subtle box-shadow (amber @ 20% opacity, `blurRadius: 6`, `spreadRadius: 2`)
- **Animated Effect:** Chasing beam (same as potential rehearsals)
- **Rationale:** Consistent with potential rehearsal treatment

### Out of Scope (Unchanged)

- **Catalog setlist card** (`setlist_card.dart`): pulsating rose glow stays as-is (separate feature, unrelated to dashboard cards)

---

## Current Code Analysis

### 1. Existing Box-Shadow Implementation (Commit `0d27ac7`)

All four dashboard card widgets currently use `AppCard.boxShadow` param:

**RehearsalCard (`lib/features/home/widgets/rehearsal_card.dart`):**

- Line 295 (potential state): `boxShadow: [BoxShadow(color: Color(0x33F59E0B), blurRadius: 6, spreadRadius: 4)]`
- Line 529 (confirmed state): `boxShadow: [BoxShadow(color: Color(0x332563EB), blurRadius: 6, spreadRadius: 4)]`

**ConfirmedGigCard (`lib/features/home/widgets/confirmed_gig_card.dart`):**

- Line 53: `boxShadow: [BoxShadow(color: Color(0x3322C55E), blurRadius: 6, spreadRadius: 4)]`

**PotentialGigCard (`lib/features/home/widgets/potential_gig_card.dart`):**

- Line 290: `boxShadow: [BoxShadow(color: Color(0x33F59E0B), blurRadius: 6, spreadRadius: 4)]`

This implementation must be replaced per the revised design.

### 2. AppCard Component (`lib/components/ui/app_card.dart`)

**Relevant Parameters:**

- `border`: Optional `BoxBorder?` — supports `Border.all(color, width)` (added in commit `ae65ab2`)
- `boxShadow`: Optional `List<BoxShadow>?` — supports ambient glows (added in commit `0d27ac7`)
- Both params pass through to `DecorationDelta.boxDelta()` from Forui

**Key Finding:**  
`AppCard` already supports both `border` and `boxShadow` simultaneously. For potential cards, we can use both—static border for the frame + box-shadow for ambient glow, with the chasing beam effect added as a wrapper widget.

### 3. AnimatedGradientBorder Reference (Deleted File)

**File Path (pre-deletion):** `lib/features/setlists/widgets/animated_gradient_border.dart`  
**Deleted in:** Commit `ff6689e` (card consolidation)  
**Recovered via:** `git show origin/main:lib/features/setlists/widgets/animated_gradient_border.dart`

**Original Implementation:**

- `CustomPaint` widget with `_GradientBorderPainter`
- `AnimationController` driving a rotating `SweepGradient` via `GradientRotation`
- Deterministic speed/direction via `GradientAnimationConfig.fromId(uuid)` — uses hashCode as seed
- Multi-color gradient (was used for setlist cards: rose→purple→blue rotating effect)
- Border width: 2px, configurable
- Duration range: 3-8 seconds, deterministic per ID

**Key Components for Reuse:**

1. `CustomPaint` + `_GradientBorderPainter` pattern
2. `SweepGradient` with `GradientRotation(angle)` for rotation
3. `AnimationController` with `.repeat()` for continuous animation
4. `PaintingStyle.stroke` for border-only rendering (no fill)
5. `RRect.fromRectAndRadius` for rounded rectangle border

**Adaptation Required:**

- Change from multi-color gradient to single-color "comet" effect
- Gradient stops pattern: `[Colors.transparent, amber, Colors.transparent]` with appropriate stop positions
- This creates a moving "spotlight" of brighter amber rather than a full-perimeter static ring
- Keep deterministic speed via ID hash (use `gig.id` or `rehearsal.id`)

### 4. Color Constants (Already Defined)

From `lib/app/theme/design_tokens.dart` and `lib/app/theme/brand_colors.dart`:

```dart
AppColors.blueAccent = Color(0xFF2563EB);  // blue-600
AppColors.success = Color(0xFF22C55E);     // green-500
BrandColors.warning = Color(0xFFF59E0B);   // amber-500 (dark theme)
```

All required colors are defined. Use inline hex literals for clarity (e.g., `Color(0xFF2563EB)` for blue border).

---

## Proposed Solution

**Approach:**

1. **Confirmed cards (rehearsals/gigs):** Replace `boxShadow` param with `border` param (1.5px solid color)
2. **Potential cards (rehearsals/gigs):** Keep `border` + reduced `boxShadow` (for ambient glow) + wrap `AppCard` output in `AnimatedChasingBorder` widget (new widget, adapted from recovered `AnimatedGradientBorder`)

**Why This Approach:**

**Confirmed Cards:**

- Straightforward param swap—`AppCard.border` already exists and works correctly (proven in commit `ae65ab2`)
- No wrapper widgets needed
- No animation overhead
- Clean, stable visual

**Potential Cards:**

- Wrapper widget pattern keeps `AppCard` unchanged (no new params needed)
- Separates animation logic from card composition
- Reuses proven `AnimatedGradientBorder` architecture (CustomPaint + SweepGradient)
- Deterministic animation speed per event ID prevents visual chaos when multiple potential cards are visible

**Chasing Beam Implementation Details:**

**Widget Name:** `AnimatedChasingBorder`  
**File Path:** `lib/shared/widgets/animated_chasing_border.dart` (new file, shared component)

**Key Design Decisions:**

1. **Single-color comet gradient:**
   - Stop pattern: `[transparent (0.0), transparent (0.3), amber (0.45), amber (0.55), transparent (0.7), transparent (1.0)]`
   - This creates a ~40% arc of visible amber light (10% width at stop 0.45-0.55, with gradual fade-in/out)
   - As the gradient rotates, it reads as a traveling beam, not a static border

2. **Speed determinism:**
   - Use `GradientAnimationConfig.fromId(eventId)` pattern from original widget
   - Duration range: 4-6 seconds (faster than original setlist cards—potential cards need more urgency)
   - Clockwise/counter-clockwise direction randomized per event ID

3. **Integration with AppCard:**
   - `AnimatedChasingBorder` wraps the entire `AppCard` widget tree
   - Uses `CustomPaint` as foreground (paints over the card)
   - `AppCard` itself renders the static amber border + ambient glow via its existing params
   - Chasing beam paints a slightly thicker stroke (2px) over the static border for visibility

4. **Performance:**
   - Single `AnimationController` per card, no nested controllers
   - `shouldRepaint` checks `rotationAngle` only — minimal rebuild overhead
   - Animation runs only when card is visible (no off-screen animation waste)

**Border Width Rationale:**

- 1.5px for confirmed cards: matches existing border contrast fix (commit `ae65ab2`, likely 1-1.5px)
- Check `git show ae65ab2` to confirm exact width used; default to 1.5px if ambiguous
- 2px for chasing beam stroke: needs to be slightly thicker than static border for visibility

**Ambient Glow Tuning (Potential Cards):**

- Original glow: `blurRadius: 6, spreadRadius: 4`
- Revised ambient glow: `blurRadius: 6, spreadRadius: 2` (tighter, more subtle—distinct from animated beam)
- Tony's wording: "slight glow" — keep it understated, let the chasing beam be the primary dynamic indicator

---

## Files to Modify

### 1. `lib/shared/widgets/animated_chasing_border.dart` (NEW FILE)

**Create new shared widget adapted from recovered `AnimatedGradientBorder`.**

**Changes from original:**

- Rename class: `AnimatedGradientBorder` → `AnimatedChasingBorder`
- Remove multi-color gradient support (not needed)
- Hardcode amber color (`Color(0xFFF59E0B)`)
- Change gradient stops to comet pattern (see above)
- Simplify config: duration range 4000-6000ms (vs. original 3000-8000ms)
- Update docs: explain single-color comet effect for potential event cards
- Remove `backgroundColor` param (not used—`AppCard` handles background)
- Remove `gradientColors` param (always amber)
- Keep `borderWidth`, `borderRadius`, and `config` params

**Constructor signature:**

```dart
const AnimatedChasingBorder({
  Key? key,
  required Widget child,
  required ChasingBorderConfig config,  // renamed from GradientAnimationConfig
  double borderWidth = 2.0,
  double borderRadius = 16.0,
});
```

**Gradient stops (comet effect):**

```dart
final gradient = SweepGradient(
  center: Alignment.center,
  colors: const [
    Colors.transparent,
    Colors.transparent,
    Color(0xFFF59E0B), // amber-500
    Color(0xFFF59E0B),
    Colors.transparent,
    Colors.transparent,
  ],
  stops: const [0.0, 0.3, 0.45, 0.55, 0.7, 1.0],
  transform: GradientRotation(rotationAngle),
);
```

### 2. `lib/features/home/widgets/rehearsal_card.dart`

**Change 1 — Confirmed state (\_buildConfirmedCard, line ~529):**

**Before:**

```dart
child: AppCard(
  padding: EdgeInsets.zero,
  borderRadius: BorderRadius.circular(Spacing.cardRadius),
  boxShadow: const [
    BoxShadow(
      color: Color(0x332563EB), // blue-600 @ 20%
      blurRadius: 6,
      spreadRadius: 4,
    ),
  ],
  child: Container(
```

**After:**

```dart
child: AppCard(
  padding: EdgeInsets.zero,
  borderRadius: BorderRadius.circular(Spacing.cardRadius),
  border: Border.all(
    color: const Color(0xFF2563EB), // blue-600
    width: 1.5,
  ),
  child: Container(
```

**Rationale:** Remove glow, add solid blue border. No animation wrapper needed.

**Change 2 — Potential state (\_buildPotentialCard, line ~295):**

**Before:**

```dart
child: AppCard(
  padding: EdgeInsets.zero,
  borderRadius: BorderRadius.circular(Spacing.cardRadius),
  boxShadow: const [
    BoxShadow(
      color: Color(0x33F59E0B), // amber @ 20%
      blurRadius: 6,
      spreadRadius: 4,
    ),
  ],
  child: Container(
```

**After:**

```dart
child: AnimatedChasingBorder(
  config: ChasingBorderConfig.fromId(widget.rehearsal.id),
  borderRadius: Spacing.cardRadius,
  child: AppCard(
    padding: EdgeInsets.zero,
    borderRadius: BorderRadius.circular(Spacing.cardRadius),
    border: Border.all(
      color: const Color(0xFFF59E0B), // amber
      width: 1.5,
    ),
    boxShadow: const [
      BoxShadow(
        color: Color(0x33F59E0B), // amber @ 20%
        blurRadius: 6,
        spreadRadius: 2,  // reduced from 4
      ),
    ],
    child: Container(
```

**Rationale:** Wrap `AppCard` in `AnimatedChasingBorder`. Reduce `spreadRadius` from 4 → 2 for subtler ambient glow. Keep static border + box-shadow + animated beam.

**Import required:** Add `import '../../../shared/widgets/animated_chasing_border.dart';`

### 3. `lib/features/home/widgets/confirmed_gig_card.dart`

**Change — build method (line ~53):**

**Before:**

```dart
child: AppCard(
  padding: EdgeInsets.zero,
  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
  boxShadow: const [
    BoxShadow(
      color: Color(0x3322C55E), // green @ 20%
      blurRadius: 6,
      spreadRadius: 4,
    ),
  ],
  child: Container(
```

**After:**

```dart
child: AppCard(
  padding: EdgeInsets.zero,
  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
  border: Border.all(
    color: const Color(0xFF22C55E), // green-500
    width: 1.5,
  ),
  child: Container(
```

**Rationale:** Remove glow, add solid green border. No animation wrapper needed.

### 4. `lib/features/home/widgets/potential_gig_card.dart`

**Change — build method (line ~290):**

**Before:**

```dart
child: AppCard(
  padding: EdgeInsets.zero,
  borderRadius: BorderRadius.circular(Spacing.cardRadius),
  boxShadow: const [
    BoxShadow(
      color: Color(0x33F59E0B), // amber @ 20%
      blurRadius: 6,
      spreadRadius: 4,
    ),
  ],
  child: Container(
```

**After:**

```dart
child: AnimatedChasingBorder(
  config: ChasingBorderConfig.fromId(widget.gig.id),
  borderRadius: Spacing.cardRadius,
  child: AppCard(
    padding: EdgeInsets.zero,
    borderRadius: BorderRadius.circular(Spacing.cardRadius),
    border: Border.all(
      color: const Color(0xFFF59E0B), // amber
      width: 1.5,
    ),
    boxShadow: const [
      BoxShadow(
        color: Color(0x33F59E0B), // amber @ 20%
        blurRadius: 6,
        spreadRadius: 2,  // reduced from 4
      ),
    ],
    child: Container(
```

**Rationale:** Wrap `AppCard` in `AnimatedChasingBorder`. Reduce `spreadRadius` from 4 → 2 for subtler ambient glow. Keep static border + box-shadow + animated beam.

**Import required:** Add `import '../../../shared/widgets/animated_chasing_border.dart';`

---

## Implementation Tasks

The Engineer must complete these tasks in strict order:

### Phase 1 — Verify Border Width Constant

1. Check commit `ae65ab2` for the border width used in the border-contrast fix:
   ```bash
   git show ae65ab2
   ```
2. If a specific width is documented (e.g., 1px or 1.5px), use that value for all borders in this implementation
3. If ambiguous, default to 1.5px (sufficient contrast without overwhelming the card)
4. Document the chosen value in `ENGINEER_REPORT.md`

### Phase 2 — Create AnimatedChasingBorder Widget

1. Create new file: `lib/shared/widgets/animated_chasing_border.dart`
2. Copy the recovered `AnimatedGradientBorder` implementation as the starting point
3. Rename classes:
   - `AnimatedGradientBorder` → `AnimatedChasingBorder`
   - `GradientAnimationConfig` → `ChasingBorderConfig`
   - `_AnimatedGradientBorderState` → `_AnimatedChasingBorderState`
4. Simplify constructor (remove unused params):
   - Keep: `child`, `config`, `borderWidth`, `borderRadius`
   - Remove: `gradientColors`, `backgroundColor`
5. Update `ChasingBorderConfig.fromId`:
   - Change duration range: 3000-8000ms → 4000-6000ms
   - Keep hash-based determinism and clockwise/counter-clockwise logic
6. Update `_GradientBorderPainter.paint`:
   - Hardcode amber color: `Color(0xFFF59E0B)`
   - Change gradient stops to comet pattern:
     ```dart
     colors: const [
       Colors.transparent,
       Colors.transparent,
       Color(0xFFF59E0B),
       Color(0xFFF59E0B),
       Colors.transparent,
       Colors.transparent,
     ],
     stops: const [0.0, 0.3, 0.45, 0.55, 0.7, 1.0],
     ```
7. Update docs:
   - Class doc: "An animated chasing border for potential event cards (gigs/rehearsals)"
   - Explain comet effect: "A brighter arc of amber light travels around the border perimeter"
   - Note deterministic speed: "Animation speed and direction are derived from the event ID"
8. Verify compile with `flutter analyze`

### Phase 3 — Update Confirmed Cards (No Animation)

Update these two widgets — simple border swap, no wrapper:

**3.1 — rehearsal_card.dart (confirmed state)**

1. Locate `_buildConfirmedCard` method (line ~529)
2. Find the `AppCard` widget with `boxShadow` param
3. Replace `boxShadow: [...]` with `border: Border.all(color: Color(0xFF2563EB), width: 1.5)`
4. No other changes to this method

**3.2 — confirmed_gig_card.dart**

1. Locate `build` method (line ~53)
2. Find the `AppCard` widget with `boxShadow` param
3. Replace `boxShadow: [...]` with `border: Border.all(color: Color(0xFF22C55E), width: 1.5)`
4. No other changes to this method

### Phase 4 — Update Potential Cards (Animated)

Update these two widgets — add wrapper + adjust glow:

**4.1 — rehearsal_card.dart (potential state)**

1. Locate `_buildPotentialCard` method (line ~295)
2. Add import at top of file: `import '../../../shared/widgets/animated_chasing_border.dart';`
3. Find the `AppCard` widget (currently has `boxShadow`)
4. Wrap entire `AppCard` tree in `AnimatedChasingBorder`:
   ```dart
   child: AnimatedChasingBorder(
     config: ChasingBorderConfig.fromId(widget.rehearsal.id),
     borderRadius: Spacing.cardRadius,
     child: AppCard(
       // ... existing AppCard params
     ),
   ),
   ```
5. Update `AppCard` params:
   - Add `border: Border.all(color: Color(0xFFF59E0B), width: 1.5)`
   - Keep `boxShadow` but change `spreadRadius: 4` → `spreadRadius: 2`
6. Verify the `GestureDetector`/`AnimatedScale` hierarchy remains unchanged (wrapper goes inside `AnimatedScale`, wraps `AppCard`)

**4.2 — potential_gig_card.dart**

1. Locate `build` method (line ~290)
2. Add import at top of file: `import '../../../shared/widgets/animated_chasing_border.dart';`
3. Find the `AppCard` widget (currently has `boxShadow`)
4. Wrap entire `AppCard` tree in `AnimatedChasingBorder`:
   ```dart
   child: AnimatedChasingBorder(
     config: ChasingBorderConfig.fromId(widget.gig.id),
     borderRadius: Spacing.cardRadius,
     child: AppCard(
       // ... existing AppCard params
     ),
   ),
   ```
5. Update `AppCard` params:
   - Add `border: Border.all(color: Color(0xFFF59E0B), width: 1.5)`
   - Keep `boxShadow` but change `spreadRadius: 4` → `spreadRadius: 2`
6. Verify the `GestureDetector`/`AnimatedScale` hierarchy remains unchanged

### Phase 5 — Verify No AppCard Changes Required

Confirm that `lib/components/ui/app_card.dart` does NOT need modification:

- It already supports both `border` and `boxShadow` params (added in commits `ae65ab2` and `0d27ac7`)
- Both params already pass through to `DecorationDelta.boxDelta`
- No structural changes needed

If `AppCard` does not already have `boxShadow` param, stop and report blocker to Manager.

### Phase 6 — Run Analyzer

```bash
flutter analyze
```

Must pass with 0 errors. Pre-existing warnings unrelated to this feature are acceptable (document count in `ENGINEER_REPORT.md`).

If new errors appear, fix them before proceeding.

### Phase 7 — Format Code

```bash
flutter format lib/
```

Verify all modified files are properly formatted.

### Phase 8 — Generate Diff

```bash
git diff > dashboard-card-visual-revision.diff
```

Inspect diff to confirm:

- Only 5 files modified (1 new file, 4 edits)
- No unintended changes to other widgets
- No changes to `AppCard` component (should be unchanged)

### Phase 9 — Complete Engineer Report

Update `docs/features/dashboard-card-glow/ENGINEER_REPORT.md`:

- Mark all tasks complete
- Document border width chosen (from Phase 1)
- List all modified files
- Confirm analyzer passed
- Confirm diff surface matches plan
- Document any deviations or blockers (none expected)

---

## System Impact Assessment

| System             | Impact     | Notes                                                |
| ------------------ | ---------- | ---------------------------------------------------- |
| Gigs               | Modified   | Confirmed + potential gig cards visual refresh       |
| Rehearsals         | Modified   | Confirmed + potential rehearsal cards visual refresh |
| Setlists / Catalog | Unaffected | Catalog card pulsating glow stays unchanged          |
| Members / RBAC     | Unaffected | —                                                    |
| Auth / Session     | Unaffected | —                                                    |
| Routing            | Unaffected | —                                                    |
| Performance        | Monitored  | See QA Performance Testing section                   |

---

## Database Impact

**None.**

This is a pure UI change. No migrations, RLS policies, RPC functions, or backend logic affected.

---

## QA Requirements

### Visual Inspection (All Platforms: Web, iOS, Android, macOS)

**Confirmed Rehearsal Cards:**

- [ ] Solid blue border visible (#2563EB, 1.5px)
- [ ] No shadow visible
- [ ] No animation
- [ ] Border does not clip card content
- [ ] Color is saturated enough to distinguish from neutral card background

**Confirmed Gig Cards:**

- [ ] Solid green border visible (#22C55E, 1.5px)
- [ ] No shadow visible
- [ ] No animation
- [ ] Border does not clip card content
- [ ] Color is saturated enough to distinguish from neutral card background

**Potential Rehearsal Cards:**

- [ ] Solid amber border visible (#F59E0B, 1.5px)
- [ ] Subtle ambient amber glow visible (not overpowering)
- [ ] Animated chasing beam effect travels around border perimeter continuously
- [ ] Chasing beam reads as a moving "spotlight" or "comet," not a static ring
- [ ] Chasing beam is brighter than the ambient glow (should be the primary visual indicator)
- [ ] Animation speed feels appropriate (4-6 seconds per rotation)
- [ ] Animation does not stutter or jank during scroll
- [ ] Multiple potential rehearsal cards have different animation speeds/directions (deterministic per ID)

**Potential Gig Cards:**

- [ ] Same visual treatment as potential rehearsal cards (amber border + glow + chasing beam)
- [ ] Animation behavior identical to potential rehearsals
- [ ] Multiple potential gig cards have different animation speeds/directions

**Catalog Setlist Card (Out of Scope — Verify Unchanged):**

- [ ] Pulsating rose glow still present
- [ ] Animation unchanged from previous commit
- [ ] No border added (should remain glow-only)

### Edge Case Testing

**1. Empty States:**

- [ ] Empty rehearsal section shows no cards (no visual artifacts)
- [ ] Empty gig section shows no cards (no visual artifacts)
- [ ] "Load More" pagination card is unaffected (no border/glow added)

**2. Card Scroll Behavior:**

- [ ] Horizontal scroll through confirmed rehearsals (10+ cards) is smooth
- [ ] Horizontal scroll through potential gigs (5+ cards) is smooth
- [ ] Chasing beam animations continue smoothly during scroll
- [ ] No performance degradation with 20+ cards on screen

**3. Screen Edges:**

- [ ] Cards at the left/right edge of horizontal scroll show full border + glow
- [ ] No clipping of shadow or animated beam at screen edges
- [ ] Cards at top of vertical scroll list show full visual treatment

**4. Tap Interaction:**

- [ ] `AnimatedScale` press feedback still works (card scales down on tap)
- [ ] No double-tap delay
- [ ] No visual glitches when tapping during chasing beam animation

**5. Multi-Date Cards (Potential Only):**

- [ ] Chasing beam animation continues while navigating between dates (left/right chevrons)
- [ ] Animation speed/direction stays consistent across date changes
- [ ] No animation restart or flicker when date index changes

### Performance Testing (Release Mode Only)

**Critical:** Test in release mode (`flutter run --release`), NOT debug mode.

**Benchmarks:**

- [ ] Home screen initial load: <500ms (same as before)
- [ ] Scroll through 20+ cards: 60fps, no dropped frames
- [ ] Memory usage: no increase >5% from baseline (check DevTools)
- [ ] CPU usage during scroll: no sustained high CPU (check DevTools)

**Known Acceptable Overhead:**

- Each potential card adds one `AnimationController` (4-6 second duration, continuous)
- Expected CPU impact: minimal (<1% per card in release mode)
- If >10 potential cards are visible simultaneously, monitor for jank

**If Performance Issues Occur:**

- Investigate `shouldRepaint` in `_GradientBorderPainter` (should only repaint on rotation angle change)
- Verify animations pause when cards are off-screen (Flutter should handle automatically)
- Consider adding `RepaintBoundary` around `AnimatedChasingBorder` if repaints are excessive

### Accessibility

- [ ] Color contrast: all border colors pass WCAG AA against dark background (manual check)
- [ ] Animation does not trigger motion sensitivity (speed is slow, 4-6 seconds)
- [ ] No flashing or strobing effects
- [ ] Static borders (confirmed cards) provide sufficient type indication for users who cannot perceive animations

### Dark Mode

- [ ] All colors render correctly in dark mode (app is dark-only, but verify)
- [ ] Amber glow is visible against dark background
- [ ] Chasing beam contrast is sufficient

---

## Acceptance Criteria

This feature is **APPROVED** for commit when:

1. ✅ All QA visual inspection checks pass on all platforms
2. ✅ All QA edge case checks pass
3. ✅ Performance testing shows no regressions (60fps scroll, <500ms load)
4. ✅ `flutter analyze` passes with 0 errors
5. ✅ Git diff matches expected file changes (5 files: 1 new, 4 modified)
6. ✅ `ENGINEER_REPORT.md` is complete and accurate

**Rejection Criteria:**

- Chasing beam animation stutters or janks during scroll
- Ambient glow overwhelms the chasing beam effect
- Confirmed cards still have shadows (design violation)
- Border colors are too faint to distinguish card types
- Performance regression >10% in any benchmark

---

## Commit Message

```
feat(ui): replace dashboard card glow with solid borders + chasing beam animation

Design revision: box-shadow glow was too subtle for on-device visibility.

Changes:
- Confirmed rehearsals: solid blue border (#2563EB, 1.5px), no shadow/animation
- Confirmed gigs: solid green border (#22C55E, 1.5px), no shadow/animation
- Potential rehearsals/gigs: amber border (#F59E0B, 1.5px) + subtle ambient glow
  + animated "chasing beam" effect (comet-style sweeping spotlight)

Implementation:
- New shared widget: AnimatedChasingBorder (adapted from deleted AnimatedGradientBorder)
- Uses CustomPaint + SweepGradient with GradientRotation for continuous rotation
- Deterministic animation speed/direction per event ID (prevents visual chaos)
- Duration: 4-6 seconds per rotation, direction randomized per card

Amends unpushed commit 0d27ac7 on branch feature/forui-card-consolidation.

Affects: Web, iOS, Android, macOS
Testing: Manual QA (visual inspection + performance benchmarks on all platforms)
```

---

## Risk Assessment

| Risk                                            | Severity | Mitigation                                                               |
| ----------------------------------------------- | -------- | ------------------------------------------------------------------------ |
| Animation jank on low-end devices               | Medium   | Test on oldest supported iOS/Android devices                             |
| Chasing beam too distracting                    | Low      | 4-6 second duration is slow enough to avoid annoyance                    |
| Border colors too faint in dark mode            | Low      | Use saturated colors (#2563EB, #22C55E, #F59E0B), not tinted shades      |
| Memory leak from undisposed AnimationController | Low      | AnimatedChasingBorder uses SingleTickerProviderStateMixin with dispose() |
| Gradient rotation creates moiré patterns        | Low      | 2px stroke width + rounded rect prevents aliasing                        |

---

## Additional Notes

**Design Iteration Context:**  
This is the second design iteration for dashboard card type indication:

1. Original: multi-color gradient backgrounds (removed in commit `ff6689e`)
2. First iteration: color-coded box-shadow glows (commit `0d27ac7`) — too subtle
3. This iteration: solid borders + chasing beam animation — clear and dynamic

**Chasing Beam Visual Reference:**  
The effect should resemble:

- iOS "Searching..." spinner (but on a border path, not circular)
- Progress bars with a "shimmer" effect traveling across
- A spotlight beam sweeping around a perimeter

**NOT like:**

- A solid colored border that rotates (should have transparent sections)
- A blinking or flashing effect (should be continuous smooth rotation)
- A uniform ring of light (should be a localized arc/comet)

**Animation Philosophy:**  
Potential cards need visual urgency ("respond to this event!") without being distracting. The chasing beam should catch the eye during a casual scan, but not dominate the screen or induce motion sensitivity.

**If Tony Requests Further Tuning:**  
The following params are easily adjustable without structural changes:

- Gradient stop positions (adjust comet width: currently 40% arc visibility)
- Duration range (currently 4-6 seconds; can be made faster/slower)
- Border width (currently 1.5px static + 2px animated; can adjust contrast)
- Ambient glow spread (currently `spreadRadius: 2`; can increase for more subtlety)

---

**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Plan Version:** 2.0 (Revised)  
**Date:** 2026-08-16  
**Status:** Ready for Engineer implementation

---

_End of Architect Plan_
