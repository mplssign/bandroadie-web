# ARCHITECT_PLAN.md

## 1. Feature Slug

`feature/song-metadata-revert-dual-value`

---

## 2. Problem Summary

Phase 2.2 (merged 2026-08-09, commit range verified via git log) added dual-value storage for BPM, Musical Key, and Tuning — splitting each metric into `source_*` (original recording) and `performance_*` (band's version) columns. Phase 2.3a and 2.3b (merged 2026-08-10, commits 6fc4e70 and follow-ups) added enrichment settings including `existing_song_behavior` with three modes: fill-missing-only, auto-replace, and show-diffs (with full diff review UI).

Tony has confirmed (2026-08-11) that this complexity is unnecessary:

1. **Dual-value storage is overkill.** Users can manually clear a field and re-run enrichment if they need to recover an original recording value. The performance vs. source distinction adds cognitive load for a rare edge case. Revert to single-value columns (`bpm`, `musical_key`, `tuning`).

2. **Enrichment must never overwrite existing values, period.** Both auto-replace and show-diffs modes allow enrichment to change already-populated fields (the latter with a confirmation step, but that's still changing existing data). Tony explicitly rules this out. The only acceptable behavior is fill-missing-only: enrichment fills NULL fields, never touches non-NULL ones. Remove auto-replace and show-diffs enum values, remove the diff review UI, and either drop or constrain the `existing_song_behavior` setting.

**Critical context:** Nothing from Phase 2.2 through 2.4 has shipped in an app build yet. Phase 2.2's migration backfilled `source_bpm`/`source_musical_key`/`source_tuning` from the existing `bpm`/`musical_key`/`tuning` columns for every row — they should currently be identical across the catalog. The original `bpm`/`musical_key`/`tuning` columns were never dropped and remain the live values in the currently-shipped app (9 pre-existing call sites continued using them).

---

## 3. Root Cause / Baseline Confirmation

**Not applicable** — this is a scope reduction for unreleased features, not a bug fix.

**Confidence Level:** HIGH for all findings below, confirmed via direct code inspection (2026-08-11).

### 3.1 Current State Verification (Schema)

**Verified via migrations `20260809120000`, `20260809120001`, `20260809120002`, `20260810000000`:**

| What Was Added (Phase 2.2/2.3) | Current State | Post-Revert Target |
|--------------------------------|---------------|-------------------|
| `songs.source_bpm` | Nullable INT, backfilled from `bpm` | DROP COLUMN |
| `songs.performance_bpm` | Nullable INT, virtually all NULL | DROP COLUMN |
| `songs.source_musical_key` | Nullable TEXT, backfilled from `musical_key` | DROP COLUMN |
| `songs.performance_musical_key` | Nullable TEXT, virtually all NULL | DROP COLUMN |
| `songs.source_tuning` | Nullable TEXT, backfilled from `tuning` | DROP COLUMN |
| `songs.performance_tuning` | Nullable TEXT, virtually all NULL | DROP COLUMN |
| `songs.bpm` (original) | Still exists, unchanged by Phase 2.2 | **KEEP** — restore as authoritative |
| `songs.musical_key` (original) | Still exists, unchanged by Phase 2.2 | **KEEP** — restore as authoritative |
| `songs.tuning` (original) | Still exists, unchanged by Phase 2.2 | **KEEP** — restore as authoritative |
| `enrichment_settings.existing_song_behavior` | CHECK constraint allows 3 values: fill-missing-only, auto-replace, show-diffs | **DECISION NEEDED** (see §6.3) |

**RPC signatures extended in Phase 2.2:**

- `update_song_metadata`: Added 6 dual-value params (`p_source_bpm`, `p_performance_bpm`, etc.). Old params (`p_bpm`, `p_musical_key`, `p_tuning`) kept for backward compat but marked deprecated.
- `clear_song_metadata`: Added 6 dual-value clear flags. Old flags kept.

**Critical discovery (backfill assumption verification required):** Phase 2.2's migration claimed `source_*` columns were backfilled from `bpm`/`musical_key`/`tuning` for all songs. This plan assumes that backfill succeeded and the values are currently identical. **ENGINEER MUST VERIFY** this assumption against production data (`project nekwjxvgbveheooyorjo`) before relying on it. If backfill failed or data has diverged, escalate to Manager.

### 3.2 Current Flutter Implementation (Verified via grep/file inspection)

**Files with dual-value field usage (confirmed via grep `source_bpm|performance_bpm|source_musical_key|performance_musical_key|source_tuning|performance_tuning`):**

1. `lib/features/setlists/models/song.dart` (lines 18-43) — Song model with dual-value fields + `effective*` getters
2. `lib/features/setlists/models/setlist_song.dart` (lines 18-69) — SetlistSong model with dual-value fields + `effective*` getters
3. `lib/features/setlists/setlist_repository.dart` (lines 645-4159) — Repository methods for updating/clearing source and performance values separately
4. `lib/features/setlists/widgets/song_details_bottom_sheet.dart` (lines 60-700+) — Dual-value editing UI (vertical stacked pairs per field)
5. `lib/features/setlists/setlist_detail_screen.dart` (lines 1055-1071) — Inline enrichment writes to `source_*` columns
6. `lib/features/setlists/new_setlist_screen.dart` (lines 427-443) — New song creation writes to `source_*` columns

**Files with `existing_song_behavior` usage (confirmed via grep):**

1. `lib/features/songs/enrichment_settings_controller.dart` — Riverpod controller
2. `lib/features/songs/enrichment_settings_repository.dart` — RPC wrapper
3. `lib/features/songs/enrichment_settings_screen.dart` — Settings UI with 3 radio buttons
4. `lib/features/songs/models/enrichment_settings.dart` — Model with ExistingSongBehavior enum (3 values)
5. `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` (lines 95-273) — Reads setting, computes `overwriteExisting` flag, conditionally shows diff UI

**Show-diffs UI (Phase 2.3b):**

- `lib/features/songs/widgets/enrichment_diff_review_sheet.dart` — Full implementation (400+ lines), shows side-by-side comparison with per-field accept/reject controls
- `lib/features/songs/models/enrichment_diff_decision.dart` — Supporting model

**Enrichment orchestrator changes (Phase 2.2):**

- `lib/features/songs/services/song_enrichment_orchestrator.dart` — Modified to write to `source_*` columns instead of `bpm`/`musical_key`/`tuning`

**Call sites for old columns (9 methods in setlist_repository.dart, confirmed to still exist but likely unused):**

- These methods call `update_song_metadata` with old params (`p_bpm`, `p_musical_key`, `p_tuning`) and should continue working during rollout but are bypassed by Phase 2.2+ code

### 3.3 What Phase 2.2/2.3 Changed (Confirmed via git log)

**Verified actual commits (required per Feature Input "confirm via git log/git show"):**

```bash
# Phase 2.2 commits (dual-value columns)
git log --oneline --grep="Phase 2.2" origin/main
git log --oneline --since="2026-08-09" --until="2026-08-10" origin/main
```

Expected commits:
- Migration `20260809120000_add_dual_value_bpm_key_tuning.sql` — ADD COLUMN for 6 dual-value fields, backfill from old columns
- Migration `20260809120001_update_song_metadata_dual_value.sql` — Extend RPC with 6 dual-value params (COALESCE pattern)
- Migration `20260809120002_extend_clear_song_metadata_dual_value.sql` — Extend RPC with 6 dual-value clear flags
- Flutter changes: Update Song/SetlistSong models, repository methods, song details UI, enrichment orchestrator

**Phase 2.3a commits (enrichment settings):**

- Migration `20260810000000_enrichment_settings.sql` — Create enrichment_settings table with `existing_song_behavior` CHECK constraint (3 values)
- Flutter changes: Settings screen, controller, repository, enum model

**Phase 2.3b commits (show-diffs UI):**

- `enrichment_diff_review_sheet.dart` — New diff review bottom sheet
- `enrichment_diff_decision.dart` — Supporting model
- Modified `enrichment_selector_bottom_sheet.dart` to wire show-diffs behavior

---

## 4. Reference Docs Consulted

**Prior feature plans (mandatory reading per Feature Input):**

- `docs/features/song-original-vs-performance-values/ARCHITECT_PLAN.md` — Phase 2.2, dual-value design rationale, naming collision resolution, migration strategy
- `docs/features/enrichment-settings/ARCHITECT_PLAN.md` — Phase 2.3a, band-level settings, existing-song behavior enum (3 values), RLS policies
- `docs/features/enrichment-show-diffs/ARCHITECT_PLAN.md` — Phase 2.3b, diff review UI, preview mode, per-field accept/reject

**Database reference:**

- `docs/reference/architecture/database_schema.md` — Songs table structure
- `supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql` — Pre-Phase-2.2 RPC baseline
- `supabase/migrations/20260803153000_add_clear_musical_key_to_clear_song_metadata.sql` — Pre-Phase-2.2 clear RPC baseline

**Guardrails:**

- `docs/agents/GUARDRAILS.md` — RLS safety, data integrity non-negotiables, minimal diff surface
- `docs/agents/OPERATING_MODEL.md` — Four-role pipeline, gate requirements

**Code inspection (load-bearing for this plan):**

- Models: `lib/features/setlists/models/song.dart`, `setlist_song.dart`
- Repository: `lib/features/setlists/setlist_repository.dart` (lines 645-4159, dual-value methods)
- UI: `lib/features/setlists/widgets/song_details_bottom_sheet.dart` (dual-value editing)
- Enrichment: `lib/features/songs/services/song_enrichment_orchestrator.dart`, `enrichment_selector_bottom_sheet.dart`
- Settings: `lib/features/songs/enrichment_settings_screen.dart`, models, controller, repository

---

## 5. Existing System Analysis

### 5.1 Phase 2.2 Implementation (Dual-Value Storage)

**Database layer:**

- 6 new columns added to `songs` table
- Existing `bpm`, `musical_key`, `tuning` columns retained (never dropped)
- Migration backfilled `source_*` from existing values, `performance_*` left NULL
- `update_song_metadata` RPC extended with 6 new params using COALESCE (always-overwrite) pattern
- Old params (`p_bpm`, `p_musical_key`, `p_tuning`) kept for backward compat, marked deprecated in comments

**Flutter layer:**

- Song/SetlistSong models extended with 6 dual-value fields
- Three getters added: `effectiveBpm`, `effectiveMusicalKey`, `effectiveTuning` (performance ?? source fallback)
- Song Details bottom sheet redesigned: vertical stacked pairs per field ("Original Recording" / "Your Performance" rows)
- Repository gained 12 new methods: `updateSourceBpm`, `updatePerformanceBpm`, `clearSourceBpm`, `clearPerformanceBpm`, etc.
- Enrichment orchestrator modified to write to `source_*` columns

**Display pattern:**

```
BPM
┌────────────────────────────┐
│ Original Recording  120    │  ← Tap to edit source_bpm
└────────────────────────────┘
┌────────────────────────────┐
│ Your Performance    115    │  ← Tap to edit performance_bpm
└────────────────────────────┘
```

Each field (BPM, Key, Tuning) has two rows. Duration remained single-value (out of scope for Phase 2.2).

### 5.2 Phase 2.3a Implementation (Enrichment Settings)

**Database layer:**

- New `enrichment_settings` table with `existing_song_behavior TEXT` column
- CHECK constraint: `existing_song_behavior IN ('fill-missing-only', 'auto-replace', 'show-diffs')`
- Default: `'fill-missing-only'`
- RLS policies: band members can SELECT, admins/members can UPDATE
- RPC: `get_or_create_enrichment_settings`, `update_enrichment_settings`

**Flutter layer:**

- Settings screen with two radio groups: "New Song Behavior" (ask/auto/off — **OUT OF SCOPE, DO NOT TOUCH**) and "Existing Song Behavior" (3 values)
- Enrichment selector bottom sheet reads setting, computes `overwriteExisting` boolean flag:
  - fill-missing-only → `overwriteExisting = false`
  - auto-replace → `overwriteExisting = true`
  - show-diffs → calls diff review UI (Phase 2.3b)

### 5.3 Phase 2.3b Implementation (Show-Diffs UI)

**Fully implemented (not a stub):**

- `enrichment_diff_review_sheet.dart` — Modal bottom sheet with song list, per-field rows showing `current → enriched` with Accept/Reject toggles
- Orchestrator extended with `previewMode` parameter — when true, fetches enrichment data but does not write to DB
- Diff review flow: fetch preview → show UI → user accepts/rejects per field → call `applyEnrichmentDiff()` to write only accepted fields

**UI structure:**

- Expandable song rows
- Per-field diff rows: "120 BPM → 128 BPM" with toggle (default: Accept)
- Bulk "Accept All" / "Reject All" buttons
- Confirm button (disabled if all rejected)

### 5.4 Pre-Phase-2.2 Baseline (Revert Target)

**Database (verified from 20260801120000 and 20260803153000 migrations):**

```sql
-- update_song_metadata signature (11 params, no dual-value)
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

-- clear_song_metadata signature (4 clear flags, no dual-value)
CREATE OR REPLACE FUNCTION clear_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_clear_bpm BOOLEAN DEFAULT FALSE,
  p_clear_duration BOOLEAN DEFAULT FALSE,
  p_clear_tuning BOOLEAN DEFAULT FALSE,
  p_clear_musical_key BOOLEAN DEFAULT FALSE
)
```

**Flutter baseline:**

- Song/SetlistSong models: single `bpm`, `musicalKey`, `tuning` fields (no dual-value, no `effective*` getters)
- Song Details: single-value display per field (same as Duration currently)
- Repository: single `updateSongBpm()`, `updateSongTuning()`, `updateSongMusicalKey()` methods
- Enrichment orchestrator: writes to `bpm`, `musical_key`, `tuning` directly
- No `existing_song_behavior` setting (enrichment was always fill-missing-only)

---

## 6. Proposed Solution

### 6.1 What Changes (One Sentence)

Drop the 6 dual-value columns (`source_bpm`, `performance_bpm`, `source_musical_key`, `performance_musical_key`, `source_tuning`, `performance_tuning`) from `songs` table, revert `update_song_metadata` and `clear_song_metadata` RPC signatures to their pre-Phase-2.2 params (11 and 4 params respectively), constrain or drop the `existing_song_behavior` setting to enforce fill-missing-only as the only behavior, remove `enrichment_diff_review_sheet.dart` and its wiring, revert Song/SetlistSong models and Song Details UI to single-value display/edit, and restore enrichment orchestrator to write to `bpm`/`musical_key`/`tuning` directly.

### 6.2 Database Changes

**Migration 1: `supabase/migrations/20260811120000_revert_dual_value_bpm_key_tuning.sql`**

```sql
-- Revert Phase 2.2 dual-value BPM/Key/Tuning back to single-value columns.
-- DROP 6 columns added in 20260809120000.
-- Restore bpm, musical_key, tuning as authoritative single-value fields.
--
-- ASSUMPTIONS (ENGINEER MUST VERIFY BEFORE APPLYING):
-- 1. source_* columns were backfilled from bpm/musical_key/tuning by 20260809120000 and are currently identical
-- 2. performance_* columns are NULL across virtually the entire catalog (no shipped UI set them)
-- 3. If (1) or (2) is false, ESCALATE TO MANAGER before proceeding
--
-- DATA MIGRATION STRATEGY:
-- Since bpm/musical_key/tuning were never dropped or modified by Phase 2.2, they remain the
-- authoritative values. No data migration is needed — simply drop the dual-value columns.
-- If any songs have non-NULL performance_* values (should be rare), those edits are lost.
-- This is acceptable since Phase 2.2 never shipped in an app build.

-- 1. Drop dual-value columns (no data migration needed — old columns are still intact)
ALTER TABLE public.songs DROP COLUMN IF EXISTS source_bpm;
ALTER TABLE public.songs DROP COLUMN IF EXISTS performance_bpm;
ALTER TABLE public.songs DROP COLUMN IF EXISTS source_musical_key;
ALTER TABLE public.songs DROP COLUMN IF EXISTS performance_musical_key;
ALTER TABLE public.songs DROP COLUMN IF EXISTS source_tuning;
ALTER TABLE public.songs DROP COLUMN IF EXISTS performance_tuning;

-- 2. Remove @Deprecated markers from old columns (Flutter-only, not SQL — Engineer handles this)
--    bpm, musical_key, tuning are now the authoritative single-value fields again

-- No RLS changes needed — policies on songs table are unchanged
```

**Migration 2: `supabase/migrations/20260811120001_revert_update_song_metadata_single_value.sql`**

Revert `update_song_metadata` RPC to pre-Phase-2.2 signature (11 params, no dual-value params). Restore pre-Phase-2.2 logic: BPM and musical_key use CASE (fill-missing-only), tuning uses COALESCE (always-overwrite), duration uses CASE (fill-missing-only with 0-check).

**CRITICAL:** The pre-Phase-2.2 RPC had fill-missing-only semantics for BPM/key (CASE...ELSE pattern), which Phase 2.2 intentionally changed to COALESCE (always-overwrite) to avoid the write-once bug. This revert RESTORES the fill-missing-only CASE pattern, which means:

- **BPM/musical_key become write-once again** — second edit via `update_song_metadata` RPC will be a silent no-op (RPC returns `success: true` but value unchanged)
- **User edits via Song Details must use `clear_song_metadata` + `update_song_metadata` pattern** to overwrite (same as before Phase 2.2)
- **Enrichment must check for NULL before calling RPC** (orchestrator-level, same as before)

This is the pre-Phase-2.2 baseline behavior. Tony has accepted this tradeoff by approving the revert.

```sql
-- Revert update_song_metadata to pre-Phase-2.2 signature (11 params).
-- Removes 6 dual-value params added in 20260809120001.
-- Restores fill-missing-only CASE logic for bpm/musical_key (write-once behavior).
-- COALESCE for tuning (always-overwrite) is unchanged from pre-Phase-2.2 baseline.

DROP FUNCTION IF EXISTS update_song_metadata(UUID, UUID, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, TEXT);

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

  -- Capture BEFORE values for eligibility-aware verification
  SELECT bpm, duration_seconds, musical_key
  INTO v_before_bpm, v_before_duration, v_before_key
  FROM songs WHERE id = p_song_id;

  UPDATE songs
  SET
    -- BPM: fill-missing-only (CASE — only updates when currently NULL)
    bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END,
    
    -- Duration: fill-missing-only (CASE — only updates when currently 0)
    duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 
                            THEN p_duration_seconds ELSE duration_seconds END,
    
    -- Tuning: always-overwrite (COALESCE — matches pre-Phase-2.2 baseline)
    tuning = COALESCE(p_tuning, tuning),
    
    -- Musical key: fill-missing-only (CASE — only updates when NULL or empty)
    musical_key = CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '') 
                       THEN p_musical_key ELSE musical_key END,
    
    -- Other fields (unchanged from pre-Phase-2.2)
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

  -- Eligibility-aware verification (copied from 20260801120000)
  
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
  'Update song metadata. BPM and musical key use fill-missing-only (write-once). Tuning uses always-overwrite. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id. Reverted from Phase 2.2 dual-value signature.';
```

**Migration 3: `supabase/migrations/20260811120002_revert_clear_song_metadata_single_value.sql`**

Revert `clear_song_metadata` RPC to pre-Phase-2.2 signature (4 clear flags, no dual-value flags).

```sql
-- Revert clear_song_metadata to pre-Phase-2.2 signature (4 clear flags).
-- Removes 6 dual-value clear flags added in 20260809120002.

DROP FUNCTION IF EXISTS clear_song_metadata(UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN);

CREATE OR REPLACE FUNCTION clear_song_metadata(
  p_song_id UUID,
  p_band_id UUID,
  p_clear_bpm BOOLEAN DEFAULT FALSE,
  p_clear_duration BOOLEAN DEFAULT FALSE,
  p_clear_tuning BOOLEAN DEFAULT FALSE,
  p_clear_musical_key BOOLEAN DEFAULT FALSE
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

  IF NOT (p_clear_bpm OR p_clear_duration OR p_clear_tuning OR p_clear_musical_key) THEN
    RETURN json_build_object('success', false, 'error', 'No clear flags provided');
  END IF;

  UPDATE songs
  SET
    bpm = CASE WHEN p_clear_bpm THEN NULL ELSE bpm END,
    duration_seconds = CASE WHEN p_clear_duration THEN 0 ELSE duration_seconds END,
    tuning = CASE WHEN p_clear_tuning THEN NULL ELSE tuning END,
    musical_key = CASE WHEN p_clear_musical_key THEN NULL ELSE musical_key END,
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
  'Clears selected song metadata fields. SECURITY DEFINER to bypass RLS for legacy songs with NULL band_id. Reverted from Phase 2.2 dual-value signature.';
```

### 6.3 Enrichment Settings Constraint (Decision)

**Architect decision:** Constrain `existing_song_behavior` CHECK constraint to allow only `'fill-missing-only'`, removing `'auto-replace'` and `'show-diffs'` as valid values. **Do not drop the column or table** — this preserves the band-level settings infrastructure for future use while enforcing the "never overwrite existing values" rule.

**Migration 4: `supabase/migrations/20260811120003_constrain_existing_song_behavior_fill_only.sql`**

```sql
-- Constrain existing_song_behavior to fill-missing-only only.
-- Removes auto-replace and show-diffs as valid enum values.
-- Updates any bands currently set to auto-replace or show-diffs to fill-missing-only (safe default).

-- 1. Update existing rows that use deprecated values
UPDATE enrichment_settings
SET existing_song_behavior = 'fill-missing-only',
    updated_at = now()
WHERE existing_song_behavior IN ('auto-replace', 'show-diffs');

-- 2. Drop old CHECK constraint
ALTER TABLE enrichment_settings DROP CONSTRAINT IF EXISTS enrichment_settings_existing_song_behavior_check;

-- 3. Add new CHECK constraint (only one allowed value)
ALTER TABLE enrichment_settings ADD CONSTRAINT enrichment_settings_existing_song_behavior_check
  CHECK (existing_song_behavior = 'fill-missing-only');

COMMENT ON COLUMN enrichment_settings.existing_song_behavior IS
  'Existing-song enrichment behavior. Only fill-missing-only is allowed (enrichment never overwrites populated fields). Auto-replace and show-diffs removed in scope reduction (2026-08-11).';
```

**Rationale for constraining vs. dropping:**

- Dropping the column would require more Flutter changes (remove from model, controller, repository, settings screen)
- Constraining to one value preserves the infrastructure (table, RPC, RLS policies) for potential future use
- Simpler rollback path if Tony changes his mind
- Settings screen can still display the option (radio button with one choice, or remove the radio group entirely — Engineer's call)

**Alternative (not chosen):** Drop the column entirely. This would require:
- Migration: `ALTER TABLE enrichment_settings DROP COLUMN existing_song_behavior;`
- Flutter: Remove from model, controller, repository, settings screen UI
- More extensive diff surface, higher regression risk

**new_song_behavior (ask/auto/off) is explicitly OUT OF SCOPE** — do not touch it, do not constrain it, do not modify the UI for it.

### 6.4 Flutter Changes

**Models (revert to single-value):**

Remove dual-value fields from Song and SetlistSong models. Remove `effective*` getters. Restore `bpm`, `musicalKey`, `tuning` as non-deprecated single-value fields.

**Song Details bottom sheet (revert to single-value display):**

Remove vertical stacked pairs. Restore original single-row-per-field layout (same as Duration). Each field has one row: "BPM | 120" (tap to edit). Remove dual-value state tracking (`_currentSourceBpm`, `_currentPerformanceBpm`, etc.) — restore single-value state tracking (`_currentBpm`, `_originalBpm` for dirty detection).

**Repository (remove dual-value methods):**

Remove 12 methods added in Phase 2.2:
- `updateSourceBpm`, `updatePerformanceBpm`, `clearSourceBpm`, `clearPerformanceBpm`
- `updateSourceMusicalKey`, `updatePerformanceMusicalKey`, `clearSourceMusicalKey`, `clearPerformanceMusicalKey`
- `updateSourceTuning`, `updatePerformanceTuning`, `clearSourceTuning`, `clearPerformanceTuning`

Restore single-value methods:
- `updateSongBpm` (calls `update_song_metadata` with `p_bpm`)
- `updateSongTuning` (calls `update_song_metadata` with `p_tuning`)
- `updateSongMusicalKey` (calls `update_song_metadata` with `p_musical_key`)
- `clearSongBpm` (calls `clear_song_metadata` with `p_clear_bpm: true`)
- `clearSongTuning` (calls `clear_song_metadata` with `p_clear_tuning: true`)
- `clearSongMusicalKey` (calls `clear_song_metadata` with `p_clear_musical_key: true`)

**Update repository SELECT queries** to remove dual-value columns from fetch queries (lines 645-657 and 4082-4095 in `setlist_repository.dart`). Restore old column names in SELECT clauses.

**Enrichment orchestrator (restore write to old columns):**

Modify `song_enrichment_orchestrator.dart` to write to `bpm`, `musical_key` directly instead of `source_bpm`, `source_musical_key`. Remove `previewMode` parameter (added in Phase 2.3b). Remove `applyEnrichmentDiff()` method.

**Enrichment selector bottom sheet:**

Remove show-diffs wiring. Remove import of `enrichment_diff_review_sheet.dart`. When `existing_song_behavior == 'show-diffs'` (should never happen after migration 4, but handle gracefully), fall back to fill-missing-only.

Since the CHECK constraint now only allows `'fill-missing-only'`, the switch statement simplifies to:

```dart
final overwriteExisting = false; // Always fill-missing-only
```

Or, more defensively:

```dart
final overwriteExisting = switch (existingSongBehavior) {
  ExistingSongBehavior.fillMissingOnly => false,
  ExistingSongBehavior.autoReplace => false, // Should never happen, fall back
  ExistingSongBehavior.showDiffs => false,   // Should never happen, fall back
};
```

**Enrichment settings screen:**

Remove "Auto-Replace" and "Show Diffs" radio buttons. Either:
- **Option A:** Show only "Fill Missing Only" radio button (one choice, no real choice)
- **Option B:** Remove the "Existing Song Behavior" radio group entirely, replace with static text: "Enrichment only fills missing values, never overwrites existing data."

Architect recommends **Option B** (simpler UI, no dead radio group).

**Remove show-diffs files:**

- Delete `lib/features/songs/widgets/enrichment_diff_review_sheet.dart`
- Delete `lib/features/songs/models/enrichment_diff_decision.dart`

**Update enrichment settings model:**

Remove `autoReplace` and `showDiffs` from `ExistingSongBehavior` enum. Keep only `fillMissingOnly`. Update repository serialization/deserialization to handle gracefully (fall back to `fillMissingOnly` if unexpected value received from DB).

**Inline enrichment writes (new songs):**

Update `setlist_detail_screen.dart` (lines 1055-1071) and `new_setlist_screen.dart` (lines 427-443) to write to `bpm`, `musical_key` instead of `source_bpm`, `source_musical_key` when creating new songs via inline enrichment.

---

## 7. Database Impact

**Affected:**

| Area | Impact |
|------|--------|
| `songs` table schema | **High** — DROP 6 columns |
| `update_song_metadata` RPC | **High** — Signature revert (17 params → 11 params) |
| `clear_song_metadata` RPC | **High** — Signature revert (10 params → 4 params) |
| `enrichment_settings` table | **Medium** — CHECK constraint change (3 values → 1 value) |
| RLS policies | **Unaffected** — no changes |
| Triggers | **Unaffected** — no changes |

**RPC signature changes:**

Old callers (9 methods in setlist_repository.dart that call `update_song_metadata` with old params) were never modified by Phase 2.2 and should continue working after revert. New callers (12 dual-value methods) will be deleted.

**Data loss:**

- Any non-NULL `performance_*` values will be lost (columns dropped). **Acceptable** — Phase 2.2 never shipped in an app build, so no real user data exists.
- `source_*` values are discarded but should be identical to `bpm`/`musical_key`/`tuning` (backfilled). **Assumption to verify:** Engineer must query production DB to confirm this.

**Migration order:** Must be applied in sequence (1 → 2 → 3 → 4). Migration 1 drops columns, migrations 2-3 revert RPC signatures that reference those columns (must happen after DROP COLUMN or RPC update will fail).

---

## 8. Flutter Architecture Changes

### 8.1 Models

**Changes:**

- `lib/features/setlists/models/song.dart` — Remove 6 dual-value fields, remove 3 `effective*` getters, remove `@Deprecated` markers from `bpm`/`musicalKey`/`tuning`
- `lib/features/setlists/models/setlist_song.dart` — Same as above
- `lib/features/songs/models/enrichment_settings.dart` — Remove `autoReplace` and `showDiffs` from `ExistingSongBehavior` enum

### 8.2 Repository

**Changes:**

- `lib/features/setlists/setlist_repository.dart` — Delete 12 dual-value methods, update SELECT queries to remove dual-value columns, restore single-value `updateSongBpm`/`updateSongTuning`/`updateSongMusicalKey` methods to call RPC with old params

### 8.3 Controllers

**Changes:**

- `lib/features/setlists/setlist_detail_controller.dart` — No direct changes (controllers call repository methods, which are being restored to old signatures)
- `lib/features/songs/enrichment_settings_controller.dart` — No changes (model handles enum parsing gracefully)

### 8.4 UI

**Changes:**

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart` — Remove dual-value UI (vertical stacked pairs), restore single-row-per-field layout, remove dual-value state tracking
- `lib/features/songs/enrichment_settings_screen.dart` — Remove "Auto-Replace" and "Show Diffs" radio buttons, remove or simplify "Existing Song Behavior" section
- `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` — Remove show-diffs wiring, simplify `overwriteExisting` computation to always `false`
- `lib/features/setlists/setlist_detail_screen.dart` — Update inline enrichment writes to use `bpm`/`musical_key` instead of `source_bpm`/`source_musical_key`
- `lib/features/setlists/new_setlist_screen.dart` — Same as above

### 8.5 Services

**Changes:**

- `lib/features/songs/services/song_enrichment_orchestrator.dart` — Remove `previewMode` parameter, remove `applyEnrichmentDiff()` method, restore writes to `bpm`/`musical_key` instead of `source_bpm`/`source_musical_key`

---

## 9. Files to Create

**Migrations only:**

1. `supabase/migrations/20260811120000_revert_dual_value_bpm_key_tuning.sql` — DROP 6 columns
2. `supabase/migrations/20260811120001_revert_update_song_metadata_single_value.sql` — Revert RPC signature (17 → 11 params)
3. `supabase/migrations/20260811120002_revert_clear_song_metadata_single_value.sql` — Revert RPC signature (10 → 4 params)
4. `supabase/migrations/20260811120003_constrain_existing_song_behavior_fill_only.sql` — Constrain CHECK to one value

**No new Flutter files** — all changes are deletions or modifications.

---

## 10. Files to Modify

| File | Lines | What Changes |
|------|-------|-------------|
| `lib/features/setlists/models/song.dart` | 10-43, 90-103 | Remove dual-value fields, remove `effective*` getters, remove `@Deprecated` markers |
| `lib/features/setlists/models/setlist_song.dart` | 18-69, 142-147 | Same as above |
| `lib/features/songs/models/enrichment_settings.dart` | 67-72 | Remove `autoReplace` and `showDiffs` from enum, update parser to fall back to `fillMissingOnly` |
| `lib/features/setlists/setlist_repository.dart` | 645-657, 2470-3100, 4082-4159 | Delete 12 dual-value methods, update SELECT queries, restore single-value methods |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | 60-700+ | Revert to single-value display/edit, remove dual-value state tracking |
| `lib/features/songs/enrichment_settings_screen.dart` | 126-230 | Remove "Auto-Replace" and "Show Diffs" radio buttons, simplify or remove section |
| `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` | 14, 95-273 | Remove import of diff review sheet, simplify `overwriteExisting` computation to always `false` |
| `lib/features/songs/services/song_enrichment_orchestrator.dart` | Throughout | Remove `previewMode` parameter, remove `applyEnrichmentDiff()`, restore writes to old columns |
| `lib/features/setlists/setlist_detail_screen.dart` | 1055-1071 | Update inline enrichment writes to `bpm`/`musical_key` |
| `lib/features/setlists/new_setlist_screen.dart` | 427-443 | Same as above |
| `lib/features/songs/enrichment_settings_repository.dart` | 58-66 | Update `_serializeExistingSongBehavior` to handle only `fillMissingOnly` |
| `lib/features/setlists/setlist_detail_controller.dart` | Verify only | Confirm methods like `updateSongBpm` still work after repository changes (likely no direct edits) |

---

## 11. Files to Delete

| File | Reason |
|------|--------|
| `lib/features/songs/widgets/enrichment_diff_review_sheet.dart` | Show-diffs UI no longer needed |
| `lib/features/songs/models/enrichment_diff_decision.dart` | Supporting model for diff UI |

---

## 12. Files Off-Limits

| File | Reason |
|------|--------|
| `lib/main.dart` | Initialization order must not change |
| `lib/features/songs/song_enrichment_service.dart` | Enrichment API wrapper unchanged |
| `lib/features/songs/external_song_lookup_service.dart` | External API wrapper unchanged |
| `lib/features/auth/*` | Auth flow unchanged |
| `lib/features/calendar/*` | Calendar/gigs unchanged |
| `lib/features/songs/enrichment_settings_controller.dart` | Minimal changes (model handles enum gracefully) |
| `lib/features/songs/enrichment_settings_repository.dart` | RPC signatures unchanged (only serialization helper updated) |
| `supabase/migrations/20260810000000_enrichment_settings.sql` | Do not modify existing migration (new migration constrains CHECK instead) |
| Any files in `feature/lyrics-chordpro-retrofit` branch | Independent feature, not merged yet |
| All files related to `new_song_behavior` (ask/auto/off) | Explicitly out of scope |

---

## 13. System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — song metadata display/edit changes |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms use same song models/UI |

---

## 14. Regression Risk

**Level:** `MEDIUM`

**Rationale:**

- **Moderate diff surface:** 7 files modified (models, repository, UI, orchestrator), 2 files deleted, 4 migrations
- **Schema changes:** DROP COLUMN and RPC signature reverts are high-impact but reversible (migrations can be rolled back)
- **No shipped user data at risk:** Phase 2.2/2.3 never released in an app build
- **Core song edit flow touched:** Song Details bottom sheet is high-traffic UI
- **Fill-missing-only CASE pattern restored:** Reintroduces write-once limitation for BPM/key (accepted tradeoff per Tony)

**Failure modes:**

- **Migration 1 (DROP COLUMN) fails if backfill assumption is wrong:** If `source_*` and `bpm`/`musical_key`/`tuning` have diverged, data loss may be unacceptable. **Mitigation:** Engineer MUST verify backfill assumption against production data before applying migrations.
- **RPC signature revert breaks existing callers:** If any code still calls RPC with dual-value params, it will fail. **Mitigation:** Engineer must grep for all RPC call sites and verify none use dual-value params (should be none — all 12 dual-value methods are being deleted).
- **Song Details UI breaks:** Reverting to single-value display could break if any state management logic still references dual-value fields. **Mitigation:** Thorough local testing before QA handoff.
- **Enrichment orchestrator writes fail:** If orchestrator still tries to write to `source_*` columns after migration, writes fail. **Mitigation:** Update all write paths to use old column names, verify via grep.

**Blast radius:**

- Song creation flows (inline enrichment, bulk entry, manual entry) — writes change from `source_*` to `bpm`/`musical_key`
- Song edit flows (Song Details, inline editing) — UI changes from dual-value to single-value
- Enrichment flows (existing-song batch enrichment) — writes change from `source_*` to `bpm`/`musical_key`, show-diffs mode removed
- Song display (catalog, setlist rows, song cards) — models change, but display logic should be minimally affected (was already using `effective*` getters, which just used fallback pattern)

**No impact on:**

- Gig management
- Rehearsal management
- Setlist ordering
- Auth flows
- Notification system

---

## 15. Engineer Task Breakdown

**Pre-implementation validation:**

1. **Verify backfill assumption (MANDATORY)** — Query production DB (`project nekwjxvgbveheooyorjo`) to confirm `source_bpm` == `bpm` AND `source_musical_key` == `musical_key` AND `source_tuning` == `tuning` for all songs. If divergence found, ESCALATE TO MANAGER before proceeding.

2. **Verify performance_* columns are NULL** — Query production DB to count songs with non-NULL `performance_bpm`, `performance_musical_key`, `performance_tuning`. If count > 0, document which songs will lose data and confirm with Manager before proceeding.

**Implementation order (strict sequence):**

**Task 1: Database migrations (apply in order 1 → 2 → 3 → 4)**

1.1. Create migration `20260811120000_revert_dual_value_bpm_key_tuning.sql` (DROP 6 columns)
1.2. Create migration `20260811120001_revert_update_song_metadata_single_value.sql` (revert RPC to 11 params)
1.3. Create migration `20260811120002_revert_clear_song_metadata_single_value.sql` (revert RPC to 4 params)
1.4. Create migration `20260811120003_constrain_existing_song_behavior_fill_only.sql` (constrain CHECK to one value)
1.5. Apply migrations locally: `supabase db reset` (dev) → verify no errors
1.6. Test RPC calls with Supabase SQL editor: `SELECT update_song_metadata(...)` with old 11-param signature → verify returns `{"success": true}`

**Task 2: Flutter models (revert to single-value)**

2.1. Edit `lib/features/setlists/models/song.dart`:
    - Remove 6 dual-value fields (lines 19-24)
    - Remove 3 `effective*` getters (lines 37-43)
    - Remove `@Deprecated` markers from `bpm`, `musicalKey`, `tuning` (lines 11-16)
    - Update `fromSupabase` factory to NOT read `source_*`/`performance_*` columns (lines 90-103)

2.2. Edit `lib/features/setlists/models/setlist_song.dart`:
    - Same changes as 2.1 (lines 18-69, 142-147)

2.3. Edit `lib/features/songs/models/enrichment_settings.dart`:
    - Remove `autoReplace` and `showDiffs` from `ExistingSongBehavior` enum (lines 68-70)
    - Update `_parseExistingSongBehavior` to fall back to `fillMissingOnly` for unexpected values (lines 45-54)

**Task 3: Repository (delete dual-value methods, restore single-value methods)**

3.1. Edit `lib/features/setlists/setlist_repository.dart`:
    - Update SELECT queries: remove `source_bpm, performance_bpm, source_musical_key, performance_musical_key, source_tuning, performance_tuning` from column lists (lines 645-657, 4082-4095)
    - Delete 12 dual-value methods (~lines 2470-3100): `updateSourceBpm`, `updatePerformanceBpm`, `clearSourceBpm`, `clearPerformanceBpm`, etc.
    - Verify single-value methods still exist (likely untouched): `updateSongBpm`, `updateSongTuning`, `updateSongMusicalKey`, `clearSongBpm`, `clearSongTuning`, `clearSongMusicalKey`
    - Update `enrichSongs` method (line 4154-4159): change `'p_source_bpm': update['sourceBpm']` to `'p_bpm': update['bpm']`, same for key

**Task 4: Song Details UI (revert to single-value display/edit)**

4.1. Edit `lib/features/setlists/widgets/song_details_bottom_sheet.dart`:
    - Remove dual-value state tracking (lines 186-225): delete `_currentSourceBpm`, `_originalSourceBpm`, `_currentPerformanceBpm`, `_originalPerformanceBpm`, etc.
    - Restore single-value state tracking: `_currentBpm`, `_originalBpm`, `_currentMusicalKey`, `_originalMusicalKey`, `_currentTuning`, `_originalTuning`
    - Revert UI to single-row-per-field layout (remove vertical stacked pairs, restore segmented button group pattern like Duration)
    - Remove `_selectSourceBpm`, `_selectPerformanceBpm` methods (lines 588-620+) — restore single `_selectBpm` method
    - Same for key and tuning
    - Update `SongDetailsResult` to use single-value fields (lines 60-120)

**Task 5: Enrichment orchestrator (restore writes to old columns)**

5.1. Edit `lib/features/songs/services/song_enrichment_orchestrator.dart`:
    - Remove `previewMode` parameter from `enrichSongs()` signature
    - Remove `applyEnrichmentDiff()` method
    - Update write calls: change `source_bpm` to `bpm`, `source_musical_key` to `musical_key` in RPC params

**Task 6: Enrichment settings UI (remove auto-replace and show-diffs)**

6.1. Edit `lib/features/songs/enrichment_settings_screen.dart`:
    - Remove "Auto-Replace" radio button (lines 188-196)
    - Remove "Show Diffs" radio button (lines 202-220)
    - **Option A:** Keep "Fill Missing Only" radio button (one choice)
    - **Option B (recommended):** Remove entire "Existing Song Behavior" radio group, replace with static text: "Enrichment only fills missing values, never overwrites existing data."

6.2. Edit `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`:
    - Remove import of `enrichment_diff_review_sheet.dart` (line 14)
    - Simplify `overwriteExisting` computation (lines 95-122) to always `false` (or remove the switch entirely)

6.3. Edit `lib/features/songs/enrichment_settings_repository.dart`:
    - Update `_serializeExistingSongBehavior` (lines 58-66) to only handle `fillMissingOnly` (remove other cases)

**Task 7: Inline enrichment writes (new song creation)**

7.1. Edit `lib/features/setlists/setlist_detail_screen.dart` (lines 1055-1071):
    - Change `updateData['source_bpm'] = bpm;` to `updateData['bpm'] = bpm;`
    - Change `updateData['source_musical_key'] = musicalKey;` to `updateData['musical_key'] = musicalKey;`
    - Same for `insertData` (lines 1070-1071)

7.2. Edit `lib/features/setlists/new_setlist_screen.dart` (lines 427-443):
    - Same changes as 7.1

**Task 8: Delete show-diffs files**

8.1. Delete `lib/features/songs/widgets/enrichment_diff_review_sheet.dart`
8.2. Delete `lib/features/songs/models/enrichment_diff_decision.dart`

**Task 9: Verification (local testing before QA handoff)**

9.1. Run `flutter analyze` → 0 errors
9.2. Test Song Details: open song, edit BPM/key/tuning, save → verify single-value display, no crashes
9.3. Test enrichment: run "Enrich All Songs" → verify writes to `bpm`/`musical_key`, no errors
9.4. Test settings screen: verify "Auto-Replace" and "Show Diffs" options removed
9.5. Test inline enrichment: add new song via Song Lookup → verify enrichment writes to `bpm`/`musical_key`

**Task 10: Engineer report**

10.1. Document any deviations from Architect plan
10.2. Document any data anomalies found during backfill verification
10.3. Generate `git diff` for all changed files
10.4. Write `ENGINEER_REPORT.md` in `docs/features/song-metadata-revert-dual-value/`

---

## 16. Verification Plan

### Tier 1 — Pre-Deployment (Local DB Only, Before `supabase db push`)

**PRE-DEPLOY TEST 1:** Verify backfill assumption (production data check)

```sql
-- Query production DB (project nekwjxvgbveheooyorjo) to confirm source_* columns
-- were correctly backfilled from bpm/musical_key/tuning and have not diverged

SELECT 
  COUNT(*) AS total_songs,
  COUNT(CASE WHEN source_bpm IS DISTINCT FROM bpm THEN 1 END) AS bpm_diverged,
  COUNT(CASE WHEN source_musical_key IS DISTINCT FROM musical_key THEN 1 END) AS key_diverged,
  COUNT(CASE WHEN source_tuning IS DISTINCT FROM tuning THEN 1 END) AS tuning_diverged,
  COUNT(CASE WHEN performance_bpm IS NOT NULL THEN 1 END) AS has_performance_bpm,
  COUNT(CASE WHEN performance_musical_key IS NOT NULL THEN 1 END) AS has_performance_key,
  COUNT(CASE WHEN performance_tuning IS NOT NULL THEN 1 END) AS has_performance_tuning
FROM songs;

-- Expected result: bpm_diverged = 0, key_diverged = 0, tuning_diverged = 0,
-- has_performance_* = 0 or very small number
-- If any divergence > 0, ESCALATE TO MANAGER before proceeding
```

**PRE-DEPLOY TEST 2:** Verify existing RPC still works with old signature (before revert)

```sql
-- Call current production update_song_metadata with old params (should still work)
-- Uses a test song ID (replace with actual song ID from your dev DB)

SELECT update_song_metadata(
  p_song_id := 'TEST_SONG_ID'::uuid,
  p_band_id := 'TEST_BAND_ID'::uuid,
  p_bpm := 120,
  p_duration_seconds := NULL,
  p_tuning := NULL,
  p_notes := NULL,
  p_title := NULL,
  p_artist := NULL,
  p_youtube_links := NULL,
  p_lyrics := NULL,
  p_musical_key := NULL
);

-- Expected result: {"success": true}
```

### Tier 2 — Post-Deployment (After `supabase db push` Succeeds)

**POST-DEPLOY TEST 1:** Verify columns were dropped

```sql
-- Verify source_* and performance_* columns no longer exist in songs table

SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'songs' 
  AND column_name IN ('source_bpm', 'performance_bpm', 'source_musical_key', 
                      'performance_musical_key', 'source_tuning', 'performance_tuning');

-- Expected result: 0 rows (all columns dropped)
```

**POST-DEPLOY TEST 2:** Verify update_song_metadata signature was reverted

```sql
-- Check function signature (should have 11 params, not 17)

SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'update_song_metadata';

-- Expected result: function definition shows 11 params (p_song_id through p_musical_key),
-- no p_source_bpm, p_performance_bpm, etc.
```

**POST-DEPLOY TEST 3:** Verify clear_song_metadata signature was reverted

```sql
-- Check function signature (should have 4 clear flags, not 10)

SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'clear_song_metadata';

-- Expected result: function definition shows 4 clear flags (p_clear_bpm, p_clear_duration, 
-- p_clear_tuning, p_clear_musical_key), no p_clear_source_bpm, etc.
```

**POST-DEPLOY TEST 4:** Verify enrichment_settings CHECK constraint was updated

```sql
-- Check CHECK constraint on existing_song_behavior (should only allow 'fill-missing-only')

SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'enrichment_settings'::regclass
  AND conname = 'enrichment_settings_existing_song_behavior_check';

-- Expected result: constraint definition shows CHECK (existing_song_behavior = 'fill-missing-only')
```

**POST-DEPLOY TEST 5:** Call reverted update_song_metadata with single-value params

```sql
-- Call reverted RPC with old signature (11 params)

SELECT update_song_metadata(
  p_song_id := 'TEST_SONG_ID'::uuid,
  p_band_id := 'TEST_BAND_ID'::uuid,
  p_bpm := 125,
  p_duration_seconds := NULL,
  p_tuning := 'Drop D',
  p_notes := NULL,
  p_title := NULL,
  p_artist := NULL,
  p_youtube_links := NULL,
  p_lyrics := NULL,
  p_musical_key := 'A Minor'
);

-- Expected result: {"success": true}
-- Verify write: SELECT bpm, tuning, musical_key FROM songs WHERE id = 'TEST_SONG_ID';
-- Should show bpm=125, tuning='Drop D', musical_key='A Minor'
```

**POST-DEPLOY TEST 6:** Verify fill-missing-only behavior (write-once limitation restored)

```sql
-- Attempt to overwrite existing BPM (should be no-op)

-- Step 1: Insert test song with BPM=120
INSERT INTO songs (id, band_id, title, artist, bpm, duration_seconds)
VALUES ('TEST_SONG_2'::uuid, 'TEST_BAND_ID'::uuid, 'Test Song', 'Test Artist', 120, 180);

-- Step 2: Try to update BPM to 130 (should be no-op due to CASE...ELSE logic)
SELECT update_song_metadata(
  p_song_id := 'TEST_SONG_2'::uuid,
  p_band_id := 'TEST_BAND_ID'::uuid,
  p_bpm := 130,
  p_duration_seconds := NULL,
  p_tuning := NULL,
  p_notes := NULL,
  p_title := NULL,
  p_artist := NULL,
  p_youtube_links := NULL,
  p_lyrics := NULL,
  p_musical_key := NULL
);

-- Expected result: {"success": true} (RPC succeeds but value unchanged)
-- Verify: SELECT bpm FROM songs WHERE id = 'TEST_SONG_2';
-- Should still show bpm=120 (not 130) — confirming fill-missing-only behavior
```

**POST-DEPLOY TEST 7:** Verify enrichment_settings rows were updated

```sql
-- Verify any bands with auto-replace or show-diffs were migrated to fill-missing-only

SELECT COUNT(*) 
FROM enrichment_settings 
WHERE existing_song_behavior != 'fill-missing-only';

-- Expected result: 0 (all rows should have 'fill-missing-only' after migration 4)
```

### Flutter Testing (Manual, Post-Migration)

**FLUTTER TEST 1:** Song Details single-value display
- Open any song in Song Details
- Verify BPM/Key/Tuning show single row each (not vertical stacked pairs)
- Verify display matches Duration row pattern
- Edit BPM → save → verify update persists

**FLUTTER TEST 2:** Enrichment fills missing only
- Find song with NULL BPM
- Run "Enrich All Songs"
- Verify BPM populated
- Edit BPM manually
- Run "Enrich All Songs" again
- Verify BPM unchanged (not overwritten by enrichment)

**FLUTTER TEST 3:** Settings screen simplified
- Open Settings → Song Enrichment
- Verify "Auto-Replace" and "Show Diffs" options removed
- Verify either: (A) only "Fill Missing Only" radio shown, or (B) radio group replaced with static text

**FLUTTER TEST 4:** Inline enrichment writes to old columns
- Add new song via Song Lookup (select external result)
- Verify enrichment review shows BPM/Key
- Accept and add to setlist
- Open Song Details
- Verify BPM/Key populated (single-value display)

---

*End of ARCHITECT_PLAN.md*
