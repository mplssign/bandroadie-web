# Architect Plan — feature/rls-consolidate-permissive-policies

## Feature Slug

`feature/rls-consolidate-permissive-policies`

## Problem Summary

Supabase Performance Advisor reports 102 `multiple_permissive_policies` warnings (live-confirmed 2026-08-25 against project `nekwjxvgbveheooyorjo`) across 11 tables. Root cause: each affected table carries two or more stacked generations of RLS policies that were never reconciled — legacy policies scoped TO public, newer policies scoped TO authenticated using SECURITY DEFINER helper functions. Postgres must OR and evaluate all PERMISSIVE policies for each row scan, creating measurable overhead.

This is a separate Advisor category from the already-completed `auth_rls_initplan` work (feature/rls-policy-performance-hardening). That feature wrapped `auth.uid()` calls; this feature consolidates duplicate/overlapping policies to achieve exactly one PERMISSIVE policy per (table, role, action) combination.

## Root Cause

**Cause:** Each of the 11 affected tables has multiple PERMISSIVE RLS policies for the same (table, action) combination, with different role scoping (TO public vs TO authenticated) or different implementation styles (inline EXISTS vs SECURITY DEFINER helper functions). The legacy TO public policies were never dropped when newer TO authenticated policies were added.

**Mechanism:**

- PostgreSQL's RLS evaluator ORs together all PERMISSIVE policies for a given (table, role, action), executing each policy's predicate for every row scanned
- Legacy policies scoped TO public create role fanout — the same logical policy duplication shows up as up to 7 separate Advisor warnings (once per role that inherits from public: anon, authenticated, authenticator, cli_login_postgres, dashboard_user, reviewer_readonly, supabase_privileged_role)
- Newer policies scoped TO authenticated use cleaner helper functions (`is_band_member()`, `is_band_admin()`) but were layered on top of legacy policies instead of replacing them
- The Advisor detects this pattern and flags each (table, role, action) tuple with multiple PERMISSIVE policies as a performance warning

**Confidence:** `HIGH` — confirmed via:

- `get_advisors(type=performance)` returning exactly 102 `multiple_permissive_policies` warnings across 11 tables (2026-08-25)
- Direct `pg_policies` inspection showing policy count per table: bands (9 policies), setlists (11), setlist_songs (9), rehearsals (9), songs (6), profiles (8), users (8), gig_responses (8), band_members (4), contributor_permissions (2), user_band_roles (4)
- Expected consolidated count: ~39 policies (one per table+action, some tables have fewer than 4 actions covered)

## Reference Docs Consulted

**Architecture and database conventions:**

- `docs/reference/architecture/database_schema.md` — RLS policy inventory, RBAC conventions, table schemas, RPC function signatures
- `docs/agents/GUARDRAILS.md` — Supabase safety rules (RLS self-referencing prohibition, migration discipline)
- `docs/agents/OPERATING_MODEL.md` — Pipeline gates, commit gate requirements

**Precedent features:**

- `docs/features/rls-policy-performance-hardening/ARCHITECT_PLAN.md` — Established PRE_MIGRATION_RLS_STATE.md pattern for capturing rollback state
- `docs/features/rls-migration-comment-escaping/ARCHITECT_PLAN.md` — Critical lesson: multi-line comments in migration files must have every line prefixed with `--`, not just the first line. Use single-line comments only for inline documentation.

**Repository memory:**

- `/memories/repo/supabase.md` — Documents Supabase branch creation failures (status MIGRATIONS_FAILED with zero migrations applied due to cascading failures during automated replay). Also documents that migrations 001-072 were never committed to version control, causing branch creation to fail replaying migration 073 against an empty database.

## Existing System Analysis

### Current RLS Policy Generations

**Affected tables and policy counts (from live pg_policies, 2026-08-25):**

| Table                   | Total Policies | TO public | TO authenticated |
| ----------------------- | -------------: | --------: | ---------------: |
| bands                   |              9 |         5 |                4 |
| setlists                |             11 |         7 |                4 |
| setlist_songs           |              9 |         5 |                4 |
| rehearsals              |              9 |         4 |                5 |
| songs                   |              6 |         3 |                3 |
| profiles                |              8 |         4 |                4 |
| users                   |              8 |         4 |                4 |
| gig_responses           |              8 |         4 |                4 |
| band_members            |              4 |         4 |                0 |
| contributor_permissions |              2 |         2 |                0 |
| user_band_roles         |              4 |         4 |                0 |

**Example — bands DELETE policies (3 policies, should be 1):**

```sql
-- Legacy TO public, admin-only
CREATE POLICY "Only admins can delete bands" ON public.bands
FOR DELETE TO public
USING (EXISTS (
  SELECT 1 FROM band_members bm
  WHERE bm.band_id = bands.id
    AND bm.user_id = (SELECT auth.uid())
    AND bm.role = 'admin'::band_role_type
    AND bm.status = 'active'
));

-- Legacy TO public, creator-only
CREATE POLICY "bands: delete creator" ON public.bands
FOR DELETE TO public
USING (created_by = (SELECT auth.uid()));

-- Newer TO authenticated, admin-only (using helper function)
CREATE POLICY "bands_delete_admins" ON public.bands
FOR DELETE TO authenticated
USING (is_band_admin(id));
```

