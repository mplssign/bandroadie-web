# Architect Plan — Remove Onboarding Banner

## Feature Slug

`bug/remove-onboarding-banner`

---

## Problem Summary

The dashboard displays a red card with the text "Let's get this show started! Add your first gig or rehearsal below." when a band has no gigs or rehearsals. This card must be permanently removed. The existing empty-state cards ("No Rehearsal Scheduled" and "No Upcoming Gigs") should continue to display independently as they already do.

---

## Root Cause

**Confidence Level:** HIGH

**Evidence:**
Direct observation in `lib/features/home/widgets/empty_home_state.dart`:

1. **Lines 217-247:** The `_EmptyHeroSection` private widget class renders the unwanted banner with the "Let's get this show started!" text
2. **Line 145:** The widget is instantiated as the first animated section: `_buildAnimatedSection(0, _EmptyHeroSection())`
3. **Lines 61, 73:** Animation arrays are generated for 4 sections, including the banner as section 0

**Cause:**
The `_EmptyHeroSection` widget is unconditionally rendered in the `EmptyHomeState` widget's build method. It has no conditional logic, no state variable controlling its visibility, and no provider dependency. The widget exists solely to display the onboarding message.

**Why the empty-state cards are unaffected:**
The "No Rehearsal Scheduled" (lines 150-158) and "No Upcoming Gigs" (lines 164-172) cards are separate `EmptySectionCard` widgets with no dependency on `_EmptyHeroSection`. Removing the banner does not affect their rendering logic.

---

## Reference Docs Consulted

Not applicable — this is a UI-only bug with no backend, notification, or auth domain involvement.

---

## Existing System Analysis

**Current Behavior:**

1. When `EmptyHomeState` renders, it displays 4 animated sections:
   - Section 0: `_EmptyHeroSection` (the red banner)
   - Section 1: "No Rehearsal Scheduled" card
   - Section 2: "No Upcoming Gigs" card
   - Section 3: Quick Actions row (conditional)

2. Each section has staggered entrance animations (fade + slide) with a 150ms delay between sections

3. The banner is always shown — no conditional rendering based on first-time user status or app state

**Data Flow:**

- `home_screen.dart` and `home_tab_content.dart` instantiate `EmptyHomeState` when the band has no upcoming events
- `EmptyHomeState` constructs the UI in its `build()` method
- No state provider or controller drives the banner visibility
- No database query or preference check affects the banner

**Failure Point:**
The banner is hardcoded into the widget tree. There is no "first run" flag, no preference toggle, and no business logic that should have prevented it from appearing after initial onboarding.

---

## Proposed Solution

**Minimal change to permanently remove the banner:**

1. **Delete the `_EmptyHeroSection` class** (lines 217-247 in `empty_home_state.dart`) — this is dead code after removal from the widget tree

2. **Remove the banner instantiation** (lines 143-147) — the call to `_buildAnimatedSection(0, _EmptyHeroSection())` and its associated spacing

3. **Adjust animation generation** (lines 61, 73) — reduce from 4 sections to 3 sections:
   - Change `List.generate(4, ...)` to `List.generate(3, ...)`

4. **Re-index remaining animated sections** — shift indices down by 1:
   - "No Rehearsal Scheduled": index 1 → 0
   - "No Upcoming Gigs": index 2 → 1
   - Quick Actions: index 3 → 2

5. **Update comment references** in `design_tokens.dart` (line 223) and `brand_action_button.dart` (line 10) — remove outdated references to the "Let's get this show started" card

**Why this is minimal:**

- No new files or abstractions
- No state management changes
- No controller or provider modifications
- No changes to parent widgets (`home_screen.dart`, `home_tab_content.dart`)
- The animation system continues to work identically with 3 sections instead of 4

**Why this is safe:**

- The banner has no dependencies — no other code references `_EmptyHeroSection`
- The empty-state cards are independent widgets that already render correctly
- Animation indices are local to this file — no external coupling

