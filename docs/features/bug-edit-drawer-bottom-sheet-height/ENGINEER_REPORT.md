# Engineer Report

## Feature Slug

bug/edit-drawer-bottom-sheet-height

## Feature Title

Edit Drawer / Bottom Sheet Height Fix

## Goal

Increase the maximum height available to edit-mode drawers and sheets while keeping read-only/detail behavior unchanged, and verify the fix with the repository’s required analyzer and test checks.

## Architect Tasks Completed

- [x] Task 1 — Updated `BandMemberEditDrawer.show()` to pass `mainAxisMaxRatio: 0.95`.
- [x] Task 2 — Updated the song details sheet edit-mode height ceiling to `0.95` while leaving the read-only branch at `0.85`.

## Files Created

- none

## Files Modified

- lib/features/contacts/widgets/band_member_edit_drawer.dart
- lib/features/setlists/widgets/song_details_bottom_sheet.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 8 warnings

```text
Analyzing bandroadie...

   info • Use a 'SizedBox' to add whitespace to a layout. Try using a 'SizedBox'
          rather than a 'Container' •
          lib/features/setlists/widgets/reorderable_song_card.dart:187:18 •
          sized_box_for_whitespace
   info • Use a 'SizedBox' to add whitespace to a layout. Try using a 'SizedBox'
          rather than a 'Container' •
          lib/features/setlists/widgets/song_card.dart:113:18 •
          sized_box_for_whitespace
   info • 'anonKey' is deprecated and shouldn't be used. Use publishableKey
          instead. anonKey will be removed in a future major version. Try
          replacing the use of the deprecated member with the replacement •
          lib/main.dart:62:7 • deprecated_member_use
   info • 'anonKey' is deprecated and shouldn't be used. Use publishableKey
          instead. anonKey will be removed in a future major version. Try
          replacing the use of the deprecated member with the replacement •
          lib/main.dart:88:7 • deprecated_member_use
warning • The value of the local variable 'submittedValue' isn't used. Try
       removing the variable or using it •
       test/components/ui/app_text_field_test.dart:312:15 •
       unused_local_variable
warning • The value of the local variable 'editingCompleted' isn't used. Try
       removing the variable or using it •
       test/components/ui/app_text_field_test.dart:416:12 •
       unused_local_variable
warning • The value of the local variable 'tapped' isn't used. Try removing the
       variable or using it • test/components/ui/app_text_field_test.dart:438:12
       • unused_local_variable
warning • The value of the local variable 'submittedValue' isn't used. Try
       removing the variable or using it •
       test/components/ui/app_text_form_field_test.dart:326:15 •
       unused_local_variable

8 issues found. (ran in 5.4s)
```

## Test Results

Passed

```text
00:04 +30: /Users/tonyholmes/apps/bandroadie/test/features/setlists/services/bul
k_song_parser_test.dart: Key column — invalid/unknown values unrecognized key is
 a non-fatal warning, row stays valid
[BulkSongParser] Unknown key: "Zzz"
00:04 +31: /Users/tonyholmes/apps/bandroadie/test/features/setlists/services/bul
k_song_parser_test.dart: Key column — invalid/unknown values enharmonic spelling
 not in the canonical set is unknown (no aliasing)
[BulkSongParser] Unknown key: "Db" -> normalized="Db"
00:13 +176: All tests passed!
```

## Code Efficiency / Bloat Check

Confirmed no dead code, unused imports/variables/parameters, redundant restating comments, single-use wrapper abstractions, or unnecessary defensive checks in the diff.

## Verification

Manual steps performed:

- Verified the repo is on the expected branch: `bug/edit-drawer-bottom-sheet-height`.
- Confirmed the working tree only contains the two scoped source edits plus the required report artifact.
- Reviewed the exact change in the edit-mode height logic for both files and confirmed the read-only path remains at `0.85`.
- Confirmed the `showModalBottomSheet` path in the song sheet was not refactored to the shared wrapper, as required by scope.

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes — the fix is limited to the two approved UI files, preserves read-only behavior, and the repository-level analyzer and test checks passed.

## Full Git Diff

```diff
diff --git a/lib/features/contacts/widgets/band_member_edit_drawer.dart b/lib/features/contacts/widgets/band_member_edit_drawer.dart
index 9f2b704..93916b8 100644
--- a/lib/features/contacts/widgets/band_member_edit_drawer.dart
+++ b/lib/features/contacts/widgets/band_member_edit_drawer.dart
@@ -48,6 +48,7 @@ class BandMemberEditDrawer extends ConsumerStatefulWidget {
       context: context,
       isScrollControlled: true,
       backgroundColor: Colors.transparent,
+      mainAxisMaxRatio: 0.95,
       builder: (_) => BandMemberEditDrawer(
         member: member,
         adminCount: adminCount,
         activeMemberCount: activeMemberCount,
     );
diff --git a/lib/features/setlists/widgets/song_details_bottom_sheet.dart b/lib/features/setlists/widgets/song_details_bottom_sheet.dart
index d74afba..41fd527 100644
--- a/lib/features/setlists/widgets/song_details_bottom_sheet.dart
+++ b/lib/features/setlists/widgets/song_details_bottom_sheet.dart
@@ -904,7 +904,7 @@ class _SongDetailsSheetState extends ConsumerState<_SongDeta
 ilsSheet>
         child: Container(
           margin: EdgeInsets.only(bottom: bottomPadding),
           constraints: BoxConstraints(
-            maxHeight: screenHeight * 0.85,
+            maxHeight: screenHeight * (widget.isReadOnly ? 0.85 : 0.95),
             minHeight: screenHeight * 0.6,
           ),
           decoration: BoxDecoration(
```