**Effective access:** Admin OR creator (because PERMISSIVE policies OR together). The three predicates are non-equivalent — consolidation must preserve both conditions.

### Pattern Categories

**Category A: Equivalent duplicates (safe to drop legacy, keep authenticated):**

- bands INSERT: "bands: insert own" (public) vs "bands_insert_authenticated" (authenticated) — identical `created_by = auth.uid()` check
- gig_responses ALL actions: public vs authenticated pairs all implement identical logic with different syntax (EXISTS join vs `is_band_member()` helper)
- profiles INSERT/UPDATE: public vs authenticated pairs are identical
- users INSERT/UPDATE: public vs authenticated pairs are identical

**Category B: Non-equivalent policies requiring OR'ed consolidation (from Feature Input Root Cause Notes 1-7):**

1. **band_members SELECT (Note 1):** "Active members can view band co-members" (`is_band_member(band_id)`) vs "Users can view own memberships" (`user_id = auth.uid()`). **Must verify:** Does `is_band_member()` already cover the user's own row, or is this genuinely non-equivalent? Function body shows it checks `user_id = auth.uid()` with no status filter, so likely equivalent. If equivalent, keep the broader policy; if not, OR both.

2. **bands DELETE (Note 2):** "Only admins can delete bands" (admin check) vs "bands: delete creator" (creator check) vs "bands_delete_admins" (admin check via helper). **Non-equivalent** — admin-only vs creator-only. Consolidated policy must allow admin OR creator.

3. **contributor_permissions (Note 3):** One ALL-command admin-only policy vs one SELECT-command member policy. For SELECT, both apply (admin is also a member), creating redundancy. For other commands (INSERT/UPDATE/DELETE), only the admin policy applies. **Decision required:** Split the ALL-command policy into per-command policies, or leave redundancy for SELECT and consolidate other commands separately.

4. **rehearsals DELETE/UPDATE (Note 4):** Legacy allows role IN (admin, member); newer allows admin only. **Non-equivalent** — consolidation must preserve member-role DELETE/UPDATE rights per PROJECT_CONTEXT.md RBAC table ("member has full CRUD for gigs/rehearsals/setlists").

5. **setlist_songs SELECT (Note 5):** One policy requires active band_members status, two do not. **Decision required:** Determine whether active-status filtering is intentional; if so, consolidate to require active; if not, consolidate to the broader (no status filter) predicate.

6. **setlists DELETE/INSERT/UPDATE (Note 6 — CRITICAL):** Legacy policy "Band members can X setlists" has NO role check (any band_members row qualifies, including contributor role). This is broader than PROJECT_CONTEXT.md RBAC table suggests (contributors should have "Configurable via contributor_permissions" access, not blanket CRUD). **Instruction from Feature Input:** Preserve current effective (wide-open) access; do not tighten. Add "Known Issue — Not Fixed Here" comment in migration.

7. **songs INSERT/SELECT (Note 7 — CRITICAL):** Two policies have no band-membership scoping at all (`auth.role() = 'authenticated'` and `USING (true)`). Effective access for songs SELECT/INSERT is currently unrestricted for any authenticated user regardless of band membership. **Instruction from Feature Input:** Preserve current wide-open behavior; do not tighten. Add "Known Issue — Not Fixed Here" comment in migration. Likely related to documented "Legacy songs with NULL band_id" global-catalog design.

### Why This Exists

- No migration template or policy consolidation linting enforced
- Policy additions were layered on incrementally as helper functions were introduced
- Developer intent (authorization logic) was correct; redundancy was not actively harmful (just suboptimal for performance)
- Postgres accepts multiple PERMISSIVE policies without error; only the Performance Advisor surfaces the inefficiency

## Proposed Solution

### Core Strategy

**For each of the 11 tables, consolidate to exactly one PERMISSIVE policy per action (SELECT, INSERT, UPDATE, DELETE):**

1. **Where policies are equivalent:** Keep the TO authenticated policy using `is_band_member()` / `is_band_admin()` helpers; drop the legacy TO public policy.

2. **Where policies are non-equivalent:** Create a consolidated policy scoped TO authenticated with all existing predicates OR'ed together to preserve current effective access.

3. **All consolidated policies:**
   - Scoped `FOR <action> TO authenticated` (not TO public)
   - Named using `<table>_<action>_<qualifier>` snake_case convention
   - Complete predicate logic with no simplifications that might narrow access

### Migration File

**One migration:** `20260825120000_consolidate_permissive_rls_policies.sql`

**Structure:**

- Header: Feature reference, Advisor count (102 warnings), brief description
- 11 table blocks, one per affected table
- Each block: DROP all existing policies for that table, then CREATE consolidated replacements (one per action)
- Inline comments: Single-line only (per `rls-migration-comment-escaping` lesson), document which legacy policies are dropped and why
- No multi-line policy definitions in comments — rollback state lives in PRE_MIGRATION_RLS_STATE.md

