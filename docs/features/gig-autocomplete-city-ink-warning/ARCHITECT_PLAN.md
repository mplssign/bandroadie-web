# Architect Plan: Gig Autocomplete City Query and Ink Warning Fix

## Feature Slug

`bug/gig-autocomplete-city-ink-warning`

---

## Problem Summary

Two independent bugs in the gig form's autocomplete fields:

1. **City autocomplete queries nonexistent column**: `_fetchGigCitySuggestions()` in `event_editor_drawer.dart` queries `.from('gigs').select('city, date')` but the `gigs` table has no `city` column (the correct column is `location`). Every keystroke throws `PostgrestException` code `42703` "column gigs.city does not exist", which is silently caught. City suggestions have never worked since this was introduced.

2. **Ink-visibility warning in autocomplete dropdowns**: Both `_buildGigNameAutocomplete()` (~line 618) and `_buildGigCityAutocomplete()` (~line 695) in `gig_form_fields.dart` wrap their options list in `Material(elevation: 4) > Container(decoration: BoxDecoration(...)) > ListView`. The `Container`'s `BoxDecoration` sits between the `Material` ancestor and the `ListTile` children, blocking ink rendering. Flutter throws the framework assertion "ListTile background color or ink splashes may be invisible" every time the dropdown opens.

---

## Root Cause

### Bug 1: Nonexistent Column Query (Confidence: HIGH)

**Confirmed in code** at `lib/features/events/widgets/event_editor_drawer.dart:878-926`:

```dart
void _fetchGigCitySuggestions(String query) {
  _gigCityDebounceTimer?.cancel();

  if (query.length < 2) {
    if (_gigCitySuggestions.isNotEmpty) {
      setState(() => _gigCitySuggestions = []);
    }
    return;
  }

  _gigCityDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
    try {
      final response = await supabase
          .from('gigs')
          .select('city, date')  // ← BUG: 'city' column does not exist
          .eq('band_id', widget.bandId)
          .not('city', 'is', null)  // ← Also references nonexistent column
          .neq('city', '')           // ← Also references nonexistent column
          .ilike('city', '$query%')  // ← Also references nonexistent column
          .order('date', ascending: false)
          .limit(30);

      // Dedupe logic (never reached due to exception)...

    } catch (e) {
      debugPrint('[GigCityAutocomplete] Error: $e');
      // Fail silently ← Exception swallowed here
    }
  });
}
```

**Database schema confirmed** via migrations and code inspection:

- `gigs` table stores city in the `location` column (verified in `events_repository.dart:696` where `'location': formData.location` is inserted)
- `gigs` table has: `id`, `band_id`, `name`, `date`, `start_time`, `end_time`, `load_in_time`, **`location`** (city), `address` (street), `state`, `notes`, `is_potential`, `setlist_id`, `setlist_name`, `required_member_ids`, `gig_pay`, `venue_id`
- `venues` table separately has a `city` column, but gigs store their own city value in `location` (with optional `venue_id` FK for linking to a venue record)

**Why it fails:**

- Every query throws `PostgrestException` with code `42703` (undefined_column)
- The try/catch silently swallows the exception and logs it
- The suggestions list is never populated, so users see no autocomplete options

---

### Bug 2: Container Blocking Ink (Confidence: HIGH)

**Confirmed in code** at two locations:

**Location 1:** `lib/features/events/widgets/gig_form_fields.dart:618-672` (`_buildGigNameAutocomplete`)

```dart
optionsViewBuilder: (
  BuildContext context,
  AutocompleteOnSelected<String> onSelected,
  Iterable<String> options,
) {
  if (options.isEmpty) return const SizedBox.shrink();
  return Align(
    alignment: Alignment.topLeft,
    child: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      child: Container(  // ← BUG: This Container blocks ink
        constraints: const BoxConstraints(maxHeight: 200),
        width: MediaQuery.of(context).size.width - (Spacing.pagePadding * 2),
        decoration: BoxDecoration(  // ← Decoration between Material and ListTile
          color: context.colors.surfaceElevated,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          border: Border.all(color: context.colors.border),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: options.length,
          itemBuilder: (BuildContext context, int index) {
            final option = options.elementAt(index);
            return ListTile(  // ← ListTile ink rendering blocked by Container above
              dense: true,
              title: Text(...),
              onTap: () => onSelected(option),
            );
          },
        ),
      ),
    ),
  );
}
```

