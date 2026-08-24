# Architect Plan — feature/rls-policy-performance-hardening

## Feature Slug

`feature/rls-policy-performance-hardening`

## Problem Summary

Live Supabase Performance Advisor reports 124 `auth_rls_initplan` warnings across 32 of 35 tables — RLS policies call `auth.uid()` (and in 2 cases `auth.role()`) directly in their USING/WITH CHECK expressions, causing PostgreSQL to re-evaluate these functions once per row instead of once per query. This is a known Postgres optimizer limitation where directly-called auth/session functions are treated as volatile and not cached for the query's lifetime, creating measurable overhead on queries scanning hundreds or thousands of rows.

Separately, the Security Advisor reports exactly one `function_search_path_mutable` warning: `public.get_user_band_role`. This SECURITY INVOKER function was created in migration `20260302000000_band_user_roles.sql` without `SET search_path = public`, and was missed during the Aug 14, 2026 search_path hardening sweep (migrations `20260814120003` covering 33 functions and `20260814120005` covering 7 more).

Both are backend-only SQL hardening with no intended change in authorization logic — bundling them lets one migration pair and one advisor re-pull close out both warnings.

## Root Cause

**RLS policy performance issue:**

- **Cause:** RLS policies call `auth.uid()` and `auth.role()` directly in USING/WITH CHECK clauses without wrapping them in `(select ...)` subselects.
- **Mechanism:** PostgreSQL's query planner treats bare auth.\* function calls as volatile (non-immutable) and creates an InitPlan node that executes once per row. Wrapping in `(select auth.uid())` forces evaluation at plan time and caches the result for the query's lifetime, changing evaluation timing from per-row to per-query.
- **Affected:** 124 policies with `auth.uid()`, 2 policies with `auth.role()` (both on `songs` table), across 32 tables.
- **Confidence:** `HIGH` — confirmed via `SELECT COUNT(*) FROM pg_policies WHERE schemaname='public' AND (qual LIKE '%auth.uid()%' OR with_check LIKE '%auth.uid()%')` returning 124 rows across 32 distinct tables, plus 2 additional rows for `auth.role()`.

**Function search_path issue:**

- **Cause:** `get_user_band_role` function was created in migration `20260302000000_band_user_roles.sql` without `SET search_path` attribute and was not included in the Aug 14, 2026 search_path hardening migrations.
- **Mechanism:** Functions without explicit `search_path` configuration can be subject to search_path injection attacks or namespace confusion. GUARDRAILS.md §4 mandates `SET search_path = public` for all production functions (both SECURITY DEFINER and SECURITY INVOKER).
- **Confidence:** `HIGH` — confirmed via `SELECT prosecdef, proconfig FROM pg_proc WHERE proname='get_user_band_role'` returning `prosecdef=false, proconfig=null`, and verified no subsequent migrations modified this function's search_path.

## Reference Docs Consulted

**Architecture and database conventions:**

- `docs/reference/architecture/database_schema.md` — RLS policy inventory, RBAC conventions, function signatures
- `docs/reference/architecture/supabase_functions.md` — Edge function list (confirmed no RPC dependencies on policy evaluation)
- `docs/reference/architecture/architecture.md` — Init order, platform differences, RBAC enforcement (RLS as final authority)
- `docs/agents/GUARDRAILS.md` — Supabase safety rules (§4: "always include SET search_path = public")
- `docs/agents/OPERATING_MODEL.md` — Pipeline gates, production deployment protocol, safety non-negotiables

**Precedent feature for migration pattern:**

- `docs/features/security-definer-revoke-public/ARCHITECT_PLAN.md` — Established pattern for batched ACL migrations with PRE*MIGRATION*\*\_STATE.md companion file for rollback
- `docs/features/security-definer-revoke-public/PRE_MIGRATION_ACL_STATE.md` — Example of capturing exact pre-migration state from live database for rollback plans

**No domain-specific notification docs required** — this feature is database-only performance/security hardening with no connection to notification delivery, setlist ordering, or other business logic.

## Existing System Analysis

### Current RLS Policy Pattern

All 126 affected policies follow this pattern (example from `gigs` table):

```sql
CREATE POLICY "Band members can view gigs" ON public.gigs
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = gigs.band_id
      AND user_id = auth.uid()  -- ← Direct call, re-evaluated per row
      AND status = 'active'
  )
);
```

