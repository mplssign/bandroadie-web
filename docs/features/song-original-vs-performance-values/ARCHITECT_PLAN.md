# ARCHITECT_PLAN.md

## 1. Feature Slug

`feature/song-original-vs-performance-values`

---

## 2. Problem Summary

BandRoadie currently stores a single value each for a song's BPM, musical key, and tuning (`songs.bpm`, `songs.musical_key`, `songs.tuning` — all nullable). These values conflate two conceptually distinct things:

1. **Source recording metadata** — what the original artist's recording actually is (BPM, key, tuning)
2. **Band's performance choice** — what this specific band has decided to play (different key for vocal range, different tempo for energy, different tuning for practicality)

**User impact today:** Once a band edits a song's BPM/key/tuning to reflect their performance choice, the original recording's value is permanently lost/overwritten. There's no way to:

- See what the original recording was after editing
- Revert to the original value
- Reference both values side-by-side
- Distinguish "this is what we found via enrichment" from "this is what we decided to play"

This is Phase 2.2 of the "Song Data Enrichment" initiative. Phase 2.1 (existing-song BPM/key/duration enrichment via GetSongBPM) shipped 2026-08-01 and deliberately preceded this phase — its enrichment writes are the natural source for what becomes the "source" value once dual-value storage exists.

**Scope for this phase:** Add dual-value storage and editing in **Song Details bottom sheet only**. Song cards, setlist rows, and catalog list are explicitly out of scope — they continue showing today's single value. Exact data model, UI layout, fallback behavior (what shows before a user ever sets a performance value), and migration strategy (what happens to existing data) are for this plan to design and propose.

