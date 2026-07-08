# Engineer Report

## Feature Slug

`bug/one-calendar-recurring-auto-block`

## Feature Title

One Calendar Recurring Auto-Block (Incomplete Coverage)

## Goal

Fix auto-conflict blocking to propagate block-outs for all occurrences of recurring rehearsals and all dates of multi-date potential gigs, not just the first/main date. This ensures complete conflict protection across bands when One Calendar auto-blocking is enabled.

## Architect Tasks Completed

- [x] Task 1 — Add `autoBlockConflictingDates()` method to `auto_conflict_blocking_service.dart` accepting `List<DateTime> eventDates`, reads preferences/bands once, nested loop through dates and bands, per-band-per-date try-catch
- [x] Task 2 — Update `createRehearsal()` in `events_repository.dart` (line ~164) to call `autoBlockConflictingDates()` passing `dates` list from line 91
- [x] Task 3 — Update `createGig()` in `events_repository.dart` (line ~647) to build date list from `formData.date` + `formData.additionalDates`, call `autoBlockConflictingDates()` with full list

## Files Created

- none

## Files Modified

- `lib/features/calendar/auto_conflict_blocking_service.dart` — Added new multi-date method `autoBlockConflictingDates()` (102 lines)
- `lib/features/events/events_repository.dart` — Updated two call sites to use new method (14 lines changed, 10 insertions)

## Analyzer Results

Command: `flutter analyze`

**Result:** 0 errors, 4 warnings

All warnings are pre-existing deprecation warnings in setlist-related files (off-limits per Architect plan):

- `lib/features/setlists/new_setlist_screen.dart:984:13` — `onReorder` deprecated
- `lib/features/setlists/setlist_detail_screen.dart:1716:29` — `axisAlignment` deprecated
- `lib/features/setlists/setlist_detail_screen.dart:2295:23` — `onReorder` deprecated
- `lib/features/setlists/setlists_tab_content.dart:511:25` — `onReorder` deprecated

**No new warnings introduced by this implementation.**

## Test Results

Not run — Architect plan did not specify test execution requirements. Manual testing plan provided in ARCHITECT_PLAN.md sections "Engineer Task Breakdown" (Tasks 4-6) and "Verification Plan" (POST-DEPLOY TEST 4-6).

## Verification

Manual steps performed:

- ✅ Verified session preconditions: correct branch (`bug/one-calendar-recurring-auto-block`), clean working tree
- ✅ Read and followed ENGINEER.md, GUARDRAILS.md, and ARCHITECT_PLAN.md in full
- ✅ Implemented exactly as specified in Architect plan pseudo-code
- ✅ Maintained existing error handling patterns (per-band-per-date try-catch)
- ✅ Preserved single-date method `autoBlockConflictingDate()` for backward compatibility
- ✅ No formatting changes outside edited regions
- ✅ Flutter analyze passed with 0 errors
- ✅ Git diff confirmed only two approved files changed

## Deviations From Architect Plan

None — Implementation follows the plan exactly:

- New method signature matches specification
- Preference/band resolution extracted outside date loop (optimal database query pattern)
- Nested loop structure (dates × bands) as specified
- Per-band-per-date error isolation preserved
- Both call sites updated with correct date list construction

## Blockers Encountered

None

## Ready For QA

Yes

---

## Implementation Summary

### Task 1: Multi-Date Auto-Blocking Method

Added `autoBlockConflictingDates()` to `auto_conflict_blocking_service.dart`:

- Accepts `List<DateTime> eventDates` parameter
- Reads preferences once via `getPreferences()` (early return if disabled)
- Reads user's bands once via `band_members` query
- Resolves target bands once via `getBandIdsToApplyBlockOut()`
- Nested loop: outer iterates `eventDates`, inner iterates `otherBandIds`
- Per-band-per-date try-catch for error isolation (duplicate dates or other errors)
- Debug logging shows date count and per-band-per-date results

### Task 2: Rehearsal Creation Integration

Updated `events_repository.dart` line 161:

- Changed method call from `autoBlockConflictingDate()` (singular) to `autoBlockConflictingDates()` (plural)
- Changed parameter from `eventDate: firstRehearsal.date` to `eventDates: dates`
- The `dates` list (generated at line 91) contains all recurring occurrence dates
- One-off rehearsals: list has 1 element (no behavior change)
- Recurring rehearsals: list has N elements (all occurrences now blocked)

### Task 3: Gig Creation Integration

Updated `events_repository.dart` line 644:

- Built combined date list: `[formData.date, ...formData.additionalDates.map((e) => e.date)]`
- Changed method call from `autoBlockConflictingDate()` to `autoBlockConflictingDates()`
- Changed parameter from `eventDate: formData.date` to `eventDates: allDates`
- One-date gigs: list has 1 element (no behavior change)
- Multi-date potential gigs: list has main date + additional dates (all now blocked)

### Database Query Optimization

**Before (Broken):**

- 1 occurrence blocked (first/main date only)
- 1 preference read, 1 `band_members` query, N block-out inserts

**After (Fixed):**

- All occurrences blocked
- 1 preference read, 1 `band_members` query, (dates × bands) block-out inserts
- No N+1 query problem: preference/band resolution extracted outside loop

**Example (4-week recurring, 3 other bands):**

- 1 preference read
- 1 `band_members` query
- 12 block-out inserts (4 dates × 3 bands)

### Error Handling Preserved

- Per-band-per-date try-catch ensures one failure doesn't prevent other blocks
- Duplicate date constraint violations logged gracefully
- Top-level try-catch ensures event creation succeeds even if all blocking fails
- No changes to existing error handling pattern

### Backward Compatibility