**Migration timestamp:** `20260825120000` (sorts after `20260824173132_fix_ensure_catalog_band_creation_race.sql`)

### Example Consolidations

**bands DELETE (Non-equivalent — Root Cause Note 2):**

```sql
-- DROP 3 existing policies
DROP POLICY IF EXISTS "Only admins can delete bands" ON public.bands;
DROP POLICY IF EXISTS "bands: delete creator" ON public.bands;
DROP POLICY IF EXISTS "bands_delete_admins" ON public.bands;

-- CREATE 1 consolidated policy preserving both admin AND creator rights
CREATE POLICY "bands_delete_creator_or_admin" ON public.bands
FOR DELETE TO authenticated
USING (is_band_admin(id) OR created_by = (select auth.uid()));
```

**gig_responses INSERT (Equivalent — safe to consolidate to authenticated helper):**

```sql
-- DROP 2 existing policies (identical logic, different syntax)
DROP POLICY IF EXISTS "Band members can create gig responses" ON public.gig_responses;
DROP POLICY IF EXISTS "gig_responses_insert_own" ON public.gig_responses;

-- CREATE 1 consolidated policy using cleaner helper function
CREATE POLICY "gig_responses_insert_own" ON public.gig_responses
FOR INSERT TO authenticated
WITH CHECK (user_id = (select auth.uid()) AND EXISTS (
  SELECT 1 FROM gigs g
  WHERE g.id = gig_responses.gig_id
    AND is_band_member(g.band_id)
));
```

**setlists DELETE (Non-equivalent — Root Cause Note 6, CRITICAL):**

```sql
-- DROP 3 existing policies
DROP POLICY IF EXISTS "Admins and members can delete setlists" ON public.setlists;
DROP POLICY IF EXISTS "Band members can delete setlists" ON public.setlists;
DROP POLICY IF EXISTS "setlists_delete_creator_or_admin" ON public.setlists;

-- CREATE 1 consolidated policy preserving broadest current access
-- Known Issue — Not Fixed Here: This preserves contributor-role DELETE access,
-- which is broader than PROJECT_CONTEXT.md RBAC table suggests. Fixing this
-- over-permissiveness is out of scope for this performance-focused feature.
CREATE POLICY "setlists_delete_members" ON public.setlists
FOR DELETE TO authenticated
USING (EXISTS (
  SELECT 1 FROM band_members bm
  WHERE bm.band_id = setlists.band_id
    AND bm.user_id = (select auth.uid())
    AND bm.status = 'active'
    -- No role filter — preserves current behavior where any active member can delete
));
```

**songs SELECT (Non-equivalent — Root Cause Note 7, CRITICAL):**

```sql
-- DROP 3 existing policies
DROP POLICY IF EXISTS "Band members can view songs" ON public.songs;
DROP POLICY IF EXISTS "Songs are viewable by authenticated users" ON public.songs;
DROP POLICY IF EXISTS "songs_select_authenticated" ON public.songs;

-- CREATE 1 consolidated policy preserving broadest current access
-- Known Issue — Not Fixed Here: Effective access is unrestricted for any
-- authenticated user (no band-membership check). Likely intentional for
-- "Legacy songs with NULL band_id" global-catalog design, but out of scope
-- to verify or fix here.
CREATE POLICY "songs_select_authenticated" ON public.songs
FOR SELECT TO authenticated
USING (true);
```

### Out of Scope

- **`is_band_admin(uuid)` STABLE marking** — Separate pre-existing issue (function calls `auth.uid()` unwrapped and is not marked STABLE); flagged but not fixed here
- **Fixing setlists contributor over-permissiveness (Note 6)** — Document as known issue, preserve current behavior
- **Fixing songs unrestricted access (Note 7)** — Document as known issue, preserve current behavior
- **`unused_index` (8) and `no_primary_key` (3) Advisor warnings** — Separate categories, not addressed here
- **Flutter/Dart code changes** — Database-only change
- **Migration file `20260823120000_wrap_rls_auth_functions.sql`** — Separate sibling feature on its own branch, unrelated

## Database Impact

**Migrations:** Required — one new migration file as described above.

**RLS Policies:**

- **Affected:** 11 tables, consolidating from ~78 total policies down to ~39 policies (one per table+action)
- **Authorization logic:** Unchanged for equivalent pairs; expanded via OR for non-equivalent pairs to preserve current effective access
- **Self-referencing check:** None — all authorization checks join against `band_members` or call SECURITY DEFINER helper functions; no policies query their own table

**RPC Functions:**

- **Not modified** — `is_band_member()`, `is_band_admin()`, `is_band_member_with_role()`, `get_bandmate_user_ids()` function bodies are off-limits per Feature Input
- **Note for record only:** `is_band_admin(uuid)` calls `auth.uid()` unwrapped and is not marked STABLE; separate issue, explicitly out of scope

**Triggers:** Not applicable — no trigger modifications required.

**Performance Impact:**

- Expected: Advisor warning count drops from 102 to 0 (or near-0 if any non-consolidatable edge cases remain)
- Row-scan performance may improve for queries on tables with many policies (e.g., setlists: 11→4, bands: 9→4)
- Impact is query-plan-dependent — most visible on queries scanning hundreds of rows

