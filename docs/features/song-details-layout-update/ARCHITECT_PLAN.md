# ARCHITECT_PLAN.md

## Feature Slug
`feature/song-details-layout-update`

## Feature Title
Update Song Details Field Layout

---

## Problem Summary

The Song Details bottom sheet (`_SongDetailsSheet`) presents fields in a layout that does not match the approved designer mock. Specifically:

1. The metadata row is **3 columns** (BPM / Duration / Tuning) instead of **4** — the musical key field is missing entirely.
2. The action buttons row ("Add Lyrics", "Add YouTube") uses plain inline links, not the equal-width outlined rose-button style with icons.
3. A "+ Add Notes" button is absent — Notes is always-visible as a large textarea rather than a button-triggered edit.
4. The `musical_key` field does not exist in the database, the Dart models, or the RPC.

This is a **layout + persistence** change. The Key field must be added end-to-end before the 4-column metadata row can be assembled.

---

## Root Cause

**Confidence: HIGH** (confirmed by code and migration inspection)

The `songs` table has no `musical_key` (or equivalent) column. No migration introducing it was found in `supabase/migrations/`. Neither the `Song` model (`lib/features/setlists/models/song.dart`) nor `SetlistSong` (`lib/features/setlists/models/setlist_song.dart`) carries a musical key field. The `SongDetailsResult`, `_SongDetailsSheetState`, the `update_song_metadata` RPC, and the fetch join in `SetlistRepository.fetchSongsForSetlist` all lack it.

The UI layout issues are secondary consequences: the 4-column row cannot be built until the data layer exists.

---

## Reference Docs Consulted

No `docs/reference/setlists/` or `docs/reference/songs/` directory exists. Domain knowledge was derived directly from the codebase.

---

## Existing System Analysis

### Data flow (read)
```
Supabase songs table
  → fetchSongsForSetlist() (SetlistRepository, line 608)
    → nested join: setlist_songs JOIN songs (fields: id, title, artist, bpm,
      duration_seconds, tuning, album_artwork, notes, youtube_links, lyrics)
    → SetlistSong.fromSupabase()
  → SetlistDetailController state
  → SetlistDetailScreen._handleSongTap()
    → showSongDetailsBottomSheet(song: SetlistSong)
      → _SongDetailsSheet (displays fields)
```

### Data flow (write — Song Details save)
```
_SongDetailsSheetState._handleSave()
  → Navigator.pop(SongDetailsResult)
SetlistDetailScreen._handleSongTap() receives result
  → notifier.updateSongTitleArtist()   [if titleChanged || artistChanged]
  → notifier.updateSongBpm()           [if bpmChanged]
  → notifier.clearSongBpm()            [if bpmChanged && bpm == null]
  → notifier.updateSongDuration()      [if durationChanged]
  → notifier.updateSongNotes()         [if notesChanged]
  → notifier.updateSongTuning()        [if tuningChanged]
  → notifier.updateSongYoutubeLinks()  [if youtubeLinksChanged]
  → notifier.updateSongLyrics()        [if lyricsChanged]
Each notifier method calls SetlistRepository.update*() → supabase.rpc('update_song_metadata', params: {...})
```

### RPC signature (current, 10 parameters)
```sql
update_song_metadata(
  p_song_id UUID, p_band_id UUID,
  p_bpm INTEGER, p_duration_seconds INTEGER,
  p_tuning TEXT, p_notes TEXT,
  p_title TEXT, p_artist TEXT,
  p_youtube_links TEXT, p_lyrics TEXT
) RETURNS JSON
```
All Dart callers pass **all 10 parameters by name** to avoid PGRST203 overload ambiguity. Adding `p_musical_key` as an 11th parameter must drop and recreate the function with all 11 parameters.

### Current UI structure of `_SongDetailsSheet`
| Section | Current | Target |
|---------|---------|--------|
| Song Title | full-width tap-to-edit field | **no change** |
| Artist / Band | full-width tap-to-edit field | **no change** |
| Metrics row | 3-col: BPM / Duration / Tuning | **4-col: BPM / Duration / Tuning / Key** |
| Action row | 2 plain inline text+icon links | **3 equal-width outlined rose buttons** |
| Notes | always-visible textarea (180px min) | **button-triggered, preview-when-set** |
| Save | full-width filled rose | **no change** |
| Cancel | full-width text | **no change** |