**Out of scope:** Duration (not subject to performance variation per Tony's explicit decision), lyrics, tuning auto-fill research (Phase 2.5), data-source settings (Phase 2.3). Enrichment integration changes are IN scope — Phase 2.1's enrichment flow must be updated to write to the correct dual-value column.

---

## 3. Root Cause / Baseline Confirmation

Not a bug — this is new functionality. **Confidence: HIGH** for all findings below, confirmed via direct code inspection and schema verification this session (2026-08-09).

### 3.1 Current Schema Verification

**Confirmed via Song model (`lib/features/setlists/models/song.dart:6-77`):**

| Column             | Type      | Nullable       | Current Usage                                 |
| ------------------ | --------- | -------------- | --------------------------------------------- |
| `bpm`              | `INTEGER` | YES            | Single value — conflates source + performance |
| `musical_key`      | `TEXT`    | YES            | Single value — conflates source + performance |
| `tuning`           | `TEXT`    | YES            | Single value — conflates source + performance |
| `duration_seconds` | `INTEGER` | NO (0 = unset) | Single value — NOT in dual-value scope        |

All three target fields are nullable and store only one value today. No separate "source" vs "performance" columns exist.

### 3.2 Current Edit Flow Verification

**Song Details bottom sheet** (`lib/features/setlists/widgets/song_details_bottom_sheet.dart`):

- **Dirty-tracking local state** (lines 138-152):
  - `_currentBpm` / `_originalBpm` (int?)
  - `_currentDurationSeconds` / `_originalDurationSeconds` (int)
  - `_currentMusicalKey` / `_originalMusicalKey` (String?)
  - `_currentTuning` / `_originalTuning` (String?)

  **CRITICAL NAMING COLLISION:** These `_original*` variables mean "the value when this edit session started" (for change detection/dirty tracking), NOT "the original recording's value." This is completely unrelated to this feature's concept of "source recording" vs "performance version."

- **Edit widgets reused** (all isolated, well-tested):
  - `showBpmInputDialog()` (`bpm_input_dialog.dart`)
  - `showDurationInputDialog()` (`duration_input_dialog.dart`)
  - `showKeyPickerBottomSheet()` (`key_picker_bottom_sheet.dart`)
  - `showTuningPickerBottomSheet()` (`tuning_picker_bottom_sheet.dart`)

- **Current display pattern**: `SegmentedButtonGroup` 4-row layout (Duration | BPM | Key | Tuning), each row shows one value, tap to edit.

- **Save path** (~line 496): `_handleSave()` builds `SongDetailsResult` and pops it; caller is `setlist_detail_screen.dart:_handleSongTap()` (~line 1723) which dispatches to per-field controller methods (`updateSongBpm`, `updateSongTuning`, `updateSongMusicalKey`, etc.).

### 3.3 Current Enrichment Flow and RPC Asymmetry (Phase 2.1, Shipped 2026-08-01)

**Entry points**:

1. Single song: "Enrich Song Data" action in song details overflow menu
2. Multi-select: "Enrich" button in catalog multi-select toolbar
3. Catalog-wide: "Enrich All Songs" in catalog overflow menu

**Flow** (`lib/features/songs/services/song_enrichment_orchestrator.dart:78-196`):

1. User selects fields to enrich (BPM / Duration / Key checkboxes in `EnrichmentSelectorBottomSheet`)
2. Orchestrator calls:
   - `SongEnrichmentService.lookup()` → GetSongBPM API → returns BPM + Key
   - `ExternalSongLookupService.search()` → iTunes/MusicBrainz → returns Duration
3. For each song, calls `SetlistRepository.enrichSong()` → `update_song_metadata` RPC
4. RPC updates: `bpm`, `musical_key`, `duration_seconds` (single-value columns)
5. Shows results summary overlay

**Current RPC logic** (verified from prod migration `20260801120000_fix_update_song_metadata_false_success.sql`):

```sql
-- BPM: fill-missing-only (never overwrites existing non-NULL values)
bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END,

-- Musical key: fill-missing-only (never overwrites existing non-NULL/non-empty values)
musical_key = CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '')
  THEN p_musical_key ELSE musical_key END,

-- Duration: fill-missing-only (never overwrites existing non-zero values)
duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0
  THEN p_duration_seconds ELSE duration_seconds END,

-- Tuning: ALWAYS OVERWRITES when p_tuning provided (COALESCE pattern)
tuning = COALESCE(p_tuning, tuning),
```

**Critical asymmetry discovered (Manager gate review finding):** `tuning` uses COALESCE (always overwrites), while `bpm`/`musical_key` use fill-missing-only CASE. This means:

- Tuning edits can be changed multiple times by users ✅
- BPM/musical_key edits are write-once (second edit is silent no-op with `success: true`) ❌ — known prod limitation that was the root cause of the 2026-08-01 false-success production incident

**Call sites in `setlist_repository.dart`** (verified via grep): 9 methods call `update_song_metadata` RPC, each passing all 11 params (one non-null per method): `updateSongBpmOverride` (~line 1534), `updateSongDurationOverride` (~line 1852), `updateSongTuningOverride` (~line 1953), `updateSongNotes` (~line 2064), `updateSongTitleArtist` (~line 2172), `updateSongYoutubeLinks` (~line 2241), `updateSongLyrics` (~line 2305), `updateSongMusicalKey` (~line 2383), `enrichSong` (~line 3473).

**Critical integration point:** Phase 2.1 writes to `bpm`, `musical_key` columns today. Once dual-value columns exist, enrichment should write to the SOURCE columns (not performance), and the RPC/orchestrator must be updated.

**ARCHITECT DECISION:** The new dual-value columns will ALL use COALESCE (always-overwrite) pattern like `tuning`, NOT fill-missing-only CASE like `bpm`/`musical_key`. This avoids reintroducing the write-once bug class from the 2026-08-01 false-success incident. Enrichment flow will check for NULL values in orchestrator code BEFORE calling RPC, so fill-missing-only semantics are preserved at the orchestrator level, not in the RPC itself. (Race condition implications documented in §13.)

### 3.4 Naming Collision Must Be Resolved

Per Feature Input directive:

> `song_details_bottom_sheet.dart` already has local state (`_originalBpm`, `_currentBpm`, ~lines 137–174, and similar patterns for tuning) where "original" means "the value before this edit session" for local change-detection/dirty-tracking — completely unrelated to this feature's "original recording" concept. Pick non-colliding terminology in new code/schema/variable names (e.g. consider `sourceBpm`/`performanceBpm` or similar) and explicitly note in your plan how the existing dirty-tracking logic and the new dual-value concept coexist without confusion.

**Decision for this plan:**

- **Schema column names:** `source_bpm` / `performance_bpm`, `source_musical_key` / `performance_musical_key`, `source_tuning` / `performance_tuning`
- **Model field names:** `sourceBpm` / `performanceBpm`, `sourceMusicalKey` / `performanceMusicalKey`, `sourceTuning` / `performanceTuning`
- **UI labels:** "Original Recording" / "Your Performance" (or "Band's Version")
- **Existing dirty-tracking variables stay unchanged:** `_originalBpm` / `_currentBpm` etc. continue to mean "value at start of this edit session" vs "value during this edit session" — these are local UI state only, completely separate from the dual-value schema/model concept.

This terminology is non-colliding, semantically clear, and matches established Flutter/Dart conventions (camelCase for Dart, snake_case for SQL).

---

## 4. Reference Docs Consulted

**Phase 1 and Phase 2.1 prior art (mandatory per feature input):**

- `docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md` — Phase 1 (new-song enrichment with review screen), GetSongBPM integration, key normalization, ~75% accuracy accepted
- `docs/features/existing-song-enrichment/ARCHITECT_PLAN.md` — Phase 2.1 (existing-song batch enrichment), dual-provider flow (GetSongBPM for BPM/Key, iTunes/MusicBrainz for Duration), fill-missing-only RPC logic, three granularities (single/multi/catalog-wide)
- `docs/reference/bpm/BPM_FEATURE_IMPLEMENTATION.md`, `BPM_FEATURE_DEPLOYMENT.md`, `BPM_QUICK_REFERENCE.md` — Historical context for BPM feature (noted as partially stale per Phase 1 findings)

**Domain reference:**

- `docs/reference/architecture/database_schema.md` — Songs table structure (confirmed BPM/key/tuning are nullable single values)
- `docs/reference/general/AI_DECISIONS.md` — DECISION-004 (GetSongBPM integration)
- `docs/agents/GUARDRAILS.md` — RLS safety, async lifecycle, file size targets, data integrity non-negotiables
- `docs/agents/OPERATING_MODEL.md` — Four-role pipeline (Manager/Architect/Engineer/QA), gate requirements, minimal diff surface principle

**Code inspection (load-bearing for this plan):**

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart:1-550` — Current edit sheet structure, dirty-tracking variables, `_originalBpm` naming collision confirmed, save path via `_handleSave()` ~line 496
- `lib/features/setlists/setlist_detail_screen.dart:1723+` — PRIMARY DISPATCHER: `_handleSongTap()` awaits bottom sheet result, dispatches to per-field notifier methods
- `lib/features/setlists/models/song.dart:6-77` — Current Song model schema, single-value fields confirmed
- `lib/features/songs/song_enrichment_service.dart:1-150` — Phase 1/2.1 enrichment service, `SongEnrichmentResult` shape
- `lib/features/songs/services/song_enrichment_orchestrator.dart:1-150` — Phase 2.1 orchestrator, field-selection logic, RPC call pattern
- `lib/features/setlists/setlist_repository.dart` — 9 methods call `update_song_metadata` RPC (grep verified)
- `supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql` — Current prod RPC definition with tuning/bpm asymmetry
- `supabase/migrations/20260803153000_add_clear_musical_key_to_clear_song_metadata.sql` — Current prod `clear_song_metadata` RPC (4 params)

---

## 5. Existing System Analysis

### 5.1 Current Song Details Display (Single Value)

**Layout** (via `SegmentedButtonGroup`, `song_details_bottom_sheet.dart:1176+`):

```
Duration  │  BPM  │  Key  │  Tuning
  3:24    │ 120   │  Am   │  Drop D
```

Each row shows one value, taps to edit via the corresponding input dialog. No distinction between "what the recording is" vs "what we play."

### 5.2 Proposed Dual-Value Display (Song Details Only)

**Design decision rationale:**

Given the constraint "Song Details only — do not extend dual-value display/editing to song cards, setlist rows, catalog list" and the need to show/edit two independent values per field, several layouts were considered:

1. **Nested segmented rows** (Original Recording row above, Band's Version row below) — visually cleanest but violates the "don't change song cards" constraint since the segmented group IS shown on song cards in some flows.

2. **Side-by-side columns within each segment** — cramped on mobile, hard to distinguish which value is which.

3. **Expand-to-edit modal per field** — requires 3 taps to see both values (tap row → see source → tap again → see performance), too much friction.

4. **Vertical stacked pairs, one per field** — ✅ SELECTED. Clearest information architecture, no ambiguity, sufficient space, matches existing edit-flow patterns.

**Proposed layout:**

```
┌─────────────────────────────────────────────┐
│  BPM                                         │
│  ┌─────────────────────────────────────────┐│
│  │ Original Recording          120 BPM     ││  ← Tap to edit source BPM
│  └─────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────┐│
│  │ Your Performance            115 BPM     ││  ← Tap to edit performance BPM
│  └─────────────────────────────────────────┘│
├─────────────────────────────────────────────┤
│  Key                                         │
│  ┌─────────────────────────────────────────┐│
│  │ Original Recording          Am          ││  ← Tap to edit source key
│  └─────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────┐│
│  │ Your Performance            G           ││  ← Tap to edit performance key
│  └─────────────────────────────────────────┘│
├─────────────────────────────────────────────┤
│  Tuning                                      │
│  ┌─────────────────────────────────────────┐│
│  │ Original Recording          Standard    ││  ← Tap to edit source tuning
│  └─────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────┐│
│  │ Your Performance            Drop D      ││  ← Tap to edit performance tuning
│  └─────────────────────────────────────────┘│
└─────────────────────────────────────────────┘
```

**Behavior:**

- **"Original Recording"** row: Shows `source_bpm` / `source_musical_key` / `source_tuning` from the database. Populated by enrichment (GetSongBPM) or manual entry. Editable (user can correct if enrichment was wrong). Display: `"120 BPM"` or `"—"` if null.
- **"Your Performance"** row: Shows `performance_bpm` / `performance_musical_key` / `performance_tuning`. User-editable. Display: `"115 BPM"` or `"Not set (using original)"` if null.
- **Fallback display when performance is null:** Show a hint like `"Not set (using original)"` or just `"—"` — exact UX wording is Engineer's discretion, but the semantic is: "no performance override has been set, so in contexts where we need one value, we'd fall back to the source value."

**Duration stays single-value:** Duration row remains unchanged, one value, no dual-value split. Per Feature Input, duration is not subject to performance variation (bands don't intentionally play songs shorter/longer than the original as a practice choice — any duration difference is incidental, not a deliberate "we play this in 3:00 instead of 3:30" decision like key transposition or tempo change).

**What about song cards / catalog list / setlist rows?** They continue showing whatever single value they show today. The data model change (adding new columns) has unavoidable ripple effects on reads — those surfaces will need to pick ONE value to display (likely `performance_bpm` with fallback to `source_bpm` if null, or similar). That display logic change is **not** dual-value UI — it's just "read the new schema and pick the appropriate value." The Engineer must handle this to not break those surfaces, but must NOT add dual-value editing or side-by-side display there — that's explicitly out of scope per Feature Input.

---

## 6. Proposed Solution

### 6.1 What Changes (One Sentence)

Add six new nullable columns to `songs` table (`source_bpm`, `performance_bpm`, `source_musical_key`, `performance_musical_key`, `source_tuning`, `performance_tuning`), migrate existing single-value data to `source_*` columns, update Song Details bottom sheet to display/edit both values per field in a vertical stacked layout, extend `update_song_metadata` RPC with 6 new COALESCE (always-overwrite) parameters while keeping old params for backward compatibility, extend `clear_song_metadata` RPC with 6 new clear flags, and update Phase 2.1's enrichment flow to write to `source_*` columns with orchestrator-level NULL-checks for fill-missing-only semantics.

### 6.2 Database Changes

**Migration: `supabase/migrations/20260809120000_add_dual_value_bpm_key_tuning.sql`**

```sql
-- Add dual-value storage for BPM, musical key, and tuning.
-- Phase 2.2 of Song Data Enrichment initiative.
--
-- "source" = original recording metadata (from enrichment or manual entry)
-- "performance" = band's performance choice (user-controlled, never touched by enrichment)
--
-- Existing single-value columns (bpm, musical_key, tuning) are migrated to source_* columns.
-- Performance columns default to NULL (no override set yet).

-- 1. Add new columns
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS source_bpm INTEGER;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS performance_bpm INTEGER;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS source_musical_key TEXT;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS performance_musical_key TEXT;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS source_tuning TEXT;
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS performance_tuning TEXT;

COMMENT ON COLUMN public.songs.source_bpm IS
  'BPM of the original recording. Populated by enrichment or manual entry. Editable.';
COMMENT ON COLUMN public.songs.performance_bpm IS
  'BPM this band plays (performance override). User-controlled. NULL = no override, use source.';
COMMENT ON COLUMN public.songs.source_musical_key IS
  'Musical key of the original recording. Populated by enrichment or manual entry. Editable.';
COMMENT ON COLUMN public.songs.performance_musical_key IS
  'Musical key this band plays (performance override). User-controlled. NULL = no override, use source.';
COMMENT ON COLUMN public.songs.source_tuning IS
  'Tuning of the original recording. Populated by enrichment or manual entry. Editable.';
COMMENT ON COLUMN public.songs.performance_tuning IS
  'Tuning this band plays (performance override). User-controlled. NULL = no override, use source.';

-- 2. Migrate existing data: single-value columns → source columns
--    Performance columns stay NULL (no override was possible before this migration)
UPDATE public.songs
SET
  source_bpm = bpm,
  source_musical_key = musical_key,
  source_tuning = tuning
WHERE
  source_bpm IS NULL
  OR source_musical_key IS NULL
  OR source_tuning IS NULL;

-- 3. Old columns are kept for now (backward compatibility during rollout)
--    They are NOT dropped in this migration — that's a follow-up decision
--    after confirming all code paths use the new dual-value columns.
--
--    Deprecation note: As of Phase 2.2, `bpm`, `musical_key`, `tuning` columns
--    are considered deprecated. New code should use `source_*` / `performance_*`.

-- No RLS changes needed — new columns inherit existing RLS policies on songs table.
```

**Rationale for NOT dropping old columns immediately:**

- Safer rollout: existing code that reads `bpm` / `musical_key` / `tuning` continues working during gradual cutover.
- Allows rollback: if Phase 2.2 needs to be reverted, old columns still have the original data.
- Follow-up cleanup migration (Phase 2.3 or later) can drop them once all code is confirmed to use dual-value columns.

**Rollback strategy:** If this migration is rolled back, the new columns can be dropped and old columns still have the pre-migration data (unchanged). If songs were edited AFTER migration using the new dual-value UI, those edits would be lost on rollback — acceptable risk for a feature rollback.

### 6.3 RPC Changes (update_song_metadata)

**Migration: `supabase/migrations/20260809120001_update_song_metadata_dual_value.sql`**

Extend `update_song_metadata` RPC with 6 new dual-value parameters. **CRITICAL DESIGN DECISION:** Use COALESCE (always-overwrite) pattern for all 6 new dual-value columns to avoid write-once bug. Enrichment's fill-missing-only semantics move to orchestrator layer (NULL-check before calling RPC). **OLD PARAMS KEPT** — purely additive change to maintain backward compatibility with 9 existing call sites in `setlist_repository.dart`.

```sql
-- Extend update_song_metadata RPC to support dual-value BPM/key/tuning.
-- Phase 2.2 of Song Data Enrichment initiative.
--
-- DESIGN RATIONALE (addresses Manager gate review findings):
-- All 6 new dual-value columns use COALESCE (always-overwrite when param provided).
-- This matches tuning's existing behavior and prevents the write-once bug that existed
-- for bpm/musical_key (where second edit was silent no-op).
--
-- Enrichment fill-missing-only semantics are handled in orchestrator (NULL-check before call),
-- NOT in RPC. This separation allows:
-- - Enrichment: check if source_bpm IS NULL in orchestrator, only call RPC if true
-- - Direct user edits: always call RPC, always overwrite (user intent is explicit)
--
-- OLD PARAMETERS (p_bpm, p_musical_key, p_tuning) are KEPT for backward compatibility.
-- 9 existing call sites in setlist_repository.dart continue working unchanged.
-- Old params continue writing to old columns during rollout (will be dropped in Phase 2.3+).

DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION update_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  -- OLD single-value parameters (kept for backward compat with 9 call sites)
  p_bpm INTEGER DEFAULT NULL,
  p_duration_seconds INTEGER DEFAULT NULL,
  p_tuning TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_title TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL,
  p_youtube_links TEXT DEFAULT NULL,
  p_lyrics TEXT DEFAULT NULL,
  p_musical_key TEXT DEFAULT NULL,
  -- NEW: Dual-value parameters (Phase 2.2) — all use COALESCE (always overwrite)
  p_source_bpm INTEGER DEFAULT NULL,
  p_performance_bpm INTEGER DEFAULT NULL,
  p_source_musical_key TEXT DEFAULT NULL,
  p_performance_musical_key TEXT DEFAULT NULL,
  p_source_tuning TEXT DEFAULT NULL,
  p_performance_tuning TEXT DEFAULT NULL
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
  v_before_bpm INTEGER;
  v_before_duration INTEGER;
  v_before_key TEXT;
  v_new_bpm INTEGER;
  v_new_duration INTEGER;
  v_new_key TEXT;
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

  -- Capture BEFORE values for eligibility-aware verification (old columns only)
  SELECT bpm, duration_seconds, musical_key
  INTO v_before_bpm, v_before_duration, v_before_key
  FROM songs WHERE id = p_song_id;

  UPDATE songs
  SET
    -- NEW: Dual-value BPM — COALESCE = always overwrites when parameter provided
    source_bpm = COALESCE(p_source_bpm, source_bpm),
    performance_bpm = COALESCE(p_performance_bpm, performance_bpm),

    -- NEW: Dual-value musical key — COALESCE = always overwrites
    source_musical_key = COALESCE(p_source_musical_key, source_musical_key),
    performance_musical_key = COALESCE(p_performance_musical_key, performance_musical_key),

    -- NEW: Dual-value tuning — COALESCE = always overwrites (matches existing tuning behavior)
    source_tuning = COALESCE(p_source_tuning, source_tuning),
    performance_tuning = COALESCE(p_performance_tuning, performance_tuning),

    -- OLD single-value columns: kept unchanged for backward compat during rollout
    -- (These retain their existing CASE/COALESCE logic from 20260801120000 migration)
    bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END,
    duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END,
    tuning = COALESCE(p_tuning, tuning),
    musical_key = CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '') THEN p_musical_key ELSE musical_key END,

    -- Other fields (unchanged from current prod RPC)
    notes = CASE WHEN p_notes IS NOT NULL THEN p_notes ELSE notes END,
    title = COALESCE(p_title, title),
    artist = COALESCE(p_artist, artist),
    youtube_links = CASE WHEN p_youtube_links IS NOT NULL THEN p_youtube_links ELSE youtube_links END,
    lyrics = CASE WHEN p_lyrics IS NOT NULL THEN p_lyrics ELSE lyrics END,

    updated_at = NOW()
  WHERE id = p_song_id
  RETURNING bpm, duration_seconds, musical_key INTO v_new_bpm, v_new_duration, v_new_key;

  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;

  -- Eligibility-aware verification for OLD columns only (keep existing logic from 20260801120000)
  -- New dual-value columns use COALESCE (no verification needed — always succeed or fail atomically)

  IF p_bpm IS NOT NULL THEN
    IF v_before_bpm IS NULL THEN
      IF v_new_bpm IS DISTINCT FROM p_bpm THEN
        RETURN json_build_object(
          'success', false,
          'error', 'BPM update failed: requested ' || p_bpm || ', got ' || COALESCE(v_new_bpm::text, 'NULL')
        );
      END IF;
    END IF;
  END IF;

  IF p_duration_seconds IS NOT NULL THEN
    IF v_before_duration = 0 THEN
      IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN
        RETURN json_build_object(
          'success', false,
          'error', 'Duration update failed: requested ' || p_duration_seconds || ', got ' || COALESCE(v_new_duration::text, 'NULL')
        );
      END IF;
    END IF;
  END IF;

  IF p_musical_key IS NOT NULL THEN
    IF v_before_key IS NULL OR TRIM(v_before_key) = '' THEN
      IF v_new_key IS DISTINCT FROM p_musical_key THEN
        RETURN json_build_object(
          'success', false,
          'error', 'Musical key update failed: requested ' || p_musical_key || ', got ' || COALESCE(v_new_key, 'NULL')
        );
      END IF;
    END IF;
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION update_song_metadata TO authenticated;

