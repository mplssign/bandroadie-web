# ARCHITECT_PLAN

## 1. Feature Slug

feature/song-key-tuning-none-option

## 2. Problem Summary

Users can set song Key and Tuning but cannot reliably clear either back to unset.

- Musical key clear is a regression: UI and client call paths already emit an empty-string clear signal, but current RPC behavior no longer writes NULL to songs.musical_key.
- Tuning clear is a missing capability: picker has no explicit None option, save is blocked without a concrete tuning selection, and repository update method rejects empty values.
- Song Details currently treats unset tuning as Standard (E) using a fallback, so cleared values are visually indistinguishable from explicit Standard.

## 3. Root Cause

Primary root causes and confidence:

1. update_song_metadata no longer supports musical key clearing (HIGH)

- Confirmed in supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql: musical_key assignment is fill-only and never writes NULL.
- The previous clear branch (p_musical_key = '' THEN NULL) existed in supabase/migrations/20260703034302_fix_musical_key_clear_in_update_song_rpc.sql but was removed in the later rewrite.

2. Tuning clear path is not implemented in client architecture (HIGH)

- tuning picker has no None row and \_handleSave returns early when selection is null.
- controller/repository only expose updateSongTuning\* flow and SetlistRepository.updateSongTuningOverride rejects empty tuning.
- clear_song_metadata is already used for BPM clear and supports clear flags pattern, but no tuning clear method is wired from UI.

3. Song Details fallback masks unset tuning (HIGH)

- Song details state initialization and change-comparison logic force widget.song.tuning ?? 'standard_e', causing null to render and compare as Standard.

## 4. Reference Docs Consulted

- docs/agents/ARCHITECT.md
- docs/agents/GUARDRAILS.md
- docs/agents/OPERATING_MODEL.md
- .github/copilot-instructions.md
- docs/reference/general/BAND_ROADIE_DOCUMENTATION.md
- docs/reference/architecture/database_schema.md

No dedicated feature reference folder exists for key/tuning metadata under docs/reference for this specific behavior.

## 5. Existing System Analysis

Current key path:

1. Key picker UI

- lib/features/setlists/widgets/key_picker_bottom_sheet.dart returns empty string when tapping an already-selected key.

2. Song Details call chain

- lib/features/setlists/widgets/song_details_bottom_sheet.dart stores clear as empty string and emits SongDetailsResult.musicalKey.
- lib/features/setlists/setlist_detail_screen.dart always calls notifier.updateSongMusicalKey when musicalKeyChanged.
- lib/features/setlists/setlist_detail_controller.dart calls repository.updateSongMusicalKey.
- lib/features/setlists/setlist_repository.dart calls RPC update_song_metadata with p_musical_key set to provided value.

3. Enrichment review call chain

- lib/features/setlists/widgets/song_enrichment_review_sheet.dart already maps empty string to null in local state.

Failure point:

- update_song_metadata (current SQL) only fills musical_key when existing value is NULL/blank and incoming p_musical_key is NOT NULL; it has no clear branch.

Current tuning path:

1. Tuning picker UI

- lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart has grouped tuning options only, no None row, and save enabled only when a concrete selection changed.

2. Song Details tuning call chain

- Song Details picker result is always a concrete tuningId (plus optional capo), then saved via update path.
- setlist_detail_screen handles tuningChanged only when result.tuning is non-null and calls updateSongTuning.
- controller updateSongTuning requires non-empty tuning and repository updateSongTuningOverride rejects empty tuning.

3. Reorderable song card call chain

- lib/features/setlists/widgets/reorderable_song_card.dart also uses tuning picker and only emits concrete string value through onTuningChanged.

Display masking:

- Song Details computes current/original tuning with default standard_e and displays tuning name from that value, so unset cannot be distinguished from explicit Standard.

## 6. Proposed Solution

Implement clear behavior using explicit clear RPC methods (same architecture as BPM clear), and add explicit None options in both pickers.

Design decisions:

1. Musical key clear architecture

- Add p_clear_musical_key boolean to clear_song_metadata (migration).
- Add repository clearSongMusicalKeyOverride method, mirroring clearSongBpmOverride pattern including PGRST202/42883 direct-update fallback.
- Route clear key actions to clearSongMusicalKeyOverride instead of relying on update_song_metadata empty-string sentinel.
- Keep existing key toggle-to-deselect behavior; add visible None entry at top of key picker for explicit clear UX.

2. Tuning clear architecture

