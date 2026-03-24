# Engineer Report

## Feature Slug

bug/gig-availability-multi-date-save-fix

## Feature Title

Bug: Gig Availability Only Saves First Date When Multiple Dates Present + Feature: Replace "Multiple" Button with Always-Visible "+ Add Another Date" UX

## Goal

Fix three defects in the gig response data access layer that caused multi-date potential gig availability to only save for the primary date. Additionally, replace the hidden "Multiple" button affordance with an always-visible "+ Add Another Date" button for better discoverability.

## Architect Tasks Completed

### Sub-feature 1 — Bug Fix

- [x] Task 1.1 — Fix `_performUpsert`: added `.isFilter('gig_date_id', null)` to SELECT and UPDATE queries
- [x] Task 1.2 — Fix `fetchUserResponse`: added `.isFilter('gig_date_id', null)` to SELECT query
- [x] Task 1.3 — Added `additionalDateIds` field to `PendingPotentialGig` with default `const []`
- [x] Task 1.4 — Updated `fetchPendingPotentialGigs` select clause to include `gig_dates(id)` join
- [x] Task 1.5 — Updated `PendingPotentialGig.fromJson` to parse `additionalDateIds` from joined `gig_dates` array
- [x] Task 1.6 — Replaced single `upsertResponse()` call in prompt `onRespond` with `upsertResponseForDate()` calls for primary date and all additional dates

### Sub-feature 2 — UX Feature

- [x] Task 2.1 — Removed `onMultiDateToggled` from `EventFormFields` constructor and field declaration
- [x] Task 2.2 — Deleted `_buildMultipleDatesToggle()` method entirely
- [x] Task 2.3 — Restructured `_buildDatePicker()`: removed Multiple toggle, removed `isMultiDate` gate, always shows "+ Add Another Date" when `isPotentialGig`
- [x] Task 2.4 — Added `_isMultiDate = true;` in `_addAdditionalDate()` inside setState
- [x] Task 2.5 — Added `if (_additionalDates.isEmpty) _isMultiDate = false;` in `_removeAdditionalDate()` inside setState
- [x] Task 2.6 — Removed `onMultiDateToggled` parameter from `_createEventFormFields()` call

## Files Created

- None

## Files Modified

- `lib/features/gigs/gig_response_repository.dart`
- `lib/features/gigs/potential_gig_prompt_service.dart`
- `lib/features/events/widgets/event_form_fields.dart`
- `lib/features/events/widgets/event_editor_drawer.dart`

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found!"

## Test Results

Not run — no existing tests for these paths, and Architect plan does not require tests.

## Verification

Manual steps not performed (Engineer agent — runtime verification is QA scope).

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes
