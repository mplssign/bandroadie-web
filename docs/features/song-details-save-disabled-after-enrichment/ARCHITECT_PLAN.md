# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/song-details-save-disabled-after-enrichment`

---

## 2. Problem Summary

After running "Enrich Song Data" from the Song Details modal, the enrichment completes successfully (confirmed by "Enrichment Complete" overlay showing field updates), and the Song Details UI displays the enriched values (e.g., BPM 177, Duration 4:23, Key F#m). However, the Save button at the bottom of the modal remains disabled, with no explicit path to commit or confirm the displayed values. This creates user confusion about whether the enrichment actually persisted to the database.

**User impact:** Users are unsure whether enriched values are saved. The disabled Save button feels like a broken state rather than an "all saved" confirmation. There is no explicit feedback communicating that enrichment auto-saves directly to the database.

---

## 3. Root Cause

**Diagnosis:** This is a UX communication issue, not a code bug. The enrichment system is working as designed.

**What actually happens:**

1. User taps "Enrich Song Data" in Song Details
2. Enrichment selector opens, user selects fields (BPM, Duration, Key)
3. Orchestrator fetches enrichment data from APIs (GetSongBPM for BPM/Key, iTunes/MusicBrainz for Duration)
4. Orchestrator calls `update_song_metadata` RPC, which **writes directly to the database** (not through Song Details' save flow)
5. RPC returns `{success: true}`
6. Song Details' `_handleEnrichSong()` method calls `_refreshAndRebaselineMetadata()` to sync local form state with the database
7. The rebaseline query fetches the newly-persisted values from the database
8. Both `_currentBpm/Duration/Key` **and** `_originalBpm/Duration/Key` are set to the refreshed database values
9. `_computeChangeFlags()` returns `anyChanged: false` because current === original
10. `_hasChanges` becomes `false`, which disables the Save button
11. UI displays the enriched values (from database), but Save is disabled (because there's nothing to save)

**Why this confuses users:**

- **No explicit "saved" feedback:** The Enrichment Results overlay shows what was updated, but doesn't explicitly state "Changes have been saved to the database"
- **Disabled Save button feels broken:** Users expect a disabled button to mean "nothing to do" or "something is wrong", not "everything is already saved"
- **No clear confirmation path:** Users want to see a "Commit" or "Save" action after enrichment, but the system design is auto-save (enrichment writes directly to DB)
- **Mental model mismatch:** Users expect enrichment to be a "proposal" that requires explicit confirmation, but it's actually an auto-commit operation

**Root Cause Confidence:** **HIGH** — confirmed via direct code inspection:

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart:587-643` — `_handleEnrichSong()` calls orchestrator, then rebaselines form state
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart:331-347` — `_refreshAndRebaselineMetadata()` sets both current AND original to DB values
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart:247-312` — `_computeChangeFlags()` compares current vs. original, Save enables only when anyChanged
- `lib/features/songs/services/song_enrichment_orchestrator.dart:231-260` — Orchestrator calls `_repository.enrichSongs()` which invokes `update_song_metadata` RPC
- `lib/features/setlists/setlist_repository.dart:3287-3359` — `enrichSongs()` calls RPC, which persists immediately
- `supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql` — RPC includes eligibility-aware verification, returns `{success: false}` only on genuine persistence failures (not on expected no-ops)

**What is NOT the cause:**

- ❌ Data not persisting (verified: rebaseline query fetches values from DB, and UI displays them)
- ❌ RPC false-success bug (fixed by migration `20260801120000_fix_update_song_metadata_false_success.sql`, which is on main as of today)
- ❌ Rebaseline query failing (would cause Save to remain enabled if it failed silently; user reports Save is disabled)
- ❌ Related to PR #99 (`bug/song-details-save-clears-enriched-fields`) — that fixed a different symptom (manual Save clearing enriched fields), already merged

---

## 4. Reference Docs Consulted

**Domain reference:**

- `docs/features/existing-song-enrichment/ARCHITECT_PLAN.md` — Phase 2.1 enrichment architecture, confirms auto-save design (no per-song review step)
- No specific `docs/reference/songs/` or `docs/reference/setlists/` domain docs exist

**Code inspection (load-bearing for this diagnosis):**

- `lib/features/setlists/widgets/song_details_bottom_sheet.dart:1-1100` — Song Details form state management, enrichment handler, rebaseline logic
- `lib/features/songs/services/song_enrichment_orchestrator.dart:1-330` — Enrichment flow, field eligibility, result tracking
- `lib/features/setlists/setlist_repository.dart:3287-3359` — `enrichSongs()` RPC wrapper
- `lib/features/songs/widgets/enrichment_results_overlay.dart` — Results overlay UI (checked for messaging)
- `supabase/migrations/20260801120000_fix_update_song_metadata_false_success.sql` — RPC verification logic

---

## 5. Existing System Analysis

### 5.1 Current Enrichment Flow (from Song Details)

```
User opens Song Details for an existing song
  ↓
User taps "Enrich Song Data" button
  ↓
EnrichmentSelectorBottomSheet shows (BPM, Duration, Key checkboxes)
  ↓
User selects fields and taps "Enrich Songs"
  ↓
SongEnrichmentOrchestrator.enrichSongs() runs:
  - Fetches song data (title, artist, current field values)
  - Checks field eligibility (BPM=NULL? Duration=0? Key=NULL/empty?)
  - Calls APIs for eligible fields only
  - Calls update_song_metadata RPC with fetched values
  - RPC writes directly to database (SECURITY DEFINER, bypasses Song Details save flow)
  - Returns per-field results (updated/notFound/unchanged/error)
  ↓
_handleEnrichSong() checks if current song was updated:
  - If yes: calls _refreshAndRebaselineMetadata(bandId)
  - Rebaseline queries database: SELECT bpm, duration_seconds, musical_key
  - Sets BOTH _currentXxx and _originalXxx to refreshed values
  - Calls _checkForChanges(), which computes anyChanged = false
  - _hasChanges = false → Save button disabled
  ↓
Enrichment results overlay shows summary ("X of Y songs enriched")
  ↓
User taps Done → returns to Song Details
  ↓
UI displays enriched values, Save button is disabled
```

### 5.2 Why Save Is Disabled After Enrichment

The Save button's enabled state is controlled by `_hasChanges`:

```dart
// From song_details_bottom_sheet.dart:1674-1689
ElevatedButton(
  onPressed: _hasChanges ? () => _handleSave(context) : null,  // ← disabled when _hasChanges=false
  child: const Text('Save'),
)
```

`_hasChanges` is computed by `_computeChangeFlags()`:

```dart
// From song_details_bottom_sheet.dart:247-312
final bpmChanged = _currentBpm != _originalBpm;
final durationChanged = _currentDurationSeconds != _originalDurationSeconds;
final musicalKeyChanged = (_currentMusicalKey ?? '') != (_originalMusicalKey ?? '');

final anyChanged = titleChanged || artistChanged || notesChanged || tuningChanged ||
                   bpmChanged || durationChanged || youtubeLinksChanged ||
                   lyricsChanged || musicalKeyChanged;
```

After enrichment, `_refreshAndRebaselineMetadata()` sets:

```dart
// From song_details_bottom_sheet.dart:331-347
setState(() {
  _currentBpm = refreshedBpm;
  _originalBpm = refreshedBpm;  // ← same as current
  _currentDurationSeconds = refreshedDurationSeconds;
  _originalDurationSeconds = refreshedDurationSeconds;  // ← same as current
  _currentMusicalKey = refreshedMusicalKey;
  _originalMusicalKey = refreshedMusicalKey;  // ← same as current
  _hasChanges = _computeChangeFlags().anyChanged;  // ← evaluates to false
});
```

**Result:** `bpmChanged = false`, `durationChanged = false`, `musicalKeyChanged = false`, so `anyChanged = false`, so `_hasChanges = false`, so Save button is disabled.

**This is correct behavior** — there are no pending changes because enrichment already wrote to the database. However, this leaves users confused because there's no explicit feedback confirming the save.

### 5.3 Existing Feedback Mechanisms

**What the user DOES see:**

1. **Enrichment Results Overlay** (`lib/features/songs/widgets/enrichment_results_overlay.dart`):
   - Top-line: "✓ X of Y songs enriched"
   - Per-field results: "BPM: Updated", "Duration: Unchanged", "Key: Not found"
   - This confirms what was fetched from APIs, but does NOT explicitly state "Changes saved to database"

2. **Disabled Save button** in Song Details:
   - This correctly indicates "no pending changes"
   - But users interpret it as "broken" or "can't save", not as "already saved"

**What the user does NOT see:**

- No explicit "Changes saved" toast/banner
- No "✓ Saved" button state
- No green checkmark or success indicator after enrichment completes
- Cancel button is also disabled, which adds to the "something is wrong" feeling

---

## 6. Proposed Solution

### 6.1 What Changes (One Sentence)

After enrichment completes and rebaselines form state, show explicit UX feedback confirming that enriched values are already persisted to the database, transforming the Save button to a "Done" button with explanatory text, and disabling the Cancel button (no changes to discard).

### 6.2 Detailed Solution

**Change 1: Transform bottom action bar after enrichment**

When enrichment completes successfully (`_didCurrentSongMetadataUpdate()` returns true), set a new state flag `_justEnriched = true`. This flag triggers a temporary UX state:

**Before enrichment (current behavior):**

```
[Cancel (text button)]     [Save (filled button, enabled if _hasChanges)]
```

**After enrichment (new behavior):**

```
[Cancel (text button, disabled)]     [Done (filled button, always enabled)]
```

With explanatory text above the buttons:

```
"✓ Enrichment saved automatically"
```

**Change 2: "Done" button behavior**

The Done button simply closes the modal (same as Cancel, but conveys completion rather than cancellation). It calls `Navigator.of(context).pop()` with no result (no changes to save).

**Change 3: Clear the `_justEnriched` flag when user makes a manual edit**

If the user manually edits any field after enrichment, revert to normal Save/Cancel behavior:

- Clear `_justEnriched = false`
- Re-enable Cancel
- Change Done back to Save
- Remove the "saved automatically" text

This ensures the UX only shows the "auto-saved" state immediately after enrichment, not indefinitely.

**Change 4: Update Enrichment Results Overlay messaging**

Change the top-line message from:

```
"✓ X of Y songs enriched"
```

To:

```
"✓ X of Y songs enriched and saved"
```

This makes it explicit that enrichment is not just a proposal — it's an auto-commit operation.

---

## 7. Database Impact

**Database: not applicable**

No database changes required. The RPC `update_song_metadata` is working correctly. The issue is purely client-side UX feedback.

---

## 8. Flutter Architecture Changes

**State changes:**

- Add `bool _justEnriched = false` flag to `_SongDetailsSheetState`
- Set `_justEnriched = true` in `_handleEnrichSong()` after successful `_refreshAndRebaselineMetadata()`
- Clear `_justEnriched = false` in `_checkForChanges()` when any field is manually edited

**UI changes:**

- Modify `_buildFixedBottomActions()` to:
  - Show explanatory text "✓ Enrichment saved automatically" when `_justEnriched == true`
  - Disable Cancel button when `_justEnriched == true`
  - Change Save to Done when `_justEnriched == true`
  - Done button is always enabled when shown, calls `Navigator.of(context).pop()`

**Overlay changes:**

- Modify `enrichment_results_overlay.dart`:
  - Change top-line message to include "and saved"
  - Optional: add a subtitle "Changes have been written to the database"

---

## 9. Files to Create

**None.**

---

## 10. Files to Modify

| File                                                           | What changes                                                                                                                                                                                                                                                                           |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Add `_justEnriched` state flag; modify `_handleEnrichSong()` to set flag after rebaseline; modify `_checkForChanges()` to clear flag on manual edit; modify `_buildFixedBottomActions()` to show Done button, disable Cancel, and display "saved automatically" text when flag is true |
| `lib/features/songs/widgets/enrichment_results_overlay.dart`   | Change top-line message from "X of Y songs enriched" to "X of Y songs enriched and saved" for explicit confirmation                                                                                                                                                                    |

---

## 11. Files Off-Limits

| File                                                            | Reason                                                                             |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `lib/features/songs/services/song_enrichment_orchestrator.dart` | Orchestration logic is correct; no changes needed to enrichment flow               |
| `lib/features/setlists/setlist_repository.dart`                 | Repository correctly calls RPC; no changes needed to persistence layer             |
| `supabase/migrations/*.sql`                                     | RPC verification logic is correct; no database changes needed                      |
| `lib/features/setlists/setlist_detail_screen.dart`              | Entry point calls are correct; no changes to catalog/multi-select enrichment flows |

---

## 12. System Impact Map

| System                                 | Impact                                                                                           |
| -------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Gigs                                   | **unaffected** — gigs do not interact with song enrichment                                       |
| Rehearsals                             | **unaffected** — rehearsals do not interact with song enrichment                                 |
| Setlists / Catalog                     | **unaffected** — enrichment persistence is unchanged, only Song Details UI feedback affected     |
| Members / RBAC                         | **unaffected** — no permission or membership logic changes                                       |
| Auth / Session                         | **unaffected** — no authentication changes                                                       |
| Routing                                | **unaffected** — no navigation changes (Done button closes modal same as Cancel)                 |
| Notifications                          | **unaffected** — no notification triggers                                                        |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms use the same Song Details modal; UX improvement applies universally |

---

## 13. Regression Risk

**Risk Level:** **LOW**

**Rationale:**

- Single-file change to Song Details UI logic (plus one-line message change in results overlay)
- No changes to enrichment orchestration, RPC calls, or database persistence
- New state flag (`_justEnriched`) has clear lifecycle: set after enrichment, cleared on manual edit
- Done button behavior is identical to Cancel (closes modal with no save)
- No changes to Save/Cancel logic when `_justEnriched == false` (normal editing flow unchanged)
- Change is additive (new UX state after enrichment), does not alter existing edit-then-save flow

**What could regress:**

- Done button could fail to close modal (low risk, same code as Cancel)
- `_justEnriched` flag could stick if not cleared properly (mitigated by clearing in `_checkForChanges()`)
- Explanatory text could layout poorly on small screens (testable via responsive preview)

**Mitigation:**

- QA must test both enrichment-then-close AND enrichment-then-manual-edit-then-save flows
- Verify Cancel button is disabled only when `_justEnriched == true`, not during normal editing
- Test on iOS and Web to confirm button layout and text rendering

---

## 14. Engineer Task Breakdown

**Task 1:** Add `_justEnriched` state flag

- In `_SongDetailsSheetState`, add `bool _justEnriched = false;`
- Initialize to false in `initState()`

**Task 2:** Set flag after successful enrichment

- In `_handleEnrichSong()`, after `await _refreshAndRebaselineMetadata(bandId)` completes successfully
- Add: `setState(() { _justEnriched = true; });`
- Only set if `_didCurrentSongMetadataUpdate(result)` returned true (enrichment actually updated this song)

**Task 3:** Clear flag on manual field edit

- In `_checkForChanges()`, at the end of the method
- Add: `if (_justEnriched && _hasChanges) { setState(() { _justEnriched = false; }); }`
- This ensures the flag clears as soon as the user makes any manual edit after enrichment

**Task 4:** Modify bottom action bar UI

- In `_buildFixedBottomActions()`, wrap the button row in a Column
- Add conditional explanatory text above buttons when `_justEnriched == true`:
  ```dart
  if (_justEnriched) ...[
    Text(
      '✓ Enrichment saved automatically',
      style: AppTextStyles.callout.copyWith(
        color: context.colors.success, // or primary
        fontWeight: FontWeight.w600,
      ),
    ),
    const SizedBox(height: 8),
  ],
  ```

**Task 5:** Change Cancel button behavior when enriched

- Modify Cancel TextButton: `onPressed: _justEnriched ? null : _handleCancel`
- This disables Cancel when `_justEnriched == true` (nothing to cancel)

**Task 6:** Change Save button to Done when enriched

- Modify Save ElevatedButton:
  - Label: `_justEnriched ? 'Done' : 'Save'`
  - onPressed: `_justEnriched ? () => Navigator.of(context).pop() : (_hasChanges ? () => _handleSave(context) : null)`
- Done button is always enabled when shown, simply closes modal

**Task 7:** Update Enrichment Results Overlay message

- In `enrichment_results_overlay.dart`, locate the top-line summary text
- Change from: `'✓ $enrichedCount of $total songs enriched'`
- To: `'✓ $enrichedCount of $total songs enriched and saved'`

**Task 8:** Test enrichment-then-close flow

- Open Song Details for a song with missing BPM
- Tap "Enrich Song Data", select BPM, tap Enrich
- Verify results overlay shows "enriched and saved"
- Tap Done, return to Song Details
- Verify explanatory text shows "✓ Enrichment saved automatically"
- Verify Cancel is disabled, Done button is enabled
- Tap Done, verify modal closes
- Re-open Song Details, verify enriched BPM is still present

**Task 9:** Test enrichment-then-edit flow

- Open Song Details, enrich BPM
- After enrichment completes, manually edit Duration
- Verify `_justEnriched` flag clears, explanatory text disappears
- Verify Cancel re-enables, Done changes back to Save
- Verify Save button enables (because Duration changed)
- Tap Save, verify changes persist

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (no database changes)

**Not applicable** — this is a client-only UX change. No database migrations or RPC changes.

### Tier 2 — Post-deployment (after code changes deployed)

**TEST 1: Enrichment-then-close (success path)**

```
Steps:
1. On iOS device, open BandRoadie and navigate to Catalog
2. Find song "Don't Tell Me You Love Me" (Night Ranger) or create a test song with BPM=NULL
3. Tap song card → Song Details
4. Clear BPM if present, Save
5. Tap "Enrich Song Data"
6. Select BPM, tap "Enrich Songs"
7. Wait for enrichment to complete

Expected:
- Enrichment Results Overlay shows "✓ 1 of 1 songs enriched and saved" ← message change
- Tap Done, return to Song Details
- Song Details displays BPM 177 (or appropriate value)
- Explanatory text shows "✓ Enrichment saved automatically" ← new text
- Cancel button is disabled (grayed out) ← new state
- Done button is enabled (blue/primary color) ← button label change
- Tap Done → modal closes
- Re-open Song Details → BPM is still 177 (persisted correctly)
```

**TEST 2: Enrichment-then-manual-edit (flag clearing)**

```
Steps:
1. Open Song Details for a song with BPM=NULL, Duration=0
2. Tap "Enrich Song Data", select BPM only
3. Complete enrichment (Song Details shows BPM 177, Done button visible)
4. Manually edit Duration to 3:30 (tap Duration field, enter value)

Expected:
- After entering Duration, explanatory text "✓ Enrichment saved automatically" disappears ← flag cleared
- Cancel button re-enables ← normal state restored
- Done button changes back to Save ← label changes
- Save button is enabled (blue) ← has pending changes
- Tap Save → changes persist
- Re-open Song Details → BPM=177, Duration=210 (both persisted)
```

**TEST 3: No enrichment updates (unchanged path)**

```
Steps:
1. Open Song Details for a song that already has BPM=120, Duration=180, Key="Am"
2. Tap "Enrich Song Data", select all three fields
3. Complete enrichment

Expected:
- Enrichment Results Overlay shows "0 of 1 songs enriched" (all fields unchanged)
- Tap Done, return to Song Details
- Explanatory text does NOT show (no enrichment occurred) ← flag not set
- Save button is disabled (no changes) ← normal behavior
- Cancel button is enabled ← normal behavior
```

**TEST 4: Multi-field enrichment**

```
Steps:
1. Open Song Details for a song with all fields empty (BPM=NULL, Duration=0, Key=NULL)
2. Tap "Enrich Song Data", select BPM, Duration, and Key
3. Complete enrichment

Expected:
- Enrichment Results Overlay shows "1 of 1 songs enriched and saved"
- Tap Done, return to Song Details
- Song Details displays BPM, Duration, and Key values
- Explanatory text shows "✓ Enrichment saved automatically"
- Done button is enabled
- Tap Done → modal closes
- Re-open Song Details → all three fields persisted correctly
```

**TEST 5: Platform-specific (Web)**

```
Steps:
1. Open BandRoadie in Chrome (incognito)
2. Login, navigate to Catalog
3. Repeat TEST 1 (enrichment-then-close)

Expected:
- Same behavior as iOS
- Button layout renders correctly (no overflow or misalignment)
- Explanatory text is visible and styled correctly
```

**TEST 6: Database persistence check (production verification)**

```sql
-- Run this query before and after enrichment in TEST 1 to confirm RPC actually persists

SELECT id, title, artist, bpm, duration_seconds, musical_key, updated_at
FROM songs
WHERE title = 'Don''t Tell Me You Love Me'
  AND artist = 'Night Ranger'
  AND band_id = '<your-test-band-id>'
LIMIT 1;

-- BEFORE enrichment: bpm=NULL, duration_seconds=0, musical_key=NULL
-- AFTER enrichment: bpm=177 (or appropriate value), updated_at changed
-- Confirms RPC write succeeded, not just UI state
```

---

## 16. QA Regression Areas

**Primary (must test):**

1. **Song Details enrichment-then-close flow** (TEST 1)
   - Verify Done button appears after enrichment
   - Verify explanatory text shows
   - Verify Cancel is disabled
   - Verify modal closes on Done tap
   - Verify re-opening Song Details shows persisted values

2. **Song Details enrichment-then-edit flow** (TEST 2)
   - Verify flag clears after manual edit
   - Verify Save/Cancel return to normal behavior
   - Verify Save persists both enriched and manually-edited fields

3. **Enrichment results overlay messaging** (all tests)
   - Verify message says "enriched and saved", not just "enriched"

**Secondary (regression testing):** 4. **Normal Song Details edit-then-save flow (no enrichment)**

- Open Song Details, manually edit BPM, tap Save
- Verify Save button enables when field changes
- Verify Cancel works normally
- Verify no "enrichment saved" text appears (flag not set)

5. **Multi-select enrichment from Catalog** (not Song Details)
   - Select 3 songs, tap "Enrich" in toolbar
   - Verify enrichment runs
   - Verify results overlay shows (with "and saved" message)
   - Verify no impact on Song Details (flag is local to modal instance)

6. **Catalog-wide enrichment** (not Song Details)
   - Tap overflow menu → "Enrich All Songs"
   - Verify enrichment runs for all songs
   - Verify results overlay shows (with "and saved" message)

7. **iOS and Web parity**
   - Run TEST 1 and TEST 2 on both iOS and Web
   - Verify button layout, text rendering, and behavior are identical

---

## 17. Rollout / Migration Strategy

**Not applicable** — client-only UX change, no backend migration required.

**Deployment steps:**

1. Merge feature branch to main
2. Deploy web via `./tools/deploy_web.sh`
3. Deploy iOS/Android via standard mobile release process

**Rollback plan:**

- If issue discovered post-deploy, revert commit and redeploy
- No database state to clean up (no migrations)

---

## 18. Out of Scope

**Explicitly NOT addressed in this fix:**

1. **Changing enrichment from auto-save to manual-confirm** — out of scope, would require redesigning the enrichment flow to keep values in a "pending" state and add explicit Save logic
2. **Adding an "Undo Enrichment" button** — out of scope, would require storing pre-enrichment snapshots
3. **Enrichment progress spinner in Song Details** — out of scope, enrichment is fast (<2 seconds for single song)
4. **Adding a settings toggle for "auto-save enrichment"** — out of scope, all enrichment is auto-save by design per Phase 2.1
5. **Changing Cancel button to always be enabled** — out of scope, disabling Cancel after enrichment correctly indicates "nothing to discard"
6. **Adding a timestamp to "Enrichment saved automatically" text** — out of scope, adds unnecessary complexity for a temporary state

---

**End of ARCHITECT_PLAN.md**
