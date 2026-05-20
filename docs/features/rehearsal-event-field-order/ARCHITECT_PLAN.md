# ARCHITECT PLAN
## Feature: Align Rehearsal Add Event Fields With Gig Field Order

---

## Feature Slug
`rehearsal-event-field-order`

---

## Problem Summary
The Rehearsal form in the Add Event bottom sheet does not match the Gig form's field ordering and behavior. The Potential Rehearsal toggle appears after the Location field instead of at the top of the form (before Date), and rehearsals lack the multi-date support (`+ Add another date`) that Potential Gigs have. This inconsistency creates a confusing UX where users encounter different patterns for similar event types.

**What:** Misaligned field order and missing multi-date support for potential rehearsals.  
**Why:** Rehearsal-specific fields (including Potential toggle) render AFTER shared fields (Date, Time, Duration), whereas Gig-specific fields (including Potential toggle) render BEFORE shared fields. Rehearsals also lack the `rehearsal_dates` table infrastructure that gigs use for multi-date support.

---

## Root Cause
**Confidence: HIGH (confirmed in code)**

The rehearsal form structure diverges from the gig pattern in two critical ways:

1. **Field Rendering Order:**
   - **Gigs:** Type-specific fields (name, potential toggle) render FIRST, then shared fields (date, time, duration, setlist, notes)
   - **Rehearsals:** Shared fields render FIRST, then type-specific fields (location, potential toggle, recurring)
   - This is controlled by the build method in `event_editor_drawer.dart` lines 880-936

2. **Missing Multi-Date Infrastructure:**
   - Gigs have a `gig_dates` table to store additional dates for potential gigs
   - Rehearsals have no equivalent `rehearsal_dates` table
   - `gig_responses` supports per-date responses via `gig_date_id` column
   - `rehearsal_responses` has no `rehearsal_date_id` column (single-date only)

The feature request requires both structural alignment (field order) and functional parity (multi-date support).

---

## Reference Docs Consulted
None exist. No reference documentation found for:
- `docs/reference/rehearsals/`
- `docs/reference/gigs/`
- `docs/reference/events/`

This was documented explicitly during Phase 4 of the architecture process.

---

## Existing System Analysis

### Current Data Flow

**Gigs (reference implementation):**
1. User toggles Potential Gig → enables member selection grid + `+ Add another date` button
2. User taps `+ Add another date` → adds DateTime to `_additionalDates` list
3. On save → `EventsRepository.createGig()` inserts main gig record + inserts `gig_dates` records for additional dates
4. Members respond to potential gig → responses stored in `gig_responses` with optional `gig_date_id` (NULL = primary date)
5. On edit → fetches gig with nested `gig_dates` via `get_band_full_state` RPC, populates form, allows add/remove dates
6. On update → syncs `gig_dates` (deletes removed, inserts new)

**Rehearsals (current state):**
1. User toggles Potential Rehearsal → enables member selection grid (NO multi-date option)
2. On save → `EventsRepository.createRehearsal()` inserts rehearsal record only (no additional dates)
3. Members respond → responses stored in `rehearsal_responses` (no date-specific responses possible)
4. On edit → fetches rehearsal (no nested dates), single date only

**Field Ordering:**
- `event_editor_drawer.dart` build method (lines 880-936) controls order:
  - Gigs: `GigFormFields` (includes potential toggle) → `EventFormFields` (date, time, etc.) → additional gig fields
  - Rehearsals: `EventFormFields` (date, time, etc.) → `RehearsalFormFields` (location, potential toggle)

---

## Proposed Solution

### Minimal Change Strategy
Align rehearsals with gigs by:
1. Reordering rehearsal form components to match gig pattern
2. Adding `rehearsal_dates` table + supporting infrastructure (mirrors `gig_dates`)
3. Updating helper text for both Potential Gig and Potential Rehearsal toggles

### Changes Required

**1. Database Migration (New)**
- Create `rehearsal_dates` table (mirrors `gig_dates` schema):
  ```sql
  CREATE TABLE rehearsal_dates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rehearsal_id UUID NOT NULL REFERENCES rehearsals(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
  );
  ```
- Add `rehearsal_date_id UUID` column to `rehearsal_responses` (nullable, FK to rehearsal_dates)
- Update unique constraint on `rehearsal_responses` from `(rehearsal_id, user_id)` to `(rehearsal_id, user_id, COALESCE(rehearsal_date_id, '00000000-0000-0000-0000-000000000000'))` (matches gig_responses pattern)
- Add RLS policies for `rehearsal_dates` (band members can access)
- Update `get_band_full_state` RPC to include nested `rehearsal_dates` for rehearsals

