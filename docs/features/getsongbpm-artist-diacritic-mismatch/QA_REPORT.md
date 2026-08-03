# QA Report

## Feature Slug

bug/getsongbpm-artist-diacritic-mismatch

## Feature Title

Catalog GetSongBPM artist diacritic mismatch

## Final Verdict

APPROVED

## Validation Summary

Validated in strict QA phase order against the Architect plan and Guardrails, with direct git diff inspection (not report-only review). Confirmed a single in-scope code change in the edge function that applies Unicode NFD + combining-mark stripping for artist normalization and shared word normalization used by artist-variant matching. Independently re-ran analyzer, normalization smoke assertions (Node equivalent to the Architect deno snippet), and live runtime probes for Mötley Crüe versus Motley Crue; both runtime responses matched and returned identical non-null BPM/key results. No out-of-scope file edits, dependency additions, schema work, or response-contract/key-vocabulary changes were found.

## Architect Scope Review

- Scope adherence: compliant
- Files modified: as expected
- Files off-limits: not touched

## Completeness Check

- All Architect tasks implemented: yes
- Missing tasks: none

## Behavior Verification

- Validation method: code-path analysis and runtime tested
- Result: matches expected
- Notes: The change to normalizeWords is shared by artist-variant matching and title normalization. This makes accented and non-accented title spellings transliteration-equivalent during the variant-title equality check. Reviewed for unintended broadening: no fuzzy title matching was introduced (still exact normalized equality), and artist-variant gating still applies, so no concrete unintended false-positive path was identified from this change.

## Regression Check

- Risk level: LOW
- Systems reviewed: Setlists/Catalog (affected), Gigs, Rehearsals, Members/RBAC, Auth/Session, Routing, Notifications, Platform iOS/Android/Web/macOS
- Regressions found: none

## Database Safety

Not applicable (edge-function-only change; no migrations/RLS/RPC/trigger edits). Production safety SQL verification accepted from manager-run direct Supabase check: invalid_key_values=0 and 4 out_of_range_bpm rows predate this deploy.

## Analyzer Results

Command: flutter analyze
Result: 0 errors

## Test Results

Not run (no Architect requirement for flutter test in this edge-function-only scope).

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none found
- Unrelated changes: none found

## Issues Found

None