- Add repository clearSongTuningOverride method, mirroring clearSongBpmOverride with p_clear_tuning true and direct-update fallback.
- Add controller clearSongTuning method with optimistic update + rollback + broadcaster clear event.
- Update all tuning picker call paths to treat None as clear request and call clearSongTuning.

3. Picker UI behavior

- Key picker: insert None as first list item above Major header. Tapping returns empty string and closes.
- Tuning picker: insert None as first list item above Standard & Drop Tunings. Selecting None is considered a valid pending change and Save is enabled.
- Tuning picker result model should carry an explicit clear signal (recommended: nullable tuningId with isClear intent, or dedicated clear flag).

4. Display fallback correction

- Remove standard_e fallback in Song Details internal state for current/original tuning.
- Render unset tuning as em dash in Song Details metrics row.
- Reopen tuning picker with no preselection when tuning is unset.

What must not change:

- No changes to financials or events features.
- No changes to app initialization order, auth flow, routing, or theme system.
- No new dependencies.

## 7. Database Impact

Database: affected.

Migrations:

- Required: one new migration to replace clear_song_metadata signature/body and add p_clear_musical_key clear flag handling.

RLS:

- Unaffected directly (function remains SECURITY DEFINER with search_path public, and membership checks preserved).

RPCs:

- clear_song_metadata: affected (signature + logic extended).
- update_song_metadata: unchanged in this feature plan (used for set operations, not clear operations).

Triggers:

- Unaffected.

Notes:

- This avoids reintroducing fragile string-sentinel semantics inside update_song_metadata, reducing recurrence risk from future function rewrites.

## 8. Flutter Architecture Changes

State and flow changes:

- setlist_repository.dart
  - Add clearSongTuningOverride.
  - Add clearSongMusicalKeyOverride.

- setlist_detail_controller.dart
  - Add clearSongTuning.
  - Add clearSongMusicalKey.
  - Keep optimistic update pattern and rollback parity with existing clearSongBpm.

- setlist_detail_screen.dart
  - In SongDetails result handling:
    - For tuningChanged, call clear path when tuning is null/clear sentinel.
    - For musicalKeyChanged, call clear path when value is null or empty.

Widgets:

- key_picker_bottom_sheet.dart: explicit None option at top, preserve tap-selected-key-to-deselect behavior.
- tuning_picker_bottom_sheet.dart: explicit None option at top, Save enabled for clear selection.
- song_details_bottom_sheet.dart: remove default Standard fallback and show unset distinctly.
- reorderable_song_card.dart: propagate tuning clear signal from picker to callback and controller path.

## 9. Files to Create

- supabase/migrations/<timestamp>\_add_clear_musical_key_to_clear_song_metadata.sql
  - Replace clear_song_metadata with new optional clear flag for musical_key.

No other new files required.

## 10. Files to Modify

- lib/features/setlists/widgets/key_picker_bottom_sheet.dart
  - Add explicit None row above Major section; return empty string on tap.

- lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart
  - Add explicit None row above first group.
  - Update temporary selection model and save gating to allow clear result.
  - Return clear signal in picker result.

- lib/features/setlists/widgets/song_details_bottom_sheet.dart
  - Remove standard_e fallback for current/original tuning.
  - Update change detection and metrics rendering for nullable tuning.
  - Treat tuning clear from picker as changed state.

- lib/features/setlists/widgets/reorderable_song_card.dart
  - Handle tuning picker clear signal and pass clear intent through callback.

- lib/features/setlists/setlist_detail_screen.dart
  - Route tuning and key clear results to clear controller methods.

- lib/features/setlists/setlist_detail_controller.dart
  - Add clearSongTuning and clearSongMusicalKey methods.
  - Keep optimistic update/rollback and broadcaster behavior aligned with existing patterns.

- lib/features/setlists/setlist_repository.dart
  - Add clearSongTuningOverride and clearSongMusicalKeyOverride using clear_song_metadata + fallback.

## 11. Files Off-Limits

- lib/main.dart
  - Initialization order is guardrailed and unrelated.

- lib/features/financials/\*\*
  - Explicitly out of scope per feature input.

- lib/features/events/\*\*
  - Explicitly out of scope per feature input.

- pubspec.yaml
  - No dependency changes needed.

- Any notification/auth/routing modules
  - Unrelated to this metadata-clear feature.

## 12. System Impact Map

| System                                 | Impact                              |
| -------------------------------------- | ----------------------------------- |
| Gigs                                   | unaffected                          |
| Rehearsals                             | unaffected                          |
| Setlists / Catalog                     | affected                            |
| Members / RBAC                         | unaffected                          |
| Auth / Session                         | unaffected                          |
| Routing                                | unaffected                          |
| Notifications                          | unaffected                          |
| Platform (iOS / Android / Web / macOS) | affected (shared Flutter code path) |

