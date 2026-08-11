# ARCHITECT PLAN — Lyrics ChordPro Retrofit

## Feature Slug
`feature/lyrics-chordpro-retrofit`

---

## Problem Summary

BandRoadie's existing lyrics feature (shipped v1.1.7, `lib/features/lyrics/`) stores lyrics as JSON (`LyricsData`/`LyricsBlock` model) with section-level formatting (`LyricsHighlight` enum: verse/chorus/bridge/etc.) rendered as colored background tints. It has no chord support. Phase 2.4 retrofits this into a plain-text ChordPro system so bands can manually enter chord annotations (e.g., `[Am]`, `[C]`, `[G]`) inline with lyrics text, and toggle chord visibility on/off when viewing.

**Critical Constraint:** No automatic chord or lyrics-fetch provider is being integrated. This is **manual-entry only**. Research (`docs/features/phase-2.4-lyrics-research/PROVIDER_FINDINGS.md`) found no provider offering both a legal commercial API and chord data. A lyrics-text-only auto-fetch (e.g., Musixmatch) is a possible future Phase 2.5, but explicitly out of scope for this retrofit — **do not build any Edge Function, provider client, or fetch UI for automatic data**.

**Confirmed Breaking Change:** Migration uses **lossy conversion**. Existing `LyricsHighlight` formatting (section colors, font size, bold) is discarded — block `text` fields are concatenated into plain text, `highlight`/`fontSize`/`isBold` metadata is dropped. **Tony explicitly accepted this trade-off on 2026-08-10.** Verified against prod (`nekwjxvgbveheooyorjo`): 325 songs currently have non-empty `lyrics`; 808 blocks across those songs use non-`"none"` highlight values. This is real data loss, but the decision is final — do not re-litigate or propose dual-format storage.

---

## Root Cause

**Not applicable** — this is a feature retrofit, not a bug fix.

**Confidence Level:** N/A

---

## Reference Docs Consulted

**Phase 2.4 Research:**
- `docs/features/phase-2.4-lyrics-research/PROVIDER_FINDINGS.md` — Provider evaluation, ChordPro recommendation, retrofit approach, migration options

**Existing Implementation:**
- `lib/features/lyrics/models/lyrics_data.dart` — Current JSON data model
- `lib/features/lyrics/widgets/lyrics_editor_sheet.dart` — Formatting toolbar, per-line highlight coloring
- `lib/features/lyrics/widgets/lyrics_view_screen.dart` — Section-based rendering with colored backgrounds
- `lib/features/lyrics/services/lyrics_view_settings_service.dart` — Per-song view preferences (font size, auto-scroll speed)

**Database:**
- `supabase/migrations/088_add_lyrics_youtube_to_update_song_rpc.sql` — `songs.lyrics` TEXT column, `update_song_metadata` RPC signature

**Reference Pattern:**
- `lib/features/songs/enrichment_settings_screen.dart` — Settings-based toggle pattern (reviewed, but not directly applicable — enrichment uses settings radio tiles, not runtime view toggle)
- **Note:** Enrichment pattern is settings-based (saved preference for future behavior), whereas lyrics needs a **runtime toggle** (per-session show/hide preference with persisted default). Implementation pattern will differ.

---

## Existing System Analysis

### Current Lyrics Feature (Shipped v1.1.7)

**Data Model:**
```dart
// lib/features/lyrics/models/lyrics_data.dart
enum LyricsHighlight {
  none, intro, verse, preChorus, chorus, bridge, outro
  // Each has colorValue (20% opacity background) and accentColorValue
}

class LyricsBlock {
  final String text;
  final LyricsHighlight highlight;
  final double fontSize;
  final bool isBold;
}

class LyricsData {
  final List<LyricsBlock> blocks;
  final double defaultFontSize;
  final bool defaultBold;
  
  String toJsonString() // Serialize to JSON for songs.lyrics TEXT column
  factory fromJsonString(String?) // Deserialize from DB
  String get plainText // Blocks joined with '\n\n'
}
```

**Storage:**
- Column: `songs.lyrics` (TEXT, nullable)
- Format: JSON string (via `LyricsData.toJsonString()`)
- Example:
  ```json
  {
    "blocks": [
      {"text": "When you try your best...", "highlight": "verse", "fontSize": 22},
      {"text": "Fix you", "highlight": "chorus", "fontSize": 22, "isBold": true}
    ],
    "defaultFontSize": 22.0,
    "defaultBold": false
  }
  ```

**Editor (`lyrics_editor_sheet.dart`):**
- Full-screen bottom sheet modal
- Custom `_HighlightedLyricsController` extends `TextEditingController` to render per-line text colors based on block highlights
- Formatting toolbar (horizontal scroll):
  - Font size –/+ buttons (circular rose-outlined)
  - Bold toggle
  - 7 color preset chips (intro/verse/pre-chorus/chorus/bridge/outro/none) with colored dots
- Tap color chip → applies highlight to selected line(s)
- Line-level highlight tracking: `Map<int, LyricsHighlight> _blockHighlights`
- On save: merges consecutive lines with same highlight into one `LyricsBlock`

**Viewer (`lyrics_view_screen.dart`):**
- Full-screen route (PageRouteBuilder with fade + slide)
- Renders `LyricsBlock` list with:
  - Section label (e.g., "Verse", "Chorus") via `highlight.label`
  - Background tint via `highlight.colorValue` (20% opacity)
  - Per-block font size and bold
- Auto-scroll: Timer-based pixel-per-frame scrolling (~60 fps), adjustable speed
- Font size ±: User-adjustable (12.0–36.0 range)
- Toolbar auto-hide: 3-second delay when auto-scrolling
- Manual scroll detection: Pauses auto-scroll on drag
- Settings persisted per-song via `LyricsViewSettingsService`

**Settings Service (`lyrics_view_settings_service.dart`):**
- Storage: SharedPreferences
- Key format: `lyrics_view_<songId>`
- Fields:
  ```dart
  class LyricsViewSettings {
    final double fontSize;
    final double scrollSpeed; // pixels/second
    final bool autoScrollEnabled;
  }
  ```
- Per-song, per-user (local device only)

**Usage Points:**
- `setlist_detail_screen.dart` — "View Lyrics" button (tap song card) → `showLyricsViewScreen()`
- `song_details_bottom_sheet.dart` — "Edit Lyrics" button → `showLyricsEditor()` → saves via Supabase RPC or direct UPDATE
- `setlist_song.dart`, `song.dart` models — `lyrics` field (String?, stores JSON)
- `reorderable_song_card.dart`, `song_card.dart` — Lyrics icon badge (shows if `LyricsData.fromJsonString(song.lyrics).isNotEmpty`)