## Flutter Architecture Changes

None — this is a database-only change. No Dart code, state management, widgets, or repositories require modification.

## Files to Create

| File                                                                           | Justification                                                                                                                                                                                            |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docs/features/rls-consolidate-permissive-policies/ARCHITECT_PLAN.md`          | This plan — required per ARCHITECT.md Phase 12                                                                                                                                                           |
| `docs/features/rls-consolidate-permissive-policies/PRE_MIGRATION_RLS_STATE.md` | Rollback reference — captures exact CREATE POLICY definitions for all affected policies (78 policies across 11 tables) before migration execution. Follows `rls-policy-performance-hardening` precedent. |
| `supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql`   | Single migration file dropping redundant policies and creating consolidated replacements. Must use single-line comments only per `rls-migration-comment-escaping` lesson.                                |

## Files to Modify

None — no existing files require modification; this is a pure-addition migration feature.

## Files Off-Limits

| File                                                                                                      | Reason                                                                               |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| All files under `lib/`                                                                                    | Flutter code unchanged — database-only change                                        |
| All files under `supabase/functions/`                                                                     | Edge functions unchanged — no dependencies                                           |
| All existing migration files                                                                              | Approved migrations — never modify post-deployment                                   |
| `supabase/migrations/20260823120000_wrap_rls_auth_functions.sql`                                          | Sibling feature on separate branch (`bug/rls-migration-comment-escaping`), unrelated |
| `supabase/migrations/20260823120001_harden_get_user_band_role_search_path.sql`                            | Sibling feature on separate branch, unrelated                                        |
| Functions: `is_band_member()`, `is_band_admin()`, `is_band_member_with_role()`, `get_bandmate_user_ids()` | Explicitly off-limits per Feature Input; function bodies must not change             |
| `lib/main.dart`                                                                                           | Init order must not change (GUARDRAILS.md §1)                                        |

## System Impact Map

| System                           | Impact                                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Gigs                             | affected — RLS policies on `gig_responses` updated; authorization logic unchanged                            |
| Rehearsals                       | affected — RLS policies updated; Note 4 non-equivalence preserved (member-role DELETE/UPDATE rights)         |
| Setlists / Catalog               | affected — RLS policies updated; Note 6 over-permissiveness preserved as-is (known issue flagged)            |
| Members / RBAC                   | affected — RLS policies on `band_members` updated; authorization logic unchanged                             |
| Auth / Session                   | unaffected — authentication flows unchanged                                                                  |
| Routing                          | unaffected — no routing changes                                                                              |
| Notifications                    | unaffected — no policies on notification tables in 11-table scope (notifications not in affected table list) |
| Platform (iOS/Android/Web/macOS) | affected (all) — backend change applies uniformly; performance may improve on large-dataset queries          |

## Regression Risk

**Level:** `MEDIUM`

**Rationale:**

**+Risk (HIGH):**

- **11 tables affected** — large surface area across core features (bands, setlists, gigs, rehearsals, songs, members)
- **No staging environment** — changes apply directly to production database (200+ users, 91 bands, 1733 songs)
- **Manual policy authoring** — transcribing predicates from pg_policies and constructing OR logic for 7 non-equivalent pairs is error-prone
- **Zero automated RLS test coverage** — no test suite validates authorization behavior; verification is manual only
- **Seven non-equivalent policy pairs** — Root Cause Notes 1-7 each require careful predicate merging, not simple drop-and-replace
- **Two "Known Issue" cases** — Notes 6 (setlists) and 7 (songs) must preserve current over-permissiveness without accidentally tightening access

**-Risk (LOW):**

- **Advisor-driven** — fixing known Performance Advisor findings, not speculative optimization
- **Rollback path clear** — PRE_MIGRATION_RLS_STATE.md captures exact pre-migration definitions
- **No client code changes** — Flutter app, edge functions, RPC bodies untouched
- **Precedent established** — `rls-policy-performance-hardening` and `rls-migration-comment-escaping` features provide migration patterns and verification approaches
- **Authorization explicitly preserved** — consolidated policies OR all existing predicates; no intentional behavior changes

**-Risk (MEDIUM):**

- Consolidation is mechanical where policies are equivalent (drop legacy, keep authenticated)
- Performance improvement is the goal, not authorization redesign
- No new authorization concepts introduced

**Mitigations:**

- **Transaction-wrapped verification** — Tier 2 executes migration inside BEGIN/ROLLBACK against production to verify effective access before actual deployment
- **Before/after effective access comparison** — Explicit probes for all 7 flagged non-equivalent pairs inside verification transaction
- **Advisor re-check** — Post-deployment `get_advisors` must confirm `multiple_permissive_policies` count drops from 102 to 0 (or near-0 with remaining warnings documented)
- **PRE_MIGRATION_RLS_STATE.md capture** — Complete rollback reference is the sole restoration path (no branch or local testing fallback)

**Why MEDIUM, not HIGH:** Authorization logic is explicitly preserved (OR of all existing predicates), not redesigned. No new authorization patterns introduced.

**Why MEDIUM, not LOW:** 11 tables is a large scope; 7 non-equivalent pairs require manual OR-logic construction; no automated tests to catch authorization regressions.

## Engineer Task Breakdown

### Task 1: Capture Pre-Migration RLS State

Query `pg_policies` for all 11 affected tables and generate complete `CREATE POLICY` statements for every existing policy (78 policies total). Write output to `PRE_MIGRATION_RLS_STATE.md`.

**CRITICAL:** PRE_MIGRATION_RLS_STATE.md is the **sole rollback path** for this feature. Supabase managed branches cannot be used (migrations 001-072 were never committed to version control per `docs/features/rls-migration-comment-escaping/QA_REPORT.md` Check #4, causing branch creation to fail replaying migration 073 against an empty database). Local `supabase start` is unavailable (Tony does not run Docker). Accuracy of this capture is mandatory — it is the only way to restore pre-migration policy state if rollback is required.

**Query pattern (example for bands table):**

```sql
SELECT 
  'CREATE POLICY "' || policyname || '" ON public.' || tablename || E'\n' ||
  'FOR ' || cmd || ' TO ' || array_to_string(roles, ', ') || E'\n' ||
  CASE 
    WHEN qual IS NOT NULL THEN 'USING (' || qual || E')\n'
    ELSE ''
  END ||
  CASE
    WHEN with_check IS NOT NULL THEN 'WITH CHECK (' || with_check || ');'
    ELSE ';'
  END as policy_definition
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'bands'
ORDER BY cmd, policyname;
```

Repeat for all 11 tables. Group by table in PRE_MIGRATION_RLS_STATE.md. Include header documenting source (live pg_policies, 2026-08-25) and purpose (sole rollback reference — no branch or local testing fallback available).

**Scope:** 11 tables, 78 policies total.

**Verification:** Policy count per table matches live query from Phase 5.

### Task 2: Write Migration File — Header

Create `supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql`.

Write header:

```sql
-- Feature: feature/rls-consolidate-permissive-policies
-- Issue: 102 multiple_permissive_policies Performance Advisor warnings
-- Description: Consolidate redundant/overlapping RLS PERMISSIVE policies
-- to achieve one policy per (table, action) combination. Preserves current
-- effective access by OR'ing all existing predicates for non-equivalent pairs.
-- Rollback reference: docs/features/rls-consolidate-permissive-policies/PRE_MIGRATION_RLS_STATE.md
```

**Verification:** Header is complete and includes rollback pointer.

### Task 3: Write Migration File — Per-Table Consolidation Blocks

For each of the 11 tables, write a block containing:

1. DROP POLICY IF EXISTS for all existing policies on that table (from PRE_MIGRATION_RLS_STATE.md)
2. CREATE POLICY for each consolidated policy (one per action)

**Critical instructions:**

- Use single-line comments only (per `rls-migration-comment-escaping` lesson)
- For non-equivalent pairs (Root Cause Notes 1-7), OR all predicates together
- For Notes 6 and 7, add inline comment: `-- Known Issue — Not Fixed Here: [brief explanation]`
- All consolidated policies scoped TO authenticated (not TO public)
- Use `(select auth.uid())` not bare `auth.uid()` per `rls-policy-performance-hardening` convention

**Table processing order:**

1. bands (9 policies → 4 consolidated)
2. setlists (11 policies → 4 consolidated)
3. setlist_songs (9 policies → 4 consolidated)
4. rehearsals (9 policies → 4 consolidated)
5. songs (6 policies → 4 consolidated)
6. profiles (8 policies → 4 consolidated)
7. users (8 policies → 4 consolidated)
8. gig_responses (8 policies → 4 consolidated)
9. band_members (4 policies → 3 or 4 consolidated, depending on Note 1 analysis)
10. contributor_permissions (2 policies → decision per Note 3)
11. user_band_roles (4 policies → 3 consolidated, merge two SELECT policies)

**Scope:** 11 table blocks, ~39 CREATE POLICY statements, 78 DROP POLICY statements.

**Verification:**

- Each table has exactly one PERMISSIVE policy per action (SELECT/INSERT/UPDATE/DELETE where currently covered)
- No `CREATE POLICY ... TO public` statements remain
- All predicates use `(select auth.uid())` wrapper
- Notes 6 and 7 include "Known Issue" comments

### Task 4: Validate Migration File Syntax

Before committing, validate:

- Every line is valid SQL or a properly `--`-prefixed comment (no continuation lines without `--`)
- No multi-line comment blocks (per `rls-migration-comment-escaping` lesson)
- DROP count: `grep -c "^DROP POLICY" <file>` returns 78
- CREATE count: `grep -c "^CREATE POLICY" <file>` returns 39 (or final consolidated count)
- No bare `auth.uid()` calls: `grep 'auth\.uid()' <file> | grep -v '(select auth.uid())'` returns 0

**Verification:** All syntax checks pass.

### Task 5: Update ENGINEER_REPORT.md

Write `ENGINEER_REPORT.md` documenting:

- Tasks 1-4 completed
- `flutter analyze` not applicable (database-only change)
- Migration file path and line count
- PRE_MIGRATION_RLS_STATE.md path and policy count captured
- Ready for QA: Yes (pending transaction-wrapped verification per Tier 2 verification plan)

## Verification Plan

### Tier 1 — Pre-Deployment (Local Query Validation Only)

**Tier 1 tests do NOT apply the migration.** They validate supporting queries and data integrity only.

**PRE-DEPLOY TEST 1: Verify affected table list and current policy counts**

```sql
-- Confirm 11 tables are in scope and current policy counts match plan
SELECT
  tablename,
  COUNT(*) as current_policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'bands', 'band_members', 'setlists', 'songs', 'setlist_songs',
    'users', 'profiles', 'contributor_permissions', 'gig_responses',
    'rehearsals', 'user_band_roles'
  )
