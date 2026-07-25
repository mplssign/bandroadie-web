# Venue Detail View — Architectural Plan

## Feature Slug

`feature/venue-detail-view`

---

## Problem Summary

Users currently see venues in a flat, unsorted list with no search capability or quick navigation. The venues list needs A-Z section grouping (omitting empty letters), a search bar for live filtering, and an iOS Contacts-style index scroll column on the right. Tapping a venue should navigate to a read-only detail view showing venue information, associated contacts, and notes — not the current edit screen.

**Why:** This improves discoverability and usability for bands managing large venue lists.

---

## Root Cause

**Confidence:** HIGH (direct observation)

No root cause — this is a greenfield feature addition. Current implementation is a basic flat list with no grouping, search, or detail view. Venues are fetched from Supabase ordered by name ascending, displayed as VenueCard widgets, and tapping opens VenueFormScreen (edit mode).

**Observed state:**

- `venues_view.dart` (line 100–158): CustomScrollView with flat SliverList
- `venues_repository.dart` (line 50–54): Venues fetched with `.order('name', ascending: true)`, contacts embedded via `.select('*, venue_contacts(*)')`
- `venues_view.dart` (line 149–150): `onTap` navigates to `VenueFormScreen` for editing
- No search state, no section grouping logic, no index column widget

---

## Reference Docs Consulted

None — no reference docs exist for the venues domain. This is a UI/navigation enhancement with no backend changes required.

**Note:** Venues domain is implemented under `lib/features/contacts/` (not `lib/features/venues/`).

---

## Existing System Analysis

### Current Data Flow

1. **Load:** `contacts_tab_content.dart` (line 135–136) lazy-loads venues when segment 1 is selected
2. **Fetch:** `venues_controller.dart` (line 45–70) calls `VenuesRepository.fetchVenues(bandId: bandId)`
3. **Query:** `venues_repository.dart` (line 50–54) runs:
   ```sql
   SELECT *, venue_contacts(*)
   FROM venues
   WHERE band_id = :bandId
   ORDER BY name ASC
   ```
4. **Parse:** Results deserialized into `List<Venue>`, each with embedded `List<VenueContact>`
5. **Display:** `venues_view.dart` (line 136–158) renders flat SliverList of VenueCard widgets
6. **Navigate:** Tapping VenueCard opens `VenueFormScreen` (line 149–150)

### Current Limitations

- No search or filter capability
- No section headers or grouping
- No quick scroll index
- No read-only detail view (tapping goes directly to edit screen)
- Venue contacts already fetched but fully expanded in list cards (could be condensed in list, expanded in detail)

### Existing Assets

- **Models:** `Venue` and `VenueContact` already contain all required fields (address, city, state, phone, notes)
- **Repository:** Already fetches venues with contacts embedded
- **Navigation:** Uses `fadeSlideRoute` helper for Navigator.push (not GoRouter)
- **Entry point:** Contacts tab → SegmentedToggle → Venues (index 1)

---

## Proposed Solution

### 1. Add Search Bar

Insert a TextField above the venues list (inside CustomScrollView as SliverToBoxAdapter). Update VenuesController to add `searchQuery` to VenuesState and a `setSearchQuery(String query)` method. Filter venues client-side based on case-insensitive name match.

### 2. Implement A-Z Section Grouping

Group venues into sections by the first letter of `venue.name.toUpperCase()`. Omit sections for letters with no venues. Render each section as:

- SliverToBoxAdapter: section letter header
- SliverList: venues in that section

Use a helper function `_groupVenuesByLetter(List<Venue> venues)` returning `Map<String, List<Venue>>`.

### 3. Add Right-Side Index Column

Use a Stack with Positioned to overlay an A-Z index column on the right edge. Tapping a letter scrolls the list to that section. For empty letters, jump to the nearest populated section.

**Scroll-to-index approach:** Use the `scrollable_positioned_list` package (pub.dev/packages/scrollable_positioned_list). This provides `ItemScrollController` and `ScrollablePositionedList.builder` for precise scroll-to-index.

**Why this package:** Industry standard for iOS Contacts-style scroll behavior, handles dynamic item heights, more reliable than manual offset calculation or GlobalKey approaches.

### 4. Handle Search + Section Interaction

When `searchQuery.isNotEmpty`:

- Display flat filtered list (no section headers)
- Hide or disable the index column
- Show "No results" if filtered list is empty

When search is cleared (`searchQuery.isEmpty`):

- Restore full A-Z sectioned list
- Re-enable index column

### 5. Create Read-Only Venue Detail Screen

New file: `lib/features/contacts/widgets/venue_detail_screen.dart`

Displays:

- Venue name (page title)
- Address, city, state (location block)
- Phone (tappable to launch dialer)
- Notes (if present)
- List of VenueContact entries (name, title, phone, email)

No editing — this is read-only. Use Scaffold with AppBar and scrollable body. Match existing design language (rose borders, 24px radius cards from VenueCard).

### 6. Update Navigation

In `venues_view.dart`, modify VenueCard's `onTap` to navigate to VenueDetailScreen instead of VenueFormScreen. Preserve VenueFormScreen navigation from the "Add" button (line 122–128).

---

## Database Impact

**Not applicable.** All required data (venues + venue_contacts) is already fetched via existing repository query. No schema changes, no new RPCs, no RLS policy changes, no migrations.

---

## Flutter Architecture Changes

### State (VenuesController)

Add to `VenuesState`:

```dart
final String searchQuery;
final List<Venue> filteredVenues; // computed from venues + searchQuery
```

Add to `VenuesNotifier`:

```dart
void setSearchQuery(String query) {
  state = state.copyWith(
    searchQuery: query,
    filteredVenues: _filterVenues(state.venues, query),
  );
}

List<Venue> _filterVenues(List<Venue> venues, String query) {
  if (query.isEmpty) return venues;
  final lower = query.toLowerCase();
  return venues.where((v) => v.name.toLowerCase().contains(lower)).toList();
}
```

### Widgets (VenuesView)

Replace flat SliverList with:

1. SliverToBoxAdapter: TextField search bar
2. Conditional rendering:
   - If searching: flat filtered list
   - If not searching: grouped A-Z sections

Add Stack + Positioned for index column overlay.

### New Widget (VenueDetailScreen)

Standalone screen with Scaffold, AppBar, and scrollable body displaying venue + contacts in read-only format.

---

## Files to Create

| File                                                     | Justification                                                                                                                                                            |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/contacts/widgets/venue_detail_screen.dart` | New read-only detail view. Cannot reuse VenueFormScreen (edit mode, requires form state). ~250 lines: Scaffold, AppBar, scrollable body with venue info + contact cards. |

---

## Files to Modify

| File                                             | What Changes                                                                                                                                                                                                                                                                                                                                                                                |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/venues_controller.dart`   | Add `searchQuery` and `filteredVenues` to VenuesState. Add `setSearchQuery(String query)` and `_filterVenues()` methods.                                                                                                                                                                                                                                                                    |
| `lib/features/contacts/widgets/venues_view.dart` | (1) Add TextField search bar in SliverToBoxAdapter. (2) Replace flat SliverList with conditional: if searching, flat filtered list; else A-Z sectioned list using `_groupVenuesByLetter()`. (3) Add Stack + Positioned index column overlay. (4) Change VenueCard onTap to navigate to VenueDetailScreen. (5) Replace SliverList with ScrollablePositionedList.builder from new dependency. |
| `pubspec.yaml`                                   | Add `scrollable_positioned_list: ^0.3.8` (latest stable version as of 2026-07) under dependencies.                                                                                                                                                                                                                                                                                          |

---

## Files Off-Limits

| File                                                   | Reason                                                                                            |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                        | No routing changes required — uses Navigator.push, not GoRouter for detail screens.               |
| `lib/features/contacts/venues_repository.dart`         | Data fetch already correct: venues ordered by name, contacts embedded. No backend changes needed. |
| `lib/features/contacts/models/venue.dart`              | Model already contains all required fields (address, city, state, phone, notes, contacts).        |
| `lib/features/contacts/models/venue_contact.dart`      | Model already contains all required fields (name, title, phone, email).                           |
| `lib/features/contacts/widgets/venue_form_screen.dart` | Out of scope — editing functionality unchanged.                                                   |
| `lib/features/contacts/widgets/venue_card.dart`        | Visual design unchanged — only `onTap` callback behavior changes (handled in parent VenuesView).  |
| `lib/features/contacts/contacts_tab_content.dart`      | Segment toggle and lazy-load logic already correct.                                               |

---

## Migration Policy

**Not required.** No database changes.

---

## Edge Function Deploy

**Not required.** No backend changes.

---

## New Dependencies

**Allowed:** `scrollable_positioned_list: ^0.3.8`

**Justification:** Industry-standard package for iOS Contacts-style index scroll. Provides `ItemScrollController` and `ScrollablePositionedList.builder` for precise scroll-to-index with dynamic item heights. Alternatives (manual offset calculation, GlobalKey scroll) are unreliable for variable-height sectioned lists.

---

## New Files

See "Files to Create" table above. Only one new file: `venue_detail_screen.dart` (~250 lines, Scaffold + read-only venue display).

---

## System Impact Map

| System                                 | Impact                                                                |
| -------------------------------------- | --------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                            |
| Rehearsals                             | unaffected                                                            |
| Setlists / Catalog                     | unaffected                                                            |
| Members / RBAC                         | unaffected                                                            |
| Auth / Session                         | unaffected                                                            |
| Routing                                | affected — new detail screen navigation path added                    |
| Notifications                          | unaffected                                                            |
| Platform (iOS / Android / Web / macOS) | affected — all platforms (UI changes only, no platform-specific code) |

---

## Regression Risk

**Level:** LOW

**Rationale:**

- Zero backend changes (no queries, no RLS, no edge functions)
- Isolated to venues feature (no cross-feature dependencies)
- Existing edit flow (VenueFormScreen) preserved, accessed via "Add" button
- New detail screen is read-only (no data mutation)
- Search and grouping logic is pure client-side transformation
- New dependency (`scrollable_positioned_list`) is widely used, stable package

**Risk factors mitigated:**

- No auth, session, or init order changes
- No database mutations or schema changes
- Venues list entry point unchanged (Contacts tab → segment 1)
- Repository fetch unchanged (same query, same order)

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Add scrollable_positioned_list Dependency

- Edit `pubspec.yaml`: add `scrollable_positioned_list: ^0.3.8` under `dependencies` section
- Run `flutter pub get` to install

### Task 2: Extend VenuesState with Search Fields

- Edit `lib/features/contacts/venues_controller.dart`:
  - Add `searchQuery` (String, default `''`) and `filteredVenues` (List<Venue>, default `[]`) to `VenuesState`
  - Update `copyWith()` to include new fields

### Task 3: Implement setSearchQuery in VenuesNotifier

- Edit `lib/features/contacts/venues_controller.dart`:
  - Add `setSearchQuery(String query)` method
  - Add `_filterVenues(List<Venue> venues, String query)` helper
  - Filter on case-insensitive `name` match

### Task 4: Create VenueDetailScreen

- Create `lib/features/contacts/widgets/venue_detail_screen.dart`
- Scaffold with AppBar (title: venue name)
- Body: SingleChildScrollView with:
  - Venue info card (address, city, state, phone, notes)
  - Contacts section (list of VenueContact entries)
- Match existing design (24px radius, rose border, gradient glow)
- Make phone numbers tappable (url_launcher)

### Task 5: Add Search Bar to VenuesView

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Add TextField inside SliverToBoxAdapter above list
  - TextField calls `ref.read(venuesProvider.notifier).setSearchQuery(value)`
  - Add TextEditingController, dispose in dispose()

### Task 6: Implement A-Z Grouping Logic

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Add `_groupVenuesByLetter(List<Venue> venues)` helper returning `Map<String, List<Venue>>`
  - Group by first letter of `venue.name.toUpperCase()`
  - Omit empty letters

### Task 7: Replace Flat List with Sectioned List

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Replace SliverList with ScrollablePositionedList.builder
  - Render section headers (SliverToBoxAdapter per letter) + venues
  - Use ItemScrollController for index column
  - Conditional: if `searchQuery.isNotEmpty`, render flat filtered list (no sections)

### Task 8: Add A-Z Index Column

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Wrap CustomScrollView in Stack
  - Add Positioned(right: 8) with Column of 26 letter buttons (A–Z)
  - Tapping letter calls `ItemScrollController.scrollTo(index: sectionIndex)`
  - For empty letters, jump to nearest populated section
  - Hide/disable index when `searchQuery.isNotEmpty`

### Task 9: Update VenueCard Navigation

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Change VenueCard's `onTap` from navigating to `VenueFormScreen(venue: venue)` to `VenueDetailScreen(venue: venue)`
  - Preserve "Add" button navigation to `VenueFormScreen(venue: null)`

### Task 10: Handle Empty Search Results

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - When `searchQuery.isNotEmpty && filteredVenues.isEmpty`, display "No venues found" empty state

### Task 11: Test on All Platforms

- Verify on Web, iOS, Android, macOS (UI only, no platform-specific code)
- Confirm search live-filters as user types
- Confirm A-Z sections render correctly
- Confirm index scroll jumps to sections (or nearest for empty letters)
- Confirm detail screen displays all venue + contact fields
- Confirm phone tap launches dialer

---

## Verification Plan

### Manual Testing (All platforms: Web, iOS, Android, macOS)

**Pre-deployment (Tier 1 — client-side only):**

No database changes required. All testing is client-side.

**Test 1: Load Venues List**

1. Navigate to Contacts tab → Venues segment
2. Verify venues load and display in alphabetical order
3. Verify A-Z section headers appear (e.g., "A", "B", "C"...)
4. Verify letters with no venues are omitted

**Test 2: Search Functionality**

1. Type in search bar
2. Verify list filters live as user types
3. Verify section headers + index column hidden during search
4. Clear search → verify full sectioned list restored

**Test 3: Index Scroll**

1. Tap "M" in index column
2. Verify list scrolls to "M" section
3. Tap an empty letter (e.g., "X" if no venues start with X)
4. Verify list scrolls to nearest populated section

**Test 4: Venue Detail Navigation**

1. Tap a venue card in the list
2. Verify navigates to read-only VenueDetailScreen (not VenueFormScreen)
3. Verify venue name, address, city, state, phone, notes display
4. Verify venue contacts (name, title, phone, email) display

**Test 5: Edit Flow Preserved**

1. Tap "Add" button in VenuesView
2. Verify navigates to VenueFormScreen (edit mode) as before
3. Verify no regressions in add/edit/delete flows

**Test 6: Edge Cases**

1. Test with 0 venues → verify empty state
2. Test with 1 venue → verify section header + no index needed
3. Test with 200+ venues → verify scroll performance acceptable
4. Test search with no results → verify "No venues found" message

---

## QA Regression Areas

### Primary Test Areas

1. **Venues List Display:**
   - A-Z sections render correctly
   - Empty letters omitted
   - Venues alphabetically ordered within sections

2. **Search Functionality:**
   - Live filtering as user types
   - Case-insensitive match
   - Sections/index hidden during search
   - Clear search restores full list

