# QA Report

## Feature Slug

feature/song-enrichment-confidence-scoring

## Feature Title

Song Enrichment Confidence Scoring (Phase B)

## Final Verdict

**REQUIRES CHANGES**

## Validation Summary

I read the Architect plan, Engineer report, and actual working-tree diff on branch `feature/song-enrichment-confidence-scoring`, then ran the required Deno baseline test command in `supabase/functions/getsongbpm_lookup/`. The edge-function unit tests passed, and the implementation uses a direct public iTunes fetch rather than an internal edge-function invoke.

One required recheck did not pass: `index.ts` still contains a `duration_seconds` reference in its header comment, so the stricter no-reference condition the user requested is not fully satisfied. Runtime verification of the new iTunes corroboration path was not possible pre-deploy, so behavior verification here is code-path analysis only.

## Architect Scope Review

- Scope adherence: compliant
- Files modified: as expected
- Files off-limits: not touched

## Completeness Check

- All Architect tasks implemented: yes
- Missing tasks: none

## Behavior Verification

- Validation method: code-path analysis
- Result: mostly matches expected, but the requested no-reference check is not fully satisfied because `supabase/functions/getsongbpm_lookup/index.ts` still contains a stale `duration_seconds` mention in a comment; actual runtime exercise of the deployed iTunes integration was not available pre-deploy

## Regression Check

- Risk level: MEDIUM
- Systems reviewed: Supabase Edge Functions, Setlists / Catalog, Auth / Session, Database
- Regressions found: none in behavior; one stale comment reference blocks approval

## Database Safety

Not applicable

## Analyzer Results

Command: `deno test --allow-env index.test.ts`
Result: 0 errors / 30 tests passed

## Test Results

Passed

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none found
- Unrelated changes: none found

## Code Efficiency Review

- Dead code / unused imports, vars, params: none found in the implementation diff
- Redundant restating comments: found 1 stale `duration_seconds` reference in `supabase/functions/getsongbpm_lookup/index.ts`
- Unnecessary abstraction for single call sites: none found
- Unneeded defensive checks (impossible-case guards, try/catch): none found
- Duplicated logic that should reuse existing code: none found
- Overall assessment: acceptable

## Issues Found

### Warning

1. Remove the stale `duration_seconds` reference from the `supabase/functions/getsongbpm_lookup/index.ts` header comment so the file satisfies the requested no-reference check.

---

## Addendum — Tier 2 Post-Deploy Verification (2026-08-28)

Runtime exercise of the deployed iTunes corroboration path — flagged above as not available pre-deploy — is now confirmed with real evidence from the live function (`getsongbpm_lookup` v19, project `nekwjxvgbveheooyorjo`):

- **Known-good parenthetical case** (`Come Out And Play (Keep 'Em Separated)` / The Offspring): `bpm: 160`, `key: G`, `confidence: medium` (legacy fields unchanged), `bpmConfidence: 95`, `keyConfidence: 95` — the real ceiling, meaning the live iTunes corroboration call succeeded end-to-end (`secondaryTitleMatch`/`secondaryArtistMatch` both true), not just the isolated scoring function.
- **Wrong-version trap** (`Every Rose Has Its Thorn` / Poison): `bpm: 70`, `key: C`, `versionType: null` — correctly the studio entry, not the adjacent "(MTV Unplugged)" candidate (BPM 143, F♯) — confirming Phase A's version-type reject rule still holds under Phase B's added scoring, with `bpmConfidence`/`keyConfidence` again at 95.

Both calls returned `ok: true` with no 5xx, confirming the non-blocking/no-throw contract holds in production. This closes the runtime-verification gap noted in the original Behavior Verification section above.
