# ARCHITECT_PLAN.md

## Feature Slug

`home-rehearsal-scroll-row`

## Problem Summary

The home screen currently displays only a single "Next Rehearsal" card under the "Upcoming Rehearsals" section header. Users cannot see additional upcoming rehearsals without navigating to the calendar. This is inconsistent with the "Upcoming Gigs" section, which displays all upcoming confirmed gigs in a horizontal scrollable row.

## Root Cause

**Confidence:** HIGH

The home screen UI in `lib/features/home/home_tab_content.dart` (line ~827) renders only `rehearsalState.nextRehearsal` (a single `Rehearsal` object) instead of consuming `rehearsalState.confirmedRehearsals` (a `List<Rehearsal>` containing all confirmed rehearsals).

The data layer already provides all confirmed rehearsals via `RehearsalState.confirmedRehearsals`, but the UI was never implemented to display them in a horizontal scroll row. The implementation stopped at showing only the next single rehearsal.

**Evidence:**

- `RehearsalState` (rehearsal_controller.dart, line 22) has `List<Rehearsal> confirmedRehearsals`
- home_tab_content.dart line ~827: renders single `RehearsalCard` for `nextRehearsal` only
- home_tab_content.dart line ~858: already has `_buildHorizontalGigsList` for all confirmed gigs — the pattern to follow

## Reference Docs Consulted

No reference documentation exists for the home or rehearsals domains. Checked:

- `docs/reference/home/` — does not exist
- `docs/reference/rehearsals/` — does not exist

## Existing System Analysis

### Data Flow (Current):

1. `bandFullStateProvider` fetches all band data via Supabase RPC (includes all rehearsals)
2. `RehearsalNotifier.build()` receives rehearsals and calls `_categorizeRehearsals()`
3. `_categorizeRehearsals()` separates rehearsals into:
   - `upcomingRehearsals` — all rehearsals with date >= today and end time in future
   - `confirmedRehearsals` — subset of `upcomingRehearsals` where `isPotential == false`
   - `potentialRehearsals` — subset of `upcomingRehearsals` where `isPotential == true`
   - `nextRehearsal` — first element of `confirmedRehearsals` (or null if empty)
4. `HomeTabContent` widget watches `rehearsalProvider` and renders:
   - **Potential events row** (line ~770): horizontal scroll of potential gigs + potential rehearsals (already working)
   - **Upcoming Rehearsals section** (line ~827): single `RehearsalCard` for `nextRehearsal` **← THIS IS THE GAP**
   - **Upcoming Gigs section** (line ~858): horizontal scroll of all confirmed gigs via `_buildHorizontalGigsList`

### Card Widgets:

- `RehearsalCard` (lib/features/home/widgets/rehearsal_card.dart):
  - Supports both confirmed and potential variants
  - Uses `minHeight: Spacing.rehearsalCardHeight` (130.0) for confirmed rehearsals
  - Already used in horizontal scroll context (potential rehearsals row, line ~1004)
  - Takes `onTap`, `setlistName`, `bandTimezone` props
- `ConfirmedGigCard` (lib/features/home/widgets/confirmed_gig_card.dart):
  - Used in horizontal scroll for confirmed gigs
  - Height: `Spacing.gigCardHeight` (126.0)
  - Similar pattern to follow

## Proposed Solution

**Replace the single rehearsal card with a horizontal scroll row of all confirmed rehearsals, mirroring the existing "Upcoming Gigs" pattern.**

### Changes:

1. **Add `_buildHorizontalRehearsalsList` method** in home_tab_content.dart:
   - Mirror the structure of `_buildHorizontalGigsList` (line ~1036-1058)
   - Accept `RehearsalState rehearsalState` parameter
   - Extract `rehearsalState.confirmedRehearsals`
   - Return `SizedBox` with height `Spacing.rehearsalCardHeight`
   - Use `ListView.separated` with horizontal scroll
   - Render each rehearsal as a `RehearsalCard` with setlist name lookup
   - Include `onTap: () => _openEditRehearsalSheet(rehearsal)`

2. **Update "Upcoming Rehearsals" section** (line ~827-850):
   - Change condition from `nextRehearsal != null` to `confirmedRehearsals.isNotEmpty`
   - Replace single `RehearsalCard` builder with call to `_buildHorizontalRehearsalsList(rehearsalState)`
   - Retain empty state logic when `confirmedRehearsals.isEmpty`

3. **Empty state logic**:
   - If `confirmedRehearsals.isEmpty` AND `potentialRehearsals.isNotEmpty`:
     - Render `SizedBox.shrink()` (potential rehearsals already shown in top row)
   - If `confirmedRehearsals.isEmpty` AND `potentialRehearsals.isEmpty`:
     - Render `EmptySectionCard` with "No Rehearsal Scheduled" message

### Design Tokens:

- Use `Spacing.rehearsalCardHeight` (130.0) for scroll container height
- Use `Spacing.space16` (16.0) for horizontal spacing between cards
- Match separator pattern from `_buildHorizontalGigsList`

