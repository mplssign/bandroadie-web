# ARCHITECT_PLAN.md

**Feature Slug:** `bug/gig-availability-multi-date-save-fix`  
**Branch Name:** `bug/gig-availability-multi-date-save-fix`  
**Date:** 2026-03-24

This plan covers two discrete items:

- **Sub-feature 1** — Bug: Gig Availability Only Saves First Date When Multiple Dates Present
- **Sub-feature 2** — Feature: Replace "Multiple" Button with Always-Visible "+ Add Another Date" UX

---

## 1. Problem Summary

### Sub-feature 1 — Multi-Date Availability Save Bug

When a user responds to a multi-date potential gig — either through the blocking availability prompt modal or the edit form — only the primary date's availability is persisted. Additional dates silently receive no response. The user believes their availability has been saved for all dates, but only the first date's response exists in the database.

### Sub-feature 2 — Replace "Multiple" Button UX

In the Potential Gig creation/edit form, a "Multiple" button appears to the right of the "Date" label when the Potential Gig toggle is on. Users must tap this button before they can add additional dates. The request is to remove this button and instead always show a "+ Add Another Date" button below the date picker whenever the Potential Gig toggle is on. This eliminates a hidden affordance and makes multi-date entry discoverable by default.

---

## 2. Existing System Analysis

### Multi-Date Gig Data Model

- **`gigs` table**: Stores one row per gig. The primary date is in `gigs.date`.
- **`gig_dates` table**: Child table storing additional dates. FK to `gigs.id`. Unique constraint on `(gig_id, date)`.
- **`gig_responses` table**: Stores per-user availability. Columns: `gig_id`, `user_id`, `response` (yes/no), `gig_date_id` (nullable FK to `gig_dates.id`).
  - `gig_date_id = NULL` → response for the primary date.
  - `gig_date_id = <uuid>` → response for a specific additional date.
  - Unique index: `(gig_id, user_id, COALESCE(gig_date_id, '00000000-0000-0000-0000-000000000000'))`.

### Availability Prompt Flow (Sub-feature 1)

1. `PotentialGigPromptNotifier.checkAndShowPendingPrompts()` runs on app startup/resume.
2. Calls `GigResponseRepository.fetchPendingPotentialGigs()` — returns gigs where the user has no response row.
3. For each pending gig, shows `AvailabilityPromptModal` (blocking yes/no dialog).
4. On response, calls `GigResponseRepository.upsertResponse()` — saves ONE response row with `gig_date_id = NULL` (primary date only).
5. `fetchPendingPotentialGigs` considers a gig "responded" if ANY response row exists for `(gig_id, user_id)`.

### Edit Form Availability Flow (Sub-feature 1)

1. User opens a multi-date gig in edit mode.
2. `_loadCurrentUserResponse()` calls `fetchUserResponse()` — queries `gig_responses` for `(gig_id, user_id)` without filtering by `gig_date_id`.
3. `_loadPerDateAvailability()` calls `fetchAllDateResponses()` — correctly fetches per-date responses for all dates.
4. User selects per-date availability via `_updatePerDateResponse()` — stores in `_perDateAvailability` local state.
5. On save:
   - Step A: `upsertResponse()` is called for `_currentUserResponse` (primary date, no `gig_date_id`).
   - Step B: `_savePerDateResponses()` iterates `_perDateAvailability` and calls `upsertResponseForDate()` for each date.

### "Multiple" Button Flow (Sub-feature 2)

1. `EventFormFields._buildDatePicker()` renders a "Date" label row.
2. When `isPotentialGig` is true, `_buildMultipleDatesToggle()` renders a "Multiple" pill button to the right of the "Date" label.
3. Tapping it calls `onMultiDateToggled(!isMultiDate)`, which sets `_isMultiDate` in `EventEditorDrawer`.
4. When `isMultiDate` is true, additional date pickers and an "Add another date" container appear below the primary date picker.
5. `_addAdditionalDate()` appends a new date (+7 days from last) but does NOT set `_isMultiDate = true`.

