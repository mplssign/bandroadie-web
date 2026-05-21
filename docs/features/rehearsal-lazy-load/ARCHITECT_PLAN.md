# ARCHITECT_PLAN.md

## Feature Slug

`feature/rehearsal-lazy-load`

## Problem Summary

The Upcoming Rehearsals section on the home screen uses a button-based pagination approach for open-ended recurring rehearsals (no `recurrence_until` date). Users must tap a "Load More" button to see the next 10 occurrences. The feature request specifies that infinite scroll should be implemented instead — the next 10 occurrences should load automatically when the user scrolls to the bottom of the horizontal list, without requiring any button tap.

## Root Cause

**Confidence:** HIGH

The `ListView.separated` in `_buildHorizontalRehearsalsList()` (home_tab_content.dart, line ~1067-1119) has no `ScrollController` and no scroll position listener. The current implementation renders a `LoadMoreRehearsalsCard` button as the final item in the list, which the user must tap to trigger `ref.read(rehearsalPaginationProvider.notifier).loadMore(seriesId)`. There is no mechanism to detect scroll position and auto-trigger loading.

**Evidence:**

- Line 1068 in home_tab_content.dart: `ListView.separated(...)` has no `controller:` parameter
- Line 1081-1091: `LoadMoreRehearsalsCard` is conditionally rendered when `item.isLoadMore == true`
- No scroll listener exists to detect when scroll position approaches the end of the list
- Pagination state management (`RehearsalPaginationController`) and series grouping (`RehearsalDisplayHelper`) already exist and work correctly — the only gap is the trigger mechanism

## Reference Docs Consulted

No reference documentation exists for the rehearsals or home domains. Checked:

- `docs/reference/rehearsals/` — does not exist
- `docs/reference/home/` — does not exist

## Existing System Analysis

### Data Flow (Current):

1. **Occurrence generation** (at creation time):
   - `EventsRepository._generateRecurringDates()` generates all occurrences when a recurring rehearsal is created
   - For open-ended rehearsals (no `recurrence_until`), defaults to 1 year: `recurrence.untilDate ?? formData.date.add(const Duration(days: 365))`
   - Maximum 52 iterations (weekly rehearsals for ~1 year)
   - All occurrences are stored in the database with `parent_rehearsal_id` linking to the parent

2. **Data fetching**:
   - `bandFullStateProvider` fetches all rehearsals via Supabase RPC
   - `RehearsalController._categorizeRehearsals()` filters into confirmed/potential/upcoming
   - All confirmed rehearsals (including recurring occurrences) are available in `rehearsalState.confirmedRehearsals`

3. **Pagination state** (button-based):
   - `RehearsalPaginationController` tracks visible count per series (default: 10)
   - `RehearsalDisplayHelper.groupIntoSeries()` groups rehearsals by parent ID, identifies open-ended series
   - `RehearsalDisplayHelper.flattenForDisplay()` applies pagination limits and inserts "load more" markers
   - `DisplayItem` represents either a rehearsal or a load-more marker

4. **UI rendering** (home_tab_content.dart, line ~1050-1120):
   - `_buildHorizontalRehearsalsList()` watches `rehearsalPaginationProvider`
   - Groups rehearsals into series, flattens for display
   - `ListView.separated` renders each `DisplayItem`:
     - If `item.isRehearsal`: renders `RehearsalCard`
     - If `item.isLoadMore`: renders `LoadMoreRehearsalsCard` button
   - User taps button → calls `loadMore(seriesId)` → state updates → UI rebuilds with more occurrences

### Scroll Behavior:

- Horizontal scroll (`Axis.horizontal`) with no `ScrollController`
- No scroll position monitoring
- No threshold detection for auto-loading
- Button tap is the only trigger for pagination

## Proposed Solution

**Replace button-based pagination with scroll-triggered auto-load using a `ScrollController` and scroll position listener.**

### Changes:

1. **Add `ScrollController` for rehearsal list**:
   - Declare a `ScrollController _rehearsalScrollController` in `HomeTabContent` (stateful widget or via a manager)
   - Initialize in `initState()` or on first build
   - Attach to the `ListView.separated` in `_buildHorizontalRehearsalsList()`
   - Add a listener that checks scroll position

