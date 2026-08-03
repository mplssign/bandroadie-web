# Engineer Report

## Feature Slug

bug/getsongbpm-title-fallback-parenthetical

## Feature Title

GetSongBPM title fallback for trailing parenthetical subtitles

## Goal

Implement a conservative title fallback in the GetSongBPM edge lookup so songs with trailing parenthetical subtitles can enrich BPM/key when provider indexing is under the shorter primary title. Keep artist matching, candidate selection, key normalization vocabulary, and response semantics unchanged.

## Architect Tasks Completed

- [x] Task 1 - Added helper in the edge function to compute fallback title by stripping one trailing parenthetical group and surrounding whitespace.
- [x] Task 2 - Refactored lookup flow to attempt full title first, then retry once with fallback title only when first attempt returns no usable match and fallback differs.
- [x] Task 3 - Kept existing match filtering and selectBestAvailableMatch logic unchanged.
- [x] Task 4 - Kept output contract and confidence semantics unchanged ({ bpm, musicalKey, confidence } with medium/none).
- [x] Task 5 - Added minimal logging for fallback attempted status and result attempt source.
- [x] Task 6 - Deployed getsongbpm_lookup to project nekwjxvgbveheooyorjo.
- [x] Task 7 - Executed Tier 1 and Tier 2 verification steps; documented outputs and blocker for Post-Deploy Test 3 credentials.

## Files Created

- docs/features/getsongbpm-title-fallback-parenthetical/ENGINEER_REPORT.md

## Files Modified

- supabase/functions/getsongbpm_lookup/index.ts

## Analyzer Results

Command: flutter analyze
Result: 0 errors / 0 warnings

## Test Results

Not run (no Architect-mandated flutter test step for this edge-function-only change)

## Verification

Manual steps performed:

1. Tier 1 - Pre-Deploy Test 1 (live baseline probes)

- Full-title probe request:
  {"title":"Come Out And Play (Keep 'Em Separated)","artist":"The Offspring"}
- Output:

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

- Short-title control request:
  {"title":"Come Out And Play","artist":"Offspring"}
- Output:

```json
{
  "ok": true,
  "data": {
    "bpm": 160,
    "musicalKey": "G",
    "confidence": "medium"
  }
}
```

2. Tier 1 - Pre-Deploy Test 2 (source scan baseline)

- Planned command used rg, but rg is unavailable in this shell.
- Substitution used: grep -nE "lookupGetSongBpm|normalizeTitleName|parenthetical|fallback|attempt" supabase/functions/getsongbpm_lookup/index.ts
- Baseline showed no fallback retry implementation.

3. Tier 1 - Pre-Deploy Test 3 (key normalization baseline)

- Planned command used rg, but rg is unavailable in this shell.
- Substitution used: grep -nE "SHARP_TO_FLAT|VALID_MAJOR_KEYS|VALID_MINOR_KEYS|normalizeKey" supabase/functions/getsongbpm_lookup/index.ts
- Confirmed baseline vocabulary constants and normalizeKey symbols.

4. Deploy

- Command:
  supabase functions deploy getsongbpm_lookup --project-ref nekwjxvgbveheooyorjo
- Output included:
  {"project_ref":"nekwjxvgbveheooyorjo","functions":["getsongbpm_lookup"],"message":"Deployed Functions."}

5. Tier 2 - Post-Deploy Test 1 (download deployed source + scan)

- Architect command used unsupported --output path flag for current CLI.
- Substitution used:
  - Run in temp dir: /tmp/edge_fn_getsongbpm_title_fallback_post
  - Command: supabase functions download getsongbpm_lookup --project-ref nekwjxvgbveheooyorjo
  - Scanned downloaded file at /tmp/edge_fn_getsongbpm_title_fallback_post/supabase/functions/getsongbpm_lookup/index.ts
- Output confirmed fallback helper, attempt-tagged logging, and two-attempt flow are deployed.

6. Tier 2 - Post-Deploy Test 2 (live post-deploy probes)

- Full-title probe request:
  {"title":"Come Out And Play (Keep 'Em Separated)","artist":"The Offspring"}
- Output:

```json
{
  "ok": true,
  "data": {
    "bpm": 160,
    "musicalKey": "G",
    "confidence": "medium"
  }
}
```

- Short-title control request:
  {"title":"Come Out And Play","artist":"Offspring"}
- Output:

```json
{
  "ok": true,
  "data": {
    "bpm": 160,
    "musicalKey": "G",
    "confidence": "medium"
  }
}
```

7. Tier 2 - Post-Deploy Test 3 (production SQL safety query)

- Blocked because SUPABASE_DB_PASSWORD is not set in this shell.
- Explicit output:
  POST_DEPLOY_TEST_3_BLOCKED: SUPABASE_DB_PASSWORD is not set

## Deviations From Architect Plan

- Replaced rg commands with grep equivalents because rg is not installed in this shell.
- Replaced supabase functions download command syntax to match current Supabase CLI behavior (no path-valued --output flag for this command).
- No scope deviations in code changes; only the planned edge-function file was modified.

## Blockers Encountered

- Post-Deploy Test 3 SQL safety query is blocked by missing SUPABASE_DB_PASSWORD in shell environment.

## Ready For QA

No - Functional fix is deployed and live probes pass, but Post-Deploy Test 3 remains blocked pending DB credentials.
