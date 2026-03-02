# ARCHITECT_PLAN — replace_bulk_entry_with_csv_ingestion

> Status: READY FOR ENGINEERING (updated)  
> Date: 2026-03-01 (revised 2026-03-01)  
> Role: Architect  
> Branch: `feature/replace_bulk_entry_with_csv_ingestion`  
> Revision: Addressed disposal lifecycle, advisory summary semantics, text field clearing, double-click guard, focus state reset.

---

## 1. Problem Summary

The BulkEntryScreen currently uses a spreadsheet-style table where each cell has a `_PasteInterceptFormatter` that detects multi-cell paste (tabs/newlines) and distributes values across columns and rows. This approach has proven fragile:

- The `_PasteInterceptFormatter` intercepts inside the Flutter text input formatter pipeline, causing race conditions between `onPaste` callbacks and the framework applying `oldValue` (ref: `fix_bulk_entry_paste_behavior` bug).
- The paste-distribution logic (`_handlePasteFromText`) duplicates column-parsing that already exists in `BulkSongParser._parseColumns`.
- Users must paste into a specific cell to trigger distribution — there is no dedicated ingestion surface.
- The formatter approach is inherently platform-fragile (different paste behaviors on iOS, Android, macOS, web).

The feature request replaces this with a single multiline text field for CSV-style ingestion, which is simpler, more reliable, and platform-consistent.

---

## 2. Why Current Model Is Incorrect

| Issue | Detail |
|-------|--------|
| **Formatter race condition** | `_PasteInterceptFormatter.formatEditUpdate` fires `onPaste` then returns `oldValue`. Framework applies `oldValue` after callback, clobbering controller state. Required `addPostFrameCallback` workaround. |
| **Duplicated parsing** | `_parsePasteColumns` in the screen duplicates `BulkSongParser._parseColumns`. Two separate column-splitting implementations to maintain. |
| **No dedicated input surface** | Paste must target a specific table cell. No clear affordance for "paste your list here." |
| **No validation feedback before commit** | Users see table rows but get no summary of recognized vs. skipped rows until after submission. |
| **Tuning parentheses not handled in UI paste path** | `_parsePasteColumns` splits naively on commas, so `Standard (E A D G B e)` may produce extra columns. Only `BulkSongParser._normalizeTuning` handles parenthetical stripping — but the UI paste path doesn't use it. |

---

## 3. Proposed CSV Ingestion Architecture

### 3.1 New UX Flow

1. **Ingestion surface**: Replace the instruction text at the top of BulkEntryScreen with a multiline `TextField` (the "paste box"). Placeholder text shows the expected CSV format.
2. **Parse trigger**: A "Parse" / "Load Songs" button below the text field triggers parsing. Parsing does NOT happen on every keystroke — it is an explicit action.
3. **Parsing**: The pasted/typed text is sent to `BulkSongParser.parse()` (reuse existing parser — it already supports comma-delimited input).
4. **Validation summary**: After parsing, display a brief summary line: e.g., "Loaded 12 songs (2 skipped)".
5. **Table population**: Parsed `BulkSongRow` objects populate the existing `_RowData` table controllers programmatically.
6. **Table remains the editing surface**: Users can manually edit any cell after ingestion, or add more rows by hand. The table UI is unchanged.
7. **Re-ingestion**: If the user pastes again, the text field clears the table and re-populates. Confirm if table has user edits (optional — can defer).
8. **Text field clears after successful load.** After "Load Songs" successfully populates the table, clear `_csvController.text`. The table is now the source of truth for editing. Retaining stale CSV text would create a confusing desync between the text field and the table state.
9. **Double-click guard.** The "Load Songs" button must be disabled while `_handleCsvIngestion` is executing. Use a `_isLoadingSongs` boolean flag: set `true` before parsing, set `false` after `setState` completes. The button's `onPressed` is `null` when the flag is `true`. This prevents rapid taps from triggering concurrent dispose/rebuild cycles.

### 3.2 Reuse BulkSongParser — Do NOT Create a New Parser

`BulkSongParser` already handles:
- Comma-delimited splitting (`_parseColumns`)
- Tab-delimited splitting (spreadsheet paste still works)
- BPM validation (1–300, int parse)
- Tuning normalization with parenthetical stripping (`_normalizeTuning`)
- De-duplication
- Per-row error/warning reporting via `BulkSongParseResult`

