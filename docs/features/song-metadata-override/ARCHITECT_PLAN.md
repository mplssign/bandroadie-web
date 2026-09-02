# ARCHITECT PLAN: `bug/song-metadata-override`

**Title:** Song key/tempo manual changes overwritten by web enrichment  
**Date:** 2026-09-02  
**Reported Version:** 1.4.5 (245) — Scott Lotspeich, HonkyTonk band, iOS  

---

## Problem Summary

When a user manually edits BPM or musical key on a Catalog song, then runs enrichment, the user's values are silently overwritten by web-sourced data. The user has no means to preserve their custom values across enrichment runs.

---

## Root Cause

**Two compounding bugs, both in the song metadata write path:**

### Bug 1 — Primary (reported): Enrichment unconditionally overwrites user-set values

`enrichment_selector_bottom_sheet.dart` hardcodes `overwriteExisting = true` (post-dual-value-revert comment: "Checkbox consent = allow overwrite"). This propagates through the orchestrator → `enrichSongs()` repository → `update_song_metadata` RPC with `p_allow_enrich_overwrite: true`. The RPC then overwrites BPM and musical key on every enriched song, even those the user manually edited. There is no "user manually set this" flag anywhere in the system.

**Confidence: HIGH** — confirmed in `enrichment_selector_bottom_sheet.dart` L88 and `setlist_repository.dart:3503`.

### Bug 2 — Secondary (regression from migration 20260827183550): Manual edits of *existing* BPM/key silently fail

`update_song_metadata` with `p_allow_enrich_overwrite=FALSE` (the default, used by all manual-edit callers) uses this logic:
```sql
bpm = CASE
  WHEN p_bpm IS NOT NULL AND (p_allow_enrich_overwrite OR bpm IS NULL)
  THEN p_bpm
  ELSE bpm
END
```
If a song already has `bpm=110` and the user sets it to 120, the condition evaluates to `TRUE AND (FALSE OR FALSE) = FALSE` — the update is silently dropped. The same applies to `musical_key`. This means after enrichment overwrites a user's value, the user cannot even recover it by re-editing without first clearing the field.

**Confidence: HIGH** — confirmed by reading migration `20260827183550_add_enrich_overwrite_param.sql`. The comment in that migration says "false = manual edit use case" but the fill-missing-only semantics are wrong for edits on existing values.

---

## Existing System Analysis

| Component | Relevant Behavior |
|---|---|
| `update_song_metadata` RPC (12-param, post-20260827) | `p_allow_enrich_overwrite=TRUE` overwrites BPM/key; `FALSE` does fill-missing-only for BPM/key. Tuning always-overwrites (not enriched). Duration always-overwrites. |
| `clear_song_metadata` RPC (6-param, post-20260822) | Clears `bpm`, `duration_seconds`, `tuning`, `musical_key` by boolean flags. No override-flag awareness. |
| `SetlistRepository.enrichSongs()` | Calls `update_song_metadata` with `p_allow_enrich_overwrite: true`. This is the only enrichment write path. |
| `SetlistRepository.updateSongBpmOverride()` | Calls `update_song_metadata` without `p_allow_enrich_overwrite` (defaults FALSE). Broken for songs with existing BPM due to Bug 2. |
| `SetlistRepository.updateSongMusicalKey()` | Same pattern as above. Broken for songs with existing musical key. |
| `SongEnrichmentOrchestrator.enrichSongs()` | Filters using `song.bpm == null` check when `overwriteExisting=false`. But the selector always sends `overwriteExisting=true`, bypassing this filter. |
| `EnrichmentSelectorBottomSheet` | `overwriteExisting` hardcoded to `true`. No user-facing toggle exists (was removed in scope reduction). |
| `Song` model | No `bpmManualOverride` / `musicalKeyManualOverride` fields. |
| `upsertExternalSong()` | Does client-side fill-missing-only (`existingRow['bpm'] == null`) before calling direct `.update()`. Not affected. |
| Songs with `NULL band_id` | Use SECURITY DEFINER RPCs to bypass RLS. Any schema change must account for this (new columns inherit RLS policies; RPCs must be redeployed with `SET search_path = public`). |

---

## Proposed Solution

Add two boolean override flags to `songs` — one per affected field — and fix both the RPC's manual-edit write path and its enrichment-overwrite protection in a single migration pair. Surface the flags in the `Song` model so the orchestrator can exclude locked songs before calling the RPC (accurate enrichment result reporting without extra round-trips).

