# Architect Plan — Bulk Entry Apostrophe Corruption Fix

## Feature Slug

`bug/bulk-entry-apostrophe-corruption`

## Problem Summary

When pasting song data from Google Sheets into the Bulk Entry overlay, song titles containing a Unicode LEFT SINGLE QUOTATION MARK (U+2018, `'`) are corrupted. The curly apostrophe is replaced with three consecutive straight apostrophes (`'''`), making titles appear broken.

**Example:**

- **Input (Google Sheets cell):** `Ain't Talkin' 'Bout Love` (Van Halen)
  - First two apostrophes are straight (U+0027)
  - Third apostrophe is curly (U+2018)
- **Output (in BandRoadie):** `Ain't Talkin' '''Bout Love`
  - Three consecutive straight apostrophes between "Talkin'" and "Bout"

## Root Cause

**Confidence: HIGH**

Google Sheets' TSV export normalizes Unicode smart quotes (U+2018) to straight apostrophes (U+0027) and then escapes them by doubling, producing sequences like `''` in the clipboard data. This is similar to SQL string literal escaping where apostrophes are doubled to escape them.

The `BulkSongParser._parseColumns` method:

1. Splits raw input on delimiters (tabs, commas, or spaces)
2. Trims whitespace from each column
3. **Does NOT un-escape doubled apostrophes or handle RFC 4180 quote wrapping**

Result: Escaped text like `Talkin' ''Bout` is parsed as-is, stored in the database, and displayed with three consecutive apostrophes.

## Reference Docs Consulted

None found. No reference documentation exists for bulk entry, parsing, or setlist management in `docs/reference/`.

## Existing System Analysis

### Current Data Flow

1. **User action:** Copy cells from Google Sheets
2. **Clipboard (TSV):** `Van Halen	Ain't Talkin' ''Bout Love	120	Standard`
   - U+2018 has been normalized to U+0027 and doubled by Google Sheets
3. **BulkSongParser.parse():**
   - Splits lines on newline
   - Calls `_parseColumns()` for each line
   - `_parseColumns()` splits on tabs: `["Van Halen", "Ain't Talkin' ''Bout Love", "120", "Standard"]`
   - Trims each column (no un-escaping)
4. **BulkSongRow created:** `title = "Ain't Talkin' ''Bout Love"` (escaped apostrophe remains)
5. **SetlistRepository.bulkAddSongs():** Stores title as-is in database
6. **UI Display:** Shows `Ain't Talkin' '''Bout Love` (three consecutive apostrophes)

### Current Parsing Logic

Located in `lib/features/setlists/services/bulk_song_parser.dart`:

```dart
List<String> _parseColumns(String line) {
  // Try TAB-delimited first (spreadsheet paste)
  if (line.contains('\t')) {
    return line.split('\t').map((c) => c.trim()).toList();
  }

  // Try comma-delimited (manual entry)
  if (line.contains(',')) {
    return line.split(',').map((c) => c.trim()).toList();
  }

  // Fall back to 2+ spaces (legacy support)
  return line.split(RegExp(r'\s{2,}')).map((c) => c.trim()).toList();
}
```

**Problem:** The `.trim()` operation only removes leading/trailing whitespace. It does not:

- Strip outer double quotes from RFC 4180-wrapped fields
- Un-escape doubled quotes: `""` → `"`
- Un-escape doubled apostrophes: `''` → `'` (Google Sheets behavior)

## Proposed Solution

Add RFC 4180-compliant field un-escaping to the `_parseColumns` method:

1. **Create a new helper method:** `String _unescapeField(String field)`
   - Check if field is wrapped in double quotes (`"..."`)
   - If wrapped, strip outer quotes
   - Un-escape any doubled characters:
     - `""` → `"` (standard RFC 4180)
     - `''` → `'` (Google Sheets apostrophe escaping)
   - Handle edge cases (unbalanced quotes, empty fields)

2. **Update `_parseColumns`:** Apply `_unescapeField` to each column after splitting and trimming

**Why this approach:**

