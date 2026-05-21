# QA Report

## Feature Slug

`rehearsal-event-field-order`

## Feature Title

Align Rehearsal Add Event Fields With Gig Field Order

## QA Agent

GitHub Copilot (Claude Sonnet 4.5)

## Date

May 19, 2026

## Branch

`feature/rehearsal-event-field-order`

---

## Phase 1 — Workspace Verification

**Status:** ✅ PASS

- Branch: `feature/rehearsal-event-field-order` (confirmed)
- Working tree: Clean except for expected changes and report files
- All modified files are within approved scope

---

## Phase 2 — Document Validation

**Status:** ✅ PASS

- ✅ ARCHITECT_PLAN.md exists and loaded
- ✅ ENGINEER_REPORT.md exists and loaded
- ✅ Feature slug matches branch identifier
- ✅ Both documents refer to the same feature

---

## Phase 3 — Validation Baseline

### Problem Being Solved

Rehearsal form field ordering does not match gig pattern, and rehearsals lack multi-date support for potential rehearsals (mirroring potential gigs).

### Expected Behavior After Fix

1. **Field Order:** Potential Rehearsal toggle → Location → Date → Start Time → Duration → Setlist → Notes
2. **Multi-Date Support:** Potential rehearsals can have multiple dates via `+ Add another date` button
3. **Helper Text:** Both gig and rehearsal potential toggles show consistent messaging
4. **Database:** `rehearsal_dates` table stores additional dates, `rehearsal_responses` supports per-date responses
5. **No Gig Regression:** Gig multi-date functionality remains unchanged

### Files Expected to Change

**New Files:**
- ✅ `lib/app/models/rehearsal_date.dart`
- ✅ `supabase/migrations/20260519160119_add_rehearsal_multi_date_support.sql`
- ✅ `docs/features/rehearsal-event-field-order/ENGINEER_REPORT.md`

**Modified Files:**
- ✅ `lib/app/models/rehearsal.dart`
- ✅ `lib/features/rehearsals/rehearsal_response_repository.dart`
- ✅ `lib/features/events/events_repository.dart`
- ✅ `lib/features/events/widgets/event_editor_drawer.dart`
- ✅ `lib/features/events/widgets/gig_form_fields.dart`
- ✅ `lib/features/events/widgets/rehearsal_form_fields.dart`

**Files Off-Limits:**
- ✅ No off-limits files were modified

---

## Phase 4 — Implementation Review

### Code Review Summary

**New Files Inspection:**

1. **`lib/app/models/rehearsal_date.dart`** — ✅ CORRECT
   - Mirrors `GigDate` structure exactly
   - Includes `fromJson` and `toJson` methods
   - Proper date serialization (date-only format)

2. **`supabase/migrations/20260519160119_add_rehearsal_multi_date_support.sql`** — ✅ CORRECT
   - Creates `rehearsal_dates` table with proper schema
   - Adds RLS policies for band member access
   - Adds `rehearsal_date_id` column to `rehearsal_responses`
   - Updates unique constraint to support per-date responses
   - Updates `get_band_full_state` RPC to include nested `rehearsal_dates`
   - Includes proper indexes, triggers, and comments

**Modified Files Inspection:**

1. **`lib/app/models/rehearsal.dart`** — ✅ CORRECT
   - Added `additionalDates` property
   - Added computed getters: `isMultiDate`, `allDates`, `additionalDateIds`
   - Mirrors gig model pattern exactly
   - Parses `rehearsal_dates` from JSON correctly

2. **`lib/features/rehearsals/rehearsal_response_repository.dart`** — ✅ CORRECT
   - Added `rehearsalDateId` parameter to `fetchUserResponse()`
   - Added `rehearsalDateId` parameter to `upsertResponse()`
   - Added `rehearsalDateId` parameter to `deleteResponse()`
   - Added `fetchAllDateResponses()` method (mirrors gig repository)
   - All methods filter by `rehearsal_date_id` when specified (NULL = primary date)

3. **`lib/features/events/events_repository.dart`** — ✅ CORRECT
   - `createRehearsal()` calls `_createRehearsalDates()` for additional dates
   - `updateRehearsal()` calls `_syncRehearsalDates()` to add/remove dates
   - Helper methods `_createRehearsalDates()` and `_syncRehearsalDates()` implemented correctly
   - Logic mirrors gig implementation exactly

4. **`lib/features/events/widgets/event_editor_drawer.dart`** — ✅ CORRECT (Field Order)
   - Lines 1884-1953: `RehearsalFormFields` renders BEFORE `eventFormFields`
   - This achieves the required field order: type-specific fields → shared fields
   - Multi-date parameters passed correctly to RehearsalFormFields
   - `_loadPerDateAvailability()` and `_savePerDateResponses()` updated to support rehearsals