- Existing `autoBlockConflictingDate()` (singular) method preserved unchanged
- Other potential call sites unaffected
- Both methods can coexist (single-date vs. multi-date scenarios)

---

## Complete Git Diff

```diff
diff --git a/lib/features/calendar/auto_conflict_blocking_service.dart b/lib/features/calendar/auto_conflict_blocking_service.dart
index e54a248..9de1a75 100644
--- a/lib/features/calendar/auto_conflict_blocking_service.dart
+++ b/lib/features/calendar/auto_conflict_blocking_service.dart
@@ -118,6 +118,108 @@ class AutoConflictBlockingService {
       debugPrint('[AutoConflictBlockingService] Auto-block error: $e');
     }
   }
+
+  /// Automatically block multiple dates on other bands when recurring events are created
+  ///
+  /// [userId] - The user who is confirming the event
+  /// [eventBandId] - The band where the event is being created
+  /// [eventDates] - List of event dates to block
+  /// [eventStartTime] - The start time of the event (for rehearsals)
+  /// [eventEndTime] - The end time of the event (for rehearsals, optional)
+  /// [eventName] - The name of the event (for display in block-out reason)
+  /// [bandName] - The name of the band (for display in block-out reason)
+  Future<void> autoBlockConflictingDates({
+    required String userId,
+    required String eventBandId,
+    required List<DateTime> eventDates,
+    DateTime? eventStartTime,
+    DateTime? eventEndTime,
+    required String eventName,
+    required String bandName,
+  }) async {
+    debugPrint(
+      '[AutoConflictBlockingService] Auto-blocking ${eventDates.length} date(s) for user: $userId, event: $eventName',
+    );
+
+    try {
+      // Check if user has auto-conflict blocking enabled
+      final prefs = await _prefsRepository.getPreferences();
+
+      if (!prefs.oneCalendarEnabled || !prefs.autoBlockConflictsEnabled) {
+        debugPrint(
+          '[AutoConflictBlockingService] Auto-block disabled, skipping',
+        );
+        return;
+      }
+
+      // Fetch user's bands from database
+      final bandsResponse = await supabase
+          .from('band_members')
+          .select('band_id')
+          .eq('user_id', userId);
+
+      final userBandIds = (bandsResponse as List)
+          .map((row) => row['band_id'] as String)
+          .toList();
+
+      // Get band IDs where block-out should be propagated
+      final bandIds = await _prefsRepository.getBandIdsToApplyBlockOut(
+        userBandIds,
+      );
+
+      // Remove the event band (user is already busy in that band)
+      final otherBandIds = bandIds.where((id) => id != eventBandId).toList();
+
+      if (otherBandIds.isEmpty) {
+        debugPrint(
+          '[AutoConflictBlockingService] No other bands to block, skipping',
+        );
+        return;
+      }
+
+      // Generate block-out reason
+      final reason = 'Unavailable (scheduled with $bandName)';
+
+      // Loop through all dates
+      for (final eventDate in eventDates) {
+        // Use only the date (not time) for block-out
+        final blockOutDate = DateTime(
+          eventDate.year,
+          eventDate.month,
+          eventDate.day,
+        );
+
+        // Loop through all other bands
+        for (final bandId in otherBandIds) {
+          try {
+            await _blockOutRepository.createBlockOut(
+              bandId: bandId,
+              userId: userId,
+              startDate: blockOutDate,
+              untilDate: null, // Single day
+              reason: reason,
+            );
+            debugPrint(
+              '[AutoConflictBlockingService] Auto-blocked date $blockOutDate for band: $bandId',
+            );
+          } catch (e) {
+            // Skip duplicates or errors for individual bands
+            // (user may have already manually blocked the date)
+            debugPrint(
+              '[AutoConflictBlockingService] Failed to auto-block for band $bandId date $blockOutDate: $e',
+            );
+          }
+        }
+      }
+
+      debugPrint(
+        '[AutoConflictBlockingService] Auto-block complete: ${eventDates.length} date(s) × ${otherBandIds.length} bands',
+      );
+    } catch (e) {
+      // Do not fail the primary operation if auto-blocking fails
+      debugPrint('[AutoConflictBlockingService] Auto-block error: $e');
+    }
+  }
 }

 // ============================================================================
diff --git a/lib/features/events/events_repository.dart b/lib/features/events/events_repository.dart
index 25a1be6..12fac29 100644
--- a/lib/features/events/events_repository.dart
+++ b/lib/features/events/events_repository.dart
@@ -158,10 +158,10 @@ class EventsRepository {
                 .single();
             final bandName = bandResponse['name'] as String;

-            await _autoConflictBlockingService.autoBlockConflictingDate(
+            await _autoConflictBlockingService.autoBlockConflictingDates(
               userId: userId,
               eventBandId: bandId,
-              eventDate: firstRehearsal.date,
+              eventDates: dates,
               eventStartTime: null,
               eventEndTime: null,
               eventName: 'Rehearsal',
@@ -641,10 +641,16 @@ class EventsRepository {
             .single();
         final bandName = bandResponse['name'] as String;

-        await _autoConflictBlockingService.autoBlockConflictingDate(
+        // Build date list: main date + additional dates
+        final allDates = [
+          formData.date,
+          ...formData.additionalDates.map((e) => e.date),
+        ];
+
+        await _autoConflictBlockingService.autoBlockConflictingDates(
           userId: userId,
           eventBandId: bandId,
-          eventDate: formData.date,
+          eventDates: allDates,
           eventStartTime: null,
           eventEndTime: null,
           eventName: formData.name ?? formData.displayName,
```

---

## Stats

- Files changed: 2
- Lines added: 112
- Lines removed: 4
- Net change: +108 lines