---

## 3. Root Cause

### Sub-feature 1 — Root Cause Confidence: HIGH (confirmed in code)

There are three related defects in the gig response data access layer:

**Defect A — Prompt service saves only primary date response.**  
Location: `potential_gig_prompt_service.dart` line ~165, `onRespond` callback.  
The callback calls `upsertResponse()` which inserts a row with `gig_date_id = NULL`. It never saves responses for additional dates (`gig_dates` rows). The `PendingPotentialGig` model does not carry additional date IDs, and `fetchPendingPotentialGigs` does not join `gig_dates`. After the primary date response is saved, `fetchPendingPotentialGigs` considers the gig "responded" and never re-prompts.

**Defect B — `_performUpsert` does not filter by `gig_date_id`.**  
Location: `gig_response_repository.dart`, `_performUpsert()` method (~line 275–295).  
Both the SELECT (`.maybeSingle()`) and UPDATE queries filter only on `(gig_id, user_id)` without constraining `gig_date_id`. When per-date responses exist (rows with different `gig_date_id` values), `.maybeSingle()` returns multiple rows and throws. The UPDATE would also overwrite all per-date rows with the same response value.

**Defect C — `fetchUserResponse` does not filter by `gig_date_id`.**  
Location: `gig_response_repository.dart`, `fetchUserResponse()` method (~line 218–228).  
Same issue as Defect B. When per-date responses exist, `.maybeSingle()` throws. The error is silently caught by `_loadCurrentUserResponse()`, leaving `_currentUserResponse` as null.

**Impact chain:**

1. User responds via prompt → only primary date saved (Defect A).
2. User opens edit form after per-date responses exist → `fetchUserResponse` throws (Defect C), silently swallowed.
3. User saves from edit form after per-date responses exist → `_performUpsert` throws or overwrites all rows (Defect B).

### Sub-feature 2 — Root Cause Confidence: HIGH (confirmed in code)

Not a defect — this is a UX improvement. The "Multiple" button is a hidden affordance. The `_buildMultipleDatesToggle()` widget is a small pill button positioned to the right of the "Date" label that must be tapped before multi-date entry becomes available. This adds an unnecessary step and is not discoverable.

---

## 4. Proposed Solution

### Sub-feature 1 — Fix Multi-Date Availability Save

**Strategy:** Fix all three defects with localized changes to the repository and prompt service. No new abstractions, controllers, or providers.

1. **Fix `_performUpsert`**: Add `.isFilter('gig_date_id', null)` to both the SELECT and UPDATE queries so they only operate on the primary date response row.

2. **Fix `fetchUserResponse`**: Add `.isFilter('gig_date_id', null)` to the SELECT query so it only returns the primary date response.

3. **Expand `PendingPotentialGig`**: Add `additionalDateIds` field (`List<String>`). Modify `fetchPendingPotentialGigs` to join `gig_dates(id)` in the select clause. Parse the joined data in `fromJson`.

4. **Fix prompt service save**: In the `onRespond` callback, replace the single `upsertResponse()` call with `upsertResponseForDate()` calls — one for the primary date (`gigDateId: null`) and one for each additional date ID. This uses the already-correct `_performUpsertForDate` method which properly handles `gig_date_id`.

### Sub-feature 2 — Replace "Multiple" Button with "+ Add Another Date"

**Strategy:** Remove the toggle mechanism and replace it with an always-visible action button. Minimal changes to two files.

1. **Remove `_buildMultipleDatesToggle()`** from `EventFormFields` and its call site.

2. **Remove `onMultiDateToggled`** constructor parameter and field from `EventFormFields`.

3. **Restructure `_buildDatePicker()`**: After the primary date picker and any existing additional date pickers, always show a "+ Add Another Date" styled button when `isPotentialGig` is true. Remove the `isMultiDate` gate on rendering additional dates — use `additionalDates.isNotEmpty` instead. Remove inline `showAddButton` from the last date row.