---

## Proposed Solution

### Scope: Layout + Persistence

**Step 1 — DB migration** (`musical_key` column)  
Add `musical_key TEXT` to `songs` table. No CHECK constraint — values are enforced by the client-side dropdown picker. No NOT NULL — existing rows can be NULL.

**Step 2 — RPC migration** (`update_song_metadata`)  
Drop the existing 10-parameter function and recreate with an 11th parameter `p_musical_key TEXT DEFAULT NULL`. The UPDATE logic follows the same CASE-when-not-null pattern used by `p_notes`. All Dart callers must be updated to pass all 11 parameters.

**Step 3 — Model updates**  
Add `String? musicalKey` to `Song` and `SetlistSong`. Update `fromSupabase` factories. Add `clearMusicalKey` to `SetlistSong.copyWith`.

**Step 4 — Repository updates**  
- `fetchSongsForSetlist`: add `musical_key` to the nested songs join field list.
- Add `updateSongMusicalKey({bandId, songId, musicalKey})` method following the same pattern as `updateSongTuningOverride`.
- Update **all existing** `update_song_metadata` RPC call sites to pass `p_musical_key: null` (11 total params) to prevent PGRST203 overload errors.

**Step 5 — Result + state wiring**  
Add `musicalKey` and `musicalKeyChanged` to `SongDetailsResult`. Add `String? _currentMusicalKey` and `_originalMusicalKey` to `_SongDetailsSheetState`.

**Step 6 — Controller**  
Add `updateSongMusicalKey(String songId, String? musicalKey)` to `SetlistDetailController`.

**Step 7 — Screen handler**  
In `SetlistDetailScreen._handleSongTap`, add handler for `result.musicalKeyChanged`.

**Step 8 — UI layout**  
In `song_details_bottom_sheet.dart`:
1. Extend `_buildMetricsRow()` to a 4-column row, adding Key as the 4th column. Key renders as a `GestureDetector` container with a chevron icon (identical pattern to Tuning). Tapping opens a `_showKeyPicker()` which uses `showDialog` with a scrollable `ListView` of 24 standard musical key values.
2. Replace `_buildAddButtonsRow()` with a 3-button equal-width row: **+ Add Lyrics** (music-note icon) | **+ Add YouTube** (play icon) | **+ Add Notes** (file-text icon). Each button is an `Expanded` `OutlinedButton`-style `Container` with `border: Border.all(color: AppColors.primary)`, `borderRadius: Spacing.buttonRadius`, and rose text/icon.
3. Move Notes editing behind `_isEditingNotes` bool. When `_isEditingNotes` is true, show the inline `TextField` (existing `_notesController`). When false and notes non-empty, show a preview card (tappable to enter edit mode, same style as `_buildLyricsPreview`). When false and notes empty, nothing is shown below the 3-button row (the button itself is the affordance).
4. Remove the always-visible Notes label + textarea block that currently closes `_buildNotesSection()`.

**Step 9 — AppIcons**  
Add `static const IconData noteFile = LucideIcons.fileText;` to `AppIcons` for the Notes button icon.

### Musical key value set
Stored as plain text. The picker shows 24 values in two groups:

Major: `C`, `C#`, `D`, `Eb`, `E`, `F`, `F#`, `G`, `Ab`, `A`, `Bb`, `B`  
Minor: `Cm`, `C#m`, `Dm`, `Ebm`, `Em`, `Fm`, `F#m`, `Gm`, `Abm`, `Am`, `Bbm`, `Bm`

Display: the picker shows the stored string as-is (e.g., "C#", "Ebm"). The dropdown container shows `_currentMusicalKey ?? '—'` with a chevron.

### Narrow-screen (≤375pt) wrapping
The 4-column metadata row uses `Expanded` for each column (identical to the existing 3-column row). At 375pt − 32pt padding = 343pt content, each column is ≈73pt. Tuning and Key labels are clipped with `overflow: TextOverflow.ellipsis`. The 3-button action row also uses `Expanded` per button. No special wrapping code is needed — Flutter's `Expanded` handles this correctly.

---

## Database Impact

