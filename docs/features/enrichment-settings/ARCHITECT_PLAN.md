# ARCHITECT_PLAN — Enrichment Settings (Phase 2.3a)

## Feature Slug

`feature/enrichment-settings`

---

## Problem Summary

BandRoadie's song enrichment system (Phase 2.1 and 2.2) allows users to enrich songs with BPM, Duration, and Musical Key from external APIs. Currently, enrichment is always opt-in via the Enrichment Drawer. There is no way for users to configure default enrichment behavior at the band level.

Phase 2.3a introduces **band-level enrichment settings** to control:

1. **New song behavior** — whether to ask, auto-enrich, or skip enrichment when adding new songs via Song Lookup, Bulk Import, or Manual Entry
2. **Existing song behavior** — whether to fill missing values only, auto-replace all values, or (in future Phase 2.3b) show a diff review UI before updating

This phase implements settings storage, UI, and wires "ask/auto/off" behavior into all three new-song entry points. The existing-song "show-diffs" mode is schema-reserved but not implemented (falls back to "fill-missing-only" with a note).

---

## Root Cause

**Not applicable** — this is a greenfield feature, not a bug.

**Confidence Level:** N/A

---

## Reference Docs Consulted

**Existing patterns:**

- `lib/features/calendar/one_calendar_settings_screen.dart` — band-level settings UI pattern
- `lib/features/calendar/one_calendar_preferences_controller.dart` — Riverpod state management for band preferences
- `supabase/migrations/20260626005216_add_user_calendar_preferences.sql` — user-level preferences table pattern (adapted to band-scoped)
- `supabase/migrations/20260322100000_print_templates.sql` — band-scoped table pattern with CHECK constraints
- `lib/features/songs/services/song_enrichment_orchestrator.dart` — existing orchestrator for batch enrichment (reusable for "auto" mode)
- `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` — existing review UI (reusable for "ask" mode)

**Song entry points:**

- `lib/features/setlists/widgets/song_lookup_overlay.dart` — Entry Point 1: Song Lookup
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` — Entry Point 2: Bulk Import
- `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart` — Entry Point 3: Manual Entry

**No enrichment-specific reference docs exist yet.** This is the first settings layer for the enrichment system.

---

## Existing System Analysis

### Phase 2.1 — Enrichment Selector Bottom Sheet (Existing)

- Located in `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`
- Allows users to select which fields (BPM, Duration, Key) to enrich
- Calls `SongEnrichmentOrchestrator` to process batch enrichments
- Returns `EnrichmentOrchestrationResult` with per-song outcomes
- **Behavior:** Always opt-in — user must open bottom sheet and confirm
- **Current text:** "Only missing values will be filled — existing data is never overwritten." (hardcoded)

### Phase 2.2 — Dual-Value Fields (Existing)

- Songs have `source_*` and `performance_*` columns for BPM, Key, Tuning
- Enrichment writes to `source_*` fields; users can edit `performance_*` fields independently
- Existing-song enrichment currently hardcoded to "fill missing only" behavior (see enrichment_selector_bottom_sheet.dart)

### Song Entry Points (Existing)

**1. Song Lookup** (`song_lookup_overlay.dart`):

- User searches external APIs (Spotify/iTunes) → taps result
- Flow: `_handleExternalSongTap()` → `showSongEnrichmentReviewSheet()` → user reviews BPM/Duration/Key → taps "Add to Setlist" → `widget.onUpsertExternalSong()` → repository
- **Current behavior:** Always shows review sheet (implicit "ask" mode)

**2. Bulk Import** (`bulk_entry_screen.dart`):

- User pastes TSV or types multiple songs → parses to `BulkSongRow` objects → `onBulkSongsSubmitted` callback → `_handleBulkSubmit()` → `repository.bulkAddSongs()`
- **Current behavior:** Creates songs with title/artist only; no enrichment

**3. Manual Entry** (`original_song_screen.dart`):

- User types title + artist → `onSubmit` callback → `_handleOriginalSongsSubmit()` → `_ensureSongRecord()` → `addSongToSetlistEnsureCatalog()`
- **Current behavior:** Creates songs with title/artist only; no enrichment

### Current Gaps

1. **No default enrichment behavior** — users must manually open enrichment drawer after adding songs
2. **Inconsistent new-song handling** — Song Lookup shows review UI, but Bulk/Manual do not
3. **No band-level preferences** — enrichment settings cannot be configured per-band
4. **No differentiation between new and existing songs** — drawer treats all songs the same

---

## Proposed Solution

### Architecture Overview

**Band-level settings table:**

- New `enrichment_settings` table with `band_id` foreign key
- Two enum columns: `new_song_behavior` and `existing_song_behavior`
- RLS policies: band members can SELECT, admins/members can UPDATE
- RPC functions: `get_or_create_enrichment_settings()`, `update_enrichment_settings()`

**Settings screen:**

- New `EnrichmentSettingsScreen` following `OneCalendarSettingsScreen` pattern
- Accessed via Settings → Song Enrichment
- Radio group for "New Song Behavior" (Ask / Auto / Off)
- Radio group for "Existing Song Behavior" (Fill Missing Only / Auto-Replace / Show Diffs\*)
  - \*Show Diffs is schema-reserved; selecting it falls back to Fill Missing Only with a note

**Riverpod state management:**

- `enrichmentSettingsProvider` (AsyncNotifierProvider) — fetches settings for active band
- `EnrichmentSettingsController` — handles RPC calls and state updates
- Auto-refreshes when `activeBandProvider` changes

**Integration into entry points:**

**Song Lookup:**

- After tapping external result, check `new_song_behavior`:
  - **Ask:** Show `showSongEnrichmentReviewSheet()` (current behavior)
  - **Auto:** Call enrichment service inline, write to song, skip review UI
  - **Off:** Skip enrichment, create song with title/artist/duration only

**Bulk Import:**

- After parsing TSV, check `new_song_behavior`:
  - **Ask:** For each new song, show inline modal (simplified review UI) before adding
  - **Auto:** For each new song, call enrichment service inline, write to song
  - **Off:** Create songs with title/artist only (current behavior)

**Manual Entry:**

- After user submits title/artist, check `new_song_behavior`:
  - **Ask:** Show inline modal (simplified review UI) before adding
  - **Auto:** Call enrichment service inline, write to song
  - **Off:** Create song with title/artist only (current behavior)

**Existing-song enrichment (Phase 2.1 drawer):**

- Check `existing_song_behavior`:
  - **Fill Missing Only:** Only update `source_*` fields that are NULL (existing behavior with checkbox checked)
  - **Auto-Replace:** Update all `source_*` fields regardless of current value (existing behavior with checkbox unchecked)
  - **Show Diffs:** _(Phase 2.3b — not implemented)_ If selected, fall back to Fill Missing Only and log a note

**Reuse existing infrastructure:**

- `SongEnrichmentOrchestrator.enrichSongs()` for "auto" mode batch enrichment
- `SongEnrichmentService.lookup()` for single-song inline enrichment
- `showSongEnrichmentReviewSheet()` for "ask" mode review UI
- Existing RPC functions: `update_song_metadata`, `clear_song_metadata` for RLS bypass

---

## Database Impact

### Migration: `20260810000000_enrichment_settings.sql`

**New table:**

```sql
CREATE TABLE enrichment_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id UUID NOT NULL REFERENCES bands(id) ON DELETE CASCADE,
  new_song_behavior TEXT NOT NULL DEFAULT 'ask'
    CHECK (new_song_behavior IN ('ask', 'auto', 'off')),
  existing_song_behavior TEXT NOT NULL DEFAULT 'fill-missing-only'
    CHECK (existing_song_behavior IN ('fill-missing-only', 'auto-replace', 'show-diffs')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(band_id)
);

