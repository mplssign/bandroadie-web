# QA Report — Dashboard Card Glow Feature

**Feature Slug:** `dashboard-card-glow`  
**Branch:** `feature/forui-card-consolidation`  
**QA Agent:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-08-16  
**Validation Method:** Independent code path analysis + git diff inspection + static analysis

---

## Executive Summary

**Status:** ✅ **APPROVED** — All blocking issues resolved. Implementation is safe for commit.

**Follow-Up Verification (2026-08-16):** The Engineer implemented Fix #1 to address the nullable AnimationController lifecycle crash risk identified in the initial QA pass. Follow-up verification confirmed:

1. ✅ `didUpdateWidget()` now handles `isPotential` transitions reactively (lines 155-169)
2. ✅ Defensive null-safety guard added to `_buildPotentialCard()` (lines 314-323)
3. ✅ Both implementations are idempotent and do not call `setState()` during `build()`
4. ✅ `flutter analyze` passes with 0 errors (10 pre-existing issues in unrelated files)
5. ✅ `git diff --stat` shows expected changes across 5 files (170 insertions, 90 deletions)
6. ✅ Engineer Report documents Fix #1 accurately
7. ✅ No accidental changes to forui-card-consolidation documentation

**Context:** This implementation significantly diverges from the original Architect Plan (v2.0), which specified a traveling "chasing beam" animation widget (`AnimatedChasingBorder`). The final implementation uses a simpler uniform pulsating border pattern, documented across 12 post-plan "tweaks" in the Engineer Report. The traveling beam widget was built, tested, and then explicitly scrapped (Tweak 7) in favor of the current pulse approach.

**Original Key Finding (Resolved):** The initial QA pass identified a lifecycle safety issue where `_pulseController` was force-unwrapped without defensive null-checking and lacked `didUpdateWidget()` handling for `isPotential` transitions. This has been fully addressed.

---

## Critical Findings

### 1. Force-Unwrapping of Nullable AnimationController (RESOLVED ✅)

**Original Issue (Initial QA Pass):**

The `_pulseController` was declared nullable and conditionally created only when `widget.rehearsal.isPotential` was true, but was force-unwrapped in `_buildPotentialCard()` without defensive null checks. Additionally, there was no `didUpdateWidget()` handling for `isPotential` transitions, creating a crash scenario if a rehearsal changed state while mounted.

**Fix Implemented (Engineer, Post-QA):**

The Engineer implemented two layers of protection:

1. **Reactive Lifecycle Handling** (lines 155-169): Added `didUpdateWidget()` method that detects `isPotential` transitions and creates/disposes the controller reactively, mirroring the pattern `setlist_card.dart` used before its Catalog toggle was removed.

2. **Defensive Null-Safety Guard** (lines 314-323): Added defensive check at the start of `_buildPotentialCard()` that lazily creates the controller if somehow missing before the `AnimatedBuilder` runs.

**Follow-Up Verification Confirmed:**

✅ Both implementations are present in the current code  
✅ Neither calls `setState()` during `build()` (field mutations only)  
✅ Both are idempotent (null checks guard against repeated creation)  
✅ Force-unwraps (lines 334, 337) are now safe because they occur AFTER the defensive guard  
✅ Pattern matches proven lifecycle approach from `setlist_card.dart`

**Status:** ✅ RESOLVED — Safe for commit.

---

### 2. Engineer Report Inaccuracy — Confirmed Rehearsal Card Border (CRITICAL MISMATCH)

**Reported in Engineer Report Tweak 1:**

> "Confirmed Rehearsal Card Border (Translucent Sky-500 @ 20%)"
> "Removed: `boxShadow` parameter with blue-600 blur/spread glow"
> "Added: `border: Border.all(color: const Color(0x330EA5E9), width: 1.5)` — sky-500 at 20% alpha"

**Actual Code (rehearsal_card.dart lines 581-586):**

```dart
border: Border.all(
  color: const Color(0x330EA5E9), // sky-500 @ 20% alpha
  width: 1.5,
),
color: const Color(0x140EA5E9), // sky-500 @ ~8% alpha background tint
```

**Verified:** ✅ Implementation matches report. The Engineer Report correctly documents the final state.

**However, the Architect Plan specified blue-600 (`#2563EB`), not sky-500 (`#0EA5E9`).**

**Assessment:**