4. **Auto-set `_isMultiDate` in `_addAdditionalDate()`**: Set `_isMultiDate = true` when adding a date, so `_buildFormData()` includes the dates correctly.

5. **Auto-clear `_isMultiDate` in `_removeAdditionalDate()`**: Set `_isMultiDate = false` when the last additional date is removed.

6. **Remove `onMultiDateToggled` parameter** from the `_createEventFormFields()` call in `EventEditorDrawer`.

---

## 5. Database Impact

### Sub-feature 1

- **Schema impact:** None. No table changes. No new columns.
- **RLS impact:** None. Existing RLS policies are unaffected.
- **RPC impact:** None. No RPC functions are changed.
- **Auth impact:** None.
- **Migration policy:** Not required.

The fix writes additional rows to `gig_responses` (one per additional date per user response) using existing columns and constraints. The unique index `(gig_id, user_id, COALESCE(gig_date_id, ...))` already supports per-date responses.

### Sub-feature 2

Database: not applicable. UI-only change.

---

## 6. RLS / RPC Changes

### Sub-feature 1

No RLS or RPC changes required. All writes go through existing `gig_responses` INSERT/UPDATE paths that are already covered by RLS policies.

### Sub-feature 2

Not applicable.

---

## 7. Flutter Architecture Changes

### Sub-feature 1

| Layer      | Change                                                                           |
| ---------- | -------------------------------------------------------------------------------- |
| Repository | Fix `_performUpsert` and `fetchUserResponse` to filter by `gig_date_id IS NULL`. |
| Model      | Add `additionalDateIds` field to `PendingPotentialGig`.                          |
| Repository | Modify `fetchPendingPotentialGigs` query to join `gig_dates`.                    |
| Service    | Modify prompt `onRespond` to save responses for all dates.                       |

No new providers, controllers, or state management patterns.

### Sub-feature 2

| Layer  | Change                                                                        |
| ------ | ----------------------------------------------------------------------------- |
| Widget | Remove `_buildMultipleDatesToggle()` from `EventFormFields`.                  |
| Widget | Restructure `_buildDatePicker()` to always show "+ Add Another Date".         |
| Widget | Remove `onMultiDateToggled` prop from `EventFormFields`.                      |
| State  | Auto-manage `_isMultiDate` in `_addAdditionalDate` / `_removeAdditionalDate`. |
| Widget | Remove `onMultiDateToggled` from `_createEventFormFields()` call.             |

No new providers, controllers, or state management patterns.

---

## 8. Exact Files to Create

None.

---

## 9. Exact Files to Modify

### Sub-feature 1

| File                                                  | What Changes                                                                                                                                                                                                                                                                                                                                                                                                      |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/gigs/gig_response_repository.dart`      | Fix `_performUpsert`: add `.isFilter('gig_date_id', null)` to SELECT and UPDATE queries (~lines 278, 287, 293). Fix `fetchUserResponse`: add `.isFilter('gig_date_id', null)` to SELECT query (~line 223). Add `additionalDateIds` field to `PendingPotentialGig` model (~line 100). Modify `fetchPendingPotentialGigs` to join `gig_dates(id)` in select clause (~line 142) and parse in `fromJson` (~line 112). |
| `lib/features/gigs/potential_gig_prompt_service.dart` | Replace single `upsertResponse()` call in `onRespond` callback (~line 160) with `upsertResponseForDate()` calls: one for primary date (null) and one for each `gig.additionalDateIds` entry.                                                                                                                                                                                                                      |

### Sub-feature 2

| File                                                   | What Changes                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_form_fields.dart`   | Remove `onMultiDateToggled` from constructor and field (~lines 28, 64). Remove `_buildMultipleDatesToggle()` method (~lines 233–252). In `_buildDatePicker()`: remove the Multiple toggle call (~line 170), remove `isMultiDate` gate on additional date rendering (~line 181), remove `showAddButton` from date rows (~line 188), always show "+ Add Another Date" button when `isPotentialGig` (~after line 193). |
| `lib/features/events/widgets/event_editor_drawer.dart` | In `_addAdditionalDate()` (~line 756): add `_isMultiDate = true;` inside setState. In `_removeAdditionalDate()` (~line 765): add `if (_additionalDates.isEmpty) _isMultiDate = false;` inside setState. In `_createEventFormFields()` (~line 1640): remove `onMultiDateToggled` parameter.                                                                                                                          |

