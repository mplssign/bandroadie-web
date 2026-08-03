# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/song-details-enrichment-no-db-write`

---

## 2. Problem Summary

Running Song Details → `Enrich Song Data` on production song `625e82c1-f56c-4dfc-bba7-0148eb8dedc1` (`American Girl` / `Tom Petty`, band `003be463-e63a-4ec5-b152-4f64c60afcbf`) completes the flow without writing `musical_key` to `songs`.

The failure is not the previously fixed `update_song_metadata` false-success path. For this song, only `musical_key` is eligible for enrichment (`bpm = 89`, `duration_seconds = 213`, `musical_key = NULL`), and the current lookup path returns no usable key for the stored artist string. Because no key is returned, the client never calls the RPC, so the database row remains unchanged.

There is also a smaller UI bug: the results modal always presents the run as `Enrichment Complete`, even when nothing was updated and the only outcome was `notFound`. That wording made this provider-side miss look like a silent persistence failure.

---

## 3. Root Cause

**Primary root cause:** `getsongbpm_lookup` uses an overly strict artist-match gate for title+artist lookups. It requires a normalized exact artist-name match, so the stored artist `Tom Petty` returns `confidence: 'none'`, while the fuller canonical credit `Tom Petty and the Heartbreakers` returns a valid result.

**Confidence:** `HIGH`

**Confirmed evidence from this session:**

- Production row inspection:
  - `songs.id = 625e82c1-f56c-4dfc-bba7-0148eb8dedc1`
  - `bpm = 89`
  - `duration_seconds = 213`
  - `musical_key = NULL`
  - `updated_at = 2026-04-12 13:35:05.885943+00`
- Live production Edge Function invocation with stored metadata:
  - `{"title":"American Girl","artist":"Tom Petty","duration_seconds":213}`
  - Response: `{"ok":true,"data":{"bpm":null,"musicalKey":null,"confidence":"none"}}`
- Live production Edge Function invocation with fuller artist credit:
  - `{"title":"American Girl","artist":"Tom Petty and the Heartbreakers","duration_seconds":213}`
  - Response: `{"ok":true,"data":{"bpm":114,"musicalKey":"A","confidence":"medium"}}`
- `SongEnrichmentOrchestrator.enrichSongs()` only calls `SetlistRepository.enrichSongs()` when `updateMap.isNotEmpty`.
- With `fetchedKey == null`, `updateMap` stays empty, so no RPC is attempted and no DB write can occur.
- The live production `update_song_metadata(...)` definition includes the 2026-08-01 eligibility-aware verification fix, so this specific failure is upstream of the RPC.

**Secondary root cause:** `lib/features/songs/widgets/enrichment_results_overlay.dart` always titles the modal `Enrichment Complete`, even when `result.enriched == 0` and the run produced only `notFound` outcomes.

**Confidence:** `HIGH`

**Classification:**

- `update_song_metadata` regression: `NO`
- distinct bug in the same RPC: `NO`
- lookup/fetch layer bug: `YES` (`getsongbpm_lookup` artist matching)
- minimal UI copy bug: `YES` (`enrichment_results_overlay.dart`)

**Note on logs:** direct Edge Function / Postgres service logs were not exposed through the available toolset in this session, so diagnosis used production read-only SQL plus live production function invocation against the exact song metadata. Confidence remains high because the alternate-artist invocation reproduces the success path immediately.

---

## 4. Reference Docs Consulted

- `docs/features/existing-song-enrichment/ARCHITECT_PLAN.md`
- `docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md`
- `docs/features/new-song-key-enrichment/ENGINEER_REPORT.md`
- `docs/features/new-song-key-enrichment/QA_REPORT.md`
- `docs/reference/bpm/BPM_QUICK_REFERENCE.md`

No dedicated `docs/reference/` subdirectory exists for existing-song enrichment beyond the prior feature docs above. Those prior feature docs are the authoritative domain reference for this plan.

---

## 5. Existing System Analysis

Current production flow for Song Details enrichment:

1. `song_details_bottom_sheet.dart` calls `SongEnrichmentOrchestrator.enrichSongs()` for the selected song.
2. `SongEnrichmentOrchestrator` loads the current song row and determines which requested fields are still eligible.
3. For this production song, only `musical_key` is eligible because BPM and duration are already populated.
4. `SongEnrichmentService.lookup()` invokes the deployed `getsongbpm_lookup` Edge Function with title, artist, and duration.
5. `getsongbpm_lookup` currently filters candidates by normalized exact artist-name equality.
6. With stored artist `Tom Petty`, the function returns `confidence: 'none'` and `musicalKey: null`.
7. The orchestrator therefore leaves `updateMap` empty.
8. Because `updateMap.isEmpty`, `SetlistRepository.enrichSongs()` is not called.
9. Because the repository is never called, `update_song_metadata` is never called.
10. The results overlay is still shown, with a fixed `Enrichment Complete` title even when the only field result is `notFound`.

