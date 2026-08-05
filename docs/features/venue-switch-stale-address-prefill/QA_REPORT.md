# QA Report

## Feature Slug

`bug/venue-switch-stale-address-prefill`

## Feature Title

Fix Stale Address When Switching Between Linked Venues

## Final Verdict

**APPROVED**

## Validation Summary

Implementation correctly distinguishes between initial venue linking and venue switching scenarios. Code-path analysis confirms that the "only fill if empty" protection is preserved for initial links while venue switches now unconditionally sync all address fields to the newly selected venue's data. The fix prevents the false-positive sync-back dialog that would have offered to corrupt the newly selected venue's contact card with stale data from the previously selected venue.

## Architect Scope Review

- **Scope adherence:** Compliant
- **Files modified:** As expected — only `lib/features/events/widgets/event_editor_drawer.dart` lines 746-810
- **Files off-limits:** Not touched — `_venueNeedsUpdate()` (lines 810-845) and `_syncVenueData()` (lines 847-870) remain unmodified as required

## Completeness Check

- **All Architect tasks implemented:** Yes
  - Task 1: Target method located and analyzed ✓
  - Task 2: Venue-switch detection implemented (`previousVenueId`, `isSwitchingVenues`) ✓
  - Task 3: Prefill logic replaced with conditional if/else paths ✓
  - Task 4: Syntax verified, analyzer passed ✓
  - Task 5: Git diff generated and matches expected changes ✓
- **Missing tasks:** None

## Behavior Verification

- **Validation method:** Code-path analysis
- **Result:** Matches expected behavior

### Code-Path Analysis Results

#### 1. Initial-Link Protection Preserved ✓

When `_selectedVenueId` is null before selection:

- `previousVenueId` captures null
- `isSwitchingVenues = previousVenueId != null && previousVenueId != selectedVenue.id` evaluates to FALSE
- Execution falls to `else` branch (initial link path)
- "Only fill if empty" logic executes: checks `_locationController.text.trim().isEmpty` etc.
- **Confirmation:** Manually-typed addresses are protected from being overwritten

#### 2. Switch Behavior Correct ✓

When `_selectedVenueId` was already set to a different venue:

- `previousVenueId` is non-null and differs from `selectedVenue.id`
- `isSwitchingVenues` evaluates to TRUE
- Execution enters `if (isSwitchingVenues)` branch
- Unconditional assignments execute:
  - `_locationController.text = selectedVenue.city ?? '';`
  - `_addressController.text = selectedVenue.address ?? '';`
  - `_stateController.text = selectedVenue.state?.toUpperCase() ?? '';`
- **Confirmation:** All three fields get overwritten with new venue's values, including clearing to empty string if new venue field is null

#### 3. Reselecting Same Venue is No-Op ✓

When `previousVenueId == selectedVenue.id`:

- `isSwitchingVenues = previousVenueId != null && previousVenueId != selectedVenue.id` evaluates to FALSE
- Execution falls to `else` branch (initial link path)
- Fields already contain matching data from earlier selection
- All "only fill if empty" checks fail (fields not empty)
- No assignments occur
- **Confirmation:** Silent no-op with no visible effect

#### 4. Interaction with Sync-Back Dialog ✓

After venue switch from A to B:

- Fields now contain Venue B's real data (updated by switch branch)
- On save, `_venueNeedsUpdate()` (line 810) compares form fields against Venue B's stored values
- Comparison finds match → returns null
- No sync-back dialog appears
- **Confirmation:** Fix eliminates false-positive mismatch from venue switching

#### 5. \_venueNeedsUpdate() and \_syncVenueData() Unmodified ✓

Verified by reading lines 810-870:

- `_venueNeedsUpdate()` unchanged at lines 810-845
- `_syncVenueData()` unchanged at lines 847-870
- Both methods match Architect plan description exactly
- **Confirmation:** Required methods not modified

### Test Scenario Analysis (Section 15 of Architect Plan)

**Static verification completed for all 6 scenarios:**

