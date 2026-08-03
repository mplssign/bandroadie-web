# ARCHITECT_PLAN.md

## 1. Feature Slug

bug/getsongbpm-lookup-partial-match-data

## 2. Problem Summary

GetSongBPM enrichment is intermittently returning missing BPM and sometimes missing key for known songs, while duration in the same enrichment run often succeeds via a separate provider path. The issue is upstream in the getsongbpm_lookup edge function match-selection logic, not in persistence: the update_song_metadata RPC already hard-fails true write failures and does not indicate failure in these cases.

## 3. Root Cause

Primary root cause: HIGH confidence

- In [supabase/functions/getsongbpm_lookup/index.ts](supabase/functions/getsongbpm_lookup/index.ts), candidates are reduced to exact normalized artist-name matches, then the function always selects strongMatches[0].
- If that first strong match has null tempo/key (documented malformed entries), the function returns confidence none, even if later strong matches may contain usable data.
- There is no fallback ranking among strong matches by data completeness.

Secondary contributing condition: MEDIUM confidence

- Live runtime probes in production show song-specific upstream variability.
- Direct function calls via project endpoint returned:
  - Enter Sandman / Metallica -> bpm 123, key Em, confidence medium
  - All The Small Things / Blink-182 -> bpm null, key null, confidence none
- Repeated artist-variant probes for Blink-182 (Blink 182, blink182, uppercase, etc.) still returned confidence none.
- Production table state also shows mixed historical outcomes for the same exact title/artist pair (some rows populated, others null), indicating unstable upstream candidate quality/order over time.

Conclusion

- The confirmed code defect is deterministic (first strong-match-only selection).
- Provider coverage/ordering variance also exists and explains why some songs can still return none after the code fix.

## 4. Reference Docs Consulted

- [docs/agents/ARCHITECT.md](docs/agents/ARCHITECT.md)
- [docs/agents/GUARDRAILS.md](docs/agents/GUARDRAILS.md)
- [docs/agents/OPERATING_MODEL.md](docs/agents/OPERATING_MODEL.md)
- [docs/reference/bpm/BPM_FEATURE_IMPLEMENTATION.md](docs/reference/bpm/BPM_FEATURE_IMPLEMENTATION.md)
- [docs/reference/bpm/BPM_QUICK_REFERENCE.md](docs/reference/bpm/BPM_QUICK_REFERENCE.md)
- [docs/reference/bpm/BPM_FEATURE_DEPLOYMENT.md](docs/reference/bpm/BPM_FEATURE_DEPLOYMENT.md)
- [docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md](docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md)
- [docs/features/new-song-key-enrichment/QA_REPORT.md](docs/features/new-song-key-enrichment/QA_REPORT.md)
- [supabase/functions/getsongbpm_lookup/index.ts](supabase/functions/getsongbpm_lookup/index.ts)
- [lib/features/songs/song_enrichment_service.dart](lib/features/songs/song_enrichment_service.dart)
- [lib/features/songs/services/song_enrichment_orchestrator.dart](lib/features/songs/services/song_enrichment_orchestrator.dart)
- [lib/features/setlists/setlist_repository.dart](lib/features/setlists/setlist_repository.dart)

## 5. Existing System Analysis

Current data flow

1. UI enrichment path calls [lib/features/songs/song_enrichment_service.dart](lib/features/songs/song_enrichment_service.dart).
2. Service invokes edge function getsongbpm_lookup.
3. Edge function queries GetSongBPM using type=both and lookup format song:<title> artist:<artist>.
4. Edge function keeps only exact normalized artist matches.
5. Edge function selects first strong match only and parses tempo/key_of.
6. If both parsed bpm and key are null, returns confidence none.
7. Orchestrator treats confidence none as per-field notFound and does not attempt alternate candidates.
8. Duration enrichment is separate (iTunes/MusicBrainz path), so duration can still populate when BPM/key does not.

Failure mode mapping

- Trigger not called: not the issue (enrichment path is invoked; rows show updated_at changes and duration writes).
- Recipient resolution fails: not applicable.
- Preference gate blocks send: not applicable.
- Token missing/stale: not applicable.
- Backend error path: not primary (calls return 200 with valid payload).
- RLS policy blocks read: not applicable to this edge function behavior.

