# Engineer Report

## Feature Slug

`feature/song-notes-view-drawer`

## Feature Title

Song Notes View Drawer — Read-only notes view with dedicated Edit mode

## Goal

Restore the QA-approved UX where song notes have a dedicated read-only view in a bottom drawer, with an explicit "Edit" button to enter edit mode. Previously, tapping the notes button jumped directly into inline edit mode whether adding a new note or viewing an existing one. This change provides a "View notes" state for existing notes while preserving the inline "Add Notes" flow for songs without notes.

## Architect Tasks Completed

- [x] Task 1 — Create `lib/features/setlists/widgets/song_notes_drawer.dart` with `SongNotesDrawer` and `showSongNotesDrawer()`
- [x] Task 2 — Add import in `song_details_bottom_sheet.dart`
- [x] Task 3 — Add new `_viewNotes()` method
- [x] Task 4 — Update notes button label to `'View notes'` when notes exist
- [x] Task 5 — Update notes button `onTap` to route through `_viewNotes` when notes exist
- [x] Task 6 — Update notes preview `onTap` to route through `_viewNotes`
- [x] Task 7 — Run `flutter analyze` — confirmed 0 errors/warnings

## Files Created

- `lib/features/setlists/widgets/song_notes_drawer.dart` (283 lines)

## Files Modified

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart` (5 edits: 1 import, 1 method addition, 3 onTap/label updates)

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors, 0 warnings**

```
Analyzing bandroadie...
No issues found! (ran in 6.0s)
```

## Test Results

Not run — Architect plan specifies manual verification only (no SQL/migration surface, analyzer gate only)

## Verification

Per Architect plan, verification is post-implementation (Pre-QA Manual Verification). Implementation focuses on:

**Critical QA Round 1 guard implemented:**

- Save button in edit mode is disabled when `_notesController.text.trim() == widget.notes.trim()` (line 68 of `song_notes_drawer.dart`)

**Dark-mode safety:**

- Uses `context.colors.surface` for drawer background (line 97)
- Uses `context.colors.border` for divider and text field border
- Uses `context.colors.textPrimary`, `textSecondary`, `textMuted` for text colors
- No hardcoded gray or color values

**Persistence pattern:**

- Drawer's "Save" only updates `_notesController.text` in parent sheet via `Navigator.pop(result)` (line 81)
- Parent's `_viewNotes()` calls `_checkForChanges()` after updating controller (line 618)
- Database write only happens through existing outer Song Details "Save" button (unchanged)

**PopScope dismiss handling:**

- View mode dismiss → `Navigator.pop(null)` (line 78)
- Edit mode dismiss → reset controller text, return to view mode (lines 74-76)
- Matches `_SongDetailsSheet._handleCancel()` pattern

**Entry points:**

- Notes button (when notes exist): routes to `_viewNotes()` (line 1312)
- Notes preview card: routes to `_viewNotes()` (line 1356)
- Inline "Add Notes" flow (no notes): unchanged, still sets `_isEditingNotes = true` (line 1312)

## Deviations From Architect Plan

None — all 7 tasks implemented exactly as specified

## Blockers Encountered

None

## Ready For QA

**Yes**

Implementation is complete and matches Architect specification exactly. All files-to-modify and files-explicitly-off-limits constraints were respected. The new drawer is self-contained UI-local state with no cross-feature dependencies. The inline "Add Notes" flow for songs without notes is byte-for-byte unchanged.

Manual verification (per Architect plan §15) should confirm:

1. Button label changes from "Edit Notes" to "View notes" when note exists
2. Notes drawer opens in read-only view (not edit mode)
3. Edit button in drawer enters edit mode correctly
4. Save button disabled when text unchanged (Critical issue guard)
5. Cancel in edit mode returns to view (does not close drawer)
6. Cancel in view mode closes drawer
7. Outer Song Details "Save" persists the note (not drawer's internal Save)
8. Dark mode rendering (no hardcoded colors, uses `context.colors.*`)
9. All platforms (iOS/Android/Web/macOS) render drawer correctly
10. `isReadOnly: true` mode preserves existing behavior (button hidden, preview non-interactive)