This parser is sufficient. The only change needed is **how input reaches it**:
- Currently: table controllers → `StringBuffer` (TSV reconstruction) → `BulkSongParser.parse()`
- Proposed: multiline text field → `BulkSongParser.parse()` directly

### 3.3 Table Population from Parse Result

After `BulkSongParser.parse()` returns a `BulkSongParseResult`:

1. **Dispose before replacing.** Before clearing `_rows`:
   - Call `FocusManager.instance.primaryFocus?.unfocus()` to release any active focus on a row's FocusNode.
   - Reset `_focusedRowIndex` to 0 (or -1).
   - Iterate the existing `_rows` list and call `.dispose()` on every `_RowData` instance to release all `TextEditingController` and `FocusNode` resources.
   - Only then clear the list.
   This prevents FocusNode-use-after-dispose and TextEditingController leak.
2. For each `BulkSongRow` in `parseResult.allRows` (or `validRows` — TBD by engineer):
   - Create a `_RowData`.
   - Set `row.artist.text`, `row.song.text`, `row.bpm.text`, `row.tuning.text` from the parsed model.
   - For `tuning`, use `tuningLabel` if available (human-readable), otherwise raw tuning ID.
   - For `bpm`, use `bpm?.toString() ?? ''`.
3. Call `setState` once after all rows are populated.

### 3.4 Removal of Paste-Distribution Infrastructure

The following are no longer needed and should be removed:

| Item | Location | Reason |
|------|----------|--------|
| `_PasteInterceptFormatter` class | `bulk_entry_screen.dart` L661–680 | No per-cell paste interception needed |
| `_PasteAwareTextField` class | `bulk_entry_screen.dart` L690–742 | Replaced by standard `TextField` without formatter |
| `_handlePasteFromText` method | `bulk_entry_screen.dart` L202–231 | Paste distribution logic replaced by CSV ingestion |
| `_parsePasteColumns` method | `bulk_entry_screen.dart` L233–240 | Duplicate of `BulkSongParser._parseColumns` |
| `onPasteText` parameter in `_tableCell` | `bulk_entry_screen.dart` L470 | No longer passed |

Table cells should use a plain `TextField` (or a simpler private widget without paste interception).

### 3.5 Submission Path (Unchanged)

`_handleSubmit` currently serializes `_RowData` back to TSV → `BulkSongParser.parse()`. After this change:
- Option A (simpler): Keep the same serialization path. Table edits are re-parsed on submit.
- Option B (cleaner): Store the `BulkSongParseResult` from ingestion, then reconcile with table edits on submit.

**Recommendation: Option A.** It's the minimal change. The existing `_handleSubmit` → `BulkSongParser.parse()` pipeline works, and manual table edits naturally flow through it. No new state management needed.

> **Design principle:** The ingestion summary ("Loaded 12 songs, 2 skipped") displayed after "Load Songs" is **advisory only** — it reflects the ingestion-time parse for user feedback. The **submission parse** (triggered by "Add Songs" / `_handleSubmit`) is the **authoritative** parse. The engineer must NOT cache or reuse the ingestion `BulkSongParseResult` at submit time. This ensures manual table edits are always captured.

---

## 4. Exact Files To Modify

