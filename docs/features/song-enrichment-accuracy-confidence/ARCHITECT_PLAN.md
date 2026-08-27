# ARCHITECT_PLAN.md

## 1. Feature Slug

`feature/song-enrichment-accuracy-confidence`

Type: feature
Branch: `feature/song-enrichment-accuracy-confidence`
Docs path: `docs/features/song-enrichment-accuracy-confidence/ARCHITECT_PLAN.md`

---

## 0. ⚠️ Pre-Implementation Blockers & Discrepancies (READ FIRST)

Two items from the Feature Input turned out to be inaccurate against the codebase. Per the
directive to flag rather than silently work around them, both are documented here. **Neither
blocks the read-only plan, but item (A) should be confirmed by Tony before the Engineer starts.**

### A. Sibling dependency `feature/song-enrichment-overwrite-existing` was never built; the bpm/musical_key write-once bug is still fully open on `main`

The Feature Input says to confirm `feature/song-enrichment-overwrite-existing` has merged to
`main` before branching, and to stop if it hasn't. Investigation result:

- No branch, commit, tag, or ref named `song-enrichment-overwrite-existing` (or any
  `*overwrite*` variant) exists locally, on `origin`, or across `--all` refs. No
  `docs/features/*overwrite*` directory exists. **The feature was never built.**
- The live version of `update_song_metadata` on `main` is
  `supabase/migrations/20260811120001_revert_update_song_metadata_single_value.sql`. Its header
  states "Restores fill-missing-only CASE logic for bpm/musical_key (**write-once behavior**),"
  and the function body confirms it: `bpm` only updates `WHEN p_bpm IS NOT NULL AND bpm IS NULL`,
  and `musical_key` only updates `WHEN p_musical_key IS NOT NULL AND (musical_key IS NULL OR
  TRIM(musical_key) = '')`. **Existing non-null bpm/musical_key values cannot be overwritten.**
- The bpm/musical_key **overwrite (write-once) bug is therefore still fully open on `main`.** It
  is not fixed, not merged, and not present anywhere in the base this feature branches from.
- The separate `bug/song-duration-edit-silently-fails` branch (migration
  `20260827120000_fix_song_duration_write_once.sql`) fixes the **duration** write-once case only —
  it does not touch the bpm/musical_key CASE gates.
- Note: `SongEnrichmentOrchestrator.enrichSongs()` exposes an `overwriteExisting` client-side
  parameter, but that only controls whether the client *sends* a value; the RPC still refuses to
  overwrite non-null bpm/musical_key server-side. Client intent and server behavior diverge.

**Conclusion:** There is no stale-base merge conflict risk, because the sibling branch does not
exist. But the Feature Input's premise — that the bpm/musical_key overwrite behavior was handled
by a sibling feature already on `main` — is **false**: that bug remains open. This does **not**
change this feature's Phase A/B/C engineering scope: the `update_song_metadata` RPC stays
correctly **off-limits** here (see §11), and fixing the bpm/musical_key write-once behavior
remains a separate, still-unowned piece of work. **Tony should decide whether that RPC bug needs
its own branch** — it is out of scope for this accuracy/confidence feature.

### B. Secondary providers cannot supply BPM or musical key

The Feature Input suggests evaluating `musicbrainz_search` / `itunes_search` to "independently
corroborate BPM and/or musical key." Confirmed against both edge functions:

- `itunes_search` returns only `title`, `artist`, `duration_seconds`, `album_artwork`, `itunes_id`.
- `musicbrainz_search` returns only `title`, `artist`, `duration_seconds`, `release_count`,
  `musicbrainz_id`.

**Neither returns BPM or musical key.** The only provider that ever supplied key/BPM
independently was AcousticBrainz, which the Feature Input confirms is dead (shut down Nov 2022).

