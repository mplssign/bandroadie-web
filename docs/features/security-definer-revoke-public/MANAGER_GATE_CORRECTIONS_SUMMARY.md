# Manager Gate Corrections Summary — feature/security-definer-revoke-public

**Date:** 2026-08-22  
**Status:** CORRECTED — Ready for Manager Review  
**Architect Plan:** `docs/features/security-definer-revoke-public/ARCHITECT_PLAN.md`

## Summary of Changes

This document summarizes the Manager gate corrections applied to `ARCHITECT_PLAN.md` for the `feature/security-definer-revoke-public` feature. The corrections address two issues identified during post-implementation verification:

1. **Part 1: Coverage gap** — 2 functions missing from every batch
2. **Part 2: Branch-testing strategy** — no longer matches approved deployment plan

---

## Part 1: Coverage Gap Corrections

### Problem

Manager gate review found that 2 of the 58 currently anon-executable `SECURITY DEFINER` functions in `public` were never captured in `PRE_MIGRATION_ACL_STATE.md` and are not covered by any of the 7 batches. Both were confirmed via live query against production (2026-08-22).

**Root cause:** Both have near-identical names to functions that were correctly classified as trigger-bound (harmless):

- `notify_band_members` vs. the already-covered `notify_new_band_member`/`notify_gig_created`/`notify_rehearsal_created` (all trigger-bound)
- `recompute_setlist_stats` vs. the already-covered `trigger_recompute_setlist_stats` (trigger-bound)

Both missed functions return `void`, not `trigger`, and are directly callable via PostgREST RPC today.

### Risk Assessment

| Function                  | Signature                                                                                                     | Current ACL                                                                                                                  | Risk                                                                                                                                                                                         |
| ------------------------- | ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `notify_band_members`     | `p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb` | Standard PUBLIC grant (`{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}`) | **Zero internal authorization check.** Anon can call this directly and insert an arbitrary notification (attacker-controlled title/body) into any band's members' feeds for any `p_band_id`. |
| `recompute_setlist_stats` | `p_setlist_id uuid`                                                                                           | Standard PUBLIC grant                                                                                                        | Anon can force-recompute any setlist's duration total from existing data. Low impact, still an unauthenticated write path outside the intended boundary.                                     |

**Internal usage (confirmed via function body inspection):**

- `notify_band_members` is called internally from `notify_gig_created` and `notify_rehearsal_created` via `PERFORM notify_band_members(...)` — both are `SECURITY DEFINER`, so internal calls are unaffected by revoking PUBLIC/anon on the callee
- `recompute_setlist_stats` is called internally by `trigger_recompute_setlist_stats`, also `SECURITY DEFINER`
- No app code path calls either function directly (confirmed via grep across `lib/` and `supabase/functions/` — zero matches)

### Changes Applied

#### 1. Scope Numbers Updated

**Before:** 56 unique functions, 58 signatures, 7 batches  
**After:** **56 unique functions, 58 signatures, 8 batches**

Updated in:

- Problem Summary
- Proposed Solution → Core Changes
- Engineer Task Breakdown (added Task 8a)
- Verification Plan → Tier 1 → Batch count reconciliation
- Summary at end of plan

#### 2. Added Batch 8

**New file:** `supabase/migrations/20260822120007_revoke_anon_batch_8_notifications_setlist_stats.sql`

```sql
-- Function 1: notify_band_members
REVOKE ALL ON FUNCTION notify_band_members(p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION notify_band_members(p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb) TO authenticated;

-- Function 2: recompute_setlist_stats
REVOKE ALL ON FUNCTION recompute_setlist_stats(p_setlist_id uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION recompute_setlist_stats(p_setlist_id uuid) TO authenticated;
```

With rollback block restoring PUBLIC grants (both functions had PUBLIC grant in pre-migration state, confirmed via live proacl query 2026-08-22).

Added to:

- Proposed Solution → Batching Strategy (new Batch 8 section)
- Files to Create table
- Engineer Task Breakdown (new Task 8a)

#### 3. Updated Verification Plan

Added checks for both functions:

- **Tier 1:** Confirm Batch 8 includes both functions with correct signatures
- **Tier 2 POST-DEPLOY TEST 4:** Updated function list to include `notify_band_members` and `recompute_setlist_stats` in comprehensive privilege inventory
- **Tier 2 POST-DEPLOY TEST 5:** New test specifically for Batch 8 functions
- **Manual smoke tests:** Added Batch 8 test: create gig → verify `notify_band_members` called internally; edit setlist song → verify duration recalculates

