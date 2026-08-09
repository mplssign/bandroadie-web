# QA Report

## Feature Slug

`bug/remove-orphaned-spotify-functions`

## Feature Title

Remove Orphaned Spotify Edge Functions

## Final Verdict

**APPROVED**

## Validation Summary

All dead Spotify enrichment code has been cleanly removed per the Architect Plan. The implementation deletes two never-invoked edge functions (`spotify_search` folder, `spotify_audio_features` config), removes 151 lines of dead Dart code from `SetlistRepository`, and eliminates the unused `skipBackgroundEnrichment` parameter. Code-path analysis confirms the iTunes → MusicBrainz search flow remains intact, historical Spotify data display is preserved (`SongSource.spotify` enum, `Song.spotifyId` field), and `flutter analyze` passes with 0 errors. This is a pure cleanup change with no functional impact.

## Architect Scope Review

- **Scope adherence:** Compliant
- **Files modified:** As expected (4 modified, 2 deleted) — no deviations
- **Files off-limits:** Not touched — verified `SongSource.spotify` enum case, `Song.spotifyId` field, `song_link_detector.dart`, migrations, and `main.dart` remain unchanged

### Files Modified (Expected)

| File                                                                | Change Summary                                                                                                                      | Status        |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| `supabase/config.toml`                                              | Removed `[functions.spotify_search]` and `[functions.spotify_audio_features]` sections                                              | ✅ Verified   |
| `lib/features/setlists/setlist_repository.dart`                     | Removed `_fetchSpotifyBpm()`, `_attemptBpmEnrichment()`, fire-and-forget enrichment block, and `skipBackgroundEnrichment` parameter | ✅ Verified   |
| `lib/features/setlists/widgets/song_lookup_overlay.dart`            | Removed `skipBackgroundEnrichment: true,` argument                                                                                  | ✅ Verified   |
| `docs/features/remove-orphaned-spotify-functions/ARCHITECT_PLAN.md` | Formatting only (blank lines, escaped underscores)                                                                                  | ✅ Acceptable |

### Files Deleted (Expected)

| File                                          | Reason                                                | Status               |
| --------------------------------------------- | ----------------------------------------------------- | -------------------- |
| `supabase/functions/spotify_search/deno.json` | Dead edge function config                             | ✅ Confirmed deleted |
| `supabase/functions/spotify_search/index.ts`  | Dead edge function with broken `get_secrets` RPC call | ✅ Confirmed deleted |

### Off-Limits Files (Preserved)

| File/Element                                                                            | Verification                                     | Status                 |
| --------------------------------------------------------------------------------------- | ------------------------------------------------ | ---------------------- |
| `lib/features/songs/external_song_lookup_service.dart` — `SongSource.spotify` enum case | `grep -A3 "enum SongSource" ... \| grep spotify` | ✅ Present             |
| `lib/features/setlists/models/song.dart` — `Song.spotifyId` field                       | `grep -n "spotifyId" ...`                        | ✅ Present (3 matches) |
| `lib/features/setlists/links/song_link_detector.dart` — Spotify link detection          | `git diff` shows no changes                      | ✅ Not modified        |
| `lib/main.dart` — Initialization order                                                  | `git diff` shows no changes                      | ✅ Not modified        |
| `supabase/migrations/**/*.sql`                                                          | `git diff` shows no changes                      | ✅ Not modified        |

## Completeness Check

- **All Architect tasks implemented:** Yes
- **Missing tasks:** None

### Task Completion Matrix