3. **Index Scroll:**
   - Tapping letter scrolls to correct section
   - Empty letters jump to nearest section
   - Smooth scroll animation

4. **Venue Detail Screen:**
   - All venue fields display (name, address, city, state, phone, notes)
   - All venue contacts display (name, title, phone, email)
   - Phone tap launches dialer
   - Read-only (no edit controls)

### Regression Test Areas

5. **Existing Edit Flow:**
   - "Add" button still navigates to VenueFormScreen
   - Add/edit/delete venue flows unchanged
   - Venue contacts add/edit/delete unchanged (accessed via edit screen)

6. **Contacts Tab Integration:**
   - Segment toggle (Band/Venues/Contacts) still works
   - Lazy-load on segment switch still works
   - RefreshIndicator still works

7. **Cross-Platform:**
   - Web: search, index, detail screen work
   - iOS: search, index, detail screen work
   - Android: search, index, detail screen work
   - macOS: search, index, detail screen work

---

## Rollout / Migration Strategy

Not applicable — client-only UI change, no backend migration.

**Deployment steps:**

1. Merge PR to main
2. Deploy web via `./tools/deploy_web.sh`
3. Mobile: build and release updated apps (standard release process)

---

## Out of Scope

Explicitly not included in this feature:

1. **Editing venues or contacts** — VenueFormScreen unchanged, accessed via "Add" button
2. **Deleting venues or contacts** — delete flows unchanged, accessed via edit screen
3. **Adding venues or contacts from detail screen** — detail screen is read-only
4. **Backend changes** — no database schema, RLS, RPC, or edge function changes
5. **Search on fields other than venue name** — search only matches venue name (not address, city, notes) — **Superseded by Amendment 6** (city + contact-person-name matching retroactively authorized; see Amendment 6 below)
6. **Filtering by letter** — index scroll only, no filter chips or dropdowns
7. **Sort order customization** — venues remain alphabetical by name (existing behavior)
8. **Venue contact re-ordering** — contacts display in database order (existing behavior)
9. **Map integration** — no map view of venue addresses
10. **Favorites or pinned venues** — no starring or top-of-list persistence

---

## Amendment: Sticky Section Headers

**Amendment Date:** 2026-07-24  
**Amendment Author:** Architect  
**Trigger:** User requirement from Tony

### New Requirement

As the user scrolls the venues list, the current section's letter header should stay pinned at the top of the visible list until the next section's letter reaches the top and replaces it (standard iOS Contacts sticky header behavior). This applies only to the sectioned (non-search) state — while search is active, headers are already hidden per the existing plan.

### Root Cause Analysis

**Confidence:** HIGH (direct code observation post-implementation)

**Current State (ENGINEER_REPORT.md lines 34-37):**

The Engineer successfully implemented Tasks 1-11, but introduced an **implementation deviation** from the original plan that affects both scroll-to-index and sticky header feasibility:

**Observed in `venues_view.dart` (lines 369-424):**

- The sectioned list is rendered using **standard `SliverList`** with `SliverChildBuilderDelegate`
- Section headers and venues are built as a **flat list of widgets** in `_buildSectionedList()` (line 373-374: `final items = <Widget>[]`)
- The list is NOT using `ScrollablePositionedList.builder` as specified in the original plan
- `ItemScrollController` is declared (line 31) but **not connected to any scrollable** — calls to `_itemScrollController.scrollTo()` in `_buildIndexColumn()` (lines 452-458) have no effect

**Impact:**

1. **Scroll-to-index broken:** Index column taps do not scroll to the target section (original Task 8 non-functional)
2. **Sticky headers not possible via SliverPersistentHeader:** Because the list is still wrapped in `CustomScrollView` but the sectioned items are pre-built as a flat widget list, we cannot insert `SliverPersistentHeader` between sections without restructuring

**Why this happened:**  
The original plan specified "Replace SliverList with ScrollablePositionedList.builder" (Task 7, line 307) but the Engineer kept the `CustomScrollView` + `SliverList` approach and built sections as a flat list, likely because `ScrollablePositionedList` is not Sliver-based and does not integrate cleanly with `CustomScrollView`'s Sliver architecture.

### Constraints Assessed

**scrollable_positioned_list package capabilities:**

- `ScrollablePositionedList.builder` — provides `ItemScrollController.scrollTo(index)` for precise scroll-to-index
- `ItemPositionsListener` — reports currently visible item indices in real time
- **Not Sliver-based** — incompatible with `CustomScrollView` + standard Sliver widgets
- **Does not provide built-in sticky headers** — would require overlay approach

**Current implementation constraints:**

- Already using `CustomScrollView` with Sliver widgets (search bar, title bar)
- Cannot mix Sliver widgets with non-Sliver `ScrollablePositionedList` in the same scroll view
- Sticky headers require either:
  1. `SliverPersistentHeader` (requires proper Sliver structure)
  2. Overlay approach driven by scroll position tracking

### Proposed Solution

**Two-part fix:**

#### Part A: Fix Scroll-to-Index (Restore Original Plan Intent)

Replace the current `CustomScrollView` sectioned list implementation with a proper `ScrollablePositionedList.builder` that:

1. Wraps the entire scrollable content (title, search bar, sectioned venues) in a single `ScrollablePositionedList`
2. Connects `ItemScrollController` to enable working scroll-to-index
3. Builds items lazily: `itemBuilder` returns title, search bar, section headers, and venue cards based on computed flat index
4. Adds `ItemPositionsListener` to track visible items

**Why this approach:**

- Aligns with original architectural decision to use `scrollable_positioned_list` for scroll-to-index
- Fixes the broken index column functionality
- Provides `ItemPositionsListener` for tracking scroll position (needed for sticky headers)
- Single scroll controller for entire view

**Trade-off:**

- Loses Sliver widgets (must build title/search as regular widgets in the item builder or as a header)
- Slightly more complex item index calculation (title + search + sections = computed flat indices)

#### Part B: Add Sticky Header Overlay

Use `ItemPositionsListener` to track which section is currently at the top of the visible viewport, then render a **positioned overlay label** showing the current section letter:

1. Add `ItemPositionsListener` to the `ScrollablePositionedList`
2. Track `itemPositions` in state to determine which section is topmost visible
3. Render `Positioned` sticky header overlay (top: [search bar height]) displaying the current section letter
4. Match existing section header design (rose color, bold, page title font size)
5. Hide sticky header when `searchQuery.isNotEmpty` (consistent with existing search behavior)

**Why overlay vs. native sticky header:**

- `scrollable_positioned_list` does not support Sliver-based sticky headers
- Overlay approach is the standard pattern for non-Sliver scrollables
- Performance is acceptable for iOS Contacts-style section headers (single text widget overlay)
- Avoids need for additional dependencies

### Files to Modify (Amendment Only)