**Location 2:** `lib/features/events/widgets/gig_form_fields.dart:753-807` (`_buildGigCityAutocomplete`)

Identical structure — same `Material > Container(decoration: BoxDecoration) > ListView > ListTile` nesting.

**Why it fails:**

- `ListTile` requires a `Material` ancestor to paint its ink splash effects
- The `Container`'s own `BoxDecoration` creates a new painting layer that obscures the `Material` below it
- Flutter framework detects this and emits the assertion warning: "ListTile background color or ink splashes may be invisible"
- The warning fires every time the dropdown opens, spamming console output during manual testing

---

## Reference Docs Consulted

None directly applicable. This is a localized UI bug in the gig form autocomplete fields. No domain-specific reference docs exist for autocomplete widget patterns.

---

## Existing System Analysis

### Current Behavior (Bug 1)

**User flow:**

1. User opens Add/Edit Gig drawer
2. User taps into the City field
3. User types 2+ characters
4. `_fetchGigCitySuggestions` is called via debounced callback
5. Supabase query executes: `.from('gigs').select('city, date')`
6. PostgreSQL rejects the query with error `42703` (undefined_column)
7. Exception is caught, logged as `[GigCityAutocomplete] Error: PostgrestException(message: column gigs.city does not exist, code: 42703, ...)`
8. Suggestions list remains empty
9. Autocomplete dropdown never appears (no suggestions to show)

**What should happen:**

- Query should succeed against `gigs.location` column
- Past cities from the band's gigs should be returned, deduped case-insensitively
- Dropdown should show up to 15 unique city suggestions

**Data source:**

- `gigs.location` stores the city name (e.g., "Chicago", "Minneapolis")
- `gigs.venue_id` is optional — gigs can have a freeform `location` without linking to a `venues` record
- Query should scope to `band_id`, filter non-null/non-empty values, prefix-match case-insensitively

---

### Current Behavior (Bug 2)

**User flow:**

