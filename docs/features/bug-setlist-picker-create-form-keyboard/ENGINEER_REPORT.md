# Engineer Report

## Feature Slug

bug/setlist-picker-create-form-keyboard

## Feature Title

Setlist Picker Create Form Hidden Behind Keyboard (duplicate keyboard inset)

## Goal

Remove the duplicate keyboard inset handling in the setlist picker create-new flow so the form remains visible and usable above the keyboard. Keep all existing sheet sizing, animation, and create/list behavior unchanged.

## Architect Tasks Completed

- [x] Task 1 - Opened and reviewed lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart
- [x] Task 2 - Confirmed the local keyboard inset logic existed as AnimatedPadding(bottom: keyboardHeight)
- [x] Task 3 - Removed only the redundant keyboard padding wrapper; kept form/list layout intact
- [x] Task 4 - Preserved mainAxisMaxRatio: 0.85 and useSafeArea: true at sheet invocation
- [x] Task 5 - Verified create flow structure and visibility path in code (Column + Flexible + \_buildCreateNewForm)
- [x] Task 6 - Ran required validation commands and confirmed no out-of-scope file edits

## Files Created

- docs/features/bug-setlist-picker-create-form-keyboard/ENGINEER_REPORT.md

## Files Modified

- lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart

## Analyzer Results

Command: flutter analyze
Result: 0 errors, 0 warnings introduced

## Test Results

Passed
Command: flutter test
Result: All tests passed

## Code Efficiency / Bloat Check

Confirmed no dead code, unused imports/variables/parameters, redundant restating comments, single-use wrapper abstractions, or unnecessary defensive checks in the diff. The diff is a direct minimal removal of duplicated inset behavior.

## Verification

Manual steps performed:

- Traced Catalog Select -> Move to setlist -> Create New Setlist code path in lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart.
- Verified build() no longer reads MediaQuery viewInsets into keyboardHeight and no longer wraps content in AnimatedPadding(bottom: keyboardHeight).
- Verified \_buildCreateNewForm() remains mounted under the same Column/Flexible container, so available height is no longer reduced a second time.
- Verified setlist-list path remains unchanged: \_isCreatingNew false still renders \_buildSetlistList(selectableSetlists) and does not depend on keyboardHeight.
- Verified showSetlistPickerBottomSheet() still uses mainAxisMaxRatio: 0.85 and useSafeArea: true.

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes

## Git Diff

```diff
diff --git a/lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart b/lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart
index 392450a..9e6960d 100644
--- a/lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart
+++ b/lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart
@@ -234,9 +234,6 @@ class _SetlistPickerSheetState extends ConsumerState<_SetlistPickerSheet>
     final selectableSetlists =
         setlistsState.setlists.where((s) => !s.isCatalog).toList();

-    // Get keyboard height to push content above keyboard
-    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
-
     return AnimatedBuilder(
       animation: _animController,
       builder: (context, child) {
@@ -245,29 +242,25 @@ class _SetlistPickerSheetState extends ConsumerState<_SetlistPickerSheet>
           child: Opacity(opacity: _fadeAnimation.value, child: child),
         );
       },
-      child: AnimatedPadding(
-        duration: const Duration(milliseconds: 100),
-        padding: EdgeInsets.only(bottom: keyboardHeight),
-        child: Container(
-          margin: const EdgeInsets.all(16),
-          decoration: BoxDecoration(
-            color: context.colors.surface,
-            borderRadius: BorderRadius.circular(Spacing.cardRadius),
-          ),
-          child: Column(
-            mainAxisSize: MainAxisSize.min,
-            children: [
-              // Header
-              _buildHeader(),
-
-              // Content (existing setlists or create new)
-              Flexible(
-                child: _isCreatingNew
-                    ? _buildCreateNewForm()
-                    : _buildSetlistList(selectableSetlists),
-              ),
-            ],
-          ),
+      child: Container(
+        margin: const EdgeInsets.all(16),
+        decoration: BoxDecoration(
+          color: context.colors.surface,
+          borderRadius: BorderRadius.circular(Spacing.cardRadius),
+        ),
+        child: Column(
+          mainAxisSize: MainAxisSize.min,
+          children: [
+            // Header
+            _buildHeader(),
+
+            // Content (existing setlists or create new)
+            Flexible(
+              child: _isCreatingNew
+                  ? _buildCreateNewForm()
+                  : _buildSetlistList(selectableSetlists),
+            ),
+          ],
         ),
       ),
     );
```
