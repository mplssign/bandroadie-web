# ARCHITECT_PLAN.md

## Feature Slug

`feature/song-links-multi-type`

---

## Problem Summary

The song details view currently has an "Add YouTube" button that accepts links of any type but labels them as YouTube-only. Users need the ability to add **multiple links per song** (not limited to one), with each link auto-classified by type (YouTube, Spotify, Apple Music, Amazon Music, SoundCloud, Google Docs, Google Sheets, PDF, or generic) and displayed with a matching icon.

This is not just a labeling change—it requires expanding the link storage model to support type detection and rendering type-specific icons per link.

---

## Root Cause

**Confidence: HIGH** (confirmed by code inspection)

The current implementation already supports multiple links per song (the `youtube_links` column stores a JSON array), but:

1. **UI labels are YouTube-specific**: Button text says "Add YouTube" and modal title says "Add YouTube Link"
2. **No link type classification**: The `YouTubeLink` model stores only `title` and `url`, with no `type` field
3. **Hardcoded YouTube icon**: All links render with a red YouTube play circle icon, regardless of actual link type
4. **No URL detection logic**: No utility exists to classify a URL by hostname/pattern

**Evidence:**

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart` line 27: `class YouTubeLink` has only `title` and `url`
- Line 1106: Button text is `'Add YouTube'`
- Line 583: Modal title is `'Add YouTube Link'`
- Line 1296: Icon is hardcoded `Icons.play_circle_outline, color: Colors.red`
- `songs` table has `youtube_links TEXT` column (migration 086) storing JSON: `[{"title": "...", "url": "..."}]`
- No `type` field exists in the JSON schema or model

---

## Reference Docs Consulted

No `docs/reference/songs/` or `docs/reference/setlists/` directory exists. Domain knowledge derived from:

- `docs/reference/architecture/database_schema.md` — confirmed `songs.youtube_links` column schema
- `supabase/migrations/086_add_youtube_links_column.sql` — confirmed JSON structure
- Codebase inspection: `song_details_bottom_sheet.dart`, `Song` model, `setlist_repository.dart`

---

## Existing System Analysis

### Current Storage Model

**Database:**

- `songs.youtube_links TEXT` column stores JSON array: `[{"title": "Live Performance", "url": "https://youtube.com/..."}]`
- No schema constraint — plain TEXT, JSON structure enforced by client only
- Column supports multiple links per song (it's an array)

**Models:**

- `Song.youtubeLinks` — nullable String (JSON)
- `SetlistSong.youtubeLinks` — nullable String (JSON)
- `YouTubeLink` class (lines 27–78 in `song_details_bottom_sheet.dart`):
  - Fields: `title` (String), `url` (String)
  - Static methods: `listFromJson()`, `listToJson()`
  - No `type` or link classification

**UI Flow:**

1. User taps "Add YouTube" button (line 1086–1125)
2. Modal prompts for title and URL (line 571–694)
3. Link added to `_youtubeLinks` list state
4. Rendered as button with YouTube play icon + title (line 1283–1326)
5. Tapping button opens URL via `url_launcher`
6. Delete via X icon (not available in read-only mode)

**Persistence:**

- `SetlistRepository.updateSongYoutubeLinks()` writes JSON string to `songs.youtube_links`
- Direct Supabase `.update()` with RPC fallback for legacy `NULL band_id` songs
- No validation of URL format or link count limit

### Current Icon Rendering

Line 1296: `Icons.play_circle_outline, color: Colors.red` — hardcoded for all links.

### Current Labels

- Button: "Add YouTube" (line 1106)
- Modal title: "Add YouTube Link" (line 583)
- Modal hint: "YouTube URL" (line 634)

---

## Proposed Solution

Expand the existing link storage to support multi-type links with auto-detection and type-specific icons. **No database migration required**—we expand the JSON schema by adding an optional `type` field.

### Core Changes

1. **Expand JSON schema** (backward-compatible):
   - Current: `[{"title": "...", "url": "..."}]`
   - New: `[{"title": "...", "url": "...", "type": "youtube"}]`
   - `type` is optional—missing values default to `"youtube"` for backward compatibility

2. **Create link type detector utility**:
   - New file: `lib/features/setlists/links/song_link_detector.dart`
   - Pure function: `SongLinkType detectLinkType(String url)`
   - Regex/hostname matching for: YouTube, Spotify, Apple Music, Amazon Music, SoundCloud, Google Docs, Google Sheets, PDF (`.pdf` extension), generic fallback

3. **Rename and expand model**:
   - Move `YouTubeLink` → new file `lib/features/setlists/links/song_link.dart`
   - Rename class: `YouTubeLink` → `SongLink`
   - Add `type` field (`SongLinkType` enum)
   - Update `fromJson` to handle missing `type` (default to `youtube`)
   - Update `toJson` to include `type`

4. **Update UI labels**:
   - "Add YouTube" → "Add a link"
   - "Add YouTube Link" → "Add Link"
   - "YouTube URL" hint → "Link URL"

5. **Map link types to icons**:
   - YouTube: `Icons.play_circle_outline` (red)
   - Spotify: `LucideIcons.music` (green `#1DB954`)
   - Apple Music: `LucideIcons.music` (pink/red `#FA243C`)
   - Amazon Music: `LucideIcons.music` (blue `#00A8E1`)
   - SoundCloud: `LucideIcons.music` (orange `#FF5500`)
   - Google Docs: `LucideIcons.fileText` (blue)
   - Google Sheets: `LucideIcons.table` (green)
   - PDF: `LucideIcons.fileText` (red)
   - Generic: `LucideIcons.link` (default text color)