| File                                             | What Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/widgets/venues_view.dart` | **(1)** Replace `CustomScrollView` + `SliverList` sectioned implementation with `ScrollablePositionedList.builder`. **(2)** Add `ItemPositionsListener` to track visible item positions. **(3)** Add state field to store current sticky header letter. **(4)** Build flat item list: title → search bar → (section header → venues per section). **(5)** Add `_buildStickyHeader()` method returning `Positioned` overlay label. **(6)** Update `_buildIndexColumn()` to work with new flat index calculation. **(7)** Hide sticky header when `isSearching`. |

### Files Off-Limits (Amendment)

All files from original plan remain off-limits. No new files created. No new dependencies.

### Migration Policy (Amendment)

**Not required.** Client-only UI change.

### New Dependencies (Amendment)

**None.** Uses existing `scrollable_positioned_list: ^0.3.8` package capabilities (`ItemPositionsListener`).

### Regression Risk (Amendment)

**Level:** LOW → **MEDIUM**

**Rationale for increase:**

- Replacing `CustomScrollView` + `SliverList` with `ScrollablePositionedList.builder` is a **significant structural change** to the list rendering approach
- Item index calculation becomes more complex (flat index mapping across title, search, headers, venues)
- Scroll behavior may differ subtly from Sliver-based scrolling (momentum, overscroll, refresh indicator interaction)
- RefreshIndicator integration needs verification (`ScrollablePositionedList` may not support `RefreshIndicator` out of the box)

**Risk factors:**

- Touching core list rendering (high-traffic user path)
- Scroll performance must remain acceptable for 200+ venues
- All platforms affected (Web, iOS, Android, macOS)

**Mitigation:**

- Thorough testing per platform (especially refresh indicator, scroll performance)
- QA validation of scroll-to-index now working correctly (was broken before)
- Sticky header visibility only affects visual presentation, not data or navigation

### Engineer Task Breakdown (Amendment)

Execute in strict order after original Tasks 1-11 are confirmed implemented:

#### Task A1: Add ItemPositionsListener and Sticky Header State

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Import `ItemPositionsListener` from `scrollable_positioned_list`
  - Add `final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create()` field
  - Add state field: `String? _currentStickyLetter`
  - Add listener in `initState()` to update `_currentStickyLetter` when `itemPositions` changes

#### Task A2: Restructure Sectioned List as ScrollablePositionedList

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Remove `CustomScrollView` wrapper for sectioned list
  - Replace `_buildSectionedList()` with `_buildScrollablePositionedList()` returning `ScrollablePositionedList.builder`
  - Compute flat item list: `[title widget, search bar widget, ...section headers + venues...]`
  - Implement `itemBuilder` that returns the correct widget for each flat index
  - Connect `itemScrollController` and `itemPositionsListener`
  - Preserve `RefreshIndicator` if possible (research compatibility), or handle pull-to-refresh alternatively

#### Task A3: Update Index Column to Use Correct Flat Indices

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Modify `_buildIndexColumn()` to calculate correct flat index for each section (accounting for title + search bar + prior section headers/venues)
  - Verify `ItemScrollController.scrollTo(index)` now works correctly

#### Task A4: Add Sticky Header Overlay

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Add `_buildStickyHeader()` method returning `Positioned` widget
  - Position: `top: [calculated offset below search bar]`, `left: Spacing.pagePadding`, `right: Spacing.pagePadding`
  - Display `_currentStickyLetter` (if not null and not searching)
  - Match section header styling (rose color, bold, page title font size)

#### Task A5: Integrate Sticky Header into Stack

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Wrap scrollable content + index column in `Stack`
  - Add sticky header overlay as third Stack child (above scroll, below index column)
  - Conditional: hide when `isSearching` or `_currentStickyLetter == null`

#### Task A6: Test Sticky Header Behavior

- Verify on all platforms (Web, iOS, Android, macOS):
  - Section header sticks to top as user scrolls
  - Sticky header updates to new letter when next section reaches top
  - Sticky header hidden during search
  - Index column scroll-to-index now works correctly (fix for original Task 8)
  - RefreshIndicator still works (or pull-to-refresh alternative works)
  - Scroll performance acceptable for 200+ venues

### Verification Plan (Amendment)

**Manual Testing (All platforms: Web, iOS, Android, macOS)**

**Test A1: Sticky Header Visibility**

1. Navigate to Contacts tab → Venues segment (non-searching state)
2. Scroll down slowly through sections
3. Verify current section letter appears as sticky header at top
4. Verify sticky header remains visible as venues scroll underneath
5. Verify sticky header updates to "B" when "B" section header reaches top

**Test A2: Sticky Header Hidden During Search**

1. Type in search bar
2. Verify sticky header disappears
3. Clear search
4. Verify sticky header reappears with correct section letter

**Test A3: Index Column Scroll-to-Index Fixed**

1. Tap "M" in index column
2. Verify list scrolls to "M" section (this was broken before amendment)
3. Verify sticky header shows "M"
4. Tap "A"
5. Verify list scrolls to "A" section
6. Verify sticky header shows "A"

**Test A4: Scroll Performance**

1. Test with 200+ venues
2. Verify smooth scrolling (no jank or frame drops)
3. Verify sticky header updates smoothly during fast scroll
4. Verify index column tap still scrolls quickly

**Test A5: Refresh Indicator**

1. Pull down to refresh (platform-appropriate gesture)
2. Verify venues reload
3. Verify sticky header reappears after reload with correct letter

**Test A6: Edge Cases**

1. First section ("A") — verify sticky header shows "A" when at top
2. Last section — verify sticky header shows last letter
3. Single venue — verify sticky header shows correct letter
4. Rapid scroll through many sections — verify sticky header updates correctly

### QA Regression Areas (Amendment)

**Primary Test Areas (New):**

8. **Sticky Section Headers:**
   - Sticky header displays correct section letter
   - Header updates when next section reaches top
   - Header hidden during search
   - Header matches existing section header design
   - Header positioned correctly below search bar

**Regression Test Areas (Amendment-Specific):**

9. **Scroll-to-Index Fix:**
   - Index column taps now scroll to correct section (was broken pre-amendment)
   - Scroll animation is smooth
   - Empty letter taps jump to nearest section

10. **List Rendering:**
    - All venues display correctly (no missing items)
    - Section headers still render in correct positions
    - No visual glitches during scroll
    - Search functionality unchanged (flat filtered list)

11. **Platform-Specific Scroll Behavior:**
    - RefreshIndicator works on all platforms (or acceptable alternative)
    - Overscroll behavior matches platform conventions
    - Scroll momentum feels natural
    - No regressions in lazy-load or segment switch

### System Impact Map (Amendment)

| System                                 | Impact                                               |
| -------------------------------------- | ---------------------------------------------------- |
| Gigs                                   | unaffected                                           |
| Rehearsals                             | unaffected                                           |
| Setlists / Catalog                     | unaffected                                           |
| Members / RBAC                         | unaffected                                           |
| Auth / Session                         | unaffected                                           |
| Routing                                | unaffected                                           |
| Notifications                          | unaffected                                           |
| Platform (iOS / Android / Web / macOS) | **affected** — scroll rendering architecture changed |

### Out of Scope (Amendment)

Explicitly not included in this amendment:

1. **Custom sticky header design** — matches existing section header styling exactly
2. **Animated sticky header transitions** — instant update on section change (iOS Contacts behavior)
3. **Multiple sticky headers** — only current section letter displayed
4. **Sticky header for search results** — hidden during search per existing plan
5. **Backdrop blur or shadow on sticky header** — simple overlay, no visual effects
6. **Sticky header tap to scroll** — read-only display, not interactive
7. **Alternative scrollable widgets** — uses existing `scrollable_positioned_list` package only
8. **Backend changes** — client-only UI change

---

**Amendment Summary:**  
This amendment fixes a **critical implementation gap** (broken scroll-to-index functionality due to incorrect use of `scrollable_positioned_list` package) and adds the requested **sticky section header** feature using `ItemPositionsListener` from the same package. The approach restructures the list rendering to use `ScrollablePositionedList.builder` as originally specified, enabling both working index column scrolling and scroll position tracking for the sticky header overlay.

**Key Constraint:** `scrollable_positioned_list` is not Sliver-based, so the solution uses an overlay approach rather than native `SliverPersistentHeader`. This is the standard pattern for non-Sliver scrollables and matches iOS Contacts behavior.

**Regression risk increased from LOW to MEDIUM** due to structural changes to list rendering, requiring thorough cross-platform testing of scroll behavior, refresh indicator, and performance with large venue lists.

# Venue Detail View — Amendment 2: Design Match + # Section

**Amendment Date:** 2026-07-24  
**Amendment Author:** Architect  
**Trigger:** User requirement from Tony with design reference image

---

## New Requirements

Tony provided a design reference image showing how the venue listing screen should look. This amendment addresses:

1. **Sticky section headers** — As user scrolls, current section letter stays pinned at top (standard iOS Contacts behavior). Applies only to sectioned (non-search) state.

2. **# catch-all section** — Venues whose name does not start with A-Z (e.g., starts with number or symbol) should be grouped into a trailing "#" section at the end of the list. Index column shows A-Z followed by #. Tapping # scrolls to that section, following same "jump to nearest" rule for empty sections.

3. **Simplified VenueCard design** — Current card is too detailed (shows border, gradient, icons, phone, contacts). Design reference shows minimal cards with only venue name (bold white) and city/state (light gray). Detail belongs in detail screen, not list view.

---

## Design Analysis

### Reference Image Shows:

- Black background
- "Venues" title (white, left)
- "+ Add" button (rose, right)
- Dark search bar with light placeholder, search icon
- Section headers: rose, bold, left-aligned (A, B, C, D visible)
- **Simple venue cards:**
  - Dark gray/charcoal background (`context.colors.surface`)
  - Venue name: white, bold (AppFontSizes.title or pageTitle)
  - City, State: light gray (context.colors.textSecondary)
  - NO border, NO gradient glow, NO icons
  - Rounded corners (likely 12-16px, not 24px)
  - Compact vertical padding
- A-Z index on right (rose)
- **# at bottom of index**

### Current Implementation Gaps:

**From venue_card.dart (lines 32-111):**

- 2px rose border (`Border.all(color: AppColors.primary, width: 2)`)
- 24px border radius
- Gradient glow overlay (LinearGradient with primary color alpha)
- Shows location icon + full address
- Shows phone icon + phone number (tappable)
- Shows ALL venue contacts in list card with dividers (lines 96-103)
- Contact details: name, title badge, email, phone
- Heavy padding (24px all sides)

**Gap:** Current card is a full detail view embedded in the list. Design shows minimal preview cards.

**From venues_view.dart:**

- Already has A-Z grouping logic (`_groupVenuesByLetter`, line 79-88)
- Groups by first letter: `venue.name[0].toUpperCase()`
- Uses '#' as fallback for empty names (line 82)
- **Missing:** Does not group non-letter starting names into '#' section
- **Missing:** Index column does not show '#' entry (line 442-474)

---

## Root Cause Analysis

**Confidence:** HIGH (direct observation post-implementation + design reference)

### Issue 1: Sticky Headers (Amendment 1 carryover)

Already diagnosed in Amendment 1 (ARCHITECT_PLAN.md lines 458-732):

- Engineer used `SliverList` instead of `ScrollablePositionedList.builder`
- `ItemScrollController` declared but not connected
- Scroll-to-index broken
- Solution: Use `ScrollablePositionedList.builder` + `ItemPositionsListener` for sticky overlay

**Status:** Amendment 1 tasks (A1-A6) not yet implemented by Engineer.

### Issue 2: # Section Missing

Current `_groupVenuesByLetter()` (venues_view.dart lines 79-88):

```dart
final letter = venue.name.isEmpty ? '#' : venue.name[0].toUpperCase();
```

**Problem:** Only handles empty names. Venues starting with numbers or symbols (e.g., "5th Street Bar", "@venue", "123 Club") are grouped by their literal first character ('5', '@', '1'), creating scattered single-venue sections instead of one consolidated '#' section.

**Expected behavior:** All non-letter starting venues should map to '#' and appear in one trailing section at end of list.

### Issue 3: VenueCard Too Detailed

Current card (venue_card.dart lines 28-111) shows:

- Rose border + gradient (lines 35-59)
- Location icon + full address (lines 77-84)
- Phone icon + phone (lines 87-93)
- All venue contacts with dividers (lines 96-103)
- Contact name, title badge, email, phone (lines 137-196)

**Design reference shows:** Just venue name + city/state, no decorations.

**Why this is wrong for list view:**

- Cognitive overload — too much information per card
- Violates list/detail separation pattern
- VenueDetailScreen exists for full venue info
- List view should be scannable preview, not full detail

---

## Proposed Solution

### Part A: Sticky Headers (Amendment 1 continuation)

Execute Amendment 1 tasks A1-A6 as written (ARCHITECT_PLAN.md lines 584-626). No changes to that plan.

**Summary:**

1. Add `ItemPositionsListener` to track visible items
2. Replace `CustomScrollView` sectioned list with `ScrollablePositionedList.builder`
3. Render sticky header overlay using `_currentStickyLetter` state
4. Hide during search

**Note:** Sticky header must also display '#' when scrolled to # section (handled by ItemPositionsListener tracking).

### Part B: Add # Catch-All Section

Modify `_groupVenuesByLetter()` logic to consolidate all non-letter starting venues into '#':

**Current (line 79-88):**

```dart
final letter = venue.name.isEmpty ? '#' : venue.name[0].toUpperCase();
```

**Proposed:**

```dart
final firstChar = venue.name.isEmpty ? '#' : venue.name[0].toUpperCase();
final letter = RegExp(r'^[A-Z]$').hasMatch(firstChar) ? firstChar : '#';
```

**Result:**

- Venues starting with A-Z: grouped by letter
- Venues starting with anything else (numbers, symbols, empty): grouped into '#'
- '#' section appears at end (after 'Z' in sorted map)

**Index column update:** Add '#' as 27th entry after 'Z' (venues_view.dart line 442). Tapping '#' scrolls to '#' section (or nearest populated section if no such venues exist).

### Part C: Simplify VenueCard Design

**Objective:** Match design reference — minimal preview card showing only name + city/state.

**Changes to venue_card.dart:**

1. **Remove decorations (lines 32-59):**
   - Remove `Border.all` (rose border)
   - Remove gradient glow `Stack` + `Positioned.fill` + `LinearGradient`
   - Keep plain `Container` with `context.colors.surface` background
   - Reduce border radius: 24px → 16px (matches Spacing.cardRadius)

2. **Simplify content (lines 60-111):**
   - Show venue name (bold, white, AppFontSizes.title)
   - Show city/state only: `"${venue.city}, ${venue.state}"` (light gray, AppFontSizes.body, textSecondary color)
   - Remove location icon + address
   - Remove phone icon + phone
   - Remove all venue contacts section (lines 96-103)
   - Remove dividers

3. **Reduce padding:** 24px → 16px (matches Spacing.pagePadding)

**Rationale:** List cards are for scanning and selection. Full detail (address, phone, contacts, notes) belongs in VenueDetailScreen, which is accessed by tapping the card. This matches iOS Contacts pattern (list shows name + preview, detail shows full info).

**Layout:**

```
┌─────────────────────────────┐
│ Venue Name                  │ ← bold white, AppFontSizes.title
│ City, State                 │ ← light gray, AppFontSizes.body, textSecondary
└─────────────────────────────┘
```

**Conditional rendering:** If `venue.city` or `venue.state` is null/empty, handle gracefully:

- Both present: "City, State"
- Only city: "City"
- Only state: "State"
- Neither: omit subtitle line

---

## Database Impact

**Not applicable.** Client-only UI changes.

---

## Flutter Architecture Changes

### VenuesView (venues_view.dart)

**From Amendment 1 (A1-A6):** Sticky header implementation via `ScrollablePositionedList.builder` + `ItemPositionsListener`.

**New for Amendment 2:**

1. **Update `_groupVenuesByLetter()`** (line 79-88):
   - Change grouping logic to map non-letter starting names to '#'
   - Sort map so '#' appears after 'Z'

2. **Update `_buildIndexColumn()`** (line 427-480):
   - Add '#' as 27th letter after 'Z'
   - Tapping '#' scrolls to '#' section (or nearest)

3. **Sticky header must render '#'** when that section is visible (handled by ItemPositionsListener in Amendment 1 — no additional changes needed if A1-A6 correctly track current section letter).

### VenueCard (venue_card.dart)

**Simplify to minimal preview:**

1. Remove border, gradient, Stack decorations
2. Reduce border radius: 24px → 16px
3. Reduce padding: 24px → 16px
4. Show only: venue name (line 66-74) + city/state subtitle
5. Remove location block (lines 77-84)
6. Remove phone block (lines 87-93)
7. Remove contacts loop (lines 96-103)
8. Remove all helper methods except `_formatCityState()` (new method for city/state formatting)

**Result:** ~80-100 lines (down from 245 lines).

---

## Files to Create

**None.** Amendment modifies existing files only.

---

## Files to Modify

| File                                             | What Changes                                                                                                                                                                                                        |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/widgets/venues_view.dart` | **(Amendment 1 A1-A6):** Sticky headers via ScrollablePositionedList + ItemPositionsListener. **(Amendment 2):** Update `_groupVenuesByLetter()` to map non-letter names to '#'. Add '#' to index column after 'Z'. |
| `lib/features/contacts/widgets/venue_card.dart`  | Remove border, gradient, icons, phone, contacts. Show only venue name + city/state. Reduce padding and radius. Simplify to ~80-100 lines.                                                                           |

---

## Files Off-Limits

All files from original plan + Amendment 1 remain off-limits. No changes to:

- `lib/features/contacts/venues_controller.dart` (state management unchanged)
- `lib/features/contacts/widgets/venue_detail_screen.dart` (detail view unchanged — already shows full info)
- `lib/features/contacts/models/venue.dart` (model unchanged)
- `lib/features/contacts/widgets/venue_form_screen.dart` (edit screen unchanged)

---

## Migration Policy

**Not required.** Client-only UI changes.

---

## New Dependencies

**None.** Uses existing packages.

---

## Regression Risk

**Level:** MEDIUM (unchanged from Amendment 1)

**Rationale:**

- Amendment 1 structural changes (ScrollablePositionedList) = MEDIUM risk
- Amendment 2 adds minimal changes on top:
  - Grouping logic tweak (low risk — pure function, no side effects)
  - Index column entry addition (low risk — UI only)
  - VenueCard simplification (low risk — removes code, simplifies rendering)

**Combined risk remains MEDIUM** due to Amendment 1 scroll architecture changes. Amendment 2 changes are low-risk incremental additions.

---

## Engineer Task Breakdown

Execute in strict order:

### Amendment 1 Tasks (A1-A6) — Execute First

See ARCHITECT_PLAN.md lines 584-626. These tasks implement sticky headers and fix scroll-to-index.

### Amendment 2 Tasks (B1-B3) — Execute After A1-A6

#### Task B1: Update Grouping Logic for # Section

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Modify `_groupVenuesByLetter()` method (line 79-88)
  - Change logic: check if first char matches `RegExp(r'^[A-Z]$')`
  - If yes: group by that letter
  - If no: group into '#'
  - Ensure map is sorted so '#' appears after 'Z' in iteration order

#### Task B2: Add # to Index Column

- Edit `lib/features/contacts/widgets/venues_view.dart`:
  - Modify `_buildIndexColumn()` method (line 427-480)
  - Add '#' as final entry in letters list (after 'Z')
  - Tapping '#' calculates correct flat index for '#' section and scrolls there
  - If '#' section empty (no such venues), jump to last populated section (likely 'Z' or earlier)

#### Task B3: Simplify VenueCard to Match Design

- Edit `lib/features/contacts/widgets/venue_card.dart`:
  - Remove `Border.all` (rose border) from Container decoration
  - Remove gradient glow `Stack` + `Positioned.fill` + `LinearGradient`
  - Change border radius: `BorderRadius.circular(24)` → `BorderRadius.circular(16)`
  - Change padding: `EdgeInsets.all(24)` → `EdgeInsets.all(16)`
  - Remove location icon + address block (lines 77-84)
  - Remove phone icon + phone block (lines 87-93)
  - Remove contacts loop + dividers (lines 96-103)
  - Remove `_buildVenueContactSection()` method (lines 137-196)
  - Remove `_launchPhone()` method (lines 198-207)
  - Remove `_buildInfoRow()` method (lines 209-243)
  - Add `_formatCityState()` method returning conditional city/state string
  - Update `build()` to show:
    1. Venue name (bold, white, AppFontSizes.title)
    2. City/state subtitle (gray, AppFontSizes.body, textSecondary) — only if present
  - Result: ~80-100 lines

---

## Verification Plan

### Manual Testing (All platforms: Web, iOS, Android, macOS)

**Pre-deployment (Tier 1 — client-side only):**

All tests are client-side UI validation. No database changes.

#### Test B1: # Section Grouping

1. Add test venues with non-letter starting names:
   - "5th Avenue Bar"
   - "@TheVenue"
   - "123 Club"
   - "!Exclaim"
2. Navigate to Venues list (non-search state)
3. Verify all non-letter venues grouped into '#' section
4. Verify '#' section appears after 'Z' (or after last populated letter section)
5. Verify section header shows '#'

#### Test B2: # Index Entry

1. Verify index column shows A-Z followed by '#' at bottom
2. Tap '#' in index
3. Verify list scrolls to '#' section (if it exists)
4. If '#' section empty (no such venues), verify scroll jumps to nearest section
5. Verify sticky header shows '#' when scrolled to '#' section

#### Test B3: Simplified VenueCard Design

1. View venues list
2. Verify each card shows:
   - Venue name (bold, white)
   - City, State (light gray) — if present
   - Plain background (no rose border)
   - No gradient glow
   - No location icon
   - No phone icon
   - No contact details
   - 16px rounded corners (not 24px)
   - Compact padding
3. Verify cards are visually simpler and more scannable
4. Tap a card → verify VenueDetailScreen shows full detail (address, phone, contacts, notes)

#### Test B4: Edge Cases

1. Venue with city but no state → verify "City" subtitle (no trailing comma)
2. Venue with state but no city → verify "State" subtitle
3. Venue with neither city nor state → verify no subtitle line
4. Venue starting with space character → verify grouped into '#'
5. Venue starting with emoji → verify grouped into '#'
6. Empty venue name → verify grouped into '#' (existing behavior)

#### Test B5: Amendment 1 + Amendment 2 Integration

1. Sticky header displays 'A', 'B', 'C'... as user scrolls
2. Sticky header displays '#' when scrolled to '#' section
3. Sticky header hidden during search (existing behavior)
4. Index column taps scroll correctly to A-Z and '#' sections
5. Search still works (filters by name, hides sections + sticky header)

---

## QA Regression Areas

### Primary Test Areas (Amendment 2)

12. **# Section Grouping:**
    - All non-letter starting venues grouped into '#'
    - '#' section appears after last letter section
    - Section header shows '#'
    - Empty '#' section handled gracefully (no header if no such venues)

13. **# Index Entry:**
    - '#' appears at bottom of index column (after 'Z')
    - Tapping '#' scrolls to '#' section or nearest
    - Sticky header shows '#' when at '#' section

