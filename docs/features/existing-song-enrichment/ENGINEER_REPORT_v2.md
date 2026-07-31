# Engineer Report (v2)

## Feature Slug

existing-song-enrichment

## Scope of This Fix

This pass fixes only the two issues identified in `QA_REPORT_v2.md`:

1. Partial enrichment results were discarded when one provider call failed.
2. Single-song enrichment did not broadcast a refresh event.

No unrelated approved work (toolbar, selector styling, spinner behavior) was modified.

## Changes Made

### 1) Partial success preservation in orchestrator

**File:** `lib/features/songs/services/song_enrichment_orchestrator.dart`

**What changed:**

- Split enrichment provider calls into independent error handling blocks:
  - GetSongBPM lookup (BPM/Key)
  - External duration lookup (iTunes/MusicBrainz)
- Removed the shared `try`/`catch` behavior that converted the whole song to `error` when one provider failed.
- Preserved successful fetched values from one provider even if the other provider fails.
- Always attempts RPC update when at least one field resolved (`updateMap` is non-empty).
- Per-field result reporting now reflects true mixed outcomes per song:
  - `updated`, `notFound`, or `error` can coexist across fields for the same song.
- Song-level summary counters now support partial outcomes without collapsing the song into one state.

**Why:**

This ensures a duration lookup failure no longer discards successful BPM/Key results, matching the fill-missing behavior expected for partial success.

### 2) Single-song enrichment broadcast refresh

**File:** `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

**What changed:**

- Added import for `setlist_detail_controller.dart` to access `songUpdateBroadcasterProvider` and `SongUpdateEvent`.
- After single-song orchestration completes, added the same broadcast pattern used by other enrichment entry points:
  - For any song with at least one `updated` field, broadcast `SongUpdateEvent(songId: detail.songId)`.
- Broadcast happens before showing the results overlay.

**Why:**

This aligns single-song behavior with multi-select/catalog-wide paths so catalog/list UIs refresh immediately after successful enrichment.

## Analyzer Result

Command run: `flutter analyze`

- Errors: 0
- Info: 1
  - `lib/features/setlists/setlist_detail_screen.dart:1449` (`use_build_context_synchronously`)

No new analyzer errors were introduced by this fix.

## Files Modified in This Pass

- `lib/features/songs/services/song_enrichment_orchestrator.dart`
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`

## Ready For QA

Yes. The two scoped issues from `QA_REPORT_v2.md` are addressed in this pass.