## 6. Proposed Solution

Minimal solution principle

- Keep scope limited to candidate-selection/parsing behavior in the existing edge function.
- No Flutter UI, repository, orchestrator, migration, or schema changes.

Change set

1. In getsongbpm_lookup, replace first strong-match-only selection with best-available strong-match selection.
2. Candidate scoring order inside strong matches:
   - First priority: has numeric tempo.
   - Second priority: has normalizable key.
   - Third priority: preserve provider order as tie-breaker.
3. If no strong match has usable data but strong matches exist:
   - Return confidence none (preserve no-guess behavior).
4. Preserve existing strict artist normalization and no-throw contract.
5. Add structured debug logs (non-sensitive) to distinguish:
   - no search array
   - zero strong matches
   - strong matches present but no usable tempo/key
   - selected candidate had tempo/key

What must not change

- API response contract to callers.
- Confidence semantics (medium or none).
- Key normalization vocabulary rules.
- Any client-side orchestration/result overlay behavior.

## 7. Database Impact

Database: not applicable

Migrations

- None

RLS policies

- Unaffected

RPC signatures

- Unaffected

Triggers

- Unaffected

## 8. Flutter Architecture Changes

None.

No changes to state management, widgets, repositories, controllers, or providers in Flutter. This fix is server-side inside the edge function only.

## 9. Files to Create

none

## 10. Files to Modify

| File                                                                                           | What changes                                                                                                                                    |
| ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| [supabase/functions/getsongbpm_lookup/index.ts](supabase/functions/getsongbpm_lookup/index.ts) | Replace first strong-match-only logic with best-available strong-match selection and add targeted diagnostic logging for match-outcome reasons. |

## 11. Files Off-Limits

| File                                                                                                                           | Reason                                                            |
| ------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------- |
| [lib/features/songs/song_enrichment_service.dart](lib/features/songs/song_enrichment_service.dart)                             | Caller contract already correct; fix is upstream selection logic. |
| [lib/features/songs/services/song_enrichment_orchestrator.dart](lib/features/songs/services/song_enrichment_orchestrator.dart) | NotFound handling is expected; changing it would mask root cause. |
| [lib/features/setlists/setlist_repository.dart](lib/features/setlists/setlist_repository.dart)                                 | Persistence path already validated and must remain unchanged.     |
| [supabase/migrations](supabase/migrations)                                                                                     | No schema/RPC/RLS change required for this bug fix.               |

## 12. System Impact Map

| System                                 | Impact                                         |
| -------------------------------------- | ---------------------------------------------- |
| Gigs                                   | unaffected                                     |
| Rehearsals                             | unaffected                                     |
| Setlists / Catalog                     | affected (enrichment quality only)             |
| Members / RBAC                         | unaffected                                     |
| Auth / Session                         | unaffected                                     |
| Routing                                | unaffected                                     |
| Notifications                          | unaffected                                     |
| Platform (iOS / Android / Web / macOS) | affected equally (server-side lookup behavior) |

## 13. Regression Risk

LOW

Rationale

- Single-file change in existing edge function.
- No schema, RLS, RPC signature, or client contract changes.
- Fallback behavior remains non-blocking and confidence none where data is unusable.

## 14. Engineer Task Breakdown

1. Modify [supabase/functions/getsongbpm_lookup/index.ts](supabase/functions/getsongbpm_lookup/index.ts): implement strong-match ranking by data completeness instead of selecting index 0.
2. Add reason-coded logs for no-search, no-strong-match, no-usable-strong-match, selected-candidate summary (no secrets).
3. Keep existing output contract exactly unchanged.
4. Deploy edge function to project nekwjxvgbveheooyorjo.
5. Run pre/post verification SQL and runtime probes from Section 15.
6. Produce ENGINEER_REPORT.md with exact before/after selection behavior and probe outputs.

## 15. Verification Plan

Tier 1 - Pre-deployment (must pass before deploy)

-- PRE-DEPLOY TEST 1:
Confirm deployed Edge Function source currently contains first-match-only selector marker.