| Task           | Description                                                                | Status                                |
| -------------- | -------------------------------------------------------------------------- | ------------------------------------- |
| Task 1         | Delete `supabase/functions/spotify_search/` directory                      | ✅ Complete                           |
| Task 2         | Remove `spotify_audio_features` config from `config.toml`                  | ✅ Complete                           |
| Task 2 (bonus) | Remove `spotify_search` config from `config.toml`                          | ✅ Complete (Engineer identified gap) |
| Task 3a        | Remove fire-and-forget enrichment block (~lines 3667-3682)                 | ✅ Complete                           |
| Task 3b        | Remove `skipBackgroundEnrichment` parameter from `upsertExternalSong`      | ✅ Complete                           |
| Task 3c        | Remove `_attemptBpmEnrichment` method                                      | ✅ Complete                           |
| Task 3d        | Remove `_fetchSpotifyBpm` method                                           | ✅ Complete                           |
| Task 4         | Remove `skipBackgroundEnrichment` argument from `song_lookup_overlay.dart` | ✅ Complete                           |
| Task 5         | Verify `flutter analyze` passes                                            | ✅ Complete (0 errors)                |
| Task 6         | Document completion (Engineer Report)                                      | ✅ Complete                           |

## Behavior Verification

- **Validation method:** Code-path analysis (runtime testing not performed)
- **Result:** Matches expected behavior

### Code-Path Analysis — Song Search Flow

**Expected behavior:** Song search uses iTunes (primary) → MusicBrainz (fallback), with no Spotify edge function invocation.

**Verified:**

1. `ExternalSongLookupService._performExternalSearch()` (lines 193-250) calls:
   - `_searchItunes()` first (line 209)
   - `_searchMusicBrainz()` as fallback (lines 221, 238)
   - **No call to any Spotify search function** ✅

2. Grep confirms no remaining references:
   - `spotify_search`: 0 matches in `lib/`
   - `spotify_audio_features`: 0 matches in `lib/`
   - `_attemptBpmEnrichment`: 0 matches in `lib/`
   - `_fetchSpotifyBpm`: 0 matches in `lib/`
   - `skipBackgroundEnrichment`: 0 matches in `lib/`

### Code-Path Analysis — Historical Data Display

**Expected behavior:** Legacy songs with `source = 'spotify'` in the database should display "Online" label without crashing.

**Verified:**

1. `SongSource.spotify` enum case preserved (line 14 of `external_song_lookup_service.dart`)
2. `sourceLabel` getter (lines 69-76) maps `SongSource.spotify` → `"Online"` ✅
3. `Song.spotifyId` field preserved (line 15 of `song.dart`) for backward compatibility ✅

### Code-Path Analysis — BPM Enrichment (GetSongBPM)

**Expected behavior:** BPM enrichment via GetSongBPM (unrelated to deleted Spotify functions) should remain functional.

**Verified:**

- No changes to GetSongBPM provider or enrichment paths outside the deleted fire-and-forget block
- The deleted `_attemptBpmEnrichment` method was confirmed dead (never executed due to `spotifyId` always being null)
- GetSongBPM enrichment flow (existing-song-enrichment feature, Phase 1/2) remains intact ✅

## Regression Check

- **Risk level:** LOW
- **Systems reviewed:** Setlists/Catalog (affected), Auth, Routing, RBAC, Notifications, Platform layers (unaffected)
- **Regressions found:** None

### System Impact Analysis

| System             | Impact       | Regression Risk | Notes                                                                             |
| ------------------ | ------------ | --------------- | --------------------------------------------------------------------------------- |
| Gigs               | Unaffected   | None            | No changes to gig domain                                                          |
| Rehearsals         | Unaffected   | None            | No changes to rehearsal domain                                                    |
| Setlists / Catalog | **Affected** | LOW             | Dead enrichment code removed; no functional change (path was already unreachable) |
| Members / RBAC     | Unaffected   | None            | No changes to member or permission logic                                          |
| Auth / Session     | Unaffected   | None            | No changes to auth flow or session management                                     |
| Routing            | Unaffected   | None            | No navigation changes                                                             |
| Notifications      | Unaffected   | None            | No changes to notification domain                                                 |
| Platform (all)     | Unaffected   | None            | Shared Dart code paths only; no platform-specific changes                         |

