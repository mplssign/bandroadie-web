# QA Report

## Feature Slug

move-song-between-setlists-failure

## Feature Title

Move Song Between Setlists Failure

## Final Verdict

**APPROVED**

## Validation Summary

Migration SQL implementation matches Architect specification exactly. Root cause (NOT DEFERRABLE constraint + ROW_NUMBER() trigger collision) is addressed via two-part fix: constraint made DEFERRABLE INITIALLY DEFERRED and trigger function rewritten with surgical decrement logic. Validation performed via code-path analysis of migration SQL against Architect plan. No Dart code changes required or made.

## Architect Scope Review

- Scope adherence: compliant
- Files modified: as expected (only migration file created)
- Files off-limits: not touched (no Dart files modified, no existing migrations changed)

## Completeness Check

- All Architect tasks implemented: Tasks 1-4 complete, Tasks 5-11 properly deferred per Engineer scope
- Missing tasks: Tasks 5-11 (local db reset, Tier 1/2 SQL tests, deployment) are deferred per QA session instructions and require database credentials/deployment permissions beyond Engineer scope

## Behavior Verification

- Validation method: code-path analysis
- Result: matches expected

**Root cause addressed:**
1. Constraint timing fixed: DEFERRABLE INITIALLY DEFERRED defers uniqueness check to transaction end, preventing transient collisions during multi-row UPDATE
2. Trigger logic corrected: Surgical decrement (`position = position - 1 WHERE position > OLD.position`) eliminates ROW_NUMBER() 1-indexed vs 0-indexed mismatch
3. Minimal disruption: Only positions after deleted position are updated (not wholesale renumbering)

## Regression Check

- Risk level: MEDIUM
- Systems reviewed: Gigs, Rehearsals, Setlists/Catalog, Members/RBAC, Auth/Session, Routing, Notifications, Platform
- Regressions found: none

**Medium risk rationale (per Architect assessment):**
- Trigger fires on ALL deletes from setlist_songs (Move, Remove, Delete from Catalog, Special item deletion, cascade deletes)
- Constraint change affects transaction behavior (check timing moved from immediate to deferred)
- Trigger rewrite changes logic path (wholesale renumber → surgical decrement)
- Production data has position gaps proving current trigger fails intermittently
- HOWEVER: DEFERRABLE is standard pattern for this bug class, surgical approach is simpler/faster than ROW_NUMBER()

**Guardrails compliance verified:**
- SECURITY DEFINER function includes `SET search_path = public` (GUARDRAILS.md Section 4)
- No RLS self-reference risk (no RLS changes)
- Data write atomicity preserved (constraint deferral ensures atomic transaction)
- Only Architect-approved files modified (migration only, no Dart changes)

## Database Safety

Verified

**Safety checks passed:**
1. Migration matches Architect plan exactly (line-by-line verification)
2. Part 1: ALTER TABLE operations match specification (DROP + ADD CONSTRAINT with DEFERRABLE INITIALLY DEFERRED)
3. Part 2: Function signature matches existing trigger expectations (RETURNS TRIGGER, AFTER DELETE)
4. Function includes `SET search_path = public` per GUARDRAILS.md Section 4 requirement
5. No RLS policies modified (not applicable)
6. No privilege escalation (SECURITY DEFINER updates same table only)
7. No unintended cascade behavior (surgical decrement targets position > OLD.position only)
8. No RPC signature changes (not applicable)
9. Migration content matches claimed behavior (DEFERRABLE constraint + surgical decrement)
10. No infinite recursion risk (trigger updates different rows, not triggering row)
11. No potential deadlock (single-table UPDATE with simple WHERE clause)

**Implementation correctness:**
- Constraint timing: INITIALLY DEFERRED checks uniqueness at transaction commit, not per-row
- Surgical decrement: `UPDATE ... SET position = position - 1 WHERE setlist_id = OLD.setlist_id AND position > OLD.position`
- Preserves 0-indexed convention (no ROW_NUMBER() start-at-1 mismatch)
- Returns OLD (appropriate for AFTER DELETE trigger)

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings

Output:
```
Analyzing bandroadie...
No issues found! (ran in 4.6s)
```

## Test Results

Not run — migration is database-only and requires Supabase environment access. Tier 1 pre-deploy and Tier 2 post-deploy SQL tests from Architect plan must be executed manually with database credentials during deployment phase.

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none
- Unrelated changes: none

**Migration file inspection:**
- No hardcoded credentials or API keys
- No environment variables outside approved scope
- No debug print statements or TODO hacks
- No test scaffolding in production code
- Comment block documents root cause and fix strategy appropriately

## Issues Found

None

## Deployment Prerequisites

Before deployment to staging/production, the following must be completed:

1. **Tier 1 pre-deploy tests** (Architect plan lines 253-287):
   - Verify current constraint is NOT DEFERRABLE
   - Verify trigger function uses ROW_NUMBER()
   - Verify trigger is attached to setlist_songs table
   - Document existing position gaps in production data

2. **Apply migration:**
   ```bash
   supabase db push
   ```

3. **Tier 2 post-deploy tests** (Architect plan lines 289-476):
   - Verify constraint is now DEFERRABLE INITIALLY DEFERRED
   - Verify trigger function uses surgical decrement (not ROW_NUMBER())
   - Run end-to-end move operation test (DO block from plan)
   - Run direct delete operation test (DO block from plan)

4. **Manual QA testing in staging app** (all deletion paths):
   - Move operation (swipe right, choose Move)
   - Delete from setlist (swipe left, choose Remove)
   - Delete from Catalog (cascades to all setlists)
   - Delete special item (set break/pause)
   - Copy operation (should still work)
   - Verify sequential 0-indexed positions maintained after each operation

5. **Production deployment:**
   - Deploy during low-traffic window
   - Monitor logs for 48 hours for constraint violations or trigger errors

## QA Approval Notes

Implementation is complete and correct per Architect specification. The Engineer properly completed all tasks within scope (Tasks 1-4: migration file creation with DEFERRABLE constraint and surgical decrement trigger). Tasks 5-11 require database access and deployment permissions beyond Engineer scope and were appropriately deferred.

Migration SQL addresses the confirmed root cause through two complementary fixes:
1. Constraint deferral prevents transient collisions during multi-row UPDATE
2. Surgical decrement eliminates 1-indexed vs 0-indexed mismatch and reduces update surface area

Deployment team should execute Tier 1/2 SQL tests and manual QA regression testing per Architect verification plan before production rollout.