14. **Simplified VenueCard Design:**
    - Card shows only name + city/state
    - No border, no gradient, no icons
    - Compact padding and smaller radius (16px)
    - Cards are scannable and visually clean
    - Full detail still accessible via VenueDetailScreen

### Regression Test Areas (Amendment 1 + 2 Combined)

15. **Sticky Section Headers:**
    - Sticky header displays correct letter (A-Z, #)
    - Header updates as user scrolls through sections
    - Header hidden during search
    - Header positioned correctly below search bar

16. **Scroll-to-Index:**
    - Index column taps scroll to correct sections (A-Z, #)
    - Empty letter taps jump to nearest populated section
    - Scroll animation smooth on all platforms

17. **List Rendering:**
    - All venues display correctly
    - Section headers render in correct positions (A-Z, #)
    - No missing venues or duplicate entries
    - Search functionality unchanged (flat filtered list, no sections)

18. **Detail Navigation:**
    - Tapping venue card navigates to VenueDetailScreen
    - Detail screen shows full venue info (address, phone, contacts, notes)
    - No regressions in detail screen layout or data display

19. **Edit Flow:**
    - "Add" button still navigates to VenueFormScreen
    - Venue add/edit/delete flows unchanged
    - No regressions in form validation or submission

---

## System Impact Map

| System                                 | Impact                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                             |
| Rehearsals                             | unaffected                                                             |
| Setlists / Catalog                     | unaffected                                                             |
| Members / RBAC                         | unaffected                                                             |
| Auth / Session                         | unaffected                                                             |
| Routing                                | unaffected                                                             |
| Notifications                          | unaffected                                                             |
| Platform (iOS / Android / Web / macOS) | **affected** — UI rendering changes (scroll architecture, card design) |

---

## Out of Scope (Amendment 2)

Explicitly not included:

1. **Custom card styling** — uses existing design tokens (Spacing.cardRadius, context.colors.surface, AppFontSizes, etc.)
2. **Animated card transitions** — no animations on card simplification, instant visual change
3. **Card hover states** — existing AnimatedCardPressable behavior preserved
4. **# section custom sorting** — venues within '#' section remain alphabetically ordered by name (existing behavior)
5. **Search matching on city/state** — search still only matches venue name (existing behavior) — **Superseded by Amendment 6** (city + contact-person-name matching retroactively authorized; see Amendment 6 below)
6. **Detail screen redesign** — VenueDetailScreen layout unchanged (still shows full venue + contacts info)
7. **Index column redesign** — index styling unchanged, only '#' entry added
8. **Backend changes** — no database schema, query, RLS, or edge function changes

---

## Amendment Summary

This amendment combines **three user requirements** into one cohesive update:

1. **Sticky section headers** — Continued from Amendment 1 (tasks A1-A6), uses `ItemPositionsListener` to track scroll position and render sticky overlay showing current section letter (A-Z or #).

2. **# catch-all section** — Groups all venues starting with non-letter characters (numbers, symbols, empty) into a consolidated '#' section at the end of the list. Index column shows '#' after 'Z', tappable to scroll to that section.

3. **Simplified VenueCard design** — Removes visual decorations (border, gradient, icons) and detail content (phone, contacts, dividers). Cards now show only venue name + city/state for scannable preview. Full detail remains accessible in VenueDetailScreen.

**Design rationale:** Matches provided reference image showing minimal iOS Contacts-style venue list. Separates preview (list) from detail (detail screen), reducing cognitive load and improving scannability for large venue lists.

**Regression risk remains MEDIUM** (unchanged from Amendment 1) due to scroll architecture restructuring. Amendment 2 changes are low-risk incremental additions.

**Files affected:** `venues_view.dart` (grouping + index + sticky headers) and `venue_card.dart` (simplified design).

**No new dependencies, no database changes, no backend changes.**

---

## Amendment: Detail Screen Redesign + Edit

**Amendment Date:** 2026-07-24  
**Amendment Author:** Architect  
**Trigger:** User requirement from Tony with mockup image

---

## New Requirement

The venue detail screen needs two changes:

1. **Add Edit button** — An "Edit" link/button in the AppBar top right that navigates to the existing `VenueFormScreen`, pre-filled with the venue's data. This explicitly reverses the earlier decision that the detail view is read-only with no editing capability.

2. **Redesign layout with individual field cards** — Each field type should be rendered as a separate rounded card with a muted label above the value, matching the existing surface-card visual language used elsewhere in the app. Below the title row, render cards in this specific order:
   - **Address** — street address, then city/state/zip on a second line within the same card
   - **Phone** — venue's own phone number
   - **Contact group, repeated once per `venue_contacts` row** — if a venue has multiple contacts, repeat this whole set of cards per contact, in order:
     - Contact Person (name)
     - Contact Title
     - Contact Phone Number
     - Contact Email
   - **Notes** — last, multi-line

3. **Graceful field omission** — Missing/empty fields should omit their card entirely, applying the same pattern already used in `venue_card.dart` for city/state handling (lines 68-80).

**Out of scope:** Adding venues or contacts from the detail screen remains out of scope — only editing the existing venue via the existing form, not inline editing or contact CRUD from this screen.

---

## Root Cause Analysis

**Confidence:** HIGH (direct observation of current implementation)

### Current State

**File: `lib/features/contacts/widgets/venue_detail_screen.dart` (lines 1-321)**

- AppBar shows venue name as title, no action button (lines 28-33)
- Body renders two types of cards:
  1. **One large venue info card** (lines 63-150) — shows address, phone, notes grouped together with ornate decorations (24px radius, 2px rose border, gradient glow overlay, 24px padding)
  2. **Multiple contact cards** (lines 152-249) — one per venue_contacts row, with same ornate styling
- No edit functionality — user must navigate back to list to access edit flow
- Uses helper methods: `_formatFullAddress()`, `_launchPhone()`, `_buildInfoRow()`

### Gap Between Current and Required

1. **Missing Edit navigation** — No button to edit the venue from the detail screen
2. **Grouped fields instead of individual cards** — Address, phone, notes are combined in one card; contact fields are combined per contact
3. **Ornate visual style** — Current cards use gradient glow + border, which is heavier than the "surface-card visual language" specified in the requirement
4. **No field labels** — Current design uses icons + values, but requirement specifies "muted label above the value"

### Earlier Off-Limits Decision Reversed

**Original plan (line 201-209)** listed `venue_detail_screen.dart` as off-limits:
> "Out of scope — editing functionality unchanged."

**Amendment 2 (line 1038-1044)** maintained this restriction:
> "detail view unchanged — already shows full info"

**This amendment explicitly reverses that decision** to enable:
1. Adding Edit navigation to `VenueFormScreen`
2. Redesigning the layout with individual field cards

---

## Proposed Solution

### Part A: Add Edit Button to AppBar

Add an `actions` list to the AppBar with a TextButton or IconButton labeled "Edit":
- Positioned in AppBar top right (standard Flutter AppBar actions placement)
- On tap: navigate to `VenueFormScreen(venue: venue)` using existing navigation helper (`fadeSlideRoute` from `app/helpers/route_helpers.dart`)
- Pre-fills form with current venue data for editing

### Part B: Redesign Body with Individual Field Cards

Replace the current two-card layout (one large venue info card + multiple contact cards) with individual field cards following this structure:

**Card Design Pattern:**
- Background: `context.colors.surface`
- Border radius: `16` (matching simplified venue_card.dart, Amendment 2)
- Padding: `16` (matching simplified venue_card.dart)
- No border, no gradient glow (simplified surface-card pattern)
- Label: muted color (`context.colors.textSecondary`), smaller font size (`AppFontSizes.caption`), above the value
- Value: primary text color (`context.colors.textPrimary`), standard body font size (`AppFontSizes.body`)

**Card Order (as specified):**

1. **Address Card** (if venue has address, city, or state)
   - Label: "Address"
   - Line 1: `venue.address` (if present)
   - Line 2: formatted city/state/zip (e.g., "Austin, TX 78701")
   - Omit card if all address fields are null/empty

2. **Phone Card** (if `venue.phone` is present)
   - Label: "Phone"
   - Value: `venue.phone`
   - Tappable to launch dialer (preserve existing `_launchPhone` logic)
   - Omit card if phone is null/empty

3. **Contact Group Cards** (repeated per `venue.contacts` entry)
   - For each contact in `venue.contacts`, render 4 cards in order:
     - **Contact Person** — label "Contact Person", value `contact.name`
     - **Contact Title** — label "Contact Title", value `contact.title` (omit if null/empty)
     - **Contact Phone Number** — label "Contact Phone", value `contact.phone`, tappable (omit if null/empty)
     - **Contact Email** — label "Contact Email", value `contact.email` (omit if null/empty)
   - If a venue has 2 contacts, this produces 8 contact-related cards (4 per contact)
   - If a venue has 0 contacts, this produces 0 contact-related cards

4. **Notes Card** (if `venue.notes` is present)
   - Label: "Notes"
   - Value: `venue.notes`, multi-line
   - Omit card if notes is null/empty

**Helper Method:**
- Add `_buildFieldCard(BuildContext context, String label, String value, {VoidCallback? onTap, int maxLines = 2})` to reduce duplication
- Conditionally render each card only if its value is non-null and non-empty

---

## Database Impact

**Not applicable.** Client-only UI changes. No schema, RLS, RPC, or edge function changes.

---

## Flutter Architecture Changes

### VenueDetailScreen (venue_detail_screen.dart)

**Changes:**

1. **AppBar (lines 28-33):**
   - Add `actions: [...]` with TextButton or IconButton labeled "Edit"
   - On tap: `Navigator.push(context, fadeSlideRoute(VenueFormScreen(venue: venue)))`
   - Import `app/helpers/route_helpers.dart` and `venue_form_screen.dart`

2. **Body (lines 34-61):**
   - Replace `_buildVenueInfoCard()` and contact cards loop with a flat list of individual field cards
   - Render cards in specified order: address, phone, contact groups, notes
   - Use `_buildFieldCard()` helper to reduce duplication

3. **Delete obsolete methods:**
   - `_buildVenueInfoCard()` (lines 63-150) — replaced by individual field cards
   - `_buildContactCard()` (lines 152-249) — replaced by individual contact field cards
   - `_hasLocation` getter (lines 251-254) — logic inlined into address card conditional
   - `_formatFullAddress()` (lines 256-272) — logic moved into address card rendering

4. **Keep existing methods:**
   - `_launchPhone()` (lines 274-283) — still needed for phone cards
   - `_buildInfoRow()` (lines 285-319) — may be adapted or replaced by `_buildFieldCard()`

5. **Add new helper:**
   - `_buildFieldCard(BuildContext context, String label, String value, {VoidCallback? onTap, int maxLines})` — renders a single field card with label above value, optional tap handler

**Result:** File size expected to be similar or slightly smaller (~300-350 lines) due to consolidation of card rendering logic.

---

## Files to Create

**None.** Amendment modifies existing file only.

---

## Files to Modify

| File                                                     | What Changes                                                                                                                                                                                                                                                                                               |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/widgets/venue_detail_screen.dart` | **(1)** Add Edit button to AppBar actions that navigates to `VenueFormScreen(venue: venue)`. **(2)** Redesign body with individual field cards (address, phone, contact fields repeated per contact, notes) using new `_buildFieldCard()` helper. **(3)** Delete obsolete card-building methods. **(4)** Apply graceful field omission (only render cards for non-empty values). |

---

## Files Off-Limits (Status Change)

**`venue_detail_screen.dart` status change:**

- **Original plan (line 201-209):** Listed as off-limits — "Out of scope — editing functionality unchanged"
- **Amendment 2 (line 1038-1044):** Maintained off-limits status — "detail view unchanged — already shows full info"
- **This amendment:** **Now IN SCOPE** for two reasons:
  1. Adding Edit button navigation to VenueFormScreen (reverses read-only decision)
  2. Redesigning layout with individual field cards (UX improvement per mockup)

**All other files from original plan + prior amendments remain off-limits:**

| File                                                   | Reason                                                                                 |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| `lib/main.dart`                                        | No routing changes required — uses Navigator.push, not GoRouter.                       |
| `lib/features/contacts/venues_repository.dart`         | Data fetch already correct.                                                            |
| `lib/features/contacts/models/venue.dart`              | Model already contains all required fields.                                            |
| `lib/features/contacts/models/venue_contact.dart`      | Model already contains all required fields.                                            |
| `lib/features/contacts/widgets/venue_form_screen.dart` | Edit screen unchanged — already accepts `venue` parameter for pre-filling.             |
| `lib/features/contacts/widgets/venue_card.dart`        | List card design finalized in Amendment 2.                                             |
| `lib/features/contacts/widgets/venues_view.dart`       | List view finalized in prior amendments.                                               |
| `lib/features/contacts/contacts_tab_content.dart`      | Tab structure unchanged.                                                               |

---

## Migration Policy

**Not required.** Client-only UI changes.

---

## New Dependencies

**None.** Uses existing navigation helpers and design tokens.

---

## Regression Risk

**Level:** LOW

**Rationale:**

- Isolated to a single screen (`venue_detail_screen.dart`)
- No data mutations (edit button only navigates to existing form)
- No backend changes
- No state management changes
- Uses existing `VenueFormScreen` which is already tested
- Existing navigation pattern (`fadeSlideRoute`) already used throughout app
- Individual field cards simplify rendering logic (fewer conditionals within large cards)

**Risk factors mitigated:**

- No auth, session, or init order changes
- No database schema, RLS, or RPC changes
- No cross-feature dependencies
- Edit navigation uses existing, proven VenueFormScreen
- Field card rendering is straightforward conditional rendering (if value exists, show card)

---

## Engineer Task Breakdown

Execute in strict order:

### Task D1: Add Edit Button to AppBar

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Add import: `import '../../../app/helpers/route_helpers.dart';`
  - Add import: `import 'venue_form_screen.dart';`
  - Update AppBar (line 28-33) to include `actions: [...]` with a TextButton or IconButton:
    - Label: "Edit"
    - Color: `AppColors.primary`
    - On tap: `Navigator.push(context, fadeSlideRoute(VenueFormScreen(venue: venue)))`

### Task D2: Create _buildFieldCard Helper Method

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Add new method `_buildFieldCard(BuildContext context, String label, String value, {VoidCallback? onTap, int maxLines = 2})`
  - Return a `Container` with:
    - Background: `context.colors.surface`
    - Border radius: `BorderRadius.circular(16)`
    - Padding: `EdgeInsets.all(16)`
    - Child: `Column` with:
      - Label text (muted, caption size, textSecondary color)
      - 8px gap
      - Value text (primary color, body size, textPrimary color)
      - Optional `GestureDetector` wrapper if `onTap` is provided

### Task D3: Redesign Body with Individual Field Cards

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Replace `_buildVenueInfoCard()` and contacts loop in body (lines 36-56) with a flat Column of individual field cards:
    - **Address card** (conditional: only if address, city, or state exists)
      - Label: "Address"
      - Value: format address with street on line 1, city/state/zip on line 2
      - Use `_buildFieldCard(context, 'Address', formattedAddress, maxLines: 3)`
    - **Phone card** (conditional: only if `venue.phone` is non-null/non-empty)
      - Label: "Phone"
      - Value: `venue.phone!`
      - Use `_buildFieldCard(context, 'Phone', venue.phone!, onTap: () => _launchPhone(venue.phone!))`
    - **Contact group cards** (loop over `venue.contacts`, conditionally render 4 cards per contact):
      - For each `contact` in `venue.contacts`:
        - **Contact Person card:** `_buildFieldCard(context, 'Contact Person', contact.name)`
        - **Contact Title card** (conditional: only if `contact.title` is non-null/non-empty): `_buildFieldCard(context, 'Contact Title', contact.title!)`
        - **Contact Phone card** (conditional: only if `contact.phone` is non-null/non-empty): `_buildFieldCard(context, 'Contact Phone', contact.phone!, onTap: () => _launchPhone(contact.phone!))`
        - **Contact Email card** (conditional: only if `contact.email` is non-null/non-empty): `_buildFieldCard(context, 'Contact Email', contact.email!)`
    - **Notes card** (conditional: only if `venue.notes` is non-null/non-empty)
      - Label: "Notes"
      - Value: `venue.notes!`
      - Use `_buildFieldCard(context, 'Notes', venue.notes!, maxLines: 10)`

### Task D4: Delete Obsolete Methods

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Delete `_buildVenueInfoCard()` method (lines 63-150)
  - Delete `_buildContactCard()` method (lines 152-249)
  - Delete `_hasLocation` getter (lines 251-254)
  - Delete `_formatFullAddress()` method (lines 256-272)
  - Delete `_buildInfoRow()` method (lines 285-319) — replaced by `_buildFieldCard()`

### Task D5: Add 16px Gap Between Field Cards

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Add `const SizedBox(height: 16)` between each field card in the Column
  - Standard spacing for card separation

### Task D6: Test on All Platforms

- Verify on Web, iOS, Android, macOS:
  - Edit button appears in AppBar top right
  - Tapping Edit navigates to VenueFormScreen pre-filled with venue data
  - Individual field cards render with labels above values
  - Missing/empty fields omit their card
  - Phone cards are tappable and launch dialer
  - Notes card displays multi-line text
  - Contact fields repeat correctly per contact (e.g., venue with 2 contacts shows 8 contact cards)

---

## Verification Plan

### Manual Testing (All platforms: Web, iOS, Android, macOS)

**Pre-deployment (Tier 1 — client-side only):**

No database changes required. All testing is client-side UI validation.

**Test D1: Edit Button Navigation**

1. Navigate to a venue detail screen
2. Verify "Edit" button appears in AppBar top right
3. Tap Edit button
4. Verify navigates to VenueFormScreen
5. Verify form is pre-filled with venue data (name, address, city, state, phone, notes)
6. Cancel form and return to detail screen
7. Verify navigation works smoothly

**Test D2: Individual Field Cards Render**

1. Navigate to a venue detail screen with complete data (all fields populated)
2. Verify each field renders as a separate card:
   - Address card (street on line 1, city/state/zip on line 2)
   - Phone card
   - Contact Person card (for each contact)
   - Contact Title card (for each contact with title)
   - Contact Phone card (for each contact with phone)
   - Contact Email card (for each contact with email)
   - Notes card
3. Verify each card has:
   - Muted label above value (caption size, textSecondary color)
   - Primary value below label (body size, textPrimary color)
   - 16px padding
   - 16px border radius
   - Surface background color
4. Verify 16px vertical gap between cards

**Test D3: Graceful Field Omission**

1. Create/navigate to venues with partial data:
   - Venue with no phone → verify Phone card omitted
   - Venue with no address/city/state → verify Address card omitted
   - Venue with no notes → verify Notes card omitted
   - Contact with no title → verify Contact Title card omitted for that contact
   - Contact with no phone → verify Contact Phone card omitted for that contact
   - Contact with no email → verify Contact Email card omitted for that contact
   - Venue with no contacts → verify no contact cards rendered
2. Verify only non-empty fields display their cards

**Test D4: Phone Tappable**

1. Navigate to venue with phone number
2. Tap Phone card value
3. Verify dialer launches with correct number (existing `_launchPhone` logic)
4. Tap Contact Phone card value (for contact with phone)
5. Verify dialer launches with contact's number

**Test D5: Multiple Contacts Render Correctly**

1. Navigate to venue with 2 contacts, each with full data (name, title, phone, email)
2. Verify 8 contact cards render (4 per contact, in order):
   - Contact Person (contact 1)
   - Contact Title (contact 1)
   - Contact Phone (contact 1)
   - Contact Email (contact 1)
   - Contact Person (contact 2)
   - Contact Title (contact 2)
   - Contact Phone (contact 2)
   - Contact Email (contact 2)
3. Verify cards are visually distinct (16px gap between)

**Test D6: Notes Multi-Line Display**

1. Navigate to venue with long notes (multiple paragraphs)
2. Verify Notes card displays full text across multiple lines
3. Verify no text truncation (maxLines: 10 should accommodate most notes)

**Test D7: Edge Cases**

1. Venue with only name (all other fields null/empty) → verify only AppBar shows, body shows "No additional information" or similar empty state (if Engineer adds one, otherwise just empty Column)
2. Venue with address but no city/state → verify Address card shows only street address
3. Venue with city/state but no address → verify Address card shows only city/state
4. Contact with only name (all other fields null/empty) → verify only Contact Person card renders for that contact

---

## QA Regression Areas

### Primary Test Areas (Amendment 3)

20. **Edit Button Navigation:**
   - Edit button visible in AppBar top right
   - Tapping Edit navigates to VenueFormScreen
   - Form pre-filled with correct venue data
   - Navigation smooth with no errors

21. **Individual Field Card Layout:**
   - Each field type renders as separate card with label above value
   - Cards use simplified surface-card design (no border/gradient)
   - 16px padding, 16px radius, 16px vertical gaps
   - Labels muted (textSecondary, caption size)
   - Values primary (textPrimary, body size)

22. **Graceful Field Omission:**
   - Missing/empty fields omit their card
   - No empty cards or placeholders shown
   - Venues with partial data display correctly
   - Contacts with partial data display correctly

23. **Contact Field Repetition:**
   - Multiple contacts render correctly (4 cards per contact with full data)
   - Contact cards appear in order per contact
   - Gaps between contact groups clear
   - Empty contact fields omit their card per contact

### Regression Test Areas (All Prior Features)

24. **Venue List View:**
   - Simplified venue cards still render correctly (name + city/state)
   - Search functionality still works
   - Section headers and # section still work
   - Tapping venue card still navigates to detail screen (this screen)

25. **Venue Form (Edit) Flow:**
   - Editing venue from detail screen Edit button works
   - Form pre-fills correctly
   - Saving edits updates venue data
   - Returning to detail screen shows updated data
   - "Add" button in venues list still opens blank form

26. **Navigation:**
   - Back button from detail screen returns to venue list
   - Back button from edit form returns to detail screen
   - No navigation stack issues

---

## System Impact Map

| System                                 | Impact                                                                |
| -------------------------------------- | --------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                            |
| Rehearsals                             | unaffected                                                            |
| Setlists / Catalog                     | unaffected                                                            |
| Members / RBAC                         | unaffected                                                            |
| Auth / Session                         | unaffected                                                            |
| Routing                                | **affected** — new navigation path: VenueDetailScreen → VenueFormScreen |
| Notifications                          | unaffected                                                            |
| Platform (iOS / Android / Web / macOS) | **affected** — UI changes to detail screen (all platforms)            |

---

## Out of Scope (Amendment 3)

Explicitly not included in this amendment:

1. **Inline editing** — Edit button navigates to existing VenueFormScreen, not inline form on detail screen
2. **Adding venues from detail screen** — "Add" button remains in venues list view only
3. **Adding contacts from detail screen** — Contact CRUD remains in VenueFormScreen only
4. **Editing contacts from detail screen** — Contact editing remains in VenueFormScreen only
5. **Deleting venues or contacts from detail screen** — Delete functionality remains in edit form only
6. **Custom field card styling** — Uses existing design tokens (Spacing.cardRadius, context.colors.surface, AppFontSizes, etc.)
7. **Animated card transitions** — No animations on field cards, standard rendering
8. **Empty state message** — If venue has no fields to display, body is empty (Engineer may optionally add "No additional information" message, but not required)
9. **Field validation on detail screen** — Detail screen is read-only display; validation happens in VenueFormScreen
10. **Search or filter on detail screen** — Detail screen shows all fields for one venue only

---

## Amendment Summary

This amendment enables editing from the venue detail screen and redesigns the layout to improve scannability and match the surface-card visual language used throughout the app.

**Key changes:**

1. **Edit button added** — Reverses earlier read-only decision; users can now edit venue directly from detail screen via existing VenueFormScreen
2. **Individual field cards** — Each field type (address, phone, contact person, contact title, contact phone, contact email, notes) is a separate labeled card, replacing the previous grouped layout
3. **Graceful omission** — Empty fields omit their card entirely, applying the same pattern used in Amendment 2's simplified venue_card.dart
4. **Simplified design** — Field cards use surface background, 16px radius, 16px padding, no border/gradient (matching Amendment 2's simplified list card design)

**Files affected:** `venue_detail_screen.dart` only (now IN SCOPE after being off-limits in original plan and Amendment 2).

**Regression risk: LOW** — isolated to single screen, uses existing VenueFormScreen navigation, no backend changes.

**No new dependencies, no database changes, no backend changes.**

---

## Amendment: Edit Form Contact Section Styling

**Amendment Date:** 2026-07-25
**Amendment Author:** Architect
**Trigger:** User requirement from Tony

---

## New Requirement

`lib/features/contacts/widgets/venue_form_screen.dart` (the venue edit form) has been off-limits in every prior round of this feature ("Edit screen unchanged"). It is now in scope for this specific change only. Two styling corrections to the "Contacts at this venue" section of the edit form:

1. **Remove the gray background** from the contacts section's fields so they visually match how the venue's own fields (name, address, phone, etc.) render elsewhere in the same form.
2. **Match vertical spacing** between contact form fields to whatever spacing is already used between the venue's own form fields.

This is a styling/spacing correction only — no new fields, no new validation, no changes to how contacts are saved.

---

## Root Cause / Investigation Findings

**Confidence:** HIGH (direct code observation)

### Investigation Finding: The target file is not where expected

`venue_form_screen.dart` does **not** itself render the individual contact fields. It only renders the "Contacts at this venue" section header, the "Add Contact" button, and an `AnimatedList` (lines 460-519) that delegates each contact's field rendering to a separate widget: `lib/features/contacts/widgets/venue_contact_block.dart`.

`venue_contact_block.dart` was **never explicitly named** in any prior off-limits table (original plan, Amendment 2, or Amendment 3 all list `venue_form_screen.dart` but not this file). Functionally, however, it is part of the same venue edit form Tony's instruction refers to as having been off-limits. This amendment treats it as in-scope for this narrow styling change, alongside the explicit reversal for `venue_form_screen.dart`.

**Net effect:** `venue_form_screen.dart` requires **no line changes** for this amendment — the section header/Add-button rendering it owns is already correct and unaffected. All actual edits happen in `venue_contact_block.dart`.

### Current State — Venue's own fields (`venue_form_screen.dart`, lines 391-455)

- Rendered as plain `TextField`s directly inside the form's `ListView` — no wrapping `Container`, no card, no border.
- Each field's gray fill comes entirely from the shared `_inputDecoration()` helper (`venue_form_screen.dart` lines 301-321): `filled: true, fillColor: context.colors.surface`, `OutlineInputBorder` using `context.colors.border`, `borderRadius: 8`.
- Vertical gaps between fields are a consistent `const SizedBox(height: 16)`: Name→Address (line 398), Address→City/State row (line 406), City/State row→Phone (line 437), Phone→Notes (line 447).

### Current State — Contact fields (`venue_contact_block.dart`)

- Each `VenueContactBlock` (one per venue contact) is wrapped in an outer `Container` (lines 146-153):
  ```dart
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.colors.border),
    ),
    child: Column(
  ```
  This `BoxDecoration` is the extra gray card shell that venue fields don't have. The internal `TextField`s (Name, Phone, Email, Notes) use the *same* `_inputDecoration()`-style pattern (locally defined at lines 122-142, functionally identical to the venue form's) — so each individual field's own fill already matches the venue fields. The mismatch is solely the outer wrapping container's background + border.
- Vertical gaps inside one contact block:
  - Line 182: `SizedBox(height: 12)` — header row → Name field
  - Line 192: `SizedBox(height: 12)` — Name → Title (label + `TitlePillSelector`)
  - Line 203: `SizedBox(height: 8)` — Title label → `TitlePillSelector` (internal to the Title field)
  - Line 211: `SizedBox(height: 12)` — Title → Phone
  - Line 223: `SizedBox(height: 12)` — Phone → Email
  - Line 234: `SizedBox(height: 8)` — Email → domain-chip shortcut row (internal to the Email field)
  - Line 257: `SizedBox(height: 12)` — domain chips → Notes

### Gap Analysis

1. **Background:** Contact blocks have an outer `color: context.colors.surface` + `border: Border.all(...)` on their wrapping `Container` that venue fields do not have. This is the "gray background" Tony is describing — it is a self-contained decoration property, not tied to field structure.
2. **Spacing:** The four field-to-field transitions inside a contact block (Name→Title, Title→Phone, Phone→Email, Email→Notes) use `12px`, while venue's own field-to-field transitions use `16px`. The two `8px` gaps (label→control within Title, and Email→domain-chip-row within Email) and the `12px` header→Name gap are internal/structural spacing with no equivalent on the venue side, so they are left out of scope — changing them would be restructuring internal field layout, not matching a form-field-to-form-field gap.

**Confirmation:** No new fields, no new validation, no change to `_emitChange()`, `onChanged`, or any save/load path in `venue_form_screen.dart`'s `_save()`. Purely visual: one `Container` decoration removal and four `SizedBox` height changes.

---

## Proposed Solution

### Part A: Remove Gray Background

In `venue_contact_block.dart`, remove the `color` and `border` properties from the outer `Container`'s `BoxDecoration` (lines 149-153), leaving `margin` and `padding` untouched so the block's overall footprint and internal field positions do not shift. Delete the now-empty `decoration:` property entirely rather than leaving an inert `BoxDecoration` with only `borderRadius`.

**Result:** Contact fields render on the plain form background, identical in visual weight to venue's own fields — since each field's own gray fill already comes from the identical `_inputDecoration()` pattern used by both sections.

### Part B: Normalize Field-to-Field Spacing to 16px

In `venue_contact_block.dart`, change the four field-to-field `SizedBox` gaps from `12` to `16`:
- Line 192 (Name → Title)
- Line 211 (Title → Phone)
- Line 223 (Phone → Email)
- Line 257 (domain chips → Notes)

Leave line 182 (header → Name, 12px) and lines 203 / 234 (internal label→control gaps, 8px) unchanged.

---

## Database Impact

**Not applicable.** Client-only styling change.

---

## Flutter Architecture Changes

None. No state, no controller, no repository changes. Pure widget-tree styling adjustment confined to `venue_contact_block.dart`'s `build()` method.

---

## Files to Create

**None.**

---

## Files to Modify

| File | What Changes |
|------|-------------|
| `lib/features/contacts/widgets/venue_contact_block.dart` | (1) Remove `color`/`border` from the outer `Container`'s `BoxDecoration` (lines 149-153), keeping `margin`/`padding` unchanged. (2) Change four `SizedBox(height: 12)` field-to-field gaps to `SizedBox(height: 16)` (lines 192, 211, 223, 257). |

**No changes required to `venue_form_screen.dart`** — investigation confirmed it does not render the contact fields directly; it only hosts the section header, "Add Contact" button, and `AnimatedList` wiring, none of which are affected by this styling correction.

---

## Files Off-Limits (Status Change)

**Reversal, scoped narrowly to this amendment only:**

| File | Status |
|------|--------|
| `lib/features/contacts/widgets/venue_form_screen.dart` | **Off-limits reversed for this round only**, per Tony's explicit instruction — reviewed in full; confirmed no edits are actually needed here (see Investigation Findings above). Reverts to off-limits after this amendment. |
| `lib/features/contacts/widgets/venue_contact_block.dart` | **Newly in-scope** — not previously named in any off-limits table, but functionally part of the edit form Tony intended. In-scope for this styling/spacing change only. |

**All other files from the original plan and prior amendments remain off-limits**, including `venues_repository.dart`, `venue.dart`, `venue_contact.dart`, `venue_card.dart`, `venues_view.dart`, `venue_detail_screen.dart`, and `contacts_tab_content.dart`.

---

## Migration Policy

**Not required.**

---

## New Dependencies

**None.**

---

## Regression Risk

**Level:** LOW

**Rationale:**

- Change is isolated to one widget's `build()` method (`venue_contact_block.dart`)
- No controller, repository, state, or save-path changes
- No new fields, no validation changes
- Purely visual: one decoration removal, four spacing value changes
- Contact add/remove animation (`AnimatedList`, `SizeTransition`/`FadeTransition` in `venue_form_screen.dart`) is untouched — margin/padding driving those transitions' sizing is preserved

---

## Engineer Task Breakdown

Execute in strict order:

### Task E1: Remove Gray Card Background from Contact Blocks

- Edit `lib/features/contacts/widgets/venue_contact_block.dart`:
  - In the `Container` returned by `build()` (lines 146-153), remove the `decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.colors.border))` property entirely.
  - Keep `margin: const EdgeInsets.only(bottom: 16)` and `padding: const EdgeInsets.all(16)` unchanged.

### Task E2: Normalize Spacing Between Contact Fields to 16px

- Edit `lib/features/contacts/widgets/venue_contact_block.dart`:
  - Line 192: change `const SizedBox(height: 12)` (Name → Title) to `const SizedBox(height: 16)`
  - Line 211: change `const SizedBox(height: 12)` (Title → Phone) to `const SizedBox(height: 16)`
  - Line 223: change `const SizedBox(height: 12)` (Phone → Email) to `const SizedBox(height: 16)`
  - Line 257: change `const SizedBox(height: 12)` (domain chips → Notes) to `const SizedBox(height: 16)`
  - Do **not** change line 182 (header → Name, 12px) or lines 203 / 234 (internal label→control gaps, 8px) — these are not field-to-field transitions and have no venue-field equivalent to match.

### Task E3: Verify

- Run `flutter analyze` — must pass with 0 errors, 0 warnings
- Confirm `venue_form_screen.dart` required no edits (per Investigation Findings) — if implementation reveals otherwise, stop and report back rather than improvising
- Visual check across platforms: contact fields render with no gray card/border shell, matching venue fields' plain appearance; 16px gaps between Name/Title/Phone/Email/Notes fields within a contact block, consistent with the 16px gaps between venue's own fields
- Confirm unaffected: "Add Contact" / remove (delete icon) animations, `TitlePillSelector` behavior, email domain-chip shortcuts, contact save/load round-trip via `_save()`

---

## Verification Plan

**Not applicable as two-tier DB verification** — client-only styling change, no database involved.

### Manual Testing (All platforms: Web, iOS, Android, macOS)

**Test E1: Background Removed**
1. Open venue edit form (new or existing venue with at least one contact)
2. Verify contact fields (Name, Title, Phone, Email, Notes) render without a gray card box or border around them
3. Verify each individual field still shows its own filled input background (unchanged — matches venue fields)

**Test E2: Spacing Matches Venue Fields**
1. Compare vertical gap between venue's own fields (e.g., Address → City/State) to the gap between contact fields (e.g., Name → Title, Phone → Email)
2. Verify gaps are visually consistent (16px) between both sections

**Test E3: No Functional Regression**
1. Add a new contact via "Add Contact" — verify entry animation, field entry, and save work unchanged
2. Remove a contact — verify removal animation unchanged
3. Edit an existing venue with multiple contacts — verify all contact data loads, edits, and saves correctly
4. Verify `TitlePillSelector` and email domain-chip shortcuts still function

---

## QA Regression Areas

**Primary Test Areas (This Amendment):**

27. **Contact Field Styling:**
    - No gray background/border box around contact field groups
    - Contact fields visually match venue fields' plain appearance
    - 16px spacing between contact fields matches 16px spacing between venue fields

**Regression Test Areas:**

28. **Venue Edit Form (Unchanged Behavior):**
    - Venue's own fields (Name, Address, City/State, Phone, Notes) render and save unchanged
    - "Add Contact" / remove contact animations unchanged
    - Contact save/load (create, update, delete) unchanged
    - `TitlePillSelector`, phone formatting, email domain-chip shortcuts unchanged
    - Delete Venue flow unchanged

29. **No Cross-Screen Regression:**
    - Venue list, detail screen, and search/index behavior from prior amendments unaffected (no files in those areas were touched)

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — styling-only change to venue edit form's contact section, all platforms |

---

## Out of Scope

Explicitly not included in this amendment:

1. **Restructuring contact fields** — no field reordering, no new fields, no removed fields
2. **Changing venue's own field styling** — venue fields are the reference/target style, not modified
3. **Header→field spacing (12px) or internal label→control spacing (8px)** — left unchanged, not "between form fields" gaps
4. **Data model, validation, or save/load logic changes** — confirmed none required
5. **`venue_form_screen.dart` code changes** — investigation confirmed none needed; off-limits status reverts after this amendment
6. **Contact block header/remove-button redesign** — unchanged
7. **Backend changes** — no database, RLS, RPC, or edge function changes

---

## Amendment Summary

Tony's requirement was framed around `venue_form_screen.dart`, but investigation showed the actual contact-field rendering lives in a separate, previously-unlisted file: `venue_contact_block.dart`. That file's outer `Container` wraps each contact block in a `BoxDecoration` (surface fill + border) that the venue's own fields don't have — that's the "gray background" mismatch. Internally, contact fields use 12px gaps between fields versus the venue section's 16px. The fix is two isolated, low-risk edits to `venue_contact_block.dart`: drop the `BoxDecoration` (keep margin/padding), and bump four field-to-field `SizedBox` gaps from 12px to 16px. `venue_form_screen.dart` needs no edits despite being the file named off-limits — its off-limits status is formally reversed for this round per instruction, then reverts.

**Files affected:** `venue_contact_block.dart` only.

**Regression risk: LOW** — single-widget styling change, no state/data/save-path impact.

**No new dependencies, no database changes, no backend changes.**

---

## Amendment: Detail Screen Polish

**Amendment Date:** 2026-07-25
**Amendment Author:** Architect
**Trigger:** User requirement from Tony — six polish items for the venue detail screen

---

## New Requirements

1. Add static title text "Venue Details" to the (currently bare) AppBar.
2. Increase top padding above the venue-name header row for visual separation from the title bar. Edit button must stay in its current position (same row as venue name, right-aligned) — not moved into the AppBar.
3. Contact Person's value should render one step larger than other field values.
4. Remove labels for Contact Title, Contact Phone, Contact Email in the read-only detail view (bare values, no label above). Contact Person's label stays. These labels must remain in the edit form's inputs.
5. Add a "navigate to this address" icon next to the venue's Address field, reusing the existing gig-details navigation mechanism rather than inventing a new one.
6. Preserve tap-to-call for venue Phone and Contact Phone; add tap-to-email for Contact Email (currently has no tap handler).

---

## Investigation

**Confidence:** HIGH (direct code observation)

### Current state of `venue_detail_screen.dart` (265 lines, substantially redesigned across the two most recent amendment rounds)

- **AppBar** (lines 26-32): bare — no `title`, no `actions`. `backgroundColor: context.colors.surface`, `foregroundColor: context.colors.textPrimary`, `elevation: 0`. Kept bare deliberately in "Detail Screen Redesign Round 2" so the venue name (rendered separately, below the AppBar) can wrap to multiple lines without the native single-line `AppBar.title` truncation.
- **Header row** (lines 37-74): a `Padding` (`EdgeInsets.fromLTRB(Spacing.pagePadding, Spacing.space8, Spacing.pagePadding, Spacing.space24)` — i.e., top padding is currently `Spacing.space8` = 8px) wrapping a `Row` with `Expanded(Text(venue.name, style: AppTextStyles.pageTitle...))` + a right-aligned `TextButton` labeled "Edit" (rose, navigates via `fadeSlideRoute` to `VenueFormScreen(venue: venue)`). This is the row item 2 must not disturb structurally — only the top padding value changes.
- **`_buildGroups()`** (lines 94-160): builds a flat list of grouped `Container` cards — Address+Phone group (lines 97-119), one group per contact (lines 121-145), and a standalone Notes group (lines 147-152).
  - Address field: `_buildFieldEntry(context, 'Address', _formatAddress(), maxLines: 3)` (lines 102-107) — added only if address/city/state present.
  - Phone field: `_buildFieldEntry(context, 'Phone', venue.phone!, onTap: () => _launchPhone(venue.phone!))` (lines 110-115).
  - Per contact: Contact Person (line 124, always shown), Contact Title (lines 126-130, conditional), Contact Phone (lines 131-138, conditional, tappable), Contact Email (lines 139-143, conditional, **no `onTap`**).
- **`_buildFieldEntry()`** (lines 197-240): current signature is `(BuildContext context, String label, String value, {VoidCallback? onTap, int maxLines = 2})`. `label` is non-nullable and always rendered (caption size, `textSecondary`) above the value (hardcoded `AppFontSizes.body`, `textPrimary`). To satisfy items 3 and 4, both the label-rendering and the value's font size need to become configurable per call site.
- **`_launchPhone()`** (lines 162-171): dials via `Uri(scheme: 'tel', ...)` + `launchUrl`. Already used by both venue Phone and Contact Phone — item 6's "preserve" requirement is satisfied automatically as long as this method and its two call sites are left untouched by the other edits (verified: none of items 1-5 touch this method or its call sites).
- No `_launchEmail()` exists. Contact Email (line 139-143) has no `onTap`.
- **Design tokens** (`design_tokens.dart` lines 309-324): `AppFontSizes.body = 16.0`. The next step up is `AppFontSizes.title = 18.0` (already an existing token — no new constant needed). Per instruction, Contact Person's value should use `AppFontSizes.title` (18px).

### Investigation for item 5 — gig details navigation icon

**File:** `lib/features/gigs/widgets/view_gig_drawer.dart` (this is the gig details action drawer — the "gig details screen" referred to in the requirement; `lib/features/gigs/` contains no other file with a maps/navigation pattern).

- **Trigger UI** (lines 297-326): a `Row` — venue/location text in `Expanded`, followed by an `IconButton`:
  ```dart
  IconButton(
    icon: const Icon(LucideIcons.navigation2, color: AppColors.primary),
    color: AppColors.primary,
    iconSize: 20,
    onPressed: () => _openNavigation(context),
    tooltip: 'Navigate',
    style: IconButton.styleFrom(
      side: const BorderSide(color: AppColors.primary, width: BrandButton.borderWidth),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Spacing.buttonRadius)),
    ),
  ),
  ```
- **Launch mechanism** (lines 54-206, enum at 445-449): `_openNavigation()` builds a query string from gig fields, tries a platform-default deep link first (`_buildDefaultNavigationUri`: `maps://?q=` on iOS, `geo:0,0?q=` on Android, `https://maps.google.com/?q=` elsewhere — `kIsWeb`/`defaultTargetPlatform` from `flutter/foundation.dart`), and if that fails to launch, shows a bottom-sheet app picker (`_showNavigationAppPicker`, an `_NavigationApp` enum: appleMaps/googleMaps/waze) and launches the chosen provider's URI via `_launchFallbackProvider` → `_providerUri`, showing a snackbar (`showAppSnackBar` from `shared/utils/snackbar_helper.dart`) if the chosen app isn't installed.
- **Dependencies used:** `lucide_flutter` (already a pubspec dependency, `^0.575.0` — confirmed in `pubspec.yaml`), `url_launcher` (already imported in `venue_detail_screen.dart`), `flutter/foundation.dart`, `shared/utils/snackbar_helper.dart`.
- **Query construction** (gig-specific, lines 54-58): `hasAddress ? '${gig.address} ${gig.location}' : '${gig.name} ${gig.location}'`. `Venue` has no single "location" field — the equivalent composition for a venue is street address (or venue name if no street address) plus city and state.