| Area | Status |
|------|--------|
| `songs` table schema | **affected** — new `musical_key TEXT` column |
| `update_song_metadata` RPC | **affected** — 11th parameter added; drop-and-recreate required |
| RLS policies | **unaffected** — no policy changes |
| `setlist_songs` table | **unaffected** |
| `setlists` table | **unaffected** |
| Triggers | **unaffected** |
| Other RPCs | **unaffected** |

**Migration required: YES**  
Two migration files (see Files to Create).

---

## Flutter Architecture Changes

| Layer | Change |
|-------|--------|
| `Song` model | Add `musicalKey` field, update `fromSupabase` |
| `SetlistSong` model | Add `musicalKey` field, update `fromSupabase`, update `copyWith` |
| `SongDetailsResult` | Add `musicalKey`, `musicalKeyChanged` fields |
| `_SongDetailsSheetState` | Add `_currentMusicalKey`, `_originalMusicalKey`; new `_showKeyPicker()`, `_buildKeyDropdown()`; refactor `_buildMetricsRow`, `_buildNotesSection`, `_buildAddButtonsRow` |
| `SetlistRepository` | Add `musical_key` to join, add `updateSongMusicalKey`, update all 10 existing RPC call sites to pass 11 params |
| `SetlistDetailController` | Add `updateSongMusicalKey` method |
| `SetlistDetailScreen` | Handle `result.musicalKeyChanged` in `_handleSongTap` |
| `AppIcons` | Add `noteFile = LucideIcons.fileText` |

---

## Files to Create

| File | Justification |
|------|---------------|
| `supabase/migrations/20260630000000_add_musical_key_to_songs.sql` | Add `musical_key TEXT` column to `songs` table |
| `supabase/migrations/20260630000001_add_musical_key_to_update_song_rpc.sql` | Drop and recreate `update_song_metadata` with 11th parameter `p_musical_key` |

---

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/setlists/models/song.dart` | Add `String? musicalKey` field; update constructor, `fromSupabase` |
| `lib/features/setlists/models/setlist_song.dart` | Add `String? musicalKey` field; update constructor, `fromSupabase`, `copyWith` |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Add Key state + picker; extend metrics row to 4-col; redesign action buttons row to 3 equal-width outlined rose buttons; convert Notes from always-visible textarea to button-triggered preview pattern; wire musical key into `SongDetailsResult` |
| `lib/features/setlists/setlist_repository.dart` | Add `musical_key` to `fetchSongsForSetlist` join; add `updateSongMusicalKey`; update all existing `update_song_metadata` RPC calls to 11 params |
| `lib/features/setlists/setlist_detail_controller.dart` | Add `updateSongMusicalKey` |
| `lib/features/setlists/setlist_detail_screen.dart` | Handle `result.musicalKeyChanged` in `_handleSongTap` |
| `lib/app/theme/app_icons.dart` | Add `noteFile = LucideIcons.fileText` |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/main.dart` | Init order must not change (Guardrail §1) |
| `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` | Tuning picker is unchanged; Key uses its own inline picker |
| `lib/features/setlists/widgets/masked_duration_input.dart` | Duration widget unchanged |
| `lib/features/setlists/widgets/action_buttons_row.dart` | This is the Catalog/setlist action row, not the song-details action row |
| All files not listed under Files to Modify | No opportunistic changes |

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | affected — song fetch and update paths extended |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — all platforms render the new layout |

---

## Regression Risk

**LOW**

- The `update_song_metadata` RPC change is additive (new optional parameter with DEFAULT NULL). Existing callers that do not pass `p_musical_key` will still resolve correctly once all Dart call sites are updated to pass the 11th param explicitly.
- The fetch join change adds one column; `SetlistSong.fromSupabase` already tolerates missing optional fields.
- Notes behavior change is UI-only and confined to `song_details_bottom_sheet.dart`. The underlying `_notesController` and `updateSongNotes` path are unchanged.
- No auth, session, routing, or init order changes.
- The only moderate risk is the PGRST203 overload window: between deploying the new RPC (11 params) and deploying the new Dart client code (calling with 11 params), callers sending 10 params will hit a PGRST203 ambiguity error if the old 10-param function is already dropped. **Mitigation**: the migration drops the 10-param signature and creates only the 11-param signature; the Dart client update must ship in the same release as the migration.

