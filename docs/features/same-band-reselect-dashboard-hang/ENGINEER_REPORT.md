# Engineer Report

## Feature Slug

bug/same-band-reselect-dashboard-hang

## Feature Title

Dashboard Hang on Same-Band Reselection

## Goal

Fix permanent loading spinner when user taps the currently active band in the band switcher. The bug caused the dashboard to hang on "Setting up the stage..." indefinitely, requiring app restart. The fix prevents unnecessary provider resets by adding early-return guards when the same band is reselected.

## Architect Tasks Completed

- [x] Task 1 — Add guard in `home_screen.dart` (\_handleBandSelected method, line 158)
- [x] Task 2 — Add guard in `app_shell.dart` (onBandSelected callback, line 311)
- [x] Task 3 — Add guard in `calendar_screen.dart` (\_handleBandSelected method, line 151)
- [x] Task 4 — Add guard in `setlists_screen.dart` (\_handleBandSelected method, line 415)
- [x] Task 5 — Verified no other call sites (grep confirmed only 4 call sites modified)
- [x] Task 6 — Ran analyzer (0 errors)

## Files Created

None

## Files Modified

- `lib/features/home/home_screen.dart` — Added same-band guard (+3 lines)
- `lib/features/shell/app_shell.dart` — Added same-band guard (+3 lines)
- `lib/features/calendar/calendar_screen.dart` — Added same-band guard (+3 lines)
- `lib/features/setlists/setlists_screen.dart` — Added same-band guard (+3 lines)

## Analyzer Results

Command: `flutter analyze`
Result: No issues found! (ran in 6.5s)

- 0 errors
- 0 warnings
- 0 new issues introduced

## Test Results

Not run — Architect plan specifies manual UI testing only (no automated tests for this bug fix).

## Verification

Automated verification completed:

- `flutter analyze` passed with 0 errors
- `dart format` confirmed all files already properly formatted (0 changes)
- `grep -r "resetForBandChange" lib/` confirmed no additional call sites beyond the 4 modified

Manual verification planned for QA phase (see Architect Plan section 16 for full regression test matrix):

- Same-band reselection from all 4 screens (Dashboard, Calendar, Setlists, AppBar)
- Different-band selection still triggers reload correctly
- Behavior tested on Android, iOS, Web, macOS platforms

## Deviations From Architect Plan

**Manager-directed deviation from plan section 10 (guard placement):**

The Architect plan specified placing the guard as the first statement in each handler, BEFORE the close call (`_closeBandSwitcher()` / `onClose()`). However, the Manager verified that `_BandListItem.onTap` (line ~171 in `lib/features/home/widgets/band_switcher.dart`) calls only `onBandSelected(band)` — the switcher does NOT close itself.

**Issue with original plan:** With the guard placed before the close call, tapping the already-active band would early-return while the switcher stays open (dead tap). This fails the plan's QA scenario #1: "Drawer closes, dashboard shows existing data immediately."

**Manager-directed fix:** Move the close call ABOVE the guard in all four handlers:
- `lib/features/home/home_screen.dart` `_handleBandSelected`: `_closeBandSwitcher();` first, then guard
- `lib/features/calendar/calendar_screen.dart` `_handleBandSelected`: `_closeBandSwitcher();` first, then guard
- `lib/features/setlists/setlists_screen.dart` `_handleBandSelected`: `_closeBandSwitcher();` first, then guard
- `lib/features/shell/app_shell.dart` `onBandSelected:` callback: `onClose();` first, then guard

**Final implementation order (all four files):**
1. Close the switcher first
2. Check if same band and early-return
3. Reset providers and select band (only runs for different band)

The guard itself is unchanged: `final currentBandId = ref.read(activeBandIdProvider); if (band.id == currentBandId) return;` — it remains BEFORE any `debugPrint`, `resetForBandChange()`, or `selectBand()` calls, ensuring the switcher always closes even for same-band taps.

## Blockers Encountered

None

## Ready For QA