**Reuse decision:** Per instruction ("reusing the same icon, launch mechanism... rather than inventing a new one") and per `GUARDRAILS.md` §7 ("never refactor opportunistically," "prefer localized in-place edits over new abstractions"), the mechanism is **duplicated** into `venue_detail_screen.dart` as private methods (mirroring `ViewGigDrawer`, which is also a `StatelessWidget`), not extracted into a shared cross-feature helper — extracting a new shared utility was not requested and would be a new abstraction beyond what item 5 asks for. Only the query-construction logic is venue-specific; the URI schemes, app-picker sheet, fallback launch, and button styling are copied verbatim.

**File size note:** `venue_detail_screen.dart` is currently 265 lines. Duplicating the navigation mechanism (~120-130 lines including the picker sheet and enum) plus the other five items brings the file to an estimated ~400-420 lines, at or slightly past the `GUARDRAILS.md` §8 "Feature widgets: 400 lines" target. This is a soft target, not a hard stop, and the Architect permits the overage here: the alternative (extracting a shared navigation helper) is an unrequested abstraction, and the file remains a single, cohesive read-only detail screen with no structural complexity added.

---

## Proposed Solution

### Item 1 — AppBar title

Add `title: Text('Venue Details', style: AppTextStyles.title3)` to the `AppBar` (lines 28-32). No explicit color needed — the `AppBar`'s existing `foregroundColor: context.colors.textPrimary` supplies it, matching the convention used elsewhere (e.g., `tips_and_tricks_screen.dart` line 78, `create_setlist_screen.dart` line 22: `Text('...', style: AppTextStyles.title3)` with no color override).