---

## Engineer Task Breakdown

Execute in order. Each task must be complete and verified before proceeding.

**Task 1 — DB migration: add `musical_key` column**
File: `supabase/migrations/20260630000000_add_musical_key_to_songs.sql`

```sql
-- Add musical_key column to songs table.
-- Nullable TEXT — no CHECK constraint; values validated by client-side picker.
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS musical_key TEXT;

COMMENT ON COLUMN public.songs.musical_key IS
  'Musical key of the song (e.g. "C#", "Ebm"). Nullable free-text validated by client.';
```

**Task 2 — DB migration: update `update_song_metadata` RPC**
File: `supabase/migrations/20260630000001_add_musical_key_to_update_song_rpc.sql`

Drop the existing 10-parameter function and recreate with 11 parameters. The `musical_key` column follows the same update-when-not-null CASE pattern as `notes`. Grant `EXECUTE` to `authenticated` on the new 11-parameter signature.

```sql
-- Drop existing 10-parameter signature to avoid PGRST203 overload conflict
DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION update_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_bpm INTEGER DEFAULT NULL,
  p_duration_seconds INTEGER DEFAULT NULL,
  p_tuning TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL,
  p_youtube_links TEXT DEFAULT NULL,
  p_lyrics TEXT DEFAULT NULL,
  p_musical_key TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_is_member BOOLEAN;
  v_song_band_id UUID;
  v_update_count INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id AND user_id = v_user_id AND status = 'active'
  ) INTO v_is_member;

  IF NOT v_is_member THEN
    RETURN json_build_object('success', false, 'error', 'Access denied: not an active member of this band');
  END IF;

  SELECT band_id INTO v_song_band_id FROM songs WHERE id = p_song_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Song not found');
  END IF;

  IF v_song_band_id IS NOT NULL AND v_song_band_id != p_band_id THEN
    RETURN json_build_object('success', false, 'error', 'Song belongs to a different band');
  END IF;

  UPDATE songs
  SET
    bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END,
    duration_seconds = COALESCE(p_duration_seconds, duration_seconds),
    tuning = COALESCE(p_tuning, tuning),
    notes = CASE WHEN p_notes IS NOT NULL THEN p_notes ELSE notes END,
    title = COALESCE(p_title, title),
    artist = COALESCE(p_artist, artist),
    youtube_links = CASE WHEN p_youtube_links IS NOT NULL THEN p_youtube_links ELSE youtube_links END,
    lyrics = CASE WHEN p_lyrics IS NOT NULL THEN p_lyrics ELSE lyrics END,
    musical_key = CASE WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END,
    updated_at = NOW()
  WHERE id = p_song_id;

  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION update_song_metadata IS
  'Update song metadata including musical key. BPM only updates when currently NULL. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';
```

> **IMPORTANT**: `musical_key` uses the same CASE-when-not-null pattern as `notes` and `lyrics`, NOT the COALESCE pattern. This allows clearing the key by passing an explicit non-null empty string. To clear the key, pass `p_musical_key: ''` and handle the empty string as NULL in the Dart layer — OR pass `p_musical_key: null` to leave it unchanged. The Engineer must decide the clearing strategy; recommendation is to treat empty string from the picker as NULL before passing to the RPC.

**Task 3 — Model: `Song`**
File: `lib/features/setlists/models/song.dart`

- Add `final String? musicalKey;` to the class fields and constructor.
- In `Song.fromSupabase`: add `musicalKey: json['musical_key'] as String?,`

**Task 4 — Model: `SetlistSong`**
File: `lib/features/setlists/models/setlist_song.dart`

- Add `final String? musicalKey;` to the class fields and constructor.
- Update the DATA MAPPING comment block to include `songs.musical_key -> musicalKey`.
- In `SetlistSong.fromSupabase`: add `musicalKey: songData['musical_key'] as String?,`
- In `SetlistSong.copyWith`: add `String? musicalKey, bool clearMusicalKey = false` parameter and handle: `musicalKey: clearMusicalKey ? null : (musicalKey ?? this.musicalKey),`

**Task 5 — Repository: fetch join + new update method + RPC call site updates**
File: `lib/features/setlists/setlist_repository.dart`

