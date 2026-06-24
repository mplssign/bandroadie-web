# ARCHITECT_PLAN — dashboard-potential-card-spacing

## Feature Identifier

`bug/dashboard-potential-card-spacing`

## Type

Bug Fix — Dashboard UI spacing

## Problem Statement

On the Dashboard (`HomeTabContent`), the Potential Events section (horizontal carousel showing potential gigs and rehearsals) renders with zero bottom margin when the section immediately below it is the rehearsal section in its empty state ("No Rehearsal Scheduled").

When the rehearsal section contains real rehearsal cards (confirmed rehearsals), the spacing between sections is correct because the section title renders with `topSpacing: Spacing.space24`.

The bug is state-dependent: spacing collapses specifically when the rehearsal section renders its empty-state UI without its section title.

---

## Root Cause Analysis

**Confidence Level:** HIGH (confirmed in code through direct observation)

**Primary Failure Point:** `lib/features/home/home_tab_content.dart` (lines 844-890)

### Current Behavior (Data Flow)

1. **Potential Events Section** (lines 844-857):
   - Conditional: Only renders when `gigState.potentialGigs.isNotEmpty || rehearsalState.potentialRehearsals.isNotEmpty`
   - Wrapped in `_AnimatedCardEntrance` widget
   - Calls `_buildHorizontalPotentialEvents()` to render horizontal scroll list
   - **NO bottom margin or spacing after this section**

2. **Rehearsal Section Title** (lines 860-867):
   - Conditional: Only renders when `rehearsalState.confirmedRehearsals.isNotEmpty`
   - When rendered: `SectionHeader(title: 'Upcoming Rehearsals', topSpacing: Spacing.space24)` provides 24px top spacing
   - When NOT rendered: zero spacing

3. **Rehearsal Section Content** (lines 871-890):
   - Three possible states:
     - **State A:** `confirmedRehearsals.isNotEmpty` → renders `_buildHorizontalRehearsalsList()` (confirmed rehearsal cards)
     - **State B:** `confirmedRehearsals.isEmpty && potentialRehearsals.isEmpty` → renders `EmptySectionCard` (empty state)
     - **State C:** `confirmedRehearsals.isEmpty && potentialRehearsals.isNotEmpty` → renders nothing (potential rehearsals already shown in potential events section)
   - The `EmptySectionCard` widget has no inherent top margin

4. **Gigs Section** (lines 893+):
   - Title ALWAYS renders: `SectionHeader(title: 'Upcoming Gigs', topSpacing: Spacing.space24)`
   - Provides consistent 24px top spacing

### Broken Scenario

**When:** Dashboard has potential events + no confirmed rehearsals + no potential rehearsals

**Layout stack:**

```
Potential Events Section (horizontal carousel)
↓ [ZERO SPACING] ← BUG
Empty Rehearsal Section Card ("No Rehearsal Scheduled")
↓ [24px spacing from Gigs title]
Upcoming Gigs Section
```

**Why it breaks:**

- Potential Events section: no bottom margin
- Rehearsal section title: doesn't render (condition fails)
- Empty state card: no top margin
- Result: **Zero spacing between Potential Events and empty state card**

### Working Scenario (for comparison)

**When:** Dashboard has potential events + confirmed rehearsals exist

**Layout stack:**

```
Potential Events Section (horizontal carousel)
↓ [24px spacing from Rehearsal title] ← CORRECT
Rehearsal Section Title ("Upcoming Rehearsals")
↓ [12px spacing]
Rehearsal Cards (horizontal scroll)
↓ [24px spacing from Gigs title]
Upcoming Gigs Section
```

**Why it works:**

- The `SectionHeader` for rehearsals renders with `topSpacing: Spacing.space24`
- This provides the visual gap between sections

---

## System Impact Assessment

