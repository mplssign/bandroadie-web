# Engineer Report — Remove Orphaned Spotify Edge Functions

**Feature Slug:** `bug/remove-orphaned-spotify-functions`  
**Branch:** `bug/remove-orphaned-spotify-functions`  
**Engineer:** GitHub Copilot (Engineer Agent)  
**Date:** 2026-08-09  
**Status:** ✅ COMPLETE

---

## Summary

Successfully removed all dead Spotify enrichment code per the Architect Plan. All deletions were scoped precisely to the files and code blocks specified in the plan. No unrelated changes were made.

---

## Files Modified

### 1. `supabase/config.toml`

**Changes:**

- Removed `[functions.spotify_audio_features]` configuration section (originally ~lines 95-96)
- Removed `[functions.spotify_search]` configuration section (originally ~lines 92-93)

**Note:** The Architect Plan (Task 2) only specified removing the `spotify_audio_features` config entry. The `spotify_search` config removal was identified as a gap during the Manager's Implementation Gate review and added as a cleanup item. Since Task 1 deleted the entire `supabase/functions/spotify_search/` directory, its config stanza should also be removed for consistency.

**Verification:**

```bash
grep -n "spotify_audio_features" supabase/config.toml
# Result: no matches ✅

grep -n "spotify" supabase/config.toml
# Result: no matches ✅
```

### 2. `lib/features/setlists/setlist_repository.dart`

**Changes:**

- Removed fire-and-forget enrichment call block (~lines 3667-3682)
- Removed `skipBackgroundEnrichment` parameter from `upsertExternalSong` signature and docstring (~lines 3530, 3545)
- Removed entire `_attemptBpmEnrichment` method (~lines 4440-4538)
- Removed entire `_fetchSpotifyBpm` method (~lines 4540-4567)
- Removed "BPM ENRICHMENT (SPOTIFY)" section header comment

**Verification:**

```bash
grep -n "_fetchSpotifyBpm\|_attemptBpmEnrichment" lib/features/setlists/setlist_repository.dart
# Result: no matches ✅

grep -n "skipBackgroundEnrichment" lib/features/setlists/setlist_repository.dart
# Result: no matches ✅

grep -n "spotify_audio_features" lib/features/setlists/setlist_repository.dart
# Result: no matches ✅
```

### 3. `lib/features/setlists/widgets/song_lookup_overlay.dart`

**Change:** Removed `skipBackgroundEnrichment: true,` argument from `repo.upsertExternalSong()` call (~line 310).

**Verification:**

```bash
grep -n "skipBackgroundEnrichment" lib/features/setlists/widgets/song_lookup_overlay.dart
# Result: no matches ✅
```

---

## Files Deleted

### 1. `supabase/functions/spotify_search/` (entire directory)

**Reason:** Dead edge function with broken `get_secrets` RPC call, never invoked by client code.

**Verification:**

```bash
ls supabase/functions/ | grep spotify
# Result: no matches ✅
```

---

## Files Preserved (Intentionally NOT Modified)

Per the Architect Plan, the following elements were explicitly preserved for backward compatibility with historical data:

1. **`lib/features/songs/external_song_lookup_service.dart`**
   - `SongSource.spotify` enum case — used for displaying legacy songs whose stored `source` is `spotify`
   - Confirmed present ✅

2. **`lib/features/setlists/models/song.dart`**
   - `Song.spotifyId` field — persists historical Spotify IDs in database
   - Confirmed present ✅

---

## Verification — `flutter analyze`

```bash
flutter analyze
```

**Output:**

```
Analyzing bandroadie...
No issues found! (ran in 4.3s)
```

**Result:** ✅ 0 errors, 0 warnings

**Re-verified:** 2026-08-09 after additional `spotify_search` config cleanup

---

## Post-Merge Manual Action Required

**Action Owner:** Tony

The Engineer agent cannot undeploy edge functions from production. After this branch is merged to `main`, Tony must manually undeploy the orphaned edge functions from the production Supabase project:

```bash
# Via Supabase CLI
supabase functions delete spotify_search --project-ref nekwjxvgbveheooyorjo
supabase functions delete spotify_audio_features --project-ref nekwjxvgbveheooyorjo
```

**Note:** Leaving the deployed functions in production is acceptable if undeployment is deferred — both functions are JWT-protected, never invoked by the client, and will fail silently if somehow called due to the broken `get_secrets` RPC dependency.

**Verification (Tony only):**

```bash
supabase functions list --project-ref nekwjxvgbveheooyorjo
# Expected: spotify_search and spotify_audio_features NOT in list
```

---

## Pre-Deployment Test Results

All pre-deployment tests from the Architect Plan verification plan passed:

| Test                                       | Command                                                                                           | Result                 |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------- | ---------------------- |
| spotify_search directory deleted           | `ls supabase/functions/ \| grep spotify`                                                          | ✅ No matches          |
| spotify_audio_features config removed      | `grep -n "spotify_audio_features" supabase/config.toml`                                           | ✅ No matches          |
| spotify_search config removed              | `grep -n "spotify" supabase/config.toml`                                                          | ✅ No matches          |
| Dead methods removed                       | `grep -n "_fetchSpotifyBpm\|_attemptBpmEnrichment" lib/features/setlists/setlist_repository.dart` | ✅ No matches          |
| skipBackgroundEnrichment removed (repo)    | `grep -n "skipBackgroundEnrichment" lib/features/setlists/setlist_repository.dart`                | ✅ No matches          |
| skipBackgroundEnrichment removed (overlay) | `grep -n "skipBackgroundEnrichment" lib/features/setlists/widgets/song_lookup_overlay.dart`       | ✅ No matches          |
| flutter analyze passes                     | `flutter analyze`                                                                                 | ✅ No issues found!    |
| SongSource.spotify enum preserved          | `grep -A3 "enum SongSource" lib/features/songs/external_song_lookup_service.dart \| grep spotify` | ✅ Present             |
| Song.spotifyId field preserved             | `grep -n "spotifyId" lib/features/setlists/models/song.dart`                                      | ✅ Present (3 matches) |

---

## Regression Risk Assessment

**Risk Level:** LOW

**Rationale:**

- Only deleted provably dead code (zero active call paths)
- No database schema changes
- No RLS policy changes
- No initialization order changes
- No changes to actively used services (iTunes/MusicBrainz search, GetSongBPM enrichment remain untouched)
- All preserved elements (spotifyId field, SongSource.spotify enum) confirmed intact
- `flutter analyze` passed cleanly with zero warnings

**Post-Deployment Testing Recommended:**

1. Song search and add flow (iTunes → MusicBrainz) — confirm no errors
2. BPM enrichment via GetSongBPM (new-song review screen) — confirm still functional
3. Historical data display — if any legacy songs with `source = 'spotify'` exist, confirm they render correctly

---

## Compliance with Engineer Role

This implementation strictly adhered to the Engineer agent role defined in `docs/agents/ENGINEER.md`:

✅ Implemented only what was explicitly listed in `ARCHITECT_PLAN.md`  
✅ Modified only files listed in the plan  
✅ Created only files listed in the plan (this report)  
✅ Did not refactor, clean up, reformat, or fix unrelated code  
✅ Did not change database schema, migrations, config beyond what was specified  
✅ Did not commit, push, merge, or open PRs  
✅ No unlisted files were touched

---

## Next Steps

1. ✅ Review this report for accuracy
2. ✅ Commit changes to `bug/remove-orphaned-spotify-functions` branch
3. ⏳ Open PR for code review
4. ⏳ Merge to `main` after approval
5. ⏳ **[Tony only]** Manually undeploy `spotify_search` and `spotify_audio_features` from prod
6. ⏳ Run post-deployment smoke tests (song search, BPM enrichment, historical data display)

---

**Engineer Session Complete** — All tasks (1-6) executed successfully per Architect Plan.
