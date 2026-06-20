# Engineer Report

## Feature Slug

bug/share-drawer-regression

## Feature Title

Share Drawer Regression — Restore Share Format Picker

## Goal

Restore the share format picker functionality that was never merged to main from the feature/share-format-picker branch. Users can now select between "Text / Email" (rich plain-text) and "Spreadsheet" (tab-delimited) formats before sharing a setlist.

## Architect Tasks Completed

- [x] Task 1 — Add ShareFormat enum
- [x] Task 2 — Replace `_handleShare()` method
- [x] Task 3 — Add `_showShareFormatPicker()` method
- [x] Task 4 — Add `_generateSpreadsheetText()` method
- [x] Task 5 — Add `_ShareFormatSheet` widget
- [x] Task 6 — Add `_ShareFormatOption` widget
- [x] Task 7 — Run Flutter Analyze
- [x] Task 8 — Format changed file

## Files Created

- none

## Files Modified

- lib/features/setlists/setlist_detail_screen.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings

Output:

```
Analyzing bandroadie...
No issues found! (ran in 3.7s)
```

## Test Results

Not run — Architect plan requires manual testing on iOS and Web platforms, which should be performed by QA.

## Verification

Implementation verified by code inspection:

1. **ShareFormat enum** — Added after imports, before class definition (lines ~52-56)
2. **\_handleShare() method** — Replaced with version that shows format picker, handles dismissal, generates conditional text based on format selection (lines ~1225-1264)
3. **\_showShareFormatPicker() method** — Added after \_handleShare(), shows modal bottom sheet with proper mounted checks (lines ~1266-1281)
4. **\_generateSpreadsheetText() method** — Added after \_generateShareText(), generates tab-delimited format with header row (lines ~1360-1377)
5. **\_ShareFormatSheet widget** — Added at end of file, displays two format options with proper styling (lines ~3026-3065)
6. **\_ShareFormatOption widget** — Added after \_ShareFormatSheet, renders individual format tiles (lines ~3067-3101)

Critical constraints verified:

- ✅ `_formatSongSecondLine()` was NOT modified (remains `'$artist\n$metadata'`)
- ✅ `_formatTwoColumnLine()` was NOT restored (correctly absent)
- ✅ `_generateShareText()` was NOT modified (preserved as-is)
- ✅ All new code uses design tokens (Spacing, AppTextStyles, context.colors)
- ✅ Proper mounted checks in async methods
- ✅ Format picker is dismissible (returns null on cancel)

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes

### QA Testing Instructions

Per Architect plan, QA must test:

**Test 1: Text/Email format**

- Open any setlist → Tap share icon → Verify format picker appears → Tap "Text / Email" → Verify native share sheet with plain-text format (artist and metadata on separate lines with newline)

**Test 2: Spreadsheet format**

- Open any setlist → Tap share icon → Tap "Spreadsheet" → Verify native share sheet with tab-delimited format → Paste into spreadsheet app (Numbers/Excel/Google Sheets) → Verify four columns: Title, Artist, BPM, Tuning

**Test 3: Dismiss format picker**

- Open any setlist → Tap share icon → Tap outside sheet or swipe down → Verify sheet closes without showing share sheet (cancelled)

**Test 4: Empty setlist**

- Create new empty setlist → Tap share icon → Select either format → Verify share sheet with header only (no songs)

**Test 5: Catalog share**

- Open Catalog → Tap share icon → Test both formats → Verify correct content

**Platforms:** iOS and Web (minimum); Android and macOS optional

**Regression checks:** No setState-after-dispose errors, format picker dismissal works, both formats produce correct output