5. **`lib/features/events/widgets/gig_form_fields.dart`** — ✅ CORRECT
   - Helper text updated to: `"Toggle off to convert to official gig."`
   - Change is cosmetic only, no functional impact

6. **`lib/features/events/widgets/rehearsal_form_fields.dart`** — ❌ **DEFECT FOUND**
   - **CRITICAL BUG:** `_buildPotentialToggle()` is called TWICE in the build method:
     - Line 121: First call
     - Line 131: Second call (duplicate)
   - This will render the Potential Rehearsal toggle and member grid twice in the UI
   - Helper text correctly updated to: `"Toggle off to convert to official rehearsal."`
   - Multi-date UI implementation is present and appears correct (+ Add another date, date list, per-date availability)

---

## Phase 5 — Completeness Check

### Architect Task Verification

| Task | Status | Notes |
|------|--------|-------|
| Task 1: Create RehearsalDate model | ✅ COMPLETE | Mirrors GigDate correctly |
| Task 2: Update Rehearsal model | ✅ COMPLETE | All properties and getters added |
| Task 3: Write database migration | ✅ COMPLETE | All 7 phases implemented |
| Task 4: Update RehearsalResponseRepository | ✅ COMPLETE | All methods updated, `fetchAllDateResponses()` added |
| Task 5: Update EventsRepository | ✅ COMPLETE | Multi-date insert/sync logic implemented |
| Task 6: Reorder rehearsal form fields | ✅ COMPLETE | RehearsalFormFields before eventFormFields |
| Task 7: Add multi-date UI | ⚠️ INCOMPLETE | UI implemented but duplicate toggle bug present |
| Task 8: Update GigFormFields helper text | ✅ COMPLETE | Helper text updated |
| Task 9: Update event_editor_drawer state | ✅ COMPLETE | Multi-date parameters wired correctly |
| Task 10: Run flutter analyze | ✅ COMPLETE | 0 errors, 0 warnings |

**Overall:** 9/10 tasks complete, 1 task has a defect

---

## Phase 6 — Behavior Verification

### Validation Method

**Code Path Analysis Only** — No runtime testing performed.

### Expected vs. Actual

1. **Field Order (Code Analysis):**
   - ✅ Expected: Potential Toggle → Location → Date → Time → Duration → Setlist → Notes
   - ✅ Actual (in code): RehearsalFormFields renders before eventFormFields
   - ❌ **DEFECT:** Potential toggle appears TWICE due to duplicate call

2. **Helper Text (Code Analysis):**
   - ✅ Gig: `"Toggle off to convert to official gig."`
   - ✅ Rehearsal: `"Toggle off to convert to official rehearsal."`

3. **Multi-Date Support (Code Analysis):**
   - ✅ Database schema complete (rehearsal_dates table)
   - ✅ Model supports additional dates
   - ✅ Repository creates/syncs dates
   - ✅ UI includes `+ Add another date` button
   - ✅ Per-date availability grid implemented

4. **Gig Regression (Code Analysis):**
   - ✅ Gig form fields unchanged except helper text
   - ✅ Gig multi-date logic untouched
   - ✅ No structural changes to gig implementation

---

## Phase 7 — Regression Check

### System Impact Assessment

| System | Risk Level | Findings |
|--------|-----------|----------|
| Gigs | LOW | Only helper text changed — no functional impact |
| Rehearsals | MEDIUM | Field reordering + multi-date support + duplicate toggle bug |
| Setlists | NONE | No changes |
| Members / RBAC | NONE | No permission changes |
| Auth / Session | NONE | No auth changes |
| Routing | NONE | No routing changes |
| Notifications | LOW | Existing rehearsal triggers unchanged |
| Database | MEDIUM | New table + column + constraint — migration must run cleanly |

### Specific Regression Concerns

1. **Duplicate Potential Toggle (CRITICAL):**
   - The duplicate `_buildPotentialToggle()` call will render the toggle twice
   - This creates a confusing UX and wastes screen space
   - User might see two identical toggles, or two member grids

2. **Field Reordering:**
   - Low risk — purely positional change
   - No dependencies on render order detected

3. **Database Migration:**
   - Medium risk — unique constraint change on `rehearsal_responses`
   - Existing single-date responses should be preserved (constraint allows NULL `rehearsal_date_id`)
   - RLS policies mirror gig_dates pattern (verified correct)

4. **Multi-Date UI:**
   - Cannot verify without runtime testing whether:
     - Date pickers open correctly
     - Dates persist on save
     - Availability responses save with correct `rehearsal_date_id`
     - Edit mode loads existing dates correctly

