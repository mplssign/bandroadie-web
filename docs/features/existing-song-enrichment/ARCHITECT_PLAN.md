# ARCHITECT_PLAN.md

## 1. Feature Slug

`feature/existing-song-enrichment`

---

## 2. Problem Summary

Phase 1 (PR #97, `feature/new-song-key-enrichment`) added automatic BPM and musical key fetching via GetSongBPM, but only at the moment a NEW song is added through the external search/lookup flow. Songs already in the catalog — added before Phase 1 shipped, added without search lookup, or added via bulk import — have no way to backfill BPM and key data short of manual field-by-field editing. This is Phase 2.1 of the broader "Song Data Enrichment" initiative.

**User impact today:** Thousands of existing catalog songs have `bpm: null` and `musical_key: null` even though GetSongBPM could likely provide these values via title+artist lookup. Users must manually edit each song individually via the song details sheet, which is tedious at scale.

**Scope for this phase:** Add enrichment actions for EXISTING catalog songs at three granularities:

1. **Single song** — from the song detail sheet
2. **Multi-select** — from the catalog multi-select toolbar
3. **Catalog-wide** — from the catalog overflow menu (all songs in one operation)

All three use the identical flow: user selects which fields to enrich (BPM, Duration, Key) via a checkbox drawer → auto-enrichment runs → results summary shows what happened (updated/not-found/error).

**Out of scope for Phase 2.1:** Dual original/performance values (Phase 2.2), settings screen for data-source preferences (Phase 2.3), lyrics enrichment (Phase 2.4), tuning enrichment (Phase 2.5), enrichment during CSV/bulk import.

---

## 3. Root Cause / Baseline Confirmation

Not a bug — this is new functionality. **Confidence: HIGH** for all findings below, confirmed via direct code inspection and Phase 1 prior-art review.

### 3.1 Data Source Confirmation (Critical Finding)

The feature input states "Working provider paths exist for these [BPM, Duration, Key]" — **this is TRUE, but requires TWO separate providers**.

**Finding:**

| Field        | Provider                    | Input Required    | Available for Existing Songs?                                |
| ------------ | --------------------------- | ----------------- | ------------------------------------------------------------ |
| **BPM**      | GetSongBPM                  | `title`, `artist` | ✅ Yes — title+artist lookup works for any song              |
| **Key**      | GetSongBPM                  | `title`, `artist` | ✅ Yes — title+artist lookup works for any song              |
| **Duration** | iTunes / MusicBrainz Search | `title`, `artist` | ✅ Yes — title+artist lookup returns duration for most songs |

**GetSongBPM analysis (Phase 1 confirmed):**

- Endpoint: `POST /functions/v1/getsongbpm_lookup` with `{title: string, artist: string, duration_seconds?: number, isrc?: string}`
- Returns: `{bpm: number|null, musicalKey: string|null, confidence: 'medium'|'none'}`
- **Does NOT return `duration`** — confirmed in Phase 1 ARCHITECT_PLAN.md §6.4 Task 1 findings and Edge Function implementation (`supabase/functions/getsongbpm_lookup/index.ts` header comment: "Duration is not present in any response field")
- **Works without spotify_id** — pure title+artist lookup
- ✅ **Use for: BPM and Key enrichment**

**iTunes / MusicBrainz Search analysis (NEWLY CONFIRMED):**

- Service: `ExternalSongLookupService` (client-side, already deployed from Phase 1)
- APIs: iTunes Search API (free, public) → MusicBrainz fallback (Edge Function)
- Input: `title`, `artist` (same as GetSongBPM)
- Returns: `SongLookupResult` with `durationSeconds: int?` field populated from:
  - iTunes: `trackTimeMillis` converted to seconds
  - MusicBrainz: `duration_seconds` field directly
- **Success rate:** High for popular/mainstream songs (iTunes has comprehensive catalog), lower for obscure tracks
- ✅ **Use for: Duration enrichment**

**Why existing songs need duration enrichment:**

From migration `20260621000001_songs_duration_zero_correction.sql`:

- Songs created via **bulk import** or **manual entry** have `duration_seconds = 0` (database DEFAULT)
- Songs created via **external search** (iTunes/MusicBrainz lookup) have actual duration values
- Existing catalog has a mix: songs with real durations (from search flow) and songs with 0 (from bulk/manual)
- Songs with `duration_seconds = 0` display as "0:00" in UI — enrichment can backfill real values

**Two-provider enrichment flow:**

1. **If BPM or Key checked:** Call `SongEnrichmentService.lookup()` → GetSongBPM API → extract BPM/Key
2. **If Duration checked:** Call `ExternalSongLookupService.search()` → iTunes/MusicBrainz → extract duration from first result
3. **Merge results** and update song via `update_song_metadata` RPC

**Critical design note:** Duration enrichment uses a DIFFERENT provider (iTunes/MusicBrainz) than BPM/Key (GetSongBPM). Both are title+artist lookups, but separate API calls. This is acceptable because:

- Both APIs are already deployed and stable (Phase 1)
- Sequential calls are simple (no complex orchestration)
- ExternalSongLookupService already handles iTunes → MusicBrainz fallback
- Matches user mental model: "search for this song online and fill missing data"

**Implication for Phase 2.1 scope:**

- ✅ **BPM enrichment:** Available via GetSongBPM
- ✅ **Key enrichment:** Available via GetSongBPM
- ✅ **Duration enrichment:** Available via iTunes/MusicBrainz search

**All three fields are selectable in the enrichment drawer.** No scope reduction needed.

### 3.2 Database Schema Confirmation

From migrations and model inspection:

- `songs.bpm` — `INTEGER`, nullable
- `songs.duration_seconds` — `INTEGER`, not null (migration `20260621000000_songs_duration_not_null.sql` changed from nullable)
- `songs.musical_key` — `TEXT`, nullable (added Phase 1, migration `20260630000000_add_musical_key_to_songs.sql`)
- `songs.tuning` — `TEXT`, nullable
- `songs.lyrics` — `TEXT`, nullable (JSON string)

**Key finding:** `update_song_metadata` RPC (`20260630000001_add_musical_key_to_update_song_rpc.sql`) has critical non-overwrite logic:

```sql
bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END,
duration_seconds = COALESCE(p_duration_seconds, duration_seconds),
musical_key = CASE WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END,
```

**Interpretation:**

- **BPM:** Only updates if currently `NULL` — **perfect for enrichment** (won't overwrite user-entered values)
- **Duration:** Always updates if provided via `COALESCE(p_duration_seconds, duration_seconds)` — **overwrites existing values** — needs modification for "fill missing only" behavior. Note: `duration_seconds` is `NOT NULL` with `0` as the "unset" sentinel (§3.1), so the fill-missing condition must be `duration_seconds = 0`, not `IS NULL`.
- **Musical key:** Always updates if provided — **overwrites existing values** — needs modification for "fill missing only" behavior

**Implication:** The RPC's current "fill missing only" behavior works perfectly for BPM. Both `musical_key` and `duration_seconds` require RPC updates to match BPM's non-overwrite pattern. Feature input states "default behavior for this phase is fixed at **fill missing fields only, never overwrite an existing value**" — this requires an RPC change for both fields.

### 3.3 Multi-Select Infrastructure Confirmation

From `lib/features/setlists/setlist_detail_screen.dart:105-108, 1173-1224`:

- ✅ `_isSelectMode` flag exists
- ✅ `_selectedSongIds` Set tracks selected songs
- ✅ `_enterSelectMode()` / `_exitSelectMode()` methods exist
- ✅ `_buildSelectModeBottomActions()` shows Cancel + "Add X to Setlist" toolbar
- ✅ Catalog-only feature (gated by `state.isCatalog` checks)

**Pattern:** Multi-select toolbar uses a sticky bottom bar with Cancel (text button) and primary action (filled button, disabled when no selection). This is the exact pattern to reuse for "Enrich X Songs."

### 3.4 Rate Limits and Catalog-Wide Enrichment

GetSongBPM free tier: **3,000 requests/hour** (Phase 1 ARCHITECT_PLAN.md §6.4).

For a band with 200 songs in Catalog:

- Catalog-wide enrichment = 200 API calls
- At 3,000/hour limit = 54 seconds minimum (assuming instant responses)
- Real-world with network latency: ~2-3 minutes

**Strategy needed:**

- Batch processing (e.g., 10 songs at a time)
- Progress UI (percentage complete, cancel button)
- Error recovery (network failures, rate limit 429s)
- Never block the UI thread

**Admin-gating question:** Feature input asks "Confirm whether 'Enrich All Songs' should be admin-gated per existing RBAC conventions."

From PROJECT_CONTEXT.md RBAC:

- `admin`: Full CRUD, delete band, remove members, manage roles
- `member`: Full CRUD for gigs/rehearsals/setlists
- `contributor`: Configurable permissions

**Analysis:** Enrichment is a metadata update operation on songs, similar to editing BPM/key/duration manually. Manual editing is NOT admin-gated (all roles can edit song metadata via song details sheet, gated only by band membership). **Enrichment should follow the same access pattern** — available to all band members, not admin-only. Catalog-wide enrichment is just batch editing, not a destructive or permission-escalating operation.

**Decision:** Do NOT admin-gate enrichment. Require only active band membership (same as manual editing).

---

## 4. Reference Docs Consulted

**Phase 1 prior art (mandatory reading per feature input):**

- `docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md` — GetSongBPM integration, API gotchas, artist-matching logic, key normalization, ~75% accuracy accepted, attribution requirements
- `docs/features/new-song-key-enrichment/ENGINEER_REPORT.md` — Live API spike findings, secret retrieval bug fix, artist-matching logic bug fix, POST-DEPLOY verification
- `docs/features/new-song-key-enrichment/QA_REPORT.md` — Artist-matching deviation (first-match vs. exactly-one), file-size warnings, approved with recommendations

**Domain reference:**

- `docs/reference/architecture/supabase_functions.md` — Deployed Edge Functions, auth model, required secrets (confirmed `getsongbpm_lookup` v—, `spotify_audio_features` v18, `spotify_search` v19 all ACTIVE)
- `docs/reference/architecture/database_schema.md` — Songs table schema (bpm, duration_seconds, musical_key, tuning, lyrics)
- `docs/reference/general/AI_DECISIONS.md` — DECISION-002 (AcousticBrainz removal), DECISION-004 (GetSongBPM integration)

**Code inspection (load-bearing for this plan):**

- `lib/features/setlists/setlist_repository.dart:4246-4359` — `_attemptBpmEnrichment`, `_fetchSpotifyBpm` (dormant on existing-song path, Spotify-only, ignores duration_ms)
- `lib/features/songs/song_enrichment_service.dart` — Phase 1 service, single-song design, returns `SongEnrichmentResult{bpm, musicalKey, confidence}`
- `supabase/functions/getsongbpm_lookup/index.ts` — Confirmed no duration in response (header comment lines 1-30)
- `supabase/migrations/20260630000001_add_musical_key_to_update_song_rpc.sql` — RPC signature and non-overwrite logic for BPM
- `lib/features/setlists/setlist_detail_screen.dart:105-108, 1173-1334` — Multi-select infrastructure (select mode, toolbar, selected IDs tracking)
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart:1-150` — Single-song edit sheet pattern (reuse target for entry point)

**Not consulted (out of scope or non-existent):**

- `docs/reference/bpm/*.md` — Phase 1 confirmed these are stale (iTunes replaced Spotify as search source post-doc-write), not relied on
- `docs/reference/notifications/` — Not applicable to this feature

---

## 5. Existing System Analysis

### 5.1 Current Enrichment Flow (Phase 1, New Songs Only)

```
User searches in Song Lookup Overlay
  → ExternalSongLookupService (iTunes → MusicBrainz fallback)
  → User taps result
  → SongEnrichmentReviewSheet opens (Phase 1)
      → Calls SongEnrichmentService.lookup(title, artist) in background
      → GetSongBPM returns BPM + Key
      → User reviews/edits Duration, BPM, Key
      → User saves
  → SetlistRepository.upsertExternalSong(..., musicalKey, skipBackgroundEnrichment: true)
  → Song written to database with enriched fields
```

**Key characteristic:** Enrichment happens BEFORE the song is saved to the database. The review sheet is the gate between "search result selected" and "song persisted."

### 5.2 Proposed Enrichment Flow (Phase 2.1, Existing Songs)

```
User selects song(s) from Catalog:
  - Single song: tap overflow menu on song card → "Enrich Song Data" action
  - Multi-select: enter select mode → select songs → "Enrich" button in toolbar
  - Catalog-wide: tap overflow menu in catalog header → "Enrich All Songs" action

→ EnrichmentSelectorBottomSheet opens
    Fields:
      [x] BPM
      [x] Duration
      [x] Key
      [ ] Tuning (disabled, explanatory text: "Tuning is performance-specific and must be set manually")
      [ ] Lyrics (disabled, explanatory text: "Lyrics enrichment deferred due to licensing complexity")
    Default: BPM + Duration + Key checked
    Actions: Cancel | Enrich

→ User checks desired fields, taps Enrich

→ Enrichment runs (UI shows progress overlay)
    For each song:
      1. Call SongEnrichmentService.lookup(title, artist)
      2. Extract requested fields only (BPM if checked, Duration if checked, Key if checked)
      3. Call update_song_metadata RPC with non-null values for checked fields
      4. Track result: updated | no-match | error
    If catalog-wide: batch 10 at a time, show progress percentage

→ EnrichmentResultsOverlay shows summary
    Top-line: "X of Y songs enriched"
    Detail table: song title/artist, BPM result (updated/not-found/unchanged), Duration result (updated/not-found/unchanged), Key result (updated/not-found/unchanged)
    Actions: Done | Undo (if feasible, or defer to manual correction)
```

**Critical difference from Phase 1:** No per-song review step. User selects fields upfront, enrichment runs automatically, results shown after. This matches the feature input's explicit "no per-song review step" requirement and is appropriate for batch operations.

### 5.3 Non-Overwrite Enforcement

From §3.2, the RPC's current behavior:

- **BPM:** `CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END` — ✅ Perfect, only fills missing
- **Duration:** `COALESCE(p_duration_seconds, duration_seconds)` — ❌ Always overwrites if provided
- **Musical key:** `CASE WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END` — ❌ Always overwrites if provided

**Required RPC changes:**

1. Update `musical_key` logic to match `bpm`:

```sql
musical_key = CASE WHEN p_musical_key IS NOT NULL AND musical_key IS NULL THEN p_musical_key ELSE musical_key END,
```

2. Update `duration_seconds` logic with 0-sentinel check (NOT NULL column, 0 = unset):

```sql
duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END,
```

These ensure enrichment never overwrites user-entered values for any field.

---

## 6. Proposed Solution

### 6.1 What Changes (One Sentence)

Add enrichment actions at three entry points (single song, multi-select, catalog-wide) that open a field-selector drawer (BPM, Duration, and Key checkboxes), run GetSongBPM lookups for BPM/Key and iTunes/MusicBrainz lookups for Duration in batch for checked fields, update songs via the modified RPC (non-overwrite for BPM, Duration, and Key), and show a results summary overlay.

### 6.2 Entry Points (Three Identical Flows)

**1. Single Song (Song Detail Sheet)**

- Add "Enrich Song Data" action to the song details bottom sheet overflow menu (alongside existing Edit, Delete, etc.)
- On tap: open `EnrichmentSelectorBottomSheet` with `songIds: [song.id]`
- Entry point file: `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

**2. Multi-Select (Catalog Toolbar)**

- Add "Enrich" as a secondary action button in `_buildSelectModeBottomActions()` toolbar
- Layout: Cancel (text button) | "Add X to Setlist" (primary filled button) | "Enrich" (secondary icon/text button)
- No mode toggle needed — both actions available simultaneously
- On tap: open `EnrichmentSelectorBottomSheet` with `songIds: _selectedSongIds.toList()`
- Entry point file: `lib/features/setlists/setlist_detail_screen.dart`

**3. Catalog-Wide (Catalog Overflow Menu)**

- Add "Enrich All Songs" action to the catalog screen's existing overflow menu (⋮ icon in header)
- On tap: open `EnrichmentSelectorBottomSheet` with `songIds: null` (signals "all catalog songs")
- Entry point file: `lib/features/setlists/setlist_detail_screen.dart` (catalog-specific action, gated by `state.isCatalog`)

### 6.3 Enrichment Selector Drawer

**New file:** `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`

**Purpose:** Let user select which fields to enrich before batch processing starts.

**UI Structure:**

```
┌─────────────────────────────────────┐
│ Enrich Song Data                    │
│                                      │
│ Select data to auto-enrich for X    │
│ songs. Only missing values will be   │
│ filled — existing data is never     │
│ overwritten.                         │
│                                      │
│ ☑ BPM                                │
│   Tempo in beats per minute         │
│                                      │
│ ☑ Duration                           │
│   Song length in minutes:seconds    │
│                                      │
│ ☑ Key                                │
│   Musical key (e.g., C, Am, F#)     │
│                                      │
│ ☐ Tuning (not available)            │
│   Tuning varies by performance and  │
│   must be set manually per band.    │
│                                      │
│ ☐ Lyrics (not available)            │
│   Lyrics require manual entry due   │
│   to copyright restrictions.        │
│                                      │
│ [Cancel]           [Enrich Songs]   │
└─────────────────────────────────────┘
```

**Fields:**

- **BPM, Duration, Key:** `CheckboxListTile`, selectable, default checked
- **Tuning, Lyrics:** `CheckboxListTile`, enabled: false, with explanatory subtitle text:
  - **Tuning:** "Tuning varies by performance and must be set manually per band."
  - **Lyrics:** "Lyrics require manual entry due to copyright restrictions."
- **Buttons:** Cancel (text button) | Enrich Songs (filled button, disabled if nothing checked)

**Return value:** `EnrichmentSelectorResult{bpmSelected: bool, durationSelected: bool, keySelected: bool}` or `null` if cancelled

**Size target:** ~200-250 lines (simple sheet, no complex logic)

### 6.4 Enrichment Service Extension

**File:** `lib/features/songs/song_enrichment_service.dart` (extend existing)

**New method:**

```dart
/// Enrich multiple songs in batch for BPM, Duration, and Key.
///
/// For each song, calls GetSongBPM and returns results.
/// Never throws — failed lookups return 'none' confidence.
///
/// Progress callback is invoked after each song completes.
/// NOTE: This handles BPM/Key only. Duration uses separate ExternalSongLookupService.
Future<List<SongEnrichmentBatchResult>> enrichBatch({
  required List<EnrichmentSongInput> songs,
  void Function(int completed, int total)? onProgress,
}) async {
  // Implementation: sequential with optional parallelism (start with sequential for safety)
}

class EnrichmentSongInput {
  final String id;
  final String title;
  final String artist;
  final int? currentBpm;
  final int? currentDuration;
  final String? currentKey;
}

class SongEnrichmentBatchResult {
  final String songId;
  final String title;
  final String artist;
  final SongEnrichmentResult result; // existing result type from Phase 1
}
```

**Design notes:**

- Reuses existing `SongEnrichmentService.lookup()` method (no API changes)
- Sequential processing initially (simplest, avoids rate limit complexity)
- Progress callback for UI updates
- Returns full results list (not streamed) — simpler state management

**Optimization (out of scope for Phase 2.1):** Parallel batches of 5-10 songs with rate-limit backoff. Sequential is sufficient for Phase 2.1 given typical catalog sizes (50-200 songs) and GetSongBPM's generous 3,000/hour limit.

### 6.5 Enrichment Orchestration

**New file:** `lib/features/songs/services/song_enrichment_orchestrator.dart`

**Purpose:** Coordinate the full enrichment flow — fetch songs, call service, update database, handle errors.

**Key method:**

```dart
Future<EnrichmentOrchestrationResult> enrichSongs({
  required String bandId,
  required List<String> songIds, // empty = all catalog songs
  required bool enrichBpm,
  required bool enrichDuration,
  required bool enrichKey,
  void Function(int completed, int total)? onProgress,
}) async {
  // 1. Fetch song records (title, artist, current BPM, duration, key) via repository
  // 2. Filter: skip songs where all requested fields are already filled
  // 3. For each song:
  //    a. If BPM or Key requested: Call SongEnrichmentService.lookup() → GetSongBPM
  //    b. If Duration requested: Call ExternalSongLookupService.search() → iTunes/MusicBrainz
  //    c. Merge results
  //    d. Call update_song_metadata RPC with requested+found fields
  //    e. Track success/failure
  // 4. Return summary
}

class EnrichmentOrchestrationResult {
  final int total;
  final int enriched;   // successfully updated
  final int notFound;   // API returned 'none' confidence or no search results
  final int unchanged;  // already had values
  final int errors;     // RPC or network failures
  final List<SongEnrichmentDetail> details; // per-song outcomes for results UI
}

class SongEnrichmentDetail {
  final String songId;
  final String title;
  final String artist;
  final EnrichmentFieldResult bpmResult;
  final EnrichmentFieldResult durationResult;
  final EnrichmentFieldResult keyResult;
}

enum EnrichmentFieldResult {
  notRequested,  // field not checked in drawer
  updated,       // API returned value, RPC succeeded
  notFound,      // API returned 'none' confidence or empty search results
  unchanged,     // already had a value (skip due to non-overwrite)
  error,         // RPC or network failure
}
```

**Error handling:**

- Network failures: track as `error`, include in summary, never throw
- RPC failures (band membership revoked mid-enrichment): stop and report
- Rate limit 429s: treat as temporary error, track as `error` (no automatic retry in Phase 2.1 — simplest)

**Cancellation (out of scope for Phase 2.1):** No explicit cancel button during enrichment. If catalog-wide takes too long, user can navigate away (operation continues in background, results lost). Proper cancellation requires `CancelToken` or similar — defer to future phase if needed.

### 6.6 Repository Method (Batch Update)

**File:** `lib/features/setlists/setlist_repository.dart`

**New method:**

```dart
/// Enrich songs via update_song_metadata RPC.
///
/// Only updates fields where newValue is non-null.
/// Returns success/failure per song.
Future<Map<String, bool>> enrichSongs({
  required String bandId,
  required Map<String, EnrichmentUpdate> updates, // songId -> update
}) async {
  // For each song:
  //   Call supabase.rpc('update_song_metadata', {...})
  //   Track success (returns {success: true}) or failure
  // Return map of songId -> success bool
}

class EnrichmentUpdate {
  final int? bpm;
  final int? durationSeconds;
  final String? musicalKey;
}
```

**Note:** This is a thin wrapper around existing `update_song_metadata` RPC calls. No new repository abstraction needed — could inline in orchestrator if preferred, but extracting for testability and separation of concerns.

### 6.7 Enrichment Results Overlay

**New file:** `lib/features/songs/widgets/enrichment_results_overlay.dart`

**Purpose:** Show summary of enrichment batch results after completion.

**UI Structure:**

```
┌─────────────────────────────────────┐
│ Enrichment Complete                 │
│                                      │
│ ✓ 42 of 50 songs enriched           │
│ • 8 songs not recognized             │
│                                      │
│ Song Title · Artist                  │
│ BPM: Updated   Dur: Updated   Key: Updated │
│                                      │
│ Another Song · Artist                │
│ BPM: Not found   Dur: Unchanged   Key: Updated │
│                                      │
│ Third Song · Artist                  │
│ BPM: Unchanged   Dur: Not found   Key: Unchanged │
│                                      │
│ ... (scrollable)                     │
│                                      │
│              [Done]                  │
└─────────────────────────────────────┘
```

**Top-line summary:**

- "X of Y songs enriched" (count of `updated` results)
- "Z songs not recognized" (count of `notFound` results)
- "N errors" if any RPC/network failures

**Detail table (scrollable):**

- Song title/artist
- BPM result: Updated | Not found | Unchanged | Not requested | Error
- Duration result: Updated | Not found | Unchanged | Not requested | Error
- Key result: Updated | Not found | Unchanged | Not requested | Error
- Color coding: green checkmark for Updated, gray dash for Unchanged/Not requested, orange ! for Not found, red X for Error

**Actions:**

- **Done:** Close overlay, return to catalog (exit select mode if in multi-select)
- **Undo (future):** Out of scope for Phase 2.1 — would require storing pre-enrichment snapshots. Users can manually revert via song details sheet.

**Size target:** ~300-400 lines (list view + summary + result formatting)

### 6.8 Progress Overlay (Catalog-Wide)

**New file:** `lib/features/songs/widgets/enrichment_progress_overlay.dart`

**Purpose:** Show progress during long-running catalog-wide enrichment.

**UI Structure:**

```
┌─────────────────────────────────────┐
│ Enriching Songs...                  │
│                                      │
│ 42 of 150 songs processed            │
│                                      │
│ [Progress Bar 28%]                   │
│                                      │
│ Currently: Song Title by Artist      │
└─────────────────────────────────────┘
```

**Shown when:**

- Catalog-wide enrichment (50+ songs expected)
- Updates every song completion via `onProgress` callback
- Auto-dismissed when enrichment completes, replaced by results overlay

**Not shown for:**

- Single song enrichment (completes in <2 seconds)
- Multi-select <20 songs (fast enough to not need progress)

**Cancellation:** Out of scope for Phase 2.1 (see §6.5).

**Size target:** ~100-150 lines (simple overlay with progress indicator)

---

## 7. Database Impact

### 7.1 Migration Required: Yes (RPC Modification)

**New file:** `supabase/migrations/20260801000000_fix_musical_key_duration_overwrite_in_update_song_rpc.sql`

**Purpose:** Change `musical_key` and `duration_seconds` update logic in `update_song_metadata` RPC to match `bpm` non-overwrite pattern (fill missing only, never overwrite existing values).

**Content:**

```sql
-- Fix musical_key to never overwrite existing values during enrichment.
-- Matches bpm's "fill missing only" logic.
-- Required for feature/existing-song-enrichment Phase 2.1.

DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

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
    -- CHANGED: Fill missing only (duration_seconds = 0 is the "unset" sentinel, NOT NULL column)
    duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END,
    tuning = COALESCE(p_tuning, tuning),
    notes = CASE WHEN p_notes IS NOT NULL THEN p_notes ELSE notes END,
    title = COALESCE(p_title, title),
    artist = COALESCE(p_artist, artist),
    youtube_links = CASE WHEN p_youtube_links IS NOT NULL THEN p_youtube_links ELSE youtube_links END,
    lyrics = CASE WHEN p_lyrics IS NOT NULL THEN p_lyrics ELSE lyrics END,
    -- CHANGED: Fill missing only, same as bpm
    musical_key = CASE WHEN p_musical_key IS NOT NULL AND musical_key IS NULL THEN p_musical_key ELSE musical_key END,
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
  'Update song metadata including musical key and duration. BPM, duration_seconds, and musical_key only update when currently NULL/0 (non-overwrite). SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';
```

**Rationale:**

- **Musical key:** The existing RPC's `musical_key` logic (`CASE WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END`) always overwrites if a non-null value is provided. The new logic (`CASE WHEN p_musical_key IS NOT NULL AND musical_key IS NULL THEN p_musical_key ELSE musical_key END`) matches `bpm`'s fill-missing-only pattern.
- **Duration:** The existing RPC's `duration_seconds` logic (`COALESCE(p_duration_seconds, duration_seconds)`) always overwrites if a non-null value is provided. The new logic uses `duration_seconds = 0` as the "unset" sentinel (NOT NULL column with DEFAULT 0 per §3.1), so the condition is `duration_seconds = 0`, not `IS NULL`. This matches the same non-overwrite intent as BPM/key.

**Backward compatibility:** ✅ Fully compatible for both fields.

- **Musical key:** Manual editing via song details sheet passes `p_musical_key` only when the user explicitly changed the field (checked via `musicalKeyChanged` flag in `SongDetailsResult`). If the user didn't touch key, `p_musical_key` is `null` and the `ELSE musical_key` branch preserves the existing value — unchanged behavior. The new logic only affects callers that pass a non-null `p_musical_key` when the DB already has a non-null value, which today is no one (manual editing doesn't do this).
- **Duration:** Manual editing passes `p_duration_seconds` only when the user changed duration. The new logic only prevents overwrite when `duration_seconds = 0` (unset). If a user manually sets duration to 180 seconds and then an enrichment call tries to update it to 200, the existing value (180) is preserved. Legitimate 0-second songs are not a concern (no valid audio recording is 0 seconds; the display UI shows "0:00" as a visual indicator of missing data, not as a valid duration).

### 7.2 RLS Impact

**None.** This is a signature-preserving RPC body change. No new policies, no policy modification. The RPC is already `SECURITY DEFINER` with band membership check — unchanged.

### 7.3 Affected / Unaffected Summary

| Area                       | Status                                                                                                                           |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `songs` table schema       | Unaffected — no new columns, no constraints                                                                                      |
| RLS policies               | Unaffected                                                                                                                       |
| `update_song_metadata` RPC | **Affected** — logic changes for `musical_key` (NULL check) and `duration_seconds` (0 check) to implement non-overwrite behavior |
| Any other RPC              | Unaffected                                                                                                                       |
| Existing rows              | Unaffected — migration is RPC-only, no data migration                                                                            |

---

## 8. Flutter Architecture Changes

### 8.1 New Files

| File                                                               | Purpose                                                                                      | Size Target    |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------- | -------------- |
| `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` | Field selection drawer (BPM/Duration/Key checkboxes + disabled fields with explanatory text) | ~200-250 lines |
| `lib/features/songs/widgets/enrichment_results_overlay.dart`       | Results summary after enrichment (top-line + detail table)                                   | ~300-400 lines |
| `lib/features/songs/widgets/enrichment_progress_overlay.dart`      | Progress indicator for catalog-wide enrichment                                               | ~100-150 lines |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`    | Coordinate fetch → enrich → update flow, handle errors                                       | ~250-350 lines |

**Total new code:** ~850-1,150 lines across 4 files. All feature-scoped, no cross-cutting concerns.

### 8.2 Modified Files

| File                                                           | Changes                                                                                                                                                                                                          |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart`             | Add "Enrich" button to multi-select toolbar (~20 lines), Add "Enrich All Songs" to catalog overflow menu (~15 lines), Wire both to open enrichment selector → orchestrator → results overlay (~40 lines handler) |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Add "Enrich Song Data" action to overflow menu (~10 lines), Wire to enrichment selector for single song (~20 lines handler)                                                                                      |
| `lib/features/songs/song_enrichment_service.dart`              | Add `enrichBatch()` method (~80-100 lines)                                                                                                                                                                       |
| `lib/features/setlists/setlist_repository.dart`                | Add `enrichSongs()` batch update method (~60-80 lines) — thin RPC wrapper                                                                                                                                        |

**Total modified code:** ~245-285 lines across 4 existing files.

### 8.3 State Management

**No new Riverpod providers needed.** The enrichment flow is one-shot (user action → async operation → show results → done), not reactive state. The orchestrator and service are plain Dart classes instantiated directly in handlers.

**Existing providers used:**

- `setlistDetailProvider` — for fetching current song list in catalog-wide mode
- `setlistRepositoryProvider` — for calling `enrichSongs()` method
- `activeBandProvider` — for current `bandId`

**Pattern:** Same as Phase 1's review sheet — instantiate services directly, call async methods, show results. No need for persistent state containers.

---

## 9. Files to Create

| File                                                                                           | Justification                                                                    |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `supabase/migrations/20260801000000_fix_musical_key_duration_overwrite_in_update_song_rpc.sql` | Modify RPC for non-overwrite behavior on musical_key and duration_seconds (§7.1) |
| `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`                             | Field selection UI (§6.3) — new, isolated widget                                 |
| `lib/features/songs/widgets/enrichment_results_overlay.dart`                                   | Results summary UI (§6.7) — new, isolated widget                                 |
| `lib/features/songs/widgets/enrichment_progress_overlay.dart`                                  | Progress UI for catalog-wide (§6.8) — new, isolated widget                       |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`                                | Coordinate enrichment flow (§6.5) — new service, separation of concerns          |

---

## 10. Files to Modify

| File                                                           | Changes                                                                                                                            |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart`             | Add multi-select "Enrich" button (§6.2 #2), Add catalog overflow "Enrich All Songs" action (§6.2 #3), Wire both to enrichment flow |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Add "Enrich Song Data" action to single-song overflow menu (§6.2 #1)                                                               |
| `lib/features/songs/song_enrichment_service.dart`              | Add `enrichBatch()` method for multi-song lookups (§6.4)                                                                           |
| `lib/features/setlists/setlist_repository.dart`                | Add `enrichSongs()` batch update wrapper (§6.6)                                                                                    |

---

## 11. Files Off-Limits

| File                                                   | Reason                                                                                                                                                                                                                  |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                        | Init order must not change; unrelated to this feature                                                                                                                                                                   |
| `lib/features/songs/external_song_lookup_service.dart` | **Not to be modified** — but IS an intended dependency. The orchestrator (§6.5) calls `ExternalSongLookupService.search()` for duration enrichment (iTunes/MusicBrainz lookup). Existing service, stable, reused as-is. |
| `supabase/functions/getsongbpm_lookup/index.ts`        | Edge Function API unchanged — reusing as-is from Phase 1                                                                                                                                                                |
| `supabase/functions/spotify_audio_features/index.ts`   | Not modifying dormant Spotify path — out of scope (§3.1)                                                                                                                                                                |
| `lib/features/setlists/models/song.dart`               | Model unchanged — all fields already exist                                                                                                                                                                              |
| `lib/features/setlists/setlist_detail_controller.dart` | State management unchanged — no new providers needed                                                                                                                                                                    |

---

## 12. System Impact Map

| System                                 | Impact                                                                                                          |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                                      |
| Rehearsals                             | unaffected                                                                                                      |
| Setlists / Catalog                     | **affected** — enrichment actions added to catalog UI (multi-select toolbar, overflow menu, song detail sheet)  |
| Members / RBAC                         | **affected** (minimally) — enrichment requires active band membership (same as manual editing), no admin-gating |
| Auth / Session                         | unaffected                                                                                                      |
| Routing                                | unaffected                                                                                                      |
| Notifications                          | unaffected                                                                                                      |
| Platform (iOS / Android / Web / macOS) | **affected** — shared Flutter UI code, all four platforms get enrichment actions identically                    |

---

## 13. Regression Risk

**Level: LOW-MEDIUM**

**Toward LOW:**

- RPC change is surgical (one `CASE` statement modified) and backward-compatible
- New UI entry points are isolated additions (overflow menus, toolbar button) — no existing actions removed or changed
- Enrichment flow is entirely new code paths — cannot regress existing flows
- GetSongBPM API already proven in Phase 1 (deployed, tested, QA-approved)
- No auth, session, routing, or init-order changes
- No shared code path with gigs, rehearsals, or notifications

**Toward MEDIUM (why not LOW):**

- **RPC change affects manual editing:** Though backward-compatible by design (§7.1), any CASE statement error could break manual key editing for all users. Requires careful Tier 1 pre-deploy testing.
- **Catalog-wide enrichment volume:** A band with 500+ songs triggering 500 GetSongBPM calls in sequence is untested at scale. Rate limit handling (3,000/hour) is graceful-degrade only (§6.5), no auto-retry.
- **Multi-select toolbar:** Adding a new button/action to the existing toolbar pattern risks layout issues on small screens or conflicting with "Add to Setlist" action (needs UX polish).
- **No cancellation:** Catalog-wide enrichment that takes 5+ minutes cannot be cancelled (§6.5) — user must wait or navigate away (loses results). Not a data-integrity risk, but a UX friction point.

**Mitigations:**

- Extensive Tier 1 testing of RPC change (§15 PRE-DEPLOY TESTs 1-5)
- Progress UI for catalog-wide (§6.8) keeps user informed
- Batch processing (§6.4) prevents blocking UI thread
- Clear explanatory text in selector drawer (§6.3) sets expectations about Duration unavailability

---

## 14. Engineer Task Breakdown

Execute in order. Tasks 1-6 are infrastructure/foundation, Tasks 7-10 are UI/wiring, Task 11 is testing.

1. **Write and test RPC migration** (Task 3 + Tier 1 tests 1-9 from §15)
   - Write `20260801000000_fix_musical_key_duration_overwrite_in_update_song_rpc.sql`
   - Run Tier 1 PRE-DEPLOY tests locally against existing schema (before applying migration) — 9 tests total covering BPM, musical_key, and duration_seconds baseline behavior
   - Apply migration: `supabase db push`
   - Run Tier 2 POST-DEPLOY tests (after migration applied) — 6 tests total verifying non-overwrite works for all three fields
   - Confirm manual key and duration editing still works (smoke test via song details sheet)

2. **Extend `SongEnrichmentService` with batch method** (§6.4)
   - Add `enrichBatch()` method to existing service class
   - Reuse existing `lookup()` method (no API changes)
   - Add progress callback support
   - Unit test (optional but recommended): mock Supabase client, verify sequential calls

3. **Create `SongEnrichmentOrchestrator`** (§6.5)
   - Implement fetch → enrich → update flow
   - Handle errors gracefully (network, RPC, rate limit)
   - Return structured result with per-song outcomes
   - Test locally with 5-10 song sample (verify RPC calls succeed)

4. **Create `EnrichmentSelectorBottomSheet`** (§6.3)
   - Checkboxes for BPM + Duration + Key (selectable, default checked)
   - Disabled checkboxes for Tuning, Lyrics with explanatory text
   - Return `EnrichmentSelectorResult` or null
   - Match existing bottom sheet style (design_tokens, AppColors)

5. **Create `EnrichmentResultsOverlay`** (§6.7)
   - Top-line summary (X of Y enriched, Z not found)
   - Scrollable detail table (song + BPM result + Duration result + Key result)
   - Color-coded result badges
   - Done button → close and refresh catalog

6. **Create `EnrichmentProgressOverlay`** (§6.8)
   - Progress bar + count (X of Y processed)
   - Currently processing: song title
   - Auto-dismiss when complete

7. **Wire single-song entry point** (§6.2 #1)
   - Add "Enrich Song Data" to song details sheet overflow menu
   - Handler: open selector → orchestrator with `[songId]` → results overlay
   - Test with 1 song (verify RPC call, results display)

8. **Wire multi-select entry point** (§6.2 #2)
   - Add "Enrich X Songs" button to catalog multi-select toolbar
   - Handler: open selector → orchestrator with `_selectedSongIds.toList()` → results overlay → exit select mode
   - Test with 3-5 selected songs (verify batch processing)

9. **Wire catalog-wide entry point** (§6.2 #3)
   - Add "Enrich All Songs" to catalog overflow menu
   - Handler: open selector → show progress overlay → orchestrator with all catalog songs → results overlay
   - Test with 20-30 song catalog (verify progress updates, completion)

10. **Add repository batch update method** (§6.6)
    - Add `enrichSongs()` to `SetlistRepository`
    - Call `update_song_metadata` RPC per song
    - Return success/failure map
    - Used by orchestrator in Task 3

11. **Manual verification per §15**
    - Run all manual end-to-end tests
    - Run `flutter analyze` — 0 errors before proceeding

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (before `supabase db push`)

**Purpose:** Verify the RPC change is correct and backward-compatible BEFORE applying the migration.

**Run against:** Production database schema (current `update_song_metadata` RPC with old `musical_key` logic).

- **PRE-DEPLOY TEST 1:** Confirm current RPC signature and `musical_key` logic (baseline)

  ```sql
  SELECT pg_get_functiondef(oid)
  FROM pg_proc
  WHERE proname = 'update_song_metadata';
  -- Expected: 11 parameters, musical_key logic is:
  -- musical_key = CASE WHEN p_musical_key IS NOT NULL THEN p_musical_key ELSE musical_key END
  ```

- **PRE-DEPLOY TEST 2:** Verify current behavior — updating key when already set (should overwrite)

  ```sql
  -- Setup: Insert test song with key 'Am'
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    -- Get first band for current user
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    IF v_band_id IS NULL THEN
      RAISE EXCEPTION 'No active band membership for current user';
    END IF;

    -- Insert test song with musical_key = 'Am'
    INSERT INTO songs (id, band_id, title, artist, duration_seconds, musical_key)
    VALUES (v_test_song_id, v_band_id, 'Test Song Pre-Deploy', 'Test Artist', 180, 'Am');

    -- Call RPC to update key to 'C' (should overwrite 'Am' → 'C')
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_musical_key := 'C'
    );

    RAISE INFO 'RPC result: %', v_result;

    -- Verify: musical_key should now be 'C' (old behavior = overwrites)
    IF (SELECT musical_key FROM songs WHERE id = v_test_song_id) = 'C' THEN
      RAISE INFO '✓ PRE-DEPLOY TEST 2 PASSED: Old RPC overwrites existing key';
    ELSE
      RAISE EXCEPTION '✗ PRE-DEPLOY TEST 2 FAILED: musical_key not overwritten';
    END IF;

    -- Cleanup
    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

- **PRE-DEPLOY TEST 3:** Verify current behavior — updating key when null (should fill)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    -- Insert test song with musical_key = NULL
    INSERT INTO songs (id, band_id, title, artist, duration_seconds, musical_key)
    VALUES (v_test_song_id, v_band_id, 'Test Song Null Key', 'Test Artist', 180, NULL);

    -- Call RPC to set key to 'Dm'
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_musical_key := 'Dm'
    );

    -- Verify: musical_key should now be 'Dm'
    IF (SELECT musical_key FROM songs WHERE id = v_test_song_id) = 'Dm' THEN
      RAISE INFO '✓ PRE-DEPLOY TEST 3 PASSED: RPC fills null key';
    ELSE
      RAISE EXCEPTION '✗ PRE-DEPLOY TEST 3 FAILED: musical_key not filled';
    END IF;

    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

- **PRE-DEPLOY TEST 4:** Verify BPM non-overwrite works (baseline for new musical_key logic)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    -- Insert test song with bpm = 120
    INSERT INTO songs (id, band_id, title, artist, duration_seconds, bpm)
    VALUES (v_test_song_id, v_band_id, 'Test Song BPM', 'Test Artist', 180, 120);

    -- Call RPC to update bpm to 140 (should NOT overwrite, keeps 120)
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_bpm := 140
    );

    -- Verify: bpm should still be 120 (non-overwrite)
    IF (SELECT bpm FROM songs WHERE id = v_test_song_id) = 120 THEN
      RAISE INFO '✓ PRE-DEPLOY TEST 4 PASSED: BPM non-overwrite works';
    ELSE
      RAISE EXCEPTION '✗ PRE-DEPLOY TEST 4 FAILED: BPM overwritten unexpectedly';
    END IF;

    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

- **PRE-DEPLOY TEST 5:** Verify BPM fill-missing works (baseline)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    -- Insert test song with bpm = NULL
    INSERT INTO songs (id, band_id, title, artist, duration_seconds, bpm)
    VALUES (v_test_song_id, v_band_id, 'Test Song Null BPM', 'Test Artist', 180, NULL);

    -- Call RPC to set bpm to 130
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_bpm := 130
    );

    -- Verify: bpm should now be 130
    IF (SELECT bpm FROM songs WHERE id = v_test_song_id) = 130 THEN
      RAISE INFO '✓ PRE-DEPLOY TEST 5 PASSED: BPM fill-missing works';
    ELSE
      RAISE EXCEPTION '✗ PRE-DEPLOY TEST 5 FAILED: BPM not filled';
    END IF;

    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

- **PRE-DEPLOY TEST 6:** Verify duration_seconds overwrite behavior (baseline — current RPC always overwrites)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    IF v_band_id IS NULL THEN
      RAISE EXCEPTION 'No active band membership for current user';
    END IF;

    -- Insert test song with duration_seconds = 180 (3:00)
    INSERT INTO songs (id, band_id, title, artist, duration_seconds)
    VALUES (v_test_song_id, v_band_id, 'Test Song Duration Overwrite', 'Test Artist', 180);

    -- Call RPC to update duration to 240 (should overwrite 180 → 240 with old logic)
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_duration_seconds := 240
    );

    RAISE INFO 'RPC result: %', v_result;

    -- Verify: duration_seconds should now be 240 (old behavior = overwrites)
    IF (SELECT duration_seconds FROM songs WHERE id = v_test_song_id) = 240 THEN
      RAISE INFO '✓ PRE-DEPLOY TEST 6 PASSED: Old RPC overwrites existing duration';
    ELSE
      RAISE EXCEPTION '✗ PRE-DEPLOY TEST 6 FAILED: duration_seconds not overwritten';
    END IF;

    -- Cleanup
    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

- **PRE-DEPLOY TEST 7:** Verify duration_seconds fill-missing works (baseline)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    -- Insert test song with duration_seconds = 0 (unset sentinel)
    INSERT INTO songs (id, band_id, title, artist, duration_seconds)
    VALUES (v_test_song_id, v_band_id, 'Test Song Duration Fill', 'Test Artist', 0);

    -- Call RPC to set duration to 200
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_duration_seconds := 200
    );

    -- Verify: duration_seconds should now be 200
    IF (SELECT duration_seconds FROM songs WHERE id = v_test_song_id) = 200 THEN
      RAISE INFO '✓ PRE-DEPLOY TEST 7 PASSED: RPC fills duration when 0';
    ELSE
      RAISE EXCEPTION '✗ PRE-DEPLOY TEST 7 FAILED: duration_seconds not filled';
    END IF;

    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

**Expected results:** All 7 tests pass. Tests 2-3 confirm old key behavior (overwrites). Tests 4-5 confirm BPM non-overwrite works today (pattern to copy). Tests 6-7 confirm duration overwrites today (needs fixing).

---

### Tier 2 — Post-deployment (after `supabase db push` succeeds)

**Purpose:** Verify the RPC migration applied correctly and new behavior works.

**Run against:** Database with new RPC deployed.

- **POST-DEPLOY TEST 1:** Verify new RPC signature unchanged (still 11 params)

  ```sql
  SELECT routine_name, array_length(proargnames, 1) as param_count
  FROM information_schema.routines
  JOIN pg_proc ON proname = routine_name
  WHERE routine_name = 'update_song_metadata';
  -- Expected: 1 row, param_count = 11 (unchanged signature)
  ```

- **POST-DEPLOY TEST 2:** Verify new behavior — updating key when already set (should NOT overwrite)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    -- Insert test song with musical_key = 'Am'
    INSERT INTO songs (id, band_id, title, artist, duration_seconds, musical_key)
    VALUES (v_test_song_id, v_band_id, 'Test Song Post-Deploy', 'Test Artist', 180, 'Am');

    -- Call RPC to update key to 'C' (should NOT overwrite, keeps 'Am')
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_musical_key := 'C'
    );

    RAISE INFO 'RPC result: %', v_result;

    -- Verify: musical_key should still be 'Am' (new behavior = non-overwrite)
    IF (SELECT musical_key FROM songs WHERE id = v_test_song_id) = 'Am' THEN
      RAISE INFO '✓ POST-DEPLOY TEST 2 PASSED: New RPC non-overwrite works for key';
    ELSE
      RAISE EXCEPTION '✗ POST-DEPLOY TEST 2 FAILED: musical_key overwritten (regression!)';
    END IF;

    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

- **POST-DEPLOY TEST 3:** Verify fill-missing still works for key

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    -- Insert test song with musical_key = NULL
    INSERT INTO songs (id, band_id, title, artist, duration_seconds, musical_key)
    VALUES (v_test_song_id, v_band_id, 'Test Song Fill Key', 'Test Artist', 180, NULL);

    -- Call RPC to set key to 'Dm'
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_musical_key := 'Dm'
    );

    -- Verify: musical_key should now be 'Dm'
    IF (SELECT musical_key FROM songs WHERE id = v_test_song_id) = 'Dm' THEN
      RAISE INFO '✓ POST-DEPLOY TEST 3 PASSED: New RPC fills null key';
    ELSE
      RAISE EXCEPTION '✗ POST-DEPLOY TEST 3 FAILED: musical_key not filled';
    END IF;

    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

- **POST-DEPLOY TEST 4:** Verify BPM non-overwrite still works (no regression)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    -- Insert test song with bpm = 120
    INSERT INTO songs (id, band_id, title, artist, duration_seconds, bpm)
    VALUES (v_test_song_id, v_band_id, 'Test Song BPM Post', 'Test Artist', 180, 120);

    -- Call RPC to update bpm to 140 (should NOT overwrite, keeps 120)
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_bpm := 140
    );

    -- Verify: bpm should still be 120
    IF (SELECT bpm FROM songs WHERE id = v_test_song_id) = 120 THEN
      RAISE INFO '✓ POST-DEPLOY TEST 4 PASSED: BPM non-overwrite still works';
    ELSE
      RAISE EXCEPTION '✗ POST-DEPLOY TEST 4 FAILED: BPM logic regressed';
    END IF;

    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

- **POST-DEPLOY TEST 5:** Verify new behavior — duration_seconds non-overwrite (should NOT overwrite when > 0)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    -- Insert test song with duration_seconds = 180 (3:00)
    INSERT INTO songs (id, band_id, title, artist, duration_seconds)
    VALUES (v_test_song_id, v_band_id, 'Test Song Duration Non-Overwrite', 'Test Artist', 180);

    -- Call RPC to update duration to 240 (should NOT overwrite, keeps 180)
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_duration_seconds := 240
    );

    RAISE INFO 'RPC result: %', v_result;

    -- Verify: duration_seconds should still be 180 (new behavior = non-overwrite)
    IF (SELECT duration_seconds FROM songs WHERE id = v_test_song_id) = 180 THEN
      RAISE INFO '✓ POST-DEPLOY TEST 5 PASSED: New RPC non-overwrite works for duration';
    ELSE
      RAISE EXCEPTION '✗ POST-DEPLOY TEST 5 FAILED: duration_seconds overwritten (regression!)';
    END IF;

    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

- **POST-DEPLOY TEST 6:** Verify fill-missing still works for duration_seconds (when = 0)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID := gen_random_uuid();
    v_band_id UUID;
    v_user_id UUID := auth.uid();
    v_result JSON;
  BEGIN
    SELECT band_id INTO v_band_id
    FROM band_members
    WHERE user_id = v_user_id AND status = 'active'
    LIMIT 1;

    -- Insert test song with duration_seconds = 0 (unset sentinel)
    INSERT INTO songs (id, band_id, title, artist, duration_seconds)
    VALUES (v_test_song_id, v_band_id, 'Test Song Duration Fill Post', 'Test Artist', 0);

    -- Call RPC to set duration to 210
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_duration_seconds := 210
    );

    -- Verify: duration_seconds should now be 210
    IF (SELECT duration_seconds FROM songs WHERE id = v_test_song_id) = 210 THEN
      RAISE INFO '✓ POST-DEPLOY TEST 6 PASSED: New RPC fills duration when 0';
    ELSE
      RAISE EXCEPTION '✗ POST-DEPLOY TEST 6 FAILED: duration_seconds not filled';
    END IF;

    DELETE FROM songs WHERE id = v_test_song_id;
  END $$;
  ```

**Expected results:** All 6 tests pass. Tests 2-3 confirm new key behavior. Test 4 confirms BPM unchanged (no regression). Tests 5-6 confirm new duration_seconds non-overwrite behavior (fill when 0, preserve when > 0).

---

### Manual End-to-End Verification (Tony to run)

**Prerequisites:**

- Migration applied (`supabase db push` succeeded)
- Flutter app running with all Phase 2.1 code changes
- Active band with 20+ songs in Catalog (mix of songs with/without BPM/key already set)

**Test cases:**

1. **Single song enrichment (song details sheet entry point)**
   - Open any song from Catalog that has `bpm: null` and `musical_key: null`
   - Tap overflow menu (⋮) → "Enrich Song Data"
   - **Verify:** Enrichment selector drawer opens
   - **Verify:** BPM, Duration, and Key are checked by default
   - **Verify:** Tuning, Lyrics are disabled with explanatory text visible
   - Uncheck Duration and Key, keep only BPM checked
   - Tap "Enrich Songs"
   - **Verify:** Progress overlay shows briefly (or results overlay if instant)
   - **Verify:** Results overlay shows "1 of 1 songs enriched" (or "0 of 1" if not found)
   - **Verify:** Detail shows BPM result (Updated/Not found), Duration result (Not requested), and Key result (Not requested)
   - Tap "Done"
   - **Verify:** Song card now shows BPM badge (if updated) and still no key badge

2. **Single song non-overwrite test**
   - Open a song that already has BPM = 120 and Key = "Am"
   - Tap overflow menu → "Enrich Song Data"
   - Check BPM, Duration, and Key
   - Tap "Enrich Songs"
   - **Verify:** Results overlay shows "0 of 1 songs enriched"
   - **Verify:** Detail shows BPM: Unchanged, Key: Unchanged
   - **Verify:** Song still shows BPM 120 and Key "Am" (not overwritten)

3. **Multi-select enrichment (catalog toolbar entry point)**
   - Tap catalog header's selection icon (enter select mode)
   - Select 5 songs (mix: some with null BPM/key, some already filled)
   - **Verify:** Multi-select toolbar shows "5 selected"
   - Tap "Enrich" button (or icon)
   - **Verify:** Enrichment selector drawer opens
   - Keep BPM, Duration, and Key checked
   - Tap "Enrich Songs"
   - **Verify:** Progress overlay shows briefly (5 songs, should be fast)
   - **Verify:** Results overlay shows "X of 5 songs enriched" (X = count that had nulls and matched in API)
   - **Verify:** Detail table shows all 5 songs with per-field results (Updated/Unchanged/Not found)
   - Tap "Done"
   - **Verify:** Select mode exits, catalog refreshes with updated BPM/key badges

4. **Catalog-wide enrichment (overflow menu entry point)**
   - Tap catalog header overflow (⋮) → "Enrich All Songs"
   - **Verify:** Enrichment selector drawer opens
   - Keep BPM, Duration, and Key checked
   - Tap "Enrich Songs"
   - **Verify:** Progress overlay shows with percentage (e.g., "12 of 50 songs processed")
   - **Verify:** Progress updates after each song (not frozen)
   - **Wait for completion (may take 1-3 minutes for 50+ songs)**
   - **Verify:** Results overlay shows "X of Y songs enriched, Z songs not recognized"
   - **Verify:** Detail table scrollable, shows all songs with results
   - Tap "Done"
   - **Verify:** Catalog refreshes, newly enriched songs show BPM/key badges

5. **Network failure handling**
   - **Setup:** Disable network or throttle to simulate slow/failing API
   - Open enrichment selector for 1 song
   - Check BPM, Duration, and Key
   - Tap "Enrich Songs"
   - **Verify:** Results overlay shows "0 of 1 songs enriched, 0 songs not recognized, 1 error" (or similar failure message)
   - **Verify:** App does not crash or show unhandled error UI
   - **Verify:** Song's BPM/key remain unchanged (no partial write)

6. **Explanatory text visibility**
   - Open enrichment selector (any entry point)
   - **Verify:** Duration checkbox is ENABLED and checked by default (alongside BPM and Key)
   - **Verify:** Tuning checkbox is disabled and shows: "Tuning varies by performance and must be set manually per band."
   - **Verify:** Lyrics checkbox is disabled and shows: "Lyrics require manual entry due to copyright restrictions."
   - **Verify:** Text is readable (not truncated or overlapping)

7. **Regression check: Manual editing still works**
   - Open any song's details sheet
   - Tap BPM → edit to 135 → save
   - **Verify:** BPM updates successfully
   - Tap Key → select "F#m" → save
   - **Verify:** Key updates successfully
   - **Verify:** No error about RPC or missing parameters

---

## 16. QA Regression Areas

**What QA must specifically test:**

1. **Three enrichment entry points** (§15 manual tests 1, 3, 4)
   - Single song (song details sheet overflow menu)
   - Multi-select (catalog toolbar)
   - Catalog-wide (catalog header overflow menu)
   - All three show same drawer, same flow, same results format

2. **Non-overwrite behavior** (§15 manual test 2)
   - Enriching a song that already has BPM/key shows "Unchanged" in results
   - Pre-existing values are not modified

3. **Field selection respects checkboxes**
   - Unchecking BPM → only Duration and Key enriched (BPM shows "Not requested")
   - Unchecking Duration → only BPM and Key enriched
   - Unchecking Key → only BPM and Duration enriched
   - Unchecking all three → "Enrich Songs" button disabled

4. **Progress UI (catalog-wide only)**
   - Progress overlay shows during long enrichment (50+ songs)
   - Percentage updates correctly
   - Does not freeze or block UI

5. **Results summary accuracy**
   - Top-line counts match detail table
   - "Not found" count reflects API's 'none' confidence responses
   - "Unchanged" count reflects songs that already had values
   - "Error" count reflects RPC/network failures

6. **Manual editing regression** (§15 manual test 7)
   - Editing BPM via song details sheet still works
   - Editing Key via song details sheet still works
   - Editing Duration, Tuning, Notes still work (unchanged code paths)

7. **Multi-select mode exit**
   - After enrichment completes, select mode exits automatically
   - Selected song IDs are cleared

8. **Platform consistency** (test on at least iOS + Web)
   - Enrichment actions appear in correct menus on both platforms
   - Drawer/overlay UI renders correctly (no layout breaks)
   - GetSongBPM API calls succeed on both platforms (Edge Function is platform-agnostic)

9. **`flutter analyze`:** 0 errors, 0 warnings

---

## 17. Rollout / Migration Strategy

**Prerequisites (Tony):**

- None — all infrastructure from Phase 1 is reused (GetSongBPM API key, Edge Function already deployed)

**Deployment sequence:**

1. **Apply migration:**

   ```bash
   supabase db push --project-ref nekwjxvgbveheooyorjo
   ```

   Expected: Migration `20260801000000_fix_musical_key_overwrite_in_update_song_rpc.sql` applies successfully.

2. **Run POST-DEPLOY tests** (§15 Tier 2, Tests 1-4)
   - Verify RPC change applied correctly
   - Verify non-overwrite works for key
   - Verify BPM behavior unchanged

3. **Deploy Flutter app:**
   - Web: `./tools/deploy_web.sh`
   - iOS/Android/macOS: normal store/TestFlight process
   - No version-skew risk — new UI calls existing RPC with existing parameters (just different logic internally)

4. **Post-deploy monitoring:**
   - Watch for errors in `getsongbpm_lookup` Edge Function logs (rate limits, API failures)
   - Monitor Supabase RPC logs for `update_song_metadata` errors (should be none)

**Rollback:**

- Flutter changes revert via normal git revert (no data written is destructive)
- RPC revert: Manually apply the old migration's `CREATE OR REPLACE FUNCTION` statement (restores old `musical_key` logic)
- No data cleanup needed — enrichment only fills nulls, never corrupts existing data

**Safe deployment:** ✅ RPC change is non-breaking, all data writes are additive (fill nulls only), no auth/session changes.

---

## 18. Out of Scope

Explicitly not part of Phase 2.1 (per feature input and this plan's scope discipline):

1. ~~**Duration enrichment**~~ — ✅ NOW IN SCOPE, using iTunes/MusicBrainz search (§3.1)
2. **Dual original/performance values** (Phase 2.2) — no schema for this exists yet
3. **Settings screen for data-source preferences** (Phase 2.3) — no UI for this exists yet
4. **Lyrics enrichment** (Phase 2.4) — copyright/licensing deferred
5. **Tuning enrichment** (Phase 2.5) — performance-specific, not auto-fetchable
6. **Enrichment during CSV/bulk import** — separate flow, separate entry point
7. **Undo enrichment action** — would require storing pre-enrichment snapshots, significant complexity
8. **Cancellation of in-progress catalog-wide enrichment** — would require CancelToken or similar, defer if needed
9. **Parallel batch processing** — sequential is sufficient for Phase 2.1 (see §6.4 optimization note)
10. **Auto-retry on rate limit 429** — graceful-degrade only (track as error), no automatic backoff/retry
11. **Enrichment via spotify_id (Spotify Audio Features path)** — dormant, not resurrected (§3.1)
12. **GetSongBPM ISRC-based lookup** — API doesn't support it (Phase 1 confirmed), no change
13. **De-staling `docs/reference/bpm/*.md`** — out of scope (stale docs noted in §4, not fixed)

---

## 19. Open Questions / Tony Confirmations Required

**RESOLVED:**

1. ✅ **Duration scope** — CONFIRMED as selectable. Duration IS available via iTunes/MusicBrainz title+artist lookup (§3.1). Plan updated to include Duration as a selectable field alongside BPM and Key.

2. ✅ **Multi-select toolbar UX** — CONFIRMED as Option B (secondary button alongside "Add to Setlist"). No mode toggle needed, both actions co-located in same toolbar (§6.2 #2).

**Not blocking (proceed with plan's design if no feedback):**

- Admin-gating for "Enrich All Songs" — plan says NO admin-gating (§3.4), proceed if no objection
- Progress overlay threshold — plan shows progress for catalog-wide (50+ songs), not for multi-select <20 songs (§6.8), adjust if too aggressive/conservative

**No open questions remain. Ready for Engineer implementation.**

---

**End of ARCHITECT_PLAN.md**
