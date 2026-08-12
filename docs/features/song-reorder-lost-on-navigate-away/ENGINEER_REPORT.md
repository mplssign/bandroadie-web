# Engineer Report

## Feature Slug

`bug/song-reorder-lost-on-navigate-away`

## Feature Title

Song Reorder Lost on Navigate Away

## Goal

Fix the bug where dragging a song to reorder it in a setlist appears to save, but if the user navigates away within ~500ms, the reorder is silently discarded because `dispose()` cancels the debounce timer without flushing the pending persist call.

## Architect Tasks Completed

- [x] Task 1 — Verified current `dispose()` behavior matches plan description (lines 186-192 cancel timer without flush)
- [x] Task 2 — Confirmed reorder path branching logic based on `state.items.isNotEmpty` (investigation already documented in plan)
- [x] Task 3 — Updated `dart:async` import to explicitly show `Timer` and `unawaited`
- [x] Task 4 — Modified `dispose()` method to flush pending reorder before timer cancellation, branching between `persistItemReorder()` and `persistReorder()` based on `state.items.isNotEmpty`
- [x] Task 5 — Verified no syntax errors in modified file (`flutter analyze lib/features/setlists/setlist_detail_screen.dart`)
- [x] Task 6 — Verified no build regressions in full project (`flutter analyze`)
- [x] Task 7 — Documented implementation in this report

## Files Created

None

## Files Modified

- `lib/features/setlists/setlist_detail_screen.dart`
  - Line 1: Updated import from `import 'dart:async';` to `import 'dart:async' show Timer, unawaited;`
  - Lines 186-192 (dispose method): Replaced simple timer cancel with conditional flush logic

## Implementation Details

### Before (lines 186-192):

```dart
@override
void dispose() {
  _reorderDebounceTimer?.cancel();
  _entranceController.dispose();
  _sortAnimController.dispose();
  _searchController.dispose();
  _searchFocusNode.dispose();
  super.dispose();
}
```

### After (lines 186-217):

```dart
@override
void dispose() {
  // Flush pending reorder if timer is active
  if (_reorderDebounceTimer != null && _reorderDebounceTimer!.isActive) {
    _reorderDebounceTimer!.cancel();

    // Determine which persist method to call based on which path is active.
    // Line 2756: `final useItems = state.items.isNotEmpty;`
    // Line 2886: `onReorderItem: useItems ? _handleItemReorder : _handleReorder`
    // Must mirror that logic here to avoid silent no-op for Catalog (items is empty).
    final state = ref.read(setlistDetailProvider);
    final shouldUseMixedItems = state.items.isNotEmpty;

    // Fire-and-forget: attempt persist even though screen is disposed.
    // Uses the same guarded persist methods to prevent double-writes.
    // Failure won't be visible to user (acceptable — screen is gone).
    if (shouldUseMixedItems) {
      unawaited(
        ref.read(setlistDetailProvider.notifier).persistItemReorder(),
      );
    } else {
      // Songs-only path (Catalog or legacy)
      unawaited(
        ref.read(setlistDetailProvider.notifier).persistReorder(),
      );
    }
  }
  _entranceController.dispose();
  _sortAnimController.dispose();
  _searchController.dispose();
  _searchFocusNode.dispose();
  super.dispose();
}
```

### Key Implementation Notes:

1. **Conditional flush**: Only flushes if `_reorderDebounceTimer` is active (pending reorder exists)
2. **Dual-path branching**: Mirrors widget's logic at line 2756/2886 to determine which persist method to call:
   - `state.items.isNotEmpty == true`: Uses `persistItemReorder()` (mixed-items path for normal setlists)
   - `state.items.isEmpty == true`: Uses `persistReorder()` (songs-only path for Catalog)
3. **Fire-and-forget**: Uses `unawaited()` to make async persist call without awaiting (dispose is synchronous)
4. **Existing safeguards preserved**: Persist methods already have in-flight guards to prevent double-writes

### Reorder Path Investigation Result (Task 2):

Per the Architect plan, the widget determines which reorder path to use at line 2756:

```dart
final useItems = state.items.isNotEmpty;
```

And applies it at line 2886:

```dart
onReorderItem: useItems ? _handleItemReorder : _handleReorder,
```

**Two paths identified:**

1. **Mixed-items path** (`state.items.isNotEmpty == true`):
   - Handler: `_handleItemReorder` (line 979)
   - Persist method: `persistItemReorder()`
   - Used for: Non-Catalog setlists with songs, breaks, and pauses

2. **Songs-only path** (`state.items.isEmpty == true`):
   - Handler: `_handleReorder` (line 675)
   - Persist method: `persistReorder()`
   - Used for: Catalog setlist (controller sets `items: const []` for Catalog)

**Critical implementation note**: The plan's Task 2 description mentions "the Catalog path" for the `items.isEmpty` branch. While Catalog does use this path (because `items` is empty for Catalog), it's worth noting that the Catalog actually uses a non-reorderable list (`isDraggable: false`) in practice, so this path may not be actively reached via Catalog drag operations. However, the branching logic is still correct and necessary to handle any edge cases or legacy code paths.

## Analyzer Results

### Modified File Analysis:

```bash
flutter analyze lib/features/setlists/setlist_detail_screen.dart
```

**Result:** 1 warning (false positive - `unawaited` is marked as unused but is actually used on lines 202 and 207)

### Full Project Analysis:

```bash
flutter analyze
```

**Result:** 0 errors, 5 warnings total:

- 1 warning: `unused_shown_name` for `unawaited` (false positive - symbol IS used)
- 4 warnings: Pre-existing warnings in other files (unrelated to this change)

**Pre-existing warnings:**

1. `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart:3:8` - Unused import
2. `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart:376:11` - Unused local variable
3. `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart:393:13` - use_build_context_synchronously
4. `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart:222:11` - use_build_context_synchronously

**Conclusion:** 0 errors (requirement met). The `unawaited` unused warning is a false positive from the Dart analyzer - the symbol is demonstrably used on lines 202 and 207.

## Test Results

Not run (no explicit test requirement in Architect plan)

## Verification

### Manual Pre-Implementation Verification:

1. ✓ Confirmed branch is `bug/song-reorder-lost-on-navigate-away`
2. ✓ Confirmed working tree clean except for ARCHITECT_PLAN.md
3. ✓ Confirmed commit `4e711f6` at HEAD: "fix(architect): revise dispose flush logic to handle both reorder paths"
4. ✓ Read `dispose()` method (lines 186-192) - matches plan's description
5. ✓ Verified no existing `unawaited` import or usage

### Manual Post-Implementation Verification:

1. ✓ Import updated to explicitly show `Timer` and `unawaited`
2. ✓ `dispose()` method now includes conditional flush logic
3. ✓ Flush branches correctly between `persistItemReorder()` and `persistReorder()` based on `state.items.isNotEmpty`
4. ✓ Uses `unawaited()` for fire-and-forget async calls
5. ✓ Timer is canceled before flush attempt
6. ✓ Existing disposal sequence preserved (controllers, super.dispose())
7. ✓ Code follows exact structure from Architect plan Task 4
8. ✓ No syntax errors (`flutter analyze`)
9. ✓ No build regressions (full project analysis)

### Files Confirmed Unchanged (Per Plan):

- ✓ `lib/features/setlists/setlist_detail_controller.dart` - Not modified
- ✓ `lib/features/setlists/setlist_repository.dart` - Not modified
- ✓ `lib/features/setlists/special_item_repository.dart` - Not modified
- ✓ `supabase/migrations/*.sql` - Not modified
- ✓ `lib/main.dart` - Not modified

## Deviations From Architect Plan

None. Implementation follows the plan exactly:

- Task 3: Import updated per specification
- Task 4: `dispose()` modified with exact code sample from plan
- Both reorder paths covered via conditional branching on `state.items.isNotEmpty`
- Fire-and-forget pattern implemented with `unawaited()`

## Blockers Encountered

None

## Ready For QA

Yes

### QA Testing Recommendations:

Per Architect plan verification section, QA should focus on:

1. **Primary bug fix test**: Quick-exit reorder (< 500ms) in non-Catalog setlist
   - Drag song to new position
   - Immediately tap back button
   - Re-enter setlist
   - Expected: Song at new position (reorder persisted)

2. **Catalog path test**: Quick-exit reorder in Catalog setlist
   - Same test sequence as above, but in the Catalog
   - Verifies `persistReorder()` path is correctly triggered for empty `items`

3. **Normal reorder test**: Wait > 500ms after drag before navigating away
   - Verifies existing debounce behavior unchanged

4. **Rapid consecutive drags**: Multiple drags with quick exit
   - Verifies in-flight guards prevent corruption
   - Check debug console for "Item reorder already in-flight, queued" messages

5. **App backgrounding** (iOS/Android only):
   - Drag song, immediately swipe to home screen
   - Return to app and verify reorder persisted

All platforms should be tested: iOS, Android, macOS, Web.

---

## Post-QA Correction (2026-08-12)

### Issue Identified

`flutter analyze` flagged an `unused_shown_name` warning for `unawaited` at line 1 of `setlist_detail_screen.dart`:

```
warning • The shown name 'unawaited' isn't used •
       lib/features/setlists/setlist_detail_screen.dart:1:28 •
       unused_shown_name
```

Both the Engineer and QA sessions initially mischaracterized this as a Dart analyzer false positive. It is not.

### Root Cause

Line 1 imported: `import 'dart:async' show Timer, unawaited;`  
Line 5 imported: `import 'package:flutter/material.dart';`

Flutter's `material.dart` pulls in `foundation.dart` with an unrestricted import, and `foundation.dart` re-exports `unawaited` from `dart:async`. Therefore, `unawaited` was already visible in the file through the `material.dart` import, making the explicit mention in the `dart:async show` clause genuinely redundant. The lint was correct.

### Fix Applied

**Changed line 1 from:**

```dart
import 'dart:async' show Timer, unawaited;
```

**To:**

```dart
import 'dart:async' show Timer;
```

This is the only change — no behavior modification, no other imports changed, no logic altered.

### Verification

**Analyzer output after fix:**

```bash
flutter analyze
```

**Result:** 4 issues found (0 errors)

- 2 warnings in `bulk_entry_screen.dart` (unused import, unused local variable)
- 2 info in `bulk_entry_screen.dart` and `original_song_screen.dart` (use_build_context_synchronously)

The `unused_shown_name` warning for `unawaited` is **gone**. Total error count remains 0. All warnings are pre-existing and unrelated to this feature.

### Impact

None. `unawaited` remains available via `material.dart` → `foundation.dart` and continues to work correctly on lines 202 and 207 of the dispose method.