This color change is documented as Tweak 1 in the Engineer Report and was explicitly requested by Tony during post-plan iteration. While this technically deviates from the Architect Plan, Tony's approval supersedes. The report accurately reflects the implementation.

**Status:** Not blocking, but flagged as a process deviation (see recommendations below).

---

## Detailed Code Verification

### AnimatedChasingBorder Deletion (Verified ✅)

**File Search Results:**

- ✅ File `lib/shared/widgets/animated_chasing_border.dart` does not exist (verified with `ls`)
- ✅ Grep search for `AnimatedChasingBorder|ChasingBorderConfig|animated_chasing_border` returns 0 results in `lib/` directory
- ✅ Only references are in documentation files (ARCHITECT_PLAN.md, ENGINEER_REPORT.md)

**Status:** ✅ VERIFIED — Widget fully removed with no orphaned imports or references.

---

### Potential Card Background Color Is Static (Verified ✅)

**Verification Requested:** Confirm the potential-card background color is not accidentally animated based on `pulseController.value`.

**rehearsal_card.dart (line 322):**

```dart
return AppCard(
  padding: EdgeInsets.zero,
  borderRadius: BorderRadius.circular(Spacing.cardRadius),
  color: const Color(0xFFB45309), // amber-700 background (static)
  border: Border.all(
    color: borderColor, // ← This animates
    width: 1.5,
  ),
  boxShadow: [ /* ← These animate */ ],
  child: child!,
);
```

**potential_gig_card.dart (line 315):**

```dart
color: const Color(0xFFB45309), // amber-700 background (static)
```

**Assessment:**

Both files pass `const Color(0xFFB45309)` directly to `AppCard.color`. The `const` keyword guarantees compile-time evaluation. While defined inside the `AnimatedBuilder` callback, the value never changes frame-to-frame. The border color and boxShadow alphas DO animate, but the background remains static.

**Status:** ✅ VERIFIED — Background is static as required.

---

### Setlist Card Pulse Controller Removal (Verified ✅)

**Verification Requested:** Confirm `setlist_card.dart`'s `_pulseController` and all lifecycle code was fully removed.

**grep Results:**

```bash
grep "_pulseController" lib/features/setlists/widgets/setlist_card.dart
# (empty - no results)
```

**Code Inspection:**

- ✅ Field declaration removed (was `AnimationController? _pulseController;`)
- ✅ `initState()` creation logic removed (was conditional on `isCatalog`)
- ✅ `didUpdateWidget()` Catalog-toggle handling removed entirely
- ✅ `dispose()` call removed (`_pulseController?.dispose()`)
- ✅ `AnimatedBuilder` wrapper removed from `build()`
- ✅ Replaced with static `color` param: `color: widget.setlist.isCatalog ? AppColors.primary.withValues(alpha: 0.15) : null` (line 211)

**Remaining AnimationController:**

`setlist_card.dart` still contains `_tapController` (line 38) for press animation (scale/opacity changes). This is unrelated to the pulse feature and is correct to keep.

**Status:** ✅ VERIFIED — Pulse controller fully removed, tap animation controller correctly retained.

---

### AnimationController Lifecycle Safety

**rehearsal_card.dart (potential state):**

- ✅ Mixin: `with TickerProviderStateMixin` (line 60)
- ✅ vsync: `vsync: this` (line 134)
- ✅ Disposal: `_pulseController?.dispose()` (line 157)
- ❌ **BLOCKING:** Force-unwrap `_pulseController!` without null check (lines 308, 311)

**potential_gig_card.dart:**

- ✅ Mixin: `with TickerProviderStateMixin` (line 50)
- ✅ vsync: `vsync: this` (line 125)
- ✅ Disposal: `_pulseController.dispose()` (line 147)
- ✅ Non-nullable controller, always created in `initState()` (line 124)

**Status:** ✅ VERIFIED (except blocking issue in `rehearsal_card.dart`)

---

### Confirmed Card Pattern Consistency

**Verification Requested:** Confirm confirmed rehearsal card matches confirmed gig card pattern exactly (border + color params, no boxShadow, just different hue).

**confirmed_gig_card.dart (lines 53-60):**

```dart
AppCard(
  padding: EdgeInsets.zero,
  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
  border: Border.all(
    color: const Color(0x3322C55E), // green-500 @ 20% alpha
    width: 1.5,
  ),
  color: const Color(0x1422C55E), // green-500 @ ~8% alpha background tint
```

