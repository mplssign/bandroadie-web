# Feature Slug

feature/song-enrichment-overwrite-existing

---

# Problem Summary

Users cannot overwrite existing BPM, Duration, or Musical Key values during song enrichment, even when those fields' checkboxes are checked. The enrichment flow has partial infrastructure for an `overwriteExisting` flag, but it's hardcoded to `false` in the UI and incomplete in the orchestrator (duration logic doesn't check it). Even if the client-side flag were enabled, the `update_song_metadata` RPC would still block overwrites server-side with fill-once CASE logic for BPM and Key. This prevents users from correcting inaccurate metadata (reported by Whiskey Ridge on Facebook: "not pulling the right keys").

---

# Root Cause

Confirmed by reading actual code:

## Server-Side (Primary Blocker)

`supabase/migrations/20260811120001_revert_update_song_metadata_single_value.sql` defines `update_song_metadata` with fill-once logic:

```sql
-- BPM: fill-missing-only
bpm = CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END

-- Duration: fill-missing-only (but will be changed by bug/song-duration-edit-silently-fails)
duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0
                        THEN p_duration_seconds ELSE duration_seconds END

-- Musical Key: fill-missing-only
musical_key = CASE WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR TRIM(musical_key) = '')
                   THEN p_musical_key ELSE musical_key END

-- Tuning: always-overwrite (COALESCE - already correct)
tuning = COALESCE(p_tuning, tuning)
```

The RPC has no parameter to signal "allow overwrite for enrichment." Even if the client wanted to overwrite, the server blocks it.

## Client-Side (Secondary/Incomplete)

1. **UI hardcoded to false**: `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart:87`
   ```dart
   const bool overwriteExisting = false;
   ```
   Comment says: "Always use fill-missing-only behavior (never overwrite)"

2. **Orchestrator incomplete for duration**: `lib/features/songs/services/song_enrichment_orchestrator.dart:124-127`
   ```dart
   final needsBpm = enrichBpm && (overwriteExisting || song.bpm == null);
   final needsDuration = enrichDuration && song.durationSeconds == 0;  // BUG: doesn't check overwriteExisting
   final needsKey = enrichKey && (overwriteExisting || song.musicalKey == null);
   ```
   Duration skips songs with non-zero values even if `overwriteExisting` is true.

3. **EnrichmentSelectorResult exists but unused**: The `overwriteExisting` field exists and is plumbed through to the orchestrator, but it has no effect because of (1) and (2).

**Root Cause Confidence:** HIGH (directly observed in code)

---

# Reconciliation with bug/song-duration-edit-silently-fails

The unmerged branch `bug/song-duration-edit-silently-fails` (commit `872789f`, migration `20260827120000_fix_song_duration_write_once.sql`) changes `duration_seconds` from fill-once to always-overwrite using COALESCE, affecting **all callers** (enrichment and manual edits).

**Reconciliation Strategy:**

This feature will **rebase on top of (or merge after)** the bug branch, treating duration as already solved:
- Bug branch: makes `duration_seconds` always overwrite for everyone (fixes manual edits)
- This feature: adds optional `p_allow_enrich_overwrite` param for **BPM and Key only**
- Net result: Duration always overwrites (correct for both use cases), BPM/Key overwrite only when enrichment explicitly requests it

This avoids duplicating or conflicting with the bug branch's migration. The Engineer must verify the bug branch has been merged to `main` before starting implementation, or coordinate with Tony if both branches need to be reconciled in the same migration window.

---

# Reference Docs Consulted

- `docs/reference/bpm/BPM_QUICK_REFERENCE.md` - background on song enrichment architecture
- `docs/reference/bpm/BPM_FEATURE_IMPLEMENTATION.md` - enrichment service patterns
- No notification-domain docs were relevant (this is a setlist/song metadata feature)

---

# Existing System Analysis

## Data Flow

1. User taps "Enrich Song Data" → `showEnrichmentSelectorBottomSheet()` displays checkboxes
2. User checks BPM/Duration/Key fields → UI returns `EnrichmentSelectorResult` with `overwriteExisting: false` (hardcoded)
3. `SongEnrichmentOrchestrator.enrichSongs()` filters songs:
   - Checks `overwriteExisting || field is null/empty` for BPM and Key
   - Checks `durationSeconds == 0` for Duration (doesn't look at overwriteExisting)
4. For each song needing enrichment, orchestrator fetches metadata from GetSongBPM
5. Orchestrator calls `SetlistRepository.enrichSongs()` → calls `update_song_metadata` RPC
6. RPC blocks BPM/Key overwrites with CASE logic, returns `success: true` even if fields unchanged

## Call Sites for update_song_metadata

`lib/features/setlists/setlist_repository.dart` has ~9 call sites:
- `enrichSongs()` (~line 3490) - batch enrichment, passes multiple fields
- `updateSongBpmOverride()` (~line 1551) - manual single-field edit
- `updateSongDurationOverride()` (~line 1869) - manual single-field edit
- `updateSongMusicalKey()` (~line 2400) - manual single-field edit
- Several others for tuning, notes, title, artist, lyrics

**Critical constraint:** All manual-edit call sites pass `null` for fields they're not updating. They must continue working unchanged. Any new RPC parameter must be **optional with safe default** (default `false` = fill-once behavior) so existing calls are unaffected.

---

# Proposed Solution

## Design

Add optional `p_allow_enrich_overwrite BOOLEAN DEFAULT FALSE` parameter to `update_song_metadata` RPC. When `true`:
- **BPM**: overwrite if `p_bpm IS NOT NULL` (regardless of current value)
- **Musical Key**: overwrite if `p_musical_key IS NOT NULL` (regardless of current value)
- **Duration**: already always-overwrites after bug branch merge (no change needed)
- **Tuning**: already always-overwrites (COALESCE, no change)

When `false` (default): preserve current fill-once behavior for BPM/Key (backward compatible).

## Changes Required

### 1. Database (Migration)

Create `supabase/migrations/20260827_HHMMSS_add_enrich_overwrite_param.sql`:
- Add `p_allow_enrich_overwrite BOOLEAN DEFAULT FALSE` parameter to `update_song_metadata`
- Modify BPM and Key assignments:
  ```sql
  bpm = CASE 
    WHEN p_bpm IS NOT NULL AND (p_allow_enrich_overwrite OR bpm IS NULL) 
    THEN p_bpm 
    ELSE bpm 
  END
  
  musical_key = CASE
    WHEN p_musical_key IS NOT NULL AND (p_allow_enrich_overwrite OR musical_key IS NULL OR TRIM(musical_key) = '')
    THEN p_musical_key
    ELSE musical_key
  END
  ```
- Update verification logic to match
- Keep duration as COALESCE (assuming bug branch has merged)
- Drop and recreate function (includes new param in signature)
- Keep `GRANT EXECUTE ... TO authenticated` unchanged
- Update COMMENT to document new param

**Migration Dependencies:**
- MUST be applied after `20260827120000_fix_song_duration_write_once.sql` OR incorporate its changes if bug branch hasn't merged yet
- Engineer must check migration order and coordinate with Tony if conflict

### 2. Client - Repository Layer

**File:** `lib/features/setlists/setlist_repository.dart`

**Method:** `enrichSongs()` (line ~3490)

Add `p_allow_enrich_overwrite: true` to RPC params (enrichment always wants overwrite):
```dart
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
    'p_allow_enrich_overwrite': true,  // NEW: enable enrichment overwrites
  },
);
```

**No changes** to manual-edit methods (`updateSongBpmOverride`, etc.) - they omit the new param, defaulting to `false` (fill-once), preserving current behavior.

### 3. Client - Orchestrator Layer

**File:** `lib/features/songs/services/song_enrichment_orchestrator.dart`

**Line:** ~127 (duration check)

Fix duration to respect `overwriteExisting`:
```dart
// BEFORE
final needsDuration = enrichDuration && song.durationSeconds == 0;

// AFTER
final needsDuration = enrichDuration && (overwriteExisting || song.durationSeconds == 0);
```

Repeat same fix at line ~149 (second occurrence in same method).

### 4. Client - UI Layer

**File:** `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`

**Line:** ~87

Remove hardcoded `const bool overwriteExisting = false`:
```dart
// BEFORE
const bool overwriteExisting = false;

// AFTER
final bool overwriteExisting = true;  // Checkbox consent = allow overwrite
```

**Line:** ~85-87 (subtitle text)

Update subtitle to reflect new behavior:
```dart
// BEFORE
final subtitleText = 'Select data to auto-enrich for ${widget.songCount} '
    '${widget.songCount == 1 ? "song" : "songs"}. Only missing '
    'values will be filled — existing data is never overwritten.';

// AFTER
final subtitleText = 'Select data to auto-enrich for ${widget.songCount} '
    '${widget.songCount == 1 ? "song" : "songs"}. Checked fields will be '
    'updated with fresh data, overwriting existing values if necessary.';
```

---

# Database Impact

## RLS Policies
- **No impact:** RPC uses `SECURITY DEFINER`, RLS is already bypassed for legacy songs

## Migrations
- **New migration required:** Add `p_allow_enrich_overwrite` param to `update_song_metadata`
- **Dependency:** Must apply after (or incorporate) `20260827120000_fix_song_duration_write_once.sql` from bug branch

## RPC Signature
- **Additive change:** New optional param with safe default (`FALSE`)
- **Backward compatible:** All existing calls work unchanged (omitted param defaults to `false`)
- **No PostgREST overload risk:** Only one signature for `update_song_metadata` (11 params → 12 params)

## Tables
- **No schema changes:** Only function logic modified

## Triggers
- **No impact:** No triggers on `songs` table for this operation

---

# System Impact

| System | Impact | Reason |
|--------|--------|--------|
| Gigs | unaffected | Does not modify gig creation or response logic |
| Rehearsals | unaffected | Does not modify rehearsal persistence |
| Setlists / Catalog | **affected** | Song metadata updates broadcast via `songUpdateBroadcasterProvider`; all open setlists refresh enriched songs |
| Members / RBAC | unaffected | Uses existing band membership check in RPC; no permission changes |
| Auth / Session | unaffected | Uses existing `auth.uid()` check in RPC |
| Routing | unaffected | No navigation changes |
| Notifications | unaffected | No notification triggers for song enrichment |

---

# Files to Modify

## Database
1. `supabase/migrations/20260827_HHMMSS_add_enrich_overwrite_param.sql` (NEW)

## Client - Dart
2. `lib/features/setlists/setlist_repository.dart` (modify `enrichSongs()` only)
3. `lib/features/songs/services/song_enrichment_orchestrator.dart` (fix duration check, 2 locations)
4. `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` (remove hardcoded false, update subtitle)

**Total:** 1 new migration + 3 Dart files modified

---

# Off-Limits

Per Feature Input:
- ❌ `supabase/functions/getsongbpm_lookup/index.ts` (Phase A work, already shipped)
- ❌ `supabase/functions/getsongbpm_lookup/index.test.ts` (Phase A work)

Additional constraints:
- ❌ Do not modify manual-edit call sites (`updateSongBpmOverride`, etc.) - they must preserve current behavior
- ❌ Do not resurrect dual-value columns or diff-review sheets (Phase 2.2 was reverted Aug 2026)
- ❌ Do not add a separate confirmation dialog - checkbox itself is user consent

---

# Manual Edit Behavior (Unchanged)

Manual edits (inline BPM/Duration/Key edits in Song Details UI) call the same RPC but **omit** the new `p_allow_enrich_overwrite` parameter, so it defaults to `false`:
- **BPM manual edit:** Fill-once (unchanged)
- **Duration manual edit:** Always-overwrite (changed by bug branch, not this feature)
- **Key manual edit:** Fill-once (unchanged)

This preserves existing behavior for non-enrichment flows. Only the "Enrich Song Data" action explicitly passes `p_allow_enrich_overwrite: true`.

---

# User Consent Model

The checkbox itself serves as explicit user consent for overwriting. Product rule: "automated/background processes must never silently overwrite existing data without explicit user consent."

**Confirmation:** The user's own wording in the Feature Input - "as long as a field's checkbox is checked when they tap 'Enrich Song Data,' that field should be overwritten" - confirms the checkbox is the consent mechanism. No additional confirmation toggle needed.

---

# Testing Strategy

## Pre-Merge Validation (QA Agent)

1. **Manual smoke test on iOS device:**
   - Create song with existing BPM=120, Key=C, Duration=180
   - Run "Enrich Song Data" with all fields checked
   - Verify BPM/Key/Duration update to fetched values (overwrite)
   - Reopen song details - confirm new values persisted

2. **Checkbox gating:**
   - Same song, run enrichment with BPM unchecked, Key checked
   - Verify BPM unchanged, Key updated

3. **Manual edit preservation:**
   - Edit BPM manually on Song Details screen when value already exists
   - Verify edit still respects fill-once (or always-overwrite for duration per bug branch)

4. **Multi-song batch:**
   - Select 5 songs, run enrichment
   - Verify results overlay shows per-song success/failure
   - Verify song cards update immediately (broadcast refresh)

5. **Empty field fill:**
   - Song with BPM=null, run enrichment with BPM checked
   - Verify BPM fills (same as today - fill-once still works)

## Automated Tests

Not required (project has minimal test coverage per `GUARDRAILS.md`). If Engineer adds tests, target:
- `song_enrichment_orchestrator.dart` - unit test `needsDuration` logic respects `overwriteExisting`

---

# Rollback Plan

If production issues arise:

1. **Revert migration:**
   ```sql
   -- Restore 11-param signature from 20260811120001
   CREATE OR REPLACE FUNCTION update_song_metadata(
     -- 11 params, no p_allow_enrich_overwrite
     ...
   ) RETURNS JSON ...
   ```

2. **Client auto-adapts:** Passing extra param to old function signature fails gracefully (PostgREST error), enrichment still attempts but won't overwrite

3. **No data corruption risk:** Worst case = enrichment doesn't overwrite (returns to current behavior)

---

# Migration Timing

**Recommended:** Apply after `bug/song-duration-edit-silently-fails` merges to `main`. If that branch hasn't merged yet, Engineer must either:
- Wait for merge, then rebase this feature branch
- Or incorporate the duration COALESCE change from `20260827120000_fix_song_duration_write_once.sql` into this feature's migration (single combined migration)

Tony must confirm merge status before Engineer proceeds.

---

# Security Considerations

- **No new attack surface:** New param only affects enrichment flow, which already requires authenticated user + active band membership
- **RLS bypass unchanged:** Function remains `SECURITY DEFINER` (required for legacy NULL band_id songs)
- **ACL unchanged:** `GRANT EXECUTE ... TO authenticated` preserved (no anon access)
- **No service_role key exposure:** Client uses anon key only

---

# Brand Voice (UI Copy)

Updated subtitle in enrichment selector:
> "Select data to auto-enrich for N songs. Checked fields will be updated with fresh data, overwriting existing values if necessary."

Shorter, clearer, removes the incorrect "never overwritten" claim.

---

# Success Criteria

- ✅ User can overwrite existing BPM/Duration/Key during enrichment when checkboxes are checked
- ✅ Unchecked fields are never touched (same as today)
- ✅ Manual edits (non-enrichment) preserve current behavior
- ✅ Multi-song enrichment batch works correctly
- ✅ Song cards in all open setlists refresh immediately after enrichment
- ✅ `flutter analyze` passes with 0 errors
- ✅ No PostgREST PGRST203 ambiguous function errors

---

# Architect Sign-Off

**Diagnosis Confidence:** HIGH (directly observed in code)  
**Solution Risk:** LOW (additive change, backward compatible)  
**Merge Blocker:** Confirm `bug/song-duration-edit-silently-fails` merge status before starting  

This plan is ready for Engineer implementation.
