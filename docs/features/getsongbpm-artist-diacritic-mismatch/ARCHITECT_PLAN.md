# ARCHITECT_PLAN.md

## 1. Feature Slug

bug/getsongbpm-artist-diacritic-mismatch

## 2. Problem Summary

Catalog-wide GetSongBPM enrichment can miss musical key and BPM for songs whose artist names contain diacritics or other non-ASCII characters, even when the provider has usable data for the exact song. The failure is not in the Flutter enrichment flow or persistence; it is in the `getsongbpm_lookup` edge function’s artist-name normalization, which currently strips non-ASCII characters instead of transliterating them to their base Latin forms.

This produces false non-matches between transliteration-equivalent artist spellings such as `Mötley Crüe` and `Motley Crue`, so the lookup returns `confidence: 'none'` and enrichment stops before a valid BPM/key candidate is selected. This is a different defect from the already-shipped strong-match selection fix in `docs/features/getsongbpm-lookup-partial-match-data/ARCHITECT_PLAN.md`; that fix changed which candidate wins after matching, while this bug prevents the right candidates from matching at all.

## 3. Root Cause

Primary root cause: HIGH confidence

- In `supabase/functions/getsongbpm_lookup/index.ts`, `normalizeArtistName()` and the artist-word normalization used by `isArtistVariantMatch()` remove any character outside `[a-z0-9]`.
- That behavior discards accented Latin letters instead of decomposing them, so transliteration-equivalent names do not compare equal.
- Example: `Mötley Crüe` becomes `mtleycre`, while `Motley Crue` becomes `motleycrue`.
- Because the exact-match and variant-match filters rely on those normalized strings, valid GetSongBPM candidates are excluded before `selectBestAvailableMatch()` can consider their BPM/key completeness.

## 4. Reference Docs Consulted

Read from `docs/reference/notifications/`:

- [docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md](docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md)
- [docs/reference/notifications/NOTIFICATION_SYSTEM.md](docs/reference/notifications/NOTIFICATION_SYSTEM.md)
- [docs/reference/notifications/notifications.md](docs/reference/notifications/notifications.md)

These docs describe the notification delivery stack and are orthogonal to this defect, but they were reviewed because the feature request explicitly asked for the notification reference set to be loaded first.

## 5. Existing System Analysis

Current data flow:

1. The Flutter enrichment UI calls `lib/features/songs/song_enrichment_service.dart`.
2. The service delegates to `lib/features/songs/services/song_enrichment_orchestrator.dart`.
3. The orchestrator calls the `getsongbpm_lookup` Supabase edge function with the song title and artist exactly as stored.
4. The edge function queries GetSongBPM using `type=both` and `lookup=song:<title> artist:<artist>`.
5. The function builds `exactArtistMatches` by comparing `normalizeArtistName()` results.
6. If no exact artist matches exist, it attempts `artistVariantMatches` using `normalizeWords()` plus `isArtistVariantMatch()`.
7. Matching candidates are then scored with `selectBestAvailableMatch()`, which prefers usable tempo/key data.
8. If the artist normalization filters reject the right candidates, the function returns `confidence: 'none'` and enrichment records no BPM/key for that row.

The key detail is that candidate selection is already not the problem in the current workspace; the failure happens earlier, during artist matching. That is why this bug is distinct from the prior first-match-selection fix.

## 6. Proposed Solution

Change only the artist-normalization path inside `supabase/functions/getsongbpm_lookup/index.ts`.

What changes:

1. Replace the ASCII-only artist normalization with Unicode-aware transliteration that decomposes accented Latin characters and strips combining marks before the existing alphanumeric cleanup.
2. Apply the same Unicode-aware normalization to the word-based artist variant matcher so exact-match and variant-match filtering both become diacritic-insensitive.
3. Keep the existing candidate scoring logic, response shape, confidence semantics, and key normalization vocabulary unchanged.
4. Preserve the current no-throw, degrade-to-`none` contract when provider data is genuinely missing.

What must not change:

- `SHARP_TO_FLAT`, `VALID_MAJOR_KEYS`, and `VALID_MINOR_KEYS`.
- The `confidence` contract (`medium` or `none`).
- The edge function’s response envelope.
- Any Flutter enrichment orchestration or repository behavior.

New files required:

- None.

## 7. Database Impact

Database: not applicable.

- Migrations: none.
- RLS policies: unaffected.
- RPC signatures: unaffected.
- Triggers: unaffected.

This is an edge-function-only fix.

## 8. Flutter Architecture Changes

None.

No state management, widgets, repositories, controllers, or providers in Flutter need to change. The defect is fully contained in the Supabase edge function that queries GetSongBPM.

## 9. Files to Create

none

## 10. Files to Modify

| File                                                                                           | What changes                                                                                                                               |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| [supabase/functions/getsongbpm_lookup/index.ts](supabase/functions/getsongbpm_lookup/index.ts) | Make artist normalization Unicode-aware for exact-match and variant-match filtering; keep match selection and response contract unchanged. |

**Migration policy:** not required

**Edge function deploy:** required

**New dependencies:** not allowed

## 11. Files Off-Limits