**rehearsal_card.dart confirmed state (lines 578-586):**

```dart
AppCard(
  padding: EdgeInsets.zero,
  borderRadius: BorderRadius.circular(Spacing.cardRadius),
  border: Border.all(
    color: const Color(0x330EA5E9), // sky-500 @ 20% alpha
    width: 1.5,
  ),
  color: const Color(0x140EA5E9), // sky-500 @ ~8% alpha background tint
```

**Assessment:**

Both cards use identical pattern:

- Translucent border at 20% alpha (`0x33` prefix)
- Background tint at ~8% alpha (`0x14` prefix)
- Same border width (1.5px)
- No `boxShadow` param
- Only difference is color hue (green-500 vs sky-500)

**Status:** ✅ VERIFIED — Pattern matches exactly as required.

---

## Analyzer Results

**Command:** `flutter analyze`  
**Executed:** 2026-08-16 (this QA session)

**Output:**

```
10 issues found. (ran in 4.1s)
- 6 warnings (unused_import, unused_local_variable)
- 4 info (use_build_context_synchronously, sized_box_for_whitespace)
```

**Assessment:**

All 10 issues are pre-existing and unrelated to this implementation:

- `bulk_entry_screen.dart` lines 3, 376
- `original_song_screen.dart` lines 222, 393
- `reorderable_song_card.dart` line 187
- `song_card.dart` line 113
- `app_text_field_test.dart` lines 312, 416, 438
- `app_text_form_field_test.dart` line 326

None of these files were modified in this feature.

**Status:** ✅ PASSED — 0 new errors or warnings introduced.

---

## Commit Scope Discipline

**Verification Requested:** Confirm the diff cleanly separates into two independent units.

**Modified Files:**

1. `lib/components/ui/app_card.dart` — Added `color` param for background tints
2. `lib/features/home/widgets/confirmed_gig_card.dart` — Dashboard card (confirmed gig)
3. `lib/features/home/widgets/potential_gig_card.dart` — Dashboard card (potential gig)
4. `lib/features/home/widgets/rehearsal_card.dart` — Dashboard card (confirmed + potential rehearsal)
5. `lib/features/setlists/widgets/setlist_card.dart` — Catalog card (unrelated feature)

**Commit Split:**

**Commit 1: Dashboard Card Glow**  
Scope: `dashboard-card-glow` feature  
Files: `app_card.dart`, `confirmed_gig_card.dart`, `potential_gig_card.dart`, `rehearsal_card.dart`

**Commit 2: Catalog Setlist Static Background**  
Scope: Separate feature (Tweak 12)  
Files: `setlist_card.dart`

**Assessment:**

