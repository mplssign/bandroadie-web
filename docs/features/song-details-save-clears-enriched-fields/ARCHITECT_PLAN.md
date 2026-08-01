# ARCHITECT PLAN

## Feature Slug

`bug/song-details-save-clears-enriched-fields`

## Problem Summary

After enrichment writes BPM/duration/key for an existing song, Song Details can still hold stale local values in the open bottom sheet. A subsequent Save may interpret stale local blanks/defaults as user-intentional clears and write those values back, reverting enrichment.

## Root Cause

**Primary root cause (HIGH confidence): stale local form state is initialized once and never synchronized after async enrichment completes.**

Evidence in code:

1. Local form state is initialized once in `initState` from `widget.song`:
   - `_currentBpm = widget.song.bpm` at `song_details_bottom_sheet.dart:167`
   - `_currentDurationSeconds = widget.song.durationSeconds` at `song_details_bottom_sheet.dart:168`
   - `_currentMusicalKey = widget.song.musicalKey` at `song_details_bottom_sheet.dart:184`
2. `_handleEnrichSong` performs async enrichment, then only broadcasts a generic update event and shows results overlay:
   - enrichment call at `song_details_bottom_sheet.dart:549-555`
   - broadcast at `song_details_bottom_sheet.dart:560-566`
   - results overlay at `song_details_bottom_sheet.dart:570-573`
3. No refresh of `_currentBpm`, `_currentDurationSeconds`, `_currentMusicalKey`, or any local baseline happens after enrichment resolves.
4. Change detection and save decisions compare local state vs baseline fields:
   - `_checkForChanges` compares `_currentBpm` vs `widget.song.bpm` and `_currentDurationSeconds` vs `widget.song.durationSeconds` at `song_details_bottom_sheet.dart:246-248`, then sets `_hasChanges` and logs `bpmChanged/anyChanged` at `song_details_bottom_sheet.dart:267-273`.
   - `_handleSave` repeats the same changed-field comparisons at `song_details_bottom_sheet.dart:407-413`, and emits `SongDetailsResult` with changed flags at `song_details_bottom_sheet.dart:426-446`.
5. Parent save handler executes clear/update RPCs strictly from those flags:
   - if `result.bpmChanged && result.bpm == null` => `clearSongBpm(...)` at `setlist_detail_screen.dart:1623-1631`
   - if `result.durationChanged` => `updateSongDuration(... result.duration!)` at `setlist_detail_screen.dart:1636-1641`

This is exactly the destructive path: stale local values are treated as true edits.

## Existing System Analysis

Current bottom sheet state lifecycle:

1. Open sheet with `showSongDetailsBottomSheet(...)`.
2. Initialize local mutable state from `widget.song` one time in `initState`.
3. User taps `Enrich Song Data`; enrichment writes to DB asynchronously.
4. Sheet does **not** rehydrate its local form state from post-enrichment song data.
5. Save compares local state against baseline and can mark fields changed.
6. Parent applies per-field mutations (including explicit clears) based on changed flags.

Important secondary observation:

- The enrichment broadcast currently sends only `SongUpdateEvent(songId: ...)` with no field payload from this path, so the event alone is not sufficient for precise metadata synchronization.

## Proposed Solution (Minimal, Safe)

Implement a local-state rebaseline step inside Song Details after enrichment success.

### Required behavior

1. After `_handleEnrichSong` completes and before returning control to user actions, fetch fresh song metadata for the current song id.
2. If enrichment updated any field for this song, update both:
   - local editable values (`_currentBpm`, `_currentDurationSeconds`, `_currentMusicalKey`)
   - local baseline/original values used for change detection (new `_originalBpm`, `_originalDurationSeconds`, and existing `_originalMusicalKey`)
3. Recompute `_hasChanges` immediately after rebaseline so Save is disabled unless user subsequently edits.
4. `_handleSave` and `_checkForChanges` must compare against local baseline variables, not potentially stale/externally-shifting assumptions.

### Why this fix

- Keeps change-source-of-truth inside the sheet coherent after async external mutation.
- Prevents silent destructive writes from stale controls.
- Requires no architecture expansion and no DB/RPC changes.

## Implementation Boundaries

### Files to Modify

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
  - Add explicit baseline fields for BPM and duration.
  - Add a post-enrichment refresh/rebaseline method.
  - Update `_checkForChanges` and `_handleSave` comparisons to use maintained baselines.
  - Ensure `_hasChanges` is recalculated after rebaseline.

### Files Off-Limits

- `lib/features/setlists/setlist_detail_screen.dart`
  - No save pipeline change in this bug fix; keep existing per-field write behavior.
- `lib/features/setlists/setlist_detail_controller.dart`
  - No notifier/repository contract changes in this bug fix.
- `lib/features/setlists/setlist_repository.dart`
  - No RPC/database behavior changes required.
- `supabase/migrations/**`
  - Not part of this bug.

### Database / Migration Policy

- Migration required: **No**
- RPC signature changes: **No**
- Edge function deploy: **No**
- New dependencies: **No**
- New files: **None**

## Regression Risk

**LOW to MEDIUM**

Rationale:

- Surface area is one widget file.
- Logic touches Save enablement and changed-flag computation, so regression risk is centered on metadata edit UX.
- No backend/schema changes.

## Engineer Task Breakdown

1. Add local baseline state variables for BPM and duration in the Song Details state class.
2. Initialize those baseline values in `initState` alongside existing local fields.
3. Extract comparison logic into a single internal helper that uses local baselines (avoid divergence between `_checkForChanges` and `_handleSave`).
4. Add a post-enrichment refresh/rebaseline flow in `_handleEnrichSong`:
   - only when enrichment result indicates at least one updated field for the current song.
   - fetch latest song record.
   - update local values + baselines in one `setState`.
   - recompute `_hasChanges`.
5. Keep existing UI structure unchanged for this bug fix (button reordering is separate scope).
6. Run static analysis and targeted manual flow validation.

## Verification Plan

1. Repro baseline (before fix) documented by QA logs: enrichment followed by Save can clear BPM/duration.
2. After fix, execute this flow:
   - Open Song Details for song with null/0 metadata.
   - Trigger enrichment that updates BPM and/or duration/key.
   - Confirm the metrics row updates to enriched values in the same open sheet.
   - Confirm Save is disabled immediately after rebaseline when no user edits remain.
   - Tap Save without edits; verify no clear RPC path is invoked and values persist.
3. Edit one field intentionally after enrichment, Save, and verify only that intended field is written.
4. Validate non-enrichment edits still work:
   - direct BPM clear should still call clear behavior when explicitly user-cleared.
   - duration edits should still persist expected numeric values.

## QA Regression Areas

- Song Details: enrich then immediate Save with no manual edits (primary bug).
- Song Details: enrich then intentional manual edit then Save (ensure only intentional change persists).
- Song Details: direct BPM clear and duration edit flows (no regression in explicit edits).
- Catalog and non-catalog metadata edits unaffected by this fix.

## Out of Scope

- Moving `Enrich Song Data` button above the metrics row.
- Refactoring broadcaster payload contracts across the setlist feature.
- Any database/RPC logic changes.
