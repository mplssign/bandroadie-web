# Architect Plan

## Feature Slug
`gig-address-field`

## Branch
`feat/gig-address-field`

---

## Problem Summary

The Edit Gig form captures only a city field. Users need to record a street address (venue address) alongside the city so that the Navigate button can open maps with a precise location rather than just a venue name + city string. The address field does not exist in the database, model, or form data.

---

## Existing System Analysis

### Current gig location data flow

```
DB gigs.location (TEXT, NOT NULL)
  → Gig.fromJson: json['location']
  → EventFormData.fromGig: location: gig.location
  → EventEditorDrawer._locationController
  → GigFormFields._buildGigCityAutocomplete (label: "City")
  → EventsRepository.createGig / updateGig: 'location': formData.location
```

**Key observations:**
- The database column is named `location` but the UI labels it "City". There is no separate `city` column on `gigs`.
- `_fetchGigCitySuggestions` in `event_editor_drawer.dart` queries `gigs.city` (line 740), but no `city` column exists — this silently fails in the catch block. Pre-existing bug; **out of scope**.
- `GigFormFields.buildCityAutocomplete(context)` is the public method called from `EventEditorDrawer.build()` at line 2155.
- `ViewGigDrawer._openNavigation` (line 54): `Uri.encodeComponent('${gig.name} ${gig.location}')`.
- `get_band_full_state` RPC uses `to_jsonb(g.*)` — new columns are included automatically, **no RPC update needed**.
- `GigRepository._gigSelectClause` uses `'*'` — new column included automatically, **no change needed**.

### No existing `address` column

Confirmed: no migration adds an `address` column to `gigs`. The venues table has an `address` column (`20260410000000_contacts_venues_tables.sql:14`) — `gigs` does not.

---

## Proposed Solution

Minimal change set: add one nullable `TEXT` column to the DB, plumb it through the model and form data, wire a new address `TextField` into the form (left of city in a `Row`), persist it in the repository, and update the Navigate button in `ViewGigDrawer`.

---

## Database Impact

### Migration required
**File:** `supabase/migrations/20260701000000_add_address_to_gigs.sql`

```sql
-- Add optional street address to gigs table.
ALTER TABLE public.gigs
  ADD COLUMN address TEXT;
```

- Nullable: no default, no backfill required. Existing rows get NULL.
- No RLS impact: no new policy needed; existing band-scoped RLS covers the column.
- No RPC update needed: `get_band_full_state` uses `to_jsonb(g.*)`, which picks up new columns automatically.
- No index needed: address is not filtered on in queries.

**Migration policy: required**
**Edge function deploy: not required**

---

## Flutter Architecture Changes

Six Dart files change. No new providers, repositories, or controllers.

### 1. `lib/app/models/gig.dart`
Add `address` field:
```dart
final String? address;
```
- Constructor: add `this.address,`
- `fromJson`: `address: json['address'] as String?,`
- `toJson`: `'address': address,`

### 2. `lib/features/events/models/event_form_data.dart`
Add `address` field:
```dart
final String? address;
```
- Constructor: add `this.address,`
- `copyWith`: add `String? address,` param and `address: address ?? this.address,` in body
- `fromGig` factory: add `address: gig.address,`
- `fromRehearsal` factory: no change (rehearsals have no address)
- `fromCalendarEvent` factory: no change (fallback path, non-gig)

### 3. `lib/features/events/widgets/event_editor_drawer.dart`
**New state fields** (add alongside existing `_locationController` etc.):
```dart
final _addressController = TextEditingController();
final _addressHintController = FieldHintController();
final _gigAddressFocusNode = FocusNode();
```

**`initState` — edit-mode population block** (after `_locationController.text = data.location;`):
```dart
_addressController.text = data.address ?? '';
```

**`initState` — hint controller initialization** (after `_cityHintController.initialize`):
```dart
_addressHintController.initialize(
  hasInitialValue: isEdit && (_addressController.text.isNotEmpty),
);
```