The `auth.uid()` call is bare — not wrapped in a subselect. PostgreSQL treats this as a volatile expression and creates an InitPlan node in the query plan that re-executes `auth.uid()` for every row the query scans, even though the result is constant for the query's lifetime.

**Tables affected (32):**
bands, band_members, band_invitations, gigs, gig_responses, rehearsals, rehearsal_dates, setlists, songs, setlist_songs, setlist_special_items, song_notes, notifications, notification_preferences, device_tokens, band_calendar_subscriptions, venues, venue_contacts, contacts, block_dates, contributor_permissions, financial_entries, financial_entry_splits, print_templates, profiles, users, user_band_roles, band_access_events, gig_dates, enrichment_settings, app_config, feedback

**Auth function calls:**

- `auth.uid()` appears in 124 policy expressions
- `auth.role()` appears in 2 policy expressions (both on `songs` table for authenticated-only access)

### Current `get_user_band_role` Definition

```sql
CREATE OR REPLACE FUNCTION public.get_user_band_role(p_band_id UUID)
RETURNS TEXT AS $$
  SELECT role::TEXT FROM public.band_members
  WHERE band_id = p_band_id
    AND user_id = auth.uid()
    AND status = 'active'
  LIMIT 1;
$$ LANGUAGE sql STABLE;
```

**Attributes:**

- `prosecdef = false` (SECURITY INVOKER — intentional per migration comment)
- `proconfig = null` (no SET search_path)
- Created: `20260302000000_band_user_roles.sql`
- Last modified: Never (no subsequent ALTER FUNCTION)

The function is SECURITY INVOKER by design (the migration comment explicitly explains why DEFINER would be inappropriate), but still requires immutable `search_path` per GUARDRAILS.md §4.

### Why These Issues Exist

**RLS policy pattern:**

- No migration template or linting rule enforces subselect wrapping
- Postgres accepts the bare call syntax — no compile-time error
- Performance impact is query-dependent (only visible on scans of many rows)
- Developer intent (authorization logic) is correct; only evaluation timing is suboptimal

**`get_user_band_role` search_path gap:**

- Aug 14, 2026 hardening sweep used explicit function name lists (`ALTER FUNCTION <name>(...) SET search_path = public`)
- `get_user_band_role` was not included in either `20260814120003` (33 functions) or `20260814120005` (7 functions)
- No automated inventory or advisor query was run to find remaining functions without `search_path`
- This feature closes the gap by adding the missing configuration

## Proposed Solution

### Core Changes

1. **Wrap all auth function calls in RLS policies** — Replace all 126 RLS policies (DROP POLICY + CREATE POLICY) with identical authorization logic but wrapped auth function calls:
   - `auth.uid()` → `(select auth.uid())`
   - `auth.role()` → `(select auth.role())`
   - All other predicate logic remains byte-for-byte identical

2. **Add search_path to `get_user_band_role`** — `ALTER FUNCTION public.get_user_band_role(uuid) SET search_path = public;`

3. **Capture pre-migration RLS state** — Before implementing, Engineer will capture the exact `CREATE POLICY` definition for every affected policy by querying `pg_policies` and generating complete `CREATE POLICY` statements for rollback reference.

### Migration Strategy

**Two sequential migration files:**

1. `20260823120000_wrap_rls_auth_functions.sql` — Replace all 126 RLS policies
   - Structure: DROP POLICY for each policy, then CREATE POLICY with wrapped auth calls
   - Rollback plan embedded in migration comments with exact pre-migration CREATE POLICY statements

2. `20260823120001_harden_get_user_band_role_search_path.sql` — Add search_path to `get_user_band_role`
   - Single statement: `ALTER FUNCTION public.get_user_band_role(uuid) SET search_path = public;`
   - Rollback: `ALTER FUNCTION public.get_user_band_role(uuid) RESET search_path;`

**Why two migrations, not one:**

- Logical separation: RLS policy performance optimization vs. function security hardening
- Granular rollback: If policy migration encounters issues, function hardening can still proceed (or vice versa)
- Clearer git history and QA verification surface

**Why not batched (like security-definer-revoke-public):**

- RLS policy changes are atomic — all 126 policies are replaced in a single transaction with identical mechanical transformation
- No functional interdependencies between policies
- Single migration file keeps the transformation visually verifiable (side-by-side old-vs-new in one diff)
- Function hardening is independent and already minimal (one ALTER statement)

