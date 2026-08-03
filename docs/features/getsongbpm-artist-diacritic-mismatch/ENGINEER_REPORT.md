# Engineer Report

## Feature Slug

bug/getsongbpm-artist-diacritic-mismatch

## Feature Title

Catalog GetSongBPM artist diacritic mismatch

## Goal

Ensure GetSongBPM artist matching is diacritic-insensitive so transliteration-equivalent artist names (for example, Mötley Crüe vs Motley Crue) resolve to the same candidate set and return the same BPM/key result when provider data exists.

## Architect Tasks Completed

- [x] Task 1 — Updated `supabase/functions/getsongbpm_lookup/index.ts` artist normalization to Unicode-aware NFD + combining-mark stripping before existing lowercase/alphanumeric cleanup.
- [x] Task 2 — Applied identical Unicode-aware normalization to `normalizeWords()` (shared by artist variant matching and title normalization).
- [x] Task 3 — Preserved candidate scoring (`selectBestAvailableMatch()`), confidence semantics, response envelope, and key-vocabulary logic.
- [x] Task 4 — Deployed edge function `getsongbpm_lookup` to project `nekwjxvgbveheooyorjo`.
- [x] Task 5 — Ran pre-deploy and post-deploy verification probes from Architect Section 15 (with one environment constraint noted below).
- [x] Task 6 — Recorded behavior change and verification details in this report.

## Files Created

- docs/features/getsongbpm-artist-diacritic-mismatch/ENGINEER_REPORT.md

## Files Modified

- supabase/functions/getsongbpm_lookup/index.ts

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 warnings
Output:

```text
Analyzing bandroadie...
No issues found! (ran in 4.8s)
```

## Test Results

Not run (Architect plan does not require `flutter test` for this edge-function-only change).

## Verification

Manual steps performed:

- Phase 2 slug/path checks:

```text
branch=bug/getsongbpm-artist-diacritic-mismatch
slug=getsongbpm-artist-diacritic-mismatch
plan=docs/features/getsongbpm-artist-diacritic-mismatch/ARCHITECT_PLAN.md
plan_exists=yes
plan_slug=bug/getsongbpm-artist-diacritic-mismatch
slug_match=yes
```

- Pre-deploy Test 1 (Architect command):

```text
zsh: command not found: deno
```

Equivalent JavaScript runtime smoke test (Node) executed successfully:

```text
normalize_artist_smoke_node_equivalent=pass
```

- Pre-deploy Test 2 (key-normalization vocabulary isolation):

```text
49:const VALID_MAJOR_KEYS = new Set(['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']);
50:const VALID_MINOR_KEYS = new Set(['Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'Abm', 'Am', 'Bbm', 'Bm']);
54:const SHARP_TO_FLAT: Record<string, string> = { 'D#': 'Eb', 'G#': 'Ab', 'A#': 'Bb' };
64:function normalizeKey(raw: unknown): string | null {
76:    if (SHARP_TO_FLAT[root]) {
77:        root = SHARP_TO_FLAT[root];
82:    if (isMinor ? VALID_MINOR_KEYS.has(normalized) : VALID_MAJOR_KEYS.has(normalized)) {
198:        const musicalKey = normalizeKey(candidate?.key_of);
```

- Deploy edge function:

```text
Uploading asset (getsongbpm_lookup): supabase/functions/getsongbpm_lookup/deno.json
Uploading asset (getsongbpm_lookup): supabase/functions/getsongbpm_lookup/index.ts
{"project_ref":"nekwjxvgbveheooyorjo","functions":["getsongbpm_lookup"],"dashboard_url":"https://supabase.com/dashboard/project/nekwjxvgbveheooyorjo/functions","message":"Deployed Functions."}
```

- Post-deploy Test 1 (downloaded deployed source and grep verification):

```text
{"function_slugs":["getsongbpm_lookup"],"project_ref":"nekwjxvgbveheooyorjo","message":"Downloaded Edge Function source."}
SRC_FILE=/tmp/edge_fn_getsongbpm_post/supabase/functions/getsongbpm_lookup/index.ts
90:function normalizeArtistName(name: string): string {
92:        .normalize('NFD')
100:        .normalize('NFD')
139:function isArtistVariantMatch(requestArtist: string, candidateArtist: string): boolean {
254:    const normalizedRequestArtist = normalizeArtistName(artist);
260:        const normalized = normalizeArtistName(candidateArtist);
286:                isArtistVariantMatch(artist, candidateArtist);
```

- Post-deploy Test 2 (live runtime probes):
  Diacritic input:

```json
{
  "ok": true,
  "data": {
    "bpm": 152,
    "musicalKey": "F",
    "confidence": "medium"
  }
}
```

ASCII transliteration input:

```json
{
  "ok": true,
  "data": {
    "bpm": 152,
    "musicalKey": "F",
    "confidence": "medium"
  }
}
```

Outcome: both variants return identical non-null `bpm` and `musicalKey`.

- Post-deploy Test 3 (read-only production safety SQL):
  Command attempted:

```text
supabase db query --linked "SELECT ... FROM songs;"
```

Output:

```text
Initialising login role...
{"_tag":"Error","error":{"code":"LegacyDbConfigConnectTempRoleError","message":"failed to connect as temp role: failed to connect to postgres: effect/sql/SqlError: PgClient: Connection timed out","suggestion":"Connect to your database by setting the env var correctly: SUPABASE_DB_PASSWORD"}}
```

Status: blocked by missing `SUPABASE_DB_PASSWORD` in this terminal environment.

## Deviations From Architect Plan

- The exact `deno eval` pre-deploy smoke command could not run because Deno is not installed in this shell. An equivalent JavaScript runtime smoke test using Node executed the same normalization logic and passed.
- The exact post-deploy SQL safety query could not complete due missing database password for linked remote query (`SUPABASE_DB_PASSWORD` not available in environment).

## Blockers Encountered

- `deno` binary unavailable in terminal for the exact Architect pre-deploy command.
- `supabase db query --linked` remote access blocked by missing `SUPABASE_DB_PASSWORD` in environment.

## Ready For QA

No (Post-deploy Test 3 could not be completed in this environment due missing database password).