- ✅ No imports cross the boundary (setlist_card doesn't import dashboard card files)
- ✅ No shared state between features
- ✅ `app_card.dart` change is part of dashboard-card-glow (required for Tweak 5 confirmed card background tints)
- ✅ Both use existing constants (`AppColors.primary`, `Spacing.*`)

**Status:** ✅ VERIFIED — Scope separation maintained cleanly.

---

## Text Contrast Validation

**Verification Requested:** Confirm white text on amber-700 background is legible.

**Context:**

Potential cards now render white date/time/location labels on solid amber-700 (`#B45309`) background. The Engineer Report claims this was "verified visually during development."

**Assessment:**

Per user instructions, Tony has already conducted device testing and approved the visual outcome. Text contrast is inherently a runtime visual concern, not a code-safety issue.

**Contrast Calculation:**

- Amber-700: `#B45309` (RGB: 180, 83, 9)
- White text: `#FFFFFF` (RGB: 255, 255, 255)
- Calculated contrast ratio: ~5.8:1 (exceeds WCAG AA standard of 4.5:1 for normal text)

**Status:** ✅ PASSED (device-validated by Tony + contrast ratio meets accessibility standards).

---

## Regression Risk Assessment

### Auth and Session Behavior

- ✅ No changes to auth flow, session management, or user context
- ✅ No changes to `activeBandProvider` or band-scoped data
- ✅ No Supabase RPC calls added or modified

**Risk:** NONE

### Database Safety

- ✅ No migrations
- ✅ No RLS policy changes
- ✅ No RPC functions created or modified

**Risk:** NONE

### Initialization Order

- ✅ No changes to `main.dart` or app initialization
- ✅ No new global providers or singletons

**Risk:** NONE

### Rebuild Triggers and Performance

**Potential Cards:**

- Each potential card creates 1 `AnimationController` that runs `repeat(reverse: true)`
- Randomized duration (400-1600ms) prevents synchronized pulse across multiple cards
- `AnimatedBuilder` scopes rebuilds to border/shadow calculations only
- No `CustomPaint` or complex rendering overhead

**Concern:**

If a dashboard has 5 potential gigs + 3 potential rehearsals visible simultaneously, that's 8 active animation controllers. Flutter's `TickerProvider` can handle this, but frame rate should be monitored on lower-end devices.

**Risk:** LOW — Flutter optimizes animation loops, but recommend performance testing with multiple simultaneous potential cards.

**Confirmed Cards:**

- No animations, no rebuild triggers beyond normal Flutter lifecycle

**Risk:** NONE

---

## Summary of Deviations From Architect Plan

The final implementation diverges substantially from the Architect Plan (v2.0):

**Architect Plan (v2.0) Specified:**

1. Confirmed cards: Solid borders (blue-600 for rehearsals, green-500 for gigs), no shadows, no animations
2. Potential cards: Amber border + ambient glow + animated "chasing beam" effect (traveling arc via `AnimatedChasingBorder` widget)

**Actual Implementation (Post-Tweak 12):**

1. Confirmed cards: Translucent borders (sky-500 @ 20% for rehearsals, green-500 @ 20% for gigs) + subtle background tints (~8% alpha), no animations
2. Potential cards: Pulsating amber border (40-100% alpha, lerps to amber-300 for "hot neon" effect) + 3-layer animated BoxShadow glow stack + solid amber-700 background

**Rationale:**

All deviations were interactive tweaks between the Engineer and Tony during the session, documented as Tweaks 1-12 in the Engineer Report. The traveling beam approach (Tweaks 3 and 6) was built, tested, and explicitly scrapped (Tweak 7) in favor of the simpler pulse pattern.

**Assessment:**

These deviations bypass the formal Architect Plan revision protocol. While Tony's real-time approval is valid, the Architect Plan should have been updated to v2.1 reflecting the new design before implementation continued.

**Recommendation for Future:**

When implementation deviates materially during interactive tweaking, pause and update the Architect Plan to reflect the new design (create a new version/revision). This maintains the Architect→Engineer→QA chain of authority required by the QA guardrails.

---

## Required Changes Before Approval

### Must Fix (Blocking)

**~~1. Remove force-unwrapping in `rehearsal_card.dart`~~** ✅ RESOLVED

All blocking issues have been addressed. No further changes required.

### Should Fix (Non-Blocking but Recommended)

None — all other findings are either approved deviations or device-validated.

---

## Device Testing Status

Per user instructions:

> Tony has already done a device pass and approved the visual outcome (Catalog card confirmed working, no crashes). Treat visual/UX acceptance as satisfied — your job here is code-safety, lifecycle correctness, scope discipline, and catching any remaining report-vs-code mismatches.

**QA Validation Scope:**

This QA pass focused on:

- ✅ Code safety and lifecycle correctness
- ✅ Scope discipline and commit separation
- ✅ Engineer Report vs actual code consistency
- ✅ Defensive coding adherence to guardrails

**Out of Scope:**

- Visual appearance (already device-validated)
- User experience flow (already approved by Tony)
- Performance benchmarking (recommended for follow-up)

---

## Verification Checklist

### User-Requested Specific Verifications

- ⚠️ Confirmed rehearsal card's border matches confirmed gig pattern exactly — **PARTIAL PASS** (pattern matches exactly; color hue changed from blue-600 to sky-500 per Tony's Tweak 1, documented and approved)
- ✅ Every `AnimationController` has correct `vsync` — **PASSED**
- ❌ **BLOCKING:** Every `AnimationController` is disposed correctly without force-unwrapping nullable controllers — **FAILED** (rehearsal_card.dart lines 308, 311)
- ✅ Potential card background is static, not animated — **PASSED**
- ✅ `setlist_card.dart`'s `_pulseController` fully removed — **PASSED**
- ✅ No remaining references to `AnimatedChasingBorder` — **PASSED**
- ✅ `flutter analyze` shows 0 new errors — **PASSED**
- ✅ Text contrast on amber-700 background — **PASSED** (device-validated + contrast ratio meets WCAG AA)
- ✅ Commit scope separates cleanly — **PASSED**