### Item 2 — Header row top padding

Change the header row's `Padding` (line 39) top value from `Spacing.space8` (8px) to `Spacing.space24` (24px), matching the existing bottom value on the same `Padding` for visual rhythm. The Edit `TextButton` is a sibling of the venue-name `Text` inside the same `Row` at lines 45-73 — untouched structurally; only the padding of their shared parent changes.

### Item 3 — Contact Person value font size

Add a `double valueFontSize = AppFontSizes.body` parameter to `_buildFieldEntry()`; use it in place of the hardcoded `AppFontSizes.body` on the value `Text`'s style (line ~220). At the Contact Person call site only (line 124), pass `valueFontSize: AppFontSizes.title` (18px — one token step above `body`'s 16px, per design_tokens.dart). All other call sites (Address, Phone, Contact Title/Phone/Email, Notes) omit the parameter and keep the 16px default.

### Item 4 — Remove labels for Contact Title/Phone/Email

Change `_buildFieldEntry()`'s `label` parameter from `String label` to `String? label`. Inside the method, wrap the label `Text` + its `SizedBox(height: 8)` in `if (label != null) ...[...]`, rendering only the value when `label` is null. Update the three call sites:
- Contact Title (line 128): `_buildFieldEntry(context, null, contact.title!)`
- Contact Phone (line 132-137): `_buildFieldEntry(context, null, contact.phone!, onTap: () => _launchPhone(contact.phone!))`
- Contact Email (line 140-142): `_buildFieldEntry(context, null, contact.email!, onTap: () => _launchEmail(contact.email!))`

