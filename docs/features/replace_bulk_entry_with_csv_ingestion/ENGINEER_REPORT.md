# ENGINEER_REPORT — replace_bulk_entry_with_csv_ingestion

> Date: 2026-03-01
> Role: Engineer
> Branch: `feature/replace_bulk_entry_with_csv_ingestion`

---

## 1) Goal

Replace the fragile per-cell `_PasteInterceptFormatter` paste-distribution infrastructure in BulkEntryScreen with a dedicated multiline CSV ingestion text field. The new flow sends pasted text through `BulkSongParser.parse()` directly, eliminating formatter race conditions and duplicated parsing logic.

---

## 2) Current State

Previously, BulkEntryScreen used `_PasteInterceptFormatter` (a `TextInputFormatter` subclass) and `_PasteAwareTextField` to detect multi-cell paste events, intercept them, and distribute values across table rows/columns. This caused race conditions with the Flutter text input pipeline and duplicated column-parsing logic already present in `BulkSongParser`.

---

## 3) Constraints (Non-negotiables)

- Follow docs/global/ARCHITECTURE.md
- Follow docs/global/AI_DECISIONS.md
- Follow documentation/RUNTIME_CONFIG.md
- Minimal changes only — single file modified
- No initialization order changes
- No new config loading paths
- No new dependencies

---

## 4) Files Modified

| # | File | Change Type |
|---|------|------------|
| 1 | `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Modified |

**Total files modified: 1**
**No new files created (other than this report).**
**No dependencies added.**

---

## 5) Summary of Changes

### Added

- **`_csvController`** (`TextEditingController`): Controller for the multiline CSV paste text field. Disposed in `dispose()`.
- **`_isLoadingSongs`** (`bool`): Guard flag preventing double-tap on "Load Songs" button. Button's `onTap` is `null` when `true`.
- **`_ingestionSummary`** (`String?`): Advisory summary displayed after parsing (e.g., "Loaded 12 songs, 2 skipped").
- **`_handleCsvIngestion()`**: Parses `_csvController.text` via `BulkSongParser.instance.parse()`, calls `_populateTableFromParseResult()`, clears the text field, and builds the advisory summary string.
- **`_populateTableFromParseResult(BulkSongParseResult)`**: Safely replaces all table rows:
  1. Unfocuses active focus via `FocusManager.instance.primaryFocus?.unfocus()`
  2. Resets `_focusedRowIndex` to 0
  3. Disposes all existing `_RowData` instances
  4. Creates new `_RowData` for each valid parsed row, setting controller text from parsed model
  5. Ensures at least one empty row exists
- **`_TableTextField`**: Simple replacement widget for `_PasteAwareTextField` — a standard `TextField` without paste interception. Same visual styling.
- **CSV ingestion UI in `build()`**: Multiline `TextField` with monospace font, placeholder showing expected format, bordered with accent color on focus. "Load Songs" button with loading state. Ingestion summary line shown after parse.

### Removed

- **`_PasteInterceptFormatter`** class: No longer needed — CSV ingestion replaces per-cell paste interception.
- **`_PasteAwareTextField`** class: Replaced by `_TableTextField` (no paste interception).
- **`_handlePasteFromText(int rowIndex, String pastedText)`** method: Paste distribution logic replaced by `_handleCsvIngestion`.
- **`_parsePasteColumns(String line)`** method: Duplicated `BulkSongParser._parseColumns` — no longer needed.
- **`onPasteText` parameter** in `_tableCell`: No longer threaded through to table cells.

### Unchanged

- `_handleSubmit()` path: Still serializes `_RowData` → TSV → `BulkSongParser.parse()` → `widget.onSubmit()`. No change.
- `_RowData` class: Unchanged.
- Row management (`_createRow`, `_addRow`, `_removeRow`): Unchanged.
- Table layout, column headers, footer, keyboard toolbar: Unchanged.
- `BulkSongParser` service: Not modified (reused as-is).
- `BulkSongRow` model: Not modified.

---

## 6) Verification Results

### `flutter analyze`

```
Analyzing bandroadie...

warning • Dead code • lib/features/lyrics/widgets/lyrics_view_screen.dart:347:19
 • dead_code
1 issue found. (ran in 4.0s)
```

**Result: PASS** — The single warning is pre-existing, in an unrelated file (`lyrics_view_screen.dart`). Zero new warnings or errors introduced.

### IDE Error Check

Zero errors in the modified file.

---

## 7) Notes for QA (Handoff)

### QA Focus Areas

1. **CSV Paste & Parse**: Paste comma-delimited and tab-delimited data into the multiline text field, tap "Load Songs", verify table populates correctly. Follow Test Cases 1–7 from ARCHITECT_PLAN.md Section 8.

2. **FocusNode lifecycle**: After loading songs, verify no "FocusNode used after dispose" errors in debug console. Test by:
   - Focusing a table cell
   - Pasting CSV into the text field
   - Tapping "Load Songs" while a cell is focused

3. **Double-tap guard**: Rapidly tap "Load Songs" — verify no crashes or duplicate processing.

4. **Text field clears after load**: After successful "Load Songs", verify the multiline text field is cleared.

5. **Ingestion summary**: Verify the summary line shows correct counts (loaded, skipped, duplicates removed).

6. **Manual editing after ingestion**: After loading songs via CSV, manually edit cells, add rows, delete rows — verify "Add Songs" submission still works correctly.

7. **Empty input**: Tap "Load Songs" with empty text field — verify no crash, no table change.

8. **Submit path unchanged**: The "Add Songs" button still re-parses from table controllers via TSV → `BulkSongParser.parse()`. Verify songs are correctly added to the setlist.

9. **Platform check**: Test on macOS at minimum. iOS and web if feasible.

### Known Risks

- **Comma in artist/song names**: Pre-existing limitation of `BulkSongParser._parseColumns`. Not introduced by this change.
- **Re-paste overwrites manual edits**: Acceptable for V1 per architect plan. No confirmation dialog.

### Not Changed

- No initialization order changes
- No config path changes
- No auth flow changes
- No database/RPC changes
- No new dependencies
