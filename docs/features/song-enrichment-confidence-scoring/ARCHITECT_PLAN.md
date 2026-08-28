# ARCHITECT_PLAN.md

## 1. Feature Slug

`feature/song-enrichment-confidence-scoring`

Type: feature
Branch: `feature/song-enrichment-confidence-scoring`
Docs path: `docs/features/song-enrichment-confidence-scoring/ARCHITECT_PLAN.md`

---

## 2. Problem Summary

`getsongbpm_lookup` still behaves like a single-source matcher. It returns BPM and musical key from GetSongBPM with only a binary confidence flag (`'medium' | 'none'`), so callers cannot tell whether a match was strongly corroborated or only barely acceptable. Phase A already tightened the match gate itself, but Phase B still needs a second-source identity cross-check and a real numeric confidence score that can be returned additively without changing the existing response semantics.

---

## 3. Root Cause

| Root cause                                                                                                                                                                                            | Confidence                                                                                                                      |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ---- |
| `supabase/functions/getsongbpm_lookup/index.ts` has no secondary corroboration step after GetSongBPM returns a candidate, so the function cannot distinguish a strong identity match from a weak one. | HIGH                                                                                                                            |
| The response contract only exposes `confidence: 'medium'                                                                                                                                              | 'none'`; there are no numeric per-field confidence fields and no `matchTitle`/`versionType` metadata for downstream visibility. | HIGH |
| The only available secondary providers in this repo, `itunes_search` and `musicbrainz_search`, are metadata-only and return no BPM or musical key, so they can corroborate identity only.             | HIGH                                                                                                                            |

---

## 4. Reference Docs Consulted

No notification-domain reference docs were relevant to this feature. The BPM references and parent phase plan were the applicable sources:

- `docs/reference/bpm/BPM_QUICK_REFERENCE.md`
- `docs/reference/bpm/BPM_FEATURE_IMPLEMENTATION.md`
- `docs/reference/bpm/BPM_FEATURE_DEPLOYMENT.md`
- `docs/reference/bpm/ACOUSTICBRAINZ_BPM_FEATURE.md`
- `docs/features/song-enrichment-accuracy-confidence/ARCHITECT_PLAN.md`

Confirmed from live code/config while reading those references:

- `supabase/functions/itunes_search/index.ts` returns `title`, `artist`, `duration_seconds`, `album_artwork`, `itunes_id`.
- `supabase/functions/musicbrainz_search/index.ts` returns `title`, `artist`, `duration_seconds`, `release_count`, `musicbrainz_id`.
- `supabase/config.toml` keeps both functions on `verify_jwt = true`.

---

## 5. Existing System Analysis

Current flow for song enrichment:

1. `SongEnrichmentService.lookup()` in `lib/features/songs/song_enrichment_service.dart` calls `supabase.functions.invoke('getsongbpm_lookup')`.
2. `supabase/functions/getsongbpm_lookup/index.ts` queries `https://api.getsong.co` with `song:<title> artist:<artist>`.
3. Phase A logic already filters exact-artist candidates by title similarity and rejects version mismatches, then returns the best candidate with `confidence: 'medium'` if BPM or key is present.
4. If no usable primary match exists, the function retries once on the parenthetical title fallback and otherwise returns `confidence: 'none'`.
5. The edge function currently returns only `{ bpm, musicalKey, confidence }`. There is no `matchTitle`, no `versionType`, no per-field numeric confidence, and no secondary corroboration path.
6. `itunes_search` and `musicbrainz_search` are separate read-only edge functions invoked from the Flutter lookup layer, not from `getsongbpm_lookup`. They supply metadata only and cannot validate BPM/key values.

The live code also shows `getsongbpm_lookup` already reads `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`, so a server-side corroboration fetch can be added without new secrets or config paths.

---

## 6. Proposed Solution

Implement Phase B only, in `supabase/functions/getsongbpm_lookup/index.ts`, with tests in the existing edge-function test file.

What changes:

- Add a best-effort secondary identity lookup against `itunes_search` after GetSongBPM yields a candidate.
- Make that secondary call non-blocking and no-throw: wrap it in `try/catch`, enforce a short timeout, and treat any failure as zero contribution to confidence.
- Compute `bpmConfidence` and `keyConfidence` from named signal weights using a new pure `computeConfidence(signals)` helper.
- Extend the response additively with `bpmConfidence`, `keyConfidence`, `matchTitle`, and `versionType` while leaving `confidence: 'medium' | 'none'` unchanged.