**`initState` — listener** (alongside `_locationController.addListener`):
```dart
_addressController.addListener(_markDirty);
```

**`dispose()`** (alongside `_locationController.dispose()`):
```dart
_addressController.dispose();
_addressHintController.dispose();
_gigAddressFocusNode.dispose();
```

**`_buildFormData()`** (in the `EventFormData(...)` constructor call):
```dart
address: _addressController.text.trim().isEmpty
    ? null
    : _addressController.text.trim(),
```

**`_createGigFormFields()`** — pass three new params to `GigFormFields(...)`:
```dart
addressController: _addressController,
addressHintController: _addressHintController,
gigAddressFocusNode: _gigAddressFocusNode,
```

**`build()`** — change call from:
```dart
gigFormFields!.buildCityAutocomplete(context),
```
to:
```dart
gigFormFields!.buildAddressCityRow(context),
```

### 4. `lib/features/events/widgets/gig_form_fields.dart`
**New constructor params** (add alongside city autocomplete params):
```dart
required this.addressController,
required this.addressHintController,
required this.gigAddressFocusNode,
```
**New final fields:**
```dart
final TextEditingController addressController;
final FieldHintController addressHintController;
final FocusNode gigAddressFocusNode;
```

**New public method `buildAddressCityRow`** (replaces `buildCityAutocomplete` as the entry point — keep `buildCityAutocomplete` intact as a private implementation called from within the row):

```dart
Widget buildAddressCityRow(BuildContext context) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 6,
        child: _buildAddressField(context),
      ),
      const SizedBox(width: Spacing.space8),
      Expanded(
        flex: 4,
        child: _buildGigCityAutocomplete(context),
      ),
    ],
  );
}
```

**New private method `_buildAddressField`:**
```dart
Widget _buildAddressField(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Address',
        style: AppTextStyles.footnote.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: addressController,
        focusNode: gigAddressFocusNode,
        enabled: !isSaving,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        style: AppTextStyles.callout.copyWith(
          color: context.colors.textPrimary,
        ),
        onChanged: (_) => onMarkDirty(),
        decoration: InputDecoration(
          hintText: 'e.g., 123 Main St',
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
      FieldHint(
        text: 'Street address (optional)',
        controller: addressHintController,
      ),
    ],
  );
}
```

**`buildCityAutocomplete`** — rename internal reference:
- Keep the public `buildCityAutocomplete` method for backward compatibility (it is still referenced nowhere externally after the change — but leave it in place to be safe; its implementation is unchanged).
- `_buildGigCityAutocomplete` remains private and is called from `buildAddressCityRow`.

### 5. `lib/features/events/events_repository.dart`
**`createGig`** — add to `data` map (after `'load_in_time'`):
```dart
'address': formData.address,
```

**`updateGig`** — add to `data` map (after `'load_in_time'`):
```dart
'address': formData.address,
```

### 6. `lib/features/gigs/widgets/view_gig_drawer.dart`
**`_openNavigation`** — update query construction:
```dart
Future<void> _openNavigation(BuildContext context) async {
  final hasAddress =
      gig.address != null && gig.address!.trim().isNotEmpty;
  final query = Uri.encodeComponent(
    hasAddress
        ? '${gig.address} ${gig.location}'
        : '${gig.name} ${gig.location}',
  );
  final uri = Uri.parse('https://maps.google.com/?q=$query');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      showAppSnackBar(context, message: 'Could not open maps');
    }
  }
}
```

---

## Files to Create