## 13. Regression Risk

MEDIUM.

Rationale:

- Touches shared setlist metadata edit flows and SQL RPC behavior.
- Includes function signature/body migration and multiple UI call sites.
- Risk is bounded by localized changes and use of existing clear pattern (clearSongBpm precedent).

## 14. Engineer Task Breakdown

1. Create migration to extend clear_song_metadata with p_clear_musical_key boolean and NULL-assignment branch for musical_key.
2. Add repository clearSongTuningOverride using clear_song_metadata with p_clear_tuning true and direct-update fallback.
3. Add repository clearSongMusicalKeyOverride using clear_song_metadata with p_clear_musical_key true and direct-update fallback.
4. Add controller clearSongTuning and clearSongMusicalKey with optimistic update + rollback + broadcaster updates.
5. Update setlist_detail_screen save routing for tuning/key clear vs set behavior.
6. Update key picker to include explicit None option above Major while preserving tap-selected-key toggle clear.
7. Update tuning picker to include explicit None option above first group and to return clear signal with Save enabled.
8. Update reorderable song card tuning callback flow to support clear signal from picker.
9. Update Song Details tuning state initialization/comparison/display so unset remains unset and visibly distinct from Standard.
10. Validate all picker call sites found via search are covered (song details, reorderable card, enrichment review for key behavior).

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before supabase db push)

Run only against existing objects without applying schema/function changes.

```sql
-- PRE-DEPLOY TEST 1:
-- Baseline current clear_song_metadata signature list (document current args)
SELECT
  p.proname,
  oidvectortypes(p.proargtypes) AS arg_types
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'clear_song_metadata';

-- PRE-DEPLOY TEST 2:
-- Confirm songs.musical_key is nullable (required for clear-to-NULL)
SELECT
  column_name,
  is_nullable,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'songs'
  AND column_name = 'musical_key';

-- PRE-DEPLOY TEST 3:
-- Confirm update_song_metadata currently has no clear branch (baseline regression evidence)
SELECT
  CASE
    WHEN pg_get_functiondef(p.oid) ILIKE '%p_musical_key = ''''% then null%'
      THEN 'HAS_CLEAR_BRANCH'
    ELSE 'NO_CLEAR_BRANCH'
  END AS musical_key_clear_branch_state
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'update_song_metadata'
LIMIT 1;
```

### Tier 2 — Post-deployment (run after supabase db push succeeds)