### Regression Risk Rationale

**Why LOW:**

1. **Only dead code deleted** — Zero active call paths removed (confirmed via grep and code-path analysis)
2. **No database changes** — Zero migrations, no schema changes, no RLS policy changes
3. **No initialization order changes** — `main.dart` not modified (GUARDRAILS.md rule #1)
4. **No service layer changes** — iTunes/MusicBrainz search untouched, GetSongBPM enrichment untouched
5. **Historical data preserved** — `SongSource.spotify` enum and `Song.spotifyId` field intact
6. **Clean static analysis** — `flutter analyze` returns 0 errors, 0 warnings
7. **Minimal diff surface** — 6 files changed, 348 lines deleted, 66 lines added (formatting only in ARCHITECT_PLAN.md)

**Potential edge case (already handled):**

- If any legacy database records have `source = 'spotify'`, they will continue to display correctly with "Online" label (verified in `sourceLabel` getter)

## Database Safety

**Not applicable** — This change does not affect the database.

- No migrations created or modified
- No RLS policies changed
- No RPC functions created, modified, or deleted (the broken `get_secrets` call was in edge function code, not SQL)
- No triggers affected
- No schema changes

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors, 0 warnings

```
Analyzing bandroadie...
No issues found! (ran in 4.3s)
```

**Re-verified:** 2026-08-09 after Engineer's additional `spotify_search` config cleanup

## Test Results

**Not run** — per Architect Plan Task 5, no tests required. The deleted code was never covered by tests, and no test file modifications were specified.

**Test coverage verification:**

```bash
find test/ -name "*.dart" -exec grep -l "spotify_audio_features|spotify_search|_attemptBpmEnrichment|_fetchSpotifyBpm|skipBackgroundEnrichment" {} \; 2>/dev/null
```

**Result:** 0 test files reference the deleted code ✅

## Diff Safety Review

- **Secrets:** None found ✅
- **Debug artifacts:** None found ✅
- **Unrelated changes:** None (ARCHITECT_PLAN.md formatting only — acceptable) ✅

### Detailed Scan Results

| Check                       | Command                                                                           | Result                                                                                    |
| --------------------------- | --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Secrets in diff             | `git diff HEAD \| grep -iE "(API_KEY\|SECRET\|PASSWORD\|TOKEN)"`                  | References to `get_secrets` only in documentation and deleted code — no actual secrets ✅ |
| Debug artifacts in new code | `git diff HEAD lib/ \| grep -E "^\+" \| grep -iE "(print\\(\|TODO\|FIXME\|HACK)"` | 0 matches — no debug code added ✅                                                        |
| Print statements            | `git diff HEAD lib/`                                                              | Only deletions (removed `debugPrint` calls from deleted methods) ✅                       |
| Commented code              | Visual inspection of diff                                                         | None ✅                                                                                   |
| Temporary flags             | Visual inspection of diff                                                         | None ✅                                                                                   |

### Diff Statistics

```
 docs/features/.../ARCHITECT_PLAN.md            |  93 +++++++++---- (formatting only)
 lib/features/setlists/setlist_repository.dart  | 151 -------------------- (deletions)
 .../widgets/song_lookup_overlay.dart           |   1 -                        (deletion)
 supabase/config.toml                           |   6 -                        (deletions)
 supabase/functions/spotify_search/deno.json    |   8 --                       (file deleted)
 supabase/functions/spotify_search/index.ts     | 155 --------------------- (file deleted)
 6 files changed, 66 insertions(+), 348 deletions(-)
```

**Analysis:** All changes are deletions or formatting. No new code added except whitespace in ARCHITECT_PLAN.md.

## Issues Found

**None**

---

## QA Pre-Deployment Test Results

All pre-deployment tests from the Architect Plan verification plan passed:

### PRE-DEPLOY TEST 1: spotify_search directory deleted

```bash
ls supabase/functions/ | grep spotify
```

**Result:** ✅ No matches

**Verification:**

```bash
test -d supabase/functions/spotify_search && echo "EXISTS" || echo "DELETED"
# Output: DELETED
```

### PRE-DEPLOY TEST 2: spotify_audio_features config removed

```bash
grep -n "spotify_audio_features" supabase/config.toml
```

**Result:** ✅ No matches

**Extended verification:**

```bash
grep -n "spotify" supabase/config.toml
```

**Result:** ✅ No matches (both `spotify_search` and `spotify_audio_features` configs removed)

### PRE-DEPLOY TEST 3: Dead methods removed from setlist_repository.dart

```bash
grep -n "_fetchSpotifyBpm\|_attemptBpmEnrichment" lib/features/setlists/setlist_repository.dart
```

**Result:** ✅ No matches

### PRE-DEPLOY TEST 4: skipBackgroundEnrichment parameter removed

```bash
grep -n "skipBackgroundEnrichment" lib/features/setlists/setlist_repository.dart
# Result: ✅ No matches

grep -n "skipBackgroundEnrichment" lib/features/setlists/widgets/song_lookup_overlay.dart
# Result: ✅ No matches
```

### PRE-DEPLOY TEST 5: flutter analyze passes

```bash
flutter analyze
```

**Result:** ✅ No issues found! (ran in 4.3s)

### PRE-DEPLOY TEST 6: Preserved elements still exist

```bash
# Confirm SongSource.spotify enum case still exists
grep -A3 "enum SongSource" lib/features/songs/external_song_lookup_service.dart | grep spotify
# Result: ✅ "enum SongSource { catalog, itunes, spotify, musicbrainz }"

# Confirm spotifyId field still exists in Song model
grep -n "spotifyId" lib/features/setlists/models/song.dart
# Result: ✅ 3 matches (field declaration, constructor, fromJson)
```

---

## Post-Deployment Testing Recommendations

**Note:** These tests require live device/browser verification, which cannot be performed by the QA agent. Tony must run these manually after merge and edge function undeployment.

### POST-DEPLOY TEST 1: Song search and add flow (iTunes → MusicBrainz)

**Steps:**

1. Open BandRoadie (any platform)
2. Navigate to any setlist
3. Tap "Add Song" → search for "Yellow Submarine Beatles"
4. Confirm: iTunes/MusicBrainz results appear (no errors in search overlay)
5. Add song to setlist
6. Confirm: Song appears in setlist and Catalog, no console errors

**Expected result:** Search works normally, no Spotify-related errors

### POST-DEPLOY TEST 2: BPM enrichment via GetSongBPM

**Steps:**

1. In new-song review screen, tap "Get BPM" button
2. Confirm: GetSongBPM lookup executes (existing enrichment flow, unrelated to Spotify)
3. Confirm: No references to `spotify_audio_features` or `_attemptBpmEnrichment` in debug logs

**Expected result:** BPM enrichment works via GetSongBPM, no Spotify code path invoked

### POST-DEPLOY TEST 3: Inline editing (BPM/Duration/Tuning)

**Steps:**

1. Open any setlist with existing songs
2. Tap BPM field on a song card → edit value → save
3. Tap Duration field → edit value → save
4. Tap Tuning field → change tuning → save
5. Confirm: All edits persist without errors

**Expected result:** Inline editing continues to work (unrelated to deleted code)

### POST-DEPLOY TEST 4: Historical data display

**Steps:**

1. If any legacy songs exist with `source = 'spotify'` in database (from pre-iTunes migration era):
   - Verify they display correctly with "Online" label
   - Verify they don't crash when rendered
2. If no legacy Spotify songs exist, skip this test

**Expected result:** Legacy Spotify songs render with "Online" label, no crashes

### POST-DEPLOY TEST 5: Edge functions undeployed (Tony only)

**Command:**

```bash
supabase functions list --project-ref nekwjxvgbveheooyorjo
```

**Expected result:** `spotify_search` and `spotify_audio_features` NOT in list

**Note:** This test can only be run after Tony manually undeploys the functions per the Engineer Report's post-merge instructions.

---

## QA Regression Areas — Coverage Summary

All regression areas specified in the Architect Plan were validated:

| Regression Area                                          | Validation Method  | Result                                                                                     |
| -------------------------------------------------------- | ------------------ | ------------------------------------------------------------------------------------------ |
| 1. Song search and add flow (iTunes → MusicBrainz)       | Code-path analysis | ✅ No Spotify errors (Spotify path deleted, iTunes/MusicBrainz paths intact)               |
| 2. Song creation from search overlay                     | Code analysis      | ✅ Songs still upserted to Catalog/setlist (no functional change to upsert logic)          |
| 3. BPM enrichment via GetSongBPM                         | Code analysis      | ✅ Unrelated to deleted code (GetSongBPM flow in existing-song-enrichment feature remains) |
| 4. Inline editing of BPM/Duration/Tuning                 | Code analysis      | ✅ No changes to inline editing methods                                                    |
| 5. Historical data display (legacy `source = 'spotify'`) | Code analysis      | ✅ `SongSource.spotify` → "Online" label preserved                                         |
| 6. `flutter analyze`                                     | Executed           | ✅ 0 errors, 0 warnings                                                                    |

**Runtime verification status:** Not performed (QA agent limitation). Post-deployment manual testing required for items 1-4 above.

---

## Post-Merge Manual Action Required

**Action owner:** Tony

After this branch is merged to `main`, the deployed edge functions must be manually undeployed from production:

```bash
supabase functions delete spotify_search --project-ref nekwjxvgbveheooyorjo
supabase functions delete spotify_audio_features --project-ref nekwjxvgbveheooyorjo
```

**Verification:**

```bash
supabase functions list --project-ref nekwjxvgbveheooyorjo
# Expected: spotify_search and spotify_audio_features NOT in list
```

**Note:** If undeployment is deferred, leaving the functions deployed is acceptable — both are JWT-protected, never invoked by the client, and will fail silently if somehow called due to the broken `get_secrets` RPC dependency.

---

## Branch and Working Tree Status

**Branch:** `bug/remove-orphaned-spotify-functions` ✅ Confirmed

**Working tree status:**

```
Changes not staged for commit:
  modified:   docs/features/remove-orphaned-spotify-functions/ARCHITECT_PLAN.md
  modified:   lib/features/setlists/setlist_repository.dart
  modified:   lib/features/setlists/widgets/song_lookup_overlay.dart
  modified:   supabase/config.toml
  deleted:    supabase/functions/spotify_search/deno.json
  deleted:    supabase/functions/spotify_search/index.ts

Untracked files:
  docs/features/chore-staging-ledger-repair/ (unrelated)
  docs/features/remove-orphaned-spotify-functions/ENGINEER_REPORT.md ✅
```

**Status:** ✅ Reviewable state — only expected feature changes present

---

## QA Agent Sign-Off

**Validated by:** QA Agent (GitHub Copilot)  
**Date:** 2026-08-09  
**Validation confidence:** HIGH (code-path analysis only; runtime verification pending post-deployment manual testing)

**Summary:** This implementation is a clean, scope-compliant deletion of dead code. All Architect tasks completed, all pre-deployment tests pass, zero regressions found in code-path analysis. The Engineer correctly preserved historical data elements and stayed within approved file boundaries. Ready for commit.

**Next steps:**

1. ✅ Review this QA report
2. ⏳ Commit changes to `bug/remove-orphaned-spotify-functions` branch
3. ⏳ Open PR for code review
4. ⏳ Merge to `main` after approval
5. ⏳ **[Tony only]** Manually undeploy edge functions from prod
6. ⏳ **[Tony only]** Run post-deployment smoke tests (song search, BPM enrichment, historical data display)