What the live repo check showed:

- `grep` across `supabase/functions/` found no existing server-to-server edge-function pattern using `Authorization: Bearer ...`.
- `itunes_search/index.ts` already talks to the public iTunes API directly and does not require auth, so the corroboration step should mirror that and avoid making `itunes_search` a runtime dependency.

What must not change:

- The primary GetSongBPM match logic from Phase A.
- The meaning of the existing `confidence` field.
- The returned BPM/key values on a valid primary match.
- The behavior of `itunes_search` and `musicbrainz_search` contracts.
- Any Flutter/Dart code in this phase.
- Any database schema, RLS, RPC, or trigger behavior.

Design details:

- Use direct server-side fetch from `getsongbpm_lookup` to `https://itunes.apple.com/search` with `term`, `entity=song`, and `limit` query params, mirroring the existing iTunes edge-function shape without invoking that edge function at runtime.
- Score with named constants, clamp to `[0, 100]`, and keep the score deterministic from the same signal set every time.
- Apply the score per field: `bpmConfidence` and `keyConfidence` should be `null` when the corresponding field is absent; `keyConfidence` should also be `null` when the key cannot be normalized to the app vocabulary.
- Populate `matchTitle` with the selected candidate title, and `versionType` with the accepted version label when one exists, otherwise `null`.
- Secondary-source absence or disagreement must lower confidence, never suppress a valid BPM/key result.

---

## 7. Database Impact

Not applicable.

- No migrations.
- No schema changes.
- No RLS changes.
- No RPC changes.
- No trigger changes.
- No database writes.

Edge function deploy: required for `getsongbpm_lookup`.

---

## 8. Flutter Architecture Changes

None in this phase.

The new fields are intentionally additive so the current Flutter client can ignore them safely. A later Phase C can read and display `bpmConfidence` / `keyConfidence` without changing this phase's backend contract.

---

## 9. Files to Create

none

---

## 10. Files to Modify