COMMENT ON FUNCTION update_song_metadata IS
  'Update song metadata including dual-value BPM/key/tuning (Phase 2.2). All dual-value params use COALESCE (always overwrite when provided). Enrichment fill-missing-only logic handled in orchestrator layer via NULL-checks. Old params (p_bpm, p_musical_key, p_tuning) kept for backward compat with 9 existing call sites. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';
```

**Backward compatibility:**

- Old callers passing `p_bpm`/`p_musical_key`/`p_tuning` → continue writing to old columns with existing CASE/COALESCE logic (unchanged)
- New callers passing `p_source_bpm`/`p_performance_bpm` etc. → write to new dual-value columns with COALESCE (always-overwrite)
- 9 existing call sites in `setlist_repository.dart` continue working without modification

### 6.4 Clear RPC Extension

**Migration: `supabase/migrations/20260809120002_extend_clear_song_metadata_dual_value.sql`**

Extend `clear_song_metadata` RPC to support clearing the 6 new dual-value columns. Current prod RPC has 4 clear flags (bpm, duration, tuning, musical_key); add 6 new flags for source/performance pairs.

```sql
-- Extend clear_song_metadata to support clearing dual-value BPM/key/tuning columns.
-- Phase 2.2 of Song Data Enrichment initiative.

DROP FUNCTION IF EXISTS clear_song_metadata(UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN);

CREATE OR REPLACE FUNCTION clear_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  -- OLD single-value clear flags (kept for rollout, deprecated)
  p_clear_bpm BOOLEAN DEFAULT FALSE,
  p_clear_duration BOOLEAN DEFAULT FALSE,
  p_clear_tuning BOOLEAN DEFAULT FALSE,
  p_clear_musical_key BOOLEAN DEFAULT FALSE,
  -- NEW dual-value clear flags (Phase 2.2)
  p_clear_source_bpm BOOLEAN DEFAULT FALSE,
  p_clear_performance_bpm BOOLEAN DEFAULT FALSE,
  p_clear_source_musical_key BOOLEAN DEFAULT FALSE,
  p_clear_performance_musical_key BOOLEAN DEFAULT FALSE,
  p_clear_source_tuning BOOLEAN DEFAULT FALSE,
  p_clear_performance_tuning BOOLEAN DEFAULT FALSE
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

  -- At least one clear flag must be set
  IF NOT (
    p_clear_bpm OR p_clear_duration OR p_clear_tuning OR p_clear_musical_key OR
    p_clear_source_bpm OR p_clear_performance_bpm OR
    p_clear_source_musical_key OR p_clear_performance_musical_key OR
    p_clear_source_tuning OR p_clear_performance_tuning
  ) THEN
    RETURN json_build_object('success', false, 'error', 'No clear flags provided');
  END IF;

  UPDATE songs
  SET
    -- OLD single-value clears (kept for rollout, deprecated)
    bpm = CASE WHEN p_clear_bpm THEN NULL ELSE bpm END,
    duration_seconds = CASE WHEN p_clear_duration THEN 0 ELSE duration_seconds END,
    tuning = CASE WHEN p_clear_tuning THEN NULL ELSE tuning END,
    musical_key = CASE WHEN p_clear_musical_key THEN NULL ELSE musical_key END,
    -- NEW dual-value clears (Phase 2.2)
    source_bpm = CASE WHEN p_clear_source_bpm THEN NULL ELSE source_bpm END,
    performance_bpm = CASE WHEN p_clear_performance_bpm THEN NULL ELSE performance_bpm END,
    source_musical_key = CASE WHEN p_clear_source_musical_key THEN NULL ELSE source_musical_key END,
    performance_musical_key = CASE WHEN p_clear_performance_musical_key THEN NULL ELSE performance_musical_key END,
    source_tuning = CASE WHEN p_clear_source_tuning THEN NULL ELSE source_tuning END,
    performance_tuning = CASE WHEN p_clear_performance_tuning THEN NULL ELSE performance_tuning END,
    updated_at = NOW()
  WHERE id = p_song_id;

  GET DIAGNOSTICS v_update_count = ROW_COUNT;
  IF v_update_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'Update failed unexpectedly');
  END IF;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION clear_song_metadata TO authenticated;