1. User types into Gig Name or City field
2. Autocomplete suggestions are available (Name suggestions work; City suggestions don't due to Bug 1, but the UI structure issue exists regardless)
3. `optionsViewBuilder` returns the dropdown overlay
4. Flutter framework detects the `Container` with `BoxDecoration` between `Material` and `ListTile`
5. Framework emits assertion: `"ListTile background color or ink splashes may be invisible. To make sure that ListTile's ink splashes are visible, make sure that ListTile is between a Material widget and the nearest ancestor that has a BoxDecoration."`
6. Warning repeats every time dropdown opens
7. Ink splash effects may render incorrectly (obscured by Container's paint layer)

**What should happen:**

- `Material` widget provides ink layer directly to `ListView`
- No intermediate `Container` with decoration blocks ink rendering
- No framework warnings
- Ink splashes render correctly on tap

---

## Proposed Solution

### Bug 1: Fix Column Name in Query

**Change:** In `lib/features/events/widgets/event_editor_drawer.dart`, method `_fetchGigCitySuggestions` (lines 878-926):

1. Change `.select('city, date')` to `.select('location, date')`
2. Change all references to `'city'` in filter clauses to `'location'`:
   - `.not('city', 'is', null)` → `.not('location', 'is', null)`
   - `.neq('city', '')` → `.neq('location', '')`
   - `.ilike('city', '$query%')` → `.ilike('location', '$query%')`
3. Rename the local variable `city` in the dedupe loop to `location`:
   - `final city = row['city'] as String?;` → `final location = row['location'] as String?;`
   - `if (city != null && city.isNotEmpty) {` → `if (location != null && location.isNotEmpty) {`
   - `final lower = city.toLowerCase();` → `final lower = location.toLowerCase();`
   - `suggestions.add(city);` → `suggestions.add(location);`

**Why this works:**

- `location` is the actual column name on the `gigs` table
- Query will succeed and return real past-gig cities
- Deduplication logic remains unchanged (case-insensitive comparison)
- No impact on UI rendering — the suggestions are just strings displayed in the dropdown

**No database changes required** — the `location` column already exists.

---

### Bug 2: Remove Container, Move Decoration to Material

**Change:** In `lib/features/events/widgets/gig_form_fields.dart`:

**Location 1:** `_buildGigNameAutocomplete` (~line 618)
**Location 2:** `_buildGigCityAutocomplete` (~line 695)

For both methods, modify the `optionsViewBuilder` return statement:

**Before:**

```dart
return Align(
  alignment: Alignment.topLeft,
  child: Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    child: Container(
      constraints: const BoxConstraints(maxHeight: 200),
      width: MediaQuery.of(context).size.width - (Spacing.pagePadding * 2),
      decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: context.colors.border),
      ),
      child: ListView.builder(...),
    ),
  ),
);
```

**After:**

```dart
return Align(
  alignment: Alignment.topLeft,
  child: Material(
    elevation: 4,
    color: context.colors.surfaceElevated,  // ← Moved from Container
    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    child: Container(
      constraints: const BoxConstraints(maxHeight: 200),
      width: MediaQuery.of(context).size.width - (Spacing.pagePadding * 2),
      decoration: BoxDecoration(
        // color removed (now on Material)
        borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        border: Border.all(color: context.colors.border),
      ),
      child: ListView.builder(...),
    ),
  ),
);
```

**Why this works:**

- `Material` widget now owns the background `color` property
- `Container` keeps the `border` and `borderRadius` in its `BoxDecoration`
- Border is cosmetic only — does not block ink
- `ListTile` ink splashes now have a direct `Material` ancestor with no intermediate opaque paint layer
- Framework assertion no longer fires

**Alternative considered and rejected:** Remove `Container` entirely and apply all properties to `Material`. Rejected because `Container` provides the `constraints` and `width` properties cleanly, and keeping it with just a border decoration is simpler than rearchitecting the layout.

---

## Database Impact

**Not applicable.** Both bugs are client-side UI/query issues. No migrations, RLS changes, or RPC updates required.

---

## Flutter Architecture Changes

### State Management

- No changes to Riverpod providers or Notifiers
- No changes to controller logic

### Widgets

- Modify `event_editor_drawer.dart` (1 method: `_fetchGigCitySuggestions`)
- Modify `gig_form_fields.dart` (2 methods: `_buildGigNameAutocomplete`, `_buildGigCityAutocomplete`)

### Repositories

- No changes

### Models

- No changes

---

## Files to Create

**None.**

---

## Files to Modify

| File                                                   | What Changes                                                                                                                                                                                                |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | Fix `_fetchGigCitySuggestions` method (lines 878-926): change all references from `'city'` to `'location'` in the Supabase query and dedupe loop.                                                           |
| `lib/features/events/widgets/gig_form_fields.dart`     | Fix `_buildGigNameAutocomplete` (~line 618) and `_buildGigCityAutocomplete` (~line 695): move `color` property from `Container.decoration` to `Material`, leave `border` and `borderRadius` on `Container`. |

---

## Files Off-Limits

| File                                                        | Reason                                                     |
| ----------------------------------------------------------- | ---------------------------------------------------------- |
| `lib/main.dart`                                             | Init order must not change (GUARDRAILS.md §1)              |
| `lib/app/theme/design_tokens.dart`                          | No design token changes — bug is structural, not stylistic |
| `lib/features/calendar/block_out_repository.dart`           | Explicitly out of scope per feature input                  |
| `lib/features/calendar/auto_conflict_blocking_service.dart` | Explicitly out of scope per feature input                  |
| Any file in `supabase/migrations/`                          | No database changes required                               |
| Any file in `lib/features/events/models/`                   | Models unchanged — only UI/query logic affected            |

---

## System Impact Map

| System                                 | Impact                                                                                |
| -------------------------------------- | ------------------------------------------------------------------------------------- |
| Gigs                                   | **affected** — city autocomplete will now return suggestions; ink warnings eliminated |
| Rehearsals                             | unaffected — rehearsal location autocomplete uses different logic (already works)     |
| Setlists / Catalog                     | unaffected                                                                            |
| Members / RBAC                         | unaffected                                                                            |
| Auth / Session                         | unaffected                                                                            |
| Routing                                | unaffected                                                                            |
| Notifications                          | unaffected                                                                            |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms share this code; bugs affect all equally                 |

---

## Regression Risk

**LOW**

**Rationale:**

- Only 2 files modified, 3 methods touched
- Changes are localized to autocomplete UI widgets — no cross-feature mutations
- Bug 1 fix changes only the query logic within a single debounced callback — no state dependencies
- Bug 2 fix changes only the widget tree structure of dropdown overlays — no business logic
- No database queries altered except for correcting the column name (query shape unchanged)
- No shared state, providers, or controllers affected
- No initialization order impact
- Both bugs are isolated to the gig form's autocomplete fields — rehearsal location autocomplete uses different code and is unaffected

**Risk factors mitigated:**

- No RLS policy changes → no risk of breaking permissions
- No controller/repository changes → no risk of breaking other event operations (create/update/delete)
- No migration required → no risk of database schema drift
- No new dependencies → no risk of package conflicts

---

## Engineer Task Breakdown

### Task 1: Fix City Autocomplete Query (Bug 1)

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Method:** `_fetchGigCitySuggestions` (lines 878-926)

**Steps:**

1. Locate the Supabase query block starting at line ~896
2. Change `.select('city, date')` to `.select('location, date')`
3. Change `.not('city', 'is', null)` to `.not('location', 'is', null)`
4. Change `.neq('city', '')` to `.neq('location', '')`
5. Change `.ilike('city', '$query%')` to `.ilike('location', '$query%')`
6. In the dedupe loop (lines ~910-918):
   - Change `final city = row['city'] as String?;` to `final location = row['location'] as String?;`
   - Change all references to `city` variable to `location`
7. Save file

**Verification:**

- Open Add/Edit Gig drawer, type into City field
- Verify no `PostgrestException` in console
- Verify past gig cities appear as suggestions (if any exist for the band)

---

### Task 2: Fix Gig Name Autocomplete Ink Warning (Bug 2, Part 1)

**File:** `lib/features/events/widgets/gig_form_fields.dart`

**Method:** `_buildGigNameAutocomplete` (~line 535-678)

**Steps:**

1. Locate the `optionsViewBuilder` return statement (~line 618)
2. In the `Material` widget (line ~624):
   - Add property: `color: context.colors.surfaceElevated,`
   - Result: `Material(elevation: 4, color: context.colors.surfaceElevated, borderRadius: ...)`
3. In the `Container.decoration` BoxDecoration (line ~630):
   - Remove the `color: context.colors.surfaceElevated,` line
   - Keep `borderRadius` and `border` properties
4. Save file

**Verification:**

- Open Add/Edit Gig drawer, type into Gig Name field
- Verify no ink-visibility warning in console when dropdown appears
- Tap a suggestion, verify ink splash renders correctly

---

### Task 3: Fix Gig City Autocomplete Ink Warning (Bug 2, Part 2)

**File:** `lib/features/events/widgets/gig_form_fields.dart`

**Method:** `_buildGigCityAutocomplete` (~line 681-830)

**Steps:**

1. Locate the `optionsViewBuilder` return statement (~line 753)
2. In the `Material` widget (line ~759):
   - Add property: `color: context.colors.surfaceElevated,`
   - Result: `Material(elevation: 4, color: context.colors.surfaceElevated, borderRadius: ...)`
3. In the `Container.decoration` BoxDecoration (line ~765):
   - Remove the `color: context.colors.surfaceElevated,` line
   - Keep `borderRadius` and `border` properties
4. Save file

**Verification:**

- Open Add/Edit Gig drawer, type into City field (should now show suggestions after Task 1)
- Verify no ink-visibility warning in console when dropdown appears
- Tap a suggestion, verify ink splash renders correctly

---

### Task 4: Run Analyzer

```bash
flutter analyze
```

**Expected result:** 0 errors, 0 warnings, 0 hints.

If any errors appear, stop and report.

---

### Task 5: Format Modified Files

```bash
dart format lib/features/events/widgets/event_editor_drawer.dart
dart format lib/features/events/widgets/gig_form_fields.dart
```

**Expected result:** Files formatted according to Dart style guide.

---

### Task 6: Generate Git Diff

```bash
git diff > ~/Desktop/gig-autocomplete-fix.diff
```

Include the full diff in `ENGINEER_REPORT.md`.

---

### Task 7: Manual Device Testing (Optional but Recommended)

**Platform:** iOS (physical device preferred) or macOS

**Steps:**

1. Run app: `./run.sh <device-id>` or `flutter run -d macos`
2. Create or edit a gig
3. Type into City field:
   - Verify suggestions appear (if past gigs exist for the band)
   - Verify no console errors
4. Tap into Gig Name field, type to trigger suggestions:
   - Verify no console warnings when dropdown appears
   - Tap a suggestion, verify ink splash is visible
5. Tap into City field again:
   - Verify no console warnings when dropdown appears
   - Tap a suggestion, verify ink splash is visible

**If device deployment is not feasible** (expected based on prior context), document in `ENGINEER_REPORT.md` and defer to QA for full device verification.

---

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable.** No database changes or edge function updates required.

---

### Tier 2 — Post-deployment

**Not applicable.** This is a client-side bug fix with no backend changes.

---

### Manual Verification (Required)

**Test 1: City Autocomplete Now Returns Suggestions**

1. Ensure the test band has at least one existing gig with a non-empty `location` value (e.g., create a test gig with city "Chicago")
2. Open Add/Edit Gig drawer
3. Tap into City field, type "Chi"
4. **Expected:** Dropdown appears with "Chicago" as a suggestion
5. **Expected:** No `PostgrestException` in console
6. Type "xyz" (city that doesn't exist)
7. **Expected:** No dropdown (no matches), no console errors

**Pass criteria:** Suggestions populate correctly, no exceptions thrown.

---

**Test 2: Gig Name Autocomplete — No Ink Warning**

1. Open Add/Edit Gig drawer
2. Tap into Gig Name field, type 2+ characters to trigger suggestions (e.g., "Blue Note")
3. Wait for dropdown to appear
4. **Expected:** No Flutter framework warning in console about ListTile ink visibility
5. Tap a suggestion
6. **Expected:** Ink splash effect renders correctly on tap (visible ripple)

**Pass criteria:** No console warnings, ink splash visible on tap.

---

**Test 3: City Autocomplete — No Ink Warning**

1. Open Add/Edit Gig drawer
2. Tap into City field, type 2+ characters to trigger suggestions (e.g., "Chi")
3. Wait for dropdown to appear
4. **Expected:** No Flutter framework warning in console about ListTile ink visibility
5. Tap a suggestion
6. **Expected:** Ink splash effect renders correctly on tap (visible ripple)

**Pass criteria:** No console warnings, ink splash visible on tap.

---

**Test 4: Autocomplete Styling Unchanged**

1. Open Add/Edit Gig drawer
2. Trigger both Name and City autocomplete dropdowns
3. **Expected:** Dropdown appearance matches pre-fix styling:
   - Elevated shadow (elevation 4)
   - Rounded corners (8px radius)
   - Border visible
   - Background color matches `surfaceElevated` theme color
   - Text color correct
   - Tap areas still 48px minimum (dense ListTile)

**Pass criteria:** Visual appearance unchanged from before fix.

---

## QA Regression Areas

### Primary (Must Test)

1. **City autocomplete functionality**
   - Suggestions populate for existing gig cities
   - Case-insensitive matching works
   - Deduplication works (no duplicate suggestions)
   - Empty results for non-matching queries (no crash)

2. **Ink rendering in both autocomplete dropdowns**
   - No console warnings when dropdowns open
   - Ink splash visible on tap for both Name and City dropdowns
   - Styling unchanged (elevation, border, colors)

3. **Gig creation/editing workflow**
   - Can still create gigs with typed-in city values (not selected from dropdown)
   - City field saves correctly to database (`gigs.location`)
   - Autocomplete doesn't interfere with manual typing

### Secondary (Regression Check)

4. **Rehearsal location autocomplete**
   - Verify rehearsal location autocomplete still works (uses different code path)
   - No console errors or warnings when triggering rehearsal location suggestions

5. **Event form validation**
   - Required field validation still works for Name and City
   - Error messages display correctly

6. **Keyboard/focus behavior**
   - Tapping dropdown suggestion correctly closes keyboard and fills field
   - Focus transitions correctly between fields

---

## Rollout / Migration Strategy

**Not applicable.** This is a bug fix with no deployment dependencies. Changes are client-side only and take effect immediately on next app build.

---

## Out of Scope

1. **Venue autocomplete integration:** This fix corrects the city query to use `gigs.location`. Integrating venue autocomplete (querying `venues` table and auto-filling city/address/state from a selected venue) is a separate feature and is explicitly out of scope.

2. **Query optimization:** The current query uses `.limit(30)` and dedupes to 15 client-side. Optimizing this to dedupe server-side (e.g., via `DISTINCT` or an RPC function) is out of scope.

3. **Autocomplete debounce tuning:** The 300ms debounce delay is not being changed.

4. **Rehearsal location autocomplete:** Already works (queries `rehearsals.location` correctly) and is unaffected by this fix.

5. **Auto-conflict blocking service:** Explicitly excluded per feature input.

6. **Address/State autocomplete:** Only City autocomplete is being fixed. Address and State fields remain plain text inputs.

---

**End of Architect Plan**
