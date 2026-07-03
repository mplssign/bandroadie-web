# Architect Plan — Song Edit Metadata Tap-to-Edit UI

## Feature Slug

`song-edit-metadata-tap-to-edit`

## Problem Summary

In the Song Edit UI (`song_details_bottom_sheet.dart`), four metadata fields — BPM, Duration, Tuning, Key — currently use mixed interaction patterns: BPM and Duration allow inline text editing, while Tuning and Key open separate UI surfaces. The requirement is to standardize all four fields as **read-only label + value pairs** with tap-to-edit behavior: tapping opens a dialog or bottom sheet for input.

The four fields must be displayed as a **single grouped ButtonGroup component** — one connected segmented strip with four segments — not four independent bordered containers in a Row:

```
┌──────────────────────────────────────────────────┐
│  BPM    │ Duration │   Tuning   │      Key      │
│  123    │   4:10   │  Standard  │       E       │
└──────────────────────────────────────────────────┘
```

Each segment: label on top (secondary text, small), current value below (primary text). The entire segment is the tap target.

**Explicitly unchanged:**

- Song Title and Artist keep their existing TextField inputs (tap-to-edit already implemented at lines 923-1067)
- No other fields or screens change
- Persistence paths remain unchanged

## Root Cause

Not applicable — this is a feature request, not a bug fix.

**Confidence:** N/A (feature)

## Reference Docs Consulted

No song/setlist-specific reference documentation exists. Consulted:

- `docs/reference/architecture/database_schema.md` — confirmed `songs` table schema and `musical_key` field
- Migrations `20260630000000_add_musical_key_to_songs.sql` and `20260630000001_add_musical_key_to_update_song_rpc.sql` — confirmed Key field exists as `musical_key` TEXT, persisted via `update_song_metadata` RPC

## Existing System Analysis

### Current UI Implementation

File: `lib/features/setlists/widgets/song_details_bottom_sheet.dart` (1,703 lines)

**Method:** `_buildMetricsRow()` (lines 1072-1264)

Current pattern for the four metadata fields:

1. **BPM** (lines 1085-1129): TextField with numeric keyboard, inline editing, range 20-300
2. **Duration** (lines 1134-1158): `MaskedDurationInput` widget (currency-style mm:ss input), inline editing
3. **Tuning** (lines 1163-1210): Read-only Container + GestureDetector → opens `showTuningPickerBottomSheet`
4. **Key** (lines 1215-1262): Read-only Container + GestureDetector → opens `_showKeyPicker()` AlertDialog

**Key option lists** (lines 21-48):