---

## 10. Risks / Edge Cases

### Sub-feature 1

| Risk                                                                        | Severity | Mitigation                                                                                                                                                            |
| --------------------------------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Prompt response saves one-at-a-time per date (non-atomic)                   | LOW      | Existing retry logic in `upsertResponseForDate` handles transient failures. If a mid-save failure occurs, partial responses are valid — user can re-edit to complete. |
| Existing users may have orphaned primary-only responses for multi-date gigs | LOW      | No migration needed. When they next open the edit form, per-date availability shows null for additional dates. They can respond to those dates and save.              |
| `fetchPendingPotentialGigs` query performance with gig_dates join           | LOW      | gig_dates has an index on `gig_id`. The join is lightweight (only selecting `id`).                                                                                    |
| Race condition: user responds via prompt while also editing the gig         | LOW      | Unique index on `gig_responses` prevents duplicate rows. Both paths use upsert logic.                                                                                 |

### Sub-feature 2

| Risk                                                                              | Severity | Mitigation                                                                                                             |
| --------------------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------- |
| Removing `onMultiDateToggled` is a breaking API change for EventFormFields        | LOW      | `EventFormFields` is only instantiated in `EventEditorDrawer._createEventFormFields()`. Single call site.              |
| Users accustomed to "Multiple" button may not find "+ Add Another Date"           | LOW      | The new button is more visible (always shown, below the date picker). Net improvement in discoverability.              |
| Auto-setting `_isMultiDate = false` when last date removed could lose user intent | LOW      | If the user removes all additional dates, the gig correctly reverts to single-date. User can re-add dates at any time. |

---

## 11. Verification Plan

### Engineer Validation Commands

```bash
flutter analyze   # Must pass with 0 errors
flutter test      # Must pass (no existing tests for these paths, but regression check)
```

### Manual Verification — Sub-feature 1

1. **Prompt flow — multi-date gig:**
   - Create a potential gig with 3 dates.
   - Log out and log back in (or trigger prompt check).
   - Respond "yes" to the availability prompt.
   - Open the gig in edit mode.
   - Verify all 3 dates show "yes" for the current user.

2. **Edit form — per-date availability:**
   - Open a multi-date potential gig in edit mode.
   - Select different availability for each date (e.g., yes, no, yes).
   - Save.
   - Reopen the gig.
   - Verify each date retains its individual response.

3. **Edit form — second save (regression):**
   - After step 2, change one date's availability and save again.
   - Verify no errors and all dates retain correct responses.

4. **Single-date gig — no regression:**
   - Create a single-date potential gig.
   - Respond via prompt modal.
   - Verify response saved correctly.

### Manual Verification — Sub-feature 2

1. **"Multiple" button removed:**
   - Open gig creation form, toggle Potential Gig on.
   - Verify no "Multiple" button appears next to "Date" label.

2. **"+ Add Another Date" always visible:**
   - With Potential Gig toggled on, verify "+ Add Another Date" button appears below the date picker.
   - Tap it. Verify a second date picker appears with date +7 days.
   - Tap it again. Verify a third date picker appears.

3. **Date removal:**
   - Remove all additional dates via ✕ buttons.
   - Verify "+ Add Another Date" button remains visible.
   - Verify form saves correctly as single-date gig.

4. **Non-potential gig — no button:**
   - Create a regular (non-potential) gig.
   - Verify no "+ Add Another Date" button appears.

