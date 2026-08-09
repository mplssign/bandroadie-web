# Feature: Remove Orphaned Spotify Edge Functions

## Feature Slug
`bug/remove-orphaned-spotify-functions`

## Problem Summary
Two Supabase edge functions in production — `spotify_search` (v21) and `spotify_audio_features` (v20) — both call a non-existent RPC function `supabase.rpc('get_secrets', { secret_names: [...] })` to retrieve Spotify API credentials. This RPC has never existed in the database (confirmed via direct `pg_proc` query against prod project `nekwjxvgbveheooyorjo` — only `create_secret` and `update_secret` exist, no `get_secrets` was ever migrated).

Both functions are confirmed **dead code**, not live bugs:

1. **`spotify_search`** — Never invoked by the client. The song lookup flow (`ExternalSongLookupService._performExternalSearch`) only calls `itunes_search` then falls back to `musicbrainz_search`. No Dart code references `spotify_search`. Edge function logs from prod (24h sample) show zero invocations.

2. **`spotify_audio_features`** — The folder `supabase/functions/spotify_audio_features/` does not exist in the codebase (already deleted or never created), but references remain in:
   - `supabase/config.toml` line 95 (`[functions.spotify_audio_features]`)
   - `lib/features/setlists/setlist_repository.dart` line 4566 (invoke call in `_fetchSpotifyBpm`)
   - Multiple documentation files

   The call path is dead: `_fetchSpotifyBpm` is only called from `_attemptBpmEnrichment` when `spotifyId != null`, but per an existing code comment at line 3670, "spotifyId is always null on this path." BPM enrichment today uses GetSongBPM provider (Phase 1/2, already shipped), not Spotify.

This is tech-debt cleanup, not a user-facing incident. No migrations, cron jobs, or SQL reference either function or `get_secrets`.

## Root Cause
**Confidence Level:** HIGH (confirmed in code)

The immediate cause is a non-existent RPC `get_secrets` that both functions attempt to call. However, the deeper root cause is that both functions are obsolete:

- `spotify_search` was superseded when iTunes/MusicBrainz became the search provider (PR #127, commit `c69e41c`, ~Dec 2025)
- `spotify_audio_features` was superseded when GetSongBPM became the BPM enrichment provider (existing-song-enrichment feature, Phase 1/2 shipped)

The functions were deployed but never undeployed when the client code migrated away. The broken `get_secrets` call prevents them from running if ever invoked, but they are never invoked, making this a silent dead-code issue rather than a runtime failure.

## Reference Docs Consulted
- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `.github/copilot-instructions.md` (BandRoadie project conventions)

*Note:* No notification-specific reference docs were consulted; this feature does not involve the notification domain.

## Existing System Analysis

### Current Data Flow (Dead Paths)

**Path 1: `spotify_search` (never invoked)**
```
User searches for song
  → ExternalSongLookupService.searchExternalSongs()
    → _performExternalSearch()
      → _searchItunes() [first attempt]
      → _searchMusicBrainz() [fallback, no Spotify]
```
**Result:** `spotify_search` edge function is deployed but unreachable from client code.

**Path 2: `spotify_audio_features` (call path exists but spotifyId always null)**
```
User adds song from search overlay
  → SetlistRepository.upsertExternalSong()
    → (if bpm == null && !skipBackgroundEnrichment)
      → _attemptBpmEnrichment(spotifyId: spotifyId)  // spotifyId always null
        → (if spotifyId != null) _fetchSpotifyBpm()  // never executes
          → supabase.functions.invoke('spotify_audio_features') // never reached
```
**Result:** The `_attemptBpmEnrichment` method always returns early without updating anything because `spotifyId` is always null and no BPM is found.

### Confirmed Dead Code Elements

1. **`supabase/functions/spotify_search/index.ts`** — Deployed in prod, never called
2. **`spotify_audio_features` config in `supabase/config.toml`** — References non-existent function folder
3. **`SetlistRepository._fetchSpotifyBpm()`** — Private method, never executes (spotifyId always null)
4. **`SetlistRepository._attemptBpmEnrichment()`** — Private method, always returns early without effect
5. **`upsertExternalSong.skipBackgroundEnrichment` parameter** — Only used to gate the dead _attemptBpmEnrichment call

### Not Dead (Historical Data / Display)

- **`SongSource.spotify` enum case** — Used in switch statement for displaying legacy songs whose stored `source` is `spotify` (pre-iTunes migration data). Maps to generic "Online" label.
- **`Song.spotifyId` field** — Persists historical data. Keep for backward compatibility.
- **`spotifyId` parameters** — Threaded through `upsertExternalSong`, `_attemptBpmEnrichment`. Currently always null, but harmless to keep as pass-through for historical context.

## Proposed Solution

### Minimal Deletion

**Delete entire directory:**
1. `supabase/functions/spotify_search/` (edge function with broken `get_secrets` call)

**Modify existing files (remove dead code):**
1. `supabase/config.toml` — Remove `[functions.spotify_audio_features]` section (lines ~95-96)
2. `lib/features/setlists/setlist_repository.dart`:
   - Remove entire `_fetchSpotifyBpm()` method (~lines 4559-4594)
   - Remove entire `_attemptBpmEnrichment()` method (~lines 4481-4556)
   - Remove fire-and-forget enrichment call block (~lines 3667-3682)
   - Remove `skipBackgroundEnrichment` parameter from `upsertExternalSong` signature (~line 3545) and docstring (~line 3530)
3. `lib/features/setlists/widgets/song_lookup_overlay.dart`:
   - Remove `skipBackgroundEnrichment: true,` argument from `repo.upsertExternalSong()` call (~line 310)

### Preserve for Historical Data

Do NOT remove:
- `SongSource.spotify` enum case (used for display of legacy search results)
- `Song.spotifyId` field (persists historical Spotify IDs)
- `spotifyId` parameters in `upsertExternalSong` (currently unused but harmless, may support future migrations)

### Post-Merge Manual Action (Tony)

The Engineer cannot undeploy edge functions. After merge, Tony must manually undeploy from prod:
```bash
# Via Supabase Dashboard or CLI
supabase functions delete spotify_search --project-ref nekwjxvgbveheooyorjo
supabase functions delete spotify_audio_features --project-ref nekwjxvgbveheooyorjo
```

Leaving deployed functions in prod is acceptable if Tony confirms — they are never invoked, JWT-protected, and will fail silently if somehow called.

## Database Impact

**Database:** Not applicable

- No migrations required (no schema changes)
- No RLS policies affected
- No RPC functions created, modified, or deleted (the broken `get_secrets` call is in edge function code, not SQL)
- No triggers affected

This is purely a client-side Dart cleanup + edge function source deletion + config cleanup.

## Flutter Architecture Changes

### Repositories
- **`SetlistRepository`** — Remove two private methods (`_fetchSpotifyBpm`, `_attemptBpmEnrichment`) and one unused parameter (`skipBackgroundEnrichment`)

### Widgets
- **`SongLookupOverlay`** — Remove one unused argument in `upsertExternalSong` call

### State Management
- No Riverpod providers affected
- No controllers affected

### Models
- No changes to `Song`, `SongLookupResult`, or any other model

## Files to Create

**None.** This is a pure deletion/cleanup change.

## Files to Modify

| File | Description of Changes |
|------|------------------------|
| `supabase/config.toml` | Remove `[functions.spotify_audio_features]` section and `verify_jwt = true` line (~lines 95-96) |
| `lib/features/setlists/setlist_repository.dart` | (1) Remove `_fetchSpotifyBpm` method (~lines 4559-4594); (2) Remove `_attemptBpmEnrichment` method (~lines 4481-4556); (3) Remove fire-and-forget enrichment block (~lines 3667-3682); (4) Remove `skipBackgroundEnrichment` parameter from `upsertExternalSong` signature (~line 3545) and docstring (~line 3530) |
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | Remove `skipBackgroundEnrichment: true,` line (~line 310) from `repo.upsertExternalSong()` call |

**Files to delete:**
| Path | Reason |
|------|--------|
| `supabase/functions/spotify_search/` (entire directory) | Dead edge function with broken `get_secrets` RPC call, never invoked by client |

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/features/songs/external_song_lookup_service.dart` | Do not remove `SongSource.spotify` enum case — used for displaying legacy data |
| `lib/features/setlists/models/song.dart` | Do not remove `spotifyId` field — persists historical Spotify IDs |
| `supabase/migrations/**/*.sql` | No database changes required |
| `docs/**/*.md` | Do not modify documentation as part of this cleanup — doc updates are out of scope |
| `android/app/src/main/assets/**/*.js` | Compiled artifacts — will be regenerated on next build |
| `lib/main.dart` | Initialization order must not change |

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — dead Spotify enrichment code removed from song creation path; no functional change (path was already dead) |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | unaffected — all platforms use the same shared Dart code path |

## Regression Risk

**Level:** LOW

**Rationale:**
- Only deleting provably dead code — no live call paths affected
- No database schema changes
- No RLS policy changes
- No initialization order changes
- No changes to any actively used service layer (iTunes/MusicBrainz search, GetSongBPM enrichment remain untouched)
- The `spotifyId` field and `SongSource.spotify` enum case are preserved for historical data display
- After deletion, `flutter analyze` should pass cleanly (three simple unused-parameter removals + two method deletions + one directory deletion)

The only risk is if there exists an undiscovered code path that somehow passes a non-null `spotifyId` to `upsertExternalSong`, but:
1. Grep confirms no Dart code constructs a `SongLookupResult` with `source: SongSource.spotify`
2. The only place `spotifyId` is set on `SongLookupResult` is in `external_song_lookup_service.dart`, where it's always null (iTunes/MusicBrainz results don't populate it)
3. The code comment at line 3670 explicitly documents "spotifyId is always null on this path"

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Delete `spotify_search` Edge Function
- Delete the entire directory: `supabase/functions/spotify_search/`
- Confirm deletion: `ls supabase/functions/` should not list `spotify_search/`

### Task 2: Remove `spotify_audio_features` Config
- Open `supabase/config.toml`
- Delete lines ~95-96:
  ```toml
  [functions.spotify_audio_features]
  verify_jwt = true
  ```
- Confirm: search file for "spotify_audio_features" returns zero matches

### Task 3: Remove Dead Code from `setlist_repository.dart`
In order (to avoid orphaned references):

**3a. Remove fire-and-forget enrichment call block (~lines 3667-3682)**
- Delete the entire `if (bpm == null && !skipBackgroundEnrichment) { ... }` block
- Keep the `return newId;` statement immediately after
- Confirm: `_attemptBpmEnrichment` is no longer called from this file

**3b. Remove `skipBackgroundEnrichment` parameter (~lines 3530, 3545)**
- Remove from `upsertExternalSong` method signature (change `bool skipBackgroundEnrichment = false,` → remove entire line)
- Remove from method docstring (delete the `/// [skipBackgroundEnrichment] - ...` line)
- Confirm: grep for "skipBackgroundEnrichment" in this file returns zero matches

**3c. Remove `_attemptBpmEnrichment` method (~lines 4481-4556)**
- Delete the entire method including docstring
- Confirm: search file for "_attemptBpmEnrichment" returns zero matches

**3d. Remove `_fetchSpotifyBpm` method (~lines 4559-4594)**
- Delete the entire method including docstring
- Confirm: search file for "_fetchSpotifyBpm" returns zero matches
- Confirm: search file for "spotify_audio_features" returns zero matches

### Task 4: Remove `skipBackgroundEnrichment` Argument from Call Site
- Open `lib/features/setlists/widgets/song_lookup_overlay.dart`
- Find the `repo.upsertExternalSong(...)` call (~line 300-311)
- Remove the line: `skipBackgroundEnrichment: true,`
- Confirm: search file for "skipBackgroundEnrichment" returns zero matches

### Task 5: Verify Clean Build
- Run: `flutter analyze`
- Confirm: 0 errors, 0 warnings
- If unused import warnings appear (unlikely), remove them
- Do NOT run `flutter test` — no test changes required (deleted code was never tested)

### Task 6: Document Completion
- Create `docs/features/remove-orphaned-spotify-functions/ENGINEER_REPORT.md`
- List all modified/deleted files
- Confirm `flutter analyze` output
- Note: Edge function undeployment is a post-merge manual action for Tony

## Verification Plan

### Tier 1 — Pre-deployment (must pass before commit)

**PRE-DEPLOY TEST 1: Confirm spotify_search directory deleted**
```bash
ls supabase/functions/ | grep spotify
# Expected: no output (or only spotify_search if deletion not yet done)
# After deletion: zero matches for "spotify_search"
```

**PRE-DEPLOY TEST 2: Confirm spotify_audio_features config removed**
```bash
grep -n "spotify_audio_features" supabase/config.toml
# Expected: no matches
```

**PRE-DEPLOY TEST 3: Confirm dead methods removed from setlist_repository.dart**
```bash
grep -n "_fetchSpotifyBpm\|_attemptBpmEnrichment" lib/features/setlists/setlist_repository.dart
# Expected: no matches
```

**PRE-DEPLOY TEST 4: Confirm skipBackgroundEnrichment parameter removed**
```bash
grep -n "skipBackgroundEnrichment" lib/features/setlists/setlist_repository.dart
# Expected: no matches

grep -n "skipBackgroundEnrichment" lib/features/setlists/widgets/song_lookup_overlay.dart
# Expected: no matches
```

**PRE-DEPLOY TEST 5: Confirm flutter analyze passes**
```bash
flutter analyze
# Expected: "No issues found!" (or 0 errors, 0 warnings)
```

**PRE-DEPLOY TEST 6: Confirm preserved elements still exist**
```bash
# Confirm SongSource.spotify enum case still exists (line ~14)
grep -n "enum SongSource" lib/features/songs/external_song_lookup_service.dart
grep -A3 "enum SongSource" lib/features/songs/external_song_lookup_service.dart | grep spotify

# Confirm spotifyId field still exists in Song model
grep -n "spotifyId" lib/features/setlists/models/song.dart

# Expected: Both should return matches (these must NOT be deleted)
```

### Tier 2 — Post-deployment (run after merge + manual edge function undeployment)

**POST-DEPLOY TEST 1: Confirm song creation still works (iTunes/MusicBrainz path)**
1. Open BandRoadie (any platform)
2. Navigate to any setlist
3. Tap "Add Song" → search for "Yellow Submarine Beatles"
4. Confirm: iTunes/MusicBrainz results appear (no errors)
5. Add song to setlist
6. Confirm: Song appears in setlist, no errors in console

**POST-DEPLOY TEST 2: Confirm BPM enrichment path (GetSongBPM) still works**
1. In new-song review screen, tap "Get BPM" button
2. Confirm: GetSongBPM lookup executes (existing enrichment flow, unrelated to Spotify)
3. Confirm: No references to Spotify in debug logs

**POST-DEPLOY TEST 3: Confirm edge functions undeployed (Tony only)**
```bash
# Via Supabase CLI or Dashboard
supabase functions list --project-ref nekwjxvgbveheooyorjo
# Expected: spotify_search and spotify_audio_features NOT in list
```

**POST-DEPLOY TEST 4: Smoke test existing setlists**
1. Open an existing setlist with songs
2. Reorder songs (drag & drop)
3. Edit BPM/Duration inline
4. Confirm: All existing functionality works, no console errors

## QA Regression Areas

QA must explicitly validate:

1. **Song search and add flow (primary)** — Confirm iTunes → MusicBrainz search still works, no Spotify errors
2. **Song creation** — Add new songs from search overlay, confirm they appear in Catalog and setlist
3. **BPM enrichment (GetSongBPM)** — Confirm existing enrichment flow still works (new-song review screen "Get BPM" button)
4. **Inline editing** — Confirm BPM/Duration/Tuning edits still work on existing songs
5. **Historical data display** — If any legacy songs exist with `source = 'spotify'` in the database, confirm they still display correctly (should show "Online" label, not crash)
6. **Cross-platform** — Test on iOS, Android, Web, macOS (same Dart code path, but confirm no platform-specific issues)

## Rollout / Migration Strategy

**Not applicable.** This is a pure deletion change with no database migration, no user-facing feature change, and no rollback complexity.

**Post-merge action required (Tony):**
- Manually undeploy `spotify_search` and `spotify_audio_features` from prod Supabase project `nekwjxvgbveheooyorjo`
- Confirm undeployment via `supabase functions list` or Dashboard
- If undeployment fails or is deferred, confirm with Tony that leaving stale deployed functions (never called, JWT-protected) is acceptable

## Out of Scope

Explicitly NOT included in this feature:

1. **Documentation updates** — Do not modify any `.md` files in `docs/` (many reference `spotify_audio_features` and broken architecture; updating them is a separate docs-debt task)
2. **Removing `SongSource.spotify` enum case** — Keep for displaying legacy historical data
3. **Removing `Song.spotifyId` field** — Keep for backward compatibility with existing database records
4. **Removing `spotifyId` database column** — Out of scope (would require migration + data validation)
5. **Broader Spotify reference cleanup** — If other dormant Spotify-related code paths exist elsewhere, they are not addressed here
6. **Compiled artifacts in `android/app/src/main/assets/`** — Will be regenerated on next build, do not manually edit
7. **Test file changes** — The deleted code was never covered by tests; no test updates required

---

**Summary:** Delete two dead edge functions (one folder, one config), remove five dead Dart code elements (two methods, one parameter, one call site, one argument), preserve historical data fields. Zero functional impact — all deleted code was already unreachable.