### Design Decisions

**D1: Per-field flags, not per-song flag.**  
`bpm_manual_override` and `musical_key_manual_override` are independent. Setting BPM manually doesn't block key enrichment.

**D2: Flags live on `songs`, not `setlist_songs`.**  
Manual overrides protect the catalog-level value. Per-setlist BPM overrides (in `setlist_songs`) are a separate, already-existing mechanism and are not affected.

**D3: `p_allow_enrich_overwrite=FALSE` → "caller is a user edit — always write, set flag."**  
This fixes Bug 2 (manual edits of existing BPM now succeed) and is the only semantic change to callers that don't set the parameter. All such callers either pass `p_bpm=NULL` (no-op) or are the two manual-edit methods — both of which want "always write + set flag."

**D4: `p_allow_enrich_overwrite=TRUE` → "caller is enrichment — respect the flag."**  
Enrichment writes BPM/key only if `bpm_manual_override=FALSE` / `musical_key_manual_override=FALSE`. The flag is NOT cleared by enrichment (only explicit user clears reset it).

**D5: No new RPC parameter needed.**  
The existing boolean already separates the two call sites. No PGRST203 risk.

**D6: `clear_song_metadata` clears the flag when clearing the field.**  
If the user explicitly clears BPM or key, the override flag is reset, allowing future enrichment to fill in the field again.

**D7: `Song` model gains the two boolean fields (surfaced to orchestrator only — not to UI).**  
The orchestrator skips enrichment for flag-locked songs client-side, so `EnrichmentFieldResult.unchanged` is reported accurately instead of a misleading `updated`. No UI lock indicator in this fix (out of scope).

**D8: `enrichment_selector_bottom_sheet.dart` is NOT changed.**  
The hardcoded `overwriteExisting=true` is intentional product behavior for the selector ("overwrite all checked fields"). The DB flag now gates which fields can actually be overwritten, making the selector's stated behavior accurate without code changes.

---

## Database Impact

### New: `songs` table columns
```sql
bpm_manual_override        BOOLEAN NOT NULL DEFAULT FALSE
musical_key_manual_override BOOLEAN NOT NULL DEFAULT FALSE
```
No separate indexes needed (boolean columns with predominantly-false values; no selective query patterns requiring them).

All existing rows default to `FALSE`. Enrichment behavior for all existing songs is unchanged immediately after migration.

### Changed: `update_song_metadata` function (same 12-param signature)

New BPM block:
```sql
-- Manual edit (p_allow_enrich_overwrite=FALSE): always write, set flag
-- Enrichment    (p_allow_enrich_overwrite=TRUE):  write only if not user-locked
bpm = CASE
  WHEN p_bpm IS NOT NULL AND (NOT p_allow_enrich_overwrite)               THEN p_bpm
  WHEN p_bpm IS NOT NULL AND p_allow_enrich_overwrite
       AND NOT COALESCE(v_before_bpm_override, FALSE)                     THEN p_bpm
  ELSE bpm
END,
bpm_manual_override = CASE
  WHEN p_bpm IS NOT NULL AND NOT p_allow_enrich_overwrite                 THEN TRUE
  ELSE bpm_manual_override
END,
```
Same pattern for `musical_key` / `musical_key_manual_override`.

Verification section updated: use local `v_bpm_write_eligible` / `v_key_write_eligible` booleans (computed before UPDATE from the BEFORE snapshot including the new flag columns) to determine whether the eligibility check should fire — preventing false-positive errors when enrichment intentionally skips a locked field.

### Changed: `clear_song_metadata` function (same 6-param signature)

Add to the UPDATE:
```sql
bpm_manual_override = CASE WHEN p_clear_bpm THEN FALSE ELSE bpm_manual_override END,
musical_key_manual_override = CASE WHEN p_clear_musical_key THEN FALSE ELSE musical_key_manual_override END,
```

No signature change → no new REVOKE/GRANT needed (existing grants from migration 20260822120005 remain valid for the 6-param signature).

`update_song_metadata` signature is unchanged (12 params) → existing REVOKE/GRANT from migration 20260827183550 remains valid.

---

## Flutter Architecture Changes

### `lib/features/setlists/models/song.dart`
Add two fields:
```dart
final bool bpmManualOverride;
final bool musicalKeyManualOverride;
```
Both default `false`. Parse from `json['bpm_manual_override'] as bool? ?? false` etc.

