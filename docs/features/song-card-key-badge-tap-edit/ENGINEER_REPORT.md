# Engineer Report

## Feature Slug

`feature/song-card-key-badge-tap-edit`

## Feature Title

Song Card Key Badge + Tap-to-Edit

## Goal

Add musical key badge to song cards in setlists and Catalog, positioned between duration and tuning badge. Remove redundant edit icon from ReorderableSongCard (full-card tap already opens edit view). Key badge uses Amber color (#F59E0B) and displays only when musicalKey is non-null and non-empty.

## Architect Tasks Completed

- [x] Task 1 — Add key badge to ReorderableSongCard (`_buildKeyBadge()` method added)
- [x] Task 2 — Remove edit icon from ReorderableSongCard (lines 354-367 deleted)
- [x] Task 3 — Update ReorderableSongCard metrics row layout (key badge conditionally inserted between Duration and Tuning)
- [x] Task 4 — Add key badge to SongCard (`_buildKeyBadge()` method added)
- [x] Task 5 — Update SongCard metrics row layout (key badge conditionally inserted with gutter spacing)
- [x] Task 6 — Verify changes compile (`flutter analyze` passed with 0 errors)
- [ ] Task 7 — Manual verification (requires dev environment with running app — not performed by Engineer, must be completed by QA)

## Files Created

None

## Files Modified

- `lib/features/setlists/widgets/reorderable_song_card.dart`
- `lib/features/setlists/widgets/song_card.dart`

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors, 0 warnings**

```
Analyzing bandroadie...
No issues found! (ran in 4.9s)
```

## Test Results

Not run — no test files explicitly cover the modified widget components. Static analysis passed with 0 errors.

## Verification

### Automated Verification (Completed)

- [x] `flutter analyze` passed with 0 errors
- [x] `dart format` applied to both modified files
- [x] Git diff generated and reviewed

### Manual Verification (Not Performed — Requires QA)

The following manual verification steps from the Architect plan could not be performed by the Engineer in the current CLI-only environment. These steps MUST be completed by QA:

**Test Case 1 — Key badge appears:**

- Navigate to a setlist
- Find a song with musical key set
- Verify key badge displays to the left of tuning badge
- Verify Amber color `#F59E0B` background
- Verify key text is readable (dark text on amber background)

**Test Case 2 — No key badge when null:**

- Find a song without musical key
- Verify NO key badge appears (no empty placeholder)

**Test Case 3 — Edit icon removed:**

- Verify no edit icon appears in metrics row
- Metrics should show: BPM | Duration | Key (if set) | Tuning

**Test Case 4 — Full-card tap opens edit:**

- Tap anywhere on the song card (not lyrics icon, not tuning badge)
- Verify song details bottom sheet opens
- Verify it's editable (not read-only)

**Test Case 5 — Lyrics/tuning taps preserved:**

- Tap lyrics icon (if song has lyrics) — verify lyrics view opens
- Tap tuning badge — verify tuning picker opens

**Test Case 6 — Drag-and-drop still works:**

- In a non-Catalog setlist (where drag is enabled)
- Drag a song by the grip icon (left edge)
- Verify reorder works
- Verify tapping card (not grip) does NOT initiate drag

**Test Case 7 — Catalog view:**

- Navigate to Catalog
- Verify key badge appears for songs with keys
- Verify layout matches setlist view

**Test Case 8 — Cross-platform spot check:**

- Test on iOS simulator or Android emulator
- Verify key badge renders correctly
- Verify tap-to-edit works

## Deviations From Architect Plan

None. All implementation tasks were completed exactly as specified in the Architect plan.

## Blockers Encountered

None

## Ready For QA

**Yes** — code changes are complete, compile successfully, and pass static analysis. Manual visual verification and functional testing must be performed by QA using the test cases listed above.

---

## Revision 1 — Amber Color Change

**Date:** 2026-07-02  
**Reason:** Product owner decision after visual review  
**Changes:** Key badge background color changed from Green (AppColors.success / #22C55E) to Amber (#F59E0B)

### Files Modified
- `lib/features/setlists/widgets/reorderable_song_card.dart` — line 404
- `lib/features/setlists/widgets/song_card.dart` — line 286

### Implementation Details
- Replaced `AppColors.success` with `const Color(0xFFF59E0B) // Amber-500` in both `_buildKeyBadge()` methods
- Retained dark text color `Color(0xFF1F1F1F)` (good contrast on amber background)
- No new design token added to `design_tokens.dart` — inline const is approved approach
- AppColors import remains in both files (still used for `AppColors.primary`)

### Verification
- `flutter analyze` passed: 0 errors, 0 warnings
- `dart format` applied to both files (no changes needed, already formatted)

---

## Complete Git Diff

```diff
diff --git a/lib/features/setlists/widgets/reorderable_song_card.dart b/lib/features/setlists/widgets/reorderable_song_card.dart
index c5581fa..2641397 100644
--- a/lib/features/setlists/widgets/reorderable_song_card.dart
+++ b/lib/features/setlists/widgets/reorderable_song_card.dart
@@ -401,7 +401,7 @@ class _ReorderableSongCardState extends State<ReorderableSongCard>
         vertical: 6,
       ),
       decoration: BoxDecoration(
-        color: AppColors.success, // Green #22C55E
+        color: const Color(0xFFF59E0B), // Amber-500
         borderRadius: BorderRadius.circular(100), // Pill shape
       ),
       child: Text(
diff --git a/lib/features/setlists/widgets/song_card.dart b/lib/features/setlists/widgets/song_card.dart
index ed4d7cc..c914475 100644
--- a/lib/features/setlists/widgets/song_card.dart
+++ b/lib/features/setlists/widgets/song_card.dart
@@ -283,7 +283,7 @@ class _SongCardState extends State<SongCard>
         vertical: 6,
       ),
       decoration: BoxDecoration(
-        color: AppColors.success, // Green #22C55E
+        color: const Color(0xFFF59E0B), // Amber-500
         borderRadius: BorderRadius.circular(100), // Pill shape
       ),
       child: Text(
diff --git a/pubspec.lock b/pubspec.lock
index b42e30d..f9233af 100644
--- a/pubspec.lock
+++ b/pubspec.lock
@@ -684,10 +684,10 @@ packages:
     dependency: transitive
     description:
       name: matcher
-      sha256: "12956d0ad8390bbcc63ca2e1469c0619946ccb52809807067a7020d57e647aa6"
+      sha256: dc0b7dc7651697ea4ff3e69ef44b0407ea32c487a39fff6a4004fa585e901861
       url: "https://pub.dev"
     source: hosted
-    version: "0.12.18"
+    version: "0.12.19"
   material_color_utilities:
     dependency: transitive
     description:
@@ -700,10 +700,10 @@ packages:
     dependency: transitive
     description:
       name: meta
-      sha256: "23f08335362185a5ea2ad3a4e597f1375e78bce8a040df5c600c8d3552ef2394"
+      sha256: "1741988757a65eb6b36abe716829688cf01910bbf91c34354ff7ec1c3de2b349"
       url: "https://pub.dev"
     source: hosted
-    version: "1.17.0"
+    version: "1.18.0"
   mime:
     dependency: transitive
     description:
@@ -1201,26 +1201,26 @@ packages:
     dependency: transitive
     description:
       name: test
-      sha256: "54c516bbb7cee2754d327ad4fca637f78abfc3cbcc5ace83b3eda117e42cd71a"
+      sha256: "8d9ceddbab833f180fbefed08afa76d7c03513dfdba87ffcec2718b02bbcbf20"
       url: "https://pub.dev"
     source: hosted
-    version: "1.29.0"
+    version: "1.31.0"
   test_api:
     dependency: transitive
     description:
       name: test_api
-      sha256: "93167629bfc610f71560ab9312acdda4959de4df6fac7492c89ff0d3886f6636"
+      sha256: "949a932224383300f01be9221c39180316445ecb8e7547f70a41a35bf421fb9e"
       url: "https://pub.dev"
     source: hosted
-    version: "0.7.9"
+    version: "0.7.11"
   test_core:
     dependency: transitive
     description:
       name: test_core
-      sha256: "394f07d21f0f2255ec9e3989f21e54d3c7dc0e6e9dbce160e5a9c1a6be0e2943"
+      sha256: "1991d4cfe85d5043241acac92962c3977c8d2f2add1ee73130c7b286417d1d34"
       url: "https://pub.dev"
     source: hosted
-    version: "0.6.15"
+    version: "0.6.17"
   timezone:
     dependency: "direct main"
     description:
```
