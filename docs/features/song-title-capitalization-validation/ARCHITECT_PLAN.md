# Architect Plan — song-title-capitalization-validation

**Branch:** `bug/song-title-capitalization-validation`
**Type:** Bug fix
**Date:** 2026-03-12

---

## 1. Problem Summary

The song details editor in `song_details_bottom_sheet.dart` applies `toTitleCase()` normalization to user input in both the change detection (`_checkForChanges()`) and save (`_handleSave()`) methods. This lossy normalization forces the first letter of every word to uppercase and all subsequent letters to lowercase, which masks legitimate capitalization changes the user makes.

When a song's stored title already matches the output of `toTitleCase()`, any capitalization edit that `toTitleCase()` would reverse becomes invisible to change detection. The Save button remains disabled even though the user made a deliberate edit.

Specific manifestation: a user editing `(What's So Funny 'Bout) Peace, Love, And Understanding` to change `And` → `and` sees `toTitleCase()` revert it to `And`, matching the stored title, so `_hasChanges` stays `false`.

More broadly, users cannot save titles with non-standard capitalization such as `AC/DC`, `McCartney`, `R.E.M.`, or intentionally lowercase articles (`and`, `the`, `of`).

---

## 2. Existing System Analysis

### Change detection flow

```
User types in TextField (_titleController)
  → listener fires _checkForChanges()
  → newTitle = toTitleCase(_titleController.text.trim())   ← PROBLEM
  → titleChanged = (newTitle != widget.song.title)
  → _hasChanges = titleChanged || artistChanged || ...
  → Save button enabled/disabled based on _hasChanges
```

### Save flow

```
User taps Save → _handleSave()
  → newTitle = toTitleCase(_titleController.text.trim())   ← PROBLEM
  → Returns SongDetailsResult with normalized title
  → Caller passes to updateSongTitleArtist() → saved to DB
```

### Callers of toTitleCase() (full list)

| File                             | Line(s)    | Usage                                          | Affected by this fix? |
| -------------------------------- | ---------- | ---------------------------------------------- | --------------------- |
| `song_details_bottom_sheet.dart` | 273, 274   | `_checkForChanges()` — title & artist          | **YES**               |
| `song_details_bottom_sheet.dart` | 388, 389   | `_handleSave()` — title & artist               | **YES**               |
| `setlist_repository.dart`        | 3137, 3138 | `upsertExternalSong()` — import normalization  | No                    |
| `setlist_repository.dart`        | 3719, 3720 | `_createOrFindSong()` — bulk add normalization | No                    |

### Prior fix context

Commit `876e56c` (`fix: song-title-parentheses-save-block`) fixed `toTitleCase()` to treat punctuation as transparent — parentheses and apostrophes no longer consume the `capitalizeNext` flag. That fix is already in main and in this branch.

However, that fix only corrected the character classification logic inside `toTitleCase()`. The higher-level problem — that `_checkForChanges()` and `_handleSave()` apply lossy normalization to user text — was not addressed.

---

## 3. Root Cause

**Primary failure layer:** Flutter UI — `_checkForChanges()` and `_handleSave()` in `song_details_bottom_sheet.dart`

**Root cause:** Both methods call `toTitleCase()` on user text before processing. `toTitleCase()` is a lossy normalization (forces first letters uppercase, all others lowercase). When the normalized result matches the stored title, the change detector reports no change, even though the user edited the text.

**Root Cause Confidence:** HIGH — confirmed in code

### Reproduction trace (with current fixed toTitleCase)

1. Song stored (via import + normalization): `(What's So Funny 'Bout) Peace, Love, And Understanding`
2. User opens song details, title field shows: `(What's So Funny 'Bout) Peace, Love, And Understanding`
3. User edits `And` to `and`: `(What's So Funny 'Bout) Peace, Love, and Understanding`
4. `_checkForChanges()` fires, computes: `toTitleCase(user_text)` → `(What's So Funny 'Bout) Peace, Love, And Understanding`
5. `toTitleCase` result matches `widget.song.title` → `titleChanged = false`
6. `_hasChanges = false` → Save button stays disabled

### Working vs failing path

| Scenario                                            | Behavior                                                  |
| --------------------------------------------------- | --------------------------------------------------------- |
| Changing BPM, tuning, notes, duration               | Save enables (no `toTitleCase()` applied to these fields) |
| Changing title text content (adding/removing words) | Save enables (text differs even after normalization)      |
| Changing ONLY capitalization within title           | **Save disabled** (toTitleCase reverts the change)        |

---

## 4. Proposed Solution

Remove `toTitleCase()` normalization from both `_checkForChanges()` and `_handleSave()`. Compare and save raw trimmed user text instead of normalized text.

### Change in \_checkForChanges() (line 273-274)

**Before:**

```dart
final newTitle = toTitleCase(_titleController.text.trim());
final newArtist = toTitleCase(_artistController.text.trim());
```

**After:**

