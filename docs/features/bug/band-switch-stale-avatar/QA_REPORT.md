# QA Report

## Feature Slug

bug/band-switch-stale-avatar

## Feature Title

Band Switch Stale Avatar

## Final Verdict

**REQUIRES CHANGES**

## Validation Summary

Reviewed Architect and Engineer documents, inspected branch diff and local code hunk, and verified analyzer status. The one-line invalidation is present in the correct location inside selectBand(). Static analysis passes with 0 errors. However, the branch-level diff against main includes out-of-scope files outside the Architect-approved change list, so this cannot be approved as-is.

## Architect Scope Review

- Scope adherence: violated
- Files modified: deviations noted below
- Files off-limits: not touched for this bug fix path, but out-of-scope files exist in branch diff

## Completeness Check

- All Architect tasks implemented: no
- Missing tasks: Scope containment requirement failed because branch diff includes non-feature files

## Behavior Verification

- Validation method: code-path analysis
- Result: matches expected for implemented hunk (state update -> invalidate displayBandProvider -> navigation)

## Regression Check

- Risk level: LOW
- Systems reviewed: avatar display, provider dependency path, routing handoff in selectBand(), permissions invalidation path
- Regressions found: none from the one-line change itself

## Database Safety

Not applicable

## Analyzer Results

Command: flutter analyze
Result: 0 errors

## Test Results

Not run

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none found in reviewed hunk
- Unrelated changes: found
  - docs/features/bug/notifications-band-member-event/ARCHITECT_PLAN.md
  - docs/features/bug/notifications-band-member-event/ENGINEER_REPORT.md
  - docs/features/bug/notifications-band-member-event/QA_REPORT.md
  - supabase/migrations/20260614000000_fix_notification_default_on_missing_preferences.sql
  - docs/features/bug/band-switch-stale-avatar/ARCHITECT_PLAN.md appears as added in branch diff (not in approved modify list)

## Issues Found

### Critical (must fix before commit)

1. Branch diff exceeds Architect-approved scope for this feature. QA requires an isolated diff containing only the approved implementation file change for this bug (plus documentation files explicitly permitted for this feature workflow).

### Warnings (should fix)

1. None.

### Suggestions (optional)

1. Isolate this fix by rebasing/cherry-picking onto a clean bug branch and re-running QA checks.

## Evidence Notes

- selectBand() ordering verified in code: state update at line 336, display invalidation at line 337, navigation at line 347.
- Circular dependency/cascade assessment: no circular dependency introduced. displayBandProvider watches activeBandProvider and draftBandProvider; invalidating displayBandProvider from ActiveBandNotifier does not create a self-referential watch cycle. Provider is synchronous (not FutureProvider), so loading flicker risk from this line is low.

## Required Pre-Deploy Manual Step (Tony)

- Tier 2 manual UI test is required before deploy (QA cannot execute this): switch between bands with different avatar colors and verify header avatar updates immediately without flicker or stale color persistence.