#### 4. Updated PRE_MIGRATION_ACL_STATE.md Handling

**Task 1** now includes instruction to:

- Read existing `PRE_MIGRATION_ACL_STATE.md` in full
- Verify `notify_band_members` and `recompute_setlist_stats` are missing
- Append 2 rows to the Complete ACL State table with exact captured state
- Re-read file after edit to confirm no corruption
- Update Summary to reflect 58 signatures total

**Files to Modify table** now includes:

- `PRE_MIGRATION_ACL_STATE.md` — Append 2 rows for the missed functions

#### 5. Added GUARDRAILS.md Update

Updated the ACL discipline bullet in GUARDRAILS.md §4 to include:

> When verifying function ACLs, use `has_function_privilege(role, oid, 'EXECUTE')` — never string-match the raw ACL array for a named grantee, as a PUBLIC grant makes every role's effective privilege true even with no explicit named entry (this caused an incorrect "special case" classification for `is_band_member_with_role` during this feature's implementation).

**Rationale:** Determining effective privilege must use `has_function_privilege(role, oid, 'EXECUTE')`, never string-matching the raw ACL array for a named grantee — a PUBLIC grant makes every role's effective privilege `true` even with no explicit named entry, which caused an incorrect "special case" classification for `is_band_member_with_role` during this feature's implementation.

---

## Part 2: Deployment Strategy Corrections

### Problem

`ARCHITECT_PLAN.md` currently references Supabase branch testing in **29 places** across the Verification Plan, Task 10, every batch's task description, and the Rollout Strategy. This is no longer achievable or intended:

- Project is confirmed on Supabase Free tier (branching requires Pro)
- Tony has explicitly approved a direct-to-production deployment strategy in lieu of branch testing

### Changes Applied

#### 1. Tier 1 Renamed

**Before:** "Pre-Deployment (Supabase Branch Only)"  
**After:** **"Pre-Deployment (Static/Logic Verification)"**

Content updated to:

- SQL syntax review
- Signature-matching against `PRE_MIGRATION_ACL_STATE.md`
- Rollback completeness review
- Batch count reconciliation
- No live target required

#### 2. Tier 2 Renamed

**Before:** "Post-Deployment (After Each Batch on Branch, Then Production)"  
**After:** **"Post-Deployment (After Each Batch, Direct to Production)"**

Content updated to:

- Run `has_function_privilege('anon', ...)` = false and `has_function_privilege('authenticated', ...)` = true for that batch's functions immediately after applying to production
- Manual smoke test of affected app flow
- Before next batch proceeds
- Removed all "branch" language from this tier

#### 3. Task 10 Replaced

**Before:** "Post-Batch Verification on Branch"  
**After:** **"Post-Batch Verification (Production)"**

Content updated to:

- Manager runs privilege sweep after each batch
- Engineer/Tony spot-checks affected app flow
- After all 8 batches complete, run comprehensive privilege inventory
- Check production Supabase Advisors

#### 4. Task 11 (Production Deployment) Gate Updated

**Before:** "Apply all migrations to production (gate: Manager approval after branch verification passes)"  
**After:** **"gate: Manager approval after QA_REPORT.md is APPROVED (per COMMIT_GATE.md and GUARDRAILS.md §11) and per-batch production verification passes"**

**Rationale:** This plan must go through QA (per `QA.md` Phase 8 — Database Safety) before any batch is applied to production — that gate was missing from the plan's stated rollout and needs to be explicit.

#### 5. Rollout Strategy Rewritten

##### Phase 1: Branch Preparation → Pre-Deployment Verification

**Before:**

1. Clone production schema to Supabase branch
2. Capture pre-migration ACL state
3. Apply batches to branch
4. Run verification on branch
5. Final branch verification

**After:**

1. Capture pre-migration ACL state (Task 1) — MANDATORY
2. Static verification (Tier 1): SQL syntax, signature matching, rollback completeness, batch count reconciliation
3. **QA approval gate:** QA runs full regression suite, produces `QA_REPORT.md` with APPROVED status (per `COMMIT_GATE.md` and `GUARDRAILS.md` §11)

##### Phase 2: Production Deployment

**Before:** Single push to production after branch verification  
**After:** **Batched deployment with per-batch production verification**

**Gate:** Manager approval after QA approval complete

1. Apply Batch 1 to production
2. Run Tier 2 verification immediately (privilege checks + smoke test)
3. If passes, proceed to Batch 2; if fails, diagnose and rollback
4. Repeat for Batches 2-8 sequentially: apply → verify → proceed
5. After all 8 batches, run comprehensive privilege inventory
6. Check production Supabase Advisors: 58→0 drop