```dart
final newTitle = _titleController.text.trim();
final newArtist = _artistController.text.trim();
```

### Change in \_handleSave() (line 388-389)

**Before:**

```dart
final newTitle = toTitleCase(_titleController.text.trim());
final newArtist = toTitleCase(_artistController.text.trim());
```

**After:**

```dart
final newTitle = _titleController.text.trim();
final newArtist = _artistController.text.trim();
```

### Why this is correct

1. **Change detection now compares raw user text to stored text.** Any real edit — including casing — is detected.
2. **Save preserves user intent.** The saved title is exactly what the user typed (trimmed), not a machine-normalized version.
3. **Import normalization is preserved.** `toTitleCase()` calls in `setlist_repository.dart` (`upsertExternalSong()`, `_createOrFindSong()`) remain unchanged. New songs entering the system via import/bulk-add are still normalized.
4. **No architectural changes.** No new providers, controllers, or state layers.

### Verification of fix correctness

| User action                         | Before fix                                           | After fix                                 |
| ----------------------------------- | ---------------------------------------------------- | ----------------------------------------- |
| Edit `And` → `and` in title         | Save disabled (toTitleCase reverts)                  | Save enabled (raw text differs)           |
| Edit `(what's` → `(What's` in title | Save enabled (toTitleCase produces different result) | Save enabled (raw text differs)           |
| Type `AC/DC` as artist              | Saved as `Ac/dc`                                     | Saved as `AC/DC`                          |
| Type `McCartney` as artist          | Saved as `Mccartney`                                 | Saved as `McCartney`                      |
| Make no changes, close editor       | Save disabled → Cancel closes                        | Save disabled → Cancel closes (unchanged) |

---

## 5. Database Impact

**None.** No schema changes, migrations, triggers, or constraints affected.

---

## 6. RLS / RPC Changes

**None.** The `update_song_metadata` RPC saves the title/artist as-is. No RPC logic changes needed.

---

## 7. Flutter Architecture Changes

**Minimal.** Removing 4 `toTitleCase()` function calls from one widget file. No new files, providers, controllers, repositories, or state management changes.

The `import` of `title_case_formatter.dart` in `song_details_bottom_sheet.dart` can be removed if `toTitleCase()` is no longer called. However, the import may be retained if the engineer prefers (no lint error since Dart tree-shakes unused imports at build time, though `flutter analyze` will flag it).

---

## 8. Exact Files to Create

None.

---

## 9. Exact Files to Modify

| File                                                           | Change                                                                                                                                                                                                 |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Remove `toTitleCase()` wrapping from `_checkForChanges()` (lines 273-274) and `_handleSave()` (lines 388-389). Remove unused import of `title_case_formatter.dart` (line 8) if no other usages remain. |

---

## 10. Risks / Edge Cases

### Risk 1: False change detection from keyboard auto-capitalization

**Risk level:** Very Low

The title TextField uses `textCapitalization: TextCapitalization.words`, which is a keyboard hint — it does not modify text programmatically. The user controls what gets typed. Without `toTitleCase()` normalization, the raw text is compared to stored text. If the soft keyboard auto-capitalizes a letter and the user doesn't correct it, the change detector will flag it as a change. This is correct behavior — the text IS different.

### Risk 2: Import vs edit inconsistency

**Risk level:** Low (pre-existing)

Songs entered via import/bulk-add are still normalized by `toTitleCase()` in the repository. Songs edited in the details sheet are now saved as-is. This means:

- Import: `AC/DC` → stored as `Ac/dc`
- User edits via details: `Ac/dc` → `AC/DC` → stored as `AC/DC`

This is actually improved behavior — users can now correct import normalization artifacts. The inconsistency in import normalization is a separate concern (out of scope).

### Risk 3: Gig/rehearsal form fields unaffected

**Confirmed no impact.** Gig name, venue, and rehearsal location fields use `TitleCaseTextFormatter` as an `inputFormatter` on the TextField itself. These are separate UI surfaces and are not changed by this fix.

### Edge case: \_ensureSongRecord() bypass

`_ensureSongRecord()` in `new_setlist_screen.dart` (line 367) inserts songs without `toTitleCase()` normalization. This is a pre-existing inconsistency, not introduced by this fix. Out of scope for this bug.

---

## 11. Verification Plan

### Engineer verification

1. `flutter analyze` — must pass with no new warnings
2. `flutter test` — must pass
3. Manual verification:
   - Open a song with a normalized title (e.g., `(What's So Funny 'Bout) Peace, Love, And Understanding`)
   - Change only the capitalization (e.g., `And` → `and`)
   - Confirm Save button becomes enabled
   - Save and verify the title is stored as typed
   - Reopen and confirm the saved title persists

### QA verification

1. **Primary scenario:** Title capitalization edit with parentheses — Save button enables and saves correctly
2. **Artist field:** Same behavior — capitalization-only edit enables Save
3. **Non-casing edits:** BPM, tuning, notes, duration, lyrics — still detect changes (regression check)
4. **No-change scenario:** Open editor, make no changes, confirm Save stays disabled
5. **Multi-field edit:** Change both title casing AND another field — Save enables and both changes persist

