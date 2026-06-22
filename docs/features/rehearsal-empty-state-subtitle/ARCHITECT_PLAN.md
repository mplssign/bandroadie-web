# ARCHITECT PLAN — Rehearsal Empty State Subtitle Removal

## Feature Slug

`bug/rehearsal-empty-state-subtitle`

## Problem Summary

The subtitle text "The stage is empty and the amps are cold." is still displaying under the "No Rehearsal Scheduled" empty state in the deployed web app (version 1.2.21+176). Despite commit `d20697f` ("fix: remove empty rehearsal subtitle from home empty state") being merged to main, the subtitle text persists in production on the web platform.

## Root Cause

**Confidence Level: HIGH**

The subtitle exists in **three separate locations** in the codebase:

1. **`lib/features/home/widgets/empty_home_state.dart`** — Fixed by commit d20697f ✓  
   This widget renders when the user has ZERO gigs AND ZERO rehearsals (completely empty state).

2. **`lib/features/home/home_tab_content.dart` line 876** — NOT FIXED ⚠️  
   This is the PRIMARY active code path used by `AppShell` (the main navigation shell). It renders the rehearsal empty section when the user has events but specifically no rehearsals.

3. **`lib/features/home/home_screen.dart` line 795** — NOT FIXED ⚠️  
   This is a SECONDARY code path used for specific navigation scenarios (e.g., `setlists_screen.dart` navigating back to dashboard via `_navigateToDashboard()`).

The previous fix only addressed location #1 (`empty_home_state.dart`), which handles the fully empty state. However, the user is likely viewing the dashboard with some events (gigs) but no rehearsals, which triggers the empty section card in `home_tab_content.dart` (location #2) — this is the code path actively being rendered in production.

**Why this was missed:**

- Multiple rendering contexts for the same UI element
- The same `EmptySectionCard` widget is instantiated in three different places
- The fix targeted the wrong variant (fully empty state vs. section empty state)

## Reference Docs Consulted

Not applicable — this is a UI text display bug with no domain documentation requirements.

## Existing System Analysis

### Current Behavior

When a user views the dashboard:

**Scenario A: No events at all**

- `AppShell` → `HomeTabContent` → checks if no gigs AND no rehearsals
- Renders `EmptyHomeState` widget (from `empty_home_state.dart`)
- This variant was fixed by commit d20697f ✓

**Scenario B: Has events, but no rehearsals** (PRODUCTION ISSUE)

- `AppShell` → `HomeTabContent` → renders main content with event sections
- Rehearsal section shows `EmptySectionCard` directly in `home_tab_content.dart` line 876
- Subtitle "The stage is empty and the amps are cold." is rendered ⚠️

**Scenario C: Navigation from setlists screen**

- User in `setlists_screen.dart` taps back to dashboard
- `_navigateToDashboard()` uses `Navigator.pushReplacement` with `HomeScreen`
- `HomeScreen` renders its own copy of the empty state with subtitle at line 795 ⚠️

### Architecture Context

```
main.dart
  └─ app.dart
      └─ AppShell (primary navigation shell)
          └─ IndexedStack
              ├─ Tab 0: HomeTabContent ← PRIMARY DASHBOARD (ACTIVE)
              ├─ Tab 1: SetlistsTabContent
              ├─ Tab 2: CalendarTabContent
              └─ Tab 3: ContactsTabContent

Legacy/alternate path:
  setlists_screen.dart → _navigateToDashboard()
      └─ Navigator.pushReplacement(HomeScreen) ← SECONDARY PATH
```

## Proposed Solution

Remove the `subtitle` parameter from both `EmptySectionCard` widget instantiations:

1. **`lib/features/home/home_tab_content.dart` line 876**  
   Remove the line: `subtitle: 'The stage is empty and the amps are cold.',`

2. **`lib/features/home/home_screen.dart` line 795**  
   Remove the line: `subtitle: 'The stage is empty and the amps are cold.',`

