# Architect Plan — Share Drawer Regression

## Feature Slug

`bug/share-drawer-regression`

---

## Problem Summary

The share format picker bottom sheet does not appear when tapping the share icon on Setlist Detail screen. Users expect to see a format picker with "Text / Email" and "Spreadsheet" options, but instead the share sheet appears immediately with only plain-text format.

---

## Root Cause

**Confidence Level:** HIGH (confirmed via git history and code inspection)

The share format picker feature was implemented on the `feature/share-format-picker` branch (commit 87357d3) but was never merged to main. Git history analysis confirms:

```bash
$ git merge-base --is-ancestor 87357d3 main
NO - commit is not in main history
```

This is not a regression caused by merge conflict resolution. The feature simply never made it to production. The current `_handleShare()` method on main calls `_generateShareText()` directly and immediately opens the native share sheet, bypassing any format selection UI.

---

## Reference Docs Consulted

None applicable. Share functionality is UI-only and has no domain reference documentation.

---

## Existing System Analysis

**Current behavior on main:**

```
User taps share icon
  ↓
_handleShare() executes
  ↓
_generateShareText() generates plain-text format
  ↓
Share.share() opens native share sheet immediately
```

**Expected behavior (from feature/share-format-picker branch):**

```
User taps share icon
  ↓
_handleShare() executes
  ↓
_showShareFormatPicker() displays bottom sheet
  ↓
User selects format (Text/Email or Spreadsheet)
  ↓
_generateShareText() OR _generateSpreadsheetText() called based on selection
  ↓
Share.share() opens native share sheet with formatted text
```

**Components missing from main:**

1. `ShareFormat` enum (defines `textEmail` and `spreadsheet` options)
2. `_showShareFormatPicker()` method (displays modal bottom sheet, returns selected format)
3. `_ShareFormatSheet` widget (bottom sheet UI with two format options)
4. `_ShareFormatOption` widget (individual format option tile)
5. `_generateSpreadsheetText()` method (generates tab-delimited spreadsheet format)
6. Updated `_handleShare()` that calls format picker before sharing

**Components that exist on main but need to be replaced:**

1. `_handleShare()` — currently calls `_generateShareText()` directly; needs to call `_showShareFormatPicker()` first
2. `_formatSongSecondLine()` — currently returns `'$artist\n$metadata'` (newline version from share-text-bpm-newline feature); this is correct and should be preserved
3. `_formatTwoColumnLine()` — does NOT exist on main (was removed by share-text-bpm-newline); should NOT be restored

**Critical note on `_formatSongSecondLine()`:**

The `feature/share-format-picker` branch has the OLD version of `_formatSongSecondLine()` that delegates to `_formatTwoColumnLine()`. This was later replaced by the `feature/share-text-bpm-newline` changes that simplified it to `return '$artist\n$metadata'`. When merging the format picker, we must preserve the NEWER version from main, not revert to the old two-column layout.

---

## Proposed Solution

Add the share format picker functionality from `feature/share-format-picker` to main, with the following adaptations:

1. **Add new enum** at top of file (after imports, before class definition):
   - `ShareFormat` enum with `textEmail` and `spreadsheet` values

2. **Replace `_handleShare()` method** with version that:
   - Calls `_showShareFormatPicker()` to get user's format selection
   - Returns early if user dismisses (format is null)
   - Generates text based on format selection (text/email or spreadsheet)
   - Checks mounted before sharing
   - Shares with native share sheet

3. **Add new method `_showShareFormatPicker()`**:
   - Shows modal bottom sheet with `_ShareFormatSheet` widget
   - Returns `Future<ShareFormat?>` (null if dismissed)
   - Uses proper mounted checks

4. **Add new method `_generateSpreadsheetText()`**:
   - Generates tab-delimited format: `Title\tArtist\tBPM\tTuning`
   - Header row + data rows
   - Returns String

5. **Add new widget `_ShareFormatSheet`**:
   - Stateless widget
   - Two `_ShareFormatOption` tiles
   - Pops with selected ShareFormat on tap

6. **Add new widget `_ShareFormatOption`**:
   - Stateless widget
   - Displays small text (e.g., "Share by") and large text (e.g., "Text / Email")
   - InkWell with tap handler
   - Styled with design tokens

**DO NOT MODIFY:**

- `_formatSongSecondLine()` — keep the current newline version from main
- `_generateShareText()` — works correctly, no changes needed
- `_formatHeaderSubline()` — works correctly, no changes needed
- `_formatTotalDuration()` — works correctly, no changes needed

**DO NOT ADD:**

- `_formatTwoColumnLine()` — this was intentionally removed by share-text-bpm-newline, do not restore it

---

## Database Impact

**Not applicable** — UI-only change. No migrations, RLS policies, RPC functions, or triggers affected.

---

## Flutter Architecture Changes

**State:**

- No state changes
- No new Riverpod providers
- No controller modifications

**Widgets:**