6. **Auto-detect on add**:
   - When user saves a link, call `detectLinkType(url)` and populate `type` field
   - Store in JSON with type included

### Backward Compatibility

Existing `youtube_links` records in production have no `type` field. The `SongLink.fromJson()` method will check for missing `type` and default to `SongLinkType.youtube`. No data migration required.

---

## Database Impact

**Not applicable.** The `youtube_links` column already stores JSON TEXT with no schema constraint. We're adding an optional `type` field to the JSON structure, which is client-side only. Existing records remain valid.

**Verification:**

- No migration file required
- No RLS policy changes
- No RPC signature changes (the column name stays `youtube_links`, content is still JSON string)
- Existing RPC `update_song_metadata` parameter `p_youtube_links` accepts TEXT—no change needed

---

## Flutter Architecture Changes

### State Management

No new controllers or providers required. The `_SongDetailsSheetState` in `song_details_bottom_sheet.dart` already manages `_youtubeLinks` as local state. We replace `List<YouTubeLink>` with `List<SongLink>`.

### Models

- **New file**: `lib/features/setlists/links/song_link.dart` (extracted from `song_details_bottom_sheet.dart`)
  - `SongLinkType` enum with 9 values
  - `SongLink` class (renamed from `YouTubeLink`, adds `type` field)
  - Static parsing methods updated
- **No changes**: `Song` model, `SetlistSong` model (both still use `String?` for `youtubeLinks`)

### Widgets

- **Modified**: `song_details_bottom_sheet.dart`
  - Update imports to use `SongLink` from new file
  - Replace all `YouTubeLink` references with `SongLink`
  - Update button text: `'Add YouTube'` → `'Add a link'`
  - Update modal title and hints
  - Update `_buildYouTubeLinkButton()` to call `_getIconForLinkType()` helper
  - Add `_getIconForLinkType()` and `_getColorForLinkType()` helper methods

### Repository

No changes required. `SetlistRepository.updateSongYoutubeLinks()` already writes a JSON string—content structure is transparent to it.

---

## Files to Create

| File                                                  | Purpose                                                                    |
| ----------------------------------------------------- | -------------------------------------------------------------------------- |
| `lib/features/setlists/links/song_link.dart`          | Model for multi-type song links (extracted and renamed from `YouTubeLink`) |
| `lib/features/setlists/links/song_link_detector.dart` | Pure utility for URL-to-type classification                                |

**Justification:**

1. **`song_link.dart`**: The `YouTubeLink` class currently lives inline in `song_details_bottom_sheet.dart` (2,788 lines, already oversized). Extracting it to a dedicated model file follows the feature-first structure (`lib/features/setlists/links/`) and makes the model testable in isolation.

2. **`song_link_detector.dart`**: URL classification logic is pure business logic with no UI dependencies. Isolating it in a service file allows unit testing and reuse if link detection is needed elsewhere (e.g., bulk song import).

---

## Files to Modify

| File                                                           | What changes                                                                                                                                                                                                                                                                         |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Import new `SongLink` model; replace all `YouTubeLink` → `SongLink`; update button labels ("Add YouTube" → "Add a link"); update modal title/hints; add `_getIconForLinkType()` and `_getColorForLinkType()` helper methods; update `_buildYouTubeLinkButton()` to use dynamic icons |

