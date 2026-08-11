# ARCHITECT_PLAN — Show Diffs Review UI for Existing-Song Enrichment (Phase 2.3b)

## Feature Slug

`feature/enrichment-show-diffs`

---

## Problem Summary

Phase 2.3a (merged 2026-08-10, PR #138, commit 6fc4e70) introduced a band-level `existing_song_behavior` setting with three enum values: `fill-missing-only`, `auto-replace`, and `show-diffs`. Only the first two are functional. The `show-diffs` value is schema-reserved but not wired to any behavior — when selected, the system silently falls back to `fill-missing-only` behavior in `enrichment_selector_bottom_sheet.dart` (lines 71-98).

The settings screen shows a static note under the Show Diffs option: "Review changes before updating (coming in Phase 2.3b)" (line 189) and a fallback notice when selected: "Diff review UI coming in Phase 2.3b — currently falls back to Fill Missing Only" (lines 206-215).

Users who select "Show Diffs" expect to see a side-by-side comparison of current values vs. enriched values with per-field accept/reject controls before any write happens. Instead, the system behaves identically to "Fill Missing Only" mode with no user feedback about the fallback.

This feature implements the deferred `show-diffs` behavior.

---

## Root Cause

**Not applicable** — this is a greenfield feature (Phase 2.3a explicitly deferred this functionality to Phase 2.3b).

**Confidence Level:** N/A

---

## Reference Docs Consulted

**Phase 2.3a documentation (required reading):**

- `docs/features/enrichment-settings/ARCHITECT_PLAN.md` — complete context for the enrichment settings system, the three enum values, and the deferral decision (lines 1352-1409)
- `docs/features/enrichment-settings/ENGINEER_REPORT.md` — implementation details for Phase 2.3a
- `docs/features/enrichment-settings/QA_REPORT.md` — verified behavior of fill-missing-only and auto-replace modes

**Existing patterns:**

- `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` — new-song review UI pattern with field-by-field editing (Ask mode). Closest existing pattern for review-before-save, but different flow (new song, not diff comparison).
- `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` — entry point for existing-song enrichment, currently computes boolean `overwriteExisting` flag from `ExistingSongBehavior` enum (lines 71-98)
- `lib/features/songs/services/song_enrichment_orchestrator.dart` — batch enrichment coordinator, currently only understands boolean `overwriteExisting` parameter

**Database layer:**

- `supabase/migrations/20260809120001_update_song_metadata_dual_value.sql` — current `update_song_metadata` RPC signature. Supports field-level writes via optional parameters (pass NULL for fields to skip). Uses COALESCE for dual-value columns (always overwrite when provided).
- `supabase/migrations/20260810000000_enrichment_settings.sql` — enrichment_settings table with CHECK constraint for `show-diffs` enum value (already shipped)

**No known related bugs:** The Phase 2.3a QA report confirms fill-missing-only and auto-replace modes work correctly. This feature extends the system with a third mode, not fixes a bug.

---

## Existing System Analysis

### Current Enrichment Flow (Existing Songs)

**Entry point:** User opens Enrichment Drawer from Setlist Detail screen → `enrichment_selector_bottom_sheet.dart`

**Step 1:** Bottom sheet reads `enrichmentSettingsProvider` for active band

```dart
final existingSongBehavior = settingsAsync.whenOrNull(
  data: (settings) => settings.existingSongBehavior,
) ?? ExistingSongBehavior.fillMissingOnly; // fallback
```

**Step 2:** User selects fields to enrich (BPM, Duration, Key) via checkboxes

**Step 3:** Bottom sheet computes `overwriteExisting` flag based on `existingSongBehavior`:

- `fillMissingOnly` → `overwriteExisting = false`
- `autoReplace` → `overwriteExisting = true`
- `showDiffs` → `overwriteExisting = false` **(fallback — no diff UI implemented)**

**Step 4:** Bottom sheet returns `EnrichmentSelectorResult`:

```dart
EnrichmentSelectorResult(
  bpmSelected: _bpmSelected,
  durationSelected: _durationSelected,
  keySelected: _keySelected,
  overwriteExisting: overwriteExisting,
)
```

**Step 5:** Caller (`setlist_detail_screen.dart`) invokes `SongEnrichmentOrchestrator.enrichSongs()`:

```dart
await orchestrator.enrichSongs(
  bandId: bandId,
  songIds: selectedSongIds,
  enrichBpm: result.bpmSelected,
  enrichDuration: result.durationSelected,
  enrichKey: result.keySelected,
  overwriteExisting: result.overwriteExisting,
  onProgress: (completed, total) { /* ... */ },
);
```

**Step 6:** Orchestrator fetches songs, filters by eligibility, calls enrichment APIs, writes to DB via RPC

**Step 7:** Results overlay shows per-song outcomes (updated/not-found/unchanged/error)

### Current Gap

When `existingSongBehavior == showDiffs`:

- No diff review UI is shown
- System silently behaves as `fillMissingOnly` (only writes to NULL fields)
- User has no visibility into what enrichment values were found or skipped
- No per-field accept/reject controls exist
- Static note on settings screen acknowledges the missing functionality

### Existing Enrichable Fields

From `update_song_metadata` RPC signature (lines 31-44 of 20260809120001 migration):

- **BPM** (`p_source_bpm`) — dual-value, COALESCE (always overwrite when provided)
- **Musical Key** (`p_source_musical_key`) — dual-value, COALESCE (always overwrite when provided)
- **Tuning** (`p_source_tuning`) — dual-value, COALESCE (always overwrite when provided)
- **Duration** (`p_duration_seconds`) — single-value, NOT part of source/performance model, uses 0-check not NULL-check

**Note:** Phase 2.2 (dual-value columns) only added source/performance for BPM, Key, and Tuning. Duration remains a single-value field and is not currently enriched by the orchestrator for existing songs (only for new songs via Song Lookup).

**Current orchestrator enrichment scope** (from `song_enrichment_orchestrator.dart` lines 105-114):

- **BPM:** Enriched via `SongEnrichmentService.lookup()` → writes to `source_bpm`
- **Key:** Enriched via `SongEnrichmentService.lookup()` → writes to `source_musical_key`
- **Duration:** Enriched via `ExternalSongLookupService.searchExternalSongs()` → writes to `duration_seconds`
- **Tuning:** NOT enriched by orchestrator (manual entry only)

**For Phase 2.3b diff review:** Show diffs for BPM, Key, and Duration. Tuning is not enriched, so it does not appear in diff UI.

---

## Proposed Solution

### Architecture Overview

**New diff review UI:** Modal bottom sheet (similar to `song_enrichment_review_sheet.dart` pattern) that shows:

1. Song title/artist (non-editable header)
2. Per-field comparison rows for BPM, Key, Duration (only if enrichment was requested and API returned a value)
3. Each row shows: **Current value** ←→ **Enriched value** with an accept/reject toggle per field
4. Bulk "Accept All" / "Reject All" buttons
5. Confirm button (disabled until at least one field is accepted)

**Flow modification:**

**Before (Phase 2.3a):**

```
User opens drawer → selects fields → showDiffs behavior → computes overwriteExisting=false → calls orchestrator → writes only to NULL fields
```

**After (Phase 2.3b):**

```
User opens drawer → selects fields → showDiffs behavior → orchestrator runs in "preview mode" (fetch enrichment data, do NOT write to DB) → show diff review UI → user accepts/rejects per field → write only accepted fields to DB → show results overlay
```

**Key difference:** Orchestrator must support a "preview mode" that fetches enrichment data but does not write to DB, returning the enriched values for diff review instead of writing immediately.

### Implementation Strategy

**Option A (chosen):** Add `previewMode` parameter to `SongEnrichmentOrchestrator.enrichSongs()`. When true, orchestrator fetches enrichment data and returns it in `EnrichmentOrchestrationResult.details` without calling the RPC. Caller shows diff review UI, collects user decisions, then calls a new method `applyEnrichmentDiff()` to write only accepted fields.

**Why Option A:**

- Minimal diff surface (one parameter + one new method)
- Preserves existing orchestrator logic for fill-missing-only and auto-replace modes
- No new abstractions — reuses existing `EnrichmentOrchestrationResult` with extended semantics
- Clear separation: fetch → review → write

**Option B (rejected):** Create a new `SongEnrichmentDiffService` that wraps orchestrator logic. **Rejected:** Speculative abstraction, violates "no new architecture unless existing pattern cannot solve the problem" guardrail.

**Option C (rejected):** Refactor orchestrator to always return diff data, caller decides whether to show UI. **Rejected:** Breaking change for existing callers (fill-missing-only and auto-replace modes don't need diff data).

### Orchestrator Changes

**Current signature:**

```dart
Future<EnrichmentOrchestrationResult> enrichSongs({
  required String bandId,
  required List<String> songIds,
  required bool enrichBpm,
  required bool enrichDuration,
  required bool enrichKey,
  bool overwriteExisting = false,
  void Function(int completed, int total)? onProgress,
})
```

**New signature:**

```dart
Future<EnrichmentOrchestrationResult> enrichSongs({
  required String bandId,
  required List<String> songIds,
  required bool enrichBpm,
  required bool enrichDuration,
  required bool enrichKey,
  bool overwriteExisting = false,
  bool previewMode = false, // NEW: fetch enrichment data but do not write to DB
  void Function(int completed, int total)? onProgress,
})
```

**Behavior when `previewMode = true`:**

- Fetch songs from DB (unchanged)
- Filter by eligibility (unchanged)
- Call enrichment APIs (unchanged)
- **Skip RPC write** — do not call `_repository.enrichSongs()`
- Return enriched values in `SongEnrichmentDetail` (extend model to include `enrichedBpm`, `enrichedKey`, `enrichedDuration`)

**New model:**

```dart
class SongEnrichmentDetail {
  final String songId;
  final String title;
  final String artist;
  final EnrichmentFieldResult bpmResult;
  final EnrichmentFieldResult durationResult;
  final EnrichmentFieldResult keyResult;
  // NEW: Preview mode data (null when previewMode=false)
  final int? currentBpm;
  final String? currentKey;
  final int? currentDuration;
  final int? enrichedBpm;
  final String? enrichedKey;
  final int? enrichedDuration;
}
```

**New method:**

```dart
Future<void> applyEnrichmentDiff({
  required String bandId,
  required Map<String, EnrichmentDiffDecision> decisions,
})
```

Where `EnrichmentDiffDecision` is:

```dart
class EnrichmentDiffDecision {
  final int? acceptedBpm;
  final String? acceptedKey;
  final int? acceptedDuration;
}
```

This method calls `_repository.enrichSongs()` with only the accepted fields for each song.

### UI Flow (Show Diffs Mode)

**Step 1:** User opens Enrichment Drawer, selects fields (BPM, Duration, Key), taps "Enrich Songs"

**Step 2:** Bottom sheet detects `existingSongBehavior == showDiffs`, sets `previewMode = true`

**Step 3:** Call orchestrator:

```dart
final previewResult = await orchestrator.enrichSongs(
  bandId: bandId,
  songIds: selectedSongIds,
  enrichBpm: result.bpmSelected,
  enrichDuration: result.durationSelected,
  enrichKey: result.keySelected,
  previewMode: true, // NEW
  onProgress: (completed, total) { /* show "Fetching enrichment data..." progress */ },
);
```

**Step 4:** Show diff review bottom sheet:

```dart
final decisions = await showEnrichmentDiffReviewSheet(
  context,
  songs: previewResult.details,
);
```

**Step 5:** If user confirms (not cancelled), call `applyEnrichmentDiff()`:

```dart
await orchestrator.applyEnrichmentDiff(
  bandId: bandId,
  decisions: decisions,
);
```

**Step 6:** Show results overlay (reuse existing `EnrichmentResultsOverlay`)

### Diff Review UI Spec

**Widget:** `EnrichmentDiffReviewSheet` (new file: `lib/features/songs/widgets/enrichment_diff_review_sheet.dart`)

**Layout:**

- **Header:** "Review Enrichment Changes" + close button
- **Subtitle:** "Accept or reject enriched values for each field. Only accepted changes will be saved."
- **Song list:** Scrollable list of songs with expandable/collapsible rows
- **Per-song row:**
  - Song title/artist (bold)
  - Expandable section showing per-field diffs:
    - **BPM:** `120 → 128` with Accept/Reject toggle (default: Accept)
    - **Key:** `C Major → D Major` with Accept/Reject toggle (default: Accept)
    - **Duration:** `3:45 → 3:52` with Accept/Reject toggle (default: Accept)
  - If no changes found for a field: show "No change" or hide row
- **Bulk controls:** "Accept All" / "Reject All" buttons (applies to all fields across all songs)
- **Footer:** "Confirm" button (disabled if all fields rejected), "Cancel" button

**Interaction:**

- Tap song row → expand/collapse per-field diffs
- Tap Accept/Reject toggle → update decision state
- Tap "Accept All" → set all fields to Accept
- Tap "Reject All" → set all fields to Reject
- Tap "Confirm" → return `Map<String, EnrichmentDiffDecision>` with only accepted fields
- Tap "Cancel" or back button → return `null`

**Display rules:**

- Only show fields that were enriched (if BPM was not checked in drawer, don't show BPM row)
- Only show songs where at least one field has a diff (current ≠ enriched)
- If enriched value == current value, mark as "No change" (don't allow Accept/Reject, field is skipped)
- If enrichment API returned `null` or "not found", mark as "Not found" (don't show diff row)
- **Duration special case (fill-only RPC semantics):**
  - If current duration is 0 (missing) AND enriched duration differs: show as actionable diff with Accept/Reject toggle (default: Accept)
  - If current duration is non-zero AND enriched duration differs: show as **informational-only** ("Enrichment found: X:XX") without Accept/Reject toggle, with explanation: "Current duration is already set. Clear it first to apply enriched value."
  - This prevents false-success writes (RPC would return `success: true` but DB value unchanged due to CASE...ELSE fill-only logic)

**Visual design:**

- Follow existing modal bottom sheet pattern (`song_enrichment_review_sheet.dart` structure)
- Use `AppScaffold` + drag handle
- Current value: left-aligned, muted color
- Arrow icon: `→` between current and enriched
- Enriched value: right-aligned, primary color
- Accept toggle: green checkmark icon, Reject toggle: red X icon (default: Accept)

### Settings Screen Change

Remove the static note "Diff review UI coming in Phase 2.3b — currently falls back to Fill Missing Only" from `enrichment_settings_screen.dart` (lines 199-217).

Update the subtitle for "Show Diffs" radio tile (line 189):
**Before:** `'Review changes before updating (coming in Phase 2.3b)'`
**After:** `'Review changes before updating existing songs'`

---

## Database Impact

**Database:** not applicable

No schema changes required. The `show-diffs` enum value already exists in `enrichment_settings.existing_song_behavior` column (CHECK constraint from 20260810000000 migration).

**RPC field-level write semantics:**

The `update_song_metadata` RPC (migration `20260809120001_update_song_metadata_dual_value.sql`) has **different write semantics per field**:

| Field    | Parameter              | Write Logic                                                                                                                                              | Accept Behavior in Diff UI                                                                                                                                                                                          |
| -------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BPM      | `p_source_bpm`         | COALESCE (always overwrite when provided)                                                                                                                | Always writable — Accept writes enriched value regardless of current value                                                                                                                                          |
| Key      | `p_source_musical_key` | COALESCE (always overwrite when provided)                                                                                                                | Always writable — Accept writes enriched value regardless of current value                                                                                                                                          |
| Duration | `p_duration_seconds`   | CASE...ELSE (fill-only: `CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END`, line 103) | **Fill-only** — Accept only writes when current value is 0. If current value is non-zero, write is silently skipped (RPC returns `success: true` but DB value unchanged — known CASE...ELSE false-success pattern). |

**Duration limitation:** Because Duration uses fill-only semantics (not COALESCE), the diff UI must **only show Duration as an actionable diff (with Accept/Reject) when the song's current duration is 0**. If enrichment finds a different duration for a song that already has a non-zero duration, the UI shows it as **informational-only** ("Enrichment found: X:XX" without Accept/Reject controls) since there is no write path that can apply it.

**Why not change the RPC:** Duration is intentionally fill-only (not part of the source/performance dual-value model introduced in Phase 2.2). Changing it to COALESCE would require:

- RPC migration (breaks "no DB changes" claim)
- Risk assessment increase (touches existing fill-missing-only and auto-replace write paths)
- Justification for why Duration should be always-overwrite when BPM/Key use source vs. performance distinction

**RPC usage pattern (no signature change):**
When user accepts only BPM for song X:

```dart
await supabase.rpc('update_song_metadata', params: {
  'p_song_id': songX.id,
  'p_band_id': bandId,
  'p_source_bpm': acceptedBpm,
  // p_source_musical_key: NULL (omitted, no update)
  // p_duration_seconds: NULL (omitted, no update)
});
```

BPM and Key use COALESCE → always written. Duration (if included) only written when current value is 0.

---

## Flutter Architecture Changes

### New Files

| File                                                           | Purpose                                                    |
| -------------------------------------------------------------- | ---------------------------------------------------------- |
| `lib/features/songs/widgets/enrichment_diff_review_sheet.dart` | Diff review UI modal with per-field accept/reject controls |
| `lib/features/songs/models/enrichment_diff_decision.dart`      | Model for per-song field acceptance decisions              |

### Modified Files

| File                                                               | What Changes                                                                                                                                                          |
| ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`    | Add `previewMode` parameter to `enrichSongs()`, extend `SongEnrichmentDetail` model with current/enriched values, add `applyEnrichmentDiff()` method                  |
| `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` | When `existingSongBehavior == showDiffs`, call orchestrator with `previewMode: true`, show diff review UI, call `applyEnrichmentDiff()` with user decisions           |
| `lib/features/songs/enrichment_settings_screen.dart`               | Remove "coming in Phase 2.3b" note (lines 199-217), update "Show Diffs" subtitle (line 189)                                                                           |
| `lib/features/setlists/setlist_repository.dart`                    | Potentially add `enrichSongsPartial()` method if field-level writes need a separate code path (evaluate during implementation — existing `enrichSongs()` may suffice) |

**Repository change evaluation:** The existing `enrichSongs()` method signature is:

```dart
Future<Map<String, bool>> enrichSongs({
  required String bandId,
  required Map<String, Map<String, dynamic>> updates,
})
```

The `updates` map is `songId → {field: value}`. This already supports field-level writes (pass only the fields you want to update). **No new repository method required** — `applyEnrichmentDiff()` can call the existing `enrichSongs()` method with filtered field maps.

---

## Files to Create

| File                                                           | Justification                                                                                  |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `lib/features/songs/widgets/enrichment_diff_review_sheet.dart` | New UI component for diff review (no existing equivalent)                                      |
| `lib/features/songs/models/enrichment_diff_decision.dart`      | Type-safe model for per-song accept/reject decisions (prevents Map<String, dynamic> ambiguity) |

---

## Files to Modify

| File                                                               | Lines              | What Changes                                                                                                                                                                                                                     |
| ------------------------------------------------------------------ | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`    | 78-99, 28-40, 330+ | Add `previewMode` parameter (default `false`), extend `SongEnrichmentDetail` with 6 new fields (current/enriched values), modify enrichment loop to skip RPC write when `previewMode = true`, add `applyEnrichmentDiff()` method |
| `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart` | 71-120             | Read `existingSongBehavior`, when `showDiffs` → call orchestrator with `previewMode: true`, show `showEnrichmentDiffReviewSheet()`, call `applyEnrichmentDiff()` with decisions                                                  |
| `lib/features/songs/enrichment_settings_screen.dart`               | 189, 199-217       | Update subtitle text, remove fallback notice container                                                                                                                                                                           |

---

## Files Off-Limits

| File                                                                     | Reason                                                                                                                                                     |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                          | Initialization order must not change                                                                                                                       |
| `lib/features/setlists/setlist_repository.dart`                          | Existing `enrichSongs()` method already supports field-level writes — no changes needed unless implementation reveals a blocker (then escalate to Manager) |
| `lib/features/songs/external_song_lookup_service.dart`                   | Enrichment API wrapper unchanged                                                                                                                           |
| `lib/features/songs/song_enrichment_service.dart`                        | Enrichment API wrapper unchanged                                                                                                                           |
| `supabase/migrations/20260809120001_update_song_metadata_dual_value.sql` | RPC signature already supports field-level writes                                                                                                          |
| `supabase/migrations/20260810000000_enrichment_settings.sql`             | Enum value already exists, no schema changes required                                                                                                      |
| All test files                                                           | No new tests required (project conventions: minimal test coverage)                                                                                         |

---

## System Impact Map

| System                                 | Impact                                                                               |
| -------------------------------------- | ------------------------------------------------------------------------------------ |
| Gigs                                   | unaffected                                                                           |
| Rehearsals                             | unaffected                                                                           |
| Setlists / Catalog                     | **affected** — existing-song enrichment behavior changes when Show Diffs is selected |
| Members / RBAC                         | unaffected                                                                           |
| Auth / Session                         | unaffected                                                                           |
| Routing                                | unaffected                                                                           |
| Notifications                          | unaffected                                                                           |
| Platform (iOS / Android / Web / macOS) | unaffected — all platforms support modal bottom sheets                               |

---

## Regression Risk

**Level:** `LOW`

**Rationale:**

- **Isolated change:** Only affects `showDiffs` enum path, which currently has zero users (silently falls back to fill-missing-only)
- **Existing modes unchanged:** `fillMissingOnly` and `autoReplace` modes continue to call orchestrator with `previewMode: false` (default parameter), no behavior change
- **Orchestrator change is additive:** New parameter with default value (`previewMode = false`) preserves all existing call sites (3 callers in `setlist_detail_screen.dart` and `song_details_bottom_sheet.dart`)
- **No database changes:** Schema, RLS, and RPC unchanged
- **No new dependencies:** UI uses existing modal pattern, no new packages
- **Blast radius limited to enrichment system:** Does not touch setlist ordering, song creation, gig management, or auth flows

**Failure modes:**

- **Enrichment fetch fails in preview mode:** Same error handling as current orchestrator (return `EnrichmentFieldResult.error`), user sees "Failed to fetch enrichment" message, can cancel
- **User accepts all fields but RPC write fails:** Same error handling as current orchestrator (return error in results overlay), no silent data corruption
- **Diff UI crashes or hangs:** User can cancel (return null), enrichment is skipped, no data written
- **Existing mode regression:** Default parameter prevents behavior change for fill-missing-only and auto-replace callers

**Mitigation:**

- Preview mode does not write to DB — safe to test extensively in dev/staging without data side effects
- Diff UI is modal — if it fails to open, user remains in drawer and can retry or cancel
- All write operations go through existing RPC with existing validation and error handling

---

## Engineer Task Breakdown

### Task 1: Extend Orchestrator Model

**File:** `lib/features/songs/services/song_enrichment_orchestrator.dart`

**Steps:**

1. Extend `SongEnrichmentDetail` class (lines 28-40) with 6 new optional fields:
   - `int? currentBpm`
   - `String? currentKey`
   - `int? currentDuration`
   - `int? enrichedBpm`
   - `String? enrichedKey`
   - `int? enrichedDuration`
2. These fields are nullable and only populated when `previewMode = true`
3. Update constructor to accept new fields
4. Existing callers (fill-missing-only, auto-replace) continue to pass nulls or omit these fields

**Verification:**

- Compile check: no errors in existing call sites
- Runtime: fill-missing-only mode continues to return `SongEnrichmentDetail` with new fields as null

---

### Task 2: Add Preview Mode to Orchestrator

**File:** `lib/features/songs/services/song_enrichment_orchestrator.dart`

**Steps:**

1. Add `previewMode` parameter to `enrichSongs()` signature (line 78, default `false`)
2. In enrichment loop (lines 130-330), after fetching enrichment data and before RPC write:
   - If `previewMode = true`:
     - Populate `SongEnrichmentDetail` with `currentBpm`, `currentKey`, `currentDuration` (from song model)
     - Populate `enrichedBpm`, `enrichedKey`, `enrichedDuration` (from API response)
     - **Important:** Always populate `currentDuration` (even if non-zero) and `enrichedDuration` (even if differs from non-zero current) — the diff UI layer will decide whether to show as actionable or informational based on current value
     - Skip RPC call to `_repository.enrichSongs()`
     - Set per-field results to `EnrichmentFieldResult.updated` if enriched value exists, `EnrichmentFieldResult.notFound` if API returned null
   - If `previewMode = false`:
     - Execute existing logic (write to DB, populate results based on RPC success/failure)
3. Return `EnrichmentOrchestrationResult` with populated `details` list

**Verification:**

- Call `enrichSongs(previewMode: true)` with 1 song → returns enriched values, no DB write
- Call `enrichSongs(previewMode: false)` with same song → writes to DB, returns existing result format
- Check DB after preview call → no new `updated_at` timestamps
- **Duration-specific:** Call preview mode with song that has `duration_seconds = 180` → verify `currentDuration` and `enrichedDuration` both populated even though current is non-zero

---

### Task 3: Add Apply Diff Method

**File:** `lib/features/songs/services/song_enrichment_orchestrator.dart`

**Steps:**

1. Create new method `applyEnrichmentDiff()` (insert after `enrichSongs()` method, before class end)
2. Signature:
   ```dart
   Future<EnrichmentOrchestrationResult> applyEnrichmentDiff({
     required String bandId,
     required Map<String, EnrichmentDiffDecision> decisions,
   })
   ```
3. Implementation:
   - Build `updates` map for `_repository.enrichSongs()`:
     ```dart
     final updates = <String, Map<String, dynamic>>{};
     for (final entry in decisions.entries) {
       final songId = entry.key;
       final decision = entry.value;
       final songUpdates = <String, dynamic>{};
       if (decision.acceptedBpm != null) songUpdates['sourceBpm'] = decision.acceptedBpm;
       if (decision.acceptedKey != null) songUpdates['sourceMusicalKey'] = decision.acceptedKey;
       if (decision.acceptedDuration != null) songUpdates['durationSeconds'] = decision.acceptedDuration;
       if (songUpdates.isNotEmpty) updates[songId] = songUpdates;
     }
     ```
   - Call `_repository.enrichSongs(bandId: bandId, updates: updates)`
   - Build and return `EnrichmentOrchestrationResult` based on RPC results
4. Return result with per-song outcomes for results overlay

**Verification:**

- Call `applyEnrichmentDiff()` with 1 song, accept BPM only → DB updated with new BPM, key/duration unchanged
- Call with 2 songs, accept all fields for song A, reject all for song B → only song A updated
- Call with empty decisions map → returns result with 0 enriched, no DB writes

---

### Task 4: Create Diff Decision Model

**File:** `lib/features/songs/models/enrichment_diff_decision.dart`

**Steps:**

1. Create new file in `lib/features/songs/models/` directory
2. Define `EnrichmentDiffDecision` class:

   ```dart
   class EnrichmentDiffDecision {
     final int? acceptedBpm;
     final String? acceptedKey;
     final int? acceptedDuration;

     const EnrichmentDiffDecision({
       this.acceptedBpm,
       this.acceptedKey,
       this.acceptedDuration,
     });

     bool get hasAnyAcceptedFields =>
       acceptedBpm != null || acceptedKey != null || acceptedDuration != null;
   }
   ```

3. Add `copyWith()` method for immutability:
   ```dart
   EnrichmentDiffDecision copyWith({
     int? acceptedBpm,
     String? acceptedKey,
     int? acceptedDuration,
   }) {
     return EnrichmentDiffDecision(
       acceptedBpm: acceptedBpm ?? this.acceptedBpm,
       acceptedKey: acceptedKey ?? this.acceptedKey,
       acceptedDuration: acceptedDuration ?? this.acceptedDuration,
     );
   }
   ```

**Verification:**

- Create instance with all fields → `hasAnyAcceptedFields` returns true
- Create instance with no fields → `hasAnyAcceptedFields` returns false
- Call `copyWith()` → returns new instance with updated field

---

### Task 5: Create Diff Review UI

**File:** `lib/features/songs/widgets/enrichment_diff_review_sheet.dart`

**Steps:**

1. Create `showEnrichmentDiffReviewSheet()` function returning `Future<Map<String, EnrichmentDiffDecision>?>`
2. Accept parameter: `List<SongEnrichmentDetail> songs`
3. Build modal bottom sheet with:
   - Drag handle (standard pattern)
   - Header: "Review Enrichment Changes" with close button
   - Subtitle: "Accept or reject enriched values for each field. Only accepted changes will be saved."
   - Scrollable list of songs (use `ListView.builder`)
   - Per-song expandable tile (use `ExpansionTile` or custom implementation)
4. Per-song tile shows:
   - Song title/artist (bold)
   - Per-field diff rows (only show fields where enriched value exists and differs from current):
     - **BPM:** `Current: 120 → Enriched: 128` with Accept/Reject toggle (always actionable)
     - **Key:** `Current: C Major → Enriched: D Major` with Accept/Reject toggle (always actionable)
     - **Duration:** Conditional display based on current value:
       - If `currentDuration == 0 or null`: `Current: None → Enriched: 3:52` with Accept/Reject toggle (actionable — RPC will write)
       - If `currentDuration > 0 and differs from enriched`: Show as **informational-only** with icon (e.g., info icon) + text: "Enrichment found: 3:52. Current duration is already set. Clear it first to apply enriched value." **No Accept/Reject toggle** (prevents CASE...ELSE false-success)
   - If no diffs exist for a song, hide the song entirely or show "No changes found"
5. Bulk controls (fixed at bottom):
   - "Accept All" button → sets all **actionable** fields to Accept (skips informational-only Duration rows)
   - "Reject All" button → sets all actionable fields to Reject
6. Footer:
   - "Confirm" button (disabled if all actionable fields rejected) → returns decisions map
   - "Cancel" button → returns null
7. State management: Use `StatefulWidget` with `Map<String, EnrichmentDiffDecision>` to track per-song decisions
8. **Duration guard logic:**
   - When building decisions map for `applyEnrichmentDiff()`, only include `acceptedDuration` if `currentDuration == 0`
   - Never include Duration in decisions if current value is non-zero (even if user somehow interacts with informational row)

**UI Design:**

- Current value: `AppTextStyles.body.copyWith(color: context.colors.textSecondary)`
- Arrow: `Icon(AppIcons.arrowRight, size: 16)`
- Enriched value: `AppTextStyles.body.copyWith(color: context.colors.primary, fontWeight: FontWeight.w600)`
- Accept toggle: Green checkmark icon, primary color when selected
- Reject toggle: Red X icon, error color when selected
- Default state: Accept (all actionable fields start as accepted)
- **Informational-only Duration:** Info icon (blue), text in `context.colors.textSecondary`, no toggle controls

**Verification:**

- Show sheet with 1 song, BPM + Key diffs (both actionable) → both default to Accept
- Show sheet with 1 song, Duration diff where `currentDuration = 0` → Duration shows as actionable with Accept/Reject toggle
- Show sheet with 1 song, Duration diff where `currentDuration = 180` (non-zero) → Duration shows as informational-only, no toggle, explanation text present
- Tap "Accept All" → only actionable fields switch to Accept, informational Duration unchanged
- Tap "Reject All" → only actionable fields switch to Reject
- Tap Confirm with mixed states → returns decisions map with only accepted actionable fields
- Tap Cancel → returns null

---

### Task 6: Wire Show Diffs Mode in Bottom Sheet

**File:** `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`

**Steps:**

1. In `_EnrichmentSelectorBottomSheetState` class, modify the "Enrich Songs" button handler (currently around line 120-140)
2. Before calling orchestrator, check `existingSongBehavior`:
   - If `fillMissingOnly` or `autoReplace` → existing flow (unchanged)
   - If `showDiffs` → new flow:
     a. Call orchestrator with `previewMode: true`
     b. Show progress indicator: "Fetching enrichment data..."
     c. When orchestrator completes, filter `result.details` to only songs with at least one field where `enrichedBpm/Key/Duration != currentBpm/Key/Duration`
     d. If no diffs exist, show snackbar: "No enrichment changes found" and return
     e. Call `showEnrichmentDiffReviewSheet(context, songs: filteredSongs)`
     f. If user confirms (returns non-null decisions), call `orchestrator.applyEnrichmentDiff(bandId: bandId, decisions: decisions)`
     g. Show results overlay with outcomes
3. Handle errors:
   - If preview fetch fails → show error snackbar, do not open diff UI
   - If apply diff fails → show error in results overlay (existing error handling)
   - If user cancels diff review → return to drawer, no writes

**Verification:**

- Settings = Show Diffs → tap "Enrich Songs" → progress indicator appears
- Preview completes → diff review UI opens with correct songs/fields
- User accepts some fields, rejects others → tap Confirm → only accepted fields written
- User taps Cancel in diff UI → returns to drawer, no writes
- Preview fetch fails → error snackbar shown, no diff UI

---

### Task 7: Update Settings Screen

**File:** `lib/features/songs/enrichment_settings_screen.dart`

**Steps:**

1. Line 189: Update subtitle for "Show Diffs" radio tile:
   - **Before:** `'Review changes before updating (coming in Phase 2.3b)'`
   - **After:** `'Review changes before updating existing songs'`
2. Lines 199-217: Delete the entire "Note for Show Diffs" container:
   ```dart
   // DELETE THIS BLOCK:
   if (settings.existingSongBehavior == ExistingSongBehavior.showDiffs)
     Container(
       padding: const EdgeInsets.all(Spacing.space12),
       decoration: BoxDecoration(...),
       child: Row(...),
     ),
   ```
3. No other changes

**Verification:**

- Open Settings → Song Enrichment → verify "Show Diffs" subtitle is updated
- Select "Show Diffs" → verify no fallback notice appears
- Select other options → no change in UI

---

## Verification Plan

### Tier 1 — Pre-deployment (local Flutter testing, no DB changes required)

**PRE-DEPLOY TEST 1: Preview mode does not write to DB**

1. Run app locally: `flutter run -d macos`
2. Set band enrichment settings to "Show Diffs"
3. Open setlist, add 3 songs with missing BPM/Key
4. Open Enrichment Drawer, select BPM + Key, tap "Enrich Songs"
5. Verify progress indicator: "Fetching enrichment data..."
6. **Check DB:** Query `songs` table for the 3 song IDs → verify `updated_at` timestamps unchanged
7. Verify diff review UI opens with 3 songs
8. **Do not confirm** — tap Cancel
9. **Check DB again:** Verify no `updated_at` changes, no new `source_bpm` or `source_musical_key` values

**Expected:** No DB writes during preview fetch, UI shows enriched values for review

---

**PRE-DEPLOY TEST 2: Accept all fields writes correctly**

1. Repeat Test 1 steps 1-7
2. In diff review UI, verify all fields default to Accept (green checkmarks)
3. Tap "Confirm"
4. Verify progress indicator: "Updating songs..."
5. Verify results overlay: "3 songs enriched"
6. **Check DB:** Query `songs` table → verify `source_bpm` and `source_musical_key` updated for all 3 songs, `updated_at` timestamps changed

**Expected:** All accepted fields written to DB, results overlay shows success

---

**PRE-DEPLOY TEST 3: Accept some, reject others**

1. Open setlist with 2 songs: Song A (missing BPM, Key), Song B (missing BPM, Key)
2. Set settings to "Show Diffs", open drawer, select BPM + Key, tap "Enrich Songs"
3. In diff review UI:
   - Song A: Accept BPM, Reject Key
   - Song B: Reject BPM, Accept Key
4. Tap "Confirm"
5. **Check DB:**
   - Song A: `source_bpm` updated, `source_musical_key` unchanged (NULL)
   - Song B: `source_bpm` unchanged (NULL), `source_musical_key` updated

**Expected:** Only accepted fields written per song

---

**PRE-DEPLOY TEST 4: Reject all fields disables Confirm**

1. Open diff review UI with 1 song, 2 fields (BPM + Key)
2. Tap "Reject All"
3. Verify all toggles switch to red X
4. Verify "Confirm" button is disabled (grayed out)
5. Tap "Confirm" (should be non-interactive)
6. Verify no write happens, UI remains open or shows validation message

**Expected:** Cannot confirm when all fields rejected

---

**PRE-DEPLOY TEST 5: Bulk "Accept All" / "Reject All" controls**

1. Open diff review UI with 3 songs, 2-3 fields each
2. Manually set mixed Accept/Reject states across songs
3. Tap "Accept All" → verify all fields across all songs switch to Accept
4. Tap "Reject All" → verify all fields across all songs switch to Reject
5. Tap "Accept All" again → verify all back to Accept
6. Tap "Confirm" → verify all fields written

**Expected:** Bulk controls apply to all fields across all songs

---

**PRE-DEPLOY TEST 6: No diffs found shows feedback**

1. Open setlist with 2 songs that already have BPM + Key (source_bpm, source_musical_key not NULL)
2. Set settings to "Show Diffs", open drawer, select BPM + Key, tap "Enrich Songs"
3. Orchestrator runs in preview mode, fetches enrichment data
4. Verify diff review UI **does not open** if enriched values match current values
5. Verify snackbar: "No enrichment changes found" or similar

**Expected:** If all enriched values == current values, skip diff UI and show feedback

---

**PRE-DEPLOY TEST 7: Enrichment fetch fails in preview mode**

1. Disconnect network or use a test song that triggers API failure (e.g., empty title)
2. Set settings to "Show Diffs", open drawer, select BPM, tap "Enrich Songs"
3. Preview fetch fails for 1 or more songs
4. Verify error snackbar: "Failed to fetch enrichment data" or similar
5. Verify diff review UI **does not open**
6. Verify no DB writes

**Expected:** Graceful error handling, no diff UI shown, no data corruption

---

**PRE-DEPLOY TEST 8: Fill Missing Only mode unchanged**

1. Set settings to "Fill Missing Only"
2. Open drawer, select BPM + Key, tap "Enrich Songs"
3. Verify **no diff review UI** appears (existing behavior)
4. Verify orchestrator writes only to NULL fields (existing behavior)
5. **Check DB:** Verify `source_bpm` updated only for songs with NULL `source_bpm`, existing values preserved

**Expected:** Fill Missing Only mode behavior unchanged by this feature

---

**PRE-DEPLOY TEST 9: Auto-Replace mode unchanged**

1. Set settings to "Auto-Replace"
2. Open drawer, select BPM + Key, tap "Enrich Songs"
3. Verify **no diff review UI** appears (existing behavior)
4. Verify orchestrator overwrites all fields (existing behavior)
5. **Check DB:** Verify `source_bpm` updated for all songs, including songs that already had values

**Expected:** Auto-Replace mode behavior unchanged by this feature

---

**PRE-DEPLOY TEST 10: Duration fill-only semantics (CASE...ELSE false-success guard)**

1. Create test song with:
   - `title`: "Test Song A"
   - `duration_seconds`: 180 (3:00 — non-zero)
   - `source_bpm`: NULL (missing)
2. Set settings to "Show Diffs"
3. Open drawer, select BPM + Duration, tap "Enrich Songs"
4. **Assume enrichment returns:** BPM = 120, Duration = 240 (4:00 — differs from current)
5. In diff review UI, verify:
   - BPM shows as actionable diff: `None → 120` with Accept/Reject toggle (default: Accept)
   - Duration shows as **informational-only**: "Enrichment found: 4:00" with explanation: "Current duration is already set. Clear it first to apply enriched value." **No Accept/Reject toggle.**
6. Tap "Accept All" → verify Duration informational row is **not affected** (no toggle to change)
7. Tap "Confirm"
8. **Check DB:**
   - `source_bpm`: Updated to 120 (Accept worked)
   - `duration_seconds`: **Still 180** (unchanged — informational row correctly prevented write)
   - `updated_at`: Changed (RPC was called for BPM)
9. Verify results overlay shows: "1 song enriched" (BPM only, Duration not counted)
10. **Repeat with song B where `duration_seconds = 0`:**
    - Enrichment returns Duration = 200 (3:20)
    - Diff UI shows Duration as **actionable diff**: `0:00 → 3:20` with Accept/Reject toggle
    - Accept Duration → verify DB `duration_seconds` updated to 200

**Expected:** Duration diffs only writable when current value is 0. Non-zero current duration shows enriched value as informational-only, preventing CASE...ELSE false-success (RPC returns `success: true` but DB unchanged).

---

### Tier 2 — Post-deployment (production validation, no DB changes required)

**POST-DEPLOY TEST 1: Settings screen updated**

1. Open production app → Settings → Song Enrichment
2. Verify "Show Diffs" subtitle: "Review changes before updating existing songs"
3. Select "Show Diffs"
4. Verify **no fallback notice** appears below the radio tiles

**Expected:** Settings screen reflects Phase 2.3b completion

---

**POST-DEPLOY TEST 2: End-to-end Show Diffs flow (production)**

1. Open production app, navigate to a setlist with 3-5 songs missing BPM/Key
2. Set settings to "Show Diffs"
3. Open Enrichment Drawer, select BPM + Key, tap "Enrich Songs"
4. Verify preview progress indicator
5. Verify diff review UI opens with correct songs and fields
6. Accept some fields, reject others
7. Tap "Confirm"
8. Verify results overlay shows correct counts (enriched/not-found/unchanged)
9. Open song details → verify only accepted fields were updated

**Expected:** Full flow works in production with real API data

---

**POST-DEPLOY TEST 3: Cross-platform validation**

Run POST-DEPLOY TEST 2 on:

- iOS (iPhone)
- Android (Pixel or Samsung)
- Web (Chrome incognito)
- macOS (desktop app)

**Expected:** Diff review UI renders correctly and functions identically on all platforms

---

## QA Regression Areas

**Primary feature validation:**

- Show Diffs mode triggers diff review UI (not silent fallback)
- Diff review UI shows correct current vs. enriched values
- Per-field Accept/Reject toggles work correctly
- Bulk "Accept All" / "Reject All" controls work
- Only accepted fields are written to DB
- Results overlay shows correct counts after Show Diffs flow

**Regression checks:**

- Fill Missing Only mode unchanged (no diff UI, only writes to NULL fields)
- Auto-Replace mode unchanged (no diff UI, overwrites all fields)
- Enrichment Drawer field selection (BPM/Duration/Key checkboxes) unchanged
- Enrichment Drawer progress indicator and results overlay unchanged
- Settings screen loads and updates correctly
- Active band switching refreshes settings correctly
- New-song enrichment (Song Lookup "Ask" mode) unchanged

**Edge cases:**

- No diffs found (all enriched values == current values) → shows feedback, no diff UI
- Enrichment fetch fails in preview mode → error handling, no diff UI, no writes
- User rejects all fields → Confirm button disabled, no writes
- User cancels diff review → returns to drawer, no writes
- Songs with partial enrichment (BPM found, Key not found) → only shows fields with diffs

**Platform-specific:**

- iOS: Diff review modal renders correctly, scrolling works, toggles respond to taps
- Android: Same as iOS
- Web: Keyboard navigation works (Tab to cycle fields, Enter to toggle Accept/Reject)
- macOS: Same as iOS

**Performance:**

- Preview fetch for 20 songs completes within 10 seconds (acceptable enrichment API latency)
- Diff review UI with 20 songs scrolls smoothly (no jank or frame drops)
- Apply diff for 20 songs completes within 5 seconds (acceptable RPC batch latency)

---

## Rollout / Migration Strategy

**No migration required:** This is a pure client-side UI feature. The `show-diffs` enum value already exists in the database (shipped with Phase 2.3a). No schema changes, no data backfill, no RPC changes.

**Deployment:**

1. Merge PR after QA APPROVED
2. Deploy web: `./tools/deploy_web.sh`
3. Submit iOS/Android builds to App Store / Play Store (standard release process)
4. macOS: Users pull latest via git or download updated .app

**Rollback plan:**

- If critical bug found: revert commit, redeploy web immediately
- iOS/Android: Submit emergency hotfix build (standard process)
- No database rollback required (no schema changes)

**Feature flag:** Not required. Show Diffs mode is opt-in (user must change settings from default "Fill Missing Only"). If diff UI has a critical bug, users can switch to Fill Missing Only or Auto-Replace as a workaround.

---

## Out of Scope

**Not included in Phase 2.3b:**

- Editing enriched values in diff UI (user can only Accept or Reject, not edit inline) — if user wants different values, they must reject and edit manually after enrichment
- Diff review for new-song enrichment (Song Lookup "Ask" mode already has a review UI, not a diff comparison)
- Per-field enrichment preferences (e.g., "always auto-enrich BPM, always ask for Key") — this would require a new settings dimension
- Enrichment history/analytics (tracking which fields were accepted/rejected over time)
- Tuning enrichment (tuning is not enriched by orchestrator, manual entry only)
- Bulk accept/reject per field across all songs (e.g., "Accept all BPM changes, reject all Key changes") — current bulk controls apply to all fields uniformly
- Undo/redo for diff decisions (user must tap Cancel and start over if they change their mind)
- Side-by-side comparison of source vs. performance values (diff UI shows current source value vs. enriched source value only)

---

## Additional Context

**Design decisions:**

1. **Preview mode prevents double-write:** Orchestrator fetches enrichment data but does not write to DB. This ensures diff review UI always shows pre-write state, preventing race conditions where a song's value changes between preview and confirm.

2. **Default state is Accept:** All fields default to Accept (green checkmark) because the user explicitly opened the Enrichment Drawer and selected fields to enrich. The intent is to enrich, not to skip. Reject is a deliberate opt-out.

3. **Confirm disabled when all rejected:** Prevents accidental no-op writes. If user rejects all fields, they should cancel (explicit action) rather than confirm (which would do nothing).

4. **Filter out unchanged fields:** If enriched value == current value, don't show a diff row. This reduces visual noise and focuses user attention on actual changes.

5. **No inline editing:** User can Accept or Reject, not edit enriched values. This keeps the UI simple and prevents validation complexity (e.g., invalid BPM values). If user wants different values, they reject and edit manually in song details after enrichment.

6. **Reuse existing results overlay:** After diff confirmation, show the same results overlay as fill-missing-only and auto-replace modes. This provides consistent feedback across all enrichment modes.

7. **No new RPC required:** The existing `update_song_metadata` RPC supports field-level writes via optional parameters. `applyEnrichmentDiff()` builds a filtered field map and calls the existing RPC.

8. **No staging SQL tests:** This feature has zero database changes. All Tier 1 and Tier 2 tests are Flutter-based (UI and orchestrator logic).

**Success criteria:**

Phase 2.3b is complete when:

- Show Diffs mode triggers diff review UI (not silent fallback to Fill Missing Only)
- Diff review UI shows correct current vs. enriched values for BPM, Key, Duration
- Per-field Accept/Reject toggles work correctly
- Bulk "Accept All" / "Reject All" controls work
- Only accepted fields are written to DB
- Results overlay shows correct counts after confirmation
- Settings screen subtitle updated, fallback notice removed
- All Tier 1 and Tier 2 tests pass
- No regressions in Fill Missing Only or Auto-Replace modes
- QA approves with APPROVED verdict

---

**End of ARCHITECT_PLAN.md**