5. **Edit mode — existing multi-date gig:**
   - Open an existing multi-date potential gig in edit mode.
   - Verify additional dates are shown.
   - Verify "+ Add Another Date" button appears below existing dates.

---

## 12. Engineer Task Breakdown

### Sub-feature 1 — Bug Fix (execute in order)

| #   | Task                                                                                                                                                                                                                                                                                                                                                                    | File                                |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| 1.1 | Fix `_performUpsert`: add `.isFilter('gig_date_id', null)` to the SELECT query (before `.maybeSingle()`) and to the UPDATE query (after `.eq('user_id', userId)`).                                                                                                                                                                                                      | `gig_response_repository.dart`      |
| 1.2 | Fix `fetchUserResponse`: add `.isFilter('gig_date_id', null)` to the SELECT query (before `.maybeSingle()`).                                                                                                                                                                                                                                                            | `gig_response_repository.dart`      |
| 1.3 | Add `final List<String> additionalDateIds;` field to `PendingPotentialGig`. Add it as a required constructor parameter with default `const []`.                                                                                                                                                                                                                         | `gig_response_repository.dart`      |
| 1.4 | Update `fetchPendingPotentialGigs` select clause: change `'id, band_id, name, date, start_time, end_time, location'` to `'id, band_id, name, date, start_time, end_time, location, gig_dates(id)'`.                                                                                                                                                                     | `gig_response_repository.dart`      |
| 1.5 | Update `PendingPotentialGig.fromJson`: parse `additionalDateIds` from the joined `gig_dates` array. Extract `id` from each element. Handle null/empty gracefully.                                                                                                                                                                                                       | `gig_response_repository.dart`      |
| 1.6 | In `potential_gig_prompt_service.dart`, replace the `onRespond` callback body: instead of calling `_repository.upsertResponse()`, call `_repository.upsertResponseForDate(gigId, null, userId, responseStr)` for the primary date, then loop through `gig.additionalDateIds` and call `_repository.upsertResponseForDate(gigId, dateId, userId, responseStr)` for each. | `potential_gig_prompt_service.dart` |

### Sub-feature 2 — UX Feature (execute in order)

| #   | Task                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | File                       |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------- |
| 2.1 | Remove `onMultiDateToggled` from `EventFormFields` constructor and field declaration.                                                                                                                                                                                                                                                                                                                                                                                                                  | `event_form_fields.dart`   |
| 2.2 | Delete the `_buildMultipleDatesToggle()` method entirely.                                                                                                                                                                                                                                                                                                                                                                                                                                              | `event_form_fields.dart`   |
| 2.3 | In `_buildDatePicker()`: remove the `_buildMultipleDatesToggle()` call from the Date label Row. Remove the `if (isMultiDate)` conditional wrapping the additional dates loop — render additional dates unconditionally based on `additionalDates.isNotEmpty`. Set `showAddButton: false` on all date rows (remove inline add). After all date pickers, add a `if (eventType == EventType.gig && isPotentialGig)` block that renders the "+ Add Another Date" button (reuse existing styled container). | `event_form_fields.dart`   |
| 2.4 | In `_addAdditionalDate()`: add `_isMultiDate = true;` as the first line inside `setState`.                                                                                                                                                                                                                                                                                                                                                                                                             | `event_editor_drawer.dart` |
| 2.5 | In `_removeAdditionalDate()`: add `if (_additionalDates.isEmpty) _isMultiDate = false;` after `_additionalDates.removeAt(index);` inside `setState`.                                                                                                                                                                                                                                                                                                                                                   | `event_editor_drawer.dart` |
| 2.6 | In `_createEventFormFields()`: remove the `onMultiDateToggled` named parameter from the `EventFormFields()` constructor call.                                                                                                                                                                                                                                                                                                                                                                          | `event_editor_drawer.dart` |

---

## 13. Rollout / Migration Strategy

No database migration required. No feature flags needed.

**Rollout:**

