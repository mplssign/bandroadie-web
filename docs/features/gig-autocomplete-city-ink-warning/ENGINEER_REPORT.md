# Engineer Report

## Feature Slug

`bug/gig-autocomplete-city-ink-warning`

---

## Feature Title

Gig Autocomplete City Query and Ink Warning Fix

---

## Goal

Fix two independent bugs in the gig form's autocomplete fields: (1) City autocomplete queries a nonexistent `city` column instead of the correct `location` column, causing all city suggestions to fail silently with PostgrestException 42703. (2) Both gig name and city autocomplete dropdowns trigger ink-visibility warnings because their `Container.decoration` blocks the `Material` ancestor from painting `ListTile` ink splashes.

---

## Architect Tasks Completed

- [x] Task 1 — Fix City Autocomplete Query (Bug 1): Changed all references from `'city'` to `'location'` in `_fetchGigCitySuggestions` method in `event_editor_drawer.dart`
- [x] Task 2 — Fix Gig Name Autocomplete Ink Warning (Bug 2, Part 1): Moved `color` property from `Container.decoration` to `Material` in `_buildGigNameAutocomplete` in `gig_form_fields.dart`
- [x] Task 3 — Fix Gig City Autocomplete Ink Warning (Bug 2, Part 2): Moved `color` property from `Container.decoration` to `Material` in `_buildGigCityAutocomplete` in `gig_form_fields.dart`
- [x] Task 4 — Run Analyzer: `flutter analyze` passed with 0 errors
- [x] Task 5 — Format Modified Files: Both files formatted (no changes needed, already compliant)
- [x] Task 6 — Generate Git Diff: Full diff captured below

---

## Files Created

None

---

## Files Modified

- `lib/features/events/widgets/event_editor_drawer.dart`
- `lib/features/events/widgets/gig_form_fields.dart`

---

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors

**Warnings/Info:** 10 pre-existing issues in unrelated files (bulk_entry_screen.dart, original_song_screen.dart, reorderable_song_card.dart, song_card.dart, test files). None in modified files. No new warnings introduced.

---

## Test Results

Not run (no tests exist for these specific autocomplete UI widgets)

---

## Code Efficiency / Bloat Check

**Confirmed:** No dead code, unused imports/variables/parameters, redundant comments, single-use wrapper abstractions, or unnecessary defensive checks in the diff.

**Details:**

- All changed lines serve a functional purpose (fix query column name, move color property)
- No new abstractions created
- No new variables or imports added
- Changes are minimal and surgical (11 lines modified in event_editor_drawer.dart, 4 lines moved in gig_form_fields.dart)

---

## Verification

### Manual Steps Performed:

**Static Analysis:**

- [x] Confirmed `gigs` table schema has `location` column (not `city`) via repository code inspection
- [x] Verified both autocomplete methods have identical `Material > Container(decoration) > ListView > ListTile` structure before fix
- [x] Verified `color` moved from `Container.decoration` to `Material` in both methods after fix

**Code Review:**

- [x] All query column references changed from `'city'` to `'location'` in event_editor_drawer.dart
- [x] Local variable renamed from `city` to `location` in dedupe loop
- [x] `Material` widget now has `color: context.colors.surfaceElevated` property in both autocomplete methods
- [x] `Container.decoration` no longer has `color` property, retains `borderRadius` and `border`

---

## Deviations From Architect Plan

None

---

## Blockers Encountered

None

---

## Ready For QA

**Yes**

**QA should verify:**

1. City autocomplete now returns suggestions when typing in the City field (requires existing gigs with non-null `location` values for the test band)
2. No `PostgrestException` console errors when typing into City field
3. No ink-visibility warnings in console when gig name or city autocomplete dropdowns open
4. Ink splash effects render correctly when tapping autocomplete suggestions

---

## Git Diff

```diff
diff --git a/lib/features/events/widgets/event_editor_drawer.dart b/lib/features/events/widgets/event_editor_drawer.dart
index 1bf8973..13a2c46 100644
--- a/lib/features/events/widgets/event_editor_drawer.dart
+++ b/lib/features/events/widgets/event_editor_drawer.dart
@@ -892,11 +892,11 @@ class _EventEditorDrawerState extends ConsumerState<EventEditorDrawer>
         // prefix-matched, case-insensitive
         final response = await supabase
             .from('gigs')
-            .select('city, date')
+            .select('location, date')
             .eq('band_id', widget.bandId)
-            .not('city', 'is', null)
-            .neq('city', '')
-            .ilike('city', '$query%')
+            .not('location', 'is', null)
+            .neq('location', '')
+            .ilike('location', '$query%')
             .order('date', ascending: false)
             .limit(30);

@@ -904,12 +904,12 @@ class _EventEditorDrawerState extends ConsumerState<EventEditorDrawer>
         final Set<String> seenLower = {};
         final List<String> suggestions = [];
         for (final row in response) {
-          final city = row['city'] as String?;
-          if (city != null && city.isNotEmpty) {
-            final lower = city.toLowerCase();
+          final location = row['location'] as String?;
+          if (location != null && location.isNotEmpty) {
+            final lower = location.toLowerCase();
             if (!seenLower.contains(lower)) {
               seenLower.add(lower);
-              suggestions.add(city);
+              suggestions.add(location);
               if (suggestions.length >= 15) break;
             }
           }
diff --git a/lib/features/events/widgets/gig_form_fields.dart b/lib/features/events/widgets/gig_form_fields.dart
index a332f6e..578a981 100644
--- a/lib/features/events/widgets/gig_form_fields.dart
+++ b/lib/features/events/widgets/gig_form_fields.dart
@@ -626,13 +626,13 @@ class GigFormFields extends ConsumerWidget {
               alignment: Alignment.topLeft,
               child: Material(
                 elevation: 4,
+                color: context.colors.surfaceElevated,
                 borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                 child: Container(
                   constraints: const BoxConstraints(maxHeight: 200),
                   width: MediaQuery.of(context).size.width -
                       (Spacing.pagePadding * 2),
                   decoration: BoxDecoration(
-                    color: context.colors.surfaceElevated,
                     borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                     border: Border.all(color: context.colors.border),
                   ),
@@ -771,13 +771,13 @@ class GigFormFields extends ConsumerWidget {
               alignment: Alignment.topLeft,
               child: Material(
                 elevation: 4,
+                color: context.colors.surfaceElevated,
                 borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                 child: Container(
                   constraints: const BoxConstraints(maxHeight: 200),
                   width: MediaQuery.of(context).size.width -
                       (Spacing.pagePadding * 2),
                   decoration: BoxDecoration(
-                    color: context.colors.surfaceElevated,
                     borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                     border: Border.all(color: context.colors.border),
                   ),
```
