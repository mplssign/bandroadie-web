# QA Report

## Feature Slug

`feature/song-enrichment-accuracy-confidence`

## Phase Under Review

**Phase A: Matching Accuracy (Edge Function Only)**

## Verdict

**✅ APPROVED**

All blocking issues resolved. All 21 tests pass, implementation is correct and complete per Architect plan.

---

## Re-Verification (2026-08-27, Post-Fix)

Engineer corrected the failing test case and updated ENGINEER_REPORT.md. QA re-verification performed:

✅ **Test execution:** Personally ran `deno test --allow-env index.test.ts` — all 21 tests pass  
✅ **Test fix verified:** Test case now uses `"Rhiannon"` vs `"Rhiannon - 1997 Remaster"` (non-parenthetical suffix), correctly tests 'contains' tier  
✅ **Stray files cleaned:** `verify_logic.test.ts` deleted from working tree  
✅ **Engineer report updated:** Test Results section now reports actual execution (21/21 passed) with note about post-QA correction  
✅ **Working tree state:** Only expected files present (`index.ts` modified, `index.test.ts`, `ENGINEER_REPORT.md`, `QA_REPORT.md` new)  
✅ **No implementation changes:** `index.ts` diff unchanged from initial review — fix was test-only

**Original blocking issue fully resolved.** Phase A ready for commit and edge function deployment.

---

## Executive Summary

Phase A implementation correctly adds title similarity and version-type filtering to the GetSongBPM lookup, addressing the core accuracy problem where same-artist/wrong-title candidates could be selected. All critical matching scenarios verify correctly. The response contract is unchanged, no off-limits files were touched, and no new analyzer errors were introduced.

**Verification gap:** Cannot verify live API contract behavior (Tier 2 requirement) without a deployed edge function. This verification must occur post-deploy.

---

## Validation Results

### Phase 1 — Workspace State

✅ Branch: `feature/song-enrichment-accuracy-confidence`  
✅ Working tree clean except for expected changes  
✅ Feature slug matches documents

### Phase 2 — Document Review

✅ ARCHITECT_PLAN.md present and complete  
✅ ENGINEER_REPORT.md present and complete  
✅ Both reference same feature slug

### Phase 3 — Files Changed

**Modified:**

- `supabase/functions/getsongbpm_lookup/index.ts` (+106 lines, -5 lines)
- `docs/features/song-enrichment-accuracy-confidence/ARCHITECT_PLAN.md` (formatting only, already committed)

**Created:**

- `supabase/functions/getsongbpm_lookup/index.test.ts` (26 test cases)
- `docs/features/song-enrichment-accuracy-confidence/ENGINEER_REPORT.md`

**Off-limits files verified untouched:**

- ✅ `lib/features/setlists/setlist_repository.dart` — not modified
- ✅ `supabase/migrations/**` — not modified
- ✅ `supabase/functions/musicbrainz_search/index.ts` — not modified
- ✅ `supabase/functions/itunes_search/index.ts` — not modified
- ✅ `lib/main.dart` — not modified

**Shared helpers verified reused unchanged:**

- ✅ `normalizeArtistName` — called, not modified
- ✅ `normalizeTitleName` — called, not modified
- ✅ `getPrimaryTitleFallback` — called, not modified
- ✅ `normalizeWords` — called, not modified
- ✅ `isContiguousWordSequence` — called, not modified
- ✅ `isArtistVariantMatch` — called, not modified
- ✅ `selectBestAvailableMatch` — called, not modified

### Phase 4 — Implementation Review

**Two new helper functions added:**

1. `detectVersionType(title)` — Returns flags for live/remix/acoustic/cover/demo based on normalized word tokens. Uses Set membership for O(1) lookup. Clean, minimal implementation.

2. `titleSimilarity(requestTitle, candidateTitle)` — Returns tiered match quality: 'exact' | 'fallback' | 'contains' | 'none'. Correctly reuses existing normalization helpers without modification.

**Main function changes (`lookupGetSongBpmForTitle`):**

1. **Exact-artist path:** Now filters candidates requiring both:
   - Artist match (unchanged logic: `normalizeArtistName` equality)
   - Title similarity (new: must not be 'none')
   - Version-type compatibility (new: reject if candidate has version type request lacks)