---

## Files Off-Limits

| File                                                   | Reason                                                                        |
| ------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `lib/main.dart`                                        | Init order must not change                                                    |
| `lib/features/setlists/setlist_repository.dart`        | Repository is 4,027 lines — no changes needed (persistence path is unchanged) |
| `lib/features/setlists/setlist_detail_controller.dart` | Controller logic unchanged — link list is managed in sheet state              |
| `lib/features/setlists/setlist_detail_screen.dart`     | Screen is 2,788 lines — no changes needed (bottom sheet call site unchanged)  |
| `lib/features/setlists/models/song.dart`               | Model field remains `String?` (JSON) — no structural change                   |
| `lib/features/setlists/models/setlist_song.dart`       | Model field remains `String?` (JSON) — no structural change                   |
| `supabase/migrations/*`                                | No migration required — JSON schema expansion is client-side                  |

---

## System Impact Map

| System                                 | Impact                                                                                                                                             |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected — gigs do not interact with song links                                                                                                  |
| Rehearsals                             | unaffected — rehearsals do not interact with song links                                                                                            |
| Setlists / Catalog                     | **affected** — song details view is part of setlist/catalog song management; link storage and display are modified                                 |
| Members / RBAC                         | unaffected — no permission changes; existing song edit permissions apply                                                                           |
| Auth / Session                         | unaffected — no auth flow changes                                                                                                                  |
| Routing                                | unaffected — no new routes or navigation changes                                                                                                   |
| Notifications                          | unaffected — song edits do not trigger notifications                                                                                               |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms use `song_details_bottom_sheet.dart`; `url_launcher` package works cross-platform; no platform-specific code required |

---

## Regression Risk

**MEDIUM**

**Rationale:**

- **Setlists / Catalog** are affected — any song with existing YouTube links must parse correctly with the new model
- Backward compatibility is critical — existing JSON without `type` field must default correctly
- Multi-platform surface area (iOS, Android, macOS, Web) — all use the same bottom sheet
- **Low complexity**: No database changes, no RLS, no RPC signature changes, no new dependencies, no state management changes
- **Isolated change**: Only `song_details_bottom_sheet.dart` UI logic and two new utility files are modified
- **Testing surface**: Existing songs with YouTube links, new songs with mixed link types, link add/remove/tap-to-open flows

**Mitigations:**

- Unit tests for `detectLinkType()` (test all 9 link types)
- Unit tests for `SongLink.fromJson()` backward compatibility (missing `type` field)
- QA regression: existing YouTube links render and open correctly, new link types detect correctly

---

## Engineer Task Breakdown

Execute in strict order. Each task must be complete and verified before proceeding.

---

### Task 1 — Create SongLinkType enum and SongLink model

**File:** `lib/features/setlists/links/song_link.dart`

Create the new model file with:

1. `SongLinkType` enum with 9 values:

   ```dart
   enum SongLinkType {
     youtube,
     spotify,
     appleMusic,
     amazonMusic,
     soundcloud,
     googleDocs,
     googleSheets,
     pdf,
     generic,
   }
   ```

2. `SongLink` class (adapted from `YouTubeLink`):
   - Fields: `title` (String), `url` (String), `type` (SongLinkType)
   - Constructor with required named parameters
   - `fromJson` factory: parse `type` string to enum, default to `youtube` if missing or unrecognized
   - `toJson` method: include `type` as string (use `.name`)
   - Static `listFromJson(String?)` and `listToJson(List<SongLink>)` methods
   - Equality and hashCode overrides

**Acceptance Criteria:**

- `fromJson` handles missing `type` field → defaults to `SongLinkType.youtube`
- `fromJson` handles unrecognized `type` value → defaults to `SongLinkType.youtube`
- `toJson` includes `type` field as lowercase string (e.g., `"youtube"`, `"appleMusic"`)
- Static parsing methods work identically to original `YouTubeLink` methods

---

### Task 2 — Create link type detector utility

**File:** `lib/features/setlists/links/song_link_detector.dart`

Create a pure utility function:

```dart
import 'song_link.dart';

/// Detects the link type from a URL string.
///
/// Uses hostname and pattern matching to classify URLs.
/// Returns [SongLinkType.generic] if no match is found.
SongLinkType detectLinkType(String url);
```