### `lib/features/songs/services/song_enrichment_orchestrator.dart`
Update `needsBpm` and `needsKey` filtering to respect the new flags:
```dart
final needsBpm = enrichBpm
    && !song.bpmManualOverride          // never override user-locked field
    && (overwriteExisting || song.bpm == null);
final needsKey = enrichKey
    && !song.musicalKeyManualOverride
    && (overwriteExisting || song.musicalKey == null);
```

This ensures locked songs are excluded **before** a RPC call is made, so `bpmResult` is `EnrichmentFieldResult.unchanged` (not a misleading `updated`) and the RPC verification logic is never hit for a locked field.

### `lib/features/setlists/setlist_repository.dart` — `fetchSongsForBand()`
Add `bpm_manual_override, musical_key_manual_override` to the column list used by the enrichment orchestrator's song-fetch call.

> **Note:** `fetchSongsForBand` is used only by the enrichment orchestrator. The `SetlistSong` model used for display does NOT need the new fields (they are internal enrichment logic only).

---

## Files to Create

| File | Purpose |
|---|---|
| `supabase/migrations/20260902120000_add_manual_override_flags.sql` | ADD two boolean columns to `songs` |
| `supabase/migrations/20260902120001_fix_update_song_metadata_manual_override.sql` | Rewrite `update_song_metadata` and `clear_song_metadata` with flag awareness |
| `docs/features/song-metadata-override/ARCHITECT_PLAN.md` | This file |

---

## Files to Modify

| File | Change |
|---|---|
| `lib/features/setlists/models/song.dart` | Add `bpmManualOverride`, `musicalKeyManualOverride` fields + fromSupabase parsing |
| `lib/features/songs/services/song_enrichment_orchestrator.dart` | Add flag guard to `needsBpm` / `needsKey` filter |
| `lib/features/setlists/setlist_repository.dart` | Add new columns to `fetchSongsForBand` column select |

---

## Files Off-Limits

| File | Reason |
|---|---|
| `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` | `overwriteExisting=true` is correct product behavior; DB flags now enforce correctness without changing the UI |
| `lib/features/setlists/setlist_repository.dart` → `updateSongBpmOverride` / `updateSongMusicalKey` | No code change needed; callers already omit `p_allow_enrich_overwrite` (defaults to FALSE = manual-edit semantics after the fix) |
| `lib/features/setlists/setlist_repository.dart` → `enrichSongs` | No code change; `p_allow_enrich_overwrite: true` remains correct for enrichment path |
| All `setlist_songs` table code | Per-setlist overrides are a distinct, unaffected system |
| All `SetlistSong` model code | Display model; override flags are enrichment-internal |
| `main.dart` and init order | No touch to init sequence |
| Firebase, auth, deep link, routing code | Unaffected |

---

## System Impact Map

| System | Impact |
|---|---|
| Songs / Catalog | **Affected** — schema change + RPC behavior change |
| Setlists | Enrichment flow modified (orchestrator filter) |
| Auth / Session | Unaffected |
| Routing | Unaffected |
| Notifications | Unaffected |
| Gigs / Rehearsals | Unaffected |
| Members | Unaffected |
| iOS | Affected (primary reported platform) |
| Android | Affected (same enrichment code path) |
| macOS | Affected |
| Web | Affected |

---

## Regression Risk: MEDIUM

**Reasons:**
1. `update_song_metadata` semantic change for `p_allow_enrich_overwrite=FALSE`: previously fill-missing-only for BPM/key; now always-write + sets flag. This fixes Bug 2 but changes behavior for the two affected call sites (`updateSongBpmOverride`, `updateSongMusicalKey`). All other callers pass `p_bpm=NULL` / `p_musical_key=NULL`, so the changed path is never reached.
2. Enrichment for songs with `bpm_manual_override=TRUE` now silently skips BPM. All existing songs start with `FALSE`, so no disruption at deploy time.
3. `Song` model gains two new fields; any query selecting songs without the new columns will parse them as `false` (default). The only query that needs them is `fetchSongsForBand` (for the orchestrator).

---

## Engineer Task Breakdown

Tasks are ordered; each must be complete before the next begins.

### Task 1 — Migration: add override flag columns
**File:** `supabase/migrations/20260902120000_add_manual_override_flags.sql`