The `EmptySectionCard` widget already handles `null` subtitles gracefully by not rendering the subtitle text widget when the parameter is omitted or `null`.

**Why this is minimal:**

- Only removes subtitle text — no logic changes
- No new widgets or abstractions needed
- No changes to empty state behavior or button callbacks
- Follows the pattern established by commit d20697f

## Database Impact

**Not applicable** — This is a client-side UI text change with no database interaction.

## Flutter Architecture Changes

### State Management

No state management changes required. The `EmptySectionCard` widget is stateless and receives all props from parent widgets.

### Widgets Affected

- `home_tab_content.dart` — Remove subtitle prop from `EmptySectionCard` (line ~876)
- `home_screen.dart` — Remove subtitle prop from `EmptySectionCard` (line ~795)

### Repositories

No repository changes required.

### Controllers/Providers

No controller or provider changes required.

## Files to Create

**None** — This is a text removal fix only.

## Files to Modify

| File                                      | What changes                                                                                                                                        |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/home_tab_content.dart` | Remove `subtitle: 'The stage is empty and the amps are cold.',` from `EmptySectionCard` widget instantiation at line ~876 (rehearsal empty section) |
| `lib/features/home/home_screen.dart`      | Remove `subtitle: 'The stage is empty and the amps are cold.',` from `EmptySectionCard` widget instantiation at line ~795 (rehearsal empty section) |

## Files Off-Limits

| File                                                | Reason                                                       |
| --------------------------------------------------- | ------------------------------------------------------------ |
| `lib/main.dart`                                     | Init order must not change (GUARDRAILS.md §1)                |
| `lib/features/home/widgets/empty_home_state.dart`   | Already fixed by commit d20697f — do not modify              |
| `lib/features/home/widgets/empty_section_card.dart` | Widget implementation is correct — accepts optional subtitle |
| `lib/features/gigs/*`                               | Gig empty states are out of scope                            |
| `lib/features/setlists/*`                           | Setlist empty states are out of scope                        |

## System Impact Map

| System                                 | Impact                                                   |
| -------------------------------------- | -------------------------------------------------------- |
| Gigs                                   | unaffected                                               |
| Rehearsals                             | affected — empty state subtitle removed                  |
| Setlists / Catalog                     | unaffected                                               |
| Members / RBAC                         | unaffected                                               |
| Auth / Session                         | unaffected                                               |
| Routing                                | unaffected                                               |
| Notifications                          | unaffected                                               |
| Platform (iOS / Android / Web / macOS) | affected — all platforms render the same Flutter widgets |

## Regression Risk

**Level: LOW**

**Rationale:**

- Only removes display text — no logic changes
- No state management, navigation, or data flow modifications
- EmptySectionCard widget already supports `null` subtitle (proven by empty_home_state.dart after d20697f)
- Change is identical in pattern to the previous successful fix (d20697f)
- No cross-system dependencies affected

**Potential edge cases:**

- None identified — this is a pure text removal

## Engineer Task Breakdown

Execute in order:

### Task 1: Remove subtitle from home_tab_content.dart

- Open `lib/features/home/home_tab_content.dart`
- Locate the `EmptySectionCard` widget instantiation for rehearsals (line ~876)
- Remove the entire line: `subtitle: 'The stage is empty and the amps are cold.',`
- Verify the closing parenthesis/comma alignment remains correct

### Task 2: Remove subtitle from home_screen.dart

- Open `lib/features/home/home_screen.dart`
- Locate the `EmptySectionCard` widget instantiation for rehearsals (line ~795)
- Remove the entire line: `subtitle: 'The stage is empty and the amps are cold.',`
- Verify the closing parenthesis/comma alignment remains correct

### Task 3: Verify compilation

- Run `flutter analyze`
- Confirm 0 errors
- If warnings exist unrelated to this change, document them but do not fix

### Task 4: Visual verification

- Run the app on web: `flutter run -d chrome`
- Navigate to dashboard
- Verify the rehearsal empty state shows title "No Rehearsal Scheduled" with NO subtitle
- Verify button "Schedule Rehearsal" is still present and functional

### Task 5: Generate ENGINEER_REPORT.md

- Document all changes made
- Include `git diff` output
- Confirm all Architect tasks completed
- List any deviations (should be none)

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable** — No database or backend changes.

### Tier 2 — Post-deployment

#### TEST 1: Rehearsal empty state displays correctly in primary dashboard

```
Platform: Web (Chrome)
Steps:
1. Log in to BandRoadie web app
2. Ensure user has a band with gigs but NO rehearsals scheduled
3. Navigate to Dashboard (home tab)
4. Observe rehearsal section

Expected:
- Section shows "No Rehearsal Scheduled" as title
- NO subtitle text appears
- "Schedule Rehearsal" button is present and functional
```

#### TEST 2: Rehearsal empty state displays correctly in legacy HomeScreen

```
Platform: Web (Chrome)
Steps:
1. Log in to BandRoadie web app
2. Navigate to Setlists tab
3. From setlists screen, navigate back to Dashboard using any back/home navigation
4. Observe rehearsal section (if navigated via HomeScreen path)

Expected:
- Section shows "No Rehearsal Scheduled" as title
- NO subtitle text appears
- "Schedule Rehearsal" button is present and functional
```

#### TEST 3: Fully empty state remains fixed (regression check)

```
Platform: Web (Chrome)
Steps:
1. Log in to BandRoadie web app
2. Ensure user has a band with ZERO gigs AND ZERO rehearsals
3. Navigate to Dashboard

Expected:
- EmptyHomeState widget renders
- Rehearsal section shows "No Rehearsal Scheduled" as title
- NO subtitle text appears (confirmed fixed by d20697f)
- "Create Rehearsal" button is present
```

#### TEST 4: Cross-platform consistency

```
Platforms: iOS, Android, macOS
Steps:
1. Repeat TEST 1 on each native platform
2. Verify identical behavior (no subtitle)

Expected:
- Consistent behavior across all platforms
- No subtitle text on any platform
```

## QA Regression Areas

QA must specifically validate:

1. **Rehearsal empty state on Dashboard (primary focus)**
   - Scenario: User has gigs but no rehearsals
   - Verify: No subtitle text appears
   - Platforms: Web, iOS, Android, macOS

2. **Fully empty dashboard (regression check)**
   - Scenario: User has zero events (no gigs, no rehearsals)
   - Verify: EmptyHomeState widget still has no subtitle (from d20697f fix)
   - Platforms: Web, iOS, Android, macOS

3. **Gig empty states (regression check — should be unaffected)**
   - Scenario: User has rehearsals but no gigs
   - Verify: Gig empty state displays correctly (not modified by this change)
   - Platforms: Web, iOS, Android, macOS

4. **Navigation flows (ensure HomeScreen path still works)**
   - Navigate: Setlists → back to Dashboard
   - Navigate: Calendar → back to Dashboard
   - Navigate: Members → back to Dashboard
   - Verify: No subtitle appears regardless of navigation path

5. **Empty state button functionality**
   - Click "Schedule Rehearsal" button from empty state
   - Verify: Add Event bottom sheet opens with Rehearsal pre-selected
   - Verify: Creating a rehearsal removes the empty state

## Rollout / Migration Strategy

**Not applicable** — Pure client-side UI text change. No migration required. Change takes effect immediately on next web deployment or next app update for native platforms.

## Out of Scope

Explicitly excluded from this fix:

- Gig empty state subtitles (not part of the reported issue)
- Setlist empty state subtitles (not part of the reported issue)
- Catalog empty state subtitles (not part of the reported issue)
- Any other "roadie humor" text in the app (only rehearsal subtitle is in scope)
- Refactoring `EmptySectionCard` widget to centralize empty state text
- Consolidating `HomeScreen` and `HomeTabContent` into a single component
- Removing legacy navigation paths (e.g., `_navigateToDashboard()` in setlists_screen.dart)