- Deploy to all platforms simultaneously (iOS, Android, macOS, web).
- Existing users with orphaned primary-only responses for multi-date gigs are not affected — their responses remain valid. When they next edit the gig, they can respond to additional dates.

**Backfill consideration (out of scope):**

- A SQL script could retroactively copy primary-date responses to additional dates for existing multi-date gigs. This is NOT required for the fix and is explicitly out of scope.

---

## 14. Out of Scope

- Backfilling existing orphaned responses for multi-date gigs.
- Per-date prompt modals (showing separate yes/no for each date in the prompt flow).
- Re-prompting users when new dates are added to a gig they already responded to.
- Refactoring `EventEditorDrawer` (2304 lines) — changes are localized and do not worsen maintainability.
- Refactoring `gig_response_repository.dart` (750 lines) — changes are localized.
- Any changes to `gig_form_fields.dart` beyond what flows through from `event_form_fields.dart` prop removal.
- Changes to the availability display in `GigFormFields._buildPotentialGigContainer()` — this already works correctly for multi-date display.
- Notification changes for multi-date availability.
- Test creation (no existing test coverage for these paths; testing conventions documented but coverage is minimal).

---

## 15. Widget Contracts (Public API)

### `EventFormFields` — Changed

**Removed parameter:**

```dart
// REMOVED
final ValueChanged<bool> onMultiDateToggled;
```

**Retained parameters (unchanged):**

```dart
final bool isMultiDate;                    // Still needed for form data building
final List<DateTime> additionalDates;      // Still needed for display
final ValueChanged<int> onAdditionalDateTap;
final ValueChanged<int> onAdditionalDateRemoved;
final VoidCallback onAdditionalDateAdded;
```

### `PendingPotentialGig` — Changed

**Added field:**

```dart
final List<String> additionalDateIds;  // IDs from gig_dates table
```

All other widget contracts remain unchanged.

---

## 16. Data Flow Architecture

### Sub-feature 1 — Fixed Prompt Flow

```
App Startup / Resume
    ↓
PotentialGigPromptNotifier.checkAndShowPendingPrompts()
    ↓
GigResponseRepository.fetchPendingPotentialGigs()
    → SELECT *, gig_dates(id) FROM gigs WHERE is_potential AND date >= today
    → Returns List<PendingPotentialGig> with additionalDateIds
    ↓
For each pending gig:
    AvailabilityPromptModal.show() → user selects YES/NO
    ↓
    onRespond callback:
        → upsertResponseForDate(gigId, null, userId, response)       ← primary date
        → for each additionalDateId:
            upsertResponseForDate(gigId, dateId, userId, response)   ← additional dates
```

### Sub-feature 1 — Fixed Edit Form Save Flow

```
EventEditorDrawer._saveEvent()
    ↓
    repository.updateGig(...)
    ↓
    if (isPotentialGig && _currentUserResponse != null):
        upsertResponse(gigId, bandId, userId, response)
            → _performUpsert with .isFilter('gig_date_id', null)  ← FIXED: only touches primary
    ↓
    if (isPotentialGig && _isMultiDate && _perDateAvailability.isNotEmpty):
        _savePerDateResponses()
            → for each dateKey in _perDateAvailability:
                upsertResponseForDate(gigId, gigDateId, userId, response)
```

### Sub-feature 2 — New Date Picker Flow

```
Potential Gig toggle ON
    ↓
_buildDatePicker():
    ├── Primary date picker (always shown)
    ├── Additional date pickers (shown if additionalDates.isNotEmpty)
    └── "+ Add Another Date" button (always shown when isPotentialGig)
            ↓ onTap
        EventEditorDrawer._addAdditionalDate()
            → _isMultiDate = true (auto-set)
            → _additionalDates.add(lastDate + 7 days)
            → rebuilds _buildDatePicker() with new date row

Remove last additional date:
    EventEditorDrawer._removeAdditionalDate()
        → _additionalDates.removeAt(index)
        → if empty: _isMultiDate = false (auto-clear)
```

---

## 17. Exact Code Locations