### Example Side-by-Side Transformation

**Before (one of 124 auth.uid() policies):**

```sql
CREATE POLICY "Band members can view gigs" ON public.gigs
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = gigs.band_id
      AND user_id = auth.uid()
      AND status = 'active'
  )
);
```

**After:**

```sql
CREATE POLICY "Band members can view gigs" ON public.gigs
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = gigs.band_id
      AND user_id = (select auth.uid())
      AND status = 'active'
  )
);
```

**Before (one of 2 auth.role() policies):**

```sql
CREATE POLICY "Songs are viewable by authenticated users" ON public.songs
FOR SELECT USING (
  auth.role() = 'authenticated'::text
);
```

**After:**

```sql
CREATE POLICY "Songs are viewable by authenticated users" ON public.songs
FOR SELECT USING (
  (select auth.role()) = 'authenticated'::text
);
```

**Verification:** Authorization logic is byte-for-byte identical except for the added `(select ...)` wrapper. Every policy should allow the same set of rows post-migration as pre-migration.

## Database Impact

**Migrations:** Required — 2 new migration files as described above.

**RLS Policies:**

- Affected — all 126 policies replaced (124 with `auth.uid()`, 2 with `auth.role()`)
- Authorization logic unchanged — only evaluation timing changes (per-query vs per-row)
- Tables: 32 of 35 tables in public schema

**RPC Functions:**

- Affected — `get_user_band_role` receives `SET search_path = public` attribute
- Signature unchanged, body unchanged, only function attributes modified via ALTER FUNCTION

**Triggers:** Not applicable — no trigger logic changes.

**Performance Impact:**

- Expected improvement on queries scanning many rows (e.g., setlist with 100+ songs, gig list with 50+ events)
- Impact is query-plan-dependent — queries scanning 1-10 rows may see no measurable difference
- Worst case: no performance improvement (optimizer chooses same plan) — no regression expected

## Flutter Architecture Changes

None — this is a database-only change. No Dart code, state management, widgets, or repositories require modification.

## Files to Create