GROUP BY tablename
ORDER BY tablename;

-- Expected: 11 rows, with policy counts matching Phase 5 findings:
-- bands (9), setlists (11), setlist_songs (9), rehearsals (9), songs (6),
-- profiles (8), users (8), gig_responses (8), band_members (4),
-- contributor_permissions (2), user_band_roles (4)
```

**PRE-DEPLOY TEST 2: Verify helper functions exist and are callable by authenticated**

```sql
-- Confirm SECURITY DEFINER helpers exist
SELECT
  proname,
  prosecdef,
  pg_catalog.pg_get_function_identity_arguments(oid) as args
FROM pg_proc
WHERE proname IN ('is_band_member', 'is_band_admin', 'is_band_member_with_role')
  AND pronamespace = 'public'::regnamespace
ORDER BY proname, args;

-- Expected: 3 rows (is_band_member may have multiple signatures)
-- All should have prosecdef = true (SECURITY DEFINER)
```

**PRE-DEPLOY TEST 3: Baseline effective access for known test cases**

```sql
-- Capture current effective access outcomes for comparison post-migration
-- Test case: Can user A (admin of band B) delete band B?
-- Test case: Can user C (member of band D) delete setlist in band D?
-- Test case: Can user E (any authenticated user) SELECT from songs?