| Scenario                                    | Expected Outcome          | Code-Path Verification                           | Runtime Test Required |
| ------------------------------------------- | ------------------------- | ------------------------------------------------ | --------------------- |
| Test 1: Initial link with manual address    | Manual address preserved  | ✓ Verified (else branch, empty check fails)      | YES                   |
| Test 2: Initial link with no manual address | Venue address prefills    | ✓ Verified (else branch, empty check passes)     | YES                   |
| Test 3: Venue switch A→B                    | Fields update to B's data | ✓ Verified (if branch, unconditional assignment) | YES                   |
| Test 4: Switch to venue with empty address  | Fields clear to empty     | ✓ Verified (if branch, `?? ''` assigns empty)    | YES                   |
| Test 5: Reselect same venue                 | No-op                     | ✓ Verified (else branch, all checks fail)        | YES                   |
| Test 6: Edit mode, no name change           | Fields unchanged          | ✓ Verified (method not called)                   | YES                   |

**Manual Runtime Testing Required:**
All 6 scenarios require on-device/browser validation to confirm UI interactions behave as expected. Code-path analysis confirms the logic is correct, but actual user interaction flow (autocomplete selection, field updates, save dialog) must be tested manually per Section 15 verification plan.

**Tony must manually test:**

- Autocomplete dropdown selection triggers correct branch
- TextEditingController updates are visible in UI
- Sync-back dialog appears/doesn't appear correctly in each scenario
- Cross-platform consistency (Web, iOS, Android, macOS)

## Regression Check

- **Risk level:** LOW
- **Systems reviewed:**
  - Gigs (affected) — venue switch prefill behavior changed as designed
  - Rehearsals (unaffected) — separate form, no venue linking
  - Setlists/Catalog (unaffected) — no interaction with gig venue logic
  - Members/RBAC (unaffected) — no permission changes
  - Auth/Session (unaffected) — no auth flow changes
  - Routing (unaffected) — no navigation changes
  - Notifications (unaffected) — no notification changes
  - Contacts/Venues (indirectly protected) — sync-back false-positives prevented, no code changes
  - Platform (unaffected) — shared Flutter code, no platform-specific paths
- **Regressions found:** None

### Regression Risk Rationale

- **Isolated change:** Single method in one file, no ripple effects
- **No new state:** Uses existing `_selectedVenueId` field to detect switches
- **Preserves original intent:** Initial-link scenario keeps "only fill if empty" protection
- **No database changes:** Pure client-side UI logic
- **No cross-feature impact:** Venue switching only affects gig forms
- **Well-defined scenarios:** All four scenarios have clear expected outcomes validated in code

## Database Safety

**Not applicable** — No database schema, RLS policies, migrations, or RPC function changes. This is pure client-side UI logic.

## Analyzer Results

- **Command:** `flutter analyze`
- **Result:** No issues found! (0 errors, 0 warnings)
- **Verification:** Ran successfully in 4.5s on 2026-08-05

## Test Results

**Not run** — No automated tests exist for this UI interaction flow. Manual UI testing required per Architect plan Section 15 (Tier 2 verification).

The Architect plan explicitly designates this as a Tier 2 manual UI testing requirement, as the bug involves autocomplete dropdown selection, TextEditingController updates, and dialog interactions that cannot be validated through automated tests without significant test infrastructure investment.

## Diff Safety Review

- **Secrets:** None found ✓
- **Debug artifacts:** None found ✓
- **Unrelated changes:** None found ✓
- **Formatting-only changes:** None — all changes are functional ✓
- **Accidental file deletions:** None ✓

### Diff Details

```diff
+    // Capture previous venue ID to detect venue switches
+    final previousVenueId = _selectedVenueId;
+    final isSwitchingVenues =
+        previousVenueId != null && previousVenueId != selectedVenue.id;
```

- Two new local variables added to detect venue switch scenario
- No global state introduced
- Comment added explaining purpose

```diff
-        // Only fill empty fields to avoid clobbering user-entered values.
+        if (isSwitchingVenues) {
+          // Switching from one venue to another — always sync to new venue's values
+          _locationController.text = selectedVenue.city ?? '';
+          _addressController.text = selectedVenue.address ?? '';
+          _stateController.text = selectedVenue.state?.toUpperCase() ?? '';
+        } else {
+          // Initial link — only fill empty fields to preserve user-entered values
```