## Database Impact

**Not applicable**

All required data is already fetched via `bandFullStateProvider`. No schema changes, RLS changes, RPC changes, or migrations needed.

## Flutter Architecture Changes

**State:** No changes. `RehearsalState.confirmedRehearsals` already provides all data.

**Widgets:** No new widgets. Reuse existing `RehearsalCard`.

**Repositories:** No changes.

**Controllers:** No changes.

## Files to Create

**None**

## Files to Modify

| File                                      | Description                                                                                                                                                                                                           |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/home_tab_content.dart` | Add `_buildHorizontalRehearsalsList` method (after line ~1058, following `_buildHorizontalGigsList`). Update "Upcoming Rehearsals" section (line ~827-850) to call this method when `confirmedRehearsals.isNotEmpty`. |

## Files Off-Limits

| File                                                | Reason                                                                            |
| --------------------------------------------------- | --------------------------------------------------------------------------------- |
| `lib/features/rehearsals/rehearsal_controller.dart` | Data fetching already works correctly; `confirmedRehearsals` is already populated |
| `lib/features/rehearsals/rehearsal_repository.dart` | No changes to data layer required                                                 |
| `lib/features/home/widgets/rehearsal_card.dart`     | Card already supports horizontal layout; no modifications needed                  |
| `lib/features/home/home_screen.dart`                | Obsolete file; all logic migrated to home_tab_content.dart                        |
| `lib/main.dart`                                     | Init order must not change                                                        |

## System Impact Map

| System                                 | Impact                                                             |
| -------------------------------------- | ------------------------------------------------------------------ |
| Gigs                                   | unaffected                                                         |
| Rehearsals                             | affected — display logic only (UI change in home_tab_content.dart) |
| Setlists / Catalog                     | unaffected                                                         |
| Members / RBAC                         | unaffected                                                         |
| Auth / Session                         | unaffected                                                         |
| Routing                                | unaffected                                                         |
| Notifications                          | unaffected                                                         |
| Platform (iOS / Android / Web / macOS) | affected — UI change applies to all platforms                      |

## Regression Risk

**Level:** LOW

**Rationale:**

- Single-file change, purely presentational
- No state management changes (reuses existing `confirmedRehearsals` list)
- No data fetching changes (uses existing rehearsal provider)
- No database or backend changes
- Mirrors existing proven pattern (`_buildHorizontalGigsList`)
- `RehearsalCard` already tested in horizontal scroll context (potential rehearsals section)
- Does not touch auth, session, routing, or init order
- No changes to other home screen sections (gigs, quick actions, potential events)

## Engineer Task Breakdown

Execute in order:

1. **Add `_buildHorizontalRehearsalsList` method**
   - Place after `_buildHorizontalGigsList` method (line ~1058)
   - Method signature: `Widget _buildHorizontalRehearsalsList(RehearsalState rehearsalState)`
   - Extract `final confirmedRehearsals = rehearsalState.confirmedRehearsals;`
   - Return `SizedBox.shrink()` if empty
   - Return `SizedBox(height: Spacing.rehearsalCardHeight, child: ListView.separated(...))`
   - `scrollDirection: Axis.horizontal`, `clipBehavior: Clip.none`
   - `itemCount: confirmedRehearsals.length`
   - `separatorBuilder: (context, index) => const SizedBox(width: 16)`
   - `itemBuilder`: Lookup setlist name from `setlistsState`, render `RehearsalCard` with:
     - `rehearsal: confirmedRehearsals[index]`
     - `setlistName: setlistName` (from lookup)
     - `bandTimezone: ref.watch(activeBandProvider).activeBand?.timezone ?? 'America/Chicago'`
     - `onTap: () => _openEditRehearsalSheet(rehearsal)`

2. **Update "Upcoming Rehearsals" section in `_buildContentState`**
   - Locate the `_AnimatedCardEntrance` widget at line ~831 (delay: 80ms)
   - Replace condition from `nextRehearsal != null` to `rehearsalState.confirmedRehearsals.isNotEmpty`
   - Replace single `Builder` + `RehearsalCard` with call to `_buildHorizontalRehearsalsList(rehearsalState)`
   - Retain empty state logic:
     - If `confirmedRehearsals.isEmpty` AND `potentialRehearsals.isNotEmpty`: render `SizedBox.shrink()`
     - If `confirmedRehearsals.isEmpty` AND `potentialRehearsals.isEmpty`: render `EmptySectionCard`

3. **Run `flutter analyze` and verify zero errors**
   - Fix any linting issues
   - Confirm no type errors or warnings

4. **Manual verification**
   - Hot reload on macOS or web
   - Confirm horizontal scroll row appears with multiple rehearsals
   - Confirm empty state still works when no rehearsals exist
   - Confirm setlist names appear correctly
   - Confirm tap on rehearsal card opens edit drawer

## Verification Plan

### Tier 1 — Pre-deployment (manual testing only)

**Not applicable** — This feature has no database or backend changes. All verification is manual UI testing.

### Tier 2 — Post-deployment (manual testing)

**Test 1: Multiple confirmed rehearsals render in horizontal scroll row**

- Given: User has 3 confirmed rehearsals scheduled
- When: User opens home screen
- Then: "Upcoming Rehearsals" section shows horizontal scroll row with 3 cards
- And: Cards scroll horizontally with proper spacing (16px between cards)
- Platform: macOS, iOS, Web

**Test 2: Single confirmed rehearsal renders correctly**

- Given: User has 1 confirmed rehearsal scheduled
- When: User opens home screen
- Then: "Upcoming Rehearsals" section shows horizontal scroll row with 1 card
- And: Card is not stretched to full width (matches `RehearsalCard` intrinsic width)
- Platform: macOS

**Test 3: No confirmed rehearsals shows empty state**

- Given: User has 0 confirmed rehearsals and 0 potential rehearsals
- When: User opens home screen
- Then: "Upcoming Rehearsals" section shows `EmptySectionCard` with "No Rehearsal Scheduled" message
- And: "Schedule Rehearsal" button is visible (for admin/member, hidden for contributor)
- Platform: Web

**Test 4: Potential rehearsals do not appear in confirmed row**

- Given: User has 2 potential rehearsals (isPotential=true) and 1 confirmed rehearsal
- When: User opens home screen
- Then: Top "Potential Events" row shows 2 potential rehearsals
- And: "Upcoming Rehearsals" section shows horizontal scroll row with 1 confirmed rehearsal only
- Platform: iOS

**Test 5: Setlist names display correctly**

- Given: Confirmed rehearsal has setlistId linked to setlist "Full Set A"
- When: User opens home screen
- Then: Rehearsal card displays "Full Set A" as setlist name
- Platform: macOS

**Test 6: Tap on rehearsal card opens edit drawer**

- Given: User is admin/member (not contributor)
- When: User taps on confirmed rehearsal card
- Then: Edit Event drawer opens with rehearsal details pre-populated
- Platform: macOS

**Test 7: Rehearsal order matches date proximity**

- Given: User has 3 confirmed rehearsals (dates: May 22, May 25, May 30)
- When: User opens home screen
- Then: Rehearsal cards appear in order: May 22, May 25, May 30 (left to right)
- Platform: Web

**Test 8: Confirmed rehearsals section hidden when only potential rehearsals exist**

- Given: User has 2 potential rehearsals and 0 confirmed rehearsals
- When: User opens home screen
- Then: "Upcoming Rehearsals" section renders `SizedBox.shrink()` (no empty state, no scroll row)
- And: Only the top "Potential Events" row is visible
- Platform: macOS

## QA Regression Areas

QA must specifically test:

1. **Home screen rehearsal display**
   - Multiple confirmed rehearsals in horizontal scroll row
   - Single confirmed rehearsal renders correctly (not stretched)
   - Empty state when no rehearsals exist
   - Setlist names appear correctly on rehearsal cards

2. **Potential rehearsals (no regression)**
   - Potential rehearsals still appear in top "Potential Events" horizontal row
   - Potential rehearsals do NOT appear in "Upcoming Rehearsals" section
   - Availability buttons (YES/NO) still work on potential rehearsal cards

3. **Upcoming Gigs (no regression)**
   - Confirmed gigs horizontal scroll row still works
   - Empty state for gigs still works
   - Tap on gig card still opens edit drawer

4. **Rehearsal edit flow (no regression)**
   - Tap on confirmed rehearsal card opens edit drawer
   - Editing rehearsal refreshes home screen correctly
   - Deleting rehearsal removes it from home screen

5. **RBAC (no regression)**
   - Contributors cannot tap rehearsal cards to edit (onTap is null)
   - Admin/member can tap rehearsal cards to edit
   - Empty state "Schedule Rehearsal" button hidden for contributors

6. **Platform consistency**
   - Test on iOS, Android, macOS, and Web
   - Confirm horizontal scroll behavior works on all platforms
   - Confirm touch targets are accessible (48px minimum)

## Rollout / Migration Strategy

**Not applicable** — Pure UI change with no backend or data migration required.

Deployment: Standard web deploy via `./tools/deploy_web.sh` after QA approval. Mobile apps will receive the change in next build/release.

## Out of Scope

The following are explicitly **not** included in this feature:

1. Changes to rehearsal data fetching logic (already works correctly)
2. Changes to RehearsalCard widget design or behavior
3. Changes to rehearsal edit drawer or form
4. Changes to potential rehearsals display (already horizontal scroll)
5. Changes to rehearsal detail screen or routing
6. Changes to rehearsal creation flow
7. Changes to rehearsal response/availability tracking
8. Changes to recurring rehearsal display logic
9. Performance optimizations for large rehearsal lists
10. Accessibility enhancements beyond existing RehearsalCard behavior

---

**Architect approval:** Ready for Engineer implementation.
**Branch:** `feature/home-rehearsal-scroll-row`