**Design consequence (my decision, see §6):** A second source cannot _verify the BPM/key values_.
It can only corroborate **song identity** — i.e., that a track with this title + artist (and
approximately this duration) genuinely exists — which raises confidence that GetSongBPM matched
the _right_ song, and therefore that its BPM/key belong to the requested song. This is a
defensible and honest cross-check, and it directly serves the feature's stated goal ("not picking
the wrong song/version… giving the user visibility — not guaranteeing perfect data").

---

## 2. Problem Summary

BandRoadie's song enrichment (BPM + musical key auto-fill) relies solely on GetSongBPM via
`supabase/functions/getsongbpm_lookup/index.ts`. Three related gaps:

1. **Matching accuracy.** The exact-artist-match branch (`exactArtistMatches`) filters candidates
   by artist name only and performs **no title comparison at all**, unlike the artist-variant
   fallback branch directly below it, which does compare `normalizeTitleName`. `selectBestAvailableMatch`
   then picks any exact-artist candidate with a parseable tempo/key, with no title-similarity and
   no version-type (live/remix/acoustic/cover/demo) filtering. This can pull BPM/key from a
   _different song by the same artist_.
2. **Single source, no cross-check.** No second provider corroborates the match.
3. **Confidence is invisible and binary.** `LookupResult.confidence` is `'medium' | 'none'`,
   never displayed anywhere in the enrichment UI, and carries no real signal.

## 3. Root Cause

| #   | Root cause                                                                                                                                                                                                                                                                                                                                | Confidence                         |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| 1   | `exactArtistMatches` (in `lookupGetSongBpmForTitle`) filters on `normalizeArtistName(candidate.artist.name) === normalizedRequestArtist` **only**; there is no `normalizeTitleName`/`getCandidateTitle` title check, and `selectBestAvailableMatch` ranks solely on tempo/key completeness. A same-artist, wrong-title candidate can win. | **HIGH** — direct code observation |
| 2   | `lookupGetSongBpm` calls only GetSongBPM; there is no corroborating provider call.                                                                                                                                                                                                                                                        | **HIGH**                           |
| 3   | Confidence is a two-value string literal set to `'medium'` on any accepted match and `'none'` otherwise; `song_enrichment_service.dart` parses it as an opaque `String`; no UI reads it.                                                                                                                                                  | **HIGH**                           |

## 4. Reference Docs Consulted

The Architect template hardcodes `docs/reference/notifications/`, which is **orthogonal to this
feature** (this is the songs/enrichment domain, not notifications). The relevant domain reference
set is `docs/reference/bpm/`. Consulted:

- `docs/reference/bpm/BPM_QUICK_REFERENCE.md` — confirms the provider topology; explicitly notes
  `musicbrainz_search` is a "Fallback search (**no BPM data**)".
- `docs/reference/bpm/ACOUSTICBRAINZ_BPM_FEATURE.md`, `BPM_FEATURE_IMPLEMENTATION.md`,
  `BPM_FEATURE_DEPLOYMENT.md` — reviewed; AcousticBrainz path confirmed defunct (matches Feature Input).
- Prior feature plans (regression guardrails):
  - `docs/features/getsongbpm-artist-diacritic-mismatch/ARCHITECT_PLAN.md`
  - `docs/features/getsongbpm-title-fallback-parenthetical/ARCHITECT_PLAN.md`
  - `docs/features/getsongbpm-lookup-partial-match-data/ARCHITECT_PLAN.md`

`docs/reference/notifications/` was **not** read in full for diagnosis — it has no bearing on song
enrichment. Flagged here per Phase 4's "document if absent/inapplicable" rule.

## 5. Existing System Analysis

Current data flow (batch "Enrich Song Data"):

1. UI triggers `SongEnrichmentOrchestrator.enrichSongs()`
   (`lib/features/songs/services/song_enrichment_orchestrator.dart`).
2. Per song needing BPM/key, orchestrator calls `SongEnrichmentService.lookup()`
   (`lib/features/songs/song_enrichment_service.dart`), which invokes the
   `getsongbpm_lookup` edge function.