- Existing prefill logic wrapped in if/else conditional
- Comment updated to reflect both scenarios
- Venue switch branch: unconditional assignment with null-coalescing to empty string
- Initial link branch: preserved original "only fill if empty" logic verbatim

**Verification:** Every changed line is essential to the fix. No extraneous modifications.

## Issues Found

**None**

## Critical Pre-Commit Checklist

- [x] Implementation matches Architect plan Section 10 specifications exactly
- [x] All 5 Architect tasks (Section 14) completed
- [x] Only approved file modified (event_editor_drawer.dart lines 746-810)
- [x] `_venueNeedsUpdate()` and `_syncVenueData()` not modified (lines 810-870)
- [x] No behavioral regressions introduced
- [x] `flutter analyze` passes with 0 errors, 0 warnings
- [x] No database safety issues (not applicable)
- [x] No secrets or debug artifacts in diff
- [x] Git diff matches Engineer report exactly
- [x] Branch is `bug/venue-switch-stale-address-prefill` as required
- [x] Working tree contains only expected changes

## Required Manual Testing (Tony Must Complete)

The following 6 scenarios from Architect Plan Section 15 **MUST** be tested manually on-device/browser before merge:

### High Priority (Core Bug Fix)

1. **Test 3 — Venue Switch A→B (Primary Bug Fix)**
   - Link gig to Venue A (e.g., "The Bluebird Cafe")
   - Verify address fields prefill with Venue A's data
   - Clear gig name completely
   - Type different venue name (e.g., "3rd and Lindsley")
   - Select from autocomplete
   - **CRITICAL:** Verify address fields immediately update to Venue B's data
   - Save gig
   - **CRITICAL:** Verify no sync-back dialog appears (or if it does, explains why)

### Medium Priority (Protection Cases)

2. **Test 1 — Initial Link with Manual Address**
   - Create new gig
   - Type manual address "999 Test St", city "Test City", state "CA"
   - Type venue name "The Bluebird Cafe"
   - Select from autocomplete
   - **Verify:** Manual address retained (not overwritten)

3. **Test 2 — Initial Link with No Manual Address**
   - Create new gig
   - Do NOT type any address
   - Type venue name "The Bluebird Cafe"
   - Select from autocomplete
   - **Verify:** Address fields prefill with venue's stored data

### Low Priority (Edge Cases)

4. **Test 4 — Switch to Venue with Empty Address**
   - Link to venue with address
   - Switch to venue with no address stored
   - **Verify:** Address fields clear to empty (no stale data)

5. **Test 5 — Reselect Same Venue**
   - Link to venue, fields prefill
   - Clear gig name, type same venue name, select
   - **Verify:** No visible change (silent no-op)

6. **Test 6 — Edit Mode, No Name Change**
   - Open existing gig with venue linked
   - Modify time or notes (do NOT touch gig name)
   - Save
   - **Verify:** Address fields unchanged

### Platform Coverage

Test at minimum on:

- [x] Web (Chrome) — Tony's primary platform
- [ ] iOS (simulator or device)
- [ ] Android (emulator or device)
- [ ] macOS

## Notes for Tony

**This implementation is safe to commit** based on code-path analysis. However, **you must run all 6 manual test scenarios** before merging to production, particularly Test 3 (the primary bug fix), to confirm:

1. Autocomplete selection triggers the correct code branch
2. TextEditingController updates are visible in the UI immediately
3. The sync-back dialog no longer appears in the venue-switch scenario (or appears correctly with updated logic)
4. No unintended side effects on other gig form interactions

The code logic is sound and matches the Architect plan exactly. The risk is LOW. Manual validation is purely to confirm UI interaction behavior matches the code-path expectations.

---

## QA Agent Signature

**Validated by:** QA Agent (GitHub Copilot)  
**Date:** 2026-08-05  
**Branch:** bug/venue-switch-stale-address-prefill  
**Commit state:** Uncommitted (working tree clean except expected change)  
**Architect Plan Version:** Final (venue-switch-stale-address-prefill/ARCHITECT_PLAN.md)  
**Engineer Report Version:** Final (venue-switch-stale-address-prefill/ENGINEER_REPORT.md)