-- This test requires a known test user UUID and band ID; placeholder only:
-- SELECT EXISTS (
--   SELECT 1 FROM bands
--   WHERE id = '<test_band_id>'
--     AND <consolidated_USING_clause_from_migration>
-- ) AS can_delete_as_admin;

-- NOTE: Actual test execution deferred to Tier 2 (requires known test data)
```

### Tier 2 — Transaction-Wrapped Verification Against Production

**Why this approach:** Supabase managed branches are structurally unavailable (migrations 001-072 never committed to version control per `docs/features/rls-migration-comment-escaping/QA_REPORT.md` Check #4, causing branch creation to fail replaying migration 073 against an empty database). Local `supabase start` is unavailable (Tony does not run Docker). Instead, execute the full migration inside a transaction against production, verify effective access for all 7 flagged non-equivalent pairs, then ROLLBACK — never committing the verification transaction.

**CRITICAL:** This transaction verifies only. The actual deployment is a separate, subsequent `supabase db push --linked` (see Rollout section step 8).

**POST-DEPLOY TEST 1: Execute migration in transaction and verify effective access for all 7 flagged pairs**

```sql
BEGIN;

-- Apply the full consolidation migration (paste entire contents of
-- 20260825120000_consolidate_permissive_rls_policies.sql here)
-- All DROP POLICY and CREATE POLICY statements for 11 tables


-- Verify policy consolidation completed
SELECT
  tablename,
  COUNT(*) as policy_count,
  array_agg(policyname ORDER BY policyname) as policy_names
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'bands', 'band_members', 'setlists', 'songs', 'setlist_songs',
    'users', 'profiles', 'contributor_permissions', 'gig_responses',
    'rehearsals', 'user_band_roles'
  )
GROUP BY tablename
ORDER BY tablename;
-- Expected: 11 rows, each with policy_count <= 4 (one per action)


-- Verify all consolidated policies scoped TO authenticated
SELECT
  tablename,
  policyname,
  roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'bands', 'band_members', 'setlists', 'songs', 'setlist_songs',
    'users', 'profiles', 'contributor_permissions', 'gig_responses',
    'rehearsals', 'user_band_roles'
  )
  AND 'public' = ANY(roles)
ORDER BY tablename, policyname;
-- Expected: 0 rows


-- ========================================================================
-- Effective Access Verification — All 7 Flagged Non-Equivalent Pairs
-- ========================================================================

-- Set up JWT claims for test user (replace with real production user UUID)
SET LOCAL role = authenticated;
SET LOCAL request.jwt.claims = '{"sub": "<real-production-user-uuid>", "role": "authenticated"}';


-- NOTE 1: band_members SELECT
-- Question: Does is_band_member(band_id) already cover user's own row,
-- or must we OR with user_id = auth.uid()?
-- Test: As user X, confirm can SELECT own band_members row
SELECT EXISTS (
  SELECT 1 FROM band_members
  WHERE user_id = '<test-user-uuid>'
    AND band_id = '<test-band-id>'
) AS note1_can_select_own_membership;
-- Expected: true (user can view own membership)