Contact Person (line 124) keeps `'Contact Person'` as its label — unchanged. Address, Phone, and Notes call sites are unchanged (still pass their string labels).

**Edit form confirmation (no change needed there):** `venue_contact_block.dart` (the widget that actually renders the edit form's per-contact inputs — confirmed in the prior "Edit Form Contact Section Styling" amendment) already shows its own labels independently of this screen: `_inputDecoration('Name'/'Phone'/'Email')` sets `labelText` on each `TextField` (lines 185, 214, 226), and Title has its own `Text('Title', ...)` label above the `TitlePillSelector` (lines 190-197). These are separate widgets from `venue_detail_screen.dart`'s `_buildFieldEntry()` labels and are unaffected by this amendment.

### Item 5 — Navigation icon on Address field

Duplicate the navigation mechanism from `view_gig_drawer.dart` into `venue_detail_screen.dart` as new private methods, adapted only in query construction:

- New imports: `package:flutter/foundation.dart` (for `kIsWeb`, `defaultTargetPlatform`), `package:lucide_flutter/lucide_flutter.dart` (for `LucideIcons.navigation2`), `package:bandroadie/shared/utils/snackbar_helper.dart` (for `showAppSnackBar`). `url_launcher` is already imported.
- New helper `_navigationQuery()`:
  ```dart
  String _navigationQuery() {
    final parts = <String>[];
    if (venue.address != null && venue.address!.isNotEmpty) {
      parts.add(venue.address!);
    } else {
      parts.add(venue.name);
    }
    if (venue.city != null && venue.city!.isNotEmpty) parts.add(venue.city!);
    if (venue.state != null && venue.state!.isNotEmpty) parts.add(venue.state!);
    return parts.join(' ');
  }
  ```
  (Mirrors the gig drawer's `hasAddress ? address+location : name+location` fallback, substituting venue's city/state for the gig's single `location` field.)
- New methods, copied verbatim from `view_gig_drawer.dart` except for the query source: `_openNavigation(BuildContext context)` (uses `_navigationQuery()` instead of gig fields, otherwise identical control flow to lines 54-87), `_buildDefaultNavigationUri(String query)` (identical to lines 89-101), `_showNavigationAppPicker(BuildContext context)` (identical to lines 103-154), `_launchFallbackProvider(...)` (identical to lines 156-179), `_providerUri(...)` (identical to lines 181-195), `_appName(...)` (identical to lines 197-206), and the `enum _NavigationApp { appleMaps, googleMaps, waze }` (identical to lines 445-449).
- In `_buildGroups()`, wrap the Address field entry (currently lines 102-107) in a `Row` so the icon sits beside it:
  ```dart
  addressPhoneFields.add(
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildFieldEntry(context, 'Address', _formatAddress(), maxLines: 3),
        ),
        IconButton(
          icon: const Icon(LucideIcons.navigation2, color: AppColors.primary),
          color: AppColors.primary,
          iconSize: 20,
          tooltip: 'Navigate',
          onPressed: () => _openNavigation(context),
          style: IconButton.styleFrom(
            side: const BorderSide(color: AppColors.primary, width: BrandButton.borderWidth),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Spacing.buttonRadius)),
          ),
        ),
      ],
    ),
  );
  ```
  This is added only inside the existing conditional (address/city/state present) — same condition that already gates the Address field today, so the icon never appears without an address to navigate to.

### Item 6 — Tap-to-call preserved, tap-to-email added

`_launchPhone()` and its two call sites (venue Phone, Contact Phone) are not touched by items 1-5 — confirmed preserved by construction. Add `_launchEmail(String email)`, mirroring `_launchPhone()`'s pattern:
```dart
Future<void> _launchEmail(String email) async {
  final uri = Uri(scheme: 'mailto', path: email);
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  } catch (_) {}
}
```
Wire it as the `onTap` for the Contact Email field entry (see item 4's call-site change above).

---

## Database Impact

**Not applicable.** Client-only UI changes to a single screen.

---

## Flutter Architecture Changes

All changes confined to `lib/features/contacts/widgets/venue_detail_screen.dart`. No controller, repository, model, or state management changes. `_buildFieldEntry()`'s signature changes (nullable `label`, new `valueFontSize` parameter) are additive/widening — all existing call sites either already pass a non-null label (unaffected) or are explicitly updated in this amendment.

---

## Files to Create

**None.**

---

## Files to Modify

| File | What Changes |
|------|-------------|
| `lib/features/contacts/widgets/venue_detail_screen.dart` | **(1)** Add `title: Text('Venue Details', style: AppTextStyles.title3)` to AppBar. **(2)** Increase header row's top padding from `Spacing.space8` to `Spacing.space24`. **(3)** Add `valueFontSize` parameter to `_buildFieldEntry()`; pass `AppFontSizes.title` at the Contact Person call site only. **(4)** Make `_buildFieldEntry()`'s `label` parameter nullable, omitting label rendering when null; pass `null` at Contact Title/Phone/Email call sites. **(5)** Add navigation icon + duplicated navigation mechanism (`_openNavigation`, `_buildDefaultNavigationUri`, `_showNavigationAppPicker`, `_launchFallbackProvider`, `_providerUri`, `_appName`, `_navigationQuery`, `enum _NavigationApp`) adapted from `view_gig_drawer.dart`; wrap Address field in a `Row` with the new icon button. **(6)** Add `_launchEmail()`; wire as Contact Email's `onTap`. New imports: `flutter/foundation.dart`, `lucide_flutter`, `shared/utils/snackbar_helper.dart`. |

---

## Files Off-Limits

All files from the original plan and every prior amendment remain off-limits **except** the one listed above, with one clarification:

| File | Reason |
|------|--------|
| `lib/features/gigs/widgets/view_gig_drawer.dart` | **Read-only reference for this amendment.** Its navigation mechanism is duplicated, not modified — this file itself is not touched. |
| `lib/features/contacts/widgets/venue_contact_block.dart` | Confirmed (Investigation, item 4) already has its own labels for Title/Phone/Email; no changes needed or permitted here. |
| `lib/features/contacts/widgets/venue_form_screen.dart` | Edit screen — unaffected by detail-screen polish. |
| `lib/features/contacts/widgets/venues_view.dart`, `venue_card.dart` | List view — finalized in prior amendments, unaffected. |
| `lib/features/contacts/venues_controller.dart`, `venues_repository.dart`, `models/venue.dart`, `models/venue_contact.dart` | Data layer — unaffected, no new fields needed (query uses existing `address`/`city`/`state`/`name`/`email`). |

---

## Migration Policy

**Not required.** Client-only UI change.

---

## New Dependencies

**None.** `lucide_flutter` and `url_launcher` are already pubspec dependencies (confirmed); only new *imports* of already-available packages/files are added to `venue_detail_screen.dart`.

---

## Regression Risk

**Level:** LOW

**Rationale:**

- Isolated to a single screen (`venue_detail_screen.dart`), no cross-feature or backend impact
- No data mutations — navigation icon only opens external maps apps; email tap only opens external mail client
- `_launchPhone()` and its call sites are untouched by construction (verified in Investigation) — tap-to-call regression risk is effectively zero
- `_buildFieldEntry()` signature changes are backward-widening (nullable label, defaulted new parameter) — every existing call site either needs no change or is explicitly updated here
- Navigation mechanism is a verbatim copy of an already-shipped, working pattern (`view_gig_drawer.dart`) — no new URI schemes or fallback logic invented

**Risk factor noted:** File grows to an estimated ~400-420 lines (see Investigation "File size note"), at/past the `GUARDRAILS.md` §8 soft target for feature widgets. Accepted as a soft-target overage per guardrails; no structural/architectural risk introduced.

---

## Engineer Task Breakdown

Execute in strict order:

### Task F1: Add AppBar Title

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Add `title: Text('Venue Details', style: AppTextStyles.title3)` to the `AppBar` (lines 28-32)

### Task F2: Increase Header Row Top Padding

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Change the header `Padding`'s (line 39) top value from `Spacing.space8` to `Spacing.space24`
  - Do not move, restyle, or reposition the "Edit" `TextButton` — it stays in the same `Row` as the venue name, right-aligned

### Task F3: Bump Contact Person Value Font Size

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Add `double valueFontSize = AppFontSizes.body` parameter to `_buildFieldEntry()`
  - Use `valueFontSize` in the value `Text`'s `style.fontSize` (replacing the hardcoded `AppFontSizes.body`)
  - At the Contact Person call site (line 124), pass `valueFontSize: AppFontSizes.title`
  - Leave all other call sites unchanged (they inherit the 16px default)

### Task F4: Remove Labels for Contact Title/Phone/Email

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Change `_buildFieldEntry()`'s `label` parameter from `String label` to `String? label`
  - Wrap the label `Text` + following `SizedBox(height: 8)` in `if (label != null) ...[...]`
  - Update Contact Title call site to pass `null` instead of `'Contact Title'`
  - Update Contact Phone call site to pass `null` instead of `'Contact Phone'`
  - Update Contact Email call site to pass `null` instead of `'Contact Email'`
  - Leave Contact Person's label (`'Contact Person'`) and all non-contact call sites (Address, Phone, Notes) unchanged
  - No changes to `venue_contact_block.dart` — confirmed its labels are independent and already correct

### Task F5: Add Navigation Icon to Address Field

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Add imports: `package:flutter/foundation.dart`, `package:lucide_flutter/lucide_flutter.dart`, `package:bandroadie/shared/utils/snackbar_helper.dart`
  - Add `_navigationQuery()` helper (see Proposed Solution, item 5)
  - Add `_openNavigation(BuildContext context)`, `_buildDefaultNavigationUri(String query)`, `_showNavigationAppPicker(BuildContext context)`, `_launchFallbackProvider(...)`, `_providerUri(...)`, `_appName(...)`, and `enum _NavigationApp { appleMaps, googleMaps, waze }`, adapted from `view_gig_drawer.dart` lines 54-206 and 445-449 (identical logic; only the query source changes)
  - In `_buildGroups()`, wrap the Address field entry in a `Row` with the new `IconButton` (icon `LucideIcons.navigation2`, `AppColors.primary`, `iconSize: 20`, `tooltip: 'Navigate'`, bordered `IconButton.styleFrom` matching `view_gig_drawer.dart`'s styling), inside the existing address/city/state conditional

### Task F6: Add Tap-to-Email

- Edit `lib/features/contacts/widgets/venue_detail_screen.dart`:
  - Add `_launchEmail(String email)` mirroring `_launchPhone()`'s try/`canLaunchUrl`/`launchUrl` pattern, using `Uri(scheme: 'mailto', path: email)`
  - Wire it as the Contact Email field entry's `onTap` (part of Task F4's call-site update)

### Task F7: Verify

- Run `flutter analyze` — must pass with 0 errors, 0 warnings
- Confirm `_launchPhone()` and its two call sites (venue Phone, Contact Phone) are unchanged
- Confirm Edit button still navigates to `VenueFormScreen(venue: venue)`, still right-aligned on the venue-name row
- Confirm `venue_contact_block.dart` was not touched (Contact Title/Phone/Email labels in the edit form remain intact)
- Format all changed files with `dart format`

---

## Verification Plan

**Not applicable as two-tier DB verification** — client-only UI change, no database involved.

### Manual Testing (All platforms: Web, iOS, Android, macOS)

**Test F1: AppBar Title**
1. Navigate to a venue's detail screen
2. Verify "Venue Details" appears in the AppBar

**Test F2: Header Spacing**
1. Verify visibly more space between the AppBar and the venue name/Edit row than before
2. Verify Edit button is still on the same row as the venue name, right-aligned, unmoved

**Test F3: Contact Person Font Size**
1. Navigate to a venue with at least one contact
2. Verify Contact Person's value renders visibly larger than Contact Title/Phone/Email and Address/Phone/Notes values

**Test F4: Labels Removed**
1. Verify Contact Title, Contact Phone, Contact Email render as bare values with no label above them
2. Verify Contact Person still shows its "Contact Person" label
3. Open the same venue's Edit form → verify Title, Phone, Email fields (in the contact block) still show their own labels

**Test F5: Navigation Icon**
1. Navigate to a venue with an address
2. Verify a navigation icon appears beside the Address field
3. Tap it → verify it attempts to open the device's default maps app (or shows the Apple Maps/Google Maps/Waze picker as fallback, matching gig details behavior)
4. Navigate to a venue with only city/state (no street address) → verify icon still appears and navigates using available fields

**Test F6: Tap-to-Call and Tap-to-Email**
1. Tap venue Phone → verify dialer launches (regression check)
2. Tap Contact Phone → verify dialer launches (regression check)
3. Tap Contact Email → verify device's mail client opens with the address pre-filled (new functionality)

---

## QA Regression Areas

### Primary Test Areas (This Amendment)

30. **AppBar Title:** "Venue Details" static title displays correctly on all platforms
31. **Header Spacing:** Increased top padding visible; Edit button position/behavior unchanged
32. **Contact Person Emphasis:** Font size visibly larger than other field values
33. **Label Omission:** Contact Title/Phone/Email show no label; Contact Person label intact; edit form labels intact
34. **Navigate Icon:** Icon appears next to Address, matches gig-details visual style, launches maps app or picker correctly with partial-address fallback
35. **Tap-to-Email:** Contact Email opens mail client with correct address pre-filled

### Regression Test Areas

36. **Tap-to-Call:** Venue Phone and Contact Phone both still launch dialer correctly
37. **Edit Navigation:** Edit button still opens `VenueFormScreen` pre-filled with venue data
38. **Detail Screen Layout:** Grouped containers (Address+Phone, per-contact, Notes) still render correctly; graceful field omission for missing data unchanged
39. **List/Search/Index (No Regression Expected):** `venues_view.dart`, `venue_card.dart` untouched by this amendment — confirm no regressions

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected — `view_gig_drawer.dart` read as reference only, not modified |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected — no new navigation destinations, only external app launches (maps, mail) |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — maps deep-link scheme differs per platform (`maps://` iOS, `geo:` Android, HTTPS fallback elsewhere); mailto and tel launches are cross-platform |

---

## Out of Scope

Explicitly not included in this amendment:

1. **Modifying `view_gig_drawer.dart`** — read-only reference; the navigation mechanism is duplicated, not extracted or refactored
2. **Extracting a shared navigation helper/widget** — not requested; would be a new abstraction beyond the scope of "replicate in place"
3. **Changing venue list card or search/index behavior** — `venues_view.dart`, `venue_card.dart` untouched
4. **Changing the edit form's contact field labels/styling** — `venue_contact_block.dart` confirmed already correct, untouched
5. **Adding a navigation icon to Contact Phone or other fields** — only the venue Address field gets the navigate icon, per requirement
6. **Backend changes** — no database, RLS, RPC, or edge function changes

---

## Amendment Summary

Six polish items applied to `venue_detail_screen.dart` only: a static "Venue Details" AppBar title, increased top spacing above the venue-name/Edit row (Edit button position unchanged), a one-step-larger font for Contact Person's value, removal of labels for Contact Title/Phone/Email (Contact Person's label and the edit form's own labels are unaffected), a "navigate to this address" icon next to Address — duplicating `view_gig_drawer.dart`'s existing maps-launch mechanism (default deep link with Apple Maps/Google Maps/Waze picker fallback) rather than inventing a new one — and a new `_launchEmail()` wired to Contact Email, alongside confirmation that `_launchPhone()` and its two existing call sites are untouched.

**Files affected:** `venue_detail_screen.dart` only (read-only reference to `view_gig_drawer.dart` for pattern-matching, not modified).

**Regression risk: LOW** — single-screen, no backend/data changes, navigation mechanism is a verbatim copy of an already-shipped pattern. Noted: file size grows to an estimated ~400-420 lines, at/past the guardrails' soft target for feature widgets, accepted given the alternative is an unrequested new abstraction.

**No new dependencies, no database changes, no backend changes.**

---

## Amendment 6: Search Scope Retroactive Authorization + List Grouping Performance Fix

**Amendment Date:** 2026-07-25
**Amendment Author:** Architect
**Trigger:** `QA_REPORT.md` verdict REQUIRES CHANGES — Critical Issue #1 (undocumented search scope expansion) and Warning #1 (redundant per-item grouping recompute)

### Background

`QA_REPORT.md` documents that an earlier QA session made live edits to `venues_view.dart` and `venues_controller.dart` at Tony's direct request — including expanding the search filter to match venue city and contact names — without routing the change through an Architect amendment, in violation of the documented pipeline (`docs/agents/QA.md`, `docs/agents/OPERATING_MODEL.md`). The code change itself was verified correct and low-risk by QA; the only defect is procedural — `ARCHITECT_PLAN.md` was never updated to reflect it, so the plan contradicted the shipped code. Tony has now confirmed directly that he wants the expanded search behavior kept. This amendment closes that gap retroactively (Part A) and separately addresses a QA-flagged performance warning (Part B) that requires an actual code change.

---

### Part A: Search Scope Retroactive Authorization

#### Current Actual Behavior (verified in code)

`lib/features/contacts/venues_controller.dart`, `_filterVenues()` (lines 164–174):

```dart
List<Venue> _filterVenues(List<Venue> venues, String query) {
  if (query.isEmpty) return venues;
  final lower = query.toLowerCase();
  return venues.where((v) {
    if (v.name.toLowerCase().contains(lower)) return true;
    if (v.city != null && v.city!.toLowerCase().contains(lower)) {
      return true;
    }
    return v.contacts.any((c) => c.name.toLowerCase().contains(lower));
  }).toList();
}
```

The search bar hint text in `venues_view.dart` (line 433) reads `'Search venues, names, cities'`, openly reflecting this.

**Confirmed matching fields, exactly three:**

1. Venue name — case-insensitive substring match
2. Venue city — case-insensitive substring match, null-safe (venues with no city are simply not matched on this field, not excluded from results)
3. Contact person name — case-insensitive substring match against any `VenueContact.name` belonging to the venue

**Confirmed NOT matched** (no further scope creep beyond what's already shipped): venue address, venue state, venue phone, venue notes, contact title, contact phone, contact email. There is no fuzzy matching, no per-field weighting, no filter-chip UI, and no debounce behavior beyond what the original plan specified.

#### Authorization

The behavior above is **retroactively authorized** as of this amendment. This is documentation-only for Part A — the code is already implemented, `flutter analyze` clean, and QA has already verified it functionally correct. No Engineer tasks are required for Part A.

The original plan's Out of Scope item 5 (line 478) and Amendment 2's Out of Scope item 5 (line ~1262) are both superseded — see inline annotations added at those locations. The corrected scope statement is:

> **Search fields:** Search matches venue name, venue city, and contact person name (case-insensitive substring match on each). It does not match venue address, state, phone, notes, or contact title/phone/email. This is the full and final search scope for this feature — any further expansion requires a new Architect amendment.

---

### Part B: List Grouping Performance Fix

#### Root Cause

**Confidence:** HIGH (direct code observation)

`_groupVenuesByLetter()` (`venues_view.dart` lines 220–238) builds a `Map<String, List<Venue>>` by iterating the full venue list and then sorts its entries — an O(n log n) operation over the entire venue list, every time it is called. It is currently called independently, with no shared cache, from three separate sites:

1. `_calculateItemCount()` (line 104) — called once per `build()`, via the `itemCount:` parameter passed to `ScrollablePositionedList.builder` (line 413)
2. `_buildItem()` (line 157) — called via the `itemBuilder:` callback (line 414–416), which `ScrollablePositionedList.builder` invokes lazily **once per newly-visible item as the user scrolls**, not once per `build()`
3. `_buildIndexColumn()` (line 489) — called once per `build()`, when not searching (line 423)

The redundant cost sits specifically in `_buildItem()`: every time a new item scrolls into view, the full grouping-and-sort over the entire venue list re-runs from scratch, even though the result is identical to the previous call within the same `build()` cycle. `GUARDRAILS.md` §5 explicitly warns against scanning entire lists inside `build()`; this is the lazy-builder equivalent of that same anti-pattern, and it sits directly on the "smooth scrolling with 200+ venues" requirement this plan's own Verification Plan (Test 6 / Test A4) calls out.

#### Proposed Solution

Compute `grouped` **once per `build()` call** and pass it down as a parameter into `_calculateItemCount`, `_buildItem`, and `_buildIndexColumn`, replacing each function's independent internal call to `_groupVenuesByLetter()`.

`build()` already re-runs whenever `venuesProvider` state changes (venues loaded/refreshed) or `searchQuery` toggles `isSearching` — both of which are exactly the conditions under which the grouped map needs to be recomputed. Computing it once at the top of `build()`, guarded by `isSearching` (grouping is only needed in the sectioned branch), gives correct invalidation for free with no additional caching, memoization, or dirty-checking machinery required.

This is a pure refactor of existing private method signatures within a single file. **Confirmed: no new files, no new dependencies** — `_groupVenuesByLetter()`'s internal logic is unchanged; only the number of times it executes changes (from up to N+2 times per render cycle, where N is the number of items scrolled into view, down to exactly 1).

#### Files to Modify (Amendment 6, Part B)

| File | What Changes |
|------|---------------|
| `lib/features/contacts/widgets/venues_view.dart` | Compute `grouped` once in `build()`; thread it as a parameter into `_calculateItemCount`, `_buildItem`, and `_buildIndexColumn`, removing their internal calls to `_groupVenuesByLetter()`. No other files touched. |

#### Files Off-Limits (Amendment 6)

All files from the original plan and prior amendments remain off-limits. `venues_controller.dart` is off-limits for Part B (Part A requires no code change to it either — it is already correct). No new files. No new dependencies.

#### Migration Policy

**Not required.** Client-only, no backend involvement in either part.

#### New Dependencies

**None.**

#### Regression Risk

**Level:** LOW

**Rationale:** Part A requires no code change at all. Part B is a signature-only refactor of three private methods in one file — the grouping algorithm, sort order, section boundaries, and rendered output are byte-for-byte unchanged; only *when* the computation runs changes. No public API, no state shape, no widget tree structure changes.

#### Engineer Task Breakdown (Amendment 6)

Part A requires no Engineer tasks (documentation-only, already shipped and QA-verified).

**Part B — execute in order, all within `venues_view.dart`:**

##### Task C1: Compute `grouped` Once in `build()`

- In `build()`, immediately after `isSearching` and `displayVenues` are computed (around line 278–280), add:
  ```dart
  final grouped = isSearching
      ? const <String, List<Venue>>{}
      : _groupVenuesByLetter(displayVenues);
  ```

##### Task C2: Thread `grouped` into `_calculateItemCount`

- Change signature to `int _calculateItemCount(bool isSearching, List<Venue> venues, Map<String, List<Venue>> grouped)`
- Remove the internal `final grouped = _groupVenuesByLetter(venues);` call (line 104); use the passed-in parameter instead

##### Task C3: Thread `grouped` into `_buildItem`

- Change signature to `Widget _buildItem(BuildContext context, int index, bool isSearching, List<Venue> venues, Map<String, List<Venue>> grouped)`
- Remove the internal `final grouped = _groupVenuesByLetter(venues);` call (line 157); use the passed-in parameter instead

##### Task C4: Thread `grouped` into `_buildIndexColumn`

- Change signature to `Widget _buildIndexColumn(BuildContext context, List<Venue> venues, Map<String, List<Venue>> grouped)`
- Remove the internal `final grouped = _groupVenuesByLetter(venues);` call (line 489); use the passed-in parameter instead

##### Task C5: Update Call Sites in `build()`

- Update the `itemCount:` call (line 413) to pass `grouped`
- Update the `itemBuilder:` call (lines 414–416) to pass `grouped`
- Update the `_buildIndexColumn` call (line 423) to pass `grouped`

##### Task C6: Confirm No Behavioral Drift

- `_groupVenuesByLetter()` itself (lines 220–238) is unchanged — same grouping rule, same sort order (A–Z then `#`)
- Confirm the empty-search-results branch (lines 283–358), which never calls any of the three grouping-dependent functions, is unaffected

---

### Verification Plan (Amendment 6)

**Part A:** No new verification required — already verified by QA (`QA_REPORT.md`, "Everything else — matches spec on code-path review").

**Part B — Manual Testing (client-side, all platforms):**

**Test C1: Rendering Parity**
1. Load venues list (non-searching, sectioned view)
2. Confirm section headers, letters, and venue ordering are pixel-identical to pre-fix behavior
3. Confirm item count (including bottom spacer) is unchanged

**Test C2: Index Column Parity**
1. Tap each populated letter in the index column
2. Confirm scroll-to-section still lands on the correct section (using `_getFlatIndexForSection`, unchanged)
3. Tap an empty letter, confirm "nearest populated section" fallback still works

**Test C3: Search Mode Unaffected**
1. Type in search bar, confirm flat filtered list renders correctly (the `grouped` map passed in this branch is an empty const map and must not be read by the searching branch of `_buildItem`)
2. Clear search, confirm sectioned view restores correctly

**Test C4: Scroll Performance (200+ venues)**
1. Load 200+ venues, scroll continuously top to bottom and back
2. Confirm no visual regression; performance should be equal or better than pre-fix (fewer redundant sort operations per scroll)
3. Per `GUARDRAILS.md` §12, measure in release mode, not debug — debug-mode frame time is not representative

---

### QA Regression Areas (Amendment 6)

**Primary Test Areas:**

1. **Search scope (Part A):** Confirm search continues to match venue name, city, and contact person name only — no further fields. Confirm hint text still reads `'Search venues, names, cities'`.
2. **Grouping call-site consolidation (Part B):** Confirm `_groupVenuesByLetter()` is invoked exactly once per `build()` call (not once per scrolled-in item) — verifiable via a temporary debug print during QA if desired, removed before commit.
3. **Rendering parity (Part B):** Section headers, item ordering, item count, and index column behavior must be identical to pre-fix — this is a pure performance refactor with zero intended visual or functional change.

**Regression Test Areas:**

4. Index column tap-to-scroll (all 27 entries, including nearest-section fallback for empty letters)
5. Search → clear search transition (sectioned view restoration)
6. Empty search results state (unaffected — never reads `grouped`)
7. Scroll performance with 200+ venues, measured in release mode

---

### System Impact Map (Amendment 6)

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — scroll rendering performance improved on all platforms; no platform-specific code |

---

### Out of Scope (Amendment 6)

Explicitly not included in this amendment:

1. **Further search field expansion** — venue name, city, and contact person name are the final, authorized search scope; address, state, phone, notes, and other contact fields remain unmatched
2. **Fuzzy matching, search debouncing, or ranking changes** — search remains exact case-insensitive substring match, applied synchronously on every keystroke as originally implemented
3. **Caching/memoization beyond per-`build()` computation** — no `Provider`-level cache, no manual dirty-checking; Flutter's own rebuild-on-state-change behavior is sufficient, since `build()` only re-runs when `venuesProvider` state actually changes
4. **Changes to `_groupVenuesByLetter()`'s internal grouping or sort logic** — algorithm unchanged, only call-site count changes
5. **Sticky header work** — already resolved and removed per prior QA verification; not reopened by this amendment
6. **Changes to `venue_card.dart`, `venue_detail_screen.dart`, or `venue_contact_block.dart`** — untouched by this amendment
7. **Backend changes** — no database, RLS, RPC, or edge function changes
8. **New files, new dependencies** — confirmed not needed for either part

---

### Amendment Summary

**Part A** retroactively authorizes the already-shipped, already QA-verified search scope expansion (venue name + city + contact person name), resolving `QA_REPORT.md`'s Critical Issue #1 by bringing `ARCHITECT_PLAN.md` into agreement with the actual code. No code changes required. The prior "Out of Scope" restrictions (original plan and Amendment 2) are marked superseded in place, and confirmed scope creep is bounded — investigation found exactly the three fields QA already identified, nothing further.

**Part B** resolves `QA_REPORT.md`'s Warning #1 by consolidating three independent call sites of `_groupVenuesByLetter()` — an O(n log n) operation over the full venue list — down to a single computation per `build()`, threaded through as a parameter. This directly targets the redundant per-scrolled-item recomputation inside `_buildItem()`, which is the hot path since `ScrollablePositionedList.builder`'s `itemBuilder` runs lazily per newly-visible item during scroll. Pure refactor, zero intended behavioral or visual change.

**Files affected:** `venues_controller.dart` (none — Part A is documentation-only), `venues_view.dart` (Part B only, signature-only refactor of three private methods).

**Regression risk: LOW** for both parts — Part A ships no code change; Part B changes only internal call plumbing with no change to algorithm, output, or public API.

**No new dependencies, no database changes, no backend changes, no new files.**