3. Edge function `lookupGetSongBpm` → `lookupGetSongBpmForTitle`:
   - Builds `lookup=song:<title> artist:<artist>`, `type=both`, queries `https://api.getsong.co`.
   - `exactArtistMatches` = candidates whose normalized artist equals the request **(no title check)**.
   - `bestExactArtistMatch = selectBestAvailableMatch(exactArtistMatches)` → returns
     `confidence: 'medium'` if it has a bpm or key.
   - Only if `exactArtistMatches.length === 0` does it try `artistVariantMatches`, which **does**
     enforce `normalizeTitleName(candidateTitle) === normalizedRequestTitle` **and**
     `isArtistVariantMatch`.
   - Otherwise `noneResult()` (`confidence: 'none'`).
   - One retry via `getPrimaryTitleFallback` (trailing-parenthetical trim) on no match.
4. Orchestrator maps result → `SongEnrichmentDetail` (per-song, per-field `EnrichmentFieldResult`),
   calls `SetlistRepository.enrichSongs()` (which uses the `update_song_metadata` RPC).
5. `enrichment_results_overlay.dart` renders per-song cards with BPM / Dur / Key status badges
   ("Updated" / "Not found" / "Unchanged" / "Error"). **No values, no confidence shown.**

Notable existing scaffolding: `SongEnrichmentDetail` already declares `enrichedBpm`, `enrichedKey`,
`enrichedDuration`, `currentBpm`, `currentKey`, `currentDuration` fields — but the orchestrator
**never populates them** and the overlay never reads them. There is currently **no** confidence
field anywhere in the Flutter models.

Duration path is separate: it comes from `ExternalSongLookupService.searchExternalSongs()` (Spotify
→ iTunes/MusicBrainz), **not** from GetSongBPM.

## 6. Proposed Solution

Because this spans the edge function (matching + scoring + contract), the Flutter models
(carrying confidence), and the UI (display), and because the Feature Input explicitly invites a
phased plan for a change of this size, this is structured as **three phases**. Each phase is
independently implementable, testable, and shippable.

### Design decisions (mine to make, per Feature Input)

**D1 — Title similarity on the exact-artist path.** Add the same title gate the variant branch
already uses. A candidate on the exact-artist path is only eligible if its title matches the
request under a tiered comparison: (a) exact `normalizeTitleName` equality, else (b) equality
against `getPrimaryTitleFallback`-trimmed titles (both sides), else (c) contiguous-word-subsequence
containment (reuse `isContiguousWordSequence` on `normalizeWords`). Candidates failing all three
are rejected from the exact-artist pool. This mirrors the rigor already proven in the variant path.

**D2 — Version-type handling.** Introduce a small classifier `detectVersionType(title)` →
`{ live, remix, acoustic, cover, demo }` flags derived from tokenized title words (e.g. `live`,
`remix`, `acoustic`, `cover`, `demo`, `unplugged`). Rule: if a candidate's title indicates a
version the **request title does not**, the candidate is **rejected** outright (not merely
deprioritized) — this is the highest-signal wrong-match guard. If the request itself indicates a
version, candidates matching that same version are preferred and plain versions are allowed as a
weaker fallback. This applies to both the exact-artist and variant paths.

**D3 — Second source = identity corroboration only (see §0.B).** After GetSongBPM yields a
matched candidate, call **one** secondary provider (recommend `itunes_search` first — cleanest
title/artist/duration, no rate-limit/User-Agent friction; `musicbrainz_search` as an optional
tie-breaker using `release_count` to favor originals). The secondary call:

- Confirms a track with matching normalized title + artist exists → **+corroboration**.
- If GetSongBPM's triggering search provided a duration, and the secondary duration agrees within
  a tolerance (±10 s or ±7%), that is additional corroboration; a gross mismatch (>15%) lowers
  confidence.
