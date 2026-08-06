# Architect Plan — iTunes Search CORS Proxy

## Feature Slug

`bug/itunes-search-cors-proxy`

## Problem Summary

`ExternalSongLookupService._searchItunes()` calls the iTunes Search API directly from the client using `http.get()`. On Flutter Web, this executes as a browser `fetch()` call, which is subject to CORS (Cross-Origin Resource Sharing) restrictions. Apple's iTunes Search API is documented and designed for server/native consumption and does not reliably send `Access-Control-Allow-Origin` headers for arbitrary browser origins.

Every other external data source in BandRoadie (Spotify via `spotify_search`, MusicBrainz via `musicbrainz_search`) is proxied through a Supabase Edge Function to avoid this exact problem. iTunes is the one exception, making it vulnerable to CORS blocks on Web.

When iTunes fails (including CORS blocks), the `_performExternalSearch()` method silently falls back to MusicBrainz. Because MusicBrainz results lack BPM and album artwork, Web users may be unknowingly degraded to inferior results without any indication that iTunes was blocked.

Additionally, if both iTunes and MusicBrainz fail (network error, rate limit, outage), the outer catch block returns an empty list (`[]`), which is indistinguishable from a genuinely empty search result. Users see "no results" with no error state and no retry affordance.

## Root Cause

**Root Cause 1 — CORS Exposure (Web-specific)**

- Confidence: **HIGH** (confirmed in code)
- Location: `lib/features/songs/external_song_lookup_service.dart:216-262`
- `_searchItunes()` calls `http.get(Uri.https('itunes.apple.com', '/search', {...}))` directly from the client
- On Flutter Web, `http.get()` compiles to a browser `fetch()`, which enforces CORS
- iTunes Search API does not send CORS headers for arbitrary origins
- The request can be silently blocked by the browser, degrading results to MusicBrainz-only without user awareness
- Native platforms (iOS, macOS, Android) are not subject to CORS and work correctly, but use the same code path

**Root Cause 2 — Silent Double-Failure (All Platforms)**

- Confidence: **HIGH** (confirmed in code)
- Location: `lib/features/songs/external_song_lookup_service.dart:164-212`
- `_performExternalSearch()` has a top-level catch block that returns `[]` on any error
- If both iTunes and MusicBrainz fail (e.g., network outage, rate limiting, API downtime), the caller receives an empty list
- `song_lookup_overlay.dart:504-507` checks `_externalResults.isEmpty` but cannot distinguish between "no matches" and "search failed" because it does not check `_externalError` state
- No error UI is shown; no retry affordance is provided

## Reference Docs Consulted

None applicable — this is an implementation bug in client-side HTTP handling, not a domain-specific feature. The pattern to follow is established in `supabase/functions/musicbrainz_search/index.ts`.

## Existing System Analysis

**Current Flow (iTunes Direct Client-Side Call)**

1. User types a search query in the Song Lookup overlay
2. After 250ms debounce, `_onSearchChanged()` triggers `_searchExternal(query)`
3. `_searchExternal()` calls `searchExternalSongs()` on `ExternalSongLookupService`
4. `searchExternalSongs()` calls `_performExternalSearch()`, which:
   - Calls `_searchItunes(query, fetchLimit)` — **client-side HTTP GET to itunes.apple.com**
   - If iTunes succeeds, rank and return results
   - If iTunes fails or returns empty, fallback to `_searchMusicBrainz(query, fetchLimit)` — **calls Supabase Edge Function**
   - If MusicBrainz succeeds, rank and return results
   - If both fail, outer catch returns `[]`
5. Overlay receives results and updates UI

**Problem on Web:**

- Step 4 (iTunes call) can fail silently due to CORS block
- Fallback to MusicBrainz happens automatically, so user sees results but loses BPM and album artwork
- No indication that iTunes was blocked or degraded

**Problem on All Platforms:**

- If both iTunes and MusicBrainz fail in step 4, the user sees "No matching songs" with no way to distinguish error from empty result
- No retry button, no error message

**Existing Edge Functions (Established Pattern):**

- `supabase/functions/musicbrainz_search/index.ts` — proxies MusicBrainz API, adds CORS headers
- `supabase/functions/spotify_search/index.ts` — proxies Spotify API with token caching, adds CORS headers
- Both follow the same pattern: Deno serve, CORS preflight handling, fetch + reshape, structured JSON response