- `_kMajorKeys`: 12 major keys (C, C#, D, Eb, E, F, F#, G, Ab, A, Bb, B)
- `_kMinorKeys`: 12 minor keys (Cm, C#m, Dm, Ebm, Em, Fm, F#m, Gm, Abm, Am, Bbm, Bm)
- Total: 24 standard keys

**Tuning options:** Defined in `tuning_picker_bottom_sheet.dart` and `tuning/tuning_helpers.dart` — includes standard tunings (Standard E, Drop D, etc.) and custom user-defined tunings.

### Persistence Path

**Entry point:** `setlist_detail_screen.dart:1120` — calls `showSongDetailsBottomSheet()` when user taps a song card.

**Save flow (lines 1126-1223):**

1. Sheet returns `SongDetailsResult` with changed fields flagged
2. Screen checks each `*Changed` flag and calls corresponding controller method:
   - `updateSongBpm()` / `clearSongBpm()` (lines 1159-1168)
   - `updateSongDuration()` (lines 1172-1178)
   - `updateSongTuning()` (lines 1188-1195)
   - `updateSongMusicalKey()` (lines 1218-1222)

**Controller layer:** `setlist_detail_controller.dart`

- Each `update*()` method calls the repository

**Repository layer:** `setlist_repository.dart`

- All four fields persist via `update_song_metadata` RPC (SECURITY DEFINER function, bypasses RLS for legacy NULL band_id songs)
- RPC signature (11 parameters): `p_song_id`, `p_band_id`, `p_bpm`, `p_duration_seconds`, `p_tuning`, `p_notes`, `p_title`, `p_artist`, `p_youtube_links`, `p_lyrics`, `p_musical_key`
- Example: `updateSongMusicalKey()` at line 2163 calls RPC with only `p_musical_key` populated, all others null

**Schema:**

- `songs` table: `bpm` INT, `duration_seconds` INT, `tuning` TEXT, `musical_key` TEXT
- No setlist-level overrides for Key (it's song-global only)

### Discovery: Key Field Already Persisted

The `musical_key` field was added via migration `20260630000000_add_musical_key_to_songs.sql`. The field is TEXT, nullable, and validated client-side. The `update_song_metadata` RPC was updated to accept `p_musical_key` (11-parameter signature). The save path is fully implemented (lines 1218-1222 in `setlist_detail_screen.dart`).

## Proposed Solution

### UI Changes

Replace the inline editing widgets for BPM and Duration with read-only displays + tap targets that open dialogs. Change the Key field from AlertDialog to bottom sheet for consistency with Tuning. **Render all four fields as a single grouped ButtonGroup component** — one connected segmented strip with equal-width segments (or flexibly weighted based on content).

**New interaction model:**

1. **BPM:** Tap segment → open numeric input dialog (range 20-300, allow clear to null)
2. **Duration:** Tap segment → open mm:ss input dialog (masked input, same behavior as current `MaskedDurationInput`)
3. **Tuning:** Tap segment → open tuning bottom sheet (unchanged from existing behavior) ✓
4. **Key:** Tap segment → open key bottom sheet (change from AlertDialog to bottom sheet for consistency)

**Visual layout:** Single grouped ButtonGroup with four segments. Each segment displays:

```
Label (secondary text, small, e.g., "BPM")
Value (primary text, e.g., "123")
```

The entire segment is the tap target. Long tuning names (e.g., "Open D Suspended") must ellipsize with `TextOverflow.ellipsis`, not overflow.

**Component selection:**

- Check `lib/components/ui/` for existing ButtonGroup/segmented component → **none found**
- Evaluate Flutter's `SegmentedButton` widget as a base → **not present in codebase**
- Create a custom reusable `SegmentedButtonGroup` widget in `lib/components/ui/` styled with existing design tokens (`AppColors`, `AppTextStyles`, `Spacing`)
- The widget should accept a list of segments with label, value, and onTap callback
- Render as a single rounded container with internal dividers between segments
- Each segment: vertically stacked label + value, centered, equal flex weight (or weighted based on content if needed)

### Implementation Strategy

1. Create a new reusable `SegmentedButtonGroup` widget in `lib/components/ui/segmented_button_group.dart`
2. Extract the BPM input logic into a new dialog: `bpm_input_dialog.dart` with explicit return type distinguishing cancelled/cleared/new value
3. Extract the Duration input logic into a new dialog: `duration_input_dialog.dart` with explicit return type distinguishing cancelled/cleared/new value
4. Extract the Key picker logic into a new bottom sheet: `key_picker_bottom_sheet.dart`
5. Update `_buildMetricsRow()` in `song_details_bottom_sheet.dart`:
   - Replace the four independent containers with a single `SegmentedButtonGroup` instance
   - Add `int? _currentBpm` state variable (initialized from `widget.song.bpm`) to mirror `_currentDurationSeconds` and `_currentMusicalKey`
   - Remove `_bpmController` and its listeners
   - BPM segment tap → `_selectBpm()` → updates `_currentBpm` → `_checkForChanges()`
   - Duration segment tap → `_selectDuration()` → updates `_currentDurationSeconds` → `_checkForChanges()`
   - Tuning segment tap → `_selectTuning()` (existing logic)
   - Key segment tap → `_selectKey()` → updates `_currentMusicalKey` → `_checkForChanges()`
6. Remove or comment out `_showKeyPicker()` method (lines 431-523) — replaced by new bottom sheet
7. Preserve all other state variables and `_checkForChanges()` logic
8. Ensure `_checkForChanges()` compares `_currentBpm` and flows BPM changes into `SongDetailsResult` changed-flags so `updateSongBpm()` / `clearSongBpm()` fire correctly

**Dialog return type specification (Amendment 3):**

Both BPM and Duration dialogs must distinguish three outcomes: cancelled (no change), cleared (set to null), and new value. Use a sealed result class or a record with an explicit flag:

```dart
sealed class DialogResult<T> {}
class DialogCancelled<T> extends DialogResult<T> {}
class DialogCleared<T> extends DialogResult<T> {}
class DialogValue<T> extends DialogResult<T> {
  final T value;
  DialogValue(this.value);
}
```

Or simpler record-based approach:

```dart
typedef DialogResult<T> = ({bool cancelled, T? value});
// cancelled: true → user cancelled (no change)
// cancelled: false, value: null → user cleared
// cancelled: false, value: T → new value
```

The handler in `_SongDetailsSheetState` must interpret these three cases correctly:
- Cancelled → no state change, no `_checkForChanges()`
- Cleared → set `_currentBpm` or `_currentDurationSeconds` to null/0, call `_checkForChanges()`
- New value → set state to value, call `_checkForChanges()`

**BPM dialog requirements:**

- TextField with numeric keyboard
- InputFormatter: digits only, max 3 digits
- Validation: 20-300 range, show error for out-of-range
- "Clear" button (returns `DialogCleared`)
- "Cancel" button (returns `DialogCancelled`)
- "Save" button (returns `DialogValue(int)` if valid, else blocks)

**Duration dialog requirements:**

- Reuse `MaskedDurationInput` widget (already implemented, currency-style mm:ss)
- Or implement simpler TextField with mm:ss mask
- "Clear" button (returns `DialogCleared`)
- "Cancel" button (returns `DialogCancelled`)
- "Save" button (returns `DialogValue(int)` seconds)

**Key picker bottom sheet requirements:**

- Scrollable list with two sections: Major (12), Minor (12)
- Section headers styled as secondary text
- ListTile for each key, checkmark icon for selected
- Tap to select and auto-dismiss (returns key string)
- Cancel button at bottom (returns null)

### Rationale

- **Consistency:** All four metadata fields use tap-to-edit, no inline editing
- **Predictability:** User knows to tap the segment, not the container
- **Visual cohesion:** Single grouped component (not four separate bordered boxes) creates a cleaner, more intentional UI
- **Focus management:** No keyboard appearing on the sheet itself, avoiding layout shift
- **Reusability:** `SegmentedButtonGroup` widget can be used elsewhere; dialogs/sheets can be tested independently
- **No persistence changes:** Existing save logic is untouched, reducing regression risk
- **Ellipsis handling:** Long tuning names are truncated gracefully, preventing UI overflow

## Database Impact

**Not applicable** — UI-only change. All fields already exist in the `songs` table:

- `bpm` INT — exists ✓
- `duration_seconds` INT — exists ✓
- `tuning` TEXT — exists ✓
- `musical_key` TEXT — exists (added via migration 20260630000000) ✓

The `update_song_metadata` RPC already accepts all 11 parameters including `p_musical_key`. No schema changes, no migration required.

## Flutter Architecture Changes

### State

**Added:**

- `int? _currentBpm` in `_SongDetailsSheetState` — initialized from `widget.song.bpm`, updated by BPM dialog result, rendered in BPM segment, compared in `_checkForChanges()`

**Removed:**

- `_bpmController` (TextEditingController) — replaced by `_currentBpm` state + dialog

**Unchanged:**

- `_currentDurationSeconds` (int) — updated by Duration dialog result instead of widget listener
- `_currentTuning` (String) — unchanged ✓
- `_currentMusicalKey` (String?) — unchanged ✓

### Widgets

**Modified:**

- `song_details_bottom_sheet.dart`: Replace `_buildMetricsRow()` four-container layout with single `SegmentedButtonGroup`, add `_currentBpm` state, remove `_bpmController` and `_showKeyPicker()` method

**Created:**

- `segmented_button_group.dart`: Reusable grouped segmented UI component (label + value per segment, tap callbacks)
- `bpm_input_dialog.dart`: Dialog for numeric BPM input (20-300) with `DialogResult<int>` return type
- `duration_input_dialog.dart`: Dialog for mm:ss duration input with `DialogResult<int>` return type
- `key_picker_bottom_sheet.dart`: Bottom sheet for 24-key selection (replaces `_showKeyPicker()` AlertDialog)

### Repositories

No changes — `setlist_repository.dart` persistence methods remain unchanged.

### Controllers

No changes — `setlist_detail_controller.dart` methods remain unchanged.

## Files to Create

| File                                                              | Purpose                                                  | Justification                                                                                                                                  |
| ----------------------------------------------------------------- | -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/segmented_button_group.dart`                   | Reusable grouped segmented UI component                  | No existing ButtonGroup in `lib/components/ui/`. Create reusable widget styled with design tokens. Single responsibility: render grouped segments. |
| `lib/features/setlists/widgets/bpm_input_dialog.dart`             | Numeric input dialog for BPM (20-300)                    | Extract BPM editing logic from inline TextField; isolate validation and range enforcement; explicit `DialogResult<int>` return type               |
| `lib/features/setlists/widgets/duration_input_dialog.dart`        | Masked mm:ss input dialog for duration                   | Extract Duration editing logic from inline MaskedDurationInput; explicit `DialogResult<int>` return type                                          |
| `lib/features/setlists/widgets/key_picker_bottom_sheet.dart`      | Bottom sheet for 24-key selection (major/minor)          | Replace AlertDialog with bottom sheet for consistency with Tuning picker; scrollable list with section headers                                    |

**Justification for separate files:** Each dialog/sheet is 100-200 lines with its own state, validation, and UI logic. Extracting them keeps `song_details_bottom_sheet.dart` maintainable and allows independent testing. The `SegmentedButtonGroup` widget is a reusable UI primitive that can be used in other features.

## Files to Modify

| File                                                           | What changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | **Lines 1072-1264 (`_buildMetricsRow()`):** Replace four-container Row layout with single `SegmentedButtonGroup` instance. Add `int? _currentBpm` state (initialized from `widget.song.bpm`). Remove `_bpmController`, its listeners, `_parseBpm()` method, and `_showKeyPicker()` method (lines 431-523). Add handlers: `_selectBpm()`, `_selectDuration()`, `_selectTuning()`, `_selectKey()`. Render BPM segment from `_currentBpm`, Duration from `_currentDurationSeconds`, Tuning from `_currentTuning`, Key from `_currentMusicalKey`. Ensure `_checkForChanges()` compares `_currentBpm` and flows BPM changes into `SongDetailsResult` flags. |

## Files Off-Limits

| File                                                            | Reason                                                                                             |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart`              | 3,190 lines — persistence logic at lines 1117-1225 must not change. No modifications to save flow. |
| `lib/features/setlists/setlist_repository.dart`                 | 4,138 lines — `update_song_metadata` RPC calls must not change. Repository methods untouched.      |
| `lib/features/setlists/setlist_detail_controller.dart`          | Controller methods untouched.                                                                      |
| `lib/features/setlists/models/song.dart`                        | Song model untouched.                                                                              |
| `lib/features/setlists/widgets/masked_duration_input.dart`      | May be reused in duration dialog, but not modified. Or replaced by simpler TextField mask.         |
| `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` | Tuning picker unchanged (already tap-to-sheet).                                                    |
| `lib/features/setlists/widgets/reorderable_song_card.dart`      | Inline tuning editing on song cards is separate from Song Edit sheet — no changes.                 |
| `lib/app/theme/design_tokens.dart`                              | Use existing tokens only (AppColors, AppTextStyles, Spacing). No new global colors.                |
| `supabase/migrations/**`                                        | No schema changes.                                                                                 |

## System Impact Map

| System                                 | Impact                                                                                                                                         |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Songs / Catalog                        | **Affected** — UI change in Song Edit sheet (metadata fields now single grouped ButtonGroup with tap-to-edit)                                  |
| Setlists                               | **Affected** — Song Edit accessed from setlist detail screen                                                                                   |
| Gigs                                   | **Unaffected** — No gig-related code touched                                                                                                   |
| Rehearsals                             | **Unaffected** — No rehearsal-related code touched                                                                                             |
| Members / RBAC                         | **Unaffected** — No permission changes                                                                                                         |
| Auth / Session                         | **Unaffected** — No auth changes                                                                                                               |
| Routing                                | **Unaffected** — No route changes                                                                                                              |
| Notifications                          | **Unaffected** — No notification triggers                                                                                                      |
| Platform (iOS / Android / Web / macOS) | **Affected (UI only)** — Dialogs and bottom sheets work on all platforms. Keyboard behavior unchanged (numeric for BPM, numeric for Duration). |

## Regression Risk

**Level:** LOW

**Rationale:**

- **UI-only change** — No logic changes to persistence paths, repository, controller, or RPC
- **Isolated scope** — Only `_buildMetricsRow()` and four new files (one reusable component, three dialogs/sheets)
- **No Title/Artist changes** — Explicitly preserved (lines 923-1067)
- **No Tuning changes** — Already tap-to-sheet, unchanged
- **Persistence paths verified** — `update_song_metadata` RPC handles all four fields, no new code paths
- **No schema changes** — All fields exist, no migration
- **Single entry point** — Song Edit sheet only called from `setlist_detail_screen.dart:1120`
- **Platform-agnostic** — Dialogs and bottom sheets use standard Flutter widgets, no platform-specific code
- **Reusable component** — `SegmentedButtonGroup` is a standalone UI primitive with no dependencies on feature logic

**Potential risks:**

- **Focus management:** Ensure dialogs dismiss keyboard properly
- **Change detection:** `_checkForChanges()` must fire correctly after dialog edits (test BPM/Duration null → value → null transitions)
- **Validation:** BPM range (20-300) must enforce in dialog, not silently fail
- **Ellipsis truncation:** Long tuning names must not cause overflow or layout breakage

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Create SegmentedButtonGroup Widget

- Create `lib/components/ui/segmented_button_group.dart`
- Define a reusable widget that accepts a list of segments
- Each segment: `{String label, String value, VoidCallback? onTap}`
- Render as a single rounded container (border radius from `Spacing.buttonRadius`)
- Internal dividers between segments (1px width, border color)
- Each segment: Column with label (secondary text, small) on top, value (primary text) below, centered
- Equal flex weight for segments (or weighted based on content if needed)
- Long values: `TextOverflow.ellipsis`, `maxLines: 1`
- Use `AppColors`, `AppTextStyles`, `Spacing` from design_tokens.dart
- Widget signature example:
  ```dart
  class SegmentedButtonGroup extends StatelessWidget {
    final List<SegmentData> segments;
    const SegmentedButtonGroup({required this.segments});
  }
  class SegmentData {
    final String label;
    final String value;
    final VoidCallback? onTap;
    SegmentData({required this.label, required this.value, this.onTap});
  }
  ```

### Task 2: Create BPM Input Dialog with DialogResult Return Type

- Create `lib/features/setlists/widgets/bpm_input_dialog.dart`
- Define `DialogResult<T>` sealed class or record type:
  ```dart
  sealed class DialogResult<T> {}
  class DialogCancelled<T> extends DialogResult<T> {}
  class DialogCleared<T> extends DialogResult<T> {}
  class DialogValue<T> extends DialogResult<T> {
    final T value;
    DialogValue(this.value);
  }
  ```
- Implement `showBpmInputDialog()` function
- StatefulWidget with TextField (numeric keyboard, max 3 digits)
- Validation: enforce 20-300 range, show error text below field for out-of-range
- Three buttons:
  - "Cancel" (returns `DialogCancelled<int>()`)
  - "Clear" (returns `DialogCleared<int>()`)
  - "Save" (validates and returns `DialogValue<int>(bpm)` if valid, else blocks with error)
- Use `AppColors`, `AppTextStyles`, `Spacing` from design_tokens.dart
- Return type: `Future<DialogResult<int>>`

### Task 3: Create Duration Input Dialog with DialogResult Return Type

- Create `lib/features/setlists/widgets/duration_input_dialog.dart`
- Reuse `DialogResult<T>` type from Task 2 (or define inline if not exported)
- Implement `showDurationInputDialog()` function
- Reuse `MaskedDurationInput` widget inside dialog OR implement simpler TextField with mm:ss mask
- Three buttons:
  - "Cancel" (returns `DialogCancelled<int>()`)
  - "Clear" (returns `DialogCleared<int>()`)
  - "Save" (returns `DialogValue<int>(seconds)`)
- Use `AppColors`, `AppTextStyles`, `Spacing` from design_tokens.dart
- Return type: `Future<DialogResult<int>>`

### Task 4: Create Key Picker Bottom Sheet

- Create `lib/features/setlists/widgets/key_picker_bottom_sheet.dart`
- Implement `showKeyPickerBottomSheet()` function
- Scrollable ListView with two sections:
  - "Major" section header (secondary text, padding)
  - 12 ListTile widgets (`_kMajorKeys` list copied from song_details_bottom_sheet.dart)
  - Divider
  - "Minor" section header
  - 12 ListTile widgets (`_kMinorKeys` list)
- Each ListTile shows key name, trailing checkmark if selected
- Tap ListTile → return key string and auto-dismiss
- Cancel button at bottom (returns null)
- Use `AppColors`, `AppTextStyles`, `Spacing` from design_tokens.dart
- Copy `_kMajorKeys` and `_kMinorKeys` constants into this file
- Return type: `Future<String?>`

### Task 5: Update Song Details Sheet Imports and Add _currentBpm State

- Open `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
- Add imports:
  ```dart
  import '../../../components/ui/segmented_button_group.dart';
  import 'bpm_input_dialog.dart';
  import 'duration_input_dialog.dart';
  import 'key_picker_bottom_sheet.dart';
  ```
- In `_SongDetailsSheetState`, add new state variable:
  ```dart
  int? _currentBpm;
  ```
- In `initState()`, initialize `_currentBpm`:
  ```dart
  _currentBpm = widget.song.bpm;
  ```
- In `_checkForChanges()`, add comparison for `_currentBpm`:
  ```dart
  final bpmChanged = _currentBpm != widget.song.bpm;
  ```
- Update the `SongDetailsResult` return to include BPM change flag (it should already exist, verify it's set correctly)

### Task 6: Remove BPM TextField State and Method

- In `_SongDetailsSheetState`:
  - Remove `_bpmController` TextEditingController declaration (line ~212)
  - Remove `_bpmController` initialization in `initState()` (line ~245)
  - Remove `_bpmController.addListener(_checkForChanges)` (line ~269)
  - Remove `_bpmController.removeListener(_checkForChanges)` in `dispose()` (line ~308)
  - Remove `_bpmController.dispose()` (line ~312)
  - Remove `_parseBpm()` method (lines 368-386) — replaced by dialog validation
- Remove `_showKeyPicker()` method (lines 431-523) — replaced by bottom sheet
- Remove `_kMajorKeys` and `_kMinorKeys` constants (lines 21-48) — moved to key_picker_bottom_sheet.dart

### Task 7: Add Dialog/Sheet Handler Methods

- Add BPM handler:
  ```dart
  Future<void> _selectBpm() async {
    final result = await showBpmInputDialog(
      context,
      initialBpm: _currentBpm,
    );
    if (result is DialogCleared<int>) {
      setState(() {
        _currentBpm = null;
      });
      _checkForChanges();
    } else if (result is DialogValue<int>) {
      setState(() {
        _currentBpm = result.value;
      });
      _checkForChanges();
    }
    // DialogCancelled → no change
  }
  ```
- Add Duration handler:
  ```dart
  Future<void> _selectDuration() async {
    final result = await showDurationInputDialog(
      context,
      initialSeconds: _currentDurationSeconds,
    );
    if (result is DialogCleared<int>) {
      setState(() {
        _currentDurationSeconds = 0;
      });
      _checkForChanges();
    } else if (result is DialogValue<int>) {
      setState(() {
        _currentDurationSeconds = result.value;
      });
      _checkForChanges();
    }
    // DialogCancelled → no change
  }
  ```
- Add helper for duration formatting:
  ```dart
  String _formatDuration(int seconds) {
    if (seconds <= 0) return '—';
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
  ```
- Add Key handler:
  ```dart
  Future<void> _selectKey() async {
    final result = await showKeyPickerBottomSheet(
      context,
      selectedKey: _currentMusicalKey,
    );
    if (result != null && result != _currentMusicalKey) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentMusicalKey = result;
      });
      _checkForChanges();
    }
  }
  ```
- Verify existing Tuning handler is correctly wired (should already exist)

### Task 8: Replace _buildMetricsRow() with SegmentedButtonGroup

- Locate `_buildMetricsRow()` method (lines 1072-1264)
- Replace the entire Row with four Container children with:
  ```dart
  Widget _buildMetricsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Optional: Add a section label if needed, or remove
        SegmentedButtonGroup(
          segments: [
            SegmentData(
              label: 'BPM',
              value: _currentBpm?.toString() ?? '—',
              onTap: widget.isReadOnly ? null : _selectBpm,
            ),
            SegmentData(
              label: 'Duration',
              value: _formatDuration(_currentDurationSeconds),
              onTap: widget.isReadOnly ? null : _selectDuration,
            ),
            SegmentData(
              label: 'Tuning',
              value: _currentTuning ?? '—',
              onTap: widget.isReadOnly ? null : _selectTuning,
            ),
            SegmentData(
              label: 'Key',
              value: _currentMusicalKey ?? '—',
              onTap: widget.isReadOnly ? null : _selectKey,
            ),
          ],
        ),
      ],
    );
  }
  ```
- Preserve any existing section label or spacing above/below the ButtonGroup
- Ensure the method signature and return type remain unchanged

### Task 9: Verify and Test Locally

- Run `flutter analyze` — must pass with 0 errors
- Test on iOS simulator:
  1. Open Song Edit sheet (tap any song in setlist)
  2. Verify BPM, Duration, Tuning, Key display as a **single grouped segmented strip**, not four separate containers
  3. Verify each segment has label on top, value below, centered
  4. Tap BPM segment → numeric dialog opens, enter valid BPM (100), save → segment updates to "100"
  5. Tap BPM segment → click "Clear" → segment shows "—"
  6. Tap BPM segment → enter 19, click "Save" → error shown, cannot save
  7. Tap BPM segment → enter 301, click "Save" → error shown, cannot save
  8. Tap BPM segment → click "Cancel" → no change to segment value
  9. Tap Duration segment → mm:ss dialog opens, enter 4:15, save → segment updates to "4:15"
  10. Tap Duration segment → click "Clear" → segment shows "0:00" or "—"
  11. Tap Duration segment → click "Cancel" → no change
  12. Tap Tuning segment → bottom sheet opens (existing behavior) → select new tuning → segment updates
  13. Verify long tuning names ellipsize correctly (no overflow)
  14. Tap Key segment → bottom sheet opens (not dialog) → select Eb → segment updates to "Eb"
  15. Tap Key segment → click "Cancel" at bottom → no change
  16. Verify Title and Artist fields still work as inline TextField inputs
  17. Save all changes → verify persistence (check setlist view)
  18. Open Song Edit again → verify all values persisted correctly (including BPM rendering from `_currentBpm`)
- Test on Android emulator (repeat above)
- Test legacy song with NULL band_id (if available) → verify save works (RPC bypasses RLS)

### Task 10: Commit with Descriptive Message

- Stage only the modified and new files (no unrelated changes)
- Commit message format: `feat(songs): grouped segmented ButtonGroup for song metadata tap-to-edit`
- Body:

  ```
  Replace four independent bordered containers with a single grouped
  SegmentedButtonGroup component for BPM, Duration, Tuning, Key fields.
  Add explicit DialogResult return type to distinguish cancelled/cleared/new value.
  Add _currentBpm state to mirror _currentDurationSeconds and _currentMusicalKey.

  New files:
  - segmented_button_group.dart: reusable grouped segmented UI component
  - bpm_input_dialog.dart: numeric BPM input (20-300) with DialogResult<int>
  - duration_input_dialog.dart: mm:ss duration input with DialogResult<int>
  - key_picker_bottom_sheet.dart: 24-key scrollable bottom sheet

  Modified:
  - song_details_bottom_sheet.dart: replace _buildMetricsRow() four-container
    layout with SegmentedButtonGroup, add _currentBpm state, remove _bpmController,
    _showKeyPicker() method, and key constants

  No persistence changes. All fields already exist in songs table.
  ```

## Verification Plan

### Manual Verification (iOS Simulator)

1. **Open Song Edit sheet** — Tap any song in a setlist to open `song_details_bottom_sheet`
2. **Verify grouped layout** — Confirm BPM, Duration, Tuning, Key fields render as a **single grouped segmented strip** with internal dividers, not four separate bordered containers
3. **Verify segment structure** — Each segment has label on top (secondary text, small), value below (primary text), centered
4. **Tap BPM segment** — Numeric dialog opens
5. **Enter valid BPM** — Type 125, click "Save" → segment updates to "125"
6. **Clear BPM** — Tap BPM segment, click "Clear" → segment shows "—"
7. **Test BPM validation** — Tap BPM, enter 19, click "Save" → error shown, cannot save. Enter 301, click "Save" → error shown, cannot save.
8. **Cancel BPM edit** — Tap BPM, change value, click "Cancel" → segment value unchanged
9. **Tap Duration segment** — mm:ss dialog opens
10. **Enter duration** — Type 4:15, click "Save" → segment updates to "4:15"
11. **Clear duration** — Tap Duration, click "Clear" → segment shows "0:00" or "—"
12. **Cancel duration edit** — Tap Duration, change value, click "Cancel" → segment value unchanged
13. **Tap Tuning segment** — Bottom sheet opens (existing behavior), select "Drop D" → segment updates
14. **Verify long tuning names** — Select a long tuning name (e.g., "Open D Suspended") → segment ellipsizes correctly, no overflow
15. **Tap Key segment** — Bottom sheet opens (not AlertDialog), scroll to "Eb", tap → segment updates to "Eb"
16. **Cancel key selection** — Tap Key, click "Cancel" at bottom → segment value unchanged
17. **Verify Title/Artist** — Tap "Song Title" → inline TextField appears, edit works. Tap "Artist / Band" → inline TextField appears, edit works.
18. **Save changes** — Tap "Save" button → sheet dismisses
19. **Verify persistence** — Check setlist view → song shows updated BPM, duration, key
20. **Reopen Song Edit** — Tap same song → all fields show persisted values (verify BPM renders from `_currentBpm`)
21. **Test legacy song (if available)** — Find a song with NULL band_id, edit metadata, save → verify RPC bypasses RLS successfully

### Android Emulator Verification

Repeat steps 1-21 on Android emulator to confirm cross-platform behavior.

### flutter analyze

Must pass with 0 errors before commit.

## QA Regression Areas

QA must specifically test:

1. **Grouped ButtonGroup layout**:
   - Verify single grouped segmented strip with four segments, not four separate containers
   - Verify internal dividers between segments
   - Verify each segment has label on top, value below, centered
   - Verify equal-width segments (or flexible based on content)
   - Verify no visual gaps or alignment issues
2. **BPM segment**:
   - Tap opens numeric dialog (not inline editing)
   - Valid range 20-300 enforced
   - "Clear" button sets to null (shows "—")
   - "Cancel" button makes no change
   - Out-of-range values blocked (19, 301)
   - Persistence verified (save, close, reopen) — value renders from `_currentBpm`
3. **Duration segment**:
   - Tap opens mm:ss dialog (not inline editing)
   - Masked input works (currency-style)
   - "Clear" button works
   - "Cancel" button makes no change
   - Persistence verified
4. **Tuning segment**:
   - Tap opens bottom sheet (unchanged from before)
   - Select tuning updates segment
   - Long tuning names ellipsize correctly (no overflow)
   - Persistence verified
5. **Key segment**:
   - Tap opens **bottom sheet** (not AlertDialog)
   - Scrollable list with Major/Minor sections
   - Select key updates segment
   - "Cancel" button makes no change
   - Persistence verified
6. **Title and Artist fields**:
   - Tap Title → inline TextField appears (unchanged)
   - Tap Artist → inline TextField appears (unchanged)
   - Edits persist correctly
7. **Legacy song with NULL band_id**:
   - If available, verify metadata edits persist via RPC
8. **All platforms**:
   - iOS simulator
   - Android emulator
   - Web (if applicable)
9. **Multiple edits in one session**:
   - Edit BPM, Duration, Key in one session, save all → all persist
   - Verify BPM change detection works correctly (null → value → null transitions)
10. **Read-only mode** (if invoked with `isReadOnly: true`):
    - Tap targets disabled on all segments
    - No dialogs/sheets open

## Rollout / Migration Strategy

Not applicable — UI-only change, no data migration, no feature flag required. Deploy to production via standard web deploy script after QA approval.

## Out of Scope

- Changes to song card inline editing (e.g., `reorderable_song_card.dart` tuning picker) — separate from Song Edit sheet
- Setlist-level overrides for Key field — Key is song-global only, no setlist override exists
- BPM/Duration overrides in `setlist_songs` table — existing override logic unchanged
- New tuning options or custom key definitions — use existing 24-key list and existing tuning picker
- Bulk editing of metadata across multiple songs — single-song edit only
- Undo/redo for metadata edits — not required
- Accessibility improvements beyond standard Flutter widgets — dialogs/sheets use semantic labels by default