Current data flow for the confirmed alternate-artist case:

1. Same title, same duration, artist changed to `Tom Petty and the Heartbreakers`.
2. `getsongbpm_lookup` returns `bpm = 114`, `musicalKey = 'A'`, `confidence = 'medium'`.
3. That confirms the provider and persistence path are both viable when a usable key reaches the client.

Conclusion: the `no DB write` symptom is a consequence of the lookup layer rejecting a valid candidate before persistence is attempted.

---

## 6. Proposed Solution

Fix the root cause in the Edge Function, then make the results modal stop claiming completion when nothing was saved.

### 6.1 Edge Function change

Modify `supabase/functions/getsongbpm_lookup/index.ts` so artist resolution works in two passes:

1. Keep the existing normalized exact artist-name match as the first-pass preference.
2. If exact matches are empty, run a narrow fallback for canonical artist variants:
   - require normalized title equality between request and candidate
   - allow artist match when one normalized artist string is a clear prefix/containment variant of the other
   - only use this fallback when it yields at least one candidate with usable BPM or key data
3. Preserve existing best-candidate selection order and existing `none` fallback when neither pass yields a usable result.
4. Add a concise log reason distinguishing `exact_artist_match`, `artist_variant_match`, and `no_usable_match`.

This is the smallest safe change that fixes the confirmed `Tom Petty` vs `Tom Petty and the Heartbreakers` failure without reopening the prior broader matching debate.

### 6.2 User-facing copy change

Modify `lib/features/songs/widgets/enrichment_results_overlay.dart` so the modal title and primary summary reflect actual outcomes:

- if at least one field updated: keep success wording
- if zero fields updated and one or more fields are `notFound`: show neutral `No New Song Data Found` wording
- if zero fields updated and one or more fields errored: show incomplete/error wording

This is a minimal wording correction, not a redesign. The detail badges already carry the needed per-field status.

### 6.3 What must not change

- Do not change fill-missing-only behavior
- Do not change `SongEnrichmentOrchestrator` persistence gating
- Do not change `SetlistRepository.enrichSongs()`
- Do not change `update_song_metadata` signature or SQL body
- Do not add retries, caching, or new provider integrations
- Do not add a migration

---

## 7. Database Impact

**Migration policy:** `not required`

**Database:** existing schema is sufficient.

**RLS:** unaffected.

**RPCs:** `update_song_metadata(...)` is unaffected. Its current production definition already contains the 2026-08-01 false-success verification logic and is not the failure origin for this bug.

**Triggers:** unaffected.

**Edge function deploy:** `required`

No SQL or database-object change is required for the fix.

---

## 8. Flutter Architecture Changes

- State management: unchanged
- Repositories: unchanged
- Controllers/notifiers: unchanged
- Widgets affected: `enrichment_results_overlay.dart` copy only

This remains a narrow UI wording change plus a server-side lookup fix.

---

## 9. Files to Create

`none`

---

## 10. Files to Modify

| File                                                         | Description of change                                                                                                                   |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/functions/getsongbpm_lookup/index.ts`              | Relax artist matching with a narrow second-pass canonical-variant fallback; keep exact-match priority; add concise match-reason logging |
| `lib/features/songs/widgets/enrichment_results_overlay.dart` | Make title and primary summary conditional so zero-update runs do not present as completed saves                                        |

---

## 11. Files Off-Limits

| File                                                            | Reason                                                                                                          |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_repository.dart`                 | Repository/RPC call path is already correct for this scenario; changing it would mask the real upstream failure |
| `lib/features/songs/services/song_enrichment_orchestrator.dart` | `updateMap.isNotEmpty` gating is correct and should remain the persistence boundary                             |
| `lib/features/songs/song_enrichment_service.dart`               | Service contract is already sufficient; the bug is in function-side candidate matching, not invoke plumbing     |
| `supabase/migrations/*`                                         | No schema or SQL-function change is required                                                                    |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart`  | Entry-point wiring is not the failure origin                                                                    |
| `lib/main.dart`                                                 | Init order must not change                                                                                      |

---

## 12. System Impact Map

| System                                 | Impact     |
| -------------------------------------- | ---------- |
| Gigs                                   | unaffected |
| Rehearsals                             | unaffected |
| Setlists / Catalog                     | affected   |
| Members / RBAC                         | unaffected |
| Auth / Session                         | unaffected |
| Routing                                | unaffected |
| Notifications                          | unaffected |
| Platform (iOS / Android / Web / macOS) | affected   |

Reasoning:

- the Edge Function is shared by new-song review enrichment and existing-song enrichment
- the overlay copy is shared by enrichment flows across platforms

---

## 13. Regression Risk

`MEDIUM`

Rationale:

- the edge-function match logic is shared by multiple enrichment entry points
- the fix is small, but it changes candidate-acceptance behavior
- no auth, routing, init, or SQL changes are involved
- the UI change is low risk and copy-only

---

## 14. Engineer Task Breakdown

1. Update `supabase/functions/getsongbpm_lookup/index.ts` to keep exact artist matching first, then apply the narrow canonical-variant fallback described in §6.1.
2. Keep candidate selection and key normalization behavior otherwise unchanged.
3. Add concise log reasons for exact match, artist-variant match, and no usable match.
4. Deploy the updated `getsongbpm_lookup` function to production.
5. Update `lib/features/songs/widgets/enrichment_results_overlay.dart` so title and primary summary text reflect `updated` vs `notFound` vs `error` outcomes.
6. Run focused post-deploy verification against the production function and the reported production song.

---

## 15. Verification Plan

**Tier 1 — Pre-deployment (must pass before deploy):**

`-- PRE-DEPLOY TEST 1:` Confirm the reported production row is still the expected baseline.

```sql
SELECT id, band_id, title, artist, bpm, duration_seconds, musical_key, updated_at
FROM public.songs
WHERE id = '625e82c1-f56c-4dfc-bba7-0148eb8dedc1';
```

Expected before fix validation: `bpm = 89`, `duration_seconds = 213`, `musical_key IS NULL`.

`-- PRE-DEPLOY TEST 2:` Confirm the live RPC still contains the 2026-08-01 false-success guard and is not being changed by this work.

```sql
SELECT pg_get_functiondef(
  'public.update_song_metadata(uuid,uuid,integer,integer,text,text,text,text,text,text,text)'::regprocedure
) LIKE '%Eligibility-aware verification%';
```

Expected: `true`.

`-- PRE-DEPLOY TEST 3:` Confirm no schema work is pending for this feature.

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'songs'
  AND column_name = 'musical_key';
```