## Proposed Solution

**Change 1 — Create iTunes Search Edge Function**

- Create `supabase/functions/itunes_search/index.ts` following the `musicbrainz_search` pattern
- Accept `{ query: string, limit?: number }` as request body
- Fetch `https://itunes.apple.com/search?term=...&entity=song&limit=...` server-side (Deno)
- Return structured response: `{ ok: boolean, data?: Track[], error?: string }`
- Add CORS headers (`Access-Control-Allow-Origin: *`) so Web clients can call it
- No authentication required (iTunes Search API is free and public)

**Change 2 — Proxy iTunes Call Through Edge Function**

- Modify `_searchItunes()` in `external_song_lookup_service.dart` to call `_supabase.functions.invoke('itunes_search', body: {...})` instead of `http.get()`
- Parse the Edge Function response (same structure as MusicBrainz)
- Keep all existing ranking, scoring, and popularity logic unchanged
- This change makes iTunes work identically on all platforms (Web, iOS, macOS, Android) since the HTTP call now originates from the server

**Change 3 — Propagate Errors Instead of Swallowing Them**

- Modify `_performExternalSearch()` to throw or return a failure signal when both iTunes and MusicBrainz fail, instead of returning `[]`
- Option A (preferred): Throw an exception with a descriptive message
- Option B: Return a `Result<List<SongLookupResult>, String>` type (requires more refactoring)
- Use Option A for minimal diff

**Change 4 — Handle Error State in UI**

- Modify `song_lookup_overlay.dart` `_buildBody()` gate to check `_externalError == null` in addition to checking if results are empty
- This ensures that when an external search error exists, the UI displays the error banner (which already exists at lines 704-729) instead of the generic "no results" state
- The existing try-catch block in `_searchExternal()` already sets `_externalError` correctly when exceptions are thrown
- The error banner already has a retry button that re-triggers the search

**Guardrail Compliance:**