| File | Justification |
|------|--------------|
| `supabase/migrations/20260701000000_add_address_to_gigs.sql` | Schema change: new nullable `address` column on gigs table |
| `docs/features/gig-address-field/ARCHITECT_PLAN.md` | This file |

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/app/models/gig.dart` | Add `address` field, fromJson, toJson |
| `lib/features/events/models/event_form_data.dart` | Add `address` field, copyWith, fromGig |
| `lib/features/events/widgets/event_editor_drawer.dart` | Add controller/focus/hint, wire address in initState/dispose/_buildFormData/_createGigFormFields/build |
| `lib/features/events/widgets/gig_form_fields.dart` | Add address params, add `buildAddressCityRow` and `_buildAddressField` methods |
| `lib/features/events/events_repository.dart` | Add `'address'` to createGig and updateGig data maps |
| `lib/features/gigs/widgets/view_gig_drawer.dart` | Update `_openNavigation` to prefer address+city when address present |

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/features/gigs/gig_repository.dart` | Select clause uses `*`; new column is included automatically |
| `supabase/migrations/20260313000000_get_band_full_state.sql` | RPC uses `to_jsonb(g.*)`; no update needed |
| All notification-related files | Unaffected |
| All rehearsal files | Unaffected |
| `lib/main.dart` | Init order must not change |

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | **affected** — new address field, model, form, persist |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — new form field renders on all platforms (simple TextField, no platform-specific code) |

---

## Regression Risk

**LOW**

- Only the gig create/edit form and the view drawer navigate action are affected.
- The new column is nullable; existing rows return NULL → `Gig.address` is null → address is never displayed or used in the navigate URL (falls back to existing behavior).
- `EventFormData.fromRehearsal` is untouched.
- The `_openNavigation` change is additive (falls back to existing `name + location` when address is null/empty).
- No RLS, RPC, or init-order changes.

---

## Engineer Task Breakdown

Execute in order. Each task is atomic and independently verifiable.

1. **[DB]** Create migration file `supabase/migrations/20260701000000_add_address_to_gigs.sql` with `ALTER TABLE public.gigs ADD COLUMN address TEXT;`

2. **[Model]** Update `lib/app/models/gig.dart`: add `final String? address;` field, add to constructor, fromJson, toJson.

3. **[FormData]** Update `lib/features/events/models/event_form_data.dart`: add `final String? address;` field, add to constructor, copyWith, and `fromGig` factory.

4. **[Repository]** Update `lib/features/events/events_repository.dart`: add `'address': formData.address,` to both `createGig` and `updateGig` data maps.

5. **[Widget - GigFormFields]** Update `lib/features/events/widgets/gig_form_fields.dart`:
   - Add three constructor params: `addressController`, `addressHintController`, `gigAddressFocusNode`
   - Add corresponding `final` fields
   - Add `_buildAddressField(BuildContext context)` private method
   - Add `buildAddressCityRow(BuildContext context)` public method

6. **[Widget - EventEditorDrawer]** Update `lib/features/events/widgets/event_editor_drawer.dart`:
   - Add `_addressController`, `_addressHintController`, `_gigAddressFocusNode` declarations
   - Populate address in initState edit-mode block
   - Initialize `_addressHintController` in initState
   - Add `_addressController.addListener(_markDirty);`
   - Dispose all three in `dispose()`
   - Add `address:` to `_buildFormData()`
   - Pass three new params in `_createGigFormFields()`
   - Change `buildCityAutocomplete` call to `buildAddressCityRow` in `build()`

7. **[ViewGigDrawer]** Update `lib/features/gigs/widgets/view_gig_drawer.dart`: update `_openNavigation` as described.

8. **[Analysis]** Run `flutter analyze` — must report 0 errors, 0 warnings.

---

## Verification Plan

### Tier 1 — Pre-deployment (run before `supabase db push`)

No server-side logic is changed. The only Tier 1 check is migration syntax.

```sql
-- PRE-DEPLOY TEST 1: Verify migration SQL is syntactically valid
-- (Run in a Supabase SQL editor on a branch DB or local instance before pushing to prod)
-- This test is informational — can be verified by inspecting the migration file directly.
-- The column is nullable TEXT with no default. Verify:
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'gigs'
  AND column_name = 'address';
-- Expected: 0 rows (column does not exist yet — confirms pre-deploy state)
```