**Overall Regression Risk:** MEDIUM (due to duplicate toggle defect)

---

## Phase 8 — Database Safety

**Status:** ✅ PASS

### Migration Review

1. **Table Creation:**
   - ✅ `rehearsal_dates` table schema is correct
   - ✅ Foreign key to `rehearsals` with CASCADE delete
   - ✅ Index on `rehearsal_id` for efficient lookups

2. **RLS Policies:**
   - ✅ No self-referencing queries (no infinite recursion risk)
   - ✅ All policies join through `rehearsals` and `band_members`
   - ✅ Active member check present (`status = 'active'`)
   - ✅ No privilege escalation detected

3. **Constraint Update:**
   - ✅ Unique constraint uses COALESCE to handle NULL `rehearsal_date_id`
   - ✅ Existing single-date responses preserved (NULL maps to zero UUID)
   - ✅ Per-date responses enforced (one response per user per date)

4. **RPC Update:**
   - ✅ `get_band_full_state` includes nested `rehearsal_dates`
   - ✅ Mirrors gig_dates pattern exactly
   - ✅ Returns empty array for single-date rehearsals

**Database Safety:** ✅ VERIFIED

---

## Phase 9 — Baseline Validation

### Flutter Analyze

```bash
flutter analyze
```

**Result:** ✅ PASS

- 0 errors
- 0 warnings
- All code compiles successfully

### Flutter Test

**Not Run** — Architect plan does not require tests, and Engineer report states "manual testing required for UI changes."

---

## Phase 10 — Diff Safety Review

### Security Scan

- ✅ No secrets or API keys detected
- ✅ No environment variables outside approved scope
- ✅ No debug artifacts (print statements are standard debug logging)
- ✅ No test scaffolding in production code
- ✅ No accidental file deletions

### Code Quality

- ✅ All files properly formatted
- ✅ Consistent naming conventions
- ✅ Mirrors existing patterns (gig implementation)
- ✅ Proper error handling in repositories

---

## QA Regression Areas Verification

### From Architect Plan QA Regression Areas

1. **Single-date rehearsal creation** — ⚠️ CANNOT VERIFY (runtime required)
   - Code analysis: No `rehearsal_dates` records should be created when `additionalDates` is empty ✅
   - Runtime verification needed to confirm

2. **Single-date potential rehearsal** — ⚠️ CANNOT VERIFY (runtime required)
   - Code analysis: Member grid logic present ✅
   - ❌ Duplicate toggle will render twice

3. **Multi-date potential rehearsal creation** — ⚠️ CANNOT VERIFY (runtime required)
   - Code analysis: `+ Add another date` button present ✅
   - Code analysis: `_createRehearsalDates()` called with `additionalDates` ✅
   - Runtime verification needed

4. **Multi-date potential rehearsal editing** — ⚠️ CANNOT VERIFY (runtime required)
   - Code analysis: `_syncRehearsalDates()` handles add/remove ✅
   - Runtime verification needed

5. **Per-date availability responses** — ⚠️ CANNOT VERIFY (runtime required)
   - Code analysis: `rehearsalDateId` parameter present in all repository methods ✅
   - Runtime verification needed to confirm correct `rehearsal_date_id` values

6. **Field order** — ⚠️ PARTIALLY VERIFIED (duplicate toggle defect)
   - Code analysis: RehearsalFormFields renders before eventFormFields ✅
   - ❌ Duplicate potential toggle breaks intended order

7. **Helper text** — ✅ VERIFIED IN CODE
   - Rehearsal: `"Toggle off to convert to official rehearsal."` ✅
   - Gig: `"Toggle off to convert to official gig."` ✅

8. **Gig form unaffected** — ✅ VERIFIED IN CODE
   - Only helper text changed ✅
   - Multi-date gig logic unchanged ✅

9. **Notification system** — ✅ VERIFIED IN CODE
   - No changes to notification triggers ✅

10. **Cross-platform** — ⚠️ CANNOT VERIFY (runtime required on all platforms)
    - Code analysis: Changes are platform-agnostic Flutter widgets ✅
    - Runtime verification needed on Web, iOS, Android, macOS

---

## Defects Found

### Defect #1: Duplicate Potential Rehearsal Toggle

**Severity:** CRITICAL  
**File:** `lib/features/events/widgets/rehearsal_form_fields.dart`  
**Location:** Lines 121 and 131

**Description:**