Expected: one row, `musical_key`.

**Tier 2 — Post-deployment (run after Edge Function deploy succeeds):**

No SQL function is created or replaced by this fix, so `pg_get_functiondef` verification is not applicable to the changed surface. Post-deploy validation centers on the deployed Edge Function plus production row state.

`-- POST-DEPLOY TEST 1:` Invoke the deployed Edge Function with the exact stored metadata for the reported song.

Expected JSON shape:

```json
{
  "ok": true,
  "data": {
    "musicalKey": "A",
    "confidence": "medium"
  }
}
```

`-- POST-DEPLOY TEST 2:` Invoke the deployed Edge Function with a known nonsense title/artist.

Expected JSON shape:

```json
{
  "ok": true,
  "data": {
    "bpm": null,
    "musicalKey": null,
    "confidence": "none"
  }
}
```

`-- POST-DEPLOY TEST 3:` Manually run Song Details enrichment on the reported production song with only `Key` selected.

Expected behavior:

- enrichment results show `Key = Updated`
- the song details UI refreshes with key `A`
- no misleading `Enrichment Complete` success wording appears on zero-update scenarios elsewhere

`-- POST-DEPLOY TEST 4:` Production verification query after the manual run.

```sql
SELECT id, title, artist, bpm, duration_seconds, musical_key, updated_at
FROM public.songs
WHERE id = '625e82c1-f56c-4dfc-bba7-0148eb8dedc1';
```

Expected after successful fix verification:

- `musical_key = 'A'`
- `bpm = 89` unchanged
- `duration_seconds = 213` unchanged
- `updated_at` advanced from the pre-deploy baseline

`-- POST-DEPLOY TEST 5:` Manual negative-path UI check on any song that still produces no usable enrichment result.

Expected behavior:

- modal title is neutral/incomplete wording, not `Enrichment Complete`
- primary summary does not imply a save happened when `result.enriched == 0`
- field badges still show `Not found` or `Error` accurately

---

## 16. QA Regression Areas

- Existing-song enrichment for `American Girl` / `Tom Petty` in Toxic Crayon
- Other artist-variant cases where the stored artist is a shortened credit and the provider returns a fuller canonical credit
- New-song enrichment review flow, because it shares the same Edge Function
- Negative path where lookup legitimately returns no result
- Results modal wording for all-zero-update runs
- BPM and duration non-overwrite behavior during key-only enrichment

---

## 17. Rollout / Migration Strategy

No migration.

Rollout order:

1. Deploy the updated `getsongbpm_lookup` Edge Function.
2. Deploy the Flutter client with the overlay wording fix.
3. Re-run the reported production scenario and confirm the row-level result in SQL.

Backend-first deploy is safe because the current client already tolerates `confidence: 'medium'` and `musicalKey` values from the function.

---

## 18. Out of Scope

- changing `update_song_metadata`
- adding migrations or RLS changes
- redesigning enrichment UX beyond the minimal wording correction
- broad fuzzy-matching heuristics unrelated to canonical artist-credit variants
- retry queues, analytics, caching, or provider fallback changes
- fixing the unrelated `bug/song-details-enrichment-blanks-fields` work already in flight