- The secondary call is **best-effort and non-blocking**: any failure/timeout contributes zero,
  never an error, and never blocks the BPM/key result (same no-throw contract as today).

**D4 — Disagreement policy.** BPM/key values are **never discarded** on mere lack of
corroboration (secondary sources can't judge BPM/key correctness). Instead, absence or
contradiction of identity corroboration **lowers the confidence percentage** and lets the user
decide. The **only** outright rejection is D2 version-type mismatch. This honors the Feature
Input's "give the user visibility, not guarantee perfect data."

**D5 — Confidence score (0–100, per field).** Computed in the edge function from real signals:

| Signal                                                  | Contribution |
| ------------------------------------------------------- | ------------ |
| Title: exact `normalizeTitleName` match                 | +50          |
| Title: parenthetical-fallback match                     | +38          |
| Title: contiguous-word containment only                 | +25          |
| Artist: exact normalized match                          | +25          |
| Artist: variant match                                   | +15          |
| Version-type: request & candidate agree (or both plain) | +10          |
| Secondary source confirms title+artist identity         | +10          |
| Secondary source duration agrees (±tolerance)           | +5           |
| Secondary source duration grossly disagrees (>15%)      | −15          |

Clamp to `[0, 100]`. **Per-field application:**

- **BPM confidence** = the match-identity score above (BPM is only present if a candidate matched).
- **Key confidence** = same identity score, but `null` if the key failed `normalizeKey` (so a
  fetched BPM can read high while an unresolved key reads as "no key" rather than false confidence).
- **Duration confidence** = a lighter, separate score computed in the orchestrator from the
  duration provider path (exact title/artist agreement of the chosen external result), since
  duration does not flow through GetSongBPM. Phase C treats duration confidence as optional; if
  not implemented, the UI simply omits a % for duration rather than showing a fabricated number.

The weights are a **proposed starting point** the Engineer implements as named constants; they are
tunable and must not be treated as sacred. The requirement is that the number derives from these
real signals, not a cosmetic constant.

**D6 — Non-breaking response contract.** Do **not** change the meaning of the existing
`confidence: 'medium' | 'none'` field (older clients rely on `=== 'none'`). **Add** fields
additively:

```jsonc
data: {
  bpm: number | null,
  musicalKey: string | null,
  confidence: 'medium' | 'none',   // unchanged, back-compat
  bpmConfidence: number | null,    // 0–100, null when no bpm
  keyConfidence: number | null,    // 0–100, null when no/unnormalizable key
  matchTitle: string | null,       // the candidate title actually matched (for UI/debug)
  versionType: string | null       // e.g. 'live' when request itself was a live version
}
```

The Flutter client reads the new fields when present and ignores them when absent, so Phase A/B
can deploy before Phase C ships.

### Phase breakdown

- **Phase A — Matching accuracy (edge function only).** D1 + D2. No contract change, no client
  change. Immediately reduces wrong-song/wrong-version matches. Lowest risk. Independently
  shippable and independently valuable.
- **Phase B — Second-source cross-check + numeric confidence (edge function).** D3 + D4 + D5 + D6.
  Additive response fields; still no _required_ client change (client ignores unknown fields).
- **Phase C — Surface confidence % in the UI (Flutter).** Thread `bpmConfidence`/`keyConfidence`
  (and optional duration confidence) through `SongEnrichmentService` → orchestrator →
  `SongEnrichmentDetail` → `enrichment_results_overlay.dart`, displaying a per-field percentage on
  each song card. Optionally surface it on `song_enrichment_review_sheet.dart` (single new-song
  flow) — treated as a stretch within Phase C, not required.

**Recommended sequencing:** A → B → C, each behind its own QA gate. A can merge and deploy alone.

### What must NOT change (regression guardrails)

- `normalizeArtistName` (diacritic transliteration — shipped by
  `getsongbpm-artist-diacritic-mismatch`; do not revert to ASCII-strip).
- `getPrimaryTitleFallback` and the single trailing-parenthetical retry (shipped by
  `getsongbpm-title-fallback-parenthetical`).
- `isArtistVariantMatch`, `isContiguousWordSequence`, `normalizeWords`, `normalizeTitleName`
  (may be **reused** but not altered in signature/behavior).
- `normalizeKey`, `SHARP_TO_FLAT`, `VALID_MAJOR_KEYS`, `VALID_MINOR_KEYS` (24-key vocabulary).
- The no-throw, degrade-to-`none`, never-block-the-UI contract.
- The existing `confidence: 'medium' | 'none'` field meaning.
- The `update_song_metadata` RPC and `SetlistRepository.enrichSongs()` (owned by the write-once
  bug fix — out of scope here).

## 7. Database Impact

**Database: not applicable.**

- Migrations: none. This feature does not alter schema, RLS, RPCs, or triggers.
- The `update_song_metadata` RPC used by `enrichSongs()` is **off-limits** (owned by
  `bug/song-duration-edit-silently-fails`).
- Edge function deploys: **required** for Phase A and Phase B (`getsongbpm_lookup`). No new
  secrets required for `itunes_search`/`musicbrainz_search` (public APIs, already deployed).

## 8. Flutter Architecture Changes

- **Phase A / B:** none.
- **Phase C:**
  - `SongEnrichmentResult` (`song_enrichment_service.dart`): add nullable `bpmConfidence`,
    `keyConfidence` (int?), parsed additively from the response.
  - `SongEnrichmentDetail` (`song_enrichment_orchestrator.dart`): add nullable per-field
    confidence fields; **populate** them (and the already-declared `enrichedBpm`/`enrichedKey`)
    from the lookup result. No new provider, controller, or state class.
  - `enrichment_results_overlay.dart`: render a per-field `NN%` on each badge/card. Presentation
    only; no new state, no new provider.
  - No changes to Riverpod providers, repositories (beyond reading new fields), routing, or init
    order.

## 9. Files to Create

**none** — all changes are in-place edits to existing files.

## 10. Files to Modify

| File                                                              | Phase       | What changes                                                                                                                                                                          |
| ----------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/functions/getsongbpm_lookup/index.ts`                   | A           | Add title-similarity gate to the exact-artist-match path (D1); add `detectVersionType` + version-type reject/prefer logic to both match paths (D2). Reuse existing helpers unchanged. |
| `supabase/functions/getsongbpm_lookup/index.ts`                   | B           | Add best-effort secondary identity corroboration call (D3); compute per-field numeric confidence (D5); add additive response fields (D6). No change to existing field meanings.       |
| `lib/features/songs/song_enrichment_service.dart`                 | C           | Parse additive `bpmConfidence`/`keyConfidence` into `SongEnrichmentResult`.                                                                                                           |
| `lib/features/songs/services/song_enrichment_orchestrator.dart`   | C           | Carry confidence + enriched values into `SongEnrichmentDetail`.                                                                                                                       |
| `lib/features/songs/widgets/enrichment_results_overlay.dart`      | C           | Display per-field confidence percentage per song.                                                                                                                                     |
| `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` | C (stretch) | Optionally surface confidence for the single new-song review flow.                                                                                                                    |

## 11. Files Off-Limits

| File                                                                                                                    | Reason                                                                                                                           |
| ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_repository.dart`                                                                         | `enrichSongs()` / `update_song_metadata` path is owned by `bug/song-duration-edit-silently-fails`. Do not modify the write path. |
| `supabase/migrations/**`                                                                                                | No DB change in scope.                                                                                                           |
| `supabase/functions/musicbrainz_search/index.ts`, `supabase/functions/itunes_search/index.ts`                           | Consumed read-only as corroboration providers; do not modify their contracts.                                                    |
| `supabase/functions/acousticbrainz_bpm/**`                                                                              | Dead provider — do not use or resurrect.                                                                                         |
| `lib/main.dart`                                                                                                         | Init order must not change.                                                                                                      |
| Shared helpers `normalizeArtistName`, `getPrimaryTitleFallback`, `isArtistVariantMatch`, `normalizeKey`, `VALID_*_KEYS` | Shipped, regression-sensitive; reuse only, do not alter.                                                                         |

## 12. System Impact Map

| System                                 | Impact                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------ |
| Gigs                                   | unaffected                                                               |
| Rehearsals                             | unaffected                                                               |
| Setlists / Catalog                     | affected (enrichment accuracy + results UI)                              |
| Members / RBAC                         | unaffected                                                               |
| Auth / Session                         | unaffected                                                               |
| Routing                                | unaffected                                                               |
| Notifications                          | unaffected                                                               |
| Platform (iOS / Android / Web / macOS) | affected (Phase C UI renders on all; edge changes are platform-agnostic) |
| Supabase Edge Functions                | affected (`getsongbpm_lookup` deploy)                                    |
| Database (schema/RLS/RPC)              | unaffected                                                               |

## 13. Regression Risk

**Overall: MEDIUM.**

- Phase A: **LOW–MEDIUM** — tightens matching; risk is _over_-rejecting valid matches (false
  negatives). Mitigated by the tiered title comparison (exact → fallback → containment) so
  legitimate variations still pass, and by preserving the variant-fallback path.
- Phase B: **MEDIUM** — adds an external call and new scoring. Non-blocking/best-effort design
  bounds the blast radius; additive contract avoids breaking existing clients.
- Phase C: **LOW** — presentational; no state/routing/init/DB changes.
- No auth, session, routing, init-order, or DB mutations touched. Shared regression-sensitive
  helpers are reuse-only.

## 14. Engineer Task Breakdown

**Phase A (edge function — matching accuracy):**

1. Add `detectVersionType(title): { live, remix, acoustic, cover, demo }` using `normalizeWords`
   token membership. Pure helper; no external state.
2. Add a `titleSimilarity(requestTitle, candidateTitle)` tiered check reusing
   `normalizeTitleName`, `getPrimaryTitleFallback`, `getCandidateTitle`, `isContiguousWordSequence`
   → returns a tier: `exact | fallback | contains | none`.
3. In `lookupGetSongBpmForTitle`, filter `exactArtistMatches` to also require `titleSimilarity !== none`.
4. Apply D2 version-type reject/prefer rules to both the exact-artist and artist-variant pools.
5. Keep `selectBestAvailableMatch`, response contract, and confidence semantics unchanged in Phase A.
6. Update the header comment block and log lines to reflect the added title/version gating.

**Phase B (edge function — cross-check + confidence):** 7. Add a best-effort secondary identity lookup (recommend `itunes_search`) invoked with the
Supabase service client already available in the function; wrap in try/catch, short timeout,
contribute zero on failure. 8. Implement `computeConfidence(signals)` returning `bpmConfidence` / `keyConfidence` per D5 with
named constant weights; clamp `[0,100]`; `keyConfidence = null` when key unnormalizable. 9. Extend the response `data` with `bpmConfidence`, `keyConfidence`, `matchTitle`, `versionType`
(additive; leave `confidence` string untouched).

**Phase C (Flutter — surface confidence):** 10. Parse new fields into `SongEnrichmentResult` (nullable ints). 11. Thread confidence + enriched values into `SongEnrichmentDetail` in the orchestrator. 12. Render per-field `NN%` in `enrichment_results_overlay.dart` (hide when null). 13. (Stretch) Surface confidence in `song_enrichment_review_sheet.dart`.

## 15. Verification Plan

**Database: not applicable — there are no SQL migrations in this feature.** The two-tier
pre/post-`db push` SQL protocol does not apply. Verification is edge-function + Flutter behavior
testing. (Tier labels retained below for process compliance.)

**Tier 1 — Pre-deploy (before `supabase functions deploy getsongbpm_lookup`):**

- `-- PRE-DEPLOY TEST 1:` Unit-test the new pure helpers (`detectVersionType`, `titleSimilarity`,
  `computeConfidence`) locally with `deno test` or equivalent, against fixture candidates:
  same-artist/different-title (must reject), exact match (must accept, high confidence),
  live-vs-studio (must reject when request is studio), parenthetical-subtitle (must still match
  via fallback tier — regression guard for `getsongbpm-title-fallback-parenthetical`),
  diacritic artist (must still match — regression guard for `getsongbpm-artist-diacritic-mismatch`).
- `-- PRE-DEPLOY TEST 2:` Confirm existing `confidence: 'medium' | 'none'` outputs are unchanged
  for previously-passing fixtures (no contract regression).

**Tier 2 — Post-deploy (after `supabase functions deploy`):**

- `-- POST-DEPLOY TEST 1:` Live-invoke `getsongbpm_lookup` for a known good case (e.g.
  `Come Out And Play (Keep 'Em Separated)` / `The Offspring`) → still returns usable data
  (parenthetical fallback intact) and now a `bpmConfidence` number.
- `-- POST-DEPLOY TEST 2:` Live-invoke a same-artist/wrong-title pairing that previously
  mismatched → confirm it now returns `none` or a materially lower confidence, not the wrong
  song's BPM/key.
- `-- POST-DEPLOY TEST 3:` Confirm the secondary provider path degrades silently (temporarily
  force it to fail) — BPM/key still returned, confidence just lower; no 5xx, no thrown error.

## 16. QA Regression Areas

- **Primary:** Run "Enrich Song Data" on a catalog with (a) an exact-title song, (b) a
  same-artist-different-title song, (c) a live/remix-titled song, (d) a parenthetical-subtitle
  title, (e) a diacritic-artist song. Verify correct match/reject behavior and that (d) and (e)
  still succeed (no regression of the two shipped fixes).
- Confirm the results overlay shows a per-field confidence % that varies meaningfully between
  exact and fuzzy matches (not a constant).
- Confirm enrichment never blocks or errors when the secondary provider is slow/unavailable.
- Confirm `confidence: 'none'` songs still render "Not found" exactly as before.
- Confirm the single new-song review sheet still fetches and pre-fills BPM/key (Phase C stretch
  only changes display, not fetch).
- Cross-platform render check of the new % on Web / iOS / Android / macOS.
- Confirm no change to the duration path behavior or the `update_song_metadata` write path.

## 17. Rollout / Migration Strategy

- Ship in phase order A → B → C, each behind its own QA APPROVED gate and its own edge deploy
  (A and B) / web+app release (C).
- Because the response contract is additive (D6), Phase A/B edge deploys are safe with the current
  production client (unknown fields ignored). Phase C client can ship any time after B is live.
- Edge deploy: `supabase functions deploy getsongbpm_lookup`. No secrets, no migration.
- No data backfill: this changes future enrichment runs only; previously-written values are
  untouched.

## 18. Out of Scope

- Fixing GetSongBPM's own source-data quality (e.g. the "Every Rose Has Its Thorn" wrong-key
  case) — bad provider data, explicitly excluded.
- Resurrecting or using AcousticBrainz (dead provider).
- The `update_song_metadata` write-once RPC bug — the **duration** case is owned by
  `bug/song-duration-edit-silently-fails`; the **bpm/musical_key** write-once case is still open
  and unowned on `main` (see §0.A) and is not addressed here.
- Any change to Spotify/duration lookup contracts beyond read-only corroboration use.
- Overwrite-existing (write-once) behavior for bpm/musical_key — **not present in `main`**; still
  a separate open bug (see §0.A), out of scope for this feature.
- New provider _credentials_ or paid providers — the cross-check reuses existing free/public
  functions only.