- Minimal change — single file, single method addition
- Preserves existing delimiter detection logic (tab/comma/space)
- Backward compatible — unquoted fields pass through unchanged
- Follows RFC 4180 standard for CSV/TSV parsing

## Database Impact

**Not applicable.**  
No migrations, RLS policies, RPC functions, or triggers affected. This is pure client-side parsing logic.

## Flutter Architecture Changes

### State Management

No changes. Parsing logic is stateless service layer.

### Widgets

No changes to `bulk_add_songs_overlay.dart`. The overlay already delegates parsing to the service.

### Repositories

No changes to `setlist_repository.dart`. The repository accepts parsed `BulkSongRow` objects and is unaware of escaping.

### Services

**Modified:** `BulkSongParser` in `lib/features/setlists/services/bulk_song_parser.dart`

- Add `_unescapeField` helper method
- Call `_unescapeField` in `_parseColumns` after splitting

## Files to Create

**None.**

## Files to Modify

| File                                                   | Changes                                                                                                                                                                                            |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/services/bulk_song_parser.dart` | Add `_unescapeField(String field)` method to strip RFC 4180 outer quotes and un-escape doubled quotes/apostrophes. Update `_parseColumns` to call `_unescapeField` on each column after splitting. |

## Files Off-Limits

| File                                                        | Reason                                                                            |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/bulk_add_songs_overlay.dart` | Parsing logic belongs in service layer, not UI. Overlay is not the failure point. |
| `lib/features/setlists/setlist_repository.dart`             | No database changes needed. Repository correctly uses parsed data.                |
| `lib/features/setlists/setlist_detail_screen.dart`          | Active feature branch constraint (share-format-picker in flight).                 |
| `lib/main.dart`                                             | No initialization changes required.                                               |

## System Impact Map

| System                                 | Impact                                     |
| -------------------------------------- | ------------------------------------------ |
| Gigs                                   | unaffected                                 |
| Rehearsals                             | unaffected                                 |
| Setlists / Catalog                     | **affected** — bulk entry parsing improved |
| Members / RBAC                         | unaffected                                 |
| Auth / Session                         | unaffected                                 |
| Routing                                | unaffected                                 |
| Notifications                          | unaffected                                 |
| Platform (iOS / Android / Web / macOS) | unaffected — parsing is platform-agnostic  |

## Regression Risk

**LEVEL: LOW**

**Rationale:**

- Single file modified (`bulk_song_parser.dart`)
- Pure function added (no state, no side effects)
- Change is additive — existing unquoted fields pass through unchanged
- No auth, routing, database, or init order changes
- Bulk entry is an isolated feature with clear input/output boundaries
- If un-escaping logic is incorrect, worst case is continued corruption (no new breakage)

**Risk mitigation:**

- Unit tests will validate escaped and unescaped inputs
- Manual QA will test Google Sheets paste with smart quotes

## Engineer Task Breakdown

Execute in order:

### Task 1: Implement `_unescapeField` Helper Method

**File:** `lib/features/setlists/services/bulk_song_parser.dart`

Add a private method after `_parseColumns`:

```dart
/// Un-escape a TSV/CSV field that may be wrapped in double quotes.
///
/// Handles RFC 4180 quote wrapping and un-escaping:
/// - Strips outer double quotes if present: `"value"` → `value`
/// - Un-escapes doubled double-quotes: `""` → `"`
/// - Un-escapes doubled apostrophes (Google Sheets): `''` → `'`
///
/// If the field is not quoted, returns it as-is (after trim).
String _unescapeField(String field) {
  final trimmed = field.trim();

  // Not wrapped in quotes — return as-is
  if (!trimmed.startsWith('"') || !trimmed.endsWith('"') || trimmed.length < 2) {
    return trimmed;
  }

  // Strip outer quotes
  final inner = trimmed.substring(1, trimmed.length - 1);

  // Un-escape doubled quotes and apostrophes
  return inner
      .replaceAll('""', '"')   // RFC 4180: doubled double-quote
      .replaceAll("''", "'");  // Google Sheets: doubled apostrophe
}
```

**Validation:**

- Handles quoted fields: `"value"` → `value`
- Handles escaped quotes: `"say ""hello"""` → `say "hello"`
- Handles escaped apostrophes: `"Ain't Talkin' ''Bout Love"` → `Ain't Talkin' 'Bout Love`
- Passes through unquoted fields: `value` → `value`
- Handles empty/whitespace: `""` → `""`