**Detection Rules (regex or `contains()` checks):**

| Type           | Hostname/Pattern                           |
| -------------- | ------------------------------------------ |
| `youtube`      | `youtube.com`, `youtu.be`, `m.youtube.com` |
| `spotify`      | `spotify.com`, `open.spotify.com`          |
| `appleMusic`   | `music.apple.com`, `itunes.apple.com`      |
| `amazonMusic`  | `music.amazon.com`, `amazon.com/music`     |
| `soundcloud`   | `soundcloud.com`                           |
| `googleDocs`   | `docs.google.com/document`                 |
| `googleSheets` | `docs.google.com/spreadsheets`             |
| `pdf`          | URL ends with `.pdf` (case-insensitive)    |
| `generic`      | fallback if none match                     |

**Implementation Notes:**

- Case-insensitive matching
- Handle `http://`, `https://`, and no-scheme URLs
- Use `Uri.tryParse()` to extract hostname safely
- If parse fails, return `generic`

**Acceptance Criteria:**

- Function is pure (no side effects, no async)
- Returns correct `SongLinkType` for all 9 categories
- Handles malformed URLs gracefully (returns `generic`)
- Handles URLs with query params and fragments correctly

---

### Task 3 — Update song_details_bottom_sheet.dart imports and class references

**File:** `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

1. **Remove** the inline `YouTubeLink` class definition (lines 20–78)

2. **Add** imports at top of file:

   ```dart
   import '../links/song_link.dart';
   import '../links/song_link_detector.dart';
   ```

3. **Find and replace** all references:
   - `YouTubeLink` → `SongLink` (class name)
   - `_youtubeLinks` variable name can stay as-is (no breaking rename needed) OR rename to `_songLinks` for clarity (Engineer's choice — must be consistent throughout file)

**Acceptance Criteria:**

- No compilation errors
- All `YouTubeLink` references replaced with `SongLink`
- Imports point to new files in `lib/features/setlists/links/`
- No duplicate class definitions

---

### Task 4 — Update button and modal labels

**File:** `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

**Changes:**

1. **Line ~1106** (button label in `_buildAddButtonsRow()`):

   ```dart
   // Before:
   'Add YouTube',
   // After:
   'Add a link',
   ```

2. **Line ~583** (modal title in `_showAddYouTubeModal()`):

   ```dart
   // Before:
   'Add YouTube Link',
   // After:
   'Add Link',
   ```

3. **Line ~634** (URL field hint in `_showAddYouTubeModal()`):

   ```dart
   // Before:
   hintText: 'YouTube URL',
   // After:
   hintText: 'Link URL',
   ```

4. **Rename method** (optional but recommended for clarity):
   ```dart
   // Before:
   Future<void> _showAddYouTubeModal() async { ... }
   // After:
   Future<void> _showAddLinkModal() async { ... }
   ```
   Update the call site in `_buildAddButtonsRow()` accordingly.

**Acceptance Criteria:**

- Button text reads "Add a link"
- Modal title reads "Add Link"
- URL hint reads "Link URL"
- Method rename is consistent (if applied)

---

### Task 5 — Auto-detect link type on add

**File:** `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

In the modal's save button `onPressed` handler (inside `_showAddYouTubeModal` / `_showAddLinkModal`):

**Current code** (~line 660):

```dart
onPressed: () {
  final title = titleController.text.trim();
  final url = urlController.text.trim();
  if (title.isNotEmpty && url.isNotEmpty) {
    Navigator.of(context).pop(YouTubeLink(title: title, url: url));
  }
},
```

**Updated code**:

```dart
onPressed: () {
  final title = titleController.text.trim();
  final url = urlController.text.trim();
  if (title.isNotEmpty && url.isNotEmpty) {
    final detectedType = detectLinkType(url);
    Navigator.of(context).pop(
      SongLink(title: title, url: url, type: detectedType),
    );
  }
},
```

**Acceptance Criteria:**

- Link type is detected from URL before adding to list
- `SongLink` instance includes the detected `type`

---

### Task 6 — Add icon/color helper methods

**File:** `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

Add two new private methods in `_SongDetailsSheetState`:

