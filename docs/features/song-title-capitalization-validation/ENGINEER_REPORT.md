git pull origin main# Engineer Report — song-title-capitalization-validation

**Feature Slug:** song-title-capitalization-validation
**Feature Title:** Song Title Capitalization Validation Bug Fix
**Branch:** bug/song-title-capitalization-validation
**Date:** 2026-03-12

---

## Goal

Remove lossy `toTitleCase()` normalization from the song details bottom sheet's change detection and save methods, so users can save capitalization-only edits to song titles and artist names.

---

## Architect Tasks Completed

- [x] Task 1: Remove `toTitleCase()` from `_checkForChanges()` (lines 273-274)
- [x] Task 2: Remove `toTitleCase()` from `_handleSave()` (lines 388-389)
- [x] Task 3: Remove unused import of `title_case_formatter.dart` (line 8)
- [x] Task 4: Run verification (`flutter analyze`, `flutter test`)

---

## Files Created

None.

---

## Files Modified

| File                                                           | Change                                                                                                                                                                 |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Removed `toTitleCase()` wrapping from `_checkForChanges()` and `_handleSave()` for both title and artist fields. Removed unused import of `title_case_formatter.dart`. |

---

## Change Summary

```
Files changed: 1
Lines added: 3
Lines removed: 6
```

Changes:

- Removed import of `../../../shared/utils/title_case_formatter.dart` (1 line removed)
- `_checkForChanges()`: Replaced `toTitleCase(_titleController.text.trim())` → `_titleController.text.trim()` for title and artist. Removed now-inaccurate comment. (2 lines replaced with 2 lines, 1 comment line removed)
- `_handleSave()`: Replaced `toTitleCase(_titleController.text.trim())` → `_titleController.text.trim()` for title and artist. (2 lines replaced with 2 lines)

---

## File Size Changes

| File                             | Before      | After       |
| -------------------------------- | ----------- | ----------- |
| `song_details_bottom_sheet.dart` | ~1356 lines | ~1353 lines |

---

## Analyzer Results

```
Command: flutter analyze
Result: No issues found! (ran in 4.2s)
```

---

## Test Results

```
Command: flutter test
Result: 00:01 +6: All tests passed!
```

---

## Verification

- `flutter analyze`: 0 errors, 0 warnings
- `flutter test`: 6 tests passed, 0 failures
- `dart format`: No formatting changes needed
- `git diff --name-only`: Only `lib/features/setlists/widgets/song_details_bottom_sheet.dart` modified — matches Architect plan scope exactly
- Confirmed no remaining references to `toTitleCase` in `song_details_bottom_sheet.dart`
- Confirmed `toTitleCase()` calls in `setlist_repository.dart` (import normalization) are untouched

---

## Deviations From Architect Plan

None.

---

## Blockers Encountered

None.

---

## Ready For QA

Yes. Implementation matches Architect plan exactly. All validation checks pass. Single file modified as specified.

### QA Focus Areas

1. Open a song with a normalized title, change only capitalization (e.g., `And` → `and`), confirm Save button enables
2. Save and verify the title persists as typed
3. Verify artist field behaves the same way
4. Verify non-casing edits (BPM, tuning, notes, duration) still detect changes
5. Verify no-change scenario: open editor, make no changes, confirm Save stays disabled