```sql
-- Add per-field manual-override flags to songs.
-- FALSE (default): field may be overwritten by enrichment.
-- TRUE: user explicitly set this field; enrichment must not overwrite it.

ALTER TABLE public.songs
  ADD COLUMN IF NOT EXISTS bpm_manual_override BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS musical_key_manual_override BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.songs.bpm_manual_override IS
  'TRUE when user has manually set BPM. Enrichment will not overwrite while this flag is set. Cleared when user explicitly clears BPM.';
COMMENT ON COLUMN public.songs.musical_key_manual_override IS
  'TRUE when user has manually set musical key. Enrichment will not overwrite while this flag is set. Cleared when user explicitly clears the key.';
```

No REVOKE/GRANT needed — new columns inherit existing RLS policies on the `songs` table.

---

### Task 2 — Migration: fix `update_song_metadata` and `clear_song_metadata`
**File:** `supabase/migrations/20260902120001_fix_update_song_metadata_manual_override.sql`

**`update_song_metadata`** — rewrite with `CREATE OR REPLACE FUNCTION` (same 12-param signature; no DROP needed):

DECLARE section additions:
```sql
v_before_bpm_override      BOOLEAN;
v_before_key_override      BOOLEAN;
v_bpm_write_eligible       BOOLEAN;
v_key_write_eligible       BOOLEAN;
```

BEFORE snapshot — extend existing SELECT to:
```sql
SELECT bpm, duration_seconds, musical_key, bpm_manual_override, musical_key_manual_override
INTO v_before_bpm, v_before_duration, v_before_key, v_before_bpm_override, v_before_key_override
FROM songs WHERE id = p_song_id;
```

Compute eligibility (before the UPDATE):
```sql
-- Manual edit (p_allow_enrich_overwrite=FALSE): always eligible (fixes Bug 2).
-- Enrichment (p_allow_enrich_overwrite=TRUE): eligible only if not user-locked.
v_bpm_write_eligible := p_bpm IS NOT NULL AND (
  NOT p_allow_enrich_overwrite
  OR NOT COALESCE(v_before_bpm_override, FALSE)
);
v_key_write_eligible := p_musical_key IS NOT NULL AND (
  NOT p_allow_enrich_overwrite
  OR NOT COALESCE(v_before_key_override, FALSE)
);
```

UPDATE SET clause — replace old BPM and musical_key blocks:
```sql
bpm = CASE WHEN v_bpm_write_eligible THEN p_bpm ELSE bpm END,

bpm_manual_override = CASE
  WHEN p_bpm IS NOT NULL AND NOT p_allow_enrich_overwrite THEN TRUE
  ELSE bpm_manual_override
END,

musical_key = CASE WHEN v_key_write_eligible THEN p_musical_key ELSE musical_key END,

musical_key_manual_override = CASE
  WHEN p_musical_key IS NOT NULL AND NOT p_allow_enrich_overwrite THEN TRUE
  ELSE musical_key_manual_override
END,
```

Verification section — replace old BPM/key checks with eligibility-aware versions:
```sql
IF p_bpm IS NOT NULL AND v_bpm_write_eligible THEN
  IF v_new_bpm IS DISTINCT FROM p_bpm THEN
    RETURN json_build_object('success', false, 'error',
      'BPM update failed: requested ' || p_bpm || ', got ' || COALESCE(v_new_bpm::text, 'NULL'));
  END IF;
END IF;

IF p_musical_key IS NOT NULL AND v_key_write_eligible THEN
  IF v_new_key IS DISTINCT FROM p_musical_key THEN
    RETURN json_build_object('success', false, 'error',
      'Musical key update failed: requested ' || p_musical_key || ', got ' || COALESCE(v_new_key, 'NULL'));
  END IF;
END IF;
```

REVOKE/GRANT: same signature → re-assert existing grant (idempotent, safe):
```sql
REVOKE ALL ON FUNCTION update_song_metadata(
  uuid, uuid, integer, integer, text, text, text, text, text, text, text, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION update_song_metadata(
  uuid, uuid, integer, integer, text, text, text, text, text, text, text, boolean
) TO authenticated;
```

---

**`clear_song_metadata`** — rewrite with `CREATE OR REPLACE FUNCTION` (same 6-param signature):

ADD to the UPDATE SET:
```sql
bpm_manual_override = CASE WHEN p_clear_bpm THEN FALSE ELSE bpm_manual_override END,
musical_key_manual_override = CASE WHEN p_clear_musical_key THEN FALSE ELSE musical_key_manual_override END,
```

