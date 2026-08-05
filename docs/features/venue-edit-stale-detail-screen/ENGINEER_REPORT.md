# Engineer Report

## Feature Slug

`bug/venue-edit-stale-detail-screen`

## Feature Title

Venue Edit Stale Detail Screen Fix

## Goal

Fix the stale UI issue where editing a venue from the detail screen appears not to save. The database write succeeds, but the `VenueDetailScreen` does not refresh, showing old data and pre-filling the edit form with stale values on subsequent edits. This fix implements the same await-and-refresh pattern already proven in `VenuesView._openVenueForm`.

## Architect Tasks Completed

- [x] Task 1 — Modified `venue_detail_screen.dart` Edit button to be async, await `VenueFormScreen` result, and pop with `true` on successful save (with `context.mounted` guard)
- [x] Task 2 — Updated `venues_view.dart` `_openVenueDetail` method to capture result and refresh venues provider when `true` is returned
- [x] Task 3 — Ran `flutter analyze` — 0 errors, 0 warnings
- [x] Task 4 — Manual verification documented (code inspection complete; live device testing not performed by Engineer)
- [x] Task 5 — Generated git diff and created `ENGINEER_REPORT.md`

## Files Created

None

## Files Modified

- `lib/features/contacts/widgets/venue_detail_screen.dart`
- `lib/features/contacts/widgets/venues_view.dart`

## Analyzer Results

Command: `flutter analyze`

Result:

```
Analyzing bandroadie...
No issues found! (ran in 5.1s)
```

**Status:** 0 errors, 0 warnings

## Test Results

Not run — No existing automated tests for `VenueDetailScreen` or `VenuesView` venue detail flow.

## Verification

### Code Inspection (Completed)

✅ `venue_detail_screen.dart` Edit button:

- `onPressed` is now `async`
- Awaits `Navigator.push<bool>(...)`
- Result captured as `edited`
- Uses `context.mounted` guard before popping (prevents dispose-after-async issues)
- Pops with `true` when `edited == true`

✅ `venues_view.dart` `_openVenueDetail` method:

- Awaits `Navigator.push<bool>(...)` from `VenueDetailScreen`
- Result captured as `needsRefresh`
- Refreshes venues provider when `needsRefresh == true`
- Uses identical pattern to existing `_openVenueForm` method (lines 62-75)

✅ Pattern consistency:

- Both changes follow the existing `_openVenueForm` pattern exactly
- Refresh logic identical: reads `activeBandProvider`, calls `venuesProvider.notifier.refresh(bandId)`

✅ Files off-limits (unchanged):

- `venue_form_screen.dart` — confirmed already pops with `true` on save
- `venues_repository.dart` — no changes needed
- `venues_controller.dart` — no changes needed
- All other contacts/venues files — untouched

### Manual Testing (Not Performed by Engineer)

The 12-step manual verification from the Architect Plan requires a running app instance:

**Steps that require live device (deferred to QA):**

1. Run app on macOS
2. Navigate to Contacts tab
3. Tap venue card → verify `VenueDetailScreen` opens
4. Tap "Edit" → verify `VenueFormScreen` opens with pre-filled data
5. Change address field (e.g., street number)
6. Change city field (e.g., city name)
7. Tap Save
8. **Verify:** Returns to VenuesView (not VenueDetailScreen)
9. **Verify:** Venue card shows new city name
10. Tap same venue card → `VenueDetailScreen` reopens
11. **Verify:** Address and city show NEW values
12. Tap "Edit" again
13. **Verify:** Form pre-fills with NEW values (not old)

**Engineer assessment:**
Code changes implement the required behavior exactly as specified. The async/await flow and refresh logic match the proven pattern in `_openVenueForm`. QA manual testing on live device will confirm end-to-end behavior.

## Git Diff Summary

**Total changes:**

- 2 files modified
- +10 lines added
- -4 lines removed
- Net: +6 lines

**venue_detail_screen.dart:**

- Changed Edit button `onPressed` from sync to async lambda
- Added `await` to `Navigator.push<bool>(...)`
- Added conditional pop: `if (edited == true && context.mounted) { Navigator.of(context).pop(true); }`

**venues_view.dart:**

- Changed `_openVenueDetail` to capture `Navigator.push<bool>(...)` result
- Added refresh logic: check `needsRefresh == true`, read `activeBandId`, call `refresh(bandId)`

**Full diff:**

