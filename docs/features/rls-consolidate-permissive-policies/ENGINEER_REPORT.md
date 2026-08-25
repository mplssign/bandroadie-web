# Engineer Report

## Feature Slug

`feature/rls-consolidate-permissive-policies`

## Feature Title

Consolidate Permissive RLS Policies for Performance Optimization

## Goal

Consolidate redundant/overlapping RLS PERMISSIVE policies across 11 tables to achieve exactly one policy per (table, action) combination. Reduces Performance Advisor warnings from 102 to 0 by eliminating the overhead of OR'ing multiple stacked policy generations. Preserves current effective access by OR'ing all existing predicates for non-equivalent pairs.

## Architect Tasks Completed

- [x] Task 1 — Capture pre-migration RLS state to PRE_MIGRATION_RLS_STATE.md (78 policies, 495 lines)
- [x] Task 2 — Write migration file header with feature reference and rollback pointer
- [x] Task 3 — Write 11 per-table DROP/CREATE consolidation blocks in exact order with proper constraints
- [x] Task 4 — Run syntax validation checks (all pass: 78 DROP, 41 CREATE, 0 bare auth.uid(), single-line comments only)
- [x] Task 5 — Write ENGINEER_REPORT.md (this file)

## Files Created

- `docs/features/rls-consolidate-permissive-policies/PRE_MIGRATION_RLS_STATE.md` (495 lines, 78 policies captured from live pg_policies)
- `supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql` (458 lines, 78 DROP + 41 CREATE)
- `docs/features/rls-consolidate-permissive-policies/ENGINEER_REPORT.md` (this file)

## Files Modified

None — pure-addition feature

## Analyzer Results

**Not applicable** — Database-only change, no Dart code modified. `flutter analyze` would pass unchanged (0 errors, no new warnings).

## Test Results

**Not run** — Verification occurs via QA Tier 2 transaction-wrapped test against production (per Architect plan). Unit tests not applicable for RLS policy changes.

## Code Efficiency / Bloat Check

Not applicable — SQL migration file only, no Dart code. Migration follows minimal-line principle:

- Single-line comments only (no multi-line blocks per `rls-migration-comment-escaping` lesson)
- No redundant DROP statements (each policy dropped once)
- No dead predicates (all OR branches serve effective access preservation)
- "Known Issue" comments included only where mandated by Architect plan (Notes 6, 7)

## Verification

Manual verification performed:

1. **PRE_MIGRATION_RLS_STATE.md accuracy:**
   - Queried live `pg_policies` for all 11 tables via `mcp_supabase2_execute_sql`
   - Policy count per table matches Architect plan baseline: bands (9), setlists (11), setlist_songs (9), rehearsals (9), songs (6), profiles (8), users (8), gig_responses (8), band_members (4), contributor_permissions (2), user_band_roles (4)
   - Total: 78 policies captured

2. **Migration file syntax validation (Task 4):**
   - DROP count: 78 ✅
   - CREATE count: 41 ✅ (increased from planned 39 due to contributor_permissions ALL policy split)
   - Bare `auth.uid()` calls: 0 ✅ (all wrapped with `(select auth.uid())`)
   - Single-line comments only ✅ (no multi-line continuation errors)