REVOKE/GRANT: same signature → re-assert:
```sql
REVOKE ALL ON FUNCTION clear_song_metadata(
  uuid, uuid, boolean, boolean, boolean, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION clear_song_metadata(
  uuid, uuid, boolean, boolean, boolean, boolean
) TO authenticated;
```

---

### Task 3 — Flutter: `Song` model
**File:** `lib/features/setlists/models/song.dart`

Add to fields and constructor:
```dart
final bool bpmManualOverride;
final bool musicalKeyManualOverride;
```
Default both to `false` in constructor. Add to `fromSupabase`:
```dart
bpmManualOverride: json['bpm_manual_override'] as bool? ?? false,
musicalKeyManualOverride: json['musical_key_manual_override'] as bool? ?? false,
```

---

### Task 4 — Flutter: `fetchSongsForBand` query
**File:** `lib/features/setlists/setlist_repository.dart`

In `fetchSongsForBand()`, add `bpm_manual_override, musical_key_manual_override` to the column select string used by the enrichment orchestrator.

> **Scope note:** Only the query that feeds `enrichSongs` orchestrator needs these columns. Do NOT change the `SetlistSong` select queries or any display-path queries.

---

### Task 5 — Flutter: orchestrator filter
**File:** `lib/features/songs/services/song_enrichment_orchestrator.dart`

In `enrichSongs()`, replace the `needsBpm` and `needsKey` expressions:

**Before:**
```dart
final needsBpm = enrichBpm && (overwriteExisting || song.bpm == null);
final needsKey = enrichKey && (overwriteExisting || song.musicalKey == null);
```

**After:**
```dart
final needsBpm = enrichBpm
    && !song.bpmManualOverride
    && (overwriteExisting || song.bpm == null);
final needsKey = enrichKey
    && !song.musicalKeyManualOverride
    && (overwriteExisting || song.musicalKey == null);
```

Apply the same guard to the duplicate `needsBpm`/`needsKey` expressions that appear inside the song loop at the early-exit check (both occurrences must be updated).

---

## Verification Plan

### Tier 1 — Pre-deploy (read-only, no side effects)

**T1-1:** Confirm new columns exist and have correct defaults:
```sql
SELECT column_name, column_default, is_nullable, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'songs'
  AND column_name IN ('bpm_manual_override', 'musical_key_manual_override');
-- Expect: 2 rows, data_type=boolean, is_nullable=NO, column_default='false'
```

**T1-2:** Confirm no existing song has a TRUE override (all should be FALSE after migration):
```sql
SELECT COUNT(*) FROM public.songs
WHERE bpm_manual_override = TRUE OR musical_key_manual_override = TRUE;
-- Expect: 0
```

**T1-3:** Confirm `update_song_metadata` has exactly one overload (no PGRST203 risk):
```sql
SELECT proname, pronargs
FROM pg_proc
WHERE proname = 'update_song_metadata'
  AND pronamespace = 'public'::regnamespace;
-- Expect: exactly 1 row, pronargs = 12
```

**T1-4:** Confirm `clear_song_metadata` has exactly one overload:
```sql
SELECT proname, pronargs
FROM pg_proc
WHERE proname = 'clear_song_metadata'
  AND pronamespace = 'public'::regnamespace;
-- Expect: exactly 1 row, pronargs = 6
```

**T1-5:** Verify grants on `update_song_metadata` (use OID-based check, NOT string-match on ACL):
```sql
SELECT
  has_function_privilege('authenticated',
    (SELECT oid FROM pg_proc
     WHERE proname='update_song_metadata'
       AND pronamespace='public'::regnamespace),
    'EXECUTE') AS authenticated_can_execute,
  has_function_privilege('anon',
    (SELECT oid FROM pg_proc
     WHERE proname='update_song_metadata'
       AND pronamespace='public'::regnamespace),
    'EXECUTE') AS anon_can_execute;
-- Expect: authenticated_can_execute=TRUE, anon_can_execute=FALSE
```

**T1-6:** Same check for `clear_song_metadata`:
```sql
SELECT
  has_function_privilege('authenticated',
    (SELECT oid FROM pg_proc
     WHERE proname='clear_song_metadata'
       AND pronamespace='public'::regnamespace),
    'EXECUTE') AS authenticated_can_execute,
  has_function_privilege('anon',
    (SELECT oid FROM pg_proc
     WHERE proname='clear_song_metadata'
       AND pronamespace='public'::regnamespace),
    'EXECUTE') AS anon_can_execute;
-- Expect: authenticated_can_execute=TRUE, anon_can_execute=FALSE
```