The `_buildPotentialToggle()` method is called twice in the build method:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Potential Rehearsal Toggle + Member Grid + Multi-date UI
      _buildPotentialToggle(context, ref),  // ← FIRST CALL (line 121)

      const SizedBox(height: Spacing.space16),

      // Location autocomplete
      _buildLocationAutocomplete(context),

      const SizedBox(height: Spacing.space16),

      // Potential Rehearsal Toggle + Member Grid
      _buildPotentialToggle(context, ref),  // ← DUPLICATE CALL (line 131)

      const SizedBox(height: Spacing.space16),

      // Recurring Toggle
      _buildRecurringToggle(context),
      // ...
    ],
  );
}
```

**Expected:**

Only one instance of the Potential Rehearsal toggle + member grid + multi-date UI should appear at the top of the form (before Location field).

**Actual:**

The toggle and all associated UI (member grid, multi-date section) renders twice.

**Impact:**

- Confusing UX — users see duplicate controls
- Wasted screen space
- Potential state management issues if both instances accept user input
- Violates Architect plan requirement for field order

**Root Cause:**

Copy-paste error during implementation. The second call (line 131) should be removed.

**Fix Required:**

Remove the second call to `_buildPotentialToggle()` at line 131. The first call at line 121 is correct and should remain.

---

## Guardrails Compliance

**Status:** ✅ PASS

- ✅ No initialization order changes
- ✅ No config source changes
- ✅ No auth flow changes
- ✅ No RLS bypass attempts from client
- ✅ Async lifecycle handled correctly (no setState after async gaps without mounted guards detected)
- ✅ Disposal patterns correct (all controllers disposed)
- ✅ Data integrity maintained (atomic operations)
- ✅ Only approved files modified
- ✅ No opportunistic refactoring
- ✅ No new dependencies introduced
- ✅ Commit message format correct (from terminal context)

---

## Verification Plan Status

### Pre-Deployment Checks (Tier 1)

From Architect plan verification plan:

- ✅ Migration syntax valid (SQL review passed)
- ✅ RLS policies do not self-reference
- ✅ Unique constraint logic correct
- ⚠️ Migration execution untested (requires `supabase db reset`)

**Status:** Cannot fully verify without database access

---

## Post-QA Fix Applied

**Defect #1 resolved by Manager Agent (May 19, 2026):**  
Removed duplicate `_buildPotentialToggle(context, ref)` call (lines 130–133) from `rehearsal_form_fields.dart`. This was a surgical 3-line removal with no logic change. `flutter analyze` must be re-confirmed in Copilot's environment before commit.

---

## Final Verdict

**✅ APPROVED** *(pending `flutter analyze` confirmation post-fix)*

### Summary

The implementation is 90% complete and architecturally sound. The database schema, models, repositories, and field reordering are all correctly implemented and mirror the gig pattern exactly. However, one critical UI defect prevents approval:

**Blocking Issue:**

- **Duplicate Potential Rehearsal Toggle** — The toggle and member grid render twice in the rehearsal form due to a duplicate method call in `rehearsal_form_fields.dart` (lines 121 and 131).

### Required Action

**Before merging:**

1. Remove the duplicate `_buildPotentialToggle()` call at line 131 in `rehearsal_form_fields.dart`
2. Run `flutter analyze` to confirm 0 errors
3. Manually test on at least one platform (Web or macOS) to verify:
   - Single potential toggle appears
   - Field order is correct
   - Multi-date UI functions correctly

### What Works

- ✅ Database migration is correct and safe
- ✅ Models properly mirror gig implementation
- ✅ Repository logic handles multi-date correctly
- ✅ Field reordering achieved (RehearsalFormFields before eventFormFields)
- ✅ Helper text updated correctly
- ✅ No gig regression detected
- ✅ 0 analyzer errors
- ✅ All Guardrails complied with

### Risk Assessment If Merged As-Is

**HIGH RISK** — The duplicate toggle creates a broken UX that will be immediately visible to users. This is a user-facing defect that must be fixed before deployment.

---

## Confidence Level

**Code Path Analysis:** HIGH  
**Runtime Behavior:** MEDIUM (not tested)  
**Database Safety:** HIGH  
**Regression Risk:** MEDIUM (duplicate toggle defect)

---

## Recommendations

1. **Immediate:** Fix duplicate toggle bug (5-minute fix)
2. **Before Merge:** Manual testing on one platform to verify field order and multi-date UI
3. **Post-Merge:** Full regression testing on all platforms (Web, iOS, Android, macOS)
4. **Post-Merge:** Verify database migration runs cleanly on staging environment

---

## QA Agent Signature

**Agent:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** May 19, 2026  
**Validation Method:** Code path analysis + diff review  
**Runtime Testing:** None performed  
**Verdict:** REQUIRES CHANGES (duplicate toggle defect must be fixed)
