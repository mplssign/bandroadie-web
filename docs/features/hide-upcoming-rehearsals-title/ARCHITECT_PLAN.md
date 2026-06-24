# ARCHITECT_PLAN — hide-upcoming-rehearsals-title

---

## 1. Feature Slug

`feature/hide-upcoming-rehearsals-title`

---

## 2. Problem Summary

On the BandRoadie dashboard, the "Upcoming Rehearsals" section heading is currently visible even when there are no confirmed rehearsals to display. This occurs when all rehearsals are marked as "potential" (shown in a separate "Potential Events" section) or when only potential rehearsal cards are displayed, leaving an orphaned section title with no content below it.

**Current behavior:**

- "Upcoming Rehearsals" title always renders, regardless of content
- When only potential rehearsals exist (no confirmed rehearsals), the title shows but the content area is empty (renders `SizedBox.shrink()`)
- This creates a poor UX with an orphaned heading

**Desired behavior:**

- "Upcoming Rehearsals" title should only render when there is content to display below it
- Hide the title when there are no confirmed rehearsals AND potential rehearsals exist (since potential rehearsals are shown in a different section)
- Keep the title when showing the empty state card ("No Rehearsal Scheduled") to provide context for the action button

---

## 3. Root Cause

**Confidence: HIGH**

The "Upcoming Rehearsals" section header is rendered unconditionally in the dashboard layout, while the content below uses conditional logic that can result in an empty state.

**Primary issue location:** `lib/features/home/home_tab_content.dart` (lines 860-877)

**Evidence:**

```dart
// Upcoming rehearsals section
const SectionHeader(
    title: 'Upcoming Rehearsals',
    topSpacing: Spacing.space24),
const SizedBox(height: Spacing.space12),
_AnimatedCardEntrance(
  delay: const Duration(milliseconds: 80),
  child: rehearsalState.confirmedRehearsals.isNotEmpty
      ? _buildHorizontalRehearsalsList(rehearsalState)
      : rehearsalState.potentialRehearsals.isNotEmpty
          ? const SizedBox.shrink()  // ← Orphaned title when this path is taken
          : EmptySectionCard(
              title: 'No Rehearsal Scheduled',
              buttonLabel: 'Schedule Rehearsal',
              onButtonPressed: isContributor
                  ? null
                  : () => _openAddEventSheet(EventType.rehearsal),
            ),
),
```

**Logic breakdown:**

1. `confirmedRehearsals.isNotEmpty` → Show horizontal list ✓ (title should show)
2. `confirmedRehearsals.isEmpty` AND `potentialRehearsals.isNotEmpty` → Show `SizedBox.shrink()` ⚠️ (title shows but no content)
3. `confirmedRehearsals.isEmpty` AND `potentialRehearsals.isEmpty` → Show empty state card ✓ (title should show)

**Secondary location:** `lib/features/home/home_screen.dart` (lines 766-768)

This is a legacy code path used for specific navigation scenarios (e.g., navigating from setlists screen back to dashboard). The same conditional rendering pattern exists but is less problematic because this file doesn't have the multi-section "Potential Events" structure. However, for consistency and correctness, it should use the same conditional rendering logic.

---

## 4. Reference Docs Consulted

- `docs/features/rehearsal-empty-state-subtitle/ARCHITECT_PLAN.md` — Historical context on rehearsal empty state handling and dual code paths (`home_tab_content.dart` vs `home_screen.dart`)
- `docs/features/home-rehearsal-scroll-row/ARCHITECT_PLAN.md` — Context on how confirmed vs potential rehearsals are structured and rendered
- No dedicated dashboard conditional rendering reference docs exist

---

## 5. Existing System Analysis

### 5.1 Data Model

**Rehearsal State** (`lib/features/rehearsals/rehearsal_controller.dart`):

```dart
class RehearsalState {
  final List<Rehearsal> confirmedRehearsals;  // isPotential == false
  final List<Rehearsal> potentialRehearsals;  // isPotential == true
  final Rehearsal? nextRehearsal;             // First confirmed rehearsal
  // ...
}
```

