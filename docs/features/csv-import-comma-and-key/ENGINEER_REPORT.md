# Engineer Report

## Feature Slug
`bug/csv-import-comma-and-key`

## Feature Title
CSV Import Comma Corruption + Musical Key Column

## Goal
Fix quoted CSV fields with an internal comma corrupting the imported song title during bulk/CSV import, and add a bulk-importable "Key" column (Artist, Song, BPM, Tuning, Key) that threads a song's musical key through parsing, the bulk-entry UI, and the repository into `songs.musical_key`.

## Architect Tasks Completed
- [x] Task 1 — Fixed comma corruption (`bulk_song_parser.dart`): added `_splitCsvLine()` quote-aware splitter; comma-delimited branch of `_parseColumns` now calls it instead of `line.split(',')`. Tab-delimited and 2+-space branches untouched.
- [x] Task 2 — Added Key to the data model (`bulk_song_row.dart`): `unknownKey` added to `BulkSongValidationError`; `musicalKey` field added and threaded through the constructor and both `.valid()`/`.invalid()` factories; `formattedKey` getter added. `dedupeKey`/`==`/`hashCode` left unchanged per plan.
- [x] Task 3 — Parse and validate Key (`bulk_song_parser.dart`): optional 5th-column (`rawKey`) extraction; `_normalizeKey()` added mirroring `_normalizeTuning`'s structure against a locally duplicated 24-key canonical set; warning-priority chain extended to `bpmWarning ?? tuningWarning ?? keyWarning`; no enharmonic aliasing.
- [x] Task 4 — Added Key column to the UI (`bulk_entry_screen.dart`): `_RowData` gained `key`/`keyFocus` (disposed, included in `isEmpty`); `_kFlexKey` added with flex values rebalanced (Artist 3 / Song 3 / BPM 2 / Tuning 2 / Key 2); header, row cell, seeding, re-serialization, and hint text all updated.
- [x] Task 5 — Threaded Key through the repository (`setlist_repository.dart`): `bulkAddSongs` passes `musicalKey: row.musicalKey`; `_createOrFindSong` gained a `musicalKey` parameter, added `musical_key` to the existing-song `SELECT`, added enrich-if-null update logic, and added conditional insert for new songs. No RPC, no enum mapping.
- [x] Task 6 (recommended) — Added `test/features/setlists/services/bulk_song_parser_test.dart` with 12 tests covering: quoted-comma title repro, plain comma-delimited (no regression), tab-delimited (no regression), apostrophe un-escaping (no regression), internal-comma title + trailing Key column combination, valid key normalization (major, minor-suffix variants, "major" suffix), unknown key (non-fatal warning), enharmonic non-aliasing ("Db" not treated as "C#"), and missing Key column.
- [x] Task 7 — `flutter analyze`: 0 errors, 0 warnings.

## Files Created
- `test/features/setlists/services/bulk_song_parser_test.dart` (recommended test file per Task 6)

## Files Modified
- `lib/features/setlists/services/bulk_song_parser.dart`
- `lib/features/setlists/models/bulk_song_row.dart`
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
- `lib/features/setlists/setlist_repository.dart`

No files outside this list were touched. No file from the plan's "Files Off-Limits" table was modified.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings (clean run, "No issues found!")

## Test Results
Passed — full suite (`flutter test`): 29/29 passed, including the 12 new tests in `bulk_song_parser_test.dart`. No pre-existing tests regressed.