| File                                                 | What changes                                                                                                                                                           |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/functions/getsongbpm_lookup/index.ts`      | Add the best-effort `itunes_search` corroboration call, the confidence-scoring helper, and the additive response fields. Keep the legacy `confidence` field untouched. |
| `supabase/functions/getsongbpm_lookup/index.test.ts` | Add unit coverage for confidence scoring, timeout/failure degradation, and additive response-contract behavior.                                                        |

---

## 11. Files Off-Limits

| File                                                   | Reason                                                                                               |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `lib/**/*.dart`                                        | Phase C is explicitly out of scope; no Flutter/UI changes in this phase.                             |
| `lib/features/setlists/setlist_repository.dart`        | Song write-path and `update_song_metadata` behavior are owned by a separate feature.                 |
| `supabase/migrations/**`                               | No database change is required.                                                                      |
| `supabase/functions/itunes_search/index.ts`            | Referenced only as the existing shape to mirror; not a runtime dependency and must remain unchanged. |
| `supabase/functions/musicbrainz_search/index.ts`       | Read-only reference source; contract must remain unchanged.                                          |
| `supabase/functions/acousticbrainz_bpm/**`             | Dead provider; do not resurrect or depend on it.                                                     |
| `supabase/config.toml`                                 | `verify_jwt` is already confirmed for the relevant functions; no config change is needed.            |
| `docs/features/song-enrichment-accuracy-confidence/**` | Parent plan is the reference only; do not edit or append to it.                                      |

---

## 12. System Impact Map

| System                                 | Impact                                                                                    |
| -------------------------------------- | ----------------------------------------------------------------------------------------- |
| Setlists / Catalog                     | affected                                                                                  |
| Members / RBAC                         | unaffected                                                                                |
| Auth / Session                         | unaffected                                                                                |
| Routing                                | unaffected                                                                                |
| Notifications                          | unaffected                                                                                |
| Platform (iOS / Android / Web / macOS) | unaffected in this phase; the backend response is additive and the UI does not change yet |
| Supabase Edge Functions                | affected                                                                                  |
| Database                               | unaffected                                                                                |

---

## 13. Regression Risk

**Overall: MEDIUM.**

Reasoning: this phase changes the lookup function's runtime behavior by adding a second outbound call and new scoring logic, but it remains additive, non-blocking, and database-free. The main risks are accidental timeout regressions or overly aggressive scoring, both of which are contained by the no-throw requirement and by preserving the existing primary BPM/key result path.

---

## 14. Engineer Task Breakdown

1. Add a best-effort `itunes_search` corroboration helper inside `supabase/functions/getsongbpm_lookup/index.ts` that uses a short timeout, parses title/artist/duration metadata, and contributes zero on any failure.
2. Add a pure `computeConfidence(signals)` helper with named weights, clamping, and null handling for missing or unnormalizable fields.
3. Extend the selected response object with `bpmConfidence`, `keyConfidence`, `matchTitle`, and `versionType` while preserving the existing `confidence` string exactly as-is.
4. Update the edge-function tests to cover exact-match, fuzzy-match, timeout/failure, null-key, and additive-contract cases.

---

## 15. Verification Plan

Database: not applicable. There are no SQL migrations in this feature, so the pre/post-deployment SQL protocol does not apply.

### Tier 1 — Pre-deployment (before `supabase functions deploy getsongbpm_lookup`):

- `-- PRE-DEPLOY TEST 1:` Run the edge-function unit tests for the pure scoring helpers and fixture-based match cases. Confirm exact-title/exact-artist results score higher than fuzzy containment results, and confirm the score is always clamped to `[0, 100]`.
- `-- PRE-DEPLOY TEST 2:` Run a mocked failure/timeout test for the secondary iTunes lookup. Confirm the primary BPM/key result is still returned unchanged, the failure contributes zero, and no exception escapes the helper.
- `-- PRE-DEPLOY TEST 3:` Run a response-contract snapshot test that confirms `confidence` still only returns `'medium'` or `'none'`, and the new `bpmConfidence`, `keyConfidence`, `matchTitle`, and `versionType` fields are additive only.

### Tier 2 — Post-deployment (after `supabase functions deploy getsongbpm_lookup` succeeds):

- `-- POST-DEPLOY TEST 1:` Live-invoke `getsongbpm_lookup` for a known good parenthetical-fallback case and verify the legacy fields still match current behavior while the new additive fields are present and populated.
- `-- POST-DEPLOY TEST 2:` Live-invoke a same-artist / wrong-title or wrong-version case that previously produced a risky match and verify the function does not return the wrong candidate's BPM/key, with confidence lower or no match as appropriate.
- `-- POST-DEPLOY TEST 3:` Live-invoke a case where the secondary corroboration path is unavailable or fails and confirm the function still returns the primary BPM/key response without a 5xx or thrown error.
- `-- POST-DEPLOY TEST 4:` Confirm there is no production data mutation to verify, because this phase is read-only. No SQL production verification query applies.

SQL test authoring rules are unchanged for future phases that do touch the database: any data-changing test must roll back or clean up, and any modified-row test must restore original values in all code paths.

---

## 16. QA Regression Areas

- Exact-title / exact-artist enrichment still returns the same BPM/key as before.
- Same-artist but wrong-title cases do not gain a false sense of certainty from the new score.
- Live / remix / acoustic / cover / demo gating from Phase A still behaves exactly as shipped.
- Parenthetical fallback still matches the intended track.
- Diacritic artist matching still works.
- Direct iTunes API fetch failures do not block or error the lookup.
- The legacy `confidence` field still reads as `'medium'` or `'none'` only.
- The current Flutter client ignores the additive fields safely until Phase C.

---

## 17. Rollout / Migration Strategy

- Deploy `getsongbpm_lookup` only.
- No migration, no client release, and no schema change are required for this phase.
- Because the response is additive, the current production Flutter app can remain on the same build while the backend ships.
- Phase C can consume `bpmConfidence` and `keyConfidence` later without revisiting this backend contract.

---

## 18. Out of Scope

- Any `.dart` file change, including the Phase C UI surfacing work.
- Any change to `supabase/functions/itunes_search/index.ts` or `supabase/functions/musicbrainz_search/index.ts`.
- Any use of AcousticBrainz or other dead / new providers.
- Any database migration, RLS, RPC, or trigger change.
- Any change to `update_song_metadata` or `lib/features/setlists/setlist_repository.dart`.
- Any non-additive response-contract change that would alter the meaning of `confidence`.
- Any effort to surface the new confidence fields in Flutter before Phase C.