| System                     | Impact         | Notes                                                                                                                                                        |
| -------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Dashboard (HomeTabContent) | **Affected**   | Primary bug location — spacing collapse in specific state                                                                                                    |
| Dashboard (HomeScreen)     | **Unaffected** | Different rendering logic; potential gig has explicit bottom spacing (line 762), and empty rehearsal state only shows when `potentialGig == null` (line 800) |
| Gigs                       | **Unaffected** | Read-only display, no logic changes                                                                                                                          |
| Rehearsals                 | **Unaffected** | Read-only display, no logic changes                                                                                                                          |
| Setlists / Catalog         | **Unaffected** | Not involved in dashboard layout                                                                                                                             |
| Members / RBAC             | **Unaffected** | No permission logic changes                                                                                                                                  |
| Auth / Session             | **Unaffected** | No auth flow changes                                                                                                                                         |
| Routing                    | **Unaffected** | No navigation changes                                                                                                                                        |

---

## Database Impact

**Status:** Not applicable (pure UI layout fix — no database interaction)

---

## Proposed Solution

**Approach:** Add consistent bottom spacing after the Potential Events section

**Rationale:**

- Ensures uniform vertical rhythm between dashboard sections regardless of conditional rendering logic
- Simplest fix with minimal code change
- Follows existing pattern used elsewhere (e.g., `home_screen.dart` line 762 adds spacing after potential gig)
- Prevents future regressions if section ordering or conditional logic changes

**Alternative approaches considered:**

1. ❌ Always render the rehearsal section title (even for empty state) — changes UX, adds unnecessary header
2. ❌ Add conditional top spacing before empty state card — localized fix, harder to maintain, adds complexity
3. ❌ Add `topSpacing` parameter to `EmptySectionCard` widget — over-engineering for a single use case
4. ✅ **Add bottom spacing after potential events section** — cleanest, most maintainable

---

## Files to Modify

### 1. `lib/features/home/home_tab_content.dart`

**Location:** Lines 844-857 (Potential Events section)

**Change:** Add `SizedBox(height: Spacing.space24)` after the `_AnimatedCardEntrance` wrapper containing `_buildHorizontalPotentialEvents()`

**Current code structure:**

```dart
if (gigState.potentialGigs.isNotEmpty ||
    rehearsalState.potentialRehearsals.isNotEmpty) ...[
  _AnimatedCardEntrance(
    delay: const Duration(milliseconds: 0),
    child: _buildHorizontalPotentialEvents(
      gigState.potentialGigs,
      rehearsalState.potentialRehearsals,
      gigAllDateResponses,
      rehearsalUserResponses,
      rehearsalAllDateResponses,
      setlistsState,
    ),
  ),
],

// Upcoming rehearsals section
// Title — only when confirmed rehearsals exist
if (rehearsalState.confirmedRehearsals.isNotEmpty) ...[
```

**Proposed change:**

```dart
if (gigState.potentialGigs.isNotEmpty ||
    rehearsalState.potentialRehearsals.isNotEmpty) ...[
  _AnimatedCardEntrance(
    delay: const Duration(milliseconds: 0),
    child: _buildHorizontalPotentialEvents(
      gigState.potentialGigs,
      rehearsalState.potentialRehearsals,
      gigAllDateResponses,
      rehearsalUserResponses,
      rehearsalAllDateResponses,
      setlistsState,
    ),
  ),
  // Only add spacing when rehearsal section won't have title
  // (title provides topSpacing when confirmed rehearsals exist)
  if (rehearsalState.confirmedRehearsals.isEmpty) // ← ADD THIS CONDITIONAL
    const SizedBox(height: Spacing.space24),       // ← ADD THIS LINE
],

// Upcoming rehearsals section
// Title — only when confirmed rehearsals exist
if (rehearsalState.confirmedRehearsals.isNotEmpty) ...[
```

**Impact:**

- Two line addition (conditional + spacing)
- **Conditional logic:** Spacing only applies when confirmed rehearsals are empty
- When confirmed rehearsals exist, the `SectionHeader` provides `topSpacing: Spacing.space24` (avoids double spacing)
- When confirmed rehearsals are empty, adds spacing before empty state card or before gigs section
- Consistent with spacing pattern used between other dashboard sections