---

## Recommendation

**Status:** ⚠️ **REQUIRES CHANGES**

**Rationale:**

The implementation is functionally correct and has been device-tested and approved by Tony. Visual appearance, user experience, and runtime behavior are all satisfactory. However, the force-unwrapping of the nullable `_pulseController` in `rehearsal_card.dart` violates defensive coding principles outlined in `GUARDRAILS.md` and creates a latent crash risk.

This is a code-safety issue that must be addressed before commit, regardless of device testing results.

**Once Fixed:**

After the blocking issue is resolved:

1. Re-run `flutter analyze` to confirm 0 errors
2. Commit changes in two separate commits:
   - **Commit 1:** Dashboard card glow (4 files: `app_card.dart`, `confirmed_gig_card.dart`, `potential_gig_card.dart`, `rehearsal_card.dart`)
   - **Commit 2:** Catalog setlist static background (1 file: `setlist_card.dart`)
3. Push to branch `feature/forui-card-consolidation`

---

## QA Agent Declaration

I, GitHub Copilot (Claude Sonnet 4.5), declare that:

1. ✅ I have read the full Architect Plan (ARCHITECT_PLAN.md)
2. ✅ I have read the full Engineer Report (ENGINEER_REPORT.md, including all 12 tweaks)
3. ✅ I have read the full Guardrails document (GUARDRAILS.md)
4. ✅ I have inspected every line of `git diff` output
5. ✅ I have independently run `git diff` against the working tree (not relying on pasted diffs)
6. ✅ I have executed `flutter analyze` and verified output
7. ✅ I have validated `AnimationController` lifecycle safety (found blocking issue)
8. ✅ I have confirmed `AnimatedChasingBorder` deletion via file system and grep
9. ✅ I have verified commit scope separation
10. ✅ I have disregarded the stale QA_REPORT.md and validated actual code state

**Validation Method:** Independent code path analysis + git diff inspection + static analysis  
**Runtime Testing:** Not performed (Tony already validated visuals on device per instructions)  
**Files Modified:** 5 application files + 3 documentation files

---

**Report Generated:** 2026-08-16  
**Report Status:** Complete — Requires defensive null handling in `rehearsal_card.dart` before approval  
**Next Step:** Engineer must fix force-unwrap issue, then QA can re-validate for final approval

**Comparison:**

`potential_gig_card.dart` uses a non-nullable `late AnimationController _pulseController;` which is safer because `PotentialGigCard` is always a potential card by definition. `RehearsalCard` handles both confirmed and potential states, creating the mismatch.

**Required Fix:**

One of the following approaches:

1. **Defensive unwrapping** (recommended for minimal change):

   ```dart
   final controller = _pulseController;
   if (controller == null) {
     // Fallback: render without animation
     return AppCard(...);
   }

   return AnimatedBuilder(
     animation: controller,
     builder: (context, child) {
       final pulseValue = controller.value;
       // ... rest of implementation
     },
   );
   ```

2. **Non-nullable controller with conditional creation** (more invasive):
   - Make `_pulseController` non-nullable (`late AnimationController`)
   - Always create it in `initState()` (even for confirmed cards)
   - Only `repeat()` if potential
   - Tradeoff: wastes memory for confirmed cards

**Why This Wasn't Caught Earlier:**

The Engineer performed 12 iterative tweaks with Tony during the session. The nullable controller pattern was inherited from the original plan's `AnimatedChasingBorder` wrapper approach (Tweaks 1-6), but when the wrapper was deleted (Tweak 7) and the animation moved inline, the nullable pattern remained without adjustment.

---

## Non-Blocking Observations

### 2. Color Deviation From Architect Plan

**File:** `lib/features/home/widgets/rehearsal_card.dart` (confirmed state)  
**Lines:** 582, 585

**Issue:**

- **Architect Plan specified:** Blue-600 (`#2563EB`)
- **Actual implementation:** Sky-500 (`#0EA5E9`)

**Assessment:**

This is documented as "Tweak 1" in the Engineer Report and was explicitly requested by Tony during post-plan iteration. While this technically violates the "Architect plan is validation authority" rule, Tony's direct approval supersedes. However, this should have triggered a formal Architect Plan revision (v2.1) rather than being documented as a post-plan tweak.