```dart
/// Returns the icon for a given link type.
IconData _getIconForLinkType(SongLinkType type) {
  switch (type) {
    case SongLinkType.youtube:
      return Icons.play_circle_outline;
    case SongLinkType.spotify:
    case SongLinkType.appleMusic:
    case SongLinkType.amazonMusic:
    case SongLinkType.soundcloud:
      return LucideIcons.music;
    case SongLinkType.googleDocs:
    case SongLinkType.pdf:
      return LucideIcons.fileText;
    case SongLinkType.googleSheets:
      return LucideIcons.table;
    case SongLinkType.generic:
      return LucideIcons.link;
  }
}

/// Returns the color for a given link type.
Color _getColorForLinkType(SongLinkType type) {
  switch (type) {
    case SongLinkType.youtube:
      return Colors.red; // YouTube red
    case SongLinkType.spotify:
      return const Color(0xFF1DB954); // Spotify green
    case SongLinkType.appleMusic:
      return const Color(0xFFFA243C); // Apple Music pink/red
    case SongLinkType.amazonMusic:
      return const Color(0xFF00A8E1); // Amazon Music blue
    case SongLinkType.soundcloud:
      return const Color(0xFFFF5500); // SoundCloud orange
    case SongLinkType.googleDocs:
      return Colors.blue; // Google Docs blue
    case SongLinkType.googleSheets:
      return Colors.green; // Google Sheets green
    case SongLinkType.pdf:
      return Colors.red; // PDF red
    case SongLinkType.generic:
      return context.colors.textSecondary; // Default text color
  }
}
```