---

## Additional Notes

### Secondary Dashboard Path (`home_screen.dart`)

The secondary dashboard path (used when navigating from Setlists screen) does NOT have the same bug due to different conditional rendering:

1. Potential gig card already has explicit bottom spacing (line 762: `SizedBox(height: Spacing.space24)`)
2. Empty rehearsal state only renders when `potentialGig == null` (line 800), so they never appear adjacent
3. When potential gig exists + no rehearsal: rehearsal section is completely skipped

**Verdict:** No changes required to `home_screen.dart`

### Spacing Consistency Audit

After this fix, the dashboard vertical spacing cadence will be:

- **24px** after Potential Events section (NEW)
- **24px** above section titles (`SectionHeader.topSpacing`)
- **12px** between section title and content (`SizedBox`)
- **Consistent visual rhythm across all dashboard states** ✅

---

## Engineer Task Breakdown

### Task 1: Apply spacing fix to `home_tab_content.dart`

**File:** `lib/features/home/home_tab_content.dart`

**Location:** After line 857 (end of Potential Events section spread operator list)

**Action:**

1. Locate the closing bracket of the Potential Events section (line 857: `],`)
2. Before the closing bracket, add the conditional spacing:
   ```dart
   // Only add spacing when rehearsal section won't have title
   // (title provides topSpacing when confirmed rehearsals exist)
   if (rehearsalState.confirmedRehearsals.isEmpty)
     const SizedBox(height: Spacing.space24),
   ```
3. Verify `Spacing` import exists at top of file (should already be imported from `design_tokens.dart`)

**Verification:**