- Rehearsals are categorized as "confirmed" or "potential" based on `isPotential` flag
- `confirmedRehearsals` = upcoming rehearsals where `isPotential == false`
- `potentialRehearsals` = upcoming rehearsals where `isPotential == true`
- `nextRehearsal` = first item in `confirmedRehearsals` (or null)

### 5.2 Dashboard Architecture

**Primary dashboard path:** `AppShell` → `HomeTabContent` (lines 840-890)

Structure:

1. **Potential Events section** (lines 844-857) — Horizontal scroll row showing potential gigs and potential rehearsals when they exist
2. **Upcoming Rehearsals section** (lines 860-877) — Vertical section for confirmed rehearsals or empty state
3. **Upcoming Gigs section** (lines 880-895) — Vertical section for upcoming gigs

**Secondary dashboard path:** Direct navigation to `HomeScreen` (used from `setlists_screen.dart` line 432)

Structure:

1. Potential gig card (if exists)
2. Upcoming Rehearsals section
3. Upcoming Gigs section

### 5.3 Current Rendering Logic

**In `home_tab_content.dart`:**

- "Upcoming Rehearsals" title is always rendered (line 860-862)
- Content uses ternary logic (lines 866-877):
  - If has confirmed → show list
  - Else if has potential → show nothing (`SizedBox.shrink()`)
  - Else → show empty state card

**Problem:** When only potential rehearsals exist, the title renders but content is empty, creating an orphaned heading.

**In `home_screen.dart`:**

- "Upcoming Rehearsals" title is always rendered (line 766)
- Content uses binary logic (lines 770-800):
  - If `nextRehearsal != null` → show rehearsal card
  - Else → show empty state card

This is less problematic because there's always content, but for consistency and to match the user's requirement ("hide title when no confirmed rehearsals"), it should also be conditional.

---

## 6. Proposed Solution

Conditionally render the entire "Upcoming Rehearsals" section (title + spacing + content) based on whether there is meaningful content to display.

**Condition to show section:**

```dart
rehearsalState.confirmedRehearsals.isNotEmpty ||
rehearsalState.potentialRehearsals.isEmpty
```

**Logic:**