-- NOTE 2: bands DELETE
-- Consolidated policy must allow admin OR creator
-- Test case A: Non-admin creator can delete own band
SELECT EXISTS (
  SELECT 1 FROM bands
  WHERE id = '<band-created-by-test-user>'
    AND (is_band_admin(id) OR created_by = (select auth.uid()))
) AS note2_creator_can_delete;
-- Expected: true (creator who is not admin can delete)

-- Test case B: Admin can delete band they didn't create
-- (Switch to different test user UUID who is admin of another band)
RESET role;
SET LOCAL role = authenticated;
SET LOCAL request.jwt.claims = '{"sub": "<admin-user-uuid>", "role": "authenticated"}';
SELECT EXISTS (
  SELECT 1 FROM bands
  WHERE id = '<band-where-admin-user-is-admin>'
    AND (is_band_admin(id) OR created_by = (select auth.uid()))
) AS note2_admin_can_delete;
-- Expected: true (admin can delete)


-- NOTE 3: contributor_permissions
-- Decision required in migration: split ALL-command policy or leave redundancy?
-- Test: Verify admin can SELECT contributor_permissions
RESET role;
SET LOCAL role = authenticated;
SET LOCAL request.jwt.claims = '{"sub": "<admin-user-uuid>", "role": "authenticated"}';
SELECT EXISTS (
  SELECT 1 FROM contributor_permissions cp
  JOIN band_members bm ON bm.band_id = cp.band_id
  WHERE bm.user_id = (select auth.uid())
    AND bm.role = 'admin'
    AND bm.status = 'active'
) AS note3_admin_can_select;
-- Expected: true


-- NOTE 4: rehearsals DELETE/UPDATE
-- Consolidated policy must allow member-role users (not just admin)
-- Test: Member-role user can DELETE rehearsal
RESET role;
SET LOCAL role = authenticated;
SET LOCAL request.jwt.claims = '{"sub": "<member-role-user-uuid>", "role": "authenticated"}';
SELECT EXISTS (
  SELECT 1 FROM rehearsals r
  JOIN band_members bm ON bm.band_id = r.band_id
  WHERE bm.user_id = (select auth.uid())
    AND bm.role = 'member'
    AND bm.status = 'active'
    AND r.id = '<test-rehearsal-id>'
) AS note4_member_can_delete_rehearsal;
-- Expected: true (member role has DELETE/UPDATE per RBAC table)


-- NOTE 5: setlist_songs SELECT
-- Question: Should active status be required or not?
-- Test: Invited (non-active) member can SELECT setlist_songs
RESET role;
SET LOCAL role = authenticated;
SET LOCAL request.jwt.claims = '{"sub": "<invited-member-uuid>", "role": "authenticated"}';
SELECT EXISTS (
  SELECT 1 FROM setlist_songs ss
  JOIN setlists s ON s.id = ss.setlist_id
  WHERE is_band_member(s.band_id)
) AS note5_invited_member_can_select;
-- Expected: depends on is_band_member() implementation (check if status filter exists)


-- NOTE 6: setlists DELETE/INSERT/UPDATE (CRITICAL — Known Issue)
-- Consolidated policy must preserve contributor-role access (broader than docs)
-- Test: Contributor-role user can DELETE setlist
RESET role;
SET LOCAL role = authenticated;
SET LOCAL request.jwt.claims = '{"sub": "<contributor-user-uuid>", "role": "authenticated"}';
SELECT EXISTS (
  SELECT 1 FROM setlists s
  JOIN band_members bm ON bm.band_id = s.band_id
  WHERE bm.user_id = (select auth.uid())
    AND bm.role = 'contributor'
    AND bm.status = 'active'
    AND s.id = '<test-setlist-id>'
) AS note6_contributor_can_delete_setlist;
-- Expected: true (preserves current over-permissive behavior per Known Issue flag)


-- NOTE 7: songs SELECT/INSERT (CRITICAL — Known Issue)
-- Consolidated policy USING (true) — any authenticated user, no band check
-- Test: User with no band memberships can SELECT songs
RESET role;
SET LOCAL role = authenticated;
SET LOCAL request.jwt.claims = '{"sub": "<user-with-no-bands-uuid>", "role": "authenticated"}';
SELECT EXISTS (
  SELECT 1 FROM songs LIMIT 1
) AS note7_any_authenticated_can_select_songs;
-- Expected: true (unrestricted access preserved per Known Issue flag)


RESET role;

-- ========================================================================
-- End of Effective Access Verification
-- ========================================================================