| File                                                                                                                                         | Reason                                                                                        |
| -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| [lib/features/songs/song_enrichment_service.dart](lib/features/songs/song_enrichment_service.dart)                                           | Caller already passes the stored artist through unchanged; not the defect.                    |
| [lib/features/songs/services/song_enrichment_orchestrator.dart](lib/features/songs/services/song_enrichment_orchestrator.dart)               | Orchestrator behavior is correct and should not be widened to mask backend matching failures. |
| [lib/features/setlists/setlist_repository.dart](lib/features/setlists/setlist_repository.dart)                                               | Persistence path is unrelated to the lookup failure.                                          |
| [supabase/migrations](supabase/migrations)                                                                                                   | No schema, RLS, RPC, or trigger change is needed.                                             |
| [docs/features/getsongbpm-lookup-partial-match-data/ARCHITECT_PLAN.md](docs/features/getsongbpm-lookup-partial-match-data/ARCHITECT_PLAN.md) | Separate shipped fix; keep this defect isolated.                                              |

## 12. System Impact Map

| System                                 | Impact                                           |
| -------------------------------------- | ------------------------------------------------ |
| Gigs                                   | unaffected                                       |
| Rehearsals                             | unaffected                                       |
| Setlists / Catalog                     | affected                                         |
| Members / RBAC                         | unaffected                                       |
| Auth / Session                         | unaffected                                       |
| Routing                                | unaffected                                       |
| Notifications                          | unaffected                                       |
| Platform (iOS / Android / Web / macOS) | affected equally, because the bug is server-side |

## 13. Regression Risk

LOW

Rationale:

- Single-file change in an existing edge function.
- No schema, RLS, RPC, trigger, or Flutter client changes.
- The fix only broadens artist equivalence for transliteration-equivalent names and does not change how candidates are scored once matched.

## 14. Engineer Task Breakdown

1. Update `supabase/functions/getsongbpm_lookup/index.ts` so artist normalization is Unicode-aware before ASCII cleanup.
2. Apply the same normalization to the variant-match path so `Mötley Crüe` and `Motley Crue` resolve to the same candidate set.
3. Preserve the existing candidate scoring, logging, and response contract.
4. Deploy the updated edge function.
5. Run the pre-deployment source checks and the post-deployment runtime probes listed below.
6. Record the exact behavior change and verification results in `ENGINEER_REPORT.md`.

## 15. Verification Plan

Tier 1 - Pre-deployment

-- PRE-DEPLOY TEST 1:
Confirm the normalization helper behavior in isolation using a local smoke test that mirrors the intended Unicode transliteration.

```bash
deno eval '
const normalizeArtistName = (value) => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");
console.assert(normalizeArtistName("Mötley Crüe") === "motleycrue");
console.assert(normalizeArtistName("Motley Crue") === "motleycrue");
console.assert(normalizeArtistName("Beyoncé") === "beyonce");
console.assert(normalizeArtistName("Björk") === "bjork");
console.log("normalize_artist_smoke=pass");
'
```

-- PRE-DEPLOY TEST 2:
Confirm the current source still leaves the key-normalization vocabulary untouched so this bug remains isolated to artist comparison.

```bash
rg -n "SHARP_TO_FLAT|VALID_MAJOR_KEYS|VALID_MINOR_KEYS|normalizeKey" supabase/functions/getsongbpm_lookup/index.ts
```

Tier 2 - Post-deployment

-- POST-DEPLOY TEST 1:
Download the deployed edge function and confirm the source now uses Unicode-aware artist normalization rather than ASCII-only stripping.

```bash
PROJECT_REF="nekwjxvgbveheooyorjo"
FUNCTION_SLUG="getsongbpm_lookup"
TMP_DIR="/tmp/edge_fn_getsongbpm_post"

rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
supabase functions download "$FUNCTION_SLUG" --project-ref "$PROJECT_REF" --output "$TMP_DIR"

SRC_FILE="$TMP_DIR/$FUNCTION_SLUG/index.ts"

rg -n "normalize\('NFD'\)|\\u0300-\\u036f|normalizeArtistName|isArtistVariantMatch" "$SRC_FILE"
```

-- POST-DEPLOY TEST 2:
Run a live runtime probe against the deployed edge function for the confirmed diacritic case and the plain-ASCII transliteration case.

```bash
SUPABASE_URL=$(jq -r '.SUPABASE_URL' dart_defines.json)
ANON_KEY=$(jq -r '.SUPABASE_ANON_KEY' dart_defines.json)

curl -s "$SUPABASE_URL/functions/v1/getsongbpm_lookup" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  --data '{"title":"Home Sweet Home","artist":"Mötley Crüe"}' | jq .

curl -s "$SUPABASE_URL/functions/v1/getsongbpm_lookup" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  --data '{"title":"Home Sweet Home","artist":"Motley Crue"}' | jq .
```

-- POST-DEPLOY TEST 3:
Run a read-only production safety query to confirm this lookup fix did not write malformed BPM or key values.

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

- Re-run catalog enrichment for songs whose artists contain diacritics and confirm BPM/key now populate when provider data exists.
- Verify a transliteration pair such as `Mötley Crüe` and `Motley Crue` produces the same lookup outcome.
- Confirm ordinary ASCII artist lookups still behave exactly as before.
- Confirm other enrichment paths and their per-field `not found` behavior remain unchanged when provider data is genuinely absent.
- Confirm no other platform-specific code paths were touched.

## 17. Rollout / Migration Strategy

- Deploy the edge function update only.
- No database migration is required.
- Validate immediately with the post-deployment runtime probes.
- If logs show remaining misses after the fix, treat them as provider coverage gaps rather than normalization failures.

## 18. Out of Scope

- Any Flutter UI, state, repository, or orchestrator change.
- Any key-vocabulary change in `normalizeKey()`.
- Any new transliteration library or broad refactor beyond the existing edge function file.
- Database schema, RLS, RPC, trigger, or migration work.
- Backfilling historical rows.
