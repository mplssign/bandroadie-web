# Architect Plan — Share Text BPM Newline

## Feature Slug

`feature/share-text-bpm-newline`

## Problem Summary

The plain-text share format for setlists currently right-justifies BPM • Tuning on the same line as the artist name, wrapping to the next line only when the combined length exceeds 56 characters. This creates inconsistent visual alignment and makes the output harder to read in email clients and messaging apps. The requested behavior is simpler: always place BPM • Tuning on its own line directly below the artist name, with no right-justification or column padding.

## Root Cause

`_formatSongSecondLine()` in `lib/features/setlists/setlist_detail_screen.dart` delegates formatting to `_formatTwoColumnLine()`, which implements the right-justification logic. The method calculates padding to align the right column within a 56-character width, wrapping only on overflow. The root cause is architectural: the two-column layout abstraction is inappropriate for the desired single-column output.

**Confidence:** HIGH — confirmed through direct code observation. The logic is explicit and isolated to these two methods.

## Reference Docs Consulted

Not applicable. This is a text formatting change with no domain-specific architecture. No reference documentation exists for share text formatting beyond inline code comments.

## Existing System Analysis

**Current data flow:**

1. User taps "Share" and selects "Text (Email)" format
2. `_generateShareText()` is called with setlist name and song list
3. For each song, `_formatSongSecondLine(song)` is called to format the artist/BPM/tuning line
4. `_formatSongSecondLine()` builds left (artist) and right (BPM • Tuning) strings
5. Delegates to `_formatTwoColumnLine(left, right)` with default width=56
6. `_formatTwoColumnLine()` checks if `left.length + right.length + 1 >= 56`
   - If fits: pads with spaces to right-justify (e.g., `Artist Name                   125 BPM • Standard`)
   - If overflows: wraps to next line with 4-space indent (e.g., `Artist Name\n    125 BPM • Standard`)
7. Final output is copied to clipboard or shared via OS share sheet

**Key observations:**

- `_formatTwoColumnLine()` has exactly one caller: `_formatSongSecondLine()` at line 1469
- No other method in the file uses two-column formatting
- `_generateSpreadsheetText()` uses tab-delimited format and does not call `_formatTwoColumnLine()`
- `_formatHeaderSubline()` and `_formatTotalDuration()` format the summary line and are unaffected

## Proposed Solution

Replace the two-column delegation pattern with direct string concatenation in `_formatSongSecondLine()`:

```dart
String _formatSongSecondLine(SetlistSong song) {
  final artist = song.artist;
  final bpmText = song.bpm != null && song.bpm! > 0 ? '${song.bpm} BPM' : '- BPM';
  final tuningText = tuningShortLabel(song.tuning);
  final metadata = '$bpmText • $tuningText';

  return '$artist\n$metadata';
}
```

**Output format change:**

```
Before:
Song Title
Artist Name                   125 BPM • Standard

After:
Song Title
Artist Name
125 BPM • Standard
```

**Dead code handling:**
Once `_formatSongSecondLine()` no longer calls `_formatTwoColumnLine()`, that method will have zero callers. The Engineer may optionally remove it to prevent future confusion, or leave it with a `// DEAD CODE` comment. Removal is preferred but not required.

## Database Impact

Not applicable. This change is purely cosmetic text formatting in the client UI layer.

## Flutter Architecture Changes

**State:** No state changes. No Riverpod providers affected.

**Widgets:** No widget tree changes. The share flow remains identical.

**Repositories:** No repository changes. Song data fetching is unchanged.

**Services:** No service layer changes.

**Models:** No model changes. `SetlistSong` fields (artist, bpm, tuning) are read as before.

**Affected method signature:**

- `_formatSongSecondLine(SetlistSong song)` — implementation changes, signature unchanged

**Unaffected methods:**

- `_generateShareText()` — continues to call `_formatSongSecondLine()` as before
- `_generateSpreadsheetText()` — tab-delimited format unchanged
- `_formatHeaderSubline()` — song count and duration formatting unchanged
- `_formatTotalDuration()` — duration formatting unchanged

## Files to Create

None.

## Files to Modify

