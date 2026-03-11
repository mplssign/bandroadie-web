# Architect Plan — song-title-parentheses-save-block

**Branch:** `feature/song-title-parentheses-save-block`
**Type:** Bug fix
**Date:** 2026-03-11

---

## 1. Problem Summary

The `toTitleCase()` utility function in `lib/shared/utils/title_case_formatter.dart` only recognizes spaces and hyphens as word boundaries. Non-letter characters such as opening parentheses `(` and apostrophes `'` consume the `capitalizeNext` flag without being letters themselves, causing the _next actual letter_ to be lowercased.

This manifests when a user tries to correct capitalization in a song title that begins with a parenthesis — for example, changing `(what's` to `(What's`. The `_checkForChanges()` method in the song details bottom sheet runs the edited title through `toTitleCase()`, which reverts `W` back to `w`. The comparison then finds no difference from the stored title, so `_hasChanges` remains `false` and the Save button stays disabled.

The user cannot save a valid, correctly-capitalized title.

---

## 2. Existing System Analysis

### toTitleCase() function (lib/shared/utils/title_case_formatter.dart)

Lines 21–42. Iterates through each character:

- Space or hyphen → write character, set `capitalizeNext = true`
- `capitalizeNext == true` → write `char.toUpperCase()`, set `capitalizeNext = false`
- Otherwise → write `char.toLowerCase()`

**Bug**: when `(` is the first character, `capitalizeNext` is `true`. The `(` is not a space/hyphen, so it enters the `capitalizeNext` branch. `(` uppercased is still `(`, and `capitalizeNext` is now `false`. The next character (the actual first letter) hits the `else` branch and gets **lowercased**.

Same issue occurs with apostrophes at word start (e.g., `'Bout` → `'bout`).

### TitleCaseTextFormatter class (same file, lines 55–85)

Contains identical logic as a `TextInputFormatter`. Same bug.

### Callers of toTitleCase()

| File                                                                            | Usage                                                   |
| ------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` (lines 273, 274) | `_checkForChanges()` — change detection for Save button |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` (lines 388, 389) | `_handleSave()` — normalize before returning result     |
| `lib/features/setlists/setlist_repository.dart` (lines 3137, 3138)              | `upsertExternalSong()` — normalize on import            |
| `lib/features/setlists/setlist_repository.dart` (lines 3719, 3720)              | `_createOrFindSong()` — normalize on create/find        |

### Callers of TitleCaseTextFormatter

| File                                                                | Usage                                     |
| ------------------------------------------------------------------- | ----------------------------------------- |
| `lib/features/events/widgets/rehearsal_form_fields.dart` (line 137) | Location field input formatter            |
| `lib/features/events/widgets/gig_form_fields.dart` (lines 209, 356) | Gig name and venue field input formatters |

---

## 3. Root Cause

**Primary failure surface:** Flutter UI — shared utility function (`toTitleCase`)

**Classification:** LIKELY — confirmed via Dart execution

The `toTitleCase()` function and `TitleCaseTextFormatter` class treat **all non-space, non-hyphen characters** as word constituents that consume the `capitalizeNext` flag. Punctuation characters like `(`, `)`, `'`, `"`, `[`, `{` are not letters but still flip `capitalizeNext` to `false`, preventing the next actual letter from being capitalized.

### Confirmed reproduction trace

1. Song imported with title normalized by `toTitleCase()`: `(what's So Funny 'bout) Peace, Love, And Understanding`
2. User opens song details, title field shows: `(what's So Funny 'bout) Peace, Love, And Understanding`
3. User changes `w` to `W`: `(What's So Funny 'bout) Peace, Love, And Understanding`
4. `_checkForChanges()` calls `toTitleCase()` on the edited text
5. `toTitleCase("(What's So Funny 'bout) Peace, Love, And Understanding")` → `(what's So Funny 'bout) Peace, Love, And Understanding` (reverts W → w)
6. Result matches `widget.song.title` → `titleChanged = false` → `_hasChanges = false` → Save disabled

### Working vs failing path comparison