- Show section when: has confirmed rehearsals (display the list)
- Show section when: has no rehearsals at all (display empty state with action button)
- Hide section when: has only potential rehearsals (they're shown in "Potential Events" section above)

**Implementation approach:**

1. **In `home_tab_content.dart`:** Wrap the section header, spacing, and content in a conditional check
2. **In `home_screen.dart`:** Wrap the section header, spacing, and content in a similar conditional check (using `nextRehearsal != null` as proxy for "has confirmed rehearsals")

---

## 7. Database Impact

**Not applicable**

This is a pure UI change. No database schema, RLS policies, RPC functions, or migrations are affected.

---

## 8. Flutter Architecture Changes

**State:** No changes to `RehearsalState` or `RehearsalNotifier`. Existing data structure already separates confirmed vs potential rehearsals.

**Widgets:** No new widgets. Modify existing dashboard layout to conditionally render section header.

**Repositories:** No changes.

**Controllers:** No changes.

**Providers:** No changes. Existing `rehearsalProvider` already provides all necessary data.

---

## 9. Files to Create

**None**

---

## 10. Files to Modify

| File                                      | Change Description                                                                                                                                                                                                             |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/home/home_tab_content.dart` | Wrap "Upcoming Rehearsals" section (lines 860-877) in conditional: `if (rehearsalState.confirmedRehearsals.isNotEmpty \|\| rehearsalState.potentialRehearsals.isEmpty) ...` to hide title when only potential rehearsals exist |
| `lib/features/home/home_screen.dart`      | Wrap "Upcoming Rehearsals" section (lines 766-803) in conditional: `if (nextRehearsal != null \|\| potentialGig == null) ...` for consistency with primary dashboard path                                                      |

---

## 11. Files Off-Limits

| File                                                | Reason                                                         |
| --------------------------------------------------- | -------------------------------------------------------------- |
| `lib/features/rehearsals/rehearsal_controller.dart` | State management logic is correct; no changes needed           |
| `lib/features/home/widgets/rehearsal_card.dart`     | Card rendering logic is correct; issue is layout-level         |
| `lib/features/home/widgets/section_header.dart`     | Widget is correct; issue is conditional rendering at call site |
| `lib/features/home/widgets/empty_section_card.dart` | Empty state widget is correct; no changes needed               |
| `lib/features/home/widgets/potential_gig_card.dart` | Potential events section rendering is correct                  |
| `lib/app/models/rehearsal.dart`                     | Data model is correct                                          |
| All other files                                     | Not related to this UI fix                                     |

---

## 12. System Impact Map

| System                                 | Impact     | Rationale                                                                 |
| -------------------------------------- | ---------- | ------------------------------------------------------------------------- |
| Gigs                                   | Unaffected | Change is isolated to rehearsals section rendering                        |
| Rehearsals                             | Affected   | Conditional rendering of section title when no confirmed rehearsals exist |
| Setlists / Catalog                     | Unaffected | No changes to setlist display logic                                       |
| Members / RBAC                         | Unaffected | No changes to permissions or role checks                                  |
| Auth / Session                         | Unaffected | No changes to authentication flow                                         |
| Routing                                | Unaffected | No changes to navigation logic                                            |
| Notifications                          | Unaffected | No changes to notification system                                         |
| Platform (iOS / Android / Web / macOS) | Unaffected | UI change applies consistently across all platforms                       |

---

## 13. Regression Risk

**Risk Level: LOW**

**Rationale:**

- Isolated UI change affecting only conditional rendering of one section title
- No state management changes
- No data fetching or business logic changes
- No changes to touch targets or interaction patterns
- Change follows existing pattern used by other dashboard sections
- Both code paths (primary and secondary) are updated for consistency

**Affected user scenarios:**

1. User with only potential rehearsals (no confirmed) → Will see "Potential Events" section but no "Upcoming Rehearsals" title (IMPROVED UX)
2. User with confirmed rehearsals → Will see "Upcoming Rehearsals" section as before (NO CHANGE)
3. User with no rehearsals at all → Will see "Upcoming Rehearsals" title + empty state card as before (NO CHANGE)

---

## 14. Engineer Task Breakdown

Execute in strict order:

### Task 1: Modify `home_tab_content.dart` — Add conditional wrapper for Upcoming Rehearsals section

**File:** `lib/features/home/home_tab_content.dart`  
**Location:** Lines 859-877

**Action:** Wrap the "Upcoming Rehearsals" section (comment, header, spacing, and content) in a conditional `if` statement

**Before:**

```dart
                                // Upcoming rehearsals section
                                const SectionHeader(
                                    title: 'Upcoming Rehearsals',
                                    topSpacing: Spacing.space24),
                                const SizedBox(height: Spacing.space12),
                                _AnimatedCardEntrance(
                                  delay: const Duration(milliseconds: 80),
                                  child: rehearsalState
                                          .confirmedRehearsals.isNotEmpty
                                      ? _buildHorizontalRehearsalsList(
                                          rehearsalState)
                                      : rehearsalState
                                              .potentialRehearsals.isNotEmpty
                                          ? const SizedBox.shrink()
                                          : EmptySectionCard(
                                              title: 'No Rehearsal Scheduled',
                                              buttonLabel: 'Schedule Rehearsal',
                                              onButtonPressed: isContributor
                                                  ? null
                                                  : () => _openAddEventSheet(
                                                        EventType.rehearsal,
                                                      ),
                                            ),
                                ),
```

**After:**

```dart
                                // Upcoming rehearsals section (only show when has confirmed or no rehearsals at all)
                                if (rehearsalState.confirmedRehearsals.isNotEmpty ||
                                    rehearsalState.potentialRehearsals.isEmpty) ...[
                                  const SectionHeader(
                                      title: 'Upcoming Rehearsals',
                                      topSpacing: Spacing.space24),
                                  const SizedBox(height: Spacing.space12),
                                  _AnimatedCardEntrance(
                                    delay: const Duration(milliseconds: 80),
                                    child: rehearsalState
                                            .confirmedRehearsals.isNotEmpty
                                        ? _buildHorizontalRehearsalsList(
                                            rehearsalState)
                                        : EmptySectionCard(
                                            title: 'No Rehearsal Scheduled',
                                            buttonLabel: 'Schedule Rehearsal',
                                            onButtonPressed: isContributor
                                                ? null
                                                : () => _openAddEventSheet(
                                                      EventType.rehearsal,
                                                    ),
                                          ),
                                  ),
                                ],
```

**Key changes:**

- Add `if` condition: `rehearsalState.confirmedRehearsals.isNotEmpty || rehearsalState.potentialRehearsals.isEmpty`
- Wrap all section elements in spread operator list `...[...]`
- Update comment to explain the condition
- Simplify inner ternary: remove `potentialRehearsals.isNotEmpty` check since it's redundant (outer `if` already filters this case)

### Task 2: Modify `home_screen.dart` — Add conditional wrapper for Upcoming Rehearsals section

**File:** `lib/features/home/home_screen.dart`  
**Location:** Lines 765-803

**Action:** Wrap the "Upcoming Rehearsals" section (comment, header, spacing, and content) in a conditional `if` statement

**Before:**

```dart
        // Upcoming rehearsals section
        const SectionHeader(title: 'Upcoming Rehearsals'),
        const SizedBox(height: Spacing.space12),
        _AnimatedCardEntrance(
          delay: const Duration(milliseconds: 100),
          child: nextRehearsal != null
              ? Builder(
                  builder: (context) {
                    // Look up setlist name from setlistId
                    String? setlistName;
                    if (nextRehearsal.setlistId != null) {
                      final setlist = setlistsState.setlists
                          .where(
                            (s) => s.id == nextRehearsal.setlistId,
                          )
                          .firstOrNull;
                      setlistName = setlist?.name;
                    }
                    return RehearsalCard(
                      rehearsal: nextRehearsal,
                      bandTimezone: bandTimezone,
                      setlistName: setlistName,
                      onTap: () => _openEditRehearsalSheet(
                        nextRehearsal,
                      ),
                    );
                  },
                )
              : EmptySectionCard(
                  title: 'No Rehearsal Scheduled',
                  buttonLabel: 'Schedule Rehearsal',
                  onButtonPressed: isContributor
                      ? null
                      : () => _openAddEventSheet(
                            EventType.rehearsal,
                          ),
                ),
        ),
```

**After:**

```dart
        // Upcoming rehearsals section (only show when has confirmed or when no potential gig prompt)
        if (nextRehearsal != null || potentialGig == null) ...[
          const SectionHeader(title: 'Upcoming Rehearsals'),
          const SizedBox(height: Spacing.space12),
          _AnimatedCardEntrance(
            delay: const Duration(milliseconds: 100),
            child: nextRehearsal != null
                ? Builder(
                    builder: (context) {
                      // Look up setlist name from setlistId
                      String? setlistName;
                      if (nextRehearsal.setlistId != null) {
                        final setlist = setlistsState.setlists
                            .where(
                              (s) => s.id == nextRehearsal.setlistId,
                            )
                            .firstOrNull;
                        setlistName = setlist?.name;
                      }
                      return RehearsalCard(
                        rehearsal: nextRehearsal,
                        bandTimezone: bandTimezone,
                        setlistName: setlistName,
                        onTap: () => _openEditRehearsalSheet(
                          nextRehearsal,
                        ),
                      );
                    },
                  )
                : EmptySectionCard(
                    title: 'No Rehearsal Scheduled',
                    buttonLabel: 'Schedule Rehearsal',
                    onButtonPressed: isContributor
                        ? null
                        : () => _openAddEventSheet(
                              EventType.rehearsal,
                            ),
                  ),
          ),
        ],
```

**Key changes:**

- Add `if` condition: `nextRehearsal != null || potentialGig == null`
- Wrap all section elements in spread operator list `...[...]`
- Update comment to explain the condition

**Rationale for condition:** In `home_screen.dart`, there's no separate list of potential rehearsals, so we use `nextRehearsal != null` as proxy for "has confirmed rehearsals". We also check `potentialGig == null` to ensure the empty state card shows when there are no potential events at all. This matches the UX intent: hide the section when there might be potential rehearsals being shown above.

### Task 3: Run `flutter analyze`

**Command:** `flutter analyze`  
**Expected:** 0 errors, 0 warnings  
**Action:** Verify no syntax errors or lint warnings introduced by the changes

### Task 4: Visual verification

**Command:** `flutter run -d chrome`  
**Actions:**

1. Test scenario 1: User with only potential rehearsals
   - Expected: "Potential Events" section visible, "Upcoming Rehearsals" section hidden
2. Test scenario 2: User with at least one confirmed rehearsal
   - Expected: "Upcoming Rehearsals" section visible with content
3. Test scenario 3: User with no rehearsals at all
   - Expected: "Upcoming Rehearsals" section visible with empty state card

### Task 5: Generate ENGINEER_REPORT.md

**Location:** `docs/features/hide-upcoming-rehearsals-title/ENGINEER_REPORT.md`  
**Content:**

- Confirm all tasks completed
- List modified files
- Include `git diff` output
- Document any deviations (should be none)
- Confirm `flutter analyze` passed
- Describe visual verification results

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (Static Verification)

**Not applicable** (no database changes)

### Tier 2 — Post-deployment (Client Verification)

#### TEST 1: Verify conditional rendering in primary dashboard

**Platform:** Web (Chrome)

**Steps:**

1. Log in to BandRoadie
2. Ensure active band has:
   - At least 1 potential rehearsal (`isPotential=true`)
   - Zero confirmed rehearsals (`isPotential=false`)
3. Navigate to Dashboard (Home tab)

**Expected:**

- "Potential Events" horizontal scroll section is visible at top
- Potential rehearsal card(s) are visible in that section
- "Upcoming Rehearsals" section title is NOT visible
- No empty space where "Upcoming Rehearsals" section would be

**Query to verify data state:**

```sql
SELECT id, location, date, is_potential
FROM rehearsals
WHERE band_id = '<active-band-id>'
  AND date >= CURRENT_DATE
ORDER BY date;
```

#### TEST 2: Verify title shows when confirmed rehearsals exist

**Platform:** Web (Chrome)

**Steps:**

1. Same band as TEST 1
2. Create one confirmed rehearsal (via "Schedule Rehearsal" button or edit existing potential to confirmed)
3. Observe dashboard

**Expected:**

- "Upcoming Rehearsals" section title IS visible
- Horizontal scroll row shows confirmed rehearsal(s)
- Section header renders above the content

#### TEST 3: Verify title shows for empty state when no rehearsals at all

**Platform:** iOS

**Steps:**

1. Log in with band that has zero rehearsals (confirmed or potential)
2. Navigate to Dashboard

**Expected:**

- "Upcoming Rehearsals" section title IS visible
- Empty state card renders below title
- Card shows "No Rehearsal Scheduled" message
- "Schedule Rehearsal" button is visible (unless user is contributor)

#### TEST 4: Verify legacy dashboard path (home_screen.dart)

**Platform:** macOS

**Steps:**

1. Navigate to Setlists tab
2. Use back navigation to return to Dashboard (this should use `HomeScreen` widget)
3. Observe rehearsal section

**Expected:**

- Conditional rendering logic applies consistently
- If no confirmed rehearsals but has potential gig: section might be hidden (depending on data state)
- If has confirmed rehearsal or no potential events: section is visible

#### TEST 5: Verify no regression to gigs section

**Platform:** Android

**Steps:**

1. Log in with band that has gigs (potential or confirmed)
2. Navigate to Dashboard
3. Observe "Upcoming Gigs" section

**Expected:**

- "Upcoming Gigs" section title always renders (no change)
- Content displays correctly (no regression)

#### TEST 6: Cross-platform consistency

**Platforms:** iOS, Android, Web, macOS

**Steps:**

1. Repeat TEST 1 on each platform
2. Verify identical behavior

**Expected:**

- Conditional rendering works consistently on all platforms
- No platform-specific rendering issues

---

## 16. QA Regression Areas

### Primary Verification

**Dashboard Rehearsal Section Rendering:**

1. **Scenario: Only potential rehearsals exist**
   - Given: Band has 2 potential rehearsals, 0 confirmed rehearsals
   - When: User opens Dashboard
   - Then: "Potential Events" section shows both potential rehearsals
   - And: "Upcoming Rehearsals" section title is NOT rendered
   - And: No orphaned title or empty space
   - Platforms: iOS, Android, Web, macOS

2. **Scenario: Only confirmed rehearsals exist**
   - Given: Band has 2 confirmed rehearsals, 0 potential rehearsals
   - When: User opens Dashboard
   - Then: "Upcoming Rehearsals" section title IS rendered
   - And: Horizontal scroll row shows both confirmed rehearsals
   - Platforms: iOS, Android, Web, macOS

3. **Scenario: Mixed rehearsals (potential and confirmed)**
   - Given: Band has 1 potential rehearsal and 2 confirmed rehearsals
   - When: User opens Dashboard
   - Then: "Potential Events" section shows the potential rehearsal
   - And: "Upcoming Rehearsals" section title IS rendered
   - And: Section shows 2 confirmed rehearsals in horizontal scroll
   - Platforms: iOS, Android, Web, macOS

4. **Scenario: No rehearsals at all**
   - Given: Band has 0 rehearsals (confirmed or potential)
   - When: User opens Dashboard
   - Then: "Upcoming Rehearsals" section title IS rendered
   - And: Empty state card shows "No Rehearsal Scheduled"
   - And: "Schedule Rehearsal" button is visible (for admins/members)
   - Platforms: iOS, Android, Web, macOS

5. **Scenario: Legacy dashboard path (from setlists navigation)**
   - Given: User is viewing Setlists screen
   - When: User navigates back to Dashboard using back button/navigation
   - Then: Rehearsal section renders with same conditional logic
   - Platforms: iOS, Web

### Regression Verification

**Other Dashboard Sections:**

1. **Potential Events section** — Verify no changes to rendering logic
2. **Upcoming Gigs section** — Verify title always shows (unchanged)
3. **Quick Actions section** — Verify no layout shifts or interaction issues
4. **Empty state (no events at all)** — Verify `EmptyHomeState` widget still renders correctly

**Interaction Patterns:**

1. **Create Rehearsal flow** — Verify "Schedule Rehearsal" button opens correct sheet/modal
2. **Edit Rehearsal flow** — Verify tapping rehearsal card opens edit sheet
3. **Rehearsal response flow** — Verify YES/NO buttons on potential rehearsal cards work correctly
4. **Scroll behavior** — Verify horizontal scroll rows work smoothly

**Navigation:**

1. **AppShell navigation** — Verify switching between Home/Calendar/Setlists tabs works correctly
2. **Deep link to dashboard** — Verify URL routing to dashboard renders correctly
3. **Setlists → Dashboard navigation** — Verify back navigation from setlists uses correct rendering logic

---

## 17. Rollout / Migration Strategy

**Not applicable**

This is a client-side UI change only. No backend deployment, migration, or rollout coordination required.

**Deployment:**
Standard web and app store deployment after QA approval:

- Web: `./tools/deploy_web.sh`
- iOS/Android: Next app store release

---

## 18. Out of Scope

**Explicitly NOT included in this change:**

❌ Changing how potential vs confirmed rehearsals are categorized (data model unchanged)  
❌ Modifying the "Potential Events" section rendering logic  
❌ Changing rehearsal card design or content  
❌ Updating empty state card copy or button labels  
❌ Modifying section header styling or spacing  
❌ Changing animation timing or delays  
❌ Adding new dashboard sections or widgets  
❌ Modifying gigs section conditional rendering (out of scope — gigs section should keep current behavior)  
❌ Updating `EmptyHomeState` widget (fully empty dashboard) — already works correctly  
❌ Changing rehearsal response (YES/NO) functionality  
❌ Modifying RBAC permissions for creating rehearsals

---

**ARCHITECT PLAN COMPLETE**