### Task 2: Update `_parseColumns` to Use `_unescapeField`

**File:** `lib/features/setlists/services/bulk_song_parser.dart`

Replace the existing `_parseColumns` method:

**OLD:**

```dart
List<String> _parseColumns(String line) {
  // Try TAB-delimited first (spreadsheet paste)
  if (line.contains('\t')) {
    return line.split('\t').map((c) => c.trim()).toList();
  }

  // Try comma-delimited (manual entry)
  if (line.contains(',')) {
    return line.split(',').map((c) => c.trim()).toList();
  }

  // Fall back to 2+ spaces (legacy support)
  return line.split(RegExp(r'\s{2,}')).map((c) => c.trim()).toList();
}
```

**NEW:**

```dart
List<String> _parseColumns(String line) {
  // Try TAB-delimited first (spreadsheet paste)
  if (line.contains('\t')) {
    return line.split('\t').map(_unescapeField).toList();
  }

  // Try comma-delimited (manual entry)
  if (line.contains(',')) {
    return line.split(',').map(_unescapeField).toList();
  }

  // Fall back to 2+ spaces (legacy support)
  return line.split(RegExp(r'\s{2,}')).map(_unescapeField).toList();
}
```

**Change:** Replace `.map((c) => c.trim())` with `.map(_unescapeField)` in all three branches.

**Rationale:** `_unescapeField` already trims whitespace as its first step, so no functionality is lost.

### Task 3: Run Flutter Analyze

Ensure no new lint errors introduced:

```bash
flutter analyze
```

Expected: `0 errors`

### Task 4: Manual Testing — Create Test Cases

Document test cases in `ENGINEER_REPORT.md`:

**Test Case 1: Unquoted plain text (existing behavior)**

- Input: `Van Halen\tAin't No Fun\t120\tStandard`
- Expected: `title = "Ain't No Fun"` (unchanged)

**Test Case 2: Quoted field with escaped apostrophe (bug fix)**

- Input: `Van Halen\t"Ain't Talkin' ''Bout Love"\t120\tStandard`
- Expected: `title = "Ain't Talkin' 'Bout Love"` (three apostrophes → two)

**Test Case 3: Quoted field with escaped double-quote**

- Input: `Artist\t"Say ""Hello"""\t\t`
- Expected: `title = "Say "Hello""` (doubled quotes un-escaped)

**Test Case 4: Unquoted field with single apostrophe**

- Input: `Artist\tDon't Stop\t\t`
- Expected: `title = "Don't Stop"` (unchanged)

**Test Case 5: Empty and whitespace fields**

- Input: `Artist\t""\t\t`
- Expected: `title = ""` (empty string)

### Task 5: Manual QA — Google Sheets Paste

1. Create a Google Sheets test sheet with songs containing smart quotes:
   - `Ain't Talkin' 'Bout Love` (Van Halen) — with U+2018 before 'Bout
   - `Don't Stop Believin'` (Journey) — with U+2019 at end
   - `Rock 'n' Roll` — with U+2018 and U+2019
2. Copy all rows and paste into Bulk Entry overlay
3. Verify titles are parsed correctly without `'''` corruption

## Verification Plan

### Tier 1 — Pre-deployment (Local Testing Only)

**NOT APPLICABLE.** This is a client-side Flutter bug with no database changes.

### Tier 2 — Post-deployment (Manual QA)

**QA must execute these tests after code is merged:**

#### Test 1: Google Sheets Paste with Smart Quotes

1. Open Google Sheets
2. Create a sheet with these songs (copy from this doc to preserve U+2018/U+2019):
   ```
   Van Halen    Ain't Talkin' 'Bout Love    133    Standard
   Journey      Don't Stop Believin'         119    Standard
   AC/DC        Rock 'n' Roll                        Drop D
   ```
   (Ensure third column has U+2018 before 'Bout, U+2019 at end of Believin', and U+2018/U+2019 in Rock 'n' Roll)