**Current Data Flow:**
1. User taps "Edit Lyrics" → `showLyricsEditor()` with `LyricsData.fromJsonString(song.lyrics)`
2. Editor displays formatted blocks with color-coded lines
3. User edits text, applies highlights via toolbar
4. On save → `LyricsData` serialized to JSON → saved to `songs.lyrics` via RPC (`update_song_metadata`) or direct `UPDATE`
5. User taps "View Lyrics" → `showLyricsViewScreen()` with parsed `LyricsData`
6. Viewer renders blocks with colored backgrounds, section labels

---

## Proposed Solution

### High-Level Retrofit Strategy

**ChordPro Format:**
- Plain-text storage: `songs.lyrics` column remains TEXT, but stores ChordPro plain-text instead of JSON
- Chord annotations: `[Am]`, `[C]`, `[G]` inline before the word/syllable they apply to
- Section labels (optional): `{start_of_chorus}`, `{end_of_chorus}` etc. (ChordPro directives)
- Example:
  ```
  [Am]When you try your [C]best but you [G]don't succeed
  [Am]When you get what you [C]want but not what you [G]need
  
  {start_of_chorus}
  [F]Lights will [C]guide you [G]home
  {end_of_chorus}
  ```

**Migration:**
- **One-time data migration** converts all existing non-null `songs.lyrics` JSON rows to plain-text ChordPro
- **Lossy strategy** (Tony-approved, 2026-08-10):
  1. Parse JSON as `LyricsData`
  2. Extract `blocks[].text` fields
  3. Concatenate with `\n\n` separators (preserves paragraph breaks)
  4. Discard `highlight`, `fontSize`, `isBold`, `defaultFontSize`, `defaultBold` metadata
  5. Write back plain text to `songs.lyrics`
- **No ChordPro section-label preservation** (no mapping of `LyricsHighlight.verse` → `{start_of_verse}`). This was considered and rejected — plain text only, no directives in initial migration.
- **Timing:** Migration must execute **before** the retrofit ships to production. All users must see plain-text data post-deployment. Script is reviewable and Tony-gated.

**Retrofitted Editor:**
- **Remove:** Formatting toolbar (font size ±, bold, highlight color chips, per-line coloring in `TextEditingController`)
- **Keep:** Full-screen modal presentation, save/cancel flow, `TextField` with multiline input
- **Add:** ChordPro syntax helper
  - Tooltip or help icon button near top-right (next to Cancel/Save)
  - Displays: "Add chords by typing `[Am]` before a word. Example: `[G]Hello [C]world`"
  - Optional: Link to external ChordPro syntax guide (or inline help sheet)
- **Simplify state:** Remove `Map<int, LyricsHighlight> _blockHighlights`, remove `_HighlightedLyricsController`, use standard `TextEditingController`
- **Validation:** None required — any plain text is valid (brackets are optional, no strict parsing on save)

**Retrofitted Viewer:**
- **Remove:** Section-based rendering with colored backgrounds, section labels
- **Keep:** Full-screen route, auto-scroll, font size ±, toolbar auto-hide, manual scroll detection, existing settings persistence
- **Add:** ChordPro parser
  - Regex: `\[([^\]]+)\]` → extract chord, remove from lyrics text, render chord above aligned word
  - Rendering: Each line split into `[Chord]text` pairs → `Column` of `Row` widgets:
    ```dart
    Column(
      children: [
        Text(chord, style: chordStyle), // Small, rose accent, only if chords visible
        Text(word, style: lyricsStyle),  // Normal lyrics text
      ]
    )
    ```
  - Handle edge cases:
    - `[Chord]` at start of line → render above first word
    - `[Chord]` mid-word (e.g., `hel[G]lo`) → render above that position
    - Multiple `[Chord]` before same word → stack chords vertically or join with `/`
    - No chords → render as plain text (no change from current behavior)
- **Add:** Chords-on/off toggle
  - UI: Switch control in top toolbar (between song title and font size buttons)
  - Label: "Chords" (compact) or icon (e.g., music note icon)
  - Behavior: When OFF, parser extracts chords but doesn't render them (lyrics text only visible)
  - State: Persisted per-user (not per-song) via `LyricsViewSettingsService.chordsVisible` (new field, default `true`)
  - **Key point:** Toggle is functional even if song has no chords — it's a view preference, not song-specific metadata. Songs with no `[Chord]` annotations will show no visual difference between on/off states.

**Extended Settings:**
```dart
// lib/features/lyrics/services/lyrics_view_settings_service.dart
class LyricsViewSettings {
  final double fontSize;
  final double scrollSpeed;
  final bool autoScrollEnabled;
  final bool chordsVisible; // NEW — default true
}
```
- `chordsVisible` is **per-user, not per-song** — stored in SharedPreferences with global key `lyrics_view_chords_visible` (separate from per-song settings)
- Rationale: Users who prefer chords-off likely want it off for all songs, not per-song configuration

**Deprecated Model Classes:**
- `LyricsData`, `LyricsBlock`, `LyricsHighlight` → Mark `@Deprecated` after migration
- Remove after confirming zero usage via grep (post-retrofit, in a follow-up cleanup commit)
- Keep models in codebase temporarily for rollback safety (in case migration needs to revert)

**UI/UX Messaging:**
- Editor help text: "Add chords using ChordPro format, e.g., `[G]` before a word"
- Do NOT imply automatic chord lookup anywhere (no "Fetch Chords" button, no Musixmatch/Ultimate Guitar references)
- Existing songs without chords: Toggle has no visible effect until user manually adds `[Chord]` annotations

---

## Database Impact

**Schema Changes:** None required

**Existing Column:**
- `songs.lyrics` (TEXT, nullable) — already exists, no DDL changes
- Current: Stores JSON string
- After retrofit: Stores plain-text ChordPro
- Migration is data-only (UPDATE content format), not schema-only (no ALTER TABLE)

**RLS Policies:** Not affected
- `songs` table RLS already permits band members to read/write lyrics
- No new RLS policies required