COMMENT ON FUNCTION clear_song_metadata IS
  'Clears selected song metadata fields (dual-value BPM/key/tuning added in Phase 2.2). SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id.';
```

### 6.5 Model Changes

**File: `lib/features/setlists/models/song.dart`**

Add six new fields to `Song` class:

```dart
class Song {
  final String id;
  final String title;
  final String artist;

  // OLD single-value fields (deprecated in Phase 2.2, kept for backward compat during rollout)
  @Deprecated('Use sourceBpm/performanceBpm instead')
  final int? bpm;
  @Deprecated('Use sourceMusicalKey/performanceMusicalKey instead')
  final String? musicalKey;
  @Deprecated('Use sourceTuning/performanceTuning instead')
  final String? tuning;

  // NEW dual-value fields (Phase 2.2)
  final int? sourceBpm;
  final int? performanceBpm;
  final String? sourceMusicalKey;
  final String? performanceMusicalKey;
  final String? sourceTuning;
  final String? performanceTuning;

  final int durationSeconds; // unchanged, still single-value
  final String? albumArtwork;
  final String bandId;
  final String? spotifyId;
  final String? musicbrainzId;
  final String? notes;
  final String? youtubeLinks;
  final String? lyrics;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    @Deprecated('Use sourceBpm/performanceBpm') this.bpm,
    @Deprecated('Use sourceMusicalKey/performanceMusicalKey') this.musicalKey,
    @Deprecated('Use sourceTuning/performanceTuning') this.tuning,
    this.sourceBpm,
    this.performanceBpm,
    this.sourceMusicalKey,
    this.performanceMusicalKey,
    this.sourceTuning,
    this.performanceTuning,
    required this.durationSeconds,
    this.albumArtwork,
    required this.bandId,
    this.spotifyId,
    this.musicbrainzId,
    this.notes,
    this.youtubeLinks,
    this.lyrics,
  });

  /// Get the effective BPM to display (performance if set, else source)
  int? get effectiveBpm => performanceBpm ?? sourceBpm;

  /// Get the effective key to display (performance if set, else source)
  String? get effectiveMusicalKey => performanceMusicalKey ?? sourceMusicalKey;

  /// Get the effective tuning to display (performance if set, else source)
  String? get effectiveTuning => performanceTuning ?? sourceTuning;

  factory Song.fromSupabase(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      artist: json['artist'] as String? ?? 'Unknown Artist',
      // Old fields (kept for rollout, deprecated)
      bpm: json['bpm'] as int?,
      musicalKey: json['musical_key'] as String?,
      tuning: json['tuning'] as String?,
      // New dual-value fields
      sourceBpm: json['source_bpm'] as int?,
      performanceBpm: json['performance_bpm'] as int?,
      sourceMusicalKey: json['source_musical_key'] as String?,
      performanceMusicalKey: json['performance_musical_key'] as String?,
      sourceTuning: json['source_tuning'] as String?,
      performanceTuning: json['performance_tuning'] as String?,
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      albumArtwork: json['album_artwork'] as String?,
      bandId: json['band_id'] as String,
      spotifyId: json['spotify_id'] as String?,
      musicbrainzId: json['musicbrainz_id'] as String?,
      notes: json['notes'] as String?,
      youtubeLinks: json['youtube_links'] as String?,
      lyrics: json['lyrics'] as String?,
    );
  }
}
```

**`SetlistSong` model** (`lib/features/setlists/models/setlist_song.dart`) inherits from `Song` or wraps it — update identically.

**Helper getters** (`effectiveBpm`, `effectiveMusicalKey`, `effectiveTuning`):

- Used by song cards, setlist rows, catalog list — anywhere that needs to display ONE value (not dual).
- Fallback logic: `performance ?? source` — if the band has set a performance override, show that; else show the source/original value.
- This is the ONLY place where "pick one value" logic lives — all other code should explicitly choose which field to read (source or performance), not rely on a magic fallback.

### 6.6 Song Details UI Changes

**File: `lib/features/setlists/widgets/song_details_bottom_sheet.dart`**

**Current structure** (single-value):

- `SegmentedButtonGroup` with 4 rows: Duration | BPM | Key | Tuning
- Each row shows one value, taps to edit via dialog

**New structure** (dual-value for BPM/Key/Tuning):

Replace the single `SegmentedButtonGroup` with:

1. **Duration row** (unchanged, single-value)
2. **BPM section** (dual-value):
   - "BPM" header
   - Two tappable rows: "Original Recording" / "Your Performance"
   - Each row opens `showBpmInputDialog()` with appropriate initial value
   - On save, writes to the correct field (source vs performance)
3. **Key section** (dual-value):
   - "Key" header
   - Two tappable rows: "Original Recording" / "Your Performance"
   - Each row opens `showKeyPickerBottomSheet()`
4. **Tuning section** (dual-value):
   - "Tuning" header
   - Two tappable rows: "Original Recording" / "Your Performance"
   - Each row opens `showTuningPickerBottomSheet()`

**State variables:**

Extend existing dirty-tracking pattern (no naming collision — see §3.4):

```dart
// Source values (original recording)
late int? _currentSourceBpm;
late int? _originalSourceBpm;  // for dirty tracking THIS edit session
late String? _currentSourceMusicalKey;
late String? _originalSourceMusicalKey;
late String? _currentSourceTuning;
late String? _originalSourceTuning;

// Performance values (band's version)
late int? _currentPerformanceBpm;
late int? _originalPerformanceBpm;
late String? _currentPerformanceMusicalKey;
late String? _originalPerformanceMusicalKey;
late String? _currentPerformanceTuning;
late String? _originalPerformanceTuning;

// Existing dirty-tracking variables STAY UNCHANGED:
// _originalBpm, _currentBpm, etc. can be removed as part of the cutover,
// but this plan does not require removing them (less risky to leave as dead code).
```

**Change detection:**

```dart
void _checkForChanges() {
  final sourceBpmChanged = _currentSourceBpm != _originalSourceBpm;
  final performanceBpmChanged = _currentPerformanceBpm != _originalPerformanceBpm;
  final sourceKeyChanged = _currentSourceMusicalKey != _originalSourceMusicalKey;
  final performanceKeyChanged = _currentPerformanceMusicalKey != _originalPerformanceMusicalKey;
  final sourceTuningChanged = _currentSourceTuning != _originalSourceTuning;
  final performanceTuningChanged = _currentPerformanceTuning != _originalPerformanceTuning;

  final hasChanges =
    sourceBpmChanged || performanceBpmChanged ||
    sourceKeyChanged || performanceKeyChanged ||
    sourceTuningChanged || performanceTuningChanged ||
    /* ...existing checks for title/artist/notes/duration/etc. */;

  setState(() => _hasChanges = hasChanges);
}
```

**Display logic:**

For each dual-value field:

- **Source row:** `_currentSourceBpm?.toString() ?? '—'`
- **Performance row:** `_currentPerformanceBpm?.toString() ?? 'Not set (using original)'`

The phrase `"Not set (using original)"` (or similar Engineer-chosen wording) makes the fallback semantic explicit to the user.

**Save logic:**

```dart
SongDetailsResult(
  // ...existing fields...
  sourceBpm: _currentSourceBpm,
  performanceBpm: _currentPerformanceBpm,
  sourceMusicalKey: _currentSourceMusicalKey,
  performanceMusicalKey: _currentPerformanceMusicalKey,
  sourceTuning: _currentSourceTuning,
  performanceTuning: _currentPerformanceTuning,
  sourceBpmChanged: _currentSourceBpm != _originalSourceBpm,
  performanceBpmChanged: _currentPerformanceBpm != _originalPerformanceBpm,
  sourceMusicalKeyChanged: _currentSourceMusicalKey != _originalSourceMusicalKey,
  performanceMusicalKeyChanged: _currentPerformanceMusicalKey != _originalPerformanceMusicalKey,
  sourceTuningChanged: _currentSourceTuning != _originalSourceTuning,
  performanceTuningChanged: _currentPerformanceTuning != _originalPerformanceTuning,
);
```

`SongDetailsResult` class gains 6 new fields + 6 new `*Changed` flags (12 additions total). Calling code (`setlist_detail_screen.dart:_handleSongTap()` ~line 1723) dispatches these to per-field notifier methods.

### 6.7 Enrichment Integration Update

**Phase 2.1's enrichment writes to single-value columns today.** Once dual-value columns exist, enrichment must write to **source columns only** (never performance). Fill-missing-only enforcement already exists in orchestrator NULL-check logic (lines 110-113, 131-133) — just needs to read the new dual-value fields.

**File: `lib/features/songs/services/song_enrichment_orchestrator.dart`**

**Three changes:**

1. **Lines 110 and 131** — Update existing NULL-checks to read new dual-value fields:

```dart
// OLD (Phase 2.1)
final needsBpm = enrichBpm && song.bpm == null;
final needsKey = enrichKey && song.musicalKey == null;

// NEW (Phase 2.2)
final needsBpm = enrichBpm && song.sourceBpm == null;
final needsKey = enrichKey && song.sourceMusicalKey == null;
```

2. **Lines 216 and 220** — Update `updateMap` keys when building batch update:

```dart
// OLD (Phase 2.1)
final updateMap = <String, dynamic>{};
if (fetchedBpm != null) updateMap['bpm'] = fetchedBpm;
if (fetchedKey != null) updateMap['musicalKey'] = fetchedKey;