---

## Database Impact

**Status:** Not applicable

This is a UI-only change. No database tables, RLS policies, RPC functions, migrations, or triggers are involved.

---

## Flutter Architecture Changes

**State Management:**
No changes. The `EmptyHomeState` widget is stateful only for animation controllers, which remain unchanged in behavior (still 3 staggered animations, just one fewer section).

**Widgets:**

- `EmptyHomeState` widget: modified (banner removed, animation count reduced)
- `_EmptyHeroSection` widget: deleted
- `EmptySectionCard` widget: not modified (used by the remaining empty-state cards)

**Repositories:**
No changes. This bug does not touch data access or business logic.

**Controllers/Providers:**
No changes. No Riverpod provider drives the banner visibility.

---

## Files to Create

None.

---

## Files to Modify

| File                                              | What Changes                                                                                                                          |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/widgets/empty_home_state.dart` | Remove `_EmptyHeroSection` widget class, remove banner instantiation, reduce animation count from 4 to 3, re-index remaining sections |
| `lib/app/theme/design_tokens.dart`                | Update comment on line 223 to remove reference to removed card                                                                        |
| `lib/components/ui/brand_action_button.dart`      | Update comment on line 10 to remove reference to removed card                                                                         |

---

## Files Off-Limits

| File                                                | Reason                                                                                                         |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/home_screen.dart`                | Parent widget — no changes required, instantiates `EmptyHomeState` without awareness of its internal structure |
| `lib/features/home/home_tab_content.dart`           | Parent widget — same reason as above                                                                           |
| `lib/features/home/widgets/empty_section_card.dart` | Shared widget used by remaining empty-state cards — must not be modified                                       |
| `lib/features/home/widgets/quick_actions_row.dart`  | Independent widget — no coupling to the banner                                                                 |
| `lib/main.dart`                                     | Initialization order must not change                                                                           |
| Any test files                                      | No tests currently exist for `EmptyHomeState` widget                                                           |

---

## System Impact Map

| System                                 | Impact                                                    |
| -------------------------------------- | --------------------------------------------------------- |
| Gigs                                   | unaffected                                                |
| Rehearsals                             | unaffected                                                |
| Setlists / Catalog                     | unaffected                                                |
| Members / RBAC                         | unaffected                                                |
| Auth / Session                         | unaffected                                                |
| Routing                                | unaffected                                                |
| Notifications                          | unaffected                                                |
| Platform (iOS / Android / Web / macOS) | unaffected — UI rendering only, no platform-specific code |

---

## Regression Risk

**Level:** LOW

**Rationale:**

1. **Isolated change:** Only one widget file is functionally modified
2. **No shared state:** The banner has no dependencies or consumers
3. **Independent widgets:** The remaining empty-state cards are separate `EmptySectionCard` instances with no coupling to the removed banner
4. **Animation integrity preserved:** The staggered entrance animation system continues to work with 3 sections instead of 4 — the logic is identical, just fewer iterations
5. **No backend involvement:** No database, RLS, RPC, or edge function changes
6. **No cross-feature impact:** The home screen is the only feature that uses `EmptyHomeState`

**Failure modes with LOW probability:**

- Animation indices miscalculated (mitigated by careful review of index changes)
- Comment updates introduce syntax errors (mitigated by only touching comments, not code)

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Update animation generation count

**File:** `lib/features/home/widgets/empty_home_state.dart`  
**Action:** Change `List.generate(4, ...)` to `List.generate(3, ...)` on line 61 (fade animations) and line 73 (slide animations)  
**Reason:** The banner removal reduces the total animated sections from 4 to 3

### Task 2: Remove banner instantiation

**File:** `lib/features/home/widgets/empty_home_state.dart`  
**Action:** Delete lines 143-147 (the call to `_buildAnimatedSection(0, _EmptyHeroSection())` and the preceding `SizedBox(height: Spacing.space32)` separator, and the following `SizedBox(height: 34)` separator)  
**Reason:** Removes the banner from the widget tree  
**Important:** Verify that the spacing between the app bar and the first card (Rehearsal) is visually correct after removal — retain ONE `SizedBox(height: 34)` after the app bar