| File                                                                           | Justification                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docs/features/rls-policy-performance-hardening/ARCHITECT_PLAN.md`             | This plan — required per ARCHITECT.md Phase 12                                                                                                                                                                                |
| `docs/features/rls-policy-performance-hardening/PRE_MIGRATION_RLS_STATE.md`    | Rollback reference — captures exact CREATE POLICY definitions for all 126 affected policies before migration execution. Follows precedent from `security-definer-revoke-public` feature's PRE_MIGRATION_ACL_STATE.md pattern. |
| `supabase/migrations/20260823120000_wrap_rls_auth_functions.sql`               | Replace all 126 RLS policies with auth function calls wrapped in subselects. Must include complete rollback plan in comments.                                                                                                 |
| `supabase/migrations/20260823120001_harden_get_user_band_role_search_path.sql` | Add SET search_path = public to `get_user_band_role` function.                                                                                                                                                                |

## Files to Modify

| File | What changes                                                                                                                                                                                                                                              |
| ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| None | No existing files require modification — this is a pure-addition migration feature with new SQL files only. GUARDRAILS.md already contains the correct rule ("always include SET search_path = public") from the Aug 14 hardening work; no update needed. |

## Files Off-Limits

| File                                  | Reason                                                                   |
| ------------------------------------- | ------------------------------------------------------------------------ |
| All files under `lib/`                | Flutter code unchanged — database-only change per plan scope             |
| All files under `supabase/functions/` | Edge functions unchanged — no RPC or RLS dependencies affected           |
| All existing migration files          | Approved migrations — never modify post-deployment                       |
| `lib/main.dart`                       | Init order must not change (GUARDRAILS.md §1)                            |
| `.github/copilot-instructions.md`     | Coding instructions unchanged — no new architectural patterns introduced |

## System Impact Map

| System                                 | Impact                                                                                                                                                               |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | Affected — RLS policies updated (auth function wrapping only), authorization logic unchanged, performance may improve on large gig lists                             |
| Rehearsals                             | Affected — RLS policies updated (auth function wrapping only), authorization logic unchanged                                                                         |
| Setlists / Catalog                     | Affected — RLS policies updated (auth function wrapping only), authorization logic unchanged, performance may improve on catalog queries (1,733 songs in production) |
| Members / RBAC                         | Affected — `get_user_band_role` receives search_path hardening; RLS policies on `band_members` updated; authorization logic unchanged                                |
| Auth / Session                         | Unaffected — authentication flows use built-in Supabase auth, not these policies or functions                                                                        |
| Routing                                | Unaffected — no routing logic changes                                                                                                                                |
| Notifications                          | Affected — RLS policies on `notifications`, `notification_preferences`, `device_tokens` updated; authorization logic unchanged                                       |
| Platform (iOS / Android / Web / macOS) | Affected (all) — all platforms may benefit from performance optimization on queries scanning many rows; no behavior change expected                                  |
| Financial Entries                      | Affected — RLS policies updated; authorization logic unchanged                                                                                                       |

## Regression Risk

**Level:** `LOW`

**Rationale:**

**-Risk (LOW):**

- Pure performance/security optimization — no intended authorization logic changes
- Database-only changes — no client code, UI, state management, or routing modifications
- Mechanically verifiable transformation — `auth.uid()` → `(select auth.uid())` can be verified via simple text diff
- Well-documented Postgres pattern — Supabase's own Performance Advisor documentation recommends this exact transformation
- Pre/post migration RLS state can be compared byte-for-byte (excluding whitespace/parens)
- Small migration surface — 2 SQL files, 1 function attribute change via ALTER, 126 policy replacements with identical mechanical pattern
- Advisor-driven — both issues flagged by Supabase built-in advisors, not speculative optimization
- Rollback is mechanical — PRE_MIGRATION_RLS_STATE.md captures exact CREATE POLICY statements for restoration

**+Risk (MEDIUM):**

- 126 policies affected — any typo in policy name, table name, or predicate expression could change authorization behavior
- No staging environment — changes apply directly to production database serving 100+ bands' live data
- Zero automated test coverage on RLS policies — manual verification is the only safety net

**+Risk (LOW):**

- Manual migration authoring — policies must be transcribed from pg_policies output; copy-paste errors possible
- Search-and-replace risk — if Engineer uses blind find/replace instead of policy-by-policy review, subtle predicate differences could be missed

**Mitigations in place:**

- PRE_MIGRATION_RLS_STATE.md capture before implementation — complete rollback path
- Side-by-side old-vs-new comparison required in migration comments for at least 3 example policies per table
- Post-migration verification query that diffs policy definitions excluding whitespace/parens
- Behavioral smoke test: confirm specific known allow/deny outcomes unchanged (e.g., cross-band access still denied, same-band access still allowed)
- Two-stage verification: Tier 1 (syntax-only SQL validation) and Tier 2 (post-deployment behavioral check)

**Why risk is LOW, not MEDIUM:**

- The transformation is purely additive parentheses — no logic rewrites, no new predicates, no table joins changed
- RLS policies are fail-closed — if a policy is incorrect post-migration, users will see "no data" or "permission denied," not data leakage across bands
- Authorization logic testing already happens implicitly via production use — 100+ bands querying data daily; any regression would surface immediately
- Rollback is instant — captured state allows full policy restoration in <5 minutes if regression detected post-deploy

Overall risk is LOW because the transformation is mechanical, the pattern is well-documented, and rollback is comprehensive.

## Engineer Task Breakdown

Execute in strict order. Do not skip. Do not parallelize.

### Task 1: Capture Pre-Migration RLS State

**Goal:** Create `PRE_MIGRATION_RLS_STATE.md` with exact CREATE POLICY definitions for all 126 affected policies.

**Steps:**

1. Query live database via `supabase db query --linked` to extract all policies with auth function calls:

   ```sql
   SELECT
     schemaname,
     tablename,
     policyname,
     cmd,
     permissive,
     roles,
     qual,
     with_check
   FROM pg_policies
   WHERE schemaname = 'public'
     AND (qual LIKE '%auth.uid()%' OR with_check LIKE '%auth.uid()%'
          OR qual LIKE '%auth.role()%' OR with_check LIKE '%auth.role()%')
   ORDER BY tablename, policyname;
   ```

2. For each row, construct the exact `CREATE POLICY` statement:

   ```sql
   CREATE POLICY "<policyname>" ON public.<tablename>
   FOR <cmd>
   [TO <roles>]
   [USING (<qual>)]
   [WITH CHECK (<with_check>)];
   ```

3. Write all 126 CREATE POLICY statements to `PRE_MIGRATION_RLS_STATE.md` with:
   - Header documenting capture date, source (production), and purpose (rollback reference)
   - Table of contents grouping policies by table
   - Complete CREATE POLICY statement for each policy (not abbreviated)

4. Verify count: exactly 126 policies captured (124 auth.uid() + 2 auth.role()).

**Output:** `PRE_MIGRATION_RLS_STATE.md` exists and is committed to git before Task 2 begins.

### Task 2: Write Migration — Wrap RLS Auth Functions

**Goal:** Create `supabase/migrations/20260823120000_wrap_rls_auth_functions.sql`.

**Structure:**

```sql
-- ============================================================================
-- Wrap auth function calls in RLS policies for performance optimization
-- ============================================================================
-- Feature: rls-policy-performance-hardening
-- Issue: RLS policies call auth.uid() and auth.role() directly, causing
--        Postgres to re-evaluate per row instead of per query (InitPlan)
-- Fix: Wrap auth function calls in (select ...) subselects to force
--      plan-time evaluation and cache result for query lifetime
-- ============================================================================
-- Performance Advisor: 124 auth_rls_initplan warnings (auth.uid())
--                      2 policies with auth.role() (songs table)
--                      32 tables affected
-- ============================================================================