// NEW (Phase 2.2)
final updateMap = <String, dynamic>{};
if (fetchedBpm != null) updateMap['sourceBpm'] = fetchedBpm;
if (fetchedKey != null) updateMap['sourceMusicalKey'] = fetchedKey;
```

**File: `lib/features/setlists/setlist_repository.dart`**

**Method: `enrichSongs()` at line 3456** (batch-shaped, used by orchestrator)

3. **Lines 3477 and 3485** — Update RPC parameter mapping:

```dart
// OLD (Phase 2.1)
final result = await supabase.rpc(
  'update_song_metadata',
  params: {
    'p_song_id': songId,
    'p_band_id': bandId,
    'p_bpm': update['bpm'],
    'p_duration_seconds': update['durationSeconds'],
    'p_tuning': null,
    'p_notes': null,
    'p_title': null,
    'p_artist': null,
    'p_youtube_links': null,
    'p_lyrics': null,
    'p_musical_key': update['musicalKey'],
  },
);

// NEW (Phase 2.2)
final result = await supabase.rpc(
  'update_song_metadata',
  params: {
    'p_song_id': songId,
    'p_band_id': bandId,
    'p_source_bpm': update['sourceBpm'],
    'p_duration_seconds': update['durationSeconds'],
    'p_tuning': null,
    'p_notes': null,
    'p_title': null,
    'p_artist': null,
    'p_youtube_links': null,
    'p_lyrics': null,
    'p_source_musical_key': update['sourceMusicalKey'],
  },
);
```

**Note:** The `enrichSongs()` method signature does NOT change — it's batch-shaped (`Map<String, Map<String, dynamic>> updates`) and remains that way. Only the keys read from the `update` map and the RPC parameter names change.

**Critical:** Song cards, catalog list, setlist rows currently read `bpm`, `musical_key`, `tuning` columns (single-value). Once dual-value columns exist and old columns are populated by backward-compat RPC logic, these surfaces MUST be updated to read the new columns.

**Files affected:**

- Any Supabase query that selects `bpm, musical_key, tuning` from `songs` or `setlist_songs` tables.
- Confirmed locations: `SetlistRepository.fetchSongsForSetlist()`, `fetchSongsForBand()` (catalog), and any other select query.

**Change:**

```dart
// OLD
.select('id, title, artist, bpm, musical_key, tuning, duration_seconds, ...')