- No guitar/musical-instrument emoji in error messages (per Tony's standing override)
- No changes to files outside the specified scope
- No opportunistic cleanup
- Minimal diff surface

## Database Impact

**Not applicable.** No schema changes, RLS policies, RPCs, or triggers are involved. This is a client-side service refactor plus a new Edge Function.

## Flutter Architecture Changes

**State Management:**

- No new providers or controllers
- No changes to existing state structure
- `song_lookup_overlay.dart` already has `_externalError` state and the UI already renders error banners; the gate in `_buildBody()` just needs to check this state to let errors fall through correctly

**Widgets:**

- `song_lookup_overlay.dart`: modify `_buildBody()` gate condition to check `_externalError == null` so error states are displayed instead of the generic "no results" state
- No new widgets required

**Repositories:**

- No repository changes (this is a service, not a repository)

**Services:**

- `ExternalSongLookupService`: refactor `_searchItunes()` to call Edge Function, modify `_performExternalSearch()` to throw on total failure

## Files to Create

| File                                        | Justification                                                                                                                                                                                                          |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/functions/itunes_search/index.ts` | New Edge Function to proxy iTunes Search API server-side, avoiding CORS on Web. Follows the established pattern from `musicbrainz_search`. Required because iTunes is a third-party API not designed for browser CORS. |

## Files to Modify

| File                                                     | What Changes                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/songs/external_song_lookup_service.dart`   | 1. Refactor `_searchItunes()` (lines 216-262) to call `_supabase.functions.invoke('itunes_search', ...)` instead of `http.get()`. 2. Modify `_performExternalSearch()` (lines 164-212) to throw an exception when both iTunes and MusicBrainz fail, instead of returning `[]`. No changes to ranking, scoring, or caching logic.                                                                                                   |
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | 1. The existing try-catch in `_searchExternal()` (lines 191-236) already sets `_externalError` correctly—no changes needed there. 2. **Modify `_buildBody()` gate** (lines 504-507): add `&& _externalError == null` to the no-results condition so that when an external search error exists, the UI falls through to `_buildResultsList()` where the error banner is displayed (lines 703-732), instead of showing "no results". |

## Files Off-Limits

| File                                                                   | Reason                                                                                                                 |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                        | Init order must not change                                                                                             |
| `lib/features/songs/external_song_lookup_service.dart` (debounce code) | `_debounceTimer` and `cancelPendingSearch()` are dead code (never started). Explicitly out of scope per Feature Input. |
| `supabase/functions/spotify_search/index.ts`                           | Not involved in this fix. Spotify integration is not used by the current service.                                      |
| Any file not listed in "Files to Modify" or "Files to Create"          | Minimal diff surface — no opportunistic refactors                                                                      |

## System Impact Map

| System                                 | Impact                                                                                                                                                                                     |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Gigs                                   | unaffected                                                                                                                                                                                 |
| Rehearsals                             | unaffected                                                                                                                                                                                 |
| Setlists / Catalog                     | **affected** — Song lookup is how songs get added to setlists. iTunes results will now work correctly on Web (no CORS blocks). Error states will be surfaced to users.                     |
| Members / RBAC                         | unaffected                                                                                                                                                                                 |
| Auth / Session                         | unaffected                                                                                                                                                                                 |
| Routing                                | unaffected                                                                                                                                                                                 |
| Notifications                          | unaffected                                                                                                                                                                                 |
| Platform (iOS / Android / Web / macOS) | **Web is primary beneficiary** (CORS fix), but all platforms will use the new Edge Function proxy. Native platforms already work, but will continue to work identically through the proxy. |

## Regression Risk

**Level: LOW**

**Rationale:**

1. **Isolated scope**: Only changes song lookup service and its caller. No auth, session, routing, or init order changes.
2. **Proven pattern**: New Edge Function follows the exact pattern from `musicbrainz_search`, which is already in production.
3. **Additive error handling**: Error propagation improves UX by showing error states instead of hiding them. Does not break existing success paths.
4. **Single system affected**: Only Setlists/Catalog song lookup is touched. No cross-feature mutations.
5. **No database changes**: No migrations, RLS, or RPC changes that could cause data integrity issues.
6. **Web improvement, native unchanged**: Web gets a fix for CORS degradation. Native platforms (iOS, macOS, Android) continue to work as before (iTunes never failed on native due to lack of CORS enforcement).

**Risk areas to monitor:**

- Edge Function deployment and availability (if the new `itunes_search` function fails to deploy or is unreachable, iTunes searches will fail entirely instead of silently degrading)
- iTunes API rate limiting (now all requests come from the same Supabase IP; unlikely to be an issue given low traffic)

## Engineer Task Breakdown

**Task 1 — Create iTunes Search Edge Function**

1. Create `supabase/functions/itunes_search/index.ts`
2. Copy structure from `musicbrainz_search/index.ts` as the template
3. Implement:
   - CORS headers (preflight + all responses)
   - Request body parsing: `{ query: string, limit?: number }`
   - Input validation: query must be non-empty, limit defaults to 10, max 25
   - Server-side fetch to `https://itunes.apple.com/search?term={query}&entity=song&limit={limit}`
   - Parse iTunes response: extract `results` array
   - Reshape each track to match expected format:
     ```typescript
     {
       title: track['trackName'],
       artist: track['artistName'],
       duration_seconds: Math.round(track['trackTimeMillis'] / 1000),
       album_artwork: track['artworkUrl100'],
       itunes_id: track['trackId']
     }
     ```
   - Return `{ ok: true, data: tracks }` on success
   - Return `{ ok: false, error: string }` on failure
4. Test locally with `supabase functions serve itunes_search`
5. Verify CORS headers are present in responses

**Task 2 — Refactor `_searchItunes()` to Use Edge Function**

1. Open `lib/features/songs/external_song_lookup_service.dart`
2. Locate `_searchItunes()` method (lines 216-262)
3. Replace the `http.get(uri)` call with:
   ```dart
   final response = await _supabase.functions.invoke(
     'itunes_search',
     body: {'query': query, 'limit': limit},
   );
   ```
4. Replace the response parsing:
   - Check `response.status != 200` → throw exception
   - Parse `response.data`: check `data['ok'] != true` → throw exception
   - Extract `data['data']` as the results list
5. Keep all existing popularity scoring and result mapping logic unchanged
6. Remove `import 'package:http/http.dart' as http;` if no longer used (check if `_searchMusicBrainz` still uses it — it doesn't, it uses Edge Function)

**Task 3 — Propagate Errors from `_performExternalSearch()`**

1. Locate `_performExternalSearch()` method (lines 164-212)
2. Find the outer `catch (e)` block that currently returns `[]` (line 209)
3. Replace `return [];` with `rethrow;` to propagate the exception to the caller
4. Ensure both the iTunes and MusicBrainz catch blocks also rethrow (or let exceptions bubble up naturally)

**Task 4 — Handle Errors in Song Lookup Overlay**

1. Open `lib/features/setlists/widgets/song_lookup_overlay.dart`
2. Locate `_searchExternal()` method (lines 191-236)
3. The existing try-catch block already sets `_externalError` on catch (lines 226-234) — no changes needed here
4. Locate `_buildBody()` method (lines 490-511)
5. Find the no-results gate condition (lines 504-507):
   ```dart
   if (_filteredSongs.isEmpty &&
       _externalResults.isEmpty &&
       !_isSearchingExternal) {
     return _buildNoResultsState();
   }
   ```
6. Modify the condition to also check `_externalError == null`:
   ```dart
   if (_filteredSongs.isEmpty &&
       _externalResults.isEmpty &&
       !_isSearchingExternal &&
       _externalError == null) {
     return _buildNoResultsState();
   }
   ```
7. This ensures that when an external error exists, the UI falls through to `_buildResultsList()` (which displays the error banner at lines 703-732) instead of showing the generic "no results" state
8. Verify the error banner displays correctly with the retry button that calls `_searchExternal(_searchController.text)`

**Task 5 — Test End-to-End**

1. Deploy Edge Function: `supabase functions deploy itunes_search`
2. Run app on Web: `flutter run -d chrome`
3. Open Song Lookup overlay
4. Search for a known track (e.g., "Bohemian Rhapsody")
5. Verify iTunes results appear with album artwork and duration
6. Open DevTools → Network tab, confirm no CORS errors
7. Simulate Edge Function failure (disconnect network or use invalid endpoint temporarily) and verify error state displays with retry button
8. Run app on native (macOS): `flutter run -d macos`
9. Verify song lookup still works identically

**Task 6 — Run `flutter analyze`**

1. Run `flutter analyze` and confirm 0 errors
2. Fix any new warnings introduced by changes (if any)

## Verification Plan

### Tier 1 — Pre-deployment (Run Before Edge Function Deploy)

Not applicable. This fix is entirely client-side service refactor + new Edge Function. There are no existing database objects to test. All verification happens post-deploy.

### Tier 2 — Post-deployment (Run After Edge Function Deploy)

**POST-DEPLOY TEST 1: Verify Edge Function Exists and Responds**

```bash
# Verify the itunes_search function is deployed
curl -X POST \
  https://[PROJECT_REF].supabase.co/functions/v1/itunes_search \
  -H "Authorization: Bearer [ANON_KEY]" \
  -H "Content-Type: application/json" \
  -d '{"query": "Bohemian Rhapsody", "limit": 5}'

# Expected: HTTP 200, JSON response with { ok: true, data: [...] }
# Confirm 'data' array contains tracks with title, artist, duration_seconds, album_artwork
```

**POST-DEPLOY TEST 2: Verify CORS Headers**

```bash
# OPTIONS preflight
curl -X OPTIONS \
  https://[PROJECT_REF].supabase.co/functions/v1/itunes_search \
  -H "Origin: https://bandroadie.com" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type" \
  -v

# Expected: HTTP 200, headers include:
#   Access-Control-Allow-Origin: *
#   Access-Control-Allow-Headers: authorization, x-client-info, apikey, content-type
```

**POST-DEPLOY TEST 3: Web Client CORS Validation**

1. Open `https://app.bandroadie.com` in Chrome
2. Open DevTools → Console and Network tabs
3. Navigate to a setlist, tap "Add Song"
4. Search for "Bohemian Rhapsody"
5. Check Network tab for request to `/functions/v1/itunes_search`
6. Confirm:
   - Request completes with HTTP 200
   - No CORS errors in Console
   - Results display with album artwork (iTunes provides artwork, MusicBrainz does not)

**POST-DEPLOY TEST 4: Error State Display**

1. In the app (Web), open Song Lookup overlay
2. Temporarily disconnect network (DevTools → Network → Offline)
3. Search for any query
4. Confirm:
   - After search completes, error message displays: "External search failed"
   - Retry button is visible and functional
5. Reconnect network, tap Retry
6. Confirm results load correctly

**POST-DEPLOY TEST 5: Native Platform Parity**

1. Run app on macOS: `flutter run -d macos`
2. Open Song Lookup overlay
3. Search for "Bohemian Rhapsody"
4. Confirm results display identically to Web (same tracks, same artwork, same duration)
5. Verify no regressions in native behavior

**POST-DEPLOY TEST 6: Empty Result vs. Error Distinction**

1. Search for a nonsense query that will return no results (e.g., "xyzabc123nonexistent")
2. Confirm: "No matching songs" empty state displays (not an error state)
3. Simulate network failure (disconnect or block supabase.co in hosts file)
4. Search again
5. Confirm: Error state displays with retry button (distinguishable from empty results)

## QA Regression Areas

**Primary Test Area — Song Lookup (All Platforms)**

1. Open Song Lookup overlay from any setlist
2. Search for common tracks (e.g., "Bohemian Rhapsody", "Hotel California", "Sweet Child O' Mine")
3. Verify results include:
   - iTunes results with album artwork
   - Correct artist, title, duration
   - Results are ranked sensibly (exact matches first)
4. Tap a result to add to setlist
5. Verify song is added successfully and appears in the setlist

**Web-Specific Testing — CORS Verification**

1. Open `app.bandroadie.com` in Chrome (not localhost)
2. Open DevTools → Network and Console tabs
3. Perform song searches
4. Verify:
   - No CORS errors in Console
   - Requests to `/functions/v1/itunes_search` complete successfully
   - Album artwork loads correctly (indicates iTunes results, not MusicBrainz degradation)

**Error Handling — Network Failures**

1. On Web, use DevTools → Network → Offline mode
2. On native, disconnect WiFi
3. Perform a song search
4. Verify:
   - Error state displays clearly
   - Retry button is present and functional
   - After reconnecting and retrying, results load correctly

**Regression Testing — Other Search Scenarios**

1. Search for an artist name only (e.g., "Queen")
2. Search for a partial title (e.g., "Bohemian")
3. Search for songs already in the Catalog
4. Verify:
   - Catalog results appear in "In Catalog" section
   - External results appear in "External Results" section
   - No duplicates between sections

**Platform Parity Testing**

1. Perform identical searches on Web, iOS (if available), and macOS
2. Verify results are consistent across platforms
3. Verify no regressions on native platforms (song lookup worked before on native, should continue to work identically)

## Rollout / Migration Strategy

**Not applicable.** This is a bug fix with no schema changes. Rollout is standard:

1. Deploy Edge Function: `supabase functions deploy itunes_search`
2. Verify Edge Function is reachable via Tier 2 tests
3. Deploy client code to Web: `./tools/deploy_web.sh`
4. Monitor for errors in Sentry or Supabase logs
5. If Edge Function fails to deploy or is unreachable, roll back client changes (but this is unlikely — Edge Functions are deployed independently and have high uptime)

**Rollback Plan:**

- If the new Edge Function fails, the outer catch in `_performExternalSearch()` will now throw an error instead of silently degrading. This means song searches will show error states instead of silently returning MusicBrainz-only results.
- If this is deemed worse than silent degradation, revert the client changes (Task 2 and Task 3) to restore the old behavior while investigating the Edge Function issue.
- Edge Functions are independently versioned and can be redeployed without client changes.

## Out of Scope

**Explicitly excluded from this fix:**

1. **Debounce timer dead code**: `_debounceTimer` and `cancelPendingSearch()` in `external_song_lookup_service.dart` are never started. Do not touch this code.
2. **Spotify integration**: A `spotify_search` Edge Function exists but is not currently used by the service. Do not integrate Spotify as part of this fix.
3. **Search ranking algorithm changes**: The existing popularity scoring and ranking logic in `_rankResults()` should remain unchanged.
4. **UI redesign**: The overlay layout and styling are out of scope. Only add error handling logic, do not change the visual design.
5. **MusicBrainz proxy verification**: MusicBrainz is already proxied and works correctly. Do not modify `_searchMusicBrainz()`.
6. **Caching behavior**: The 5-minute in-memory cache (`_CacheEntry`) should remain unchanged.
7. **Background enrichment**: The feature input mentions "no album artwork" from MusicBrainz, but background enrichment via AcousticBrainz or other services is out of scope for this fix.

---

**End of Architect Plan**