3. **Line-by-line consolidation verification against PRE_MIGRATION_RLS_STATE.md:**

   **bands (4 policies):**
   - DELETE: OR of "admin check" (lines 36-39) + "creator check" (line 42) + "is_band_admin" (line 45) → consolidated to `is_band_admin(id) OR created_by = (select auth.uid())` ✅
   - INSERT: 2 equivalent policies (lines 48, 51) both require `created_by = auth.uid()` → consolidated to `created_by = (select auth.uid())` ✅
   - SELECT: 3 policies (lines 54-67), broadest is "Band members can view bands" (line 54) with `is_deleted = false AND is_band_member(id)` → consolidated matches ✅
   - UPDATE: 1 policy (line 69) → `is_band_admin(id)` preserved exactly ✅

   **setlists (4 policies) — CORRECTED after Implementation Gate review:**
   - DELETE: 3 originals (lines 105-115), broadest is "Band members can delete setlists" (line 108) with NO status filter + "creator/admin" (line 113) → fixed to `is_band_member(band_id) OR created_by = (select auth.uid())` ✅
   - INSERT: 3 originals (lines 118-131), broadest is "Band members can create setlists" (line 124) with NO status or created_by requirement → fixed to `is_band_member(band_id)` only ✅
   - SELECT: 2 equivalent policies (lines 134, 137) → `is_band_member(band_id)` ✅
   - UPDATE: 3 originals (lines 140-161), broadest is "Band members can update setlists" (line 153) + "creator/admin" (line 158) → fixed to `is_band_member(band_id) OR created_by = (select auth.uid())` ✅

   **setlist_songs (4 policies):**
   - DELETE: 2 equivalent policies (lines 172, 175) using setlist join → consolidated uses `is_band_member(s.band_id)` via setlist join ✅
   - INSERT: 2 equivalent policies (lines 178, 181) → consolidated uses `is_band_member(s.band_id)` via setlist join ✅
   - SELECT: 3 originals (lines 184-197), broadest has no status filter → `is_band_member(s.band_id)` (no status filter in helper) ✅
   - UPDATE: 2 equivalent policies (lines 200, 203) → consolidated uses `is_band_member(s.band_id)` via setlist join ✅

   **rehearsals (4 policies):**
   - DELETE: 2 originals (lines 217, 220), broadest is admin+member role filter (line 217) → consolidated preserves `role IN ('admin', 'member')` ✅
   - INSERT: 2 originals (lines 223, 226), broadest is just `is_band_member` (line 226) → `is_band_member(band_id)` ✅
   - SELECT: 3 originals (lines 229-240), broadest is `is_band_member` (line 237) → `is_band_member(band_id)` ✅
   - UPDATE: 2 originals (lines 243, 252), broadest has admin+member role filter (line 243) → consolidated preserves `role IN ('admin', 'member')` ✅

   **songs (3 policies):**
   - INSERT: 2 originals (lines 261, 264), broadest is "any authenticated" (line 261) → `USING (true)` ✅
   - SELECT: 3 originals (lines 267-274), broadest is `USING (true)` (line 273) → `USING (true)` ✅
   - UPDATE: 1 policy (line 277) → `is_band_member(band_id)` preserved exactly ✅

   **profiles (4 policies):**
   - DELETE: 1 policy (line 288) → `id = (select auth.uid())` ✅
   - INSERT: 2 equivalent policies (lines 291, 294) → `id = (select auth.uid())` ✅
   - SELECT: 3 originals (lines 297-303), OR of "own" + "bandmates with status filter" → consolidated ORs both ✅
   - UPDATE: 2 equivalent policies (lines 306, 309) → `id = (select auth.uid())` ✅

   **users (4 policies):**
   - DELETE: 1 policy (line 318) → `id = (select auth.uid())` ✅
   - INSERT: 2 equivalent policies (lines 321, 324) → `id = (select auth.uid())` ✅
   - SELECT: 3 originals (lines 327-333), OR of "own" + "get_bandmate_user_ids()" → consolidated ORs both ✅
   - UPDATE: 2 equivalent policies (lines 336, 339) → `id = (select auth.uid())` ✅

   **gig_responses (4 policies):**
   - DELETE: 2 equivalent policies (lines 348, 351) → `user_id = (select auth.uid())` ✅
   - INSERT: 2 equivalent policies (lines 354, 357), both require own + band member via gig → consolidated matches ✅
   - SELECT: 2 equivalent policies (lines 360, 363) → band member check via gig ✅
   - UPDATE: 2 equivalent policies (lines 366, 369) → own + band member check via gig ✅

   **band_members (3 policies):**
   - INSERT: 1 policy (line 81) → `is_band_member(band_id) OR user_id = (select auth.uid())` ✅
   - SELECT: 2 originals (lines 84, 87), OR of both → `user_id = (select auth.uid()) OR is_band_member(band_id)` ✅
   - UPDATE: 1 policy (line 90) → admin check with is_band_member guard preserved exactly ✅

   **contributor_permissions (4 policies) — CORRECTED after Implementation Gate review:**
   - Original had 1 ALL policy covering INSERT/UPDATE/DELETE/SELECT + 1 SELECT policy → split ALL into INSERT/UPDATE/DELETE separately + kept SELECT policy → now 4 total (one per action) ✅
   - INSERT: admin-only (split from ALL, line 453) ✅
   - UPDATE: admin-only (split from ALL, line 459) ✅
   - DELETE: admin-only (split from ALL, line 466) ✅
   - SELECT: any active member (line 469, kept from original SELECT-only policy) ✅

   **user_band_roles (3 policies):**
   - INSERT: 1 policy (line 479) → `user_id = (select auth.uid())` ✅
   - SELECT: 2 originals (lines 482, 485), OR of "own" + "bandmates with status filter" → consolidated ORs both ✅
   - UPDATE: 1 policy (line 488) → `user_id = (select auth.uid())` ✅

4. **Table order:**
   - Confirmed migration processes tables in exact Architect-specified order: bands, setlists, setlist_songs, rehearsals, songs, profiles, users, gig_responses, band_members, contributor_permissions, user_band_roles ✅

## Deviations From Architect Plan

**Deviation 1: contributor_permissions consolidation approach**

- **Architect plan specified:** "2 policies → 2 consolidated" or "decision per Note 3" (Section "Engineer Task Breakdown" Task 3, line 10)
- **Implemented:** 2 policies → 4 consolidated (split ALL-command policy into INSERT/UPDATE/DELETE separately + kept SELECT-only policy)
- **Justification:** The ALL-command policy covered INSERT/UPDATE/DELETE/SELECT. Keeping it as-is would have left 2 PERMISSIVE policies for SELECT action (ALL policy + SELECT-only policy), failing to achieve "one policy per action" consolidation goal. Splitting ALL into per-command policies achieves exactly one policy per action for this table.
- **Impact:** CREATE count increased from planned 39 to actual 41. This table will show 0 `multiple_permissive_policies` warnings post-deployment (full consolidation achieved).

## Blockers Encountered

None

## Ready For QA

**Yes**

This implementation is ready for QA Tier 2 transaction-wrapped verification against production. The migration:

- Consolidates 78 policies down to 41 (one per table+action)
- Preserves all current effective access (OR'ing non-equivalent predicates per Notes 2, 4, 6, 7)
- Uses single-line comments only (no multi-line syntax errors)
- Wraps all `auth.uid()` calls with `(select auth.uid())`
- Scopes all policies TO authenticated (no TO public)
- Documents "Known Issue" cases per Architect instructions (setlists contributor over-permissiveness, songs unrestricted access)

**Post-correction changes:**

- Fixed setlists DELETE/INSERT/UPDATE: removed incorrectly-added status filter, added back dropped creator term (per Implementation Gate review)
- Fixed contributor_permissions: split ALL policy into per-command policies to achieve true one-policy-per-action consolidation

PRE_MIGRATION_RLS_STATE.md serves as sole rollback reference (managed branches unavailable per `rls-migration-comment-escaping` QA Report Check #4 — migrations 001-072 never committed to version control).

QA should execute Tier 2 verification transaction as specified in Architect plan Verification section, testing all 7 flagged non-equivalent pairs before authorizing actual deployment.