// NEW
.select('id, title, artist, source_bpm, performance_bpm, source_musical_key, performance_musical_key, source_tuning, performance_tuning, duration_seconds, ...')
```

**Display logic:** Use the `effectiveBpm` / `effectiveMusicalKey` / `effectiveTuning` getters from the `Song` model. These surfaces show ONE value, not dual — the getter handles the fallback (`performance ?? source`).

**No UI change on these surfaces** — they continue displaying a single BPM/key/tuning value exactly as today, just sourced from the correct dual-value field via the helper getter. This is "minimum needed to not break them" per Feature Input scope boundary, not "add dual-value display."

---

## 7. Database Impact

### 7.1 Migrations Required

**Three migrations** (numbered sequentially):

1. **`20260809120000_add_dual_value_bpm_key_tuning.sql`** — Add six new columns, migrate existing data, add comments. No RLS changes (new columns inherit existing policies). No DROP of old columns (kept for rollout safety).

2. **`20260809120001_update_song_metadata_dual_value.sql`** — Extend `update_song_metadata` RPC with 6 new dual-value parameters (COALESCE pattern). OLD PARAMS KEPT for backward compatibility with 9 existing call sites. Purely additive.

3. **`20260809120002_extend_clear_song_metadata_dual_value.sql`** — Extend `clear_song_metadata` RPC with 6 new boolean clear flags.

### 7.2 RLS Impact

**None.** New columns are on the `songs` table, which already has RLS enabled and working. Adding nullable columns does not require new policies. The RPCs are already `SECURITY DEFINER` with band membership check — signature extension does not change their security posture.

### 7.3 Affected / Unaffected Summary

| Area                       | Status                                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `songs` table schema       | **Affected** — 6 new nullable columns added (`source_*`, `performance_*`)                                          |
| RLS policies               | Unaffected — new columns inherit existing policies                                                                 |
| `update_song_metadata` RPC | **Affected** — 6 new params added, old params kept (17 params total: 11 old + 6 new)                               |
| `clear_song_metadata` RPC  | **Affected** — 6 new clear flags added (10 params total: 4 old + 6 new)                                            |
| Any other RPC              | Unaffected                                                                                                         |
| Existing rows              | **Affected** — data migration copies `bpm`/`musical_key`/`tuning` to `source_*` columns, `performance_*` stay NULL |

---

## 8. Flutter Architecture Changes

### 8.1 State Management

**No new Riverpod providers needed.** The Song Details sheet is already a self-contained `StatefulWidget` with local state. The dual-value extension adds more local state variables (source/performance pairs), but no new provider or controller.

**Controller methods extended:** `SetlistDetailNotifier` gains 12 new methods (6 `updateSource*` / `updatePerformance*`, 6 `clearSource*` / `clearPerformance*`).

### 8.2 Model Changes

**`Song` model** gains 6 new fields + 3 helper getters. **`SetlistSong` model** (if separate) updated identically.

**`SongDetailsResult`** class gains 6 new fields + 6 new `*Changed` flags.

### 8.3 Service Changes

**No new service classes.** `SongEnrichmentService` unchanged (returns same `SongEnrichmentResult`). `SongEnrichmentOrchestrator` extended with NULL-checks before calling `enrichSong()`.

---

## 9. Files to Create

| File                                                                           | Justification                                                 |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `supabase/migrations/20260809120000_add_dual_value_bpm_key_tuning.sql`         | Add six new columns, migrate data (§6.2)                      |
| `supabase/migrations/20260809120001_update_song_metadata_dual_value.sql`       | Extend RPC with 6 new COALESCE params, keep old params (§6.3) |
| `supabase/migrations/20260809120002_extend_clear_song_metadata_dual_value.sql` | Extend clear RPC with 6 new clear flags (§6.4)                |

**No new Dart files.** All changes are modifications to existing files.

---

## 10. Files to Modify

| File                                                            | Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/models/song.dart`                        | Add 6 new fields (`source*`, `performance*`), add 3 helper getters (`effective*`), update `fromSupabase` factory (§6.5)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `lib/features/setlists/models/setlist_song.dart`                | Mirror `Song` model changes (if this is a separate class, not just a typedef)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart`  | Replace single-value BPM/Key/Tuning rows with dual-value sections (§6.6), add 12 new state variables (6 `_currentSource*`, 6 `_currentPerformance*`), extend `SongDetailsResult` with 6 new fields + 6 new `*Changed` flags, update change detection logic                                                                                                                                                                                                                                                                                                                                                       |
| `lib/features/setlists/setlist_detail_screen.dart`              | **PRIMARY DISPATCHER** (~line 1723): `_handleSongTap()` awaits `showSongDetailsBottomSheet()` result, dispatches to per-field notifier methods. Must add calls for 6 new dual-value fields: check `sourceBpmChanged`/`performanceBpmChanged` flags, call `notifier.updateSourceBpm()`/`notifier.updatePerformanceBpm()` or `clearSourceBpm()`/`clearPerformanceBpm()` methods. Same for key and tuning.                                                                                                                                                                                                          |
| `lib/features/setlists/setlist_detail_controller.dart`          | Add 6 new update methods: `updateSourceBpm()`, `updatePerformanceBpm()`, `updateSourceMusicalKey()`, `updatePerformanceMusicalKey()`, `updateSourceTuning()`, `updatePerformanceTuning()`. Add 6 corresponding `clear*` methods. Each calls repository → RPC with new dual-value params.                                                                                                                                                                                                                                                                                                                         |
| `lib/features/setlists/setlist_repository.dart`                 | Add 6 new methods: `updateSourceBpm()`, `updatePerformanceBpm()`, etc. (one per dual-value field). Each calls `update_song_metadata` RPC with appropriate `p_source_*` or `p_performance_*` param. Update `enrichSongs()` batch method (line 3477/3485): change `'p_bpm': update['bpm']` to `'p_source_bpm': update['sourceBpm']` and `'p_musical_key': update['musicalKey']` to `'p_source_musical_key': update['sourceMusicalKey']`. Add 6 new `clearSource*`/`clearPerformance*` methods (call `clear_song_metadata` RPC with appropriate flag). Update all `select()` queries to include new columns (§6.8). |
| `lib/features/songs/services/song_enrichment_orchestrator.dart` | Update existing NULL-checks (lines 110/131): change `song.bpm` to `song.sourceBpm` and `song.musicalKey` to `song.sourceMusicalKey`. Update `updateMap` keys (lines 216/220): change `'bpm'` to `'sourceBpm'` and `'musicalKey'` to `'sourceMusicalKey'` (§6.7).                                                                                                                                                                                                                                                                                                                                                 |

---

## 11. Files Off-Limits

| File                                                                 | Reason                                                                                                                                                                                               |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                      | Init order must not change; unrelated to this feature                                                                                                                                                |
| `lib/features/setlists/widgets/song_card.dart` (if this file exists) | Out of scope per Feature Input — song cards continue showing single value via `effectiveBpm` getter, no dual-value UI added                                                                          |
| `lib/features/setlists/widgets/setlist_song_card.dart` (or similar)  | Same — out of scope                                                                                                                                                                                  |
| `lib/features/setlists/widgets/song_lookup_overlay.dart`             | Unchanged — new-song lookup flow (Phase 1) already populates source values via enrichment review screen, no change needed                                                                            |
| `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`   | Phase 2.1 UI unchanged — enrichment still selects BPM/Duration/Key as before, no performance/source distinction exposed in that UI                                                                   |
| `lib/features/songs/song_enrichment_service.dart`                    | Service API unchanged — returns `SongEnrichmentResult` with `bpm`/`musicalKey` fields as before; only the CALLER (orchestrator) changes to add NULL-checks and map to `sourceBpm`/`sourceMusicalKey` |

---

## 12. System Impact Map

| System                                 | Impact                                                                                                                                                                           |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                                                                                                       |
| Rehearsals                             | unaffected                                                                                                                                                                       |
| Setlists / Catalog                     | **affected** — Song Details UI gains dual-value display/editing; song cards/rows updated to read new columns but NO UI change (still show single value via `effective*` getters) |
| Members / RBAC                         | unaffected — same edit permissions as today (band membership)                                                                                                                    |
| Auth / Session                         | unaffected                                                                                                                                                                       |
| Routing                                | unaffected                                                                                                                                                                       |
| Notifications                          | unaffected                                                                                                                                                                       |
| Platform (iOS / Android / Web / macOS) | **affected** — shared Flutter UI code, all four platforms get dual-value Song Details identically                                                                                |

---

## 13. Regression Risk

**Level: MEDIUM**

**Toward LOW:**

- Schema change is additive (six new nullable columns), no constraints, no RLS change — safest possible migration shape.
- RPC changes are purely additive (new params added, old params kept) — zero breaking changes to 9 existing call sites.
- Model change adds new fields but keeps old fields (deprecated but functional) — gradual cutover supported.
- Phase 2.1 enrichment update is localized (NULL-checks in orchestrator, one method signature change in repository) — small diff surface.
- No auth, session, routing, or init-order changes.

**Toward MEDIUM (why not LOW):**

- **Song Details UI is high-traffic** — this is the primary edit surface for all song metadata. Any bug in the new dual-value state management (12 new state variables, change detection logic) could break saving or cause data loss.
- **Data migration risk** — the `UPDATE ... SET source_bpm = bpm` migration writes to every existing row in the `songs` table. If the migration fails mid-execution (e.g., timeout on large dataset), rollback is required. Mitigation: test on a staging database with production-scale data first.
- **Query changes affect multiple surfaces** — updating all `select()` queries to include new columns (§6.8) touches every song-list fetch in the app. Missing one query could cause song cards to show `null` BPM/key/tuning even when values exist in the new columns.
- **No automated tests** — per Feature Input context, testing infrastructure exists but coverage is minimal. This change relies entirely on manual QA for validation.
- **Orchestrator-level fill-missing-only check-then-act race** — Moving fill-missing-only enforcement from RPC (CASE) to orchestrator (NULL-check before call) introduces a theoretical race: if two enrichment requests for the same song run concurrently, both could pass the NULL-check and both could write (last-write-wins). **ACCEPTED RISK:** App has no optimistic-concurrency pattern anywhere else (no ETags, no version columns, no compare-and-swap), so this is consistent with existing architecture. In practice, enrichment UI is single-threaded (user triggers once, waits for result), so race is unlikely. If it occurs, impact is benign (both writes are enrichment data from same source, no user data lost).

**Mitigations:**

- Extensive Tier 1/Tier 2/Tier 3 SQL tests (§15) — pre/post-deploy verification including COALESCE overwrite tests
- Manual end-to-end verification (§15) on all platforms — CRITICAL: test editing same field twice (catches write-once bug)
- Gradual rollout: deploy schema + RPCs first, then Flutter app changes, monitor for errors, rollback if needed

---

## 14. Engineer Task Breakdown

Execute in order. Tasks 1-4 are database/backend, Tasks 5-11 are Flutter, Task 12 is testing.

1. **Write and test schema migration** (§6.2)
   - Write `20260809120000_add_dual_value_bpm_key_tuning.sql`
   - Test locally: `supabase db push` (or equivalent)
   - Confirm new columns exist with correct types/nullability via `\d songs` or SQL query
   - Confirm data migration succeeded: verify a few existing songs have `source_bpm`/`source_musical_key`/`source_tuning` populated, `performance_*` are NULL

2. **Write and test RPC migration (update_song_metadata)** (§6.3)
   - Write `20260809120001_update_song_metadata_dual_value.sql`
   - **CRITICAL:** Use COALESCE for all 6 new dual-value params (always-overwrite), NOT fill-missing-only CASE
   - **KEEP old params** (`p_bpm`, `p_musical_key`, `p_tuning`) — purely additive, do not remove (9 call sites depend on them)
   - Test locally: apply migration
   - Confirm RPC signature via `\df update_song_metadata` (shows 17 params: 11 old + 6 new)
   - Run Tier 1 PRE-DEPLOY tests (§15) to establish baseline
   - Run Tier 2 POST-DEPLOY tests (§15) to verify dual-value logic works

3. **Write and test clear RPC migration** (§6.4)
   - Write `20260809120002_extend_clear_song_metadata_dual_value.sql`
   - Extend `clear_song_metadata` with 6 new boolean params (`p_clear_source_bpm`, `p_clear_performance_bpm`, etc.)
   - Test locally: apply migration
   - Confirm RPC signature via `\df clear_song_metadata` (shows 10 params: 4 old + 6 new)
   - Run Tier 3 POST-RPC TEST 5 (§15) to verify clearing `performance_bpm` to NULL works

4. **Update Song model** (§6.5)
   - Add 6 new fields to `Song` class (source/performance pairs)
   - Deprecate old fields (`@Deprecated('Use sourceBpm/performanceBpm instead')`)
   - Add 3 helper getters (`effectiveBpm`, `effectiveMusicalKey`, `effectiveTuning`)
   - Update `fromSupabase` factory to read new columns
   - Update `SetlistSong` model identically (if separate file)

5. **Update repository queries** (§6.8)
   - Find all `select()` calls that include `bpm, musical_key, tuning`
   - Add new columns to select: `source_bpm, performance_bpm, source_musical_key, performance_musical_key, source_tuning, performance_tuning`
   - Confirm song cards/catalog/setlist rows still work (via manual verification — they should show one value via `effective*` getters)

6. **Add repository methods for dual-value fields** (§10)
   - Add 6 new update methods to `SetlistRepository`: `updateSourceBpm()`, `updatePerformanceBpm()`, `updateSourceMusicalKey()`, `updatePerformanceMusicalKey()`, `updateSourceTuning()`, `updatePerformanceTuning()`
   - Each method calls `update_song_metadata` RPC with the appropriate `p_source_*` or `p_performance_*` parameter (all other params NULL)
   - Add 6 corresponding `clear*` methods: `clearSourceBpm()`, `clearPerformanceBpm()`, etc. (call `clear_song_metadata` RPC with appropriate flag)
   - Update existing `enrichSongs()` batch method (~line 3477/3485): change RPC parameter mapping from `'p_bpm': update['bpm']` to `'p_source_bpm': update['sourceBpm']` and `'p_musical_key': update['musicalKey']` to `'p_source_musical_key': update['sourceMusicalKey']`. Method signature unchanged (remains batch-shaped).

7. **Update enrichment orchestrator** (§6.7)
   - Update existing NULL-checks (~lines 110/131): change `song.bpm == null` to `song.sourceBpm == null` and `song.musicalKey == null` to `song.sourceMusicalKey == null` (preserves existing fill-missing-only semantics, just reads new dual-value fields)
   - Update `updateMap` keys (~lines 216/220): change `'bpm'` to `'sourceBpm'` and `'musicalKey'` to `'sourceMusicalKey'` when building batch update map
   - No new NULL-check logic needed — orchestrator already has the right pattern, just needs to read the new model fields

8. **Add controller methods for dual-value fields** (§10)
   - Add 6 new methods to `SetlistDetailNotifier`: `updateSourceBpm()`, `updatePerformanceBpm()`, `updateSourceMusicalKey()`, `updatePerformanceMusicalKey()`, `updateSourceTuning()`, `updatePerformanceTuning()`
   - Each calls the corresponding repository method
   - Add 6 corresponding `clearSourceBpm()`, `clearPerformanceBpm()`, etc. methods

9. **Extend SongDetailsResult** (§6.6, preparation)
   - Add 6 new fields: `sourceBpm`, `performanceBpm`, `sourceMusicalKey`, `performanceMusicalKey`, `sourceTuning`, `performanceTuning`
   - Add 6 new `*Changed` flags: `sourceBpmChanged`, `performanceBpmChanged`, etc.
   - Update constructor

10. **Update Song Details UI** (§6.6, main work)
    - **Song Details bottom sheet** (`song_details_bottom_sheet.dart`):
      - Replace single-value BPM/Key/Tuning rows with dual-value sections (2 rows each: "Original Recording" / "Your Performance")
      - Add 12 new state variables (6 `_currentSource*`, 6 `_originalSource*`, 6 `_currentPerformance*`, 6 `_originalPerformance*`)
      - Initialize all 12 from `widget.song` in `initState()`
      - Update change detection (`_checkForChanges()`) to include all 6 dual-value pairs
      - Update `_handleSave()` to populate new `SongDetailsResult` fields

11. **Update setlist detail screen dispatcher** (§10)
    - **Setlist detail screen** (`setlist_detail_screen.dart`):
      - Update `_handleSongTap()` (~line 1723+): add dispatch logic for 6 new dual-value fields
      - For each field: check `sourceBpmChanged` flag → call `notifier.updateSourceBpm()` or `notifier.clearSourceBpm()`
      - For each field: check `performanceBpmChanged` flag → call `notifier.updatePerformanceBpm()` or `notifier.clearPerformanceBpm()`
      - Same pattern for key and tuning (12 new dispatch branches total)
      - **Test CRITICAL scenario:** Open Song Details, edit performance BPM to 115, save, reopen, edit performance BPM to 110, save — verify second edit succeeds (no write-once bug)

12. **Manual verification per §15**
    - Run all manual end-to-end tests (single-value display surfaces, dual-value edit surfaces, enrichment integration, CRITICAL: test editing same field twice)
    - Run `flutter analyze` — 0 errors before proceeding

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (before `supabase db push`)

**Purpose:** Verify current schema baseline before migration.

- **PRE-DEPLOY TEST 1:** Confirm new columns do not exist yet (guards against re-running migration)

  ```sql
  SELECT column_name FROM information_schema.columns
  WHERE table_name = 'songs' AND column_name IN ('source_bpm', 'performance_bpm', 'source_musical_key', 'performance_musical_key', 'source_tuning', 'performance_tuning');
  -- Expected: 0 rows
  ```

- **PRE-DEPLOY TEST 2:** Confirm old columns exist and have data

  ```sql
  SELECT column_name, data_type, is_nullable FROM information_schema.columns
  WHERE table_name = 'songs' AND column_name IN ('bpm', 'musical_key', 'tuning')
  ORDER BY column_name;
  -- Expected: 3 rows (bpm INTEGER YES, musical_key TEXT YES, tuning TEXT YES)
  ```

- **PRE-DEPLOY TEST 3:** Sample existing data
  ```sql
  SELECT id, title, artist, bpm, musical_key, tuning
  FROM songs
  WHERE bpm IS NOT NULL OR musical_key IS NOT NULL OR tuning IS NOT NULL
  LIMIT 5;
  -- Expected: at least a few rows with non-null values (confirms migration will have data to copy)
  ```

### Tier 2 — Post-deployment (after schema migration, before RPC migrations)

- **POST-DEPLOY TEST 1:** Confirm new columns exist with correct types

  ```sql
  SELECT column_name, data_type, is_nullable FROM information_schema.columns
  WHERE table_name = 'songs' AND column_name IN ('source_bpm', 'performance_bpm', 'source_musical_key', 'performance_musical_key', 'source_tuning', 'performance_tuning')
  ORDER BY column_name;
  -- Expected: 6 rows, all nullable
  ```

- **POST-DEPLOY TEST 2:** Verify data migration succeeded (old → source)

  ```sql
  SELECT
    COUNT(*) FILTER (WHERE bpm IS NOT NULL AND source_bpm = bpm) as bpm_migrated,
    COUNT(*) FILTER (WHERE bpm IS NOT NULL AND source_bpm IS NULL) as bpm_not_migrated,
    COUNT(*) FILTER (WHERE musical_key IS NOT NULL AND source_musical_key = musical_key) as key_migrated,
    COUNT(*) FILTER (WHERE musical_key IS NOT NULL AND source_musical_key IS NULL) as key_not_migrated,
    COUNT(*) FILTER (WHERE tuning IS NOT NULL AND source_tuning = tuning) as tuning_migrated,
    COUNT(*) FILTER (WHERE tuning IS NOT NULL AND source_tuning IS NULL) as tuning_not_migrated
  FROM songs;
  -- Expected: *_migrated counts match row counts with non-null old values, *_not_migrated = 0
  ```

- **POST-DEPLOY TEST 3:** Verify performance columns are all NULL (no pre-existing data)
  ```sql
  SELECT COUNT(*) FROM songs WHERE performance_bpm IS NOT NULL OR performance_musical_key IS NOT NULL OR performance_tuning IS NOT NULL;
  -- Expected: 0 (performance columns should be empty after migration)
  ```

### Tier 3 — Post-RPC migrations (both update and clear RPCs)

- **POST-RPC TEST 1:** Confirm update_song_metadata RPC signature updated

  ```sql
  SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'update_song_metadata';
  -- Expected: 17 parameters (11 old + 6 new dual-value params)
  -- Verify old params p_bpm, p_musical_key, p_tuning are STILL PRESENT
  ```

- **POST-RPC TEST 2:** Test COALESCE write for source BPM (NULL → 130)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID;
    v_band_id UUID;
    v_result JSON;
  BEGIN
    -- Get a test song with NULL source_bpm
    SELECT id, band_id INTO v_test_song_id, v_band_id FROM songs WHERE source_bpm IS NULL LIMIT 1;

    -- Call RPC to set source_bpm = 130
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_source_bpm := 130
    );

    -- Verify: source_bpm should now be 130
    IF (SELECT source_bpm FROM songs WHERE id = v_test_song_id) = 130 THEN
      RAISE INFO '✓ POST-RPC TEST 2 PASSED: source_bpm set to 130';
    ELSE
      RAISE EXCEPTION '✗ POST-RPC TEST 2 FAILED';
    END IF;
  END $$;
  ```