| Path                                         | Behavior                                                                            |
| -------------------------------------------- | ----------------------------------------------------------------------------------- |
| Title without parentheses: `What's So Funny` | `toTitleCase` → `What's So Funny` ✓ (W capitalizes, `'` doesn't interfere mid-word) |
| Title with parentheses: `(What's So Funny`   | `toTitleCase` → `(what's So Funny` ✗ (`(` consumes capitalizeNext, W lowercased)    |

---

## 4. Proposed Solution

Modify the character classification in both `toTitleCase()` and `TitleCaseTextFormatter` so that **only alphabetic characters** consume the `capitalizeNext` flag. Non-letter, non-space, non-hyphen characters (punctuation) should be written to output without affecting the `capitalizeNext` state.

### Logic change (conceptual — not implementation code):

Current behavior:

- Space/hyphen → separator (set capitalizeNext)
- capitalizeNext → uppercase, clear flag
- Anything else → lowercase

Fixed behavior:

- Space/hyphen → separator (set capitalizeNext)
- Letter + capitalizeNext → uppercase, clear flag
- Letter + !capitalizeNext → lowercase
- Non-letter punctuation → write as-is, **do not touch capitalizeNext**

### Verification of fix correctness

| Input                     | Current output            | Fixed output                                                       |
| ------------------------- | ------------------------- | ------------------------------------------------------------------ |
| `(What's So Funny 'Bout)` | `(what's So Funny 'bout)` | `(What's So Funny 'Bout)`                                          |
| `Hello World`             | `Hello World`             | `Hello World` (unchanged)                                          |
| `new-york city`           | `New-York City`           | `New-York City` (unchanged)                                        |
| `TESTING case`            | `Testing Case`            | `Testing Case` (unchanged)                                         |
| `the beatles`             | `The Beatles`             | `The Beatles` (unchanged)                                          |
| `o'brien`                 | `O'brien`                 | `O'brien` (unchanged — `'` mid-word, capitalizeNext already false) |
| `"hello" world`           | `"hello" World`           | `"Hello" World` (improved)                                         |

---

## 5. Database Impact

**None.**

- No schema changes required
- No migration needed
- No constraints, triggers, or RLS policies affected
- Existing songs with incorrectly-cased titles from prior imports remain unchanged in the database
- Users can now manually correct those titles via the song details editor (which is exactly the intent of this fix)
- Duplicate song detection in `_createOrFindSong()` already uses `.ilike()` (case-insensitive), so the changed normalization output will not create duplicates

---

## 6. RLS / RPC Changes

**None.** This bug is entirely in the Flutter client-side utility layer.

---

## 7. Flutter Architecture Changes

### Change scope: 1 file

Only `lib/shared/utils/title_case_formatter.dart` needs modification.

Two locations within this file:

1. The `toTitleCase()` function (lines 21–42)
2. The `TitleCaseTextFormatter.formatEditUpdate()` method (lines 57–85)

Both contain identical character-processing logic. Both need the same fix: add a condition that checks whether the current character is a letter before consuming `capitalizeNext`.

### No new widgets, controllers, providers, or repositories required.

### No file decomposition required.

`title_case_formatter.dart` is 85 lines (well under the 500-line limit).

`song_details_bottom_sheet.dart` is 1356 lines (over the 500-line limit) but is NOT being modified by this fix. Its pre-existing size is a separate concern outside the scope of this bug fix.

---

## 8. Exact Files to Create

**None.**

---

## 9. Exact Files to Modify

| File                                         | Change                                                                                                                                                                         |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/shared/utils/title_case_formatter.dart` | Update `toTitleCase()` function and `TitleCaseTextFormatter.formatEditUpdate()` method to treat non-letter punctuation as transparent (does not consume `capitalizeNext` flag) |

---

## 10. Risks / Edge Cases

### Low risk

1. **Gig/rehearsal form field behavior change**: The `TitleCaseTextFormatter` is used on gig name, venue, and rehearsal location fields. After the fix, a user typing `(` then a letter will see the letter capitalized (previously lowercased). This is the correct and expected behavior.

2. **Import normalization change**: Future song imports through `upsertExternalSong()` and `_createOrFindSong()` will produce slightly different normalized titles (e.g., `(What's` instead of `(what's`). This is more correct. Existing songs are not affected. Duplicate detection uses case-insensitive `.ilike()`, so no duplicates will be created.

3. **Mid-word apostrophes**: `O'Brien` → `O'brien` behavior is unchanged because `capitalizeNext` is already `false` when the apostrophe is encountered mid-word. The apostrophe passes through, `capitalizeNext` stays `false`, and `b` remains lowercase. This is the same result as the current code.

4. **Other punctuation**: Characters like `"`, `[`, `{`, `/` at word boundaries will now correctly allow the following letter to capitalize. This is universally more correct behavior.

### No risk

- No auth/session changes
- No routing changes
- No RLS policy changes
- No database changes
- No initialization order changes
- No config path changes
- No new dependencies

---

## 11. Verification Plan

### Engineer must run

1. `flutter analyze` — must pass with no issues
2. `flutter test` — must pass (if existing tests exist for `toTitleCase`)

### Manual verification

Test the following scenarios on at least one platform (macOS recommended):

1. **Primary bug fix**: Open a song with title containing opening parenthesis (e.g., the imported `(what's So Funny 'Bout)...`). Change `w` to `W`. Verify Save button becomes enabled. Save and verify title persists correctly.

2. **Standard titles**: Edit a song with a normal title (no parentheses). Verify title case behavior is unchanged.

3. **Apostrophe at word start**: Edit a song title to include `'Bout` or `'Round` after a space. Verify the capital letter is preserved.

4. **Mid-word apostrophe**: Edit a title or artist containing `O'Brien`. Verify it stays `O'brien` per title case rules (not `O'Brien`).

5. **Gig form**: Create or edit a gig with a name or venue containing parentheses. Verify the formatter capitalizes correctly after `(`.

6. **Song import**: Import a song with parentheses in the title via external search. Verify the imported title has correct capitalization.

---

## 12. Engineer Task Breakdown

### Task 1: Fix toTitleCase() function

**File:** `lib/shared/utils/title_case_formatter.dart`
**Location:** `toTitleCase()` function, lines 21–42
**Change:** Add a check for whether the character is a letter (using `RegExp(r'[a-zA-Z]')` or equivalent) in the main loop. Non-letter characters should be written to output without consuming `capitalizeNext`.

### Task 2: Fix TitleCaseTextFormatter.formatEditUpdate()

**File:** `lib/shared/utils/title_case_formatter.dart`
**Location:** `formatEditUpdate()` method, lines 57–85
**Change:** Apply the same logic change as Task 1. The inner loop has identical logic and needs the identical fix.

### Task 3: Update docstring examples

**File:** `lib/shared/utils/title_case_formatter.dart`
**Location:** Function/class doc comments, lines 10–20 and 47–54
**Change:** Add examples showing parenthesis and apostrophe handling to the doc comments for both `toTitleCase()` and `TitleCaseTextFormatter`.

### Task 4: Run verification

- `flutter analyze`
- `flutter test`
- Manual test of primary bug scenario

---

## 13. Rollout / Migration Strategy

### Rollout

- Standard deploy via `flutter build web --release` and Vercel
- No database migration required
- No feature flags required
- No rollback plan needed (change is backward compatible — titles already in DB are unaffected, and the fix only produces more correct output)

### Migration

- **None required.** Existing songs with incorrectly lowercased titles (e.g., `(what's...`) remain in the database. Users can now manually correct them via the song details editor, which is exactly what this fix enables.
- No bulk data migration is warranted for a cosmetic casing issue.

---

## 14. Out of Scope

- Decomposing `song_details_bottom_sheet.dart` (1356 lines, exceeds 500-line limit) — pre-existing technical debt, not related to this bug
- Adding unit tests for `toTitleCase()` — desirable but not required for the bug fix
- Bulk-correcting existing song titles in the database — can be done manually by users
- Handling "small words" in title case (e.g., keeping "and", "the", "of" lowercase per English title case rules) — separate feature request
- Changing the duplicate detection logic in `_createOrFindSong()` — already uses case-insensitive `.ilike()`, no issue

---

## 15. Widget Contracts (Public API)

**No new widgets introduced.** This fix modifies only a shared utility function and a text input formatter class. No widget contracts required.

---

## 16. Data Flow Architecture

### Change detection flow (existing — behavior corrected by fix)

```
User edits title in TextField
        ↓
TextEditingController listener fires
        ↓
_checkForChanges()
        ↓
toTitleCase(_titleController.text.trim())  ← FIX HERE
        ↓
Compare with widget.song.title
        ↓
Set _hasChanges = true/false
        ↓
setState() → UI rebuild
        ↓
Save button enabled/disabled
```

### Save flow (existing — behavior corrected by fix)

```
User taps Save
        ↓
_handleSave()
        ↓
toTitleCase(_titleController.text.trim())  ← FIX HERE
        ↓
Build SongDetailsResult
        ↓
Navigator.pop(result)
        ↓
Parent calls updateSongTitleArtist()
        ↓
SetlistRepository → Supabase
        ↓
songUpdateBroadcasterProvider.broadcast()
        ↓
All open setlists refresh
```

### Import normalization flow (existing — output corrected by fix)

```
External API returns song title
        ↓
SetlistRepository._createOrFindSong()
        ↓
toTitleCase(title.trim())  ← FIX HERE
        ↓
.ilike() search for existing song (case-insensitive)
        ↓
Insert or return existing ID
```

No changes to state ownership, callback flow, provider invalidation, or repository call patterns. Only the output of `toTitleCase()` changes.

---

## 17. Exact Code Locations

### File: lib/shared/utils/title_case_formatter.dart

**Location 1:** `toTitleCase()` function — main character loop (lines 28–41)

**Change:** In the `else` branch and the `capitalizeNext` branch, add a check: if the character is NOT a letter (`!RegExp(r'[a-zA-Z]').hasMatch(char)` or equivalent), write it to output unchanged and do NOT modify `capitalizeNext`. Only letters should consume the `capitalizeNext` flag or be lowercased.

**Location 2:** `TitleCaseTextFormatter.formatEditUpdate()` — main character loop (lines 67–82)

**Change:** Identical logic change as Location 1. The loop body is a copy of `toTitleCase()` and needs the same fix.

**Location 3:** Doc comments for `toTitleCase()` (lines 10–20)

**Change:** Add parenthesis example: `"(hello) world" → "(Hello) World"`

**Location 4:** Doc comments for `TitleCaseTextFormatter` (lines 47–54)

**Change:** Add same parenthesis example.
