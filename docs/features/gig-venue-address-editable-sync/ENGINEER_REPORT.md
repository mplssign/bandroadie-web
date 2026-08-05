# Engineer Report

## Feature Slug

`feature/gig-venue-address-editable-sync`

## Feature Title

Editable Venue Address on Gigs with Optional Sync

## Goal

Make venue address/city/state fields always editable on gigs (never locked), regardless of whether a venue is linked. When saving a linked gig with modified address fields, show a confirmation dialog asking whether to update the venue's contact card with the changes.

## Architect Tasks Completed

- [x] Task 1 — Read all affected files in full
- [x] Task 2 — Verify PR #118 fix is intact (confirmed: `_handleGigNameSelected()` is the only place that sets `_selectedVenueId`)
- [x] Task 3 — Remove read-only gate from address field (line ~226 in gig_form_fields.dart)
- [x] Task 4 — Remove read-only gate from state field (line ~501 in gig_form_fields.dart)
- [x] Task 5 — Remove read-only gate from city field (line ~755 in gig_form_fields.dart)
- [x] Task 6 — Add `_venueNeedsUpdate()` helper method to event_editor_drawer.dart
- [x] Task 7 — Add `_syncVenueData()` helper method to event_editor_drawer.dart
- [x] Task 8 — Modify `_handleSave()` to add sync-back confirmation dialog after validation and before setting `_isSaving = true`
- [x] Task 9 — Add required imports (`confirm_action_dialog.dart`, no `collection` package needed as existing `.cast<Venue?>().firstWhere()` pattern used)
- [x] Task 10 — Run flutter analyze (0 errors confirmed)
- [ ] Task 11-16 — Manual tests (not executable without live auth, see "Test Results" section)

## Files Created

- `docs/features/gig-venue-address-editable-sync/ENGINEER_REPORT.md` (this file)

## Files Modified

- `lib/features/events/widgets/gig_form_fields.dart` — Removed `!isVenueLinked` condition from `enabled` property on three TextField widgets (address, state, city)
- `lib/features/events/widgets/event_editor_drawer.dart` — Added `_venueNeedsUpdate()` and `_syncVenueData()` helper methods; modified `_handleSave()` to check for venue sync opportunity and show confirmation dialog; added `confirm_action_dialog.dart` import

## Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors, 0 warnings

```
Analyzing bandroadie...
No issues found! (ran in 2.8s)
```

## Test Results

**Manual tests (Tasks 11-16):** Not executable in current environment

**Reason:** All manual test steps require:

- Running the live Flutter app on a device/browser
- Active user authentication
- Live database connection with test data

**Known Engineer tooling limitation:** Cannot execute end-to-end UI flows without device auth. This is expected per the Engineer/QA separation documented in the project guidelines.

**Tests that require QA with live auth:**