- Two new private widgets added to `SetlistDetailScreen`: `_ShareFormatSheet`, `_ShareFormatOption`
- These are leaf widgets scoped to this screen only

**Repositories:**

- No repository changes

---

## Files to Create

**None** — all changes are within existing file.

---

## Files to Modify

| File                                               | Changes                                                                                                                                                                             |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart` | Add `ShareFormat` enum, replace `_handleShare()`, add `_showShareFormatPicker()`, add `_generateSpreadsheetText()`, add `_ShareFormatSheet` widget, add `_ShareFormatOption` widget |

---

## Files Off-Limits

| File                                                   | Reason                               |
| ------------------------------------------------------ | ------------------------------------ |
| `lib/main.dart`                                        | Init order must not change           |
| `lib/features/setlists/setlist_repository.dart`        | No repository changes required       |
| `lib/features/setlists/setlist_detail_controller.dart` | No state management changes required |
| All other files                                        | Not part of approved scope           |

---

## System Impact Map

| System                                 | Impact                                             |
| -------------------------------------- | -------------------------------------------------- |
| Gigs                                   | unaffected                                         |
| Rehearsals                             | unaffected                                         |
| Setlists / Catalog                     | affected (share functionality enhanced)            |
| Members / RBAC                         | unaffected (no permission changes)                 |
| Auth / Session                         | unaffected                                         |
| Routing                                | unaffected                                         |
| Notifications                          | unaffected                                         |
| Platform (iOS / Android / Web / macOS) | affected (share behavior changes on all platforms) |

---

## Regression Risk

**LOW**

**Rationale:**

- Change is localized to one file, one screen
- Only modifies share flow (user-initiated action, not automatic)
- No state management changes
- No database changes
- No auth or permission changes
- Worst-case failure: share button doesn't work (user can retry or reload)
- No crash vectors (all async code has proper mounted checks)
- The `_generateShareText()` method remains unchanged, so existing text format is preserved
- Adding spreadsheet format is purely additive (new capability, not replacing existing)

**Mitigation:**

- Existing `_generateShareText()` is preserved and unmodified
- Format picker includes the same "Text / Email" option as default behavior
- User can dismiss format picker to cancel (no forced selection)

---

## Engineer Task Breakdown

Execute in order:

### Task 1: Add ShareFormat enum

Add the `ShareFormat` enum at the top of the file, after imports and before the `SetlistDetailScreen` class definition.

```dart
/// Share output format options
enum ShareFormat {
  textEmail, // Rich plain-text format (existing)
  spreadsheet, // Tab-delimited format
}
```

### Task 2: Replace `_handleShare()` method

Locate the existing `_handleShare()` method (around line 1225) and replace it entirely with the version from `feature/share-format-picker` branch that:

- Calls `_showShareFormatPicker()` to display format picker
- Returns early if user dismisses (format is null)
- Generates text conditionally based on format selection
- Checks mounted before sharing
- Preserves the existing Share.share() call with sharePositionOrigin

**Critical:** Do not modify the error handling, mounted checks, or share position logic. Only change the text generation logic to be conditional on format selection.

### Task 3: Add `_showShareFormatPicker()` method

Add new method after `_handleShare()`:

```dart
/// Show format picker bottom sheet and return selected format.
/// Returns null if user dismisses without selecting.
Future<ShareFormat?> _showShareFormatPicker() async {
  if (!mounted) return null;

  final result = await showModalBottomSheet<ShareFormat>(
    context: context,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isDismissible: true,
    enableDrag: true,
    builder: (context) => const _ShareFormatSheet(),
  );

  if (!mounted) return null;
  return result;
}
```

### Task 4: Add `_generateSpreadsheetText()` method

Add new method after `_generateShareText()`:

```dart
/// Generate tab-delimited spreadsheet text for the setlist.
/// Format: Title\tArtist\tBPM\tTuning
String _generateSpreadsheetText({
  required List<SetlistSong> songs,
}) {
  final buffer = StringBuffer();

  // Header row
  buffer.writeln('Title\tArtist\tBPM\tTuning');

  // Data rows
  for (final song in songs) {
    final title = song.title;
    final artist = song.artist;
    final bpm =
        (song.bpm != null && song.bpm! > 0) ? song.bpm.toString() : '';
    final tuning = tuningShortLabel(song.tuning);

    buffer.writeln('$title\t$artist\t$bpm\t$tuning');
  }

  return buffer.toString();
}
```

### Task 5: Add `_ShareFormatSheet` widget

Add new widget class at the end of the file, before the final closing brace of the file (after any existing bottom sheet widgets like print options):

```dart
/// Bottom sheet for selecting share output format
class _ShareFormatSheet extends StatelessWidget {
  const _ShareFormatSheet();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        padding: EdgeInsets.only(
          left: Spacing.pagePadding,
          right: Spacing.pagePadding,
          top: Spacing.space24,
          bottom: MediaQuery.of(context).viewPadding.bottom + Spacing.space24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Text('Share Format', style: AppTextStyles.headline),
            const SizedBox(height: Spacing.space16),

            // Text / Email option
            _ShareFormatOption(
              smallText: 'Share by',
              largeText: 'Text / Email',
              onTap: () => Navigator.of(context).pop(ShareFormat.textEmail),
            ),

            const SizedBox(height: Spacing.space12),

            // Spreadsheet option
            _ShareFormatOption(
              smallText: '4-column',
              largeText: 'Spreadsheet',
              onTap: () => Navigator.of(context).pop(ShareFormat.spreadsheet),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Task 6: Add `_ShareFormatOption` widget

Add new widget class immediately after `_ShareFormatSheet`:

```dart
/// Individual share format option tile
class _ShareFormatOption extends StatelessWidget {
  final String smallText;
  final String largeText;
  final VoidCallback onTap;

  const _ShareFormatOption({
    required this.smallText,
    required this.largeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
      child: Container(
        padding: const EdgeInsets.all(Spacing.space16),
        decoration: BoxDecoration(
          color: context.colors.surfaceElevated,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              smallText,
              style: AppTextStyles.body.copyWith(
                color: context.colors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: Spacing.space4),
            Text(
              largeText,
              style: AppTextStyles.title3.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Task 7: Run Flutter Analyze

```bash
flutter analyze
```

Must pass with 0 errors, 0 warnings.

### Task 8: Manual Testing

Test on iOS and Web (minimum required platforms):

**Test 1: Text/Email format**

1. Open any setlist
2. Tap share icon
3. Verify format picker bottom sheet appears
4. Tap "Text / Email" option
5. Verify native share sheet appears with plain-text format
6. Verify text format matches existing format (artist and metadata on separate lines)

**Test 2: Spreadsheet format**

1. Open any setlist
2. Tap share icon
3. Verify format picker bottom sheet appears
4. Tap "Spreadsheet" option
5. Verify native share sheet appears with tab-delimited format
6. Paste into spreadsheet app (Numbers, Excel, Google Sheets)
7. Verify four columns: Title, Artist, BPM, Tuning

**Test 3: Dismiss format picker**

1. Open any setlist
2. Tap share icon
3. Verify format picker appears
4. Tap outside sheet or swipe down to dismiss
5. Verify sheet closes and no share sheet appears (cancelled)

**Test 4: Empty setlist**

1. Create new empty setlist
2. Tap share icon
3. Verify format picker appears
4. Select either format
5. Verify share sheet appears with header only (no songs)

**Test 5: Catalog share**

1. Open Catalog
2. Tap share icon
3. Verify format picker appears
4. Test both formats
5. Verify correct content for Catalog songs

---

## QA Regression Areas

QA must explicitly test:

1. **Share format picker appears** — primary requirement
2. **Text/Email format produces correct output** — must match existing plain-text format (artist and metadata on separate lines with newline)
3. **Spreadsheet format produces valid tab-delimited data** — must paste cleanly into spreadsheet apps
4. **Format picker dismissal works** — user can cancel by tapping outside or swiping down
5. **All platforms** — iOS, Web, Android (optional: macOS)
6. **Empty setlists** — no crash, header-only output
7. **Catalog** — works identically to regular setlists
8. **Mounted checks prevent crashes** — no setState-after-dispose errors

---

## Rollout / Migration Strategy

**Not applicable** — no database migrations, no backend changes, no data migration required.

**Deployment:**

1. Merge to main after QA approval
2. Deploy web via `./tools/deploy_web.sh`
3. No native app release required immediately (can be included in next app store release)

---

## Out of Scope

Explicitly NOT part of this work:

- Additional share formats (PDF, image, etc.)
- Share button repositioning or styling changes
- Share analytics or tracking
- Share permissions or RBAC changes
- Modifying `_formatSongSecondLine()` or `_generateShareText()` (these work correctly as-is)
- Restoring `_formatTwoColumnLine()` (this was intentionally removed and should stay removed)
- Testing on platforms other than iOS and Web (Android and macOS testing is optional)

---

## Additional Context

**Git history analysis:**

```bash
$ git log --oneline --all --grep="share" -20
02d74f6 feat(setlists): change plain-text share format to always newline BPM/tuning
849fdee feat(setlists): change plain-text share format to always newline BPM/tuning
87357d3 feat(setlists): add share format picker with spreadsheet export
```

The share format picker commit (87357d3) exists on `feature/share-format-picker` branch but is not in main's ancestry. The two later commits (02d74f6, 849fdee) that modified `_formatSongSecondLine()` to use newline format ARE on main and must be preserved.

**Key merge consideration:**

When implementing this plan, do NOT copy `_formatSongSecondLine()` or `_formatTwoColumnLine()` from the feature branch. These were superseded by the share-text-bpm-newline feature. Only copy the format picker components (`ShareFormat`, `_showShareFormatPicker()`, `_ShareFormatSheet`, `_ShareFormatOption`, `_generateSpreadsheetText()`, and updated `_handleShare()`).