---

## 12. Engineer Task Breakdown

### Task 1: Remove toTitleCase() from \_checkForChanges()

**File:** `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
**Location:** `_checkForChanges()` method, lines 273-274

**Change:** Replace `toTitleCase(_titleController.text.trim())` with `_titleController.text.trim()` for both title and artist.

### Task 2: Remove toTitleCase() from \_handleSave()

**File:** `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
**Location:** `_handleSave()` method, lines 388-389

**Change:** Same replacement.

### Task 3: Clean up unused import

**File:** `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
**Location:** Line 8

**Change:** Remove `import '../../../shared/utils/title_case_formatter.dart';` if no other references to `toTitleCase` remain in the file.

### Task 4: Run verification

**Commands:** `flutter analyze`, `flutter test`

---

## 13. Rollout / Migration Strategy

### Rollout

- Standard deploy via `flutter build web --release` and Vercel
- No database migration required
- No feature flags required
- Backward compatible — songs with previously-normalized titles continue to display correctly
- Users can now manually correct capitalization on any song

### Migration

**None required.** Existing songs retain their stored titles. Users may now edit capitalization if desired. No bulk data migration needed.

---

## 14. Out of Scope

- Decomposing `song_details_bottom_sheet.dart` (1356 lines, exceeds 500-line limit) — pre-existing technical debt, not related to this bug
- Adding unit tests for change detection logic — desirable but not required for this bug fix
- Fixing `_ensureSongRecord()` to normalize with `toTitleCase()` — pre-existing inconsistency, separate ticket
- Removing `toTitleCase()` from import paths in `setlist_repository.dart` — separate design decision about import normalization policy
- Handling "small words" in title case (keeping `and`, `the`, `of` lowercase per English title case rules) — separate feature request
- Adding `TitleCaseTextFormatter` to the song details title/artist TextFields — would re-introduce the same normalization problem

---

## 15. Widget Contracts (Public API)

**No new widgets introduced.** The `SongDetailsResult` returned by the bottom sheet will now contain raw trimmed text instead of `toTitleCase()`-normalized text. All callers already handle arbitrary string values, so no contract change is needed.

### SongDetailsResult data change

| Field    | Before                     | After                 |
| -------- | -------------------------- | --------------------- |
| `title`  | `toTitleCase()` normalized | Raw trimmed user text |
| `artist` | `toTitleCase()` normalized | Raw trimmed user text |

Callers: The screen that opens the bottom sheet receives `SongDetailsResult` and passes `title`/`artist` to `updateSongTitleArtist()`, which saves directly. No caller applies additional normalization.

---

## 16. Data Flow Architecture

### Before (current)

```
User types in title TextField
  → _titleController listener fires _checkForChanges()
  → toTitleCase(text.trim())     ← lossy normalization
  → compare to widget.song.title
  → _hasChanges = (differs)
  → Save button enabled/disabled

User taps Save
  → _handleSave()
  → toTitleCase(text.trim())     ← lossy normalization
  → SongDetailsResult(title: normalizedTitle)
  → caller → updateSongTitleArtist(title: normalizedTitle)
  → DB write
```

### After (fixed)

```
User types in title TextField
  → _titleController listener fires _checkForChanges()
  → text.trim()                  ← raw comparison
  → compare to widget.song.title
  → _hasChanges = (differs)
  → Save button enabled/disabled

User taps Save
  → _handleSave()
  → text.trim()                  ← raw save
  → SongDetailsResult(title: rawTitle)
  → caller → updateSongTitleArtist(title: rawTitle)
  → DB write
```

---

## 17. Exact Code Locations

**Location 1:** `_checkForChanges()` — title normalization (line 273)

```dart
// CURRENT (line 273):
    final newTitle = toTitleCase(_titleController.text.trim());
// FIX:
    final newTitle = _titleController.text.trim();
```

**Location 2:** `_checkForChanges()` — artist normalization (line 274)

```dart
// CURRENT (line 274):
    final newArtist = toTitleCase(_artistController.text.trim());
// FIX:
    final newArtist = _artistController.text.trim();
```

**Location 3:** `_handleSave()` — title normalization (line 388)

```dart
// CURRENT (line 388):
    final newTitle = toTitleCase(_titleController.text.trim());
// FIX:
    final newTitle = _titleController.text.trim();
```

**Location 4:** `_handleSave()` — artist normalization (line 389)

```dart
// CURRENT (line 389):
    final newArtist = toTitleCase(_artistController.text.trim());
// FIX:
    final newArtist = _artistController.text.trim();
```

**Location 5:** Import statement (line 8)

```dart
// CURRENT (line 8):
import '../../../shared/utils/title_case_formatter.dart';
// FIX: Remove this import if no other references remain in the file
```