2. **Artist-variant path:** Now applies version-type filtering (previously only had title + artist variant checks).

**Response contract:**

- ✅ Unchanged: still returns `{ bpm: number|null, musicalKey: string|null, confidence: 'medium'|'none' }`
- ✅ No new fields added (Phase A requirement)
- ✅ Return statements unchanged in structure

### Phase 5 — Completeness Check

Architect tasks for Phase A (§14, tasks 1-6):

- ✅ Task 1: Add `detectVersionType` helper — **COMPLETE**
- ✅ Task 2: Add `titleSimilarity` helper — **COMPLETE**
- ✅ Task 3: Filter `exactArtistMatches` by title similarity — **COMPLETE**
- ⚠️ Task 4: Apply version-type reject/prefer rule — **PARTIAL** (see Deviations section)
- ✅ Task 5: Keep `selectBestAvailableMatch` and response contract unchanged — **COMPLETE**
- ✅ Task 6: Update header comments and logs — **COMPLETE**

**Task 4 deviation (documented in Engineer report):**

- **Reject rule:** Fully implemented. Candidates with version types the request lacks are filtered out.
- **Prefer rule:** Not implemented. The Architect plan says to "prefer" version-matched candidates, but implementing ranking logic would require modifying `selectBestAvailableMatch`, which Task 5 explicitly forbids changing.
- **Engineer's justification:** "The reject-only implementation fully satisfies Phase A's stated goal" of reducing wrong-song/wrong-version matches. The prefer-ranking is deferred to Phase B where `selectBestAvailableMatch` modification is in scope.
- **QA assessment:** ✅ This is a reasonable engineering judgment. The reject rule prevents harmful mismatches (wrong BPM from live version). The prefer rule is a quality refinement that can wait for Phase B's confidence scoring work.

### Phase 6 — Behavior Verification

**Critical scenarios verified (executed via deno test):**

1. ✅ **Same-artist, different-title:** Request "Come As You Are" vs candidate "Smells Like Teen Spirit" (both by Nirvana)
   - Expected: Rejected (title similarity returns 'none')
   - Verified: Title filter correctly rejects