1. Create gig with new venue (verify fields editable)
2. Edit gig with linked venue, no changes (verify no dialog)
3. Edit gig with linked venue, change address (verify dialog appears, "Yes" updates venue)
4. Edit gig with linked venue, change city (verify dialog appears, "No" doesn't update venue)
5. Edit gig with linked venue, unlink before save (verify no dialog)
6. PR #118 regression check (verify autocomplete behavior unchanged)

**Code-level verification completed:**

- Static analysis confirms all changes compile without errors
- Implementation matches Architect plan exactly
- No files modified outside of scope (verified with git status)
- PR #118 fix integrity confirmed (autocomplete logic unchanged)

## Verification

**Code-level checks performed:**

- Verified `_fetchGigNameSuggestions()` does not set `_selectedVenueId` (PR #118 fix intact)
- Verified `_handleGigNameSelected()` is the only place that sets `_selectedVenueId` from user selection
- Confirmed `_venueNeedsUpdate()` correctly compares form values with venue values
- Confirmed `_syncVenueData()` calls `venuesProvider.notifier.update()` with correct parameters
- Confirmed sync-back dialog inserted at correct location in `_handleSave()` (after validation, before `_isSaving = true`)
- Confirmed all three TextField widgets in gig_form_fields.dart now use `enabled: !isSaving` (without `!isVenueLinked`)
- Verified files off-limits were not touched (venues_controller.dart, etc.)

**Manual steps performed:**

- None (requires live app with auth)

## Deviations From Architect Plan

**Import adjustment:** Plan specified `import 'package:collection/collection.dart';` for `firstWhereOrNull`, but this would require adding `collection` as a new dependency (violates guardrails without Architect approval).

**Solution:** Used existing codebase pattern `.cast<Venue?>().firstWhere(..., orElse: () => null)` instead, which is already used in the same file (lines 309, 760) and achieves the same result without introducing a new dependency.

**All other implementation:** Exact match to Architect plan.

## Blockers Encountered

None. All tasks completed successfully.

## Ready For QA

**Yes**

**Pre-deployment requirements:**

- ✅ Code implemented per Architect plan
- ✅ Flutter analyze passes (0 errors)
- ✅ Files in scope only (no off-limits files touched)
- ✅ PR #118 fix verified intact
- ✅ No new dependencies introduced
- ✅ Implementation uses existing codebase patterns

**QA Test Plan:**
Refer to Section 15 ("Verification Plan") in ARCHITECT_PLAN.md for complete manual test script. All 7 tests require live app with authentication and are now ready for QA execution.

**Deployment readiness:**

- Branch: `feature/gig-venue-address-editable-sync` (confirmed via `git branch --show-current`)
- Working tree: Clean (only documentation added)
- Regression risk: Low (isolated scope, no schema changes, existing patterns reused)

---

## Post-QA Amendment

**Date:** 2026-08-05

**Context:** QA APPROVED this feature (see [QA_REPORT.md](QA_REPORT.md)). Before commit, Tony requested one scoped copy change to the confirmation dialog.

**Change made:**

Modified [event_editor_drawer.dart](../../../lib/features/events/widgets/event_editor_drawer.dart) lines 1715-1716:

**Before:**

```dart
title: 'Update ${venueToUpdate.name}?',
message: 'Update this venue\'s contact info with these changes too?',
```

**After:**

```dart
title: 'Update Venue',
message: 'You made changes to this venue. Do you want to update the venue\'s contact card?',
```

**Rationale:**

- Title now static (removed venue-name interpolation and trailing `?` for consistency)
- Message now more explicit about context ("you made changes") and action ("update the venue's contact card")
- Tony-requested improvement to dialog clarity

**Impact:**

- Copy-only change, no logic modified
- No other files touched
- No changes to method signatures, conditions, or data flow

**Validation:**

- Command: `flutter analyze`
- Result: **0 errors, 0 warnings**

```
Analyzing bandroadie...
No issues found! (ran in 4.2s)
```

**Status:** Complete, ready for commit

---

## Post-QA Amendment 2

**Date:** 2026-08-05

**Context:** After Post-QA Amendment 1 (dialog copy change), Tony requested removal of the "Unlink venue" action entirely from the gig form. The original feature made address/city/state fields always editable regardless of venue-link state, which eliminated the editing-related need for unlinking. Tony confirmed he wants the action removed despite the tradeoff: no longer any UI way to fully detach a gig from a wrongly-linked venue, and the save-time sync-back dialog will continue offering to update that venue's card for the life of the gig.

**Changes made:**

**1. [lib/features/events/widgets/gig_form_fields.dart](../../../lib/features/events/widgets/gig_form_fields.dart):**

- **Lines 24-25 (constructor parameters):** Removed `required this.isVenueLinked,` and `required this.onUnlinkVenue,`
- **Lines 92-93 (field declarations):** Removed `final bool isVenueLinked;` and `final VoidCallback onUnlinkVenue;`
- **Lines 687-701 ("Unlink venue" widget):** Removed entire conditional block:
  ```dart
  if (isVenueLinked) ...[
    const SizedBox(height: Spacing.space8),
    Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: isSaving ? null : onUnlinkVenue,
        child: Text(
          'Unlink venue',
          style: AppTextStyles.footnote.copyWith(
            color: isSaving ? context.colors.textMuted : AppColors.primary,
          ),
        ),
      ),
    ),
  ],
  ```

**2. [lib/features/events/widgets/event_editor_drawer.dart](../../../lib/features/events/widgets/event_editor_drawer.dart):**

- **Lines 796-806 (`_unlinkVenue()` method):** Removed entire method implementation
- **Lines 2295-2296 (GigFormFields instantiation):** Removed `isVenueLinked: _selectedVenueId != null,` and `onUnlinkVenue: _unlinkVenue,` parameter passes

**What was NOT removed:**

- `_selectedVenueId` variable itself (still tracks linked venue for save-time sync logic)
- `_handleGigNameSelected()` (still sets `_selectedVenueId` from autocomplete)
- `_venueNeedsUpdate()` / `_syncVenueData()` methods (still perform save-time sync)
- Any other venue-related logic (prefill, autocomplete, sync-back dialog)

**Rationale:**

The original feature made venue address/city/state fields always editable, which removed the primary use case for "Unlink venue" (enabling field editing). Tony confirmed he wants the action removed entirely despite the tradeoff: users can no longer explicitly detach a gig from a wrongly-linked venue via the UI. The save-time sync dialog will continue offering to update the linked venue's card for the life of the gig.

**Parameter usage verification:**

Grepped for `isVenueLinked` and `onUnlinkVenue` in gig_form_fields.dart after widget removal:

- Both parameters were **only used** by the "Unlink venue" conditional widget
- No other references found → safe to remove from constructor and field declarations

**Impact:**

- UI-only change, no data model or repository logic modified
- `_selectedVenueId` still tracks venue link state for save-time sync
- Venue autocomplete, prefill, and sync-back dialog all unchanged
- No schema, migration, or RPC changes

**Validation:**

- Command: `flutter analyze`
- Result: **0 errors, 0 warnings**

```
Analyzing bandroadie...
No issues found! (ran in 5.2s)
```

**Status:** Complete, ready for commit