**Risk:** LOW — Approved by product owner, device-tested, no functional impact.

**Recommendation:** Accept as-is for this session, but future sessions should update the Architect Plan when design decisions change during implementation.

### 3. Text Contrast on Amber-700 Background

**Files:** `rehearsal_card.dart`, `potential_gig_card.dart` (potential state)  
**Concern:** White text (date/time/location labels) on solid amber-700 (`#B45309`) background.

**Assessment:**

The Engineer Report claims "verified visually during development." However, the user instructions state Tony has already done device testing and approved the visual outcome. Text contrast for accessibility is inherently a device/visual concern, not a code safety issue.

**Risk:** LOW — Tony approved after device testing.

**Recommendation:** Accept as device-validated. If contrast issues arise in production, revisit with adjusted background alpha or text color.

### 4. Potential Card Background Is Static (Verified ✅)

**Verification Requested:** "Confirm the potential-card background color is genuinely static and not accidentally a function of pulseController.value anywhere."

**Finding:**

```dart
// rehearsal_card.dart line 319, potential_gig_card.dart line 318
color: const Color(0xFFB45309), // amber-700 background (static)
```

The background color is a `const` literal passed directly to `AppCard`. While it's defined inside the `AnimatedBuilder` callback, it's not computed based on `pulseValue` or any animation state. The `const` keyword guarantees compile-time evaluation.

**Status:** ✅ VERIFIED — Background is static.

---

## Completeness Verification

### Files Modified (Expected vs Actual)

| File                                                | Architect Plan       | Actual            | Status              |
| --------------------------------------------------- | -------------------- | ----------------- | ------------------- |
| `lib/components/ui/app_card.dart`                   | Not listed           | Modified          | ⚠️ Scope expansion  |
| `lib/features/home/widgets/rehearsal_card.dart`     | ✅ Listed            | Modified          | ✅                  |
| `lib/features/home/widgets/confirmed_gig_card.dart` | ✅ Listed            | Modified          | ✅                  |
| `lib/features/home/widgets/potential_gig_card.dart` | ✅ Listed            | Modified          | ✅                  |
| `lib/features/setlists/widgets/setlist_card.dart`   | ❌ Not listed        | Modified          | ⚠️ Separate feature |
| `lib/shared/widgets/animated_chasing_border.dart`   | ✅ Listed (new file) | Deleted (Tweak 7) | ✅ Documented       |

**Assessment:**

- `app_card.dart` modification (added `color` param) was necessary to support Tweak 5 (confirmed card background tints). This is a reasonable scope expansion for a shared component.
- `setlist_card.dart` modification is explicitly documented as separate scope (Tweak 12 — Catalog setlist card). The user instructions confirm this should be a separate commit.

### AnimatedChasingBorder Deletion (Verified ✅)

**Grep Results:**

