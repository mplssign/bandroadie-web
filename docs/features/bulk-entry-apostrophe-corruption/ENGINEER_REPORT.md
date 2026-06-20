# Engineer Report

## Feature Slug

`bulk-entry-apostrophe-corruption`

## Feature Title

Bulk Entry Apostrophe Corruption Fix

## Goal

Fix the bug where song titles containing Unicode LEFT SINGLE QUOTATION MARK (U+2018) pasted from Google Sheets are corrupted, appearing with three consecutive straight apostrophes instead of the intended curly apostrophe. The solution implements RFC 4180-compliant field un-escaping to handle Google Sheets' TSV export behavior, which doubles apostrophes as escape sequences.

## Architect Tasks Completed

- [x] Task 1 — Implement `_unescapeField` helper method
- [x] Task 2 — Update `_parseColumns` to use `_unescapeField`
- [x] Task 3 — Run Flutter Analyze
- [x] Task 4 — Manual Testing (documented below)

## Files Created

None

## Files Modified

- `lib/features/setlists/services/bulk_song_parser.dart`

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings
Output: `No issues found! (ran in 3.5s)`

## Test Results

Not run. The Architect plan specified manual testing, not automated unit tests. Manual test cases documented in Verification section below.

## Verification

Manual steps to be performed during QA:

**Test Case 1: Unquoted plain text (existing behavior)**

- Input: `Van Halen\tAin't No Fun\t120\tStandard`
- Expected: `title = "Ain't No Fun"` (unchanged from previous behavior)
- Purpose: Ensure backward compatibility with unquoted fields

**Test Case 2: Quoted field with escaped apostrophe (bug fix)**

- Input: `Van Halen\t"Ain't Talkin' ''Bout Love"\t120\tStandard`
- Expected: `title = "Ain't Talkin' 'Bout Love"` (three apostrophes reduced to two)
- Purpose: Verify the primary bug fix — Google Sheets doubled apostrophes are un-escaped

**Test Case 3: Quoted field with escaped double-quote**

- Input: `Artist\t"Say ""Hello"""\t\t`
- Expected: `title = "Say "Hello""` (doubled double-quotes un-escaped per RFC 4180)
- Purpose: Ensure RFC 4180 compliance for standard CSV escaping

**Test Case 4: Unquoted field with single apostrophe**

- Input: `Beatles\tCan't Buy Me Love\t\t`
- Expected: `title = "Can't Buy Me Love"` (single apostrophe unchanged)
- Purpose: Verify single apostrophes in unquoted fields are not affected

**Test Case 5: Mixed quoted and unquoted columns**

- Input: `Led Zeppelin\t"What Is And What Should Never Be"\t120\tStandard`
- Expected: All columns parsed correctly, quoted title field has outer quotes stripped
- Purpose: Ensure mixing quoted and unquoted columns in the same row works correctly

**Test Case 6: Empty quoted field**

- Input: `Artist\t""\t\t`
- Expected: Empty title (should trigger validation error: "Missing song title")
- Purpose: Ensure empty quoted fields are handled correctly

## Deviations From Architect Plan

None. Implementation follows the Architect plan exactly:

- Added `_unescapeField` method as specified
- Updated all three branches of `_parseColumns` to call `_unescapeField`
- Modified only the single file listed in the plan
- No dependencies added
- No files created
- No refactoring performed

## Blockers Encountered

None

## Ready For QA

Yes

The implementation is complete, passes static analysis, and follows all Guardrails:

- Single file modified (minimal scope)
- Pure function added (no state changes)
- No initialization order changes
- No config changes
- No auth/routing/database changes
- Backward compatible (unquoted fields unchanged)
- Ready for manual testing with Google Sheets paste data