**2. Flutter Models (New + Modified)**
- Create `RehearsalDate` model (mirrors `GigDate`) at `lib/app/models/rehearsal_date.dart`
- Update `Rehearsal` model: add `additionalDates`, `additionalDateIds`, `allDates`, `isMultiDate` properties (mirrors `Gig`)
- EventFormData already supports multi-date (reuse existing `additionalDates`, `existingGigDateIds` fields — make naming generic or aliased)

**3. UI Restructuring**
- **event_editor_drawer.dart** (lines 880-936): Reorder rehearsal rendering:
  ```dart
  // OLD (shared fields first):
  eventFormFields, 
  RehearsalFormFields(...)
  
  // NEW (type fields first, matches gig pattern):
  RehearsalFormFields(...), // potential toggle + location
  eventFormFields // date, time, duration, setlist, notes
  ```
  
- **rehearsal_form_fields.dart**:
  - Move Potential Rehearsal toggle to TOP of widget (before location autocomplete)
  - Update helper text: `"Toggle off to convert to official rehearsal."`
  - Add multi-date UI when potential is enabled:
    - `+ Add another date` button (reuse pattern from `GigFormFields`)
    - Date list with remove buttons
    - Date pickers for additional dates
  - Update `_buildPotentialToggle()` to accept multi-date state and callbacks (mirror GigFormFields)
  
- **gig_form_fields.dart**: Update Potential Gig helper text: `"Toggle off to convert to official gig."`

**4. Repository Updates**
- **EventsRepository:**
  - `createRehearsal()`: Insert `rehearsal_dates` records for `additionalDates` (mirror `createGig` logic)
  - `updateRehearsal()`: Sync `rehearsal_dates` (delete removed, insert new) (mirror `updateGig` logic)
- **RehearsalResponseRepository:**
  - Add `rehearsalDateId` parameter to `upsertResponse()`, `fetchUserResponse()`, `fetchAllMemberResponses()`
  - Add `fetchAllDateResponses()` method (mirror `GigResponseRepository`)

---

## Database Impact

### Migration Required: YES

**New Table: `rehearsal_dates`**
- Schema:
  ```sql
  CREATE TABLE public.rehearsal_dates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rehearsal_id UUID NOT NULL REFERENCES public.rehearsals(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  
  CREATE INDEX idx_rehearsal_dates_rehearsal_id ON public.rehearsal_dates(rehearsal_id);
  ```
  
- RLS Policies (mirror gig_dates):
  ```sql
  ALTER TABLE public.rehearsal_dates ENABLE ROW LEVEL SECURITY;
  
  CREATE POLICY "Band members can view rehearsal dates"
    ON public.rehearsal_dates FOR SELECT
    USING (EXISTS (
      SELECT 1 FROM public.rehearsals r
      JOIN public.band_members bm ON bm.band_id = r.band_id
      WHERE r.id = rehearsal_dates.rehearsal_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    ));
  
  CREATE POLICY "Band members can insert rehearsal dates"
    ON public.rehearsal_dates FOR INSERT
    WITH CHECK (EXISTS (
      SELECT 1 FROM public.rehearsals r
      JOIN public.band_members bm ON bm.band_id = r.band_id
      WHERE r.id = rehearsal_dates.rehearsal_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    ));
  
  CREATE POLICY "Band members can delete rehearsal dates"
    ON public.rehearsal_dates FOR DELETE
    USING (EXISTS (
      SELECT 1 FROM public.rehearsals r
      JOIN public.band_members bm ON bm.band_id = r.band_id
      WHERE r.id = rehearsal_dates.rehearsal_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    ));
  ```

**Modified Table: `rehearsal_responses`**
- Add column:
  ```sql
  ALTER TABLE public.rehearsal_responses
  ADD COLUMN rehearsal_date_id UUID REFERENCES public.rehearsal_dates(id) ON DELETE CASCADE;
  ```
  