**If any migration fails:** Supabase halts; diagnose specific batch; execute rollback for applied batches; fix and retry

##### Regression Risk Updated

**Before:** "branch verification mitigate risk"  
**After:** "batched migrations with per-batch production verification and immediate single-statement rollback"

#### 6. Additional Context Updated

**Before:** "Branch verification is manual, not automated"  
**After:** Removed — replaced with production verification description throughout Rollout Strategy

---

## Files Modified

| File                                                             | Changes                                                                                   |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `docs/features/security-definer-revoke-public/ARCHITECT_PLAN.md` | Complete regeneration with all Part 1 and Part 2 corrections applied in single clean pass |
| `docs/agents/GUARDRAILS.md`                                      | Updated ACL discipline bullet in §4 to include `has_function_privilege()` guidance        |

---

## Verification Checklist

Confirmed after regeneration:

- [x] No duplicate section headers
- [x] Batch math reconciles: 56 unique functions, 58 signatures, 8 batches
- [x] Zero remaining references to "branch" in Verification Plan or Rollout Strategy (except appropriate git branch references)
- [x] QA gate explicitly stated before production-deployment task
- [x] Batch 8 migration file listed in Files to Create
- [x] Task 8a added for creating Batch 8
- [x] PRE_MIGRATION_ACL_STATE.md update task added
- [x] Verification Plan includes checks for 2 new functions
- [x] GUARDRAILS.md update includes `has_function_privilege()` guidance

---

## Updated Sections Summary

### Part 1 Changes:

1. **Problem Summary** — scope numbers updated to 56 unique/58 signatures
2. **Function Categories** — added Category F for missed functions
3. **Batching Strategy** — added Batch 8
4. **Files to Create** — added Batch 8 migration file
5. **Files to Modify** — added PRE_MIGRATION_ACL_STATE.md update, updated GUARDRAILS.md description
6. **Task 1** — updated to handle appending to existing PRE_MIGRATION_ACL_STATE.md
7. **Task 8a** — new task for Batch 8 creation (includes complete migration SQL)
8. **Task 9** — updated GUARDRAILS.md guidance to include `has_function_privilege()` note
9. **Task 10** — renamed to "Post-Batch Verification (Production)"
10. **Verification Plan Tier 1** — added Batch 8 signature confirmation
11. **Verification Plan Tier 2** — added POST-DEPLOY TEST 5 for Batch 8, updated TEST 4 function list
12. **Manual Smoke Tests** — added Batch 8 test
13. **QA Regression Areas** — added item 11 for Batch 8 functions
14. **Rollout Strategy** — updated Phase 1 to include appending to PRE_MIGRATION_ACL_STATE.md, added Batch 8 to Phase 2 sequential deployment

### Part 2 Changes:

1. **Verification Plan Tier 1** — renamed to "Pre-Deployment (Static/Logic Verification)"
2. **Verification Plan Tier 2** — renamed to "Post-Deployment (After Each Batch, Direct to Production)"
3. **Task 2-8** — updated closing step from "Apply to branch" to "Apply to production"
4. **Task 10** — replaced "Post-Batch Verification on Branch" with "Post-Batch Verification (Production)"
5. **Task 11** — updated gate to include QA approval requirement
6. **Rollout Strategy Phase 1** — rewritten as "Pre-Deployment Verification" (no clone step)
7. **Rollout Strategy Phase 2** — rewritten as "Production Deployment (Batched with Per-Batch Verification)"
8. **Rollout Strategy Phase 3** — updated to reflect production verification
9. **Regression Risk** — updated "branch verification" bullet to "batched migrations with per-batch production verification"

---

## Manager Review Notes

**Plan is now consistent with approved deployment strategy:**

- Direct-to-production deployment with per-batch verification
- QA gate explicitly required before any production push
- 8 batches covering all 56 unique function names (58 total signatures)
- `has_function_privilege()` guidance added to GUARDRAILS.md to prevent future classification errors

**No changes to existing Batches 1-7:**

- 7 existing migration files (`20260822120000` through `20260822120006`) remain correct and approved as-is
- No modifications to their content required

**Ready for Engineer implementation:**

- Engineer will implement Tasks 1-12 + Task 8a
- PRE_MIGRATION_ACL_STATE.md will be updated (appended) not regenerated
- GUARDRAILS.md has been updated with ACL discipline note
- Batch 8 migration file will be created per Task 8a
- QA approval required before production deployment

---

**Status:** CORRECTED — Awaiting Manager Approval