5a. In `fetchSongsForSetlist` (around line 608), add `musical_key` to the nested songs field list:
```dart
songs!inner (
  id, title, artist, bpm, duration_seconds, tuning,
  album_artwork, notes, youtube_links, lyrics, musical_key
)
```

5b. Add `updateSongMusicalKey` method following the same pattern as `updateSongTuningOverride`. The method:
- Accepts `bandId`, `songId`, `musicalKey` (nullable String)
- Calls `supabase.rpc('update_song_metadata', params: { ...all 11 params, 'p_musical_key': musicalKey })`
- Falls back to direct `supabase.from('songs').update({'musical_key': musicalKey}).eq('id', songId)` on PGRST202/42883

5c. **Update all existing `update_song_metadata` RPC call sites** to pass the new 11th parameter `'p_musical_key': null`. There are 7 call sites in `setlist_repository.dart`:
- `updateSongBpmOverride` (line ~1486)
- `updateSongDurationOverride` (line ~1651)
- `updateSongTuningOverride` (line ~1751)
- `updateSongNotes` (line ~1861)
- `updateSongYoutubeLinks` fallback (line ~1968)
- `updateSongLyrics` fallback (line ~2036)
- `updateSongTitleArtist` (line ~2099)

Each must add `'p_musical_key': null,` to its params map.

**Task 6 — Controller: add `updateSongMusicalKey`**
File: `lib/features/setlists/setlist_detail_controller.dart`

Add `Future<bool> updateSongMusicalKey(String songId, String? musicalKey)` following the exact same structure as `updateSongNotes`. Updates the in-memory `SetlistSong` via `state.songs` copyWith, then calls `_repository.updateSongMusicalKey(...)`.

**Task 7 — AppIcons: add Notes icon**
File: `lib/app/theme/app_icons.dart`

Under the Music / Setlists section, add:
```dart
static const IconData noteFile = LucideIcons.fileText;
```

**Task 8 — UI: `SongDetailsResult` and `_SongDetailsSheet` full rewrite of affected methods**
File: `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

8a. `SongDetailsResult`: add `String? musicalKey` and `bool musicalKeyChanged = false` fields.

8b. `_SongDetailsSheetState`: add state fields:
```dart
late String? _currentMusicalKey;
late String? _originalMusicalKey;
bool _isEditingNotes = false;
```

Initialize in `initState`:
```dart
_originalMusicalKey = widget.song.musicalKey;
_currentMusicalKey = widget.song.musicalKey;
```

8c. Update `_checkForChanges` and `_handleSave` to include `musicalKeyChanged = _currentMusicalKey != _originalMusicalKey`.

8d. Replace `_buildMetricsRow()` to a 4-column row. Add Key as 4th column using identical container style to Tuning (background, rounded border, chevron icon). Tapping calls `_showKeyPicker()`.

8e. Implement `_showKeyPicker()`:
```dart
Future<void> _showKeyPicker() async {
  // showDialog with ListView of 24 key values in two groups: Major + Minor
  // On selection: setState(() { _currentMusicalKey = selected; }); _checkForChanges();
}
```
The key list (const, define at top of file):
```dart
const _kMajorKeys = ['C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'];
const _kMinorKeys = ['Cm','C#m','Dm','Ebm','Em','Fm','F#m','Gm','Abm','Am','Bbm','Bm'];
```

8f. Replace `_buildAddButtonsRow()` with a 3-button equal-width row:
```
[Expanded: + Add Lyrics] [SizedBox(8)] [Expanded: + Add YouTube] [SizedBox(8)] [Expanded: + Add Notes]
```
Each button is a `GestureDetector` wrapping a `Container` with:
- `decoration: BoxDecoration(border: Border.all(color: AppColors.primary, width: 1.5), borderRadius: BorderRadius.circular(Spacing.buttonRadius))`
- `padding: EdgeInsets.symmetric(vertical: 10)`
- Contents: centered `Column` or `Row` with icon + label text (rose color, 12pt, FontWeight.w600)
- Lyrics: `AppIcons.music` icon, label "Add Lyrics" (or "Edit Lyrics" if lyrics exist)
- YouTube: `AppIcons.play` icon, label "Add YouTube"
- Notes: `AppIcons.noteFile` icon, label "Add Notes" (or "Edit Notes" if notes non-empty)

8g. Restructure `_buildNotesSection()`: remove the always-visible Notes label + TextField block. Replace with:
- If `_isEditingNotes`: show the Notes label + inline TextField (existing `_notesController`, `minLines: 6`, no change to controller logic) + a small "Done" `TextButton` that sets `_isEditingNotes = false`
- If `!_isEditingNotes` and notes non-empty: show a notes preview card (same style as `_buildLyricsPreview`, tap to re-enter edit mode)
- If `!_isEditingNotes` and notes empty: show nothing (button row handles empty state)

The `+ Add Notes` / `+ Edit Notes` button in the row should call:
```dart
setState(() => _isEditingNotes = true);
```
(Not a modal; inline expansion.)

8h. Update `_handleSave` to populate `musicalKey` and `musicalKeyChanged` in `SongDetailsResult`.

**Task 9 — Screen: handle `musicalKeyChanged`**
File: `lib/features/setlists/setlist_detail_screen.dart`

In `_handleSongTap`, after the `lyricsChanged` block, add:
```dart
if (result.musicalKeyChanged) {
  final success = await notifier.updateSongMusicalKey(song.id, result.musicalKey);
  debugPrint('[SetlistDetail] Musical key save result: $success');
}
```

---

## Verification Plan

### Tier 1 — Pre-deployment (run before `supabase db push`)

These tests operate against the **current** schema (no `musical_key` column yet). They verify helpers and supporting infrastructure.

```sql
-- PRE-DEPLOY TEST 1: Confirm songs table currently lacks musical_key
-- Expected: 0 rows (column does not exist)
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'songs'
  AND column_name  = 'musical_key';