- Update unique constraint:
  ```sql
  DROP INDEX IF EXISTS rehearsal_responses_rehearsal_user_unique;
  
  CREATE UNIQUE INDEX rehearsal_responses_rehearsal_user_date_unique 
  ON public.rehearsal_responses (rehearsal_id, user_id, COALESCE(rehearsal_date_id, '00000000-0000-0000-0000-000000000000'));
  
  COMMENT ON INDEX rehearsal_responses_rehearsal_user_date_unique IS 
  'Ensures one response per user per date. NULL rehearsal_date_id represents the primary date.';
  ```

**RPC Update: `get_band_full_state`**
- Modify query to include nested `rehearsal_dates`:
  ```sql
  -- Add to rehearsals fetch (lines 82-86):
  select coalesce(jsonb_agg(rehearsal_row order by rehearsal_row->>'date'), '[]'::jsonb)
  into rehearsals_arr
  from (
    select to_jsonb(r.*) || jsonb_build_object(
      'rehearsal_dates', coalesce(
        (select jsonb_agg(
          jsonb_build_object(
            'id', rd.id,
            'rehearsal_id', rd.rehearsal_id,
            'date', rd.date,
            'created_at', rd.created_at,
            'updated_at', rd.updated_at
          ) order by rd.date
        ) from rehearsal_dates rd where rd.rehearsal_id = r.id),
        '[]'::jsonb
      )
    ) as rehearsal_row
    from rehearsals r
    where r.band_id = p_band_id
  ) sub;
  ```

---

## Flutter Architecture Changes

### State Management (Riverpod)
- **No new providers required** — reuse existing `rehearsalProvider`, `membersProvider`, etc.
- `event_editor_drawer.dart` state variables already support multi-date (reuse `_additionalDates`, `_existingGigDateIds` — naming is generic enough)

### Widget Changes
1. **event_editor_drawer.dart**: Reorder build method (lines 880-936) for rehearsals
2. **rehearsal_form_fields.dart**: Add multi-date UI + reorder toggle
3. **gig_form_fields.dart**: Update helper text only (cosmetic)

### Repository Pattern
- Maintain existing pattern: `EventsRepository` handles mutations, `RehearsalResponseRepository` handles responses
- Add methods mirror gig equivalents (keep naming consistent)

---

## Files to Create

1. **`lib/app/models/rehearsal_date.dart`**
   - Purpose: Model for additional rehearsal dates (mirrors `GigDate`)
   - Structure:
     ```dart
     class RehearsalDate {
       final String id;
       final String rehearsalId;
       final DateTime date;
       final DateTime createdAt;
       final DateTime updatedAt;
       
       factory RehearsalDate.fromJson(Map<String, dynamic> json);
       Map<String, dynamic> toJson();
     }
     ```

2. **`supabase/migrations/YYYYMMDDHHMMSS_add_rehearsal_multi_date_support.sql`**
   - Purpose: Add rehearsal_dates table + update rehearsal_responses constraint + RLS policies
   - Phases: Table creation → RLS → Constraint update → RPC update

---

## Files to Modify

