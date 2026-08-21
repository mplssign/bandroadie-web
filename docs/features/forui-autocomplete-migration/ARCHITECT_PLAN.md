# Architect Plan: Migrate Autocomplete Fields to Forui FAutocomplete

## Feature Slug

`feature/forui-autocomplete-migration`

---

## Problem Summary

Three autocomplete fields in the app currently use Flutter's raw `RawAutocomplete`/`Autocomplete` widgets with hand-rolled Material dropdown overlays (`Material > Container > ListView > ListTile`), instead of the app's native design system (Forui). This hybrid approach caused the ink-visibility warning bug fixed in `bug/gig-autocomplete-city-ink-warning` (2026-08-21) and requires manual controller bridging in the rehearsal location field (`fieldController.addListener(() { locationController.text = fieldController.text; })`), suggesting past sync issues with the `AppTextField`/`Autocomplete` combination.

Forui provides a native `FAutocomplete` widget (present in the project's installed `forui: ^0.25.0` package) that integrates its own text field and popover system, eliminating the Material/Forui hybrid and the need for external controller management.

**Affected call sites:**

1. Gig Name autocomplete — `lib/features/events/widgets/gig_form_fields.dart`, `_buildGigNameAutocomplete()` (~line 549)
2. Gig City autocomplete — `lib/features/events/widgets/gig_form_fields.dart`, `_buildGigCityAutocomplete()` (~line 695)
3. Rehearsal Location autocomplete — `lib/features/events/widgets/rehearsal_form_fields.dart`, `_buildLocationAutocomplete()` (~line 167)

Two of the three fields (Gig City, Rehearsal Location) wrap their text input in `AppTextField` (the app's Forui `FTextField` wrapper), while Gig Name uses a plain Flutter `TextField`. All three have surrounding autocomplete scaffolding (`RawAutocomplete`/`Autocomplete` wrappers) and hand-rolled Material dropdown overlays that remain outside the Forui design system.

---

## Root Cause

**Confidence:** HIGH (confirmed via code inspection and installed package verification)

**Diagnosis:**

The three autocomplete fields were implemented before `FAutocomplete` existed or was known about, using Flutter's standard `RawAutocomplete`/`Autocomplete` APIs. Two fields (Gig City, Rehearsal Location) use `AppTextField` to approximate Forui styling, while Gig Name uses a plain Flutter `TextField` with manual styling. This creates a hybrid widget structure:

- **Text input layer:** Mix of plain Flutter `TextField` (Gig Name) and Forui `AppTextField` (Gig City, Rehearsal Location)
- **Autocomplete scaffold layer:** Flutter Material (`RawAutocomplete`/`Autocomplete`)
- **Dropdown overlay layer:** Hand-rolled Material widgets (`Material > Container > ListView > ListTile`)

**Problems caused by this hybrid:**

1. **Material framework warnings:** The `Container.decoration` in the dropdown blocked `Material` from painting `ListTile` ink splashes, causing Flutter's ink-visibility assertion warning (fixed 2026-08-21 by moving `color` to `Material`).
2. **Controller sync workaround:** Rehearsal location field requires `fieldController.addListener(() { locationController.text = fieldController.text; })` to bridge the `Autocomplete`-provided controller to the parent-owned `locationController`, indicating the `AppTextField`/`Autocomplete` combination doesn't naturally sync state.
3. **Design system drift:** Dropdown appearance is manually styled to approximate Forui theming, rather than using Forui's native popover components.

**Why FAutocomplete solves this:**

- Integrated text field + popover system — no separate `fieldViewBuilder` needed
- Forui-native theming throughout — no manual Material styling
- Self-contained controller management — no external `TextEditingController` bridging required
- Supports both sync (`List<String>`) and async (`FutureOr<Iterable<String>> Function(String query) filter`) suggestion sources, covering all three use cases

### Deferred City-Field Direct-Typing Gap Investigation

**Confidence:** HIGH (confirmed via prior bug fix documentation)

**Investigation finding:** The "City field suggestions never render for direct typing" issue mentioned in the feature input was NOT a structural widget problem caused by the `RawAutocomplete`/`AppTextField` hybrid. It was the nonexistent-column query bug root-caused and fixed in `bug/gig-autocomplete-city-ink-warning` (merged 2026-08-21).

**Evidence:**

- Prior bug fix (`docs/features/gig-autocomplete-city-ink-warning/ARCHITECT_PLAN.md`) documented that `_fetchGigCitySuggestions()` queried `.from('gigs').select('city, date')` but the `gigs` table has no `city` column
- Every keystroke threw `PostgrestException` code `42703` "column gigs.city does not exist"
- Exception was silently caught, so suggestions list remained empty
- Fix changed query to target correct `gigs.location` column

**Structural comparison:** Gig Name and Gig City fields have nearly identical widget structures (both use `RawAutocomplete` with Material dropdown). The only difference was Gig Name queried an in-memory venue list (which worked) while Gig City queried a nonexistent database column (which failed silently). This confirms the gap was a data-layer bug, not a widget-layer incompatibility.

**Implication for this migration:** Migrating to `FAutocomplete` will NOT fix the City-field gap (it's already fixed). However, the migration eliminates the hybrid architecture that obscured the original bug's symptoms, making future issues more visible.

### Controller Model Choice

**FAutocomplete controller support confirmed:** Per `FAutocompleteControl` API (forui 0.25.0), the `.managed()` control model accepts an optional `controller` parameter: `FAutocompleteControl.managed({FAutocompleteController? controller, ...})`. This allows supplying an external `FAutocompleteController` instance if needed.

**Recommendation: Use `.managed()` without external controller.** Rationale:

- **Current pattern:** Parent widget owns `TextEditingController` instances (`_nameController`, `_locationController`) solely to read `.text` for form submission. No complex controller logic beyond text capture.
- **FAutocomplete simplification:** Can manage its own state internally and expose text via `onChange` callbacks, eliminating controller declarations, disposal, and listeners in parent widget.
- **Eliminates bridge workaround:** Rehearsal location's `fieldController.addListener(() { locationController.text = fieldController.text; })` becomes unnecessary — FAutocomplete's `onChange` directly captures text.
- **Reduces refactor scope:** Not supplying external controllers means fewer touchpoints in `event_editor_drawer.dart` (no need to create/manage `FAutocompleteController` instances, just capture text in local state variables).

**Alternative (not recommended):** Supply external `FAutocompleteController` instances via `.managed(controller: ...)` to preserve controller-based state access pattern. This keeps the parent widget's current architecture but defeats the simplification benefit of Forui's integrated state management.

---

## Reference Docs Consulted

- **Installed package verification:** Read `FAutocomplete` source directly from `/Users/tonyholmes/.pub-cache/hosted/pub.dev/forui-0.25.0/lib/src/widgets/autocomplete/autocomplete.dart`
- **API confirmed:**
  - `.text()` factory for simple string lists with local filtering
  - `.textBuilder()` factory for async string filtering (debounced Supabase queries)
  - `.builder()` factory for custom types (not needed here — all three use `String`)
  - Control model: `FAutocompleteControl.managed()` (default) handles its own controller lifecycle
  - Filter signature: `FutureOr<Iterable<String>> Function(String query)` — supports both sync and async
  - Content builder: `FAutocompleteContentBuilder<String>` builds suggestion list items

**No relevant design-system reference docs found** in `docs/reference/ui/` (contains only `LANDING_PAGE_PREVIEW_GUIDE.md`) or `docs/reference/architecture/` (general architecture, no Forui form widget patterns).

---

## Existing System Analysis

### Current Implementation (Post Ink-Warning Fix)

**Gig Name Autocomplete:**

- **Widget:** `RawAutocomplete<String>`
- **Text input:** Plain Flutter `TextField` in `fieldViewBuilder` (line 573) — NOT `AppTextField`, manually styled with `InputDecoration`
- **Suggestions source:** `gigNameSuggestions` — local in-memory list filtered from `_allVenues` (venue name matching, case-insensitive prefix match)
- **Dropdown:** `Material(elevation: 4, color: surfaceElevated) > Container(decoration: border + borderRadius) > ListView > ListTile`
- **Controller:** `nameController` owned by parent widget (`event_editor_drawer.dart`), passed as `textEditingController` to `RawAutocomplete`
- **FocusNode:** `gigNameFocusNode` owned by parent
- **Selection callback:** `onSelected` sets `nameController.text` and triggers `onGigNameChanged()` which fetches venue details

**Gig City Autocomplete:**

- **Widget:** `RawAutocomplete<String>`
- **Text input:** `AppTextField` in `fieldViewBuilder`
- **Suggestions source:** `gigCitySuggestions` — populated by debounced Supabase query in parent widget (`_fetchGigCitySuggestions()` in `event_editor_drawer.dart`), 300ms debounce, min 2 chars, queries `gigs.location` with prefix match
- **Dropdown:** Identical structure to Gig Name — `Material > Container > ListView > ListTile`
- **Controller:** `locationController` owned by parent
- **FocusNode:** `gigCityFocusNode` owned by parent
- **Selection callback:** `onSelected` sets `locationController.text`

**Rehearsal Location Autocomplete:**

- **Widget:** `Autocomplete<String>` (not `RawAutocomplete`)
- **Text input:** `AppTextField` in `fieldViewBuilder`
- **Controller bridge:** `fieldController.addListener(() { locationController.text = fieldController.text; })` — syncs `Autocomplete`-provided controller to parent-owned `locationController`
- **Suggestions source:** `locationSuggestions` — local in-memory list populated by Supabase query in parent widget, filtered client-side with `.contains()` match
- **Dropdown:** `Material(elevation: 4) > Container(decoration: color + border + borderRadius) > ListView > ListTile`
  - **Note:** This field still has `color` on `Container.decoration`, not `Material` — it was NOT touched by the ink-warning fix (only gig fields were fixed)
- **Controller:** `locationController` owned by parent
- **FocusNode:** Not explicitly passed (uses `Autocomplete`'s default)
- **Selection callback:** `onSelected` sets `locationController.text`

---

## Proposed Solution

Replace all three autocomplete fields with Forui's native `FAutocomplete.textBuilder` (for async city field) or `FAutocomplete.text` (for sync name/location fields). Remove external controller management and manual controller bridging. Preserve all existing suggestion-fetching logic (venue name filter, debounced city query, rehearsal location query) by moving it into `FAutocomplete`'s `filter` parameter.

### Changes by File

**1. `lib/features/events/widgets/gig_form_fields.dart`**

**Gig Name Autocomplete (`_buildGigNameAutocomplete`, ~line 549):**

- Remove `RawAutocomplete<String>` wrapper
- Replace with `FAutocomplete.text()` factory
- Remove `fieldViewBuilder` (FAutocomplete includes its own field)
- Remove `optionsViewBuilder` (FAutocomplete uses native Forui popover)
- Move venue name filtering logic from `optionsBuilder` to `filter` parameter:
  ```dart
  filter: (query) {
    if (query.length < 2) return const Iterable<String>.empty();
    return gigNameSuggestions.where((name) =>
      name.toLowerCase().startsWith(query.toLowerCase())
    );
  }
  ```
- Add `onItemPress: (selection) => ...` callback (replaces `onSelected`)
- Pass `enabled: !isSaving`, `textCapitalization: .words`, `hint: 'e.g., Venue Name'`
- Remove `textEditingController` and `focusNode` params (FAutocomplete manages its own)
- Add `forceErrorText` for validation errors

**Gig City Autocomplete (`_buildGigCityAutocomplete`, ~line 695):**

- Remove `RawAutocomplete<String>` wrapper
- Replace with `FAutocomplete.textBuilder()` factory (async variant)
- Remove `fieldViewBuilder` and `optionsViewBuilder`
- Move debounced Supabase query logic into `filter` parameter:

  ```dart
  filter: (query) async {
    onGigCityChanged(query); // Triggers parent's _fetchGigCitySuggestions
    if (query.length < 2) return const Iterable<String>.empty();
    return gigCitySuggestions; // Parent updates this via setState
  }
  ```

  - **Note:** This maintains the existing debounce pattern (parent widget's `_gigCityDebounceTimer` handles debouncing)

- Add `onItemPress: (selection) => ...` callback
- Pass `enabled: !isSaving`, `textCapitalization: .sentences`, `hint: 'e.g., Chicago'`
- Remove `textEditingController` and `focusNode` params
- Add `forceErrorText` for validation errors

**2. `lib/features/events/widgets/rehearsal_form_fields.dart`**

**Rehearsal Location Autocomplete (`_buildLocationAutocomplete`, ~line 167):**

- Remove `Autocomplete<String>` wrapper
- Remove controller bridge workaround: `fieldController.addListener(() { locationController.text = fieldController.text; })`
- Replace with `FAutocomplete.text()` factory
- Remove `fieldViewBuilder` and `optionsViewBuilder`
- Move local filtering logic into `filter` parameter:
  ```dart
  filter: (query) {
    if (query.isEmpty) return const Iterable<String>.empty();
    final lowerQuery = query.toLowerCase();
    return locationSuggestions.where((location) =>
      location.toLowerCase().contains(lowerQuery)
    ).take(8);
  }
  ```
- Add `onItemPress: (selection) => ...` callback
- Pass `enabled: !isSaving`, `textCapitalization: .words`, `hint: 'e.g., Studio, Venue Address'`, `inputFormatters: [TitleCaseTextFormatter()]`
- Remove `textEditingController` and `focusNode` params (no longer needed)
- Add `forceErrorText` for validation errors

**3. `lib/features/events/widgets/event_editor_drawer.dart`**

- **Remove:** `_nameController` (line 130), `_locationController` (line 129) — no longer needed, FAutocomplete manages its own text state
- **Remove:** `_gigCityFocusNode` (line 204), `_gigNameFocusNode`, `_gigLocationFocusNode` — no longer needed
- **Remove:** Controller/FocusNode disposal in `dispose()` method (lines 453, 460-462)
- **Remove:** Controller listeners: `_nameController.addListener(...)` (line 436), `_locationController.addListener(...)` (line 425)
- **Update:** `_fetchGigNameSuggestions()` method to accept query string param and return filtered list (currently returns void, mutates `_gigNameSuggestions` via `setState`)
  - Change signature: `List<String> _fetchGigNameSuggestions(String query)`
  - Remove `setState` call (FAutocomplete handles re-rendering)
  - Return filtered venue names directly
- **Update:** `_fetchGigCitySuggestions()` method similarly — change to return `Future<List<String>>` instead of `void`, remove `setState`
- **Add:** Helper methods to read text values from FAutocomplete:
  - `FAutocompleteControl` instances need to be stored in state to read text values when building `EventFormData`
  - OR: Pass `onChange` callbacks to FAutocomplete to capture text in local state variables

### Data Flow Changes

**Before:**

```
User types → RawAutocomplete.optionsBuilder → parent callback → parent setState →
suggestions list updated → RawAutocomplete re-renders dropdown
```

**After:**

```
User types → FAutocomplete.filter → suggestions returned → FAutocomplete re-renders popover
```

**State access for form submission:**

- **Before:** Read `nameController.text`, `locationController.text` to build `EventFormData`
- **After:** Store `FAutocompleteControl` instances in state, read `.controller.text` OR capture text via `onChange` callbacks

---

## Database Impact

**Not applicable.** This is a pure UI widget migration. No database queries, RLS policies, RPC functions, or migrations are affected.

---

## Flutter Architecture Changes

### State Management

- **Controllers removed:** `_nameController`, `_locationController` no longer needed in `event_editor_drawer.dart`
- **FocusNodes removed:** `_gigNameFocusNode`, `_gigCityFocusNode`, `_gigLocationFocusNode` no longer needed
- **New state (if using managed control):** Store `FAutocompleteControl` instances OR capture text values via `onChange` callbacks to local `String?` state variables

### Widgets

- **Modified:** `gig_form_fields.dart` — replace `RawAutocomplete` with `FAutocomplete` in 2 methods
- **Modified:** `rehearsal_form_fields.dart` — replace `Autocomplete` with `FAutocomplete` in 1 method
- **Modified:** `event_editor_drawer.dart` — remove controllers/focus nodes, update suggestion-fetching methods

### Repositories

- **Not affected**

### Models

- **Not affected**

---

## Files to Create

**None.**

---

## Files to Modify

| File                                                     | What Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/gig_form_fields.dart`       | Replace `RawAutocomplete` with `FAutocomplete.text()` in `_buildGigNameAutocomplete()` (~line 549). Replace `RawAutocomplete` with `FAutocomplete.textBuilder()` in `_buildGigCityAutocomplete()` (~line 695). Remove `fieldViewBuilder`, `optionsViewBuilder`, `textEditingController`, `focusNode` params. Move filtering logic into `filter` parameter. Add `onItemPress` callbacks. Update constructor params to remove `nameController`, `locationController`, `gigNameKey`, `gigLocationKey`, `gigNameFocusNode`, `gigCityFocusNode`.                                                                                                                                                                       |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | Replace `Autocomplete` with `FAutocomplete.text()` in `_buildLocationAutocomplete()` (~line 167). Remove controller bridge workaround (`fieldController.addListener(...)`). Remove `fieldViewBuilder`, `optionsViewBuilder`. Move filtering logic into `filter` parameter. Add `onItemPress` callback. Update constructor to remove `locationController`, `locationKey`.                                                                                                                                                                                                                                                                                                                                          |
| `lib/features/events/widgets/event_editor_drawer.dart`   | Remove `_nameController`, `_locationController` declarations and disposal. Remove `_gigNameFocusNode`, `_gigCityFocusNode`, `_gigLocationFocusNode` declarations and disposal. Remove controller listeners (`_nameController.addListener`, `_locationController.addListener`). Update `_fetchGigNameSuggestions()` to return `List<String>` instead of `void`, remove `setState`. Update `_fetchGigCitySuggestions()` to return `Future<List<String>>` instead of `void`, remove `setState`. Add state variables OR `FAutocompleteControl` instances to capture text values for form submission. Update all constructor calls to `GigFormFields` and `RehearsalFormFields` to remove controller/focusNode params. |

---

## Files Off-Limits

| File                                              | Reason                                                                       |
| ------------------------------------------------- | ---------------------------------------------------------------------------- |
| `lib/main.dart`                                   | Init order must not change (GUARDRAILS.md §1)                                |
| `lib/app/theme/design_tokens.dart`                | No design token changes — migration uses existing Forui theme                |
| `lib/features/events/events_repository.dart`      | Repository logic unchanged — form submission uses same `EventFormData` model |
| `lib/features/events/models/event_form_data.dart` | Model unchanged — migration only affects UI widgets                          |
| `lib/components/ui/app_text_field.dart`           | AppTextField itself is not modified — FAutocomplete includes its own field   |
| Any file in `supabase/migrations/`                | No database changes                                                          |
| Any file outside `lib/features/events/widgets/`   | Autocomplete fields are isolated to event forms only                         |

---

## System Impact Map

| System                                 | Impact                                                         |
| -------------------------------------- | -------------------------------------------------------------- |
| Gigs                                   | **affected** — gig name and city autocomplete widgets replaced |
| Rehearsals                             | **affected** — rehearsal location autocomplete widget replaced |
| Setlists / Catalog                     | unaffected                                                     |
| Members / RBAC                         | unaffected                                                     |
| Auth / Session                         | unaffected                                                     |
| Routing                                | unaffected                                                     |
| Notifications                          | unaffected                                                     |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms share this code                   |

---

## Regression Risk

**MEDIUM**

**Rationale:**

- **3 autocomplete widgets replaced** across 2 files — localized but non-trivial change surface
- **Controller lifecycle changes** — removing external controllers and moving to Forui-managed state is a significant architectural shift
- **Suggestion-fetching logic moved** — from `optionsBuilder` callbacks to `filter` parameters, changing where and when filtering happens
- **Form submission integration** — reading text values for `EventFormData` changes from `controller.text` to either `FAutocompleteControl` state or `onChange`-captured variables
- **No database or cross-feature mutations** — impact isolated to event form UI

**Risk factors:**

1. **Controller state access for form submission** — if text values aren't captured correctly, gig/rehearsal creation will fail with missing or incorrect field values
2. **Debounced city query integration** — if `FAutocomplete`'s filtering model doesn't preserve the existing 300ms debounce, city autocomplete may fire too many queries or feel sluggish
3. **Venue autofill logic** — gig name selection triggers `_fetchGigNameSuggestions()` which prefills address/city/state; if `onItemPress` callback doesn't correctly invoke this, venue autofill will break
4. **Validation error display** — if `forceErrorText` doesn't propagate correctly to FAutocomplete, inline validation will be invisible
5. **Focus/keyboard behavior** — FAutocomplete manages its own focus; if this conflicts with existing keyboard handling or field-to-field navigation, UX will degrade

**Risk mitigated:**

- No RLS policy changes → no permission breakage
- No repository/provider changes → no cross-feature data flow impact
- No new dependencies → forui ^0.25.0 already installed
- No initialization order changes

---

## Engineer Task Breakdown

### Task 1: Add Forui Import and Read Widget Key Locations

**Files:** `lib/features/events/widgets/gig_form_fields.dart`, `lib/features/events/widgets/rehearsal_form_fields.dart`

**Steps:**

1. Add `import 'package:forui/forui.dart';` to both files (if not already present via transitive import through `app_text_field.dart`)
2. Locate the three autocomplete methods:
   - `gig_form_fields.dart`: `_buildGigNameAutocomplete()` (~line 549), `_buildGigCityAutocomplete()` (~line 695)
   - `rehearsal_form_fields.dart`: `_buildLocationAutocomplete()` (~line 167)
3. Note the current widget keys: `gigNameKey`, `gigLocationKey`, `locationKey` — these will be removed since FAutocomplete manages its own state

**Verification:** File locations confirmed, imports added

---

### Task 2: Migrate Gig Name Autocomplete to FAutocomplete.text

**File:** `lib/features/events/widgets/gig_form_fields.dart`

**Method:** `_buildGigNameAutocomplete()` (~line 549)

**Steps:**

1. Replace entire `RawAutocomplete<String>(...)` widget with:
   ```dart
   FAutocomplete.text(
     items: gigNameSuggestions,
     filter: (query) {
       if (query.length < 2) return const Iterable<String>.empty();
       return gigNameSuggestions.where((name) =>
         name.toLowerCase().startsWith(query.toLowerCase())
       );
     },
     hint: 'e.g., Venue Name',
     enabled: !isSaving,
     textCapitalization: TextCapitalization.words,
     forceErrorText: hasError ? errorText : null,
     onItemPress: (selection) {
       onGigNameChanged(selection);
       onMarkDirty();
     },
   )
   ```
2. Remove `key: gigNameKey` param (no longer needed)
3. Remove `textEditingController: nameController`, `focusNode: gigNameFocusNode`, `onSelected`, `fieldViewBuilder`, `optionsViewBuilder` (all replaced by FAutocomplete)
4. Keep `FieldHint` widget below the autocomplete (unchanged)

**Verification:** Widget renders, typing shows suggestions after 2 chars, selecting a suggestion calls `onGigNameChanged()`

---

### Task 3: Migrate Gig City Autocomplete to FAutocomplete.textBuilder

**File:** `lib/features/events/widgets/gig_form_fields.dart`

**Method:** `_buildGigCityAutocomplete()` (~line 695)

**Steps:**

1. Replace entire `RawAutocomplete<String>(...)` widget with:

   ```dart
   FAutocomplete.textBuilder(
     filter: (query) async {
       onGigCityChanged(query);
       if (query.length < 2) return const Iterable<String>.empty();
       // Wait briefly for parent's debounced query to update gigCitySuggestions
       await Future.delayed(const Duration(milliseconds: 350));
       return gigCitySuggestions;
     },
     hint: 'e.g., Chicago',
     enabled: !isSaving,
     textCapitalization: TextCapitalization.sentences,
     forceErrorText: hasError ? errorText : null,
     onItemPress: (selection) {
       onMarkDirty();
     },
     contentBuilder: (context, query, values) => [
       for (final value in values) FAutocompleteItem.item(value: value),
     ],
   )
   ```

   - **Note:** The `filter` callback triggers the parent's `onGigCityChanged()` which starts a 300ms debounce timer, then waits 350ms before returning `gigCitySuggestions`. This preserves the existing debounce pattern.

2. Remove `key: gigLocationKey` param
3. Remove `textEditingController: locationController`, `focusNode: gigCityFocusNode`, `onSelected`, `fieldViewBuilder`, `optionsViewBuilder`
4. Keep `FieldHint` widget below

**Verification:** Typing triggers debounced query, suggestions appear after 2+ chars and 350ms delay

---

### Task 4: Migrate Rehearsal Location Autocomplete to FAutocomplete.text

**File:** `lib/features/events/widgets/rehearsal_form_fields.dart`

**Method:** `_buildLocationAutocomplete()` (~line 167)

**Steps:**

1. Replace entire `Autocomplete<String>(...)` widget with:
   ```dart
   FAutocomplete.text(
     items: locationSuggestions,
     filter: (query) {
       if (query.isEmpty) return const Iterable<String>.empty();
       final lowerQuery = query.toLowerCase();
       return locationSuggestions.where((location) =>
         location.toLowerCase().contains(lowerQuery)
       ).take(8);
     },
     hint: 'e.g., Studio, Venue Address',
     enabled: !isSaving,
     textCapitalization: TextCapitalization.words,
     inputFormatters: [TitleCaseTextFormatter()],
     forceErrorText: hasError ? errorText : null,
     onItemPress: (selection) {
       // No callback needed — rehearsal location has no autofill side effects
     },
   )
   ```
2. Remove `key: locationKey`, `initialValue`, `optionsBuilder`, `onSelected`, `fieldViewBuilder`, `optionsViewBuilder`
3. **Remove controller bridge workaround:** Delete `fieldController.addListener(() { locationController.text = fieldController.text; })`
4. Keep `FieldHint` widget below

**Verification:** Typing shows suggestions, selecting a suggestion populates the field

---

### Task 5: Update GigFormFields Constructor — Remove Controller Params

**File:** `lib/features/events/widgets/gig_form_fields.dart`

**Location:** Class definition (~line 25)

**Steps:**

1. Remove constructor params:
   - `required this.nameController` (~line 29)
   - `required this.locationController` (~line 38)
   - `gigNameKey` (if present)
   - `gigLocationKey` (if present)
   - `gigNameFocusNode` (if present)
   - `gigCityFocusNode` (if present)
2. Remove corresponding field declarations:
   - `final TextEditingController nameController;` (~line 96)
   - `final TextEditingController locationController;` (~line 106)
   - Focus node fields (if present)
3. Add new params to capture text values:
   - `required this.onGigNameTextChanged` (callback: `ValueChanged<String>`)
   - `required this.onGigCityTextChanged` (callback: `ValueChanged<String>`)
4. Update FAutocomplete widgets to call these callbacks via `onItemPress` or add `onChange` param

**Verification:** File compiles, constructor signature updated

---

### Task 6: Update RehearsalFormFields Constructor — Remove Controller Params

**File:** `lib/features/events/widgets/rehearsal_form_fields.dart`

**Location:** Class definition (~line 20)

**Steps:**

1. Remove constructor params:
   - `required this.locationController` (~line 26)
   - `locationKey` (if present)
2. Remove field declaration:
   - `final TextEditingController locationController;` (~line 72)
3. Add new param:
   - `required this.onLocationTextChanged` (callback: `ValueChanged<String>`)
4. Update FAutocomplete widget to call this callback

**Verification:** File compiles

---

### Task 7: Update EventEditorDrawer — Remove Controllers and Update Callers

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Steps:**

1. **Remove controller declarations** (~lines 129-130):
   - `final _locationController = TextEditingController();`
   - `final _nameController = TextEditingController();`
2. **Remove focus node declarations** (~line 204):
   - `final _gigCityFocusNode = FocusNode();`
   - (Also remove `_gigNameFocusNode`, `_gigLocationFocusNode` if declared elsewhere)
3. **Add local state variables** to capture text:
   ```dart
   String? _gigNameText;
   String? _gigCityText;
   String? _rehearsalLocationText;
   ```
4. **Remove controller listeners** (~lines 425, 436):
   - Delete `_locationController.addListener(...)` block
   - Delete `_nameController.addListener(...)` block
5. **Update `dispose()` method** (~lines 449-468):
   - Remove `_locationController.dispose();`
   - Remove `_nameController.dispose();`
   - Remove `_gigCityFocusNode.dispose();`
   - Remove any other removed focus node disposal calls
6. **Update `_buildInitialValueAnimControllers()` method** (~line 409):
   - Replace `isEdit && _nameController.text.isNotEmpty` with `isEdit && _gigNameText != null && _gigNameText!.isNotEmpty`
   - Replace `isEdit && _locationController.text.isNotEmpty` with equivalent checks for new state variables
7. **Update form submission logic**:
   - In `_buildGigFormData()` method (~line 1033): Replace `name: _nameController.text.trim()` with `name: _gigNameText?.trim() ?? ''`
   - Replace `'city': _locationController.text.trim()` with `'city': _gigCityText?.trim() ?? ''`
   - In `_buildRehearsalFormData()`: Replace `location: _locationController.text.trim()` with `location: _rehearsalLocationText?.trim() ?? ''`
8. **Update GigFormFields constructor call** (~line 2298):
   - Remove `nameController: _nameController`
   - Remove `locationController: _locationController`
   - Remove `gigCityFocusNode: _gigCityFocusNode`
   - Remove any key params
   - Add `onGigNameTextChanged: (text) => setState(() => _gigNameText = text)`
   - Add `onGigCityTextChanged: (text) => setState(() => _gigCityText = text)`
9. **Update RehearsalFormFields constructor call** (~line 2231):
   - Remove `locationController: _locationController`
   - Remove key param
   - Add `onLocationTextChanged: (text) => setState(() => _rehearsalLocationText = text)`

**Verification:** File compiles, all controller references removed

---

### Task 8: Update Suggestion-Fetching Methods

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Steps:**

1. **Update `_fetchGigNameSuggestions()` method**:
   - Change signature from `void _fetchGigNameSuggestions(String query)` to `List<String> _fetchGigNameSuggestions(String query)`
   - Remove `setState(() => _gigNameSuggestions = ...)` call
   - Return filtered venue names directly: `return venues.map((v) => v.name).where(...).toList();`
   - **Note:** This method is currently not a separate method — the filtering happens inline in `RawAutocomplete.optionsBuilder`. Extract this logic into a standalone method.
2. **Update `_fetchGigCitySuggestions()` method** (~line 878):
   - Change signature from `void _fetchGigCitySuggestions(String query)` to `Future<List<String>> _fetchGigCitySuggestions(String query)`
   - Keep debounce timer logic unchanged
   - Instead of `setState(() => _gigCitySuggestions = suggestions);`, return `suggestions` directly
   - Remove `setState` call
   - **Note:** This requires refactoring the debounce timer pattern — the timer callback must now return a Future. Consider moving debounce logic into `FAutocomplete.textBuilder`'s `filter` callback instead.
3. **Simplify:** Since FAutocomplete's `filter` handles the query logic, consider removing these helper methods entirely and moving logic inline into the `filter` callbacks defined in Tasks 2-4.

**Verification:** Methods return correct types, no `setState` calls remain

---

### Task 9: Run Flutter Analyze

**Command:** `flutter analyze`

**Expected:** 0 errors

**Steps:**

1. Run analyzer from project root
2. Verify no new errors introduced
3. Confirm pre-existing warnings remain unchanged
4. Document analyzer output in ENGINEER_REPORT.md

---

### Task 10: Format Modified Files

**Command:** `dart format lib/features/events/widgets/`

**Steps:**

1. Run formatter on all three modified files
2. Commit formatting changes separately (if significant) or include with implementation

---

### Task 11: Manual Device Verification (Local Test Only)

**Platform:** macOS (lowest barrier to entry)

**Steps:**

1. Run `flutter run -d macos`
2. Create a test band (if needed)
3. Open Add Gig drawer
4. **Test Gig Name autocomplete:**
   - Type 2+ characters
   - Verify Forui-styled popover appears with venue suggestions
   - Select a suggestion, verify gig name field is populated
   - Verify venue autofill triggers (address/city/state populated if venue has data)
5. **Test Gig City autocomplete:**
   - Type 2+ characters
   - Wait for debounced query (350ms)
   - Verify popover appears with city suggestions from past gigs
   - Select a suggestion, verify city field is populated
6. **Test Rehearsal Location autocomplete:**
   - Open Add Rehearsal drawer
   - Type into Location field
   - Verify popover appears with past rehearsal locations
   - Select a suggestion, verify location field is populated
7. **Test form submission:**
   - Fill out gig form with autocomplete fields
   - Save gig, verify event is created with correct name/city values
   - Repeat for rehearsal

**Verification:** All autocomplete fields render, show suggestions, and populate correctly. Form submission includes correct text values.

---

### Task 12: Generate Git Diff

**Command:** `git diff > /tmp/forui-autocomplete-migration.diff`

**Steps:**

1. Generate full diff of changes
2. Include diff in ENGINEER_REPORT.md

---

### Task 13: Write ENGINEER_REPORT.md

**Path:** `docs/features/forui-autocomplete-migration/ENGINEER_REPORT.md`

**Required sections:**

- Feature Slug
- Feature Title
- Goal
- Architect Tasks Completed (checklist)
- Files Created
- Files Modified
- Analyzer Results
- Test Results (manual device testing notes)
- Code Efficiency / Bloat Check
- Verification
- Deviations From Architect Plan (if any)
- Blockers Encountered (if any)
- Ready For QA (yes/no)
- Git Diff

---

## Verification Plan

### Pre-Deployment (Static Analysis)

**No pre-deployment tier applicable** — this is a pure client-side UI change with no database or backend impact.

---

### Post-Implementation (Manual Testing)

**Platform:** macOS, iOS, Android, Web (test on all available platforms; macOS minimum for approval)

#### Test 1: Gig Name Autocomplete Renders with Forui Popover

**Steps:**

1. Open Add Gig drawer
2. Tap into Gig Name field
3. Type 2+ characters (e.g., "The ")

**Expected:**

- Forui-styled popover appears below the field (not Material dropdown)
- Suggestions list shows matching venue names
- Popover has Forui border, shadow, colors (matches app theme)

**Actual:** _(QA fills in)_

---

#### Test 2: Gig Name Selection Triggers Venue Autofill

**Steps:**

1. Type "Gallery" in Gig Name field
2. Select "Gallery Cabaret" from suggestions

**Expected:**

- Gig Name field populated with "Gallery Cabaret"
- If venue has address/city/state data, those fields auto-populate
- `onGigNameChanged()` callback fires, triggering `_fetchGigNameSuggestions()`

**Actual:** _(QA fills in)_

---

#### Test 3: Gig City Autocomplete Shows Debounced Suggestions

**Steps:**

1. Tap into City field
2. Type "Chi"
3. Wait 350ms

**Expected:**

- Popover appears with city suggestions from past gigs (e.g., "Chicago")
- Debounce works (no query fires until 350ms after last keystroke)
- Suggestions list updates as typing continues

**Actual:** _(QA fills in)_

---

#### Test 4: Rehearsal Location Autocomplete Works Without Controller Bridge

**Steps:**

1. Open Add Rehearsal drawer
2. Tap into Location field
3. Type "Stu"

**Expected:**

- Popover shows matching location suggestions (e.g., "Studio A")
- Selecting a suggestion populates the field correctly
- No console errors related to controller sync

**Actual:** _(QA fills in)_

---

#### Test 5: Form Submission Includes Autocomplete Field Values

**Steps:**

1. Fill out Add Gig form:
   - Gig Name: "Gallery Cabaret" (selected from autocomplete)
   - City: "Chicago" (selected from autocomplete)
   - Date, time, other required fields
2. Save gig
3. Verify gig appears in calendar/list with correct name and city

**Expected:**

- Gig is created successfully
- Gig name = "Gallery Cabaret"
- Gig city = "Chicago"
- No missing or null field values

**Actual:** _(QA fills in)_

---

#### Test 6: Validation Errors Display on Empty Autocomplete Fields

**Steps:**

1. Open Add Gig drawer
2. Leave Gig Name field empty
3. Attempt to save

**Expected:**

- Validation error appears below/on Gig Name field
- Error text is visible (red text or red field border)
- Save is blocked

**Actual:** _(QA fills in)_

---

#### Test 7: Keyboard Behavior and Focus Management

**Steps:**

1. Open Add Gig drawer
2. Tap Gig Name field → type → select suggestion
3. Tap City field → type → select suggestion
4. Use Tab key to navigate between fields (desktop platforms)

**Expected:**

- Focus moves correctly between fields
- Keyboard appears/dismisses correctly (mobile platforms)
- Tab navigation works (desktop platforms)

**Actual:** _(QA fills in)_

---

#### Test 8: Console Output — No Material Warnings

**Steps:**

1. Open Add Gig drawer
2. Type into Gig Name and City fields to trigger popovers
3. Open Add Rehearsal drawer
4. Type into Location field
5. Observe console output

**Expected:**

- No "ListTile background color or ink splashes may be invisible" warnings
- No "No Material widget found" errors
- No widget assertion failures related to autocomplete fields

**Actual:** _(QA fills in)_

---

#### Test 9: Cross-Platform Visual Consistency

**Platforms:** iOS, Android, Web (if available)

**Steps:**

1. Open Add Gig drawer on each platform
2. Trigger autocomplete popovers
3. Compare appearance across platforms

**Expected:**

- Popover appearance matches Forui theme on all platforms
- Border, shadow, text styles consistent
- No platform-specific rendering issues

**Actual:** _(QA fills in)_

---

## QA Regression Areas

**Primary:**

1. **Gig creation with autocomplete fields** — verify gig name and city values are saved correctly
2. **Rehearsal creation with location autocomplete** — verify location value is saved correctly
3. **Venue autofill** — selecting a gig name from autocomplete should prefill address/city/state if venue exists
4. **Validation errors** — empty required autocomplete fields should block form submission and show error text

**Secondary:**

5. **Gig editing** — autocomplete fields should pre-populate with existing values when editing a gig
6. **Rehearsal editing** — location autocomplete should pre-populate when editing
7. **Multi-date potential gigs** — autocomplete fields work correctly in potential gig mode
8. **Keyboard/focus behavior** — Tab navigation, keyboard dismissal (mobile), field-to-field focus
9. **Console output** — no Material framework warnings or errors

**Out of scope for regression:**

- Setlist management (unaffected)
- Calendar rendering (unaffected)
- Member availability (unaffected)
- Financial entries (unaffected)

---

## Rollout / Migration Strategy

**Not applicable** — this is a single-phase client-side UI change with no backend or database migration. All users receive the updated autocomplete widgets on next app launch after deployment.

---

## Out of Scope

- **Other search/filter fields:** Song lookup search, setlist filter, A-Z search bars are NOT autocomplete widgets (they're plain text fields with result filtering below) and are out of scope
- **Venue autocomplete refactor:** The venue lookup logic in `_fetchGigNameSuggestions()` currently queries `_allVenues` list. This remains unchanged — optimizing venue lookup (e.g., async query instead of in-memory filter) is deferred
- **Debounce refactor:** The City field's 300ms debounce is currently implemented via `Timer` in the parent widget. This could be simplified to use FAutocomplete's async filter directly, but preserving the existing pattern is safer for this migration
- **AppTextField removal:** `AppTextField` is still used throughout the app. This migration does not deprecate it — FAutocomplete includes its own text field implementation, but other non-autocomplete fields continue using `AppTextField`
- **Forui migration audit:** A comprehensive audit of all Material widgets that could be replaced with Forui equivalents (switches, radios, checkboxes, etc.) is out of scope