**Note**: Import `LucideIcons` if not already imported (it's in `app_icons.dart` but may need `import 'package:lucide_icons/lucide_icons.dart';` directly).

**Acceptance Criteria:**

- Methods compile without errors
- All 9 link types have an icon and color mapping
- Colors use exact hex values as specified

---

### Task 7 — Update link button rendering to use dynamic icons

**File:** `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

In `_buildYouTubeLinkButton()` method (~line 1283):

**Current code** (~line 1296):

```dart
Icon(Icons.play_circle_outline, color: Colors.red, size: 18),
```

**Updated code**:

```dart
Icon(
  _getIconForLinkType(link.type),
  color: _getColorForLinkType(link.type),
  size: 18,
),
```

Where `link` is the `SongLink` instance being rendered. You'll need to pass the link object (not just `title` and `url`) to `_buildYouTubeLinkButton()`.

**Update method signature**:

```dart
// Before:
Widget _buildYouTubeLinkButton(String title, String url, int index) { ... }

// After:
Widget _buildSongLinkButton(SongLink link, int index) { ... }
```

Update the call site in `_buildYouTubeLinksList()`:

```dart
// Before:
return _buildYouTubeLinkButton(displayTitle, link.url, index);

// After:
return _buildSongLinkButton(link, index);
```

Update method body to use `link.title`, `link.url`, `link.type` instead of parameters.

**Acceptance Criteria:**

- Link buttons render with type-specific icons
- Link buttons render with type-specific colors
- YouTube links use red play icon (unchanged visually)
- New link types use correct icons/colors

---

### Task 8 — Verify backward compatibility

**Manual Test (no code changes):**

1. Open the app and navigate to any song that has existing YouTube links (from production data)
2. Open song details bottom sheet
3. Verify:
   - Existing YouTube links display correctly
   - Icon is red YouTube play icon
   - Links open correctly when tapped
   - No parsing errors in debug console

**Acceptance Criteria:**

- Existing `youtube_links` JSON (without `type` field) parses successfully
- Links default to `SongLinkType.youtube`
- No runtime exceptions

---

### Task 9 — Run flutter analyze

Run `flutter analyze` and fix any errors or warnings introduced by the changes.

**Acceptance Criteria:**

- 0 errors
- No new warnings related to modified files

---

### Task 10 — Generate git diff

Run:

```bash
git diff > /tmp/song-links-multi-type.diff
```

Include the diff path in the Engineer Report.

**Acceptance Criteria:**

- Diff includes all modified and new files
- No unrelated changes in diff

---

## Verification Plan

### Tier 1 — Pre-deployment (no database changes to verify)

**Not applicable** — this feature has no database migration or RPC changes. All verification is post-implementation.

---

### Tier 2 — Post-deployment (run after implementation complete)

#### Manual Testing

**Test 1: Existing YouTube links render correctly**

1. Open song details for a song with existing YouTube links (production data)
2. Verify:
   - Links display with red YouTube play icon
   - Links open correctly when tapped
   - No console errors

**Expected**: Existing links parse with `type: youtube` (default), render correctly.

---

**Test 2: Add new YouTube link**

1. Open song details
2. Tap "Add a link"
3. Enter title: "Official Video", URL: `https://www.youtube.com/watch?v=dQw4w9WgXcQ`
4. Save
5. Verify:
   - Link displays with red YouTube play icon
   - Link opens correctly

**Expected**: YouTube link detected, correct icon/color.

---

**Test 3: Add Spotify link**

1. Open song details
2. Tap "Add a link"
3. Enter title: "Spotify Track", URL: `https://open.spotify.com/track/123`
4. Save
5. Verify:
   - Link displays with music icon in Spotify green (#1DB954)
   - Link opens correctly

**Expected**: Spotify link detected, correct icon/color.

---

**Test 4: Add Apple Music link**

1. Open song details
2. Tap "Add a link"
3. Enter title: "Apple Music", URL: `https://music.apple.com/us/album/123`
4. Save
5. Verify:
   - Link displays with music icon in Apple Music red (#FA243C)
   - Link opens correctly

**Expected**: Apple Music link detected, correct icon/color.

---

**Test 5: Add Google Docs link**

1. Open song details
2. Tap "Add a link"
3. Enter title: "Sheet Music", URL: `https://docs.google.com/document/d/123`
4. Save
5. Verify:
   - Link displays with file-text icon in blue
   - Link opens correctly

**Expected**: Google Docs link detected, correct icon/color.

---

**Test 6: Add PDF link**

1. Open song details
2. Tap "Add a link"
3. Enter title: "Chord Chart", URL: `https://example.com/chart.pdf`
4. Save
5. Verify:
   - Link displays with file-text icon in red
   - Link opens correctly

**Expected**: PDF link detected, correct icon/color.

---

**Test 7: Add generic link**

1. Open song details
2. Tap "Add a link"
3. Enter title: "Band Website", URL: `https://example.com`
4. Save
5. Verify:
   - Link displays with generic link icon in default text color
   - Link opens correctly

**Expected**: Generic link detected (no match), correct fallback icon/color.

---

**Test 8: Multiple links per song**

1. Open song details for a song
2. Add 3 links: 1 YouTube, 1 Spotify, 1 PDF
3. Verify:
   - All 3 links display with correct icons/colors
   - All 3 links open correctly
   - Links can be deleted individually via X icon

**Expected**: Multiple links coexist, each with correct type rendering.

---

**Test 9: Link persistence across sessions**

1. Add mixed link types to a song
2. Save song details
3. Close and reopen song details
4. Verify:
   - All links persist with correct types
   - Icons/colors render correctly

**Expected**: Links stored with `type` field in JSON, parsed correctly on reload.

---

**Test 10: Cross-platform rendering**

Run on iOS, Android, macOS, and Web:

1. Open song details
2. Add a Spotify link
3. Verify:
   - Link renders correctly
   - Icon/color display correctly
   - Link opens in platform browser/app when tapped

**Expected**: Cross-platform consistency (no platform-specific bugs).

---

#### Unit Tests (optional but recommended)

**Test: `detectLinkType()` for all types**

File: `test/features/setlists/links/song_link_detector_test.dart`

```dart
void main() {
  group('detectLinkType', () {
    test('detects YouTube', () {
      expect(detectLinkType('https://youtube.com/watch?v=123'), SongLinkType.youtube);
      expect(detectLinkType('https://youtu.be/123'), SongLinkType.youtube);
    });

    test('detects Spotify', () {
      expect(detectLinkType('https://open.spotify.com/track/123'), SongLinkType.spotify);
    });

    test('detects Apple Music', () {
      expect(detectLinkType('https://music.apple.com/us/album/123'), SongLinkType.appleMusic);
    });

    test('detects Amazon Music', () {
      expect(detectLinkType('https://music.amazon.com/albums/123'), SongLinkType.amazonMusic);
    });

    test('detects SoundCloud', () {
      expect(detectLinkType('https://soundcloud.com/artist/track'), SongLinkType.soundcloud);
    });

    test('detects Google Docs', () {
      expect(detectLinkType('https://docs.google.com/document/d/123'), SongLinkType.googleDocs);
    });

    test('detects Google Sheets', () {
      expect(detectLinkType('https://docs.google.com/spreadsheets/d/123'), SongLinkType.googleSheets);
    });

    test('detects PDF', () {
      expect(detectLinkType('https://example.com/file.pdf'), SongLinkType.pdf);
      expect(detectLinkType('https://example.com/file.PDF'), SongLinkType.pdf); // case insensitive
    });

    test('fallback to generic', () {
      expect(detectLinkType('https://example.com'), SongLinkType.generic);
      expect(detectLinkType('not-a-url'), SongLinkType.generic);
    });
  });
}
```

**Test: `SongLink.fromJson()` backward compatibility**

File: `test/features/setlists/links/song_link_test.dart`

```dart
void main() {
  group('SongLink.fromJson', () {
    test('parses with type field', () {
      final json = {'title': 'Test', 'url': 'https://example.com', 'type': 'spotify'};
      final link = SongLink.fromJson(json);
      expect(link.type, SongLinkType.spotify);
    });

    test('defaults to youtube when type is missing', () {
      final json = {'title': 'Test', 'url': 'https://example.com'};
      final link = SongLink.fromJson(json);
      expect(link.type, SongLinkType.youtube);
    });

    test('defaults to youtube when type is unrecognized', () {
      final json = {'title': 'Test', 'url': 'https://example.com', 'type': 'unknown'};
      final link = SongLink.fromJson(json);
      expect(link.type, SongLinkType.youtube);
    });
  });

  group('SongLink.toJson', () {
    test('includes type field', () {
      final link = SongLink(title: 'Test', url: 'https://example.com', type: SongLinkType.spotify);
      final json = link.toJson();
      expect(json['type'], 'spotify');
    });
  });
}
```

---

## QA Regression Areas

QA must specifically test:

1. **Existing YouTube links (backward compatibility)**:
   - Open songs with existing YouTube links from production data
   - Verify links display with correct icon/color
   - Verify links open correctly

2. **New link type detection**:
   - Add links for all 9 supported types
   - Verify correct icon/color for each type
   - Verify generic fallback for unrecognized URLs

3. **Multiple links per song**:
   - Add 5+ mixed-type links to a single song
   - Verify all render correctly
   - Verify all open correctly
   - Verify independent deletion

4. **Link persistence**:
   - Add mixed links, save, reopen song details
   - Verify links persist with correct types

5. **Cross-platform rendering**:
   - Test on iOS, Android, macOS, Web
   - Verify icons/colors render consistently
   - Verify `url_launcher` opens links correctly on all platforms

6. **Edge cases**:
   - Malformed URLs (no scheme, invalid format)
   - Very long link titles (truncation)
   - Empty link list (no visual regression)

7. **Read-only mode**:
   - Open song details in read-only mode (verify delete buttons hidden)
   - Verify links still tap-to-open

8. **Song details unrelated fields**:
   - Verify title, artist, BPM, duration, tuning, key, notes, lyrics editing still works
   - Verify save button reactivity unchanged
   - Verify unsaved changes dialog unchanged

---

## Rollout / Migration Strategy

**Not applicable.** No database migration, no schema change, no multi-stage rollout required. Changes are client-side only and backward-compatible.

**Deployment:**

1. Deploy web via `./tools/deploy_web.sh`
2. Post-deploy verification:
   - Incognito load
   - Open song with existing YouTube links
   - Add new Spotify link
   - Verify both render correctly

**Rollback:**
If a critical bug is found post-deploy, roll back the web deployment. The database is unaffected, so rollback is safe. Existing YouTube links will continue to work on the previous version.

---

## Out of Scope

Explicitly **not** included in this feature:

1. **Link validation**: No URL format validation (e.g., checking if YouTube URL is valid). Any string is accepted as a URL.
2. **Link count limit**: No enforced maximum number of links per song.
3. **Link preview/thumbnails**: No fetching of metadata, thumbnails, or og:image from URLs.
4. **Link reordering**: Links cannot be drag-reordered (they display in insertion order).
5. **Link editing**: Once added, a link's title/URL cannot be edited—only deleted and re-added.
6. **Deep linking to native apps**: Links open in browser/web view—no special handling for Spotify/Apple Music native app deep links.
7. **Bulk link import**: No CSV/text-paste bulk link addition.
8. **Link analytics**: No tracking of link tap counts or usage.
9. **Column rename**: The `youtube_links` column name stays as-is for backward compatibility—no migration to rename it to `links`.

---

**End of ARCHITECT_PLAN.md**