| File | What Changes | Lines (Approx) |
|------|-------------|----------------|
| `lib/features/events/widgets/event_editor_drawer.dart` | Reorder rehearsal form rendering: call RehearsalFormFields BEFORE eventFormFields | 880-936 |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | 1. Move potential toggle to top (before location)<br>2. Add multi-date UI (+Add another date, date list)<br>3. Update helper text<br>4. Add multi-date state parameters | Full file refactor |
| `lib/features/events/widgets/gig_form_fields.dart` | Update Potential Gig helper text: `"Toggle off to convert to official gig."` | ~Line 180 |
| `lib/app/models/rehearsal.dart` | Add properties: `additionalDates`, `additionalDateIds`, `allDates`, `isMultiDate` (mirror Gig) | Add ~4 properties + helper methods |
| `lib/features/events/events_repository.dart` | Update `createRehearsal()` and `updateRehearsal()` to insert/sync rehearsal_dates records | createRehearsal: +20 lines, updateRehearsal: +30 lines |
| `lib/features/rehearsals/rehearsal_response_repository.dart` | Add `rehearsalDateId` parameter to all methods, add `fetchAllDateResponses()` | +40 lines total |
| `supabase/migrations/20260313000000_get_band_full_state.sql` | Update rehearsals query to include nested rehearsal_dates (mirror gigs pattern) | ~Line 82-86 |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/main.dart` | Init order must not change (Guardrail #1) |
| `lib/features/gigs/gig_controller.dart` | Gig logic is reference implementation, not modification target |
| `lib/features/gigs/gig_repository.dart` | Gig logic is reference implementation, not modification target |
| `lib/app/models/gig.dart` | Reference model for rehearsal implementation |
| `lib/app/models/gig_date.dart` | Reference model for rehearsal_date implementation |
| `lib/features/events/widgets/event_form_fields.dart` | Shared component; must remain unchanged to avoid gig regression |

---

## System Impact Map

| System | Impact | Description |
|--------|--------|-------------|
| Gigs | **unaffected** | Only cosmetic helper text change |
| Rehearsals | **affected** | Field reordering + multi-date support + database schema |
| Setlists | **unaffected** | No changes to setlist selection or logic |
| Members / RBAC | **unaffected** | No permission model changes |
| Auth / Session | **unaffected** | No authentication flow changes |
| Routing | **unaffected** | No new routes or navigation changes |
| Notifications | **unaffected** | Existing rehearsal notification triggers continue to work |
| Platform (iOS / Android / Web / macOS) | **affected** | UI changes visible on all platforms |
| Database | **affected** | New table + column + constraint + RLS policies + RPC update |

---

## Regression Risk

**Overall: MEDIUM**

### Risk Factors
1. **Rehearsals system significantly affected** — field reordering + new multi-date behavior impacts every rehearsal creation/edit flow
2. **Database schema mutation** — new table + column + unique constraint change on rehearsal_responses could break existing single-date responses if migration is incorrect
3. **Shared component reordering** — EventFormFields now renders AFTER RehearsalFormFields instead of before; must verify no hidden dependencies on render order
4. **Multi-date UI complexity** — add/remove/edit dates must handle edge cases (empty dates, duplicate dates, past dates)
5. **Response syncing** — per-date responses for multi-date rehearsals must correctly map to rehearsal_date_id (NULL = primary date)

### Mitigation
- Migration includes explicit constraint that allows NULL rehearsal_date_id (preserves existing single-date responses)
- Reuse proven gig multi-date logic (copy-paste with find-replace "Gig" → "Rehearsal")
- Test plan includes regression checks: single-date rehearsals, potential rehearsals without multi-date, existing rehearsal responses

### Why Not HIGH
- Gigs remain untouched (reference implementation stable)
- No auth, routing, or init order changes (critical paths unaffected)
- Notification system unchanged (rehearsal triggers not modified)
- Field reordering is additive (no fields removed, only repositioned)

---

## Engineer Task Breakdown

Execute in strict order. Each task is atomic and verifiable.

### Task 1: Create `RehearsalDate` Model
- **File:** `lib/app/models/rehearsal_date.dart`
- **Action:** Copy `gig_date.dart`, rename class/fields from `Gig` → `Rehearsal`, update comments
- **Verify:** Model compiles, `fromJson` and `toJson` methods functional

### Task 2: Update `Rehearsal` Model
- **File:** `lib/app/models/rehearsal.dart`
- **Action:** Add properties: `additionalDates` (List<RehearsalDate>), computed getters: `additionalDateIds`, `allDates`, `isMultiDate`
- **Mirror:** `lib/app/models/gig.dart` lines 52-56, 159-176
- **Verify:** Rehearsal model compiles, `fromJson` includes `rehearsal_dates` parsing

### Task 3: Write Database Migration
- **File:** `supabase/migrations/YYYYMMDDHHMMSS_add_rehearsal_multi_date_support.sql`
- **Phases:**
  1. Create `rehearsal_dates` table + indexes
  2. Add RLS policies (SELECT, INSERT, DELETE)
  3. Add `rehearsal_date_id` column to `rehearsal_responses`
  4. Update unique constraint on `rehearsal_responses`
  5. Add updated_at trigger for `rehearsal_dates`
  6. Add table/column comments
- **Verify:** Migration runs cleanly via `supabase db reset`, constraints enforce expected behavior

### Task 4: Update `get_band_full_state` RPC
- **File:** `supabase/migrations/20260313000000_get_band_full_state.sql`
- **Action:** Modify rehearsals query (lines 82-86) to include nested `rehearsal_dates` as JSONB array
- **Mirror:** gigs query pattern (lines 60-77)
- **Verify:** RPC returns rehearsals with nested `rehearsal_dates` array (empty for single-date rehearsals)

### Task 5: Update `RehearsalResponseRepository`
- **File:** `lib/features/rehearsals/rehearsal_response_repository.dart`
- **Action:** 
  - Add `rehearsalDateId` parameter to `upsertResponse()`, `fetchUserResponse()`, `fetchAllMemberResponses()`
  - Add `fetchAllDateResponses()` method (mirror `GigResponseRepository.fetchAllDateResponses()`)
- **Verify:** Repository compiles, methods accept optional `rehearsalDateId`

### Task 6: Update `EventsRepository` for Rehearsal Multi-Date
- **File:** `lib/features/events/events_repository.dart`
- **Action:**
  - `createRehearsal()`: Insert `rehearsal_dates` records for each date in `formData.additionalDates`
  - `updateRehearsal()`: Sync `rehearsal_dates` (delete removed dates, insert new dates)
- **Mirror:** `createGig()` and `updateGig()` multi-date logic
- **Verify:** Creating/updating multi-date rehearsals persists additional dates to DB

### Task 7: Reorder Rehearsal Form Fields in `event_editor_drawer.dart`
- **File:** `lib/features/events/widgets/event_editor_drawer.dart`
- **Action:** In build method (lines 880-936), swap order for rehearsals:
  ```dart
  // OLD:
  eventFormFields,
  RehearsalFormFields(...)
  
  // NEW:
  RehearsalFormFields(...),
  eventFormFields,
  ```
- **Verify:** Rehearsal form renders in order: Potential Toggle → Location → Date → Time → Duration → Setlist → Notes

### Task 8: Add Multi-Date UI to `RehearsalFormFields`
- **File:** `lib/features/events/widgets/rehearsal_form_fields.dart`
- **Action:**
  1. Move `_buildPotentialToggle()` to top of build method (before location autocomplete)
  2. Add multi-date state parameters: `isMultiDate`, `additionalDates`, `selectedDate`, `existingRehearsalDateIds`, `onAdditionalDateAdded`, `onAdditionalDateRemoved`, `onAdditionalDateUpdated`, `onPerDateResponseChanged`
  3. Add `+ Add another date` button inside potential toggle container (when enabled)
  4. Add date list rendering (mirror `GigFormFields._buildMultiDateAvailabilitySection()`)
  5. Update helper text: `"Toggle off to convert to official rehearsal."`
- **Mirror:** `GigFormFields` lines 119-430 (potential gig container structure)
- **Verify:** Potential rehearsal shows `+ Add another date`, tapping adds date, date list renders correctly

### Task 9: Update Helper Text in `GigFormFields`
- **File:** `lib/features/events/widgets/gig_form_fields.dart`
- **Action:** Change helper text from `"Requires member confirmation before gig is official."` to `"Toggle off to convert to official gig."`
- **Verify:** Updated text displays correctly in gig form

### Task 10: Update `event_editor_drawer.dart` State Management
- **File:** `lib/features/events/widgets/event_editor_drawer.dart`
- **Action:**
  - Pass multi-date state to RehearsalFormFields: `isMultiDate`, `additionalDates`, `selectedDate`, `existingGigDateIds` (rename variable or alias for clarity)
  - Pass callbacks: `onAdditionalDateAdded: _addAdditionalDate`, `onAdditionalDateRemoved: _removeAdditionalDate`, `onAdditionalDateUpdated: _updateAdditionalDate`, `onPerDateResponseChanged: _updatePerDateResponse`
- **Verify:** Rehearsal form correctly updates state when dates added/removed

### Task 11: Test Single-Date Rehearsal (Regression)
- **Action:** Create a single-date rehearsal (potential: OFF), verify:
  - No multi-date UI visible
  - Saves correctly
  - Loads correctly in edit mode
  - No `rehearsal_dates` records created
- **Verify:** Existing single-date rehearsal behavior unchanged

### Task 12: Test Multi-Date Potential Rehearsal (New Feature)
- **Action:** Create a multi-date potential rehearsal:
  1. Toggle potential ON
  2. Add 2 additional dates
  3. Save
  4. Verify `rehearsal_dates` records created
  5. Edit rehearsal, verify dates load
  6. Remove 1 date, save, verify deletion
- **Verify:** Multi-date rehearsals create/update/delete correctly

### Task 13: Test Per-Date Availability Responses
- **Action:**
  1. Create multi-date potential rehearsal
  2. As another user, respond YES to date 1, NO to date 2
  3. Verify responses save with correct `rehearsal_date_id`
  4. Verify availability grid shows correct states
- **Verify:** Per-date responses work for rehearsals (mirror gig behavior)

---

## Verification Plan

### Tier 1 — Pre-deployment (before `supabase db push`)

These tests verify the migration structure and helper functions BEFORE deploying the changes.

```sql
-- PRE-DEPLOY TEST 1: Verify migration syntax is valid
-- Run: psql -d postgres -f supabase/migrations/YYYYMMDDHHMMSS_add_rehearsal_multi_date_support.sql --dry-run
-- Expected: No syntax errors