3. Copy all three rows
4. Navigate to BandRoadie → Setlist Detail → FAB → Bulk Entry
5. Paste into text area
6. **Assert:** Preview shows correct titles:
   - `Ain't Talkin' 'Bout Love` (NO triple apostrophes)
   - `Don't Stop Believin'`
   - `Rock 'n' Roll`
7. Click "Add Songs"
8. **Assert:** Songs appear in setlist with correct titles

#### Test 2: Manual Entry (Comma-Delimited)

1. Navigate to Bulk Entry
2. Manually type: `Van Halen, Ain't Talkin' 'Bout Love, 133, Standard`
3. **Assert:** Preview shows correct title without corruption
4. Add song
5. **Assert:** Song title in setlist is correct

#### Test 3: Paste with Quoted Fields (RFC 4180)

1. Create a text file with TSV containing quoted fields:
   ```
   Artist	"Say ""Hello"""	120	Standard
   Band	"It's ""Quoted"""
   ```
2. Copy and paste into Bulk Entry
3. **Assert:** Titles are un-escaped correctly:
   - `Say "Hello"` (doubled quotes become single)
   - `It's "Quoted"`

#### Test 4: Regression — Plain Paste (No Quotes)

1. Paste tab-delimited text without quotes:
   ```
   The Beatles	Come Together	82	Standard
   Led Zeppelin	Stairway to Heaven	120
   ```
2. **Assert:** Songs parse correctly (no regression)

#### Test 5: Edge Cases

1. Paste empty fields: `Artist		120	`
2. Paste whitespace-only fields: `Artist	   	120	`
3. **Assert:** Parser handles gracefully (no crashes)

## QA Regression Areas

QA must explicitly validate:

1. **Primary fix:** Google Sheets paste with U+2018/U+2019 smart quotes no longer produces `'''` corruption
2. **RFC 4180 compliance:** Quoted fields with escaped double-quotes are un-escaped correctly
3. **Backward compatibility:** Plain tab-delimited paste (no quotes) continues to work
4. **Manual entry:** Comma-delimited input is unaffected
5. **Edge cases:** Empty fields, whitespace-only fields, unbalanced quotes do not crash parser
6. **UI validation:** Bulk Entry preview correctly shows parsed titles before submission
7. **Database integrity:** Songs added via bulk entry have correct titles in Catalog and target setlist

**Platforms to test:**

- macOS (primary development platform)
- Web (Vercel deployment)
- iOS (if accessible)

**Out of scope for this fix:**

- Android testing (optional if available)
- Right-to-left language support
- Excel paste (if behavior differs from Google Sheets)

## Rollout / Migration Strategy

**Not applicable.**  
This is a pure client-side bug fix with no backend changes. Deployment is standard:

1. Merge to `main`
2. `flutter build web --release`
3. `vercel --prod`

No user migration, data backfill, or feature flag required.

## Out of Scope

Explicitly excluded from this fix:

1. **CSV parsing library:** We will not introduce a third-party CSV parsing dependency for this one bug. Inline un-escaping is sufficient.
2. **Excel-specific paste behavior:** If Excel produces different escape sequences than Google Sheets, it is not addressed in this fix.
3. **Other Unicode normalization issues:** This fix handles quote escaping only. Other Unicode normalization (e.g., accents, diacritics, combining characters) is out of scope.
4. **Bulk edit overlay:** Only bulk _add_ is fixed. If a similar bug exists in other overlays, it requires a separate ticket.
5. **Historical data cleanup:** Songs already in the database with `'''` corruption are NOT automatically fixed. Users must manually edit or re-import those songs.
6. **Parser performance optimization:** The `_unescapeField` method is O(n) where n is field length. No profiling or optimization is required unless QA reports noticeable lag for very large pastes (>500 rows).

---

**Architect Signature:** Plan complete. Ready for Engineer implementation.