### Task 3: Re-index "No Rehearsal Scheduled" section

**File:** `lib/features/home/widgets/empty_home_state.dart`  
**Action:** Change animation index from 1 to 0 in the `_buildAnimatedSection` call for the "No Rehearsal Scheduled" card (around line 150)  
**Reason:** This card becomes the first animated section after banner removal

### Task 4: Re-index "No Upcoming Gigs" section

**File:** `lib/features/home/widgets/empty_home_state.dart`  
**Action:** Change animation index from 2 to 1 in the `_buildAnimatedSection` call for the "No Upcoming Gigs" card (around line 164)  
**Reason:** This card becomes the second animated section

### Task 5: Re-index "Quick Actions" section

**File:** `lib/features/home/widgets/empty_home_state.dart`  
**Action:** Change animation index from 3 to 2 in the `_buildAnimatedSection` call for the Quick Actions row (around line 180)  
**Reason:** This row becomes the third animated section

### Task 6: Delete `_EmptyHeroSection` widget class

**File:** `lib/features/home/widgets/empty_home_state.dart`  
**Action:** Delete lines 217-261 (the entire `_EmptyHeroSection` class and its documentation comment)  
**Reason:** Dead code removal — this widget is no longer referenced anywhere

### Task 7: Update comment in design_tokens.dart

**File:** `lib/app/theme/design_tokens.dart`  
**Action:** On line 223, change the comment from `/// Matches the "Let's get this show started" hero card styling` to `/// Brand gradient styling for primary action cards`  
**Reason:** Remove reference to deleted card, preserve comment purpose

### Task 8: Update comment in brand_action_button.dart

**File:** `lib/components/ui/brand_action_button.dart`  
**Action:** On line 10, change the comment from `/// - Gradient background matching "Let's get this show started" hero card` to `/// - Brand gradient background with rose accent`  
**Reason:** Remove reference to deleted card, preserve comment purpose

### Task 9: Run `flutter analyze`

**Command:** `flutter analyze`  
**Expected:** 0 errors, 0 warnings  
**Reason:** Verify no syntax errors or linting issues introduced

### Task 10: Generate git diff

**Command:** `git diff`  
**Action:** Capture the full diff and include in `ENGINEER_REPORT.md`  
**Reason:** Provide QA with exact change surface for validation

---

## Verification Plan

**Manual testing required — no automated tests exist for this widget.**

### Tier 1 — Pre-deployment (Flutter code validation)

**Pre-deploy validation is not applicable for UI-only changes with no backend dependencies.**

All verification occurs post-implementation in the Flutter app running on each platform.

### Tier 2 — Post-deployment (UI validation on all platforms)

#### Test 1: Dashboard displays correct empty state (iOS)

**Platform:** iOS  
**Precondition:** User has a band with no upcoming gigs or rehearsals  
**Steps:**

1. Open BandRoadie on iOS device or simulator
2. Navigate to Home tab
3. Observe the empty state

**Expected:**

- The "Let's get this show started!" banner does NOT appear
- The "No Rehearsal Scheduled" card is displayed as the first card
- The "No Upcoming Gigs" card is displayed as the second card
- Quick Actions row is displayed below (if enabled)
- Entrance animations play smoothly with no visual glitches

**Fail condition:** The red banner appears, or any card is missing

#### Test 2: Dashboard displays correct empty state (Android)

**Platform:** Android  
**Precondition:** Same as Test 1  
**Steps:** Same as Test 1  
**Expected:** Same as Test 1

#### Test 3: Dashboard displays correct empty state (Web)

**Platform:** Web (Chrome, Safari, Firefox)  
**Precondition:** Same as Test 1  
**Steps:** Same as Test 1  
**Expected:** Same as Test 1

