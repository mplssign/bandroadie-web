# Engineer Report

## Feature Slug

`setlist-card-reorder-lost-on-navigate-away`

## Feature Title

Setlist Card Reorder Lost on Navigate Away

## Goal

Fix bug where dragging a setlist card to reorder it on the Setlists tab appears to save, but the reorder is silently discarded if the user navigates away before the 500ms debounce timer fires. The fix ensures pending reorders are flushed to the database during widget disposal.

## Architect Tasks Completed

- [x] Task 1 — Verified current dispose() behavior (lines 93–97 cancel timer without flush)
- [x] Task 2 — Confirmed single reorder path (no branching logic needed)
- [x] Task 3 — Not applicable (dart:async import already present without show clause)
- [x] Task 4 — Modified dispose() to flush pending reorder before timer cancellation
- [x] Task 5 — Verified no syntax errors (`flutter analyze` on modified file)
- [x] Task 6 — Verified no build regressions (`flutter analyze` on full project)
- [x] Task 7 — Documented changes in this report

## Files Created

None

## Files Modified

- `lib/features/setlists/setlists_tab_content.dart`

## Analyzer Results

**Command:** `flutter analyze lib/features/setlists/setlists_tab_content.dart`  
**Result:** 0 errors, 0 warnings (No issues found!)

**Command:** `flutter analyze` (full project)  
**Result:** 0 errors, 4 pre-existing warnings in unrelated files:

- 2 warnings in `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` (unused_import, unused_local_variable)
- 2 info messages in bulk_entry_screen.dart and original_song_screen.dart (use_build_context_synchronously)

**No new warnings or errors introduced by this implementation.**

## Test Results

Not run (per Architect plan, no tests explicitly required for this change)

## Verification

### Task 2 Investigation: Single Reorder Path Confirmed

Inspected `_handleReorder` method (lines 175-189):

- Single code path always calls `notifier.persistReorder()` on the debounce timer
- No conditional logic based on item type (Catalog vs. non-Catalog)
- Unlike the song-reorder fix which had two paths, this implementation requires no branching in `dispose()`

### Dispose Implementation: Fire-and-Forget with unawaited

Used the exact implementation from Task 4 of the Architect plan:

- Check if `_reorderDebounceTimer` is active
- If active: cancel timer, then call `unawaited(ref.read(setlistsProvider.notifier).persistReorder())`
- Fire-and-forget pattern is safe because `setlistsProvider` is NOT `.autoDispose`

### Provider Verification

Confirmed `setlistsProvider` (defined in `setlists_screen.dart` line 297) is a plain `NotifierProvider`, not `.autoDispose`. The provider survives widget teardown long enough for the RPC to complete.

### Before State (lines 93-97)

```dart
@override
void dispose() {
  _reorderDebounceTimer?.cancel();  // ← Cancelled timer, never triggered persist
  _entranceController.dispose();
  super.dispose();
}
```

### After State (lines 93-108)

```dart
@override
void dispose() {
  // Flush pending reorder if timer is active
  if (_reorderDebounceTimer != null && _reorderDebounceTimer!.isActive) {
    _reorderDebounceTimer!.cancel();

    // Fire-and-forget: attempt persist even though screen is disposed.
    // Uses the same guarded persist method to prevent data corruption.
    // Failure won't be visible to user (acceptable — screen is gone).
    unawaited(
      ref.read(setlistsProvider.notifier).persistReorder(),
    );
  }
  _entranceController.dispose();
  super.dispose();
}
```

### Import Verification

The file already has `import 'dart:async';` without a `show` clause (line 1), providing full access to `Timer` and `unawaited`. Per Task 3 of the Architect plan, no import modification was needed or performed.

## Deviations From Architect Plan

None. All tasks executed exactly as specified.

## Blockers Encountered

None.

## Ready For QA

**Yes**

The implementation is complete and ready for manual testing per the Architect plan's verification section:

- Test 1: Quick-exit reorder (< 500ms) should now persist
- Test 2: Normal reorder (> 500ms) should continue working (no regression)
- Test 3: Multiple quick reorders should coalesce correctly
- Test 4: Catalog position should remain stable
- Test 5: Cross-platform consistency (iOS, Android, Web, macOS)