```bash
PROJECT_REF="nekwjxvgbveheooyorjo"
FUNCTION_SLUG="getsongbpm_lookup"
TMP_DIR="/tmp/edge_fn_src_pre"

rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
supabase functions download "$FUNCTION_SLUG" \
  --project-ref "$PROJECT_REF" \
  --output "$TMP_DIR"

SRC_FILE="$TMP_DIR/$FUNCTION_SLUG/index.ts"

test -f "$SRC_FILE" \
  && rg -n "strongMatches\[0\]" "$SRC_FILE" \
  && echo "uses_first_strong_match=true" \
  || echo "uses_first_strong_match=false"
```

-- PRE-DEPLOY TEST 2:
Confirm update_song_metadata signature and grants are unchanged baseline (guard against accidental unrelated DB work).

```sql
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'update_song_metadata';
```

-- PRE-DEPLOY TEST 3:
Baseline affected songs table snapshot for later comparison.

```sql
SELECT title, artist, bpm, musical_key, duration_seconds, updated_at
FROM songs
WHERE (lower(title) = 'enter sandman' AND lower(artist) = 'metallica')
   OR (lower(title) = 'all the small things' AND lower(artist) IN ('blink-182','blink 182'))
ORDER BY updated_at DESC
LIMIT 20;
```

Tier 2 - Post-deployment (after edge function deploy)

-- POST-DEPLOY TEST 1:
Confirm deployed Edge Function source no longer uses first strong-match-only selector and includes best-available selector marker.

```bash
PROJECT_REF="nekwjxvgbveheooyorjo"
FUNCTION_SLUG="getsongbpm_lookup"
TMP_DIR="/tmp/edge_fn_src_post"

rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
supabase functions download "$FUNCTION_SLUG" \
  --project-ref "$PROJECT_REF" \
  --output "$TMP_DIR"

SRC_FILE="$TMP_DIR/$FUNCTION_SLUG/index.ts"

if test -f "$SRC_FILE"; then
  if rg -q "strongMatches\[0\]" "$SRC_FILE"; then
    echo "removed_first_index_selection=false"
  else
    echo "removed_first_index_selection=true"
  fi

  if rg -q "bestAvailableStrongMatch" "$SRC_FILE"; then
    echo "added_best_match_selector=true"
  else
    echo "added_best_match_selector=false"
  fi
else
  echo "source_download_failed=true"
fi
```

-- POST-DEPLOY TEST 2:
Runtime integration probe via edge endpoint for confirmed case and problematic case.

```bash
SUPABASE_URL=$(jq -r '.SUPABASE_URL' dart_defines.json)
ANON_KEY=$(jq -r '.SUPABASE_ANON_KEY' dart_defines.json)

curl -s "$SUPABASE_URL/functions/v1/getsongbpm_lookup" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  --data '{"title":"Enter Sandman","artist":"Metallica"}' | jq .

curl -s "$SUPABASE_URL/functions/v1/getsongbpm_lookup" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  --data '{"title":"All The Small Things","artist":"Blink-182"}' | jq .
```

-- POST-DEPLOY TEST 3:
Production safety check: no invalid values written by this fix (edge function only, but verify data integrity baseline).

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

- Re-run enrichment for known affected songs and confirm behavior is at least not worse, with focus on BPM population outcomes.
- Test a sample set of 20-30 songs across multiple artists to confirm reduced false none responses where tempo/key exists in alternate strong matches.
- Confirm duration-only behavior remains unchanged when BPM/key unavailable.
- Confirm results overlay still shows per-field Not found and summary counts correctly.
- Confirm no RPC write regressions for update_song_metadata path.

## 17. Rollout / Migration Strategy

- Deploy edge function only; no database migration.
- Validate with Section 15 Tier 2 probes immediately after deploy.
- Monitor function logs for reason-code distribution to determine if remaining misses are mostly provider-coverage vs artist-match strictness.

## 18. Out of Scope

- Replacing GetSongBPM provider.
- Broad client-side enrichment UX changes.
- Schema/RLS/RPC refactors.
- Changing confidence taxonomy beyond medium/none.
- Bulk backfill jobs for existing songs.