### Tier 2 — Post-deployment (run after `supabase db push`)

```sql
-- POST-DEPLOY TEST 1: Confirm address column exists with correct type
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'gigs'
  AND column_name = 'address';
-- Expected: 1 row: address | text | YES

-- POST-DEPLOY TEST 2: Confirm existing rows default to NULL (no data loss)
SELECT count(*) AS rows_with_address
FROM public.gigs
WHERE address IS NOT NULL;
-- Expected: 0 (all existing rows should have NULL address)

-- POST-DEPLOY TEST 3: Confirm write/read round-trip
DO $$
DECLARE
  test_gig_id UUID;
BEGIN
  -- Find any existing gig to test with (read-only + transactional update)
  SELECT id INTO test_gig_id FROM public.gigs LIMIT 1;
  IF test_gig_id IS NULL THEN
    RAISE NOTICE 'No gigs in DB — skipping round-trip test';
    RETURN;
  END IF;

  -- Write a test address
  UPDATE public.gigs SET address = '__test_address__' WHERE id = test_gig_id;

  -- Verify it was written
  ASSERT (SELECT address FROM public.gigs WHERE id = test_gig_id) = '__test_address__',
    'Address write failed';

  -- Restore NULL
  UPDATE public.gigs SET address = NULL WHERE id = test_gig_id;

  -- Verify restore
  ASSERT (SELECT address FROM public.gigs WHERE id = test_gig_id) IS NULL,
    'Address restore failed';

  RAISE NOTICE 'POST-DEPLOY TEST 3 PASSED';
END;
$$;
```

---

## QA Regression Areas

1. **Create gig — address + city round-trip**: Create a new gig with both address and city filled in. Save. Open the gig in ViewGigDrawer. Tap Navigate. Confirm maps opens with the address + city query string (not the name + city fallback).

2. **Create gig — address empty, city filled**: Leave address blank, fill city. Save. Navigate button must open `name + city` (existing fallback).

3. **Edit gig — address loads back**: Edit an existing gig that already has an address. Confirm the address field pre-populates correctly. Update the address. Save. Open ViewGigDrawer. Confirm Navigate uses the updated address.

4. **Edit gig — no address set**: Edit an existing gig with no address (migrated data). Confirm address field is empty. City field pre-populates as before. No regression in city behavior.

5. **Form layout**: Confirm address field appears on the left (~60%) and city on the right (~40%) in the same row, consistent with existing form field styling.

6. **Rehearsal form unaffected**: Open the rehearsal form. Confirm the location field is unchanged and no address field appears.

7. **Block-out form unaffected**: Open the block-out form. Confirm no regressions.

8. **`flutter analyze` passes**: 0 errors, 0 warnings after all changes.

---

## Dirty Tree Note

At plan-write time, the working tree is on branch `feat/view-gig-drawer-polish` with uncommitted changes to:
- `lib/app/models/gig.dart` (formattedPay fix)
- `lib/features/calendar/calendar_screen.dart`
- `lib/features/calendar/calendar_tab_content.dart`
- `lib/features/financials/financial_entry_repository.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/home/home_tab_content.dart`

These belong to the `view-gig-drawer-polish` feature. The Engineer must NOT commit these as part of this feature. The Engineer should be aware that `feat/gig-address-field` is branched from `main` — these unstaged changes from the other feature may be carried into the working tree but must not be staged or committed.

---

## Out of Scope

- `_fetchGigCitySuggestions` queries `gigs.city` (non-existent column, silently fails) — pre-existing bug, not fixed here.
- Displaying address as a new row in `ViewGigDrawer` body — not requested.
- Address autocomplete or reverse geocoding.
- Validation: address is optional; no new validation rules added.
- Renaming the DB `location` column to `city` — pre-existing naming quirk, not changed.