- **POST-RPC TEST 3:** Test COALESCE overwrite for source BPM (130 → 140, MUST succeed — critical for catching write-once bug)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID;
    v_band_id UUID;
    v_result JSON;
  BEGIN
    -- Get the test song from TEST 2 (should have source_bpm = 130)
    SELECT id, band_id INTO v_test_song_id, v_band_id FROM songs WHERE source_bpm = 130 LIMIT 1;

    -- Call RPC to OVERWRITE source_bpm = 140 (tests COALESCE, not CASE)
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_source_bpm := 140
    );

    -- Verify: source_bpm should now be 140 (overwrite succeeded)
    IF (SELECT source_bpm FROM songs WHERE id = v_test_song_id) = 140 THEN
      RAISE INFO '✓ POST-RPC TEST 3 PASSED: source_bpm overwritten to 140';
    ELSE
      RAISE EXCEPTION '✗ POST-RPC TEST 3 FAILED: write-once bug detected!';
    END IF;
  END $$;
  ```

- **POST-RPC TEST 4:** Test performance_bpm write-then-rewrite (NULL → 115 → 110 — THE critical test for Manager's identified bug scenario)

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID;
    v_band_id UUID;
    v_result JSON;
  BEGIN
    -- Get a test song with NULL performance_bpm
    SELECT id, band_id INTO v_test_song_id, v_band_id FROM songs WHERE performance_bpm IS NULL LIMIT 1;

    -- First write: set performance_bpm = 115
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_performance_bpm := 115
    );

    IF (SELECT performance_bpm FROM songs WHERE id = v_test_song_id) != 115 THEN
      RAISE EXCEPTION '✗ POST-RPC TEST 4 FAILED: first write failed';
    END IF;

    -- Second write: overwrite performance_bpm = 110 (CRITICAL test for write-once bug)
    v_result := update_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_performance_bpm := 110
    );

    -- Verify: performance_bpm should now be 110 (second write succeeded)
    IF (SELECT performance_bpm FROM songs WHERE id = v_test_song_id) = 110 THEN
      RAISE INFO '✓ POST-RPC TEST 4 PASSED: performance_bpm re-write succeeded (no write-once bug)';
    ELSE
      RAISE EXCEPTION '✗ POST-RPC TEST 4 FAILED: write-once bug detected (value stuck at 115)!';
    END IF;
  END $$;
  ```

- **POST-RPC TEST 5:** Test clear_song_metadata RPC extension

  ```sql
  DO $$
  DECLARE
    v_test_song_id UUID;
    v_band_id UUID;
    v_result JSON;
  BEGIN
    -- Get a test song with non-null performance_bpm
    SELECT id, band_id INTO v_test_song_id, v_band_id FROM songs WHERE performance_bpm IS NOT NULL LIMIT 1;

    -- Call clear RPC to null out performance_bpm
    v_result := clear_song_metadata(
      p_song_id := v_test_song_id,
      p_band_id := v_band_id,
      p_clear_performance_bpm := TRUE
    );

    -- Verify: performance_bpm should now be NULL
    IF (SELECT performance_bpm FROM songs WHERE id = v_test_song_id) IS NULL THEN
      RAISE INFO '✓ POST-RPC TEST 5 PASSED: performance_bpm cleared';
    ELSE
      RAISE EXCEPTION '✗ POST-RPC TEST 5 FAILED';
    END IF;
  END $$;
  ```

### Manual End-to-End Verification (Tony to run)

**Test platform:** iOS or macOS (native), plus Web (one platform from each category confirms cross-platform consistency).

#### Test Group 1: Song Cards / Catalog List (Single-Value Display, No Dual-Value UI)

1. Open Catalog → confirm song cards show BPM, key, tuning values (if present) — should display `effectiveBpm` / `effectiveMusicalKey` / `effectiveTuning` (performance if set, else source).
2. For a song with ONLY `source_bpm` (no `performance_bpm`): confirm card shows the source value.
3. For a song with BOTH `source_bpm` AND `performance_bpm`: confirm card shows the performance value (fallback logic correct).
4. Regression check: existing songs added before this migration should still show their original BPM/key/tuning values (migrated to `source_*` columns).

#### Test Group 2: Song Details Dual-Value Edit (BPM)

5. Open any song's details (from Catalog or setlist) → confirm Song Details bottom sheet opens.
6. **BPM section:** Confirm two rows — "Original Recording" and "Your Performance".
   - If song has `source_bpm = 120`, confirm "Original Recording" shows "120 BPM".
   - If song has `performance_bpm = null`, confirm "Your Performance" shows "Not set (using original)" (or similar wording).