- Code compiles without errors
- `flutter analyze` passes with 0 errors
- Spacing only renders when confirmed rehearsals are empty (conditional)
- When confirmed rehearsals exist, no extra spacing added (SectionHeader's topSpacing is sufficient)

---

## Verification Plan

### Pre-deployment (Local Testing)

**Platform:** macOS or iOS simulator

**Test Case 1: Verify fix in broken scenario**

1. Navigate to Dashboard
2. Ensure band has:
   - At least one potential event (gig or rehearsal)
   - Zero confirmed rehearsals
   - Zero potential rehearsals (or all potential rehearsals are shown in potential events carousel)
3. Observe vertical spacing between:
   - Potential Events carousel
   - "No Rehearsal Scheduled" empty state card
4. **Expected:** 24px vertical gap (consistent with spacing between other sections)

**Test Case 2: Verify no regression in working scenario**

1. Navigate to Dashboard
2. Ensure band has:
   - At least one potential event
   - At least one confirmed rehearsal
3. Observe vertical spacing between:
   - Potential Events carousel
   - "Upcoming Rehearsals" section title
   - Rehearsal cards
4. **Expected:** 24px gap between carousel and title, 12px gap between title and cards (unchanged)

**Test Case 3: Verify no regression when no potential events**

1. Navigate to Dashboard
2. Ensure band has:
   - Zero potential events
   - Zero confirmed rehearsals
3. Observe layout
4. **Expected:** Rehearsal empty state card appears immediately after top padding (no extra spacing before it, since potential events section doesn't render)

**Test Case 4: Verify no regression in Gigs section**

1. Navigate to Dashboard
2. Observe spacing between:
   - Rehearsal section (content or empty state)
   - "Upcoming Gigs" section title
3. **Expected:** 24px gap (unchanged — Gigs section title always provides `topSpacing`)

**Test Case 5: Verify edge case — only potential rehearsals exist**

1. Navigate to Dashboard
2. Ensure band has:
   - Potential rehearsals (shown in potential events carousel)
   - Zero confirmed rehearsals
3. Observe layout
4. **Expected:**
   - Potential Events carousel renders
   - Rehearsal section completely skips (no title, no content, no empty state)
   - "Upcoming Gigs" section appears next with 24px top spacing
   - **New spacing:** 24px gap between carousel and Gigs title (NEW — previously would have been 24px from Gigs title alone)

### Post-deployment (Production Verification)

**Platform:** Web (bandroadie.com)

**Steps:**

1. Log in with test account
2. Switch to band with appropriate data state (potential events + no rehearsals)
3. Verify spacing is correct and consistent
4. Test on multiple viewport sizes (mobile, tablet, desktop)

---

## Risk Assessment

**Risk Level:** Very Low

**Justification:**

- Single line addition
- No conditional logic changes
- No state management changes
- No database queries
- Isolated to dashboard layout only
- Follows existing spacing pattern

**Potential Issues:**

- None identified (spacing is additive and gated by existing condition)

**Rollback Plan:**

- Remove the added line
- Redeploy

---

## Compliance with Guardrails

✅ **Minimal diff surface** — Single line change
✅ **No opportunistic refactors** — Only fixes the reported bug
✅ **No database impact** — Pure UI change
✅ **No RLS changes** — Not applicable
✅ **No async lifecycle issues** — Not applicable
✅ **File size within target** — `home_tab_content.dart` stays within limits
✅ **No new dependencies** — Uses existing `Spacing` tokens
✅ **Follows existing patterns** — Matches spacing used elsewhere in codebase

---

## Definition of Done

- [ ] Code change applied to `lib/features/home/home_tab_content.dart`
- [ ] `flutter analyze` passes with 0 errors
- [ ] All 5 verification test cases pass locally
- [ ] No visual regressions in other dashboard states
- [ ] Engineer report documents the change
- [ ] QA validates all test cases
- [ ] QA verdict: APPROVED
- [ ] Code committed and pushed to feature branch
- [ ] Deployed to production (web)
- [ ] Post-deployment verification completed

---

## Amendment: Rehearsal Card Bottom Padding

### Problem Description

The confirmed rehearsal card (blue gradient card showing upcoming rehearsals with setlist pills) has excessive vertical space between the bottom of the setlist pill and the bottom edge of the card. Visual inspection indicates roughly double the desired spacing — the pill should sit closer to the card's lower edge.

**Scope:** Visual-only adjustment. No logic, no data, no state changes.

---

### Root Cause Analysis

**Confidence Level:** HIGH (confirmed in code)

**File:** `lib/features/home/widgets/rehearsal_card.dart`

**Location:** Line 420 in `_buildConfirmedCard()` method

**Current Implementation:**

The confirmed rehearsal card uses uniform padding on all sides:

```dart
Container(
  constraints: BoxConstraints(
    minHeight: Spacing.rehearsalCardHeight,
  ),
  clipBehavior: Clip.hardEdge,
  decoration: BoxDecoration(...),
  padding: const EdgeInsets.all(Spacing.space16),  // ← 16px on all sides
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Date + Time section
      // ...
      const SizedBox(height: Spacing.space16),
      // Location + Setlist section (pill is last element)
      // ...
    ],
  ),
),
```

**Analysis:**

- `EdgeInsets.all(Spacing.space16)` applies **16px padding on all sides** (top, left, right, bottom)
- The setlist pill is the last element in the card's column layout
- The 16px bottom padding creates the excessive gap between the pill and the card's bottom edge
- Other dashboard cards (potential gig card, potential rehearsal card) use the same `16px` uniform padding pattern, but those cards have different content layouts where bottom spacing is less noticeable
- **Target reduction:** Approximately 50% (from 16px to 8px) based on visual comparison

---

### Proposed Solution

**Approach:** Change from uniform padding to asymmetric padding — reduce bottom padding while maintaining top/left/right spacing.

**Rationale:**

- Maintains existing top/left/right spacing for consistency with card header and side margins
- Reduces only the bottom padding to bring the setlist pill closer to the card edge
- Uses existing design token `Spacing.space8` (8px) — already part of the design system
- Minimal code change (single line edit)
- No impact on card behavior or layout logic

**Change:**

Line 420: Replace `padding: const EdgeInsets.all(Spacing.space16),` with:

```dart
padding: const EdgeInsets.fromLTRB(
  Spacing.space16,  // left   — unchanged
  Spacing.space16,  // top    — unchanged
  Spacing.space16,  // right  — unchanged
  Spacing.space8,   // bottom — reduced from 16 to 8
),
```

**Visual Impact:**

- Bottom padding: **16px → 8px** (50% reduction)
- Setlist pill will sit 8px closer to the bottom edge of the card
- Aligns with target spacing shown in reference screenshots

---

### Files to Modify

#### `lib/features/home/widgets/rehearsal_card.dart`

**Location:** Line 420

**Current Code:**

```dart
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF2B7FFF).withValues(alpha: gradientAlpha), // blue-500
                    const Color(0xFF1447E6).withValues(alpha: gradientAlpha), // blue-700
                  ],
                ),
                borderRadius: BorderRadius.circular(Spacing.cardRadius),
                border: Border.all(
                  color: context.colors.textSecondary,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(Spacing.space16),
              child: child,
```

**Proposed Change:**

```dart
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF2B7FFF).withValues(alpha: gradientAlpha), // blue-500
                    const Color(0xFF1447E6).withValues(alpha: gradientAlpha), // blue-700
                  ],
                ),
                borderRadius: BorderRadius.circular(Spacing.cardRadius),
                border: Border.all(
                  color: context.colors.textSecondary,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                Spacing.space16,  // left
                Spacing.space16,  // top
                Spacing.space16,  // right
                Spacing.space8,   // bottom - reduced from 16 to 8
              ),
              child: child,
```

---

### System Impact Assessment

| System                     | Impact         | Notes                                                             |
| -------------------------- | -------------- | ----------------------------------------------------------------- |
| Dashboard (HomeTabContent) | **Affected**   | Displays confirmed rehearsal cards in horizontal scroll           |
| Dashboard (HomeScreen)     | **Affected**   | Displays confirmed rehearsal card (single, non-scrolling)         |
| Gigs                       | **Unaffected** | Does not use rehearsal card widget                                |
| Rehearsals                 | **Unaffected** | No direct integration with dashboard card UI                      |
| Setlists / Catalog         | **Unaffected** | Not involved                                                      |
| Members / RBAC             | **Unaffected** | No permission logic                                               |
| Auth / Session             | **Unaffected** | No auth flow changes                                              |
| Routing                    | **Unaffected** | No navigation changes                                             |
| Potential Rehearsal Cards  | **Unaffected** | Uses different card variant (`_buildPotentialCard()`) — no change |

---

### Database Impact

**Status:** Not applicable (pure UI spacing change — no database interaction)

---

### Engineer Task Breakdown

#### Task 2: Update confirmed rehearsal card bottom padding

**File:** `lib/features/home/widgets/rehearsal_card.dart`

**Location:** Line 420

**Action:**

1. Locate line 420: `padding: const EdgeInsets.all(Spacing.space16),`
2. Replace with:
   ```dart
   padding: const EdgeInsets.fromLTRB(
     Spacing.space16,  // left
     Spacing.space16,  // top
     Spacing.space16,  // right
     Spacing.space8,   // bottom
   ),
   ```
3. Verify `Spacing` import exists (should already be imported from `design_tokens.dart`)

**Verification:**

- Code compiles without errors
- `flutter analyze` passes with 0 errors
- Change only affects confirmed rehearsal cards (blue gradient variant)
- Potential rehearsal cards (orange gradient variant) remain unchanged

---

### Verification Plan (Amendment)

#### Pre-deployment (Local Testing)

**Platform:** macOS or iOS simulator

**Test Case A1: Verify reduced spacing on confirmed rehearsal card with setlist**

1. Navigate to Dashboard (HomeTabContent or HomeScreen)
2. Ensure band has at least one confirmed rehearsal with an assigned setlist
3. Observe the confirmed rehearsal card (blue gradient)
4. Measure/observe spacing between:
   - Bottom of setlist pill
   - Bottom edge of card
5. **Expected:** Approximately 8px gap (reduced from previous 16px)
6. **Visual Check:** Pill sits noticeably closer to card edge, matching target screenshot

**Test Case A2: Verify card without setlist (location only)**

1. Navigate to Dashboard
2. Ensure band has at least one confirmed rehearsal with NO assigned setlist
3. Observe the confirmed rehearsal card (blue gradient)
4. Verify layout still looks balanced with reduced bottom padding
5. **Expected:** Location row (last visible element) has 8px bottom padding — card still looks proportional

**Test Case A3: Verify no impact on potential rehearsal cards**

1. Navigate to Dashboard
2. Ensure band has at least one potential rehearsal (orange gradient card)
3. Observe the potential rehearsal card
4. Verify YES/NO buttons still have correct spacing from bottom edge
5. **Expected:** No visual change (potential cards use different build method)

**Test Case A4: Verify horizontal scroll layout (HomeTabContent)**

1. Navigate to Dashboard tab with multiple confirmed rehearsals
2. Scroll horizontally through rehearsal cards
3. Verify all cards have consistent bottom spacing
4. **Expected:** All confirmed rehearsal cards use the new 8px bottom padding uniformly

**Test Case A5: Verify single card layout (HomeScreen)**

1. Navigate to Dashboard via Setlists screen (triggers HomeScreen path)
2. Observe single confirmed rehearsal card display
3. Verify bottom spacing matches horizontal scroll variant
4. **Expected:** Same 8px bottom padding, consistent appearance

#### Post-deployment (Production Verification)

**Platform:** Web (bandroadie.com)

**Steps:**

1. Log in with test account
2. Switch to band with confirmed rehearsals (with and without setlists)
3. Verify reduced bottom spacing on all confirmed rehearsal cards
4. Test on multiple viewport sizes (mobile, tablet, desktop)
5. Compare against reference screenshots

---

### Risk Assessment (Amendment)

**Risk Level:** Very Low

**Justification:**

- Single line edit in isolated widget
- No conditional logic changes
- No state management changes
- No interaction with other widgets or controllers
- Change isolated to confirmed rehearsal card variant only
- Uses existing design token (`Spacing.space8`)
- Purely cosmetic — does not affect tap targets, scrolling, or functionality

**Potential Issues:**

- None identified

**Rollback Plan:**

- Revert line 420 to `padding: const EdgeInsets.all(Spacing.space16),`
- Redeploy

---

### Compliance with Guardrails (Amendment)

✅ **Minimal diff surface** — Single line change
✅ **No opportunistic refactors** — Only adjusts the reported spacing issue
✅ **No database impact** — Pure UI change
✅ **No RLS changes** — Not applicable
✅ **No async lifecycle issues** — Not applicable
✅ **File size within target** — `rehearsal_card.dart` stays within limits (currently ~700 lines)
✅ **No new dependencies** — Uses existing `Spacing` design tokens
✅ **Follows existing patterns** — Uses `EdgeInsets.fromLTRB()` (standard Flutter API)

---

### Definition of Done (Amendment)

- [ ] Code change applied to `lib/features/home/widgets/rehearsal_card.dart` line 420
- [ ] `flutter analyze` passes with 0 errors
- [ ] All 5 amendment test cases (A1-A5) pass locally
- [ ] No visual regressions on potential rehearsal cards
- [ ] Bottom spacing reduced to approximately 8px (confirmed visually)
- [ ] Engineer report documents the change
- [ ] QA validates all test cases
- [ ] QA verdict: APPROVED
- [ ] Code committed and pushed to `feature/dashboard-potential-card-spacing` branch
- [ ] Deployed to production (web)
- [ ] Post-deployment verification completed

---

_End of Architect Plan (with Amendment)_