ROLLBACK;  -- MANDATORY — This is verification only, never commit here
```

**Expected outcomes:**

- Policy count per table: ≤4 (one per action)
- Zero policies scoped TO public
- All 7 flagged pair tests return expected results (true for allowed, false for denied)
- ROLLBACK completes successfully (transaction never committed)

**POST-DEPLOY TEST 2: Verify Performance Advisor warnings (outside transaction)**

After ROLLBACK, the database is in pre-migration state. This test confirms baseline warning count before actual deployment.

```sql
-- Run via MCP tool, not raw SQL
-- mcp_supabase2_get_advisors(project_id='nekwjxvgbveheooyorjo', type='performance')
-- Expected: 102 multiple_permissive_policies warnings (unchanged, migration was rolled back)
```

### Verification Pass Criteria

**Tier 1 pass criteria:**

- All 3 PRE-DEPLOY tests return expected results
- PRE_MIGRATION_RLS_STATE.md exists and contains all 78 current policies
- Migration file syntax passes validation checks (no multi-line comment errors)

**Tier 2 pass criteria:**

- Transaction-wrapped migration completes without errors
- Policy count per table matches expected consolidated count (≤4 per table) inside transaction
- Zero policies scoped TO public remain inside transaction
- All 7 flagged pair effective access tests return expected results inside transaction
- ROLLBACK completes successfully
- POST-DEPLOY TEST 2 confirms baseline Advisor warning count (102) is unchanged post-rollback

**Rollback trigger:**

- If any of the 7 effective access tests inside the transaction reveals authorization regression (user who should have access is denied, or user who should be denied gains access in a direction not documented in Notes 6/7), do not proceed to actual deployment. Revise migration logic and re-run Tier 2.

## QA Regression Areas

QA must specifically test:

1. **Policy consolidation verification:**
   - Confirm policy count per table matches Architect plan's expected consolidated count
   - Confirm all policies scoped TO authenticated (none TO public)
   - Confirm Performance Advisor `multiple_permissive_policies` warning count dropped from 102 to 0 (or near-0)

2. **Authorization preservation for equivalent pairs:**
   - gig_responses: Create/read/update/delete as authenticated band member
   - profiles: Update own profile, view bandmate profiles
   - users: Update own user record, view bandmate user records
   - Confirm no regressions in typical CRUD flows

3. **Authorization preservation for non-equivalent pairs (Notes 1-7):**
   - **bands DELETE (Note 2):** Confirm both admin AND non-admin creator can delete their band
   - **rehearsals DELETE/UPDATE (Note 4):** Confirm member-role user (not just admin) can delete/update rehearsals per RBAC table
   - **setlists DELETE/INSERT/UPDATE (Note 6):** Confirm current behavior preserved (including contributor-role access if present in test data)
   - **songs SELECT/INSERT (Note 7):** Confirm any authenticated user can SELECT/INSERT songs (no band-membership gate)

4. **Performance Advisor recheck:**
   - Run `get_advisors(type=performance)` post-deployment
   - Confirm `multiple_permissive_policies` warnings dropped from 102 to expected final count
   - Document any remaining warnings with justification

5. **Rollback verification:**
   - Confirm PRE_MIGRATION_RLS_STATE.md contains all 78 pre-migration policy definitions
   - Spot-check 3 policies from PRE_MIGRATION_RLS_STATE.md against live pg_policies output to verify accuracy

## Rollout / Migration Strategy

1. **Create feature branch** (Phase 13): `feature/rls-consolidate-permissive-policies` ✅ Complete
2. **Commit ARCHITECT_PLAN.md** to establish baseline (follows sibling RLS feature convention) ✅ Complete
3. **Engineer implements Tasks 1-5**, commits PRE_MIGRATION_RLS_STATE.md and migration file
4. **QA executes Tier 1 verification** against live database (no migration applied)
5. **If Tier 1 passes:** QA executes Tier 2 verification (transaction-wrapped execution against production, rolled back)
6. **If Tier 2 passes:** QA reports APPROVED
7. **Manager authorizes commit** per COMMIT_GATE.md protocol
8. **Actual deployment** (DISTINCT from Tier 2 verification transaction): `supabase db push --linked`
   - This is the first and only time the migration is committed to the database
   - Tier 2 verified behavior inside a rolled-back transaction; this applies it permanently
9. **Post-deploy recheck:** Run `get_advisors(type=performance)` against production to confirm warning count drop from 102 to 0 (or near-0)

**No edge function deploy required** — database-only change.

**Rollback path if post-deploy issues discovered:** Use PRE_MIGRATION_RLS_STATE.md to manually restore all 78 pre-migration policies via `DROP POLICY` + `CREATE POLICY` statements. No managed branch or local testing environment available as fallback.

## Out of Scope

1. **`is_band_admin(uuid)` STABLE marking and auth.uid() wrapping** — Separate pre-existing issue; flagged for record but not fixed here
2. **Fixing setlists contributor over-permissiveness (Note 6)** — Document as known issue; preserve current behavior; file separately if Tony wants it fixed
3. **Fixing songs unrestricted access (Note 7)** — Document as known issue; preserve current behavior; likely related to NULL band_id catalog design
4. **`unused_index` (8) and `no_primary_key` (3) Advisor warnings** — Separate Advisor categories; not addressed in this feature
5. **Flutter/Dart application code changes** — Database-only change
6. **Merging or interacting with `bug/rls-migration-comment-escaping` branch** — Separate sibling feature; unrelated to this work

---

*Effective access preserved. Performance optimized. 102 warnings → 0.*