-- ===========================================================================
-- TABLE: bands (example — repeat for all 32 tables)
-- ===========================================================================

-- Policy: "Band members can view bands"
-- Old: EXISTS (SELECT 1 FROM band_members WHERE ... AND user_id = auth.uid() ...)
-- New: EXISTS (SELECT 1 FROM band_members WHERE ... AND user_id = (select auth.uid()) ...)
DROP POLICY IF EXISTS "Band members can view bands" ON public.bands;
CREATE POLICY "Band members can view bands" ON public.bands
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = bands.id
      AND user_id = (select auth.uid())
      AND status = 'active'
  )
);

-- [Repeat for all 126 policies across all 32 tables]

-- ===========================================================================
-- ROLLBACK PLAN
-- ===========================================================================
-- Restore exact pre-migration policy definitions from PRE_MIGRATION_RLS_STATE.md
-- For each policy:
--   DROP POLICY IF EXISTS "<policyname>" ON public.<tablename>;
--   CREATE POLICY "<policyname>" ON public.<tablename>
--   [exact definition from PRE_MIGRATION_RLS_STATE.md]
```

**Critical requirements:**

- Every policy must include a comment showing the old and new auth function call side-by-side
- Policies must be grouped by table with clear section headers
- Rollback plan must reference PRE_MIGRATION_RLS_STATE.md (not inline the full rollback SQL — file would be 10,000+ lines)
- Migration must be idempotent (use DROP POLICY IF EXISTS)

**Output:** Migration file complete and ready for Tier 1 verification.

### Task 3: Write Migration — Harden get_user_band_role Search Path

**Goal:** Create `supabase/migrations/20260823120001_harden_get_user_band_role_search_path.sql`.

**Structure:**

```sql
-- ============================================================================
-- Add SET search_path to get_user_band_role function
-- ============================================================================
-- Feature: rls-policy-performance-hardening
-- Issue: get_user_band_role was created without SET search_path and missed
--        during Aug 14, 2026 search_path hardening sweep
-- Fix: Add immutable search_path via ALTER FUNCTION
-- ============================================================================
-- Security Advisor: 1 function_search_path_mutable warning
-- Created: 20260302000000_band_user_roles.sql
-- Last modified: Never
-- ============================================================================

ALTER FUNCTION public.get_user_band_role(uuid) SET search_path = public;

-- ===========================================================================
-- ROLLBACK
-- ===========================================================================
-- ALTER FUNCTION public.get_user_band_role(uuid) RESET search_path;
```

**Output:** Migration file complete and ready for Tier 1 verification.

### Task 4: Write ENGINEER_REPORT.md

Document:

- Tasks completed
- Migration files created with line counts
- `PRE_MIGRATION_RLS_STATE.md` with policy count
- Tier 1 verification results (see Verification Plan below)
- Any deviations from plan or blockers encountered
- Ready for QA: YES/NO

**Output:** `ENGINEER_REPORT.md` exists and is committed to git.

## Verification Plan

**Critical:** Migration execution happens at the Release Gate after QA APPROVED, never by the Engineer during implementation. The Engineer produces the migration files only; the Manager applies them to production after QA verifies the plan and SQL correctness.

### Tier 1 — Pre-Deployment (Engineer Responsibility)

**Purpose:** Verify migration SQL syntax and transformation correctness without modifying the live database.

**Environment:** Read-only inspection of live production database + local SQL validation.

**Tests:**

**PRE-DEPLOY TEST 1: Verify policy capture completeness**

```sql
-- Run against live production (read-only)
-- Confirm PRE_MIGRATION_RLS_STATE.md captured all affected policies
SELECT
  COUNT(*) as captured_policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual LIKE '%auth.uid()%' OR with_check LIKE '%auth.uid()%'
       OR qual LIKE '%auth.role()%' OR with_check LIKE '%auth.role()%');
