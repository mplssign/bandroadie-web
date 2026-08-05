# Engineer Report

## Feature Slug

`bug/venue-switch-stale-address-prefill`

## Feature Title

Fix Stale Address When Switching Between Linked Venues

## Goal

Fix the bug where switching from one linked venue to another in the gig editor drawer retains the previous venue's address data in the form fields, leading to potential data corruption when the sync-back dialog offers to "update" the newly selected venue with stale data from the previous venue.

## Architect Tasks Completed

- [x] Task 1 — Locate and Read Target Method — Located `_handleGigNameSelected()` in event_editor_drawer.dart (lines 746-793)
- [x] Task 2 — Implement Venue-Switch Detection — Added `previousVenueId` and `isSwitchingVenues` local variables before setState
- [x] Task 3 — Replace Prefill Logic with Conditional Paths — Implemented if/else branch with venue-switch path (unconditional update) and initial-link path (only-fill-if-empty)
- [x] Task 4 — Verify Syntax and Analyze — Ran `flutter analyze`, passed with 0 errors, 0 warnings
- [x] Task 5 — Generate Diff — Generated git diff and included below

## Files Created

- none

## Files Modified

- `lib/features/events/widgets/event_editor_drawer.dart` (lines 746-793, `_handleGigNameSelected()` method)

## Analyzer Results

Command: `flutter analyze`
Result: **No issues found!** (0 errors, 0 warnings)

## Test Results

Not run — Manual UI testing per Architect plan verification section (Tier 2) to be performed by QA. No automated tests exist for this UI interaction flow.

## Verification

Implementation changes verified:

- Two local variables added before `if (mounted)` block to capture previous venue ID and detect venue switches
- Prefill logic replaced with conditional branching:
  - **Venue switch branch**: Unconditionally assigns new venue's values (using `?? ''` for null safety), clearing stale data
  - **Initial link branch**: Preserves existing "only fill if empty" logic to protect manually-entered addresses
- Updated comment to reflect both scenarios
- `_markDirty()` call remains at end of method
- No other lines in the file modified
- Analyzer passes with zero issues

## Deviations From Architect Plan

None — Implementation follows Section 14 task breakdown exactly.

## Blockers Encountered

None

## Ready For QA

Yes — Implementation complete, analyzer clean, ready for manual UI testing per Section 15 of Architect plan.

---

## Git Diff

```diff
diff --git a/lib/features/events/widgets/event_editor_drawer.dart b/lib/features/events/widgets/event_editor_drawer.dart
index 1126f79..a710c67 100644
--- a/lib/features/events/widgets/event_editor_drawer.dart
+++ b/lib/features/events/widgets/event_editor_drawer.dart
@@ -765,27 +765,38 @@ class _EventEditorDrawerState extends ConsumerState<EventEditorDrawer>
       }
     }

+    // Capture previous venue ID to detect venue switches
+    final previousVenueId = _selectedVenueId;
+    final isSwitchingVenues = previousVenueId != null && previousVenueId != selectedVenue.id;
+
     if (mounted) {
       setState(() {
         _selectedVenueId = selectedVenue.id;

-        // Only fill empty fields to avoid clobbering user-entered values.
-        if (selectedVenue.city != null &&
-            selectedVenue.city!.isNotEmpty &&
-            _locationController.text.trim().isEmpty) {
-          _locationController.text = selectedVenue.city!;
-        }
+        if (isSwitchingVenues) {
+          // Switching from one venue to another — always sync to new venue's values
+          _locationController.text = selectedVenue.city ?? '';
+          _addressController.text = selectedVenue.address ?? '';
+          _stateController.text = selectedVenue.state?.toUpperCase() ?? '';
+        } else {
+          // Initial link — only fill empty fields to preserve user-entered values
+          if (selectedVenue.city != null &&
+              selectedVenue.city!.isNotEmpty &&
+              _locationController.text.trim().isEmpty) {
+            _locationController.text = selectedVenue.city!;
+          }

-        if (selectedVenue.address != null &&
-            selectedVenue.address!.isNotEmpty &&
-            _addressController.text.trim().isEmpty) {
-          _addressController.text = selectedVenue.address!;
-        }
+          if (selectedVenue.address != null &&
+              selectedVenue.address!.isNotEmpty &&
+              _addressController.text.trim().isEmpty) {
+            _addressController.text = selectedVenue.address!;
+          }

-        if (selectedVenue.state != null &&
-            selectedVenue.state!.isNotEmpty &&
-            _stateController.text.trim().isEmpty) {
-          _stateController.text = selectedVenue.state!.toUpperCase();
+          if (selectedVenue.state != null &&
+              selectedVenue.state!.isNotEmpty &&
+              _stateController.text.trim().isEmpty) {
+            _stateController.text = selectedVenue.state!.toUpperCase();
+          }
         }
       });
     }
```

---

## Implementation Summary

Modified `_handleGigNameSelected()` method to detect venue switches versus initial venue links:

**Key changes:**

1. Added `previousVenueId` local variable to capture the venue ID before state update
2. Added `isSwitchingVenues` boolean condition that is true when `previousVenueId` is non-null AND differs from the newly selected venue's ID
3. Split address prefill logic into two branches:
   - **Venue switch**: Unconditionally overwrites all address/city/state fields with new venue's values (or empty string if venue field is null), ensuring stale data is cleared
   - **Initial link**: Preserves original "only fill if empty" behavior to protect manually-entered addresses

This fix prevents the bug where switching from Venue A to Venue B would leave Venue A's stale address in the form fields, which would trigger an incorrect sync-back dialog offering to overwrite Venue B's contact card with Venue A's data.

**Scope discipline maintained:**

- Only the specified method modified
- No changes to `_venueNeedsUpdate()` or `_syncVenueData()` (lines 795-863)
- No changes to any other files
- No database, schema, or RPC changes
- No new dependencies or state variables