-- PRE-DEPLOY TEST 2: Confirm update_song_metadata currently has exactly 10 parameters
-- Expected: exactly 1 row with parameter_count = 10
SELECT routine_name,
       (SELECT count(*) FROM information_schema.parameters p
        WHERE p.specific_name = r.specific_name
          AND p.parameter_mode = 'IN') AS parameter_count
FROM information_schema.routines r
WHERE routine_schema = 'public'
  AND routine_name = 'update_song_metadata';

-- PRE-DEPLOY TEST 3: Confirm authenticated role has EXECUTE on current RPC
-- Expected: 1 row
SELECT has_function_privilege('authenticated',
  'public.update_song_metadata(uuid,uuid,integer,integer,text,text,text,text,text,text)',
  'EXECUTE') AS has_exec;
```

### Tier 2 — Post-deployment (run after `supabase db push`)

```sql
-- POST-DEPLOY TEST 1: Confirm musical_key column exists
-- Expected: 1 row, data_type = 'text', is_nullable = 'YES'
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'songs'
  AND column_name  = 'musical_key';

-- POST-DEPLOY TEST 2: Confirm old 10-parameter function is gone
-- Expected: 0 rows
SELECT specific_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'update_song_metadata'
  AND (SELECT count(*) FROM information_schema.parameters p
       WHERE p.specific_name = routines.specific_name
         AND p.parameter_mode = 'IN') = 10;

-- POST-DEPLOY TEST 3: Confirm new 11-parameter function exists
-- Expected: 1 row
SELECT specific_name
FROM information_schema.routines r
WHERE routine_schema = 'public'
  AND routine_name = 'update_song_metadata'
  AND (SELECT count(*) FROM information_schema.parameters p
       WHERE p.specific_name = r.specific_name
         AND p.parameter_mode = 'IN') = 11;

-- POST-DEPLOY TEST 4: Confirm p_musical_key is the 11th parameter
-- Expected: 1 row, ordinal = 11, data_type = text
SELECT parameter_name, ordinal_position, data_type
FROM information_schema.parameters p
JOIN information_schema.routines r
  ON r.specific_name = p.specific_name
WHERE r.routine_schema = 'public'
  AND r.routine_name   = 'update_song_metadata'
  AND p.parameter_name = 'p_musical_key';

-- POST-DEPLOY TEST 5: Confirm authenticated role has EXECUTE on new signature
-- Expected: true
SELECT has_function_privilege('authenticated',
  'public.update_song_metadata(uuid,uuid,integer,integer,text,text,text,text,text,text,text)',
  'EXECUTE') AS has_exec;