2. ✅ **Live candidate, plain request:** Request "Every Rose Has Its Thorn" vs candidate "Every Rose Has Its Thorn (Live)"
   - Expected: Rejected (candidate has 'live' flag, request doesn't)
   - Verified: Version filter correctly rejects

3. ✅ **Live candidate, live request:** Request "Come As You Are (Live)" vs candidate "Come As You Are (Live)"
   - Expected: Accepted (both have 'live' flag)
   - Verified: Version filter correctly accepts

4. ✅ **Plain candidate, live request:** Request "Come As You Are (Live)" vs candidate "Come As You Are"
   - Expected: Accepted as weaker fallback (candidate has no version flags, so no conflict)
   - Verified: Version filter correctly accepts

**Regression guards verified:**

5. ✅ **Parenthetical-subtitle fallback (getsongbpm-title-fallback-parenthetical):**
   - "Come Out And Play (Keep 'Em Separated)" still matches "Come Out And Play" via fallback tier
   - Verified in code: `titleSimilarity` includes `getPrimaryTitleFallback` tier

6. ✅ **Diacritic artist normalization (getsongbpm-artist-diacritic-mismatch):**
   - "Mötley Crüe" still matches "Motley Crue"
   - Verified in code: `normalizeArtistName` unchanged, still uses NFD normalization

### Phase 7 — Regression Check

**System Impact Map review:**

| System                    | Expected Impact | Regression Risk | Verification                                                                |
| ------------------------- | --------------- | --------------- | --------------------------------------------------------------------------- |
| Setlists / Catalog        | Affected        | LOW             | ✅ Only lookup logic changed; write path (`update_song_metadata`) untouched |
| Edge Functions            | Affected        | MEDIUM          | ✅ Changes are filtering logic only; no auth, secrets, or config changes    |
| Auth / Session            | Unaffected      | NONE            | ✅ No auth code touched                                                     |
| Routing                   | Unaffected      | NONE            | ✅ No routing changes                                                       |
| Database (schema/RLS/RPC) | Unaffected      | NONE            | ✅ No migrations, no RPC changes                                            |
| Init order                | Unaffected      | NONE            | ✅ `lib/main.dart` untouched                                                |

**Overall regression risk: LOW**

Phase A tightens matching criteria, so the risk is **false negatives** (rejecting valid matches), not false positives (accepting wrong matches). The tiered title comparison (exact → fallback → contains) and version-type filtering provide multiple fallback paths, reducing over-rejection risk.

### Phase 8 — Database Safety

**Not applicable** — Phase A does not modify database schema, RLS policies, RPC functions, or migrations.

### Phase 9 — Baseline Validation

**Flutter analyzer:**

```
flutter analyze
8 issues found. (ran in 4.4s)
```

All 8 issues are **pre-existing** (4 info-level `sized_box_for_whitespace` and `deprecated_member_use` warnings, 4 warning-level `unused_local_variable` in test files). No new errors or warnings introduced by Phase A.

**Deno tests (initial review):**

```
deno test --allow-env index.test.ts
21 tests total
20 passed | 1 failed
```

❌ **Test failure (initial review):** `titleSimilarity - contiguous word sequence returns 'contains'`

**Details:**

- Test case: `titleSimilarity("Yesterday", "Yesterday (Remastered)")`
- Expected: `'contains'`
- Actual: `'fallback'`

**Root cause:** The test expectation was **incorrect**, not the implementation. When `getPrimaryTitleFallback("Yesterday (Remastered)")` strips the trailing parenthetical, it returns "Yesterday", matching at the fallback tier before the contains tier is checked.

**Fix applied:** Test case replaced with `"Rhiannon"` vs `"Rhiannon - 1997 Remaster"` (non-parenthetical suffix), which correctly tests the contains logic.

**Deno tests (re-verification):**

```
deno test --allow-env index.test.ts
ok | 21 passed | 0 failed (7ms)
```

✅ **All tests pass** after correction.

### Phase 10 — Diff Safety Review

✅ No secrets or API keys  
✅ No environment variables outside approved scope  
✅ No debug artifacts (print statements acceptable in edge function logs)  
✅ No test scaffolding in production code  
✅ No accidental file deletions

**Code bloat check:**
✅ No unused imports, variables, or parameters  
✅ No redundant comments restating code  
✅ No single-use wrapper abstractions  
✅ No unnecessary defensive checks (type guards are necessary for `any` typed API responses)  
✅ Direct, minimal implementation

---

## Verification Gaps (Unable to Complete)

### Tier 2 — Post-Deploy Verification (Not Possible Pre-Deploy)

The following verifications **require a deployed edge function** and cannot be performed in QA review:

1. **Live API call to verify response contract unchanged:**
   - Cannot confirm `confidence: 'medium' | 'none'` behavior with real GetSongBPM API
   - Cannot verify parenthetical-subtitle fallback with actual API responses
   - Cannot verify diacritic artist normalization with actual API responses

2. **Live API call to verify version-type filtering:**
   - Cannot confirm live/remix/acoustic candidates are actually rejected when request is plain
   - Cannot confirm same-artist/different-title candidates are actually rejected

**Recommendation:** These verifications are **mandatory after deploying** to staging/production. The Architect plan §15 explicitly calls them out as Tier 2 (post-deploy) requirements. Do not skip them.

---

## Critical Findings

### 1. Tests Were Never Executed by Engineer (Initial Submission) — ✅ PROCESS GAP CLOSED

**Initial finding:** The original ENGINEER_REPORT.md stated:

> Unit tests written: `index.test.ts` (26 test cases)  
> Execution status: Not run locally (deno not installed in local environment)  
> Ready for execution: Yes (tests are ready to run via `deno test --allow-env index.test.ts` in deployment/CI environment)

This was **unacceptable** per GUARDRAILS.md §11 and the commit gate protocol. The Engineer must verify tests pass before submitting for QA. Claiming tests are "ready to run" when they haven't been executed is not sufficient.

**Impact:** When QA installed deno and ran the tests, a failing test was immediately found. If the Engineer had run the tests during implementation, this would have been caught before QA review.

**Resolution:** Engineer installed deno, fixed the failing test, actually ran the suite (21/21 passing), and updated ENGINEER_REPORT.md to reflect real execution with a note about the post-QA correction. Process gap closed for future work.

**Lesson reinforced:** Always install required test runtimes in the development environment and verify tests pass as part of the implementation phase, not QA phase.

### 2. One Failing Test (Incorrect Expectation) — ✅ RESOLVED

**Test:** `titleSimilarity - contiguous word sequence returns 'contains'`  
**Initial status:** FAILED  
**Root cause:** Test expectation was wrong, not implementation

The test originally used "Yesterday" vs "Yesterday (Remastered)", which matches at the **fallback tier** (after stripping trailing parenthetical), not the **contains tier**. The implementation was correct; the test case was poorly chosen.

**Fix applied:** Test case replaced with `"Rhiannon"` vs `"Rhiannon - 1997 Remaster"` (non-parenthetical suffix), which correctly tests the contains logic. Explanatory comment added to the test.

**Re-verification:** ✅ All 21 tests pass after correction.

### 3. Incomplete Test Coverage (Not Blocking) ⚠️

The test suite covers:

- ✅ Helper functions (`detectVersionType`, `titleSimilarity`)
- ✅ Regression guards (parenthetical fallback, diacritic normalization)
- ✅ Version-type filtering logic (reject/accept scenarios)

Missing:

- ⚠️ Integration test for the full `lookupGetSongBpmForTitle` function with mock API responses
- ⚠️ Test for the exact-artist path's combined title + version filtering
- ⚠️ Test for the artist-variant path's combined title + version filtering

**Assessment:** The missing integration tests are **nice-to-have** but not **blocking**. The critical logic (detectVersionType, titleSimilarity, version filter loop) is well-covered. Integration testing will occur with live API calls post-deploy (Tier 2).

---

## Engineer Report Accuracy

The ENGINEER_REPORT.md is **accurate** except for the test execution claim:

✅ Files modified correctly identified  
✅ Analyzer results accurate (8 pre-existing warnings)  
✅ Bloat check accurate (no bloat introduced)  
✅ Deviation from plan (Task 4 prefer rule) correctly documented and justified  
✅ Test execution claim updated post-fix (21/21 passed, with note about correction)

---

## Changes Required Before Approval

### ~~Blocking (Must Fix)~~ — ✅ ALL RESOLVED

1. ~~Fix failing test case in `supabase/functions/getsongbpm_lookup/index.test.ts`~~ — **FIXED**
2. ~~Re-run tests to verify all 21 pass~~ — **VERIFIED** (21/21 passing)
3. ~~Update ENGINEER_REPORT.md with actual test execution results~~ — **UPDATED**
4. ~~Delete stray `verify_logic.test.ts` file~~ — **DELETED**

### ~~Recommended (Non-Blocking)~~ — ✅ COMPLETED

1. ~~Update ENGINEER_REPORT.md to reflect actual test execution status~~ — **DONE** (includes note about post-QA correction)
2. ~~Add explanatory comment in test file~~ — **DONE** ("Use a case with non-parenthetical suffix so it can't resolve at fallback tier")

---

## Approval Criteria — ✅ ALL MET

Phase A is **APPROVED** because:

1. ✅ All 21 tests pass in `index.test.ts` (verified by QA re-run)
2. ✅ No test execution gaps remain (deno installed, tests actually run and passing)
3. ✅ All blocking changes implemented and verified
4. ✅ Implementation unchanged (no code bugs found)
5. ✅ Working tree clean except for expected files

**Post-merge requirements:**

- Deploy `getsongbpm_lookup` edge function
- Execute Tier 2 post-deploy verification (live API calls)
- Document results in a post-deploy verification addendum

---

## Summary

Phase A implementation is **complete and correct**. The version-type filtering and title similarity logic successfully address the core accuracy problem (same-artist/wrong-title and wrong-version mismatches). All tests pass, no regressions introduced, and the response contract remains unchanged.

The initial QA review identified one test bug (incorrect expectation, not an implementation bug). The Engineer corrected it promptly, and QA re-verification confirms all 21 tests now pass.

**Verdict: ✅ APPROVED** — Ready for commit and edge function deployment.

---

## QA Agent Signature

**Initial review:** QA Agent, 2026-08-27 (identified test bug)  
**Re-verification:** QA Agent, 2026-08-27 (confirmed fix, approved)  
Branch: `feature/song-enrichment-accuracy-confidence`  
Commit: (pre-commit QA review)  
Deno version: 2.1.2  
Test results: 21/21 passing