## Verification
Manual steps performed (automated via the new unit test file, standing in for the plan's Tier 1 pre-deploy tests since this is a headless session with no device/simulator attached):
- PRE-DEPLOY TEST 1 equivalent: `parser.parse('"John Denver","Take Me Home, Country Road"')` → single row, Artist=`John Denver`, Song=`Take Me Home, Country Road`. Confirmed passing.
- PRE-DEPLOY TEST 2 equivalent: plain comma-delimited row (`Aerosmith, Eat The Rich, 123, Standard`) parses identically to pre-fix behavior. Confirmed passing.
- PRE-DEPLOY TEST 3 equivalent: quoted doubled-apostrophe field un-escapes correctly (regression check against the prior apostrophe-corruption fix). Confirmed passing.
- PRE-DEPLOY TEST 4 equivalent: `Van Halen, Poundcake, 118, Standard, Eb` → `musicalKey == 'Eb'`, no warning. Confirmed passing.
- PRE-DEPLOY TEST 5 equivalent: unrecognized key (`Zzz`) → row valid, `musicalKey == null`, warning = `unknownKey`, message = `'Unknown key ignored'`. Confirmed passing.
- Additional coverage beyond the plan's minimum: tab-delimited no-regression check, minor-suffix variant normalization (`Bm`/`B minor`/`bm`/`B min`), `major`-suffix normalization, and an explicit no-enharmonic-aliasing check (`Db` ≠ `C#`, stays unknown).
- PRE-DEPLOY TEST 6 (SQL schema check) and all Tier 2 post-deployment tests (require a running app + Supabase project) were **not** run in this headless session — flagged as a gap for QA to execute per the plan's Verification Plan.

## Deviations From Architect Plan
None. All five flex constants were rebalanced as suggested by the plan's example (Artist 3 / Song 3 / BPM 2 / Tuning 2 / Key 2) — this was explicitly left as the Engineer's cosmetic judgment call in the plan's Files-to-Modify table.

## Blockers Encountered
None.

## Ready For QA
Yes. Note for QA: Tier 2 post-deployment tests (end-to-end add-to-setlist/Catalog persistence checks, the single-song key-picker write-path conflict check, and the re-import "never overwrite non-null key" check) require a running app and Supabase project and were not executable in this headless engineering session — these remain outstanding per the plan's Verification Plan and should be run by QA as documented there.

---

## Full Git Diff

```diff
diff --git a/lib/features/setlists/models/bulk_song_row.dart b/lib/features/setlists/models/bulk_song_row.dart
index 2620b4c..caef41a 100644
--- a/lib/features/setlists/models/bulk_song_row.dart
+++ b/lib/features/setlists/models/bulk_song_row.dart
@@ -5,7 +5,12 @@
 // ============================================================================
 
 /// Validation error types for bulk paste rows
-enum BulkSongValidationError { missingTitle, invalidBpm, unknownTuning }
+enum BulkSongValidationError {
+  missingTitle,
+  invalidBpm,
+  unknownTuning,
+  unknownKey,
+}
 
 /// Represents a single parsed row from the bulk paste input.
 ///
@@ -28,6 +33,10 @@ class BulkSongRow {
   /// Display-friendly tuning label (for preview)
   final String? tuningLabel;
 
+  /// Normalized musical key (Column 5) - null if not provided
+  /// Matches the canonical key set in key_picker_bottom_sheet.dart
+  final String? musicalKey;
+
   /// Validation error if the row is invalid (missing required fields)
   final BulkSongValidationError? error;
 
@@ -46,6 +55,7 @@ class BulkSongRow {
     this.bpm,
     this.tuning,
     this.tuningLabel,
+    this.musicalKey,
     this.error,
     this.errorMessage,
     this.warning,
@@ -64,6 +74,7 @@ class BulkSongRow {
     required String title,
     int? bpm,
     String? tuning,
+    String? musicalKey,
     required BulkSongValidationError error,
     required String errorMessage,
   }) {
@@ -72,6 +83,7 @@ class BulkSongRow {
       title: title,
       bpm: bpm,
       tuning: tuning,
+      musicalKey: musicalKey,
       error: error,
       errorMessage: errorMessage,
     );
@@ -84,6 +96,7 @@ class BulkSongRow {
     int? bpm,
     String? tuning,
     String? tuningLabel,
+    String? musicalKey,
     BulkSongValidationError? warning,
     String? warningMessage,
   }) {
@@ -93,6 +106,7 @@ class BulkSongRow {
       bpm: bpm,
       tuning: tuning,
       tuningLabel: tuningLabel,
+      musicalKey: musicalKey,
       warning: warning,
       warningMessage: warningMessage,
     );
@@ -104,6 +118,9 @@ class BulkSongRow {
   /// Formatted tuning for display
   String get formattedTuning => tuningLabel ?? tuning ?? 'Standard';
 
+  /// Formatted musical key for display
+  String get formattedKey => musicalKey ?? '-';
+
   /// Unique key for de-duplication: lowercase artist + title
   String get dedupeKey =>
       '${artist.toLowerCase().trim()}|${title.toLowerCase().trim()}';
diff --git a/lib/features/setlists/services/bulk_song_parser.dart b/lib/features/setlists/services/bulk_song_parser.dart
index e804ae3..944b7c4 100644
--- a/lib/features/setlists/services/bulk_song_parser.dart
+++ b/lib/features/setlists/services/bulk_song_parser.dart
@@ -8,6 +8,7 @@
 // - 2+ space fallback for legacy formats
 // - BPM validation (1-300 or empty)
 // - Tuning normalization to match app's tuning IDs
+// - Musical key normalization to match the app's canonical key set
 // - De-duplication within pasted batch
 // - Validation error reporting per row
 // ============================================================================
@@ -54,10 +55,10 @@ class BulkSongParser {
   /// Parse raw input text into BulkSongRow objects.
   ///
   /// Supports two input formats:
-  /// 1. Spreadsheet paste: ARTIST\tSONG\tBPM\tTUNING (tab-delimited or 2+ spaces)
-  /// 2. Manual entry: ARTIST, SONG, BPM, TUNING (comma-delimited)
+  /// 1. Spreadsheet paste: ARTIST\tSONG\tBPM\tTUNING\tKEY (tab-delimited or 2+ spaces)
+  /// 2. Manual entry: ARTIST, SONG, BPM, TUNING, KEY (comma-delimited)
   ///
-  /// - BPM and TUNING are optional
+  /// - BPM, TUNING, and KEY are optional
   /// - Blank lines are ignored
   /// - [maxRows] limits the number of rows processed (default: no limit)
   BulkSongParseResult parse(String input, {int? maxRows}) {
@@ -104,6 +105,7 @@ class BulkSongParser {
       final title = columns[1].trim();
       final rawBpm = columns.length > 2 ? columns[2].trim() : '';
       final rawTuning = columns.length > 3 ? columns[3].trim() : '';
+      final rawKey = columns.length > 4 ? columns[4].trim() : '';
 
       // Validate title is not empty
       if (title.isEmpty) {
@@ -150,9 +152,26 @@ class BulkSongParser {
         }
       }
 
-      // Determine overall warning (prioritize BPM warning over tuning)
-      final warning = bpmWarning ?? tuningWarning;
-      final warningMessage = bpmWarningMessage ?? tuningWarningMessage;
+      // Normalize and validate musical key
+      String? musicalKey;
+      BulkSongValidationError? keyWarning;
+      String? keyWarningMessage;
+      if (rawKey.isNotEmpty) {
+        final normalizedKey = _normalizeKey(rawKey);
+        if (normalizedKey == null) {
+          // Unknown key is a warning, not an error - row is still valid
+          keyWarning = BulkSongValidationError.unknownKey;
+          keyWarningMessage = 'Unknown key ignored';
+          // Leave musicalKey as null
+        } else {
+          musicalKey = normalizedKey;
+        }
+      }
+
+      // Determine overall warning (prioritize BPM warning, then tuning, then key)
+      final warning = bpmWarning ?? tuningWarning ?? keyWarning;
+      final warningMessage =
+          bpmWarningMessage ?? tuningWarningMessage ?? keyWarningMessage;
 
       // Create valid row (with possible warning)
       final row = BulkSongRow.valid(
@@ -161,6 +180,7 @@ class BulkSongParser {
         bpm: bpm,
         tuning: tuningId,
         tuningLabel: tuningLabel,
+        musicalKey: musicalKey,
         warning: warning,
         warningMessage: warningMessage,
       );
@@ -201,13 +221,52 @@ class BulkSongParser {
 
     // Try comma-delimited (manual entry)
     if (line.contains(',')) {
-      return line.split(',').map(_unescapeField).toList();
+      return _splitCsvLine(line).map(_unescapeField).toList();
     }
 
     // Fall back to 2+ spaces (legacy support)
     return line.split(RegExp(r'\s{2,}')).map(_unescapeField).toList();
   }
 
+  /// Split a comma-delimited line into fields, honoring RFC 4180 quoting:
+  /// a comma inside a double-quoted field is NOT a delimiter.
+  ///
+  /// Quotes are preserved in the returned fields (not stripped) — stripping
+  /// and un-escaping remains the job of `_unescapeField`, which already runs
+  /// on every returned field.
+  List<String> _splitCsvLine(String line) {
+    final fields = <String>[];
+    final buffer = StringBuffer();
+    var insideQuotes = false;
+
+    for (var i = 0; i < line.length; i++) {
+      final char = line[i];
+
+      if (char == '"') {
+        if (insideQuotes && i + 1 < line.length && line[i + 1] == '"') {
+          // Escaped quote ("") inside a quoted field — keep both chars,
+          // _unescapeField collapses them later.
+          buffer.write('""');
+          i++;
+          continue;
+        }
+        insideQuotes = !insideQuotes;
+        buffer.write(char);
+        continue;
+      }
+
+      if (char == ',' && !insideQuotes) {
+        fields.add(buffer.toString());
+        buffer.clear();
+        continue;
+      }
+
+      buffer.write(char);
+    }
+    fields.add(buffer.toString());
+    return fields;
+  }
+
   /// Un-escape a TSV/CSV field that may be wrapped in double quotes.
   ///
   /// Handles RFC 4180 quote wrapping and un-escaping:
@@ -332,6 +391,71 @@ class BulkSongParser {
     }
     return result;
   }
+
+  /// Normalize musical key input to match the canonical key set used by
+  /// key_picker_bottom_sheet.dart (`_kMajorKeys` / `_kMinorKeys`, duplicated
+  /// locally here since the parser is a service and should not import a
+  /// widget file).
+  ///
+  /// Exact match after normalization only — no enharmonic aliasing (e.g.
+  /// "Db" is NOT normalized to "C#"). Returns null if unrecognized.
+  static const _kCanonicalKeys = {
+    // Major
+    'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
+    // Minor
+    'Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'Abm', 'Am', 'Bbm',
+    'Bm',
+  };
+
+  static final _minorKeyPattern = RegExp(
+    r'^([A-Ga-g])([#b]?)\s*(?:m|min|minor)$',
+    caseSensitive: false,
+  );
+
+  static final _majorKeyPattern = RegExp(
+    r'^([A-Ga-g])([#b]?)(?:\s*(?:major|maj))?$',
+    caseSensitive: false,
+  );
+
+  String? _normalizeKey(String input) {
+    final trimmed = input.trim();
+    if (trimmed.isEmpty) return null;
+
+    String root;
+    String accidental;
+    bool isMinor;
+
+    final minorMatch = _minorKeyPattern.firstMatch(trimmed);
+    if (minorMatch != null) {
+      root = minorMatch.group(1)!;
+      accidental = minorMatch.group(2) ?? '';
+      isMinor = true;
+    } else {
+      final majorMatch = _majorKeyPattern.firstMatch(trimmed);
+      if (majorMatch == null) {
+        if (kDebugMode) {
+          debugPrint('[BulkSongParser] Unknown key: "$input"');
+        }
+        return null;
+      }
+      root = majorMatch.group(1)!;
+      accidental = majorMatch.group(2) ?? '';
+      isMinor = false;
+    }
+
+    final candidate =
+        '${root.toUpperCase()}${accidental.toLowerCase()}${isMinor ? 'm' : ''}';
+
+    if (_kCanonicalKeys.contains(candidate)) {
+      return candidate;
+    }
+    if (kDebugMode) {
+      debugPrint(
+        '[BulkSongParser] Unknown key: "$input" -> normalized="$candidate"',
+      );
+    }
+    return null;
+  }
 }
 
 /// Internal class for normalized tuning data
diff --git a/lib/features/setlists/setlist_repository.dart b/lib/features/setlists/setlist_repository.dart
index 2479f77..94cec42 100644
--- a/lib/features/setlists/setlist_repository.dart
+++ b/lib/features/setlists/setlist_repository.dart
@@ -3923,6 +3923,7 @@ class SetlistRepository {
               artist: row.artist,
               bpm: row.bpm,
               tuning: row.tuning,
+              musicalKey: row.musicalKey,
             );
 
             if (songId == null) {
@@ -4043,6 +4044,7 @@ class SetlistRepository {
     required String artist,
     int? bpm,
     String? tuning,
+    String? musicalKey,
     int? durationSeconds,
     String? albumArtwork,
   }) async {
@@ -4057,7 +4059,8 @@ class SetlistRepository {
       // First, try to find existing song
       final existing = await supabase
           .from('songs')
-          .select('id, bpm, tuning, duration_seconds, album_artwork')
+          .select(
+              'id, bpm, tuning, duration_seconds, album_artwork, musical_key')
           .eq('band_id', bandId)
           .ilike('title', normalizedTitle)
           .ilike('artist', normalizedArtist)
@@ -4092,6 +4095,9 @@ class SetlistRepository {
         if (albumArtwork != null && existing[0]['album_artwork'] == null) {
           updates['album_artwork'] = albumArtwork;
         }
+        if (musicalKey != null && existing[0]['musical_key'] == null) {
+          updates['musical_key'] = musicalKey;
+        }
 
         if (updates.isNotEmpty) {
           await supabase.from('songs').update(updates).eq('id', existingId);
@@ -4124,6 +4130,10 @@ class SetlistRepository {
         insertData['album_artwork'] = albumArtwork;
       }
 
+      if (musicalKey != null && musicalKey.isNotEmpty) {
+        insertData['musical_key'] = musicalKey;
+      }
+
       // Convert app tuning ID to database enum value
       // The database uses enum: 'standard', 'drop_d', 'half_step', 'full_step'
       final dbTuning = tuningToDbEnum(tuning);
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index d688697..d5bb81c 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -11,7 +11,7 @@ import 'package:bandroadie/app/theme/app_icons.dart';
 // BULK ENTRY SCREEN
 // Screen 3 of the Add to Setlist flow — paste or type many songs at once.
 //
-// Structured editable table with columns: Artist | Song | BPM | Tuning
+// Structured editable table with columns: Artist | Song | BPM | Tuning | Key
 //
 // Supports:
 //   - Manual cell editing
@@ -46,37 +46,44 @@ class _RowData {
   final TextEditingController song;
   final TextEditingController bpm;
   final TextEditingController tuning;
+  final TextEditingController key;
   final FocusNode artistFocus;
   final FocusNode songFocus;
   final FocusNode bpmFocus;
   final FocusNode tuningFocus;
+  final FocusNode keyFocus;
 
   _RowData()
       : artist = TextEditingController(),
         song = TextEditingController(),
         bpm = TextEditingController(),
         tuning = TextEditingController(),
+        key = TextEditingController(),
         artistFocus = FocusNode(),
         songFocus = FocusNode(),
         bpmFocus = FocusNode(),
-        tuningFocus = FocusNode();
+        tuningFocus = FocusNode(),
+        keyFocus = FocusNode();
 
   void dispose() {
     artist.dispose();
     song.dispose();
     bpm.dispose();
     tuning.dispose();
+    key.dispose();
     artistFocus.dispose();
     songFocus.dispose();
     bpmFocus.dispose();
     tuningFocus.dispose();
+    keyFocus.dispose();
   }
 
   bool get isEmpty =>
       artist.text.trim().isEmpty &&
       song.text.trim().isEmpty &&
       bpm.text.trim().isEmpty &&
-      tuning.text.trim().isEmpty;
+      tuning.text.trim().isEmpty &&
+      key.text.trim().isEmpty;
 
   bool get hasRequiredFields =>
       artist.text.trim().isNotEmpty && song.text.trim().isNotEmpty;
@@ -89,10 +96,11 @@ class _RowData {
 const int _kInitialRows = 5;
 const int _kMaxRows = 500;
 
-const int _kFlexArtist = 4;
-const int _kFlexSong = 4;
+const int _kFlexArtist = 3;
+const int _kFlexSong = 3;
 const int _kFlexBpm = 2;
-const int _kFlexTuning = 3;
+const int _kFlexTuning = 2;
+const int _kFlexKey = 2;
 const double _kDeleteWidth = 36;
 const double _kCellHeight = 42;
 
@@ -164,6 +172,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
     row.songFocus.addListener(trackFocus);
     row.bpmFocus.addListener(trackFocus);
     row.tuningFocus.addListener(trackFocus);
+    row.keyFocus.addListener(trackFocus);
     return row;
   }
 
@@ -274,6 +283,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
       row.song.text = parsed.title;
       row.bpm.text = parsed.bpm?.toString() ?? '';
       row.tuning.text = parsed.tuningLabel ?? parsed.tuning ?? '';
+      row.key.text = parsed.musicalKey ?? '';
       _rows.add(row);
     }
 
@@ -302,7 +312,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
           '${r.artist.text.trim()}\t'
           '${r.song.text.trim()}\t'
           '${r.bpm.text.trim()}\t'
-          '${r.tuning.text.trim()}',
+          '${r.tuning.text.trim()}\t'
+          '${r.key.text.trim()}',
         );
       }
 
@@ -373,8 +384,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                 ),
                 decoration: InputDecoration(
                   hintText: 'Paste CSV or tab-delimited data here…\n'
-                      'Artist, Song, BPM, Tuning\n'
-                      'e.g.: Aerosmith, Eat The Rich, 123, Standard',
+                      'Artist, Song, BPM, Tuning, Key\n'
+                      'e.g.: Aerosmith, Eat The Rich, 123, Standard, G',
                   hintStyle: TextStyle(
                     fontSize: AppFontSizes.caption,
                     color: context.colors.textMuted.withValues(alpha: 0.5),
@@ -492,6 +503,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
           _headerCell('Song', _kFlexSong),
           _headerCell('BPM', _kFlexBpm),
           _headerCell('Tuning', _kFlexTuning),
+          _headerCell('Key', _kFlexKey),
           const SizedBox(width: _kDeleteWidth),
         ],
       ),
@@ -568,6 +580,13 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
             rowIndex: index,
             textCapitalization: TextCapitalization.words,
           ),
+          _tableCell(
+            controller: row.key,
+            focusNode: row.keyFocus,
+            flex: _kFlexKey,
+            hint: '-',
+            rowIndex: index,
+          ),
           SizedBox(
             width: _kDeleteWidth,
             height: _kCellHeight,
```

(New test file `test/features/setlists/services/bulk_song_parser_test.dart` is untracked — full contents shown above under Files Created / in the working tree.)