| # | File | Change Type | Description |
|---|------|------------|-------------|
| 1 | `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | **Modify** | Add multiline paste text field + "Load Songs" button. Remove `_PasteInterceptFormatter`, `_PasteAwareTextField`, `_handlePasteFromText`, `_parsePasteColumns`. Replace `_PasteAwareTextField` with plain `TextField` in table cells. Add `_populateTableFromParseResult` method. Update `build()` layout. |
| 2 | `lib/features/setlists/services/bulk_song_parser.dart` | **No change** | Already supports CSV input. Reuse as-is. |
| 3 | `lib/features/setlists/models/bulk_song_row.dart` | **No change** | Model is sufficient. |

**Total files modified: 1**

No new files are required. No new dependencies.

---

## 5. What To Remove / Deprecate

| Item | Action |
|------|--------|
| `_PasteInterceptFormatter` class | **Delete** |
| `_PasteAwareTextField` class | **Delete** — replace with a simpler private `_TableTextField` that uses standard `TextField` without paste interception |
| `_handlePasteFromText(int rowIndex, String pastedText)` | **Delete** |
| `_parsePasteColumns(String line)` | **Delete** |
| `onPasteText` parameter threading through `_tableCell` and `_PasteAwareTextField` | **Remove** |

---

## 6. Risks / Edge Cases

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Comma inside artist/song name** (e.g., "Crosby, Stills & Nash") | Medium | `BulkSongParser._parseColumns` splits on comma naively. This is an existing limitation, not introduced by this change. Document that CSV format does not support quoted fields. Future enhancement could add quote-aware splitting. |
| **Tuning with commas** (e.g., "Standard (E, A, D, G, B, e)") | Medium | `_normalizeTuning` strips parenthetical content. But if commas appear inside tuning before parenthetical stripping, `_parseColumns` splits on them first. Mitigation: parenthetical content won't appear in the 4th column because the comma split happens first. The user should omit parentheticals. This is existing behavior. |
| **Large paste (500+ rows)** | Low | `maxRows: _kMaxRows` already enforced in `BulkSongParser.parse()`. No change needed. |
| **Mobile keyboard covers paste field** | Low | Use `ScrollView` and `MediaQuery.of(context).viewInsets.bottom` padding (already done for table). Test on iOS. |
| **Web paste behavior** | Low | Multiline `TextField` handles paste natively on all platforms. This is actually *more* reliable than the formatter approach. |
| **Users with existing muscle memory** | Low | UX change: users who knew to paste into cell 1 must now paste into the text field. Clear placeholder text mitigates this. |
| **Re-paste overwrites manual edits** | Low | If user manually edits table rows, then pastes again, edits are lost. Acceptable for V1. Can add confirmation dialog later. |
| **FocusNode use-after-dispose on row replacement** | Medium | If a row's FocusNode has focus when `_rows` are replaced without unfocusing first, Flutter throws. Mitigation: `_populateTableFromParseResult` must call `FocusManager.instance.primaryFocus?.unfocus()` and reset `_focusedRowIndex` before disposing old rows. See Section 3.3. |
| **Rapid double-tap on "Load Songs"** | Medium | Concurrent `_handleCsvIngestion` calls could dispose rows mid-rebuild. Mitigation: `_isLoadingSongs` guard flag disables button during execution. See Section 3.1 step 9. |
| **Stale CSV text after load** | Low | If text field retains CSV after table population, users may assume editing the text field updates the table. Mitigation: Clear `_csvController` after successful load. See Section 3.1 step 8. |

---

## 7. Migration Strategy

No data migration needed. This is a UI-only change.

- No database changes.
- No Supabase RPC changes.
- No model changes.
- No provider/controller changes.
- No auth flow changes.
- No initialization order changes.

The `BulkSongRow` model and `BulkSongParser` service remain the contract between the UI and the submission pipeline.

---

## 8. Verification Plan

### Static Analysis

```bash
flutter analyze
```

Expected: No new warnings or errors.

### Manual Testing

**Test 1: CSV Paste — Full Fields**
1. Open any setlist → Add (+) → Bulk Entry
2. Paste into the multiline text field:
   ```
   3 Doors Down,Kryptonite,100,Standard
   Aerosmith,Eat The Rich,123,Standard
   ```
3. Tap "Load Songs"
4. Verify: Table shows 2 rows with all 4 columns populated correctly.

**Test 2: CSV Paste — BPM/Tuning Omitted**
1. Paste:
   ```
   3 Doors Down,Kryptonite
   Aerosmith,Eat The Rich
   ```
2. Tap "Load Songs"
3. Verify: Table shows 2 rows. BPM and Tuning columns are empty.

**Test 3: Tuning Normalization**
1. Paste:
   ```
   Tool,Schism,87,Drop D (D A D G B E)
   ```
2. Tap "Load Songs"
3. Verify: Tuning column shows "Drop D" (parenthetical stripped).

**Test 4: Invalid Rows Don't Crash**
1. Paste:
   ```
   VALID ROW,Song Title,120,Standard
   single-value-only
   ,Missing Artist
   Another Band,Another Song
   ```
2. Tap "Load Songs"
3. Verify: Summary shows recognized vs skipped. Valid rows populate table. Invalid rows are excluded (or shown with indicator).

**Test 5: Manual Editing After Paste**
1. Paste CSV data and load.
2. Manually edit BPM in row 1.
3. Add a new row manually.
4. Tap "Add Songs".
5. Verify: All rows (parsed + manual) submit correctly.

**Test 6: Spreadsheet Paste Still Works**
1. Copy tab-delimited data from Google Sheets.
2. Paste into multiline text field.
3. Tap "Load Songs".
4. Verify: Tab-delimited input is parsed correctly (BulkSongParser supports TSV).

**Test 7: Empty Paste**
1. Leave text field empty.
2. Tap "Load Songs".
3. Verify: No crash. No table change. Possibly show "No songs found" message.

**Test 8: Platform Check**
- Test on macOS (primary dev platform).
- Test on iOS (mobile keyboard behavior).
- Test on web (paste behavior).

### Existing Tests

```bash
flutter test
```

No existing tests for BulkEntryScreen or BulkSongParser. Engineer should add unit tests for the table-population logic if time permits.

---

## 9. Engineering Task Breakdown

The engineer should implement this as a single atomic task:

### Task 1: Replace paste-distribution with CSV ingestion in BulkEntryScreen

**File:** `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