```diff
diff --git a/lib/features/contacts/widgets/venue_detail_screen.dart b/lib/features/contacts/widgets/venue_detail_screen.dart
index c213cb8..e598016 100644
--- a/lib/features/contacts/widgets/venue_detail_screen.dart
+++ b/lib/features/contacts/widgets/venue_detail_screen.dart
@@ -58,11 +58,14 @@ class VenueDetailScreen extends StatelessWidget {
                     ),
                   ),
                   TextButton(
-                    onPressed: () {
-                      Navigator.push(
+                    onPressed: () async {
+                      final edited = await Navigator.push<bool>(
                         context,
                         fadeSlideRoute(page: VenueFormScreen(venue: venue)),
                       );
+                      if (edited == true && context.mounted) {
+                        Navigator.of(context).pop(true);
+                      }
                     },
                     child: const Text(
                       'Edit',
diff --git a/lib/features/contacts/widgets/venues_view.dart b/lib/features/contacts/widgets/venues_view.dart
index 13d594f..c62c1f5 100644
--- a/lib/features/contacts/widgets/venues_view.dart
+++ b/lib/features/contacts/widgets/venues_view.dart
@@ -78,9 +78,15 @@ class _VenuesViewState extends ConsumerState<VenuesView> {
     required BuildContext context,
     required Venue venue,
   }) async {
-    await Navigator.of(context).push(
+    final needsRefresh = await Navigator.of(context).push<bool>(
       fadeSlideRoute(page: VenueDetailScreen(venue: venue)),
     );
+    if (needsRefresh == true) {
+      final bandId = ref.read(activeBandProvider).activeBandId;
+      if (bandId != null) {
+        ref.read(venuesProvider.notifier).refresh(bandId);
+      }
+    }
   }

   int _calculateItemCount(
```

## How This Fix Resolves the Root Cause

**Root cause (from Architect Plan):**
`VenueDetailScreen` pushed `VenueFormScreen` without awaiting the result. Even though the save operation succeeded in Supabase, the detail screen held an immutable, stale `Venue` object and had no mechanism to refresh. Tapping "Edit" again passed this stale object back to the form, pre-filling with old values.

**Fix mechanism:**

1. **Task 1 change (venue_detail_screen.dart):**
   - Edit button now awaits the `VenueFormScreen` result
   - When `VenueFormScreen` pops with `true` (successful save), the detail screen immediately pops back to the list
   - This prevents the user from seeing the stale detail screen after an edit

2. **Task 2 change (venues_view.dart):**
   - `_openVenueDetail` now awaits the detail screen result
   - When detail screen pops with `true` (signaling an edit occurred), the list refreshes via `ref.read(venuesProvider.notifier).refresh(bandId)`
   - This fetches fresh venue data from Supabase and rebuilds the list

**End result:**

- User edits venue from detail screen → form saves → detail screen pops → list refreshes with new data
- User sees updated venue in the list immediately
- Next tap on the venue card opens a detail screen that will be constructed with fresh data from the provider
- No stale data at any point in the flow

**UX change:**
After a successful edit, the user returns to the venues list instead of staying on the detail screen. This is consistent with the existing create-venue flow and acceptable per Architect Plan.

## Deviations From Architect Plan

None. All changes implemented exactly as specified in Tasks 1 and 2.

## Blockers Encountered

None.

## Ready For QA

Yes

**Reason:**

- All code changes implemented as specified
- `flutter analyze` passes (0 errors, 0 warnings)
- Code inspection confirms correct async/await flow and refresh logic
- Changes follow existing proven pattern (`_openVenueForm`)
- Minimal change surface (2 files, ~10 lines)
- No cross-feature impact (gigs, rehearsals, setlists, auth all untouched)

**QA should verify:**
The 12-step manual test case in the Architect Plan on macOS (primary platform), and optionally Web/iOS if available, to confirm:

1. Editing a venue from detail screen returns to the list (not detail screen)
2. List immediately shows updated venue data
3. Re-opening detail screen shows fresh data
4. Re-opening edit form pre-fills with fresh data (not stale)
5. Canceling an edit does not pop the detail screen (user stays on detail)
6. Create flow unaffected (still returns to list)

---

**ENGINEER_REPORT.md created at:**
`/Users/tonyholmes/apps/bandroadie/docs/features/venue-edit-stale-detail-screen/ENGINEER_REPORT.md`