### Sub-feature 1

| What                               | File                                | Line(s)  | Description                                                         |
| ---------------------------------- | ----------------------------------- | -------- | ------------------------------------------------------------------- |
| `_performUpsert` SELECT            | `gig_response_repository.dart`      | ~278     | Add `.isFilter('gig_date_id', null)` before `.maybeSingle()`        |
| `_performUpsert` UPDATE            | `gig_response_repository.dart`      | ~289–293 | Add `.isFilter('gig_date_id', null)` after `.eq('user_id', userId)` |
| `fetchUserResponse` SELECT         | `gig_response_repository.dart`      | ~221–225 | Add `.isFilter('gig_date_id', null)` before `.maybeSingle()`        |
| `PendingPotentialGig` model        | `gig_response_repository.dart`      | ~100–120 | Add `additionalDateIds` field, constructor param, fromJson parsing  |
| `fetchPendingPotentialGigs` select | `gig_response_repository.dart`      | ~142     | Change select to include `gig_dates(id)`                            |
| Prompt `onRespond`                 | `potential_gig_prompt_service.dart` | ~158–168 | Replace `upsertResponse` with per-date saves                        |

### Sub-feature 2

| What                                 | File                       | Line(s)  | Description                                         |
| ------------------------------------ | -------------------------- | -------- | --------------------------------------------------- |
| `onMultiDateToggled` field           | `event_form_fields.dart`   | ~28, ~64 | Remove from constructor and field                   |
| `_buildMultipleDatesToggle()`        | `event_form_fields.dart`   | ~233–252 | Delete method                                       |
| `_buildDatePicker()` toggle call     | `event_form_fields.dart`   | ~170     | Remove `_buildMultipleDatesToggle()` call           |
| `_buildDatePicker()` multi-date gate | `event_form_fields.dart`   | ~181     | Remove `if (isMultiDate)` condition                 |
| `_buildDatePicker()` inline add      | `event_form_fields.dart`   | ~188     | Set `showAddButton: false`                          |
| `_buildDatePicker()` add button      | `event_form_fields.dart`   | ~193     | Always show "+ Add Another Date" for potential gigs |
| `_addAdditionalDate`                 | `event_editor_drawer.dart` | ~756     | Add `_isMultiDate = true;`                          |
| `_removeAdditionalDate`              | `event_editor_drawer.dart` | ~765     | Add auto-clear of `_isMultiDate`                    |
| `_createEventFormFields`             | `event_editor_drawer.dart` | ~1640    | Remove `onMultiDateToggled` parameter               |

---

## System Impact Map

| System                           | Sub-feature 1  | Sub-feature 2  |
| -------------------------------- | -------------- | -------------- |
| Gigs                             | affected       | affected       |
| Rehearsals                       | unaffected     | unaffected     |
| Setlists / Catalog               | unaffected     | unaffected     |
| Members / RBAC                   | unaffected     | unaffected     |
| Auth / Session                   | unaffected     | unaffected     |
| Routing                          | unaffected     | unaffected     |
| Notifications                    | unaffected     | unaffected     |
| Platform (iOS/Android/Web/macOS) | affected (all) | affected (all) |
| Calendar                         | unaffected     | unaffected     |
| Dashboard (potential gig cards)  | unaffected     | unaffected     |

---

## Regression Risk

### Sub-feature 1: MEDIUM

- Modifies data write paths for gig availability (upsert logic, query filters).
- Adds `.isFilter('gig_date_id', null)` to existing queries — narrow change but affects correctness of existing single-date save behavior.
- Changes prompt flow to write more rows per response — could surface latent RLS or constraint issues.
- No auth, routing, or init order changes.

### Sub-feature 2: LOW

- Pure UI change to form layout.
- Removes one widget method and one constructor parameter.
- Auto-management of `_isMultiDate` flag is behavioral but limited to the add/remove date methods.
- No data model or persistence changes.
- Single consumer of `EventFormFields`.

### Overall: MEDIUM