-- PRE-DEPLOY TEST 2: Verify RLS helper function for rehearsal_dates exists (mock)
-- (Cannot test actual function before migration, but validate logic pattern)
-- This is a structural check only
SELECT 1;
```

### Tier 2 — Post-deployment (after `supabase db push`)

These tests verify the deployed schema and data integrity.

```sql
-- POST-DEPLOY TEST 1: Verify rehearsal_dates table exists with correct schema
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'rehearsal_dates'
ORDER BY ordinal_position;
-- Expected: id (uuid, NO), rehearsal_id (uuid, NO), date (date, NO), created_at (timestamptz, NO), updated_at (timestamptz, NO)

-- POST-DEPLOY TEST 2: Verify rehearsal_responses has rehearsal_date_id column
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'rehearsal_responses' AND column_name = 'rehearsal_date_id';
-- Expected: rehearsal_date_id (uuid, YES)

-- POST-DEPLOY TEST 3: Verify unique constraint on rehearsal_responses updated
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'rehearsal_responses' AND indexname LIKE '%unique%';
-- Expected: rehearsal_responses_rehearsal_user_date_unique with COALESCE(rehearsal_date_id, '00000000...')

-- POST-DEPLOY TEST 4: Verify RLS policies exist for rehearsal_dates
SELECT schemaname, tablename, policyname, permissive, roles, cmd
FROM pg_policies
WHERE tablename = 'rehearsal_dates';
-- Expected: 3 policies (SELECT, INSERT, DELETE)