**Steps:**
1. Add a `TextEditingController` for the multiline paste text field (e.g., `_csvController`).
2. Add state flags: `bool _hasLoadedSongs` (tracks whether songs have been loaded) and `bool _isLoadingSongs` (guards against double-tap).
3. In `build()`, replace the instruction `Text` widget with:
   - A multiline `TextField` with placeholder showing CSV format example.
   - A "Load Songs" button that calls `_handleCsvIngestion()`.
   - A validation summary line (e.g., "Loaded X songs, Y skipped").
4. Implement `_handleCsvIngestion()`:
   - Guard: if `_isLoadingSongs` is true, return immediately.
   - Set `_isLoadingSongs = true` via `setState`.
   - Call `BulkSongParser.instance.parse(_csvController.text, maxRows: _kMaxRows)`.
   - Call `_populateTableFromParseResult(parseResult)`.
   - Clear `_csvController.text` after successful population.
   - Update validation summary state.
   - Set `_isLoadingSongs = false` via `setState`.
5. Implement `_populateTableFromParseResult(BulkSongParseResult result)`:
   - Unfocus: `FocusManager.instance.primaryFocus?.unfocus()`.
   - Reset `_focusedRowIndex`.
   - Dispose every existing `_RowData` in `_rows` (iterate + call `.dispose()`).
   - Clear `_rows`.
   - Create new `_RowData` for each valid row.
   - Set controller text values from parsed data.
   - Call `setState`.
6. Delete `_PasteInterceptFormatter` class.
7. Delete `_PasteAwareTextField` class.
8. Delete `_handlePasteFromText` method.
9. Delete `_parsePasteColumns` method.
10. Replace `_PasteAwareTextField` usage in `_tableCell` with a simpler `TextField` widget.
11. Clean up `dispose()` to also dispose `_csvController`.
12. Run `flutter analyze`.

---

## Appendix: Current Data Flow vs. Proposed

### Current Flow
```
User pastes into cell
  → _PasteInterceptFormatter detects tabs/newlines
  → onPaste callback → _handlePasteFromText
  → _parsePasteColumns splits line into cells
  → Sets _RowData controllers directly
  → On submit: _RowData → TSV StringBuffer → BulkSongParser.parse() → BulkSongRow[]
  → widget.onSubmit(validRows)
```

### Proposed Flow
```
User pastes into multiline text field
  → Taps "Load Songs"
  → BulkSongParser.parse(csvText) → BulkSongParseResult
  → _populateTableFromParseResult sets _RowData controllers
  → User can manually edit table
  → On submit: _RowData → TSV StringBuffer → BulkSongParser.parse() → BulkSongRow[]
  → widget.onSubmit(validRows)
```

Key difference: Parsing happens **once at ingestion** via a clean API call, not through a fragile formatter pipeline. The submit path remains identical.