#### Test 4: Dashboard displays correct empty state (macOS)

**Platform:** macOS  
**Precondition:** Same as Test 1  
**Steps:** Same as Test 1  
**Expected:** Same as Test 1

#### Test 5: Entrance animations are correct

**Platform:** Any  
**Precondition:** User has a band with no upcoming events  
**Steps:**

1. Navigate away from Home tab
2. Navigate back to Home tab
3. Observe the entrance animations

**Expected:**

- "No Rehearsal Scheduled" card fades and slides in first
- "No Upcoming Gigs" card fades and slides in second (150ms delay)
- Quick Actions row fades and slides in third (300ms delay)
- No visual jank or timing issues

**Fail condition:** Animations play out of order, or sections appear without animation

#### Test 6: Empty state with only Quick Actions

**Platform:** Any  
**Precondition:** User has a band with gigs and rehearsals scheduled (so empty state cards don't show, but Quick Actions might)  
**Steps:**

1. Navigate to Home tab
2. Observe the layout

**Expected:**

- If the home screen shows upcoming events, the `EmptyHomeState` widget should not render at all
- This test confirms that the change does not inadvertently affect the non-empty state

**Note:** This test may not apply if `EmptyHomeState` is only used when the band has no events. Verify the call sites in `home_screen.dart` and `home_tab_content.dart`.

#### Test 7: Spacing and layout are correct

**Platform:** Any  
**Precondition:** User has a band with no upcoming events  
**Steps:**

1. Navigate to Home tab
2. Inspect the spacing between elements

**Expected:**

- Spacing between app bar and first card is visually consistent with design tokens (34px)
- Spacing between cards is 34px
- Spacing between cards and Quick Actions is 17px
- Bottom padding provides adequate scroll clearance above nav bar

**Fail condition:** Excessive or insufficient spacing, visual imbalance

---

## QA Regression Areas

QA must specifically test:

1. **Empty state display on all platforms** (iOS, Android, Web, macOS)
   - Verify the banner is permanently absent
   - Verify both empty-state cards display correctly
   - Verify Quick Actions row displays when applicable

2. **Entrance animations**
   - Verify staggered animations play correctly with 3 sections
   - Verify no animation glitches or timing issues

3. **Spacing and layout**
   - Verify spacing between elements matches design tokens
   - Verify no visual regression compared to pre-change layout (except for banner removal)

4. **Non-empty state (regression check)**
   - Verify that when gigs/rehearsals exist, the home screen displays them correctly
   - Verify the change does not affect the populated home screen state

5. **Navigation to/from Home tab**
   - Verify animations replay correctly when navigating back to Home
   - Verify no state leakage or visual artifacts

---

## Rollout / Migration Strategy

Not applicable. This is a client-side UI change with no backend deployment or data migration.

**Rollout:**

- Merge to `main` after QA approval
- Deploy web build: `./tools/deploy_web.sh`
- Mobile apps will receive the fix in the next app store update

**No rollback complexity:** If issues arise, reverting the commit fully restores the banner.

---

## Out of Scope

The following are explicitly **not** part of this fix:

1. **Modifying the "No Rehearsal Scheduled" card** — content, styling, or behavior
2. **Modifying the "No Upcoming Gigs" card** — content, styling, or behavior
3. **Modifying the Quick Actions row** — which actions are shown or how they behave
4. **Adding a "first-time user" onboarding flow** — this fix is not a replacement UX
5. **Changing the empty state animation system** — stagger timing, curves, or duration
6. **Modifying any other home screen states** (populated state, loading state, error state)
7. **Removing or modifying the `BrandButton.decoration` gradient** — this styling is used elsewhere and must remain
8. **Changing the comment structure or style** in `design_tokens.dart` or `brand_action_button.dart` — only the specific reference to the removed card should change

---

**Architect Sign-Off:**  
Plan complete. Ready for Engineer implementation.