-- POST-DEPLOY TEST 5: Test rehearsal_dates insert and RLS enforcement
DO $$
DECLARE
  v_band_id UUID;
  v_rehearsal_id UUID;
  v_user_id UUID;
  v_date_id UUID;
BEGIN
  -- Create test band
  INSERT INTO bands (name, created_by) VALUES ('Test Band', auth.uid())
  RETURNING id INTO v_band_id;
  
  -- Add current user as member
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_band_id, auth.uid(), 'admin', 'active');
  
  -- Create test rehearsal
  INSERT INTO rehearsals (band_id, location, date, start_time, end_time, is_potential)
  VALUES (v_band_id, 'Test Studio', CURRENT_DATE, '19:00', '21:00', true)
  RETURNING id INTO v_rehearsal_id;
  
  -- Insert rehearsal_dates record (should succeed)
  INSERT INTO rehearsal_dates (rehearsal_id, date)
  VALUES (v_rehearsal_id, CURRENT_DATE + INTERVAL '7 days')
  RETURNING id INTO v_date_id;
  
  -- Verify inserted
  ASSERT (SELECT COUNT(*) FROM rehearsal_dates WHERE id = v_date_id) = 1, 
    'rehearsal_dates insert failed';
  
  -- Cleanup
  DELETE FROM rehearsals WHERE id = v_rehearsal_id;
  DELETE FROM bands WHERE id = v_band_id;
  
  RAISE NOTICE 'PRE-DEPLOY TEST 5: PASSED';
END $$;

-- POST-DEPLOY TEST 6: Test rehearsal_responses with rehearsal_date_id
DO $$
DECLARE
  v_band_id UUID;
  v_rehearsal_id UUID;
  v_date_id UUID;
  v_response_id UUID;