-- POST-DEPLOY TEST 6: Smoke-test musical_key round-trip
-- Writes and reads back a musical_key value using a real song in the band.
-- Replace <REAL_SONG_ID> and <REAL_BAND_ID> with valid test values from your band.
-- Run as an authenticated user who is an active band member.
-- Expected: json with success=true, then SELECT returns 'E'
/*
DO $$
DECLARE
  v_result JSON;
  v_song_id UUID := '<REAL_SONG_ID>';
  v_band_id UUID := '<REAL_BAND_ID>';
  v_original TEXT;
BEGIN
  -- Save original
  SELECT musical_key INTO v_original FROM songs WHERE id = v_song_id;

  -- Write test value
  v_result := update_song_metadata(
    v_song_id, v_band_id,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'E'
  );
  RAISE NOTICE 'RPC result: %', v_result;
  ASSERT (v_result->>'success') = 'true', 'RPC failed';

  -- Verify persisted
  ASSERT (SELECT musical_key FROM songs WHERE id = v_song_id) = 'E',
    'musical_key not persisted';

  -- Restore original
  UPDATE songs SET musical_key = v_original WHERE id = v_song_id;
  RAISE NOTICE 'Test passed, original restored.';
END $$;
*/
```

---

## QA Regression Areas

QA must specifically test:

1. **Key field — empty state**: Song Details opens for a song with no key → 4th column shows "—" with chevron, tapping opens key picker.
2. **Key field — picker**: All 24 key values appear in two groups (Major/Minor). Selecting "C#m" closes picker and shows "C#m" in the Key column.
3. **Key field — save and persist**: Select a key, tap Save → reopening Song Details shows the selected key. Cross-device/tab: open the same song on another device and confirm the key is visible.
4. **Key field — clear**: Setting key to null/empty (if supported in the picker) persists as NULL.
5. **4-column metadata row**: BPM, Duration, Tuning, Key are equal-width on a 375pt screen with no clipping or overflow beyond ellipsis.
6. **3-button action row**: All three buttons (Add Lyrics, Add YouTube, Add Notes) are equal-width and visible without clipping at 375pt.
7. **Notes button — empty state**: Song with no notes → "+ Add Notes" button present; tapping expands inline textarea; typing and saving persists notes.
8. **Notes button — set state**: Song with existing notes → preview card visible; tapping "+ Edit Notes" button or card enters edit mode.
9. **Notes — discard**: Editing notes → tapping Cancel → unsaved-changes dialog appears.
10. **Lyrics — no regression**: "+ Add Lyrics" / "Edit Lyrics" still opens the lyrics editor sheet correctly.
11. **YouTube — no regression**: "+ Add YouTube" still opens the YouTube add dialog correctly.
12. **Tuning — no regression**: Tuning dropdown still opens `TuningPickerBottomSheet`.
13. **Save disabled when unchanged**: Save button is disabled (grayed) if no fields have changed.
14. **Read-only mode**: `isReadOnly: true` hides all edit affordances including the new Key chevron and all 3 action buttons.
15. **iOS, Android, Web**: Render the layout on all three platforms.

---

## Rollout / Migration Strategy

This feature involves a DB migration and an RPC change. The migration and the Dart client update must ship together in a single release:

1. Run `supabase db push` (Tier 1 tests pass pre-push; Tier 2 tests pass post-push).
2. Deploy updated Dart client (mobile + web build).

There is no safe partial deployment. If the DB migration ships without the Dart client update, the app will call the old 10-param signature which no longer exists → PGRST202 error on all song metadata saves. Reverse is safe (Dart with 11 params but old DB) since the old function accepts DEFAULT NULL for missing params via PostgREST named-param resolution — but this has not been tested and should not be relied upon.

---

## Out of Scope

- Auto-population of `musical_key` from Spotify/MusicBrainz lookup (external enrichment).
- Displaying the musical key on the setlist song card or song metrics row.
- Filtering or sorting songs by key.
- Adding `musical_key` to the print template or PDF export.
- Any changes to `get_band_full_state` RPC (setlists data only; individual song metadata is fetched separately).
- Enharmonic equivalents in the key picker (e.g., showing C# and Db as the same key).
- Validation beyond the 24-item picker list.
- Changes to `external_song_lookup_service.dart`.