Yes

---

## Implementation Details

### Git Diff Stats

```
 lib/features/calendar/calendar_screen.dart | 3 +++
 lib/features/home/home_screen.dart         | 3 +++
 lib/features/setlists/setlists_screen.dart | 3 +++
 lib/features/shell/app_shell.dart          | 3 +++
 4 files changed, 12 insertions(+)
```

### Complete Git Diff

```diff
diff --git a/lib/features/calendar/calendar_screen.dart b/lib/features/calendar/calendar_screen.dart
index b9f7dc6..83b3eab 100644
--- a/lib/features/calendar/calendar_screen.dart
+++ b/lib/features/calendar/calendar_screen.dart
@@ -152,6 +152,9 @@ class _CalendarScreenState extends ConsumerState<CalendarScreen>
     // Close the switcher immediately for better UX
     _closeBandSwitcher();
 
+    final currentBandId = ref.read(activeBandIdProvider);
+    if (band.id == currentBandId) return;
+
     // Reset gig/rehearsal state before band switch
     debugPrint('[Dashboard] activeBand changed: ${band.id}');
     ref.read(gigProvider.notifier).resetForBandChange();
diff --git a/lib/features/home/home_screen.dart b/lib/features/home/home_screen.dart
index 19ee296..a750bd7 100644
--- a/lib/features/home/home_screen.dart
+++ b/lib/features/home/home_screen.dart
@@ -159,6 +159,9 @@ class _HomeScreenState extends ConsumerState<HomeScreen>
     // Close the switcher immediately for better UX
     _closeBandSwitcher();
 
+    final currentBandId = ref.read(activeBandIdProvider);
+    if (band.id == currentBandId) return;
+
     // Reset gig/rehearsal state before band switch to clear stale errors
     debugPrint('[Dashboard] activeBand changed: ${band.id}');
     ref.read(gigProvider.notifier).resetForBandChange();
diff --git a/lib/features/setlists/setlists_screen.dart b/lib/features/setlists/setlists_screen.dart
index b17b94a..cfe5109 100644
--- a/lib/features/setlists/setlists_screen.dart
+++ b/lib/features/setlists/setlists_screen.dart
@@ -414,6 +414,9 @@ class _SetlistsScreenState extends ConsumerState<SetlistsScreen>
 
   void _handleBandSelected(Band band) {
     _closeBandSwitcher();
+
+    final currentBandId = ref.read(activeBandIdProvider);
+    if (band.id == currentBandId) return;
     debugPrint('[Dashboard] activeBand changed: ${band.id}');
     ref.read(gigProvider.notifier).resetForBandChange();
     ref.read(rehearsalProvider.notifier).resetForBandChange();
diff --git a/lib/features/shell/app_shell.dart b/lib/features/shell/app_shell.dart
index b6e4f7e..ac28d97 100644
--- a/lib/features/shell/app_shell.dart
+++ b/lib/features/shell/app_shell.dart
@@ -310,6 +310,9 @@ class _BandSwitcherLayer extends ConsumerWidget {
       activeBandId: activeBandId,
       onBandSelected: (band) {
         onClose();
+
+        final currentBandId = ref.read(activeBandIdProvider);
+        if (band.id == currentBandId) return;
         ref.read(gigProvider.notifier).resetForBandChange();
         ref.read(rehearsalProvider.notifier).resetForBandChange();
         ref.read(activeBandProvider.notifier).selectBand(band);
```

---

## Implementation Summary

Added early-return guards to 4 band selection handlers to prevent unnecessary provider resets when user taps the currently active band. This fixes the permanent loading spinner bug while preserving correct behavior for actual band switches. Implementation is minimal (12 lines), localized to UI event handlers, and introduces no architectural changes or new dependencies.

**Manager-directed change:** Close calls moved ABOVE guards (deviation from Architect plan section 10) to ensure the band switcher always closes, even for same-band taps. This prevents a "dead tap" scenario where the switcher would remain open.
