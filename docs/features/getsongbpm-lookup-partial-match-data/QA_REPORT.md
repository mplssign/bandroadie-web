# QA Report

## Feature Slug

bug/getsongbpm-lookup-partial-match-data

## Feature Title

GetSongBPM lookup partial match data selection fix

## Final Verdict

REQUIRES CHANGES

## Validation Summary

Validated branch and scope, reviewed live git diff against main, verified deployed edge function source markers, executed required post-deploy runtime probes, and ran analyzer and database safety checks.

The deployed function no longer uses first-match-only selection and now contains the best-available selector logic. Runtime outputs for the two motivating probes were unchanged from pre-fix behavior.

Critical proof of behavior change is still missing: no validated case was produced where a strong match at index greater than 0 is selected and improves outcome versus index 0.

## Architect Scope Review

- Scope adherence: compliant
- Files modified: as expected
- Files off-limits: not touched

## Completeness Check

- All Architect tasks implemented: no
- Missing tasks:
  - Task 6 evidence requirement remains incomplete from QA perspective: no demonstrable runtime proof that ranking changed an outcome.

## Behavior Verification

- Validation method: runtime tested and code-path analysis
- Result: partial match to expected
- Confirmed:
  - Deployed code marker removed first index selector.
  - Deployed code marker added best-available selector.
  - Enter Sandman probe returns bpm 123, key Em, confidence medium.
  - All The Small Things probe returns bpm null, key null, confidence none.
- Not confirmed:
  - Whether selected_index was 0 or non-zero for post-deploy Enter Sandman probe.
  - Whether All The Small Things failure reason was zero_strong_matches or no_usable_strong_match.
  - At least one real runtime case where selected_index greater than 0 improves output versus index 0.

## Regression Check

- Risk level: MEDIUM
- Systems reviewed: setlists and catalog enrichment quality path, edge function runtime contract, update_song_metadata RPC signature and execute grant, analyzer baseline
- Regressions found:
  - No contract regression found.
  - Runtime quality improvement remains unproven for the core ranking objective.

## Database Safety

Verified

- No migrations added.
- No RLS or schema changes in this branch.
- update_song_metadata signature and authenticated EXECUTE grant unchanged.
- Post-deploy integrity query:
  - invalid_key_values = 0
  - out_of_range_bpm = 4 (pre-existing baseline style count, not attributed to this edge-function-only change)

## Analyzer Results

Command: flutter analyze
Result: 1 existing info warning outside scope, 0 errors

## Test Results

Not run

- No Architect-mandated flutter test command in this plan.
- Additional runtime probes were executed for Tier 2 and sample regression coverage.

## Diff Safety Review

- Secrets: none found in git diff
- Debug artifacts: none outside architect-approved reason-coded function logs
- Unrelated changes: none in git diff vs main

## Section 15 Tier 2 Verification

- Post-deploy source markers:
  - removed_first_index_selection=true
  - added_best_match_selector=true
- Runtime probes:
  - Enter Sandman / Metallica -> bpm 123, key Em, confidence medium
  - All The Small Things / Blink-182 -> bpm null, key null, confidence none
- Production integrity query:
  - invalid_key_values=0
  - out_of_range_bpm=4

## Section 16 Regression Areas

- Re-run known affected songs: completed; outcomes not worse but unchanged for both motivating probes.
- Sample 25-song multi-artist probe run against production:
  - medium=9
  - none=16
- Duration-only behavior when BPM and key unavailable:
  - Observed confidence none responses with no edge-function contract changes to duration path.
  - Duration path remains external to this function by design.
- Results overlay per-field Not found and summary counts:
  - Not runtime-validated in UI during this QA pass.
- RPC write regression check:
  - update_song_metadata signature and auth execute privilege unchanged.

## Issues Found

### Critical (must fix before commit)

1. Missing log-based selection evidence.
   - Required by QA request and Architect monitoring intent.
   - Need edge-function logs for the two post-deploy probes with reason=selected_candidate and selected_index values, plus reason code for All The Small Things.

2. Core fix objective unverified at runtime.
   - No real case was demonstrated where selected_index greater than 0 produced a better tempo and or key outcome than index 0.
   - Without this, the ranking change may be present in code but unproven in production behavior.

### Warnings (should fix)

1. Section 16 UI regression item was not executed: results overlay field-level and summary-count behavior remains unverified in this QA pass.

## Required Changes

1. Retrieve post-deploy edge-function logs for the two probe calls and record exact reason lines.
   - Enter Sandman: capture reason=selected_candidate with selected_index value.
   - All The Small Things: capture whether reason is zero_strong_matches or no_usable_strong_match.

2. Produce at least one real production probe case where selected_index greater than 0 is chosen and improves data completeness over index 0.
   - Include the reason line showing selected_index greater than 0.
   - Include probe response and candidate-quality evidence sufficient to prove the improved outcome.

3. Execute the remaining Section 16 UI regression validation for overlay Not found and summary counts, then append evidence to the report set.
