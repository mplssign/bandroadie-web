# ARCHITECT_PLAN.md

## 1. Feature Slug

bug/getsongbpm-title-fallback-parenthetical

## 2. Problem Summary

Catalog-wide and single-song GetSongBPM enrichment can fail to return BPM/key when a song title in the catalog includes trailing descriptive text (for example, a parenthetical subtitle) that GetSongBPM does not index under the same longer title.

Confirmed production behavior:

- `{"title":"Come Out And Play","artist":"Offspring"}` returns usable data (`bpm: 160`, `musicalKey: "G"`, `confidence: "medium"`).
- `{"title":"Come Out And Play (Keep 'Em Separated)","artist":"The Offspring"}` returns no data (`bpm: null`, `musicalKey: null`, `confidence: "none"`).
- `{"title":"Come Out And Play Keep Em Separated","artist":"The Offspring"}` also fails, confirming extra words (not punctuation) are the issue.

The defect is in lookup query construction/retry behavior inside `getsongbpm_lookup`, not Flutter client orchestration or persistence.

## 3. Root Cause

Primary root cause: HIGH confidence

- In `supabase/functions/getsongbpm_lookup/index.ts`, `lookupGetSongBpm()` builds one `lookup` string with the literal stored title and artist, performs exactly one provider request, and returns `confidence: 'none'` on no usable match.
- There is no fallback attempt that trims a trailing parenthetical subtitle from the title and retries once.
- When provider indexing uses a shorter primary title, the single literal-title request can miss valid candidates entirely.

Distinctness from prior shipped fixes:

- `bug/getsongbpm-artist-diacritic-mismatch` fixed artist normalization/transliteration.
- `bug/getsongbpm-lookup-partial-match-data` fixed candidate selection among already matched candidates.
- This bug is upstream of both: title-query construction and retry strategy.

## 4. Reference Docs Consulted

Read from `docs/reference/notifications/` (required by Architect phase order):

- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/notifications.md`

These are orthogonal to this defect and did not change diagnosis.

Additional context docs reviewed:

- `docs/features/getsongbpm-artist-diacritic-mismatch/ARCHITECT_PLAN.md`
- `docs/features/getsongbpm-lookup-partial-match-data/ARCHITECT_PLAN.md`

## 5. Existing System Analysis

Current flow:

1. Flutter enrichment path calls `SongEnrichmentService.lookup()` with stored title and artist unchanged.
2. Service invokes Supabase edge function `getsongbpm_lookup`.
3. In `lookupGetSongBpm()`, edge function builds:
   - `lookup = song:<title> artist:<artist>`
   - `type=both`
4. Provider response is filtered by exact artist and artist-variant logic.
5. `selectBestAvailableMatch()` chooses best data among matched candidates.
6. If no usable match is found, function returns `noneResult()` (`bpm: null`, `musicalKey: null`, `confidence: 'none'`).

Observed gap:

- The function never retries with an alternate title form when the initial literal-title request fails, so longer catalog titles with trailing subtitles can miss data indexed under shorter titles.

## 6. Proposed Solution

Change only `supabase/functions/getsongbpm_lookup/index.ts`.

What changes:

1. Add a helper that derives a conservative fallback "primary title" by stripping exactly one trailing parenthetical group and surrounding whitespace.
   - Example: `Come Out And Play (Keep 'Em Separated)` -> `Come Out And Play`
2. Keep the existing first attempt exactly as-is (full stored title).
3. Retry exactly once with trimmed title only when the first attempt yields no usable exact-artist or artist-variant outcome.
4. Preserve existing artist matching logic (`normalizeArtistName`, `normalizeWords`, `isArtistVariantMatch`) and candidate scoring (`selectBestAvailableMatch`) unchanged.
5. Preserve response envelope and confidence semantics unchanged (`medium` or `none`).

What must not change:

- `normalizeArtistName`, `normalizeWords`, `isArtistVariantMatch`
- `selectBestAvailableMatch()`
- `normalizeKey()`, `SHARP_TO_FLAT`, `VALID_MAJOR_KEYS`, `VALID_MINOR_KEYS`
- Edge response contract and no-throw degrade-to-none behavior
- Flutter client files and repository logic

New files required:

- None.

## 7. Database Impact

Database: not applicable.

- Migrations: none
- RLS policies: unaffected
- RPC signatures: unaffected
- Triggers: unaffected

This is an edge-function-only behavior fix.

## 8. Flutter Architecture Changes

None.

No widget, provider, controller, repository, or orchestrator changes are required. The issue is fully contained in the edge function lookup retry behavior.

## 9. Files to Create

none

## 10. Files to Modify

| File                                            | What changes                                                                                                                                                                                              |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/functions/getsongbpm_lookup/index.ts` | Add one conservative title fallback retry path in `lookupGetSongBpm()` for trailing-parenthetical titles; leave artist matching, candidate selection, key normalization, and response contract untouched. |

**Migration policy:** not required

**Edge function deploy:** required

**New dependencies:** not allowed

## 11. Files Off-Limits

| File                                                                   | Reason                                                                       |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `lib/features/songs/song_enrichment_service.dart`                      | Caller already passes stored title/artist unchanged; not the defect source.  |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`        | Orchestration behavior is correct and should not mask backend lookup misses. |
| `lib/features/setlists/setlist_repository.dart`                        | Persistence path is unrelated to lookup-title miss behavior.                 |
| `supabase/migrations`                                                  | No schema, RLS, RPC, or trigger change is required.                          |
| `docs/features/getsongbpm-artist-diacritic-mismatch/ARCHITECT_PLAN.md` | Prior shipped bug; keep fixes isolated.                                      |
| `docs/features/getsongbpm-lookup-partial-match-data/ARCHITECT_PLAN.md` | Prior shipped bug; keep fixes isolated.                                      |

## 12. System Impact Map

| System                                 | Impact                                       |
| -------------------------------------- | -------------------------------------------- |
| Gigs                                   | unaffected                                   |
| Rehearsals                             | unaffected                                   |
| Setlists / Catalog                     | affected                                     |
| Members / RBAC                         | unaffected                                   |
| Auth / Session                         | unaffected                                   |
| Routing                                | unaffected                                   |
| Notifications                          | unaffected                                   |
| Platform (iOS / Android / Web / macOS) | affected equally (server-side edge function) |

## 13. Regression Risk

LOW

Rationale:

- Single-file, localized edge function change.
- No database object changes.
- No client-side architecture or UI changes.
- Retry is bounded to one conservative trim rule (single trailing parenthetical only).

## 14. Engineer Task Breakdown

1. In `supabase/functions/getsongbpm_lookup/index.ts`, add a helper to compute a fallback primary title by removing one trailing parenthetical subtitle.
2. Refactor `lookupGetSongBpm()` so it can perform up to two attempts:
   - attempt 1: full title (existing behavior)
   - attempt 2: trimmed title (only if attempt 1 had no usable exact/variant outcome and trimmed title differs)
3. Keep existing match filtering and `selectBestAvailableMatch()` unchanged.
4. Keep output contract unchanged (`{ bpm, musicalKey, confidence }`).
5. Add minimal logging to indicate whether fallback was attempted and which attempt produced the result.
6. Deploy `getsongbpm_lookup` edge function.
7. Execute verification plan and document results in `ENGINEER_REPORT.md`.

## 15. Verification Plan

Tier 1 - Pre-deployment

-- PRE-DEPLOY TEST 1:
Confirm baseline behavior in deployed function for the known failing full title and known working short title.

```bash
SUPABASE_URL=$(jq -r '.SUPABASE_URL' dart_defines.json)
ANON_KEY=$(jq -r '.SUPABASE_ANON_KEY' dart_defines.json)

curl -s "$SUPABASE_URL/functions/v1/getsongbpm_lookup" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  --data '{"title":"Come Out And Play (Keep '\''Em Separated)","artist":"The Offspring"}' | jq .

curl -s "$SUPABASE_URL/functions/v1/getsongbpm_lookup" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  --data '{"title":"Come Out And Play","artist":"Offspring"}' | jq .
```

-- PRE-DEPLOY TEST 2:
Confirm current source has no title fallback helper/retry logic yet.

```bash
rg -n "lookupGetSongBpm|normalizeTitleName|parenthetical|fallback|attempt" supabase/functions/getsongbpm_lookup/index.ts
```

-- PRE-DEPLOY TEST 3:
Confirm key normalization vocabulary remains unchanged baseline.

```bash
rg -n "SHARP_TO_FLAT|VALID_MAJOR_KEYS|VALID_MINOR_KEYS|normalizeKey" supabase/functions/getsongbpm_lookup/index.ts
```

Tier 2 - Post-deployment

-- POST-DEPLOY TEST 1:
Download deployed edge function and confirm fallback implementation exists in source.

```bash
PROJECT_REF="nekwjxvgbveheooyorjo"
FUNCTION_SLUG="getsongbpm_lookup"
TMP_DIR="/tmp/edge_fn_getsongbpm_title_fallback_post"

rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
supabase functions download "$FUNCTION_SLUG" --project-ref "$PROJECT_REF" --output "$TMP_DIR"

SRC_FILE="$TMP_DIR/$FUNCTION_SLUG/index.ts"

rg -n "lookupGetSongBpm|parenthetical|fallback|trimmed|attempt" "$SRC_FILE"
```

-- POST-DEPLOY TEST 2:
Run live probe for failing full title and confirm fallback now returns usable data; compare with short-title control query.

```bash
SUPABASE_URL=$(jq -r '.SUPABASE_URL' dart_defines.json)
ANON_KEY=$(jq -r '.SUPABASE_ANON_KEY' dart_defines.json)

curl -s "$SUPABASE_URL/functions/v1/getsongbpm_lookup" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  --data '{"title":"Come Out And Play (Keep '\''Em Separated)","artist":"The Offspring"}' | jq .

curl -s "$SUPABASE_URL/functions/v1/getsongbpm_lookup" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  --data '{"title":"Come Out And Play","artist":"Offspring"}' | jq .
```

-- POST-DEPLOY TEST 3:
Run read-only production safety query to confirm no malformed values in stored song metadata.

```sql
SELECT
  COUNT(*) FILTER (WHERE bpm IS NOT NULL AND (bpm < 30 OR bpm > 260)) AS out_of_range_bpm,
  COUNT(*) FILTER (
    WHERE musical_key IS NOT NULL
      AND musical_key NOT IN (
        'C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B',
        'Cm','C#m','Dm','Ebm','Em','Fm','F#m','Gm','Abm','Am','Bbm','Bm'
      )
  ) AS invalid_key_values
FROM songs;
```

## 16. QA Regression Areas

- Verify the catalog song `Come Out And Play (Keep 'Em Separated)` by `The Offspring` now enriches BPM/key when provider data exists under the shorter title.
- Verify short-title control queries still behave as before.
- Verify non-parenthetical titles are unchanged.
- Verify artist diacritic scenarios from the prior bug remain correct (no regression in artist normalization behavior).
- Verify no regressions in partial-match data selection behavior from the prior candidate-scoring fix.
- Verify genuine provider-coverage gaps (for example newer songs absent from provider index) still return `confidence: 'none'` without false positives.

## 17. Rollout / Migration Strategy

- Deploy edge function update only.
- No database migration.
- Run Tier 2 probes immediately post deploy.
- Monitor edge logs for fallback-attempt frequency and outcomes.

## 18. Out of Scope

- Any Flutter client changes.
- Any artist normalization changes.
- Any candidate scoring/key normalization changes.
- Fuzzy, multi-step, or recursive title trimming.
- Attempts to resolve true provider-coverage gaps (for example unavailable new-release data).
- Backfilling historical rows.