2. **Implement scroll listener**:
   - Listener fires when `scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200`
   - When threshold reached:
     - Identify which series has more occurrences (check `series.hasMore(currentVisibleCount)`)
     - Call `ref.read(rehearsalPaginationProvider.notifier).loadMore(seriesId)` automatically
   - Use a loading flag or debounce to prevent duplicate loads while occurrences are being added

3. **Remove `LoadMoreRehearsalsCard` from display**:
   - In `_buildHorizontalRehearsalsList`, filter out items where `item.isLoadMore == true` before rendering
   - Or update `RehearsalDisplayHelper.flattenForDisplay()` to accept a `includeLoadMoreMarkers` parameter (default: true for backward compatibility)

4. **Disposal**:
   - Dispose `_rehearsalScrollController` in `HomeTabContent.dispose()` to prevent memory leaks

### Optional Enhancement:

- Add a subtle `CircularProgressIndicator` at the end of the list while new occurrences are being appended (not required by acceptance criteria, but improves UX)

### Design Constraints:

- No third-party packages (per feature input)
- Use standard Flutter `ScrollController` + `addListener()` pattern
- Existing pagination state management (`rehearsalPaginationProvider`) remains unchanged
- No changes to occurrence generation logic (already correct)

## Database Impact

**Not applicable**

All occurrences are already generated at creation time and stored in the database. Pagination is purely client-side display logic. No schema changes, RLS changes, RPC changes, or migrations required.

## Flutter Architecture Changes

**State:** No changes. `RehearsalPaginationController` and `RehearsalDisplayHelper` remain unchanged. New scroll controller is local to the widget.

**Widgets:** No new widgets. `LoadMoreRehearsalsCard` becomes unused (but retained in codebase).

**Repositories:** No changes.

**Controllers:** No changes.

## Files to Create

**None**

## Files to Modify