BEGIN
  -- Create test data
  INSERT INTO bands (name, created_by) VALUES ('Test Band', auth.uid())
  RETURNING id INTO v_band_id;
  
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_band_id, auth.uid(), 'admin', 'active');
  
  INSERT INTO rehearsals (band_id, location, date, start_time, end_time, is_potential)
  VALUES (v_band_id, 'Test Studio', CURRENT_DATE, '19:00', '21:00', true)
  RETURNING id INTO v_rehearsal_id;
  
  INSERT INTO rehearsal_dates (rehearsal_id, date)
  VALUES (v_rehearsal_id, CURRENT_DATE + INTERVAL '7 days')
  RETURNING id INTO v_date_id;
  
  -- Insert response for primary date (rehearsal_date_id = NULL)
  INSERT INTO rehearsal_responses (rehearsal_id, user_id, response)
  VALUES (v_rehearsal_id, auth.uid(), 'yes')
  RETURNING id INTO v_response_id;
  
  ASSERT (SELECT COUNT(*) FROM rehearsal_responses WHERE id = v_response_id) = 1,
    'Primary date response insert failed';
  
  -- Insert response for additional date (rehearsal_date_id = date ID)
  INSERT INTO rehearsal_responses (rehearsal_id, user_id, response, rehearsal_date_id)
  VALUES (v_rehearsal_id, auth.uid(), 'no', v_date_id)
  RETURNING id INTO v_response_id;
  
  ASSERT (SELECT COUNT(*) FROM rehearsal_responses WHERE id = v_response_id) = 1,
    'Additional date response insert failed';
  
  -- Verify unique constraint allows both (different date IDs)
  ASSERT (SELECT COUNT(*) FROM rehearsal_responses WHERE rehearsal_id = v_rehearsal_id) = 2,
    'Unique constraint should allow responses to different dates';
  
  -- Cleanup
  DELETE FROM rehearsals WHERE id = v_rehearsal_id;
  DELETE FROM bands WHERE id = v_band_id;
  
  RAISE NOTICE 'POST-DEPLOY TEST 6: PASSED';
END $$;

-- POST-DEPLOY TEST 7: Verify get_band_full_state RPC includes rehearsal_dates
DO $$
DECLARE
  v_band_id UUID;
  v_rehearsal_id UUID;
  v_date_id UUID;
  v_result JSONB;
BEGIN
  -- Create test data
  INSERT INTO bands (name, created_by) VALUES ('Test Band', auth.uid())
  RETURNING id INTO v_band_id;
  
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_band_id, auth.uid(), 'admin', 'active');
  
  INSERT INTO rehearsals (band_id, location, date, start_time, end_time, is_potential)
  VALUES (v_band_id, 'Test Studio', CURRENT_DATE, '19:00', '21:00', true)
  RETURNING id INTO v_rehearsal_id;
  
  INSERT INTO rehearsal_dates (rehearsal_id, date)
  VALUES (v_rehearsal_id, CURRENT_DATE + INTERVAL '7 days')
  RETURNING id INTO v_date_id;
  
  -- Call RPC
  SELECT get_band_full_state(v_band_id) INTO v_result;
  
  -- Verify rehearsal_dates key exists and contains expected date
  ASSERT v_result->'rehearsals'->0 ? 'rehearsal_dates',
    'rehearsal_dates key missing from RPC response';
  
  ASSERT jsonb_array_length(v_result->'rehearsals'->0->'rehearsal_dates') = 1,
    'rehearsal_dates array should contain 1 date';
  
  -- Cleanup
  DELETE FROM rehearsals WHERE id = v_rehearsal_id;
  DELETE FROM bands WHERE id = v_band_id;
  
  RAISE NOTICE 'POST-DEPLOY TEST 7: PASSED';
END $$;

-- POST-DEPLOY TEST 8: Verify no bad data written (rehearsal_dates orphans)
SELECT rd.id, rd.rehearsal_id, rd.date
FROM rehearsal_dates rd
LEFT JOIN rehearsals r ON r.id = rd.rehearsal_id
WHERE r.id IS NULL;
-- Expected: 0 rows (no orphaned rehearsal_dates)