| File                                               | Changes                                                                                                                                                                                                |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/setlist_detail_screen.dart` | Rewrite `_formatSongSecondLine()` to return `artist\nBPM • Tuning` without calling `_formatTwoColumnLine()`. Optionally remove `_formatTwoColumnLine()` as dead code (zero callers after this change). |

## Files Off-Limits

| File                                                   | Reason                                                           |
| ------------------------------------------------------ | ---------------------------------------------------------------- |
| All files except `setlist_detail_screen.dart`          | Scope explicitly limited to this single file per feature request |
| `lib/features/setlists/setlist_repository.dart`        | Data fetching unchanged                                          |
| `lib/features/setlists/setlist_detail_controller.dart` | State management unchanged                                       |
| Any theme, config, or asset file                       | No new theme tokens or assets required                           |

## System Impact Map

| System                                 | Impact                                                |
| -------------------------------------- | ----------------------------------------------------- |
| Gigs                                   | unaffected                                            |
| Rehearsals                             | unaffected                                            |
| Setlists / Catalog                     | **affected** — plain-text share output format changes |
| Members / RBAC                         | unaffected                                            |
| Auth / Session                         | unaffected                                            |
| Routing                                | unaffected                                            |
| Notifications                          | unaffected                                            |
| Platform (iOS / Android / Web / macOS) | unaffected — text formatting is platform-agnostic     |

## Regression Risk

**Level:** LOW

**Rationale:**

- Single method change in one file
- No database, RLS, RPC, migration, or edge function changes
- No state management, routing, or init order changes
- No cross-feature dependencies or shared state
- Change is cosmetic and reversible
- Spreadsheet format explicitly unchanged per scope constraints
- Other setlist features (reorder, edit, delete, bulk entry) unaffected
- Share flow UI (bottom sheet, format picker) unaffected

**Failure modes eliminated:**

- No auth or session risk
- No data integrity risk
- No permission or RBAC risk
- No platform-specific rendering differences (plain text is universal)

## Engineer Task Breakdown

Execute in strict order:

1. **Read** `lib/features/setlists/setlist_detail_screen.dart` lines 1462-1490 to confirm current implementation
2. **Rewrite** `_formatSongSecondLine()` method (lines 1462-1470) to:
   - Remove call to `_formatTwoColumnLine()`
   - Return `'$artist\n$bpmText • $tuningText'` directly
   - Preserve existing BPM null/zero handling (`'- BPM'` when invalid)
   - Preserve existing tuning label logic (`tuningShortLabel(song.tuning)`)
3. **Verify** `_formatTwoColumnLine()` has zero remaining callers via grep search
4. **Optionally remove** `_formatTwoColumnLine()` method (lines 1474-1487) or mark as dead code
5. **Run** `flutter analyze` and confirm zero errors
6. **Generate** `git diff` and confirm changes are isolated to `_formatSongSecondLine()` (and optionally `_formatTwoColumnLine()` removal)
7. **Write** `ENGINEER_REPORT.md` with:
   - Confirmation that `_formatSongSecondLine()` no longer calls `_formatTwoColumnLine()`
   - Decision: removed or preserved `_formatTwoColumnLine()`
   - `flutter analyze` output (must show 0 errors)
   - `git diff` output showing modified lines

## Verification Plan

**Tier 1 — Pre-deployment:** Not applicable (no database changes).

**Tier 2 — Post-deployment:** Not applicable (no database changes).

**Manual verification (QA responsibility):**

1. Open any setlist (Catalog or custom setlist)
2. Add 2-3 songs with varying artist name lengths and BPM/tuning values
3. Tap "Share" → select "Text (Email)" format
4. Inspect clipboard or share preview output
5. Confirm each song displays:
   ```
   Song Title
   Artist Name
   ### BPM • Tuning
   ```
6. Confirm NO right-justification padding between artist and BPM/tuning
7. Confirm BPM/tuning always appears on its own line (even for short artist names)
8. Test with edge cases:
   - Very short artist name (e.g., "U2")
   - Very long artist name (e.g., "The Jimi Hendrix Experience")
   - Missing BPM (should show `- BPM • Tuning`)
   - Standard tuning vs. alternate tuning (e.g., Drop D)
9. Verify spreadsheet format is unchanged:
   - Tap "Share" → select "Spreadsheet (CSV)"
   - Confirm tab-delimited format with header row `Title\tArtist\tBPM\tTuning`
   - Confirm no newline or formatting changes in spreadsheet output

## QA Regression Areas

QA must specifically test:

1. **Plain-text share format (primary):**
   - Output format matches new spec (artist on one line, BPM/tuning on next line)
   - No right-justification padding
   - Edge cases: very short/long artist names, missing BPM, alternate tunings

2. **Spreadsheet share format (regression check):**
   - Tab-delimited format unchanged
   - Header row present and correct
   - No newline or formatting corruption

3. **Share flow UI (regression check):**
   - Share button opens format picker bottom sheet
   - Both "Text (Email)" and "Spreadsheet (CSV)" options selectable
   - Selecting either format proceeds to OS share sheet or clipboard copy
   - Cancel button closes picker without action

4. **Other setlist operations (smoke test):**
   - Reorder songs (drag to new position)
   - Edit song metadata (BPM, duration, tuning inline editing)
   - Delete song from setlist
   - Add song to setlist (lookup, bulk entry, original song entry)
   - Setlist rename

## Rollout / Migration Strategy

Not applicable. No backend changes, no data migration, no staged rollout required. Change is live immediately upon deployment of the updated `setlist_detail_screen.dart`.

## Out of Scope

Explicitly excluded from this feature:

- Changes to `_generateSpreadsheetText()` or spreadsheet format
- Changes to `_formatHeaderSubline()` or `_formatTotalDuration()`
- Changes to any file other than `setlist_detail_screen.dart`
- New theme tokens, colors, or typography
- Database schema, RLS policies, RPC functions, or migrations
- Edge functions or backend logic
- New dependencies or packages
- Platform-specific share integrations
- Share UI redesign (bottom sheet, format picker)
- Setlist operations other than share (reorder, edit, delete, add)