| File                                                    | Description                                                                                                                                                                                                                                                    |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/home_tab_content.dart`               | Add `ScrollController _rehearsalScrollController`, initialize and attach to `ListView.separated`, implement scroll listener that auto-triggers `loadMore()`, filter out load-more display items, dispose controller in `dispose()` method                      |
| `lib/features/rehearsals/rehearsal_display_helper.dart` | _(Optional)_ Add `includeLoadMoreMarkers` parameter to `flattenForDisplay()` method to conditionally exclude load-more markers (defaults to `true` for backward compatibility). If Engineer prefers filtering in the UI layer, this file can remain unchanged. |

## Files Off-Limits

| File                                                           | Reason                                                                            |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `lib/features/rehearsals/rehearsal_pagination_controller.dart` | Pagination state logic is correct; no changes needed                              |
| `lib/features/home/widgets/load_more_rehearsals_card.dart`     | Will be unused but kept for potential future button-based reuse or other features |
| `lib/features/rehearsals/rehearsal_controller.dart`            | Data fetching and categorization already works correctly                          |
| `lib/features/rehearsals/rehearsal_repository.dart`            | No data layer changes required                                                    |
| `lib/features/events/events_repository.dart`                   | Occurrence generation logic is correct (defaults to 1 year for open-ended)        |
| `lib/app/models/rehearsal.dart`                                | Model is correct                                                                  |
| `lib/main.dart`                                                | Init order must not change                                                        |

## System Impact Map

| System                                 | Impact                                                                                |
| -------------------------------------- | ------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                            |
| Rehearsals                             | affected — pagination trigger mechanism only (display logic in home_tab_content.dart) |
| Setlists / Catalog                     | unaffected                                                                            |
| Members / RBAC                         | unaffected                                                                            |
| Auth / Session                         | unaffected                                                                            |
| Routing                                | unaffected                                                                            |
| Notifications                          | unaffected                                                                            |
| Platform (iOS / Android / Web / macOS) | affected — scroll behavior applies to all platforms                                   |

## Regression Risk

**Level:** LOW

**Rationale:**

- Single-file change (two if helper is modified, but that's optional)
- No state management changes (reuses existing `rehearsalPaginationProvider` and `RehearsalDisplayHelper`)
- No data fetching changes
- No database or backend changes
- Standard Flutter pattern (`ScrollController` + `addListener()`)
- Affects only rehearsal display on home screen (isolated UI feature)
- Does not touch auth, session, routing, or init order
- Other home screen sections (gigs, quick actions, potential events) unaffected
- `ScrollController` disposal is straightforward and well-documented in Flutter guidelines
- Rehearsal card tap behavior unchanged (opens edit drawer)
- Pagination state logic unchanged (still 10 occurrences per page)

## Engineer Task Breakdown

Execute in order:

1. **Add `ScrollController` declaration in `HomeTabContent`**
   - If `HomeTabContent` is stateless, convert to stateful or use a controller manager pattern
   - Declare `late ScrollController _rehearsalScrollController;`
   - Initialize in `initState()`: `_rehearsalScrollController = ScrollController();`

2. **Implement scroll position listener**
   - In `initState()`, add listener:
     ```dart
     _rehearsalScrollController.addListener(() {
       if (!_rehearsalScrollController.hasClients) return;

       final position = _rehearsalScrollController.position;
       const threshold = 200.0; // pixels from end

       if (position.pixels >= position.maxScrollExtent - threshold) {
         _loadMoreRehearsalsIfNeeded();
       }
     });
     ```
   - Create `_loadMoreRehearsalsIfNeeded()` method that:
     - Gets current `paginationState` and `series` from providers
     - Identifies any series where `series.hasMore(currentVisibleCount) == true`
     - Calls `ref.read(rehearsalPaginationProvider.notifier).loadMore(seriesId)` for that series
     - Uses a flag or debounce to prevent duplicate calls while rebuilding

3. **Attach controller to ListView**
   - In `_buildHorizontalRehearsalsList()`, line ~1068, add:
     ```dart
     controller: _rehearsalScrollController,
     ```

4. **Filter out load-more markers from display**
   - **Option A (UI layer):** In the `itemBuilder` or before rendering, filter `displayItems` to exclude items where `item.isLoadMore == true`
   - **Option B (helper layer):** Add a parameter to `RehearsalDisplayHelper.flattenForDisplay(series, visibleCountBySeriesId, includeLoadMoreMarkers: false)` and update the method to conditionally skip load-more marker generation

5. **Add disposal**
   - In `HomeTabContent.dispose()`:
     ```dart
     @override
     void dispose() {
       _rehearsalScrollController.dispose();
       super.dispose();
     }
     ```

6. **Run `flutter analyze` and verify zero errors**
   - Fix any linting issues
   - Confirm no type errors or warnings

7. **Manual verification**
   - Create or use an existing open-ended recurring rehearsal (no `recurrence_until`)
   - Confirm first 10 occurrences appear
   - Scroll horizontally to the end
   - Confirm next 10 occurrences load automatically (no button tap required)
   - Confirm scrolling continues to load more batches indefinitely
   - Confirm non-recurring rehearsals and finite recurring rehearsals (with `recurrence_until`) are unaffected
   - Test on iOS, macOS, and web

## Verification Plan

### Tier 1 — Pre-deployment (manual testing only)

**Not applicable** — This feature has no database or backend changes. All verification is manual UI testing.

### Tier 2 — Post-deployment (manual testing)

**Test 1: Initial render shows first 10 occurrences**

- Given: User has an open-ended recurring rehearsal (weekly, no end date)
- When: User opens home screen
- Then: "Upcoming Rehearsals" section shows first 10 occurrences in horizontal scroll
- And: No "Load More" button is visible
- Platform: macOS, iOS, Web

**Test 2: Scrolling to end auto-loads next 10 occurrences**

- Given: User has an open-ended recurring rehearsal with 30+ generated occurrences
- When: User scrolls horizontally to the end of the first 10 cards
- Then: Next 10 occurrences appear automatically without any button tap
- And: User can continue scrolling to see the new cards
- Platform: iOS, macOS

**Test 3: Scrolling continues to load more batches indefinitely**

- Given: User has an open-ended recurring rehearsal with 50+ generated occurrences
- When: User scrolls to the end of the second batch (20 total shown)
- Then: Third batch of 10 loads automatically
- And: This continues for all available occurrences
- Platform: Web

**Test 4: Finite recurring rehearsals show all occurrences (no pagination)**

- Given: User has a recurring rehearsal with `recurrence_until` date set to 5 weeks from now (5 occurrences total)
- When: User opens home screen
- Then: All 5 occurrences appear in the horizontal scroll
- And: No pagination behavior occurs
- Platform: macOS

**Test 5: Non-recurring rehearsals are unaffected**

- Given: User has 3 standalone (non-recurring) rehearsals
- When: User opens home screen
- Then: All 3 rehearsals appear in horizontal scroll as before
- And: No pagination behavior occurs
- Platform: iOS

**Test 6: Multiple open-ended series paginate independently**

- Given: User has 2 different open-ended recurring rehearsals (e.g., weekly Monday and weekly Thursday)
- When: User opens home screen
- Then: First 10 occurrences of each series appear (interleaved by date)
- When: User scrolls to the end
- Then: Next 10 occurrences from the appropriate series load automatically
- Platform: Web

**Test 7: Rehearsal card tap still opens edit drawer**

- Given: User is admin/member (not contributor)
- When: User taps on any rehearsal card in the paginated list
- Then: Edit Event drawer opens with rehearsal details pre-populated
- Platform: macOS

**Test 8: ScrollController is properly disposed**

- Given: User is on home screen with rehearsal list scrolled partway
- When: User switches to a different band (triggers full refresh)
- Then: No memory leak or scroll controller errors occur
- And: New band's rehearsals render correctly with fresh scroll position
- Platform: macOS

**Test 9: Empty state and single rehearsal still work**

- Given: User has 0 confirmed rehearsals
- When: User opens home screen
- Then: "Upcoming Rehearsals" section shows empty state or is hidden (matches existing behavior)
- Platform: Web

**Test 10: Scroll position resets on band change**

- Given: User is on home screen with rehearsal list scrolled to occurrence #20
- When: User switches to a different band via band selector
- Then: Rehearsal list resets to show first 10 occurrences of new band
- And: Scroll position starts at the beginning (left edge)
- Platform: macOS

## QA Regression Areas

QA must specifically test:

1. **Infinite scroll for open-ended recurring rehearsals**
   - First 10 occurrences render on load
   - Scrolling to end auto-loads next 10 (no button)
   - Continues for all available occurrences
   - No duplicate occurrences appear

2. **Finite recurring rehearsals (with `recurrence_until`)**
   - All occurrences render at once (no pagination)
   - Scroll behavior is normal (no auto-loading)

3. **Non-recurring rehearsals**
   - Display unchanged from previous behavior
   - No pagination applied

4. **Rehearsal card interactions (no regression)**
   - Tap on rehearsal card opens edit drawer
   - Setlist names display correctly
   - Time ranges display correctly
   - RSVP status (if applicable) displays correctly

5. **Home screen stability (no regression)**
   - Upcoming gigs section unaffected
   - Potential events section unaffected
   - Quick actions unaffected
   - Band switching still works correctly
   - Pull-to-refresh still works correctly

6. **Memory management**
   - No memory leaks when switching bands
   - No scroll controller errors in console
   - Smooth scrolling performance with large lists (50+ occurrences)

7. **Platform consistency**
   - Test on iOS, Android, macOS, and Web
   - Confirm scroll behavior works on all platforms
   - Confirm touch targets remain accessible (48px minimum)

## Rollout / Migration Strategy

**Not applicable** — Pure UI change with no backend or data migration required.

Deployment: Standard web deploy via `./tools/deploy_web.sh` after QA approval. Mobile apps will receive the change in next build/release.

## Out of Scope

The following are explicitly **not** included in this feature:

1. Changes to rehearsal occurrence generation logic (already works correctly)
2. Changes to pagination state management (`RehearsalPaginationController` remains unchanged)
3. Changes to series grouping logic (`RehearsalDisplayHelper` remains unchanged, except optional parameter)
4. Changes to `RehearsalCard` widget design or behavior
5. Changes to rehearsal edit drawer or form
6. Changes to rehearsal creation flow
7. Changes to potential rehearsals display
8. Adding a loading indicator at the end (optional enhancement, defer to Engineer)
9. Virtualization or performance optimizations for very large lists (52 weeks is manageable)
10. Accessibility enhancements beyond existing behavior
11. Vertical infinite scroll (this feature is horizontal scroll only)
12. Lazy-loading rehearsals from database (all occurrences already fetched)

---

**Architect approval:** Ready for Engineer implementation.
**Branch:** `feature/rehearsal-lazy-load`