7. Tap "Original Recording" BPM row → BPM input dialog opens → enter `125` → save.
   - Confirm dialog closes, "Original Recording" row now shows "125 BPM".
   - Save the sheet → verify database updated: `source_bpm = 125`, `performance_bpm` unchanged.
8. Tap "Your Performance" BPM row → BPM input dialog opens → enter `110` → save.
   - Confirm "Your Performance" row now shows "110 BPM".
   - Save the sheet → verify database updated: `performance_bpm = 110`, `source_bpm` unchanged.
9. Reopen the same song's details → confirm both values persisted correctly (125 / 110).
10. **CRITICAL:** Tap "Your Performance" BPM row again → change to `115` → save. Reopen → verify `performance_bpm = 115` (second edit succeeded, no write-once bug).
11. Tap "Your Performance" BPM row → clear the value (if input dialog supports clearing) → save.
    - Confirm "Your Performance" row returns to "Not set (using original)".
    - Verify database: `performance_bpm = null`.

#### Test Group 3: Musical Key Dual-Value Edit

12. Open a song with `source_musical_key = "Am"`, `performance_musical_key = null`.
13. Confirm "Original Recording" shows "Am", "Your Performance" shows "Not set...".
14. Tap "Your Performance" Key row → key picker opens → select "G" → save.
15. Confirm "Your Performance" row shows "G".
16. Save sheet → verify database: `source_musical_key = "Am"`, `performance_musical_key = "G"`.
17. Go back to Catalog → confirm song card shows "G" (performance fallback working).

#### Test Group 4: Tuning Dual-Value Edit

18. Open a song with `source_tuning = "Standard"`, `performance_tuning = null`.
19. Tap "Your Performance" Tuning row → tuning picker opens → select "Drop D" → save.
20. Confirm "Your Performance" row shows "Drop D".
21. Save sheet → verify database: `source_tuning = "Standard"`, `performance_tuning = "Drop D"`.

#### Test Group 5: Enrichment Integration (Phase 2.1)

22. Open a song with `source_bpm = null`, `source_musical_key = null` (un-enriched song).
23. Tap overflow menu → "Enrich Song Data".
24. Check BPM and Key (leave Duration unchecked) → tap "Enrich Songs".
25. Wait for enrichment to complete → results overlay shows "Updated" for BPM and Key (or "Not found" if GetSongBPM had no match).
26. Reopen song details → confirm "Original Recording" rows for BPM and Key are populated (if enrichment succeeded).
27. Confirm "Your Performance" rows are still "Not set..." (enrichment does NOT write to performance columns).
28. **Enrichment fill-missing-only test:** With same song (now has `source_bpm` populated), trigger enrichment again with BPM checked. Verify `source_bpm` is NOT overwritten (orchestrator NULL-check should skip the RPC call).

#### Test Group 6: Change Detection and Dirty Tracking

29. Open a song's details → change ONLY "Original Recording" BPM → do NOT save.
30. Tap "Cancel" or back button → confirm dirty-check dialog appears ("You have unsaved changes...").
31. Reopen → change ONLY "Your Performance" Key → tap "Cancel" → confirm dirty-check dialog.
32. Open song → change nothing → tap "Cancel" → confirm no dirty-check dialog (no changes).

#### Test Group 7: Regression Checks (Single-Value Fields)

33. Duration row: confirm unchanged (single-value, no dual-value UI).
34. Notes, YouTube links, Lyrics: confirm all unaffected by this feature (edit and save work as before).

#### Test Group 8: Multi-Platform Verification

35. Repeat tests 5-10 on Web (if different from native platform tested above) — confirm dual-value UI renders correctly, edits save, queries work.

---

## 16. QA Regression Areas

1. **Song Details dual-value editing** (all steps in §15 Test Groups 2-4) — highest priority, this is the core new surface. **CRITICAL: Test editing same field twice (Group 2 Test 10) to catch write-once bug.**
2. **Song cards / catalog list / setlist rows single-value display** (§15 Test Group 1) — regression check that fallback logic (`effective*` getters) works correctly.
3. **Enrichment integration** (§15 Test Group 5) — verify Phase 2.1's enrichment writes to `source_*` columns only, never `performance_*`. Verify enrichment doesn't overwrite existing `source_*` values (orchestrator NULL-check working).
4. **Change detection and dirty tracking** (§15 Test Group 6) — verify the new dual-value state variables integrate correctly with existing dirty-check logic, no false positives/negatives.
5. **Backward compatibility** (SQL Tier 3 POST-RPC TEST 1) — verify old RPC parameters (`p_bpm`, `p_musical_key`, `p_tuning`) still exist and work with 9 existing call sites.
6. **Data migration integrity** (SQL Tier 2 POST-DEPLOY TEST 2) — verify all existing `bpm`/`musical_key`/`tuning` values were correctly copied to `source_*` columns, no data loss.
7. **COALESCE overwrite logic** (SQL Tier 3 POST-RPC TEST 3-4) — verify all 6 new dual-value columns can be edited multiple times (no write-once bug).
8. **Clear RPC extension** (SQL Tier 3 POST-RPC TEST 5, Manual Test Group 2 Test 11) — verify clearing `performance_*` values to NULL works.
9. **Platform consistency** (§15 Test Group 8) — confirm dual-value UI works identically on iOS/Android/macOS/Web.
10. **`flutter analyze`** — 0 errors.

---

## 17. Rollout / Migration Strategy

**Prerequisite:** Staging database test (recommended, not mandatory per Feature Input, but strongly advised given data migration scope) — apply all three migrations to a copy of production data, run Tier 1-3 SQL tests, confirm no migration failures or data corruption.

**Rollout sequence:**

1. **Deploy schema migration:** `supabase db push` (or manual `psql` execution) — applies `20260809120000_add_dual_value_bpm_key_tuning.sql`. Safe, additive, ~instantaneous for small datasets, may take seconds-to-minutes for large datasets (UPDATE every row). **Downtime: none** — old columns still exist, old code still works.

2. **Deploy RPC migrations:** Apply `20260809120001_update_song_metadata_dual_value.sql` and `20260809120002_extend_clear_song_metadata_dual_value.sql`. Safe, purely additive (old params kept). **Downtime: none** — 9 existing call sites continue working unchanged.

3. **Run Tier 2 + Tier 3 SQL tests** (§15) — verify schema and RPC changes are correct before deploying Flutter app.

4. **Deploy Flutter app changes:** `./tools/deploy_web.sh` (Web) / normal store/TestFlight process (iOS/Android/macOS). **No special sequencing needed** — schema and RPCs already support dual-value reads/writes, so the new Flutter code works immediately upon deployment.

5. **Post-deploy:** Run §15 manual end-to-end tests (Test Groups 1-8), especially CRITICAL Test Group 2 Test 10 (edit same field twice).

**Rollback:**

- **Flutter changes:** Git revert → redeploy app. Any songs edited using the new dual-value UI will have `performance_*` values set; reverting the app loses the ability to view/edit those via UI, but the data remains in the database (no data loss, just inaccessible until re-deployed).
- **RPC changes:** Can be rolled back by restoring previous RPC definitions (drop dual-value params). Any dual-value edits made after the new RPC deployed would be lost.
- **Schema changes:** New columns can be dropped (`ALTER TABLE songs DROP COLUMN source_bpm, ...`) if needed. Data migration (`source_* ← bpm/musical_key/tuning`) is irreversible without a backup — **strongly recommend database backup before migration** per standard practice.

---

## 18. Out of Scope

Explicitly not part of Phase 2.2 (per Feature Input and this plan's scope discipline):

1. **Dual-value display on song cards, setlist rows, catalog list** — these surfaces continue showing ONE value via `effective*` getters, no side-by-side original/performance display.
2. **Duration dual-value** — duration remains single-value per explicit Tony decision (not a performance-varied field).
3. **Tuning auto-fill / enrichment** — tuning is user-controlled only, no automatic population (Phase 2.5 research topic).
4. **Lyrics enrichment** — Phase 2.4, separate.
5. **Data-source settings screen** — Phase 2.3, separate.
6. **Dropping old `bpm`/`musical_key`/`tuning` columns** — kept for rollout safety; cleanup is a separate follow-up migration decision.
7. **Original-vs-performance for other fields** (album artwork, Spotify ID, etc.) — not requested, not implemented.
8. **"Revert to original" button** — UI design choice deferred to Engineer; the capability exists (user can manually copy source value to performance field or clear performance field), but a dedicated one-tap revert action is not specified.

---

## 19. Open Questions for Tony

None blocking Engineer work. The following are noted for future-phase consideration but do not block Phase 2.2 implementation:

1. **When to drop old `bpm`/`musical_key`/`tuning` columns?** This plan keeps them for rollout safety. A follow-up migration (Phase 2.3 or later) can drop them once all code is confirmed to use dual-value columns only. Confirm timing.

2. **Performance value display wording:** This plan proposes `"Not set (using original)"` when `performance_bpm` is null. Alternative wordings: `"Same as original"`, `"—"` (just a dash), `"Default"`. Engineer's discretion unless you have a strong preference.

3. **Enrichment re-run behavior:** If a user manually edits `source_bpm` (correcting a wrong enrichment result) and then triggers enrichment again, should enrichment overwrite the manually-corrected source value? Current design (orchestrator NULL-check) says NO (it won't call RPC if `source_bpm` is non-null). This means a user who wants to "re-enrich" would have to manually clear the source field first. Is this acceptable, or should there be a "force re-enrich" option?

---

**End of ARCHITECT_PLAN.md**