-- Expected: 126 (124 auth.uid() + 2 auth.role())
-- Compare against policy count in PRE_MIGRATION_RLS_STATE.md
```

**PRE-DEPLOY TEST 2: Verify get_user_band_role current state**

```sql
-- Run against live production (read-only)
-- Confirm function currently lacks search_path
SELECT
  proname,
  prosecdef as is_security_definer,
  proconfig as current_search_path_config
FROM pg_proc
WHERE proname = 'get_user_band_role'
  AND pronamespace = 'public'::regnamespace;
-- Expected: prosecdef = false, proconfig = null
```

**PRE-DEPLOY TEST 3: Syntax validation (local dry-run)**

```bash
# Parse migration SQL locally without executing
cat supabase/migrations/20260823120000_wrap_rls_auth_functions.sql | psql --dry-run
cat supabase/migrations/20260823120001_harden_get_user_band_role_search_path.sql | psql --dry-run
# Expected: No syntax errors
```

**PRE-DEPLOY TEST 4: Transformation pattern verification**

```bash
# Count auth function calls in migration file
# Every bare auth.uid() should become (select auth.uid())
# Every bare auth.role() should become (select auth.role())
grep -c "auth\.uid()" supabase/migrations/20260823120000_wrap_rls_auth_functions.sql
# Expected: 0 (all should be wrapped)
grep -c "(select auth\.uid())" supabase/migrations/20260823120000_wrap_rls_auth_functions.sql
# Expected: 124

grep -c "auth\.role()" supabase/migrations/20260823120000_wrap_rls_auth_functions.sql
# Expected: 0 (all should be wrapped)
grep -c "(select auth\.role())" supabase/migrations/20260823120000_wrap_rls_auth_functions.sql
# Expected: 2
```

**Tier 1 completion criteria:**

- All 4 pre-deploy tests pass
- PRE_MIGRATION_RLS_STATE.md contains exactly 126 policies
- Migration files parse without syntax errors
- No bare `auth.uid()` or `auth.role()` calls remain in policy USING/WITH CHECK clauses (all wrapped)

### Tier 2 — Post-Deployment (Manager Responsibility at Release Gate)

**Purpose:** Verify migrations applied correctly and authorization behavior is unchanged.

**Environment:** Live production database after `supabase db push` completes successfully.

**Tests:**

**POST-DEPLOY TEST 1: Verify policy replacement succeeded**

```sql
-- Run against live production (read-only)
-- Confirm all policies now have wrapped auth function calls
SELECT
  COUNT(*) as wrapped_policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual LIKE '%(select auth.uid())%' OR with_check LIKE '%(select auth.uid())%'
       OR qual LIKE '%(select auth.role())%' OR with_check LIKE '%(select auth.role())%');
-- Expected: 126 (matching pre-migration count)

-- Confirm no policies still have bare auth function calls
SELECT
  COUNT(*) as bare_call_count
FROM pg_policies
WHERE schemaname = 'public'
  AND (
    (qual ~ '\sauth\.uid\(\)' AND qual NOT LIKE '%(select auth.uid())%')
    OR (with_check ~ '\sauth\.uid\(\)' AND with_check NOT LIKE '%(select auth.uid())%')
    OR (qual ~ '\sauth\.role\(\)' AND qual NOT LIKE '%(select auth.role())%')
    OR (with_check ~ '\sauth\.role\(\)' AND with_check NOT LIKE '%(select auth.role())%')
  );
-- Expected: 0
```

**POST-DEPLOY TEST 2: Verify get_user_band_role search_path hardened**

```sql
-- Run against live production (read-only)
SELECT
  proname,
  proconfig