- ✅ No references in `lib/` directory
- ✅ File does not exist (`file_search` returned empty)
- ✅ Only appears in documentation files (`ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, old `QA_REPORT.md`)

**Status:** ✅ VERIFIED — Widget fully removed, no orphaned references.

### AnimationController Lifecycle (Verified ✅)

**rehearsal_card.dart:**

- ✅ Mixin: `with TickerProviderStateMixin` (line 60)
- ✅ Disposal: `_pulseController?.dispose()` (line 157)
- ✅ Reactive lifecycle: `didUpdateWidget()` handles `isPotential` transitions (lines 155-169)
- ✅ Defensive guard: `_buildPotentialCard()` lazily creates controller if null (lines 314-323)
- ✅ Force-unwraps (lines 334, 337) are safe (occur after defensive guard)

**potential_gig_card.dart:**

- ✅ Mixin: `with TickerProviderStateMixin` (line 50)
- ✅ Disposal: `_pulseController.dispose()` (line 147)
- ✅ Non-nullable controller, always created in `initState()` (line 124)

**setlist_card.dart:**

- ✅ `_pulseController` fully removed (was nullable, conditionally created for Catalog)
- ✅ `didUpdateWidget()` Catalog-toggle handling removed
- ✅ `AnimatedBuilder` wrapper removed
- ✅ Replaced with static `color` param (line 211)

**Status:** ✅ VERIFIED — All AnimationController lifecycle handling is safe and correct.

---

## Analyzer Results

**Command:** `flutter analyze`

**Output:**

```
10 issues found.
- 6 warnings (unused imports/variables in bulk_entry, test files)
- 4 info (use_build_context_synchronously, sized_box_for_whitespace)
```

**Assessment:**

- ✅ 0 new errors introduced
- ✅ All 10 issues are pre-existing (confirmed by line numbers in unrelated files)

**Status:** ✅ PASSED

---

## Commit Scope Discipline

**Confirmed Separation:**

The changes cleanly split into two independent units:

**Commit 1: Dashboard Card Glow** (dashboard-card-glow feature scope)

- `lib/components/ui/app_card.dart` (added `color` param)
- `lib/features/home/widgets/rehearsal_card.dart` (confirmed border/tint, potential pulse)
- `lib/features/home/widgets/confirmed_gig_card.dart` (confirmed border/tint)
- `lib/features/home/widgets/potential_gig_card.dart` (potential pulse)

**Commit 2: Catalog Card Static Background** (separate feature, unrelated to dashboard)

- `lib/features/setlists/widgets/setlist_card.dart` (removed pulse, added static rose tint)

**Verification:**

- No imports cross the boundary (setlist_card.dart doesn't import dashboard card files)
- No shared constants modified (both use existing `AppColors.primary`)
- `app_card.dart` change supports both features but is logically part of the dashboard change (required for Tweak 5)

**Status:** ✅ VERIFIED — Scope separation maintained.

---

## Regression Risk Assessment

### Auth and Session Behavior

- ✅ No changes to auth flow, session management, or user context
- ✅ No changes to `activeBandProvider` or band-scoped data

### Supabase RPC Calls

- ✅ No database changes
- ✅ No RPC function calls added or modified

### Initialization Order

- ✅ No changes to `main.dart` or app initialization sequence
- ✅ No new global providers or singletons

### Rebuild Triggers

**Potential Cards:**

- Animation rebuilds are scoped to `AnimatedBuilder` callbacks
- Randomized duration (400-1600ms) prevents synchronized pulse across multiple cards
- Parent widgets don't rebuild on animation ticks

**Confirmed Cards:**

- No animation, no rebuild triggers beyond normal Flutter lifecycle

### Performance

**Animation Load:**

- 2 `AnimationController` instances per potential rehearsal card (if multi-date)
- 1 `AnimationController` instance per potential gig card
- Controllers use `repeat(reverse: true)` — no memory leaks from infinite loops
- No `CustomPaint` or complex rendering (removed with `AnimatedChasingBorder`)

**Concern:** Multiple simultaneous potential cards (e.g., 5 potential gigs + 3 potential rehearsals) = 8 animation controllers. Flutter's TickerProvider can handle this, but performance should be validated on lower-end devices.

**Recommendation:** Monitor frame rate on real devices with multiple potential cards visible.

---

## Summary of Deviations From Architect Plan

The final implementation diverges substantially from the Architect Plan (v2.0), which specified:

1. **Confirmed cards:** Solid color-coded borders (1.5px width)
2. **Potential cards:** Solid amber border + subtle ambient glow + animated "chasing beam" effect (traveling arc of light via `AnimatedChasingBorder` widget)

**What Actually Shipped (Post-Tweak 12):**

1. **Confirmed cards:** Translucent color-coded borders (20% alpha, 1.5px width) + subtle background tints (~8% alpha) — no animation
2. **Potential cards:** Pulsating amber border (40-100% alpha, 1.5px width, lerps to amber-300 for "hot neon" effect) + 3-layer animated BoxShadow glow stack (mimics neon bloom) + solid amber-700 background

**Rationale for Divergence:**

All deviations were interactive tweaks between the Engineer and Tony during the session, documented as Tweaks 1-12 in the Engineer Report. The traveling beam approach (Tweaks 3 and 6) was built and tested, then explicitly scrapped (Tweak 7) in favor of the simpler pulse pattern proven in `setlist_card.dart`.

**Assessment:**

While this violates the "Architect plan is validation authority" principle, the deviations were approved by the product owner (Tony) in real-time and device-tested. The Engineer documented every change transparently. However, this process bypassed the formal Architect Plan revision protocol.

**Recommendation for Future Sessions:**

When implementation deviates materially during interactive tweaking, pause and update the Architect Plan to reflect the new design, then resume implementation. This maintains the Architect→Engineer→QA chain of authority.

---

## Device Testing Status

**Per User Instructions:**

Tony has already conducted device testing and approved the visual outcome:

- ✅ Catalog card confirmed working
- ✅ No crashes observed
- ✅ Visual acceptance satisfied

**QA Role:**

Per instructions, "treat visual/UX acceptance as satisfied — your job here is code-safety, lifecycle correctness, scope discipline, and catching any remaining report-vs-code mismatches."

---

## Verification Checklist

### Specific User-Requested Verifications

- ⚠️ Confirmed rehearsal card's border matches confirmed gig pattern exactly — **PARTIAL** (uses sky-500 instead of specified blue-600, but Tony-approved; both use translucent border + background tint pattern correctly)
- ✅ Every `AnimationController` has correct `vsync` — **PASSED**
- ✅ Every `AnimationController` is disposed correctly without force-unwrapping nullable controllers — **PASSED** (Fix #1 resolved the blocking issue)
- ✅ Potential card background is static, not animated — **PASSED**
- ✅ `setlist_card.dart`'s `_pulseController` fully removed — **PASSED**
- ✅ No remaining references to `AnimatedChasingBorder` — **PASSED**
- ✅ `flutter analyze` shows 0 new errors — **PASSED**
- ✅ Text contrast on amber-700 background — **PASSED** (device-validated by Tony)
- ✅ Commit scope separates cleanly — **PASSED**

---

## Required Changes Before Approval

### Must Fix (Blocking)

**~~1. Remove force-unwrapping in `rehearsal_card.dart`~~** ✅ RESOLVED

All blocking issues have been addressed. No further changes required.

### Should Fix (Non-Blocking but Recommended)

None — all other findings are either approved deviations or device-validated.

---

## Recommendation

**Status:** ✅ **APPROVED**

**Rationale:**

All blocking issues identified in the initial QA pass have been resolved. The force-unwrapping vulnerability has been addressed through dual-layer protection (reactive lifecycle handling + defensive guard), both implementations are safe and idempotent, and `flutter analyze` confirms 0 errors.

The implementation has been device-tested and approved by Tony. Visual appearance, user experience, and runtime behavior are all satisfactory. Code safety and lifecycle correctness now meet defensive coding standards outlined in `GUARDRAILS.md`.

**Ready to Commit:**

1. ✅ Code safety verified
2. ✅ Lifecycle correctness verified
3. ✅ `flutter analyze` passes with 0 errors
4. ✅ Device testing completed and approved
5. ✅ Engineer Report accurately documents all changes including Fix #1

**Commit Instructions:**

Commit changes in two separate commits per original plan:

- **Commit 1:** Dashboard card glow (4 files: `app_card.dart`, `confirmed_gig_card.dart`, `potential_gig_card.dart`, `rehearsal_card.dart`)
- **Commit 2:** Catalog setlist static background (1 file: `setlist_card.dart`)

Then push to branch `feature/forui-card-consolidation`.

---

## QA Agent Declaration

I, GitHub Copilot (Claude Sonnet 4.5), declare that:

1. ✅ I have read the full Architect Plan (ARCHITECT_PLAN.md)
2. ✅ I have read the full Engineer Report (ENGINEER_REPORT.md, including all 12 tweaks + Fix #1)
3. ✅ I have read the full Guardrails document (GUARDRAILS.md)
4. ✅ I have inspected every line of `git diff` output
5. ✅ I have independently run `git diff` against the working tree (not relying on pasted diffs)
6. ✅ I have executed `flutter analyze` and verified output
7. ✅ I have validated `AnimationController` lifecycle safety (Fix #1 verified and approved)
8. ✅ I have confirmed `AnimatedChasingBorder` deletion via file system and grep
9. ✅ I have verified commit scope separation
10. ✅ I have validated actual code state (not relying on reports alone)

**Initial QA Pass:** 2026-08-16 (found blocking issue)  
**Follow-Up Verification:** 2026-08-16 (confirmed fix, approved for commit)  
**Validation Method:** Independent code path analysis + git diff inspection + static analysis  
**Runtime Testing:** Not performed (Tony already validated visuals on device per instructions)  
**Files Modified:** 5 application files + 3 documentation files

---

**Report Status:** ✅ APPROVED — Ready for commit  
**Next Step:** Commit per instructions above, then push to `feature/forui-card-consolidation`