---

### Tier 2 — Post-deploy (wrapped in transactions that roll back; never use production UUIDs)

> All tests below must be wrapped in `BEGIN; ... ROLLBACK;` or use DO blocks with explicit rollback. The test songs used must be created inside the transaction and rolled back.

**T2-1: Manual BPM edit on song with existing BPM (Bug 2 fix verification)**  
Set up a song with `bpm=110`. Call `update_song_metadata(p_bpm=120, p_allow_enrich_overwrite=FALSE)`.  
Assert: `bpm=120`, `bpm_manual_override=TRUE`. This was previously broken (BPM stayed 110).

**T2-2: Enrichment does not overwrite user-locked BPM**  
Set up a song with `bpm=120, bpm_manual_override=TRUE`. Call `update_song_metadata(p_bpm=117, p_allow_enrich_overwrite=TRUE)`.  
Assert: `bpm=120` (unchanged), `bpm_manual_override=TRUE` (unchanged). RPC returns `{success: true}`.

**T2-3: Enrichment writes BPM when flag is FALSE**  
Set up a song with `bpm=NULL, bpm_manual_override=FALSE`. Call `update_song_metadata(p_bpm=117, p_allow_enrich_overwrite=TRUE)`.  
Assert: `bpm=117`, `bpm_manual_override=FALSE` (enrichment does not set the flag).

**T2-4: Clear BPM resets the flag**  
Set up a song with `bpm=120, bpm_manual_override=TRUE`. Call `clear_song_metadata(p_clear_bpm=TRUE)`.  
Assert: `bpm=NULL`, `bpm_manual_override=FALSE`.

**T2-5: Musical key path (mirror of T2-1 through T2-4)**  
Repeat T2-1 to T2-4 using `musical_key` / `musical_key_manual_override` instead of `bpm`.

**T2-6: Other fields unaffected**  
Call `update_song_metadata(p_tuning='drop_d', p_bpm=NULL, p_allow_enrich_overwrite=FALSE)`.  
Assert: `tuning='drop_d'`, `bpm_manual_override` unchanged.

**T2-7: Idempotency**  
Call `update_song_metadata(p_bpm=120, p_allow_enrich_overwrite=FALSE)` twice on the same song.  
Assert: second call returns `{success: true}`, `bpm=120`, `bpm_manual_override=TRUE`.

---

## QA Regression Areas

1. **Manual BPM edit** on a song that already has BPM — confirm value updates and persists after navigation
2. **Manual BPM edit** on a song with no BPM — confirm value is set
3. **Clear BPM** — confirm BPM goes to null and enrichment can subsequently fill it
4. **Manual key edit** — same as above for musical key
5. **Enrichment (default selector)** — run enrichment on a song with user-locked BPM; confirm BPM unchanged, result shows song as "unchanged" not "updated"; confirm key enrichment still runs if key was not user-locked
6. **Enrichment on song with no prior BPM** — confirm enrichment fills BPM normally
7. **Add song via lookup overlay** — confirm `upsertExternalSong` still works (it does not use `update_song_metadata`; unaffected)
8. **Bulk add songs** — confirm inline enrichment on new songs still populates BPM/key (new songs have flag=FALSE)
9. **Songs with NULL band_id (legacy)** — confirm SECURITY DEFINER still applies and RLS bypass works for these songs

---

## Rollout Strategy

1. Deploy migration `20260902120000` first (schema-only, no behavior change)
2. Deploy migration `20260902120001` (RPC logic change)
3. Deploy Flutter build — all platforms simultaneously (no platform-conditional logic)

**Rollback:** If the RPC change causes issues, redeploy the previous `update_song_metadata` and `clear_song_metadata` bodies (from migration 20260827183550 and 20260811120002 respectively). The new columns on `songs` are backward-compatible (default FALSE) and can be left in place without harm.

---

## Out of Scope

- UI indicator showing "user-locked" status for BPM/key fields — future enhancement
- Per-setlist override flags — `setlist_songs` already has separate BPM/tuning/duration override columns; this bug only affects the catalog-level song record
- Tuning field — enrichment never sends `p_tuning` (confirmed in `enrichSongs` repository method); not affected by this bug
- Duration field — `always-overwrite` is intentional (bug/song-duration-edit-silently-fails was separately fixed in 20260827183550); no override flag for duration
- Surfacing the override flags in the enrichment results UI (e.g., showing a lock icon next to "unchanged" fields)
