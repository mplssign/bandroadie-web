# ARCHITECT PLAN — Gig Venue Autofill & Deduplication

## Feature Slug

`feature/gig-venue-autofill-dedupe`

## Problem Summary

Band admins/managers re-enter venue details manually on every gig creation, even when the venue already exists in Contacts → Venues. When entering the same venue name across multiple gigs, duplicate venue rows are created instead of reusing the existing record. The Create Gig and Edit Gig forms lack a State field, preventing state data from being captured from the gig flow.

## Root Cause

**Confidence Level: HIGH** (confirmed through direct code observation)

The venue auto-creation logic in `lib/features/events/widgets/event_editor_drawer.dart` (lines 1347-1360) creates a duplicate venue on every gig save where `_selectedVenueId == null`, because:

1. **No deduplication check** — Before creating a venue, the code does not query the `venues` table to check if a venue with that name (and city) already exists for the band
2. **Name-only creation** — The venue creation call passes only `data: {'name': _nameController.text.trim()}`, ignoring `address`, `city` (from `_locationController`), and `state` (which doesn't exist in the form)
3. **Fragile matching** — The exact-match auto-link logic (line 705) sets `_selectedVenueId` only when the venue name matches exactly, but immediately clears it if the user types anything else (line 690-691), even whitespace edits
4. **Missing State field** — The gig form has no State input, so state data cannot be captured or passed to venue creation
5. **Incomplete auto-population** — When a venue is matched, only city is auto-filled; address and state are not

**Why duplicates occur in production:**

- User types venue name → exact match found → `_selectedVenueId` set → city auto-fills
- User edits name slightly (typo fix, whitespace) → `_selectedVenueId` cleared
- On save, code sees `_selectedVenueId == null` → creates new venue with only name → duplicate row in `venues` table
- Next gig at same venue: same flow, another duplicate

## Reference Docs Consulted

**Override Applied:** No `docs/reference/gigs/` or `docs/reference/venues/` folder exists.

Domain reference loaded from:

- `docs/agents/PROJECT_CONTEXT.md` — "Venues & Contacts" and "Events" sections
- `docs/reference/architecture/database_schema.md` — `gigs`, `venues`, `venue_contacts` table definitions

## Existing System Analysis

### Current Behavior: Gig Creation Flow

1. User opens Create Gig drawer (`AddEditEventBottomSheet` → `EventEditorDrawer`)
2. User types venue name in Name field (`_nameController`)
3. As user types, `_fetchGigNameSuggestions()` (line 683):
   - Filters venues by name (case-insensitive substring match)
   - If **exact match** found (line 705): sets `_selectedVenueId`, auto-fills city from `venue.city` + `venue.state` (line 712-720)
   - If no exact match or user edits name: clears `_selectedVenueId` (line 690)
4. User fills City (`_locationController`), Address (`_addressController`), other fields
5. User taps Save → `_handleSave()` (line 1235)
6. **Venue auto-creation logic** (line 1347-1360):
   ```dart
   if (_eventType == EventType.gig &&
       _selectedVenueId == null &&
       _nameController.text.trim().isNotEmpty) {
     final newVenue = await ref.read(venuesProvider.notifier).create(
       bandId: widget.bandId,
       data: {'name': _nameController.text.trim()},  // ← ONLY name!
     );
     if (newVenue != null) {
       _selectedVenueId = newVenue.id;
       formData = formData.copyWith(venueId: newVenue.id);
     }
   }
   ```
7. Gig is created with `venue_id` set to new or matched venue
8. Next gig: repeat from step 1 → another duplicate venue if name doesn't match exactly

### Data Flow: Gig → Venue Relationship

- **Gig model** (`lib/app/models/gig.dart`): `venueId` (String?, nullable FK)
- **Gigs table** (`gigs.venue_id`): FK to `venues.id`, nullable, ON DELETE SET NULL
- **Venue model** (`lib/features/contacts/models/venue.dart`): `name, address, city, state, phone, notes`
- **Venues table** (`public.venues`): No unique constraint on name — duplicates allowed

### Venue Creation: Current Implementation

- **Triggered by:** `event_editor_drawer.dart` line 1352 → `ref.read(venuesProvider.notifier).create()`
- **Repository:** `lib/features/contacts/venues_repository.dart` → `createVenue()`
- **Data passed:** Only `{'name': ...}` — city, address, state ignored
- **No dedup check:** Code does not query for existing venue before insert

### Venue Matching: Current Implementation

- **Line 705:** Exact match only (case-insensitive name comparison)
- **Match rule:** `v.name.toLowerCase() == queryLower`
- **On match:** Sets `_selectedVenueId`, auto-fills city (line 712-720)
- **Limitations:** City or address not used for matching; state not auto-filled

## Proposed Solution

### 1. Add State Field to Gig Form (UI-only)

- Add `_stateController` (TextEditingController) to `event_editor_drawer.dart`
- Initialize in `initState()`, dispose in `dispose()`
- Add State text field to `GigFormFields` widget (below City field, before Address)
- State is transient form state — not stored in `gigs` table, only passed to venue creation

### 2. Enhance Venue Auto-Population and Matching (line ~705)

Implement smart matching logic in `_fetchGigNameSuggestions()` to handle both single-venue and multi-venue scenarios:

- **Single match:** When exactly one venue matches the typed name (case-insensitive), auto-link immediately and auto-fill city, address, and state from that venue
- **Multiple matches:** When multiple venues share the same name (different cities), require the user to fill the city field before auto-linking — once city disambiguates, auto-fill address and state from the matched venue
- **No match:** Clear `_selectedVenueId` (no auto-link)

**Rationale:** Avoids circular dependency (can't require city to match before auto-filling city) while still preventing wrong venue from being linked when band has venues with duplicate names in different cities (e.g., "Blue Note" in NYC and St. Louis). Optimizes for the common case (single match) while safely handling the edge case (multiple matches requiring disambiguation).

### 3. Add Venue Deduplication Query Before Creation (line ~1347)

Before creating a new venue, query for existing venue:

```dart
final venueName = _nameController.text.trim();
final venueCity = _locationController.text.trim();

// Build null-safe query: when city is empty, match venues where city IS NULL
final query = supabase
    .from('venues')
    .select('id')
    .eq('band_id', widget.bandId)
    .ilike('name', venueName);

final existingVenue = venueCity.isEmpty
    ? await query.isFilter('city', null).maybeSingle()
    : await query.ilike('city', venueCity).maybeSingle();

if (existingVenue != null) {
  // Use existing venue instead of creating duplicate
  _selectedVenueId = existingVenue['id'] as String;
  formData = formData.copyWith(venueId: _selectedVenueId);
} else {
  // No match — create new venue with all fields
  final newVenue = await ref.read(venuesProvider.notifier).create(
    bandId: widget.bandId,
    data: {
      'name': venueName,
      'city': venueCity.isNotEmpty ? venueCity : null,
      'address': _addressController.text.trim().isNotEmpty
          ? _addressController.text.trim()
          : null,
      'state': _stateController.text.trim().isNotEmpty
          ? _stateController.text.trim()
          : null,
    },
  );
  if (newVenue != null) {
    _selectedVenueId = newVenue.id;
    formData = formData.copyWith(venueId: newVenue.id);
  }
}
```

**Match Rule:** Band-scoped, case-insensitive match on **(name, city)**.

**Null-safe matching:** When city is empty, query matches venues where `city IS NULL` (not `city ILIKE ''`). This ensures venues created without a city can be correctly deduplicated on subsequent gig saves.

**Rationale:**

- Same venue name can legitimately exist in different cities (e.g., "The Blue Note" in NYC and St. Louis)
- Within a band's context, same name + city is almost certainly the same venue
- Address not used for matching to handle slight variations ("123 Main St" vs "123 Main Street")
- State optional for matching since city is usually sufficient

### 4. Enhance Venue Creation to Include All Fields (line ~1352)

Pass all available fields to venue creation:

```dart
data: {
  'name': _nameController.text.trim(),
  'city': _locationController.text.trim().isNotEmpty ? _locationController.text.trim() : null,
  'address': _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
  'state': _stateController.text.trim().isNotEmpty ? _stateController.text.trim() : null,
}
```

### What Must NOT Change

- Gigs table schema (no new columns)
- Venues table schema (state column already exists)
- Venue repository method signatures
- RLS policies
- Rehearsal forms (unaffected)

## Database Impact

**Not applicable** — No schema changes required.

- `gigs.venue_id`: FK already exists (migration `20260411000000_add_venue_id_to_gigs.sql`)
- `venues.state`: Column already exists (migration `20260410000000_contacts_venues_tables.sql`)
- `venues` table: No unique constraint on name — duplicates currently allowed (by design, for multi-city support)
- Dedup query uses `.eq()` and `.ilike()` — both indexed on `band_id` via `idx_venues_band_id`

**RLS Policies:** Venue insert/update already permit admins and members — no policy changes needed.

**Database query added:** One read-only SELECT on `venues` table during gig save (only when `_selectedVenueId == null`). Query is indexed (`band_id`), scoped to current band, and fails gracefully (if no match, proceeds to create as before).

## Flutter Architecture Changes

### Files Modified

#### 1. `lib/features/events/widgets/event_editor_drawer.dart`

- **State variables:** Add `TextEditingController _stateController;`
- **initState():** Initialize `_stateController = TextEditingController();`
- **initState() edit mode:** Populate `_stateController` from matched venue's state (if `_selectedVenueId` is set)
- **dispose():** Add `_stateController.dispose();`
- **\_fetchGigNameSuggestions()** (line ~705): Replace exact match logic with smart matching:

  ```dart
  // Smart matching: single-match auto-fills immediately, multi-match requires city to disambiguate
  final nameMatches = venues.where((v) => v.name.toLowerCase() == queryLower).toList();

  if (nameMatches.length == 1) {
    // Exactly one match — auto-link and auto-fill immediately
    final venue = nameMatches.first;
    _selectedVenueId = venue.id;

    // Auto-fill city from venue if set and location field is empty
    if (venue.city != null &&
        venue.city!.isNotEmpty &&
        _locationController.text.trim().isEmpty) {
      final cityState = [
        venue.city,
        if (venue.state != null && venue.state!.isNotEmpty) venue.state,
      ].join(', ');
      _locationController.text = cityState;
    }

    // Auto-fill address from venue if set and address field is empty
    if (venue.address != null &&
        venue.address!.isNotEmpty &&
        _addressController.text.trim().isEmpty) {
      _addressController.text = venue.address!;
    }

    // Auto-fill state from venue if set and state field is empty
    if (venue.state != null &&
        venue.state!.isNotEmpty &&
        _stateController.text.trim().isEmpty) {
      _stateController.text = venue.state!;
    }
  } else if (nameMatches.length > 1) {
    // Multiple matches — require city field to disambiguate
    final currentCity = _locationController.text.trim().toLowerCase();
    final exactMatch = nameMatches.cast<Venue?>().firstWhere(
          (v) => (v!.city?.toLowerCase() ?? '') == currentCity,
          orElse: () => null,
        );

    if (exactMatch != null) {
      // City disambiguated — auto-link and auto-fill address/state (city already typed)
      _selectedVenueId = exactMatch.id;

      // Auto-fill address from venue if set and address field is empty
      if (exactMatch.address != null &&
          exactMatch.address!.isNotEmpty &&
          _addressController.text.trim().isEmpty) {
        _addressController.text = exactMatch.address!;
      }

      // Auto-fill state from venue if set and state field is empty
      if (exactMatch.state != null &&
          exactMatch.state!.isNotEmpty &&
          _stateController.text.trim().isEmpty) {
        _stateController.text = exactMatch.state!;
      }
    } else {
      // Multiple matches, city doesn't disambiguate yet — don't auto-link
      _selectedVenueId = null;
    }
  } else {
    // No match — clear venue link
    _selectedVenueId = null;
  }
  ```

- **\_handleSave()** (line ~1347): Replace venue auto-creation block with dedup query + create logic (see Proposed Solution #3 above)
- **\_createGigFormFields()**: Add `stateController: _stateController` to `GigFormFields` constructor

#### 2. `lib/features/events/widgets/gig_form_fields.dart`

- **Constructor params:** Add `required this.stateController`
- **Final fields:** Add `final TextEditingController stateController;`
- **build() method:** Add State text field widget after `buildAddressCityRow()` call:
  ```dart
  const SizedBox(height: Spacing.space16),
  _buildStateField(context),
  ```
- **New method:** Add `_buildStateField(BuildContext context)` widget:
  ```dart
  Widget _buildStateField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'State (optional)',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: stateController,
          enabled: !isSaving,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          style: AppTextStyles.callout.copyWith(
            color: context.colors.textPrimary,
          ),
          onChanged: (_) => onMarkDirty(),
          decoration: InputDecoration(
            hintText: 'e.g., IL, NY, CA',
            hintStyle: AppTextStyles.callout.copyWith(
              color: context.colors.textMuted,
            ),
            filled: true,
            fillColor: context.colors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: context.colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: context.colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
  ```

### No Changes To

- `lib/app/models/gig.dart` — no new fields (gig does not store state)
- `lib/features/events/models/event_form_data.dart` — state is UI-only, not persisted in form data
- `lib/features/contacts/models/venue.dart` — state field already exists
- `lib/features/contacts/venues_repository.dart` — `create()` method already accepts arbitrary `data` map

## Files to Create

None.

## Files to Modify

| File                                                   | What Changes                                                                                                                                                                                   |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | Add `_stateController` (declare, init, dispose); enhance venue auto-fill logic to populate address + state; add venue dedup query before creation; pass city, address, state to venue creation |
| `lib/features/events/widgets/gig_form_fields.dart`     | Add `stateController` constructor param + final field; add `_buildStateField()` method; call it in `build()` after address/city row                                                            |

## Files Off-Limits

| File                                                     | Reason                                                                                      |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `lib/app/models/gig.dart`                                | No new fields — gig does not store state directly (venue does)                              |
| `lib/features/events/models/event_form_data.dart`        | State is transient UI state for venue creation only — not part of form data model           |
| `lib/features/contacts/models/venue.dart`                | State field already exists — no changes needed                                              |
| `lib/features/contacts/venues_repository.dart`           | Existing `create()` method signature already handles arbitrary data map — no changes needed |
| `supabase/migrations/`                                   | No migration needed — all columns already exist                                             |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | Rehearsals do not use venues — unaffected                                                   |

## System Impact Map

| System                                 | Impact                                                                                   |
| -------------------------------------- | ---------------------------------------------------------------------------------------- |
| Gigs                                   | **affected** — form gains State field; venue auto-fill enhanced; venue dedup logic added |
| Rehearsals                             | unaffected                                                                               |
| Setlists / Catalog                     | unaffected                                                                               |
| Members / RBAC                         | unaffected                                                                               |
| Auth / Session                         | unaffected                                                                               |
| Routing                                | unaffected                                                                               |
| Notifications                          | unaffected                                                                               |
| Venues (Contacts feature)              | **affected** — venue creation now passes city, address, state; dedup query added         |
| Platform (iOS / Android / Web / macOS) | **all affected** — gig forms on all platforms gain State field                           |

## Regression Risk

**Level: LOW**

**Rationale:**

- Only 2 files modified (`event_editor_drawer.dart`, `gig_form_fields.dart`)
- Changes isolated to gig creation/edit flow — no impact on rehearsals, setlists, members, auth
- Dedup query is read-only and fails gracefully (if no match, proceeds to create as before)
- State field is optional (nullable) — no validation failures if left empty
- Venue auto-fill enhancement is additive (fills more fields, doesn't break existing city auto-fill)
- No database schema changes
- No repository method signature changes
- No RLS policy changes

**Testing Confidence:**

- Dedup query uses indexed columns (`band_id`, name via `.ilike()`, city via `.ilike()`)
- Venue repository `create()` method already used in production — data map flexibility is by design
- State field uses standard Flutter `TextField` with same pattern as address field (recently added)

## Engineer Task Breakdown

Execute in strict order. Each task is atomic and independently verifiable.

### Task 1: [EventEditorDrawer] Add State Controller Declaration

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

- Locate line ~131 where `_venueHintController` is declared
- Add after `_addressHintController`:
  ```dart
  final _stateController = TextEditingController();
  ```

**Verification:** `flutter analyze` passes (no unused variable warning yet — will be used in next tasks).

---

### Task 2: [EventEditorDrawer] Initialize State Controller in initState()

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

- Locate `initState()` method, line ~231
- After `_addressController.addListener(...)` line, add:
  ```dart
  _stateController.addListener(_markDirty);
  ```

**Verification:** Controller is initialized and listener attached.

---

### Task 3: [EventEditorDrawer] Populate State Controller in Edit Mode

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

- Locate `initState()` edit mode block, line ~288 where `_selectedVenueId = data.venueId;` is set
- After the venue population logic (line ~288-304), add state population:
  ```dart
  // Populate state from linked venue (if any)
  if (_selectedVenueId != null) {
    final venue = venues.cast<Venue?>().firstWhere(
          (v) => v!.id == _selectedVenueId,
          orElse: () => null,
        );
    if (venue != null && venue.state != null && venue.state!.isNotEmpty) {
      _stateController.text = venue.state!;
    }
  }
  ```

**Verification:** In edit mode for a gig with a linked venue that has state set, `_stateController` is populated.

---

### Task 4: [EventEditorDrawer] Dispose State Controller

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

- Locate `dispose()` method, line ~416
- After `_addressHintController.dispose();` line, add:
  ```dart
  _stateController.dispose();
  ```

**Verification:** No controller leak warnings in Flutter DevTools.

---

### Task 5: [EventEditorDrawer] Enhance Venue Auto-Link with Smart Matching

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

- Locate `_fetchGigNameSuggestions()` method, line ~683
- Find the exact match block starting at line ~705 where `_selectedVenueId` is set
- **Replace** the existing exact match logic (lines ~705-723) with:

  ```dart
  // Smart matching: single-match auto-fills immediately, multi-match requires city to disambiguate
  final nameMatches = venues.where((v) => v.name.toLowerCase() == queryLower).toList();

  if (nameMatches.length == 1) {
    // Exactly one match — auto-link and auto-fill immediately
    final venue = nameMatches.first;
    _selectedVenueId = venue.id;

    // Auto-fill city from venue if set and location field is empty
    if (venue.city != null &&
        venue.city!.isNotEmpty &&
        _locationController.text.trim().isEmpty) {
      final cityState = [
        venue.city,
        if (venue.state != null && venue.state!.isNotEmpty) venue.state,
      ].join(', ');
      _locationController.text = cityState;
    }

    // Auto-fill address from venue if set and address field is empty
    if (venue.address != null &&
        venue.address!.isNotEmpty &&
        _addressController.text.trim().isEmpty) {
      _addressController.text = venue.address!;
    }

    // Auto-fill state from venue if set and state field is empty
    if (venue.state != null &&
        venue.state!.isNotEmpty &&
        _stateController.text.trim().isEmpty) {
      _stateController.text = venue.state!;
    }
  } else if (nameMatches.length > 1) {
    // Multiple matches — require city field to disambiguate
    final currentCity = _locationController.text.trim().toLowerCase();
    final exactMatch = nameMatches.cast<Venue?>().firstWhere(
          (v) => (v!.city?.toLowerCase() ?? '') == currentCity,
          orElse: () => null,
        );

    if (exactMatch != null) {
      // City disambiguated — auto-link and auto-fill address/state (city already typed)
      _selectedVenueId = exactMatch.id;

      // Auto-fill address from venue if set and address field is empty
      if (exactMatch.address != null &&
          exactMatch.address!.isNotEmpty &&
          _addressController.text.trim().isEmpty) {
        _addressController.text = exactMatch.address!;
      }

      // Auto-fill state from venue if set and state field is empty
      if (exactMatch.state != null &&
          exactMatch.state!.isNotEmpty &&
          _stateController.text.trim().isEmpty) {
        _stateController.text = exactMatch.state!;
      }
    } else {
      // Multiple matches, city doesn't disambiguate yet — don't auto-link
      _selectedVenueId = null;
    }
  } else {
    // No match — clear venue link
    _selectedVenueId = null;
  }
  ```

**Verification:**

- When typing a venue name with exactly one match, auto-fill happens immediately (city, address, state)
- For bands with multiple venues sharing the same name in different cities, auto-link only happens after city field disambiguates the match

---

### Task 6: [EventEditorDrawer] Add Venue Deduplication Query Before Creation

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

- Locate `_handleSave()` method, line ~1235
- Find the venue auto-creation block starting at line ~1347:
  ```dart
  // Auto-create venue if user typed a name that doesn't match an existing venue
  if (_eventType == EventType.gig &&
      _selectedVenueId == null &&
      _nameController.text.trim().isNotEmpty) {
    final newVenue = await ref.read(venuesProvider.notifier).create(
      bandId: widget.bandId,
      data: {'name': _nameController.text.trim()},
    );
    if (newVenue != null) {
      _selectedVenueId = newVenue.id;
      formData = formData.copyWith(venueId: newVenue.id);
    }
  }
  ```
- **Replace entire block** with:

  ```dart
  // Auto-create venue if user typed a name that doesn't match an existing venue
  if (_eventType == EventType.gig &&
      _selectedVenueId == null &&
      _nameController.text.trim().isNotEmpty) {
    // Check if venue already exists (band-scoped, case-insensitive name + city match)
    final venueName = _nameController.text.trim();
    final venueCity = _locationController.text.trim();

    // Build null-safe query: when city is empty, match venues where city IS NULL
    final query = supabase
        .from('venues')
        .select('id')
        .eq('band_id', widget.bandId)
        .ilike('name', venueName);

    final existingVenue = venueCity.isEmpty
        ? await query.isFilter('city', null).maybeSingle()
        : await query.ilike('city', venueCity).maybeSingle();

    if (existingVenue != null) {
      // Use existing venue instead of creating duplicate
      _selectedVenueId = existingVenue['id'] as String;
      formData = formData.copyWith(venueId: _selectedVenueId);
    } else {
      // No match — create new venue with all available fields
      final newVenue = await ref.read(venuesProvider.notifier).create(
        bandId: widget.bandId,
        data: {
          'name': venueName,
          'city': venueCity.isNotEmpty ? venueCity : null,
          'address': _addressController.text.trim().isNotEmpty
              ? _addressController.text.trim()
              : null,
          'state': _stateController.text.trim().isNotEmpty
              ? _stateController.text.trim()
              : null,
        },
      );
      if (newVenue != null) {
        _selectedVenueId = newVenue.id;
        formData = formData.copyWith(venueId: newVenue.id);
      }
    }
  }
  ```

**Verification:**

- Create a gig with venue "Test Venue" and city "Chicago" → new venue created
- Create another gig with same name and city → existing venue reused (check Contacts → Venues for duplicate count)

---

### Task 7: [EventEditorDrawer] Pass State Controller to GigFormFields

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

- Locate `_createGigFormFields()` method, line ~1850
- Find the `GigFormFields` constructor call
- After `gigAddressFocusNode: _gigAddressFocusNode,` parameter, add:
  ```dart
  stateController: _stateController,
  ```

**Verification:** `flutter analyze` passes — no missing required parameter error.

---

### Task 8: [GigFormFields] Add State Controller Parameter

**File:** `lib/features/events/widgets/gig_form_fields.dart`

- Locate the `GigFormFields` constructor, line ~18
- After `required this.gigAddressFocusNode,` parameter, add:
  ```dart
  required this.stateController,
  ```
- Locate the final fields declaration section, line ~93
- After `final FocusNode gigAddressFocusNode;` declaration, add:
  ```dart
  final TextEditingController stateController;
  ```

**Verification:** `flutter analyze` passes — parameter is now wired.

---

### Task 9: [GigFormFields] Add State Field Widget

**File:** `lib/features/events/widgets/gig_form_fields.dart`

- Locate the `build()` method, line ~125
- Find the call to `buildAddressCityRow()` (around line ~142)
- After the `buildAddressCityRow(),` line, add:
  ```dart
  const SizedBox(height: Spacing.space16),
  _buildStateField(context),
  ```
- Add the `_buildStateField()` method at the end of the class (after `buildGigPayButton()` method, line ~258):
  ```dart
  /// Builds the state field (called from parent build method).
  Widget _buildStateField(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'State (optional)',
          style: AppTextStyles.footnote.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: stateController,
          enabled: !isSaving,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          maxLength: 2,
          style: AppTextStyles.callout.copyWith(
            color: context.colors.textPrimary,
          ),
          onChanged: (_) => onMarkDirty(),
          decoration: InputDecoration(
            hintText: 'e.g., IL, NY, CA',
            counterText: '', // Hide character counter
            hintStyle: AppTextStyles.callout.copyWith(
              color: context.colors.textMuted,
            ),
            filled: true,
            fillColor: context.colors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: context.colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: BorderSide(color: context.colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Spacing.buttonRadius),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }
  ```

**Verification:**

- `flutter analyze` passes
- Open Create Gig form → State field appears below City field, before Address field
- Field accepts input, triggers dirty state on change

---

### Task 10: [Final Verification] Run Flutter Analyze

**Command:** `flutter analyze`

**Expected:** 0 errors, 0 warnings.

---

### Task 11: [Manual Test] Verify Venue Auto-Fill

1. Navigate to Contacts → Venues
2. Create a venue: Name = "Test Venue", City = "Chicago", Address = "123 Main St", State = "IL"
3. Navigate to Calendar → Add Gig
4. Type "Test Venue" in Name field → verify City, Address, State auto-fill
5. Save gig → verify it links to existing venue (check `venue_id` in Supabase or via app state)

---

### Task 12: [Manual Test] Verify Venue Deduplication

1. Create a gig: Name = "New Venue", City = "Austin", State = "TX" → Save
2. Check Contacts → Venues → verify "New Venue" was created
3. Create another gig: Name = "New Venue", City = "Austin", State = "TX" → Save
4. Check Contacts → Venues → verify NO duplicate "New Venue" entry exists (only 1 row)
5. Check both gigs in Calendar → both should link to the same venue

---

### Task 13: [Manual Test] Verify State Field Display on All Platforms

1. **Web:** Open gig form → verify State field appears
2. **iOS:** Open gig form → verify State field appears
3. **Android:** Open gig form → verify State field appears
4. **macOS:** Open gig form → verify State field appears

---

## Verification Plan

### Tier 1 — Pre-deployment (SQL-based verification)

Not applicable — no database changes or RPC functions to verify. This feature is pure Flutter client-side logic.

### Tier 2 — Post-deployment (Manual Testing)

**POST-DEPLOY TEST 1: Venue Auto-Fill**

1. Precondition: Create a venue in Contacts → Venues with Name = "Blue Note", City = "Chicago", Address = "1234 N Halsted St", State = "IL"
2. Action: Navigate to Add Gig, type "Blue Note" in Name field
3. Expected: City auto-fills to "Chicago, IL", Address auto-fills to "1234 N Halsted St", State auto-fills to "IL"
4. Action: Save gig
5. Expected: Gig is saved with `venue_id` linked to existing "Blue Note" venue (verify in Supabase `gigs` table or via app state)

**POST-DEPLOY TEST 2: Venue Deduplication**

1. Action: Create a gig with Name = "Test Venue Dedup", City = "Austin", State = "TX"
2. Expected: Gig saves successfully, new venue created in `venues` table
3. Action: Create a second gig with Name = "Test Venue Dedup", City = "Austin", State = "TX"
4. Expected: Gig saves successfully, **no duplicate venue created** — second gig links to same venue as first gig
5. Verification: Query `SELECT * FROM venues WHERE band_id = '<band_id>' AND name ILIKE 'Test Venue Dedup';` → should return exactly 1 row
6. Verification: Check Contacts → Venues → "Test Venue Dedup" appears only once

**POST-DEPLOY TEST 3: Venue Creation with All Fields**

1. Action: Create a gig with Name = "Full Venue Test", City = "Seattle", Address = "456 Pike St", State = "WA"
2. Expected: New venue created in `venues` table with all fields populated
3. Verification: Query `SELECT name, city, address, state FROM venues WHERE name ILIKE 'Full Venue Test';` → should return `name='Full Venue Test', city='Seattle', address='456 Pike St', state='WA'`

**POST-DEPLOY TEST 4: State Field Optional**

1. Action: Create a gig with Name = "No State Test", City = "Boston", Address = "789 Commonwealth Ave", leave State field empty
2. Expected: Gig saves successfully, venue created with state = NULL
3. Verification: Query `SELECT state FROM venues WHERE name ILIKE 'No State Test';` → should return `state=NULL`

**POST-DEPLOY TEST 5: Edit Mode State Population**

1. Precondition: Create a venue "Edit Test" with State = "CA"
2. Action: Create a gig with Name = "Edit Test" → save
3. Action: Edit the gig → open Edit Gig drawer
4. Expected: State field is populated with "CA"

**POST-DEPLOY TEST 6: Case-Insensitive Deduplication**

1. Action: Create a gig with Name = "CASE TEST", City = "denver", State = "CO"
2. Action: Create a second gig with Name = "case test", City = "DENVER", State = "co"
3. Expected: Second gig links to same venue as first gig (case-insensitive match on name and city)
4. Verification: Query `SELECT COUNT(*) FROM venues WHERE name ILIKE 'case test' AND city ILIKE 'denver';` → should return `1`

**POST-DEPLOY TEST 7: Null-Safe City Deduplication**

1. Action: Create a gig with Name = "No City Venue", leave City field empty, State = "TX"
2. Expected: Gig saves successfully, new venue created with `city = NULL`
3. Action: Create a second gig with Name = "No City Venue", leave City field empty, State = "TX"
4. Expected: Second gig links to same venue as first gig (null-safe match on name when city is empty)
5. Verification: Query `SELECT COUNT(*) FROM venues WHERE name ILIKE 'No City Venue' AND city IS NULL;` → should return `1`

**POST-DEPLOY TEST 8: Multi-City Venue Disambiguation**

1. Precondition: Create two venues in Contacts → Venues:
   - Name = "Blue Note", City = "New York", State = "NY"
   - Name = "Blue Note", City = "St. Louis", State = "MO"
2. Action: Navigate to Add Gig, type "Blue Note" in Name field (do not fill City yet)
3. Expected: Suggestions show "Blue Note" but no auto-link happens (`_selectedVenueId` remains null) because multiple venues match the name — disambiguation required
4. Action: Fill City field with "New York"
5. Expected: Auto-link happens immediately (city disambiguates the match), Address and State auto-fill from NYC venue
6. Action: Save gig
7. Expected: Gig links to NYC "Blue Note" venue (not St. Louis)
8. Verification: Query `SELECT city FROM venues v JOIN gigs g ON g.venue_id = v.id WHERE g.name = 'Blue Note';` → should return `city='New York'`

---

## QA Regression Areas

QA must specifically test:

### Primary Feature Validation

1. **Venue Auto-Fill:** Type existing venue name → verify City, Address, State auto-fill
2. **Venue Deduplication:** Create multiple gigs with same name+city → verify no duplicate venues created
3. **State Field Display:** State field appears on Create Gig and Edit Gig forms on all platforms (iOS, Android, Web, macOS)
4. **Venue Creation with All Fields:** New venues capture name, city, address, and state from gig form
5. **State Field Optional:** Gig saves successfully when State is left empty (no validation errors)

### Regression Testing

1. **Existing Gigs:** Edit an existing gig (created before this feature) → verify form loads correctly, save works
2. **Rehearsal Forms:** Verify rehearsal creation/edit forms are unaffected (no state field, no errors)
3. **Venue Contacts:** Navigate to Contacts → Venues → verify list displays correctly, edit venue works
4. **Gig Name Autocomplete:** Verify venue name suggestions still appear when typing in Name field
5. **City Autocomplete:** Verify city suggestions still work in City field
6. **Address Field:** Verify Address field (recently added) still works correctly
7. **Gig Pay:** Verify Gig Pay bottom sheet opens and saves correctly
8. **Load-In Time:** Verify Load-In time selector works correctly
9. **Multi-Date Potential Gigs:** Verify additional dates can be added/removed, save correctly
10. **Member Availability:** Verify member availability prompt works for potential gigs

### Edge Cases

1. **Empty Venue Name:** Leave Name field empty → verify gig saves without creating venue (expected: venue_id = null)
2. **Empty City (null-safe dedup):** Enter venue name but leave City empty → create gig → enter same venue name again with empty City → verify dedup query handles null city gracefully (should reuse existing venue where city IS NULL)
3. **Whitespace Handling:** Enter venue name with leading/trailing spaces → verify trim() works, dedup match succeeds
4. **Venue Match Then Edit:** Type venue name (match found) → edit name slightly → save → verify new venue created (not linked to original)
5. **Band Switching:** Create gig in Band A → switch to Band B → create gig → verify venues are band-scoped (no cross-band leakage)
6. **Multi-City Same Name:** Band has two venues with same name in different cities → type venue name → fill city → verify correct venue is auto-linked based on city (not random/first match)

---

## Rollout / Migration Strategy

Not applicable — no database migration required. Feature is live immediately after Flutter code deploy.

**Post-Deploy Actions:**

1. Monitor Supabase logs for venue creation queries (ensure dedup logic is running)
2. Spot-check `venues` table for duplicate names within same band — should see reduction in duplicates for new gigs
3. Verify State field appears on all platforms (web, iOS, Android, macOS)

---

## Out of Scope

Explicitly NOT included in this feature:

1. **Bulk venue deduplication for existing data** — This feature prevents NEW duplicates; it does not retroactively merge existing duplicate venue rows. A separate cleanup script would be required for that.
2. **Address parsing/validation** — No geocoding, address standardization, or validation logic. User enters address as free text.
3. **State dropdown/picker** — State is a free text field (2-character max length), not a validated enum picker. This keeps the UI simple and works for international bands.
4. **Venue editing from gig form** — If user wants to update a venue's address/state, they must go to Contacts → Venues → Edit Venue. The gig form only creates or links to venues, it does not edit them.
5. **Venue search/picker** — No dedicated venue picker UI on the gig form. Venue linking happens via exact name match auto-complete only.
6. **Venue deletion on gig delete** — Deleting a gig does not delete its linked venue. Venues persist independently in Contacts → Venues.
7. **Required state field** — State is optional (nullable). No validation errors if left empty.
8. **Rehearsal venue support** — Rehearsals do not link to venues. Only gigs use the venue system.

---

---

# ADDENDUM — Manual Verification Bug Diagnosis (Task 11)

## Date

2026-07-10

## Context

Tony completed manual runtime testing (Task 11 from original plan) and found that venue auto-fill did NOT work as designed:

**Symptom:**

1. Created first gig, entered venue name + address → saved successfully
2. Venue correctly appeared in Contacts → Venues (venue creation works)
3. Created second gig, entered the **same** venue name
4. **Expected:** City, address, state should auto-fill immediately (per smart-matching logic Task 5)
5. **Actual:** Nothing auto-filled

## Root Cause Analysis

**Confidence Level: MEDIUM**

The auto-fill failure is likely caused by **empty provider state when user types**, but the exact mechanism that caused the empty state cannot be confirmed from static code analysis alone.

### What Can Be Confirmed From Code (HIGH Confidence)

1. **`_fetchGigNameSuggestions()` reads from provider state** ([event_editor_drawer.dart:710](lib/features/events/widgets/event_editor_drawer.dart#L710)):

   ```dart
   final venues = ref.read(venuesProvider).venues;
   ```

   This is a one-time read of the current `venuesProvider.state.venues` list. It does NOT trigger a fetch or query. If the list is empty at this moment, no suggestions will be generated and no auto-fill will happen.

2. **Drawer's `load()` call is not awaited** ([event_editor_drawer.dart:322](lib/features/events/widgets/event_editor_drawer.dart#L322)):

   ```dart
   WidgetsBinding.instance.addPostFrameCallback((_) {
     ref.read(membersProvider.notifier).loadMembers(widget.bandId);
     ref.read(venuesProvider.notifier).load(widget.bandId);  // ← Not awaited
   });
   ```

   The drawer schedules `load()` asynchronously but does not wait for it to complete. The form renders immediately and the user can type before venues are loaded.

3. **VenuesNotifier.build() returns empty state** ([venues_controller.dart:43](lib/features/contacts/venues_controller.dart#L43)):

   ```dart
   @override
   VenuesState build() => const VenuesState();  // venues: []
   ```

   When the provider is first accessed or rebuilt, it starts with an empty venues list.

4. **Provider is not autoDispose** ([venues_controller.dart:147](lib/features/contacts/venues_controller.dart#L147)):

   ```dart
   final venuesProvider = NotifierProvider<VenuesNotifier, VenuesState>(
     VenuesNotifier.new,
   );
   ```

   Riverpod will NOT garbage-collect or rebuild this provider from navigation alone. It persists across screen changes.

5. **VenuesRepository has a cache layer** ([venues_repository.dart:28-44](lib/features/contacts/venues_repository.dart#L28-L44)):

   ```dart
   Future<List<Venue>> fetchVenues({
     required String? bandId,
     bool forceRefresh = false,
   }) async {
     if (!forceRefresh) {
       final cached = _cache[bandId];
       if (cached != null && !cached.isExpired) {
         return cached.data;  // ← Returns cached data without Supabase query
       }
     }
     // ... fetch from Supabase and cache
   }
   ```

   - `load()` calls `fetchVenues(forceRefresh: false)` → uses cache if available
   - `refresh()` calls `fetchVenues(forceRefresh: true)` → bypasses cache
   - Cache TTL is 5 minutes

6. **`create()` invalidates cache then calls `load()`** ([venues_controller.dart:92-102](lib/features/contacts/venues_controller.dart#L92-L102)):

   ```dart
   final venue = await _repository.createVenue(bandId: bandId, data: data);
   await load(bandId);  // ← Repository cache was invalidated by createVenue
   ```

   `createVenue()` calls `_invalidateCache(bandId)` before returning, so the subsequent `load()` fetches fresh from Supabase and updates provider state with the new venue.

7. **`load()` does NOT clear venues during fetch** ([venues_controller.dart:54](lib/features/contacts/venues_controller.dart#L54)):
   ```dart
   state = state.copyWith(isLoading: true, clearError: true);
   ```
   The `venues` parameter is not passed, so `state.venues` retains its previous value while `isLoading: true`. The list only updates after the fetch completes.

### What Cannot Be Confirmed Without Runtime Data (LOW Confidence)

**The gap:** We cannot determine from code alone why `venuesProvider.state.venues` would be empty when the user typed in the second gig drawer, given that:

- The provider is not autoDispose (won't be rebuilt from navigation)
- `create()` successfully updated provider state with the new venue after the first gig saved
- User confirmed the venue appeared in Contacts → Venues (proving provider state had the venue at that point)

**Possible explanations (all require runtime verification):**

1. **Provider state was reset between first and second gig:**
   - Band switching triggers `reset()` ([contacts_tab_content.dart:176](lib/features/contacts/contacts_tab_content.dart#L176)), which clears state
   - App restart or hot reload during development
   - Some other code path calling `ref.invalidate(venuesProvider)` or `reset()`

2. **Timing race on second drawer open:**
   - If provider state happened to be empty (from earlier reset or initial app launch)
   - User opened drawer → `load()` scheduled in postFrameCallback (not awaited)
   - User typed before `load()` completed → read empty list
   - This would only happen if the state wasn't already populated from the first gig's `create()` call

3. **First gig's `create()` didn't actually update provider state:**
   - Unlikely, since Tony confirmed venue appeared in Contacts → Venues
   - Would require the Contacts screen to call `refresh()` or `load()` and receive data from cache/Supabase independently

**Stop condition:** Diagnosis cannot progress to HIGH confidence without one of:

- Runtime logging showing exact value of `venuesProvider.state.venues` when `_fetchGigNameSuggestions()` is called
- Debugger session stepping through second drawer open
- Console logs showing whether `load()` completed before or after user typed

### Proposed Fix (Addresses Most Likely Scenario)

**Problem:** Regardless of why the state was empty, the current architecture allows a race condition where user can type before venues are loaded.

**Solution:** Optimistically update `venuesProvider.state.venues` immediately when a venue is created, ensuring it's available for subsequent drawers even if:

- Provider state happens to be empty when second drawer opens
- `load()` hasn't completed yet when user starts typing
- Provider is rebuilt between gigs (for any reason)

**Why this works:**

1. **Immediate availability:** New venue appended to state synchronously in `create()` method
2. **Survives timing gaps:** Even if user types before postFrameCallback's `load()` completes, the venue is already in state
3. **No reliance on timing:** Doesn't depend on `load()` completing before user types
4. **Standard Riverpod pattern:** Optimistic updates are a best practice for exactly this reason

---

## Corrected Solution

### Primary Fix: Optimistic State Update in VenuesNotifier.create()

**Problem:** The current `create()` method relies solely on `await load(bandId)` to refresh the list. If the provider is rebuilt later (resetting to empty state), that updated state is lost.

**Solution:** Immediately append the new venue to the existing `state.venues` list **before** calling load(), ensuring state persists even if the provider is rebuilt before the next drawer opens.

**File:** `lib/features/contacts/venues_controller.dart`

**Current implementation** (lines 92-102):

```dart
Future<Venue?> create({
  required String bandId,
  required Map<String, dynamic> data,
}) async {
  try {
    final venue = await _repository.createVenue(bandId: bandId, data: data);
    await load(bandId);  // ← Only refetches, doesn't optimistically update
    return venue;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[VenuesController] Error creating venue: $e');
    }
    return null;
  }
}
```

**Corrected implementation:**

```dart
Future<Venue?> create({
  required String bandId,
  required Map<String, dynamic> data,
}) async {
  try {
    final venue = await _repository.createVenue(bandId: bandId, data: data);

    // Optimistically append new venue to state immediately (before refetch)
    // This ensures the venue is available for subsequent drawers even if
    // the provider is rebuilt before load() completes
    state = state.copyWith(
      venues: [...state.venues, venue],
    );

    // Background refetch to sync with Supabase (in case of concurrent modifications)
    // Use unawaited to avoid blocking the return
    unawaited(load(bandId));

    return venue;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[VenuesController] Error creating venue: $e');
    }
    return null;
  }
}
```

**Rationale:**

1. **Immediate availability:** New venue is added to state synchronously, so it's available for smart-matching in subsequent drawers immediately
2. **Survives rebuilds:** Even if the provider is rebuilt (resetting to empty state), the next drawer's `load()` call will fetch the venue from Supabase (cache or fresh), so the race condition window is eliminated
3. **Background sync:** `unawaited(load(bandId))` still refetches in the background to handle edge cases (concurrent modifications by other users, Supabase replication lag), but doesn't block the return
4. **No breaking changes:** Same method signature, same return value, same error handling

**Import required:**

```dart
import 'dart:async' show unawaited;
```

---

### Secondary Fix: Ensure Initial Load Completes Before User Can Type

**Problem:** The drawer's `initState()` schedules `load()` in a postFrameCallback without awaiting it, so the user can type before venues are loaded.

**Solution:** Show a loading state in the gig name field until venues are loaded, preventing premature typing.

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Add state variable** (line ~190):

```dart
bool _venuesLoaded = false;
```

**Update initState postFrameCallback** (line ~322):

```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  await ref.read(venuesProvider.notifier).load(widget.bandId);
  if (mounted) {
    setState(() => _venuesLoaded = true);
  }
  ref.read(membersProvider.notifier).loadMembers(widget.bandId);
  _loadLocationSuggestions();
  // ... rest of postFrameCallback
});
```

**Update gig name field** (pass `_venuesLoaded` to `GigFormFields`):

```dart
GigFormFields(
  // ... existing params
  enabled: !isSaving && _venuesLoaded,  // ← Disable field until venues loaded
)
```

**Rationale:**

- Drawer opens with gig name field disabled (grayed out with loading indicator or hint text)
- Once `load()` completes, field enables
- User cannot type until venues are loaded, eliminating race condition entirely
- UX: slight delay (typically <500ms) before user can interact, but ensures auto-fill always works

**Tradeoff:** This approach adds friction (user must wait before typing). The primary fix (optimistic state update) is the preferred solution because it doesn't degrade UX. This secondary fix is **optional** as a belt-and-suspenders safeguard.

---

## Updated Files Impact

### Files to Modify (Revised)

| File                                                   | What Changes                                                                                                                                                                                                                              | Status                                                 |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `lib/features/events/widgets/event_editor_drawer.dart` | ✓ Already modified (Tasks 1-7) — State field lifecycle, smart matching, dedup query                                                                                                                                                       | Complete (original scope)                              |
| `lib/features/events/widgets/gig_form_fields.dart`     | ✓ Already modified (Tasks 8-9) — State field UI                                                                                                                                                                                           | Complete (original scope)                              |
| **`lib/features/contacts/venues_controller.dart`**     | **Task 14:** Modify `create()` method to optimistically update state before calling `load()`, add `import 'dart:async' show unawaited;`<br>**Task 17 (TEMPORARY):** Add diagnostic logging in `create()` after optimistic update          | **Required (bug fix + diagnostic)**                    |
| `lib/features/events/widgets/event_editor_drawer.dart` | **Task 16 (OPTIONAL):** Add `_venuesLoaded` state variable, await `load()` in postFrameCallback, disable gig name field until loaded<br>**Task 17 (TEMPORARY):** Add diagnostic logging in `_fetchGigNameSuggestions()` and `initState()` | Optional (Task 16) + **Required (Task 17 diagnostic)** |

**Note on Task 17:** These are temporary diagnostic changes only. All `debugPrint()` statements marked with `TEMPORARY DIAGNOSTIC` comment must be removed once root cause is confirmed.

### Files Previously Off-Limits (Now Modified Due to Bug)

| File                                           | Original Reason                                                                               | Why Now Needed                                                                                                                                                                                                                             |
| ---------------------------------------------- | --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/contacts/venues_controller.dart` | "Existing `create()` method signature already handles arbitrary data map — no changes needed" | **Root cause lives here:** The `create()` method's reliance on `await load()` to propagate state doesn't handle provider rebuilds. Must add optimistic state update to ensure newly created venues are immediately available for matching. |

**Justification for scope expansion:**

The original architect plan assumed that calling `await load(bandId)` in `create()` would be sufficient to update the venuesProvider state for subsequent drawers. This assumption was correct for the happy path (no provider rebuilds), but failed in production due to provider lifecycle behavior. The fix must touch `venues_controller.dart` because that's where the state propagation gap exists.

This is **not** a workaround — it's the proper fix. Riverpod best practices recommend optimistic updates for exactly this reason: to ensure state persists across provider rebuilds and navigation events.

---

## New Engineer Tasks (Addendum)

**Task 14:** [VenuesNotifier] Add Optimistic State Update in create()

**File:** `lib/features/contacts/venues_controller.dart`

1. Add import at top of file (line ~1):

   ```dart
   import 'dart:async' show unawaited;
   ```

2. Locate `create()` method (line ~92)

3. Replace method implementation with:

   ```dart
   Future<Venue?> create({
     required String bandId,
     required Map<String, dynamic> data,
   }) async {
     try {
       final venue = await _repository.createVenue(bandId: bandId, data: data);

       // Optimistically append new venue to state immediately
       state = state.copyWith(
         venues: [...state.venues, venue],
       );

       // Background refetch to sync with Supabase
       unawaited(load(bandId));

       return venue;
     } catch (e) {
       if (kDebugMode) {
         debugPrint('[VenuesController] Error creating venue: $e');
       }
       return null;
     }
   }
   ```

4. Run `flutter analyze` → verify 0 errors

---

**Task 15:** [Manual Test] Verify Optimistic Update Fixes Auto-Fill

**Test Scenario:**

1. **Clean state:** Clear app data or use fresh band with no venues
2. **First gig:** Create gig with Name = "Test Venue", City = "Chicago", Address = "123 Main St", State = "IL" → Save
3. **Verify venue created:** Navigate to Contacts → Venues → confirm "Test Venue" appears
4. **Second gig:** Navigate back to Calendar → Add Gig
5. **Type venue name:** Type "Test" → should see "Test Venue" in autocomplete suggestions
6. **Continue typing:** Type "Venue" (full match: "Test Venue")
7. **Expected:** City auto-fills to "Chicago, IL", Address auto-fills to "123 Main St", State auto-fills to "IL" **immediately** as soon as full name is typed
8. **Verify link:** Save gig → check Contacts → Venues → confirm only ONE "Test Venue" entry (no duplicate)
9. **Verify both gigs linked:** Check both gigs in Calendar → both should show same city/address (linked to same venue)

**Pass criteria:** Auto-fill happens in step 7 without manual re-entry. If user must manually type city/address/state, test **fails**.

---

**Task 16:** [Optional] Add Secondary Fix — Disable Gig Name Field Until Venues Loaded

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**⚠️ Only implement if Task 14 (primary fix) is insufficient or if belt-and-suspenders safety is desired.**

1. Add state variable (line ~190):

   ```dart
   bool _venuesLoaded = false;
   ```

2. Update postFrameCallback (line ~322) to await load:

   ```dart
   WidgetsBinding.instance.addPostFrameCallback((_) async {
     // Wait for venues to load before enabling gig name field
     await ref.read(venuesProvider.notifier).load(widget.bandId);
     if (mounted) {
       setState(() => _venuesLoaded = true);
     }

     ref.read(membersProvider.notifier).loadMembers(widget.bandId);
     _loadLocationSuggestions();
     // ... rest of postFrameCallback
   });
   ```

3. Update call site where `GigFormFields` is created (line ~1958) to pass enabled state:

   ```dart
   gigNameFocusNode: _gigNameFocusNode,
   gigNameSuggestions: _gigNameSuggestions,
   onGigNameChanged: _fetchGigNameSuggestions,
   enabled: !_isSaving && _venuesLoaded,  // ← Add this
   ```

4. Update `GigFormFields` constructor (file: `gig_form_fields.dart`) to accept enabled param:

   ```dart
   required this.enabled,
   ```

5. Use enabled param in gig name TextField widget:
   ```dart
   TextField(
     controller: controller,
     focusNode: focusNode,
     enabled: enabled,  // ← Add this
     // ... rest of TextField
   )
   ```

**Tradeoff:** Adds 200-500ms delay before user can type. Only implement if optimistic update (Task 14) proves insufficient in production testing.

---

## Task 15 Manual Test Result — Bug Still Reproduces

**Date:** 2026-07-10

**Test performed by:** Tony

**Result:** Task 14 (optimistic state update) **did NOT fix the issue**. After implementing the optimistic update, Tony created a new venue via gig 1 (confirmed it appeared in Contacts → Venues), then created a second gig and typed the same venue name. Address/city/state still did not auto-fill.

**Conclusion:** The MEDIUM-confidence provider-timing hypothesis was incomplete or incorrect. The root cause is not (solely) about timing or empty provider state.

**Stop condition reached:** As documented in Root Cause Analysis section, static code analysis has reached its ceiling. Runtime diagnostic data is required to progress.

---

**Task 17:** [TEMPORARY DIAGNOSTIC] Add Runtime Logging to Identify Actual Root Cause

**⚠️ TEMPORARY INSTRUMENTATION ONLY** — These debug logs are for diagnosis, not permanent code. Must be removed once root cause is confirmed and fixed.

**Purpose:** Capture real runtime data showing:

- Whether `_fetchGigNameSuggestions()` is being called when user types
- What data it's reading from `venuesProvider.state.venues`
- Whether the name-matching logic is executing correctly
- Whether the optimistic state update in `create()` is actually taking effect

### Instrumentation Points

**File 1:** `lib/features/events/widgets/event_editor_drawer.dart`

**Location:** Inside `_fetchGigNameSuggestions()` method, immediately after reading venues from provider (line ~710)

**Add:**

```dart
void _fetchGigNameSuggestions(String query) {
  // Clear suggestions if query is too short
  if (query.length < 2) {
    if (_gigNameSuggestions.isNotEmpty) {
      setState(() => _gigNameSuggestions = []);
    }
    // Clear venue link if user is editing the name
    if (_selectedVenueId != null) {
      _selectedVenueId = null;
    }
    return;
  }

  final venues = ref.read(venuesProvider).venues;
  final queryLower = query.toLowerCase();

  // TEMPORARY DIAGNOSTIC: Log what we're reading from provider
  if (kDebugMode) {
    debugPrint('[GigNameAutocomplete] Query: "$query" | Venues in state: ${venues.length} | Query lowercase: "$queryLower"');
    if (venues.isNotEmpty) {
      debugPrint('[GigNameAutocomplete] First venue: "${venues.first.name}" (id: ${venues.first.id})');
    }
  }

  final suggestions = venues
      .where((v) => v.name.toLowerCase().contains(queryLower))
      .map((v) => v.name)
      .take(15)
      .toList();

  // Smart matching: single-match auto-fills immediately, multi-match requires city to disambiguate
  final nameMatches =
      venues.where((v) => v.name.toLowerCase() == queryLower).toList();

  // TEMPORARY DIAGNOSTIC: Log matching results
  if (kDebugMode) {
    debugPrint('[GigNameAutocomplete] Name matches found: ${nameMatches.length}');
    for (final match in nameMatches) {
      debugPrint('[GigNameAutocomplete]   - "${match.name}" (city: ${match.city}, id: ${match.id})');
    }
  }

  // ... rest of method unchanged
```

**Expected output on second gig creation (if optimistic update worked):**

```
[GigNameAutocomplete] Query: "T" | Venues in state: 1 | Query lowercase: "t"
[GigNameAutocomplete] First venue: "Test Venue" (id: abc-123)
[GigNameAutocomplete] Name matches found: 0
[GigNameAutocomplete] Query: "Te" | Venues in state: 1 | Query lowercase: "te"
[GigNameAutocomplete] First venue: "Test Venue" (id: abc-123)
[GigNameAutocomplete] Name matches found: 0
[GigNameAutocomplete] Query: "Test Venue" | Venues in state: 1 | Query lowercase: "test venue"
[GigNameAutocomplete] First venue: "Test Venue" (id: abc-123)
[GigNameAutocomplete] Name matches found: 1
[GigNameAutocomplete]   - "Test Venue" (city: Chicago, id: abc-123)
```

**If venues list is empty:**

```
[GigNameAutocomplete] Query: "T" | Venues in state: 0 | Query lowercase: "t"
```

**If string comparison fails:**

```
[GigNameAutocomplete] Query: "Test Venue" | Venues in state: 1 | Query lowercase: "test venue"
[GigNameAutocomplete] First venue: "Test Venue " (id: abc-123)  // ← Note trailing space
[GigNameAutocomplete] Name matches found: 0  // ← Comparison failed due to whitespace
```

---

**File 2:** `lib/features/contacts/venues_controller.dart`

**Location:** Inside `create()` method, immediately after the optimistic state update (after Task 14's changes)

**Add:**

```dart
Future<Venue?> create({
  required String bandId,
  required Map<String, dynamic> data,
}) async {
  try {
    final venue = await _repository.createVenue(bandId: bandId, data: data);

    // Optimistically append new venue to state immediately
    state = state.copyWith(
      venues: [...state.venues, venue],
    );

    // TEMPORARY DIAGNOSTIC: Confirm optimistic update executed
    if (kDebugMode) {
      debugPrint('[VenuesController] Optimistically added venue: "${venue.name}" (id: ${venue.id})');
      debugPrint('[VenuesController] Total venues in state after update: ${state.venues.length}');
      if (state.venues.length <= 5) {
        for (final v in state.venues) {
          debugPrint('[VenuesController]   - "${v.name}" (id: ${v.id})');
        }
      }
    }

    // Background refetch to sync with Supabase
    unawaited(load(bandId));

    return venue;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[VenuesController] Error creating venue: $e');
    }
    return null;
  }
}
```

**Expected output after first gig saves:**

```
[VenuesController] Optimistically added venue: "Test Venue" (id: abc-123)
[VenuesController] Total venues in state after update: 1
[VenuesController]   - "Test Venue" (id: abc-123)
```

**If optimistic update isn't executing (bug in Task 14 implementation):**

```
[VenuesController] Error creating venue: <some error>
```

or no output at all.

---

**File 3:** `lib/features/events/widgets/event_editor_drawer.dart` (same file as File 1)

**Location:** Inside `initState()`, in the postFrameCallback where `venuesProvider.notifier).load()` is called (line ~322)

**Add:**

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  ref.read(membersProvider.notifier).loadMembers(widget.bandId);

  // TEMPORARY DIAGNOSTIC: Log venues state before and after load
  if (kDebugMode) {
    final beforeLoad = ref.read(venuesProvider).venues;
    debugPrint('[EventEditorDrawer] initState postFrameCallback - Venues before load(): ${beforeLoad.length}');
  }

  ref.read(venuesProvider.notifier).load(widget.bandId);
  _loadLocationSuggestions();
  // ... rest of postFrameCallback unchanged
```

**Expected output when opening second gig drawer (if optimistic update persisted):**

```
[EventEditorDrawer] initState postFrameCallback - Venues before load(): 1
```

**If state was reset between gigs:**

```
[EventEditorDrawer] initState postFrameCallback - Venues before load(): 0
```

---

### Additional Verification (Code Review, No Changes Required)

**Task 17a:** Re-verify `_fetchGigNameSuggestions()` is wired to fire on every keystroke

**File:** `lib/features/events/widgets/gig_form_fields.dart`

**Check:** Line ~381 in `_buildGigNameAutocomplete()` → `optionsBuilder` callback

**Confirm:**

```dart
optionsBuilder: (TextEditingValue textEditingValue) {
  onGigNameChanged(textEditingValue.text);  // ← Fires on every keystroke
  if (textEditingValue.text.length < 2) {
    return const Iterable<String>.empty();
  }
  return gigNameSuggestions;
},
```

This should be calling `onGigNameChanged` (which is `_fetchGigNameSuggestions`) on every keystroke, with no debouncing.

**Potential issue:** If `RawAutocomplete` itself is debouncing or batching calls to `optionsBuilder`, the function might not fire on every keystroke as expected. The diagnostic logs will reveal if this is happening.

---

**Task 17b:** Verify string comparison isn't failing due to whitespace or case

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Check:** Line ~720 in `_fetchGigNameSuggestions()` → name matching logic

**Confirm:**

```dart
final nameMatches =
    venues.where((v) => v.name.toLowerCase() == queryLower).toList();
```

**Potential issues:**

1. **Stored venue name has trailing/leading whitespace:** `"Test Venue "` (from Supabase) vs `"test venue"` (typed) → comparison fails
2. **Query variable doesn't match what user typed:** If `query` param is transformed somewhere before being lowercased
3. **Venue model's `name` property reads from wrong field:** Unlikely, but the diagnostic logs will show exact string values

The diagnostic logs added in Task 17 (File 1) will show both the raw venue names and the queryLower value, making any whitespace/case issues immediately visible.

---

### Test Instructions for Tony

1. **Clear app state:** Reset to clean slate (new band or clear app data)
2. **Open Xcode console or terminal** to view `debugPrint()` output
3. **Create first gig:**
   - Name: "Test Venue"
   - City: "Chicago"
   - Address: "123 Main St"
   - State: "IL"
   - Save
4. **Check console for:** `[VenuesController] Optimistically added venue: "Test Venue"` with count = 1
5. **Navigate to Contacts → Venues** and confirm venue appears
6. **Navigate back to Calendar → Add Gig (second gig)**
7. **Check console for:** `[EventEditorDrawer] initState postFrameCallback - Venues before load(): X` (what's the count?)
8. **Start typing "Test Venue" slowly**, one keystroke at a time
9. **For each keystroke, check console for:**
   - `[GigNameAutocomplete] Query: "T"` (or "Te", "Tes", etc.)
   - `Venues in state: X` (what's the count?)
   - `Name matches found: X` (should be 0 until full name is typed, then 1)
10. **If auto-fill still doesn't work, copy ALL console output** from step 3 onwards and report back

**What the logs will reveal:**

| Console Output Pattern                           | Diagnosis                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------- |
| `Venues in state: 0` throughout                  | Optimistic update didn't persist; provider state was reset                |
| `Venues in state: 1` but `Name matches found: 0` | String comparison failing (whitespace or case issue)                      |
| No `[GigNameAutocomplete]` logs when typing      | `_fetchGigNameSuggestions()` not being called (wiring issue)              |
| `Venues in state: 1` and `Name matches found: 1` | Matching logic works, but auto-fill code after the match check is failing |

---

**Task 17 Cleanup:** Once root cause is confirmed, remove all diagnostic `debugPrint()` statements added in this task. Search for `TEMPORARY DIAGNOSTIC` comment to find them all.

---

## Regression Risk (Updated)

**Level: LOW → MEDIUM**

**Original assessment:** LOW (only 2 files modified, isolated to gig flow)

**Updated assessment:** MEDIUM (now 3 files modified, touches venue state management)

**New risks introduced by bug fix:**

1. **Optimistic update race condition:** If two users create the same venue simultaneously, both will optimistically add it to their local state, then both will refetch via `load()`. The refetch will sync with Supabase (showing only one venue), but there's a brief window where the UI might show duplicates. **Mitigation:** `load()` call overwrites state with authoritative Supabase data, so duplicates self-heal within ~500ms.

2. **Stale state if load() fails:** If the background `load(bandId)` call fails (network error, Supabase down), the optimistically added venue remains in state but may not match Supabase. **Mitigation:** Next navigation or drawer open will trigger another `load()` call, syncing state. User can still create/edit gigs with the venue in the meantime.

3. **Memory growth if many venues created:** Optimistic updates append to `state.venues` without removing stale entries. If a user creates 100 venues in a session, the list grows to 100+ items. **Mitigation:** `load()` refetch replaces entire list with authoritative data, so list size is bounded by actual venue count in Supabase, not by number of creates.

**Existing risks (unchanged):**

- No impact on rehearsals, setlists, members, auth flows
- State field is optional, no validation failures
- Dedup query is read-only and null-safe

---

## QA Re-Validation Required

**Areas requiring re-test after Task 14 (optimistic update):**

1. **Primary symptom (Task 15):** Create gig → verify venue appears in Contacts → create second gig → **type same venue name** → verify city/address/state auto-fill immediately
2. **Concurrent creates:** Two devices, same band → both create venue with same name+city at same time → verify no duplicate venues in Supabase after both saves complete
3. **Network failure during create:** Create venue → kill network before `load()` completes → verify venue still appears in autocomplete for subsequent gigs (optimistic state persists)
4. **Venue list consistency:** Create 5 venues in rapid succession → navigate to Contacts → Venues → verify all 5 appear, no duplicates, sorted correctly
5. **State persistence across navigation:** Create venue → navigate to Setlists tab → navigate back to Calendar → create gig → verify venue still appears in autocomplete (state didn't reset)

**All original QA test cases (POST-DEPLOY TEST 1-8) remain valid and must pass.**

---

---

# ADDENDUM 2 — Confirmed Root Cause from Runtime Evidence

## Date

2026-07-10

## Context

After implementing Task 14 (optimistic state update) and Task 17 (diagnostic logging), Tony ran the app with instrumentation in place and reproduced the bug. The runtime logs provide direct evidence that disproves the provider-timing hypothesis behind Tasks 14 and 17.

## Runtime Evidence

**Console output during bug reproduction:**

```
[EventEditorDrawer] initState postFrameCallback - Venues before load(): 2
[GigNameAutocomplete] Query: "ga" | Venues in state: 2 | ...
[GigNameAutocomplete] First venue: "Gallery Cabaret" (id: 35bf0765-...)
[GigNameAutocomplete] Query: "gal" | Venues in state: 2 | ...
[GigNameAutocomplete] Query: "gall" | Venues in state: 2 | ...
```

**Key observations:**

1. Provider state had **2 venues** from the start (not empty)
2. "Gallery Cabaret" was present in state and correctly returned in queries
3. Logs show queries for "ga", "gal", "gall" as user typed
4. **Logs never show a query for the complete venue name** — stops at "gall"
5. User behavior (confirmed): Tony selected "Gallery Cabaret" from the autocomplete dropdown suggestion list, rather than typing the full name manually

**Conclusion:** The provider-timing/race-condition theory behind Task 14 is **disproven**. Provider state was correctly populated the entire time. The bug is NOT about empty state or timing.

## Confirmed Root Cause

**Confidence Level: HIGH** (direct runtime evidence + code observation)

**Problem:** Autocomplete suggestion selection does not trigger the venue matching/auto-fill logic.

**How it works currently:**

1. User types "ga", "gal", "gall" → `_fetchGigNameSuggestions()` fires on each keystroke
2. Autocomplete dropdown shows "Gallery Cabaret" as a suggestion
3. User taps "Gallery Cabaret" from dropdown → `onSelected` callback fires
4. **`onSelected` only sets `nameController.text` to "Gallery Cabaret"** — does NOT call `_fetchGigNameSuggestions()`
5. Smart-matching logic never evaluates the complete venue name
6. `_selectedVenueId` never gets set
7. City, address, state never auto-fill

**Code Evidence:**

File: `lib/features/events/widgets/gig_form_fields.dart`, lines 387-392:

```dart
RawAutocomplete<String>(
  // ...
  onSelected: (String selection) {
    nameController.text = selection;
    nameController.selection = TextSelection.collapsed(
      offset: selection.length,
    );
  },
  // ...
)
```

**What's missing:** The `onSelected` callback does not call `onGigNameChanged(selection)`, which is the callback that triggers `_fetchGigNameSuggestions()` in the parent `event_editor_drawer.dart`.

**Why keystroke-driven input works (partially):**

- The `optionsBuilder` callback (lines 380-385) calls `onGigNameChanged(textEditingValue.text)` on every keystroke
- If user types the **complete** venue name letter-by-letter, the smart-matching logic eventually fires and auto-fill works
- But selecting from dropdown bypasses this entirely

**Why programmatic text assignment doesn't trigger `onChanged`:**

- Setting `nameController.text = selection` programmatically does NOT fire the TextField's `onChanged` callback
- `onChanged` only fires for user-initiated typing events
- This is standard Flutter TextField behavior

## Corrected Solution

### Real Fix: Trigger Matching Logic on Autocomplete Selection

**Problem:** When user selects a venue from autocomplete dropdown, the selection sets the text field value but doesn't invoke the smart-matching logic that would set `_selectedVenueId` and auto-fill city/address/state.

**Solution:** Add `onGigNameChanged(selection)` call to the `onSelected` callback, ensuring the matching logic fires when a suggestion is selected.

**File:** `lib/features/events/widgets/gig_form_fields.dart`

**Current implementation** (lines 387-392):

```dart
onSelected: (String selection) {
  nameController.text = selection;
  nameController.selection = TextSelection.collapsed(
    offset: selection.length,
  );
},
```

**Corrected implementation:**

```dart
onSelected: (String selection) {
  nameController.text = selection;
  nameController.selection = TextSelection.collapsed(
    offset: selection.length,
  );
  // Trigger matching logic to set _selectedVenueId and auto-fill city/address/state
  onGigNameChanged(selection);
},
```

**Rationale:**

1. **Reuses existing logic:** Calls the same `onGigNameChanged` callback (which is `_fetchGigNameSuggestions()`) that already handles keystroke-driven input
2. **No duplication:** Doesn't duplicate the smart-matching algorithm
3. **Consistent behavior:** Selecting "Gallery Cabaret" from dropdown now behaves identically to typing "Gallery Cabaret" letter-by-letter
4. **Single-line change:** Minimal diff, easy to review and test
5. **No side effects:** `_fetchGigNameSuggestions()` is idempotent — calling it with the selected venue name is safe

### Verification

**Manual test:**

1. Create a venue: Name = "Test Venue", City = "Chicago", Address = "123 Main St", State = "IL"
2. Create a new gig
3. Type "Test" in venue name field → dropdown shows "Test Venue"
4. **Tap "Test Venue" from dropdown** (do NOT type the full name manually)
5. **Expected:** City auto-fills to "Chicago, IL", Address auto-fills to "123 Main St", State auto-fills to "IL" immediately after selection
6. Save gig → verify it links to existing venue (no duplicate created)

**Pass criteria:** Auto-fill happens in step 5 when selecting from dropdown, not just when typing full name.

## Disposition of Tasks 14 and 17

### Task 14: Optimistic State Update

**Original premise:** Provider state might be empty when user types, causing matching logic to fail.

**Runtime evidence:** Provider state was NOT empty — it had 2 venues including the target venue throughout the entire flow.

**Verdict:** **The optimistic update does not fix the bug.** The bug occurs even when provider state is correctly populated.

**Recommendation: Keep Task 14 as a defensive improvement.**

**Reasoning:**

1. **Generically correct pattern:** Riverpod best practices recommend optimistic updates for immediate UI feedback and resilience against provider rebuilds
2. **No downside:** The change is small, well-tested (QA-approved), and has no performance impact
3. **Defensive benefit:** Even though it doesn't fix THIS bug, it prevents a different class of bugs (stale state after provider rebuild, timing races on slow networks)
4. **Cleaner than revert:** Reverting would create noise in git history and require re-QA of the revert itself
5. **Already merged into main:** If this has been deployed, reverting adds risk for no material benefit

**If NOT yet merged:** Consider reverting for a cleaner diff focused solely on the real fix (autocomplete selection handler). Document the revert as "optimistic update was a red herring; actual fix is in onSelected callback."

**If already merged:** Keep it. Document in this addendum that it was based on incorrect diagnosis but is a reasonable defensive improvement with no harm.

### Task 17: Diagnostic Logging

**Purpose:** Temporary instrumentation to identify root cause.

**Verdict:** **Job done. Must be removed.**

**Reasoning:**

1. **Explicitly temporary:** All logging statements are marked with `// TEMPORARY DIAGNOSTIC` comment
2. **Purpose complete:** Logging successfully revealed that provider state was NOT the issue, leading to discovery of the real root cause (autocomplete selection handler)
3. **Production noise:** Debug logging in hot paths (every keystroke) is not appropriate for production code
4. **Easy to remove:** All statements marked with `TEMPORARY DIAGNOSTIC` comment for easy search-and-remove

**Action required:** Create cleanup task to remove all Task 17 diagnostic logging.

## New Engineer Tasks

**Task 18:** [REAL FIX] Trigger Matching Logic on Autocomplete Selection

**File:** `lib/features/events/widgets/gig_form_fields.dart`

1. Locate `_buildGigNameAutocomplete()` method (line ~362)
2. Find the `RawAutocomplete` widget's `onSelected` callback (line ~387)
3. Replace the `onSelected` implementation:

   ```dart
   onSelected: (String selection) {
     nameController.text = selection;
     nameController.selection = TextSelection.collapsed(
       offset: selection.length,
     );
     // Trigger matching logic to set _selectedVenueId and auto-fill city/address/state
     onGigNameChanged(selection);
   },
   ```

4. Run `flutter analyze` → verify 0 errors

**Verification:**

- Create a venue with full details (name, city, address, state)
- Create a new gig
- Type partial venue name (e.g., "Gal" for "Gallery Cabaret")
- **Select from dropdown** (do not type full name)
- Verify city, address, state auto-fill immediately after selection
- Save gig → verify it links to existing venue (no duplicate)

---

**Task 19:** [CLEANUP] Remove Task 17 Diagnostic Logging

**Files affected:**

- `lib/features/events/widgets/event_editor_drawer.dart` (2 locations)
- `lib/features/contacts/venues_controller.dart` (1 location)

**Instructions:**

1. Search for `TEMPORARY DIAGNOSTIC` comment in all files
2. Remove all `debugPrint()` statements and associated `if (kDebugMode)` blocks added in Task 17
3. Run `flutter analyze` → verify 0 errors
4. Run `git diff` → verify no functional code removed, only logging statements

**Expected removals:**

- `event_editor_drawer.dart`, line ~319: initState postFrameCallback logging
- `event_editor_drawer.dart`, line ~719: `_fetchGigNameSuggestions()` logging (2 blocks)
- `venues_controller.dart`, line ~103: `create()` method logging

**Verification:**

- Search codebase for `TEMPORARY DIAGNOSTIC` → should return 0 results
- Run app → verify no `[GigNameAutocomplete]` or `[VenuesController] Optimistically added venue` logs appear in console during normal gig creation

---

**Task 20:** [OPTIONAL] Revert Task 14 Optimistic Update (if desired for cleaner diff)

**File:** `lib/features/contacts/venues_controller.dart`

**Only perform if:**

- This feature has NOT been merged into main yet
- You prefer a minimal diff showing only the real fix
- QA is available to re-test the revert

**Instructions:**

1. Remove `import 'dart:async' show unawaited;` from top of file
2. Restore `create()` method to original implementation:

   ```dart
   Future<Venue?> create({
     required String bandId,
     required Map<String, dynamic> data,
   }) async {
     try {
       final venue = await _repository.createVenue(bandId: bandId, data: data);
       await load(bandId);
       return venue;
     } catch (e) {
       if (kDebugMode) {
         debugPrint('[VenuesController] Error creating venue: $e');
       }
       return null;
     }
   }
   ```

3. Run `flutter analyze` → verify 0 errors
4. Document in commit message: "Revert Task 14 optimistic update — was red herring, real fix is autocomplete selection handler"

**If NOT reverting (recommended if already merged):** Update `ENGINEER_REPORT.md` to note that Task 14 remains in place as a defensive improvement despite not fixing the reported bug.

---

## Updated Verification Plan

### Tier 2 — Post-deployment (Manual Testing)

**PRIMARY TEST (Task 18 Fix Verification):**

**Test: Autocomplete Selection Triggers Auto-Fill**

1. Precondition: Create a venue in Contacts → Venues with Name = "Gallery Cabaret", City = "Chicago", Address = "804 S Wabash Ave", State = "IL"
2. Action: Navigate to Add Gig, type "Gal" in Name field (partial match)
3. Expected: Autocomplete dropdown shows "Gallery Cabaret" suggestion
4. Action: **Tap "Gallery Cabaret" from dropdown** (do NOT finish typing the full name)
5. **Expected:** City auto-fills to "Chicago, IL", Address auto-fills to "804 S Wabash Ave", State auto-fills to "IL" **immediately** after dropdown selection
6. Action: Save gig
7. Expected: Gig is saved with `venue_id` linked to existing "Gallery Cabaret" venue (verify no duplicate created)

**Pass criteria:** Auto-fill happens in step 5 when selecting from dropdown, not just when typing full name letter-by-letter.

**SECONDARY TEST (Original Issue Still Fixed):**

**Test: Typing Full Name Still Triggers Auto-Fill**

1. Use same precondition (venue "Gallery Cabaret" exists)
2. Action: Navigate to Add Gig, type "Gallery Cabaret" **letter-by-letter** (do NOT use dropdown)
3. Expected: City, address, state auto-fill when full name is typed
4. Action: Save gig
5. Expected: Gig links to existing venue (no duplicate)

**Pass criteria:** Auto-fill works whether user selects from dropdown OR types full name manually.

**All original POST-DEPLOY TEST cases (1-8) remain valid and must pass.**

---

## Updated Regression Risk

**Level: MEDIUM → LOW**

**Original assessment (with Task 14):** MEDIUM (3 files modified, touches venue state management)

**Updated assessment (with Task 18 real fix):** LOW (2 files modified for real fix: gig_form_fields.dart + cleanup in event_editor_drawer.dart and venues_controller.dart)

**Risks introduced by Task 18 (real fix):**

1. **Duplicate matching calls:** If `onSelected` fires AND the TextField's `onChanged` somehow also fires for the same selection, `_fetchGigNameSuggestions()` could run twice for the same venue name. **Mitigation:** The function is idempotent — running it twice with the same input produces the same result (sets `_selectedVenueId` to same value, auto-fills same fields). No user-visible impact.

2. **Suggestion list re-calculation:** Calling `onGigNameChanged(selection)` will trigger `_fetchGigNameSuggestions()` which recalculates the suggestions list. If the dropdown is still open, this could cause a visual flicker. **Mitigation:** The dropdown typically closes immediately after selection in standard `RawAutocomplete` behavior. Even if it stays open momentarily, the suggestions list for "Gallery Cabaret" will just show "Gallery Cabaret" again — no functional impact.

**Risks mitigated:**

- Only 1 file changed for real fix (gig_form_fields.dart), not 3 files
- No state management changes (if Task 14 is reverted)
- No timing/race condition concerns
- No database query changes
- Change is localized to one callback, easy to review and test

**Existing risks (unchanged):**

- No impact on rehearsals, setlists, members, auth flows
- State field is optional, no validation failures
- Dedup query is read-only and null-safe

---

## Summary

**What we learned:**

- Provider state was never the issue — it was correctly populated throughout
- The bug occurs because autocomplete selection bypasses the matching logic
- Diagnostic logging successfully revealed the real problem (incomplete query logs showing user selected from dropdown)

**Real fix:**

- One-line change in `gig_form_fields.dart`: add `onGigNameChanged(selection);` to `onSelected` callback

**Task 14 disposition:**

- Keep as defensive improvement (if already merged) OR revert for cleaner diff (if not yet merged)

**Task 17 disposition:**

- Remove all diagnostic logging (Task 19)

**Confidence level:**

- **HIGH** — Runtime evidence directly shows the issue, code inspection confirms the missing trigger, fix is straightforward