-- POST-DEPLOY TEST 9: Verify existing single-date rehearsal responses unaffected
-- (Assumes test data exists with NULL rehearsal_date_id)
SELECT COUNT(*) FROM rehearsal_responses WHERE rehearsal_date_id IS NULL;
-- Expected: >= 0 (existing responses preserved with NULL date ID)
```

---

## QA Regression Areas

QA must specifically test:

### 1. **Single-Date Rehearsal Creation (Regression)**
   - Create a rehearsal with Potential OFF
   - Verify NO multi-date UI visible
   - Verify rehearsal saves and loads correctly
   - Verify no `rehearsal_dates` records created

### 2. **Single-Date Potential Rehearsal (Regression)**
   - Create a rehearsal with Potential ON, do NOT add additional dates
   - Verify member grid shows availability states
   - Verify rehearsal saves and loads correctly
   - Verify members can respond yes/no
   - Verify no `rehearsal_dates` records created

### 3. **Multi-Date Potential Rehearsal Creation (New Feature)**
   - Create a rehearsal with Potential ON
   - Tap `+ Add another date` twice (3 dates total)
   - Verify date list renders with remove buttons
   - Save rehearsal
   - Verify `rehearsal_dates` records created for additional dates
   - Reload rehearsal in edit mode, verify dates populate correctly

### 4. **Multi-Date Potential Rehearsal Editing**
   - Edit a multi-date rehearsal
   - Remove 1 date
   - Add 1 new date
   - Save
   - Verify deleted date removed from `rehearsal_dates`
   - Verify new date inserted into `rehearsal_dates`

### 5. **Per-Date Availability Responses**
   - As User A: Create multi-date potential rehearsal (3 dates)
   - As User B: Open rehearsal, respond YES to date 1, NO to date 2, skip date 3
   - As User A: Open rehearsal, verify User B's responses show correctly per date
   - Verify `rehearsal_responses` has 2 records for User B with correct `rehearsal_date_id`

### 6. **Field Order Verification**
   - Open Add Event → Rehearsal
   - Verify field order matches spec:
     1. Potential Rehearsal toggle
     2. Date (with `+ Add another date` if potential ON)
     3. Start Time
     4. Duration
     5. Location
     6. Setlist
     7. Notes

### 7. **Helper Text Verification**
   - Rehearsal: Potential toggle subtext = `"Toggle off to convert to official rehearsal."`
   - Gig: Potential toggle subtext = `"Toggle off to convert to official gig."`

### 8. **Gig Form Unaffected (Regression)**
   - Create a gig (potential ON)
   - Verify multi-date UI still works
   - Verify helper text updated to new copy
   - Verify no functional changes to gig behavior

### 9. **Notification System (Regression)**
   - Create a potential rehearsal (single-date)
   - Verify members receive notification
   - Create a multi-date potential rehearsal
   - Verify members receive notification (primary date only, or all dates if trigger updated — confirm expected behavior)

### 10. **Cross-Platform Consistency**
   - Test on Web, iOS, Android, macOS
   - Verify field order consistent across platforms
   - Verify multi-date UI renders correctly on all platforms

---

## Rollout / Migration Strategy

### Pre-Deployment
1. Review migration SQL in staging environment
2. Verify RLS policies do not block legitimate access
3. Test migration rollback script (if deployment fails)

### Deployment Steps
1. **Merge PR to main** after QA APPROVED
2. **Run `supabase db push`** to apply migration
3. **Run Tier 2 verification tests** (post-deployment SQL)
4. **Deploy Flutter app** to production (Web/iOS/Android/macOS)
5. **Monitor Sentry for errors** in rehearsal creation/edit flows

### Rollback Plan
If critical regression detected:
1. **Flutter rollback:** Revert PR, redeploy previous version
2. **Database rollback:** 
   ```sql
   -- Rollback migration (run manually if needed)
   DROP TABLE IF EXISTS rehearsal_dates CASCADE;
   ALTER TABLE rehearsal_responses DROP COLUMN IF EXISTS rehearsal_date_id;
   -- Restore old unique constraint (if needed)
   ```

### Post-Deployment Monitoring
- Monitor rehearsal creation success rate (expect no drop from baseline)
- Monitor `rehearsal_dates` table row count (should grow with multi-date rehearsals)
- Monitor error logs for constraint violations on `rehearsal_responses`

---

## Out of Scope

The following are explicitly NOT included in this feature:

1. **Recurring rehearsal multi-date interaction** — recurring rehearsals remain single-date per instance
2. **Notification changes** — existing rehearsal notification triggers unchanged (may send for primary date only)
3. **Calendar display for multi-date rehearsals** — calendar shows primary date only (multi-date display is future enhancement)
4. **Converting potential to official for multi-date rehearsals** — user must manually create official rehearsals for each date (or pick one primary date)
5. **Bulk date operations** — no "select all weekends" or date range picker (manual date-by-date only)
6. **Gig functional changes** — gigs remain unchanged except cosmetic helper text
7. **Field ordering for block-out events** — block-outs have separate form, unaffected by this change
8. **Setlist assignment per date** — setlist applies to all dates of a rehearsal, not per-date assignment
9. **Response deadline/cutoff for multi-date rehearsals** — no time-based response windows
10. **Historical rehearsal date editing** — cannot edit dates for past rehearsals (existing constraint applies)

---

**ARCHITECT PLAN COMPLETE**