**RPC Functions:**
- `update_song_metadata(p_song_id, p_band_id, ..., p_lyrics TEXT, ...)` — already supports `p_lyrics` parameter
- Function signature: No changes required
- Behavior: No changes required (RPC accepts TEXT, doesn't validate format)
- **Note:** RPC is used for legacy songs with `NULL band_id` (requires `SECURITY DEFINER` to bypass RLS). Band-scoped songs use direct Supabase `UPDATE`. Both paths work with plain-text ChordPro — no RPC modification needed.

**Triggers:** Not affected
- No lyrics-specific triggers exist
- Song update triggers (`updated_at`) already handle `lyrics` column changes

**Migration Script:**
- **Location:** `database/maintenance/migrate_lyrics_to_chordpro.sql`
- **Type:** One-time data migration (not a numbered Supabase migration — run manually pre-deploy)
- **Verification Required:** Tony must review SQL and approve execution against production DB
- **Pre-flight checks:**
  1. Backup production `songs` table (Tony's responsibility, confirm before executing)
  2. Run against staging first (project `staging`, if exists)
  3. Audit affected row count: `SELECT COUNT(*) FROM songs WHERE lyrics IS NOT NULL`
  4. Log sample conversions for manual inspection
- **Rollback Strategy:** Restore from backup if migration produces incorrect output. **No automatic rollback** — migration is one-way, destructive (formatting metadata is lost).

**Migration SQL (Detailed Specification):**

```sql
-- migrate_lyrics_to_chordpro.sql
-- One-time data migration: Convert songs.lyrics from JSON (LyricsData) to plain-text ChordPro
-- 
-- LOSSY CONVERSION (Tony-approved 2026-08-10):
-- - Extracts block[].text fields from JSON
-- - Concatenates blocks with double-newline separators
-- - Discards highlight, fontSize, isBold, defaultFontSize, defaultBold metadata
--
-- PRE-FLIGHT:
-- 1. Backup songs table: pg_dump or Supabase dashboard export
-- 2. Run on staging first, inspect sample outputs
-- 3. Confirm affected row count matches expectation (~325 songs as of 2026-08-10)
--
-- EXECUTION:
-- psql -h <db-host> -U postgres -d postgres -f migrate_lyrics_to_chordpro.sql
--
-- POST-FLIGHT:
-- 1. Verify no NULL lyrics for songs that had JSON before
-- 2. Spot-check 5-10 random songs for text accuracy (no truncation, line breaks preserved)

BEGIN;

-- Create a temporary backup table (optional, for rollback within session)
CREATE TEMP TABLE lyrics_backup AS 
SELECT id, lyrics 
FROM songs 
WHERE lyrics IS NOT NULL;

-- Log pre-migration stats
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM songs WHERE lyrics IS NOT NULL;
  RAISE NOTICE 'Pre-migration: % songs with non-null lyrics', v_count;
END $$;

-- Main migration: Parse JSON, extract text, concatenate, write back
UPDATE songs
SET lyrics = (
  SELECT string_agg(block_text, E'\n\n')
  FROM (
    SELECT jsonb_array_elements(lyrics_json->'blocks')->>'text' AS block_text
    FROM (
      SELECT lyrics::jsonb AS lyrics_json
    ) parsed
  ) blocks
)
WHERE lyrics IS NOT NULL
  AND lyrics != ''
  AND lyrics::jsonb ? 'blocks'; -- Only convert valid LyricsData JSON

-- Log post-migration stats
DO $$
DECLARE
  v_count INTEGER;
  v_null_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM songs WHERE lyrics IS NOT NULL;
  SELECT COUNT(*) INTO v_null_count FROM lyrics_backup lb
    WHERE NOT EXISTS (
      SELECT 1 FROM songs s WHERE s.id = lb.id AND s.lyrics IS NOT NULL
    );
  RAISE NOTICE 'Post-migration: % songs with non-null lyrics', v_count;
  IF v_null_count > 0 THEN
    RAISE WARNING '% songs lost lyrics (JSON parse failures)', v_null_count;
  END IF;
END $$;

-- Sample output for manual inspection (first 3 converted songs)
DO $$
DECLARE
  r RECORD;
BEGIN
  RAISE NOTICE 'Sample conversions (first 3 songs):';
  FOR r IN 
    SELECT s.id, s.title, s.artist, lb.lyrics AS old_lyrics, s.lyrics AS new_lyrics
    FROM songs s
    JOIN lyrics_backup lb ON lb.id = s.id
    WHERE s.lyrics IS NOT NULL
    LIMIT 3
  LOOP
    RAISE NOTICE 'Song: % by %', r.title, r.artist;
    RAISE NOTICE 'Old JSON: %', left(r.old_lyrics, 200);
    RAISE NOTICE 'New Text: %', left(r.new_lyrics, 200);
    RAISE NOTICE '---';
  END LOOP;
END $$;

COMMIT;

-- Post-migration validation query (run separately after COMMIT)
-- Confirms no songs lost lyrics unexpectedly
SELECT 
  COUNT(*) FILTER (WHERE lyrics IS NOT NULL) AS songs_with_lyrics,
  COUNT(*) FILTER (WHERE lyrics IS NULL) AS songs_without_lyrics,
  COUNT(*) FILTER (WHERE lyrics ~ '\[.+\]') AS songs_with_chords -- Expect 0 immediately after migration
FROM songs;
```

**Migration Timing in Deployment Pipeline:**
1. **Before retrofit ships:** Migration must execute against production DB
2. **Order:**
   - Deploy migration SQL to staging (if exists) → validate
   - Tony approves production migration
   - Execute SQL against production DB (`nekwjxvgbveheooyorjo`) → verify
   - **Then** deploy Flutter code with ChordPro parser/editor
3. **Rollback Window:** If Flutter deployment fails post-migration, users see plain-text lyrics without chord highlighting (degraded but not broken). Restore from backup if critical, but expect formatting loss.

---

## Flutter Architecture Changes

### State Management

**No new controllers or providers required.**

**Modified State:**
- `LyricsViewSettings` (existing service) gains `chordsVisible` field
- `lyrics_view_screen.dart` state gains `_chordsVisible` bool (initialized from settings)

### Widgets

**Modified:**
- `lyrics_editor_sheet.dart` — Strip formatting toolbar, simplify controller, add ChordPro help
- `lyrics_view_screen.dart` — Add ChordPro parser, add toggle switch, retain existing auto-scroll/font-size logic

**No new screens or major widgets required.**

### Services

**Modified:**
- `lyrics_view_settings_service.dart` — Add `chordsVisible` field to `LyricsViewSettings`

**New:**
- `chordpro_parser.dart` — Parse `[Chord]` annotations, return structured data for rendering

### Models

**Deprecated (not deleted immediately):**
- `lyrics_data.dart` — `LyricsData`, `LyricsBlock`, `LyricsHighlight` marked `@Deprecated`
- Keep in codebase post-retrofit for rollback safety (remove in follow-up cleanup PR after 2-week stability window)

**No new models required** — ChordPro is plain text, no structured model needed (parser outputs transient rendering data, not persisted model).

### Repositories

**No changes required.**

- `setlist_repository.dart` — Already saves `lyrics` as TEXT via Supabase `UPDATE` or RPC
- No new repository methods needed (plain-text saves identically to JSON from repository perspective)

---

## Files to Create

### 1. `lib/features/lyrics/services/chordpro_parser.dart`

**Purpose:** Parse ChordPro plain-text into structured rendering data (chord + text pairs).

**Justification:** Viewer needs to extract `[Chord]` annotations and align them with lyrics text. Parser logic is complex enough (regex, edge cases) to isolate into a service for testability.

**Public API:**
```dart
/// Parsed chord annotation with position metadata
class ChordAnnotation {
  final String chord; // e.g., "Am", "C", "G7"
  final int position; // Character offset in line where chord applies
}

/// Parsed line with chords extracted
class ParsedLyricsLine {
  final String text; // Lyrics text with [Chord] removed
  final List<ChordAnnotation> chords; // Chords in order of appearance
}

/// Parse ChordPro plain text into structured lines
class ChordProParser {
  /// Parse full lyrics text into lines with chord annotations
  static List<ParsedLyricsLine> parse(String lyricsText);
  
  /// Extract section directives (e.g., {start_of_chorus})
  /// Returns list of (directive, lineIndex) pairs
  /// (Phase 2.4: Not used in UI, but parse for future extensibility)
  static List<(String directive, int lineIndex)> extractDirectives(String lyricsText);
}
```

**Implementation Notes:**
- Regex: `\[([^\]]+)\]` to match `[Chord]`
- Split text into lines, parse each line independently
- Track character position of each chord before removing brackets
- Handle edge cases:
  - Empty lines → return empty `ParsedLyricsLine`
  - No chords → return line with empty `chords` list
  - Malformed brackets (e.g., `[Am` without closing) → treat as literal text, don't crash
- **No validation of chord names** — any text inside `[...]` is treated as a chord (e.g., `[invalid123]` is valid input, rendered as-is)

### 2. `database/maintenance/migrate_lyrics_to_chordpro.sql`

**Purpose:** One-time data migration to convert JSON lyrics to plain-text ChordPro.

**Justification:** Migration is a critical, reviewable artifact. Must be version-controlled and Tony-gated before production execution.

**Contents:** Full SQL script (see "Database Impact" section above for complete script).

**Execution:** Manual, via `psql` or Supabase SQL Editor, **before** Flutter code deploys.

---

## Files to Modify

| File | Changes | Rationale |
|------|---------|-----------|
| **`lib/features/lyrics/widgets/lyrics_editor_sheet.dart`** | **Remove:** Formatting toolbar (_buildFormattingToolbar), font size ±, bold toggle, color preset chips, per-line highlight tracking (`Map<int, LyricsHighlight> _blockHighlights`), custom `_HighlightedLyricsController`.<br><br>**Simplify:** Use standard `TextEditingController` instead of custom subclass.<br><br>**Add:** ChordPro syntax helper — `IconButton` with `AppIcons.help` (or `Icons.info_outline`) in header row (between Cancel and Save). Tap → show `AlertDialog` or bottom sheet with:<br>- Title: "ChordPro Format"<br>- Body: "Add chords by typing `[Am]` before a word. Example: `[G]Hello [C]world`. Chords will appear above the lyrics when viewing."<br>- Optional: "Learn more" link to external ChordPro guide (e.g., `https://www.chordpro.org/chordpro/chordpro-introduction/`).<br><br>**Keep:** Full-screen modal presentation, save/cancel flow, `TextField` multiline input, slide-up animation. | Strip all formatting features (no longer applicable in ChordPro world). Simplify state by removing per-line color tracking. Add minimal help UI so users understand `[Chord]` syntax. |
| **`lib/features/lyrics/widgets/lyrics_view_screen.dart`** | **Add:** `import 'package:bandroadie/features/lyrics/services/chordpro_parser.dart'`.<br><br>**Add:** `_chordsVisible` state variable (bool, default from settings).<br><br>**Add:** ChordPro parsing in `_buildLyricsContent()` (replaces section-based block rendering):<br>- Parse `widget.lyrics` (now plain text) via `ChordProParser.parse()`<br>- Render each `ParsedLyricsLine` as a `Column` of `Row` widgets:<br>  - For each chord: `Column([Text(chord), Text(word)])` if `_chordsVisible`, else just `Text(word)`<br>  - Chord style: `AppTextStyles.caption` (small), `AppColors.primary` (rose), positioned above word<br>  - Lyrics style: `AppTextStyles.body` scaled by `_settings.fontSize`<br><br>**Add:** Chords toggle in `_buildTopBar()`:<br>- Position: Between song title and font size buttons<br>- UI: `Switch` widget with label "Chords" or icon (`AppIcons.music` or similar)<br>- Behavior: Tap → toggle `_chordsVisible`, save to global settings (`LyricsViewSettingsService.saveChordsVisible()`), rebuild UI<br><br>**Remove:** Section-based rendering (colored backgrounds, section labels from `LyricsHighlight`), `LyricsBlock` iteration logic.<br><br>**Keep:** Auto-scroll, font size ±, toolbar auto-hide, manual scroll detection, all existing settings persistence. | Add ChordPro parser integration and chords-on/off toggle. Remove formatting-based rendering. Retain all existing viewer features (auto-scroll, font size, toolbar behavior). |
| **`lib/features/lyrics/services/lyrics_view_settings_service.dart`** | **Add:** `chordsVisible` field to `LyricsViewSettings` model:<br>`final bool chordsVisible; // default true`<br><br>**Add:** Global chords-visible persistence:<br>- New key: `lyrics_view_chords_visible_global`<br>- New methods:<br>  ```dart<br>  static Future<bool> loadChordsVisible() async {<br>    final prefs = await SharedPreferences.getInstance();<br>    return prefs.getBool('lyrics_view_chords_visible_global') ?? true;<br>  }<br>  <br>  static Future<void> saveChordsVisible(bool visible) async {<br>    final prefs = await SharedPreferences.getInstance();<br>    await prefs.setBool('lyrics_view_chords_visible_global', visible);<br>  }<br>  ```<br><br>**Rationale:** `chordsVisible` is per-user preference (not per-song), so store globally. Per-song settings (`fontSize`, `scrollSpeed`) remain unchanged. | Extend existing settings service to persist chords-visible toggle state. Use global key (not per-song) because toggle is a user preference, not song-specific. |
| **`lib/features/lyrics/models/lyrics_data.dart`** | **Add:** `@Deprecated` annotations to all classes:<br>```dart<br>@Deprecated('Use plain-text ChordPro format. Kept for rollback safety post-migration.')<br>enum LyricsHighlight { ... }<br><br>@Deprecated('Use plain-text ChordPro format. Kept for rollback safety post-migration.')<br>class LyricsBlock { ... }<br><br>@Deprecated('Use plain-text ChordPro format. Kept for rollback safety post-migration.')<br>class LyricsData { ... }<br>```<br><br>**Do NOT delete** — keep in codebase temporarily for rollback safety. Deletion deferred to follow-up cleanup PR after 2-week stability window. | Mark models as deprecated after migration (no longer used), but keep for rollback safety. Deletion requires separate cleanup commit after verifying retrofit stability in production. |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| **`lib/main.dart`** | Initialization order must not change (Guardrails §1). No init changes required for this feature. |
| **`lib/app/constants/app_constants.dart`** | No new app-level constants required (ChordPro regex lives in parser service, not global constants). |
| **`lib/features/setlists/models/setlist_song.dart`**<br>**`lib/features/setlists/models/song.dart`** | Models treat `lyrics` as `String?` (no type change required). Plain-text ChordPro stores identically to JSON from model perspective. |
| **`lib/features/setlists/setlist_repository.dart`** | Repository already saves `lyrics` as TEXT via Supabase UPDATE or RPC. No new methods required. |
| **`lib/features/setlists/setlist_detail_screen.dart`**<br>**`lib/features/setlists/widgets/song_details_bottom_sheet.dart`** | These files call `showLyricsEditor()` and `showLyricsViewScreen()` — function signatures unchanged, no modifications required. |
| **`lib/features/setlists/widgets/reorderable_song_card.dart`**<br>**`lib/features/setlists/widgets/song_card.dart`** | Lyrics icon badge logic (`LyricsData.fromJsonString(song.lyrics).isNotEmpty`) will break post-migration. **Engineer must update** to check for non-empty plain text instead (e.g., `song.lyrics?.trim().isNotEmpty ?? false`). This is a required change, not off-limits — moved to "Files to Modify" table above. |
| **Supabase RLS policies** | No RLS changes required (existing policies already permit lyrics read/write for band members). |
| **Supabase RPC functions** | `update_song_metadata` already accepts `p_lyrics TEXT` — no signature changes required. |
| **Firebase, Edge Functions** | No provider integration, no Edge Functions required (manual-entry only). |

**Correction:** Add these to "Files to Modify" table:

| File | Changes | Rationale |
|------|---------|-----------|
| **`lib/features/setlists/widgets/reorderable_song_card.dart`** | **Replace:** `LyricsData.fromJsonString(song.lyrics).isNotEmpty`<br>**With:** `song.lyrics?.trim().isNotEmpty ?? false`<br><br>Context: Lyrics icon badge display logic (lines ~74). | Post-migration, `song.lyrics` is plain text (not JSON). Simple non-empty check suffices. Avoids calling deprecated `LyricsData` parser. |
| **`lib/features/setlists/widgets/song_card.dart`** | **Replace:** `LyricsData.fromJsonString(song.lyrics).isNotEmpty`<br>**With:** `song.lyrics?.trim().isNotEmpty ?? false`<br><br>Context: Lyrics icon badge display logic (lines ~44). | Same as above — plain-text check replaces JSON parser call. |

---

## System Impact Map

| System | Impact | Details |
|--------|--------|---------|
| **Gigs** | Unaffected | Gigs do not reference lyrics. |
| **Rehearsals** | Unaffected | Rehearsals do not reference lyrics. |
| **Setlists / Catalog** | **Affected** | Lyrics viewing/editing accessed via setlist song cards. Retrofit changes editor/viewer UI. Icon badge logic updated to check plain text. |
| **Members / RBAC** | Unaffected | Lyrics permissions unchanged (band members can read/write). |
| **Auth / Session** | Unaffected | No auth or session changes. |
| **Routing** | Unaffected | `showLyricsEditor()` and `showLyricsViewScreen()` remain modal/route patterns (no signature changes). |
| **Notifications** | Unaffected | No notification triggers for lyrics edits. |
| **Platform (iOS / Android / Web / macOS)** | **Affected** | All platforms show lyrics feature. Retrofit applies uniformly (no platform-specific code). SharedPreferences used for settings (works on all platforms). |
| **Database** | **Affected** | One-time data migration required (JSON → plain text). No schema changes. |
| **Bulk Entry** | Unaffected | Bulk entry does not populate lyrics. |
| **Enrichment** | Unaffected | Enrichment does not populate lyrics (no provider integration). |

---

## Regression Risk

**Level:** **MEDIUM**

**Rationale:**

**Risk Factors:**
1. **Data Migration:** Lossy conversion of 325 songs with existing lyrics. If migration SQL has bugs (e.g., text truncation, encoding issues), users lose data permanently. **Mitigation:** Manual SQL review by Tony, staging validation, backup before production execution.
2. **Breaking Change:** Users who relied on section formatting (colored backgrounds, section labels) will see plain text post-migration. This is expected and accepted by Tony, but may generate support inquiries. **Mitigation:** Release notes clearly communicate breaking change, explain ChordPro benefits.
3. **Icon Badge Regression:** If `reorderable_song_card.dart`, `song_card.dart`, `new_setlist_screen.dart` plain-text checks are missed, lyrics icon badges will disappear post-migration (false negative: song has lyrics but badge doesn't show). **Mitigation:** QA must verify icon badge visibility for migrated songs.
4. **ChordPro Parser Edge Cases:** Parser bugs (e.g., malformed brackets, unicode chords) could crash viewer or render incorrectly. **Mitigation:** Unit tests for parser, QA manual testing with edge cases (empty lines, no chords, many chords per line, unicode).

**Low-Risk Factors:**
- No auth/session/routing changes
- No RLS policy changes
- No new database schema (column already exists)
- No cross-feature dependencies (lyrics is isolated feature)
- Existing auto-scroll/font-size logic unchanged (reused as-is)

**Medium Confidence:** Migration + breaking change + parser complexity elevate risk above LOW, but isolated scope + no architectural changes keep it below HIGH.

---

## Engineer Task Breakdown

### Phase 1 — Pre-Implementation Validation

**Task 1.1:** Verify clean branch from synced `main`
- Confirm `git status --porcelain` is clean (untracked docs OK)
- Confirm `git log HEAD..origin/main` returns empty (local main is up-to-date)
- Create feature branch: `git checkout -b feature/lyrics-chordpro-retrofit`

**Task 1.2:** Audit existing lyrics usage
- Grep for `LyricsData` usage across codebase: `rg "LyricsData" --type dart`
- Confirm all usage points are in files listed in "Files to Modify" table
- Flag any unexpected usage to Architect for review

**Task 1.3:** Review migration SQL
- Read `database/maintenance/migrate_lyrics_to_chordpro.sql` (once created)
- Understand lossy conversion logic
- Identify pre-flight checks and post-flight validation queries
- Confirm backup requirement is documented

---

### Phase 2 — Create ChordPro Parser Service

**Task 2.1:** Implement `chordpro_parser.dart`
- Create `lib/features/lyrics/services/chordpro_parser.dart`
- Define `ChordAnnotation`, `ParsedLyricsLine` models
- Implement `ChordProParser.parse(String)`:
  - Split text into lines
  - For each line: Regex match `\[([^\]]+)\]`, extract chords with positions
  - Remove brackets from text, return `ParsedLyricsLine`
- Implement `ChordProParser.extractDirectives(String)` (unused in Phase 2.4, but scaffold for future)
- Edge cases:
  - Empty lines → return `ParsedLyricsLine` with empty text and chords
  - No chords → return line with empty chords list
  - Malformed brackets (`[Am` without `]`) → treat as literal text

**Task 2.2:** Unit test ChordPro parser (optional but recommended)
- Create `test/features/lyrics/services/chordpro_parser_test.dart`
- Test cases:
  - Plain text (no chords) → returns text unchanged
  - Single chord per line → extracts correctly
  - Multiple chords per line → preserves order
  - Chord at start of line → position = 0
  - Chord mid-word → position = character offset
  - Empty lines → returns empty `ParsedLyricsLine`
  - Malformed brackets → treated as literal text (no crash)

---

### Phase 3 — Retrofit Lyrics Editor

**Task 3.1:** Simplify `lyrics_editor_sheet.dart` state
- Remove `_HighlightedLyricsController` class (entire class)
- Replace with standard `TextEditingController`
- Remove `Map<int, LyricsHighlight> _blockHighlights` state variable
- Remove `_activeHighlight` state variable
- Remove `_prevText` snapshot logic
- Remove `_onHighlightTapped()` method
- Remove `_syncControllerHighlights()` method
- Remove `_adjustHighlightsForLineChanges()` method
- Remove `_blockIndexAtOffset()` helper

**Task 3.2:** Remove formatting toolbar
- Delete `_buildFormattingToolbar()` method
- Remove toolbar from `build()` Column (remove `_buildFormattingToolbar()` call)
- Remove font size ± constants (`_minFont`, `_maxFont`, `_fontStep`)
- Remove `_fontSize` state variable
- Simplify save logic:
  - Remove per-block highlight merging
  - Return plain text directly: `Navigator.of(context).pop(text.trim())`
  - No `LyricsData` construction — return plain `String`

**Task 3.3:** Update function signature
- Change `showLyricsEditor()` return type: `Future<String?>` (was `Future<LyricsData?>`)
- Change `initialData` parameter type: `String?` (was `LyricsData?`)
- Update editor initialization:
  - Initialize `_textController` with `initialData` plain text (no JSON parsing)

**Task 3.4:** Add ChordPro syntax helper
- Add `IconButton` to header row (between Cancel and Save):
  - Icon: `AppIcons.help` or `Icons.info_outline`
  - Color: `context.colors.textSecondary`
  - `onPressed`: Show `AlertDialog` with ChordPro help:
    ```dart
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('ChordPro Format'),
        content: Text(
          'Add chords by typing [Am] before a word.\n\n'
          'Example:\n'
          '[G]Hello [C]world\n\n'
          'Chords will appear above the lyrics when viewing.',
        ),
        actions: [
          TextButton(
            child: Text('Got it'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    ```

**Task 3.5:** Update call sites
- `song_details_bottom_sheet.dart` (~line 1860):
  - Change: `showLyricsEditor(context, initialData: LyricsData.fromJsonString(_currentLyrics))`
  - To: `showLyricsEditor(context, initialData: _currentLyrics)`
  - Update save handling: `final newLyrics = await showLyricsEditor(...); if (newLyrics != null) { setState(() => _currentLyrics = newLyrics); }`
- Grep for other call sites, update similarly (confirm with `rg "showLyricsEditor"`)

---

### Phase 4 — Retrofit Lyrics Viewer

**Task 4.1:** Add ChordPro parser integration
- Import `chordpro_parser.dart` at top of file
- Change `lyrics` parameter type in `showLyricsViewScreen()`: `required String lyrics` (was `required LyricsData lyrics`)
- Update `_LyricsViewScreen` constructor: `final String lyrics;` (was `final LyricsData lyrics;`)

**Task 4.2:** Replace section-based rendering with ChordPro rendering
- In `_buildLyricsContent()`:
  - Remove `LyricsBlock` iteration logic (was looping over `widget.lyrics.blocks`)
  - Parse lyrics: `final parsedLines = ChordProParser.parse(widget.lyrics);`
  - Render each `ParsedLyricsLine`:
    ```dart
    ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(Spacing.pagePadding),
      itemCount: parsedLines.length,
      itemBuilder: (context, i) {
        final line = parsedLines[i];
        return _buildLyricsLine(line);
      },
    )
    ```
- Implement `_buildLyricsLine(ParsedLyricsLine line)`:
  - If `line.text.isEmpty`: return `SizedBox(height: 16)` (blank line spacing)
  - Split text into words (by spaces)
  - For each word, check if a chord applies (match chord position to word offset)
  - Render `Wrap` of `Column` widgets:
    ```dart
    Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (var wordWithChord in wordsWithChords)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_chordsVisible && wordWithChord.chord != null)
                Text(
                  wordWithChord.chord!,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontSize: 12,
                  ),
                ),
              Text(
                wordWithChord.word,
                style: AppTextStyles.body.copyWith(
                  fontSize: _settings.fontSize,
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
      ],
    )
    ```
- **Note:** Chord-to-word alignment is non-trivial (chords can be mid-word, multiple chords per word). Architect recommends simple heuristic:
  - Split line into character offsets
  - For each chord, find the word that starts closest to (but not after) the chord position
  - Render chord above that word
  - If multiple chords apply to same word, stack them vertically or join with `/`

**Task 4.3:** Add chords-on/off toggle
- Add `_chordsVisible` state variable (bool, default from global settings):
  ```dart
  bool _chordsVisible = true;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadChordsVisible(); // NEW
  }
  
  Future<void> _loadChordsVisible() async {
    final visible = await LyricsViewSettingsService.loadChordsVisible();
    if (!mounted) return;
    setState(() => _chordsVisible = visible);
  }
  ```
- Add toggle switch to `_buildTopBar()`:
  - Position: Between song title and font size buttons
  - UI:
    ```dart
    Row(
      children: [
        Text(
          'Chords',
          style: AppTextStyles.caption.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: _chordsVisible,
          onChanged: (value) async {
            setState(() => _chordsVisible = value);
            await LyricsViewSettingsService.saveChordsVisible(value);
          },
          activeColor: AppColors.primary,
        ),
      ],
    )
    ```

**Task 4.4:** Update call sites
- `setlist_detail_screen.dart` (~line 648):
  - Change: `showLyricsViewScreen(context, lyrics: LyricsData.fromJsonString(song.lyrics), ...)`
  - To: `showLyricsViewScreen(context, lyrics: song.lyrics ?? '', ...)`
- `new_setlist_screen.dart` (if lyrics view called from there):
  - Same pattern: pass `song.lyrics ?? ''` instead of parsed `LyricsData`

---

### Phase 5 — Extend Settings Service

**Task 5.1:** Add `chordsVisible` to `LyricsViewSettings` model
- In `lyrics_view_settings_service.dart`:
  - Add field to class: `final bool chordsVisible;` (default `true` in constructor)
  - Update `toJson()`: add `'chordsVisible': chordsVisible`
  - Update `fromJson()`: add `chordsVisible: json['chordsVisible'] as bool? ?? true`
  - Update `copyWith()`: add `chordsVisible` parameter

**Task 5.2:** Add global chords-visible persistence methods
- Add methods:
  ```dart
  static Future<bool> loadChordsVisible() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('lyrics_view_chords_visible_global') ?? true;
  }
  
  static Future<void> saveChordsVisible(bool visible) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lyrics_view_chords_visible_global', visible);
  }
  ```

---

### Phase 6 — Update Icon Badge Logic

**Task 6.1:** Update `reorderable_song_card.dart`
- Find lyrics icon badge logic (~line 74)
- Replace:
  ```dart
  final lyrics = LyricsData.fromJsonString(song.lyrics);
  if (lyrics.isNotEmpty) { ... }
  ```
- With:
  ```dart
  if (song.lyrics?.trim().isNotEmpty ?? false) { ... }
  ```

**Task 6.2:** Update `song_card.dart`
- Same pattern as 6.1 (~line 44)

---

### Phase 7 — Deprecate Old Models

**Task 7.1:** Add `@Deprecated` annotations
- In `lyrics_data.dart`:
  - Add to `LyricsHighlight` enum: `@Deprecated('Use plain-text ChordPro format. Kept for rollback safety post-migration.')`
  - Add to `LyricsBlock` class: Same deprecation message
  - Add to `LyricsData` class: Same deprecation message
- **Do not delete** — models must remain in codebase for rollback safety

---

### Phase 8 — Create Migration Script

**Task 8.1:** Write migration SQL
- Create `database/maintenance/migrate_lyrics_to_chordpro.sql`
- Copy SQL from "Database Impact" section above (complete script with pre-flight checks, backup, logging, validation)
- Add header comment with:
  - Purpose: Lossy conversion, JSON → plain-text ChordPro
  - Pre-flight requirements: Backup, staging validation, affected row count
  - Execution instructions: `psql` command
  - Post-flight validation: Query for null lyrics, sample inspection

**Task 8.2:** Document migration in ENGINEER_REPORT.md
- Section: "Database Migration"
- Include:
  - Affected row count (run `SELECT COUNT(*) FROM songs WHERE lyrics IS NOT NULL` against staging)
  - Sample conversions (first 3 songs, before/after text)
  - Execution steps for Tony
  - Rollback strategy (restore from backup)

---

### Phase 9 — Testing & QA Handoff

**Task 9.1:** Run `flutter analyze`
- Confirm 0 errors
- Confirm deprecation warnings for `LyricsData` usage are expected (only in deprecated model file itself)

**Task 9.2:** Manual smoke testing (on macOS or web)
- **Editor:**
  - Open song, tap "Edit Lyrics"
  - Enter plain text with chords: `[G]Hello [C]world`
  - Save → confirm saves to DB
  - Reopen editor → confirm text preserved
  - Tap help icon → confirm ChordPro help dialog appears
- **Viewer:**
  - Open song with chords, tap "View Lyrics"
  - Confirm chords render above lyrics text (rose color, small font)
  - Toggle chords off → confirm chords disappear, lyrics remain
  - Toggle chords on → confirm chords reappear
  - Test auto-scroll → confirm works as before
  - Test font size ± → confirm works as before
- **Icon badge:**
  - Song with lyrics → confirm lyrics icon badge shows on song card
  - Song without lyrics → confirm no icon badge
- **Migration (staging only):**
  - Run migration SQL against staging DB
  - Query migrated songs → confirm plain-text format
  - Open 5 migrated songs in viewer → confirm lyrics render correctly (no truncation, line breaks preserved)

**Task 9.3:** Generate git diff
- Run: `git diff main > /tmp/lyrics-chordpro-retrofit.diff`
- Attach to ENGINEER_REPORT.md or save as separate file in feature docs directory

**Task 9.4:** Write ENGINEER_REPORT.md
- Sections:
  1. Summary of Changes (files modified, new files created)
  2. Database Migration (SQL script location, execution steps, affected row count)
  3. Testing Results (smoke test outcomes, screenshots optional)
  4. Known Issues / Deviations from Plan (if any)
  5. QA Checklist (test cases for QA to verify)

**Task 9.5:** Commit and push
- Commit message: `feat(lyrics): Retrofit lyrics feature to ChordPro format with chord visibility toggle`
- Push: `git push origin feature/lyrics-chordpro-retrofit`
- Open PR (if applicable)

---

## Verification Plan

**Tier 1 — Pre-Deployment (must pass before Flutter deployment)**

**PRE-DEPLOY TEST 1: Migration SQL Validation (Staging)**
```sql
-- Run against staging DB first
-- Confirm migration SQL executes without errors
-- Verify affected row count matches expectation (~325 songs)
SELECT COUNT(*) FROM songs WHERE lyrics IS NOT NULL;
\i database/maintenance/migrate_lyrics_to_chordpro.sql
-- Post-migration: verify no songs lost lyrics
SELECT COUNT(*) FROM songs WHERE lyrics IS NOT NULL;
-- Spot-check 5 random songs
SELECT id, title, artist, left(lyrics, 200) AS lyrics_preview
FROM songs
WHERE lyrics IS NOT NULL
ORDER BY random()
LIMIT 5;
```
**Expected:** All songs with non-null lyrics before migration still have non-null lyrics after. Text preview shows plain text (no JSON), line breaks preserved.

**PRE-DEPLOY TEST 2: Migration SQL Dry-Run Validation**
```sql
-- Confirm backup table creation works
-- Confirm JSON parsing logic handles all existing formats
-- Run migration in transaction, then ROLLBACK (dry-run)
BEGIN;
\i database/maintenance/migrate_lyrics_to_chordpro.sql
ROLLBACK;
```
**Expected:** Migration executes without errors, ROLLBACK restores original JSON.

**PRE-DEPLOY TEST 3: Production Backup Verification**
- Tony confirms production `songs` table backup exists (pg_dump or Supabase dashboard export)
- Backup includes all rows with non-null `lyrics`
- Backup is restorable (spot-check restore to test DB)

**Expected:** Backup is complete and restorable.

---

**Tier 2 — Post-Deployment (run after Flutter deployment succeeds)**

**POST-DEPLOY TEST 1: ChordPro Parser Correctness**
- Open 5 songs with manually-entered chords in viewer
- Verify chords render above correct words
- Verify chord color is rose (`AppColors.primary`)
- Verify chord font size is smaller than lyrics text
- Toggle chords off → verify chords disappear, lyrics remain
- Toggle chords on → verify chords reappear

**Expected:** Chords align correctly with lyrics text, toggle works in both directions.

**POST-DEPLOY TEST 2: Editor Simplification**
- Open lyrics editor
- Verify formatting toolbar is removed (no font size ±, no bold, no color chips)
- Tap help icon → verify ChordPro help dialog appears with correct text
- Enter plain text with chords → save → reopen → verify text preserved

**Expected:** Editor is plain-text only, help dialog appears, save/load works correctly.

**POST-DEPLOY TEST 3: Icon Badge Regression Check**
- Song with lyrics → verify lyrics icon badge shows on song card (all 3 card types: `song_card.dart`, `reorderable_song_card.dart`, `new_setlist_screen.dart`)
- Song without lyrics → verify no icon badge

**Expected:** Icon badges appear correctly for songs with lyrics, absent for songs without.

**POST-DEPLOY TEST 4: Migrated Songs Verification**
- Open 10 randomly selected songs that had JSON lyrics pre-migration
- Verify lyrics text is correct (no truncation, no encoding issues)
- Verify line breaks are preserved (paragraphs intact)
- Verify no JSON artifacts remain (no `{`, `}`, `"blocks"` strings)

**Expected:** Migrated songs display correctly as plain text, no data loss or corruption.

**POST-DEPLOY TEST 5: Settings Persistence**
- Toggle chords off in viewer → close app → reopen same song → verify chords remain off
- Adjust font size → close app → reopen → verify font size persisted
- Toggle chords on → verify persists across app restarts

**Expected:** `chordsVisible` global setting persists correctly, per-song settings (font size, auto-scroll) persist correctly.

**POST-DEPLOY TEST 6: Cross-Platform Validation**
- Test on iOS, Android, Web, macOS (all supported platforms)
- Verify ChordPro rendering is consistent (chords above lyrics, rose color)
- Verify toggle works on all platforms
- Verify SharedPreferences persistence works on all platforms

**Expected:** Feature works identically across all platforms, no platform-specific regressions.

**POST-DEPLOY TEST 7: Edge Cases**
- Song with no chords (plain text) → verify renders normally, toggle has no visible effect
- Song with empty lyrics (`""` or `null`) → verify no crash, no icon badge
- Song with malformed brackets (`[Am` without closing) → verify treated as literal text, no crash
- Song with unicode chords (e.g., `[Amin♭]`) → verify renders correctly (no encoding issues)

**Expected:** All edge cases handled gracefully, no crashes or corrupted rendering.

---

## Additional Context

**Phase 2.5 (Future, Out of Scope):**
- **Musixmatch Lyrics-Text-Only Auto-Fetch** (optional future enhancement)
- Requires: Licensing resolution (paid partnership or free-tier-only release), attribution UI, Edge Function
- Would provide "Fetch Lyrics Text" button (similar to existing "Enrich Song Data")
- Populates `songs.lyrics` with plain-text lyrics (no chords) from Musixmatch API
- User can then manually add `[Chord]` annotations via editor
- **Do NOT implement in Phase 2.4** — manual-entry only per Tony's confirmed scope

**Follow-Up Cleanup (Post-Stability Window):**
- After 2-week production stability window, create follow-up PR to delete deprecated `LyricsData`/`LyricsBlock`/`LyricsHighlight` classes
- Confirm zero usage via grep before deletion: `rg "LyricsData|LyricsBlock|LyricsHighlight" --type dart`
- Delete `lib/features/lyrics/models/lyrics_data.dart` entirely

**Known Limitations:**
- ChordPro section directives (`{start_of_chorus}`, etc.) are parsed but not rendered in Phase 2.4 viewer (future extensibility)
- Chord-to-word alignment heuristic is approximate (mid-word chords may misalign) — acceptable for manual-entry use case, refineable in future
- No chord transposition support (future Phase 2.6 candidate)

---

**Plan Authored By:** Architect Agent  
**Date:** 2026-08-10  
**Approved By:** Pending Tony review  
**Feature Branch:** `feature/lyrics-chordpro-retrofit` (to be created)