FROM pg_proc
WHERE proname = 'get_user_band_role'
  AND pronamespace = 'public'::regnamespace;
-- Expected: proconfig = {"search_path=public"}
```

**POST-DEPLOY TEST 3: Behavioral smoke test — same-band access allowed**

```sql
-- Run against live production (read-only)
-- Confirm a known band member can still read their band's gigs
-- Use a real band_id and user_id from production (read from band_members table)
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims.sub = '<real-user-uuid>';

SELECT COUNT(*) as my_gigs
FROM gigs
WHERE band_id = '<real-band-uuid-where-user-is-member>';
-- Expected: COUNT > 0 (user can see their own band's gigs)
```

**POST-DEPLOY TEST 4: Behavioral smoke test — cross-band access denied**

```sql
-- Run against live production (read-only)
-- Confirm user cannot read gigs from a band they're not a member of
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims.sub = '<real-user-uuid>';

SELECT COUNT(*) as other_gigs
FROM gigs
WHERE band_id = '<different-band-uuid-where-user-is-not-member>';
-- Expected: COUNT = 0 (cross-band access still blocked)
```

**POST-DEPLOY TEST 5: Verify Performance Advisor warnings cleared**

**Instructions:** Call `mcp__Supabase__get_advisors` with `project_id: "nekwjxvgbveheooyorjo"`, `type: "performance"`. Filter the returned `lints` array for entries where `name == "auth_rls_initplan"`. Record the count in QA_REPORT.md. Expected: 0 (baseline pre-migration: 124). Fallback only if the tool call fails: Dashboard → Database → Advisors → Performance tab, search `auth_rls_initplan`.

**POST-DEPLOY TEST 6: Verify Security Advisor warnings cleared**

**Instructions:** Call `mcp__Supabase__get_advisors` with `project_id: "nekwjxvgbveheooyorjo"`, `type: "security"`. Filter the returned `lints` array for entries where `name == "function_search_path_mutable"` AND the detail references `get_user_band_role`. Record the count in QA_REPORT.md. Expected: 0 (baseline pre-migration: 1). Fallback only if the tool call fails: Dashboard → Database → Advisors → Security tab, search `function_search_path_mutable`.

**Tier 2 completion criteria:**

- All 6 post-deploy tests pass
- Authorization behavior unchanged (same-band allowed, cross-band denied)
- Performance and Security Advisors report 0 warnings for auth_rls_initplan and function_search_path_mutable

**If any Tier 2 test fails:**

1. Manager executes rollback plan from PRE_MIGRATION_RLS_STATE.md
2. Engineer investigates failure cause
3. Migration is revised and re-submitted for QA review
4. Pipeline returns to Architecture Gate for plan amendment if root cause requires design change

## QA Regression Areas

QA must verify the following areas remain functionally unchanged after migration:

### Authorization Behavior (Critical)

1. **Band-scoped data access** — logged-in users can read/write only their own bands' data:
   - View gig list for own band → success
   - View gig list for another band → empty (403 or zero rows)
   - Same test for rehearsals, setlists, songs, notifications, financial entries

2. **RBAC enforcement** — admin/member/contributor roles still gate operations correctly:
   - Admin can delete gig → success
   - Member can edit gig → success
   - Contributor with limited permissions cannot delete gig → permission denied

3. **Unauthenticated access** — anon users cannot read band-scoped data:
   - Logout
   - Attempt to query gigs table via PostgREST → 403 or empty
   - Attempt to query setlists table → 403 or empty

### Core Workflows (Functional)

4. **Gig creation and editing** — create a gig, edit name/date, delete it
5. **Rehearsal creation and editing** — create a rehearsal, edit location/time, delete it
6. **Setlist operations** — add song to setlist, reorder songs, remove song, delete setlist
7. **Catalog operations** — add song to Catalog, edit BPM/duration/tuning, delete song
8. **Notification delivery** — create a gig, verify band members receive notification (iOS push if possible, otherwise in-app notification list)
9. **Member management** — invite new member, accept invite, change member role, remove member

### Performance (Observational)

10. **Large query performance** — open Catalog with 100+ songs, observe load time (should not regress)
11. **Gig list with 50+ events** — observe load time (should not regress)

QA should report:

- Any authorization regression (user sees data they shouldn't, or cannot see data they should)
- Any functional workflow failure (CRUD operation that previously worked now fails)
- Any performance regression (observable delay increase on large queries)

## Rollout / Migration Strategy

**Production-only deployment — no staging environment exists.**

The live Supabase project `nekwjxvgbveheooyorjo` serves 100+ real bands' production data. `bandroadie-staging-2` was permanently deleted 2026-08-09. This migration applies directly to production after QA APPROVED.

**Pre-deployment:**

1. Engineer implements migrations and captures PRE_MIGRATION_RLS_STATE.md (Tasks 1-3)
2. Engineer runs Tier 1 verification (pre-deploy tests 1-4)
3. Engineer writes ENGINEER_REPORT.md and signals QA
4. QA reviews plan, PRE_MIGRATION_RLS_STATE.md, migration SQL, and Tier 1 verification results
5. QA verdict: APPROVED or REQUIRES CHANGES
6. If REQUIRES CHANGES, Engineer revises and pipeline returns to QA
7. If APPROVED, Manager proceeds to Release Gate

**At Release Gate (Manager applies migration):**

1. Manager verifies git branch is up to date with main and ENGINEER_REPORT.md shows all Tier 1 tests passed
2. Manager runs `supabase db push --linked` to apply both migration files to production
3. If push fails, Manager executes rollback plan and escalates to Engineer
4. If push succeeds, Manager immediately runs Tier 2 verification (post-deploy tests 1-6)
5. If Tier 2 fails, Manager executes rollback plan from PRE_MIGRATION_RLS_STATE.md and escalates
6. If Tier 2 passes, Manager signals QA for post-deployment regression testing
7. QA performs manual regression testing per QA Regression Areas section above
8. If QA finds regression, Manager executes rollback and escalates
9. If QA confirms no regression, Manager merges feature branch to main and deletes branch

**Rollback procedure (if needed):**

1. Manager opens `PRE_MIGRATION_RLS_STATE.md`
2. For each of 126 policies, Manager runs:
   ```sql
   DROP POLICY IF EXISTS "<policyname>" ON public.<tablename>;
   CREATE POLICY "<policyname>" ON public.<tablename>
   [exact definition from PRE_MIGRATION_RLS_STATE.md];
   ```
3. For `get_user_band_role`, Manager runs:
   ```sql
   ALTER FUNCTION public.get_user_band_role(uuid) RESET search_path;
   ```
4. Manager re-runs Tier 2 post-deploy tests to confirm rollback succeeded
5. Manager escalates to Architect for plan revision

**Timeline:**

- Engineer implementation: 2-4 hours (policy capture + migration authoring)
- Tier 1 verification: 30 minutes
- QA review: 1-2 hours
- Manager migration execution: 5 minutes (push + Tier 2 verification)
- QA regression testing: 1-2 hours
- Total elapsed: 4-8 hours (single session)

## Out of Scope

**Explicitly excluded from this feature:**

1. **Multiple permissive policies warnings (102)** — Separate Performance Advisor category; requires policy consolidation or architecture decision; queued for separate Feature Input.

2. **Unused index warnings (9)** — Separate Performance Advisor category; requires query analysis to determine if indexes are genuinely unused or only used by rare queries; queued for separate Feature Input.

3. **Other auth/session function optimizations** — If any policies call `auth.jwt()`, `current_setting()`, or other session functions not flagged by the advisor, they are out of scope unless explicitly confirmed to have the same InitPlan behavior.

4. **Performance benchmarking** — No baseline query timing measurements or query plan comparisons are required. This feature trusts the Performance Advisor's recommendation and Supabase's documented guidance that subselect wrapping improves performance for queries scanning many rows.

5. **Policy consolidation** — Some tables have multiple similar policies (e.g., setlists has both "Band members can view setlists" and "Admins and members can view setlists"). Consolidating or refactoring these is out of scope; this feature only wraps auth function calls in existing policies.

6. **RLS policy testing framework** — No automated test harness for RLS policies is introduced. Manual verification and production usage remain the verification path.

7. **Function search_path audit** — This feature hardens only `get_user_band_role`. Auditing all other functions for missing search_path is out of scope (the Aug 14 sweep covered 40 functions; if others were missed, they require a separate audit).

8. **Client code performance optimization** — No Flutter/Dart code changes are in scope. This is a database-only optimization.

**If any of the above become requirements during implementation, Engineer must stop and escalate to Architect for plan amendment.**