CREATE INDEX idx_enrichment_settings_band_id ON enrichment_settings(band_id);

ALTER TABLE enrichment_settings ENABLE ROW LEVEL SECURITY;

-- SELECT: any active band member
CREATE POLICY "Band members can view enrichment settings" ON enrichment_settings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM band_members bm
      WHERE bm.band_id = enrichment_settings.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- INSERT: any active band member (needed for get_or_create_enrichment_settings RPC)
CREATE POLICY "Band members can insert enrichment settings" ON enrichment_settings
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM band_members bm
      WHERE bm.band_id = enrichment_settings.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- UPDATE: admins and members only (contributors cannot change settings)
CREATE POLICY "Admins and members can update enrichment settings" ON enrichment_settings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM band_members bm
      WHERE bm.band_id = enrichment_settings.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM band_members bm
      WHERE bm.band_id = enrichment_settings.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- No DELETE policy — settings persist even if empty
```

**RPC functions:**

```sql
-- Get or create enrichment settings (returns existing or creates default)
CREATE OR REPLACE FUNCTION get_or_create_enrichment_settings(p_band_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_settings JSONB;
BEGIN
  -- Try to get existing settings
  SELECT to_jsonb(enrichment_settings.*) INTO v_settings
  FROM enrichment_settings
  WHERE band_id = p_band_id;

  -- If no settings exist, create default
  IF v_settings IS NULL THEN
    INSERT INTO enrichment_settings (band_id)
    VALUES (p_band_id)
    RETURNING to_jsonb(enrichment_settings.*) INTO v_settings;
  END IF;

  RETURN v_settings;
END;
$$;

-- Update enrichment settings
CREATE OR REPLACE FUNCTION update_enrichment_settings(
  p_band_id UUID,
  p_new_song_behavior TEXT,
  p_existing_song_behavior TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_settings JSONB;
BEGIN
  -- Validate enum values
  IF p_new_song_behavior NOT IN ('ask', 'auto', 'off') THEN
    RAISE EXCEPTION 'Invalid new_song_behavior. Must be ask, auto, or off.';
  END IF;

  IF p_existing_song_behavior NOT IN ('fill-missing-only', 'auto-replace', 'show-diffs') THEN
    RAISE EXCEPTION 'Invalid existing_song_behavior. Must be fill-missing-only, auto-replace, or show-diffs.';
  END IF;

  -- Ensure settings exist
  PERFORM get_or_create_enrichment_settings(p_band_id);

  -- Update settings
  UPDATE enrichment_settings
  SET
    new_song_behavior = p_new_song_behavior,
    existing_song_behavior = p_existing_song_behavior,
    updated_at = now()
  WHERE band_id = p_band_id
  RETURNING to_jsonb(enrichment_settings.*) INTO v_settings;

  RETURN v_settings;
END;
$$;
```

**Trigger:**

```sql
CREATE TRIGGER update_enrichment_settings_updated_at
  BEFORE UPDATE ON enrichment_settings
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
```

**No RLS policy self-referencing** — policies check `band_members` table, not `enrichment_settings`, so no recursion risk.

**No impact on existing tables** — `songs`, `setlist_songs`, `setlists` tables unchanged.

---

## Flutter Architecture Changes

### New Files

**1. `lib/features/songs/models/enrichment_settings.dart`**

```dart
class EnrichmentSettings {
  final String id;
  final String bandId;
  final NewSongBehavior newSongBehavior;
  final ExistingSongBehavior existingSongBehavior;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EnrichmentSettings({
    required this.id,
    required this.bandId,
    required this.newSongBehavior,
    required this.existingSongBehavior,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EnrichmentSettings.fromSupabase(Map<String, dynamic> json) {
    return EnrichmentSettings(
      id: json['id'],
      bandId: json['band_id'],
      newSongBehavior: _parseNewSongBehavior(json['new_song_behavior']),
      existingSongBehavior: _parseExistingSongBehavior(json['existing_song_behavior']),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  static NewSongBehavior _parseNewSongBehavior(String value) {
    switch (value) {
      case 'ask': return NewSongBehavior.ask;
      case 'auto': return NewSongBehavior.auto;
      case 'off': return NewSongBehavior.off;
      default: return NewSongBehavior.ask; // fallback
    }
  }

  static ExistingSongBehavior _parseExistingSongBehavior(String value) {
    switch (value) {
      case 'fill-missing-only': return ExistingSongBehavior.fillMissingOnly;
      case 'auto-replace': return ExistingSongBehavior.autoReplace;
      case 'show-diffs': return ExistingSongBehavior.showDiffs;
      default: return ExistingSongBehavior.fillMissingOnly; // fallback
    }
  }
}

enum NewSongBehavior {
  ask,   // Show review modal before adding
  auto,  // Auto-enrich in background, no modal
  off,   // No enrichment, manual entry only
}

enum ExistingSongBehavior {
  fillMissingOnly, // Only update NULL source_* fields
  autoReplace,     // Update all source_* fields regardless of current value
  showDiffs,       // (Phase 2.3b) Show diff review UI before updating
}
```

**2. `lib/features/songs/enrichment_settings_repository.dart`**

```dart
class EnrichmentSettingsRepository {
  final SupabaseClient _supabase;

  EnrichmentSettingsRepository(this._supabase);

  Future<EnrichmentSettings> getOrCreateSettings(String bandId) async {
    final response = await _supabase.rpc(
      'get_or_create_enrichment_settings',
      params: {'p_band_id': bandId},
    );
    return EnrichmentSettings.fromSupabase(response as Map<String, dynamic>);
  }

  Future<EnrichmentSettings> updateSettings({
    required String bandId,
    required NewSongBehavior newSongBehavior,
    required ExistingSongBehavior existingSongBehavior,
  }) async {
    final response = await _supabase.rpc(
      'update_enrichment_settings',
      params: {
        'p_band_id': bandId,
        'p_new_song_behavior': _serializeNewSongBehavior(newSongBehavior),
        'p_existing_song_behavior': _serializeExistingSongBehavior(existingSongBehavior),
      },
    );
    return EnrichmentSettings.fromSupabase(response as Map<String, dynamic>);
  }

  String _serializeNewSongBehavior(NewSongBehavior behavior) {
    switch (behavior) {
      case NewSongBehavior.ask: return 'ask';
      case NewSongBehavior.auto: return 'auto';
      case NewSongBehavior.off: return 'off';
    }
  }

  String _serializeExistingSongBehavior(ExistingSongBehavior behavior) {
    switch (behavior) {
      case ExistingSongBehavior.fillMissingOnly: return 'fill-missing-only';
      case ExistingSongBehavior.autoReplace: return 'auto-replace';
      case ExistingSongBehavior.showDiffs: return 'show-diffs';
    }
  }
}

final enrichmentSettingsRepositoryProvider = Provider<EnrichmentSettingsRepository>((ref) {
  return EnrichmentSettingsRepository(Supabase.instance.client);
});
```

**3. `lib/features/songs/enrichment_settings_controller.dart`**

```dart
class EnrichmentSettingsController extends AsyncNotifier<EnrichmentSettings> {
  @override
  Future<EnrichmentSettings> build() async {
    final activeBand = ref.watch(activeBandProvider);
    final bandId = activeBand.activeBand?.id;

    if (bandId == null) {
      throw Exception('No active band');
    }

    final repository = ref.read(enrichmentSettingsRepositoryProvider);
    return await repository.getOrCreateSettings(bandId);
  }

  Future<void> updateSettings({
    required NewSongBehavior newSongBehavior,
    required ExistingSongBehavior existingSongBehavior,
  }) async {
    final activeBand = ref.read(activeBandProvider);
    final bandId = activeBand.activeBand?.id;

    if (bandId == null) return;

    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final repository = ref.read(enrichmentSettingsRepositoryProvider);
      return await repository.updateSettings(
        bandId: bandId,
        newSongBehavior: newSongBehavior,
        existingSongBehavior: existingSongBehavior,
      );
    });
  }
}

final enrichmentSettingsProvider = AsyncNotifierProvider<EnrichmentSettingsController, EnrichmentSettings>(
  EnrichmentSettingsController.new,
);
```

**4. `lib/features/songs/enrichment_settings_screen.dart`**

- Follows `OneCalendarSettingsScreen` pattern
- AppScaffold + AppAppBar with back button
- Two radio groups: "New Song Behavior" and "Existing Song Behavior"
- Error/loading states handled with AsyncValue.when()
- Calls `enrichmentSettingsProvider.notifier.updateSettings()` on radio change
- Shows snackbar on success/error

**5. `lib/features/songs/services/inline_song_enrichment_service.dart`**

- New helper service for single-song enrichment (used by "auto" mode)
- Wraps `SongEnrichmentService.lookup()` and applies result to song via RPC
- Returns enriched song metadata (BPM, Duration, Key)
- Used by Song Lookup, Bulk Import, and Manual Entry for inline enrichment

### Modified Files

**1. `lib/features/setlists/widgets/song_lookup_overlay.dart`**

- Add: Read `enrichmentSettingsProvider` for active band
- Modify: `_handleExternalSongTap()` to check `newSongBehavior`:
  - **Ask:** Call `showSongEnrichmentReviewSheet()` (current behavior)
  - **Auto:** Call `InlineSongEnrichmentService.enrichSong()`, then `widget.onUpsertExternalSong()` with enriched metadata
  - **Off:** Call `widget.onUpsertExternalSong()` with title/artist/duration only (skip BPM/Key lookup)

**2. `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`**

- Add: Accept `EnrichmentSettings` parameter via callback
- Add: For each `BulkSongRow` where song doesn't exist in Catalog:
  - **Ask:** Show `showEnrichmentConfirmDialog()` (new inline modal) before adding
  - **Auto:** Call `InlineSongEnrichmentService.enrichSong()` before `repository.bulkAddSongs()`
  - **Off:** Add song with title/artist only (current behavior)

**3. `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`**

- Add: Accept `EnrichmentSettings` parameter via callback
- Add: For each submitted song:
  - **Ask:** Show `showEnrichmentConfirmDialog()` (new inline modal) before `_ensureSongRecord()`
  - **Auto:** Call `InlineSongEnrichmentService.enrichSong()` before `_ensureSongRecord()`
  - **Off:** Create song with title/artist only (current behavior)

**4. `lib/features/setlists/setlist_detail_screen.dart`**

- Pass `enrichmentSettingsProvider` to `BulkEntryScreen` and `OriginalSongScreen` via callbacks
- Update `_handleBulkSubmit()` and `_handleOriginalSongsSubmit()` to use enrichment settings

**5. `lib/features/setlists/new_setlist_screen.dart`**

- Pass `enrichmentSettingsProvider` to `BulkEntryScreen` and `OriginalSongScreen` via callbacks
- Update `_handleBulkSubmit()` and `_handleOriginalSongsSubmit()` to use enrichment settings

**6. `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`**

- Add: Read `enrichmentSettingsProvider` for active band
- Remove: Hardcoded subtitle text "Only missing values will be filled — existing data is never overwritten."
- Add: Dynamic subtitle text that reflects current `existingSongBehavior`:
  - **Fill Missing Only:** "Only missing values will be filled — existing data is never overwritten."
  - **Auto-Replace:** "All selected fields will be updated, including existing values."
  - **Show Diffs:** "Only missing values will be filled (diff review coming soon)."
- Orchestrator call passes `overwriteExisting` flag based on `existingSongBehavior` (fillMissingOnly = false, autoReplace = true)

**7. `lib/features/settings/settings_screen.dart`**

- Add: "Song Enrichment" settings item (below "One Calendar" or "Notifications")
- Navigation: Push `EnrichmentSettingsScreen`

### System Integration

**Active Band Switching:**

- `enrichmentSettingsProvider` watches `activeBandProvider`
- When active band changes, `build()` is called and settings are refetched
- Pattern matches `oneCalendarPreferencesProvider`

**Repository Pattern:**

- `EnrichmentSettingsRepository` handles all Supabase RPC calls
- No direct table access from client (RLS enforced)
- Repository injected via Riverpod provider

**Error Handling:**

- RPC validation errors (invalid enum) caught and displayed via snackbar
- Missing active band → throw exception → AsyncError state in UI
- Network errors → AsyncError state → Retry button in UI

---

## Files to Create

| File                                                              | Purpose                                            |
| ----------------------------------------------------------------- | -------------------------------------------------- |
| `supabase/migrations/20260810000000_enrichment_settings.sql`      | Table, RLS, RPC, trigger                           |
| `lib/features/songs/models/enrichment_settings.dart`              | Model + enums                                      |
| `lib/features/songs/enrichment_settings_repository.dart`          | Supabase RPC wrapper                               |
| `lib/features/songs/enrichment_settings_controller.dart`          | Riverpod state management                          |
| `lib/features/songs/enrichment_settings_screen.dart`              | Settings UI                                        |
| `lib/features/songs/services/inline_song_enrichment_service.dart` | Single-song enrichment helper                      |
| `lib/features/songs/widgets/enrichment_confirm_dialog.dart`       | Inline modal for "ask" mode (simplified review UI) |

---

## Files to Modify

| File                                                                     | What Changes                                                                                                                                                                                                                                            |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_lookup_overlay.dart`                 | Check `newSongBehavior` in `_handleExternalSongTap()`, branch to ask/auto/off                                                                                                                                                                           |
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`    | Add enrichment settings parameter, check `newSongBehavior` before adding each song                                                                                                                                                                      |
| `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart` | Add enrichment settings parameter, check `newSongBehavior` before creating songs                                                                                                                                                                        |
| `lib/features/setlists/setlist_detail_screen.dart`                       | Pass enrichment settings to Bulk/Original screens, update submit handlers                                                                                                                                                                               |
| `lib/features/setlists/new_setlist_screen.dart`                          | Pass enrichment settings to Bulk/Original screens, update submit handlers                                                                                                                                                                               |
| `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`       | Read `existingSongBehavior`, update subtitle text, add `overwriteExisting` to result                                                                                                                                                                    |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`          | Add optional `overwriteExisting` parameter (default `false`) to `enrichSongs()`. Change filter logic: `needsBpm = enrichBpm && (overwriteExisting \|\| song.sourceBpm == null)` (same for Key). Duration uses `durationSeconds == 0` check (unchanged). |
| `lib/features/settings/settings_screen.dart`                             | Add "Song Enrichment" navigation item                                                                                                                                                                                                                   |

---

## Files Off-Limits

| File                                                   | Reason                                                                    |
| ------------------------------------------------------ | ------------------------------------------------------------------------- |
| `lib/main.dart`                                        | Initialization order must not change                                      |
| `lib/features/songs/song_enrichment_service.dart`      | Existing lookup service is correct; reuse as-is                           |
| `lib/features/songs/external_song_lookup_service.dart` | External API wrapper unchanged                                            |
| `lib/features/setlists/setlist_repository.dart`        | Repository methods unchanged (enrichment happens before repository calls) |
| `lib/features/setlists/models/song.dart`               | Model unchanged (dual-value fields already exist from Phase 2.2)          |
| All test files                                         | No new tests required (coverage remains minimal per project conventions)  |

---

## System Impact Map

| System                                 | Impact                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                             |
| Rehearsals                             | unaffected                                                             |
| Setlists / Catalog                     | **affected** (new songs may have enriched metadata based on settings)  |
| Members / RBAC                         | **affected** (admins/members can change settings, contributors cannot) |
| Auth / Session                         | unaffected                                                             |
| Routing                                | **affected** (new route: Settings → Song Enrichment)                   |
| Notifications                          | unaffected                                                             |
| Platform (iOS / Android / Web / macOS) | unaffected (all platforms support new UI)                              |

---

## Regression Risk

**Level:** `LOW-MEDIUM`

**Rationale:**

- New table, new screen, new providers — isolated from existing code ✅
- Entry point changes are additive (check settings, branch to new behavior or fall back to current) ✅
- **Orchestrator change is NOT purely additive** — modifies core enrichment filter logic ⚠️
  - **Mitigation:** Optional parameter with `false` default preserves all existing call sites (3 callers)
  - **Blast radius:** Only affects enrichment when `overwriteExisting: true` is explicitly passed
  - **Risk:** Logic error in new condition could break Auto-Replace mode; Fill Missing mode protected by default
- No changes to repository layer, song model, or database schema for songs/setlists ✅
- RBAC policies follow existing pattern (band_members role check) ✅
- RLS policies do not reference `enrichment_settings` recursively (no infinite recursion risk) ✅
- Only 3 screens + 1 orchestrator require modification (Song Lookup, Bulk Entry, Original Song, Orchestrator)
- Settings screen is optional — users can ignore it and continue with current behavior ✅

**Failure modes:**

- **Missing settings row:** RPC `get_or_create_enrichment_settings()` creates default on first access → no crash
- **Invalid enum value:** Database CHECK constraint rejects invalid values → error caught by RPC and returned as exception
- **Active band changes mid-enrichment:** Provider auto-refreshes settings for new band → no stale data
- **Contributor attempts to change settings:** RLS UPDATE policy blocks → Supabase returns error → caught by repository and displayed as snackbar

---

## Engineer Task Breakdown

### Task 1: Create Database Migration

**File:** `supabase/migrations/20260810000000_enrichment_settings.sql`

**Steps:**

1. Create `enrichment_settings` table with `band_id`, `new_song_behavior`, `existing_song_behavior` columns
2. Add CHECK constraints for enum validation
3. Add UNIQUE constraint on `band_id`
4. Enable RLS
5. Create SELECT policy (any active band member)
6. Create UPDATE policy (admins/members only)
7. Create RPC: `get_or_create_enrichment_settings(p_band_id)`
8. Create RPC: `update_enrichment_settings(p_band_id, p_new_song_behavior, p_existing_song_behavior)`
9. Create trigger: `update_enrichment_settings_updated_at`
10. Apply migration locally: `cd supabase && supabase db reset`

**Verification:**

- Query table: `SELECT * FROM enrichment_settings;` (should be empty)
- Call RPC: `SELECT get_or_create_enrichment_settings('<test-band-id>');` (should return default settings)
- Verify RLS: Non-member cannot SELECT or UPDATE

---

### Task 2: Create Model and Enums

**File:** `lib/features/songs/models/enrichment_settings.dart`

**Steps:**

1. Define `EnrichmentSettings` class with all fields
2. Define `NewSongBehavior` enum (ask, auto, off)
3. Define `ExistingSongBehavior` enum (fillMissingOnly, autoReplace, showDiffs)
4. Implement `fromSupabase()` factory with enum parsing
5. Add enum parsing helper methods `_parseNewSongBehavior()` and `_parseExistingSongBehavior()`
6. Add fallback to `ask` and `fillMissingOnly` for invalid enum values

**Verification:**

- Unit test: Parse valid JSON → correct enum values
- Unit test: Parse invalid enum string → fallback to default
- Unit test: Missing fields → throw exception

---

### Task 3: Create Repository

**File:** `lib/features/songs/enrichment_settings_repository.dart`

**Steps:**

1. Create `EnrichmentSettingsRepository` class with `SupabaseClient` dependency
2. Implement `getOrCreateSettings(String bandId)` → calls `get_or_create_enrichment_settings` RPC
3. Implement `updateSettings()` → calls `update_enrichment_settings` RPC
4. Add enum serialization methods `_serializeNewSongBehavior()` and `_serializeExistingSongBehavior()`
5. Create `enrichmentSettingsRepositoryProvider` Riverpod provider
6. Add error handling: catch Supabase errors, rethrow with context

**Verification:**

- Call `getOrCreateSettings()` with test band ID → returns default settings
- Call `updateSettings()` → returns updated settings
- Call with invalid band ID → throws exception

---

### Task 4: Create Controller

**File:** `lib/features/songs/enrichment_settings_controller.dart`

**Steps:**

1. Create `EnrichmentSettingsController` extending `AsyncNotifier<EnrichmentSettings>`
2. Implement `build()` → watches `activeBandProvider`, calls repository
3. Implement `updateSettings()` → sets AsyncLoading, calls repository, updates state
4. Create `enrichmentSettingsProvider` (AsyncNotifierProvider)
5. Add `ref.watch(activeBandProvider)` to auto-refresh on band change

**Verification:**

- Watch provider in test widget → state is AsyncData with settings
- Call `updateSettings()` → state becomes AsyncLoading, then AsyncData with new settings
- Switch active band → `build()` is called, new settings fetched

---

### Task 5: Create Settings Screen

**File:** `lib/features/songs/enrichment_settings_screen.dart`

**Steps:**

1. Create `EnrichmentSettingsScreen` extending `ConsumerWidget`
2. Add AppScaffold + AppAppBar with back button
3. Watch `enrichmentSettingsProvider` with `.when()` for loading/error/data states
4. Build radio group for "New Song Behavior" (Ask / Auto / Off)
5. Build radio group for "Existing Song Behavior" (Fill Missing Only / Auto-Replace / Show Diffs\*)
6. Add note for Show Diffs: "Diff review UI coming in Phase 2.3b — currently falls back to Fill Missing Only"
7. Add explainer text at top: "Configure how BandRoadie enriches songs with BPM, Duration, and Musical Key"
8. On radio change, call `ref.read(enrichmentSettingsProvider.notifier).updateSettings()`
9. Show snackbar on success: "Settings updated"
10. Show error snackbar on failure: "Failed to update settings"

**Verification:**

- Open screen → settings load, radios reflect current values
- Change radio → settings update, snackbar appears
- Switch bands → settings reload for new band
- Trigger error (network off) → error state shown with Retry button

---

### Task 6: Create Inline Enrichment Service

**File:** `lib/features/songs/services/inline_song_enrichment_service.dart`

**Steps:**

1. Create `InlineSongEnrichmentService` class
2. Accept `SongEnrichmentService` and `SetlistRepository` dependencies
3. Implement `enrichSong({title, artist, duration})` → calls `SongEnrichmentService.lookup()`
4. Return enriched metadata: `{bpm, duration, key}` or `null` for each field if not found
5. Add logging for not-found cases: `debugPrint('[InlineEnrichment] BPM not found for "$title"')`
6. Handle errors gracefully: return null for failed lookups (don't block song creation)

**Verification:**

- Call `enrichSong()` with known song (e.g., "Wonderwall") → returns BPM, Duration, Key
- Call with unknown song → returns null for missing fields
- Call with invalid inputs → returns null, logs error

---

### Task 7: Create Enrichment Confirm Dialog

**File:** `lib/features/songs/widgets/enrichment_confirm_dialog.dart`

**Steps:**

1. Create `showEnrichmentConfirmDialog()` function → returns `Future<bool?>`
2. Build simple dialog with song title/artist, enrichment fields (BPM, Duration, Key)
3. Show "Loading..." state while enrichment is in progress
4. Show enriched values when loaded (or "Not found" for missing fields)
5. Add two buttons: "Skip Enrichment" (returns `false`) and "Add with Enrichment" (returns `true`)
6. Use for "ask" mode in Bulk Import and Manual Entry

**Verification:**

- Show dialog → enrichment runs, values populate
- Tap "Add with Enrichment" → dialog closes, returns `true`
- Tap "Skip Enrichment" → dialog closes, returns `false`
- Enrichment fails → shows "Not found", still allows adding song

---

### Task 8: Modify Song Lookup Overlay

**File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`

**Steps:**

1. Add `ref.watch(enrichmentSettingsProvider)` at top of `_SongLookupOverlayState`
2. Modify `_handleExternalSongTap()`:
   - Read `newSongBehavior` from settings (handle AsyncLoading/AsyncError → fall back to "ask")
   - **Ask:** Call `showSongEnrichmentReviewSheet()` (current behavior) — no change
   - **Auto:** Call `InlineSongEnrichmentService.enrichSong()`, then `widget.onUpsertExternalSong()` with enriched metadata
   - **Off:** Call `widget.onUpsertExternalSong()` with `{title, artist, duration}` only (skip BPM/Key lookup)
3. Add loading indicator during "auto" enrichment (spinner on song tile)
4. Add error handling: if "auto" enrichment fails, fall back to "off" behavior (add song without enrichment)

**Verification:**

- Settings = Ask → tap external song → review sheet opens (current behavior)
- Settings = Auto → tap external song → spinner appears briefly, song added with enriched metadata, no review sheet
- Settings = Off → tap external song → song added immediately with title/artist/duration only
- Settings provider error → fall back to Ask behavior

---

### Task 9: Modify Bulk Entry Screen

**File:** `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

**Steps:**

1. Add `EnrichmentSettings? enrichmentSettings` parameter to `onBulkSongsSubmitted` callback
2. In `_handleSubmit()`, for each `BulkSongRow`:
   - If song exists in Catalog → skip enrichment (existing-song logic handled separately in drawer)
   - If song is new:
     - **Ask:** Show `showEnrichmentConfirmDialog()` → if user confirms, enrich and add; if skips, add without enrichment
     - **Auto:** Call `InlineSongEnrichmentService.enrichSong()` → add with enriched metadata
     - **Off:** Add song with title/artist only (current behavior)
3. Add progress indicator: "Enriching 3 of 10 songs..." during "auto" mode
4. Handle errors: if enrichment fails for one song, log warning and continue with next song

**Verification:**

- Settings = Ask → submit 5 songs → 5 dialogs appear sequentially
- Settings = Auto → submit 5 songs → progress indicator shows, all songs added with enrichment
- Settings = Off → submit 5 songs → all songs added immediately with title/artist only
- One enrichment fails → other songs still process correctly

---

### Task 10: Modify Original Song Screen

**File:** `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`

**Steps:**

1. Add `EnrichmentSettings? enrichmentSettings` parameter to `onSubmit` callback
2. In `_handleSubmit()`, for each submitted song:
   - **Ask:** Show `showEnrichmentConfirmDialog()` → if user confirms, enrich and add; if skips, add without enrichment
   - **Auto:** Call `InlineSongEnrichmentService.enrichSong()` → add with enriched metadata
   - **Off:** Create song with title/artist only (current behavior)
3. Update progress indicator: show "Enriching..." during "auto" mode
4. Handle errors: if enrichment fails, fall back to "off" behavior

**Verification:**

- Settings = Ask → submit 1 song → dialog appears
- Settings = Auto → submit 1 song → brief spinner, song added with enrichment
- Settings = Off → submit 1 song → song added immediately
- Enrichment fails → song still added without enrichment

---

### Task 11: Update Setlist Detail Screen

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**Steps:**

1. Watch `enrichmentSettingsProvider` at top of `_SetlistDetailScreenState`
2. Pass `enrichmentSettings` to `BulkEntryScreen` via callback
3. Pass `enrichmentSettings` to `OriginalSongScreen` via callback
4. Update `_handleBulkSubmit()` to accept enrichment settings and pass to repository
5. Update `_handleOriginalSongsSubmit()` to accept enrichment settings and pass to `_ensureSongRecord()`

**Verification:**

- Open setlist → tap Bulk Entry → enrichment settings are passed correctly
- Open setlist → tap Original Song → enrichment settings are passed correctly
- Switch bands → new settings are fetched and passed

---

### Task 12: Update New Setlist Screen

**File:** `lib/features/setlists/new_setlist_screen.dart`

**Steps:**

1. Watch `enrichmentSettingsProvider` at top of `_NewSetlistScreenState`
2. Pass `enrichmentSettings` to `BulkEntryScreen` via callback
3. Pass `enrichmentSettings` to `OriginalSongScreen` via callback
4. Update `_handleBulkSubmit()` to accept enrichment settings and pass to repository
5. Update `_handleOriginalSongsSubmit()` to accept enrichment settings and pass to `_ensureSongRecord()`

**Verification:**

- Create new setlist → tap Bulk Entry → enrichment settings are passed correctly
- Create new setlist → tap Original Song → enrichment settings are passed correctly

---

### Task 13: Update Enrichment Selector Bottom Sheet

**File:** `lib/features/songs/widgets/enrichment_selector_bottom_sheet.dart`

**Steps:**

1. Convert from `StatefulWidget` to `ConsumerStatefulWidget` (change parent class and add `WidgetRef ref` parameter to build)
2. Watch `enrichmentSettingsProvider` in `build()` method (handle AsyncLoading/AsyncError → fall back to "fill-missing-only")
3. Read `existingSongBehavior` from settings
4. Replace hardcoded subtitle text (line ~107: "Only missing values will be filled — existing data is never overwritten.") with dynamic text based on `existingSongBehavior`:
   - **Fill Missing Only:** "Only missing values will be filled — existing data is never overwritten."
   - **Auto-Replace:** "All selected fields will be updated, including existing values."
   - **Show Diffs:** "Only missing values will be filled (diff review coming soon)."
5. Update `EnrichmentSelectorResult` class to include `overwriteExisting` boolean field
6. When user taps "Enrich Songs", set `overwriteExisting` based on `existingSongBehavior`:
   - **Fill Missing Only:** `false`
   - **Auto-Replace:** `true`
   - **Show Diffs:** `false` (falls back to Fill Missing Only)
7. Caller (setlist_detail_screen.dart) reads this flag from result and passes to `SongEnrichmentOrchestrator.enrichSongs(overwriteExisting: ...)`

**Note:** This change makes the enrichment behavior configurable at the band level. The bottom sheet no longer has a per-run toggle — the band's setting governs behavior silently. Users who want different behavior for a specific enrichment run must change the band setting first.

**Verification:**

- Settings = Fill Missing Only → subtitle shows "Only missing values will be filled...", orchestrator called with `overwriteExisting: false`
- Settings = Auto-Replace → subtitle shows "All selected fields will be updated...", orchestrator called with `overwriteExisting: true`
- Settings = Show Diffs → subtitle shows "Only missing values... (diff review coming soon)", orchestrator called with `overwriteExisting: false`
- Run enrichment with existing songs → Fill Missing mode skips non-null source*\* fields, Auto-Replace updates all source*\* fields

---

### Task 13.5: Update Song Enrichment Orchestrator

**File:** `lib/features/songs/services/song_enrichment_orchestrator.dart`

**Steps:**

1. Add optional `overwriteExisting` parameter to `enrichSongs()` signature (default `false` to preserve existing behavior for all current callers)
2. Update filter logic at lines 108-114:
   - **Before:** `needsBpm = enrichBpm && song.sourceBpm == null;`
   - **After:** `needsBpm = enrichBpm && (overwriteExisting || song.sourceBpm == null);`
   - **Before:** `needsKey = enrichKey && song.sourceMusicalKey == null;`
   - **After:** `needsKey = enrichKey && (overwriteExisting || song.sourceMusicalKey == null);`
   - **Duration:** Keep existing `needsDuration = enrichDuration && song.durationSeconds == 0;` (unchanged — Duration uses 0-check not null-check, not part of dual-value source/performance model, does not participate in overwrite semantics)
3. Update filter logic at lines 130-133 (inside loop) with identical changes
4. **No other changes** — this is the only modification to this file

**Design Note:** Duration is excluded from overwrite semantics because:

- Duration uses `durationSeconds == 0` (not nullable), not the dual-value source*\*/performance*\* pattern
- Duration is a simple scalar field, not enriched metadata
- Overwriting Duration = 0 with enriched values is already the correct behavior (0 = missing)

**Verification:**

- Call `enrichSongs(overwriteExisting: false)` on song with `source_bpm = 120` → BPM not enriched (existing behavior preserved)
- Call `enrichSongs(overwriteExisting: true)` on song with `source_bpm = 120` → BPM enriched and overwritten
- Call `enrichSongs(overwriteExisting: false)` on song with `source_bpm = null` → BPM enriched (fill missing)
- Call `enrichSongs(overwriteExisting: true)` on song with `source_bpm = null` → BPM enriched (fill missing)
- Existing call sites (setlist_detail_screen.dart lines 1510/1610, song_details_bottom_sheet.dart line 870) continue working without changes (default parameter)
- Duration enrichment unchanged for both modes (0-check logic still applies)

---

### Task 14: Add Settings Navigation

**File:** `lib/features/settings/settings_screen.dart`

**Steps:**

1. Add "Song Enrichment" list item (below "One Calendar" or "Notifications")
2. Add navigation: `Navigator.push(EnrichmentSettingsScreen())`
3. Add icon: `AppIcons.music` or `AppIcons.sparkles`
4. Add description: "Configure how songs are enriched with BPM, Duration, and Key"

**Verification:**

- Open Settings → "Song Enrichment" item appears
- Tap item → navigates to `EnrichmentSettingsScreen`

---

## Verification Plan

### Tier 1 — Pre-deployment (run locally after `supabase db reset`)

**PRE-DEPLOY TEST 1: Verify table exists**

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'enrichment_settings'
ORDER BY ordinal_position;
```

**Expected:** 6 columns: `id`, `band_id`, `new_song_behavior` (default 'ask'), `existing_song_behavior` (default 'fill-missing-only'), `created_at`, `updated_at`

---

**PRE-DEPLOY TEST 2: Verify CHECK constraints**

```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'enrichment_settings'::regclass
  AND contype = 'c';
```

**Expected:** 2 CHECK constraints:

- `new_song_behavior IN ('ask', 'auto', 'off')`
- `existing_song_behavior IN ('fill-missing-only', 'auto-replace', 'show-diffs')`

---

**PRE-DEPLOY TEST 3: Verify RLS enabled**

```sql
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'enrichment_settings';
```

**Expected:** `rowsecurity = true`

---

**PRE-DEPLOY TEST 4: Verify RPC exists**

```sql
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('get_or_create_enrichment_settings', 'update_enrichment_settings');
```

**Expected:** 2 rows (both FUNCTION)

---

**PRE-DEPLOY TEST 5: Test get_or_create RPC**

```sql
-- Use a test band ID (not production data)
DO $$
DECLARE
  v_test_band_id UUID := gen_random_uuid();
  v_result JSONB;
BEGIN
  -- Create test band
  INSERT INTO bands (id, name, created_by, image_url)
  VALUES (v_test_band_id, 'Test Band', auth.uid(), 'https://example.com/test.jpg');

  -- Create band membership (required for INSERT policy to pass)
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, auth.uid(), 'admin', 'active');

  -- Call RPC
  v_result := get_or_create_enrichment_settings(v_test_band_id);

  -- Assert defaults
  ASSERT v_result->>'band_id' = v_test_band_id::TEXT, 'band_id mismatch';
  ASSERT v_result->>'new_song_behavior' = 'ask', 'new_song_behavior should default to ask';
  ASSERT v_result->>'existing_song_behavior' = 'fill-missing-only', 'existing_song_behavior should default to fill-missing-only';

  -- Cleanup
  DELETE FROM enrichment_settings WHERE band_id = v_test_band_id;
  DELETE FROM band_members WHERE band_id = v_test_band_id;
  DELETE FROM bands WHERE id = v_test_band_id;

  RAISE NOTICE 'PRE-DEPLOY TEST 5: PASS';
END $$;
```

---

**PRE-DEPLOY TEST 6: Test update RPC**

```sql
DO $$
DECLARE
  v_test_band_id UUID := gen_random_uuid();
  v_result JSONB;
BEGIN
  -- Create test band
  INSERT INTO bands (id, name, created_by, image_url)
  VALUES (v_test_band_id, 'Test Band', auth.uid(), 'https://example.com/test.jpg');

  -- Create band membership (required for INSERT policy to pass)
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, auth.uid(), 'admin', 'active');

  -- Create default settings
  PERFORM get_or_create_enrichment_settings(v_test_band_id);

  -- Update settings
  v_result := update_enrichment_settings(v_test_band_id, 'auto', 'auto-replace');

  -- Assert updated values
  ASSERT v_result->>'new_song_behavior' = 'auto', 'new_song_behavior should be auto';
  ASSERT v_result->>'existing_song_behavior' = 'auto-replace', 'existing_song_behavior should be auto-replace';

  -- Cleanup
  DELETE FROM enrichment_settings WHERE band_id = v_test_band_id;
  DELETE FROM band_members WHERE band_id = v_test_band_id;
  DELETE FROM bands WHERE id = v_test_band_id;

  RAISE NOTICE 'PRE-DEPLOY TEST 6: PASS';
END $$;
```

---

**PRE-DEPLOY TEST 7: Test invalid enum rejection**

```sql
DO $$
DECLARE
  v_test_band_id UUID := gen_random_uuid();
  v_error_raised BOOLEAN := FALSE;
BEGIN
  -- Create band membership (required for INSERT policy to pass)
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_test_band_id, auth.uid(), 'admin', 'active');

  -- Try to update with invalid enum
  BEGIN
    PERFORM update_enrichment_settings(v_test_band_id, 'invalid', 'fill-missing-only');
  EXCEPTION
    WHEN OTHERS THEN
      v_error_raised := TRUE;
  END;

  ASSERT v_error_raised, 'Should reject invalid new_song_behavior';

  -- Cleanup
  DELETE FROM band_members WHERE band_id = v_test_band_id;

  ASSERT v_error_raised, 'Should reject invalid new_song_behavior';

  -- Cleanup
  DELETE FROM bands WHERE id = v_test_band_id;

  RAISE NOTICE 'PRE-DEPLOY TEST 7: PASS';
END $$;
```

---

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

**POST-DEPLOY TEST 1: Verify RLS SELECT policy**

```sql
-- This test must be run as a test user with band membership
-- Tony to provide test user ID and band ID

-- Scenario: User can SELECT their own band's settings
SELECT * FROM enrichment_settings WHERE band_id = '<TONY_BAND_ID>';
-- Expected: 1 row (or 0 if not yet created)

-- Scenario: User cannot SELECT another band's settings (RLS blocks)
-- Create a test band owned by another user, verify SELECT returns 0 rows
```

---

**POST-DEPLOY TEST 2: Verify RLS UPDATE policy (admin/member only)**

```sql
-- This test must be run as a test admin user
-- Tony to provide test admin user ID and band ID

-- Scenario: Admin can UPDATE settings
UPDATE enrichment_settings
SET new_song_behavior = 'auto'
WHERE band_id = '<TONY_BAND_ID>';
-- Expected: 1 row updated

-- Scenario: Contributor CANNOT UPDATE settings (must be tested manually with contributor role)
-- Expected: RLS blocks, 0 rows updated, error message
```

---

**POST-DEPLOY TEST 3: Manual Flutter integration test**

**Test Case 1: Settings screen loads and updates**

1. Open app, navigate to Settings → Song Enrichment
2. Verify settings load (current values displayed in radios)
3. Change "New Song Behavior" to "Auto"
4. Verify snackbar: "Settings updated"
5. Close screen, reopen → verify "Auto" is still selected

**Test Case 2: Song Lookup with Ask mode**

1. Set "New Song Behavior" to "Ask"
2. Navigate to Setlist → Song Lookup → search for "Wonderwall"
3. Tap external result → verify review sheet opens
4. Verify BPM, Duration, Key are shown
5. Tap "Add to Setlist" → verify song added with enriched metadata

**Test Case 3: Song Lookup with Auto mode**

1. Set "New Song Behavior" to "Auto"
2. Navigate to Setlist → Song Lookup → search for "Let It Be"
3. Tap external result → verify NO review sheet opens
4. Verify brief spinner, then song added immediately
5. Open song details → verify BPM, Duration, Key are populated

**Test Case 4: Song Lookup with Off mode**

1. Set "New Song Behavior" to "Off"
2. Navigate to Setlist → Song Lookup → search for "Hey Jude"
3. Tap external result → verify song added immediately
4. Open song details → verify BPM and Key are NOT populated (Duration may be present from search)

**Test Case 5: Bulk Import with Ask mode**

1. Set "New Song Behavior" to "Ask"
2. Navigate to Setlist → Bulk Entry → paste:
   ```
   The Beatles - Yesterday
   The Rolling Stones - Paint It Black
   ```
3. Tap "Add Songs" → verify 2 dialogs appear sequentially
4. Confirm enrichment for both → verify songs added with enriched metadata

**Test Case 6: Bulk Import with Auto mode**

1. Set "New Song Behavior" to "Auto"
2. Navigate to Setlist → Bulk Entry → paste:
   ```
   Pink Floyd - Comfortably Numb
   Led Zeppelin - Stairway to Heaven
   ```
3. Tap "Add Songs" → verify progress indicator: "Enriching 1 of 2 songs..."
4. Verify both songs added with enriched metadata

**Test Case 7: Manual Entry with Ask mode**

1. Set "New Song Behavior" to "Ask"
2. Navigate to Setlist → Original Song
3. Type title: "Test Song", artist: "Test Artist"
4. Tap "Add song" → verify dialog appears
5. Confirm enrichment → verify song added (enrichment may return "Not found" for fake song)

**Test Case 8: Manual Entry with Off mode**

1. Set "New Song Behavior" to "Off"
2. Navigate to Setlist → Original Song
3. Type title: "Another Test", artist: "Test Band"
4. Tap "Add song" → verify NO dialog, song added immediately with title/artist only

**Test Case 9: Enrichment Drawer respects existing-song behavior**

1. Set "Existing Song Behavior" to "Fill Missing Only"
2. Open Enrichment Drawer → verify "Overwrite existing values" checkbox is unchecked
3. Change to "Auto-Replace" → verify checkbox is checked
4. Change to "Show Diffs" → verify checkbox is unchecked, note appears: "Diff review UI coming in Phase 2.3b"

**Test Case 10: Active band switching refreshes settings**

1. Set Band A "New Song Behavior" to "Ask"
2. Set Band B "New Song Behavior" to "Auto"
3. Switch to Band A → navigate to Settings → verify "Ask" is selected
4. Switch to Band B → navigate to Settings → verify "Auto" is selected

---

## QA Regression Areas

**Primary feature validation:**

- Settings screen loads, updates, and persists correctly
- All 3 entry points (Song Lookup, Bulk Import, Manual Entry) respect "Ask/Auto/Off" settings
- Enrichment Drawer respects "Fill Missing Only / Auto-Replace / Show Diffs\*" settings
- Active band switching refreshes settings correctly

**Regression checks:**

- Existing Song Lookup without settings change → still works (current "ask" behavior)
- Existing Bulk Import without settings change → still works (current "off" behavior)
- Existing Manual Entry without settings change → still works (current "off" behavior)
- Existing Enrichment Drawer without settings change → still works (checkbox toggles as before)
- RLS policies block contributors from changing settings → error handled gracefully
- Missing settings row → RPC creates default on first access → no crash

**Platform-specific:**

- iOS: Settings screen renders correctly, radios work
- Android: Settings screen renders correctly, radios work
- Web: Settings screen renders correctly, radios work
- macOS: Settings screen renders correctly, radios work

**Performance:**

- "Auto" mode enrichment does not block UI → spinner shows progress
- "Ask" mode dialogs appear sequentially, do not stack
- Bulk Import with 20 songs in "Auto" mode → completes without crash or timeout

---

## Rollout / Migration Strategy

**Migration deployment:**

1. Apply migration locally: `cd supabase && supabase db reset`
2. Verify Tier 1 tests pass
3. Deploy to staging: `cd supabase && supabase db push`
4. Verify Tier 2 tests pass
5. Deploy to production: `cd supabase && supabase db push --linked`

**No data migration required:**

- New table starts empty
- RPC `get_or_create_enrichment_settings()` creates defaults on first access per band
- Existing songs/setlists/enrichment behavior unchanged

**Rollback plan:**

- If critical bug found: revert migration via `supabase db reset --to <previous-version>`
- If settings table causes issues: DROP TABLE and CASCADE will remove all settings (no FK dependencies from other tables)

**Feature flag:**

- No feature flag required — settings screen is additive and optional
- Users who don't access Settings → continue with current behavior (implicit "ask"/"off" mode)

---

## Out of Scope

**Phase 2.3b — Show Diffs UI (deferred to future feature):**

- "Show diffs" review modal for existing-song enrichment
- Side-by-side comparison of current values vs. enriched values
- Per-field accept/reject controls
- Bulk accept/reject all fields

**NOT included in Phase 2.3a:**

- Editing `existing_song_behavior` in drawer (checkbox still works but does not write to database)
- Per-field enrichment preferences (e.g., "auto-enrich BPM but ask for Key")
- Per-song overrides (all songs in a band follow the same settings)
- Notification when enrichment completes in "auto" mode
- Retry failed enrichments (if API call fails, song is added without enrichment)
- Enrichment analytics dashboard (track how many songs were enriched, success rate, etc.)

---

## Additional Context

**Design decisions:**

1. **Band-scoped settings (not user-scoped):** Enrichment preferences are per-band because song data is band-scoped. This allows different bands to have different enrichment policies (e.g., Cover Band = auto, Original Band = off).

2. **Enum in database CHECK constraint (not Flutter-only):** Validates enum values at the storage layer (defense-in-depth). Future clients (web admin panel, CLI tools) cannot insert invalid values.

3. **"Ask" as default for new songs:** Least surprising behavior — users see what enrichment data was found before it's saved. Matches current Song Lookup flow.

4. **"Fill Missing Only" as default for existing songs:** Conservative — preserves user-edited values. Users can opt into "Auto-Replace" if they want to overwrite existing data.

5. **"Show Diffs" schema-reserved but not implemented:** Including the enum value now avoids a second migration for Phase 2.3b. Selecting it falls back to "Fill Missing Only" with a note.

6. **RLS policies block contributors:** Contributors have read-only access to setlists/songs; they should not be able to change band-wide enrichment policies. Admins and members can update settings.

7. **Inline enrichment service (new):** Separate from `SongEnrichmentOrchestrator` (batch) and `SongEnrichmentService` (lookup only). `InlineSongEnrichmentService` wraps lookup + RPC write for single-song scenarios (Auto mode).

8. **Enrichment confirm dialog (new):** Simplified version of `showSongEnrichmentReviewSheet()` for Bulk/Manual entry "ask" mode. Does not allow editing enriched values (user can edit after song is added).

9. **No new tests:** Project conventions specify minimal test coverage. Existing `bulk_song_parser_test.dart` is unaffected.

10. **Active band switching:** `enrichmentSettingsProvider` watches `activeBandProvider` and auto-refreshes settings. Pattern matches `oneCalendarPreferencesProvider` and all other band-scoped providers.

**Success criteria:**

- Phase 2.3a is complete when:
  - Settings table exists in database with RLS and RPC
  - Settings screen allows selecting Ask/Auto/Off for new songs
  - Settings screen allows selecting Fill Missing Only / Auto-Replace / Show Diffs\* for existing songs
  - All 3 entry points (Song Lookup, Bulk Import, Manual Entry) respect new-song settings
  - Enrichment Drawer respects existing-song settings
  - All Tier 1 and Tier 2 tests pass
  - No regressions in existing enrichment flows

- Phase 2.3b (deferred) will be considered complete when:
  - "Show Diffs" UI is implemented with side-by-side comparison
  - Existing-song enrichment shows diff review before updating
  - Per-field accept/reject controls work
  - Fallback note is removed from settings screen
