# Engineer Report — song-title-parentheses-save-block

## Feature Slug

`song-title-parentheses-save-block`

## Feature Title

Song title with parentheses blocks Save button

## Goal

Fix the `toTitleCase()` utility function and `TitleCaseTextFormatter` so that non-letter punctuation characters (parentheses, apostrophes, quotes, etc.) do not consume the `capitalizeNext` flag. This enables users to correctly capitalize letters following punctuation in song titles, unblocking the Save button.

## Architect Tasks Completed

| Task   | Description                                                                       | Status       |
| ------ | --------------------------------------------------------------------------------- | ------------ |
| Task 1 | Fix `toTitleCase()` function — add letter check before consuming `capitalizeNext` | ✅ Completed |
| Task 2 | Fix `TitleCaseTextFormatter.formatEditUpdate()` — apply identical logic fix       | ✅ Completed |
| Task 3 | Update docstring examples — add parenthesis and apostrophe examples               | ✅ Completed |
| Task 4 | Run verification                                                                  | ✅ Completed |

## Files Created

None.

## Files Modified

| File                                         | Change                                                                                                                                                                                                                                                     |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/shared/utils/title_case_formatter.dart` | Updated `toTitleCase()` and `TitleCaseTextFormatter.formatEditUpdate()` to treat non-letter punctuation as transparent (passes through without consuming `capitalizeNext`). Added `RegExp(r'[a-zA-Z]')` letter check. Updated docstring examples for both. |

## File Size Changes

| File                                         | Before   | After     |
| -------------------------------------------- | -------- | --------- |
| `lib/shared/utils/title_case_formatter.dart` | 90 lines | 104 lines |

## Analyzer Results

- **Command:** `flutter analyze`
- **Result:** No issues found (ran in 3.7s)

## Test Results

- **Command:** `flutter test`
- **Result:** 6 tests passed, 0 failures

## Verification

### Manual test steps to perform

1. **Primary bug fix**: Open a song with title containing opening parenthesis (e.g., `(what's So Funny 'Bout)...`). Change `w` to `W`. Verify Save button becomes enabled. Save and verify title persists correctly.
2. **Standard titles**: Edit a song with a normal title (no parentheses). Verify title case behavior is unchanged.
3. **Apostrophe at word start**: Edit a song title to include `'Bout` or `'Round` after a space. Verify the capital letter is preserved.
4. **Mid-word apostrophe**: Edit a title or artist containing `O'Brien`. Verify it stays `O'brien` per title case rules.
5. **Gig form**: Create or edit a gig with a name or venue containing parentheses. Verify the formatter capitalizes correctly after `(`.
6. **Song import**: Import a song with parentheses in the title via external search. Verify the imported title has correct capitalization.

## Deviations From Architect Plan

None.

## Blockers Encountered

None.

## Ready For QA

Yes. Implementation matches Architect plan exactly. Analyzer passes with 0 issues. All existing tests pass.