```sql
-- POST-DEPLOY TEST 1:
-- Verify clear_song_metadata definition includes new clear flag + musical_key nulling branch
SELECT
  CASE
    WHEN pg_get_functiondef(p.oid) ILIKE '%p_clear_musical_key%'
     AND pg_get_functiondef(p.oid) ILIKE '%musical_key = case%'
      THEN 'PASS'
    ELSE 'FAIL'
  END AS function_shape_check
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'clear_song_metadata'
LIMIT 1;

-- POST-DEPLOY TEST 2:
-- Integration: clear musical key through RPC on a real row, then restore original value.
-- Requires a real active-member context for auth.uid(); if run in SQL editor,
-- set request.jwt.claim.sub to an active band member user id first.
DO $$
DECLARE
  v_user_id uuid;
  v_band_id uuid;
  v_song_id uuid;
  v_before_key text;
  v_after_key text;
BEGIN
  -- dependency: uses existing band_members + songs records
  SELECT bm.user_id, bm.band_id
  INTO v_user_id, v_band_id
  FROM band_members bm
  WHERE bm.status = 'active'
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No active band member found for test';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

  SELECT s.id, s.musical_key
  INTO v_song_id, v_before_key
  FROM songs s
  WHERE (s.band_id = v_band_id OR s.band_id IS NULL)
  LIMIT 1;

  IF v_song_id IS NULL THEN
    RAISE EXCEPTION 'No test song found for selected band';
  END IF;

  -- ensure song has a value to clear for deterministic assertion
  IF v_before_key IS NULL THEN
    UPDATE songs SET musical_key = 'C' WHERE id = v_song_id;
    v_before_key := 'C';
  END IF;

  PERFORM public.clear_song_metadata(
    p_song_id := v_song_id,
    p_band_id := v_band_id,
    p_clear_musical_key := true
  );

  SELECT musical_key INTO v_after_key FROM songs WHERE id = v_song_id;
  IF v_after_key IS NOT NULL THEN
    RAISE EXCEPTION 'Expected musical_key NULL after clear, got %', v_after_key;
  END IF;

  -- restore original value
  UPDATE songs
  SET musical_key = v_before_key
  WHERE id = v_song_id;

  IF (SELECT musical_key FROM songs WHERE id = v_song_id) IS DISTINCT FROM v_before_key THEN
    RAISE EXCEPTION 'Restore failed for musical_key';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    -- best-effort restore on failure
    IF v_song_id IS NOT NULL THEN
      UPDATE songs SET musical_key = v_before_key WHERE id = v_song_id;
    END IF;
    RAISE;
END;
$$;

-- POST-DEPLOY TEST 3:
-- Integration: clear tuning through RPC on a real row, then restore original value.
DO $$
DECLARE
  v_user_id uuid;
  v_band_id uuid;
  v_song_id uuid;
  v_before_tuning text;
  v_after_tuning text;
BEGIN
  SELECT bm.user_id, bm.band_id
  INTO v_user_id, v_band_id
  FROM band_members bm
  WHERE bm.status = 'active'
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No active band member found for test';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', v_user_id::text, true);

  SELECT s.id, s.tuning
  INTO v_song_id, v_before_tuning
  FROM songs s
  WHERE (s.band_id = v_band_id OR s.band_id IS NULL)
  LIMIT 1;

  IF v_song_id IS NULL THEN
    RAISE EXCEPTION 'No test song found for selected band';
  END IF;

  IF v_before_tuning IS NULL THEN
    UPDATE songs SET tuning = 'standard_e' WHERE id = v_song_id;
    v_before_tuning := 'standard_e';
  END IF;

  PERFORM public.clear_song_metadata(
    p_song_id := v_song_id,
    p_band_id := v_band_id,
    p_clear_tuning := true
  );

  SELECT tuning INTO v_after_tuning FROM songs WHERE id = v_song_id;
  IF v_after_tuning IS NOT NULL THEN
    RAISE EXCEPTION 'Expected tuning NULL after clear, got %', v_after_tuning;
  END IF;

  UPDATE songs
  SET tuning = v_before_tuning
  WHERE id = v_song_id;

  IF (SELECT tuning FROM songs WHERE id = v_song_id) IS DISTINCT FROM v_before_tuning THEN
    RAISE EXCEPTION 'Restore failed for tuning';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    IF v_song_id IS NOT NULL THEN
      UPDATE songs SET tuning = v_before_tuning WHERE id = v_song_id;
    END IF;
    RAISE;
END;
$$;

-- POST-DEPLOY TEST 4:
-- Production data safety check: ensure no empty-string keys were written.
SELECT COUNT(*) AS empty_string_musical_keys
FROM songs
WHERE musical_key = '';
```

## 16. QA Regression Areas

1. Key picker clear behavior

- None option clears key.
- Tapping currently selected key still clears key.
- Reopen picker after clear shows no key selected.

2. Tuning picker clear behavior

- None option appears above Standard & Drop Tunings.
- Selecting None enables Save and persists clear.
- Reopen picker after clear shows no tuning selected.

3. Song Details display behavior

- Unset tuning displays as em dash, not Standard.
- Explicit Standard still displays Standard.

4. Cross-surface consistency

- Song Details and Reorderable Song Card both support tuning clear end-to-end.
- Song enrichment review key behavior remains correct.

5. Persistence + sync

- Clear key/tuning persists after closing/reopening sheet and full refresh.
- Updates propagate across setlists containing the same song.

6. Non-regression metadata edits

- BPM, Duration, Notes, Title/Artist, Lyrics, YouTube links still save as before.

7. Platforms

- Smoke on Web, iOS, Android, macOS shared code path.

## 17. Rollout / Migration Strategy

1. Merge feature implementation PR after QA approval.
2. Run pre-deploy SQL checks (Tier 1).
3. Apply migration with supabase db push.
4. Run post-deploy SQL checks (Tier 2).
5. Deploy app updates per normal release flow.

Rollback:

- If clear_song_metadata change misbehaves, deploy a rollback migration restoring previous function signature/body.
- Client clear methods have direct-update fallback for RPC-not-found, reducing hard failure risk.

## 18. Out of Scope

- Any work in lib/features/financials.
- Any work in lib/features/events.
- Redesign of tuning taxonomy or key naming.
- Refactors unrelated to key/tuning clear behavior.
- Changes to authentication, routing, notifications, or app initialization order.
